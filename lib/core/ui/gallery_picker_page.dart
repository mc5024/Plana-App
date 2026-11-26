import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../features/generate/widgets/common.dart' show hintSnack;
import '../../l10n/l10n.dart';
import '../store/app_stores.dart';
import '../theme/app_theme.dart';
import '../util/image_pick.dart' show PickedImage, readAssetImage;
import '../util/log.dart';
import 'selection_bar.dart';

/// 上次选过的相册 id,存 `settings.json`。
///
/// 全应用只有这一个选择器(导入图片 / 图生图 / Vibe / 角色参考…… 都走它),
/// 所以记在这里 = 所有入口共享:在哪个相册挑过,下次从哪个相册开始。
///
/// 不进 [PrefsStore.migrateKeys] —— 那份名单是给「原本存在 secure storage、
/// 需要搬家」的老设置项用的,新键从来没在那儿待过,登记只会白读一次。
const _kAlbumKey = 'picker_album';

/// 选择结果:已读出字节的图片,或用户改走系统文件浏览器兜底。
class GalleryPickOutcome {
  const GalleryPickOutcome.images(this.images) : useFileBrowser = false;

  const GalleryPickOutcome.fileBrowser()
    : images = const [],
      useFileBrowser = true;

  final List<PickedImage> images;
  final bool useFileBrowser;
}

/// 缩略图并发限流与轻量 LRU 缓存。
///
/// photo_manager 原生侧共用固定大小的无界 FIFO 线程池,这里把同时在途的缩略图
/// 请求压在 [maxConcurrent] 以内、按 LIFO 优先加载当前可见格,并允许离屏格在入
/// 池前取消,避免分页与确认读图被积压的缩略图堵住。
class PickerThumbQueue {
  PickerThumbQueue({this.maxConcurrent = 4, this.maxCache = 180});

  final int maxConcurrent;
  final int maxCache;

  final _cache = <String, Uint8List>{};
  final _pending = <_ThumbJob>[];
  int _inFlight = 0;
  bool _paused = false;
  bool _disposed = false;

  /// 命中时刷新 LRU 顺位并同步返回字节。
  Uint8List? peek(String key) {
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit;
    return hit;
  }

  /// 入队一个缩略图拉取任务,返回取消句柄。
  VoidCallback enqueue({
    required String key,
    required Future<Uint8List?> Function() fetch,
    required void Function(Uint8List? bytes) onDone,
  }) {
    if (_disposed) return () {};
    final job = _ThumbJob(key: key, fetch: fetch, onDone: onDone);
    _pending.add(job);
    _pump();
    return () {
      job.cancelled = true;
      _pending.remove(job);
    };
  }

  /// 暂停继续派发排队中的缩略图(确认读原图期间让出原生线程池)。
  void pause() => _paused = true;

  /// 恢复派发排队中的缩略图。
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _pump();
  }

  void dispose() {
    _disposed = true;
    for (final j in _pending) {
      j.cancelled = true;
    }
    _pending.clear();
    _cache.clear();
  }

  void _putCache(String key, Uint8List bytes) {
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > maxCache) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _pump() {
    while (!_disposed &&
        !_paused &&
        _inFlight < maxConcurrent &&
        _pending.isNotEmpty) {
      final job = _pending.removeLast();
      if (job.cancelled) continue;
      final hit = peek(job.key);
      if (hit != null) {
        scheduleMicrotask(() {
          if (!_disposed && !job.cancelled) job.onDone(hit);
        });
        continue;
      }
      _inFlight++;
      _run(job);
    }
  }

  Future<void> _run(_ThumbJob job) async {
    Uint8List? bytes;
    try {
      bytes = await job.fetch();
      if (bytes != null && bytes.isEmpty) bytes = null;
      if (!_disposed && bytes != null) _putCache(job.key, bytes);
    } catch (_) {
      bytes = null;
    } finally {
      _inFlight--;
      if (!_disposed && !job.cancelled) {
        job.onDone(bytes);
      }
      _pump();
    }
  }
}

class _ThumbJob {
  _ThumbJob({required this.key, required this.fetch, required this.onDone});

  final String key;
  final Future<Uint8List?> Function() fetch;
  final void Function(Uint8List? bytes) onDone;
  bool cancelled = false;
}

/// 应用内图库选择器:photo_manager 直读系统媒体库,全部相册/全部图片可达。
/// 系统照片选择器只放行固定几个分类且不看 app 权限,只能自建绕开。
class GalleryPickerPage extends ConsumerStatefulWidget {
  const GalleryPickerPage({super.key, required this.multiple});

  final bool multiple;

  @override
  ConsumerState<GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends ConsumerState<GalleryPickerPage>
    with WidgetsBindingObserver {
  /// 每批取多少张。**别往大了调。**
  ///
  /// photo_manager 每把一行游标转成资产都要做一次 `File(path).exists()` 文件
  /// 系统 stat(`toAssetEntity` 的 `checkIfExists` 在插件里写死是 true,Dart 侧
  /// 关不掉)。桥接文件系统上一次就是一趟跨运行时调用,按一屏余量分批补。
  static const _pageSize = 30;

  /// 连续空页的兜底上限,防止大量失效 MediaStore 记录导致无限续页。
  static const _maxEmptyPages = 3;

  /// 媒体库查询条件,本页所有查询共用一份。
  ///
  /// `ignoreSize: true` 跳过 MediaStore 无索引的宽高筛选;显式关闭日期条件,
  /// 避免 `FilterOptionGroup` 默认把 `max` 冻在静态构造时刻。
  static final _filter = FilterOptionGroup(
    imageOption: const FilterOption(
      sizeConstraint: SizeConstraint(ignoreSize: true),
    ),
    orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
    createTimeCond: DateTimeCond(
      min: DateTime.utc(1970),
      max: DateTime.utc(2100),
      ignore: true,
    ),
    updateTimeCond: DateTimeCond(
      min: DateTime.utc(1970),
      max: DateTime.utc(2100),
      ignore: true,
    ),
  );

  final _thumbs = PickerThumbQueue();

  PermissionState? _perm; // null = 请求中
  AssetPathEntity? _album;
  final _assets = <AssetEntity>[];
  final _assetIds = <String>{};
  int _page = 0;
  int _totalCount = 0;
  int _emptyPages = 0;
  bool _exhausted = false;
  bool _loadingMore = false;

  /// 列表加载代际号:切相册或重载时递增,过期的异步分页/刷新直接丢弃。
  int _loadEpoch = 0;
  int _reloadCount = 0;
  bool _wentBackground = false;

  /// 确认读图中(单选/多选共用)。
  bool _confirming = false;
  String? _confirmingId;

  /// 全部相册:首次点标题切相册时才拉,失败不缓存。
  Future<List<AssetPathEntity>>? _albumsFuture;

  /// 每个相册的封面 + 张数,按相册 id 缓存(见 [_brief])。
  final _briefs = <String, Future<_AlbumBrief>>{};

  final _sel = <AssetEntity>[];
  final _selIds = <String>{};

  /// 媒体库变更通知的合并窗口。
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PhotoManager.addChangeCallback(_onLibraryChanged);
    _init();
  }

  /// 开启系统媒体库变更通知。须在拿到读权限后再开,否则 ContentObserver
  /// 回调里反查 MediaStore 会失败。
  bool _notifyOn = false;

  void _ensureChangeNotify() {
    if (_notifyOn) return;
    _notifyOn = true;
    PhotoManager.startChangeNotify();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _thumbs.dispose();
    if (_notifyOn) PhotoManager.stopChangeNotify();
    PhotoManager.removeChangeCallback(_onLibraryChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLibraryChanged(MethodCall call) {
    final args = call.arguments;
    if (args is Map) {
      // Android MediaStore: 1 = IMAGE, 0 = 部分照片授权变更;忽略视频(2)/音频(3)
      final mediaType = args['mediaType'];
      if (mediaType is int && mediaType != 0 && mediaType != 1) return;
      final album = _album;
      final gid = args['galleryId']?.toString();
      final type = args['type']?.toString();
      if (album != null &&
          !album.isAll &&
          gid != null &&
          gid != album.id &&
          type != 'delete') {
        return;
      }
    }
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _reload(force: false),
    );
  }

  /// 静默检查并原地替换当前相册,不先清空列表卸载 GridView。
  /// [force] = false 时先比对张数与首张图,无变化则跳过查询。
  Future<void> _reload({required bool force}) async {
    if (!mounted || _perm?.hasAccess != true || _confirming) return;
    if (_reloadCount > 0 && !force) return;
    _reloadCount++;
    try {
      final checkEpoch = _loadEpoch;
      final cur = await _resolveAlbum(keepId: _album?.id);
      if (!mounted || checkEpoch != _loadEpoch) return;
      if (cur == null) {
        _albumsFuture = null;
        _briefs.clear();
        if (_assets.isNotEmpty || _album != null || !_exhausted) {
          _loadEpoch++;
          setState(() {
            _album = null;
            _assets.clear();
            _assetIds.clear();
            _page = 0;
            _totalCount = 0;
            _emptyPages = 0;
            _exhausted = true;
            _loadingMore = false;
          });
        }
        return;
      }
      final total = await cur.assetCountAsync;
      if (!mounted || checkEpoch != _loadEpoch) return;
      if (!force && cur.id == _album?.id && _assets.isNotEmpty) {
        final head = total == 0
            ? const <AssetEntity>[]
            : await cur.getAssetListPaged(page: 0, size: 1);
        if (!mounted || checkEpoch != _loadEpoch) return;
        final first = head.firstOrNull;
        if (total == _totalCount &&
            first != null &&
            first.id == _assets.first.id &&
            first.modifiedDateSecond == _assets.first.modifiedDateSecond) {
          return;
        }
      }

      _albumsFuture = null;
      _briefs.clear();
      final reloadEpoch = ++_loadEpoch;
      final desired = force
          ? _pageSize * 2
          : (_page < 2 ? _pageSize * 2 : _page * _pageSize);
      final targetCount = desired.clamp(0, total);
      final fresh = targetCount == 0
          ? const <AssetEntity>[]
          : await cur.getAssetListRange(start: 0, end: targetCount);
      if (!mounted || reloadEpoch != _loadEpoch) return;
      final seen = <String>{};
      final deduped = <AssetEntity>[
        for (final a in fresh)
          if (seen.add(a.id)) a,
      ];
      setState(() {
        _album = cur;
        _totalCount = total;
        _emptyPages = 0;
        _assets
          ..clear()
          ..addAll(deduped);
        _assetIds
          ..clear()
          ..addAll(seen);
        _page = targetCount == 0
            ? 0
            : (targetCount + _pageSize - 1) ~/ _pageSize;
        _exhausted = targetCount >= total;
        _loadingMore = false;
      });
    } catch (e) {
      logd('[picker] 刷新列表失败: $e');
    } finally {
      _reloadCount--;
    }
  }

  /// 仅在真正切到后台后返回时检查媒体库变化;下拉通知栏等 `inactive -> resumed`
  /// 不触发刷新。未获权限时每次回来都重查权限。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wentBackground = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (_perm?.hasAccess != true) {
      _wentBackground = false;
      _init();
    } else if (_wentBackground) {
      _wentBackground = false;
      _reload(force: false);
    }
  }

  Future<void> _init() async {
    final ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _perm = ps);
    if (ps.hasAccess) {
      _ensureChangeNotify();
      await _openInitialAlbum(
        keepId: ref.read(prefsStoreProvider).get(_kAlbumKey),
      );
    }
  }

  /// 解析当前要打开的单个相册,不枚举全部相册。
  /// 全量 `getAssetPathList` 在 Android 上会逐行分桶计数,相册列表推迟到
  /// [_switchAlbum] 按需拉取。
  Future<AssetPathEntity?> _resolveAlbum({String? keepId}) async {
    final all = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: _filter,
    );
    var cur = all.isEmpty ? null : all.first;
    if (keepId != null && keepId != cur?.id) {
      try {
        cur = await AssetPathEntity.fromId(
          keepId,
          type: RequestType.image,
          filterOption: _filter,
        );
      } catch (e) {
        logd('[picker] 上次的相册取不到($keepId),回落全部图片: $e');
      }
    }
    return cur;
  }

  Future<void> _openInitialAlbum({String? keepId}) async {
    AssetPathEntity? cur;
    try {
      cur = await _resolveAlbum(keepId: keepId);
    } catch (e) {
      logd('[picker] 相册初始化失败: $e');
    }
    if (!mounted) return;
    await _selectAlbum(cur);
  }

  /// 拉全部相册,只在用户点开切相册面板时执行。
  Future<List<AssetPathEntity>> _fetchAlbums() async {
    try {
      return await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: _filter,
      );
    } catch (e) {
      _albumsFuture = null;
      logd('[picker] 相册列表读取失败: $e');
      return const [];
    }
  }

  Future<void> _selectAlbum(AssetPathEntity? album) async {
    final epoch = ++_loadEpoch;
    setState(() {
      _album = album;
      _assets.clear();
      _assetIds.clear();
      _page = 0;
      _totalCount = 0;
      _emptyPages = 0;
      _exhausted = album == null;
      _loadingMore = false;
    });
    if (album == null) return;
    int total;
    try {
      total = await album.assetCountAsync;
    } catch (e) {
      logd('[picker] 读取相册张数失败: $e');
      if (mounted && epoch == _loadEpoch) {
        setState(() => _exhausted = true);
      }
      return;
    }
    if (!mounted || epoch != _loadEpoch) return;
    _totalCount = total;
    if (total == 0) {
      setState(() => _exhausted = true);
      return;
    }
    await _loadMore(epoch: epoch);
    await _loadMore(epoch: epoch);
  }

  Future<void> _loadMore({int? epoch}) async {
    final targetEpoch = epoch ?? _loadEpoch;
    final album = _album;
    if (album == null || _loadingMore || _exhausted || _confirming) return;
    _loadingMore = true;
    try {
      final page = _page;
      final batch = await album.getAssetListPaged(page: page, size: _pageSize);
      if (!mounted || targetEpoch != _loadEpoch) return;
      if (batch.isEmpty) {
        final freshTotal = await album.assetCountAsync;
        if (!mounted || targetEpoch != _loadEpoch) return;
        _emptyPages++;
        final nextPage = page + 1;
        setState(() {
          _totalCount = freshTotal;
          _page = nextPage;
          if (nextPage * _pageSize >= _totalCount ||
              _emptyPages >= _maxEmptyPages) {
            _exhausted = true;
          }
        });
        return;
      }
      _emptyPages = 0;
      final nextPage = page + 1;
      setState(() {
        for (final a in batch) {
          if (_assetIds.add(a.id)) _assets.add(a);
        }
        _page = nextPage;
        if (nextPage * _pageSize >= _totalCount) _exhausted = true;
      });
    } catch (e) {
      logd('[picker] 分页读取失败: $e');
    } finally {
      if (targetEpoch == _loadEpoch) _loadingMore = false;
    }
  }

  void _toggle(AssetEntity a) {
    if (_confirming) return;
    setState(() {
      if (_selIds.remove(a.id)) {
        _sel.removeWhere((e) => e.id == a.id);
      } else {
        _selIds.add(a.id);
        _sel.add(a);
      }
    });
  }

  void _clearSel() {
    if (_confirming) return;
    setState(() {
      _sel.clear();
      _selIds.clear();
    });
  }

  /// 在页内读出选中原图后再返回;全部读失败时留在原位提示,不丢弃选择状态。
  Future<void> _confirm(List<AssetEntity> targets, {String? singleId}) async {
    if (_confirming || targets.isEmpty) return;
    _thumbs.pause();
    setState(() {
      _confirming = true;
      _confirmingId = singleId;
    });
    final images = <PickedImage>[];
    var failed = 0;
    for (final a in targets) {
      if (!mounted) return;
      final img = await readAssetImage(a);
      if (img != null) {
        images.add(img);
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    if (images.isEmpty) {
      setState(() {
        _confirming = false;
        _confirmingId = null;
      });
      _thumbs.resume();
      hintSnack(
        context,
        context.l10n.readImageFailed,
        icon: Icons.error_outline,
      );
      return;
    }
    if (failed > 0) {
      hintSnack(
        context,
        context.l10n.unreadableSkipped(failed),
        icon: Icons.error_outline,
      );
    }
    Navigator.of(context).pop(GalleryPickOutcome.images(images));
  }

  String _albumLabel(AssetPathEntity a) => a.isAll
      ? context.l10n.allImages
      : (a.name.isEmpty ? context.l10n.gallery : a.name);

  /// 串行查询单个相册的张数与最新封面,按相册 id 缓存。
  Future<_AlbumBrief> _brief(AssetPathEntity a) => _briefs[a.id] ??= () async {
    final count = await a.assetCountAsync;
    final head = count == 0
        ? const <AssetEntity>[]
        : await a.getAssetListPaged(page: 0, size: 1);
    return _AlbumBrief(head.isEmpty ? null : head.first, count);
  }();

  Future<void> _switchAlbum() async {
    if (_confirming) return;
    final albums = _albumsFuture ??= _fetchAlbums();
    final picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Text(
                    context.l10n.albums,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<AssetPathEntity>>(
                future: albums,
                builder: (context, snap) {
                  final list = snap.data;
                  if (list == null) {
                    return const SizedBox(
                      height: 96,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (list.isEmpty) {
                    return ListTile(
                      dense: true,
                      enabled: false,
                      title: Text(
                        context.l10n.noAlbums,
                        style: context.texts.bodyMedium,
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return _AlbumTile(
                        label: _albumLabel(a),
                        selected: a.id == _album?.id,
                        brief: _brief(a),
                        thumbs: _thumbs,
                        onTap: () => Navigator.of(sheet).pop(a),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == _album?.id) return;
    await ref.read(prefsStoreProvider).write(key: _kAlbumKey, value: picked.id);
    if (!mounted) return;
    await _selectAlbum(picked);
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final perm = _perm;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _album != null && !_confirming ? _switchAlbum : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _album == null
                        ? context.l10n.selectImage
                        : _albumLabel(_album!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium,
                  ),
                ),
                if (_album != null) const Icon(Icons.arrow_drop_down, size: 22),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.pickFromFiles,
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _confirming
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(const GalleryPickOutcome.fileBrowser()),
          ),
        ],
      ),
      body: perm != null && !perm.hasAccess
          ? _NoAccessView(onRetry: _init)
          : Column(
              children: [
                if (perm == PermissionState.limited)
                  _LimitedBar(
                    onManage: () async {
                      if (_confirming) return;
                      await PhotoManager.presentLimited(
                        type: RequestType.image,
                      );
                      if (!mounted) return;
                      await _reload(force: true);
                    },
                  ),
                Expanded(
                  child: _assets.isEmpty
                      ? (_exhausted
                            ? Center(
                                child: Text(
                                  context.l10n.noImages,
                                  style: context.texts.bodyMedium!.copyWith(
                                    color: scheme.outline,
                                  ),
                                ),
                              )
                            : const _SkeletonGrid())
                      : RefreshIndicator(
                          onRefresh: () => _reload(force: true),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n.metrics.pixels >
                                  n.metrics.maxScrollExtent - 900) {
                                _loadMore();
                              }
                              return false;
                            },
                            child: GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(2),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 2,
                                    crossAxisSpacing: 2,
                                  ),
                              itemCount: _assets.length,
                              itemBuilder: (context, i) => _cell(_assets[i]),
                            ),
                          ),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: widget.multiple && perm?.hasAccess == true
          ? SelectionBar(
              visible: _sel.isNotEmpty,
              onClear: _sel.isEmpty || _confirming ? null : _clearSel,
              primary: FilledButton.icon(
                onPressed: _sel.isEmpty || _confirming
                    ? null
                    : () => _confirm(List.of(_sel)),
                style: selectionPrimaryStyle(),
                icon: _confirming
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(context.l10n.okCount(_sel.length)),
              ),
            )
          : null,
    );
  }

  Widget _cell(AssetEntity a) {
    final scheme = context.scheme;
    final selected = _selIds.contains(a.id);
    final loadingSingle =
        !widget.multiple && _confirming && _confirmingId == a.id;
    return GestureDetector(
      onTap: _confirming
          ? null
          : () => widget.multiple ? _toggle(a) : _confirm([a], singleId: a.id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerHigh),
          _AssetThumb(key: ValueKey(a.id), asset: a, size: 300, queue: _thumbs),
          if (loadingSingle)
            ColoredBox(
              color: Colors.black.withValues(alpha: .32),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (widget.multiple) ...[
            if (selected)
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .16),
                  border: Border.all(color: scheme.primary, width: 3),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: selected
                  ? Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 15,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: .18),
                        border: Border.all(color: Colors.white, width: 1.6),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 经 [PickerThumbQueue] 受控加载单张资产缩略图,离屏销毁时自动取消排队。
class _AssetThumb extends StatefulWidget {
  const _AssetThumb({
    super.key,
    required this.asset,
    required this.size,
    required this.queue,
    this.showBrokenIcon = true,
  });

  final AssetEntity asset;
  final int size;
  final PickerThumbQueue queue;
  final bool showBrokenIcon;

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  Uint8List? _bytes;
  bool _failed = false;
  VoidCallback? _cancel;

  static String _keyOf(_AssetThumb w) =>
      '${w.asset.id}:${w.asset.modifiedDateSecond ?? 0}:${w.size}';

  String get _key => _keyOf(widget);

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _AssetThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_keyOf(oldWidget) != _key || oldWidget.queue != widget.queue) {
      _cancel?.call();
      _bind();
    }
  }

  @override
  void dispose() {
    _cancel?.call();
    _cancel = null;
    super.dispose();
  }

  void _bind() {
    final key = _key;
    final hit = widget.queue.peek(key);
    if (hit != null) {
      _bytes = hit;
      _failed = false;
      _cancel = null;
      return;
    }
    _bytes = null;
    _failed = false;
    final asset = widget.asset;
    final size = widget.size;
    _cancel = widget.queue.enqueue(
      key: key,
      fetch: () => asset.thumbnailDataWithOption(
        ThumbnailOption(size: ThumbnailSize.square(size), quality: 80),
      ),
      onDone: (bytes) {
        if (!mounted || _key != key) return;
        setState(() {
          _bytes = bytes;
          _failed = bytes == null;
        });
      },
    );
  }

  Widget _broken(BuildContext context) {
    if (!widget.showBrokenIcon) return const SizedBox.shrink();
    final scheme = context.scheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.broken_image_outlined, color: scheme.outline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: widget.size,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => _broken(context),
      );
    }
    if (_failed) return _broken(context);
    return const SizedBox.shrink();
  }
}

/// 相册行的附加信息:封面(相册里最新的一张,没有图时为 null)与张数。
class _AlbumBrief {
  const _AlbumBrief(this.cover, this.count);

  final AssetEntity? cover;
  final int count;
}

/// 切相册面板的一行:封面缩略图 + 相册名 + 张数,当前相册打勾。
class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.label,
    required this.selected,
    required this.brief,
    required this.thumbs,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Future<_AlbumBrief> brief;
  final PickerThumbQueue thumbs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return ListTile(
      selected: selected,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: FutureBuilder<_AlbumBrief>(
            future: brief,
            builder: (context, snap) => Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: scheme.surfaceContainerHigh),
                if (snap.data?.cover case final cover?)
                  _AssetThumb(
                    key: ValueKey(cover.id),
                    asset: cover,
                    size: 150,
                    queue: thumbs,
                    showBrokenIcon: false,
                  ),
              ],
            ),
          ),
        ),
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: FutureBuilder<_AlbumBrief>(
        future: brief,
        builder: (context, snap) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
            ],
            Text(
              snap.hasData ? '${snap.data!.count}' : '',
              style: mono(context, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载骨架:与实际网格同版式的呼吸色块(权限请求中/相册首载/切相册时)。
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) => _Pulse(
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: 24,
      itemBuilder: (context, _) =>
          ColoredBox(color: context.scheme.surfaceContainerHigh),
    ),
  );
}

/// 呼吸式明暗包装(与统计页骨架同节奏)。
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: .45,
      end: 1,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// Android 14「部分照片」授权提示条。
class _LimitedBar extends StatelessWidget {
  const _LimitedBar({required this.onManage});

  final Future<void> Function() onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.limitedPhotoAccess,
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
          ),
          TextButton(onPressed: onManage, child: Text(context.l10n.adjust)),
        ],
      ),
    );
  }
}

/// 无权限视图:去系统设置授权后回来自动刷新,也可手动重查。
class _NoAccessView extends StatelessWidget {
  const _NoAccessView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            context.l10n.needPhotoPermission,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: PhotoManager.openSetting,
            child: Text(context.l10n.goToSettings),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.recheck)),
        ],
      ),
    );
  }
}

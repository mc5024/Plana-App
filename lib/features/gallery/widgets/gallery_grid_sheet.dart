import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart'
    show ExpandBody, hintSnack, sharedAxisRoute;
import '../../import/import_panel.dart';
import '../gallery_dates.dart';
import '../gallery_search.dart';
import '../gallery_state.dart';
import '../models.dart';
import '../save_pipeline.dart';
import '../save_settings.dart';
import '../share_pipeline.dart';
import 'album_name_sheet.dart';
import 'result_badge_chip.dart';
import 'result_thumb.dart';
import '../../../core/util/haptics.dart';

/// 「›」展开:全部作品网格弹层,按天分段显示;可按模型/时间筛选、按提示词
/// 标签搜索(数据源 gallery_search 检索索引,筛选条件全 AND 组合)。
/// 点选一张即回填画布并关闭;长按弹出该张的导入 / 保存 / 删除菜单。
/// 多选只从右上角「多选」进,段头可整段全选,底部批量保存相册 / 分享 /
/// 批量删除 —— 批量操作只作用于当前可见集合。
Future<void> showGalleryGrid(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _GalleryGridSheet(),
    );

/// 「全部图库」首次打开时提一次长按 —— 网格里点一下是选中回填画布,
/// 长按才是放大预览 + 导入/保存/删除那套,不说没人会去按。
const _kGridHintKey = 'hint_grid_longpress';

class _GalleryGridSheet extends ConsumerStatefulWidget {
  const _GalleryGridSheet();

  @override
  ConsumerState<_GalleryGridSheet> createState() => _GalleryGridSheetState();
}

class _GalleryGridSheetState extends ConsumerState<_GalleryGridSheet> {
  bool _selecting = false;
  final Set<String> _picked = {};
  bool _saving = false;
  bool _sharing = false;
  // 保存与分享共用这对计数(两件事不会同时跑,canAct 互斥)
  int _saveDone = 0;
  int _saveTotal = 0;

  // ---- 检索/筛选(弹层内临时态,关弹层即重置) ----
  final _searchCtrl = TextEditingController();
  // 焦点显式管理:搜索框在 ExpandBody 里是**常驻构建**的(只是高度收成 0),
  // 用 autofocus 会在弹层一打开就抢焦点弹键盘 —— 用户还没想搜。
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  bool _searchOpen = false;
  String _query = '';
  String? _modelFilter; // null=全部;''=未知(无参数快照的老图)
  // 0=全部 / 1=今天 / 7=近7天 / 30=近30天。记住上次的 —— 常年只看近 7 天的人
  // 不该每次开网格都先筛一遍。
  late int _daysFilter = ref.read(uiPrefsProvider).galleryDaysFilter;

  // ---- 多选操作栏的几何 ----
  static const _actH = 46.0;
  static const _actSubH = 38.0;
  static const _actGap = 10.0;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsStoreProvider);
    if (prefs.get(_kGridHintKey) != null) return;
    prefs.write(key: _kGridHintKey, value: '1');
    // 弹层刚推进来那一帧 overlay 还没稳,推到帧后再弹
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        hintSnack(
          context,
          '长按一张图可放大预览,并导入 / 保存 / 删除',
          icon: Icons.touch_app_outlined,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
      }
    });
    // 只有明确点开搜索才弹键盘
    _searchOpen ? _searchFocus.requestFocus() : _searchFocus.unfocus();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v);
    });
  }

  // ---- 筛选谓词(模型 × 时间 × 搜索,全 AND) ----

  bool _passTime(ResultImage r) {
    if (_daysFilter == 0) return true;
    final now = DateTime.now();
    // 「今天」按日历日;7/30 天按滚动窗口
    final cut = _daysFilter == 1
        ? DateTime(now.year, now.month, now.day)
        : now.subtract(Duration(days: _daysFilter));
    return r.createdAt >= cut.millisecondsSinceEpoch;
  }

  bool _passModel(ResultImage r, Map<String, GallerySearchMeta> byId) {
    final want = _modelFilter;
    if (want == null) return true;
    return (byId[r.id]?.model ?? '') == want;
  }

  bool _passQuery(
    ResultImage r,
    Map<String, GallerySearchMeta> byId,
    List<String> terms,
  ) {
    if (terms.isEmpty) return true;
    final meta = byId[r.id];
    return meta != null && searchMatch(meta.text, terms);
  }

  /// 单选弹层(模型/时间共用):选项 = (文案, 值, 计数);值用单元素 record
  /// 包一层再 pop,可空的 T(全部=null)才与「取消」区分得开。
  Future<void> _pickFilter<T>({
    required String title,
    required List<(String, T, int?)> options,
    required T current,
    required ValueChanged<T> onPick,
  }) async {
    final scheme = context.scheme;
    // 弹层关闭后焦点会回落到搜索框(它一直在树里),不先收就会顺带弹出键盘
    _searchFocus.unfocus();
    final picked = await showModalBottomSheet<(T,)>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final (label, value, count) in options)
                ListTile(
                  dense: true,
                  onTap: () => Navigator.pop(ctx, (value,)),
                  title: Text(label, style: context.texts.bodyMedium),
                  trailing: value == current
                      ? Icon(Icons.check, size: 18, color: scheme.primary)
                      : (count == null
                            ? null
                            : Text(
                                '$count',
                                style: mono(
                                  context,
                                  size: 12,
                                  color: scheme.outline,
                                ),
                              )),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked.$1);
  }

  void _pickModelFilter(
    List<ResultImage> results,
    Map<String, GallerySearchMeta> byId,
  ) {
    // 模型清单按整库统计(不按筛选后,免得选中一个后其余选项全消失)
    final counts = <String, int>{};
    for (final r in results) {
      counts.update(byId[r.id]?.model ?? '', (v) => v + 1, ifAbsent: () => 1);
    }
    final models = [
      for (final k in counts.keys)
        if (k.isNotEmpty) k,
    ]..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    _pickFilter<String?>(
      title: '按模型筛选',
      current: _modelFilter,
      options: [
        ('全部', null, null),
        for (final m in models) (m, m, counts[m]),
        if ((counts[''] ?? 0) > 0) ('未知', '', counts['']),
      ],
      onPick: (v) => setState(() => _modelFilter = v),
    );
  }

  void _pickTimeFilter() {
    _pickFilter<int>(
      title: '按时间筛选',
      current: _daysFilter,
      options: const [
        ('全部', 0, null),
        ('今天', 1, null),
        ('近 7 天', 7, null),
        ('近 30 天', 30, null),
      ],
      onPick: (v) {
        ref
            .read(uiPrefsProvider.notifier)
            .patch((p) => p.copyWith(galleryDaysFilter: v));
        setState(() => _daysFilter = v);
      },
    );
  }

  Widget _chip(
    ColorScheme scheme, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final fg = active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: active ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 7, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.texts.bodySmall!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  /// 天分段段头:日期 + 张数;多选态尾部整段全选/取消。
  Widget _dayHeader(
    ColorScheme scheme,
    int dayKey,
    List<ResultImage> items,
    DateTime now,
  ) {
    final ids = [for (final r in items) r.id];
    final allOn = ids.every(_picked.contains);
    return Padding(
      // 跟着网格一起往里收 4:段头文字要和其下第一张图的左边缘对齐
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      child: Row(
        children: [
          Text(
            galleryDayLabel(dayKey, now),
            style: context.texts.titleSmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '${items.length} 张',
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (_selecting)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _saving
                  ? null
                  : () => setState(
                      () =>
                          allOn ? _picked.removeAll(ids) : _picked.addAll(ids),
                    ),
              child: Text(allOn ? '取消' : '全选'),
            ),
        ],
      ),
    );
  }

  void _enterSelect([String? pick]) {
    setState(() {
      _selecting = true;
      if (pick != null) _picked.add(pick);
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _picked.clear();
    });
  }

  void _toggle(String id) {
    setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
  }

  // ---- 滑动选择 ----
  //
  // 只认**横向**起手。竖向留给滚动 —— 多选态下照样要能翻到别的日期去,
  // 抢了竖向就等于把列表钉死。横向一旦被判定为拖选,后续 update 无论往哪个
  // 方向走都还归这个手势,所以斜着扫、扫完往下带都能连着选。
  //
  // 加/减看**起手那一格**的当前状态取反(对齐系统相册):从没选中的格子起手是
  // 整片选上,从已选中的起手是整片取消。
  bool? _dragAdding;
  final _dragSeen = <String>{};

  /// 屏幕坐标 → 该点下面那张缩略图的 id。靠命中路径里的 [MetaData]
  /// (见网格 itemBuilder)反查,不自己按几何算 —— 网格是按日期分成多个
  /// sliver 的,中间还夹着日期头,几何换算既绕又容易在改版式后悄悄失准。
  String? _idAt(Offset globalPos) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      globalPos,
      View.of(context).viewId,
    );
    for (final e in hit.path) {
      final t = e.target;
      if (t is RenderMetaData) {
        final m = t.metaData;
        if (m is String) return m;
      }
    }
    return null;
  }

  void _dragSelectStart(DragStartDetails d) {
    final id = _idAt(d.globalPosition);
    if (id == null) return;
    final adding = !_picked.contains(id);
    _dragAdding = adding;
    _dragSeen
      ..clear()
      ..add(id);
    setState(() => adding ? _picked.add(id) : _picked.remove(id));
  }

  void _dragSelectUpdate(DragUpdateDetails d) {
    final adding = _dragAdding;
    if (adding == null) return;
    final id = _idAt(d.globalPosition);
    // _dragSeen 去重:手指在一格里抖动会连发好几次 update,不去重就反复开关。
    if (id == null || !_dragSeen.add(id)) return;
    setState(() => adding ? _picked.add(id) : _picked.remove(id));
  }

  void _dragSelectEnd() {
    _dragAdding = null;
    _dragSeen.clear();
  }

  /// 给网格套上拖选手势。非多选态传 null 处理器 —— 手势识别器不参与竞技场,
  /// 横滑照常落到下层(将来要加横滑手势也不会被这层截胡)。
  Widget _dragSelectLayer({required Widget child}) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: _selecting ? _dragSelectStart : null,
    onHorizontalDragUpdate: _selecting ? _dragSelectUpdate : null,
    onHorizontalDragEnd: _selecting ? (_) => _dragSelectEnd() : null,
    onHorizontalDragCancel: _selecting ? _dragSelectEnd : null,
    child: child,
  );

  void _toggleAll(List<ResultImage> results) {
    setState(() {
      if (_picked.length == results.length) {
        _picked.clear();
      } else {
        _picked
          ..clear()
          ..addAll([for (final r in results) r.id]);
      }
    });
  }

  /// 批量保存:按默认保存设置逐张处理后存相册;逐张计数,
  /// 中途关闭弹层即中止(已存的保留)。
  /// [album] 非空 = 存进该自定义相册(gal 会按需创建 `Pictures/<album>/`)。
  /// [only] 非空 = 只存这些(长按菜单的单张保存借道同一条管线,
  /// 权限申请、保存设置、失败计数一条都不用重写)。
  Future<void> _downloadPicked({String? album, Set<String>? only}) async {
    final want = only ?? _picked;
    final items = [
      for (final r in ref.read(galleryProvider).results)
        if (want.contains(r.id)) r,
    ];
    if (items.isEmpty) return;
    // 写自建相册**以外**的相册要额外权限位,按目标申请
    final toAlbum = album != null;
    final ok =
        await Gal.hasAccess(toAlbum: toAlbum) ||
        await Gal.requestAccess(toAlbum: toAlbum);
    if (!mounted) return;
    if (!ok) {
      hintSnack(context, '未获相册权限', icon: Icons.error_outline);
      return;
    }
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    final store = ref.read(appStoresProvider).gallery;
    setState(() {
      _saving = true;
      _saveDone = 0;
      _saveTotal = items.length;
    });
    var saved = 0, failed = 0;
    for (final r in items) {
      if (!mounted) return; // 弹层已关:中止剩余
      try {
        final bytes = r.bytes ?? await store.readImage(r.id);
        if (bytes == null) {
          failed++;
        } else {
          final out = await processForSave(bytes, settings);
          await Gal.putImageBytes(out, name: 'plana_${r.seed}', album: album);
          saved++;
        }
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() => _saveDone = saved + failed);
    }
    // 存成过才记进"最近用过"(全失败的名字记下来只会碍事)
    if (album != null && saved > 0) {
      await ref
          .read(saveSettingsProvider.notifier)
          .patch((s) => s.withAlbumUsed(album));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final where = album == null ? '相册' : '「$album」';
    hintSnack(
      context,
      failed == 0 ? '已保存 $saved 张到$where' : '保存 $saved 张到$where,失败 $failed 张',
      icon: failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
    );
  }

  /// 保存到自定义相册:先问名字,再走同一条保存管线。
  Future<void> _downloadToAlbum() async {
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    final name = await showAlbumNameSheet(
      context,
      recent: settings.recentAlbums,
      count: _picked.length,
    );
    if (name == null || !mounted) return;
    await _downloadPicked(album: name);
  }

  /// 长按缩略图:压暗背景,把按住的那张从原位放大浮起,菜单紧贴在它下面。
  ///
  /// 之前是 showMenu 锚在手指坐标上 —— 图本身一点变化都没有,菜单跟哪张图
  /// 有关全靠猜。指向感只能由**图自己动**来给,锚点给不了。
  Future<void> _thumbMenu(String id, Rect from) async {
    final r = _resultOf(id);
    if (r == null) return;
    Haptics.medium();
    // 先把原图读出来**并解码**,再开抬起层。只读不解码不够:Image.memory
    // 拿到字节还要一两帧才落笔,那一两帧照样露出底下垫着的缩略图 ——
    // 看着就是「先糊一下再变清」。
    final warm = await _warmFull(r).timeout(
      const Duration(milliseconds: 300),
      onTimeout: () => null, // 读得慢就先抬起来,手势不能被读盘卡住
    );
    if (!mounted) return;
    final nav = Navigator.of(context);
    // 缩略图报的是屏幕坐标,路由画在 overlay 里 —— 有嵌套导航时两者不重合
    final box = nav.overlay?.context.findRenderObject() as RenderBox?;
    final at = box == null ? from : box.globalToLocal(from.topLeft) & from.size;
    final picked = await nav.push(
      _ThumbMenuRoute(from: at, result: r, warm: warm),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'import':
        await _importOne(id);
      case 'save':
        await _downloadPicked(only: {id});
      case 'share':
        await _sharePicked(only: {id});
      case 'delete':
        _deleteOne(id);
    }
  }

  /// 读原图并预解码。解码结果进 ImageCache,抬起层再画就是同步的。
  /// 用 MemoryImage(不带 cacheWidth)是为了**和画布同一个缓存键** ——
  /// 同一张图两边共用一次解码,而不是各解一张。
  Future<Uint8List?> _warmFull(ResultImage r) async {
    try {
      final bytes =
          r.bytes ?? await ref.read(appStoresProvider).gallery.readImage(r.id);
      if (bytes == null || !mounted) return null;
      await precacheImage(MemoryImage(bytes), context);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  ResultImage? _resultOf(String id) =>
      ref.read(galleryProvider).results.where((e) => e.id == id).firstOrNull;

  /// 导入:这张送进导入面板(解析内嵌元数据 / 用作参考),与画布侧栏同一个面板。
  ///
  /// 先关网格弹层再推面板 —— 面板是整页的,压在弹层上会留一层退不掉的夹心:
  /// 从面板返回时人会以为回到了画布,实际还在弹层里。
  Future<void> _importOne(String id) async {
    final r = ref
        .read(galleryProvider)
        .results
        .where((e) => e.id == id)
        .firstOrNull;
    if (r == null) return;
    final bytes =
        r.bytes ?? await ref.read(appStoresProvider).gallery.readImage(id);
    if (!mounted) return;
    if (bytes == null) {
      hintSnack(context, '图片尚未就绪', icon: Icons.hourglass_empty);
      return;
    }
    final nav = Navigator.of(context);
    nav.pop();
    unawaited(
      nav.push(
        sharedAxisRoute(
          ImportImagePanel(
            bytes: bytes,
            fileName: 'plana_${r.seed}.png',
            displayName: 'plana_${r.seed}',
          ),
        ),
      ),
    );
  }

  /// 分享:按保存设置处理后落进缓存,交给系统分享面板(管线见
  /// [prepareShareFiles],胶片条的上滑分享也走那条)。
  /// [only] 指定就只分享这几张(长按菜单那条单张的路),否则分享多选选中的。
  Future<void> _sharePicked({Set<String>? only}) async {
    final want = only ?? _picked;
    final items = [
      for (final r in ref.read(galleryProvider).results)
        if (want.contains(r.id)) r,
    ];
    if (items.isEmpty) return;
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    setState(() {
      _sharing = true;
      _saveDone = 0;
      _saveTotal = items.length;
    });
    final prep = await prepareShareFiles(
      items,
      store: ref.read(appStoresProvider).gallery,
      settings: settings,
      onEach: (done) {
        if (!mounted) return false; // 弹层已关:中止剩余
        setState(() => _saveDone = done);
        return true;
      },
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (prep.files.isEmpty) {
      hintSnack(context, '没有可分享的图片', icon: Icons.error_outline);
      return;
    }
    await SharePlus.instance.share(ShareParams(files: prep.files));
    if (prep.failed > 0 && mounted) {
      hintSnack(context, '${prep.failed} 张读不出来,已跳过', icon: Icons.error_outline);
    }
  }

  /// 单张删除(长按菜单里那项)。**不再二次确认** —— 长按抬起、看清是哪张、
  /// 再点删除,本身已是三步;弹窗只是给这条路再加一次点击。
  /// 批量删除那条仍然确认:一次十几张,误触代价不在一个量级。
  void _deleteOne(String id) {
    ref.read(galleryProvider.notifier).deleteResults([id]);
    if (ref.read(galleryProvider).results.isEmpty) {
      Navigator.of(context).pop(); // 删空了,弹层没得看
      return;
    }
    hintSnack(context, '已删除', icon: Icons.delete_outline);
  }

  Future<void> _deletePicked() async {
    final ids = _picked.toList();
    if (ids.isEmpty) return;
    final scheme = context.scheme;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('删除 ${ids.length} 张作品?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    ref.read(galleryProvider.notifier).deleteResults(ids);
    _exitSelect();
    if (ref.read(galleryProvider).results.isEmpty) {
      Navigator.of(context).pop(); // 删空了,弹层没得看
    }
    hintSnack(context, '已删除 ${ids.length} 张', icon: Icons.delete_outline);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(galleryProvider);
    final results = state.results;
    final search = ref.watch(gallerySearchProvider);

    // 筛选管线(先廉价的时间,再查表)
    final terms = searchTerms(_query);
    final filtered = <ResultImage>[
      for (final r in results)
        if (_passTime(r) &&
            _passModel(r, search.byId) &&
            _passQuery(r, search.byId, terms))
          r,
    ];
    final filtering =
        _query.isNotEmpty || _modelFilter != null || _daysFilter != 0;

    // 弹层开着期间条目可能被裁剪/删除/筛掉,勾选集随之收敛 ——
    // 批量操作永远只作用于当前可见集合,不留筛选外的"隐形勾选"
    _picked.removeWhere((id) => !filtered.any((r) => r.id == id));

    // 按天分段:列表天然新→旧,键的首现序即段序
    final byDay = <int, List<ResultImage>>{};
    for (final r in filtered) {
      byDay.putIfAbsent(galleryDayKey(r.createdAt), () => []).add(r);
    }
    final now = DateTime.now();

    final scheme = context.scheme;
    final h = MediaQuery.of(context).size.height * 0.82;
    final canAct = _picked.isNotEmpty && !_saving && !_sharing;

    return PopScope(
      // 多选态下系统返回/侧滑先退多选,不关弹层 —— 勾了十几张再手滑退出,
      // 重新勾一遍的代价比多按一次返回大得多。非多选态照常放行,
      // 好让预测式返回该怎么演就怎么演。
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelect();
      },
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: SizedBox(
                height: 36,
                child: _selecting
                    ? Row(
                        children: [
                          Text(
                            '已选 ${_picked.length} 张',
                            style: context.texts.titleMedium!.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => _toggleAll(filtered),
                            child: Text(
                              _picked.length == filtered.length &&
                                      filtered.isNotEmpty
                                  ? '全不选'
                                  : '全选',
                            ),
                          ),
                          TextButton(
                            onPressed: _saving ? null : _exitSelect,
                            child: const Text('完成'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Text(
                            '全部作品',
                            style: context.texts.titleMedium!.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            filtering
                                ? '${filtered.length}/${results.length} 张'
                                : '${results.length} 张',
                            style: context.texts.bodySmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _toggleSearch,
                            visualDensity: VisualDensity.compact,
                            tooltip: '搜索提示词标签',
                            icon: Icon(
                              Icons.search,
                              size: 21,
                              color: _searchOpen
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _enterSelect(),
                            child: const Text('多选'),
                          ),
                        ],
                      ),
              ),
            ),
            // 搜索框(点放大镜展开;关闭即清词)
            ExpandBody(
              expanded: _searchOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  style: context.texts.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索提示词标签…',
                    prefixIcon: const Icon(Icons.search, size: 19),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 17),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            // 筛选 chips + 检索索引回填进度
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _chip(
                    scheme,
                    label: _modelFilter == null
                        ? '模型'
                        : (_modelFilter!.isEmpty ? '未知' : _modelFilter!),
                    active: _modelFilter != null,
                    onTap: () => _pickModelFilter(results, search.byId),
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    scheme,
                    label: switch (_daysFilter) {
                      1 => '今天',
                      7 => '近 7 天',
                      30 => '近 30 天',
                      _ => '时间',
                    },
                    active: _daysFilter != 0,
                    onTap: _pickTimeFilter,
                  ),
                  if (search.building) ...[
                    const Spacer(),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '索引 ${search.done}/${search.total}',
                      style: context.texts.bodySmall!.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _dragSelectLayer(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              filtering
                                  ? Icons.search_off
                                  : Icons.image_outlined,
                              size: 40,
                              color: scheme.outline,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              filtering ? '没有符合条件的作品' : '图库是空的',
                              style: context.texts.bodyMedium!.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          for (final e in byDay.entries) ...[
                            SliverToBoxAdapter(
                              child: _dayHeader(scheme, e.key, e.value, now),
                            ),
                            // 缩略图本体还各带 5(描边 2.5 + 让位 2.5)的内缩,
                            // 所以图与图之间实际留白 = 这里的 spacing + 10。
                            // 收到 6 之后是 16,省下的宽度全给图。
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 6,
                                      crossAxisSpacing: 6,
                                    ),
                                delegate: SliverChildBuilderDelegate((_, i) {
                                  final r = e.value[i];
                                  // 拖选靠命中路径反查这个 id,见 _idAt
                                  return MetaData(
                                    metaData: r.id,
                                    child: _GridThumb(
                                      result: r,
                                      selected:
                                          !_selecting &&
                                          r.id == state.selectedId,
                                      picked:
                                          _selecting && _picked.contains(r.id),
                                      selecting: _selecting,
                                      onTap: () {
                                        if (_selecting) {
                                          _toggle(r.id);
                                        } else {
                                          ref
                                              .read(galleryProvider.notifier)
                                              .select(r.id);
                                          Navigator.of(context).pop();
                                        }
                                      },
                                      onLongPress: _selecting
                                          ? null
                                          : (from) => _thumbMenu(r.id, from),
                                    ),
                                  );
                                }, childCount: e.value.length),
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                        ],
                      ),
              ),
            ),
            // 多选操作栏:进出多选随高度动画滑入滑出
            AnimatedSize(
              duration: Motion.medium,
              curve: Motion.emphasized,
              child: !_selecting
                  ? const SizedBox(width: double.infinity)
                  : SafeArea(
                      top: false,
                      child: Padding(
                        // 上下同距,横竖间隙同取 _actGap —— 原来横 12 竖 8、
                        // 上 4 下 12,三颗挤在一小块里,不等的间隙一眼看得出别扭
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          _actGap,
                          16,
                          _actGap,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 高度写死在外层:三颗按钮各是 tonal/filled/outlined,
                            // 各自的默认内边距不一样,不给紧约束就长不齐
                            SizedBox(
                              height: _actH,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: canAct
                                          ? () => _downloadPicked()
                                          : null,
                                      icon: const Icon(
                                        Icons.download,
                                        size: 19,
                                      ),
                                      label: Text(
                                        _saving
                                            ? '保存中 $_saveDone/$_saveTotal'
                                            : '保存 (${_picked.length})',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: _actGap),
                                  Expanded(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: scheme.errorContainer,
                                        foregroundColor:
                                            scheme.onErrorContainer,
                                      ),
                                      onPressed: canAct ? _deletePicked : null,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 19,
                                      ),
                                      label: Text('删除 (${_picked.length})'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: _actGap),
                            // 次行:两颗都要多一步(选相册 / 挑应用),与上面
                            // 两颗的即时性不同级,所以矮一档(_actSubH)。
                            SizedBox(
                              height: _actSubH,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: canAct
                                          ? () => _sharePicked()
                                          : null,
                                      icon: _sharing
                                          ? const SizedBox(
                                              width: 15,
                                              height: 15,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.ios_share,
                                              size: 17,
                                            ),
                                      label: Text(
                                        _sharing
                                            ? '准备 $_saveDone/$_saveTotal'
                                            : '分享',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: _actGap),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: canAct
                                          ? _downloadToAlbum
                                          : null,
                                      icon: const Icon(
                                        Icons.photo_album_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('自定义相册'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridThumb extends StatelessWidget {
  const _GridThumb({
    required this.result,
    required this.selected,
    required this.picked,
    required this.selecting,
    required this.onTap,
    this.onLongPress,
  });

  final ResultImage result;

  /// 普通模式:是否为画布当前选中项(主题色描边)。
  final bool selected;

  /// 多选模式:是否已勾选(主题色描边 + 勾选圆标)。
  final bool picked;
  final bool selecting;
  final VoidCallback onTap;

  /// 长按:带上**这张图当前占的屏幕矩形**(不是手指坐标)——
  /// 抬起动画要从这块地方长出来,菜单才看得出是属于哪一张的。
  final void Function(Rect from)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final ring = selecting ? picked : selected;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return;
              // 减掉描边 + 让位的那 5,让抬起从图的边缘起算,不是从格子边缘
              onLongPress!(
                (box.localToGlobal(Offset.zero) & box.size).deflate(5),
              );
            },
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ring ? scheme.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.5),
          child: LayoutBuilder(
            builder: (_, c) => Stack(
              children: [
                ResultThumb(
                  result: result,
                  width: c.maxWidth,
                  height: c.maxWidth,
                  radius: 10,
                ),
                // 多选模式左上角换勾选圆标(角标让位)
                if (selecting)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: picked
                            ? scheme.primary
                            : Colors.black.withValues(alpha: .35),
                        border: picked
                            ? null
                            : Border.all(
                                color: Colors.white.withValues(alpha: .85),
                                width: 1.5,
                              ),
                      ),
                      child: picked
                          ? Icon(Icons.check, size: 15, color: scheme.onPrimary)
                          : null,
                    ),
                  )
                else if (result.badge != ResultBadge.none)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: ResultBadgeChip(badge: result.badge),
                  ),
                // 右下角生成时刻(日期由段头承担,段内标时刻才是增量信息)
                if (galleryTimeBadge(result.createdAt) case final String t
                    when t.isNotEmpty)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        t,
                        style: mono(context, size: 9, weight: FontWeight.w600)
                            .copyWith(
                              color: Colors.white.withValues(alpha: .92),
                              height: 1,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- 长按:按住抬起 + 贴着图的菜单 ----

/// 缩略图长按后的「抬起」层。
///
/// 用 PopupRoute 而不是自己搭 Overlay:遮罩、返回键、点空白关闭、进出动画
/// 全是路由自带的,手搭一遍只会漏掉其中一两样。
class _ThumbMenuRoute extends PopupRoute<String> {
  _ThumbMenuRoute({
    required this.from,
    required this.result,
    required this.warm,
  });

  /// 缩略图在 overlay 坐标系里的原始矩形 —— 放大从这里长出来,
  /// 「浮起的是这一张」全指望它。
  final Rect from;
  final ResultImage result;

  /// 开层前已读好并解码过的原图;null = 没赶上(读得慢/读失败),
  /// 层里自己去 watch,补上之前先用缩略图垫着。
  final Uint8List? warm;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: .55);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 230);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> anim,
    Animation<double> _,
  ) => _LiftedThumb(from: from, result: result, warm: warm, anim: anim);
}

class _LiftedThumb extends ConsumerWidget {
  const _LiftedThumb({
    required this.from,
    required this.result,
    required this.warm,
    required this.anim,
  });

  final Rect from;
  final ResultImage result;
  final Uint8List? warm;
  final Animation<double> anim;

  static const _margin = 16.0;
  static const _gap = 12.0;
  static const _menuW = 200.0;
  static const _itemH = 46.0;
  static const _dividerH = 9.0;
  static const _menuH = _itemH * 4 + _dividerH + 16;

  /// 抬起的图占「可用框」(去掉边距与菜单之后那块)的面积比例。
  static const _fill = .42;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final top0 = media.padding.top + _margin;
    final bot0 = size.height - media.padding.bottom - _margin;

    // 抬起后按图的**真实长宽比**摊开 —— 网格里是方裁的,这一下顺带把裁掉的
    // 部分还回来。
    //
    // 预算给的是**面积**,不是宽度。原先一律取屏宽六成,横图等于被砍了两刀:
    // 宽度先削到六成,高度再按长宽比除一次,最后只有同尺寸竖图的四成大 ——
    // 而它下面那截纵向空间明明空着。改成「什么比例都占可用框的 [_fill]」,
    // 竖图与原先基本同尺寸,横图翻倍,方图也不再偏小。
    //
    // 不铺满是刻意的:铺满就成了看图页,没有「一张卡浮在网格上」的意思,
    // 而这个「浮在网格上」正是指向感的来源。
    final aspect = (result.aspect.isFinite && result.aspect > 0)
        ? result.aspect
        : 1.0; // 老索引里 0 宽/0 高的条目,别把 NaN 送进布局
    final maxW = size.width - _margin * 2;
    final maxH = math.max(80.0, bot0 - top0 - _menuH - _gap);
    var pw = math.sqrt(maxW * maxH * _fill * aspect);
    var ph = pw / aspect;
    if (ph > maxH) {
      ph = maxH;
      pw = ph * aspect;
    }
    if (pw > maxW) {
      pw = maxW;
      ph = pw / aspect;
    }

    // 尽量停在原位附近:抬起来的是「刚按的那一张」,不是从屏幕中央蹦出来的
    // 另一张。装不下(菜单要顶到屏幕外)才整体上移。
    final groupH = ph + _gap + _menuH;
    final left = (from.center.dx - pw / 2)
        .clamp(_margin, math.max(_margin, size.width - pw - _margin))
        .toDouble();
    final top = (from.center.dy - ph / 2)
        .clamp(top0, math.max(top0, bot0 - groupH))
        .toDouble();
    final menuLeft = left
        .clamp(_margin, math.max(_margin, size.width - _menuW - _margin))
        .toDouble();
    final to = Rect.fromLTWH(left, top, pw, ph);

    // 抬起来本就是为了看清 —— 拿缩略图放大只是把糊的放得更糊,所以用原图。
    // 常态下 warm 已经读好解好(见 _warmFull),第一帧就是清的;只有没赶上
    // 时才落到这个 watch 上,那条路再淡入。
    final full = warm ?? ref.watch(galleryImageProvider(result.id)).value;

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = Motion.emphasized.transform(
          anim.value.clamp(0.0, 1.0).toDouble(),
        );
        final rect = Rect.lerp(from, to, t)!;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 原图读盘期间先垫着已经在内存里的缩略图 ——
                    // 长按到抬起之间不该有一格空白。
                    //
                    // 原图到位后必须**让它消失**,不能一直垫着:不透明图看不出
                    // 区别(全被盖住),半透明图会从透明区把这张拉伸的缩略图透
                    // 出来,看着就是背景多了一张模糊的放大图。用淡出而不是
                    // 直接撤掉 —— 与上面那层的淡入同步,慢路径才不会闪一下空白。
                    AnimatedOpacity(
                      opacity: full == null ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: ResultThumb(
                        result: result,
                        width: rect.width,
                        height: rect.height,
                        radius: 14,
                      ),
                    ),
                    // 慢路径(warm 没赶上)才会走到这个切换:淡入而不是
                    // 直接盖上去,免得眼睁睁看着一张糊的跳成清的
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: full == null
                          ? const SizedBox.shrink(key: ValueKey('wait'))
                          : Image.memory(
                              full,
                              key: const ValueKey('full'),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: menuLeft,
              top: to.bottom + _gap,
              width: _menuW,
              // 从图的下沿卷出来,不是凭空淡入 —— 强调它属于上面那张
              child: Opacity(
                opacity: t,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: math.max(t, .01),
                    child: _menu(context),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _menu(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _item(context, Icons.input, '导入', 'import'),
          _item(context, Icons.download, '保存', 'save'),
          _item(context, Icons.ios_share, '分享', 'share'),
          // 删除排最后并单独隔一条线:菜单就在手指底下,不可撤销的那项
          // 排第一位等于放到最容易误落的地方
          Divider(
            height: _dividerH,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: scheme.outlineVariant,
          ),
          _item(context, Icons.delete_outline, '删除', 'delete', danger: true),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    bool danger = false,
  }) {
    final scheme = context.scheme;
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: SizedBox(
        height: _itemH,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              icon,
              size: 20,
              color: danger ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: context.texts.bodyLarge!.copyWith(
                color: danger ? scheme.error : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

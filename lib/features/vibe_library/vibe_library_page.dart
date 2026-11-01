import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/anlas_provider.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/remote_image.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/fast_scroll_handle.dart';
import '../../core/ui/scroll_memory.dart';
import '../../core/ui/selection_bar.dart';
import '../../core/util/image_pick.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart' show CharRefItem, VibeItem;
import '../generate/nai_request.dart' show naiModelId;
import '../generate/vibe_cache.dart' show vibeCacheProvider;
import '../generate/vibe_encoder.dart';
import '../generate/widgets/common.dart'
    show ParamSlider, confirmDialog, hintSnack;
import 'naiv4vibe_codec.dart' show buildBundleText, kModelToEncodingKey;
import 'vibe_backup_sheet.dart';
import 'public_vibes.dart';
import 'vibe_detail_sheet.dart';
import 'vibe_import.dart' show ingestVibeFiles;
import 'vibe_library.dart';
import '../../core/util/haptics.dart';

// 状态圆点:压在缩略图上,不能跟种子色走 —— 单一来源见 [FixedSemantic]
const _dotOk = FixedSemantic.ok; // 当前模型可用
const _dotWarn = FixedSemantic.warn; // 缺当前模型编码,不可用

// 保留标签「收藏」:固定显示在「全部」右侧、不可在管理里删除,按含此标签的条目筛选。
const _kFavTag = '收藏';

/// 顶部各行统一的左右边距;行尾若是 IconButton,用 [_kIconEdge]
/// (减去按钮 8px 内衬)让图标视觉边与其他行对齐。
const _kEdge = 14.0;
const _kIconEdge = 6.0;

/// 发布时可选的编码模型(v4 家族)。发布必须至少编码其一。
const _publishEncodeModels = [
  ('nai-diffusion-4-5-full', 'NAI 4.5 Full'),
  ('nai-diffusion-4-5-curated', 'NAI 4.5 Curated'),
  ('nai-diffusion-4-full', 'NAI 4 Full'),
  ('nai-diffusion-4-curated-preview', 'NAI 4 Curated'),
];

String _encModelLabel(String modelId) {
  for (final (id, label) in _publishEncodeModels) {
    if (id == modelId) return label;
  }
  return modelId;
}

/// Vibe 管理器:单列横条(勾选=已加入生成、点卡即加/移)+ 本地/公共双 Tab +
/// 标签筛选 + 底部两层批量栏。导入入口在右上角,列表按最近导入排序。
class VibeLibraryPage extends ConsumerStatefulWidget {
  const VibeLibraryPage({super.key});

  @override
  ConsumerState<VibeLibraryPage> createState() => _VibeLibraryPageState();
}

class _VibeLibraryPageState extends ConsumerState<VibeLibraryPage>
    with SingleTickerProviderStateMixin {
  // 本地 | 公共库(对齐 mockup 顺序,默认本地)。
  // 只用来判「序号真的换了没」,不参与布局取值 —— 参与了就会跨页抖(见 build)。
  int _lastTabIndex = 0;
  late final TabController _tab = TabController(length: 2, vsync: this)
    ..addListener(() {
      // 只在 tab 序号真正切换时重建;忽略滑动中每帧的 offset 通知
      // (否则整页每帧重建 = 卡顿)。
      if (_tab.index == _lastTabIndex) return;
      _lastTabIndex = _tab.index;
      // 离开公共 tab 时退出多选
      if (_tab.index != 1 && _publicMulti) {
        _publicMulti = false;
        _publicSel.clear();
      }
      setState(() {});
    });
  String _search = '';
  String? _tagFilter; // null = 全部
  bool _busy = false;
  final Set<String> _collecting = {}; // 公共 vibe 下载中的 filename

  // 公共库多选模式(长按进入)+ 已选 filename 集合。
  bool _publicMulti = false;
  final Set<String> _publicSel = {};

  // 公共库「待下载」选择:点选只标记,确认选择时才批量下载并加入生成。
  final Set<String> _publicPending = {};
  // 确认下载进度:(已完成/正在下载序号, 总数);null = 非下载中。
  (int, int)? _downloading;

  // 本页是 push 出来的路由,弹回即销毁(路由自带的 PageStorage 桶也随之作废),
  // 所以滚动位置记到进程级的 ScrollMemory 里,重进本页才落得回原处。
  final _localScroll = MemoScrollController('vibe.local');
  final _publicScroll = MemoScrollController('vibe.public');

  /// 进入页面时的 vibe 快照(返回 = 放弃本次全部增删,还原它)。
  /// 点卡即时加入生成面板,没有「攒到最后才生效」的缓冲,反悔只能靠这份底片。
  late final List<VibeItem> _snapshot;

  /// 加入 Vibe 会因互斥停用角色参考,快照一并存,还原时连同恢复 ——
  /// 只还 vibe 的话角色参考还停着,等于还了半截。
  late final List<CharRefItem> _charRefsSnapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = List.of(ref.read(generateProvider).vibes);
    _charRefsSnapshot = List.of(ref.read(generateProvider).charRefs);
  }

  @override
  void dispose() {
    _tab.dispose();
    _localScroll.dispose();
    _publicScroll.dispose();
    super.dispose();
  }

  VibeLibrary get _lib => ref.read(vibeLibraryProvider.notifier);

  String get _modelKey =>
      kModelToEncodingKey[naiModelId(
        ref.read(generateProvider).params.model,
      )] ??
      '';

  // ---- 勾选语义:已加入生成面板 ----

  String? _activeItemId(VibeEntry e) {
    for (final v in ref.read(generateProvider).vibes) {
      if (v.sourceId == e.id ||
          (v.imageHash != null && v.imageHash == e.imageHash)) {
        return v.id;
      }
    }
    return null;
  }

  bool _compatible(VibeEntry e) =>
      e.hasImage || e.supportedModels.contains(_modelKey);

  /// 图字节哈希 → 缓存里已有的模型键。每次 build 建一次(见 [build])。
  Map<String, Set<String>> _cachedEnc = const {};

  /// 条目实际有的编码 = 索引里文件自带的 ∪ 缓存里后来编出来的。
  ///
  /// `supportedModels` 是**导入那一刻**文件 encodings 的快照,之后生成时新编出
  /// 来的编码只进内容寻址缓存、不回填索引(编码的唯一真相在缓存,见
  /// vibe_cache.dart)。只看索引就会把「用过之后才编出来的」显示成未编码 ——
  /// 而详情页是合并了缓存的,于是外面写未编码、点进去写已编码。
  List<String> _encModelsOf(VibeEntry e) {
    final hash = e.imageHash;
    final cached = hash == null ? null : _cachedEnc[hash];
    if (cached == null || cached.isEmpty) return e.supportedModels;
    return {...e.supportedModels, ...cached}.toList()..sort();
  }

  Future<void> _toggle(VibeEntry e) async {
    final activeId = _activeItemId(e);
    if (activeId != null) {
      ref.read(generateProvider.notifier).removeVibe(activeId);
      setState(() {});
      return;
    }
    if (!_compatible(e)) {
      hintSnack(context, '该 Vibe 无当前模型的编码,无法使用', icon: Icons.info_outline);
      return;
    }
    await _addEntryToGenerate(e);
  }

  /// 库条目 → 生成面板(本地/公共收藏后共用)。
  Future<void> _addEntryToGenerate(VibeEntry e) async {
    final data = await _lib.loadForGenerate(e);
    if (!mounted) return;
    if (data == null) {
      hintSnack(context, '无法读取该 Vibe 文件', icon: Icons.error_outline);
      return;
    }
    Haptics.selection();
    final hadCharRefs = ref.read(generateProvider).enabledCharRefs > 0;
    ref
        .read(generateProvider.notifier)
        .addVibe(
          image: data.image,
          name: e.name,
          imageHash: data.imageHash,
          strength: e.defaultStrength ?? 0.6,
          infoExtracted: data.image != null
              ? (e.defaultInfoExtracted ?? 1.0)
              : data.fixedInfoExtracted,
          encodedByModel: data.encodedByModel,
          sourceId: e.id,
        );
    if (hadCharRefs) {
      hintSnack(context, '与角色参考互斥,已暂停角色参考', icon: Icons.swap_horiz);
    }
    setState(() {});
  }

  // ---- 公共库:点选只标记(待下载),确认选择时才下载并加入生成 ----

  bool _publicCompatible(PublicVibeMeta m) =>
      m.hasImage || m.supportedModels.contains(_modelKey);

  /// 公共卡是否勾选:待下载 或 已收藏且已在生成面板。
  bool _publicChecked(PublicVibeMeta m) {
    if (_publicPending.contains(m.filename)) return true;
    final e = _lib.entryByOriginFilename(m.filename);
    return e != null && _activeItemId(e) != null;
  }

  /// 点选公共卡(非多选):已加入生成→立即移出;否则切换「待下载」标记(不下载)。
  void _togglePublicSelect(PublicVibeMeta m) {
    final e = _lib.entryByOriginFilename(m.filename);
    final activeId = e == null ? null : _activeItemId(e);
    setState(() {
      if (activeId != null) {
        ref.read(generateProvider.notifier).removeVibe(activeId);
        _publicPending.remove(m.filename);
      } else if (!_publicPending.remove(m.filename)) {
        _publicPending.add(m.filename);
      }
    });
  }

  /// 确认选择:下载所有「待下载」公共 vibe(落本地库)并加入生成,然后返回。
  Future<void> _confirmSelection() async {
    final all = ref.read(publicVibesProvider).value ?? const <PublicVibeMeta>[];
    final metas = [
      for (final m in all)
        if (_publicPending.contains(m.filename)) m,
    ];
    if (metas.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    var fail = 0;
    for (var i = 0; i < metas.length; i++) {
      if (!mounted) return;
      setState(() => _downloading = (i + 1, metas.length));
      final m = metas[i];
      try {
        var entry = _lib.entryByOriginFilename(m.filename);
        if (entry == null) {
          final text = await _fetchPublicText(m);
          if (text != null) {
            final entries = await _lib.importVibeText(
              text,
              fallbackName: m.name,
              originFilename: m.filename,
            );
            entry = entries.isEmpty ? null : entries.first;
          }
        }
        if (entry == null) {
          fail++;
          continue;
        }
        if (_activeItemId(entry) == null) {
          final data = await _lib.loadForGenerate(entry);
          if (data == null) {
            fail++;
            continue;
          }
          ref
              .read(generateProvider.notifier)
              .addVibe(
                image: data.image,
                name: entry.name,
                imageHash: data.imageHash,
                strength: entry.defaultStrength ?? 0.6,
                infoExtracted: data.image != null
                    ? (entry.defaultInfoExtracted ?? 1.0)
                    : data.fixedInfoExtracted,
                encodedByModel: data.encodedByModel,
                sourceId: entry.id,
              );
        }
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _downloading = null;
      _publicPending.clear();
    });
    if (fail > 0) hintSnack(context, '$fail 条下载失败', icon: Icons.error_outline);
    if (mounted) Navigator.of(context).pop();
  }

  // ---- 导入(右上角) ----

  Future<void> _importImages() async {
    final picked = await pickImagesOrFiles(context);
    if (picked.isEmpty || !mounted) return;
    // 图库里改走「从文件选」的,一律按文件分流(vibe 文件也放行)
    if (picked.files.isNotEmpty) return _ingest(picked.files);
    setState(() => _busy = true);
    var n = 0;
    for (final f in picked.images) {
      try {
        await _lib.importImageBytes(f.bytes, f.baseName);
        n++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _busy = false);
    hintSnack(context, '已入库 $n 张参考图', icon: Icons.check_circle_outline);
  }

  Future<void> _importFiles() async {
    // withData: false —— 整包 vibe 可能上百 MB(图是 base64),拿路径流式解析;
    // 图片则按需逐张读字节,不把整批一次性堆在内存里。
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    final files = res?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    await _ingest(files);
  }

  /// 选中的文件按内容分流入库(vibe 文件 / 图片),完事报一次数。
  Future<void> _ingest(List<PlatformFile> files) async {
    setState(() => _busy = true);
    final got = await ingestVibeFiles(_lib, files);
    if (!mounted) return;
    setState(() => _busy = false);
    final parts = [
      if (got.vibes > 0) '${got.vibes} 条 Vibe',
      if (got.images > 0) '${got.images} 张图',
      if (got.failed > 0) '${got.failed} 个失败',
    ];
    hintSnack(
      context,
      parts.isEmpty ? '没有可导入的内容' : '导入完成:${parts.join(' · ')}',
      icon: got.failed > 0 ? Icons.error_outline : Icons.check_circle_outline,
    );
  }

  // ---- 底部批量操作(作用于已勾选 = 已加入生成的库条目,对齐 web) ----

  List<VibeEntry> _checkedEntries(List<VibeEntry> all) => [
    for (final e in all)
      if (_activeItemId(e) != null) e,
  ];

  Future<void> _deleteChecked(List<VibeEntry> checked) async {
    final ok = await confirmDialog(
      context,
      title: '删除 Vibe',
      message: '将从库中删除选中的 ${checked.length} 条 Vibe(文件与缩略图一并移除),不可恢复。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    for (final e in checked) {
      final activeId = _activeItemId(e);
      if (activeId != null) {
        ref.read(generateProvider.notifier).removeVibe(activeId);
      }
      await _lib.delete(e.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _exportChecked(List<VibeEntry> checked) async {
    setState(() => _busy = true);
    try {
      final String text;
      final String name;
      if (checked.length == 1) {
        text = await _lib.exportText(checked.first);
        name =
            '${checked.first.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.naiv4vibe';
      } else {
        text = await _lib.exportBundleText(checked);
        name = 'vibes_${checked.length}.naiv4vibebundle';
      }
      final path = await FilePicker.platform.saveFile(
        fileName: name,
        bytes: utf8.encode(text),
      );
      if (path != null && mounted) {
        hintSnack(
          context,
          '已导出 ${checked.length} 条 Vibe',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (mounted) hintSnack(context, '导出失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearActive() {
    final notifier = ref.read(generateProvider.notifier);
    for (final v in [...ref.read(generateProvider).vibes]) {
      notifier.removeVibe(v.id);
    }
    setState(() {});
  }

  /// 取消选择:清掉已加入生成的 vibe + 公共库待下载标记(选择归零,不返回)。
  void _clearAllSelection() {
    _publicPending.clear();
    _clearActive();
  }

  /// 返回键的动作:还原进入页面时的快照(放弃本次全部增删,含被互斥停用的
  /// 角色参考),回生成页。「确认选择」走直接 pop,不经这里。
  ///
  /// 只管生成面板的选择 —— 库里删掉/改名/导入的条目是真落盘的,还原不回来。
  void _cancel() {
    ref.read(generateProvider.notifier)
      ..restoreVibes(_snapshot)
      ..restoreCharRefs(_charRefsSnapshot);
    Navigator.of(context).pop();
  }

  /// 相对进入页面时是否有增删(顺序也算)。
  bool _changedFromSnapshot(List<VibeItem> now) {
    if (now.length != _snapshot.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (now[i].id != _snapshot[i].id) return true;
    }
    return false;
  }

  /// 批量给选中(已勾选)条目追加一个标签。
  Future<void> _batchTag(List<VibeEntry> checked) async {
    final ctl = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量添加标签'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '标签名,如 风景',
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (tag == null || tag.isEmpty || !mounted) return;
    await _lib.addTagToAll([for (final e in checked) e.id], tag);
    if (mounted) {
      setState(() {});
      hintSnack(
        context,
        '已为 ${checked.length} 条添加标签「$tag」',
        icon: Icons.check_circle_outline,
      );
    }
  }

  /// 编辑单条 vibe 的标签(现有标签勾选 + 新建),对齐 web 单条「编辑标签」。
  Future<void> _editTags(VibeEntry e) async {
    // 标签池 = 「收藏」保留标签 + 库中全部已知标签(在用 + 新建的空标签)
    final pool = [
      _kFavTag,
      for (final t in _lib.knownTags)
        if (t != _kFavTag) t,
    ];
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _TagEditorSheet(name: e.name, pool: pool, current: e.tags),
    );
    if (result == null || !mounted) return;
    await _lib.setTags(e.id, result);
    if (mounted) setState(() {});
  }

  void _openDetail(VibeEntry e) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VibeDetailSheet(entryId: e.id),
    );
    if (!mounted) return;
    setState(() {}); // 详情里可能改了参数/删除/加入
    if (added == true) {
      hintSnack(context, '已添加到生成', icon: Icons.check_circle_outline);
    }
  }

  // 本地行:单条导出 / 删除
  Future<void> _exportOne(VibeEntry e) async {
    try {
      final text = await _lib.exportText(e);
      final safe = e.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = await FilePicker.platform.saveFile(
        fileName: '$safe.naiv4vibe',
        bytes: utf8.encode(text),
      );
      if (path != null && mounted) {
        hintSnack(
          context,
          '已导出 $safe.naiv4vibe',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (err) {
      if (mounted) hintSnack(context, '导出失败:$err', icon: Icons.error_outline);
    }
  }

  Future<void> _deleteOne(VibeEntry e) async {
    final ok = await confirmDialog(
      context,
      title: '删除 Vibe',
      message: '「${e.name}」将从库中删除(文件与缩略图一并移除),不可恢复。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    final activeId = _activeItemId(e);
    if (activeId != null) {
      ref.read(generateProvider.notifier).removeVibe(activeId);
    }
    await _lib.delete(e.id);
    if (mounted) setState(() {});
  }

  /// 发布到公共库(对齐 web:主名称 + Strength/IE 两个参数 + 选模型编码 → POST /vibes/upload)。
  /// 需 Bot 授权;必须先为所选模型编码(缓存优先,未命中扣 2 Anlas/个),编码成功才上传。
  /// 上传的是整条 .naiv4vibe(含图与合并后的编码)。
  Future<void> _publishToPublic(VibeEntry e) async {
    final session = await ref.read(botSessionProvider.future);
    if (!mounted) return;
    if (session == null) {
      hintSnack(context, '发布到公共库需要 Bot 授权', icon: Icons.info_outline);
      return;
    }
    final res =
        await showModalBottomSheet<
          ({String name, double strength, double ie, List<String> models})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _PublishSheet(
            initialName: e.name,
            initialStrength: e.defaultStrength ?? 0.6,
            initialIe: e.defaultInfoExtracted ?? 1.0,
            hasImage: e.hasImage,
          ),
        );
    if (res == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // 1) 必须编码:为所选模型在目标 IE 编码(缓存优先;失败则中止发布)。
      if (e.hasImage && res.models.isNotEmpty) {
        final img = await _lib.loadImageBytes(e);
        final hash = e.imageHash;
        if (img == null || hash == null) {
          if (mounted) {
            hintSnack(context, '无法读取原图,发布已取消', icon: Icons.error_outline);
          }
          return;
        }
        final encoder = ref.read(vibeEncoderProvider);
        var spent = false;
        for (final model in res.models) {
          final hit = await encoder.cached(
            imageHash: hash,
            model: model,
            infoExtracted: res.ie,
          );
          if (hit != null) continue; // 已缓存,免费
          if (mounted) {
            hintSnack(
              context,
              '正在编码 ${_encModelLabel(model)} · IE ${res.ie.toStringAsFixed(2)}…',
              icon: Icons.bolt_outlined,
            );
          }
          await encoder.encode(
            image: img,
            imageHash: hash,
            model: model,
            infoExtracted: res.ie,
          );
          spent = true;
        }
        if (spent) unawaited(ref.read(anlasProvider.notifier).refresh());
      }
      // 2) 导出整条(合并刚生成的编码)并覆写发布参数。
      final raw = jsonDecode(await _lib.exportText(e)) as Map<String, dynamic>;
      raw['name'] = res.name;
      final info = raw['importInfo'] is Map
          ? (raw['importInfo'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      info['strength'] = res.strength;
      info['information_extracted'] = res.ie;
      raw['importInfo'] = info;
      // 3) 上传。
      final result = await ref
          .read(backendClientProvider)
          .uploadPublicVibe(
            sessionId: session.sessionId,
            vibeData: raw,
            name: res.name,
          );
      if (!mounted) return;
      if (result.success) {
        ref.invalidate(publicVibesProvider);
        hintSnack(
          context,
          '已发布到公共库:${result.filename ?? res.name}',
          icon: Icons.check_circle_outline,
        );
      } else {
        hintSnack(
          context,
          result.message.isEmpty ? '发布失败' : result.message,
          icon: Icons.error_outline,
        );
      }
    } on BackendException catch (err) {
      if (mounted) {
        hintSnack(context, '发布失败:${err.message}', icon: Icons.error_outline);
      }
    } catch (err) {
      if (mounted) {
        hintSnack(context, '编码或发布失败:$err', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 公共行:收藏(下载落库不加入) / 下载文件到设备
  Future<String?> _fetchPublicText(PublicVibeMeta m) async {
    final session = await ref.read(botSessionProvider.future);
    if (session == null) return null;
    return ref
        .read(backendClientProvider)
        .getPublicVibeFileText(session.sessionId, m.filename);
  }

  Future<void> _collectPublic(PublicVibeMeta m) async {
    if (_lib.entryByOriginFilename(m.filename) != null) {
      hintSnack(context, '已在本地库', icon: Icons.info_outline);
      return;
    }
    setState(() => _collecting.add(m.filename));
    try {
      final text = await _fetchPublicText(m);
      if (text != null) {
        await _lib.importVibeText(
          text,
          fallbackName: m.name,
          originFilename: m.filename,
        );
        if (mounted) {
          hintSnack(context, '已收藏到本地', icon: Icons.check_circle_outline);
        }
      }
    } catch (e) {
      if (mounted) hintSnack(context, '收藏失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _collecting.remove(m.filename));
    }
  }

  // ---- 公共库多选 ----

  void _enterPublicMulti(String filename) {
    Haptics.selection();
    setState(() {
      _publicMulti = true;
      _publicSel
        ..clear()
        ..add(filename);
    });
  }

  void _togglePublicSel(String filename) {
    setState(() {
      if (!_publicSel.remove(filename)) _publicSel.add(filename);
      if (_publicSel.isEmpty) _publicMulti = false; // 全部取消则退出
    });
  }

  void _exitPublicMulti() => setState(() {
    _publicMulti = false;
    _publicSel.clear();
  });

  List<PublicVibeMeta> _visiblePublic() {
    final all = ref.read(publicVibesProvider).value ?? const <PublicVibeMeta>[];
    final q = _search.trim().toLowerCase();
    return q.isEmpty
        ? all
        : [
            for (final m in all)
              if (m.name.toLowerCase().contains(q)) m,
          ];
  }

  void _selectAllPublic() {
    final vis = _visiblePublic();
    setState(() {
      if (vis.isNotEmpty && _publicSel.length >= vis.length) {
        _publicSel.clear();
        _publicMulti = false;
      } else {
        _publicSel
          ..clear()
          ..addAll(vis.map((m) => m.filename));
      }
    });
  }

  List<PublicVibeMeta> _selectedPublicMetas() => [
    for (final m in _visiblePublic())
      if (_publicSel.contains(m.filename)) m,
  ];

  /// 批量收藏所选公共 vibe 到本地库(已在库的跳过)。
  Future<void> _collectPublicSelected() async {
    final metas = _selectedPublicMetas();
    if (metas.isEmpty) return;
    setState(() => _busy = true);
    var ok = 0, skip = 0, fail = 0;
    for (final m in metas) {
      if (_lib.entryByOriginFilename(m.filename) != null) {
        skip++;
        continue;
      }
      try {
        final text = await _fetchPublicText(m);
        if (text != null) {
          await _lib.importVibeText(
            text,
            fallbackName: m.name,
            originFilename: m.filename,
          );
          ok++;
        } else {
          fail++;
        }
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final parts = [
      if (ok > 0) '收藏 $ok',
      if (skip > 0) '已在库 $skip',
      if (fail > 0) '失败 $fail',
    ];
    hintSnack(
      context,
      parts.isEmpty ? '无可收藏' : parts.join(' · '),
      icon: fail > 0 ? Icons.error_outline : Icons.check_circle_outline,
    );
  }

  /// 批量打包所选公共 vibe 为 .naiv4vibebundle 保存到设备。
  Future<void> _bundlePublicSelected() async {
    final metas = _selectedPublicMetas();
    if (metas.isEmpty) return;
    setState(() => _busy = true);
    try {
      final raws = <Map<String, dynamic>>[];
      for (final m in metas) {
        final text = await _fetchPublicText(m);
        if (text == null) continue;
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) raws.add(decoded);
      }
      if (raws.isEmpty) {
        if (mounted) {
          hintSnack(context, '打包失败:无可用内容', icon: Icons.error_outline);
        }
        return;
      }
      final path = await FilePicker.platform.saveFile(
        fileName: 'public_vibes_${raws.length}.naiv4vibebundle',
        bytes: utf8.encode(buildBundleText(raws)),
      );
      if (path != null && mounted) {
        hintSnack(
          context,
          '已打包 ${raws.length} 条 Vibe',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (mounted) hintSnack(context, '打包失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- 列表数据 ----

  List<VibeEntry> _visible(List<VibeEntry> all) {
    final q = _search.trim().toLowerCase();
    // _tagFilter == _kFavTag(「收藏」)也走同一条 tags.contains 分支。
    final list = [
      for (final e in all)
        if ((_tagFilter == null || e.tags.contains(_tagFilter)) &&
            (q.isEmpty ||
                e.name.toLowerCase().contains(q) ||
                e.tags.any((t) => t.toLowerCase().contains(q))))
          e,
    ];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final all = ref.watch(vibeLibraryProvider).value;
    final vibes = ref.watch(generateProvider).vibes;
    final checked = all == null ? const <VibeEntry>[] : _checkedEntries(all);
    // 缓存没加载好就先按索引显示,加载完这里会重建一次
    _cachedEnc =
        ref.watch(vibeCacheProvider).value?.modelKeysByImage() ?? const {};

    return PopScope(
      // 返回 = 放弃本次全部增删(还原进入时的快照)。「确认选择」走的是
      // Navigator.pop,不经 maybePop,不会被这里拦下。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 公共库多选态:先退多选,不退页
        if (_publicMulti) {
          _exitPublicMulti();
          return;
        }
        _cancel();
      },
      child: _scaffold(scheme, all, vibes, checked),
    );
  }

  Widget _scaffold(
    ColorScheme scheme,
    List<VibeEntry>? all,
    List<VibeItem> vibes,
    List<VibeEntry> checked,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vibe 管理器'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: '云备份',
              icon: const Icon(Icons.cloud_outlined),
              onPressed: () => showVibeBackupSheet(context),
            ),
            PopupMenuButton<String>(
              tooltip: '导入',
              icon: const Icon(Icons.add),
              onSelected: (v) => v == 'img' ? _importImages() : _importFiles(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'img',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.image_outlined),
                    title: Text('导入图片'),
                  ),
                ),
                PopupMenuItem(
                  value: 'file',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.file_open_outlined),
                    title: Text('导入 Vibe 文件'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 搜索
          Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 6, _kEdge, 0),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索名称或标签…',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: context.pageControlFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          // 分段 Tab。底距**恒为 0**:两页的差别由各自页内出。
          //
          // 从前这里写的是 `_lastTabIndex == 0 ? 0 : 8` —— 可这个 Padding 在
          // TabBarView **外面**,序号一翻,两页一起往下挪 8px;而序号是滑到
          // 半程才翻的,和横向滑动动画脱钩,看上去就是列表在切换途中平白下沉
          // 一截。跨页共享的盒子不能按当前页调尺寸。
          Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 0),
            child: _segTabs(scheme, all?.length ?? 0),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                all == null
                    ? const Center(child: CircularProgressIndicator())
                    : _localTab(all),
                // 公共页没有标签筛选行顶开间距,自己补一档 —— 放在页内、
                // 滚动区之外:既不影响本地页,滚动时这道缝也留得住。
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _publicTab(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(scheme, checked, vibes),
    );
  }

  Widget _segTabs(ColorScheme scheme, int localCount) {
    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.pageControlFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // 视觉层:滑动指示器 + 渐变标签(随 tab 动画重建,无手势)。
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _tab.animation!,
                builder: (context, _) {
                  final t = _tab.animation!.value.clamp(0.0, 1.0);
                  return LayoutBuilder(
                    builder: (context, c) {
                      final segW = c.maxWidth / 2;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 3,
                            bottom: 3,
                            left: 3 + t * segW,
                            width: segW - 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: context.segThumb,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _segLabel(
                                0,
                                Icons.smartphone,
                                '本地 · $localCount',
                                t,
                              ),
                              _segLabel(1, Icons.public, '公共库', t),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // 手势层:稳定不重建,整段任意位置可点(避免高频重建吞掉点击)。
            Positioned.fill(
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tab.animateTo(i),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分段控件的标签(纯视觉,无手势):颜色随指示器位置在灰↔主色间渐变。
  Widget _segLabel(int i, IconData icon, String label, double t) {
    final scheme = context.scheme;
    final sel = i == 0 ? 1 - t : t; // 越靠近该 tab 越接近 1
    final color = Color.lerp(
      scheme.onSurfaceVariant,
      context.segLabel(scheme.primary),
      sel,
    );
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.texts.labelLarge!.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _localTab(List<VibeEntry> all) {
    // 标签(分组)筛选行 —— 紧贴本地/公共切换行下方(全部/最近 + 标签 + 管理)
    final tags = _lib.knownTags; // 含新建但尚未挂条目的空标签
    final list = _visible(all);
    return Column(
      children: [
        _tagChips(tags),
        Divider(
          height: 1,
          color: context.scheme.outlineVariant.withValues(alpha: .4),
        ),
        Expanded(child: _grid(list)),
      ],
    );
  }

  Widget _tagChips(List<String> tags) {
    final scheme = context.scheme;
    Widget chip(String label, bool sel, VoidCallback onTap, {IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            // 图标放进 label(自控间距),不用 avatar(默认间距太大)
            label: icon == null
                ? Text(label)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(label),
                    ],
                  ),
            selected: sel,
            onSelected: (_) => onTap(),
            visualDensity: VisualDensity.compact,
            // 圆形(药丸)外形
            shape: const StadiumBorder(),
            labelStyle: context.texts.labelMedium!.copyWith(
              fontWeight: FontWeight.w600,
              color: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            selectedColor: scheme.primary,
            backgroundColor: context.pageControlFill,
            side: BorderSide.none,
            showCheckmark: false,
          ),
        );
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            // 横向滚动:标签再多也不会溢出
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(_kEdge, 4, 4, 4),
              children: [
                chip(
                  '全部',
                  _tagFilter == null,
                  () => setState(() => _tagFilter = null),
                ),
                // 固定「收藏」保留标签(全部右侧,不可删除)
                chip(
                  '收藏',
                  _tagFilter == _kFavTag,
                  () => setState(() => _tagFilter = _kFavTag),
                  icon: Icons.star_rounded,
                ),
                for (final t in tags)
                  if (t != _kFavTag)
                    chip(
                      t,
                      _tagFilter == t,
                      () => setState(() => _tagFilter = t),
                    ),
              ],
            ),
          ),
          // 管理标签(重命名 / 删除)
          IconButton(
            tooltip: '管理标签',
            icon: Icon(
              Icons.settings_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: () => _manageTags(tags),
          ),
          const SizedBox(width: _kIconEdge),
        ],
      ),
    );
  }

  Future<void> _manageTags(List<String> tags) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TagManagerSheet(),
    );
    if (mounted) {
      // 被删/改的标签可能正被筛选,回落到全部(新建的空标签、收藏保留标签仍算存在)
      final live = _lib.knownTags.toSet();
      if (_tagFilter != null &&
          _tagFilter != _kFavTag &&
          !live.contains(_tagFilter)) {
        setState(() => _tagFilter = null);
      } else {
        setState(() {});
      }
    }
  }

  Widget _grid(List<VibeEntry> list) {
    final scheme = context.scheme;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.palette_outlined,
              size: 40,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 10),
            Text(
              _search.isEmpty && _tagFilter == null
                  ? '暂无本地 Vibe'
                  : '没有匹配的 Vibe',
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_search.isEmpty && _tagFilter == null) ...[
              const SizedBox(height: 4),
              Text(
                '点击右上角 + 导入',
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ],
        ),
      );
    }
    // 发布到公共库是纯后端功能:只看有没有 Bot 会话,与生成走哪条路无关。
    final canPublish = ref.watch(botSessionProvider).value != null;
    return FastScrollHandle(
      child: GridView.builder(
        controller: _localScroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final e = list[i];
          return _VibeCard(
            entry: e,
            checked: _activeItemId(e) != null,
            compatible: _compatible(e),
            encodedModels: _encModelsOf(e),
            thumb: _lib.thumbOf(e),
            onTap: () => _toggle(e), // 点卡 = 加入/移出生成
            onDelete: () => _deleteOne(e),
            onDetail: () => _openDetail(e),
            onExport: () => _exportOne(e),
            onEditTags: () => _editTags(e),
            onPublish: canPublish ? () => _publishToPublic(e) : null,
          );
        },
      ),
    );
  }

  Widget _publicHint(IconData icon, String text, {VoidCallback? onRetry}) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('点击重试'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _publicTab() {
    // 公共库是纯后端功能:只要授权过 Bot 就能用,不要求把生成也切到 Bot。
    final session = ref.watch(botSessionProvider).value;
    if (session == null) {
      return _publicHint(
        Icons.cloud_off,
        '公共 Vibe 库需要 Bot 授权\n可在「我的」→「账号与接入」中授权',
      );
    }
    final async = ref.watch(publicVibesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => e is StateError
          ? _publicHint(
              Icons.cloud_off,
              '公共 Vibe 库需要 Bot 授权\n可在「我的」页切换到 Bot 模式并授权',
            )
          : _publicHint(
              Icons.error_outline,
              '加载公共库失败',
              onRetry: () => ref.invalidate(publicVibesProvider),
            ),
      data: (all) {
        final q = _search.trim().toLowerCase();
        final list = q.isEmpty
            ? all
            : [
                for (final m in all)
                  if (m.name.toLowerCase().contains(q)) m,
              ];
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(publicVibesProvider);
            await ref
                .read(publicVibesProvider.future)
                .catchError((_) => <PublicVibeMeta>[]);
          },
          child: list.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    _publicHint(
                      Icons.public_off,
                      q.isEmpty ? '公共库暂无 Vibe' : '没有匹配的公共 Vibe',
                    ),
                  ],
                )
              : FastScrollHandle(
                  child: GridView.builder(
                    controller: _publicScroll,
                    // 顶距 8:另外 8 由本页外层那圈 Padding 出,两段合起来仍是
                    // 一档间距,只是外面那半留在了滚动区之外(滚动时不跟着走)。
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.82,
                        ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final m = list[i];
                      final entry = _lib.entryByOriginFilename(m.filename);
                      return _PublicVibeCard(
                        meta: m,
                        checked: _publicMulti
                            ? _publicSel.contains(m.filename)
                            : _publicChecked(m),
                        collected: entry != null,
                        collecting: _collecting.contains(m.filename),
                        compatible: _publicCompatible(m),
                        // 多选:点=选/取消;非多选:点=标记待下载(确认后才下)
                        onTap: () {
                          if (_publicMulti) {
                            _togglePublicSel(m.filename);
                          } else {
                            _togglePublicSelect(m);
                          }
                        },
                        // 长按:进入/切换多选
                        onLongPress: () {
                          if (_publicMulti) {
                            _togglePublicSel(m.filename);
                          } else {
                            _enterPublicMulti(m.filename);
                          }
                        },
                        // 收藏按钮(名称行右侧);多选模式隐藏
                        onCollect: _publicMulti
                            ? null
                            : () => _collectPublic(m),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  // ---- 底部操作栏 ----

  /// 公共库多选底栏:打包 / 收藏(作用于所选)+ 全选 + 退出多选。
  /// 公共库多选态的底栏。左键仍是「取消选择」(清空勾选、留在多选里),
  /// 主动作是退出多选 —— 和另外几条同一套版式。
  Widget _publicMultiBar(ColorScheme scheme) {
    final n = _publicSel.length;
    final total = _visiblePublic().length;
    final allSelected = n >= total && total > 0;
    return SelectionBar(
      // 多选态是显式进入的,进来就常驻,否则退不出去
      visible: true,
      onClear: n == 0 ? null : () => setState(_publicSel.clear),
      actions: [
        SelectionPill(
          icon: Icons.archive_outlined,
          label: '打包',
          onTap: (n == 0 || _busy) ? null : _bundlePublicSelected,
        ),
        SelectionPill(
          icon: Icons.favorite_border,
          label: '收藏',
          onTap: (n == 0 || _busy) ? null : _collectPublicSelected,
        ),
        SelectionPill(
          icon: Icons.done_all,
          label: allSelected ? '取消全选' : '全选',
          onTap: total == 0 ? null : _selectAllPublic,
        ),
      ],
      primary: FilledButton.icon(
        onPressed: _exitPublicMulti,
        style: selectionPrimaryStyle(),
        icon: const Icon(Icons.close, size: 18),
        label: Text('退出多选${n > 0 ? ' · 已选 $n' : ''}'),
      ),
    );
  }

  Widget _bottomBar(
    ColorScheme scheme,
    List<VibeEntry> checked,
    List<VibeItem> vibes,
  ) {
    // 公共库多选态:专用的「打包 / 收藏 / 全选 / 退出」栏。
    if (_tab.index == 1 && _publicMulti) return _publicMultiBar(scheme);
    final activeCount = vibes.length;
    // 没有任何选择/待下载时收起,把整屏留给列表。
    // 「相对进入时有改动」也要露着:全部移出后底栏若消失,唯一出口就只剩返回,
    // 而返回=还原快照,刚做的移出会被撤销 —— 没有「确认」就没法把移出落地。
    final show =
        activeCount > 0 ||
        checked.isNotEmpty ||
        _publicPending.isNotEmpty ||
        _downloading != null ||
        _changedFromSnapshot(vibes);
    final downloading = _downloading != null;
    final selCount = activeCount + _publicPending.length;
    final local = _tab.index == 0 && checked.isNotEmpty;
    return SelectionBar(
      visible: show,
      onClear: downloading || selCount == 0 ? null : _clearAllSelection,
      actions: [
        if (local) ...[
          SelectionPill(
            icon: Icons.archive_outlined,
            label: '打包',
            onTap: _busy ? null : () => _exportChecked(checked),
          ),
          SelectionPill(
            icon: Icons.sell_outlined,
            label: '标签',
            onTap: () => _batchTag(checked),
          ),
        ],
      ],
      destructive: local
          ? SelectionPill(
              icon: Icons.delete_outline,
              label: '删除',
              color: scheme.error,
              onTap: () => _deleteChecked(checked),
            )
          : null,
      // 确认 = 下载待下载的公共 vibe;下载中转进度并锁住
      primary: FilledButton.icon(
        onPressed: downloading ? null : _confirmSelection,
        style: selectionPrimaryStyle(),
        icon: downloading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Icon(Icons.check, size: 18),
        label: Text(
          downloading
              ? '下载中 ${_downloading!.$1}/${_downloading!.$2}'
              : (selCount > 0 ? '确认选择 ($selCount)' : '确认选择'),
        ),
      ),
    );
  }
}

/// 缩略图占位。
Widget _thumbPh(ColorScheme scheme, {IconData icon = Icons.image_outlined}) =>
    Container(
      color: scheme.surfaceContainerHigh,
      child: Icon(icon, size: 24, color: scheme.outline),
    );

/// 编码键集合的紧凑显示:同版本 Full+Curated 都有 → 版本号(4.5);
/// 只有一个 → 版本 + F/C(4.5F / 4.5C)。两个版本组用 · 分隔。
String _encModelsShort(List<String> keys) {
  final parts = <String>[];
  void group(String ver, String fullKey, String curatedKey) {
    final f = keys.contains(fullKey);
    final c = keys.contains(curatedKey);
    if (f && c) {
      parts.add(ver);
    } else if (f) {
      parts.add('${ver}F');
    } else if (c) {
      parts.add('${ver}C');
    }
  }

  group('4.5', 'v4-5full', 'v4-5curated');
  group('4.0', 'v4full', 'v4curated');
  return parts.join(' · ');
}

/// 双列网格卡片外壳:缩略图区(左上选中框 · 忙碌遮罩)+ 卡片体
/// (名称行:名称 + 右侧操作 nameTrailing;副行:标签 + 编码状态)。
/// 点卡 = onTap,长按 = onLongPress(公共多选)。
/// 点卡主体 = onTap(加入/移出生成)。
class _VibeCardShell extends StatelessWidget {
  const _VibeCardShell({
    required this.checked,
    required this.compatible,
    required this.name,
    required this.supportedModels,
    required this.thumbnail,
    required this.busy,
    required this.onTap,
    this.onLongPress,
    this.nameTrailing,
    this.tagLabel,
  });

  final bool checked;
  final bool compatible;
  final String name;
  final List<String>
  supportedModels; // 编码键(v4-5full / v4-5curated / v4full / v4curated)
  final Widget thumbnail;
  final bool busy; // 下载中
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // 长按(公共多选进入/切换)
  final Widget? nameTrailing; // 名称行右侧(本地菜单 / 公共收藏)
  final String? tagLabel; // 副行标签(公共无标签则 null)

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: checked
              ? scheme.primaryContainer.withValues(alpha: .28)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        // 边框放前景层:选中态加粗高亮只是绘制,不占布局。
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: checked
                ? scheme.primary.withValues(alpha: .7)
                : scheme.outlineVariant.withValues(alpha: .3),
            width: checked ? 1.8 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 缩略图区(占卡片上部剩余空间)
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    thumbnail,
                    if (checked)
                      Container(color: scheme.primary.withValues(alpha: .18)),
                    Positioned(top: 8, left: 8, child: _checkbox(scheme)),
                    if (busy)
                      Container(
                        color: Colors.black.withValues(alpha: .42),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 卡片体:文本列(名称 + 副行)+ 右侧更多菜单(相对整块垂直居中)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w700,
                              color: compatible
                                  ? (checked ? scheme.primary : null)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // 副行:标签(有则显示)+ 编码状态(模型名 / 未编码)
                          _metaRow(context),
                        ],
                      ),
                    ),
                    if (nameTrailing != null) ...[
                      const SizedBox(width: 2),
                      nameTrailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkbox(ColorScheme scheme) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? scheme.primary : Colors.black.withValues(alpha: .3),
        border: Border.all(
          color: checked ? scheme.primary : Colors.white.withValues(alpha: .85),
          width: 2,
        ),
      ),
      child: checked
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : null,
    );
  }

  /// 副行:标签(有则显示)+ 编码状态(编码则显示模型名,未编码显示「未编码」)。
  Widget _metaRow(BuildContext context) {
    return Row(
      children: [
        if (tagLabel != null) ...[
          Flexible(child: _tagChip(context)),
          const SizedBox(width: 6),
        ],
        Flexible(child: _encStatus(context)),
      ],
    );
  }

  /// 编码状态:未编码=灰「未编码」;已编码=绿+模型名(4.5 / 4.5F…);当前不兼容=橙「需 X」。
  Widget _encStatus(BuildContext context) {
    final scheme = context.scheme;
    final Color color;
    final IconData icon;
    final String text;
    if (supportedModels.isEmpty) {
      color = scheme.outline;
      icon = Icons.remove_circle_outline;
      text = '未编码';
    } else if (!compatible) {
      color = _dotWarn;
      icon = Icons.error_outline;
      text = '需 ${_encModelsShort(supportedModels)}';
    } else {
      color = _dotOk;
      icon = Icons.check_circle;
      text = _encModelsShort(supportedModels);
    }
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// 副行标签 chip(仅本地、有标签时)。
  Widget _tagChip(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tagLabel!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.labelSmall!.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 名称行右侧的紧凑「更多」菜单按钮(卡片体内,非缩略图浮层)。
class _CardMenuButton extends StatelessWidget {
  const _CardMenuButton({required this.onSelected, required this.items});

  final ValueChanged<String> onSelected;
  final List<PopupMenuEntry<String>> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 22,
      child: PopupMenuButton<String>(
        tooltip: '更多',
        icon: Icon(
          Icons.more_vert,
          size: 20,
          color: context.scheme.onSurfaceVariant,
        ),
        padding: EdgeInsets.zero,
        iconSize: 20,
        onSelected: onSelected,
        itemBuilder: (_) => items,
      ),
    );
  }
}

/// 本地卡片:点卡 = 加入/移出;右上菜单 = 详情/编辑标签/发布/导出/删除。
class _VibeCard extends StatelessWidget {
  const _VibeCard({
    required this.entry,
    required this.checked,
    required this.compatible,
    required this.encodedModels,
    required this.thumb,
    required this.onTap,
    required this.onDelete,
    required this.onDetail,
    required this.onExport,
    required this.onEditTags,
    this.onPublish,
  });

  final VibeEntry entry;
  final bool checked;
  final bool compatible;

  /// 实际有的编码模型键(索引 ∪ 缓存),**不是** `entry.supportedModels`
  /// —— 后者只是导入那一刻的快照,见 `_encModelsOf`。
  final List<String> encodedModels;
  final File thumb;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDetail;
  final VoidCallback onExport;
  final VoidCallback onEditTags;

  /// 发布到公共库(仅 Bot 模式提供;null = 不显示该菜单项)。
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return _VibeCardShell(
      checked: checked,
      compatible: compatible,
      name: entry.name,
      supportedModels: encodedModels,
      busy: false,
      onTap: onTap,
      tagLabel: entry.tags.isEmpty ? null : entry.tags.first,
      thumbnail: entry.hasImage
          ? Image.file(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _thumbPh(scheme),
            )
          : _thumbPh(scheme, icon: Icons.data_object),
      nameTrailing: _CardMenuButton(
        onSelected: (v) {
          switch (v) {
            case 'detail':
              onDetail();
            case 'tags':
              onEditTags();
            case 'publish':
              onPublish?.call();
            case 'export':
              onExport();
            case 'delete':
              onDelete();
          }
        },
        items: [
          const PopupMenuItem(
            value: 'detail',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.tune, size: 19),
              title: Text('详情与参数'),
            ),
          ),
          const PopupMenuItem(
            value: 'tags',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sell_outlined, size: 19),
              title: Text('编辑标签'),
            ),
          ),
          if (onPublish != null)
            const PopupMenuItem(
              value: 'publish',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.public, size: 19),
                title: Text('发布到公共'),
              ),
            ),
          const PopupMenuItem(
            value: 'export',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.ios_share, size: 19),
              title: Text('导出'),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                size: 19,
                color: scheme.error,
              ),
              title: Text('删除', style: TextStyle(color: scheme.error)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 公共卡片:点卡 = 下载落库并加入(多选态=选/取消);长按进多选;
/// 名称行右侧 = 收藏按钮(多选态隐藏)。
class _PublicVibeCard extends StatelessWidget {
  const _PublicVibeCard({
    required this.meta,
    required this.checked,
    required this.collected,
    required this.collecting,
    required this.compatible,
    required this.onTap,
    this.onLongPress,
    this.onCollect, // null = 不显示收藏(多选模式)
  });

  final PublicVibeMeta meta;
  final bool checked;
  final bool collected;
  final bool collecting;
  final bool compatible;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCollect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return _VibeCardShell(
      checked: checked,
      compatible: compatible,
      name: meta.name,
      supportedModels: meta.supportedModels,
      busy: collecting,
      onTap: onTap,
      onLongPress: onLongPress,
      tagLabel: null,
      thumbnail: meta.hasImage
          ? RemoteImage(
              meta.thumbnailUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      color: scheme.surfaceContainerHigh,
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
              errorBuilder: (_, _, _) => _thumbPh(scheme),
            )
          : _thumbPh(scheme, icon: Icons.data_object),
      nameTrailing: onCollect == null
          ? null
          : _CollectButton(
              collected: collected,
              onTap: (collecting || collected) ? null : onCollect,
            ),
    );
  }
}

/// 名称行右侧的紧凑收藏按钮(公共卡片用):已收藏=绿实心,未收藏=描边。
class _CollectButton extends StatelessWidget {
  const _CollectButton({required this.collected, this.onTap});

  final bool collected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SizedBox(
      width: 30,
      height: 22,
      child: IconButton(
        tooltip: collected ? '已收藏' : '收藏到本地',
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(
          collected ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: collected ? _dotOk : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 发布到公共库 sheet(对齐 web):主名称 + Strength / Info Extracted + 选模型编码。
/// 必须编码才能发布(有原图时至少选 1 个模型)。pop 返回 (name, strength, ie, models);取消 null。
class _PublishSheet extends StatefulWidget {
  const _PublishSheet({
    required this.initialName,
    required this.initialStrength,
    required this.initialIe,
    required this.hasImage,
  });

  final String initialName;
  final double initialStrength;
  final double initialIe;
  final bool hasImage; // 无原图=纯编码 vibe,直接用自带编码发布

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  late final TextEditingController _nameCtl = TextEditingController(
    text: widget.initialName,
  );
  late double _strength = widget.initialStrength;
  late double _ie = widget.initialIe;
  // 默认选两个 4.5 模型(对齐 web 端发布默认编码集)。
  final Set<String> _models = {
    'nai-diffusion-4-5-full',
    'nai-diffusion-4-5-curated',
  };

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final nameOk = _nameCtl.text.trim().isNotEmpty;
    // 必须编码才能发布:有原图时至少选 1 个模型。
    final canConfirm = nameOk && (!widget.hasImage || _models.isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '发布到公共库',
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '发布后所有 Bot 用户可在公共库看到并使用此 Vibe(含原图与编码)。',
              style: context.texts.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '主名称',
              style: context.texts.labelMedium!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '为这个 Vibe 起个名字',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ParamSlider(
              label: 'Strength 默认强度',
              value: _strength,
              divisions: 100,
              onChanged: (v) => setState(() => _strength = v),
            ),
            const SizedBox(height: 4),
            ParamSlider(
              label: 'Info Extracted 默认信息提取',
              value: _ie,
              divisions: 100,
              onChanged: (v) => setState(() => _ie = v),
            ),
            const SizedBox(height: 14),
            if (widget.hasImage) ...[
              Row(
                children: [
                  Text(
                    '编码模型',
                    style: context.texts.labelMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '必选 · 未缓存约 2 Anlas/个',
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, label) in _publishEncodeModels)
                    FilterChip(
                      label: Text(label),
                      selected: _models.contains(id),
                      onSelected: (v) => setState(
                        () => v ? _models.add(id) : _models.remove(id),
                      ),
                      showCheckmark: true,
                      checkmarkColor: scheme.onPrimary,
                      selectedColor: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHigh,
                      side: BorderSide.none,
                      labelStyle: context.texts.labelMedium!.copyWith(
                        color: _models.contains(id)
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: scheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '该 Vibe 无原图,将使用其自带编码直接发布。',
                        style: context.texts.labelSmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canConfirm
                        ? () => Navigator.pop(context, (
                            name: _nameCtl.text.trim(),
                            strength: _strength,
                            ie: _ie,
                            models: _models.toList(),
                          ))
                        : null,
                    icon: const Icon(Icons.publish, size: 18),
                    label: Text(widget.hasImage ? '编码并发布' : '确认发布'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条 vibe 标签编辑 sheet:池内标签点选(FilterChip)+ 新建标签输入。
/// pop 返回最终标签列表(null = 取消)。
class _TagEditorSheet extends StatefulWidget {
  const _TagEditorSheet({
    required this.name,
    required this.pool,
    required this.current,
  });

  final String name;
  final List<String> pool; // 库内已有标签(并集)
  final List<String> current; // 本条当前标签

  @override
  State<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<_TagEditorSheet> {
  late final Set<String> _sel = {...widget.current};
  late final List<String> _pool = {...widget.pool, ...widget.current}.toList()
    ..sort();
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _addNew() {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      if (!_pool.contains(t)) _pool.add(t);
      _sel.add(t);
      _pool.sort();
      _ctl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '编辑标签',
            style: context.texts.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (_pool.isEmpty)
            Text(
              '还没有标签,在下方输入新建。',
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _pool)
                  FilterChip(
                    label: Text(t),
                    selected: _sel.contains(t),
                    onSelected: (v) =>
                        setState(() => v ? _sel.add(t) : _sel.remove(t)),
                    showCheckmark: false,
                    selectedColor: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHigh,
                    side: BorderSide.none,
                    labelStyle: context.texts.labelMedium!.copyWith(
                      color: _sel.contains(t)
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '新建标签,如 风景',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _addNew(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addNew,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _sel.toList()..sort()),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 标签管理 sheet:新建标签 + 列出库内所有标签(带使用数),可重命名 / 删除(全局生效)。
class _TagManagerSheet extends ConsumerStatefulWidget {
  const _TagManagerSheet();

  @override
  ConsumerState<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends ConsumerState<_TagManagerSheet> {
  final _newCtl = TextEditingController();

  @override
  void dispose() {
    _newCtl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _newCtl.text.trim();
    if (name.isEmpty) return;
    final ok = await ref.read(vibeLibraryProvider.notifier).createTag(name);
    if (!mounted) return;
    if (ok) {
      _newCtl.clear();
      setState(() {});
    } else {
      hintSnack(context, '标签「$name」已存在', icon: Icons.info_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final lib = ref.read(vibeLibraryProvider.notifier);
    final all = ref.watch(vibeLibraryProvider).value ?? const <VibeEntry>[];
    final counts = <String, int>{};
    for (final e in all) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    // 含新建但尚未挂条目的空标签;排除「收藏」保留标签(不可删除/重命名)。
    final tags = [
      for (final t in lib.knownTags)
        if (t != _kFavTag) t,
    ];

    Future<void> rename(String old) async {
      final ctl = TextEditingController(text: old);
      final neu = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名标签'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(isDense: true),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctl.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (neu != null && neu.isNotEmpty && neu != old) {
        await lib.renameTag(old, neu);
      }
    }

    Future<void> remove(String tag) async {
      final ok = await confirmDialog(
        context,
        title: '删除标签',
        message: '标签「$tag」将从所有 Vibe 上移除(不删除 Vibe 本身)。',
        confirmLabel: '删除',
      );
      if (ok) await lib.removeTag(tag);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Text(
                  '管理标签',
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 新建标签
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCtl,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '新建标签,如 风景',
                      prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '新建',
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (tags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  '还没有标签\n在上方输入框新建,或在某条 Vibe 的「编辑标签」里新建',
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tags.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: .3),
                ),
                itemBuilder: (_, i) {
                  final t = tags[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.only(right: 4),
                    title: Text(
                      t,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${counts[t] ?? 0} 项'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '重命名',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 19,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => rename(t),
                        ),
                        IconButton(
                          tooltip: '删除',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.delete_outline,
                            size: 19,
                            color: scheme.error,
                          ),
                          onPressed: () => remove(t),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

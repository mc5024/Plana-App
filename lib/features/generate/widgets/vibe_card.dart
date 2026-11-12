import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/image_pick.dart';
import '../../vibe_library/vibe_import.dart' show ingestVibeFiles;
import '../../vibe_library/vibe_library.dart';
import '../../vibe_library/vibe_library_page.dart';
import '../canvas_state.dart';
import '../generate_state.dart';
import '../models.dart';
import 'common.dart';
import 'section_card.dart';
import '../../../l10n/l10n.dart';

/// 顶层函数:在后台 isolate 算图片内容哈希(sha256 hex),避免大图卡主线程。
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// Vibe Transfer 卡:缩略图横条(可选)+ 虚线添加格,
/// 下方只显示当前选中那张的详情(参考图名 · 移除 · Strength / Info Extracted)。
class VibeCard extends ConsumerStatefulWidget {
  const VibeCard({super.key, this.reorderIndex});

  final int? reorderIndex;

  @override
  ConsumerState<VibeCard> createState() => _VibeCardState();
}

class _VibeCardState extends ConsumerState<VibeCard> {
  String? _selectedId;

  Future<void> _onAdd() async {
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final picked = await pickImagesOrFiles(context);
    if (picked.isEmpty || !mounted) return;
    // 图库里改走「从文件选」的:不限扩展名,vibe 文件也可能在里面
    if (picked.files.isNotEmpty) return _addFiles(picked.files, canvasId);
    await _addImages(picked.images, canvasId);
  }

  /// 选图到加进来之间切走了画布:没加的就不加了(图已进 Vibe 库)。
  bool _left(String canvasId) =>
      ref.read(canvasWorkspaceProvider).activeId != canvasId;

  Future<void> _addImages(List<PickedImage> files, String canvasId) async {
    // 互斥态在加图前取一次:加 Vibe 会顺手停掉角色参考
    final hadCharRefs = ref.read(generateProvider).enabledCharRefs > 0;
    String? lastId;
    for (final f in files) {
      final bytes = f.bytes;
      final hash = await compute(_sha256Hex, bytes); // 后台算内容哈希
      if (!mounted || _left(canvasId)) return;
      // 顺手入库(同图去重;重启后可从 Vibe 库找回,编码缓存互通不多扣点)
      String? sourceId;
      try {
        final entry = await ref
            .read(vibeLibraryProvider.notifier)
            .importImageBytes(bytes, f.baseName, knownHash: hash);
        sourceId = entry.id;
      } catch (_) {
        // 入库失败不影响本次使用
      }
      if (!mounted || _left(canvasId)) return;
      final id = ref
          .read(generateProvider.notifier)
          .addVibe(
            image: bytes,
            name: f.baseName,
            imageHash: hash,
            sourceId: sourceId,
          );
      if (id.isNotEmpty) lastId = id;
    }
    if (lastId == null) return;
    if (hadCharRefs) _mutexHint(); // 整批只提示一次
    setState(() => _selectedId = lastId);
  }

  /// 从文件浏览器选来的:图片按参考图入库,vibe 文件按 vibe 解析(整包里的多条
  /// 一并加进来),都先落 Vibe 库再取用 —— 纯编码 vibe 没有图,只能这么走。
  Future<void> _addFiles(List<PlatformFile> files, String canvasId) async {
    final lib = ref.read(vibeLibraryProvider.notifier);
    final got = await ingestVibeFiles(lib, files);
    if (!mounted || _left(canvasId)) return;
    final hadCharRefs = ref.read(generateProvider).enabledCharRefs > 0;
    var failed = got.failed;
    String? lastId;
    for (final e in got.entries) {
      final data = await lib.loadForGenerate(e);
      if (!mounted || _left(canvasId)) return;
      if (data == null) {
        failed++; // 落库了但当前拿不出可生成内容(如无任何编码的纯编码条目)
        continue;
      }
      final id = ref
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
      if (id.isNotEmpty) lastId = id;
    }
    // 提示只留一条(新提示顶掉旧的):有失败先说失败,否则才提互斥
    if (failed > 0) {
      hintSnack(context, '$failed 个文件无法导入', icon: Icons.error_outline);
    } else if (lastId == null) {
      hintSnack(context, '没有可导入的内容', icon: Icons.error_outline);
    } else if (hadCharRefs) {
      _mutexHint();
    }
    if (lastId == null) return;
    setState(() => _selectedId = lastId);
  }

  void _toggle(String id, bool currentlyEnabled) {
    final hadCharRefs = ref.read(generateProvider).enabledCharRefs > 0;
    ref.read(generateProvider.notifier).setVibeEnabled(id, !currentlyEnabled);
    if (!currentlyEnabled && hadCharRefs) _mutexHint();
  }

  /// 互斥切换提示:启用/加入 Vibe 导致角色参考被暂停时,弹一次 toast。
  void _mutexHint() =>
      hintSnack(context, '与角色参考互斥,已暂停角色参考', icon: Icons.swap_horiz);

  /// 删除某张,并把选中态平移到相邻项
  void _removeVibe(String id) {
    final vibes = ref.read(generateProvider).vibes;
    final idx = vibes.indexWhere((v) => v.id == id);
    ref.read(generateProvider.notifier).removeVibe(id);
    final rest = ref.read(generateProvider).vibes;
    setState(() {
      if (rest.isEmpty) {
        _selectedId = null;
      } else if (id == _selectedId) {
        _selectedId = rest[idx.clamp(0, rest.length - 1)].id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generateProvider);
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;

    final vibes = state.vibes;
    // 无内容时恒收起;头部「+」导入后(addVibe 会 openPanel)自动展开。
    final expanded = state.openPanels.contains(Panel.vibe) && vibes.isNotEmpty;

    VibeItem? selected;
    for (final v in vibes) {
      if (v.id == _selectedId) {
        selected = v;
        break;
      }
    }
    selected ??= vibes.isNotEmpty ? vibes.first : null;
    // 挂着遮罩时这组 Vibe 不发(见 withoutInpaintVibes),卡片照常可编辑
    final idle = state.inpaint != null && vibes.isNotEmpty;

    return SectionCard(
      icon: Icons.palette_outlined,
      title: context.l10n.vibeTransfer,
      reorderIndex: widget.reorderIndex,
      badge: vibes.isEmpty ? null : CountBadge('${vibes.length}'),
      muted: idle,
      inline: [
        if (idle)
          Flexible(
            child: Text(
              '重绘时不生效',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
          ),
      ],
      actions: [
        RoundIconBtn(
          Icons.grid_view,
          tooltip: 'Vibe 库',
          color: scheme.onSurfaceVariant,
          onTap: () => Navigator.of(
            context,
          ).push(sharedAxisRoute(const VibeLibraryPage())),
        ),
        RoundIconBtn(
          Icons.add,
          // 与角色参考卡的同位按钮区分:两者互斥,tooltip 一样会让人分不清点了哪个
          tooltip: '导入 Vibe 参考图',
          color: scheme.primary,
          onTap: _onAdd,
        ),
      ],
      expanded: expanded,
      onHeaderTap: () => notifier.togglePanel(Panel.vibe),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            // 长按缩略图拖动排序(参考顺序即下发顺序)
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2),
              proxyDecorator: dragProxy,
              onReorderStart: dragStartHaptic,
              onReorderEnd: dragEndHaptic,
              onReorderItem: notifier.reorderVibes,
              children: [
                for (final v in vibes)
                  Padding(
                    key: ValueKey(v.id),
                    padding: const EdgeInsets.only(right: 10),
                    child: RefThumb(
                      selected: v.id == selected?.id,
                      enabled: v.enabled,
                      image: v.image,
                      onTap: () => setState(() => _selectedId = v.id),
                    ),
                  ),
              ],
            ),
          ),
          // 只有多张同时启用才谈得上「均衡」,单张时这行没有意义(与 web 同)
          if (state.enabledVibes > 1) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: HelpLabel(
                    text: context.l10n.normalizeStrength,
                    help: Help.normalizeVibe,
                    style: context.texts.bodySmall!.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Switch(
                  value: state.params.normalizeVibe,
                  onChanged: (v) => notifier.applyParams(
                    state.params.copyWith(normalizeVibe: v),
                  ),
                ),
              ],
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 14),
            _VibeDetail(
              vibe: selected,
              index: vibes.indexOf(selected) + 1,
              onRemove: () => _removeVibe(selected!.id),
              onToggle: () => _toggle(selected!.id, selected.enabled),
            ),
          ],
        ],
      ),
    );
  }
}

/// 选中项详情
class _VibeDetail extends ConsumerWidget {
  const _VibeDetail({
    required this.vibe,
    required this.index,
    required this.onRemove,
    required this.onToggle,
  });

  final VibeItem vibe;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(generateProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RefDetailHeader(
          index: index,
          name: vibe.name,
          onRemove: onRemove,
          enableToggle: RefEnableToggle(enabled: vibe.enabled, onTap: onToggle),
        ),
        const SizedBox(height: 14),
        LiveParamSlider(
          label: context.l10n.referenceStrength,
          help: Help.vibeStrength,
          value: vibe.strength,
          divisions: 100, // step 0.01(对齐 web)
          onCommit: (v) => notifier.updateVibe(vibe.id, strength: v),
        ),
        const SizedBox(height: 6),
        if (vibe.isEncodingOnly)
          // 纯编码 vibe(库导入、无原图):IE 随编码固定,不可调。
          // 用 onChanged: null 走 M3 禁用态,不再整块 IgnorePointer ——
          // 否则连标签上的参数说明都点不开,而恰恰是这里最该解释「为什么锁死」。
          Opacity(
            opacity: .7,
            child: ParamSlider(
              label: 'Info Extracted 信息提取(随编码固定)',
              help: Help.infoExtracted,
              value: vibe.infoExtracted,
              divisions: 100,
              onChanged: null,
            ),
          )
        else
          LiveParamSlider(
            label: context.l10n.infoExtracted,
            help: Help.infoExtracted,
            value: vibe.infoExtracted,
            divisions: 100,
            onCommit: (v) => notifier.updateVibe(vibe.id, infoExtracted: v),
          ),
      ],
    );
  }
}

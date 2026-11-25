import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/image_pick.dart';
import '../../char_library/char_library.dart';
import '../../char_library/char_library_page.dart';
import '../canvas_state.dart';
import '../generate_state.dart';
import '../models.dart';
import 'common.dart';
import '../display_names.dart';
import 'section_card.dart';
import '../../../l10n/l10n.dart';

/// 后台 isolate 算图片内容哈希(sha256 hex)。
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// 角色参考卡:缩略图横条 + 选中详情(迁移模式 · Strength · Fidelity)。
/// 参考图约束角色长相/风格;仅 4.5 模型下发,原图 contain 处理后随生成发送(无编码调用)。
class CharRefCard extends ConsumerStatefulWidget {
  const CharRefCard({super.key, this.reorderIndex});

  final int? reorderIndex;

  @override
  ConsumerState<CharRefCard> createState() => _CharRefCardState();
}

class _CharRefCardState extends ConsumerState<CharRefCard> {
  String? _selectedId;

  Future<void> _onAdd() async {
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    // 选图到加进来之间切走了画布:没加的就不加了(图已进角色参考图库)
    bool left() => ref.read(canvasWorkspaceProvider).activeId != canvasId;
    final files = await pickImageFiles(context);
    if (files.isEmpty || !mounted) return;
    // 互斥态在加图前取一次:加角色参考会顺手停掉 Vibe
    final hadVibes = ref.read(generateProvider).enabledVibes > 0;
    String? lastId;
    for (final f in files) {
      final bytes = f.bytes;
      final hash = await compute(_sha256Hex, bytes); // 后台算内容哈希
      if (!mounted || left()) return;
      // 顺手入库(同图去重;下次可从角色参考图库找回)
      try {
        await ref
            .read(charLibraryProvider.notifier)
            .importImageBytes(bytes, f.baseName, knownHash: hash);
      } catch (_) {
        // 入库失败不影响本次使用
      }
      if (!mounted || left()) return;
      lastId = ref
          .read(generateProvider.notifier)
          .addCharRef(image: bytes, name: f.baseName, imageHash: hash);
    }
    if (lastId == null) return;
    final st = ref.read(generateProvider);
    if (st.inpaint != null && !crSupportsInpainting(st.params.model)) {
      _inpaintUnsupportedHint();
    } else if (hadVibes) {
      _mutexHint(); // 整批只提示一次
    }
    setState(() => _selectedId = lastId);
  }

  void _toggle(String id, bool currentlyEnabled) {
    final hadVibes = ref.read(generateProvider).enabledVibes > 0;
    final applied = ref
        .read(generateProvider.notifier)
        .setCharRefEnabled(id, !currentlyEnabled);
    if (!applied) {
      _inpaintUnsupportedHint();
      return;
    }
    if (!currentlyEnabled && hadVibes) _mutexHint();
  }

  /// V5 等模型重绘不支持角色参考:点击启用或重绘态下添加时弹一次提示。
  void _inpaintUnsupportedHint() => hintSnack(
    context,
    context.l10n.charRefIgnoredInpaint,
    icon: Icons.block,
  );

  /// 互斥切换提示:启用/加入角色参考导致 Vibe 被暂停时,弹一次 toast。
  void _mutexHint() => hintSnack(
    context,
    context.l10n.refMutexVibePaused,
    icon: Icons.swap_horiz,
  );

  void _remove(String id) {
    final refs = ref.read(generateProvider).charRefs;
    final idx = refs.indexWhere((r) => r.id == id);
    ref.read(generateProvider.notifier).removeCharRef(id);
    final rest = ref.read(generateProvider).charRefs;
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
    final model = state.params.model;
    final refs = state.charRefs;
    // 无内容时恒收起;头部「+」导入后(addCharRef 会 openPanel)自动展开。
    final expanded =
        state.openPanels.contains(Panel.charRef) && refs.isNotEmpty;

    CharRefItem? selected;
    for (final r in refs) {
      if (r.id == _selectedId) {
        selected = r;
        break;
      }
    }
    selected ??= refs.isNotEmpty ? refs.first : null;

    final supported = crSupportsModel(model);
    final outfitOk = crSupportsOutfit(model);
    final enabledCount = refs.where((r) => r.enabled).length;
    final hasSkippedOutfit =
        supported &&
        !outfitOk &&
        refs.any((r) => r.enabled && r.mode == CharRefMode.outfit);
    final overCap =
        supported && isNai5Model(model) && enabledCount > kMaxCrRefsV5;

    return SectionCard(
      icon: Icons.face_retouching_natural,
      title: context.l10n.preciseReference,
      reorderIndex: widget.reorderIndex,
      badge: refs.isEmpty ? null : CountBadge('${refs.length}', error: overCap),
      actions: [
        RoundIconBtn(
          Icons.grid_view,
          tooltip: context.l10n.refLibrary,
          color: scheme.onSurfaceVariant,
          onTap: () => Navigator.of(
            context,
          ).push(sharedAxisRoute(const CharLibraryPage())),
        ),
        RoundIconBtn(
          Icons.add,
          // 与 Vibe 卡的同位按钮区分:两者互斥,tooltip 一样会让人分不清点了哪个
          tooltip: context.l10n.importCharRef,
          color: scheme.primary,
          onTap: _onAdd,
        ),
      ],
      expanded: expanded,
      onHeaderTap: () => notifier.togglePanel(Panel.charRef),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refs.isNotEmpty && !supported) ...[
            InfoNote(
              context.l10n.charRefOnly45,
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 12),
          ],
          if (hasSkippedOutfit) ...[
            InfoNote(
              context.l10n.charRefOutfitSkipped,
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 12),
          ],
          if (overCap) ...[
            InfoNote(
              context.l10n.charRefMaxExceeded(kMaxCrRefsV5),
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 72,
            // 长按缩略图拖动排序(参考顺序即下发顺序)
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2),
              proxyDecorator: dragProxy,
              onReorderStart: dragStartHaptic,
              onReorderEnd: dragEndHaptic,
              onReorderItem: notifier.reorderCharRefs,
              children: [
                for (final r in refs)
                  Padding(
                    key: ValueKey(r.id),
                    padding: const EdgeInsets.only(right: 10),
                    child: RefThumb(
                      selected: r.id == selected?.id,
                      enabled: r.enabled,
                      image: r.image,
                      onTap: () => setState(() => _selectedId = r.id),
                    ),
                  ),
              ],
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 14),
            _CharRefDetail(
              item: selected,
              index: refs.indexOf(selected) + 1,
              model: model,
              onRemove: () => _remove(selected!.id),
              onToggle: () => _toggle(selected!.id, selected.enabled),
            ),
          ],
        ],
      ),
    );
  }
}

class _CharRefDetail extends ConsumerWidget {
  const _CharRefDetail({
    required this.item,
    required this.index,
    required this.model,
    required this.onRemove,
    required this.onToggle,
  });

  final CharRefItem item;
  final int index;
  final String model;
  final VoidCallback onRemove;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(generateProvider.notifier);
    final l = context.l10n;
    final outfitOk = crSupportsOutfit(model);
    final fidelityOk = crSupportsFidelity(model);
    final maxStrength = crStrengthMax(model);
    final baseModes = outfitOk
        ? CharRefBaseMode.values
        : const [
            CharRefBaseMode.character,
            CharRefBaseMode.style,
            CharRefBaseMode.both,
          ];
    final unsupportedOutfit =
        !outfitOk && item.mode.baseMode == CharRefBaseMode.outfit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RefDetailHeader(
          index: index,
          name: refDisplayName(l, item.name),
          enabled: item.enabled,
          onRemove: onRemove,
          enableToggle: RefEnableToggle(enabled: item.enabled, onTap: onToggle),
        ),
        const SizedBox(height: 10),
        SegmentedButton<CharRefBaseMode>(
          segments: [
            for (final m in baseModes)
              ButtonSegment(
                value: m,
                label: Text(
                  _baseModeLabel(l, m),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
          ],
          selected: unsupportedOutfit ? const {} : {item.mode.baseMode},
          emptySelectionAllowed: unsupportedOutfit,
          onSelectionChanged: (sel) {
            if (sel.isEmpty) return;
            notifier.updateCharRef(
              item.id,
              mode: CharRefMode.fromBaseMode(sel.first),
            );
          },
          showSelectedIcon: false,
          style: _modeSegStyle,
        ),
        if (outfitOk && item.mode.supportsPreferSameOutfit) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.preferSameOutfit,
                  style: context.texts.bodySmall!.copyWith(
                    color: context.scheme.onSurface,
                  ),
                ),
              ),
              Switch(
                value: item.mode.preferSameOutfit,
                onChanged: (v) => notifier.updateCharRef(
                  item.id,
                  mode: item.mode.withPreferSameOutfit(v),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        // V5 下强度范围 0..5,中点 1.0 非线性映射;V4.5 保持 0..1 线性;刻度对齐官网 0.05。
        LiveParamSlider(
          label: l.referenceStrength,
          help: Help.charRefStrength,
          value: item.strength.clamp(0.0, maxStrength),
          min: 0.0,
          max: maxStrength,
          divisions: outfitOk ? 100 : 20,
          valueTextOf: (v) => quantizeToDivisions(
            v,
            min: 0.0,
            max: maxStrength,
            divisions: outfitOk ? 100 : 20,
          ).toStringAsFixed(2),
          toSlider: outfitOk ? crV5StrengthToSlider : null,
          fromSlider: outfitOk ? crV5StrengthFromSlider : null,
          onCommit: (v) => notifier.updateCharRef(item.id, strength: v),
        ),
        if (fidelityOk) ...[
          const SizedBox(height: 6),
          LiveParamSlider(
            label: l.fidelity,
            help: Help.fidelity,
            value: item.infoExtracted,
            divisions: 20,
            valueTextOf: (v) => quantizeToDivisions(
              v,
              min: 0.0,
              max: 1.0,
              divisions: 20,
            ).toStringAsFixed(2),
            onCommit: (v) => notifier.updateCharRef(item.id, infoExtracted: v),
          ),
        ],
      ],
    );
  }
}

String _baseModeLabel(AppLocalizations l, CharRefBaseMode mode) =>
    switch (mode) {
      CharRefBaseMode.character => l.refCharacter,
      CharRefBaseMode.style => l.refStyle,
      CharRefBaseMode.both => l.refCharacterStyle,
      CharRefBaseMode.outfit => l.refOutfit,
    };

/// 主模式分段选择器样式(与 hires_card 对齐:占满卡宽、4 项并排不折行)。
const _modeSegStyle = ButtonStyle(
  textStyle: WidgetStatePropertyAll(
    TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  ),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
  visualDensity: VisualDensity(horizontal: -3, vertical: -1),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

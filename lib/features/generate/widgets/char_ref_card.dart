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
    if (hadVibes) _mutexHint(); // 整批只提示一次
    setState(() => _selectedId = lastId);
  }

  void _toggle(String id, bool currentlyEnabled) {
    final hadVibes = ref.read(generateProvider).enabledVibes > 0;
    ref
        .read(generateProvider.notifier)
        .setCharRefEnabled(id, !currentlyEnabled);
    if (!currentlyEnabled && hadVibes) _mutexHint();
  }

  /// 互斥切换提示:启用/加入角色参考导致 Vibe 被暂停时,弹一次 toast。
  void _mutexHint() =>
      hintSnack(context, '与 Vibe 互斥,已暂停 Vibe 参考', icon: Icons.swap_horiz);

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

    return SectionCard(
      icon: Icons.face_retouching_natural,
      title: context.l10n.preciseReference,
      reorderIndex: widget.reorderIndex,
      badge: refs.isEmpty ? null : CountBadge('${refs.length}'),
      actions: [
        RoundIconBtn(
          Icons.grid_view,
          tooltip: '参考图库',
          color: scheme.onSurfaceVariant,
          onTap: () => Navigator.of(
            context,
          ).push(sharedAxisRoute(const CharLibraryPage())),
        ),
        RoundIconBtn(
          Icons.add,
          // 与 Vibe 卡的同位按钮区分:两者互斥,tooltip 一样会让人分不清点了哪个
          tooltip: '导入角色参考图',
          color: scheme.primary,
          onTap: _onAdd,
        ),
      ],
      expanded: expanded,
      onHeaderTap: () => notifier.togglePanel(Panel.charRef),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refs.isNotEmpty && !crSupportsModel(state.params.model)) ...[
            const InfoNote(
              '角色参考仅 4.5 模型支持,当前模型生成时不会发送。',
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
    required this.onRemove,
    required this.onToggle,
  });

  final CharRefItem item;
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
          name: item.name,
          onRemove: onRemove,
          enableToggle: RefEnableToggle(enabled: item.enabled, onTap: onToggle),
          leadingAction: _ModeToggle(
            mode: item.mode,
            onTap: () {
              const modes = CharRefMode.values;
              final next = modes[(item.mode.index + 1) % modes.length];
              notifier.updateCharRef(item.id, mode: next);
            },
          ),
        ),
        const SizedBox(height: 14),
        // 保持最低 0(非负,不采用 web 的 −10..+1);step 0.01。
        LiveParamSlider(
          label: context.l10n.referenceStrength,
          help: Help.charRefStrength,
          value: item.strength,
          divisions: 100,
          onCommit: (v) => notifier.updateCharRef(item.id, strength: v),
        ),
        const SizedBox(height: 6),
        LiveParamSlider(
          label: context.l10n.fidelity,
          help: Help.fidelity,
          value: item.infoExtracted,
          divisions: 100,
          onCommit: (v) => notifier.updateCharRef(item.id, infoExtracted: v),
        ),
      ],
    );
  }
}

/// 迁移模式:点击循环切换 角色 → 风格 → 角色&风格
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onTap});

  final CharRefMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cached, size: 15, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                switch (mode) {
                  CharRefMode.character => context.l10n.refCharacter,
                  CharRefMode.style => context.l10n.refStyle,
                  CharRefMode.both => context.l10n.refCharacterStyle,
                },
                style: context.texts.bodyMedium!.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

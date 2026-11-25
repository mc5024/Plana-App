import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/image_pick.dart';
import '../canvas_state.dart';
import '../generate_state.dart';
import '../models.dart';
import 'common.dart';
import 'section_card.dart';

/// 后台 isolate 算图片内容哈希(sha256 hex)。
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// 风格参考卡(Krea 2 专属):缩略图横条 + 选中详情,上方一条全局参考强度。
///
/// 壳照搬角色参考卡(同一套头栏、同一条缩略图行、同一个详情头),但功能是
/// 另一回事 —— 它走「参考图 + 官方风格参考 LoRA」,**只搬画风、不认角色**,
/// 因而没有迁移模式与保真度;强度也只有一份(那个 LoRA 的 strength),
/// 所以拎到列表上方,而不是每张一个。
class KreaStyleRefCard extends ConsumerStatefulWidget {
  const KreaStyleRefCard({super.key, this.reorderIndex});

  final int? reorderIndex;

  @override
  ConsumerState<KreaStyleRefCard> createState() => _KreaStyleRefCardState();
}

class _KreaStyleRefCardState extends ConsumerState<KreaStyleRefCard> {
  String? _selectedId;

  Future<void> _onAdd() async {
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final files = await pickImageFiles(context);
    if (files.isEmpty || !mounted) return;
    final notifier = ref.read(generateProvider.notifier);
    String? lastId;
    var dropped = 0;
    for (final f in files) {
      final hash = await compute(_sha256Hex, f.bytes); // 后台算内容哈希
      // 选图到加进来之间切走了画布:没加的就不加了
      if (!mounted || ref.read(canvasWorkspaceProvider).activeId != canvasId) {
        return;
      }
      final id = notifier.addKreaStyleRef(
        image: f.bytes,
        name: f.baseName,
        imageHash: hash,
      );
      // 满员按「先来的先留」丢弃:一次选多张时,先选中的才是他想要的那几张
      if (id.isEmpty) {
        dropped++;
      } else {
        lastId = id;
      }
    }
    if (!mounted) return;
    if (dropped > 0) {
      hintSnack(context, '最多 $kMaxKreaStyleRefs 张参考图,已忽略 $dropped 张');
    }
    if (lastId != null) setState(() => _selectedId = lastId);
  }

  void _remove(String id) {
    final refs = ref.read(generateProvider).kreaStyleRefs;
    final idx = refs.indexWhere((r) => r.id == id);
    ref.read(generateProvider.notifier).removeKreaStyleRef(id);
    final rest = ref.read(generateProvider).kreaStyleRefs;
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
    final refs = state.kreaStyleRefs;
    // 无内容时恒收起;头部「+」导入后(addKreaStyleRef 会 openPanel)自动展开。
    final expanded =
        state.openPanels.contains(Panel.kreaStyleRef) && refs.isNotEmpty;
    final full = refs.length >= kMaxKreaStyleRefs;

    KreaStyleRefItem? selected;
    for (final r in refs) {
      if (r.id == _selectedId) {
        selected = r;
        break;
      }
    }
    selected ??= refs.isNotEmpty ? refs.first : null;

    final activeCount = state.activeKreaStyleRefs.length;
    final isTurbo = kreaTierOf(state.params.model) == 'turbo';

    return SectionCard(
      icon: Icons.palette_outlined,
      title: '风格参考',
      reorderIndex: widget.reorderIndex,
      badge: refs.isEmpty
          ? null
          : CountBadge('${refs.length}/$kMaxKreaStyleRefs'),
      actions: [
        RoundIconBtn(
          Icons.add,
          tooltip: full ? '已达上限 $kMaxKreaStyleRefs 张,请先移除一张' : '导入风格参考图',
          color: full ? scheme.outline : scheme.primary,
          onTap: full
              ? () => hintSnack(context, '最多 $kMaxKreaStyleRefs 张参考图,请先移除一张')
              : _onAdd,
        ),
      ],
      expanded: expanded,
      onHeaderTap: refs.isEmpty
          ? _onAdd
          : () => notifier.togglePanel(Panel.kreaStyleRef),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Raw 档不拦,只提示:官方这个参考 LoRA 是在 Turbo 上训的,
          // 换到 Raw(后训练**之前**的基础检查点)权重分布对不上,实测会崩。
          if (activeCount > 0 && !isTurbo) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: InfoNote(
                    '官方风格参考 LoRA 基于 Turbo 档训练,Raw 档下画面易涂抹、透视塌陷。',
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
                TextButton(
                  onPressed: () => notifier.setModel('Krea 2 Turbo'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('切到 Turbo'),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
              onReorderItem: notifier.reorderKreaStyleRefs,
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
          const SizedBox(height: 14),
          // 强度是全局一份(所有参考图共用),所以不放进每张的详情里
          LiveParamSlider(
            label: 'Strength 参考强度',
            help: Help.kreaStyleRefStrength,
            value: state.kreaStyleRefWeight,
            max: kKreaStyleRefWeightMax,
            divisions: 40, // step 0.05
            onCommit: notifier.setKreaStyleRefWeight,
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            RefDetailHeader(
              index: refs.indexOf(selected) + 1,
              name: selected.name,
              enabled: selected.enabled,
              onRemove: () => _remove(selected!.id),
              enableToggle: RefEnableToggle(
                enabled: selected.enabled,
                onTap: () => notifier.setKreaStyleRefEnabled(
                  selected!.id,
                  !selected.enabled,
                ),
              ),
            ),
          ],
          // 多图的代价:实测 2 张起,参考图里的「物体」会被一并搬进画面
          if (activeCount >= 2) ...[
            const SizedBox(height: 12),
            const InfoNote(
              '同时启用多张时,参考图中的物体可能被一并带入画面。'
              '想要纯粹的画风迁移,建议只启用 1 张。',
            ),
          ],
        ],
      ),
    );
  }
}

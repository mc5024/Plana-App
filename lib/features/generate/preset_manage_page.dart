import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import 'prompt_presets.dart';
import 'widgets/common.dart';
import '../../core/util/haptics.dart';
import '../../l10n/l10n.dart';

/// 提示词预设管理页:激活切换 + 自定义增删改 + 长按拖动排序;默认预设只读可查看。
/// 入口:高级设置「管理预设」/ 我的页卡片。
class PromptPresetManagePage extends ConsumerWidget {
  const PromptPresetManagePage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    PromptPreset? preset,
  }) async {
    final r =
        await showModalBottomSheet<
          ({String name, String positive, String negative, bool suffix})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _PresetEditSheet(preset: preset),
        );
    if (r == null) return; // 取消 / 只读查看
    final n = ref.read(promptPresetsProvider.notifier);
    if (preset == null) {
      await n.add(
        name: r.name,
        positive: r.positive,
        negative: r.negative,
        suffixPositive: r.suffix,
      );
    } else {
      await n.updatePreset(
        preset.id,
        name: r.name,
        positive: r.positive,
        negative: r.negative,
        suffixPositive: r.suffix,
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PromptPreset p,
  ) async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.deletePreset,
      message: context.l10n.deletePresetBody(
        presetDisplayName(context.l10n, p),
      ),
      confirmLabel: context.l10n.delete,
    );
    if (!ok) return;
    await ref.read(promptPresetsProvider.notifier).remove(p.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final s = ref.watch(promptPresetsProvider).value;
    final activeId = ref.watch(activePromptPresetIdProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.promptPresets),
        actions: [
          IconButton(
            tooltip: context.l10n.newPreset,
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          // 长按整块拾起来拖 —— 不另立抓手:块上已经有两颗按钮,右边再添一根
          // 竖条,名字就没地方放了。顺序连高级设置那个下拉一起改。
          : ReorderableListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              buildDefaultDragHandles: false,
              proxyDecorator: dragProxy,
              onReorderStart: dragStartHaptic,
              onReorderEnd: dragEndHaptic,
              onReorderItem: (from, to) =>
                  ref.read(promptPresetsProvider.notifier).reorder(from, to),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 12),
                child: Text(
                  context.l10n.presetPageIntro,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              children: [
                for (var i = 0; i < s.presets.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(s.presets[i].id),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PresetTile(
                        preset: s.presets[i],
                        active: s.presets[i].id == activeId,
                        onTap: () {
                          Haptics.selection();
                          ref
                              .read(promptPresetsProvider.notifier)
                              .setActive(s.presets[i].id);
                        },
                        onEdit: () => _edit(context, ref, preset: s.presets[i]),
                        onDelete: s.presets[i].isDefault
                            ? null
                            : () => _delete(context, ref, s.presets[i]),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.active,
    required this.onTap,
    required this.onEdit,
    this.onDelete,
  });

  final PromptPreset preset;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: active
              ? BorderSide(color: scheme.primary, width: 1.4)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Icon(
                  active ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: active ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              presetDisplayName(context.l10n, preset),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodyMedium!.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (preset.isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              // 带系列的内置档直接报系列 —— 4.5 的 Light 和 V5 的
                              // Light 同名,只挂个「默认」两条会长得一模一样。
                              child: Text(
                                switch (preset.scope) {
                                  'v5' => 'V5',
                                  'legacy' => context.l10n.presetGroupLegacy,
                                  _ => context.l10n.presetGroupDefault,
                                },
                                style: context.texts.labelSmall!.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      if (preset.positive.isEmpty && preset.negative.isEmpty)
                        Text(
                          context.l10n.noPrefix,
                          style: context.texts.labelSmall!.copyWith(
                            color: scheme.outline,
                          ),
                        )
                      else ...[
                        if (preset.positive.isNotEmpty)
                          Text(
                            '+ ${preset.positive}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.labelSmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (preset.negative.isNotEmpty)
                          Text(
                            '- ${preset.negative}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.labelSmall!.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: preset.isDefault
                      ? context.l10n.view
                      : context.l10n.edit,
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: Icon(
                    preset.isDefault
                        ? Icons.visibility_outlined
                        : Icons.edit_outlined,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: context.l10n.delete,
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 19,
                      color: scheme.error.withValues(alpha: .85),
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

/// 新建 / 编辑 / 只读查看(默认预设)三合一 sheet。
/// controller 归 State 管(pop future 在退场动画时 resolve,外部 dispose 会崩)。
class _PresetEditSheet extends StatefulWidget {
  const _PresetEditSheet({this.preset});

  final PromptPreset? preset;

  @override
  State<_PresetEditSheet> createState() => _PresetEditSheetState();
}

class _PresetEditSheetState extends State<_PresetEditSheet> {
  late final TextEditingController nameCtl = TextEditingController(
    text: switch (widget.preset) {
      final p? => presetDisplayName(context.l10n, p),
      null => '',
    },
  );
  late final TextEditingController posCtl = TextEditingController(
    text: widget.preset?.positive ?? '',
  );
  late final TextEditingController negCtl = TextEditingController(
    text: widget.preset?.negative ?? '',
  );

  /// 正向拼在末尾。存量自定义预设没这个键 → false(前缀),与改动前一致。
  late bool _suffix = widget.preset?.suffixPositive ?? false;

  bool get _readOnly => widget.preset?.isDefault ?? false;

  @override
  void dispose() {
    nameCtl.dispose();
    posCtl.dispose();
    negCtl.dispose();
    super.dispose();
  }

  /// 正向拼在提示词开头还是末尾。
  ///
  /// 官方从 V4 起把质量词放末尾,内置档已照此;自定义档由用户自己定 ——
  /// 有人的档是画风串而不是质量词,那种放开头才对。
  Widget _placementRow(ColorScheme scheme) {
    Widget seg(String label, bool sel, VoidCallback onTap) => Expanded(
      child: InkWell(
        onTap: _readOnly ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: sel ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.texts.labelMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: _readOnly
                  ? scheme.onSurfaceVariant.withValues(alpha: .5)
                  : sel
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.placement,
            style: context.texts.labelMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          width: 152,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                seg(
                  context.l10n.placementStart,
                  !_suffix,
                  () => setState(() => _suffix = false),
                ),
                seg(
                  context.l10n.placementEnd,
                  _suffix,
                  () => setState(() => _suffix = true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctl, {
    bool multiline = false,
  }) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelMedium!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctl,
          readOnly: _readOnly,
          minLines: multiline ? 2 : 1,
          maxLines: multiline ? 6 : 1,
          style: multiline ? mono(context, size: 13) : null,
          decoration: InputDecoration(
            isDense: true,
            hintText: multiline
                ? context.l10n.emptyHint
                : context.l10n.presetName,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final title = _readOnly
        ? context.l10n.viewPreset
        : widget.preset == null
        ? context.l10n.newPreset
        : context.l10n.editPreset;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.texts.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_readOnly) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.defaultPresetReadOnly,
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
          ],
          const SizedBox(height: 14),
          _field(context.l10n.name, nameCtl),
          const SizedBox(height: 12),
          _field(
            _suffix ? context.l10n.positiveSuffix : context.l10n.positivePrefix,
            posCtl,
            multiline: true,
          ),
          const SizedBox(height: 8),
          _placementRow(scheme),
          const SizedBox(height: 12),
          // 负向没有这个选择:官方一律前缀,我们也从没变过
          _field(context.l10n.negativePrefix, negCtl, multiline: true),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  _readOnly ? context.l10n.close : context.l10n.cancel,
                ),
              ),
              if (!_readOnly) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = nameCtl.text.trim();
                    Navigator.pop(context, (
                      name: name.isEmpty ? '未命名' : name,
                      positive: posCtl.text.trim(),
                      negative: negCtl.text.trim(),
                      suffix: _suffix,
                    ));
                  },
                  child: Text(context.l10n.save),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

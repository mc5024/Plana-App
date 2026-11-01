import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart';
import '../generate/widgets/common.dart' show hintSnack;
import '../generate/widgets/lora_card.dart' show LoraThumb;
import 'lora_providers.dart';
import 'lora_stacks.dart';

/// 「保存为 LoRA 堆」:起名,把当前画布已挂的 LoRA 连同参数存成一个堆。
/// LoRA 卡头和管理器「LoRA 堆」页共用。
Future<void> showSaveLoraStackDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final loras = ref.read(generateProvider).loras;
  final base = ref.read(loraBaseProvider);
  final stacks = ref.read(loraStacksProvider.notifier);
  final entries = stackEntriesFromActive(loras);
  if (entries.isEmpty) return;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _SaveLoraStackDialog(loras: loras, base: base),
  );
  if (name == null || name.trim().isEmpty) return;
  final r = await stacks.save(name: name, base: base, loras: entries);
  if (!context.mounted) return;
  hintSnack(
    context,
    r.replaced ? '已覆盖 LoRA 堆「${r.stack.name}」' : '已保存 LoRA 堆「${r.stack.name}」',
    icon: Icons.layers_outlined,
  );
}

/// 权重读数:去掉末尾的 0(0.80 → 0.8,1.00 → 1)。
String loraStackNum(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _SaveLoraStackDialog extends ConsumerStatefulWidget {
  const _SaveLoraStackDialog({required this.loras, required this.base});

  /// 当前已挂列表(含下载中的占位条,这里滤掉)。
  final List<ActiveLora> loras;
  final String base;

  @override
  ConsumerState<_SaveLoraStackDialog> createState() =>
      _SaveLoraStackDialogState();
}

class _SaveLoraStackDialogState extends ConsumerState<_SaveLoraStackDialog> {
  late final List<ActiveLora> _ready = [
    for (final l in widget.loras)
      if (l.pending == null) l,
  ];
  late final _ctl = () {
    final text = defaultLoraStackName(widget.loras);
    return TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctl.text.trim().isEmpty) return;
    Navigator.pop(context, _ctl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final all = ref.watch(loraStacksProvider).value ?? const <LoraStack>[];
    final trimmed = _ctl.text.trim();
    final clash =
        trimmed.isNotEmpty &&
        ref
                .read(loraStacksProvider.notifier)
                .findByName(all, widget.base, trimmed) !=
            null;
    final pendingCount = widget.loras.length - _ready.length;
    final small = context.texts.labelSmall!.copyWith(color: scheme.outline);

    return AlertDialog(
      title: const Text('保存为 LoRA 堆'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            maxLength: kLoraStackNameMax,
            decoration: const InputDecoration(labelText: '名称'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (clash)
            Text(
              '已有同名的 LoRA 堆,保存会覆盖它',
              style: context.texts.labelSmall!.copyWith(color: scheme.tertiary),
            ),
          const SizedBox(height: 12),
          Text('包含 ${_ready.length} 个 LoRA', style: small),
          const SizedBox(height: 6),
          for (final l in _ready) ...[
            _EntryRow(lora: l),
            const SizedBox(height: 6),
          ],
          if (pendingCount > 0)
            Text('还在下载的 $pendingCount 个不会存进去', style: small),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: trimmed.isEmpty ? null : _submit,
          child: Text(clash ? '覆盖保存' : '保存'),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.lora});

  final ActiveLora lora;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final clip = lora.clipWeight != null && lora.hasTe != false
        ? ' c${loraStackNum(lora.clipWeight!)}'
        : '';
    return Row(
      children: [
        Opacity(
          opacity: lora.enabled ? 1 : .4,
          child: LoraThumb(lora.previewUrl, size: 28),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            lora.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall!.copyWith(
              color: lora.enabled ? scheme.onSurface : scheme.outline,
              decoration: lora.enabled ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'w${loraStackNum(lora.weight)}$clip',
          style: mono(
            context,
            size: 11,
            color: lora.enabled ? scheme.onSurfaceVariant : scheme.outline,
          ),
        ),
      ],
    );
  }
}

/// 管理器「LoRA 堆」页的一张卡:叠放缩略图 · 名称与条数 · 应用 / 删除,
/// 底下逐条列名字与权重。[installed] 为 null = 库还没读到,不标缺失。
class LoraStackCard extends StatelessWidget {
  const LoraStackCard({
    super.key,
    required this.stack,
    required this.installed,
    required this.onApply,
    required this.onDelete,
  });

  final LoraStack stack;
  final Set<String>? installed;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  bool _gone(LoraStackEntry e) =>
      installed != null && !installed!.contains(e.name);

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final label = context.texts.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final missing = stack.loras.where(_gone).length;
    return Lifted(
      radius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 6, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StackThumbs(
                  urls: [for (final e in stack.loras.take(3)) e.previewUrl],
                  ring: scheme.surfaceContainerLow,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stack.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${stack.loras.length} 个 LoRA'),
                            if (missing > 0)
                              TextSpan(
                                text: ' · $missing 个已不在库里',
                                style: TextStyle(color: scheme.error),
                              ),
                          ],
                        ),
                        style: label,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.tonal(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('应用'),
                ),
                IconButton(
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final e in stack.loras) _EntryChip(e, gone: _gone(e)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 前几张缩略图错开叠放。
class _StackThumbs extends StatelessWidget {
  const _StackThumbs({required this.urls, required this.ring});

  final List<String> urls;
  final Color ring;

  static const _size = 38.0;
  static const _step = 22.0;
  static const _ringW = 2.0;

  @override
  Widget build(BuildContext context) {
    final n = urls.isEmpty ? 1 : urls.length;
    return SizedBox(
      width: _size + (n - 1) * _step,
      height: _size,
      child: Stack(
        children: [
          for (var i = n - 1; i >= 0; i--)
            Positioned(
              left: i * _step,
              child: Container(
                padding: const EdgeInsets.all(_ringW),
                decoration: BoxDecoration(
                  color: ring,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: LoraThumb(
                  urls.isEmpty ? '' : urls[i],
                  size: _size - _ringW * 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryChip extends StatelessWidget {
  const _EntryChip(this.entry, {required this.gone});

  final LoraStackEntry entry;
  final bool gone;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final off = !entry.enabled && !gone;
    final fg = gone
        ? scheme.error
        : entry.enabled
        ? scheme.onSurface
        : scheme.outline;
    final clip = entry.clipWeight != null
        ? ' c${loraStackNum(entry.clipWeight!)}'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: gone
            ? scheme.error.withValues(alpha: .08)
            : scheme.surfaceContainerHigh.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall!.copyWith(
                color: fg,
                decoration: off ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'w${loraStackNum(entry.weight)}$clip',
            style: mono(context, size: 10, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

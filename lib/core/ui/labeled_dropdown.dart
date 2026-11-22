import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/haptics.dart';

/// 带前置标签的紧凑下拉(与高级设置里预设那一栏同款外壳)。
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<({T value, String text})> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(12),
        style: context.texts.bodyMedium!.copyWith(color: scheme.onSurface),
        items: [
          for (final e in items)
            DropdownMenuItem(
              value: e.value,
              child: Text(e.text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          Haptics.selection();
          onChanged(v);
        },
      ),
    );
  }
}

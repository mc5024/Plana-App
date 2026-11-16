/// 图像模型的分辨率 / 比例怎么选:和「对话模式」同一种弹层、同一种行,第一行是「自动」。
/// 这个模型出不了的档照列、压淡、点不动。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/setting_row.dart';
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../../../l10n/l10n.dart';

/// 选中的值,空串 = 自动;没选就关掉的是 null。
Future<String?> showImageOptionSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> available,
  required String current,
}) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => _OptionSheet(
      title: title,
      options: options,
      available: available,
      current: current,
    ),
  );
  dropFocusSoon();
  return picked;
}

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.available,
    required this.current,
  });

  final String title;
  final List<String> options;
  final List<String> available;
  final String current;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final solid = context.skin.float;
    final selFg = solid ? scheme.onPrimary : scheme.primary;
    Widget row(String value, String label) {
      final selected = value == current;
      final enabled = value.isEmpty || available.contains(value);
      return ListTile(
        onTap: enabled ? () => Navigator.pop(context, value) : null,
        enabled: enabled,
        selected: selected,
        selectedTileColor: solid
            ? scheme.primary
            : scheme.primaryContainer.withValues(alpha: .35),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 21,
          color: selected ? selFg : null,
        ),
        title: Text(
          label,
          style: context.texts.bodyLarge!.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? selFg : null,
          ),
        ),
      );
    }

    return SettingSheet(
      title: title,
      children: [
        row('', context.l10n.settingAuto),
        for (final o in options) row(o, o),
      ],
    );
  }
}

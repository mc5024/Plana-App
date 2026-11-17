/// 图像模型的分辨率 / 比例 / 张数怎么选:和「对话模式」同一种弹层、同一种行,
/// 分辨率 / 比例第一行是「自动」,下面只列这个模型出得了的档。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/setting_row.dart';
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../../../l10n/l10n.dart';

/// 选中的值,空串 = 自动;没选就关掉的是 null。[labelOf] 是行上的字,默认写值本身。
Future<String?> showImageOptionSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String current,
  bool auto = true,
  String Function(String)? labelOf,
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
      current: current,
      auto: auto,
      labelOf: labelOf,
    ),
  );
  dropFocusSoon();
  return picked;
}

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.auto,
    this.labelOf,
  });

  final String title;
  final List<String> options;
  final String current;
  final bool auto;
  final String Function(String)? labelOf;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final solid = context.skin.float;
    final selFg = solid ? scheme.onPrimary : scheme.primary;
    Widget row(String value, String label) {
      final selected = value == current;
      return ListTile(
        onTap: () => Navigator.pop(context, value),
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
        if (auto) row('', context.l10n.imageAuto),
        for (final o in options) row(o, labelOf?.call(o) ?? o),
      ],
    );
  }
}

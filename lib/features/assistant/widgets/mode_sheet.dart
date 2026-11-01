/// 选对话模式:无 / 漫画模式 / 仅自然语言。
///
/// 和「选择模型」同一种弹层、同一种行:选中那行的图标换成对勾、整行染色,点一下就关。
/// 原先是贴着按钮往上弹的菜单,位置靠手算,离输入框和键盘太近,弹出来的位置和样子
/// 都和这一页别的选择对不上。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/setting_row.dart';
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../assistant_mode.dart';

IconData assistantModeIcon(AssistantMode m, {bool on = false}) => switch (m) {
  AssistantMode.normal => Icons.layers_clear_outlined,
  AssistantMode.comic => on ? Icons.view_quilt : Icons.view_quilt_outlined,
  AssistantMode.natural => on ? Icons.notes : Icons.notes_outlined,
};

/// 选中的模式;没选就关掉的是 null。
Future<AssistantMode?> showModeSheet(
  BuildContext context, {
  required AssistantMode current,
}) async {
  final picked = await showModalBottomSheet<AssistantMode>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => _ModeSheet(current: current),
  );
  // 只是来切个模式,别顺手把软键盘顶出来
  dropFocusSoon();
  return picked;
}

class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.current});

  final AssistantMode current;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final solid = context.skin.float;
    final selFg = solid ? scheme.onPrimary : scheme.primary;
    return SettingSheet(
      title: '对话模式',
      children: [
        for (final m in AssistantMode.values)
          ListTile(
            onTap: () => Navigator.pop(context, m),
            selected: m == current,
            selectedTileColor: solid
                ? scheme.primary
                : scheme.primaryContainer.withValues(alpha: .35),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(
              m == current ? Icons.check_circle : assistantModeIcon(m),
              size: 21,
              color: m == current ? selFg : null,
            ),
            title: Text(
              assistantModeLabel(m),
              style: context.texts.bodyLarge!.copyWith(
                fontWeight: m == current ? FontWeight.w700 : FontWeight.w500,
                color: m == current ? selFg : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// 第一次打开 AI 助手时的引导:把几项使用习惯定下来。
///
/// 要点过「开始使用」才算走完;走完之前每次进 AI 页都会弹。
/// 这里定的几项之后都能在「助手设置」里改,两边用的是同一份设置和同样的文字。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/setting_row.dart';
import '../assistant_settings.dart';
import '../../../l10n/l10n.dart';

Future<void> showAssistantIntro(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _IntroDialog(),
);

class _IntroDialog extends ConsumerStatefulWidget {
  const _IntroDialog();

  @override
  ConsumerState<_IntroDialog> createState() => _IntroDialogState();
}

class _IntroDialogState extends ConsumerState<_IntroDialog> {
  /// 先在这份草稿上改,点「开始使用」才一起存 —— 中途退出不留半截设置。
  late AssistantSettings _draft =
      ref.read(assistantSettingsProvider).value ?? const AssistantSettings();

  void _edit(AssistantSettings Function(AssistantSettings) change) =>
      setState(() => _draft = change(_draft));

  Future<void> _done() async {
    await ref
        .read(assistantSettingsProvider.notifier)
        .patch(
          (o) => o.copyWith(
            autoGenerate: _draft.autoGenerate,
            inlineImage: _draft.inlineImage,
            autoImport: _draft.autoImport,
            introVersion: kAssistantIntroVersion,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // 点过「开始使用」才算走完,按返回不关
    canPop: false,
    child: AlertDialog(
      // 边距比默认的 40 小,弹窗宽一点,开关那几行的标题少折一次行
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(context.l10n.startUsingAssistant),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            settingSection(context, context.l10n.usageHabits),
            SettingRow(
              icon: Icons.bolt_outlined,
              title: context.l10n.autoDraw,
              desc: context.l10n.autoDrawDesc,
              value: _draft.autoGenerate,
              onChanged: (v) => _edit((o) => o.copyWith(autoGenerate: v)),
            ),
            SettingRow(
              icon: Icons.image_outlined,
              title: context.l10n.inlineImages,
              desc: context.l10n.inlineImagesDesc,
              value: _draft.inlineImage,
              onChanged: (v) => _edit((o) => o.copyWith(inlineImage: v)),
            ),
            SettingRow(
              icon: Icons.draw_outlined,
              title: context.l10n.autoWrite,
              desc: context.l10n.autoWriteDesc,
              value: _draft.autoImport,
              onChanged: (v) => _edit((o) => o.copyWith(autoImport: v)),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: _done, child: Text(context.l10n.getStarted)),
      ],
    ),
  );
}

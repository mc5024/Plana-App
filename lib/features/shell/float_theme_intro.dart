/// 浮卡主题的一次性介绍:升级上来的用户进主界面弹一次,点「试试」直接换上。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/store/prefs_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_settings.dart';
import '../../core/ui/theme_swatches.dart';
import '../generate/widgets/common.dart' show hintSnack;

const _kSeenKey = 'float_theme_intro_seen';

/// 换上后先在反向深浅色停这么久再切回。
const _kFlipHold = Duration(milliseconds: 1500);

bool needsFloatThemeIntro(PrefsStore prefs) => prefs.get(_kSeenKey) == null;

/// 欢迎页里能直接选浮卡,走过欢迎页的不再弹。
void markFloatThemeIntroSeen(PrefsStore prefs) =>
    unawaited(prefs.write(key: _kSeenKey, value: '1'));

Future<void> showFloatThemeIntro(BuildContext context, WidgetRef ref) async {
  markFloatThemeIntroSeen(ref.read(prefsStoreProvider));
  final before = ref.read(themeSettingsProvider);
  if (before.float) return;
  final picked = await showDialog<FloatAccent>(
    context: context,
    builder: (_) => const _IntroDialog(),
  );
  if (picked == null || !context.mounted) return;
  final notifier = ref.read(themeSettingsProvider.notifier);
  final dark = switch (before.mode) {
    ThemeMode.light => false,
    ThemeMode.dark => true,
    ThemeMode.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark,
  };
  notifier.patch(
    (x) => x.copyWith(
      seedKey: floatThemeKey(picked),
      mode: dark ? ThemeMode.light : ThemeMode.dark,
    ),
  );
  await Future<void>.delayed(_kFlipHold);
  notifier.patch((x) => x.copyWith(mode: before.mode));
  if (!context.mounted) return;
  hintSnack(
    context,
    '已换成浮卡,可在「外观与触感」换回',
    icon: Icons.palette_outlined,
    actionLabel: '换回',
    onAction: () => notifier.patch((x) => x.copyWith(seedKey: before.seedKey)),
  );
}

class _IntroDialog extends StatefulWidget {
  const _IntroDialog();

  @override
  State<_IntroDialog> createState() => _IntroDialogState();
}

class _IntroDialogState extends State<_IntroDialog> {
  FloatAccent _picked = kFloatBlue;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: const Text('试试新主题？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('全新外观上线啦!卡片更清爽,挑个喜欢的吧~'),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final a in floatAccents)
                ThemeSwatch(
                  label: '浮卡 ${a.label}',
                  size: 42,
                  selected: a == _picked,
                  fill: floatSwatchFill(a),
                  checkColor: Colors.white,
                  onTap: () => setState(() => _picked = a),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('以后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_picked),
          child: const Text('试试'),
        ),
      ],
    );
  }
}

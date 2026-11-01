import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/theme_settings.dart';

/// 主题色色板:上行浮卡各档,下行种子档位,点选即时换肤。外观页和欢迎页共用。
class ThemeSwatches extends ConsumerWidget {
  const ThemeSwatches({
    super.key,
    this.size = 44,
    this.alignment = WrapAlignment.start,
  });

  final double size;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);
    final current = ts.float ? ts.seedKey : ts.seed.key;
    void pick(String key) => notifier.patch((x) => x.copyWith(seedKey: key));
    Widget row(List<Widget> children) => Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: alignment,
      children: children,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment == WrapAlignment.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        row([
          for (final a in floatAccents)
            ThemeSwatch(
              label: '浮卡 ${a.label}',
              size: size,
              selected: current == floatThemeKey(a),
              fill: floatSwatchFill(a),
              checkColor: Colors.white,
              onTap: () => pick(floatThemeKey(a)),
            ),
        ]),
        const SizedBox(height: 14),
        row([
          for (final s in themeSeeds)
            ThemeSwatch(
              label: s.label,
              size: size,
              selected: current == s.key,
              fill: BoxDecoration(color: s.color, shape: BoxShape.circle),
              checkColor:
                  ThemeData.estimateBrightnessForColor(s.color) ==
                      Brightness.dark
                  ? Colors.white
                  : Colors.black87,
              onTap: () => pick(s.key),
            ),
        ]),
      ],
    );
  }
}

/// 浮卡档位的色块:斜分两半,深色 / 浅色两套主色。
BoxDecoration floatSwatchFill(FloatAccent a) => BoxDecoration(
  shape: BoxShape.circle,
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [.5, .5],
    colors: [a.dark, a.light],
  ),
);

class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({
    super.key,
    required this.label,
    required this.size,
    required this.selected,
    required this.fill,
    required this.checkColor,
    required this.onTap,
  });

  final String label;
  final double size;
  final bool selected;
  final BoxDecoration fill;
  final Color checkColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: Motion.fast,
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: 2,
              color: selected ? scheme.onSurface : Colors.transparent,
            ),
          ),
          child: DecoratedBox(
            decoration: fill,
            child: selected
                ? Icon(Icons.check, size: 18, color: checkColor)
                : null,
          ),
        ),
      ),
    );
  }
}

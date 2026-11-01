import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show Hct, SchemeTonalSpot;

import '../ui/slide_back_transitions.dart';
import 'app_skin.dart';

/// 浮卡主题的一档主色。主色的色度、明度与蓝色对齐,只换色相;深色底是把
/// 「夜空」各层转到同一色相。
class FloatAccent {
  const FloatAccent(this.key, this.label, this.light, this.dark, this.onDark);

  final String key;
  final String label;

  /// 浅色主色(上面放白字)
  final Color light;

  /// 深色主色及其上的字色
  final Color dark;
  final Color onDark;
}

const kFloatBlue = FloatAccent(
  'blue',
  '蓝',
  Color(0xFF1F80C6),
  Color(0xFF6CB8F6),
  Color(0xFF06223D),
);

/// 浮卡档位,按色环排列。
const floatAccents = <FloatAccent>[
  FloatAccent(
    'orange',
    '橙',
    Color(0xFFC15F36),
    Color(0xFFFF966C),
    Color(0xFF3A1708),
  ),
  FloatAccent(
    'rose',
    '粉',
    Color(0xFFBF5A7C),
    Color(0xFFFA92B2),
    Color(0xFF391521),
  ),
  FloatAccent(
    'violet',
    '紫',
    Color(0xFF896AC7),
    Color(0xFFC0A3FA),
    Color(0xFF261B3C),
  ),
  kFloatBlue,
  FloatAccent(
    'green',
    '绿',
    Color(0xFF008D62),
    Color(0xFF5CC497),
    Color(0xFF002718),
  ),
];

/// 全局主题。当前阶段使用 M3 默认配色(基准种子色),
/// 组件一律走语义角色(primary/surfaceContainer* 等),
/// 将来切 NAI 品牌皮肤时只需替换这里的 ColorScheme。
abstract final class AppTheme {
  /// 默认种子色:浅蓝(与「外观」页 sky 档一致,可在那里换其他种子)。
  static const Color seed = Color(0xFF4FA3E3);

  static ThemeData light([Color? seedColor]) =>
      _build(Brightness.light, seedColor ?? seed);

  static ThemeData dark([Color? seedColor]) =>
      _build(Brightness.dark, seedColor ?? seed);

  /// 浮卡:固定配色,不走种子取色,[accent] 只换主色。
  /// 浅色:页面浅灰,卡片 / 弹层白(Low);卡内凹槽 / 按钮(Container / High /
  /// Highest)比页面深一档。深色:夜空(蓝色为海军蓝,其余转到各自色相),
  /// 卡片比页面亮一档、带细边。选中态为实心主色;次级按钮(secondaryContainer)为凹槽灰;
  /// 底栏白底无胶囊。
  static ThemeData float(
    Brightness brightness, [
    FloatAccent accent = kFloatBlue,
  ]) {
    final dark = brightness == Brightness.dark;
    final scheme = _floatScheme(accent, dark);
    final base = _theme(scheme);
    Color navColor(Set<WidgetState> s) => s.contains(WidgetState.selected)
        ? scheme.primary
        : scheme.onSurfaceVariant;
    bool on(Set<WidgetState> s) =>
        s.contains(WidgetState.selected) && !s.contains(WidgetState.disabled);
    Color onControl(Set<WidgetState> s) {
      if (s.contains(WidgetState.disabled)) {
        return scheme.onSurface.withValues(alpha: .38);
      }
      return on(s) ? scheme.onPrimary : scheme.onSurfaceVariant;
    }

    return base.copyWith(
      extensions: [
        !dark
            ? AppSkin.floatLight
            : accent == kFloatBlue
            ? AppSkin.floatDark
            : AppSkin(
                float: true,
                edge: _nightHue(AppSkin.floatDark.edge!, accent),
              ),
      ],
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: navColor(s)),
        ),
        // 选中加粗;中文标签不留字距
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => base.textTheme.labelMedium!.copyWith(
            color: navColor(s),
            letterSpacing: 0,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      // 分段按钮:凹槽底、无描边,选中实心主色
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => on(s) ? scheme.primary : scheme.surfaceContainerHigh,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(onControl),
          iconColor: WidgetStateProperty.resolveWith(onControl),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primary,
        checkmarkColor: scheme.onPrimary,
        labelStyle: base.textTheme.labelLarge!.copyWith(
          color: WidgetStateColor.resolveWith(onControl),
        ),
      ),
      // 下面几处 M3 默认取 Container / High,在这套里是凹槽灰,改成卡片白
      dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerLow),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
      ),
      popupMenuTheme: PopupMenuThemeData(color: scheme.surfaceContainerLow),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        inactiveTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  /// 浮卡浅色卡内凹槽 / 按钮的灰。
  static const Color _floatGrey = Color(0xFFEBEDF0);

  /// 蓝色原样;其余主色容器色取自各自种子,深色底转到各自色相。
  /// 第三色(点数胶囊、计数徽章的粉)照种子主题的取法:蓝色取旧版浅蓝档,
  /// 其余取各自种子。
  static ColorScheme _floatScheme(FloatAccent a, bool dark) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final tert = ColorScheme.fromSeed(
      seedColor: a == kFloatBlue ? seed : a.light,
      brightness: brightness,
    );
    final base = (dark ? _floatDark : _floatLight).copyWith(
      tertiary: tert.tertiary,
      onTertiary: tert.onTertiary,
      tertiaryContainer: tert.tertiaryContainer,
      onTertiaryContainer: tert.onTertiaryContainer,
      tertiaryFixed: tert.tertiaryFixed,
      tertiaryFixedDim: tert.tertiaryFixedDim,
      onTertiaryFixed: tert.onTertiaryFixed,
      onTertiaryFixedVariant: tert.onTertiaryFixedVariant,
    );
    if (a == kFloatBlue) return base;
    final own = ColorScheme.fromSeed(
      seedColor: a.light,
      brightness: brightness,
    );
    final s = base.copyWith(
      primary: dark ? a.dark : a.light,
      onPrimary: dark ? a.onDark : const Color(0xFFFFFFFF),
      primaryContainer: own.primaryContainer,
      onPrimaryContainer: own.onPrimaryContainer,
      primaryFixed: own.primaryFixed,
      primaryFixedDim: own.primaryFixedDim,
      onPrimaryFixed: own.onPrimaryFixed,
      onPrimaryFixedVariant: own.onPrimaryFixedVariant,
      surfaceTint: own.surfaceTint,
      inversePrimary: dark ? a.light : a.dark,
    );
    if (!dark) return s;
    Color n(Color c) => _nightHue(c, a);
    return s.copyWith(
      secondary: n(s.secondary),
      onSecondary: n(s.onSecondary),
      secondaryContainer: n(s.secondaryContainer),
      onSecondaryContainer: n(s.onSecondaryContainer),
      surface: n(s.surface),
      surfaceBright: n(s.surfaceBright),
      surfaceContainerLowest: n(s.surfaceContainerLowest),
      surfaceContainerLow: n(s.surfaceContainerLow),
      surfaceContainer: n(s.surfaceContainer),
      surfaceContainerHigh: n(s.surfaceContainerHigh),
      surfaceContainerHighest: n(s.surfaceContainerHighest),
      onSurface: n(s.onSurface),
      onSurfaceVariant: n(s.onSurfaceVariant),
      outline: n(s.outline),
      outlineVariant: n(s.outlineVariant),
    );
  }

  /// 夜空里的一色转到 [a] 的色相(按两档主色的色相差平移),色度、明度不变。
  static Color _nightHue(Color c, FloatAccent a) {
    final shift =
        Hct.fromInt(a.light.toARGB32()).hue -
        Hct.fromInt(kFloatBlue.light.toARGB32()).hue;
    final h = Hct.fromInt(c.toARGB32());
    return Color(Hct.from((h.hue + shift) % 360, h.chroma, h.tone).toInt());
  }

  static final ColorScheme _floatLight =
      ColorScheme.fromSeed(seedColor: kFloatBlue.light).copyWith(
        primary: kFloatBlue.light,
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFCEE5FF),
        onPrimaryContainer: const Color(0xFF00466E),
        secondary: const Color(0xFF5B6A79),
        onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: _floatGrey,
        onSecondaryContainer: const Color(0xFF14191F),
        surface: const Color(0xFFF3F4F6),
        surfaceBright: const Color(0xFFFFFFFF),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFFFFFFF),
        surfaceContainer: _floatGrey,
        surfaceContainerHigh: _floatGrey,
        surfaceContainerHighest: _floatGrey,
        onSurface: const Color(0xFF14191F),
        onSurfaceVariant: const Color(0xFF4A515B),
        outline: const Color(0xFF6B727C),
        outlineVariant: const Color(0xFFDADEE4),
        inverseSurface: const Color(0xFF2B3136),
        onInverseSurface: const Color(0xFFEFF1F5),
        inversePrimary: kFloatBlue.dark,
      );

  static final ColorScheme _floatDark =
      ColorScheme.fromSeed(
        seedColor: kFloatBlue.light,
        brightness: Brightness.dark,
      ).copyWith(
        primary: kFloatBlue.dark,
        onPrimary: kFloatBlue.onDark,
        primaryContainer: const Color(0xFF004A76),
        onPrimaryContainer: const Color(0xFFD0E5FD),
        secondary: const Color(0xFFAEBDCF),
        onSecondary: const Color(0xFF1F2D3B),
        secondaryContainer: const Color(0xFF0B1220),
        onSecondaryContainer: const Color(0xFFE6EDF7),
        surface: const Color(0xFF0B1220),
        surfaceBright: const Color(0xFF141D2E),
        surfaceContainerLowest: const Color(0xFF141D2E),
        surfaceContainerLow: const Color(0xFF141D2E),
        surfaceContainer: const Color(0xFF0B1220),
        surfaceContainerHigh: const Color(0xFF0B1220),
        surfaceContainerHighest: const Color(0xFF0B1220),
        onSurface: const Color(0xFFE6EDF7),
        onSurfaceVariant: const Color(0xFF9DAAC0),
        outline: const Color(0xFF718099),
        outlineVariant: const Color(0xFF22304A),
        inverseSurface: const Color(0xFFE1E2E6),
        onInverseSurface: const Color(0xFF2B3136),
        inversePrimary: kFloatBlue.light,
      );

  static ThemeData _build(Brightness brightness, Color seedColor) => _theme(
    _widenSurfaces(
      ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness),
      seedColor,
      brightness,
    ),
  );

  static ThemeData _theme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 中日文也用西文那套字形几何(默认会换成 ideographic 基线),换语言不动版式
      typography: Typography.material2021(
        platform: defaultTargetPlatform,
        colorScheme: scheme,
        dense: Typography.englishLike2021,
      ),
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surfaceContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      // 二级页左右滑动,不跟手(见 SlideBackPageTransitionsBuilder)。
      // 默认那套预测性返回松手后页面直接消失,和进场动画接不上。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: SlideBackPageTransitionsBuilder()},
      ),
    );
  }

  /// M3 默认 surface 阶梯太贴(暗色 背景N6/卡片N10,亮色 背景N98/卡片N96),
  /// 层级观感弱。用种子的中性调色板重排一条间距更大的阶梯:
  /// 暗色 背景压深、容器逐级提亮;亮色改「灰底白卡」,容器逐级压灰。
  static ColorScheme _widenSurfaces(
    ColorScheme s,
    Color seedColor,
    Brightness brightness,
  ) {
    // 与 fromSeed 同源:默认变体 tonalSpot 的中性调色板
    final neutral = SchemeTonalSpot(
      sourceColorHct: Hct.fromInt(seedColor.toARGB32()),
      isDark: brightness == Brightness.dark,
      contrastLevel: 0.0,
    ).neutralPalette;
    Color t(int tone) => Color(neutral.get(tone));
    return brightness == Brightness.dark
        ? s.copyWith(
            surface: t(4),
            surfaceContainerLowest: t(2),
            surfaceContainerLow: t(12),
            surfaceContainer: t(18),
            surfaceContainerHigh: t(24),
            surfaceContainerHighest: t(30),
          )
        : s.copyWith(
            surface: t(96),
            surfaceContainerLowest: t(100),
            surfaceContainerLow: t(100),
            surfaceContainer: t(92),
            surfaceContainerHigh: t(89),
            surfaceContainerHighest: t(86),
          );
  }
}

/// 固定语义色 —— **不跟随种子色**。
///
/// 何时用这里、何时用 `scheme.tertiary` / `scheme.error`:
/// 元素若压在**图片或固定浅色背景**上(状态圆点、图库角标、可视化画布的
/// 参考线),跟着种子色走会在某些配色下失去对比,必须用固定值;其余一律走
/// M3 语义角色。
///
/// 集中在此的原因:早先这些色散落在四个功能文件里各自 `const` 定义,
/// 同一个「可用/免费」语义漂成了三个不同的绿(2E9E44 / 2E9E57 / 2E7D32),
/// 用户在不同页面看到的是三种颜色。
abstract final class FixedSemantic {
  /// 可用 / 免费 / 已完成
  static const ok = Color(0xFF2E9E57);

  /// 缺条件 / 不可用(但非错误)
  static const warn = Color(0xFFE8890C);

  /// 超限 / 错误
  static const danger = Color(0xFFE0413F);

  /// 重绘(图库角标)
  static const inpaint = Color(0xFF7E57C2);

  /// 打码(图库角标)。与重绘同为「派生品」,取冷灰蓝拉开区分。
  static const censor = Color(0xFF546E7A);
}

/// 便捷访问
extension ThemeX on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}

/// 等宽数字(参数读数、token 计数用)
TextStyle mono(
  BuildContext context, {
  double size = 12,
  FontWeight weight = FontWeight.w600,
  Color? color,
}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontFeatures: const [FontFeature.tabularFigures()],
    fontSize: size,
    fontWeight: weight,
    color: color ?? context.scheme.onSurface,
  );
}

/// 浮动药丸里的滑杆外观:细轨 + 小滑块 + 无水波。
/// M3 默认的滑杆压在画布/列表上太抢戏,而这些地方读数才是主角。
final compactSliderTheme = SliderThemeData(
  padding: EdgeInsets.zero,
  trackHeight: 3,
  thumbSize: const WidgetStatePropertyAll(Size(14, 14)),
  overlayShape: SliderComponentShape.noOverlay,
);

/// M3 动效时长/曲线的统一出口,页面内所有过渡保持一致节奏。
abstract final class Motion {
  static const Duration quick = Durations.short2; // 100ms(离场/关闭收得快)
  static const Duration fast = Durations.short4; // 200ms
  static const Duration medium = Durations.medium2; // 300ms
  static const Duration slow = Durations.medium4; // 400ms
  static const Curve emphasized = Easing.emphasizedDecelerate;
  static const Curve standard = Easing.standard;
}

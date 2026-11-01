import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 配色之外的组件外观。种子主题用 [AppSkin.standard];浮卡主题白卡靠发丝边
/// 托出,卡头图标放进主色方块,页面上的控件用白底。
@immutable
class AppSkin extends ThemeExtension<AppSkin> {
  const AppSkin({required this.float, this.edge});

  /// 浮卡样式
  final bool float;

  /// 卡片 / 底部区的发丝边
  final Color? edge;

  static const standard = AppSkin(float: false);

  static const floatLight = AppSkin(float: true, edge: Color(0x14101828));

  static const floatDark = AppSkin(float: true, edge: Color(0xFF26365A));

  @override
  AppSkin copyWith({bool? float, Color? edge}) =>
      AppSkin(float: float ?? this.float, edge: edge ?? this.edge);

  @override
  AppSkin lerp(AppSkin? other, double t) =>
      other == null || t < .5 ? this : other;
}

extension AppSkinX on BuildContext {
  AppSkin get skin => Theme.of(this).extension<AppSkin>() ?? AppSkin.standard;

  /// 浮卡样式的发丝边;其余主题 null。
  BoxBorder? get edgeBorder => switch (skin.edge) {
    final edge? => Border.all(color: edge),
    null => null,
  };

  /// 浮卡样式下换成卡片白,其余主题用 [standard]。
  Color raisedFill(Color standard) =>
      skin.float ? scheme.surfaceContainerLow : standard;

  /// 直接压在页面上的控件(搜索框、分类胶囊、头部按钮)的底色。
  Color get pageControlFill => raisedFill(scheme.surfaceContainerHigh);

  /// 选中态底色 / 前景。浮卡样式为实心主色。
  Color get selectedFill =>
      skin.float ? scheme.primary : scheme.secondaryContainer;
  Color get onSelectedFill =>
      skin.float ? scheme.onPrimary : scheme.onSecondaryContainer;

  /// 浅色强调底(primaryContainer 一类)及其前景:浮卡样式换成实心主色。
  Color solidFill(Color standard) => skin.float ? scheme.primary : standard;
  Color onSolidFill(Color standard) => skin.float ? scheme.onPrimary : standard;

  /// 直接压在页面上的次级按钮:浮卡样式白底描边,其余主题不改。
  ButtonStyle? get pageTonalStyle => skin.float
      ? FilledButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLow,
          foregroundColor: scheme.onSurface,
          side: switch (skin.edge) {
            final edge? => BorderSide(color: edge),
            null => null,
          },
        )
      : null;

  /// 浮在内容上的药丸(步数浮层、重绘滑杆、对比钮):浮卡样式实底卡片白描
  /// 发丝边,其余主题半透明底。
  BoxDecoration floatingPill(double radius) => BoxDecoration(
    color: skin.float
        ? scheme.surfaceContainerLow
        : scheme.surface.withValues(alpha: .85),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: skin.edge ?? scheme.outlineVariant.withValues(alpha: .7),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: .14),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  /// 选中芯片上的图标色:浮卡样式实心主色底上用 onPrimary,其余主题走芯片默认。
  Color? chipIcon(bool selected) =>
      selected && skin.float ? scheme.onPrimary : null;

  /// 滑块式分段的滑块底色;选中字色由 [segLabel] 换算。
  Color get segThumb => skin.float ? scheme.primary : scheme.surface;
  Color segLabel(Color selected) => skin.float ? scheme.onPrimary : selected;
}

/// 浮卡样式下给 [child] 描发丝边;其余主题或 [enabled] 为 false 时原样返回。
/// [radius] 为 null 时按圆形画。
class Lifted extends StatelessWidget {
  const Lifted({
    super.key,
    this.radius,
    this.enabled = true,
    required this.child,
  });

  final BorderRadius? radius;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final edge = context.skin.edge;
    if (edge == null || !enabled) return child;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: Border.all(color: edge),
      ),
      child: child,
    );
  }
}

/// 浮卡样式下给底部区(底栏 / 吸底栏)顶边描发丝边;其余主题原样返回。
class Docked extends StatelessWidget {
  const Docked({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final edge = context.skin.edge;
    if (edge == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: edge)),
      ),
      child: child,
    );
  }
}

/// 卡头 / 入口的图标。浮卡样式下放进主色圆角方块。
class SkinIcon extends StatelessWidget {
  const SkinIcon(this.icon, {super.key, this.size = 20});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!context.skin.float) {
      return Icon(icon, size: size, color: context.scheme.onSurfaceVariant);
    }
    final box = size + 8;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: context.scheme.primary,
        borderRadius: BorderRadius.circular(box * .29),
      ),
      child: Icon(
        icon,
        size: (size * .85).roundToDouble(),
        color: context.scheme.onPrimary,
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_skin.dart';
import '../theme/app_theme.dart';

/// 抬起菜单的一项:图标 + 文字,点了把 [value] 作为结果交回。
typedef LiftAction<T> = ({IconData icon, String label, T value});

/// 长按卡片的「抬起」层:卡片从原位浮起放大,菜单从它下沿卷出(同图库长按图片)。
/// [from] 是卡片在屏幕上的矩形,[aspect] 是浮起后的宽高比;[danger] 隔一条线排最后。
/// 点空白关闭返回 null。
Future<T?> showLiftMenu<T>(
  BuildContext context, {
  required Rect from,
  required double aspect,
  required Widget preview,
  required List<LiftAction<T>> actions,
  LiftAction<T>? danger,
}) => Navigator.of(context).push(
  _LiftRoute<T>(
    from: from,
    aspect: aspect,
    preview: preview,
    actions: actions,
    danger: danger,
  ),
);

/// [context] 所在部件在屏幕上的矩形(给 [showLiftMenu] 的 from)。
Rect? globalRectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _LiftRoute<T> extends PopupRoute<T> {
  _LiftRoute({
    required this.from,
    required this.aspect,
    required this.preview,
    required this.actions,
    required this.danger,
  });

  final Rect from;
  final double aspect;
  final Widget preview;
  final List<LiftAction<T>> actions;
  final LiftAction<T>? danger;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: .55);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 230);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> anim,
    Animation<double> _,
  ) => _Lifted<T>(route: this, anim: anim);
}

/// 菜单卷出时只裁下沿,左右上三边留出阴影的余量。
class _RollOutClip extends CustomClipper<Rect> {
  const _RollOutClip(this.t);

  final double t;
  static const _shadow = 24.0;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -_shadow,
    -_shadow,
    size.width + _shadow,
    size.height + _shadow * t,
  );

  @override
  bool shouldReclip(_RollOutClip old) => old.t != t;
}

class _Lifted<T> extends StatelessWidget {
  const _Lifted({required this.route, required this.anim});

  final _LiftRoute<T> route;
  final Animation<double> anim;

  static const _margin = 16.0;
  static const _gap = 12.0;
  static const _menuW = 200.0;
  static const _itemH = 46.0;
  static const _dividerH = 9.0;

  /// 浮起的卡占「可用框」(去掉边距与菜单之后那块)的面积比例。
  static const _fill = .36;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final top0 = media.padding.top + _margin;
    final bot0 = size.height - media.padding.bottom - _margin;
    final from = route.from;
    final menuH =
        _itemH * route.actions.length +
        (route.danger == null ? 0 : _itemH + _dividerH) +
        16;
    final aspect = route.aspect.isFinite && route.aspect > 0
        ? route.aspect
        : 1.0;
    final maxW = size.width - _margin * 2;
    final maxH = math.max(80.0, bot0 - top0 - menuH - _gap);
    var pw = math.sqrt(maxW * maxH * _fill * aspect);
    var ph = pw / aspect;
    if (ph > maxH) {
      ph = maxH;
      pw = ph * aspect;
    }
    if (pw > maxW) {
      pw = maxW;
      ph = pw / aspect;
    }
    // 尽量停在原位附近,装不下才整体上移
    final groupH = ph + _gap + menuH;
    final left = (from.center.dx - pw / 2)
        .clamp(_margin, math.max(_margin, size.width - pw - _margin))
        .toDouble();
    final top = (from.center.dy - ph / 2)
        .clamp(top0, math.max(top0, bot0 - groupH))
        .toDouble();
    final menuLeft = left
        .clamp(_margin, math.max(_margin, size.width - _menuW - _margin))
        .toDouble();
    final to = Rect.fromLTWH(left, top, pw, ph);

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = Motion.emphasized.transform(
          anim.value.clamp(0.0, 1.0).toDouble(),
        );
        return Stack(
          children: [
            Positioned.fromRect(
              rect: Rect.lerp(from, to, t)!,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: child,
              ),
            ),
            Positioned(
              left: menuLeft,
              top: to.bottom + _gap,
              width: _menuW,
              child: Opacity(
                opacity: t,
                child: ClipRect(
                  clipper: _RollOutClip(t),
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: math.max(t, .01),
                    child: _menu(context),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: route.preview,
    );
  }

  Widget _menu(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: context.raisedFill(scheme.surfaceContainerHigh),
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          for (final a in route.actions) _item(context, a),
          if (route.danger case final danger?) ...[
            Divider(
              height: _dividerH,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: scheme.outlineVariant,
            ),
            _item(context, danger, danger: true),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    LiftAction<T> action, {
    bool danger = false,
  }) {
    final scheme = context.scheme;
    return InkWell(
      onTap: () => Navigator.of(context).pop(action.value),
      child: SizedBox(
        height: _itemH,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              action.icon,
              size: 20,
              color: danger ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              action.label,
              style: context.texts.bodyLarge!.copyWith(
                color: danger ? scheme.error : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

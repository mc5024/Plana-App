import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 平滑展开/收起容器:高度用 SizeTransition,内容用 FadeTransition,
/// 展开时先长高再淡入、收起时先淡出再收拢 —— 避免内容"瞬间弹出"。
class ExpandBody extends StatefulWidget {
  const ExpandBody({
    super.key,
    required this.expanded,
    required this.child,
    this.curve,
  });

  final bool expanded;
  final Widget child;

  /// 高度曲线,展开收起共用。几块此消彼长时传对称曲线,总高度才单调变化。
  final Curve? curve;

  @override
  State<ExpandBody> createState() => _ExpandBodyState();
}

class _ExpandBodyState extends State<ExpandBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: widget.expanded ? 1 : 0,
  );

  late final Animation<double> _size = widget.curve == null
      ? CurvedAnimation(
          parent: _c,
          curve: Motion.emphasized,
          reverseCurve: Easing.emphasizedAccelerate,
        )
      : CurvedAnimation(parent: _c, curve: widget.curve!);

  // 展开:内容在 30%~100% 淡入;收起:0%~55% 先淡出
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(.3, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(.45, 1, curve: Curves.easeIn),
  );

  @override
  void didUpdateWidget(covariant ExpandBody old) {
    super.didUpdateWidget(old);
    if (widget.expanded != old.expanded) {
      widget.expanded ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _size,
        alignment: Alignment.topCenter,
        // RepaintBoundary:动画期间内容不重绘,缓存为纹理,只做裁剪+透明合成
        child: FadeTransition(
          opacity: _fade,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

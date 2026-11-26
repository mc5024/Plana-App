import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 带顺圆角外框进度环的生图容器(图库胶片条与 AI 助手内联图框共用):
/// - 有确定进度时,进度弧沿外框从顶边正中顺时针平滑生长;
/// - 无确定进度(准备 / 排队 / 超分 / 图像模型重绘)时,流光弧沿外框环绕,
///   内容区叠加轻暗纱与斜向扫光。
class GenProgressFrame extends StatefulWidget {
  const GenProgressFrame({
    super.key,
    required this.progress,
    required this.hasPreview,
    required this.radius,
    required this.innerRadius,
    required this.inset,
    required this.trackColor,
    required this.progressColor,
    required this.child,
    this.strokeWidth = 2.2,
    this.overlay,
  });

  /// 0..1 的确定进度;null 走不确定环绕 + 扫光动画。
  final double? progress;

  /// 底层是否已有图像(预览帧或垫底图);false 表示斜纹占位。
  final bool hasPreview;

  /// 外框圆角半径。
  final double radius;

  /// 内层内容裁切圆角半径。
  final double innerRadius;

  /// 外框边缘到内层内容的缩进(含描边宽与呼吸缝)。
  final double inset;

  /// 进度环描边宽。
  final double strokeWidth;

  /// 进度底轨颜色。
  final Color trackColor;

  /// 进度弧 / 流光弧颜色。
  final Color progressColor;

  final Widget child;

  /// 叠在暗纱扫光之上的前景层(如排队文案胶囊)。
  final Widget? overlay;

  @override
  State<GenProgressFrame> createState() => _GenProgressFrameState();
}

class _GenProgressFrameState extends State<GenProgressFrame>
    with SingleTickerProviderStateMixin {
  AnimationController? _orbit;

  AnimationController _ensureOrbit() => _orbit ??= AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) _ensureOrbit().repeat();
  }

  @override
  void didUpdateWidget(GenProgressFrame old) {
    super.didUpdateWidget(old);
    if (widget.progress == null) {
      final c = _ensureOrbit();
      if (!c.isAnimating) c.repeat();
    } else {
      _orbit?.stop();
    }
  }

  @override
  void dispose() {
    _orbit?.dispose();
    super.dispose();
  }

  Widget _content({double? shimmerT, required bool dark}) => Padding(
    padding: EdgeInsets.all(widget.inset),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.innerRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (shimmerT != null)
            IgnorePointer(
              child: CustomPaint(
                painter: _ShimmerVeilPainter(
                  t: shimmerT,
                  hasPreview: widget.hasPreview,
                  dark: dark,
                ),
              ),
            ),
          if (widget.overlay != null) widget.overlay!,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (progress == null) {
      final orbit = _ensureOrbit();
      return AnimatedBuilder(
        animation: orbit,
        builder: (_, _) => CustomPaint(
          foregroundPainter: _BorderProgressPainter(
            progress: null,
            orbitT: orbit.value,
            radius: widget.radius,
            strokeWidth: widget.strokeWidth,
            trackColor: widget.trackColor,
            progressColor: widget.progressColor,
          ),
          child: _content(shimmerT: orbit.value, dark: dark),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: Motion.fast,
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => CustomPaint(
        foregroundPainter: _BorderProgressPainter(
          progress: value,
          orbitT: 0,
          radius: widget.radius,
          strokeWidth: widget.strokeWidth,
          trackColor: widget.trackColor,
          progressColor: widget.progressColor,
        ),
        child: child,
      ),
      child: _content(dark: dark),
    );
  }
}

/// 从顶边正中出发顺时针闭合的圆角矩形路径。
Path _roundedBorderPath(Size size, double inset, double radius) {
  final left = inset;
  final top = inset;
  final right = size.width - inset;
  final bottom = size.height - inset;
  final w = right - left;
  final h = bottom - top;
  if (w <= 0 || h <= 0) return Path();
  final r = radius.clamp(0.0, math.min(w, h) / 2);
  final cx = (left + right) / 2;
  return Path()
    ..moveTo(cx, top)
    ..lineTo(right - r, top)
    ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
    ..lineTo(right, bottom - r)
    ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
    ..lineTo(left + r, bottom)
    ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
    ..lineTo(left, top + r)
    ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
    ..close();
}

class _BorderProgressPainter extends CustomPainter {
  const _BorderProgressPainter({
    required this.progress,
    required this.orbitT,
    required this.radius,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  final double? progress;
  final double orbitT;
  final double radius;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final path = _roundedBorderPath(size, inset, math.max(0.0, radius - inset));
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    // 完整底轨
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    final metric = metrics.first;
    final total = metric.length;
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = progressColor;

    final p = progress;
    if (p != null) {
      final clamped = p.clamp(0.0, 1.0);
      if (clamped <= 0.002) return;
      canvas.drawPath(metric.extractPath(0, total * clamped), fgPaint);
      return;
    }

    // 不确定态:28% 周长流光弧顺时针环绕
    final seg = total * .28;
    final start = (orbitT * total) % total;
    final end = start + seg;
    if (end <= total) {
      canvas.drawPath(metric.extractPath(start, end), fgPaint);
    } else {
      canvas.drawPath(metric.extractPath(start, total), fgPaint);
      canvas.drawPath(metric.extractPath(0, end - total), fgPaint);
    }
  }

  @override
  bool shouldRepaint(_BorderProgressPainter old) =>
      old.progress != progress ||
      old.orbitT != orbitT ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}

class _ShimmerVeilPainter extends CustomPainter {
  const _ShimmerVeilPainter({
    required this.t,
    required this.hasPreview,
    required this.dark,
  });

  final double t;
  final bool hasPreview;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.clipRect(bounds);

    final dimAlpha = hasPreview ? .30 : (dark ? .08 : .04);
    canvas.drawRect(
      bounds,
      Paint()..color = Colors.black.withValues(alpha: dimAlpha),
    );

    const skew = 0.32;
    final bandW = math.max(size.width * .65, 36.0);
    final skewPad = size.height * skew;
    final eased = Curves.easeInOut.transform(t);
    final startX = -bandW / 2;
    final endX = size.width + bandW / 2 + skewPad;
    final cx = startX + (endX - startX) * eased;
    final gleamAlpha = hasPreview ? .26 : (dark ? .14 : .52);

    canvas.save();
    canvas.translate(cx, 0);
    canvas.skew(-skew, 0);
    final bandRect = Rect.fromLTWH(-bandW / 2, -4, bandW, size.height + 8);
    final bandPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: gleamAlpha),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(bandRect);
    canvas.drawRect(bandRect, bandPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerVeilPainter old) =>
      old.t != t || old.hasPreview != hasPreview || old.dark != dark;
}

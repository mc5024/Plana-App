import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

/// 顶栏右侧的裸状态入口：点数与百分比共用单行点击区域。
///
/// [value] 为空 = 还没拿到读数：数值位换成一枚刷新图标，[loading] 时转圈。
/// 给了 [meter] 就在图标与读数底下画一条进度条（整条是满额，填色是剩多少），
/// 有 [detail] 时两者之间不再画分隔竖线。
class TopBarStatus extends StatelessWidget {
  const TopBarStatus({
    super.key,
    required this.tooltip,
    required this.value,
    required this.detail,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.valueColor,
    this.detailColor,
    this.meter,
    this.valueSample,
  });

  final String tooltip;
  final String? value;
  final String? detail;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final Color? valueColor;
  final Color? detailColor;

  /// 读数底下的额度条:[fraction] 0~1,越界夹住;[label] 是它的读数,
  /// 只给读屏(不以文字出现)。
  final ({double fraction, Color color, String label})? meter;

  /// 数值位至少按这段样本的宽度占位(等宽字体下就是定几位数):读数变短时
  /// 整块不跟着缩,顶栏另两段不挪位,底下的进度条也不变短。
  final String? valueSample;

  @override
  Widget build(BuildContext context) {
    final valueStyle = mono(
      context,
      size: 15,
      weight: FontWeight.w700,
    ).copyWith(color: valueColor ?? context.scheme.onSurface);
    Widget readout = switch (value) {
      final text? => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: valueStyle,
      ),
      null => _Pending(
        spinning: loading,
        color: valueColor ?? context.scheme.onSurfaceVariant,
      ),
    };
    if (valueSample case final sample?) {
      readout = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0,
            child: Text(sample, maxLines: 1, style: valueStyle),
          ),
          readout,
        ],
      );
    }
    final detailText = switch (detail) {
      final text? => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono(
          context,
          size: 15,
          weight: FontWeight.w700,
        ).copyWith(color: detailColor ?? context.scheme.onSurfaceVariant),
      ),
      null => null,
    };
    final leadIcon = Icon(
      icon,
      size: 18,
      color: valueColor ?? context.scheme.onSurfaceVariant,
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label:
            '$tooltip${context.l10n.commaSep}'
            '${value ?? (loading ? context.l10n.loading : context.l10n.notFetched)}'
            '${switch (detail ?? meter?.label) {
              final d? => '${context.l10n.commaSep}$d',
              null => '',
            }}',
        // 不裁切内容:进度条贴着这块的左右边和下半截,按圆角一裁两头就成了斜边。
        // 点按的水波纹由 InkWell 自己按圆角收
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: switch (meter) {
              // 进度条从图标头一直垫到读数尾。外层给的是整行高的定高约束,
              // 不先放松的话这一排会被撑满行高,条就画到了裁切框外
              final r? => Align(
                widthFactor: 1,
                child: _MeterUnder(
                  fraction: r.fraction,
                  color: r.color,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      leadIcon,
                      const SizedBox(width: 4),
                      Flexible(child: readout),
                      if (detailText != null) ...[
                        const SizedBox(width: 6),
                        Flexible(child: detailText),
                      ],
                    ],
                  ),
                ),
              ),
              null => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leadIcon,
                  const SizedBox(width: 4),
                  Flexible(child: readout),
                  if (detailText != null) ...[
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: context.scheme.outlineVariant,
                    ),
                    Flexible(child: detailText),
                  ],
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// 图标与读数底下的额度条:画在布局框外,读数仍和顶栏其余两段同一条中线。
class _MeterUnder extends StatelessWidget {
  const _MeterUnder({
    required this.fraction,
    required this.color,
    required this.child,
  });

  final double fraction;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _MeterPainter(
      fraction: fraction.clamp(0.0, 1.0),
      color: color,
      track: context.scheme.outlineVariant,
    ),
    child: child,
  );
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  static const _gap = 2.0;
  static const _height = 4.0;
  static const _radius = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height + _gap;
    const radius = Radius.circular(_radius);
    final paint = Paint();
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, size.width, top + _height, radius),
      paint..color = track,
    );
    if (fraction <= 0) return;
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, size.width * fraction, top + _height, radius),
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// 一行字按当前字号缩放排出来有多宽(顶栏据此算各段要多少地方)。
double topBarTextWidth(BuildContext context, String text, TextStyle style) =>
    (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout()).width;

/// 读数还没到时占数值位的刷新图标（与点数弹层的刷新按钮同一枚）。
/// 拉取中持续转圈；停下时转完手上这一圈再停，不歪在半截。
class _Pending extends StatefulWidget {
  const _Pending({required this.spinning, required this.color});

  final bool spinning;
  final Color color;

  @override
  State<_Pending> createState() => _PendingState();
}

class _PendingState extends State<_Pending>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _turn.repeat();
  }

  @override
  void didUpdateWidget(_Pending old) {
    super.didUpdateWidget(old);
    if (widget.spinning == old.spinning) return;
    if (widget.spinning) {
      _turn.repeat();
    } else {
      _turn.forward();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turn,
    child: Icon(Icons.refresh, size: 18, color: widget.color),
  );
}

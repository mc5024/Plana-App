import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/backend_client.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import 'stats_providers.dart';

/// 统计三页共用的小件:范围 chips、指标格、卡容器、流水行、热力图卡。

class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Lifted(
    radius: BorderRadius.circular(16),
    child: Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    ),
  );
}

/// 今日/本周/本月 胶囊组。
class RangeChips extends StatelessWidget {
  const RangeChips({super.key, required this.range, required this.onChanged});

  final String range;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Row(
      children: [
        for (final e in rangeLabels.entries) ...[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: e.key == range ? context.selectedFill : Colors.transparent,
              shape: StadiumBorder(
                side: e.key == range
                    ? BorderSide.none
                    : BorderSide(color: scheme.outlineVariant),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 6,
                  ),
                  child: Text(
                    e.value,
                    style: context.texts.labelMedium!.copyWith(
                      color: e.key == range
                          ? context.onSelectedFill
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 指标格:小图标 + 标签一行,数值一行。
/// [loading] 期间数值位是占位块;拉完仍为 null 才显示「—」。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? suffix;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: context.texts.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (loading && value == null)
          SkeletonText(
            sample: '0,000',
            style: mono(context, size: 17),
            width: 52,
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value ?? '—', style: mono(context, size: 17)),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    suffix!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// 趋势细柱条(定稿版式:hero 下面裸排一条,不套卡、不带轴标)。
/// 序列随时间范围换,按生成数量画;点柱选中(高亮只表示选中,
/// 未选中时全条无高亮),明细由上方 hero 改写。命中判定按整列 x 区间
/// (月档柱子细,逐柱点不中),上方留一段透明高度撑大触控目标。
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.selected,
    required this.onSelect,
    this.height = 46,
  });

  /// (轴标, 详情文案, 生图数, 点数)。
  final List<({String label, String full, int images, int pts})> points;

  /// 选中下标;null = 未选中。
  final int? selected;
  final ValueChanged<int?> onSelect;
  final double height;

  int _valueAt(int i) => points[i].images;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            '暂无数据',
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
        ),
      );
    }
    final max = List.generate(
      points.length,
      _valueAt,
    ).fold(0, (m, v) => v > m ? v : m);
    final dim = Color.lerp(scheme.surfaceContainerHigh, scheme.primary, .38)!;

    return LayoutBuilder(
      builder: (context, box) {
        int at(Offset local) => (local.dx / box.maxWidth * points.length)
            .floor()
            .clamp(0, points.length - 1);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 点选中的那根 = 取消选择(回到全部);拖动只切换不取消
          onTapDown: (d) {
            final i = at(d.localPosition);
            onSelect(i == selected ? null : i);
          },
          onHorizontalDragUpdate: (d) {
            final i = at(d.localPosition);
            if (i != selected) onSelect(i);
          },
          child: SizedBox(
            height: height + 12, // 上方多留一截,细柱也好点
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < points.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: points.length > 16 ? 1.2 : 2,
                      ),
                      child: Container(
                        height: max == 0
                            ? 2
                            : (2 + (height - 2) * _valueAt(i) / max).clamp(
                                2,
                                height,
                              ),
                        decoration: BoxDecoration(
                          // 0 值留基线占位(空档位也占宽,不塌缩);
                          // 主色只给选中柱,取消选中即全条无高亮
                          color: i == selected
                              ? scheme.primary
                              : _valueAt(i) == 0
                              ? scheme.surfaceContainerHigh
                              : dim,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 呼吸式明暗包装(骨架件共用)。
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: .45,
      end: 1,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// 定尺寸加载占位块(图表区等自身高度确定的场合)。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => _Pulse(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// 文字位加载占位:用一段透明的 [sample] 文字按同一 [style] 撑出行高,
/// 骨架条画在其中。**这是防高度跳变的关键**——加载态与最终文本占位
/// 完全一致,数字到位时不会把下面的内容顶动。
class SkeletonText extends StatelessWidget {
  const SkeletonText({
    super.key,
    required this.sample,
    required this.style,
    this.width,
  });

  /// 撑高度用的样本(取该位最可能的最长值,如 '0,000')。
  final String sample;
  final TextStyle style;

  /// 骨架条宽度;null = 与样本同宽。
  final double? width;

  @override
  Widget build(BuildContext context) {
    final bar = _Pulse(
      child: Container(
        width: width,
        height: (style.fontSize ?? 14) * .74,
        decoration: BoxDecoration(
          color: context.scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Opacity(opacity: 0, child: Text(sample, style: style, maxLines: 1)),
        width == null ? Positioned.fill(child: bar) : bar,
      ],
    );
  }
}

/// 流水行:圆角图标块 + 标题/副行 + 尾注。
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.trailing,
    this.trailingColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? sub;
  final String? trailing;
  final Color? trailingColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 16,
              color: iconColor ?? scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.bodyMedium),
                if (sub != null)
                  Text(
                    sub!,
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: mono(
                context,
                size: 12,
                color: trailingColor ?? scheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡内分隔线。
class CardDivider extends StatelessWidget {
  const CardDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 16, thickness: .5, color: context.scheme.outlineVariant);
}

/// 24 小时热力图卡:标题行 + 峰值副行 + 12×2 格 + 时刻标尺(+ 可选图例)。
class HeatCard extends StatelessWidget {
  const HeatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.heat,
    required this.peakText,
    this.legend = false,
  });

  final IconData icon;
  final String title;
  final AsyncValue<HourlyHeat?> heat;
  final String Function(({int hour, double avg, double total}) top) peakText;
  final bool legend;

  static Color cellColor(ColorScheme scheme, double r) => r <= 0
      ? scheme.surfaceContainerHigh
      : Color.lerp(scheme.surfaceContainerHigh, scheme.primary, .15 + .85 * r)!;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final h = heat.value;
    final cells = h?.cells ?? const [];
    final byHour = {for (final c in cells) c.hour: c.avg};
    final max = cells.fold(0.0, (m, c) => c.avg > m ? c.avg : m);
    final top = cells.isEmpty
        ? null
        : cells.reduce((a, b) => b.avg > a.avg ? b : a);
    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                title,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                h == null ? '' : '基于 ${h.totalDays} 天',
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (heat.isLoading && h == null)
            SkeletonText(
              sample: '峰值 00:00(日均 000 次)',
              style: context.texts.labelSmall!,
              width: 148,
            )
          else
            Text(
              top == null || top.avg <= 0 ? '暂无数据' : peakText(top),
              style: context.texts.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            children: [
              for (var hour = 0; hour < 24; hour++)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cellColor(
                      scheme,
                      max <= 0 ? 0 : (byHour[hour] ?? 0) / max,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in const ['0 时', '6', '12', '18', '23'])
                Text(
                  t,
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
            ],
          ),
          if (legend) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '低 ',
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
                for (final r in const [.0, .25, .5, .75, 1.0])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: cellColor(scheme, r),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                Text(
                  ' 高',
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

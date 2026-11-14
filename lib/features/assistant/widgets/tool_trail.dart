/// 「这一轮查了什么」的轨迹条,跑的时候和跑完之后共用同一套版式。
///
/// 两档密度,各只说一件事:
///
///     查了 3 处资料                    ← 折叠:只报处数
///     ├ 角色库  普拉娜                  ← 展开:哪个库、查的什么
///     ├ Tag 百科  halo
///     └ 画风库  wlop
///
/// **工具回的结果计数不显示**。计数摆在行尾试过一版,又长又没用 ——
/// 用户要的是「查了什么」,不是「命中几条」。计数留在
/// [ToolTrace.summary] 里当完成信号(圆点亮不亮),不占版面。
///
/// 查询词是从 `tool_call` 的参数里挑的([toolSubject]),以前直接丢掉了。
/// 没有它的话展开只剩三个光秃秃的库名,等于没展开。
///
/// 跑的时候恒展开(圆点逐颗点亮就是进度),跑完收成一行。转圈和秒数不在这里,
/// 在下面那个占着回复位置的气泡上(见 `assistant_page` 的 `_LiveTurn`)。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/conversation.dart';

/// 一行文字的行高倍数。**量圆点位置和排文字用的是同一个常数** ——
/// 分开写的话改了一处另一处就错位,而错位只有一两个像素,肉眼要盯着看才发现。
const _lineHeight = 1.45;

class ToolTrail extends StatefulWidget {
  const ToolTrail({super.key, required this.tools, this.running = false});

  final List<ToolTrace> tools;

  /// 这一轮还在跑:恒展开,不出折叠头。
  final bool running;

  @override
  State<ToolTrail> createState() => _ToolTrailState();
}

class _ToolTrailState extends State<ToolTrail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final running = widget.running;
    // 跑的时候一条条查资料往下长、跑完点开收起,高度都平滑地变,不一格格跳
    return AnimatedSize(
      duration: Motion.fast,
      curve: Motion.standard,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!running) _head(context, scheme),
          if (running || _open)
            for (final t in widget.tools) _row(context, scheme, t),
        ],
      ),
    );
  }

  /// 折叠头。**不描边不铺底** —— 它是一条注解,压在正文气泡上方;做成胶囊
  /// (先前那版)会和气泡抢一样的视觉重量,一屏几轮下来全是灰胶囊。
  Widget _head(BuildContext context, ColorScheme scheme) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 14, color: scheme.outline),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                toolHeadline(widget.tools),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _open ? .5 : 0,
              duration: Motion.fast,
              child: Icon(Icons.expand_more, size: 15, color: scheme.outline),
            ),
          ],
        ),
      ),
    ),
  );

  /// 一条轨迹:库名 + 查询词。两段拼在同一个 [Text.rich] 里而不是两列 ——
  /// 库名长短不一(「角色库」三个字、未登记的新工具直接是英文原名),排成列
  /// 必然参差,而拼成一段自然换行,长查询词也不会被挤出屏幕。
  ///
  /// 查完没查完只看圆点,不写「查询中…」:一行两个状态词读着比圆点还慢。
  Widget _row(BuildContext context, ColorScheme scheme, ToolTrace t) {
    final degraded = t.name == kDegradedTool;
    final subject = t.subject;
    // 圆点要对准**第一行**的中线,不是整行的中线:查询词长了会折行,
    // 按整行居中的话圆点就掉到两行中间去了。所以给它一个「一行高」的盒子居中,
    // 而不是拿一个写死的 top padding 去凑 —— 那个数在放大字号时必然错位。
    final lineH = MediaQuery.textScalerOf(
      context,
    ).scale((context.texts.labelMedium?.fontSize ?? 12) * _lineHeight);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 0, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: lineH,
            child: Center(
              child: degraded
                  ? Icon(
                      Icons.shield_outlined,
                      size: 11,
                      color: FixedSemantic.warn,
                    )
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        // 亮起来 = 这一处查完了。跑的时候一路点亮,就是进度。
                        color: t.done ? scheme.primary : scheme.outlineVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (!degraded)
                    TextSpan(
                      text: toolLabel(t.name),
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (!degraded && subject.isNotEmpty)
                    TextSpan(
                      text: '  $subject',
                      style: context.texts.labelMedium!.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (degraded)
                    TextSpan(
                      text: t.summary,
                      style: context.texts.labelSmall!.copyWith(
                        color: FixedSemantic.warn,
                      ),
                    ),
                ],
              ),
              style: const TextStyle(height: _lineHeight),
            ),
          ),
        ],
      ),
    );
  }
}

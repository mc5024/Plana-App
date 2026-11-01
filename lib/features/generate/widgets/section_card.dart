import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import 'common.dart';

/// 创作页折叠卡的统一骨架:
/// 头部一行(图标·标题·徽章·内联元素·动作按钮·chevron),
/// 展开体用 AnimatedSize + FadeTransition 过渡。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.badge,
    this.inline = const [],
    this.actions = const [],
    this.expanded = false,
    this.onHeaderTap,
    this.body,
    this.muted = false,
    this.reorderIndex,
    this.chevronPlaceholder = false,
  });

  final IconData icon;
  final String title;
  final Widget? badge;

  /// 头部标题与动作之间的内联元素(mini 缩略图、"未启用"等)
  final List<Widget> inline;
  final List<Widget> actions;
  final bool expanded;
  final VoidCallback? onHeaderTap;
  final Widget? body;

  /// 禁用观感(如图生图启用时的 Vibe 卡)
  final bool muted;

  /// 非空时卡头可长按拖拽调序(挂头部不挂展开体,避免抢输入框/滑杆手势)。
  final int? reorderIndex;

  /// 不可展开(onHeaderTap 为空)时,仍画一个静态 chevron 占位,
  /// 让卡头与其它可展开卡在视觉上对齐(如空角色卡)。不接手势、不旋转。
  final bool chevronPlaceholder;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final titleColor = muted ? scheme.onSurfaceVariant : scheme.onSurface;
    Widget header = InkWell(
      onTap: onHeaderTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 13, 13),
        child: Row(
          children: [
            // 卡头高度下限 = 动作按钮的高度(RoundIconBtn 36 / RefEnableToggle 38)。
            // 各卡的动作按钮数量不一,没有按钮的卡收起来会明显
            // 比 LoRA / 重绘放大矮一截 —— 撑一格,所有卡收起时一样高。
            const SizedBox(height: 38),
            SkinIcon(icon),
            const SizedBox(width: 9),
            Text(
              title,
              style: context.texts.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 8), badge!],
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final w in inline) ...[w, const SizedBox(width: 6)],
                ],
              ),
            ),
            for (final a in actions) ...[a, const SizedBox(width: 6)],
            if (onHeaderTap != null)
              AnimatedRotation(
                turns: expanded ? .5 : 0,
                duration: Motion.medium,
                curve: Motion.emphasized,
                child: Icon(Icons.expand_more, size: 22, color: scheme.outline),
              )
            else if (chevronPlaceholder)
              Icon(Icons.expand_more, size: 22, color: scheme.outline),
          ],
        ),
      ),
    );
    final idx = reorderIndex;
    if (idx != null) {
      header = ReorderableDelayedDragStartListener(index: idx, child: header);
    }
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            ExpandBody(
              expanded: expanded && body != null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: body ?? const SizedBox(width: double.infinity),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

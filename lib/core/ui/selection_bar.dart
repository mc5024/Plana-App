import 'package:flutter/material.dart';

import '../theme/app_skin.dart';
import '../theme/app_theme.dart';
import 'expand_body.dart';

/// 多选底栏(Vibe 管理器 / 角色参考图库 / 灵感页共用)。
///
/// 版式固定两层:
/// - 第一层 [actions] 靠左(打包/标签/收藏/全选…),[destructive] 靠右
///   —— 破坏性操作单独拉到另一头,不和常用项挤在一起误触。
/// - 第二层「取消选择」(定宽)+ [primary] 主动作(占满剩余宽度)。
///
/// [compact] 时压成一行:✕ 取消 + [actions] + [destructive](都用
/// [SelectionIconButton])+ 占满剩余宽度的 [primary]。
///
/// 尺寸基准取自灵感页:大按钮 48 高、24 圆角,底色 surfaceContainer。
/// 没有任何选中时整条收起([visible] = false),把屏幕还给列表。
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.visible,
    required this.onClear,
    required this.primary,
    this.actions = const [],
    this.destructive,
    this.safeArea = true,
    this.compact = false,
  });

  /// 展开条件。一般是「选中数 > 0」,但页面若有「退出即丢弃」的语义,
  /// 还得把「相对进入时有改动」也算进来,否则清空后底栏消失就没法确认了。
  final bool visible;

  /// 第二层左键:只清空选择,不退页。null = 置灰。
  final VoidCallback? onClear;

  /// 第二层主动作。整块自定义(确认选择 / 分段双动作 / 退出多选),
  /// 高度圆角用 [kSelectionActionHeight] / [kSelectionActionRadius] 对齐。
  final Widget primary;

  /// 第一层左侧的非破坏性批量操作,用 [SelectionPill]。
  final List<Widget> actions;

  /// 第一层右侧的破坏性操作(删除)。
  final Widget? destructive;

  /// 独立路由页要自己垫底部安全区;shell 内的 tab 页由导航栏兜着,传 false。
  final bool safeArea;

  /// 一行版式(见类注释)。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final firstRow = actions.isNotEmpty || destructive != null;
    Widget content = compact
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                SelectionIconButton(
                  icon: Icons.close,
                  tooltip: '取消选择',
                  onTap: onClear,
                ),
                for (final a in [...actions, ?destructive]) ...[
                  const SizedBox(width: 8),
                  a,
                ],
                const SizedBox(width: 10),
                Expanded(child: primary),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (firstRow) ...[
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                      const Spacer(),
                      ?destructive,
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: onClear,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(112, kSelectionActionHeight),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            kSelectionActionRadius,
                          ),
                        ),
                      ),
                      child: const Text('取消选择'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: primary),
                  ],
                ),
              ],
            ),
          );
    if (safeArea) content = SafeArea(top: false, child: content);
    return ExpandBody(
      expanded: visible,
      child: Docked(
        child: Material(
          color: context.raisedFill(scheme.surfaceContainer),
          child: content,
        ),
      ),
    );
  }
}

/// 底栏两个大按钮的统一高度与圆角。
const double kSelectionActionHeight = 48;
const double kSelectionActionRadius = 24;

/// 主动作按钮的统一样式(确认选择 / 退出多选…)。
ButtonStyle selectionPrimaryStyle() => FilledButton.styleFrom(
  minimumSize: const Size(0, kSelectionActionHeight),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kSelectionActionRadius),
  ),
);

/// 第一层的小描边按钮(图标 + 文字)。[color] 非空即破坏性配色。
class SelectionPill extends StatelessWidget {
  const SelectionPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final enabled = onTap != null;
    final fg = (color ?? scheme.onSurfaceVariant).withValues(
      alpha: enabled ? 1 : .45,
    );
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: color != null
              ? color!.withValues(alpha: .5)
              : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Text(label, style: context.texts.labelLarge!.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行底栏([SelectionBar.compact])里的圆形描边图标钮,与主动作同高。
/// [color] 非空即破坏性配色。
class SelectionIconButton extends StatelessWidget {
  const SelectionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final enabled = onTap != null;
    final fg = (color ?? scheme.onSurfaceVariant).withValues(
      alpha: enabled ? 1 : .45,
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: color != null
                ? color!.withValues(alpha: .5)
                : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: kSelectionActionHeight,
            height: kSelectionActionHeight,
            child: Icon(icon, size: 21, color: fg),
          ),
        ),
      ),
    );
  }
}

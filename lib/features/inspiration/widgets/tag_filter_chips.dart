import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

/// 「我的」库的全部 / 收藏 / 用户标签筛选行,灵感页与灵感库面板共用。
///
/// 描边小胶囊:未选只描一圈细边,选中实心主色;用户标签前加 #。
/// 标签横滑、右缘渐隐,行尾固定一颗齿轮(标签池管理)。
class TagFilterChips extends StatelessWidget {
  const TagFilterChips({
    super.key,
    required this.tags,
    required this.filter,
    required this.onChanged,
    required this.onManageTags,
    this.edge = 14,
  });

  static const favorites = ' fav';

  final List<String> tags;
  final String? filter;
  final ValueChanged<String?> onChanged;
  final VoidCallback onManageTags;
  final double edge;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    Widget chip(
      String label,
      bool selected,
      VoidCallback onTap, {
      IconData? icon,
    }) {
      final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: selected ? scheme.primary : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: fg),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    label,
                    style: context.texts.labelLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            // 右缘渐隐:标签多了被截在边上时不是一刀切
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                colors: const [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 1 - 20 / rect.width.clamp(40, double.infinity), 1],
              ).createShader(rect),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(edge, 5, 16, 5),
                children: [
                  chip(context.l10n.all, filter == null, () => onChanged(null)),
                  chip(
                    context.l10n.favorites,
                    filter == favorites,
                    () => onChanged(favorites),
                    icon: Icons.star_rounded,
                  ),
                  for (final tag in tags)
                    chip(
                      '#$tag',
                      filter == tag,
                      () => onChanged(filter == tag ? null : tag),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.manageTagPool,
            icon: Icon(
              Icons.settings_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: onManageTags,
          ),
          SizedBox(width: edge - 8),
        ],
      ),
    );
  }
}

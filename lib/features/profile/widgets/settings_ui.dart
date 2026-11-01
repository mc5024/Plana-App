import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';

/// 设置类页面共用版式:分组卡 + 单行条目。
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 48,
                  color: scheme.outlineVariant.withValues(alpha: .35),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 卡片外的小节标签。
class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text,
        style: context.texts.labelMedium!.copyWith(
          color: context.scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 单行条目:图标 + 标题,右侧可选数据值,可点时带箭头。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.valueColor,
    this.onTap,
    this.dropdown = false,
  });

  final IconData icon;
  final String title;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;

  /// 外面包着下拉菜单:箭头换成朝下,点击交给菜单。
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              title,
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? '',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall!.copyWith(
                  color: valueColor ?? scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onTap != null || dropdown) ...[
              const SizedBox(width: 4),
              Icon(
                dropdown ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: scheme.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

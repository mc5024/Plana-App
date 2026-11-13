import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/scroll_memory.dart';
import '../generate/preset_manage_page.dart';
import '../generate/widgets/common.dart' show sharedAxisRoute;
import '../stats/stats_page.dart';
import '../tools/tools_page.dart';
import 'about_page.dart';
import 'account_page.dart';
import 'appearance_page.dart';
import 'backup_page.dart';
import 'gen_settings_page.dart';
import 'storage_page.dart';
import '../../l10n/l10n.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget page) => Navigator.of(context).push(sharedAxisRoute(page));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // 右侧也留 20:两颗现在是带底色的实心按钮,可见边缘就是盒子边缘,
          // 直接与左侧 20 对齐即可。裸 IconButton 时代得留 8 —— 那时可见的
          // 只有中间那枚字形,圆形点击区在两侧各虚占一截。
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.tabProfile,
                  style: context.texts.headlineSmall!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // 这两个都不是"设置项",不在列表里占卡;图标各配两个字。
              _HeaderBtn(
                icon: Icons.settings_backup_restore,
                label: context.l10n.backup,
                onTap: () => push(const BackupPage()),
              ),
              const SizedBox(width: 8),
              _HeaderBtn(
                icon: Icons.info_outline,
                label: context.l10n.about,
                onTap: () => push(const AboutPage()),
              ),
            ],
          ),
        ),
        Expanded(
          child: ScrollMemo(
            memoKey: 'profile',
            builder: (context, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              children: [
                _EntryCard(
                  icon: Icons.manage_accounts_outlined,
                  filledIcon: Icons.manage_accounts,
                  title: context.l10n.accountAccess,
                  subtitle: context.l10n.accountAccessSub,
                  onTap: () => push(const AccountPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.query_stats,
                  filledIcon: Icons.query_stats,
                  title: context.l10n.stats,
                  subtitle: context.l10n.statsSub,
                  onTap: () => push(const StatsPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.bookmark_outline,
                  filledIcon: Icons.bookmark,
                  title: context.l10n.promptPresets,
                  subtitle: context.l10n.promptPresetsSub,
                  onTap: () => push(const PromptPresetManagePage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.tune,
                  filledIcon: Icons.tune,
                  title: context.l10n.genSettings,
                  subtitle: context.l10n.genSettingsSub,
                  onTap: () => push(const GenSettingsPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.handyman_outlined,
                  filledIcon: Icons.handyman,
                  title: context.l10n.toolbox,
                  subtitle: context.l10n.toolboxSub,
                  onTap: () => push(const ToolsPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.color_lens_outlined,
                  filledIcon: Icons.color_lens,
                  title: context.l10n.appearanceHaptics,
                  subtitle: context.l10n.appearanceSub,
                  onTap: () => push(const AppearancePage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.storage,
                  filledIcon: Icons.storage,
                  title: context.l10n.storage,
                  subtitle: context.l10n.storageSub,
                  onTap: () => push(const StoragePage()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 大入口卡(主页卡片同款容器):图标 + 主标题,标题下一行描述。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.filledIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;

  /// 浮卡样式下用的实心图标
  final IconData filledIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 11, 15),
            child: Row(
              children: [
                // 浮卡样式用实心主色图标
                SizedBox.square(
                  dimension: 32,
                  child: Icon(
                    context.skin.float ? filledIcon : icon,
                    size: 28,
                    color: context.skin.float
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.texts.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「我的」标题行右侧那两颗:图标 + 两个字。
class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: context.pageControlFill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.texts.labelLarge!.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

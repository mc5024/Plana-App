import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/scroll_memory.dart';
import '../generate/preset_manage_page.dart';
import '../generate/widgets/common.dart' show sharedAxisRoute;
import '../migrate/web_backup_page.dart';
import '../stats/stats_page.dart';
import '../tools/tools_page.dart';
import 'about_page.dart';
import 'account_page.dart';
import 'appearance_page.dart';
import 'gen_settings_page.dart';
import 'storage_page.dart';

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
                  '我的',
                  style: context.texts.headlineSmall!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // 这两个都不是"设置项",不值得在列表里占一张与存储管理等宽的卡。
              // 导入备份更是一次性的迁移动作,常驻列表里只会天天碍眼。
              //
              // 但只挂两枚裸图标又太哑:info 还算通用,import_export 那枚
              // 没人猜得出是「把 web 的备份搬进来」。各配两个字。
              _HeaderBtn(
                icon: Icons.import_export,
                // 不叫「同步」:这是选文件→预览→落库的单向一次性导入,
                // 手机这边的改动不会回流,叫同步会让人等一个不存在的回程。
                label: '导入',
                onTap: () => push(const WebBackupPage()),
              ),
              const SizedBox(width: 8),
              _HeaderBtn(
                icon: Icons.info_outline,
                label: '关于',
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
                  title: '账号与接入',
                  subtitle: 'Token 与 Bot 授权',
                  onTap: () => push(const AccountPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.query_stats,
                  filledIcon: Icons.query_stats,
                  title: '统计',
                  subtitle: '用量 · 钱包 · 全平台统计',
                  onTap: () => push(const StatsPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.bookmark_outline,
                  filledIcon: Icons.bookmark,
                  title: '提示词预设',
                  subtitle: '正负面提示词模板',
                  onTap: () => push(const PromptPresetManagePage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.tune,
                  filledIcon: Icons.tune,
                  title: '生成设置',
                  subtitle: '自动重试 · 功能模块 · 默认保存',
                  onTap: () => push(const GenSettingsPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.handyman_outlined,
                  filledIcon: Icons.handyman,
                  title: '工具箱',
                  subtitle: '权重转换 · 图片元数据',
                  onTap: () => push(const ToolsPage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.color_lens_outlined,
                  filledIcon: Icons.color_lens,
                  title: '外观与触感',
                  subtitle: '主题配色 · 振动反馈',
                  onTap: () => push(const AppearancePage()),
                ),
                const SizedBox(height: 10),
                _EntryCard(
                  icon: Icons.storage,
                  filledIcon: Icons.storage,
                  title: '存储管理',
                  subtitle: '空间占用与清理',
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show hintSnack, sharedAxisRoute;
import '../onboarding/welcome_page.dart';
import '../update/update_sheet.dart' show UpdateRow;
import 'widgets/settings_ui.dart';
import '../../l10n/l10n.dart';

/// 关于:身份 + 出处 + 法律。
///
/// 只放**别处看不到、又必须交代**的东西:版本、第三方数据与模型的来源、
/// 开源许可、免责。设置项一律不进这里。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.about)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                // 真的应用图标(资源已按自适应图标几何预合成,见 pubspec)
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 74,
                    height: 74,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  kAppName,
                  style: context.texts.titleLarge!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.l10n.appTagline,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$kAppVersion ($kAppBuild)',
                      style: mono(context, size: 12, color: scheme.outline),
                    ),
                    // 内测包发出去之后,反馈里最难对齐的就是"你装的是哪版",
                    // 版号旁边直接标出来
                    if (kIsPrerelease) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.l10n.beta,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SettingsLabel(context.l10n.version),
          const SettingsCard(children: [UpdateRow()]),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.dataResources),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.menu_book_outlined,
                title: context.l10n.codexSource,
                value: 'quicktagcloud.com',
                onTap: () => _open(context, kCodexSourceUrl),
              ),
              // 报的是**出处**,不是当前用的哪一档 —— 档位是设置项该管的事,
              // 关于页只交代东西从哪来。
              SettingsRow(
                icon: Icons.sell_outlined,
                title: context.l10n.offlineDict,
                value: 'Auto-NovelAI-Refactor',
                onTap: () => _open(context, kOfflineTagSourceUrl),
              ),
              SettingsRow(
                icon: Icons.translate_outlined,
                title: context.l10n.zhSearch,
                value: 'DanbooruSearchOnline',
                onTap: () => _open(context, kDanbooruSearchUrl),
              ),
              SettingsRow(
                icon: Icons.auto_awesome_outlined,
                title: context.l10n.imageGen,
                value: 'novelai.net',
                onTap: () => _open(context, kNovelAiUrl),
              ),
              SettingsRow(
                icon: Icons.blur_on,
                title: context.l10n.censorModel,
                value: 'anime_censor_detection',
                onTap: () => _open(context, kCensorModelUrl),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.community),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.forum_outlined,
                title: context.l10n.qqGroup,
                value: kQqGroupId,
                onTap: () => _copyQqGroup(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.guide),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.flag_outlined,
                title: context.l10n.reviewGuide,
                onTap: () => Navigator.of(
                  context,
                ).push(sharedAxisRoute(const WelcomePage(replay: true))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.legal),
          SettingsCard(
            children: [
              // 填了 kGithubRepo 才出现 —— 同一个常量也驱动「检查更新」,
              // 一处配置点亮两个功能,不会出现"有源码入口但查不了更新"的错位
              if (kGithubRepo.isNotEmpty)
                SettingsRow(
                  icon: Icons.code,
                  title: context.l10n.sourceCode,
                  value: kGithubRepo,
                  onTap: () =>
                      _open(context, 'https://github.com/$kGithubRepo'),
                ),
              SettingsRow(
                icon: Icons.balance_outlined,
                title: context.l10n.license,
                value: kLicense,
                onTap: () => _open(context, kLicenseUrl),
              ),
              SettingsRow(
                icon: Icons.description_outlined,
                title: context.l10n.thirdPartyLicenses,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: kAppName,
                  applicationVersion: '$kAppVersion ($kAppBuild)',
                  applicationLegalese: legalese(context.l10n),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              context.l10n.disclaimer(kAppName),
              style: context.texts.labelSmall!.copyWith(
                color: scheme.outline,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 复制群号。**不跳转** —— 短链会先弹浏览器再跳回 QQ,scheme 又得赌机型与
  /// QQ 版本;复制到剪贴板自己去搜,反而是唯一不会落空的那条。
  Future<void> _copyQqGroup(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: kQqGroupId));
    if (context.mounted) {
      hintSnack(context, context.l10n.qqCopied(kQqGroupId), icon: Icons.copy);
    }
  }

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      hintSnack(
        context,
        context.l10n.cantOpenBrowserShort,
        icon: Icons.link_off,
      );
    }
  }
}

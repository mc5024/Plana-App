import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show hintSnack;
import '../profile/widgets/settings_ui.dart';
import 'release_notes.dart';
import 'update_service.dart';
import '../../l10n/l10n.dart';

/// 「检查更新」行。放在关于页,按设置行规范:单行 + 右侧状态,不写副标题。
class UpdateRow extends ConsumerStatefulWidget {
  const UpdateRow({super.key});

  @override
  ConsumerState<UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends ConsumerState<UpdateRow> {
  bool _checking = false;
  UpdateCheck? _result;
  bool _failed = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _failed = false;
    });
    try {
      final installed = await installedInfo();
      final release = installed.isKnown
          ? await fetchLatestRelease(installed.versionName)
          : null;
      if (!mounted) return;
      final check = UpdateCheck(installed: installed, release: release);
      setState(() => _result = check);
      if (check.hasUpdate) {
        await showUpdateSheet(context, check);
      } else if (!installed.isKnown) {
        // 拿不到本机版本 —— 不是错误,别报红
        hintSnack(context, context.l10n.noUpdateInfo, icon: Icons.info_outline);
      } else {
        hintSnack(
          context,
          context.l10n.onLatestVersion,
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
      hintSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final r = _result;
    final (String value, Color? color) = switch (null) {
      _ when _checking => (context.l10n.checking, null),
      _ when _failed => (context.l10n.checkFailed, scheme.error),
      _ when r != null && r.hasUpdate => (
        context.l10n.newVersion(r.release!.display),
        scheme.tertiary,
      ),
      _ when r != null => (context.l10n.upToDate, null),
      _ => ('', null),
    };
    return SettingsRow(
      icon: Icons.system_update_alt,
      title: context.l10n.checkUpdates,
      value: value,
      valueColor: color,
      onTap: _check,
    );
  }
}

/// 新版本提示。只提示 + 交给浏览器打开下载地址(最新正式版是安装包直链),
/// **应用自己不下载不安装** —— 那两步交给浏览器和系统。
Future<void> showUpdateSheet(BuildContext context, UpdateCheck check) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _UpdateSheet(release: check.release!, installed: check.installed),
  );
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.release, required this.installed});

  final GithubRelease release;
  final InstalledInfo installed;

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      hintSnack(
        context,
        context.l10n.cantOpenBrowserShort,
        icon: Icons.link_off,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 26,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.newVersion(release.display),
                          style: context.texts.titleMedium!.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.currentVersion(installed.versionName),
                          style: context.texts.bodySmall!.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  // 更新说明是 GitHub 上的 Markdown 原文,长度不可控 —— 限高可滚,
                  // 不能让它把按钮顶出屏幕
                  constraints: const BoxConstraints(maxHeight: 260),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: ReleaseNotes(release.notes),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.later),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => _open(context, release.downloadUrl),
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(context.l10n.downloadUpdate),
                    ),
                  ),
                ],
              ),
              // 主按钮是后端直链时,留一个去 GitHub Release 页的入口
              if (release.downloadUrl != release.url) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _open(context, release.url),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(context.l10n.downloadOnGithub),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_settings.dart';
import '../../core/ui/theme_swatches.dart';
import '../../core/util/haptics.dart';
import '../../core/util/harmony_compat.dart';
import '../../l10n/l10n.dart';
import 'widgets/settings_ui.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.appearanceHaptics)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          SettingsLabel(context.l10n.language),
          SettingsCard(
            children: [
              _LanguageRow(
                value: ts.language,
                onChanged: (v) =>
                    notifier.patch((x) => x.copyWith(language: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.themeMode),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(context.l10n.followSystem),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(context.l10n.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(context.l10n.themeDark),
                      ),
                    ],
                    selected: {ts.mode},
                    onSelectionChanged: (s) =>
                        notifier.patch((x) => x.copyWith(mode: s.first)),
                    showSelectedIcon: false,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.themeColor),
          const SettingsCard(
            children: [
              Padding(padding: EdgeInsets.all(16), child: ThemeSwatches()),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.bottomNav),
          SettingsCard(
            children: [
              _SwitchRow(
                icon: Icons.auto_awesome,
                title: context.l10n.showAssistant,
                subtitle: context.l10n.showAssistantSub,
                value: ts.showAssistant,
                onChanged: (v) =>
                    notifier.patch((x) => x.copyWith(showAssistant: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.createPage),
          SettingsCard(
            children: [
              _SwitchRow(
                icon: Icons.view_agenda_outlined,
                title: context.l10n.compactCharCards,
                value: ts.compactCharCards,
                onChanged: (v) =>
                    notifier.patch((x) => x.copyWith(compactCharCards: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.haptics),
          SettingsCard(
            children: [
              _SwitchRow(
                icon: Icons.vibration,
                title: context.l10n.hapticFeedback,
                value: ts.haptics,
                onChanged: (v) => notifier.patch((x) => x.copyWith(haptics: v)),
              ),
            ],
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            SettingsLabel(context.l10n.galleryPicker),
            SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    // 没选过时按机型默认显示(容器里默认系统),检测返回前不选中
                    child: FutureBuilder<bool>(
                      future: isHarmonyCompatContainer,
                      builder: (context, snap) {
                        final system = ts.systemPicker ?? snap.data;
                        return SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text(context.l10n.inApp),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text(context.l10n.system),
                            ),
                          ],
                          selected: {?system},
                          emptySelectionAllowed: true,
                          onSelectionChanged: (s) {
                            if (s.isEmpty) return;
                            notifier.patch(
                              (x) => x.copyWith(systemPicker: s.first),
                            );
                          },
                          showSelectedIcon: false,
                        );
                      },
                    ),
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

/// 界面语言下拉。语言名各用本语言写,切错了也认得回来。
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final options = {
      '': context.l10n.followSystem,
      'zh': '中文',
      'en': 'English',
      'ja': '日本語',
    };
    return PopupMenuButton<String>(
      tooltip: context.l10n.uiLanguage,
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == value) return;
        Haptics.selection();
        onChanged(v);
      },
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem(
            value: e.key,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.value),
              trailing: e.key == value
                  ? Icon(Icons.check, size: 18, color: scheme.primary)
                  : null,
            ),
          ),
      ],
      child: SettingsRow(
        icon: Icons.translate,
        title: context.l10n.uiLanguage,
        value: options[value],
        dropdown: true,
      ),
    );
  }
}

/// 卡片里的一行开关。整行可点。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final sub = subtitle;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.texts.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.outline,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

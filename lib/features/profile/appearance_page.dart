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
      appBar: AppBar(title: const Text('外观与触感')),
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
          const SettingsLabel('深浅模式'),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
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
          const SettingsLabel('主题色'),
          const SettingsCard(
            children: [
              Padding(padding: EdgeInsets.all(16), child: ThemeSwatches()),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsLabel('底部导航'),
          SettingsCard(
            children: [
              _SwitchRow(
                icon: Icons.auto_awesome,
                title: '显示 AI 助手',
                subtitle: '关掉后底栏不再显示 AI 入口',
                value: ts.showAssistant,
                onChanged: (v) =>
                    notifier.patch((x) => x.copyWith(showAssistant: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsLabel('创作页'),
          SettingsCard(
            children: [
              _SwitchRow(
                icon: Icons.view_agenda_outlined,
                title: '紧凑角色卡',
                value: ts.compactCharCards,
                onChanged: (v) =>
                    notifier.patch((x) => x.copyWith(compactCharCards: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsLabel('触感'),
          SettingsCard(
            children: [
              _SwitchRow(
                icon: Icons.vibration,
                title: '振动反馈',
                value: ts.haptics,
                onChanged: (v) => notifier.patch((x) => x.copyWith(haptics: v)),
              ),
            ],
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            const SettingsLabel('图库选择器'),
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
                          segments: const [
                            ButtonSegment(value: false, label: Text('应用内')),
                            ButtonSegment(value: true, label: Text('系统')),
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

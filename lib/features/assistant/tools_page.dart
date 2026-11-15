/// 工具页:一个工具一张卡,卡头是工具开关,来源和选项排在卡里(工具关着时淡显)。
/// 版式与「我的」里的设置页同源([SettingsCard])。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../../l10n/l10n.dart';
import '../profile/widgets/settings_ui.dart';
import 'tools/agent_tool.dart';
import 'tools/tool_registry.dart';
import 'tools/tool_settings.dart';

class AssistantToolsPage extends ConsumerWidget {
  const AssistantToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(toolSettingsProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.assistantTools)),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                for (final t in kAgentTools)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ToolCard(tool: t, settings: s),
                  ),
              ],
            ),
    );
  }
}

class _ToolCard extends ConsumerWidget {
  const _ToolCard({required this.tool, required this.settings});

  final AgentTool tool;
  final ToolSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(toolSettingsProvider.notifier);
    final t = tool;
    final on = settings.toolOn(t.name);
    return SettingsCard(
      children: [
        _ToolRow(
          icon: t.icon,
          title: t.label,
          value: on,
          onChanged: (v) => n.setTool(t.name, v),
        ),
        if (t.sources.length > 1)
          for (final src in t.sources)
            _SubRow(
              icon: src.online
                  ? Icons.cloud_outlined
                  : Icons.smartphone_outlined,
              title: src.label,
              note: src.online ? context.l10n.toolSourceOnline : null,
              value: settings.sourceOn(t.name, src.id),
              enabled: on,
              onChanged: (v) => n.setSource(t.name, src.id, v),
            ),
        for (final o in t.options)
          _SubRow(
            icon: Icons.tune,
            title: o.label,
            note: o.desc,
            value: settings.optionOn(t.name, o.id),
            enabled: on,
            onChanged: (v) => n.setOption(t.name, o.id, v),
          ),
      ],
    );
  }
}

/// 卡头:工具图标 + 名字 + 开关,整行可点。
class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  void _flip(bool v) {
    Haptics.selection();
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: () => _flip(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: value ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: context.texts.bodyLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Switch(value: value, onChanged: _flip),
          ],
        ),
      ),
    );
  }
}

/// 卡里的一行来源 / 选项:和卡头的名字对齐,[note] 是标题下的一行小字。
class _SubRow extends StatelessWidget {
  const _SubRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.note,
  });

  final IconData icon;
  final String title;
  final String? note;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  void _flip(bool v) {
    Haptics.selection();
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: enabled ? () => _flip(!value) : null,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: enabled ? 1 : .42,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 4, 10, 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: value ? scheme.onSurfaceVariant : scheme.outline,
              ),
              const SizedBox(width: 10),
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
                    if (note != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        note!,
                        style: context.texts.labelSmall!.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: value, onChanged: enabled ? _flip : null),
            ],
          ),
        ),
      ),
    );
  }
}

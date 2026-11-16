/// 工具页:一个工具一张卡,卡头是工具开关,附带的选项收在卡头下一块浅底里
/// (工具关着时淡显、点不动)。卡片与「我的」里的设置页同源([SettingsCard])。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../../l10n/l10n.dart';
import '../profile/widgets/settings_ui.dart';
import 'image_gen/image_models.dart';
import 'tools/agent_tool.dart';
import 'tools/tool_registry.dart';
import 'tools/tool_settings.dart';
import 'widgets/model_sheet.dart' show showImageModelSheet;

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
                _ImageGenCard(settings: s),
              ],
            ),
    );
  }
}

/// 生成图片:不是查资料的工具,模型在回复里写出图块,App 拿去调出图模型。
class _ImageGenCard extends ConsumerWidget {
  const _ImageGenCard({required this.settings});

  final ToolSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(toolSettingsProvider.notifier);
    final on = settings.toolOn(kImageGenTool);
    final model = ref.watch(activeImageModelProvider);
    return _CardShell(
      header: _ToolRow(
        icon: Icons.image_outlined,
        title: context.l10n.toolGenerateImage,
        value: on,
        onChanged: (v) => n.setTool(kImageGenTool, v),
      ),
      enabled: on,
      options: [
        _PickRow(
          title: context.l10n.imageModelField,
          value: model?.name ?? context.l10n.notSet,
          enabled: on,
          onTap: () => showImageModelSheet(context),
        ),
        _SubRow(
          title: context.l10n.imageGenConfirm,
          value: settings.optionOn(kImageGenTool, kImageGenConfirm),
          enabled: on,
          onChanged: (v) => n.setOption(kImageGenTool, kImageGenConfirm, v),
        ),
      ],
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
    return _CardShell(
      header: _ToolRow(
        icon: t.icon,
        title: t.label,
        value: on,
        onChanged: (v) => n.setTool(t.name, v),
      ),
      enabled: on,
      options: [
        for (final o in t.options)
          _SubRow(
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

/// 一张工具卡:卡头 + 卡头下一块浅底装着的选项。没有选项就只有卡头。
class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.header,
    required this.enabled,
    this.options = const [],
  });

  final Widget header;
  final bool enabled;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        Column(
          children: [
            header,
            if (options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: AnimatedOpacity(
                  duration: Motion.fast,
                  opacity: enabled ? 1 : .42,
                  child: Material(
                    color: context.scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: options),
                  ),
                ),
              ),
          ],
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

/// 浅底里一行的最低高度:开关行、点开选的行一样高。
const _optionMinHeight = 52.0;

/// 浅底里点开选一项的一行:右边是选着的值。
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _optionMinHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
          child: Row(
            children: [
              Text(
                title,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 浅底里的一行开关,[note] 是标题下的一行小字。
class _SubRow extends StatelessWidget {
  const _SubRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.note,
  });

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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _optionMinHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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

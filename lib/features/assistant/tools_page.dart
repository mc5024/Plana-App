/// 工具页:一个工具一张卡,卡头是工具开关,附带的选项收在卡头下一块浅底里
/// (工具关着时淡显、点不动)。卡片与「我的」里的设置页同源([SettingsCard])。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../../l10n/l10n.dart';
import '../profile/widgets/settings_ui.dart';
import 'endpoints_page.dart' show openEndpointsPage;
import 'image_gen/image_models.dart';
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
                _ImageGenCard(settings: s),
              ],
            ),
    );
  }
}

/// 生成图片:不是查资料的工具,模型在回复里写出图块,App 拿去调出图模型。
/// 不在这里选模型:列出能用的出图模型和各自的触发词,原话里提到哪个就用哪个。
class _ImageGenCard extends ConsumerWidget {
  const _ImageGenCard({required this.settings});

  final ToolSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(toolSettingsProvider.notifier);
    final on = settings.toolOn(kImageGenTool);
    final models = ref.watch(imageModelChoicesProvider);
    return _CardShell(
      header: _ToolRow(
        icon: Icons.image_outlined,
        title: context.l10n.toolGenerateImage,
        value: on,
        onChanged: (v) => n.setTool(kImageGenTool, v),
      ),
      enabled: on,
      options: [
        for (final m in models)
          _PickRow(
            title: m.name,
            // 没授权的后端渠道只说暂未开放,不引导去授权
            value: m.available
                ? m.triggers.join(context.l10n.listSep)
                : context.l10n.notAvailableYet,
            enabled: on,
            // 接口里的点进去改触发词
            onTap: m.endpoint == null
                ? null
                : () => openEndpointsPage(context, editId: m.endpoint!.id),
          ),
        _PickRow(
          title: context.l10n.addImageModel,
          value: '',
          accent: true,
          enabled: on,
          onTap: () => openEndpointsPage(context),
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

/// 浅底里一行:标题 + 右边的值,能点的带箭头。[accent] = 操作行(主色字)。
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.title,
    required this.value,
    required this.enabled,
    this.onTap,
    this.accent = false,
  });

  final String title;
  final String value;
  final bool enabled;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final tap = onTap;
    return InkWell(
      onTap: enabled ? tap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _optionMinHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, tap == null ? 14 : 10, 0),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                // 标题最多占六成宽(模型 id 长),不把右边的触发词挤没
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * .6),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent ? scheme.primary : null,
                    ),
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
                if (tap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: scheme.outline),
                ],
              ],
            ),
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

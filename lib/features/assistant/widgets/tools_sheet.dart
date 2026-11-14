/// 工具页:每个工具一行开关;有多个来源、有附带选项的,接在下面一层(工具关着时淡显)。
/// 版式与助手设置同源([SettingSheet] / [SettingRow])。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/setting_row.dart';
import '../../../l10n/l10n.dart';
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../tools/tool_registry.dart';
import '../tools/tool_settings.dart';

Future<void> showToolsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => const _ToolsSheet(),
  );
  dropFocusSoon();
}

class _ToolsSheet extends ConsumerWidget {
  const _ToolsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(toolSettingsProvider).value;
    final n = ref.read(toolSettingsProvider.notifier);
    return SettingSheet(
      title: context.l10n.assistantTools,
      children: [
        if (s == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final t in kAgentTools) ...[
            SettingRow(
              icon: t.icon,
              title: t.label,
              desc: t.desc,
              value: s.toolOn(t.name),
              onChanged: (v) => n.setTool(t.name, v),
            ),
            if (t.sources.length > 1)
              for (final src in t.sources)
                _Nested(
                  SettingRow(
                    icon: src.online
                        ? Icons.cloud_outlined
                        : Icons.smartphone_outlined,
                    title: src.label,
                    desc: src.online
                        ? context.l10n.toolSourceOnline
                        : context.l10n.toolSourceOfflineDesc,
                    value: s.sourceOn(t.name, src.id),
                    enabled: s.toolOn(t.name),
                    onChanged: (v) => n.setSource(t.name, src.id, v),
                  ),
                ),
            for (final o in t.options)
              _Nested(
                SettingRow(
                  icon: Icons.tune,
                  title: o.label,
                  desc: o.desc,
                  value: s.optionOn(t.name, o.id),
                  enabled: s.toolOn(t.name),
                  onChanged: (v) => n.setOption(t.name, o.id, v),
                ),
              ),
          ],
      ],
    );
  }
}

/// 下一层的行:往里缩一格。
class _Nested extends StatelessWidget {
  const _Nested(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(left: 22), child: child);
}

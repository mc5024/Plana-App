/// 助手设置弹层。版式与编辑器设置同源([SettingSheet] / [SettingRow])——
/// 同一个 app 里两处设置长得不一样,用户会以为自己进错了地方。
///
/// 「自动」那几项都是把默认的手动改成自动,默认一律关着:这套流程的地基是
/// 「AI 碰创作页、花点数出图,两件事都得用户按一下」,打开哪一项都是用户明知
/// 自己在放权,不能替他决定。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/setting_row.dart';
import '../../generate/prompt_sections.dart' show SectionImport;
import '../../generate/widgets/common.dart' show dropFocusSoon, hintSnack;
import '../agent_model.dart' show assistantCapabilitiesProvider;
import '../assistant_settings.dart';
import '../application/assistant_controller.dart';
import '../presets/preset_rule.dart';
import '../presets/rules_library.dart';
import '../refusal_keywords_page.dart';
import '../rules_page.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_settings.dart';
import '../tools_page.dart';
import '../../../l10n/l10n.dart';

Future<void> showAssistantSettings(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // 抓手和圆角由 SettingSheet 自己画(与编辑器设置同一套),
    // 所以这儿把系统那份关掉、底色让给它。
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => const _SettingsSheet(),
  );
  dropFocusSoon();
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(assistantSettingsProvider).value;
    final n = ref.read(assistantSettingsProvider.notifier);
    final caps = ref.watch(assistantCapabilitiesProvider);
    final tools = ref.watch(toolSettingsProvider).value;
    return SettingSheet(
      title: context.l10n.assistantSettings,
      children: [
        if (s == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          settingSection(context, context.l10n.settingDisplay),
          SettingStepperRow(
            icon: Icons.format_size,
            title: context.l10n.settingMessageSize,
            desc: context.l10n.settingMessageSizeDesc,
            value: s.fontSize,
            min: AssistantSettings.fontSizeMin,
            max: AssistantSettings.fontSizeMax,
            step: AssistantSettings.fontSizeStep,
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) => n.patch((o) => o.copyWith(fontSize: v)),
          ),
          // 当前模型不能逐字显示时置灰,显示生效的「关」
          SettingRow(
            icon: Icons.keyboard_outlined,
            title: context.l10n.streamOutput,
            desc: caps.streaming
                ? context.l10n.streamOutputDesc
                : context.l10n.modelUnsupported,
            value: caps.streaming && s.stream,
            enabled: caps.streaming,
            onChanged: (v) => n.patch((o) => o.copyWith(stream: v)),
          ),
          settingSection(context, context.l10n.settingDraw),
          SettingRow(
            icon: Icons.notes,
            title: context.l10n.plainTextFormat,
            desc: context.l10n.plainTextFormatDesc,
            value: s.noDraw,
            onChanged: (v) => n.patch((o) => o.copyWith(noDraw: v)),
          ),
          SettingChoiceRow<SectionImport>(
            icon: Icons.splitscreen_outlined,
            title: context.l10n.importMode,
            desc: context.l10n.importModeDesc,
            enabled: !s.noDraw,
            value: s.importTo,
            options: SectionImport.values,
            labelOf: sectionImportLabel,
            onChanged: (v) => n.patch((o) => o.copyWith(importTo: v)),
          ),
          settingSection(context, context.l10n.settingAuto),
          // 纯文本格式开着时这两项不会发生,淡显
          SettingRow(
            icon: Icons.bolt_outlined,
            title: context.l10n.autoDraw,
            desc: context.l10n.autoDrawDesc,
            enabled: !s.noDraw,
            value: s.autoGenerate,
            onChanged: (v) => n.patch((o) => o.copyWith(autoGenerate: v)),
          ),
          SettingRow(
            icon: Icons.image_outlined,
            title: context.l10n.inlineImages,
            desc: context.l10n.inlineImagesDesc,
            value: s.inlineImage,
            onChanged: (v) => n.patch((o) => o.copyWith(inlineImage: v)),
          ),
          SettingRow(
            icon: Icons.draw_outlined,
            title: context.l10n.autoWrite,
            desc: context.l10n.autoWriteDesc,
            enabled: !s.noDraw,
            value: s.autoImport,
            onChanged: (v) => n.patch((o) => o.copyWith(autoImport: v)),
          ),
          settingSection(context, context.l10n.settingChat),
          SettingStepperRow(
            icon: Icons.history,
            title: context.l10n.contextTurns,
            desc: context.l10n.contextTurnsDesc,
            value: s.historyTurns.toDouble(),
            min: AssistantSettings.historyTurnsMin.toDouble(),
            max: AssistantSettings.historyTurnsMax.toDouble(),
            step: AssistantSettings.historyTurnsStep.toDouble(),
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) =>
                n.patch((o) => o.copyWith(historyTurns: v.round())),
          ),
          SettingStepperRow(
            icon: Icons.replay,
            title: context.l10n.failRetries,
            desc: context.l10n.failRetriesDesc,
            value: s.retries.toDouble(),
            min: 0,
            max: AssistantSettings.retriesMax.toDouble(),
            step: 1,
            format: (v) => _countLabel(context, v),
            onChanged: (v) => n.patch((o) => o.copyWith(retries: v.round())),
          ),
          SettingRow(
            icon: Icons.hide_image_outlined,
            title: context.l10n.retryStripImage,
            desc: context.l10n.retryStripImageDesc,
            enabled: s.retries > 0,
            value: s.retryStripImage,
            onChanged: (v) => n.patch((o) => o.copyWith(retryStripImage: v)),
          ),
          SettingStepperRow(
            icon: Icons.casino_outlined,
            title: context.l10n.refusalRetries,
            desc: context.l10n.refusalRetriesDesc,
            value: s.rerolls.toDouble(),
            min: 0,
            max: AssistantSettings.retriesMax.toDouble(),
            step: 1,
            format: (v) => _countLabel(context, v),
            onChanged: (v) => n.patch((o) => o.copyWith(rerolls: v.round())),
          ),
          SettingNavRow(
            icon: Icons.label_outline,
            title: context.l10n.refusalKeywords,
            desc: context.l10n.refusalKeywordsDesc,
            value: context.l10n.keywordsN(s.refusalKeywords.length),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RefusalKeywordsPage(),
              ),
            ),
          ),
          settingSection(context, context.l10n.settingLibrary),
          SettingNavRow(
            icon: Icons.handyman_outlined,
            title: context.l10n.assistantTools,
            desc: context.l10n.assistantToolsDesc,
            value: tools == null
                ? ''
                : context.l10n.toolsEnabledN(enabledTools(tools).length),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AssistantToolsPage(),
              ),
            ),
          ),
          settingSection(context, context.l10n.settingRules),
          SettingNavRow(
            icon: Icons.rule_outlined,
            title: context.l10n.rulePresets,
            desc: context.l10n.rulePresetsDesc,
            value: _rulesValue(ref),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RulesPresetPage()),
            ),
          ),
          settingSection(context, context.l10n.settingDebug),
          SettingNavRow(
            icon: Icons.bug_report_outlined,
            title: context.l10n.exportChatLog,
            desc: context.l10n.exportChatLogDesc,
            value: switch (ref.read(assistantProvider.notifier).traceCount) {
              0 => '',
              final n => context.l10n.turnsN(n),
            },
            onTap: () => _exportTrace(context, ref),
          ),
        ],
      ],
    );
  }
}

String _countLabel(BuildContext context, double v) =>
    v == 0 ? context.l10n.off : v.toStringAsFixed(0);

/// 导出成一个文本文件,存到用户选的位置。内容见 `renderTraceExport`。
Future<void> _exportTrace(BuildContext context, WidgetRef ref) async {
  if (ref.read(assistantProvider).msgs.isEmpty) {
    hintSnack(context, context.l10n.chatEmpty, icon: Icons.info_outline);
    return;
  }
  try {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final path = await FilePicker.platform.saveFile(
      fileName: 'plana-assistant-$stamp.txt',
      bytes: utf8.encode(ref.read(assistantProvider.notifier).exportTrace()),
    );
    if (path != null && context.mounted) {
      hintSnack(
        context,
        context.l10n.chatLogExported,
        icon: Icons.check_circle_outline,
      );
    }
  } catch (e) {
    if (context.mounted) {
      hintSnack(
        context,
        context.l10n.exportFailed('$e'),
        icon: Icons.error_outline,
      );
    }
  }
}

/// 规则那一行右边的状态:两个模型都用默认规则就是「默认」;都用同一份导入的预设
/// 就报它的名字;两边各用各的只说「自定义」,名字留给点进去的那一页。
String _rulesValue(WidgetRef ref) {
  final lib = ref.watch(rulesLibraryProvider).value;
  if (lib == null) return '';
  final used = [for (final f in RulesFamily.values) lib.activeFor(f)];
  if (used.every((p) => p.isDefault)) return l10nNow.presetGroupDefault;
  if (used.every((p) => p.id == used.first.id)) return used.first.name;
  return l10nNow.sizeCustom;
}

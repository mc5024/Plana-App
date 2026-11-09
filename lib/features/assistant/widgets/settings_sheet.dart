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
import '../agent_model.dart'
    show assistantBotAuthorizedProvider, assistantEndpointProvider;
import '../assistant_settings.dart';
import '../assistant_state.dart';
import '../preset_rules.dart';
import '../rules_page.dart';

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
    final authorized = ref.watch(assistantBotAuthorizedProvider);
    final customEndpoint = ref.watch(assistantEndpointProvider) != null;
    return SettingSheet(
      title: '助手设置',
      children: [
        if (s == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          settingSection(context, '显示'),
          SettingStepperRow(
            icon: Icons.format_size,
            title: '消息字号',
            desc: '对话消息的文字显示大小',
            value: s.fontSize,
            min: AssistantSettings.fontSizeMin,
            max: AssistantSettings.fontSizeMax,
            step: AssistantSettings.fontSizeStep,
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) => n.patch((o) => o.copyWith(fontSize: v)),
          ),
          SettingRow(
            icon: Icons.keyboard_outlined,
            title: '流式输出',
            desc: '逐字显示回复',
            value: s.stream,
            onChanged: (v) => n.patch((o) => o.copyWith(stream: v)),
          ),
          settingSection(context, '出图'),
          SettingRow(
            icon: Icons.notes,
            title: '纯文本格式',
            desc: '提示词只显示为文本,不导入也不出图',
            value: s.noDraw,
            onChanged: (v) => n.patch((o) => o.copyWith(noDraw: v)),
          ),
          SettingChoiceRow<SectionImport>(
            icon: Icons.splitscreen_outlined,
            title: '导入方式',
            desc: '提示词写入创作页主提示词的位置',
            enabled: !s.noDraw,
            value: s.importTo,
            options: SectionImport.values,
            labelOf: sectionImportLabel,
            onChanged: (v) => n.patch((o) => o.copyWith(importTo: v)),
          ),
          settingSection(context, '自动'),
          // 纯文本格式开着时这两项不会发生,淡显
          SettingRow(
            icon: Icons.bolt_outlined,
            title: '生成提示词后自动出图',
            desc: '提示词生成完成后立即开始出图',
            enabled: !s.noDraw,
            value: s.autoGenerate,
            onChanged: (v) => n.patch((o) => o.copyWith(autoGenerate: v)),
          ),
          SettingRow(
            icon: Icons.image_outlined,
            title: '在对话内显示图片',
            desc: '生成的图片显示在对话内,同时保存至图库',
            value: s.inlineImage,
            onChanged: (v) => n.patch((o) => o.copyWith(inlineImage: v)),
          ),
          SettingRow(
            icon: Icons.draw_outlined,
            title: '自动写入创作页',
            desc: '生成的提示词自动写回创作页,无需手动导入',
            enabled: !s.noDraw,
            value: s.autoImport,
            onChanged: (v) => n.patch((o) => o.copyWith(autoImport: v)),
          ),
          settingSection(context, '对话'),
          SettingStepperRow(
            icon: Icons.history,
            title: '上下文轮数',
            desc: '每次发送带上最近几轮对话',
            value: s.historyTurns.toDouble(),
            min: AssistantSettings.historyTurnsMin.toDouble(),
            max: AssistantSettings.historyTurnsMax.toDouble(),
            step: AssistantSettings.historyTurnsStep.toDouble(),
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) =>
                n.patch((o) => o.copyWith(historyTurns: v.round())),
          ),
          settingSection(context, '资料'),
          SettingChoiceRow<LibraryScope>(
            icon: Icons.library_books_outlined,
            title: '资料库范围',
            desc: '查询画师串与角色时使用的资料来源',
            value: effectiveLibraryScope(
              s.libraryScope,
              botAuthorized: authorized,
            ),
            options: LibraryScope.values,
            labelOf: libraryScopeLabel,
            optionEnabled: (o) =>
                libraryScopeAllowed(o, botAuthorized: authorized),
            optionNote: (o) => libraryScopeAllowed(o, botAuthorized: authorized)
                ? libraryScopeDesc(o)
                : '暂未开放',
            onChanged: (v) => n.patch((o) => o.copyWith(libraryScope: v)),
          ),
          SettingRow(
            icon: Icons.person_outline,
            title: 'OC 使用占位符',
            desc: customEndpoint
                ? '本地与公共 OC 只给 AI 占位符，出图时还原；调整原设时请关闭'
                : '仅自定义接口渠道可用',
            value: customEndpoint && s.ocPlaceholders,
            enabled: customEndpoint,
            onChanged: (v) => n.patch((o) => o.copyWith(ocPlaceholders: v)),
          ),
          settingSection(context, '规则'),
          SettingNavRow(
            icon: Icons.rule_outlined,
            title: '规则预设',
            desc: '生成提示词时遵循的规则',
            value: _rulesValue(ref),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RulesPresetPage()),
            ),
          ),
          settingSection(context, '调试'),
          SettingNavRow(
            icon: Icons.bug_report_outlined,
            title: '导出对话记录',
            desc: '当前对话每一轮发给 AI 的内容和返回',
            value: switch (ref.read(assistantProvider.notifier).traceCount) {
              0 => '',
              final n => '$n 轮',
            },
            onTap: () => _exportTrace(context, ref),
          ),
        ],
      ],
    );
  }
}

/// 导出成一个文本文件,存到用户选的位置。内容见 `renderTraceExport`。
Future<void> _exportTrace(BuildContext context, WidgetRef ref) async {
  if (ref.read(assistantProvider).msgs.isEmpty) {
    hintSnack(context, '当前对话是空的', icon: Icons.info_outline);
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
      hintSnack(context, '已导出对话记录', icon: Icons.check_circle_outline);
    }
  } catch (e) {
    if (context.mounted) {
      hintSnack(context, '导出失败:$e', icon: Icons.error_outline);
    }
  }
}

/// 规则那一行右边的状态:两个模型都用默认规则就是「默认」;都用同一份导入的预设
/// 就报它的名字;两边各用各的只说「自定义」,名字留给点进去的那一页。
String _rulesValue(WidgetRef ref) {
  final lib = ref.watch(rulesLibraryProvider).value;
  if (lib == null) return '';
  final used = [for (final f in RulesFamily.values) lib.activeFor(f)];
  if (used.every((p) => p.isDefault)) return '默认';
  if (used.every((p) => p.id == used.first.id)) return used.first.name;
  return '自定义';
}

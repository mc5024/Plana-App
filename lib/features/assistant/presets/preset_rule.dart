/// 规则预设的一段,以及按对话模式挑段。
///
/// 规则主体只讲怎么写提示词;怎么调工具是 app 的工具层,见 `runtime/prompt_composer.dart`。
library;

import '../../../l10n/l10n.dart';

/// 与服务端 `schemas.PRESET_RULES_MAX_*` 一致。导入时就卡住,别等发出去才被拒。
const kRulesMaxSections = 40;
const kRulesMaxChars = 60000;

/// 工具层那一段的段名。预设里有同名段一律当旧货丢掉 —— 工具层只认 app 自带的那份。
const kToolLayerName = 'tool_usage';

enum RulesFamily { nai45, nai5 }

String rulesFamilyLabel(RulesFamily f) => switch (f) {
  RulesFamily.nai45 => 'NAI 4.5',
  RulesFamily.nai5 => 'NAI 5',
};

/// 图片模型档位(`agentImageModel` 的产物) → 用哪一份规则:`nai_v5` 开头的是 5,其余回落 4.5。
RulesFamily rulesFamilyOf(String imageModel) =>
    imageModel.startsWith('nai_v5') ? RulesFamily.nai5 : RulesFamily.nai45;

/// 开头的空行(含只有空白的行)。
final _leadingBlankLines = RegExp(r'^(?:[ \t]*\r?\n)+');

class PresetRule {
  const PresetRule({required this.name, required this.content, this.when = ''});

  /// 段名,与服务端预设 yaml 的 name 同义。
  final String name;
  final String content;

  /// 条件段的模式名(如 `comic`、`mode:natural`),空 = 常驻。
  final String when;

  Map<String, dynamic> toJson() => {
    'name': name,
    'content': content,
    if (when.isNotEmpty) 'when': when,
  };

  static PresetRule? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = '${j['name'] ?? ''}'.trim();
    // 只去掉首尾的空行和行尾空白,不动第一行的缩进;YAML 的 `|` 块末尾补的换行也去掉
    final content = '${j['content'] ?? ''}'
        .replaceFirst(_leadingBlankLines, '')
        .trimRight();
    if (name.isEmpty || content.isEmpty) return null;
    return PresetRule(
      name: name,
      content: content,
      when: '${j['when'] ?? ''}'.trim(),
    );
  }
}

/// `['nai45', 'nai5']` 这类写法 → 模型集合,认不出的忽略。
Set<RulesFamily> decodeModels(Object? raw) {
  final names = switch (raw) {
    final List l => [for (final e in l) '$e'.trim()],
    final String s => s.split(RegExp(r'[,\s]+')),
    _ => const <String>[],
  };
  return {
    for (final n in names)
      ?RulesFamily.values.where((f) => f.name == n).firstOrNull,
  };
}

/// 模式段的 when 前缀:`mode:comic`、`mode:natural` 这类是用户手动选的模式
/// (输入框上方的模式开关,见 assistant_mode.dart)。
const kModeWhenPrefix = 'mode:';

/// when 前面加 `!` = 没选这个模式才发,给「某个模式下要换掉的段」用。默认规则里混合写法的
/// prompt_construction 写 `!mode:natural`,选了仅自然语言就换成 natural_construction。
const kWhenNotPrefix = '!';

/// 按用户选的模式([chosen],见 `assistantModeKeys`)挑段,拼成一整块:
///   · 不带条件的永远留;
///   · 带条件的只在选了那个模式时留;
///   · `!` 开头的反过来,没选才留。
String renderRules(List<PresetRule> rules, List<String> chosen) => [
  for (final r in rules)
    if (_whenWanted(r.when, chosen)) r.content,
].join('\n\n');

bool _whenWanted(String when, List<String> chosen) {
  if (when.isEmpty) return true;
  if (when.startsWith(kWhenNotPrefix)) {
    return !chosen.contains(when.substring(kWhenNotPrefix.length).trim());
  }
  return chosen.contains(when);
}

/// 超限时的提示,没超限返回 null。[reserveChars] 是给之后挂上去的工具层留的。
String? rulesLimitError(List<PresetRule> rules, {int reserveChars = 0}) {
  if (rules.length + (reserveChars > 0 ? 1 : 0) > kRulesMaxSections) {
    return l10nNow.rulesTooManySections(
      kRulesMaxSections - (reserveChars > 0 ? 1 : 0),
    );
  }
  final total = rules.fold<int>(
    0,
    (n, r) => n + r.name.length + r.content.length,
  );
  final cap = kRulesMaxChars - reserveChars;
  if (total > cap) return l10nNow.rulesTooLong(cap);
  return null;
}

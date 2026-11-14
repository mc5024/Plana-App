/// 规则文件:YAML,段落写法与服务端预设文件一致(name / when / content: |),两边的段可以
/// 直接互相复制;导入时也认一整份服务端预设文件,只取其中 group: rules 那段。
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../../l10n/l10n.dart';
import 'preset_rule.dart';

const _fileFormat = 'plana-rules';

/// 导入时给工具层留的余量:发出去的是「预设 + 工具层」,整份还得在服务端上限里。
const _toolLayerReserveChars = 6000;

/// 读出来的规则文件。名字、作者、模型文件里可能没写(比如一整份服务端预设),
/// 由导入界面让用户补上。
class RulesFile {
  const RulesFile({
    required this.name,
    required this.author,
    required this.models,
    required this.rules,
  });

  final String name;
  final String author;
  final Set<RulesFamily> models;
  final List<PresetRule> rules;
}

/// 预设 → 文件文本。
String encodeRulesFile({
  required String name,
  required String author,
  required Set<RulesFamily> models,
  required List<PresetRule> rules,
}) {
  final b = StringBuffer()
    ..writeln(l10nNow.rulesHeader1)
    ..writeln(l10nNow.rulesHeader2)
    ..writeln(l10nNow.rulesHeader3)
    ..writeln(l10nNow.rulesHeader4)
    ..writeln('format: $_fileFormat')
    ..writeln('version: 2')
    // 名字、作者用 JSON 字符串写:JSON 的双引号串本身就是合法 YAML,
    // 里面带冒号、井号也不会被读歪
    ..writeln('name: ${jsonEncode(name)}')
    ..writeln('author: ${jsonEncode(author)}')
    ..writeln(
      'models: [${[for (final m in RulesFamily.values)
        if (models.contains(m)) m.name].join(', ')}]',
    )
    ..writeln('sections:');
  for (final r in rules) {
    b.writeln('  - name: ${jsonEncode(r.name)}');
    if (r.when.isNotEmpty) b.writeln('    when: ${jsonEncode(r.when)}');
    final lines = r.content.split('\n');
    // 第一行以空格开头时必须写缩进指示符,否则 YAML 会把那几个空格当成缩进吃掉
    final firstIndented = lines
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .startsWith(RegExp(r'\s'));
    b.writeln('    content: |${firstIndented ? '2' : ''}');
    for (final l in lines) {
      b.writeln(l.isEmpty ? '' : '      $l');
    }
  }
  return b.toString();
}

/// 文件文本 → 规则文件。认三种:本 app 导出的预设(v2)、上一版导出的无名规则
/// (v1,只有一个 `model`),以及一整份服务端预设。
///
/// [fileName] 用来补缺:文件里没写名字就用文件名;服务端预设文件名里带着
/// `nai5` / `nai45`,顺手认出支持的模型。
RulesFile decodeRulesFile(String text, {String fileName = ''}) {
  final Object? doc;
  try {
    doc = loadYaml(text);
  } on YamlException catch (e) {
    // 带上行号:全文编辑里改坏了,几万字的规则光说一句「格式不对」没法找
    final line = e.span?.start.line;
    throw FormatException(
      line == null
          ? l10nNow.badFileFormat(e.message)
          : l10nNow.badFileFormatLine(line + 1, e.message),
    );
  }
  if (doc is! Map) throw FormatException(l10nNow.noSections);

  final sections = doc['sections'];
  if (sections is! List) throw FormatException(l10nNow.noSections);

  // 带 group 字段的是一整份服务端预设:只取规则主体那段,外壳不要
  final isServerPreset = sections.any(
    (s) => s is Map && s.containsKey('group'),
  );
  final rules = <PresetRule>[];
  for (final s in sections) {
    if (s is! Map) continue;
    if (isServerPreset && '${s['group'] ?? ''}'.trim() != 'rules') continue;
    // 工具层 app 自带:服务端预设里标了 layer: tools 的、以及老文件里同名的那段都不要
    if ('${s['layer'] ?? ''}'.trim() == 'tools') continue;
    final rule = PresetRule.fromJson(s);
    if (rule == null || rule.name == kToolLayerName) continue;
    rules.add(rule);
  }
  if (rules.isEmpty) throw FormatException(l10nNow.noUsableRules);
  final err = rulesLimitError(rules, reserveChars: _toolLayerReserveChars);
  if (err != null) throw FormatException(err);

  final base = fileName.replaceFirst(RegExp(r'\.[^.]*$'), '').trim();
  var models = decodeModels(doc['models']);
  if (models.isEmpty) models = decodeModels(doc['model']); // v1
  if (models.isEmpty && isServerPreset) {
    // prompts_nai5.yaml / prompts_nai45.yaml 这类:按文件名认
    final m = RegExp(r'nai(45|5)(?![0-9])').firstMatch(base.toLowerCase());
    if (m != null) models = decodeModels('nai${m.group(1)}');
  }
  return RulesFile(
    name: '${doc['name'] ?? ''}'.trim().isNotEmpty
        ? '${doc['name']}'.trim()
        : base,
    author: '${doc['author'] ?? ''}'.trim(),
    models: models,
    rules: rules,
  );
}

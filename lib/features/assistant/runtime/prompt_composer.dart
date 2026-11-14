/// 系统提示怎么拼:规则(按模式挑段,工具约定挂在 role 后面)→ 出图格式 → 工具清单 →
/// 各工具按选项补的说明。
library;

import '../domain/turn_request.dart';
import '../presets/preset_rule.dart';

/// 把工具约定挂到一份预设上。
///
/// 预设里原有的同名段先丢掉;工具约定放在 `role` 后面,没有 `role` 段的接在最后,
/// 别把工具说明顶到人设前面。[toolLayer] 为空就只是去掉旧段。
List<PresetRule> withToolLayer(List<PresetRule> rules, String toolLayer) {
  final body = [
    for (final r in rules)
      if (r.name != kToolLayerName) r,
  ];
  if (toolLayer.trim().isEmpty) return body;
  final layer = PresetRule(name: kToolLayerName, content: toolLayer.trim());
  final i = body.indexWhere((r) => r.name == 'role');
  // 别写成 `i < 0 ? [...] : [...]..insert(...)`:级联 `..` 的优先级比三元低,
  // 会作用在整个三元的结果上,没有 role 时工具层被插两遍
  if (i < 0) return [...body, layer];
  return [...body]..insert(i + 1, layer);
}

/// [modes] 是用户选的模式(见 `assistantModeKeys`);没有可用工具时 [toolLayer]、[toolList] 传空串。
String composeSystemPrompt({
  required List<PresetRule> rules,
  required List<String> modes,
  String toolLayer = '',
  String outputFormat = '',
  String toolList = '',
  List<String> notes = const [],
}) => [
  renderRules(withToolLayer(rules, toolLayer), modes),
  outputFormat.trim(),
  toolList.trim(),
  for (final n in notes) n.trim(),
].where((s) => s.isNotEmpty).join('\n\n');

/// 画布 → `[当前画面提示词]` 块,[intro] 是块前那句(见 texts.yaml 的 canvas_intro)。
String canvasBlockOf(CanvasSnapshot c, String intro) {
  final lines = <String>[
    intro,
    '[当前画面提示词]',
    'positive: ${c.positive.trim().isEmpty ? "(空)" : c.positive}',
    'negative: ${c.negative.trim().isEmpty ? "(空)" : c.negative}',
  ];
  if (c.characters.isNotEmpty) {
    lines.add('characters:');
    for (final ch in c.characters) {
      lines.add('  - name: ${ch['name']}');
      final pos = (ch['positive'] as String? ?? '').trim();
      lines.add('    positive: ${pos.isEmpty ? "(空)" : pos}');
      final neg = (ch['negative'] as String? ?? '').trim();
      if (neg.isNotEmpty) lines.add('    negative: $neg');
      final at = (ch['position'] as String? ?? '').trim();
      if (at.isNotEmpty) lines.add('    position: $at');
    }
  }
  return lines.join('\n');
}

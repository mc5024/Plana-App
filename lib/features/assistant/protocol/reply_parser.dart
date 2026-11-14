/// 模型回复怎么读:正文、`<Think>` 段、```nai_draw 出图块,以及流到一半时气泡里该显示什么。
library;

import 'dart:convert';

import '../domain/agent_event.dart' show AgentDelta;
import '../llm/llm_provider.dart' show LlmText;
import 'fenced_protocol.dart' show toolFence;

final _drawFence = RegExp(
  r'```[ \t]*nai_draw[ \t]*\r?\n(.*?)```',
  dotAll: true,
  caseSensitive: false,
);
final _thinkTag = RegExp(
  r'<Think>.*?</Think>',
  dotAll: true,
  caseSensitive: false,
);

// 流到一半时切正文用的几把尺子(见 [streamView])。流中途的 `<Think>` 多半还没收尾,
// 得按「开标签之后全是思考」算。
final _thinkOpen = RegExp(r'<Think>', caseSensitive: false);
final _thinkClose = RegExp(r'</Think>', caseSensitive: false);
final _liveFenceOpen = RegExp(
  r'```[ \t]*(?:tool_call|nai_draw)',
  caseSensitive: false,
);

/// 收到一半的标签 / 围栏头(`<Thi`、` ```na `):下一帧本来就会被认出来,少显示一帧不亏。
///
/// 反引号后面**必须跟着字母**才算:光秃秃的 ``` 多半是代码块的收尾、`…` 是行内代码的收尾。
final _liveTail = RegExp(r'(?:<[A-Za-z/]{0,6}|`{1,3}[ \t]*[A-Za-z_]{1,9})$');

/// 一条回复 → 给用户看的正文 + 出图块。剥掉 `<Think>` 段和全部围栏(工具调用的也剥)。
///
/// 出图块取**最后**一个:模型偶尔先写一版再改一版,后写的是它的结论。围栏里不是合法 JSON
/// 当这轮没出图,正文照常给。
({String reply, Map<String, dynamic>? draw}) parseReply(String raw) {
  var text = raw.replaceAll(_thinkTag, '');
  Map<String, dynamic>? draw;
  for (final m in _drawFence.allMatches(text)) {
    try {
      final j = jsonDecode(m.group(1)!.trim());
      if (j is Map<String, dynamic>) draw = j;
    } catch (_) {}
  }
  text = text.replaceAll(_drawFence, '').replaceAll(toolFence, '');
  return (reply: text.trim(), draw: draw);
}

/// 流到一半的原文 → 气泡里该显示的两块。
///
/// 每帧拿全量原文重算:`</Think>` 收尾那一刻正文会整段挪位。正文到第一个 ```tool_call /
/// ```nai_draw 围栏为止;普通的 ``` 代码块照留。`<Think>` 段(含还没收尾的)划到思考那边。
({String body, String think}) streamView(String raw) {
  final think = <String>[];
  final body = StringBuffer();
  var pos = 0;
  for (final m in _thinkOpen.allMatches(raw)) {
    if (m.start < pos) continue; // 上一段 <Think> 内部的,不重复处理
    body.write(raw.substring(pos, m.start));
    final close = _thinkClose.firstMatch(raw.substring(m.end));
    if (close == null) {
      think.add(raw.substring(m.end)); // 还没收尾:后面全算思考
      pos = raw.length;
      break;
    }
    think.add(raw.substring(m.end, m.end + close.start));
    pos = m.end + close.end;
  }
  if (pos < raw.length) body.write(raw.substring(pos));
  var text = body.toString();
  final fence = _liveFenceOpen.firstMatch(text);
  if (fence != null) text = text.substring(0, fence.start);
  return (
    body: text.replaceFirst(_liveTail, '').trim(),
    think: think.join('\n').trim(),
  );
}

/// 模型这一刻的全量回复 → 气泡里实时显示的那一帧。
AgentDelta liveDeltaOf(LlmText c) {
  final v = streamView(c.text);
  return AgentDelta(
    text: v.body,
    reasoning: [
      c.reasoning.trim(),
      v.think,
    ].where((s) => s.isNotEmpty).join('\n'),
  );
}

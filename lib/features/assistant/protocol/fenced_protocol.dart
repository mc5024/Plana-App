import 'dart:convert';

import '../runtime/prompt_assets.dart';
import '../tools/agent_tool.dart';
import 'tool_protocol.dart';

/// ```tool_call 围栏,块内一行 JSON `{"name": ..., "arguments": {...}}`。
final toolFence = RegExp(
  r'```[ \t]*tool_call[ \t]*\r?\n(.*?)```',
  dotAll: true,
  caseSensitive: false,
);

/// 写坏的调用回灌时原文最多带这么多字。
const _maxBrokenBody = 200;

/// 文本围栏:模型在正文里写 ```tool_call 代码块,结果以一条 user 消息回灌。
class FencedToolProtocol implements ToolProtocol {
  const FencedToolProtocol();

  @override
  Future<String> conventions() => toolLayerText();

  @override
  Future<String> toolList(List<AgentTool> tools) async {
    if (tools.isEmpty) return '';
    final lines = ['[可用工具] 参数名与说明以本表为准'];
    for (final t in tools) {
      final params = [
        for (final p in t.params)
          '${p.name}: ${p.type}${p.required ? '（必填）' : ''}',
      ].join(', ');
      lines
        ..add('- ${t.name}')
        ..add('  参数: ${params.isEmpty ? '无' : params}');
      for (final l in (await t.guidance()).split('\n')) {
        lines.add(l.isEmpty ? '' : '  $l');
      }
    }
    return lines.join('\n');
  }

  @override
  ParsedToolCalls parse(String reply) {
    final calls = <ToolCall>[];
    final broken = <BrokenToolCall>[];
    for (final m in toolFence.allMatches(reply)) {
      final body = m[1]!.trim();
      Object? j;
      try {
        j = jsonDecode(body);
      } on FormatException catch (e) {
        broken.add(BrokenToolCall(body, e.message));
        continue;
      }
      if (j is! Map) {
        broken.add(BrokenToolCall(body, '顶层不是对象'));
        continue;
      }
      final name = '${j['name'] ?? ''}'.trim();
      final args = j['arguments'] ?? const <String, dynamic>{};
      if (name.isEmpty) {
        broken.add(BrokenToolCall(body, '缺 name'));
      } else if (args is! Map<String, dynamic>) {
        broken.add(BrokenToolCall(body, 'arguments 不是对象'));
      } else {
        calls.add(ToolCall(name, args));
      }
    }
    return ParsedToolCalls(calls, broken: broken);
  }

  @override
  String resultMessage(
    List<ToolCallResult> results,
    List<BrokenToolCall> broken,
    PromptTexts texts,
  ) => texts.get('tool_results', {
    'count': '${results.length + broken.length}',
    'results': [
      for (final r in results) '[${r.call.name}] ${_resultText(r, texts)}',
      for (final b in broken)
        texts.get('tool_bad_json', {
          'error': b.error,
          'body': b.body.length > _maxBrokenBody
              ? '${b.body.substring(0, _maxBrokenBody)}…'
              : b.body,
        }),
    ].join('\n\n'),
  });

  static String _resultText(ToolCallResult r, PromptTexts texts) {
    if (r.error case final e?) return texts.get('tool_failed', {'error': e});
    final data = jsonEncode(r.data);
    return r.repeat ? '${texts.get('tool_repeat')}\n$data' : data;
  }
}

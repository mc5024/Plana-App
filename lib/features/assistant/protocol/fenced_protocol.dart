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
    final broken = <String>[];
    for (final m in toolFence.allMatches(reply)) {
      final body = m.group(1)!.trim();
      try {
        final j = jsonDecode(body);
        final name = j is Map ? j['name']?.toString().trim() ?? '' : '';
        if (name.isEmpty) {
          broken.add(body);
          continue;
        }
        final args = (j as Map)['arguments'];
        calls.add(ToolCall(name, args is Map<String, dynamic> ? args : const {}));
      } catch (_) {
        broken.add(body);
      }
    }
    return ParsedToolCalls(calls, broken: broken);
  }

  @override
  String resultMessage(List<ToolCallResult> results, PromptTexts texts) =>
      texts.get('tool_results', {
        'count': '${results.length}',
        'results': [
          for (final r in results)
            '[${r.call.name}] ${r.error != null ? texts.get('tool_failed', {'error': r.error!}) : jsonEncode(r.data)}',
        ].join('\n\n'),
      });
}

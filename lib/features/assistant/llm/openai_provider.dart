import '../../../l10n/l10n.dart';
import '../assistant_settings.dart' show ThinkLevel;
import 'http_provider.dart';
import 'llm_provider.dart';

/// OpenAI 兼容(`/chat/completions`,`Authorization: Bearer`)。绝大多数中转、本地推理都是这个。
class OpenAiProvider extends HttpLlmProvider {
  OpenAiProvider(super.endpoint);

  @override
  Map<String, String> get authHeaders => {'Authorization': 'Bearer $apiKey'};

  @override
  Map<String, dynamic> requestBody(LlmRequest r, {required bool stream}) => {
    'model': endpoint.model,
    'messages': [
      {'role': 'system', 'content': r.system},
      for (final m in r.messages)
        {
          'role': m.role,
          'content': m.images.isEmpty
              ? m.content
              : [
                  for (final i in m.images)
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:${i.mime};base64,${i.data}'},
                    },
                  if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
                ],
        },
    ],
    if (stream) 'stream': true,
    ...thinkFields(r.think),
  };

  /// `reasoning_effort` 两头都封顶:没有「关」,minimal 是最低;没有「超高」,high 是最高。
  @override
  Map<String, dynamic> thinkFields(ThinkLevel level) {
    if (level == ThinkLevel.auto) return const {};
    return {
      'reasoning_effort': switch (level) {
        ThinkLevel.off => 'minimal',
        ThinkLevel.low => 'low',
        ThinkLevel.high || ThinkLevel.ultra => 'high',
        _ => 'medium',
      },
    };
  }

  @override
  String? thinkNote(ThinkLevel level) => switch (level) {
    ThinkLevel.off => l10nNow.thinkNoOffFormat,
    ThinkLevel.ultra => l10nNow.thinkNoUltraFormat,
    _ => null,
  };

  /// `delta.content`;思考在 `delta.reasoning_content`(DeepSeek)或 `delta.reasoning`(OpenRouter)。
  /// 老式补全接口没有 delta,只有 text。
  @override
  LlmText parseDelta(Object? frame) {
    const none = (text: '', reasoning: '');
    if (frame is! Map) return none;
    final choices = frame['choices'];
    if (choices is! List || choices.isEmpty) return none;
    final first = choices.first;
    if (first is! Map) return none;
    final d = first['delta'];
    if (d is! Map) {
      return (
        text: first['text'] is String ? first['text'] as String : '',
        reasoning: '',
      );
    }
    final r = d['reasoning_content'] ?? d['reasoning'];
    return (
      text: d['content'] is String ? d['content'] as String : '',
      reasoning: r is String ? r : '',
    );
  }

  /// `choices[0].message.content`,老式补全接口是 `choices[0].text`。
  @override
  String parseResponse(Object? body) {
    if (body is! Map) return '';
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final msg = first['message'];
    if (msg is Map) return msg['content']?.toString() ?? '';
    return first['text']?.toString() ?? '';
  }

  /// `{"data":[{"id":"gpt-4o"}]}`
  @override
  List<String> parseModels(Object? body) =>
      body is Map ? modelIdsOf(body['data']) : const [];
}

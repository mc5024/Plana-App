import '../assistant_settings.dart' show ThinkLevel;
import 'http_provider.dart';
import 'llm_provider.dart';

/// Anthropic(`/messages`,`x-api-key` + `anthropic-version`)。
class AnthropicProvider extends HttpLlmProvider {
  AnthropicProvider(super.endpoint);

  @override
  Map<String, String> get authHeaders => {
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
  };

  @override
  Map<String, dynamic> requestBody(LlmRequest r, {required bool stream}) => {
    'model': endpoint.model,
    // 必填,没有「不限」;开了思考还得大于思考预算(预算是从它里面切出去的)
    'max_tokens': 4096 + _budget(r.think),
    'system': r.system,
    'messages': [
      for (final m in r.messages)
        {
          'role': m.role,
          'content': m.images.isEmpty
              ? m.content
              : [
                  for (final i in m.images)
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': i.mime,
                        'data': i.data,
                      },
                    },
                  if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
                ],
        },
    ],
    if (stream) 'stream': true,
    ...thinkFields(r.think),
  };

  /// 思考预算(token)。0 = 不开;下限是它自己规定的 1024。
  static int _budget(ThinkLevel l) => switch (l) {
    ThinkLevel.auto || ThinkLevel.off => 0,
    ThinkLevel.low => 1024,
    ThinkLevel.medium => 4096,
    ThinkLevel.high => 8192,
    ThinkLevel.ultra => 16384,
  };

  /// 「关」就是不带 thinking 字段。
  @override
  Map<String, dynamic> thinkFields(ThinkLevel level) {
    final budget = _budget(level);
    if (budget == 0) return const {};
    return {
      'thinking': {'type': 'enabled', 'budget_tokens': budget},
    };
  }

  @override
  String? thinkNote(ThinkLevel level) => null;

  /// `text_delta` / `thinking_delta`;`message_delta` 这类也带 delta,但不带字。
  @override
  LlmText parseDelta(Object? frame) {
    const none = (text: '', reasoning: '');
    if (frame is! Map) return none;
    final d = frame['delta'];
    if (d is! Map) return none;
    return switch (d['type']) {
      'text_delta' => (
        text: d['text'] is String ? d['text'] as String : '',
        reasoning: '',
      ),
      'thinking_delta' => (
        text: '',
        reasoning: d['thinking'] is String ? d['thinking'] as String : '',
      ),
      _ => none,
    };
  }

  /// `content[]` 里只取 type=text 那几段。
  @override
  String parseResponse(Object? body) {
    if (body is! Map) return '';
    final content = body['content'];
    if (content is! List) return '';
    return [
      for (final p in content)
        if (p is Map && p['type'] == 'text') p['text']?.toString() ?? '',
    ].join();
  }

  /// `{"data":[{"id":"claude-sonnet-4-6"}]}`
  @override
  List<String> parseModels(Object? body) =>
      body is Map ? modelIdsOf(body['data']) : const [];
}

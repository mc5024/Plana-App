// 自填接口那条的流式:三家的增量帧解析、流到一半时正文/思考怎么切、
// 以及中转不认流式时的回落。
//
// 这几处坏掉的表现都很像「模型自己慢」或「模型没回」:认错 delta 字段 = 一路空白
// 最后整段蹦出来;切错正文 = 把 <Think> 或者围栏里的 JSON 摊给用户看。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plana_app/features/assistant/domain/agent_event.dart';
import 'package:plana_app/features/assistant/assistant_settings.dart';
import 'package:plana_app/features/assistant/custom_endpoint.dart';
import 'package:plana_app/features/assistant/direct_agent.dart';

CustomEndpoint _ep(AgentApiFormat f) => CustomEndpoint(
  id: 'e1',
  name: 'test',
  format: f,
  baseUrl: 'http://api.test/v1',
  apiKey: 'k',
  model: 'm1',
);

/// 一段 SSE 响应体。
String _sse(List<String> frames) => frames.map((f) => 'data: $f\n\n').join();

MockClient _streamingClient(
  String body, {
  String contentType = 'text/event-stream',
  int status = 200,
  void Function(http.BaseRequest req, String body)? onRequest,
}) => MockClient.streaming((req, bodyStream) async {
  onRequest?.call(req, utf8.decode(await bodyStream.toBytes()));
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: {'content-type': contentType},
  );
});

Future<({String raw, List<AgentDelta> deltas})> _run(
  http.Client c,
  CustomEndpoint e, {
  bool stream = true,
}) async {
  final out = StringBuffer();
  final deltas = await directModelStream(
    c,
    e,
    system: 'sys',
    msgs: const [(role: 'user', content: '画一张', image: null)],
    think: ThinkLevel.auto,
    timeout: const Duration(seconds: 5),
    out: out,
    stream: stream,
  ).toList();
  return (raw: out.toString(), deltas: deltas);
}

void main() {
  group('directDelta', () {
    test('OpenAI:content 与两种 reasoning 字段', () {
      expect(
        directDelta(AgentApiFormat.openai, {
          'choices': [
            {
              'delta': {'content': '好的'},
            },
          ],
        }),
        (text: '好的', reasoning: ''),
      );
      // DeepSeek 那套
      expect(
        directDelta(AgentApiFormat.openai, {
          'choices': [
            {
              'delta': {'reasoning_content': '先想想'},
            },
          ],
        }),
        (text: '', reasoning: '先想想'),
      );
      // OpenRouter 那套
      expect(
        directDelta(AgentApiFormat.openai, {
          'choices': [
            {
              'delta': {'reasoning': '先想想'},
            },
          ],
        }),
        (text: '', reasoning: '先想想'),
      );
      // 收尾那帧只有 finish_reason,不带字
      expect(
        directDelta(AgentApiFormat.openai, {
          'choices': [
            {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
          ],
        }),
        (text: '', reasoning: ''),
      );
    });

    test('Gemini:thought 为真的那几段算思考', () {
      expect(
        directDelta(AgentApiFormat.google, {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '先想想', 'thought': true},
                  {'text': '好的'},
                ],
              },
            },
          ],
        }),
        (text: '好的', reasoning: '先想想'),
      );
    });

    test('Claude:text_delta / thinking_delta,别的帧不带字', () {
      expect(
        directDelta(AgentApiFormat.anthropic, {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': '好的'},
        }),
        (text: '好的', reasoning: ''),
      );
      expect(
        directDelta(AgentApiFormat.anthropic, {
          'type': 'content_block_delta',
          'delta': {'type': 'thinking_delta', 'thinking': '先想想'},
        }),
        (text: '', reasoning: '先想想'),
      );
      // message_delta 也带 delta,但里面是停止原因
      expect(
        directDelta(AgentApiFormat.anthropic, {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
        }),
        (text: '', reasoning: ''),
      );
    });

    test('不认识的帧一律当没字,不抛', () {
      for (final f in AgentApiFormat.values) {
        expect(directDelta(f, null), (text: '', reasoning: ''));
        expect(directDelta(f, 'oops'), (text: '', reasoning: ''));
        expect(directDelta(f, const <String, Object?>{}), (
          text: '',
          reasoning: '',
        ));
      }
    });
  });

  group('directStreamView', () {
    test('收完的 <Think> 划到思考,正文接着往下', () {
      final v = directStreamView('<Think>先想想</Think>好的,画一张');
      expect(v.body, '好的,画一张');
      expect(v.think, '先想想');
    });

    test('还没收尾的 <Think>:后面全算思考', () {
      final v = directStreamView('<Think>先想想,这个词');
      expect(v.body, isEmpty);
      expect(v.think, '先想想,这个词');
    });

    test('围栏一开始正文就到此为止', () {
      final v = directStreamView('我查一下画师\n```tool_call\n{"name": "sear');
      expect(v.body, '我查一下画师');
      expect(v.think, isEmpty);
      final d = directStreamView('画好了\n```nai_draw\n{"positive": "1girl');
      expect(d.body, '画好了');
    });

    test('普通代码块照留 —— 回复里列 tag 会用到', () {
      const raw = '给你:\n```\n1girl, blue eyes\n```';
      expect(directStreamView(raw).body, raw);
    });

    test('收到一半的标签和围栏头不露出来', () {
      expect(directStreamView('好的 <Thi').body, '好的');
      expect(directStreamView('好的\n```nai_dr').body, '好的');
      // 光秃秃的反引号留着:多半是代码块/行内代码的收尾,切了反而拆了好好的块
      expect(directStreamView('给你 `1girl`').body, '给你 `1girl`');
    });

    test('多段 <Think> 合到一起', () {
      final v = directStreamView('<Think>一</Think>甲<Think>二</Think>乙');
      expect(v.body, '甲乙');
      expect(v.think, '一\n二');
    });
  });

  group('directModelStream', () {
    test('OpenAI:边收边吐,原文攒齐,最后一帧是全量', () async {
      late String sent;
      final c = _streamingClient(
        _sse([
          '{"choices":[{"delta":{"reasoning_content":"想"}}]}',
          '{"choices":[{"delta":{"content":"好的"}}]}',
          '{"choices":[{"delta":{"content":",画一张"}}]}',
          '[DONE]',
        ]),
        onRequest: (_, b) => sent = b,
      );
      final r = await _run(c, _ep(AgentApiFormat.openai));

      expect(jsonDecode(sent)['stream'], isTrue, reason: '得真的开流');
      expect(r.raw, '好的,画一张', reason: 'reasoning 不进原文,不然会被当正文解析');
      expect(r.deltas, isNotEmpty);
      expect(r.deltas.last.text, '好的,画一张');
      expect(r.deltas.last.reasoning, '想');
    });

    test('Claude:换成 content_block_delta,地址不变', () async {
      late Uri uri;
      final c = _streamingClient(
        _sse([
          '{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"想"}}',
          '{"type":"content_block_delta","delta":{"type":"text_delta","text":"好的"}}',
        ]),
        onRequest: (req, _) => uri = req.url,
      );
      final r = await _run(c, _ep(AgentApiFormat.anthropic));

      expect(uri.toString(), 'http://api.test/v1/messages');
      expect(r.raw, '好的');
      expect(r.deltas.last.reasoning, '想');
    });

    test('Gemini:换成 streamGenerateContent 并带 alt=sse', () async {
      late Uri uri;
      final c = _streamingClient(
        _sse(['{"candidates":[{"content":{"parts":[{"text":"好的"}]}}]}']),
        onRequest: (req, _) => uri = req.url,
      );
      final r = await _run(c, _ep(AgentApiFormat.google));

      expect(uri.path, '/v1/models/m1:streamGenerateContent');
      expect(uri.queryParameters['alt'], 'sse');
      expect(r.raw, '好的');
    });

    test('自定义请求头随请求发出,同名覆盖默认头', () async {
      late Map<String, String> sent;
      final c = _streamingClient(
        _sse(['{"choices":[{"delta":{"content":"好的"}}]}']),
        onRequest: (req, _) => sent = req.headers,
      );
      await _run(
        c,
        _ep(
          AgentApiFormat.openai,
        ).copyWith(headers: {'X-Title': 'Plana', 'authorization': 'Token t'}),
      );

      expect(sent['X-Title'], 'Plana');
      expect(sent['Authorization'], 'Token t');
      expect(sent['Content-Type'], 'application/json');
    });

    test('中转不认流式:整段收完照样出结果', () async {
      final c = _streamingClient(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '好的,画一张'},
            },
          ],
        }),
        contentType: 'application/json',
      );
      final r = await _run(c, _ep(AgentApiFormat.openai));

      expect(r.raw, '好的,画一张');
      expect(r.deltas.single.text, '好的,画一张');
    });

    test('中转把 SSE 写成 json 类型:照样按帧收', () async {
      final c = _streamingClient(
        _sse([
          '{"choices":[{"delta":{"content":"好的"}}]}',
          '{"choices":[{"delta":{"content":",画一张"}}]}',
        ]),
        contentType: 'application/json',
      );
      final r = await _run(c, _ep(AgentApiFormat.openai));
      expect(r.raw, '好的,画一张');
    });

    test('设置里关掉:不开流、一帧不推,打的还是原来那个地址', () async {
      late Uri uri;
      late String sent;
      final c = _streamingClient(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '好的'},
            },
          ],
        }),
        contentType: 'application/json',
        onRequest: (req, b) {
          uri = req.url;
          sent = b;
        },
      );
      final r = await _run(c, _ep(AgentApiFormat.openai), stream: false);

      expect(r.deltas, isEmpty, reason: '关着就该老老实实转圈到出结果');
      expect(r.raw, '好的');
      expect((jsonDecode(sent) as Map).containsKey('stream'), isFalse);
      expect(uri.toString(), 'http://api.test/v1/chat/completions');
    });

    test('关掉时 Gemini 也回到 generateContent', () async {
      late Uri uri;
      final c = _streamingClient(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '好的'},
                ],
              },
            },
          ],
        }),
        contentType: 'application/json',
        onRequest: (req, _) => uri = req.url,
      );
      await _run(c, _ep(AgentApiFormat.google), stream: false);
      expect(uri.path, '/v1/models/m1:generateContent');
      expect(uri.queryParameters['alt'], isNull);
    });

    test('HTTP 错误:状态码 + 响应原文,不改写', () async {
      final body = jsonEncode({
        'error': {'message': '额度不足'},
      });
      final c = _streamingClient(
        body,
        contentType: 'application/json',
        status: 429,
      );
      await expectLater(
        _run(c, _ep(AgentApiFormat.openai)),
        throwsA(
          isA<AgentFailure>()
              .having((e) => e.status, 'status', 429)
              .having((e) => e.message, 'message', 'HTTP 429\n$body'),
        ),
      );
    });

    test('Claude 把报错发在流中间:同样要抛出来', () async {
      final c = _streamingClient(
        _sse([
          '{"type":"content_block_delta","delta":{"type":"text_delta","text":"好"}}',
          '{"type":"error","error":{"message":"上游过载"}}',
        ]),
      );
      await expectLater(
        _run(c, _ep(AgentApiFormat.anthropic)),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'message',
            '{"type":"error","error":{"message":"上游过载"}}',
          ),
        ),
      );
    });

    test('围栏在流里:正文只到围栏前,原文一个字不少', () async {
      final c = _streamingClient(
        _sse([
          '{"choices":[{"delta":{"content":"我查一下\\n"}}]}',
          '{"choices":[{"delta":{"content":"```tool_call\\n{\\"name\\":\\"search_artist\\"}\\n```"}}]}',
        ]),
      );
      final r = await _run(c, _ep(AgentApiFormat.openai));

      expect(r.deltas.last.text, '我查一下');
      expect(
        r.raw,
        '我查一下\n```tool_call\n{"name":"search_artist"}\n```',
        reason: '解析用的是原文,围栏得原样留着',
      );
      expect(parseToolCalls(r.raw).single.name, 'search_artist');
    });
  });
}

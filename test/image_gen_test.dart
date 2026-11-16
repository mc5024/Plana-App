// AI 助手选图像模型直接出图:存档、可选的图像模型、三种出图接口。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plana_app/features/assistant/agent_model.dart';
import 'package:plana_app/features/assistant/custom_endpoint.dart';
import 'package:plana_app/features/assistant/domain/agent_event.dart';
import 'package:plana_app/features/assistant/domain/conversation.dart';
import 'package:plana_app/features/assistant/domain/image_gen.dart';
import 'package:plana_app/features/assistant/image_gen/image_gen_client.dart';
import 'package:plana_app/features/assistant/image_gen/image_models.dart';
import 'package:plana_app/features/assistant/llm/llm_provider.dart';

const _openai = CustomEndpoint(
  id: 'o',
  name: '',
  format: AgentApiFormat.openai,
  baseUrl: 'https://img.test/v1',
  apiKey: 'k',
  model: '',
  imageModels: ['gpt-image-1'],
);

const _gemini = CustomEndpoint(
  id: 'g',
  name: '',
  format: AgentApiFormat.google,
  baseUrl: 'https://gem.test/v1beta',
  apiKey: 'gk',
  model: '',
  imageModels: ['gemini-image'],
);

final _png = base64Encode([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

const _json = {'content-type': 'application/json; charset=utf-8'};
const _sse = {'content-type': 'text/event-stream; charset=utf-8'};

ImageGenInput _input({List<LlmImage> images = const []}) =>
    (prompt: '画猫', images: images);

Matcher _fails(String message) =>
    throwsA(isA<AgentFailure>().having((e) => e.message, 'message', message));

void main() {
  group('图像模型出的那轮进存档', () {
    test('请求和用的模型随消息存', () {
      const m = AssistantMsg(
        id: '1',
        role: MsgRole.ai,
        text: '',
        at: 0,
        imageIds: ['img1'],
        imageGen: ImageGenSpec(prompt: '把头发改成红色', refId: 'img0'),
        imageModel: 'plana:big_gpt',
      );
      final back = AssistantMsg.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      );
      expect(back.imageGen!.prompt, '把头发改成红色');
      expect(back.imageGen!.attached, isFalse);
      expect(back.imageGen!.refId, 'img0');
      expect(back.imageModel, 'plana:big_gpt');
      expect(
        ImageGenSpec.fromJson(
          const ImageGenSpec(prompt: '画猫', attached: true).toJson(),
        )!.attached,
        isTrue,
      );
    });
  });

  group('图像模型', () {
    test('接口的出图模型单独存;只有出图模型也能出图,Claude 格式不出图', () {
      final back = CustomEndpoint.fromJson(_openai.toJson())!;
      expect(back.imageModels, ['gpt-image-1']);
      expect(back.canDraw, isTrue);
      expect(back.usable, isFalse);
      expect(
        _openai.copyWith(format: AgentApiFormat.anthropic).canDraw,
        isFalse,
      );
      expect(_openai.copyWith(apiKey: '').canDraw, isFalse);
    });

    test('后端渠道在前、接口的在后;没授权的后端渠道用不了', () {
      final plana = parsePlanaImageChannels({
        'channels': [
          {'key': 'big_gpt', 'name': 'GPT Image'},
          {'key': 'doubao', 'name': 'Seedream'},
        ],
        'authorized': true,
      });
      final all = imageModelChoices(plana, const [_openai, _gemini]);
      expect(all.map((c) => c.key), [
        'plana:big_gpt',
        'plana:doubao',
        'custom:o/gpt-image-1',
        'custom:g/gemini-image',
      ]);
      expect(imageModelOf(all, 'custom:g/gemini-image')!.endpoint!.id, 'g');
      expect(imageModelOf(all, 'custom:g/old'), isNull);

      final anon = imageModelChoices(
        (channels: plana.channels, authorized: false),
        const [_openai],
      );
      expect(anon.first.available, isFalse);
      expect(imageModelOf(anon, 'plana:big_gpt'), isNull);
      expect(imageModelOf(anon, 'custom:o/gpt-image-1'), isNotNull);
    });

    test('选中图像模型存在助手模型的偏好里,带 image: 前缀', () {
      expect(imageChoiceKeyOf('image:plana:big_gpt'), 'plana:big_gpt');
      expect(
        imageChoiceKeyOf('image:custom:o/gpt-image-1'),
        'custom:o/gpt-image-1',
      );
      expect(imageChoiceKeyOf('custom:o/m'), isNull);
      expect(imageChoiceKeyOf('glm'), isNull);
    });
  });

  group('出图接口', () {
    test('后端渠道:SSE 收图,error 给原因', () async {
      late http.Request seen;
      final ok = MockClient((r) async {
        seen = r;
        return http.Response(
          ': open\n\n: ping\n\nevent: final\ndata: ${jsonEncode({'image': _png, 'mime': 'image/png'})}\n\n',
          200,
          headers: _sse,
        );
      });
      final c = PlanaImageClient(
        baseUrl: 'https://plana.test',
        sessionId: 'sid',
        channel: 'big_gpt',
      );
      final bytes = await c.generate(
        _input(images: [(mime: 'image/png', data: _png)]),
        client: ok,
      );
      expect(bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
      expect(seen.url.toString(), 'https://plana.test/api/agent/image');
      expect(seen.headers['Authorization'], 'Bearer sid');
      expect(jsonDecode(seen.body), {
        'channel': 'big_gpt',
        'prompt': '画猫',
        'images': ['data:image/png;base64,$_png'],
      });

      final err = MockClient(
        (_) async => http.Response(
          'event: error\ndata: {"message": "今日额度已用完"}\n\n',
          200,
          headers: _sse,
        ),
      );
      await expectLater(c.generate(_input(), client: err), _fails('今日额度已用完'));
    });

    test('OpenAI:没参考图走 generations', () async {
      late http.Request seen;
      final mock = MockClient((r) async {
        seen = r;
        return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': _png},
            ],
          }),
          200,
          headers: _json,
        );
      });
      final c = OpenAiImageClient(_openai, 'gpt-image-1');
      await c.generate(_input(), client: mock);
      expect(seen.url.toString(), 'https://img.test/v1/images/generations');
      expect(seen.headers['Authorization'], 'Bearer k');
      expect(jsonDecode(seen.body), {
        'model': 'gpt-image-1',
        'prompt': '画猫',
        'n': 1,
      });
    });

    test('OpenAI:有参考图走 edits,图片段带类型', () async {
      late http.BaseRequest seen;
      late String body;
      final mock = MockClient.streaming((r, stream) async {
        seen = r;
        body = latin1.decode(await stream.toBytes());
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'data': [
                  {'b64_json': _png},
                ],
              }),
            ),
          ),
          200,
        );
      });
      await OpenAiImageClient(_openai, 'gpt-image-1').generate(
        _input(
          images: [
            (mime: 'image/png', data: _png),
            (mime: 'image/jpeg', data: _png),
          ],
        ),
        client: mock,
      );
      expect(seen.url.path, '/v1/images/edits');
      expect(seen.headers['Authorization'], 'Bearer k');
      expect(body, contains('name="image[]"; filename="image0.png"'));
      expect(body, contains('content-type: image/jpeg'));
    });

    test('OpenAI:错误取 message', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'rejected by the safety system'},
          }),
          400,
          headers: _json,
        ),
      );
      await expectLater(
        OpenAiImageClient(
          _openai,
          'gpt-image-1',
        ).generate(_input(), client: mock),
        _fails('HTTP 400 · rejected by the safety system'),
      );
    });

    test('Gemini:取 inlineData;只回一段话时给那段话', () async {
      late http.Request seen;
      final mock = MockClient((r) async {
        seen = r;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '给你'},
                    {
                      'inlineData': {'mimeType': 'image/png', 'data': _png},
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: _json,
        );
      });
      final c = GeminiImageClient(_gemini, 'gemini-image');
      final bytes = await c.generate(
        _input(images: [(mime: 'image/jpeg', data: _png)]),
        client: mock,
      );
      expect(bytes.first, 0x89);
      expect(
        seen.url.toString(),
        'https://gem.test/v1beta/models/gemini-image:generateContent',
      );
      expect(seen.headers['x-goog-api-key'], 'gk');
      final body = jsonDecode(seen.body) as Map;
      expect(body['generationConfig'], {
        'responseModalities': ['TEXT', 'IMAGE'],
      });
      expect((body['contents'] as List).single['parts'], [
        {'text': '画猫'},
        {
          'inlineData': {'mimeType': 'image/jpeg', 'data': _png},
        },
      ]);

      final refuse = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '这个画不了'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: _json,
        ),
      );
      await expectLater(c.generate(_input(), client: refuse), _fails('这个画不了'));
    });
  });
}

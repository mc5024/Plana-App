// AI 助手选图像模型直接出图:存档、可选的图像模型、三种出图接口。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plana_app/core/util/image_pick.dart' show PickedImage;
import 'package:plana_app/features/assistant/agent_model.dart';
import 'package:plana_app/features/assistant/application/draft_images.dart';
import 'package:plana_app/features/assistant/assistant_settings.dart';
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

ImageGenInput _input({
  List<LlmImage> images = const [],
  String size = '',
  String aspect = '',
}) => (prompt: '画猫', images: images, size: size, aspect: aspect);

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
        imageGen: ImageGenSpec(prompt: '把头发改成红色'),
        imageModel: 'plana:big_gpt',
      );
      final back = AssistantMsg.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      );
      expect(back.imageGen!.prompt, '把头发改成红色');
      expect(back.imageGen!.attached, isFalse);
      expect(back.imageModel, 'plana:big_gpt');
      final spec = ImageGenSpec.fromJson(
        const ImageGenSpec(
          prompt: '画猫',
          attached: true,
          size: '2K',
          aspect: '16:9',
        ).toJson(),
      )!;
      expect(spec.attached, isTrue);
      expect((spec.size, spec.aspect), ('2K', '16:9'));
    });

    test('用户消息带几张图;只带一张图时代的存档照读', () {
      const m = AssistantMsg(
        id: 'u',
        role: MsgRole.user,
        text: '合成',
        at: 0,
        imageHashes: ['h1', 'h2'],
      );
      final back = AssistantMsg.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      );
      expect(back.imageHashes, ['h1', 'h2']);
      final old = AssistantMsg.fromJson({
        'id': 'u',
        'role': 'user',
        'text': '照这张',
        'at': 0,
        'imageHash': 'h0',
      });
      expect(old.imageHashes, ['h0']);
    });

    test('张数随请求存,一批几张随消息存', () {
      final spec = ImageGenSpec.fromJson(
        const ImageGenSpec(prompt: '画猫', count: 3).toJson(),
      )!;
      expect(spec.count, 3);
      expect(ImageGenSpec.fromJson(const {'prompt': '画猫'})!.count, 1);
      expect(
        ImageGenSpec.fromJson(const {'prompt': '画猫', 'count': 9})!.count,
        kMaxImageCount,
      );
      const m = AssistantMsg(
        id: '1',
        role: MsgRole.ai,
        text: '',
        at: 0,
        imageIds: ['a', 'b', 'c'],
        imageBatch: 2,
      );
      final back = AssistantMsg.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      );
      expect(back.imageBatch, 2);
      expect(back.copyWith(imageIds: ['a']).imageBatch, 2);
      expect(
        AssistantMsg.fromJson(const {'id': '1', 'role': 'ai'}).imageBatch,
        1,
      );
    });
  });

  group('图像模型的快捷设置', () {
    test('分辨率 / 比例随助手设置存,认不出的丢掉', () {
      const s = AssistantSettings(imageSize: '4K', imageAspect: '9:16');
      final back = AssistantSettings.fromJson(s.toJson());
      expect((back.imageSize, back.imageAspect), ('4K', '9:16'));
      final def = AssistantSettings.fromJson(const {
        'imageSize': '8K',
        'imageAspect': 'wide',
      });
      expect((def.imageSize, def.imageAspect), ('', ''));
      // 后端下发的比例不止那七种
      expect(
        AssistantSettings.fromJson(const {'imageAspect': '21:9'}).imageAspect,
        '21:9',
      );
    });

    test('张数随助手设置存,超出范围的回到 1', () {
      final back = AssistantSettings.fromJson(
        const AssistantSettings(imageCount: 4).toJson(),
      );
      expect(back.imageCount, 4);
      expect(
        const AssistantSettings().toJson().containsKey('imageCount'),
        isFalse,
      );
      expect(AssistantSettings.fromJson(const {'imageCount': 0}).imageCount, 1);
      expect(AssistantSettings.fromJson(const {'imageCount': 5}).imageCount, 1);
    });

    test('一批:几张同时出,按次序排,没出成的跳过并带回第一个错', () async {
      var running = 0;
      var peak = 0;
      var n = 0;
      final (ok, error) = await drawBatch<String>(4, () async {
        final i = n++;
        running++;
        peak = peak < running ? running : peak;
        // 先发的慢,看结果是不是还按次序
        await Future<void>.delayed(Duration(milliseconds: 20 - i * 4));
        running--;
        if (i == 1) throw AgentFailure('额度用完');
        if (i == 3) return null;
        return 'img$i';
      });
      expect(peak, 4);
      expect(ok, ['img0', 'img2']);
      expect((error as AgentFailure).message, '额度用完');

      final (one, none) = await drawBatch<String>(1, () async => 'x');
      expect(one, ['x']);
      expect(none, isNull);
    });

    test('待发的图:按顺序加,满了的不收,能删能整份换', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(draftImagesProvider.notifier);
      PickedImage img(int i) => PickedImage('$i', Uint8List.fromList([i]));
      expect(n.add([img(1), img(2), img(3)]), 3);
      // 图上点「引用」:还差一张满,多给的不收
      expect(n.add([img(4), img(5)]), 1);
      expect(n.add([img(6)]), 0);
      expect(c.read(draftImagesProvider).map((p) => p.name), [
        '1',
        '2',
        '3',
        '4',
      ]);
      n.removeAt(1);
      expect(c.read(draftImagesProvider).map((p) => p.name), ['1', '3', '4']);
      n.set([for (var i = 0; i < 6; i++) img(i)]);
      expect(c.read(draftImagesProvider).length, kMaxAttach);
      n.clear();
      expect(c.read(draftImagesProvider), isEmpty);
    });

    test('各模型能选的档:后端按下发的,OpenAI 只有三种比例,Gemini 全开', () {
      final plana = parsePlanaImageChannels({
        'channels': [
          {
            'key': 'big_gpt',
            'name': 'GPT Image 2.6',
            'sizes': ['2K', '4K', '8K'],
            'aspects': ['21:9', '1:1', 'wide'],
          },
          // 老后端不报分辨率和比例
          {'key': 'doubao', 'name': 'Seedream 5.5'},
        ],
        'authorized': true,
      });
      final all = imageModelChoices(plana, const [_openai, _gemini]);
      expect(all[0].sizes, ['2K', '4K']);
      expect(all[0].aspects, ['21:9', '1:1']);
      expect(all[1].sizes, isEmpty);
      expect(all[1].aspects, kImageAspects);
      expect(all[2].sizes, isEmpty);
      expect(all[2].aspects, ['1:1', '2:3', '3:2']);
      expect(all[3].sizes, kImageSizes);
      expect(all[3].aspects, kImageAspects);
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

    test('后端渠道带近况;认不出的、接口里的模型都是 unknown', () {
      final plana = parsePlanaImageChannels({
        'channels': [
          {'key': 'big_gpt', 'name': 'GPT Image 2.6', 'health': 'down'},
          {'key': 'doubao', 'name': 'Seedream 5.5', 'health': 'flaky'},
        ],
        'authorized': true,
      });
      expect(imageModelChoices(plana, const [_openai]).map((c) => c.health), [
        ModelHealth.down,
        ModelHealth.unknown,
        ModelHealth.unknown,
      ]);
    });

    test('后端渠道在前、接口的在后;没授权的后端渠道用不了', () {
      final plana = parsePlanaImageChannels({
        'channels': [
          // 显示后端给的显示名,不显示实际模型 id
          {
            'key': 'big_gpt',
            'name': 'GPT Image 2.6',
            'model': 'GPT Image 2.5 Sunburst',
          },
          {'key': 'doubao', 'name': 'Seedream 5.5'},
        ],
        'authorized': true,
      });
      expect(plana.channels.map((c) => c.name), [
        'GPT Image 2.6',
        'Seedream 5.5',
      ]);
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
        _input(
          images: [(mime: 'image/png', data: _png)],
          size: '4K',
          aspect: '16:9',
        ),
        client: ok,
      );
      expect(bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
      expect(seen.url.toString(), 'https://plana.test/api/agent/image');
      expect(seen.headers['Authorization'], 'Bearer sid');
      expect(jsonDecode(seen.body), {
        'channel': 'big_gpt',
        'prompt': '画猫',
        'images': ['data:image/png;base64,$_png'],
        'aspect': '16:9',
        'size': '4K',
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
      // 比例换成三档尺寸,分辨率不发
      await c.generate(
        _input(aspect: '2:3', size: '4K'),
        client: mock,
      );
      expect((jsonDecode(seen.body) as Map)['size'], '1024x1536');
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
        _input(
          images: [(mime: 'image/jpeg', data: _png)],
          size: '2K',
          aspect: '3:4',
        ),
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
        'imageConfig': {'aspectRatio': '3:4', 'imageSize': '2K'},
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

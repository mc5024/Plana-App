// AI 助手「生成图片」:回复里的 image_gen 块、存档与回带、出图模型的选择、三种出图接口。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plana_app/features/assistant/custom_endpoint.dart';
import 'package:plana_app/features/assistant/domain/agent_event.dart';
import 'package:plana_app/features/assistant/domain/conversation.dart';
import 'package:plana_app/features/assistant/domain/image_gen.dart';
import 'package:plana_app/features/assistant/domain/turn_request.dart';
import 'package:plana_app/features/assistant/image_gen/image_gen_client.dart';
import 'package:plana_app/features/assistant/image_gen/image_models.dart';
import 'package:plana_app/features/assistant/llm/llm_provider.dart';
import 'package:plana_app/features/assistant/presets/preset_rule.dart';
import 'package:plana_app/features/assistant/protocol/reply_parser.dart';
import 'package:plana_app/features/assistant/runtime/agent_runtime.dart';
import 'package:plana_app/features/assistant/runtime/prompt_assets.dart';
import 'package:plana_app/features/assistant/tools/tool_registry.dart';
import 'package:plana_app/features/assistant/tools/tool_settings.dart';

PromptTexts _texts() =>
    PromptTexts.parse(File('assets/prompts/texts.yaml').readAsStringSync());

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

ImageGenInput _input({List<LlmImage> images = const [], String aspect = ''}) =>
    (prompt: '画猫', images: images, aspect: aspect);

Matcher _fails(String message) =>
    throwsA(isA<AgentFailure>().having((e) => e.message, 'message', message));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('回复里的 image_gen 块', () {
    final texts = _texts();

    test('读出来、从正文剥掉;认不出的参考图和比例丢掉', () {
      final p = parseReply(
        '好的\n```image_gen\n{"prompt": "画一只橘猫", "refs": ["last", "bogus", "last"], "aspect": "7:5"}\n```',
        texts,
      );
      expect(p.reply, '好的');
      expect(p.draw, isNull);
      expect(p.imageGen!.prompt, '画一只橘猫');
      expect(p.imageGen!.refs, [kImageRefLast]);
      expect(p.imageGen!.aspect, '');
    });

    test('能和 nai_draw 同时写', () {
      final p = parseReply(
        '两样都给你\n```image_gen\n{"prompt": "画参考图", "refs": ["attached"], "aspect": "16:9"}\n```\n'
        '```nai_draw\n{"positive": "1girl", "negative": "", "characters": []}\n```',
        texts,
      );
      expect(p.reply, '两样都给你');
      expect(p.draw!['positive'], '1girl');
      expect(p.imageGen!.refs, [kImageRefAttached]);
      expect(p.imageGen!.aspect, '16:9');
    });

    test('写坏了、没有 prompt 让模型重写', () {
      expect(
        () => parseReply('```image_gen\n{prompt: x}\n```', texts),
        throwsA(isA<OutputFailure>()),
      );
      expect(
        () => parseReply('```image_gen\n{"prompt": " "}\n```', texts),
        throwsA(isA<OutputFailure>()),
      );
    });

    test('流到一半时气泡里不显示这块', () {
      expect(streamView('好的\n```image_gen\n{"prompt": "画').body, '好的');
    });
  });

  group('出图块进存档和历史', () {
    const m = AssistantMsg(
      id: '1',
      role: MsgRole.ai,
      text: '好',
      at: 0,
      draw: DrawProposal(positive: 'cat'),
      imageGen: ImageGenSpec(prompt: '画猫', refs: [kImageRefAttached]),
      imageModel: 'plana:big_gpt',
    );

    test('回带时总带 image_gen,nai_draw 看 withDraw', () {
      expect(replayText(m), contains('```nai_draw'));
      expect(replayText(m), contains('"prompt":"画猫"'));
      final light = replayText(m, withDraw: false);
      expect(light, isNot(contains('nai_draw')));
      expect(light, startsWith('好\n```image_gen\n'));
      expect(
        replayText(
          const AssistantMsg(id: '2', role: MsgRole.ai, text: '嗯', at: 0),
        ),
        '嗯',
      );
    });

    test('存档往返', () {
      final back = AssistantMsg.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      );
      expect(back.imageGen!.toJson(), m.imageGen!.toJson());
      expect(back.imageModel, 'plana:big_gpt');
    });
  });

  group('出图模型', () {
    test('接口的出图模型和触发词单独存;只有出图模型也能出图,Claude 格式不出图', () {
      final e = _openai.copyWith(
        imageTriggers: {
          'gpt-image-1': ['小g', 'gpt'],
        },
      );
      final back = CustomEndpoint.fromJson(e.toJson())!;
      expect(back.imageModels, ['gpt-image-1']);
      expect(back.triggersOf('gpt-image-1'), ['小g', 'gpt']);
      // 没填触发词的拿模型 id 当触发词
      expect(_openai.triggersOf('gpt-image-1'), ['gpt-image-1']);
      expect(back.canDraw, isTrue);
      expect(back.usable, isFalse);
      expect(
        _openai.copyWith(format: AgentApiFormat.anthropic).canDraw,
        isFalse,
      );
      expect(_openai.copyWith(apiKey: '').canDraw, isFalse);
    });

    test('生成图片默认开,生成前确认默认关', () {
      const s = ToolSettings();
      expect(s.toolOn(kImageGenTool), isTrue);
      expect(s.optionOn(kImageGenTool, kImageGenConfirm), isFalse);
    });

    test('原话里提到哪个就用哪个:最早出现的优先,不分大小写;没授权的后端渠道不算', () {
      final plana = parsePlanaImageChannels({
        'channels': [
          {
            'key': 'big_gpt',
            'name': 'GPT Image',
            'triggers': ['gpt'],
          },
          {
            'key': 'official',
            'name': 'Nano Banana Pro',
            'triggers': ['香蕉', 'banana'],
          },
          // 老后端没带触发词:拿名字顶上
          {'key': 'doubao', 'name': 'Seedream'},
        ],
        'authorized': true,
      });
      expect(plana.channels.last.triggers, ['Seedream']);
      final gemini = _gemini.copyWith(
        imageTriggers: {
          'gemini-image': ['双子'],
        },
      );
      final all = imageModelChoices(plana, [_openai, gemini]);
      expect(all.map((c) => c.key), [
        'plana:big_gpt',
        'plana:official',
        'plana:doubao',
        'custom:o/gpt-image-1',
        'custom:g/gemini-image',
      ]);
      String? hit(String text) => matchImageModel(all, text)?.choice.key;
      expect(hit('用 GPT 画一只橘猫'), 'plana:big_gpt');
      expect(matchImageModel(all, '用 GPT 画')!.trigger, 'gpt');
      expect(hit('香蕉把这张图改成夜景,别用 gpt'), 'plana:official');
      expect(hit('seedream 来一张'), 'plana:doubao');
      expect(hit('双子画个猫'), 'custom:g/gemini-image');
      // 同一处取更长的:gpt-image-1 比 gpt 长
      expect(hit('gpt-image-1 画个猫'), 'custom:o/gpt-image-1');
      expect(hit('画一只橘猫'), isNull);

      expect(imageModelOf(all, 'custom:g/gemini-image')!.endpoint!.id, 'g');
      expect(imageModelOf(all, 'custom:g/old'), isNull);

      final anon = imageModelChoices(
        (channels: plana.channels, authorized: false),
        const [_openai],
      );
      expect(anon.first.available, isFalse);
      expect(matchImageModel(anon, '用 gpt 画'), isNull);
      expect(imageModelOf(anon, 'plana:big_gpt'), isNull);
      expect(
        matchImageModel(anon, 'gpt-image-1')!.choice.key,
        'custom:o/gpt-image-1',
      );
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
        _input(images: [(mime: 'image/png', data: _png)], aspect: '16:9'),
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

    test('OpenAI:没参考图走 generations,比例换成三档尺寸', () async {
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
      await c.generate(_input(aspect: '9:16'), client: mock);
      expect(seen.url.toString(), 'https://img.test/v1/images/generations');
      expect(seen.headers['Authorization'], 'Bearer k');
      expect(jsonDecode(seen.body), {
        'model': 'gpt-image-1',
        'prompt': '画猫',
        'n': 1,
        'size': '1024x1536',
      });
      await c.generate(_input(), client: mock);
      expect((jsonDecode(seen.body) as Map).containsKey('size'), isFalse);
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
      expect(body, isNot(contains('name="size"')));
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
        _input(images: [(mime: 'image/jpeg', data: _png)], aspect: '3:4'),
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
        'imageConfig': {'aspectRatio': '3:4'},
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

  group('一轮里给模型「生成图片」', () {
    const chat = CustomEndpoint(
      id: 'c',
      name: '',
      format: AgentApiFormat.openai,
      baseUrl: 'https://llm.test/v1',
      apiKey: 'k',
      model: 'm',
    );

    test('点到或沿用出图模型才写进系统提示;只回出图块也算回复', () async {
      final systems = <String>[];
      final mock = MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        systems.add((body['messages'] as List).first['content'] as String);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '```image_gen\n{"prompt": "画一只橘猫"}\n```',
                },
              },
            ],
          }),
          200,
          headers: _json,
        );
      });
      Future<List<AgentEvent>> run(String model, {String trigger = ''}) =>
          http.runWithClient(
            () =>
                agentRuntimeFor(
                      endpoint: chat,
                      backendBase: '',
                      sessionId: '',
                      backendModel: '',
                      imageModel: 'nai_v45_full',
                    )
                    .run(
                      AgentTurnRequest(
                        userText: '用 GPT 画一只橘猫',
                        imageModel: 'nai_v45_full',
                        customRules: const [
                          PresetRule(name: 'role', content: '你是画师'),
                        ],
                        tools: ToolSettings(
                          disabledTools: {for (final t in kAgentTools) t.name},
                        ),
                        stream: false,
                        imageGenModel: model,
                        imageGenTrigger: trigger,
                      ),
                    )
                    .toList(),
            () => mock,
          );

      final done = (await run(
        'GPT Image',
        trigger: 'gpt',
      )).whereType<AgentDone>().single;
      expect(done.result.imageGen!.prompt, '画一只橘猫');
      expect(done.result.hasDraw, isFalse);
      expect(systems.single, contains('```image_gen'));
      expect(
        systems.single,
        contains('提到了「gpt」,也就是出图模型 GPT Image'.replaceAll(',', '，')),
      );

      // 没点到、沿用上一轮的:说明换成「接着改那张图」
      systems.clear();
      await run('GPT Image');
      expect(systems.single, contains('上一轮用出图模型 GPT Image 出了图'));
      expect(systems.single, isNot(contains('提到了')));

      systems.clear();
      await run('');
      expect(systems.single, isNot(contains('image_gen')));
    });
  });
}

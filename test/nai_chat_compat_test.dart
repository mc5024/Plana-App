import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/net/nai_chat_compat.dart';
import 'package:plana_app/core/net/nai_client.dart';
import 'package:plana_app/core/net/nai_endpoint.dart';

Map<String, dynamic> _body({
  String action = 'generate',
  String model = 'nai-diffusion-4-5-full',
  Map<String, dynamic> extra = const {},
}) => {
  'input': '1girl',
  'model': model,
  'action': action,
  'parameters': {
    'width': 832,
    'height': 1216,
    'scale': 5.5,
    'sampler': 'k_euler',
    'steps': 23,
    'seed': 12345,
    'cfg_rescale': 0.1,
    'noise_schedule': 'karras',
    'negative_prompt': 'lowres',
    'qualityToggle': true,
    'ucPreset': 0,
    ...extra,
  },
};

Map<String, dynamic> _content(Map<String, dynamic> chat) =>
    jsonDecode((chat['messages'] as List).single['content'] as String)
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OpenAI 格式的地址补全到 /v1/chat/completions', () {
    const f = NaiApiFormat.openai;
    expect(
      naiEndpointFor('https://a.b/', f),
      'https://a.b/v1/chat/completions',
    );
    expect(
      naiEndpointFor('https://a.b/v1', f),
      'https://a.b/v1/chat/completions',
    );
    expect(
      naiEndpointFor('https://a.b/v1/chat/completions/', f),
      'https://a.b/v1/chat/completions',
    );
    expect(naiEndpointFor('https://a.b/', NaiApiFormat.nai), 'https://a.b');
    expect(naiEndpointIsChat('https://a.b/v1/chat/completions'), isTrue);
    expect(naiEndpointIsChat('https://a.b'), isFalse);
  });

  test('文生图:官方字段转成中转的字段,预设开关恒关', () {
    final chat = naiChatBody(_body());
    expect(chat['model'], 'nai-diffusion-4-5-full');
    final c = _content(chat);
    expect(c['prompt'], '1girl');
    expect(c['negative_prompt'], 'lowres');
    expect(c['size'], [832, 1216]);
    expect(c['steps'], 23);
    expect(c['scale'], 5.5);
    expect(c['sampler'], 'k_euler');
    expect(c['seed'], 12345);
    expect(c['cfg_rescale'], 0.1);
    expect(c['noise_schedule'], 'karras');
    expect(c['quality'], isFalse);
    expect(c['uc_preset'], 'none');
    expect(c.containsKey('characters'), isFalse);
  });

  test('多角色:坐标落到格子', () {
    final c = _content(
      naiChatBody(
        _body(
          extra: {
            'use_coords': true,
            'characterPrompts': [
              {
                'prompt': 'girl',
                'uc': 'blue eyes',
                'center': {'x': 0.3, 'y': 0.3},
              },
              {
                'prompt': 'boy',
                'uc': '',
                'center': {'x': 0.42, 'y': 0.95},
              },
            ],
          },
        ),
      ),
    );
    expect(c['use_coords'], isTrue);
    expect(c['characters'], [
      {
        'prompt': 'girl',
        'negative_prompt': 'blue eyes',
        'position': 'B2',
        'center': {'x': 0.3, 'y': 0.3},
      },
      {
        'prompt': 'boy',
        'negative_prompt': '',
        'position': 'C5',
        'center': {'x': 0.42, 'y': 0.95},
      },
    ]);
  });

  test('图生图 / 重绘:各进各的块,重绘模型交给中转挑', () {
    final i2i = _content(
      naiChatBody(
        _body(
          action: 'img2img',
          extra: {'image': 'IMG', 'strength': 0.55, 'noise': 0.1},
        ),
      ),
    );
    expect(i2i['i2i'], {'image': 'IMG', 'strength': 0.55, 'noise': 0.1});

    final chat = naiChatBody(
      _body(
        action: 'infill',
        model: 'nai-diffusion-4-5-curated-inpainting',
        extra: {'image': 'IMG', 'mask': 'MASK', 'strength': 0.7},
      ),
    );
    expect(chat['model'], 'nai-diffusion-4-5-curated');
    expect(_content(chat)['inpaint'], {
      'image': 'IMG',
      'mask': 'MASK',
      'strength': 0.7,
    });
  });

  test('角色参考:类型取描述,fidelity 由副强度还原', () {
    final c = _content(
      naiChatBody(
        _body(
          extra: {
            'director_reference_images': ['REF'],
            'director_reference_descriptions': [
              {
                'caption': {'base_caption': 'style', 'char_captions': []},
                'legacy_uc': false,
              },
            ],
            'director_reference_strength_values': [0.8],
            'director_reference_secondary_strength_values': [0.25],
          },
        ),
      ),
    );
    expect(c['character_references'], [
      {'image': 'REF', 'type': 'style', 'fidelity': 0.75, 'strength': 0.8},
    ]);
  });

  test('官方参数原样带上:Vibe、Variety+ 照发,图片不重复,流式与预设开关不带', () {
    final c = _content(
      naiChatBody(
        _body(
          action: 'img2img',
          extra: {
            'image': 'IMG',
            'strength': 0.5,
            'noise': 0,
            'reference_image_multiple': ['V'],
            'reference_strength_multiple': [0.6],
            'skip_cfg_above_sigma': 58,
            'stream': 'msgpack',
          },
        ),
      ),
    );
    expect(c['reference_image_multiple'], ['V']);
    expect(c['reference_strength_multiple'], [0.6]);
    expect(c['skip_cfg_above_sigma'], 58);
    expect(c.containsKey('image'), isFalse);
    expect(c.containsKey('stream'), isFalse);
    expect(c.containsKey('qualityToggle'), isFalse);
    expect(c.containsKey('ucPreset'), isFalse);
    expect(c['i2i'], {'image': 'IMG', 'strength': 0.5, 'noise': 0});
  });

  test('回复取图;没有图时把文字当错误', () {
    final png = [0x89, 0x50, 0x4e, 0x47];
    String reply(String content) => jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    });
    expect(
      naiChatImage(
        reply(
          '![image_0](data:image/png;base64,${base64Encode(png)})\n'
          '<!-- seeds:[1] -->',
        ),
      ),
      png,
    );
    expect(
      () => naiChatImage(reply('余额不足')),
      throwsA(isA<NaiException>().having((e) => e.message, 'message', '余额不足')),
    );
  });

  test('客户端:chat 地址出图,没有逐步预览和账户状态', () async {
    final png = [0x89, 0x50, 0x4e, 0x47, 1, 2];
    final paths = <String>[];
    Map<String, dynamic>? got;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      paths.add(req.uri.path);
      got = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      if (got!['model'] == 'bad') {
        req.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {'message': 'prompt 必填'},
            }),
          );
      } else {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '![image_0](data:image/png;base64,${base64Encode(png)})',
                  },
                },
              ],
            }),
          );
      }
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = NaiClient(
      base: naiEndpointFor(
        'http://127.0.0.1:${server.port}',
        NaiApiFormat.openai,
      ),
    );
    expect(client.streams, isFalse);
    await expectLater(client.subscription('tok'), throwsA(isA<NaiException>()));

    await HttpOverrides.runWithHttpOverrides(() async {
      final frames = await client
          .generateImageStream(token: 'tok', body: _body())
          .toList();
      expect(frames.single.isFinal, isTrue);
      expect(frames.single.bytes, png);
      expect(_content(got!)['prompt'], '1girl');

      await expectLater(
        client.generateImage(
          token: 'tok',
          body: _body(model: 'bad'),
        ),
        throwsA(
          isA<NaiException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message', 'prompt 必填'),
        ),
      );
    }, _RealHttp());
    expect(paths, ['/v1/chat/completions', '/v1/chat/completions']);
  });
}

class _RealHttp extends HttpOverrides {}

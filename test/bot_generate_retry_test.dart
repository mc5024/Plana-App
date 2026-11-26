import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plana_app/core/net/backend_client.dart';

void main() {
  setUp(BackendClient.clearCachesForTest);

  // 1.5KB 的"图片":长到会被抽成分片
  final imgBytes = List.generate(1536, (i) => i % 251);
  final img = base64Encode(imgBytes);
  final imgHash = sha256.convert(imgBytes).toString();
  Map<String, dynamic> inpaintParams() => {
    'inpaint': {'imageBase64': img, 'maskBase64': img},
    'positivePrompt': '1girl',
  };

  test('带图走分片入口:图片换成分片引用,同一张只传一份', () async {
    final seen = <String>[];
    String? requestPart;
    final mock = MockClient((req) async {
      seen.add(req.url.path);
      expect(req.headers['content-type'], startsWith('multipart/form-data'));
      final text = latin1.decode(req.bodyBytes);
      final start = text.indexOf('{"session_id"');
      requestPart = text.substring(start, text.indexOf('\r\n', start));
      return http.Response(jsonEncode({'success': true, 'task_id': 't2'}), 200);
    });
    final sub = await http.runWithClient(
      () => BackendClient('https://mp.test').botGenerate(
        sessionId: 'sid',
        params: inpaintParams(),
        clientRequestId: 'k2',
      ),
      () => mock,
    );
    expect(sub.taskId, 't2');
    expect(seen, ['/api/bot/generate/multipart']);
    final j = jsonDecode(requestPart!) as Map;
    expect(j['params']['inpaint'], {
      'imageBase64': '@part:p0',
      'maskBase64': '@part:p0',
    });
    expect(j['params']['positivePrompt'], '1girl');
    expect(j['client_request_id'], 'k2');
  });

  test('旧后端没有分片入口:退回 JSON,之后同一台直接走 JSON', () async {
    final seen = <String>[];
    final mock = MockClient((req) async {
      seen.add(req.url.path);
      if (req.url.path.endsWith('/multipart')) {
        return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
      }
      final j = jsonDecode(req.body) as Map;
      expect(j['params']['inpaint']['imageBase64'], img);
      return http.Response(jsonEncode({'success': true, 'task_id': 't3'}), 200);
    });
    for (var i = 0; i < 2; i++) {
      final sub = await http.runWithClient(
        () => BackendClient(
          'https://old.test',
        ).botGenerate(sessionId: 'sid', params: inpaintParams()),
        () => mock,
      );
      expect(sub.taskId, 't3');
    }
    expect(seen, [
      '/api/bot/generate/multipart',
      '/api/bot/generate',
      '/api/bot/generate',
    ]);
  });

  test('带幂等键:连接出错自动重发一次,两次是同一个键', () async {
    final keys = <Object?>[];
    final mock = MockClient((req) async {
      keys.add((jsonDecode(req.body) as Map)['client_request_id']);
      if (keys.length == 1) throw const SocketException('reset');
      return http.Response(jsonEncode({'success': true, 'task_id': 't1'}), 200);
    });
    final sub = await http.runWithClient(
      () => BackendClient(
        'https://plana.test',
      ).botGenerate(sessionId: 'sid', params: const {}, clientRequestId: 'k1'),
      () => mock,
    );
    expect(sub.taskId, 't1');
    expect(keys, ['k1', 'k1']);
  });

  test('不带幂等键:连接出错不重发', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      throw const SocketException('reset');
    });
    await expectLater(
      http.runWithClient(
        () => BackendClient(
          'https://plana.test',
        ).botGenerate(sessionId: 'sid', params: const {}),
        () => mock,
      ),
      throwsA(isA<BackendException>()),
    );
    expect(calls, 1);
  });

  test('服务端回了错误(有状态码)不重发', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode({'detail': 'busy'}), 429);
    });
    await expectLater(
      http.runWithClient(
        () => BackendClient('https://plana.test').botGenerate(
          sessionId: 'sid',
          params: const {},
          clientRequestId: 'k1',
        ),
        () => mock,
      ),
      throwsA(isA<BackendException>().having((e) => e.status, 'status', 429)),
    );
    expect(calls, 1);
  });

  test('开启分片缓存:二次同图只发 @cache 引用,会话隔离,400 失效时自动补图重提', () async {
    final requests = <({String requestJson, bool hasPart0})>[];
    var failCacheOnce = false;
    final mock = MockClient((req) async {
      expect(req.url.path, '/api/bot/generate/multipart');
      final text = latin1.decode(req.bodyBytes);
      final start = text.indexOf('{"session_id"');
      final requestJson = text.substring(start, text.indexOf('\r\n', start));
      final hasPart0 = text.contains('name="p0"');
      requests.add((requestJson: requestJson, hasPart0: hasPart0));
      if (failCacheOnce && !hasPart0) {
        failCacheOnce = false;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'detail': '图片缓存已失效，请重新上传',
              'code': 'INVALID_CACHE_KEYS',
              'missing_keys': [imgHash],
            }),
          ),
          400,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(jsonEncode({'success': true, 'task_id': 'tc'}), 200);
    });

    final client = BackendClient('https://cache.test');
    final crParams = {
      'preciseReferences': [
        {'imageBase64': img, 'mode': 'character&style', 'strength': 1.0},
      ],
    };

    await http.runWithClient(() async {
      // 1. 首次:发分片 p0
      await client.botGenerate(
        sessionId: 'sid-a',
        params: crParams,
        usePartCache: true,
      );
      // 2. 二次同会话:不传 p0,只发 @cache:<sha256>
      await client.botGenerate(
        sessionId: 'sid-a',
        params: crParams,
        usePartCache: true,
      );
      // 3. 换会话:不复用 sid-a 缓存,重新传分片 p0
      await client.botGenerate(
        sessionId: 'sid-b',
        params: crParams,
        usePartCache: true,
      );
      // 4. 服务端返回 INVALID_CACHE_KEYS:自动补发分片 p0 并成功
      failCacheOnce = true;
      await client.botGenerate(
        sessionId: 'sid-a',
        params: crParams,
        usePartCache: true,
      );
    }, () => mock);

    expect(requests, hasLength(5));
    expect(requests[0].hasPart0, isTrue);
    expect(
      (jsonDecode(requests[0].requestJson)
          as Map)['params']['preciseReferences'][0]['imageBase64'],
      '@part:p0',
    );
    expect(requests[1].hasPart0, isFalse);
    expect(
      (jsonDecode(requests[1].requestJson)
          as Map)['params']['preciseReferences'][0]['imageBase64'],
      '@cache:$imgHash',
    );
    expect(requests[2].hasPart0, isTrue);
    // 第 4 次先发 @cache 撞 400,第 5 次自动补发 @part:p0
    expect(requests[3].hasPart0, isFalse);
    expect(requests[4].hasPart0, isTrue);
  });

  test('BackendCaps 解析全部四个能力位', () {
    final c = BackendCaps.fromJson({
      'img2img_fit': true,
      'upscale_binary': true,
      'char_ref_fit': true,
      'part_cache': true,
    });
    expect(c.img2imgFit, isTrue);
    expect(c.upscaleBinary, isTrue);
    expect(c.charRefFit, isTrue);
    expect(c.partCache, isTrue);
  });
}

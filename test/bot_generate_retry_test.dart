import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plana_app/core/net/backend_client.dart';

void main() {
  // 1.5KB 的"图片":长到会被抽成分片
  final img = base64Encode(List.generate(1536, (i) => i % 251));
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
        () => BackendClient('https://old.test').botGenerate(
          sessionId: 'sid',
          params: inpaintParams(),
        ),
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
      () => BackendClient('https://plana.test').botGenerate(
        sessionId: 'sid',
        params: const {},
        clientRequestId: 'k1',
      ),
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
        () => BackendClient('https://plana.test').botGenerate(
          sessionId: 'sid',
          params: const {},
        ),
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
}

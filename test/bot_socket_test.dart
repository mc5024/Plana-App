import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/net/backend_client.dart';
import 'package:plana_app/core/net/bot_socket.dart';
import 'package:plana_app/core/net/bot_stream.dart';

class _RealHttp extends HttpOverrides {}

/// 假后端:`/ws/bot` 照服务端协议应答;[pushResult] 为 true 时在完成消息前推成图帧
/// (新服务端),否则只给 URL(旧服务端)。`/api/i/*` 回 [png] 并记下被取过。
Future<({HttpServer server, List<String> fetched, List<Map> binds})> _fakeBackend(
  Uint8List png, {
  required bool pushResult,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final fetched = <String>[];
  final binds = <Map>[];
  server.listen((req) async {
    if (req.uri.path == '/ws/bot') {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((m) {
        final j = jsonDecode(m as String) as Map;
        switch (j['action']) {
          case 'bind_session':
            binds.add(j);
            ws.add(jsonEncode({'action': 'session_bound', 'success': true}));
          case 'subscribe_task':
            final tid = j['task_id'] as String;
            ws.add(
              jsonEncode({
                'action': 'task_update',
                'task_id': tid,
                'status': 'generating',
              }),
            );
            ws.add(
              jsonEncode({
                'action': 'subscribed',
                'task_id': tid,
                'success': true,
              }),
            );
            if (pushResult) {
              ws.add(
                Uint8List.fromList([
                  1, 2, 0, 0, 0, 1, 1, 0, //
                  ...ascii.encode(tid).take(16),
                  ...List.filled(16 - tid.length, 0),
                  ...png,
                ]),
              );
            }
            ws.add(
              jsonEncode({
                'action': 'task_update',
                'task_id': tid,
                'status': 'completed',
                'result': {'type': 'url', 'url': '/api/i/abc.png', 'count': 1},
              }),
            );
        }
      });
    } else if (req.uri.path.startsWith('/api/i/')) {
      fetched.add(req.uri.path);
      req.response.add(png);
      await req.response.close();
    } else {
      req.response.statusCode = 404;
      await req.response.close();
    }
  });
  return (server: server, fetched: fetched, binds: binds);
}

void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 7, 7]);

  Future<void> withRealHttp(Future<void> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, _RealHttp());

  tearDown(() => BotSocket.instance.stop());

  test('新服务端推成图帧:直接用,不再下载;绑定时带 result_frames', () async {
    await withRealHttp(() async {
      final b = await _fakeBackend(png, pushResult: true);
      addTearDown(() => b.server.close(force: true));
      final base = 'http://127.0.0.1:${b.server.port}';
      final out = await streamBotTask(
        baseUrl: base,
        sessionId: 'sid',
        taskId: 'abcd1234abcd1234',
        client: BackendClient(base),
      );
      expect(out.single, png);
      expect(b.fetched, isEmpty);
      expect(b.binds.single['result_frames'], isTrue);
    });
  });

  test('成图是 WebP(推帧或下载):交出去的是还原好的 PNG', () async {
    final webp = File('test/fixtures/nai_sample.webp').readAsBytesSync();
    for (final push in [true, false]) {
      await withRealHttp(() async {
        final b = await _fakeBackend(webp, pushResult: push);
        addTearDown(() => b.server.close(force: true));
        final base = 'http://127.0.0.1:${b.server.port}';
        final out = await streamBotTask(
          baseUrl: base,
          sessionId: 'sid',
          taskId: push ? 'aaaa1111aaaa1111' : 'bbbb2222bbbb2222',
          client: BackendClient(base),
        );
        expect(out.single.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
      });
    }
  });

  test('生成设置选了保持 WebP:成图原样交', () async {
    final webp = File('test/fixtures/nai_sample.webp').readAsBytesSync();
    await withRealHttp(() async {
      final b = await _fakeBackend(webp, pushResult: true);
      addTearDown(() => b.server.close(force: true));
      final base = 'http://127.0.0.1:${b.server.port}';
      final out = await streamBotTask(
        baseUrl: base,
        sessionId: 'sid',
        taskId: 'cccc3333cccc3333',
        client: BackendClient(base),
        keepWebp: true,
      );
      expect(out.single, webp);
    });
  });

  test('旧服务端不推成图帧:照旧按 URL 下载', () async {
    await withRealHttp(() async {
      final b = await _fakeBackend(png, pushResult: false);
      addTearDown(() => b.server.close(force: true));
      final base = 'http://127.0.0.1:${b.server.port}';
      final out = await streamBotTask(
        baseUrl: base,
        sessionId: 'sid',
        taskId: 'ffff0000ffff0000',
        client: BackendClient(base),
      );
      expect(out.single, png);
      expect(b.fetched, ['/api/i/abc.png']);
    });
  });
}

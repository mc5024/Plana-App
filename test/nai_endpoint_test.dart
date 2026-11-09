import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'package:plana_app/core/net/gen_abort.dart';
import 'package:plana_app/core/net/nai_client.dart';
import 'package:plana_app/core/net/nai_endpoint.dart';
import 'package:plana_app/core/net/nai_proxy.dart';
import 'package:plana_app/core/store/app_stores.dart';

/// 一帧流式消息:4 字节大端长度 + msgpack。
List<int> _frame(Map<String, dynamic> msg) {
  final b = msgpack.serialize(msg);
  return [
    (b.length >> 24) & 0xff,
    (b.length >> 16) & 0xff,
    (b.length >> 8) & 0xff,
    b.length & 0xff,
    ...b,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('接口地址归一:去空白/尾斜杠,填成官方等于没填', () {
    expect(normalizeNaiBase('  https://a.b/ '), 'https://a.b');
    expect(normalizeNaiBase('https://a.b///'), 'https://a.b');
    expect(normalizeNaiBase('  '), '');
    expect(normalizeNaiBase('$kNaiOfficialBase/'), '');
    expect(naiBaseOf(''), kNaiOfficialBase);
    expect(naiBaseOf('http://127.0.0.1:9'), 'http://127.0.0.1:9');
  });

  test('代理只顶替官方基址,第三方地址照旧', () {
    expect(naiBaseOf('', proxy: true), kNaiProxyBase);
    // 不带 /image 前缀时 Worker 转去 api 子域,登录会打错地方
    expect(kNaiProxyBase, endsWith('/image'));
    expect(naiBaseOf('http://127.0.0.1:9', proxy: true), 'http://127.0.0.1:9');
  });

  test('拨代理开关:官方客户端换线路,第三方的不动', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    const third = 'http://127.0.0.1:9';
    final thirdClient = c.read(naiClientProvider(third));
    expect(c.read(naiClientProvider('')).host, kNaiOfficialBase);

    c.read(naiProxyProvider.notifier).set(true);
    expect(c.read(naiClientProvider('')).host, kNaiProxyBase);
    expect(c.read(naiClientProvider(third)), same(thirdClient));
    expect(thirdClient.host, third);
  });

  test('代理开关落盘:重启读回来,关掉删键', () {
    final stores = AppStores.ephemeral();
    ProviderContainer boot() {
      final c = ProviderContainer(
        overrides: [appStoresProvider.overrideWithValue(stores)],
      );
      addTearDown(c.dispose);
      return c;
    }

    final c = boot();
    expect(c.read(naiProxyProvider), isFalse);
    c.read(naiProxyProvider.notifier).set(true);
    expect(boot().read(naiProxyProvider), isTrue);
    c.read(naiProxyProvider.notifier).set(false);
    expect(stores.prefs.get('nai_proxy'), isNull);
    expect(boot().read(naiProxyProvider), isFalse);
  });

  test('接口地址形态校验:要协议要主机,不收查询串', () {
    expect(naiBaseLooksValid('https://nai.example.com'), isTrue);
    expect(naiBaseLooksValid('http://192.168.1.9:7000'), isTrue);
    expect(naiBaseLooksValid('nai.example.com'), isFalse);
    expect(naiBaseLooksValid('ftp://nai.example.com'), isFalse);
    expect(naiBaseLooksValid('https://a.b/ai?token=x'), isFalse);
  });

  test('主机名:整条 URL 只取主机,官方(空串)还是空串', () {
    expect(naiBaseHost('https://relay.example.com/v1'), 'relay.example.com');
    expect(naiBaseHost(''), '');
  });

  // TestWidgetsFlutterBinding 默认把所有 HttpClient 换成回 400 的假货,
  // 这条要的正是真连接 —— 在自己的 zone 里换回 dart:io 的原厂实现
  // (HttpOverrides 基类的 createHttpClient 就是它)。
  Future<void> withRealHttp(Future<void> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, _RealHttp());

  test('令牌自带的地址:生成与查点数都提交到那台机器', () async {
    final paths = <String>[];
    String? auth;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      paths.add(req.uri.path);
      auth = req.headers.value('authorization');
      if (req.uri.path == '/user/subscription') {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'active': true,
              'tier': 3,
              'trainingStepsLeft': {
                'fixedTrainingStepsLeft': 7,
                'purchasedTrainingSteps': 3,
              },
            }),
          );
      } else if (req.uri.path == '/ai/generate-image') {
        // 非流式端点直接回 PNG(魔数开头就按裸 PNG 收,不必打包成 zip)
        req.response.add([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 0, 0, 0, 0]);
      } else {
        // 一帧终图(step_ix 缺省 = 终图)
        req.response.add(
          _frame({
            'image': Uint8List.fromList([1, 2, 3]),
          }),
        );
      }
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final c = ProviderContainer();
    addTearDown(c.dispose);

    // 客户端按基址分实例:地址就是那把 Key 自己带的(见 NaiKey.endpoint)
    final base = normalizeNaiBase(
      'http://${server.address.address}:${server.port}/',
    );
    expect(base, 'http://127.0.0.1:${server.port}');
    expect(
      c.read(naiClientProvider('')),
      isNot(c.read(naiClientProvider(base))),
    );

    final client = c.read(naiClientProvider(base));
    await withRealHttp(() async {
      final sub = await client.subscription('tok');
      expect(sub.anlas, 10);
      expect(auth, 'Bearer tok');

      final frames = await client
          .generateImageStream(token: 'tok', body: const {'input': 'x'})
          .toList();
      expect(frames.single.isFinal, isTrue);
      expect(frames.single.bytes, [1, 2, 3]);

      // 关了流式走的那条(生成设置 streamGen = false)
      final png = await client.generateImage(
        token: 'tok',
        body: const {'input': 'x'},
      );
      expect(png.take(4), [0x89, 0x50, 0x4e, 0x47]);
    });

    expect(paths, [
      '/user/subscription',
      '/ai/generate-image-stream',
      '/ai/generate-image',
    ]);
  });

  test('流帧按 event_type 分预览 / 终图 / 错误', () async {
    var fail = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.add(
        _frame({
          'event_type': 'intermediate',
          'step_ix': 0,
          'image': Uint8List.fromList([1]),
        }),
      );
      req.response.add(
        fail
            ? _frame({'event_type': 'error', 'message': 'boom'})
            : _frame({
                'event_type': 'final',
                'image': Uint8List.fromList([2]),
              }),
      );
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = NaiClient(base: 'http://127.0.0.1:${server.port}');
    await withRealHttp(() async {
      final frames = await client
          .generateImageStream(token: 'tok', body: const {'input': 'x'})
          .toList();
      expect([for (final f in frames) f.isFinal], [false, true]);
      expect(frames.first.step, 1);
      expect(frames.last.bytes, [2]);

      fail = true;
      await expectLater(
        client
            .generateImageStream(token: 'tok', body: const {'input': 'x'})
            .toList(),
        throwsA(
          isA<NaiException>().having((e) => e.message, 'message', 'boom'),
        ),
      );
    });
  });

  test('非流式生成也能取消:abort 一响就断连接', () async {
    // 收下请求但永远不回,让取消成为唯一的结束方式
    final arrived = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((_) {
      if (!arrived.isCompleted) arrived.complete();
    });
    addTearDown(() => server.close(force: true));

    final client = NaiClient(base: 'http://127.0.0.1:${server.port}');
    final abort = GenAbort();
    await withRealHttp(() async {
      final pending = client.generateImage(
        token: 'tok',
        body: const {'input': 'x'},
        abort: abort,
      );
      await arrived.future; // 请求真在飞了再取消
      abort.abort();
      await expectLater(pending, throwsA(isA<NaiException>()));
    });
  });

  test('查点数:令牌被拒(401)跟查不通分得开', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      // 官方对已删的号、编的假令牌都回这一句
      final dead = req.headers.value('authorization') == 'Bearer dead';
      req.response
        ..statusCode = dead ? 401 : 503
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(
            dead
                ? {'statusCode': 401, 'message': 'Unauthorized'}
                : {'statusCode': 503, 'message': 'Service Unavailable'},
          ),
        );
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    Future<Object?> errorOf(NaiClient client, String token) async {
      try {
        await client.subscription(token);
      } catch (e) {
        return e;
      }
      return null;
    }

    final client = NaiClient(base: 'http://127.0.0.1:${server.port}');
    await withRealHttp(() async {
      expect(naiTokenRejected(await errorOf(client, 'dead')), isTrue);

      final busy = await errorOf(client, 'ok');
      expect(busy, isA<NaiException>());
      expect(naiTokenRejected(busy), isFalse);

      // 连不上(端口已关)也不算被拒
      final gone = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = gone.port;
      await gone.close(force: true);
      final offline = await errorOf(
        NaiClient(base: 'http://127.0.0.1:$port'),
        'dead',
      );
      expect(offline, isA<NaiException>());
      expect(naiTokenRejected(offline), isFalse);
    });
  });
}

class _RealHttp extends HttpOverrides {}

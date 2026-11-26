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

/// 解析 multipart/form-data 请求体为 `name -> bytes`。
Map<String, List<int>> _parseMultipart(String contentType, List<int> raw) {
  final boundary = contentType.split('boundary=').last;
  final parts = <String, List<int>>{};
  final text = latin1.decode(raw);
  for (final seg in text.split('--$boundary').skip(1)) {
    if (seg.startsWith('--')) break;
    final name = RegExp(r'name="([^"]+)"').firstMatch(seg)!.group(1)!;
    final data = seg.substring(seg.indexOf('\r\n\r\n') + 4, seg.length - 2);
    parts[name] = latin1.encode(data);
  }
  return parts;
}

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

  test('官方 / 代理:带图的请求照官网拆成二进制分片;第三方照旧 JSON', () {
    final img = base64Encode([0x89, 0x50, 1, 2, 3]);
    final vibe = base64Encode([9, 9, 9]);
    final body = {
      'input': 'x',
      'action': 'infill',
      'parameters': {
        'image': img,
        'mask': base64Encode([7]),
        'reference_image_multiple': [vibe, vibe],
        'director_reference_images': [img],
        'width': 832,
      },
    };
    final mp = encodeNaiBody(body, multipart: true);
    expect(mp.contentType, startsWith('multipart/form-data; boundary='));
    final boundary = mp.contentType.split('boundary=').last;
    // 拆分片:名字 → 字节
    final parts = <String, List<int>>{};
    final raw = mp.bytes;
    final text = latin1.decode(raw);
    for (final seg in text.split('--$boundary').skip(1)) {
      if (seg.startsWith('--')) break;
      final name = RegExp(r'name="([^"]+)"').firstMatch(seg)!.group(1)!;
      final data = seg.substring(seg.indexOf('\r\n\r\n') + 4, seg.length - 2);
      parts[name] = latin1.encode(data);
    }
    // 同一张图只放一份,request 在最后
    expect(parts.keys.toList(), [
      'image',
      'mask',
      'reference_image_multiple_0',
      'request',
    ]);
    expect(parts['image'], [0x89, 0x50, 1, 2, 3]);
    expect(parts['reference_image_multiple_0'], [9, 9, 9]);
    final req = jsonDecode(utf8.decode(parts['request']!)) as Map;
    expect(req['parameters'], {
      'image': 'image',
      'mask': 'mask',
      'reference_image_multiple': [
        'reference_image_multiple_0',
        'reference_image_multiple_0',
      ],
      'director_reference_images': ['image'],
      'width': 832,
    });
    expect(req['action'], 'infill');

    final js = encodeNaiBody(body, multipart: false);
    expect(js.contentType, 'application/json');
    expect(jsonDecode(utf8.decode(js.bytes)), body);
    // 文生图没图:就算对面收分片也照旧 JSON
    expect(
      encodeNaiBody(const {
        'input': 'x',
        'parameters': {'width': 832},
      }, multipart: true).contentType,
      'application/json',
    );
  });

  test('流式拿到终图就停止收流,连接照样回池复用', () async {
    final ports = <int>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      ports.add(req.connectionInfo!.remotePort);
      await req.drain<void>();
      req.response.add(
        _frame({
          'event_type': 'final',
          'image': Uint8List.fromList([9]),
        }),
      );
      await req.response.flush();
      // 终图之后响应还要过一会儿才结束(对外 API 等记完账才收尾)
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = NaiClient(base: 'http://127.0.0.1:${server.port}');
    await withRealHttp(() async {
      for (var i = 0; i < 2; i++) {
        await for (final f in client.generateImageStream(
          token: 'tok',
          body: const {'input': 'x'},
        )) {
          if (f.isFinal) break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    });
    expect(ports, hasLength(2));
    expect(ports.toSet(), hasLength(1));
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

  test('官网图片缓存键编码:首次带分片与 key,二次命中省分片仍走 multipart', () {
    final secret = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final img = base64Encode([0x89, 0x50, 1, 2, 3]);
    final ref = base64Encode([4, 5, 6, 7]);
    final body = {
      'input': 'x',
      'action': 'img2img',
      'parameters': {
        'image': img,
        'director_reference_images': [ref, ref],
        'width': 832,
      },
    };

    // 首次:全部带上分片 + cache_secret_key,同图去重
    final first = encodeNaiBodyWithCache(
      body,
      multipart: true,
      cacheSecret: secret,
    );
    expect(first.usedCacheKeys, isEmpty);
    expect(first.uploadedCacheKeys, hasLength(2));
    final parts1 = _parseMultipart(first.contentType, first.bytes);
    expect(parts1.keys.toList(), ['image', 'director_ref_0', 'request']);
    final req1 = jsonDecode(utf8.decode(parts1['request']!)) as Map;
    final p1 = req1['parameters'] as Map;
    expect(p1['image'], 'image');
    expect(p1['image_cache_secret_key'], isA<String>());
    expect(p1.containsKey('director_reference_images'), isFalse);
    final refs1 = p1['director_reference_images_cached'] as List;
    expect(refs1, hasLength(2));
    expect(refs1[0]['data'], 'director_ref_0');
    expect(refs1[1]['data'], 'director_ref_0');
    expect(refs1[0]['cache_secret_key'], refs1[1]['cache_secret_key']);

    // 二次:全部命中已知缓存键 → 无图片分片,但仍发含 request 的 multipart
    final second = encodeNaiBodyWithCache(
      body,
      multipart: true,
      cacheSecret: secret,
      knownCacheKeys: first.uploadedCacheKeys,
    );
    expect(second.contentType, startsWith('multipart/form-data; boundary='));
    expect(second.uploadedCacheKeys, isEmpty);
    expect(second.usedCacheKeys, first.uploadedCacheKeys);
    final parts2 = _parseMultipart(second.contentType, second.bytes);
    expect(parts2.keys.toList(), ['request']);
    final req2 = jsonDecode(utf8.decode(parts2['request']!)) as Map;
    final p2 = req2['parameters'] as Map;
    expect(p2.containsKey('image'), isFalse);
    expect(p2['image_cache_secret_key'], p1['image_cache_secret_key']);
    final refs2 = p2['director_reference_images_cached'] as List;
    expect(refs2[0], {'cache_secret_key': refs1[0]['cache_secret_key']});
    expect(refs2[1], {'cache_secret_key': refs1[0]['cache_secret_key']});
  });

  test('直连流式与非流式:按 token 复用缓存键,400 INVALID_CACHE_KEYS 自动补图重试', () async {
    NaiClient.clearImageCacheForTest();
    final refBytes = [0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4];
    final refB64 = base64Encode(refBytes);
    final received =
        <({String path, String auth, Map<String, List<int>> parts})>[];
    final serverCache = <String, Set<String>>{};
    var expireNext = false;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final auth = req.headers.value('authorization') ?? '';
      final ct = req.headers.value('content-type') ?? '';
      final raw = await req.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (b, chunk) => b..add(chunk),
      );
      final parts = _parseMultipart(ct, raw.takeBytes());
      received.add((path: req.uri.path, auth: auth, parts: parts));
      final body = jsonDecode(utf8.decode(parts['request']!)) as Map;
      final refs =
          (body['parameters'] as Map)['director_reference_images_cached']
              as List;
      final known = serverCache.putIfAbsent(auth, () => <String>{});
      final missing = <String>[];
      for (final item in refs.cast<Map>()) {
        final key = item['cache_secret_key'] as String;
        final dataName = item['data'] as String?;
        if (dataName != null && parts.containsKey(dataName)) {
          known.add(key);
        } else if (expireNext || !known.contains(key)) {
          known.remove(key);
          missing.add(key);
        }
      }
      if (missing.isNotEmpty) {
        expireNext = false;
        req.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'statusCode': 400,
              'message': 'INVALID_CACHE_KEYS',
              'details': {'invalidKeys': missing},
            }),
          );
        await req.response.close();
        return;
      }
      if (req.uri.path == '/ai/generate-image') {
        req.response.add([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 0, 0, 0, 0]);
      } else {
        req.response.add(
          _frame({
            'event_type': 'final',
            'image': Uint8List.fromList([7, 8, 9]),
          }),
        );
      }
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = NaiClient(
      base: 'http://127.0.0.1:${server.port}',
      multipartOverride: true,
      imageCacheOverride: true,
    );
    final body = {
      'input': '1girl',
      'model': 'nai-diffusion-5-full',
      'action': 'generate',
      'parameters': {
        'director_reference_images': [refB64],
      },
    };

    await withRealHttp(() async {
      // 1. tokA 首次流式:带分片 director_ref_0
      final f1 = await client
          .generateImageStream(token: 'tokA', body: body)
          .toList();
      expect(f1.single.bytes, [7, 8, 9]);

      // 2. tokA 二次流式:命中缓存,仅发 request
      final f2 = await client
          .generateImageStream(token: 'tokA', body: body)
          .toList();
      expect(f2.single.bytes, [7, 8, 9]);

      // 3. tokB 首次流式:按 token 隔离,必须带分片
      final f3 = await client
          .generateImageStream(token: 'tokB', body: body)
          .toList();
      expect(f3.single.bytes, [7, 8, 9]);

      // 4. tokA 流式服务端缓存失效 → 400 INVALID_CACHE_KEYS → 自动带图重试成功
      expireNext = true;
      final f4 = await client
          .generateImageStream(token: 'tokA', body: body)
          .toList();
      expect(f4.single.bytes, [7, 8, 9]);

      // 5. tokA 非流式服务端缓存失效 → 400 INVALID_CACHE_KEYS → 自动带图重试成功
      expireNext = true;
      final png = await client.generateImage(token: 'tokA', body: body);
      expect(png.take(4), [0x89, 0x50, 0x4e, 0x47]);
    });

    expect(
      [for (final r in received) r.parts.containsKey('director_ref_0')],
      [true, false, true, false, true, false, true],
    );
  });
}

class _RealHttp extends HttpOverrides {}

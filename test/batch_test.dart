// anima / krea 的一次采样出 N 张(`batch_size`,上限 4)。
//
// 这条链上有三处「说好了就不能改」的契约,各自都是静默失效型的坑:
//  ① 结果契约只给 **URL**:`url` 永远是第一张,只在 count>1 时额外给 `urls`
//     (含第一张)。认错主次的话会只入库第一张、白画的那几张悄悄丢掉。
//     (2026-09-04 之前这里是 base64:控制平面直接带图片字节,导致每张图被
//      WS 和轮询各投递一遍,占了后端出向的 39.5%。)
//  ② 发出去的张数必须等于**实际会出的张数**:开着重绘放大时服务端强制单张,
//     界面上却摆着「4」的话,用户选 4 出 1 张且没有任何提示(web 早期就这样);
//  ③ 批次里 N 张共用一个 seed,只有 seed + batchIndex 才唯一确定一张图。
//     出图那一刻没存下来,那张图以后**永远复现不出来**,事后补不了。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/net/backend_client.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/generate/bot_request.dart';
import 'package:plana_app/features/generate/models.dart';

/// 1×1 PNG,够走完落盘/读回这一整程。
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

GenerateState _anima({bool hires = false, int batch = 1}) =>
    GenerateState.initial().copyWith(
      prompt: '1girl',
      params: const GenParams().copyWith(
        model: 'Anima Turbo',
        batchCount: batch,
        hires: HiresConfig(enabled: hires),
      ),
    );

Future<void> _until(Future<bool> Function() cond) async {
  for (var i = 0; i < 200; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('等待条件超时');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('结果契约:url 是第一张,urls 是全部', () {
    test('count>1:用 urls(它已经含第一张,别再拼一次)', () {
      final r = botResultUrls({
        'type': 'url',
        'url': '/api/i/aa.png',
        'urls': ['/api/i/aa.png', '/api/i/bb.png', '/api/i/cc.png'],
        'count': 3,
      });
      expect(r, ['/api/i/aa.png', '/api/i/bb.png', '/api/i/cc.png']);
    });

    test('单张:没有 urls,退回 url', () {
      expect(botResultUrls({'type': 'url', 'url': '/api/i/aa.png'}), [
        '/api/i/aa.png',
      ]);
    });

    test('两条都空 = 真没图(不能凑出一个空串来充数)', () {
      expect(botResultUrls({'url': ''}), isEmpty);
      expect(botResultUrls(const {}), isEmpty);
      expect(botResultUrls(null), isEmpty);
    });

    test('urls 里混进空串/非串:剔掉,别把它当成一张图', () {
      final r = botResultUrls({
        'url': '/api/i/aa.png',
        'urls': ['/api/i/aa.png', '', 42, '/api/i/bb.png'],
      });
      expect(r, ['/api/i/aa.png', '/api/i/bb.png']);
    });

    test('**不接受**旧的 base64 形状 —— 静默解出空列表才是对的,'
        '否则会把一整串 base64 当成 URL 去请求', () {
      expect(botResultUrls({'type': 'base64', 'imageBase64': 'AAAA'}), isEmpty);
    });
  });

  group('实际张数 = 服务端会出的张数', () {
    test('NAI 那条路没有 batch 这回事', () {
      final p = const GenParams().copyWith(batchCount: 4);
      expect(p.batchable, isFalse);
      expect(p.effectiveBatch, 1);
    });

    test('anima / krea 照选的发', () {
      expect(_anima(batch: 3).params.effectiveBatch, 3);
      expect(
        const GenParams().copyWith(model: 'Krea 2', batchCount: 2).effectiveBatch,
        2,
      );
    });

    test('开着重绘放大 → 强制 1(服务端 n28["batch_size"]=1)', () {
      final p = _anima(hires: true, batch: 4).params;
      expect(p.batchCount, 4, reason: '用户的选择本身不该被抹掉,关掉放大要能回到 4');
      expect(p.effectiveBatch, 1);
    });

    test('超过上限被夹住(服务端也是 min(4, …),这边放宽没用)', () {
      expect(_anima(batch: 99).params.effectiveBatch, kBatchMax);
    });
  });

  test('载荷里带 batch_size,且带的是 effectiveBatch', () {
    final a = buildBotParams(_anima(batch: 3), seed: 1, presetId: 'none');
    expect((a['anima_extra'] as Map)['batch_size'], 3);

    // 重绘放大下发 1:界面显示什么,发出去就是什么
    final h = buildBotParams(
      _anima(hires: true, batch: 4),
      seed: 1,
      presetId: 'none',
    );
    expect((h['anima_extra'] as Map)['batch_size'], 1);

    final k = buildBotParams(
      GenerateState.initial().copyWith(
        prompt: 'x',
        params: const GenParams().copyWith(model: 'Krea 2', batchCount: 2),
      ),
      seed: 1,
      presetId: 'none',
    );
    expect((k['krea_extra'] as Map)['batch_size'], 2);
  });

  test('批次内位置要落盘:seed 一样,靠 batchIndex 区分,不存就再也复现不出来', () async {
    final root = await Directory.systemTemp.createTemp('plana_batch');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    final stores1 = await AppStores.open(rootOverride: root);
    final c1 = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores1)],
    );
    addTearDown(c1.dispose);

    final gal = c1.read(galleryProvider.notifier);
    // 一批 4 张:同一个 seed,位置 0..3
    final ids = [
      for (var i = 0; i < 4; i++)
        gal
            .addResult(
              bytes: _png,
              width: 8,
              height: 8,
              seed: 777,
              batchIndex: i,
              select: i == 0,
            )
            .id,
    ];
    // 单张生成:不写这个键
    final single = gal.addResult(bytes: _png, width: 8, height: 8, seed: 5);
    expect(single.batchIndex, -1);

    stores1.flushNow();
    final indexFile = File('${root.path}/gallery/index.json');
    await _until(() async => indexFile.exists());

    final stores2 = await AppStores.open(rootOverride: root);
    final back = {for (final r in stores2.gallery.initialResults) r.id: r};
    for (var i = 0; i < 4; i++) {
      expect(back[ids[i]]!.seed, 777);
      expect(back[ids[i]]!.batchIndex, i, reason: '第 $i 张的位置读回来要还是 $i');
    }
    expect(back[single.id]!.batchIndex, -1, reason: '老记录/单张一律 -1');
  });
}

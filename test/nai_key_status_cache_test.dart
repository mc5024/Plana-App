// 挑号用的账户状态缓存。只参与免费生成的副账号接不接一单,全看这里给的
// 读数 —— 读数旧了,见底的号就会被当成还能白出,NAI 照扣它的点而且不报错。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/net/nai_client.dart';
import 'package:plana_app/core/net/nai_key_status.dart';

NaiSubscription _sub({bool empty = false, double pct = 50}) => (
  anlas: 100,
  fixedAnlas: 100,
  purchasedAnlas: 0,
  isOpus: true,
  tier: 3,
  usage: (
    percent: empty ? 0.0 : pct,
    isNegative: empty,
    secondsToNextPct: 0,
    accounts: 1,
    purchasedPercent: 0.0,
  ),
);

const NaiTarget _t = (token: 'tok', base: '');

void main() {
  test('同一把同时只查一趟,查回来之后走缓存', () async {
    var calls = 0;
    final gate = Completer<NaiSubscription>();
    final cache = NaiKeyStatusCache((_) {
      calls++;
      return gate.future;
    });

    final a = cache.get(_t);
    final b = cache.get(_t);
    gate.complete(_sub());
    expect((await a)!.usage!.isNegative, isFalse);
    expect((await b)!.usage!.isNegative, isFalse);
    expect(await cache.get(_t), isNotNull);
    expect(calls, 1);
  });

  // 查的途中这个号跑完了一张:查回来的是那张之前的额度,不能交出去。
  test('查的途中作废:重查,不交出作废前的读数', () async {
    final replies = [
      Completer<NaiSubscription>(),
      Completer<NaiSubscription>(),
    ];
    var calls = 0;
    final cache = NaiKeyStatusCache((_) => replies[calls++].future);

    final got = cache.get(_t);
    await Future<void>.delayed(Duration.zero);
    cache.invalidate(_t); // 这时它刚跑完一张
    replies[0].complete(_sub()); // 那张之前:额度还有
    await Future<void>.delayed(Duration.zero);
    replies[1].complete(_sub(empty: true)); // 那张之后:见底了

    expect((await got)!.usage!.isNegative, isTrue);
    expect(cache.peek(_t)!.usage!.isNegative, isTrue);
  });

  // 1% 约合 17 张:余量还多时每张之后都重查,只会让下一单白等一趟请求。
  test('跑完一张:余量还多不重查,快见底才重查', () async {
    var pct = 50.0;
    var calls = 0;
    final cache = NaiKeyStatusCache((_) async {
      calls++;
      return _sub(pct: pct);
    });

    await cache.get(_t);
    cache.spent(_t);
    await cache.get(_t);
    expect(calls, 1);

    pct = 1.5;
    cache.invalidate(_t);
    await cache.get(_t); // 读到 1.5%
    cache.spent(_t);
    await cache.get(_t);
    expect(calls, 3);
  });

  test('查不到给 null,也照样缓存,不每单都再撞一次', () async {
    var calls = 0;
    final cache = NaiKeyStatusCache((_) async {
      calls++;
      throw NaiException('not found', status: 404);
    });
    expect(await cache.get(_t), isNull);
    expect(await cache.get(_t), isNull);
    expect(calls, 1);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/nai_keys.dart';
import 'nai_client.dart';

/// 一次直连查询要打谁:哪把令牌、打哪台机器(空串 = 官方)。
typedef NaiTarget = ({String token, String base});

/// 一把 Key 的查询目标。地址跟着 Key 走,调用点各拼各的迟早漏一个。
NaiTarget naiTargetOf(NaiKey k) => (token: k.token, base: k.endpoint);

/// 单把 Key 的账户状态(档位 / Anlas / V5 额度)—— 账号页每行下方那条读数。
///
/// 按**(令牌, 地址)**做 family 而不是按 Key 的 id:换令牌(手动重贴、JWT 续期)
/// 之后显示的必须是新账号的数,按 id 缓存会把旧账号的读数一直挂在那儿。地址也
/// 进键,是因为同一串 key 打两台机器就是两个账号。
///
/// 不走 [NaiGate]:这是只读的 `/user/subscription`,排在生成后面的话开一次页面
/// 要等好几张图跑完才出数,而它并不占那条「同 Key 不许并发」的生成额度。
///
/// `autoDispose` —— 离开账号页就丢掉,下次进来重新拉。点数是会变的,
/// 缓存一份旧的比不显示更糟。
final naiKeyStatusProvider = FutureProvider.autoDispose
    .family<NaiSubscription, NaiTarget>((ref, t) async {
      return ref.watch(naiClientProvider(t.base)).subscription(t.token);
    });

/// 各把 Key 的账户状态,**出图挑号**用:一张免费尺寸图在哪个号上真免费,要看
/// 那个号自己是不是 Opus、V5 额度见没见底(见 [naiKeysForJob])。
///
/// 不复用 [naiKeyStatusProvider]:那个离开账号页就丢,挑号却在哪个页面都会发生;
/// 也不能每单都现查一遍,存了十几把就是十几个请求。
///
/// 读数什么时候算旧:
///  · 放了超过 [_ttl] —— 额度会随时间回充,订阅会到期,号也可能在别处被用着;
///  · 这个号快见底时又跑完一张吃额度的图([spent])—— 那一张可能正好把它用
///    见底,接着按旧读数派单,见底的号会被当成还能白出。
class NaiKeyStatusCache {
  NaiKeyStatusCache(this._fetch);

  final Future<NaiSubscription> Function(NaiTarget t) _fetch;

  static const _ttl = Duration(seconds: 60);

  /// 单趟查询的上限:第三方中转站挂着不回时,不能让出图跟着干等。
  static const _timeout = Duration(seconds: 6);

  final _got = <NaiTarget, ({NaiSubscription? sub, DateTime at})>{};
  final _pending = <NaiTarget, Future<NaiSubscription?>>{};

  /// 每作废一次加一。一趟查询发出后这个数变了,说明查的途中这个号又跑完了
  /// 一张 —— 查回来的是那张之前的读数,不能要。
  final _epoch = <NaiTarget, int>{};

  /// 手头的读数,不发请求;没查过、查不到或已作废都是 null。
  NaiSubscription? peek(NaiTarget t) => _got[t]?.sub;

  /// 这把的读数:手头的够新就直接给,否则现查(同一把同时只查一趟)。
  ///
  /// 查不到(断网、第三方接口没有这个端点)给 null,这个结果也照样存 [_ttl] ——
  /// 不然每一单都要再撞一次。
  Future<NaiSubscription?> get(NaiTarget t) async {
    while (true) {
      final hit = _got[t];
      if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
        return hit.sub;
      }
      final e = _epoch[t] ?? 0;
      final starter = !_pending.containsKey(t);
      final sub = await _pending.putIfAbsent(t, () => _load(t));
      if ((_epoch[t] ?? 0) != e) continue; // 查的途中作废了,重查
      if (starter) _settle(t, sub); // 发起这一趟的来收尾;搭车的只拿结果
      return sub;
    }
  }

  void _settle(NaiTarget t, NaiSubscription? sub) {
    _got[t] = (sub: sub, at: DateTime.now());
    _pending.remove(t);
  }

  Future<NaiSubscription?> _load(NaiTarget t) async {
    try {
      return await _fetch(t).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  /// 这个号刚跑完一张吃额度的图(免费尺寸的 V5)。
  ///
  /// 余量还多就不作废:1% 约合 17 张,[_margin] 撑得过一个 [_ttl] 里自己连出的
  /// 加上别处用掉的,不必每张之后都重查一趟、让下一单干等。快见底了才作废。
  void spent(NaiTarget t) {
    final u = _got[t]?.sub?.usage;
    if (u != null &&
        !u.isNegative &&
        u.percent + u.purchasedPercent >= _margin) {
      return;
    }
    invalidate(t);
  }

  static const _margin = 2.0;

  /// 这个号的读数作废,下次要用时重查。
  void invalidate(NaiTarget t) {
    _got.remove(t);
    _pending.remove(t);
    _epoch[t] = (_epoch[t] ?? 0) + 1;
  }
}

/// 进程级单例:挑号那份缓存全 app 共用。
final naiKeyStatusCacheProvider = Provider<NaiKeyStatusCache>(
  (ref) => NaiKeyStatusCache(
    (t) => ref.read(naiClientProvider(t.base)).subscription(t.token),
  ),
);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/nai_keys.dart';
import 'gen_abort.dart';

/// 闸门发出的一次通行证:凭 [slot] 还槽、用哪个令牌、打哪台机器。
///
/// [slot] 只是这张通行证的编号,**不是**第几把 Key(见 [NaiGate._busy])。
///
/// [base] 跟着那把 Key 走(空串 = 官方):挑哪把是闸门定的,调用方无从自己
/// 查地址 —— 两处各查一次会在中途增删 Key 时错位,打到别人那台机器上去。
///
/// [token] 为 null = 一把可用的都没有。调用方照常往下走,让它撞到「没有令牌」
/// 那个错误 —— 卡在等位里没有下文的话,界面上就是「点了没反应」。
typedef NaiPass = ({int slot, String? token, String base});

/// 这一单落在某把 Key 上免不免费:true 免费 / false 要扣点 / null 那个号的状态
/// 查不到。见 [naiKeysForJob]。
typedef NaiFreeOn = Future<bool?> Function(NaiKey k);

/// 逐把问免不免费:官方号按它自己的档位与额度问 [onKey],两处例外跟生成按钮
/// 走([buttonFree],按主账号读数算的那个口径):
///  · 第三方中转([NaiKey.isThirdParty])**不查订阅**:多数中转没有
///    `/user/subscription`,查了也是等到超时、记成「查不到」,于是什么免费单
///    都接不到。跟按钮走同升级前。
///  · 主账号这份查不到(超时、接口抽风):「这单算不算花点数的」按主账号定,
///    当成付费单的话,按钮写着免费,只参与点数生成的副账号却会把它接走、扣点。
NaiFreeOn naiFreeOnPerKey({
  required bool Function() buttonFree,
  required NaiFreeOn onKey,
}) => (k) async {
  if (k.isThirdParty) return buttonFree();
  final free = await onKey(k);
  return free ?? (k.primary ? buttonFree() : null);
};

/// 直连 NAI 的并发闸门 —— **全 app 共用一份**。
///
/// NAI 按账号限流:同一把 Key 同时打两个请求,第二个直接 429。所以
///  · 一把 Key 同时只跑一条;
///  · 并发上限就是参与出图的把数(主账号 + 勾了参与条件的副账号)——
///    没有单独的并发设置,加一把、勾一个就自己涨。
///
/// 闸门单独放在这里、而不是留在生成控制器里,是因为**吃这条限额的不止生成**:
/// 图库的 NAI 超分、灵感页的标签预览打的是同一个账号、同一个限流桶。原先只有
/// 生成之间排队,生成中点一次超分照样能撞 429。
///
/// bot 线不走这里:那条打的是后端、花的是服务账号,并发由 `kMaxRunningBot` 管。
class NaiGate {
  NaiGate(this._ref);

  final Ref _ref;

  /// 占用中的 Key,按 [NaiKey.id] 记。**不能按列表下标记**:令牌管理页可以
  /// 拖动排序、删除,出图途中一动,下标就指到别的 Key 上 —— 还在跑的那把被
  /// 当成空的再发一张通行证(429),真正空着的那把反倒被当成占用。
  final _busy = <String>{};

  /// 发出去的通行证 → 它占着的那把 Key。编号只增不复用。
  final _held = <int, String>{};
  var _nextSlot = 0;

  final _waiters = <Completer<void>>[];

  /// 还过几次槽。挑号中途有人还槽的话,那次唤醒叫不到正在挑的这一单(它还没
  /// 进等位名单),得靠这个数发现、自己重挑。
  var _released = 0;

  Future<List<NaiKey>> _all() async {
    try {
      return await _ref.read(naiKeysStoreProvider.future);
    } catch (_) {
      return const [];
    }
  }

  /// 并发上限 = **参与出图的把数**(主账号 + 勾了参与条件的副账号)。
  /// 没有单独的并发设置 —— 加一把、勾一个,并发自己就涨上去了。循环/队列按它
  /// 决定同时投几条,某一单实际用哪把由 [acquire] 逐单挑。
  ///
  /// 给了 [paid] / [freeOn](同 [acquire])就只数**能接这一单**的:循环一批出的
  /// 是同一张图,按总把数投的话,只参与点数生成的副账号在免费循环里接不了单,
  /// 却白占一条,挂着一张一直「等待中」的卡。
  ///
  /// 一把都没存时给 1:让任务照常跑到「没有令牌」那个错误上,而不是卡在等位里
  /// 没有下文(那种卡法在界面上就是「点了没反应」)。
  Future<int> limit({bool? paid, NaiFreeOn? freeOn}) async {
    final all = await _all();
    final keys = [
      for (final k in all)
        if (k.joins) k,
    ];
    final n = paid == null && freeOn == null
        ? keys.length
        : (await _pick(all, keys, paid: paid ?? false, freeOn: freeOn)).length;
    return n < 1 ? 1 : n;
  }

  /// 从 [keys] 里挑能接这一单的,按先后排好(见 [naiKeysForJob])。
  ///
  /// 「这一单算不算花点数的」按主账号算 —— 主账号占着也照样问它,不然主账号
  /// 一忙,只参与点数生成的副账号就会把免费单接走。
  Future<List<NaiKey>> _pick(
    List<NaiKey> all,
    List<NaiKey> keys, {
    required bool paid,
    NaiFreeOn? freeOn,
  }) async {
    final primary = naiPrimaryKey(all);
    final free = await _freeMap(
      [
        ...keys,
        if (primary != null && !keys.any((k) => k.id == primary.id)) primary,
      ],
      paid: paid,
      freeOn: freeOn,
    );
    final paidJob = primary == null ? paid : free[primary.id] != true;
    return naiKeysForJob(keys, (k) => free[k.id], paidJob: paidJob);
  }

  /// 取一张通行证,可用的 Key 都占着就排队,等别人还槽。
  ///
  /// 能用哪几把、谁先谁后见 [naiKeysForJob]。免不免费有两种问法:
  ///  · [paid] —— 整单一个答案(超分、标签预览:落在哪把上都扣点);
  ///  · [freeOn] —— 逐把问(生成:同一张图在额度还有的 Opus 号上是 0 点,在别的
  ///    号上照扣)。给了它就不看 [paid]。
  ///
  /// 每次轮到都**从头重挑**:等位期间 Key 可能被增删、改了开关,号的额度也可能
  /// 变了,一开始挑好的名单早就不作数。
  /// 等位期间被取消时返回 slot = -1。
  Future<NaiPass> acquire({
    bool paid = false,
    NaiFreeOn? freeOn,
    GenAbort? abort,
  }) async {
    while (abort?.aborted != true) {
      final seen = _released;
      final all = await _all();
      // 只挑空着的:占着的反正轮不到,为它们去查状态只是白等。
      final idle = [
        for (final k in all)
          if (k.joins && !_busy.contains(k.id)) k,
      ];
      final picks = await _pick(all, idle, paid: paid, freeOn: freeOn);
      if (abort?.aborted == true) break;
      // 上面那一下 await 期间,名单里的可能已被别人占走:add 得进才算拿到。
      for (final k in picks) {
        if (_busy.add(k.id)) {
          final slot = _nextSlot++;
          _held[slot] = k.id;
          return (slot: slot, token: k.token, base: k.endpoint);
        }
      }
      // 挑号那几下 await 期间有人还了槽:空出来的那把不在这一轮的名单里,重挑。
      if (_released != seen) continue;
      // 一把都拿不到,而且谁都没在跑 —— 不会有人来还槽叫醒它,这一单是真的
      // 没有能用的 Key(一把都没存)。别让它挂在等位里。
      if (_busy.isEmpty) break;
      final w = Completer<void>();
      _waiters.add(w);
      // 等位期间被取消也要醒过来,否则这条会一直挂着
      abort?.whenAbort(() {
        if (!w.isCompleted) w.complete();
      });
      await w.future;
    }
    return (slot: -1, token: null, base: '');
  }

  Future<Map<String, bool?>> _freeMap(
    List<NaiKey> keys, {
    required bool paid,
    NaiFreeOn? freeOn,
  }) async {
    if (freeOn == null) return {for (final k in keys) k.id: !paid};
    final got = await Future.wait([for (final k in keys) _ask(freeOn, k)]);
    return {for (var i = 0; i < keys.length; i++) keys[i].id: got[i]};
  }

  /// 问不出来就当查不到:宁可少用一把,也不误花只该免费出图的号的点。
  Future<bool?> _ask(NaiFreeOn freeOn, NaiKey k) async {
    try {
      return await freeOn(k);
    } catch (_) {
      return null;
    }
  }

  void release(int slot) {
    final id = _held.remove(slot);
    if (id == null) return;
    _busy.remove(id);
    _released++;
    // 叫醒**所有**等位的,各按各能用的那几把重挑。只叫醒排头那一个的话,它若
    // 用不了空出来的这把(付费单碰上关了点数的副账号),这次唤醒就被它吞了,
    // 后面本来能用这把的只能干等到下一次还槽。等位的顶多二十来条。
    final ws = List.of(_waiters);
    _waiters.clear();
    for (final w in ws) {
      if (!w.isCompleted) w.complete();
    }
  }

  /// 占着槽跑一段 —— 超分、标签预览这类「一次一趟」的直连调用用它,
  /// 不必自己配对 acquire/release(漏掉 release 会把闸门永久焊死)。
  ///
  /// 拿不到令牌时 [body] 收到 null,由调用方决定报什么错。第二个参数是这把
  /// Key 的接口地址,直接喂 `naiClientProvider` —— 别另查一次。
  Future<T> run<T>(
    Future<T> Function(String? token, String base) body, {
    bool paid = false,
    GenAbort? abort,
  }) async {
    final pass = await acquire(paid: paid, abort: abort);
    try {
      return await body(pass.token, pass.base);
    } finally {
      release(pass.slot);
    }
  }

  /// 仅供测试观察。
  int get busyCount => _busy.length;
}

/// 闸门是进程级单例:provider 体内不 watch 任何东西,保证不会被重建。
/// 重建 = 丢掉正在占用的槽位,等于闸门失效。
final naiGateProvider = Provider<NaiGate>(NaiGate.new);

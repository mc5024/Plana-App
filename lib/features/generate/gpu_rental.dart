import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/store/app_stores.dart';
import '../../core/store/prefs_store.dart';

/// Anima / Krea 2 的算力来源:免费共享队列,或用户自己租的一台独享 GPU。
///
/// 对接服务端 `agent_router/img_rental.py` 的 `/api/rental/*`。
/// 下面几条是**服务端的规则**,app 侧只负责如实呈现,不能自行发挥:
///
///  - 租来的机器**同时服务 Anima 与 Krea 2** —— 所以通道是这两家模型共用的
///    一份设置,不是每个型号各选一份;
///  - 服务端 2026-08-19 起支持**一人多机**(上限 `IMG_MAX_RENTALS`,现为 4)
///    与**三档机型**(独享 5090 / 抢占 5090 / 抢占 4090)。开机时可以一次开
///    N 台,在跑时还能再加开;停机不带 `instance_id` 就是**全停**,所以
///    「只停这一台」和「全部停止」在界面上必须是两个说法;
///  - **计费从「建实例」起算**,开机与首张图的加载时间都算在租用时长里
///    (租的是机器的使用权,不是从打着火才开始计时)。**但没起来过就一分不收**;
///  - 中途失联只计到最后一次探通(服务端 `bill_to`),发现前的空转不收;
///  - 停止是 purge + 销毁,不是停机 —— 停机实例的云盘照收钱;
///  - 除了用户设的空闲超时,还有硬上限与平台定时关机两层兜底。
///
/// 读数(已用时长 / 费用)**以服务端为准**:本地只在两次轮询之间按秒插值,
/// 保证数字会走,但每轮都会被服务端的真值拉回去。

/// 出图请求有没有被路由到租来的那台机器上。
///
/// 服务端 `modal_anima_provider._try_rental()` 已接:出图前查这人有没有
/// **state == ready** 的租用,有就投他自己那台,没有(或还在启动中、或租卡
/// 模块不可用)就回落 Modal 免费档。**分流是服务端自动做的**,app 不送字段 ——
/// `bot_user_id` 由会话推出来,没有「这一单走哪条」的参数位。
///
/// 由此带来两条界面必须说清的事,见 rental_panel:
///  ① 启动中(state=creating)出的图**仍走免费队列** —— 只有 ready 才分流;
///  ② 实例一旦在跑,出图就走它,与 app 里那个「免费/独享」开关无关 ——
///    那个开关只是「要不要租」的意图,不是每一单的路由。
const bool kRentalRoutingReady = true;

/// 机型。**服务端下单和界面展示共用同一份**(`compshare_api.spec_of()`,随
/// status 下发 `spec` 与 `tiers[].spec`)—— 前端别自己写死:改配置得记着改三处,
/// 迟早对不上(服务端那份注释里点名了这个教训)。下面两个只是 status 还没到货
/// 时的占位,取的是服务端默认档。
const kRentalMachineName = 'RTX 5090';
const kRentalMachineSpec = '14 核 · 64 GB · 100 GB SSD';

/// status 下发的机型(`spec`)。字段缺失就退到上面那两个占位。
class RentalSpec {
  const RentalSpec({
    this.gpu = kRentalMachineName,
    this.gpuCount = 1,
    this.cpu = 14,
    this.memoryGb = 64,
    this.diskGb = 100,
    this.vramGb = 0,
  });

  final String gpu;
  final int gpuCount;
  final int cpu;
  final int memoryGb;
  final int diskGb;

  /// 显存 GB。0 = 服务端没给(老服务端的 `spec` 里没这个键)。
  final int vramGb;

  /// 卡名。多卡时带上张数(现在恒为 1,但下发的是个数字,别假设)。
  String get name => gpuCount > 1 ? '$gpu ×$gpuCount' : gpu;

  /// 副行规格:`32 GB 显存 · 14 核 · 64 GB · 100 GB SSD`。
  /// 显存摆第一位 —— 三档之间真正会影响出图的差别就是它(4090 24G / 5090 32G),
  /// 核数内存是跟着卡走的附属项。
  String get detail => [
    if (vramGb > 0) '$vramGb GB 显存',
    '$cpu 核',
    '$memoryGb GB',
    '$diskGb GB SSD',
  ].join(' · ');

  static RentalSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final gpu = j['gpu'];
    if (gpu is! String || gpu.isEmpty) return null;
    return RentalSpec(
      gpu: gpu,
      gpuCount: (j['gpu_count'] as num?)?.toInt() ?? 1,
      cpu: (j['cpu'] as num?)?.toInt() ?? 14,
      memoryGb: (j['memory_gb'] as num?)?.toInt() ?? 64,
      diskGb: (j['disk_gb'] as num?)?.toInt() ?? 100,
      vramGb: (j['vram_gb'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一个可选档位(服务端 `config.IMG_TIERS`,随 status 下发 `tiers[]`)。
///
/// **别在 app 里写死档位清单**:加档位是改服务端那张表,这边跟着渲染就行。
/// 服务端 `img_tier()` 对不认识的键一律回落默认档而不是报错,所以 app 版本
/// 落后于服务端时最差也只是开出一台默认档,不会开不了机。
///
/// 只有售价没有成本 —— 服务端 `_tier_options()` 刻意不下发 `cost_per_hour`。
class RentalTier {
  const RentalTier({
    required this.key,
    required this.label,
    this.desc = '',
    this.ratePerHour = kRateFallback,
    this.spot = false,
    this.spec = const RentalSpec(),
    this.isDefault = false,
  });

  final String key;

  /// 档位名,如「抢占 4090」。
  final String label;

  /// 一句话说清风险/卖点。抢占档那句写的是「会被收走」和「收走时怎么算钱」,
  /// 原样显示,别自己改写成「更便宜」之类的话 —— 那是在替用户低估风险。
  final String desc;

  final double ratePerHour;

  /// 可能被平台随时回收。
  final bool spot;

  final RentalSpec spec;

  /// 服务端的默认档(不传 tier 时开出来的那个)。
  final bool isDefault;

  static RentalTier? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = j['key'];
    if (key is! String || key.isEmpty) return null;
    return RentalTier(
      key: key,
      label: (j['label'] as String?)?.trim().isNotEmpty == true
          ? (j['label'] as String).trim()
          : key,
      desc: (j['desc'] as String?)?.trim() ?? '',
      ratePerHour: (j['rate_per_hour'] as num?)?.toDouble() ?? kRateFallback,
      spot: j['spot'] == true,
      spec: RentalSpec.fromJson(j['spec']) ?? const RentalSpec(),
      isDefault: j['default'] == true,
    );
  }
}

/// 服务端各项的兜底默认(拿不到 status 时用;正常路径一律以服务端下发为准)。
const kIdleChoicesFallback = <int>[180, 600, 1800, 0];
const kIdleDefaultFallback = 600;
const kMaxUptimeFallback = 4 * 3600;

/// 同时最多几台(服务端 `IMG_MAX_RENTALS`,现为 4)。
/// 兜底写 1 而不是 4:没拿到 status 时按最保守的假设显示 —— 台数选择器
/// 据此决定给不给选,宁可少给一个选项,也不要凭猜下一单四台的钱。
const kMaxCountFallback = 1;
// 只在首帧(status 还没回来)用得上。真实售价一律以服务端
// config.IMG_PRICE_PER_HOUR 为准,改价改那边,这里跟着对齐就行 —— 对不上时
// 那零点几秒里会闪一个错的单价出来。(2026-08-17 服务端 3.0 → 2.7)
const kRateFallback = 2.7;

/// 两段等待,**必须分开说**。它们发生在不同时刻,加起来写成一个数就会骗人
/// (服务端注释里专门记了这个教训:曾经合成 85,前端照着写「开机约一分半」)。
///  - [kBootHintFallback]:`start` 阻塞到服务就绪要多久(实测 36s);
///  - [kFirstImageHintFallback]:就绪后**第一张**图额外要多久(权重加载,实测 24s),
///    之后就快了。
const kBootHintFallback = 40;
const kFirstImageHintFallback = 25;

String idleLabel(int s) => s == 0 ? '不自动关' : '${s ~/ 60} 分钟';

/// 与服务端 `Rental.state` 对齐(none / creating / ready / ending / failed)。
enum RentalStatus { none, creating, ready, ending, failed }

RentalStatus _parseStatus(Object? v) => switch (v) {
  'creating' => RentalStatus.creating,
  'ready' => RentalStatus.ready,
  'ending' => RentalStatus.ending,
  'failed' => RentalStatus.failed,
  _ => RentalStatus.none,
};

/// 在跑的一台(status 的 `machines[i]`)。
///
/// 一人多机之后,机型/档位/读数**逐台**才有:合并视图 `_agg()` 里只剩几个
/// 汇总数(elapsed 取最早那台的、price 与 rate 是和),连 `spec` 都没有。
class RentalMachine {
  const RentalMachine({
    required this.instanceId,
    this.status = RentalStatus.none,
    this.tierKey = '',
    this.tierLabel = '',
    this.spot = false,
    this.spec = const RentalSpec(),
    this.ratePerHour = kRateFallback,
    this.elapsedS = 0,
    this.price = 0,
    this.jobsDone = 0,
    this.jobsFailed = 0,
    this.note = '',
  });

  final String instanceId;
  final RentalStatus status;
  final String tierKey;
  final String tierLabel;
  final bool spot;
  final RentalSpec spec;
  final double ratePerHour;
  final int elapsedS;
  final double price;
  final int jobsDone;
  final int jobsFailed;
  final String note;

  /// 这台叫什么。档位名(「抢占 4090」)比卡名信息量大 —— 同是 5090 还分
  /// 独享和抢占,而后者随时可能被平台收走。老服务端没有档位,退到卡名。
  String get label => tierLabel.isNotEmpty ? tierLabel : spec.name;

  /// 就绪之前恒为 0(服务端 `billed_seconds` 在 ready 之前不计),
  /// 所以插值也只在就绪之后往前走。
  int elapsedAt(int fetchedAtMs, int nowMs) =>
      elapsedS + _rentalDrift(status == RentalStatus.ready, fetchedAtMs, nowMs);

  double priceAt(int fetchedAtMs, int nowMs) =>
      price +
      _rentalDrift(status == RentalStatus.ready, fetchedAtMs, nowMs) /
          3600.0 *
          ratePerHour;

  static RentalMachine? fromJson(Object? j) {
    if (j is! Map) return null;
    final iid = j['instance_id'];
    if (iid is! String || iid.isEmpty) return null;
    return RentalMachine(
      instanceId: iid,
      status: _parseStatus(j['state']),
      tierKey: j['tier'] as String? ?? '',
      tierLabel: j['tier_label'] as String? ?? '',
      spot: j['spot'] == true,
      spec: RentalSpec.fromJson(j['spec']) ?? const RentalSpec(),
      ratePerHour: (j['rate_per_hour'] as num?)?.toDouble() ?? kRateFallback,
      elapsedS: (j['elapsed_s'] as num?)?.toInt() ?? 0,
      price: (j['price'] as num?)?.toDouble() ?? 0,
      jobsDone: (j['jobs_done'] as num?)?.toInt() ?? 0,
      jobsFailed: (j['jobs_failed'] as num?)?.toInt() ?? 0,
      note: j['note'] as String? ?? '',
    );
  }
}

/// 两次轮询之间往前走的秒数。**只往前**:服务端那个读数是锚点也是下限,
/// 时钟回拨(用户改时间 / NTP 校正)时若让漂移变负,界面上的时长会当着人面
/// 往回缩 —— 那比不走字更像出了错。
int _rentalDrift(bool billing, int fetchedAtMs, int nowMs) =>
    (!billing || fetchedAtMs == 0)
    ? 0
    : ((nowMs - fetchedAtMs) ~/ 1000).clamp(0, 1 << 30);

class RentalState {
  const RentalState({
    this.status = RentalStatus.none,
    this.instanceId = '',
    this.idleSeconds = kIdleDefaultFallback,
    this.elapsedS = 0,
    this.price = 0,
    this.ratePerHour = kRateFallback,
    this.jobsDone = 0,
    this.jobsFailed = 0,
    this.note = '',
    this.fetchedAtMs = 0,
    this.idleChoices = kIdleChoicesFallback,
    this.idleDefault = kIdleDefaultFallback,
    this.maxUptimeS = kMaxUptimeFallback,
    this.bootHintS = kBootHintFallback,
    this.firstImageHintS = kFirstImageHintFallback,
    this.busy = false,
    this.error = '',
    this.authed = true,
    this.spec = const RentalSpec(),
    this.tiers = const [],
    this.tierKey = '',
    this.tierLabel = '',
    this.spot = false,
    this.count = 0,
    this.maxCount = kMaxCountFallback,
    this.machines = const [],
  });

  final RentalStatus status;
  final String instanceId;
  final int idleSeconds;

  /// 服务端那一刻的已计费秒数与金额,以及取到它们的本地时刻(插值锚点)。
  final int elapsedS;
  final double price;
  final int fetchedAtMs;

  final double ratePerHour;
  final int jobsDone;
  final int jobsFailed;
  final String note;

  /// 服务端下发的可选项。
  final List<int> idleChoices;
  final int idleDefault;
  final int maxUptimeS;

  /// 开机到就绪 / 就绪后首张图,两段各自的预期秒数(见常量处的说明)。
  final int bootHintS;
  final int firstImageHintS;

  /// 开机 / 关机在途(开机会阻塞几十秒到几分钟,按钮期间不能再点)。
  final bool busy;
  final String error;

  /// 没有 Bot 会话:租卡整条路都不可用,面板据此显示暂未开放。
  final bool authed;

  /// 机型(服务端下发;没到货前是占位)。在跑时取**第一台**的 ——
  /// 合并视图 `_agg` 里根本没有 `spec` 这个键,只有 `machines[i].spec`。
  final RentalSpec spec;

  /// 可选档位清单(服务端 `IMG_TIERS`)。空 = status 还没到货,或服务端是
  /// 不认识档位的老版本 —— 两种情况下界面都退回「只有一种机型」的老样子。
  final List<RentalTier> tiers;

  /// 在跑的那台是哪一档 / 叫什么 / 是不是抢占式。同样只有 `machines[i]` 里有。
  final String tierKey;
  final String tierLabel;
  final bool spot;

  /// 在跑几台,以及服务端允许的上限(`IMG_MAX_RENTALS`)。
  final int count;
  final int maxCount;

  /// 逐台明细。老服务端不下发这个键,那时列表是空的,界面退回单机的说法。
  final List<RentalMachine> machines;

  /// 还能加开几台。
  int get room => (maxCount - count).clamp(0, maxCount);

  bool get active =>
      status == RentalStatus.creating ||
      status == RentalStatus.ready ||
      status == RentalStatus.ending;

  /// 有台在计费(至少一台就绪)。老服务端不下发 machines,退回看总状态。
  ///
  /// 多台时**不能看合并状态**:`_agg()` 只要有一台还在开就整体报 creating,
  /// 而另外几台可能早就在跑、在收钱了 —— 那时候读数停着不动是错的。
  bool get billing => machines.isEmpty
      ? status == RentalStatus.ready
      : machines.any((m) => m.status == RentalStatus.ready);

  /// **正在计费**那几台的费率之和。服务端下发的 `rate_per_hour` 是所有台
  /// (含还在开机的)之和,拿它插值会在开机那一两分钟里多算,下一轮轮询
  /// 又被真值拉回去 —— 表现成金额当着人面往回跳。
  double get billingRate => machines.isEmpty
      ? ratePerHour
      : machines
            .where((m) => m.status == RentalStatus.ready)
            .fold(0.0, (a, m) => a + m.ratePerHour);

  /// 插值后的已计费秒数。服务端读数 + 距上次取到的时间差。
  ///
  /// **启动中恒为 0**:服务端 `billed_seconds` 在就绪前返回 0(没交付就不收),
  /// 就绪那一刻才跳到「含启动时长」的值。这个跳变是对的,不要在本地抹平。
  /// 多台时服务端给的是**最早那台**的,插值也跟着它走。
  int elapsedAt(int nowMs) =>
      elapsedS + _rentalDrift(billing, fetchedAtMs, nowMs);

  /// 插值后的费用。**以服务端给的 price 为锚点往前推**,不要拿
  /// 「已计费时长 × 费率」重算 —— 多台时那两个数口径不同:elapsed_s 取的是
  /// 最早那台的,rate_per_hour 是所有台之和,乘在一起等于按最早那台的时长
  /// 给后开的几台收钱,越走越多。
  double priceAt(int nowMs) =>
      price + _rentalDrift(billing, fetchedAtMs, nowMs) / 3600.0 * billingRate;

  RentalState copyWith({
    RentalStatus? status,
    String? instanceId,
    int? idleSeconds,
    int? elapsedS,
    double? price,
    double? ratePerHour,
    int? jobsDone,
    int? jobsFailed,
    String? note,
    int? fetchedAtMs,
    List<int>? idleChoices,
    int? idleDefault,
    int? maxUptimeS,
    int? bootHintS,
    int? firstImageHintS,
    bool? busy,
    String? error,
    bool? authed,
    RentalSpec? spec,
    List<RentalTier>? tiers,
    String? tierKey,
    String? tierLabel,
    bool? spot,
    int? count,
    int? maxCount,
    List<RentalMachine>? machines,
  }) => RentalState(
    status: status ?? this.status,
    instanceId: instanceId ?? this.instanceId,
    idleSeconds: idleSeconds ?? this.idleSeconds,
    elapsedS: elapsedS ?? this.elapsedS,
    price: price ?? this.price,
    ratePerHour: ratePerHour ?? this.ratePerHour,
    jobsDone: jobsDone ?? this.jobsDone,
    jobsFailed: jobsFailed ?? this.jobsFailed,
    note: note ?? this.note,
    fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
    idleChoices: idleChoices ?? this.idleChoices,
    idleDefault: idleDefault ?? this.idleDefault,
    maxUptimeS: maxUptimeS ?? this.maxUptimeS,
    bootHintS: bootHintS ?? this.bootHintS,
    firstImageHintS: firstImageHintS ?? this.firstImageHintS,
    busy: busy ?? this.busy,
    error: error ?? this.error,
    authed: authed ?? this.authed,
    spec: spec ?? this.spec,
    tiers: tiers ?? this.tiers,
    tierKey: tierKey ?? this.tierKey,
    tierLabel: tierLabel ?? this.tierLabel,
    spot: spot ?? this.spot,
    count: count ?? this.count,
    maxCount: maxCount ?? this.maxCount,
    machines: machines ?? this.machines,
  );

  /// 合入服务端返回的一份状态(status / start / idle 都是同一张视图)。
  ///
  /// ⚠ **两张视图不是一张。** 没在跑时给的是「开机面板要的东西」(`spec`、
  /// `idle_default`、两个 hint);在跑时给的是 `_agg()` 的合并视图,里面
  /// **没有** `spec` / `tier` / `idle_default` / hint,那几样只在
  /// `machines[i]` 里逐台给。所以机型与档位必须从 `machines[0]` 取,
  /// 顶层缺键时一律沿用旧值(`?? 现值`)而不是清空 —— 否则一开机,
  /// 卡上的机型就会退回默认档那套,显示的和真租的对不上。
  RentalState merge(Map<String, dynamic> j, int nowMs) {
    final list = j['idle_choices'];
    final tierList = j['tiers'];
    // 多台时用第一台代表:app 没有多机界面,而机型/档位这几样逐台才有。
    // (真开了多台的话下面 count 会 >1,界面另有一句交代。)
    final machines = j['machines'];
    final first =
        (machines is List && machines.isNotEmpty && machines.first is Map)
        ? machines.first as Map
        : const {};
    return copyWith(
      status: _parseStatus(j['state']),
      instanceId:
          (j['instance_id'] as String?) ??
          (first['instance_id'] as String?) ??
          '',
      idleSeconds: (j['idle_timeout'] as num?)?.toInt() ?? idleSeconds,
      elapsedS: (j['elapsed_s'] as num?)?.toInt() ?? 0,
      price: (j['price'] as num?)?.toDouble() ?? 0,
      ratePerHour: (j['rate_per_hour'] as num?)?.toDouble() ?? ratePerHour,
      jobsDone: (j['jobs_done'] as num?)?.toInt() ?? 0,
      jobsFailed: (j['jobs_failed'] as num?)?.toInt() ?? 0,
      note: (j['note'] as String?) ?? (first['note'] as String?) ?? '',
      fetchedAtMs: nowMs,
      idleChoices: list is List
          ? [
              for (final v in list)
                if (v is num) v.toInt(),
            ]
          : idleChoices,
      idleDefault: (j['idle_default'] as num?)?.toInt() ?? idleDefault,
      maxUptimeS: (j['max_uptime_s'] as num?)?.toInt() ?? maxUptimeS,
      bootHintS: (j['boot_hint_s'] as num?)?.toInt() ?? bootHintS,
      firstImageHintS:
          (j['first_image_hint_s'] as num?)?.toInt() ?? firstImageHintS,
      authed: true,
      spec: RentalSpec.fromJson(first['spec'] ?? j['spec']) ?? spec,
      tiers: tierList is List
          ? [for (final t in tierList) ?RentalTier.fromJson(t)]
          : tiers,
      tierKey: (first['tier'] as String?) ?? (j['tier'] as String?) ?? tierKey,
      tierLabel: (first['tier_label'] as String?) ?? '',
      spot: first['spot'] == true,
      count:
          (j['count'] as num?)?.toInt() ??
          (machines is List ? machines.length : 0),
      maxCount: (j['max_count'] as num?)?.toInt() ?? maxCount,
      machines: machines is List
          ? [for (final m in machines) ?RentalMachine.fromJson(m)]
          : const [],
    );
  }

  /// 当前该按哪一档显示/开机。`tierKey` 在跑时来自服务端,没在跑时来自偏好。
  RentalTier? tierOf(String key) {
    for (final t in tiers) {
      if (t.key == key) return t;
    }
    return null;
  }

  /// 服务端标了 default 的那一档(清单为空时 null)。
  RentalTier? get defaultTier {
    for (final t in tiers) {
      if (t.isDefault) return t;
    }
    return tiers.isEmpty ? null : tiers.first;
  }

  /// 把用户存的档位落到当前清单上。存的那档被服务端删了就退回默认档 ——
  /// 界面上显示的必须是**真会开出来的那一档**,而服务端对不认识的键就是
  /// 静默回落默认档,这边跟着回落才不会显示一套、开出另一套。
  RentalTier? resolveTier(String prefKey) => tierOf(prefKey) ?? defaultTier;

  /// 在跑的那台该显示什么名字。服务端在跑时给的是 `tier_label`(「抢占 4090」),
  /// 拿不到就退到卡名 —— 老服务端没有档位这回事,那时卡名就是全部信息。
  String get runningLabel => tierLabel.isNotEmpty ? tierLabel : spec.name;
}

/// Anima / Krea 的算力来源。免费 = 服务端共享 Modal 队列(排队,不花钱);
/// 独享 = 自己租的那台(不排队,按时长计费)。
enum ModalChannel { free, rented }

/// 通道 + 想用的空闲超时:这两样是用户偏好,持久化。
/// 实例的运行状态不进这里 —— 那是服务端的事实,由 [gpuRentalProvider] 现问。
class RentalPrefs {
  const RentalPrefs({
    this.channel = ModalChannel.free,
    this.idleSeconds = kIdleDefaultFallback,
    this.tier = '',
  });

  final ModalChannel channel;
  final int idleSeconds;

  /// 想开哪一档(服务端 `IMG_TIERS` 的键)。**空 = 跟服务端默认档**,不是
  /// 「没选过要拦住用户」—— 存的档位可能已经被服务端删了,那时也得能开机,
  /// 所以发出去之前一律拿当前清单校一遍,对不上就当空(见 `_effectiveTier`)。
  final String tier;

  RentalPrefs copyWith({
    ModalChannel? channel,
    int? idleSeconds,
    String? tier,
  }) => RentalPrefs(
    channel: channel ?? this.channel,
    idleSeconds: idleSeconds ?? this.idleSeconds,
    tier: tier ?? this.tier,
  );

  factory RentalPrefs.fromJson(Map<String, dynamic> j) => RentalPrefs(
    channel: j['channel'] == 'rented' ? ModalChannel.rented : ModalChannel.free,
    idleSeconds: (j['idleSeconds'] as num?)?.toInt() ?? kIdleDefaultFallback,
    tier: j['tier'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'channel': channel == ModalChannel.rented ? 'rented' : 'free',
    'idleSeconds': idleSeconds,
    'tier': tier,
  };
}

const _prefsKey = 'gpu_rental';

final rentalPrefsProvider =
    AsyncNotifierProvider<RentalPrefsNotifier, RentalPrefs>(
      RentalPrefsNotifier.new,
    );

class RentalPrefsNotifier extends AsyncNotifier<RentalPrefs> {
  PrefsStore get _storage => ref.read(prefsStoreProvider);

  @override
  Future<RentalPrefs> build() async {
    try {
      final raw = await _storage.read(key: _prefsKey);
      if (raw == null || raw.isEmpty) return const RentalPrefs();
      return RentalPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const RentalPrefs();
    }
  }

  /// 先改状态(立即生效),再尽力持久化(失败不打断创作)。
  Future<void> patch(RentalPrefs Function(RentalPrefs) change) async {
    final next = change(state.value ?? const RentalPrefs());
    state = AsyncData(next);
    try {
      await _storage.write(key: _prefsKey, value: jsonEncode(next.toJson()));
    } catch (_) {}
  }
}

final gpuRentalProvider = NotifierProvider<GpuRentalNotifier, RentalState>(
  GpuRentalNotifier.new,
);

class GpuRentalNotifier extends Notifier<RentalState> {
  Timer? _poll;

  /// 上一次 status 成功回来时,服务端名下**到底有没有机器**。
  ///
  /// 单独存一份是因为不能拿合并后的 [state] 回答这个问题:那里有一条
  /// 「下单请求还在飞的时候不许被打回未启动」的保护,会把服务端的真实答案盖住。
  /// 而 start 抛异常之后恰恰要靠这个答案分辨「请求没打出去」和「打出去了、
  /// 机器已经在开」——后者报成失败的话,用户会以为什么都没发生地走开,
  /// 那台机器却在后台一路烧到硬上限。
  bool _serverHasRental = false;

  /// 轮询间隔。服务端巡检 30s 一轮(空闲超时/硬上限就是那里执行的),
  /// app 侧比它快一点,机器被自动关掉后界面不会挂着一个假的「运行中」。
  static const _pollEvery = Duration(seconds: 20);

  /// 启动中单独一档。开机现在是**后台建机 + 轮询报状态**,「什么时候能用了」
  /// 完全靠这条轮询 —— 20 秒一问的话,机器早就绪了界面还挂着「启动中」,
  /// 而那段时间出的图会被服务端回落到免费队列。抢占档实测要一两分钟,
  /// 多问几次的开销可以忽略。
  static const _pollBooting = Duration(seconds: 6);

  String? get _session => ref.read(botSessionProvider).value?.sessionId;
  BackendClient get _client => ref.read(backendClientProvider);

  @override
  RentalState build() {
    // 回前台补一次:后台挂久了系统会压制定时器,那期间实例可能已被空闲超时
    // 关掉(或者反过来,用户在别处开了一台)。不补这一下,回来看到的是旧读数。
    final life = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed) unawaited(refresh());
      },
    );
    ref.onDispose(() {
      _poll?.cancel();
      life.dispose();
    });
    // 会话到货 / 掉线都要重问一次:没有会话时整条路不可用。
    // 冷启动时这一发就是「重进 app 还能看到自己那台」的来源 ——
    // 服务端 img_rentals.json 落盘 + _load() 恢复,状态一直在。
    ref.listen(botSessionProvider, (_, next) {
      final id = next.value?.sessionId;
      if (id == null || id.isEmpty) {
        _poll?.cancel();
        state = const RentalState(authed: false);
      } else {
        unawaited(refresh());
      }
    }, fireImmediately: true);
    return const RentalState();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void _rearm() {
    _poll?.cancel();
    if (!state.active) return;
    _poll = Timer(
      state.status == RentalStatus.creating ? _pollBooting : _pollEvery,
      refresh,
    );
  }

  /// 拉一次状态。失败不清空已有读数 —— 网络抖一下就把运行中的实例显示成
  /// 「未启动」,用户会以为机器已经关了,那才是最贵的误导。
  Future<void> refresh() async {
    final sid = _session;
    if (sid == null || sid.isEmpty) {
      state = const RentalState(authed: false);
      return;
    }
    try {
      final j = await _client.rentalStatus(sid);
      if (j['ok'] != true) {
        state = state.copyWith(error: j['message'] as String? ?? '');
      } else {
        final was = state.status;
        final next = state.merge(j, _now()).copyWith(error: '');
        _serverHasRental = next.status != RentalStatus.none;
        // 开机在途时别被一次「还没登记上」的轮询打回未启动:start 那边是先
        // 落盘再建机器,理论上查得到,但两条请求赛跑不值得赌。请求还在飞的
        // 期间只允许状态往前走(creating → ready),不许被打回。
        if (state.busy && next.status == RentalStatus.none) {
          // 保持现状
        } else if (was == RentalStatus.creating &&
            next.status == RentalStatus.none) {
          // 启动中的机器从服务端名单里消失 = **开机失败**。服务端 `_boot_one`
          // 的每条失败路径都是「销毁实例 + 从名单摘掉 + 一分不收」,不会留下
          // 任何可查的痕迹 —— 不在这儿判,界面就会无声无息地退回「未启动」,
          // 而用户刚刚明明按了开机。
          state = next.copyWith(
            status: RentalStatus.failed,
            note: state.note.isEmpty ? '开机失败,实例已自动销毁' : state.note,
          );
        } else {
          state = next;
        }
      }
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
    _rearm();
  }

  /// 开机。本地先进「启动中」,期间按钮置忙,重复点不会重复下单。
  ///
  /// ⚠ **不要信这个调用返回的 state。** 2026-08-19 起服务端把建机丢进后台
  /// (`_fire_and_forget(_boot_one(...))`)然后**同步**拿合并视图就返回 ——
  /// 那几个 task 一行都还没跑,所以返回体里恒是 `state: "none", count: 0,
  /// machines: []`。照单全收的话:界面立刻退回「未启动」、`_rearm()` 看到
  /// 不 active 于是连轮询都停掉,而机器在后台照开照计费,用户什么都看不到;
  /// 更糟的是这时 `busy` 和 `active` 都是 false,再点一次就**真的会加开一台**
  /// (服务端 start 的语义已经从「返回那台已有的」变成「加开到 N+count」)。
  ///
  /// 所以:`ok` 只当作「下单收到了」,状态一律去 [refresh] 现问 ——
  /// `_boot_one` 的第一件事就是把 Rental 建出来置 creating,那一步在 create_task
  /// 调度之后、我们这条 refresh 请求到达之前必然已经跑完,查得到。
  Future<void> start(
    int idleSeconds, {
    String tier = '',
    int count = 1,
    bool addMore = false,
  }) async {
    final sid = _session;
    if (sid == null || sid.isEmpty || state.busy) return;
    // 已经在跑时只有「加开」这一种合法调用:否则重复点会真的多开几台
    // (服务端 start 的语义是加开到 N+count,不是「返回那台已有的」)。
    if (state.active && !addMore) return;
    if (addMore && state.room <= 0) return;
    state = addMore
        // 加开:在跑那几台的读数一个都不能动 —— 归零的话界面上刚花的钱会
        // 凭空消失一轮,等下一次轮询才回来。
        ? state.copyWith(busy: true, error: '')
        : state.copyWith(
            status: RentalStatus.creating,
            busy: true,
            error: '',
            note: '',
            elapsedS: 0,
            price: 0,
            count: count, // 乐观值,下面 refresh 会用服务端的真数覆盖
            tierKey: tier.isEmpty ? state.tierKey : tier,
            fetchedAtMs: _now(),
          );
    _rearm(); // 开机这一两分钟也轮询:连接万一断了,状态仍旧跟得上
    Object? thrown;
    try {
      final j = await _client.rentalStart(
        sid,
        idleTimeout: idleSeconds,
        tier: tier,
        count: count,
      );
      if (j['ok'] != true) {
        // 服务端明说没下成单(名额满 / 参数不对):那边什么都没建,一分不收。
        // ⚠ 加开失败**不能**把状态判成 failed —— 在跑的那几台还好好的,
        //   整卡切成失败页等于把关机入口也一起藏了。
        final msg = j['message'] as String? ?? '开机失败';
        state = addMore
            ? state.copyWith(busy: false, error: msg)
            : state.copyWith(
                status: RentalStatus.failed,
                busy: false,
                note: msg,
              );
        _rearm();
        return;
      }
    } catch (e) {
      // ⚠ 客户端这边出错(断网 / 超时)**不等于没开成**:服务端很可能已经把
      // 机器建起来了,正在计费。直接标成「开机失败」会让用户以为什么都没发生,
      // 而那台机器在后台一路烧到 4 小时硬上限。所以回去问服务端,以它为准。
      thrown = e;
      state = state.copyWith(error: '$e');
    }
    // busy 撑到真状态到手为止:这中间界面显示「启动中」,而不是被那份空视图
    // 打回「未启动」。refresh 里的 busy 分支正是为这一小段准备的。
    await refresh();
    state = state.copyWith(busy: false);
    if (thrown != null && !addMore && !_serverHasRental) {
      // 请求没打出去,而且服务端名下确实一台都没有 —— 这才是真的没开成。
      // (服务端 `_boot_one` 的第一件事就是把 Rental 建出来置 creating,
      //  只要它跑过一次,上面那发 status 就查得到。)
      state = state.copyWith(status: RentalStatus.failed, note: '$thrown');
    }
    // 剩下的情况:下单成功 → creating(轮询接手);下单成功但机器瞬间就没了
    // → 下一轮轮询的 creating→none 分支判成失败。
    _rearm();
  }

  /// 关机结账。返回服务端给的结账摘要(秒数 / 金额 / 出图张数),供 UI 回执。
  ///
  /// ⚠ **不带 instance_id = 这个账号名下全部停止。** 服务端 2026-08-19 起支持
  /// 一人多机(上限 4 台,web 那边能加开),app 没有多机界面,所以这里就是
  /// 「全部关掉」—— 界面上的按钮文案必须跟着说清楚,不能让人以为只关了一台。
  Future<Map<String, dynamic>?> stop({String instanceId = ''}) async {
    final sid = _session;
    if (sid == null || sid.isEmpty || state.busy || !state.active) return null;
    // 只停其中一台时**不切整卡状态**:别的机器还在跑,把整张卡切成「关机中」
    // 会让人以为全停了。忙位挡住重复点就够,真状态交给下面那发 refresh。
    final all = instanceId.isEmpty;
    state = all
        ? state.copyWith(status: RentalStatus.ending, busy: true, error: '')
        : state.copyWith(busy: true, error: '');
    try {
      final j = await _client.rentalStop(sid, instanceId: instanceId);
      if (all) {
        state = const RentalState().copyWith(
          idleChoices: state.idleChoices,
          idleDefault: state.idleDefault,
          maxUptimeS: state.maxUptimeS,
          bootHintS: state.bootHintS,
          ratePerHour: state.ratePerHour,
          // 档位清单是「有哪些能开」,与开没开机无关 —— 关机后清掉的话,
          // 配置卡会退回没有选择器的老样子,直到下一次 status 回来才恢复。
          tiers: state.tiers,
          maxCount: state.maxCount,
        );
      } else {
        state = state.copyWith(busy: false);
      }
      unawaited(refresh());
      return j['ok'] == true ? j : null;
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
      unawaited(refresh());
      return null;
    }
  }

  /// 改空闲自动关机时长。运行中即时生效;没在跑就只记偏好(下次开机带上)。
  Future<void> setIdle(int seconds) async {
    await ref
        .read(rentalPrefsProvider.notifier)
        .patch((p) => p.copyWith(idleSeconds: seconds));
    if (!state.active) {
      state = state.copyWith(idleSeconds: seconds);
      return;
    }
    final sid = _session;
    if (sid == null || sid.isEmpty) return;
    state = state.copyWith(idleSeconds: seconds); // 先落地,失败再由轮询拉回
    try {
      final j = await _client.rentalSetIdle(sid, seconds);
      if (j['ok'] == true) state = state.merge(j, _now());
    } catch (_) {
      unawaited(refresh());
    }
  }

  /// 失败态是个死胡同,给个「知道了」的出口回到未启动。
  void dismissFailure() {
    if (state.status == RentalStatus.failed) {
      state = state.copyWith(status: RentalStatus.none, note: '', error: '');
    }
  }
}

/// 计时读数 `12:34` / `1:02:03`。
String fmtUptime(int seconds) {
  final s = seconds.clamp(0, 1 << 30);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 金额读数:两位小数带 ¥。
String fmtYuan(double v) => '¥${v.toStringAsFixed(2)}';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../util/log.dart';
import 'backend_config.dart';
import 'nai_client.dart' show NaiUsage, parseNaiUsage;

/// 后端请求失败(网络/非 2xx/格式)。`message` 为可直接展示的人类可读文案。
class BackendException implements Exception {
  BackendException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// 从任务结果里取**这一批全部图的 URL**(形如 `/api/i/<hash>.png`)。
///
/// 服务端 2026-09-04 起**不再在控制平面里下发图片字节**:`url` 是第一张,
/// `count > 1` 时另带 `urls`(含第一张)。字节要自己 GET 一次,见
/// [BackendClient.fetchResultImage]。
///
/// 为什么改:以前结果是 `{type:'base64', imageBase64}`,那份 base64 会随
/// `task_update` 推一遍、再随每一次轮询响应重发一遍。实测 2718 张图对应
/// 2730 次带图轮询,占了后端出向流量的 39.5%。换成 URL 之后字节只出一次,
/// 重复请求由 HTTP 缓存吸收(内容寻址 + immutable)。
///
/// WS 的 `task_update` 和轮询的 `GET /api/bot/task/{id}` 用的是同一份结构,
/// 所以这段拆出来共用:两处各写一遍迟早只改对一处。
List<String> botResultUrls(Object? result) {
  if (result is! Map) return const [];
  final all = result['urls'];
  if (all is List) {
    final out = [
      for (final v in all)
        if (v is String && v.isNotEmpty) v,
    ];
    if (out.isNotEmpty) return out;
  }
  final one = result['url'];
  return (one is String && one.isNotEmpty) ? [one] : const [];
}

/// bot 模式一次任务查询的快照(`GET /api/bot/task/{id}`)。
class BotTask {
  BotTask({
    required this.success,
    this.status,
    this.step = 0,
    this.totalSteps = 0,
    this.urls = const [],
    this.error,
    this.warning,
    this.queuePosition = 0,
  });

  final bool success; // 任务是否存在
  final String? status; // queued/starting/generating/completed/failed/cancelled
  final int step;
  final int totalSteps;

  /// 完成时这一批全部图的 URL(单张时长度 1)。**不是字节** ——
  /// 拿它去 [BackendClient.fetchResultImage] 取。
  final List<String> urls;
  final String? error;

  /// 非致命提醒:图照常出,但有东西没生效(目前只有 LoRA 超上限被丢弃)。
  final String? warning;
  final int queuePosition;

  bool get completed => status == 'completed';
  bool get failed => status == 'failed' || status == 'cancelled';

  factory BotTask.fromJson(Map<String, dynamic> j) {
    return BotTask(
      success: j['success'] == true,
      status: j['status'] as String?,
      step: (j['step'] as num?)?.toInt() ?? 0,
      totalSteps: (j['total_steps'] as num?)?.toInt() ?? 0,
      urls: botResultUrls(j['result']),
      error: j['error'] as String?,
      warning: j['warning'] as String?,
      queuePosition: (j['queue_position'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 公共 Vibe 库列表项(`GET /api/vibes/list`,不含图片/编码本体)。
class PublicVibeMeta {
  PublicVibeMeta({
    required this.id,
    required this.name,
    required this.filename,
    required this.thumbnailUrl,
    this.supportedModels = const [],
    this.defaultStrength,
    this.defaultInfoExtracted,
    this.createdAt = 0,
    this.hasImage = true,
    this.uploaderId,
  });

  final String id;
  final String name;
  final String filename;

  /// 公开缩略图端点绝对 URL(直接喂 RemoteImage)。
  final String thumbnailUrl;
  final List<String> supportedModels;
  final double? defaultStrength;
  final double? defaultInfoExtracted;
  final int createdAt;
  final bool hasImage;
  final String? uploaderId;
}

/// 个人云端 Vibe 列表项(`GET /api/user-vibes/list`,不含图片/编码本体)。
/// [imageHash] / [metaHash] 由后端算出,恢复时与本地存的上次同步值比对定去留。
class CloudVibeMeta {
  CloudVibeMeta({
    required this.id,
    required this.name,
    required this.filename,
    this.supportedModels = const [],
    this.defaultStrength,
    this.defaultInfoExtracted,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.tags = const [],
    this.hasImage = true,
    this.imageHash,
    this.metaHash,
  });

  final String id;
  final String name;
  final String filename;
  final List<String> supportedModels;
  final double? defaultStrength;
  final double? defaultInfoExtracted;
  final int createdAt;
  final int updatedAt;
  final List<String> tags;
  final bool hasImage;
  final String? imageHash;
  final String? metaHash;

  /// 缺 filename 的条目无法取文件,直接丢弃(后端理论上不会给,防脏数据)。
  static CloudVibeMeta? fromJson(Map<String, dynamic> j) {
    final filename = j['filename'];
    if (filename is! String || filename.isEmpty) return null;
    return CloudVibeMeta(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      filename: filename,
      supportedModels: j['supportedModels'] is List
          ? [
              for (final m in j['supportedModels'] as List)
                if (m is String) m,
            ]
          : const [],
      defaultStrength: (j['defaultStrength'] as num?)?.toDouble(),
      defaultInfoExtracted: (j['defaultInfoExtracted'] as num?)?.toDouble(),
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      tags: j['tags'] is List
          ? [
              for (final t in j['tags'] as List)
                if (t is String) t,
            ]
          : const [],
      hasImage: j['hasImage'] != false,
      imageHash: j['image_hash'] as String?,
      metaHash: j['meta_hash'] as String?,
    );
  }
}

/// 备份/恢复操作记录一条(`GET /api/user-vibes/backup-log`)。
class BackupLogEntry {
  BackupLogEntry({
    required this.device,
    required this.action,
    required this.time,
    required this.count,
    required this.detail,
  });

  final String device;

  /// `backup` | `restore`
  final String action;

  /// unix 秒。
  final int time;
  final int count;
  final String detail;

  bool get isBackup => action == 'backup';

  factory BackupLogEntry.fromJson(Map<String, dynamic> j) => BackupLogEntry(
    device: j['device']?.toString() ?? '未知设备',
    action: j['action']?.toString() ?? 'backup',
    time: (j['time'] as num?)?.toInt() ?? 0,
    count: (j['vibe_count'] as num?)?.toInt() ?? 0,
    detail: j['detail']?.toString() ?? '',
  );
}

/// 公共画师串列表项(`GET /api/artists/list`)。
class PublicArtistMeta {
  PublicArtistMeta({
    required this.id,
    required this.name,
    required this.artistString,
    this.negative = '',
    this.previewUrl,
    this.usageCount = 0,
    this.createdTime = 0,
    this.addedBy,
    this.ownerId,
    this.models = const [],
  });

  final String id;
  final String name;
  final String artistString;
  final String negative;

  /// 预览图绝对 URL(端点公开;无图为 null)。
  final String? previewUrl;
  final int usageCount;
  final int createdTime; // 秒
  final String? addedBy;
  final String? ownerId;

  /// 适用模型 id(见 features/inspiration/artist_models.dart)。空 = 通用。
  /// 服务端不校验 id 在不在已知模型表里,所以这里也原样收 —— 新版客户端标的
  /// id 不该被老版静默吃掉。
  final List<String> models;
}

/// 公共 OC(角色)列表项(`GET /api/oc/list`)。
class PublicOcMeta {
  PublicOcMeta({
    required this.enName,
    this.zhName,
    this.aliases = const [],
    required this.tagGroup,
    this.negativePrompt = '',
    this.previewUrl,
    this.createdBy,
    this.ownerId,
    this.createdAt = 0,
  });

  final String enName; // 服务端主键
  final String? zhName;
  final List<String> aliases;
  final String tagGroup;
  final String negativePrompt;
  final String? previewUrl;
  final String? createdBy;
  final String? ownerId;
  final int createdAt; // 秒

  String get displayName =>
      zhName != null && zhName!.isNotEmpty ? zhName! : enName;
}

/// 公共库作者(`GET /api/public/authors`):在公共画师串 / OC 里有条目的人。
/// [id] 就是列表接口给的 owner_id(QQ 号;存量数据可能是个名字串),
/// [nickname] 由服务端从 bot 的昵称表里查(查不到为 null,显示回落到 [id])。
class PublicAuthorMeta {
  const PublicAuthorMeta({required this.id, this.nickname});

  final String id;
  final String? nickname;

  /// 展示名:有昵称用昵称,没有就是那串 QQ 号。
  String get label => nickname != null && nickname!.isNotEmpty ? nickname! : id;
}

/// 「我的 NAI 5 额度」(`GET /api/user/quota`)—— **我们自己**发给每个用户的
/// 出图配额,和 [BackendClient.getAnlas] 顺路带回的那块 `usage` 是两码事:
/// 那块是 NAI 官方发给共享号池的电池,空了是大家一起没得用;这块空了只影响自己。
///
/// 只有 nai5 的生成扣它,其它模型(含 V4.5 / V4 / anima / krea)一律不限。
class NaiQuota {
  const NaiQuota({
    this.balance = 0,
    this.limit = 0,
    this.extra = 0,
    this.activated = true,
    this.isAdmin = false,
    this.freeMode = false,
    this.refillPerDay = 0,
  });

  /// 今日余额(张)。服务端按秒连续回充,所以带小数 —— 显示时**向下**取整,
  /// 免得报了 1 张、点进去却扣不动。
  final double balance;

  /// 容量(张)。[isAdmin] 时无意义(管理员不设上限)。
  final int limit;

  /// 赠送额度(转赠而来)。**不受容量封顶**(可以超过 [limit]),所以单列而不是
  /// 并进 [balance] —— 塞进同一根进度条会让「上限」这个概念失真。
  final double extra;

  /// 出图资格。false = 没有:V5 额度只发给上线前用过 bot 出图的老用户。
  /// 这和「额度用完了」是完全不同的处境 —— 后者等回充就行,前者等多久都不会有。
  ///
  /// 老服务端不下发这个字段,缺省按有资格算,免得平白多出一块假警报。
  final bool activated;

  /// 管理员:不扣额度、不设上限。
  final bool isAdmin;

  /// 免额度窗口:共享号电池充盈时**既不扣也不挡**(额度为 0 的人照样能出)。
  /// 窗口一关就自动恢复扣减,所以这期间攒不下任何东西。
  final bool freeMode;

  /// 每天回充多少张。
  final double refillPerDay;

  /// 现在能出几张(余额 + 赠送)。
  int get available => (balance + extra).floor();

  factory NaiQuota.fromJson(Map<String, dynamic> j) => NaiQuota(
    balance: (j['daily_balance'] as num?)?.toDouble() ?? 0,
    limit: (j['daily_limit'] as num?)?.toInt() ?? 0,
    extra: (j['extra_balance'] as num?)?.toDouble() ?? 0,
    activated: j['activated'] != false,
    isAdmin: j['is_admin'] == true,
    freeMode: j['free_mode'] == true,
    refillPerDay: (j['refill_per_day'] as num?)?.toDouble() ?? 0,
  );
}

/// 一段用量统计(个人 `/api/user/stats` 与平台 `/api/platform/stats(/all)`
/// 共用一个形状,后者多活跃/总用户与起止时间)。
class UsageStats {
  const UsageStats({
    this.imageCalls = 0,
    this.aiCalls = 0,
    this.pointsSpent = 0,
    this.activeUsers = 0,
    this.totalUsers = 0,
    this.v5Calls = 0,
    this.v5Points = 0,
    this.v5Users = 0,
    this.firstRecord,
    this.lastRecord,
  });

  final int imageCalls;
  final int aiCalls;
  final int pointsSpent;
  final int activeUsers;
  final int totalUsers;

  /// NAI 5 单列:张数、点数、用过的人数([v5Users] 仅平台端点有)。
  ///
  /// 点数必须单列 —— V5 扣点是 V4.5 的 1.5 倍,光看张数看不出真实消耗;
  /// 人数则能看出计费新规(V5 超 10 张就进付费档)的影响面。
  ///
  /// ⚠ 服务端 2026-08-23 才给 calls 表加 model 列,更早的行一律 NULL、这里
  /// 统计不到 —— 所以「历史全局」里这三个数实际是**自那天起**的累计。
  /// 那之前 V5 还没上线,所以口径本身没错,只是更早的区间恒为 0。
  final int v5Calls;
  final int v5Points;
  final int v5Users;

  /// ISO 时间串(仅 `/platform/stats/all` 返回)。
  final String? firstRecord;
  final String? lastRecord;

  factory UsageStats.fromJson(Map<String, dynamic> j) => UsageStats(
    imageCalls: (j['image_calls'] as num?)?.toInt() ?? 0,
    aiCalls: (j['ai_calls'] as num?)?.toInt() ?? 0,
    pointsSpent: (j['points_spent'] as num?)?.toInt() ?? 0,
    v5Calls: (j['v5_calls'] as num?)?.toInt() ?? 0,
    v5Points: (j['v5_points'] as num?)?.toInt() ?? 0,
    v5Users: (j['v5_users'] as num?)?.toInt() ?? 0,
    activeUsers: (j['active_users'] as num?)?.toInt() ?? 0,
    totalUsers: (j['total_users'] as num?)?.toInt() ?? 0,
    firstRecord: j['first_record'] as String?,
    lastRecord: j['last_record'] as String?,
  );
}

/// 每日(time_range=today 时为每小时)个人用量点(`/api/user/stats/daily`)。
class DailyStat {
  const DailyStat({
    required this.date,
    required this.imageCalls,
    required this.pointsSpent,
  });

  /// `yyyy-MM-dd`;今日档为 `HH:mm`。
  final String date;
  final int imageCalls;
  final int pointsSpent;
}

/// 平台 24 小时热力图种类(端点与字段名随种类不同)。
enum HourlyKind {
  calls('hourly-heatmap', 'avg_calls', 'total_calls'),
  users('hourly-users', 'avg_users', 'total_users'),
  duration('hourly-duration', 'avg_duration', 'count');

  const HourlyKind(this.path, this.avgKey, this.totalKey);
  final String path;
  final String avgKey;
  final String totalKey;
}

/// 平台热力图一份(24 格 + 有效天数)。
class HourlyHeat {
  const HourlyHeat({this.cells = const [], this.totalDays = 1});

  final List<({int hour, double avg, double total})> cells;
  final int totalDays;
}

/// 账单里「一个人」的一行。estimate 的 current_user 与 settlement 结构略异:
/// settlement 直接给 `total_fee`;estimate 只给 `image_fee`/`anlas_fee`,总费
/// 需两者相加(web 同款)。这里 totalFee 取 `total_fee`,缺省时回落到分项和。
class BillingParty {
  const BillingParty({
    this.tierName = '免费',
    this.imageCalls = 0,
    this.v5Calls = 0,
    this.localCalls = 0,
    this.anlasUsed = 0,
    this.totalFee = 0,
  });

  final String tierName;

  /// **分摊基数**:只含 NAI 出图。anima / krea 走算力账单按机时实付,不进这本账
  /// (它们的张数在 [localCalls])。
  final int imageCalls;

  /// 其中的 V5 张数。V5 只有一点防误触容差,超了就整体进付费档 —— 不摆出来的话
  /// 用户完全看不出自己为什么被划到付费档。
  final int v5Calls;

  /// anima / krea 等自建后端张数。**不参与计费**,只用来说明「这些不进分摊」——
  /// 不写的话,用自建后端的人对着自己的出图记录会以为这里少算了。
  final int localCalls;

  final int anlasUsed;
  final double totalFee;

  factory BillingParty.fromJson(Map<String, dynamic> j) {
    final total = (j['total_fee'] as num?)?.toDouble();
    final imgFee = (j['image_fee'] as num?)?.toDouble() ?? 0;
    final anlasFee = (j['anlas_fee'] as num?)?.toDouble() ?? 0;
    return BillingParty(
      tierName: j['tier_name'] as String? ?? '免费',
      imageCalls: (j['image_calls'] as num?)?.toInt() ?? 0,
      v5Calls: (j['v5_calls'] as num?)?.toInt() ?? 0,
      localCalls: (j['local_calls'] as num?)?.toInt() ?? 0,
      anlasUsed: (j['anlas_used'] as num?)?.toInt() ?? 0,
      totalFee: total ?? (imgFee + anlasFee),
    );
  }
}

/// 一档阶梯的分布(人数/总张数/总费用),用于账单页的阶梯表。
typedef TierRow = ({int count, int images, double fee});

/// 计费报告(`/api/billing/estimate` 与 `/api/billing/settlement` 同结构,
/// 均出自服务端 `_compute_billing`;后者多支付状态)。
class BillingReport {
  const BillingReport({
    this.me,
    this.periodLabel = '',
    this.freeThreshold = 0,
    this.v5FreeThreshold = 0,
    this.t1 = 0,
    this.t2 = 0,
    this.distribution = const {},
    this.activeUsers = 0,
    this.earlyMode = false,
    this.paymentStatus = '',
    this.beforeStartFrom = false,
    this.billingStartFrom = '',
  });

  final BillingParty? me;

  /// 周期标签,形如 `07/23 - 08/23`。
  final String periodLabel;

  /// 免费线(张);[t1]/[t2] 为付费用户内 P50/P80 分界(0 = 人太少走均摊)。
  final int freeThreshold;

  /// V5 的免费容差(张)。和 [freeThreshold] 是**两条各算各的**线:
  /// V4.5 及更早看自己那条,V5 看这条,两条都不超才算免费档。
  /// 这条是「防误触」不是「送额度」—— 点错一两张不该把人划进付费档,但真拿
  /// V5 当主力用就得进付费池,且超了以后 V5 张数一张都不免。
  final int v5FreeThreshold;

  final int t1;
  final int t2;

  /// 阶梯名(免费/一阶/二阶/三阶/均摊)→ 分布。
  final Map<String, TierRow> distribution;
  final int activeUsers;

  /// 预估专属:周期早期样本不足。
  final bool earlyMode;

  /// 结算专属:`paid` | `unpaid` | `free`。
  final String paymentStatus;

  /// 该周期整个早于新计费规则的生效日([billingStartFrom])—— 那段消费在旧规则
  /// 下早就结清了,不重复出账。为真时服务端连明细都不下发,界面要**整块换成
  /// 空态**而不是把金额显示成 ¥0:后者会连着阶梯表一起画出来(「免费 0 人 /
  /// 一阶 0 人 … 总计 ¥0」),看着像「这期大家都没用」。
  final bool beforeStartFrom;

  /// 新规则生效日,`yyyy-MM-dd`。
  final String billingStartFrom;

  /// 结算日(每月几号)。服务端不单独下发,从 [periodLabel] 的收尾日期里取 ——
  /// 那个分界日改过一次(27 → 23),写死的话下次再改又得回来改一遍。
  /// 解析不出就回落到 23(当前配置)。
  int get cycleDay {
    final m = RegExp(r'(\d{1,2})\s*$').firstMatch(periodLabel);
    return int.tryParse(m?.group(1) ?? '') ?? 23;
  }

  /// 该阶梯的张数区间文案(对齐 web);均摊态没有区间。
  String rangeOf(String tier) => switch (tier) {
    // 免费档现在是**两条线同时满足**。只写「≤200 张」的话,超了 V5 容差却没
    // 超 200 的人完全看不懂自己为什么在付费档。
    '免费' =>
      v5FreeThreshold > 0
          ? '≤$freeThreshold·V5≤$v5FreeThreshold'
          : '≤$freeThreshold 张',
    '一阶' => t1 > 0 ? '${freeThreshold + 1}~$t1 张' : '—',
    '二阶' => t2 > 0 ? '${(t1 == 0 ? freeThreshold : t1) + 1}~$t2 张' : '—',
    '三阶' => t2 > 0 ? '>$t2 张' : '—',
    _ => '>$freeThreshold 张',
  };

  /// 人均费用;无样本返回 null。
  double? avgFeeOf(String tier) {
    final r = distribution[tier];
    if (r == null || r.count == 0) return null;
    return r.fee / r.count;
  }

  factory BillingReport.fromJson(Map<String, dynamic> j) {
    final tiers = j['tiers'];
    final dist = j['tier_distribution'];
    return BillingReport(
      me: j['current_user'] is Map<String, dynamic>
          ? BillingParty.fromJson(j['current_user'] as Map<String, dynamic>)
          : null,
      periodLabel: j['billing_month']?.toString() ?? '',
      freeThreshold:
          (tiers is Map ? (tiers['free'] as num?)?.toInt() : null) ??
          (j['free_threshold'] as num?)?.toInt() ??
          0,
      v5FreeThreshold:
          (tiers is Map ? (tiers['v5_free'] as num?)?.toInt() : null) ??
          (j['v5_free_threshold'] as num?)?.toInt() ??
          0,
      t1: tiers is Map ? ((tiers['t1'] as num?)?.toInt() ?? 0) : 0,
      t2: tiers is Map ? ((tiers['t2'] as num?)?.toInt() ?? 0) : 0,
      distribution: {
        if (dist is Map)
          for (final e in dist.entries)
            if (e.value is Map)
              e.key.toString(): (
                count: ((e.value as Map)['count'] as num?)?.toInt() ?? 0,
                images:
                    ((e.value as Map)['total_images'] as num?)?.toInt() ?? 0,
                fee: ((e.value as Map)['total_fee'] as num?)?.toDouble() ?? 0,
              ),
      },
      activeUsers: (j['active_user_count'] as num?)?.toInt() ?? 0,
      earlyMode: j['estimate_mode'] == 'early',
      paymentStatus: j['payment_status']?.toString() ?? '',
      beforeStartFrom: j['before_start_from'] == true,
      billingStartFrom: j['billing_start_from']?.toString() ?? '',
    );
  }
}

/// 一笔点数消耗(`points_spent` 行)。[reason] 由服务端拼装,
/// 形如 `web生图(生图832x1216_28步=20, 角色参考x1=5)`。
class PointRecord {
  const PointRecord({
    required this.time,
    required this.points,
    required this.reason,
    this.isV5 = false,
  });

  /// 本地时间(服务端按北京时间落库,无时区后缀)。
  final DateTime? time;
  final int points;
  final String reason;

  /// 这笔是不是 V5 出的。服务端 2026-08-23 起才按模型落库,更早的记录一律 false
  /// —— 那之前 V5 还没上线,所以这个缺省是对的,不是「不知道」。
  final bool isV5;

  factory PointRecord.fromJson(Map<String, dynamic> j) => PointRecord(
    time: DateTime.tryParse(j['timestamp']?.toString() ?? ''),
    points: (j['points'] as num?)?.toInt() ?? 0,
    reason: j['reason']?.toString() ?? '',
    // 服务端直接给了判定结果,别在客户端再解析一遍 model 前缀:两处各判各的
    // 迟早分叉(比如以后多一档 nai-diffusion-5-xxx)
    isV5: j['is_v5'] == true,
  );
}

/// 一笔生成记录(`/api/user/stats/calls`)。老记录只有时间,参数为空。
class CallRecord {
  const CallRecord({
    required this.time,
    this.width = 0,
    this.height = 0,
    this.steps = 0,
    this.model = '',
    this.anlas = 0,
    this.img2img = false,
    this.charRefs = 0,
  });

  final DateTime? time;
  final int width;
  final int height;
  final int steps;

  /// 服务端模型 id(如 `nai-diffusion-4-5-full`)。
  final String model;

  /// 该次生成扣的点数;0 = 免费档。
  final int anlas;
  final bool img2img;
  final int charRefs;

  bool get hasParams => width > 0 && height > 0;

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
    time: DateTime.tryParse(j['timestamp']?.toString() ?? ''),
    width: (j['w'] as num?)?.toInt() ?? 0,
    height: (j['h'] as num?)?.toInt() ?? 0,
    steps: (j['steps'] as num?)?.toInt() ?? 0,
    model: j['model']?.toString() ?? '',
    anlas: (j['anlas'] as num?)?.toInt() ?? 0,
    img2img: j['i2i'] == true,
    charRefs: (j['pr'] as num?)?.toInt() ?? 0,
  );
}

/// 某窗口内的消耗明细(`/api/billing/user/details`,窗口可指定到某一天)。
class UsageDetails {
  const UsageDetails({
    this.records = const [],
    this.breakdown = const [],
    this.imageCalls = 0,
    this.points = 0,
    this.v5Calls = 0,
    this.v5Points = 0,
    this.localCalls = 0,
  });

  /// 逐笔消耗,新→旧(服务端上限 50 条)。
  final List<PointRecord> records;

  /// 按 reason 归并 (原因, 点数, 笔数),另带该组里 V5 占的点数/笔数。
  /// 不按模型拆组 —— reason 里已经写了尺寸步数,再按模型拆会把同一类消耗切成两行。
  final List<
    ({String reason, int points, int count, int v5Points, int v5Count})
  >
  breakdown;

  /// **全部**出图(含自建后端),与个人中心那个「生图次数」磁贴同口径。
  final int imageCalls;
  final int points;

  /// 其中的 V5 张数与点数。V5 扣点是 V4.5 的 1.5 倍,张数看不出真实消耗。
  final int v5Calls;
  final int v5Points;

  /// anima / krea 等自建后端张数 —— 计在 [imageCalls] 里,但**不进 NAI 分摊**。
  final int localCalls;
}

/// 一条算力消费。**出图租卡和生成视频合在一条时间线上** —— 它们是同一类账目
/// (按次实付、直计不分摊);生图那笔是订阅制月盘子按用量分摊,性质不同,
/// 在 NAI 账单那一页。
class GpuBillItem {
  const GpuBillItem({
    required this.kind,
    required this.time,
    required this.cost,
    required this.seconds,
    this.minutes = 0,
    this.jobsDone = 0,
    this.jobsFailed = 0,
    this.reason = '',
    this.preset = '',
    this.mode = '',
  });

  /// `rental` 出图租卡 / `video` 生成视频。
  final String kind;

  /// ISO 时间串,服务端原样给的。
  final String time;

  /// 元。
  final double cost;

  /// rental = 租用秒数;video = 成片时长。
  final int seconds;

  // —— kind == 'rental' ——
  final double minutes;
  final int jobsDone;
  final int jobsFailed;

  /// 关机原因(用户主动 / 空闲超时 / 超过硬上限 / 失联)。
  final String reason;

  // —— kind == 'video' ——
  final String preset;
  final String mode;

  bool get isRental => kind == 'rental';

  factory GpuBillItem.fromJson(Map<String, dynamic> j) => GpuBillItem(
    kind: j['kind']?.toString() ?? '',
    time: j['time']?.toString() ?? '',
    cost: (j['cost'] as num?)?.toDouble() ?? 0,
    seconds: (j['seconds'] as num?)?.toInt() ?? 0,
    minutes: (j['minutes'] as num?)?.toDouble() ?? 0,
    jobsDone: (j['jobs_done'] as num?)?.toInt() ?? 0,
    jobsFailed: (j['jobs_failed'] as num?)?.toInt() ?? 0,
    reason: j['reason']?.toString() ?? '',
    preset: j['preset']?.toString() ?? '',
    mode: j['mode']?.toString() ?? '',
  );
}

/// 还在跑、**还没结算**的那一台。合计里已经算进去了(用户看的是「到现在为止
/// 花了多少」,不是「已结算多少」),所以界面上要把它单独标出来 —— 它的数还在涨。
class GpuBillRunning {
  const GpuBillRunning({this.seconds = 0, this.jobsDone = 0, this.cost = 0});

  final int seconds;
  final int jobsDone;
  final double cost;

  factory GpuBillRunning.fromJson(Map<String, dynamic> j) => GpuBillRunning(
    seconds: (j['seconds'] as num?)?.toInt() ?? 0,
    jobsDone: (j['jobs_done'] as num?)?.toInt() ?? 0,
    cost: (j['cost'] as num?)?.toDouble() ?? 0,
  );
}

/// 上期算力账单:管理员结算那一刻定死的快照,**只含自己那份**。
///
/// 这是实际要付的钱,所以服务端读的是结算行里存下的数、不回头重算 ——
/// 补录、改价、误删任何一样都会让界面上的数和已经收过的钱对不上。
///
/// 上期一分没花的人不下发这块(为从没用过算力的人摆一张 ¥0.00 只是噪音)。
class GpuLastPeriod {
  const GpuLastPeriod({
    this.label = '',
    this.cost = 0,
    this.rentalCost = 0,
    this.rentalCount = 0,
    this.rentalHours = 0,
    this.videoCost = 0,
    this.videoCount = 0,
    this.videoSeconds = 0,
  });

  /// 跨度,形如 `7/25 09:30 - 8/23 10:56`。
  final String label;
  final double cost;

  final double rentalCost;
  final int rentalCount;
  final double rentalHours;

  final double videoCost;
  final int videoCount;
  final int videoSeconds;

  factory GpuLastPeriod.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String k) =>
        (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final r = sub('rental');
    final v = sub('video');
    return GpuLastPeriod(
      label: j['label']?.toString() ?? '',
      cost: (j['cost'] as num?)?.toDouble() ?? 0,
      rentalCost: (r['cost'] as num?)?.toDouble() ?? 0,
      rentalCount: (r['count'] as num?)?.toInt() ?? 0,
      rentalHours: (r['hours'] as num?)?.toDouble() ?? 0,
      videoCost: (v['cost'] as num?)?.toDouble() ?? 0,
      videoCount: (v['count'] as num?)?.toInt() ?? 0,
      videoSeconds: (v['seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 算力账单(`GET /api/rental/bills`)。
///
/// ⚠ 服务端**只下发售价**,机时成本/毛利根本不在返回里 —— 别去别处拼一个出来。
class GpuBills {
  const GpuBills({
    this.ok = false,
    this.items = const [],
    this.running,
    this.periodLabel = '',
    this.settled = false,
    this.lastPeriod,
    this.totalCost = 0,
    this.rentalCost = 0,
    this.rentalHours = 0,
    this.rentalJobs = 0,
    this.rentalCount = 0,
    this.videoCost = 0,
    this.videoSeconds = 0,
    this.videoCount = 0,
    this.ratePerHour = 0,
    this.message = '',
  });

  final bool ok;

  /// 逐笔,新→旧。两张表各取最近 N 条后按时间归并再砍回 N。
  final List<GpuBillItem> items;
  final GpuBillRunning? running;

  /// 上面那些数的**口径**:管理员在 bot 里结一次账就划一期。
  /// [settled] = 已经结过账(那时这些数只算这一期,[periodLabel] 形如
  /// `8/23 10:56 结算后`);没结过账时口径仍是全部历史,界面照旧说「累计」。
  final String periodLabel;
  final bool settled;

  /// 上期账单快照,见 [GpuLastPeriod]。没结过账 / 上期没花钱时为 null。
  final GpuLastPeriod? lastPeriod;

  /// 租卡 + 视频之和(本期,见 [settled])。
  final double totalCost;

  final double rentalCost;
  final double rentalHours;
  final int rentalJobs;
  final int rentalCount;

  final double videoCost;
  final int videoSeconds;
  final int videoCount;

  final double ratePerHour;
  final String message;

  /// **本期**一分钱都还没花过。刚结完账正是这个状态,那时 [lastPeriod] 还在,
  /// 界面要照样把上期那张卡摆出来 —— 不然用户会以为自己的消费记录凭空没了,
  /// 而那笔钱恰恰是现在要付的。
  bool get isEmpty => items.isEmpty && running == null;

  factory GpuBills.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String k) =>
        (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final r = sub('rental');
    final v = sub('video');
    final run = j['running'];
    final period = sub('period');
    final last = j['last_period'];
    return GpuBills(
      ok: j['ok'] == true,
      items: [
        for (final e in (j['items'] as List?) ?? const [])
          if (e is Map) GpuBillItem.fromJson(e.cast<String, dynamic>()),
      ],
      running: run is Map
          ? GpuBillRunning.fromJson(run.cast<String, dynamic>())
          : null,
      // since 为空 = 还没结过账 → 口径是全部历史(老服务端没有 period 块,
      // 落在同一条路径上,行为不变)
      settled: (period['since']?.toString() ?? '').isNotEmpty,
      periodLabel: period['label']?.toString() ?? '',
      lastPeriod: last is Map
          ? GpuLastPeriod.fromJson(last.cast<String, dynamic>())
          : null,
      totalCost: (j['total_cost'] as num?)?.toDouble() ?? 0,
      rentalCost: (r['cost'] as num?)?.toDouble() ?? 0,
      rentalHours: (r['hours'] as num?)?.toDouble() ?? 0,
      rentalJobs: (r['jobs'] as num?)?.toInt() ?? 0,
      rentalCount: (r['count'] as num?)?.toInt() ?? 0,
      videoCost: (v['cost'] as num?)?.toDouble() ?? 0,
      videoSeconds: (v['seconds'] as num?)?.toInt() ?? 0,
      videoCount: (v['count'] as num?)?.toInt() ?? 0,
      ratePerHour: (j['rate_per_hour'] as num?)?.toDouble() ?? 0,
      message: j['message']?.toString() ?? '',
    );
  }
}

/// 机房已装 LoRA 卡片(`GET /api/lora/list`;anima 出图渠道专用)。
/// [favorited] 需带会话查询才有意义(是否在「我的库」);[addedBy] == 'bot'
/// 的官方条目豁免无人收藏时的回收。
class LoraCardInfo {
  const LoraCardInfo({
    required this.name,
    required this.displayName,
    this.type = 'concept',
    this.triggerWords = const [],
    this.recommendedWeight = 0.8,
    this.previewUrl = '',
    this.sourceUrl = '',
    this.sizeMb,
    this.syncStatus = 'synced',
    this.usageCount = 0,
    this.addedBy = 'web',
    this.favorited = false,
    this.favoriteCount = 0,
    this.visibility = 'public',
    this.isOwner = false,
    this.syncError,
    this.hasTe,
  });

  /// LR 编号(LR1…),生成载荷与收藏操作都用它。
  final String name;
  final String displayName;

  /// character / style / concept。
  final String type;
  final List<String> triggerWords;
  final double recommendedWeight;
  final String previewUrl;
  final String sourceUrl;
  final double? sizeMb;

  /// synced = 已在机房就绪;其余值(pending/uploading/failed)不可挂载。
  final String syncStatus;
  final int usageCount;
  final String addedBy;
  final bool favorited;
  final int favoriteCount;

  /// public / private —— 私有条目只有上传者本人拉得到,也不进公共库。
  final String visibility;

  /// 当前账号是不是这条的上传者(重试推送只有本人能做)。
  final bool isOwner;

  /// 推送机房失败的原因([syncStatus] == 'failed' 时才有)。
  final String? syncError;

  /// 有没有文本编码器权重。false = 只训了画面侧,CLIP 强度调了不会有任何变化;
  /// null = 服务端还没探测过(老条目),按可调处理。
  final bool? hasTe;

  bool get ready => syncStatus == 'synced';
  bool get isPrivate => visibility == 'private';

  /// 用户自己上传的文件还在 server→机房的推送途中。
  bool get pushing => syncStatus == 'uploading';

  /// 就地改收藏关系用;只列会变的那两个字段,其余原样带过。
  LoraCardInfo copyWith({bool? favorited, int? favoriteCount}) => LoraCardInfo(
    name: name,
    displayName: displayName,
    type: type,
    triggerWords: triggerWords,
    recommendedWeight: recommendedWeight,
    previewUrl: previewUrl,
    sourceUrl: sourceUrl,
    sizeMb: sizeMb,
    syncStatus: syncStatus,
    usageCount: usageCount,
    addedBy: addedBy,
    favorited: favorited ?? this.favorited,
    favoriteCount: favoriteCount ?? this.favoriteCount,
    visibility: visibility,
    isOwner: isOwner,
    syncError: syncError,
    hasTe: hasTe,
  );

  factory LoraCardInfo.fromJson(Map<String, dynamic> j) => LoraCardInfo(
    name: j['name']?.toString() ?? '',
    displayName: (j['display_name']?.toString().trim().isNotEmpty ?? false)
        ? j['display_name'].toString()
        : j['name']?.toString() ?? '',
    type: j['type']?.toString() ?? 'concept',
    triggerWords: [
      for (final t
          in j['trigger_words'] is List ? j['trigger_words'] as List : const [])
        if (t is String && t.isNotEmpty) t,
    ],
    recommendedWeight: (j['recommended_weight'] as num?)?.toDouble() ?? 0.8,
    previewUrl: j['preview_url']?.toString() ?? '',
    sourceUrl: j['source_url']?.toString() ?? '',
    sizeMb: (j['size_mb'] as num?)?.toDouble(),
    syncStatus: j['sync_status']?.toString() ?? 'synced',
    usageCount: (j['usage_count'] as num?)?.toInt() ?? 0,
    addedBy: j['added_by']?.toString() ?? 'web',
    favorited: j['favorited'] == true,
    favoriteCount: (j['favorite_count'] as num?)?.toInt() ?? 0,
    visibility: j['visibility']?.toString() ?? 'public',
    isOwner: j['is_owner'] == true,
    syncError: (j['sync_error']?.toString().trim().isNotEmpty ?? false)
        ? j['sync_error'].toString()
        : null,
    hasTe: j['has_te'] is bool ? j['has_te'] as bool : null,
  );
}

/// 图片元数据里一条 LoRA 引用的认领结果(`POST /api/lora/resolve`)。
class LoraResolveResult {
  const LoraResolveResult({
    required this.name,
    required this.hash,
    required this.status,
    this.matchedBy,
    this.weight,
    this.clipWeight,
    this.item,
    this.civitaiVersionId,
    this.civitaiName = '',
    this.civitaiBaseModel = '',
    this.civitaiPreviewUrl = '',
    this.civitaiTriggerWords = const [],
    this.civitaiType = 'concept',
    this.civitaiRecommendedWeight = 0.8,
  });

  /// 元数据里的原始名字与哈希(原样回传,便于对上是哪一行)。
  final String name;
  final String hash;

  /// local = 库里有 / civitai = 库里没有但 Civitai 上找到了 / missing = 都没有。
  final String status;

  /// hash = 按文件哈希命中(同一个文件);name = 按名字命中(可能不是同一版本)。
  final String? matchedBy;
  final double? weight;
  final double? clipWeight;

  /// status=local 时的本地库条目。
  final LoraCardInfo? item;

  /// status=civitai 时可一键装库的版本号。
  final int? civitaiVersionId;
  final String civitaiName;

  /// 非 Anima 底模的要警告 —— 装了也用不上(画崩或不生效)。
  final String civitaiBaseModel;
  final String civitaiPreviewUrl;

  /// 下面三个是「还没入库就先占位挂上」用的:下载完成前也得有名字、类型、
  /// 触发词可显示,不然占位条只能是个空壳。
  final List<String> civitaiTriggerWords;
  final String civitaiType;
  final double civitaiRecommendedWeight;

  bool get isLocal => status == 'local';
  bool get isCivitai => status == 'civitai';

  /// 展示名:优先真名,退回元数据里的原名。
  String get label =>
      item?.displayName ?? (civitaiName.isNotEmpty ? civitaiName : name);

  factory LoraResolveResult.fromJson(Map<String, dynamic> j) {
    final civitai = j['civitai'];
    final c = civitai is Map<String, dynamic> ? civitai : const {};
    final it = j['item'];
    return LoraResolveResult(
      name: j['name']?.toString() ?? '',
      hash: j['hash']?.toString() ?? '',
      status: j['status']?.toString() ?? 'missing',
      matchedBy: j['matched_by']?.toString(),
      weight: (j['weight'] as num?)?.toDouble(),
      clipWeight: (j['clip_weight'] as num?)?.toDouble(),
      item: it is Map<String, dynamic> ? LoraCardInfo.fromJson(it) : null,
      civitaiVersionId: (c['version_id'] as num?)?.toInt(),
      civitaiName: c['display_name']?.toString() ?? '',
      civitaiBaseModel: c['base_model']?.toString() ?? '',
      civitaiPreviewUrl: c['preview_url']?.toString() ?? '',
      civitaiTriggerWords: [
        for (final t
            in c['trigger_words'] is List
                ? c['trigger_words'] as List
                : const [])
          if (t is String && t.isNotEmpty) t,
      ],
      civitaiType: c['type']?.toString() ?? 'concept',
      civitaiRecommendedWeight:
          (c['recommended_weight'] as num?)?.toDouble() ?? 0.8,
    );
  }
}

/// Civitai 在线搜索结果一条(`GET /api/lora/search`,服务端代理)。
class CivitaiLoraInfo {
  const CivitaiLoraInfo({
    required this.modelId,
    required this.versionId,
    required this.name,
    this.creator = '',
    this.downloadCount = 0,
    this.previewUrl = '',
    this.triggerWords = const [],
    this.type = 'concept',
    this.recommendedWeight = 0.8,
    this.fileName = '',
    this.sizeMb,
    this.baseModel = '',
    this.tags = const [],
    this.installed = false,
    this.description = '',
  });

  final int modelId;
  final int versionId;
  final String name;
  final String creator;
  final int downloadCount;
  final String previewUrl;
  final List<String> triggerWords;
  final String type;
  final double recommendedWeight;
  final String fileName;
  final double? sizeMb;
  final String baseModel;
  final List<String> tags;

  /// 机房库里已有该版本(下载会走「仅加收藏」,不重复拉)。
  final bool installed;
  final String description;

  /// Civitai 模型页(带版本参数)。
  String get civitaiUrl =>
      'https://civitai.com/models/$modelId?modelVersionId=$versionId';

  factory CivitaiLoraInfo.fromJson(Map<String, dynamic> j) => CivitaiLoraInfo(
    modelId: (j['model_id'] as num?)?.toInt() ?? 0,
    versionId: (j['version_id'] as num?)?.toInt() ?? 0,
    name: j['name']?.toString() ?? '',
    creator: j['creator']?.toString() ?? '',
    downloadCount: (j['download_count'] as num?)?.toInt() ?? 0,
    previewUrl: j['preview_url']?.toString() ?? '',
    triggerWords: [
      for (final t
          in j['trigger_words'] is List ? j['trigger_words'] as List : const [])
        if (t is String && t.isNotEmpty) t,
    ],
    type: j['type']?.toString() ?? 'concept',
    recommendedWeight: (j['recommended_weight'] as num?)?.toDouble() ?? 0.8,
    fileName: j['file_name']?.toString() ?? '',
    sizeMb: (j['size_mb'] as num?)?.toDouble(),
    baseModel: j['base_model']?.toString() ?? '',
    tags: [
      for (final t in j['tags'] is List ? j['tags'] as List : const [])
        if (t is String && t.isNotEmpty) t,
    ],
    installed: j['installed'] == true,
    description: j['description']?.toString() ?? '',
  );
}

/// 一次自然语言补强的产出(`POST /api/agent/web/anima-nl`)。
/// [text] 是要追加到正向词末尾的一整段英文(服务端已压平换行、剥掉引号/列表号,
/// 并清掉会破坏提示词结构的 `<<` `>>` `~`);[noteZh] 只给用户看,不进提示词。
class AnimaNlResult {
  const AnimaNlResult({this.text = '', this.noteZh = ''});

  final String text;
  final String noteZh;

  Map<String, dynamic> toJson() => {'text': text, 'note_zh': noteZh};

  factory AnimaNlResult.fromJson(Map<String, dynamic> j) => AnimaNlResult(
    text: j['text']?.toString().trim() ?? '',
    noteZh: j['note_zh']?.toString().trim() ?? '',
  );
}

/// 一次提示词整理的产出(`POST /api/agent/web/krea-prompt`)。
///
/// ⚠ 与 [AnimaNlResult] 形状相同、语义相反,别混用:
///   anima  tag 是骨架、句子是补充 → [AnimaNlResult.text] **追加**到正向词末尾
///   krea   整条 prompt 就是一段自然语言 → 这里的 [text] 是**整条新的正向词**,
///          整段替换原文(追加只会得到两段互相打架的描述)
/// [noteZh] 只给用户看,不进提示词。
class KreaPromptResult {
  const KreaPromptResult({this.text = '', this.noteZh = ''});

  final String text;
  final String noteZh;

  Map<String, dynamic> toJson() => {'text': text, 'note_zh': noteZh};

  factory KreaPromptResult.fromJson(Map<String, dynamic> j) => KreaPromptResult(
    text: j['text']?.toString().trim() ?? '',
    noteZh: j['note_zh']?.toString().trim() ?? '',
  );
}

/// Plana 后端客户端(当前仅含 bot 授权四端点里 App 要用的三个;
/// verify 由 Bot 侧调用,App 不实现)。端点契约由后端项目定义,不在本仓库内。
///
/// 全站约定:auth 端点失败也返 200,要看 body 的 verified/valid 字段;
/// 其余端点非 2xx + `{"detail": ...}`。
class BackendClient {
  BackendClient(this.baseUrl);

  /// 形如 `http://host:8765`,末尾无斜杠。
  final String baseUrl;

  static const _timeout = Duration(seconds: 15);

  /// 带 body 的请求超时:**显式值与体积折算值取大者**。
  ///
  /// [_timeout] 那 15 秒是给几 KB 的小 body 定的,而重绘(整图 PNG + mask 的
  /// base64)、角色参考、vibe 上传这些能到几 MB —— 同一个 15 秒里要跑完 TLS
  /// 握手 + 把全部字节推上去 + 等服务端应答,手机上行慢一点就是稳定误杀:
  /// 报「连接后端超时」,可任务其实已经在服务端建好了(还照常扣点出图)。
  /// 按最差 100KB/s 上行兜底折算(3MB≈45s、10MB≈2 分钟),封顶 5 分钟。
  ///
  /// 取大者而不是让显式值覆盖:显式值说的是「服务端要慢慢干活」(/rental/start
  /// 6 分钟),体积算的是「字节要花多久推上去」—— 两件事该叠加。否则
  /// `/vibes/upload` 那种「几 MB body + 显式 30 秒」照样死在原地。
  static Duration _sendTimeout(int bytes, Duration? explicit) {
    final s = bytes <= 64 * 1024 ? 15 : 15 + bytes ~/ (100 * 1024);
    final byBody = Duration(seconds: s > 300 ? 300 : s);
    return explicit != null && explicit > byBody ? explicit : byBody;
  }

  Uri _u(String path) => Uri.parse('$baseUrl/api$path');

  Map<String, String> _headers([String? bearer]) => {
    'Content-Type': 'application/json',
    if (bearer != null) 'Authorization': 'Bearer $bearer',
  };

  Future<Map<String, dynamic>> _handle(
    Future<http.Response> Function() send, {
    Duration? timeout,
  }) async {
    if (baseUrl.isEmpty) throw BackendException('未配置后端地址');
    final http.Response resp;
    try {
      resp = await send().timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw BackendException('连接后端超时,请检查地址与网络');
    } catch (_) {
      throw BackendException('无法连接后端,请检查地址与网络');
    }

    return _decode(resp);
  }

  /// 响应体 → JSON 对象;非 2xx 抛 [BackendException](优先用 body 里的 detail)。
  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      var detail = '请求失败(${resp.statusCode})';
      try {
        final j = jsonDecode(utf8.decode(resp.bodyBytes));
        if (j is Map && j['detail'] is String) detail = j['detail'] as String;
      } catch (_) {}
      throw BackendException(detail, status: resp.statusCode);
    }

    try {
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    throw BackendException('后端返回格式异常');
  }

  Future<Map<String, dynamic>> _postJson(
    String path, [
    Map<String, dynamic>? body,
    String? bearer,
    Duration? timeout,
  ]) {
    // 先编码再发:拿到实际体积才能挑超时,也省掉 http 内部再编一遍。
    final payload = jsonEncode(body ?? const <String, dynamic>{});
    if (payload.length > 512 * 1024) {
      logi('[net] POST $path body=${payload.length >> 10}KB');
    }
    return _handle(
      () => http.post(_u(path), headers: _headers(bearer), body: payload),
      timeout: _sendTimeout(payload.length, timeout),
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    String? bearer,
    Duration? timeout,
  ]) => _handle(
    () => http.get(_u(path), headers: _headers(bearer)),
    timeout: timeout,
  );

  Future<Map<String, dynamic>> _putJson(
    String path, [
    Map<String, dynamic>? body,
    String? bearer,
    Duration? timeout,
  ]) {
    final payload = jsonEncode(body ?? const <String, dynamic>{});
    return _handle(
      () => http.put(_u(path), headers: _headers(bearer), body: payload),
      timeout: _sendTimeout(payload.length, timeout),
    );
  }

  /// 发起授权码(标记来源 app,授权成功时 Bot 提示会显示「NovelAI App」)。
  /// → (6 位大写 hex code, 有效期秒数)
  Future<({String code, int expiresIn})> authGenerate() async {
    final j = await _postJson('/bot/auth/generate', {'source': 'app'});
    final code = j['code'] as String?;
    if (code == null || code.isEmpty) throw BackendException('未获取到授权码');
    return (code: code, expiresIn: (j['expires_in'] as num?)?.toInt() ?? 300);
  }

  /// 轮询授权码是否已被 Bot 验证。→ (是否已验证, session_id?)
  Future<({bool verified, String? sessionId})> authCheck(String code) async {
    final j = await _postJson('/bot/auth/check', {'code': code});
    return (
      verified: j['verified'] == true,
      sessionId: j['session_id'] as String?,
    );
  }

  /// 轻量校验会话并取滑动过期时间。→ (是否有效, 归属 bot_user_id?, 过期毫秒?)
  Future<({bool valid, String? botUserId, int? expiresAtMs})> validate(
    String sessionId,
  ) async {
    final j = await _postJson('/bot/auth/validate', {'session_id': sessionId});
    return (
      valid: j['valid'] == true,
      botUserId: j['bot_user_id'] as String?,
      expiresAtMs: (j['expires_at_ms'] as num?)?.toInt(),
    );
  }

  /// 提交 bot 模式生成任务(登录:Bearer 头 + body 里 session_id)。
  /// → (是否受理, task_id?, 文案)。⚠️ 入队失败也返 200 success:false。
  /// 重绘/参考图会往 params 里塞几 MB base64,超时交 [_sendTimeout] 按体积放宽。
  Future<({bool success, String? taskId, String message})> botGenerate({
    required String sessionId,
    required Map<String, dynamic> params,
    String imageBackend = 'novelai',
  }) async {
    final j = await _postJson('/bot/generate', {
      'session_id': sessionId,
      'params': params,
      'image_backend': imageBackend,
    }, sessionId);
    return (
      success: j['success'] == true,
      taskId: j['task_id'] as String?,
      message: (j['message'] as String?) ?? '',
    );
  }

  /// 查任务状态(私有:Bearer 头,只能查自己的)。
  Future<BotTask> getTask({
    required String sessionId,
    required String taskId,
  }) async {
    final j = await _getJson('/bot/task/$taskId', sessionId);
    return BotTask.fromJson(j);
  }

  /// 取一张出图结果。[url] 就是 `result.url`(形如 `/api/i/<hash>.png`,
  /// 已含 `/api` 前缀,所以这里不走 [_u])。
  ///
  /// 不需要鉴权:哈希本身就是凭证(128 位,猜不出来)。服务端只在内存里留
  /// 10 分钟,过期即 404 —— 那是预期行为,拿到就该立刻落库。
  Future<Uint8List> fetchResultImage(String url) async {
    if (baseUrl.isEmpty) throw BackendException('未配置后端地址');
    final http.Response resp;
    try {
      resp = await http
          .get(Uri.parse('$baseUrl$url'))
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw BackendException('取结果图超时,请检查网络');
    } catch (_) {
      throw BackendException('取结果图失败,请检查网络');
    }
    if (resp.statusCode == 404) {
      throw BackendException('结果已过期(服务端只保留 10 分钟)');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw BackendException(
        '取结果图失败(${resp.statusCode})',
        status: resp.statusCode,
      );
    }
    return resp.bodyBytes;
  }

  /// 取消**排队中**的任务(`DELETE /api/task/{id}`,与 web 同一个端点)。
  ///
  /// 服务端只受理 `queued`:已经在跑的返 400、任务不存在返 404 —— 两种都当
  /// 「没取消成」返 false 而不抛出。取消是尽力而为的补救,失败无非是照常出图,
  /// 不该再朝用户弹一个错误。
  ///
  /// 值得调的理由:它不只是打个 cancelled 标记 —— NAI 侧会把任务踢出队列
  /// (省下这次的 Anlas),anima/krea 侧还会显式踢出 provider 的本地 FIFO 并
  /// 唤醒其协程,否则那条协程照样排队→出图→烧机时。
  Future<bool> cancelTask(String taskId, {String? sessionId}) async {
    try {
      final j = await _handle(
        // 2026-09-04 起这个端点要鉴权（此前完全敞着，知道 task_id 就能撤别人的任务）。
        // 不带会话会 401 —— 而 401 在这里被当成「没取消成」吞掉，表现是「点了取消
        // 但服务端照常出图」，很难查。所以调用方务必把 sessionId 传进来。
        () => http.delete(_u('/task/$taskId'), headers: _headers(sessionId)),
      );
      return j['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 后端编码 Vibe 参考(bot 模式;⚠️ 扣 2 Anlas,务必缓存)。
  /// → `encoding` 串,填进生成 `params.vibeReferences[].encodedVibe`。
  Future<String> encodeVibe({
    required String sessionId,
    required String imageBase64,
    required double informationExtracted,
    required String model,
  }) async {
    final j = await _postJson('/vibe/encode', {
      'image': imageBase64,
      'information_extracted': informationExtracted,
      'model': model,
    }, sessionId);
    final enc = j['encoding'] as String?;
    if (enc == null || enc.isEmpty) throw BackendException('Vibe 编码失败');
    return enc;
  }

  /// 服务账户 Anlas 余额(公开端点,共享池;bot 模式头部显示,对齐 web)。
  /// 共享服务账户的点数,外加 NAI 5 额度 —— 服务端把主池里各个 Opus 号的额度
  /// 电池并成了一块(`usage`,percent 是平均水位 + `accounts` 号数),字段名与
  /// NAI 直连响应同款,所以直接喂给 [parseNaiUsage]。
  ///
  /// 老服务端不带 `usage`,解析出 null,界面自然退回只显示点数,不报错。
  Future<({int anlas, NaiUsage? usage})> getAnlas() async {
    final j = await _getJson('/anlas');
    return (
      anlas: (j['anlas'] as num?)?.toInt() ?? 0,
      usage: parseNaiUsage(j['usage']),
    );
  }

  /// 共享号池的 NAI 官方额度(`GET /api/usage`,公开端点)。
  ///
  /// 这是**全平台**的水位(主池各 Opus 号合并),看的是「大家还能免费出多少图」,
  /// 属于全局视角 —— 个人「我还能出几张」看 [myNaiQuota]。一个 Opus 号都没有
  /// 时服务端回 null,这里如实返回 null(画个空电池比不画更误导)。
  ///
  /// 同一份数据也随 [getAnlas] 顺路回来;单开这条是为了不必为了看池子而去拉点数。
  Future<NaiUsage?> poolUsage() async =>
      parseNaiUsage((await _getJson('/usage'))['usage']);

  /// 我的 NAI 5 出图额度(`GET /api/user/quota`)。按会话鉴权,**只能查自己**
  /// (user_id 取自会话,传不进去别人的)。
  ///
  /// 与上面那块 `usage` 的关系见 [NaiQuota]:两道闸都过了才真正出图。
  Future<NaiQuota> myNaiQuota(String sessionId) async =>
      NaiQuota.fromJson(await _getJson('/user/quota', sessionId));

  // ── 出图租卡(anima / krea2 付费档)──────────────────────────────
  // 服务端 `agent_router/img_rental.py`。四个端点都要 Bot 会话。
  // 免费档仍走 Modal 共享通道,这几个只管租来的那台机器。

  /// 当前用户的租用状态。没在跑时返回 `active=false` + 各项可选值
  /// (`idle_choices` / `idle_default` / `max_uptime_s` / `boot_hint_s` /
  /// `rate_per_hour`)—— 这些**以服务端为准**,app 侧只留一份兜底默认。
  Future<Map<String, dynamic>> rentalStatus(String sessionId) =>
      _getJson('/rental/status', sessionId);

  /// 下单开一台。[tier] 是服务端 `IMG_TIERS` 的键,空 = 用服务端默认档
  /// (不认识的键服务端也静默回落默认档,不报错)。
  ///
  /// ⚠ **这个调用不再阻塞到就绪。** 2026-08-19 起服务端把建机丢进后台
  /// (`_fire_and_forget`)、立刻返回,理由是开机要 40~120 秒,而 nginx 默认
  /// `proxy_read_timeout` 才 60 秒 —— 阻塞式必然被中间某一跳掐断,前端报
  /// 「开机失败」,机器却照开。所以**返回体里的 state 恒是 none**(那几个
  /// 后台任务还没跑),只能当作「下单收到了」,真状态去 `/rental/status` 问。
  ///
  /// 超时留 90 秒而不是默认那 15 秒:一来下单本身要跟平台 OpenAPI 打个来回,
  /// 二来服务端万一还是老的阻塞版,这段能盖住一部分;真超时了调用方也会回去
  /// 问状态,不会误报成「没开成」。
  /// [count] 一次开几台(服务端并发建,所以耗时和开一台差不多)。已经有机器
  /// 时是**加开**到 N+count,超过 `IMG_MAX_RENTALS` 会被服务端顶回来
  /// (`ok:false` + 一句「最多同时租 N 台」),那时它一台都不建。
  Future<Map<String, dynamic>> rentalStart(
    String sessionId, {
    int? idleTimeout,
    String tier = '',
    int count = 1,
  }) => _postJson(
    '/rental/start',
    {
      'idle_timeout': ?idleTimeout,
      if (tier.isNotEmpty) 'tier': tier,
      if (count > 1) 'count': count,
    },
    sessionId,
    const Duration(seconds: 90),
  );

  /// 停机结账(先 purge 实例上的内容再销毁)。返回 seconds / minutes / price。
  ///
  /// ⚠ [instanceId] 给了只停那一台;**不给 = 这个账号名下全部停止**
  /// (服务端 2026-08-19 起支持一人多机)。漏传那个 id 就是替用户做了一个
  /// 他没授权的决定,所以界面上这两件事必须是两个说法。
  Future<Map<String, dynamic>> rentalStop(
    String sessionId, {
    String instanceId = '',
  }) => _postJson(
    '/rental/stop',
    {'instance_id': instanceId},
    sessionId,
    const Duration(minutes: 3),
  );

  /// 改空闲自动关机时长(秒,0 = 不自动关)。运行中即时生效。
  Future<Map<String, dynamic>> rentalSetIdle(
    String sessionId,
    int idleTimeout,
  ) => _postJson('/rental/idle', {'idle_timeout': idleTimeout}, sessionId);

  /// 算力账单(`GET /api/rental/bills`)。租卡 + 视频合成一条时间线。
  Future<GpuBills> rentalBills(String sessionId, {int limit = 50}) async =>
      GpuBills.fromJson(
        await _getJson('/rental/bills?limit=$limit', sessionId),
      );

  // ── 公共 Vibe 库 ──────────────────────────────────────────────

  /// 缩略图端点绝对 URL(公开,`<img>`/RemoteImage 直接引用)。
  String publicVibeThumbUrl(String filename) =>
      '$baseUrl/api/vibes/thumbnail/${Uri.encodeComponent(filename)}';

  /// 列出公共 Vibe(登录:Bearer 头)。仅元数据 + 缩略图 URL,不含图/编码。
  Future<List<PublicVibeMeta>> listPublicVibes(String sessionId) async {
    final j = await _getJson('/vibes/list', sessionId);
    final vibes = j['vibes'];
    if (vibes is! List) return const [];
    final out = <PublicVibeMeta>[];
    for (final v in vibes) {
      if (v is! Map) continue;
      final filename = v['filename'];
      if (filename is! String || filename.isEmpty) continue;
      out.add(
        PublicVibeMeta(
          id: v['id'] is String ? v['id'] as String : filename,
          name: v['name'] is String && (v['name'] as String).isNotEmpty
              ? v['name'] as String
              : filename,
          filename: filename,
          thumbnailUrl: publicVibeThumbUrl(filename),
          supportedModels: v['supportedModels'] is List
              ? [
                  for (final m in v['supportedModels'] as List)
                    if (m is String) m,
                ]
              : const [],
          defaultStrength: (v['defaultStrength'] as num?)?.toDouble(),
          defaultInfoExtracted: (v['defaultInfoExtracted'] as num?)?.toDouble(),
          createdAt: (v['createdAt'] as num?)?.toInt() ?? 0,
          hasImage: v['hasImage'] != false,
          uploaderId: v['uploaderId'] as String?,
        ),
      );
    }
    return out;
  }

  /// 拉取公共 Vibe 完整 .naiv4vibe 文件文本(登录:Bearer 头;含图/编码,较重)。
  /// 直接返回原始 JSON 文本,供 [VibeLibrary.importVibeText] 落库。
  Future<String> getPublicVibeFileText(
    String sessionId,
    String filename,
  ) async {
    if (baseUrl.isEmpty) throw BackendException('未配置后端地址');
    final uri = _u('/vibes/file/${Uri.encodeComponent(filename)}');
    final http.Response resp;
    try {
      resp = await http
          .get(uri, headers: _headers(sessionId))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw BackendException('拉取公共 Vibe 超时');
    } catch (_) {
      throw BackendException('无法连接后端');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw BackendException(
        '拉取公共 Vibe 失败(${resp.statusCode})',
        status: resp.statusCode,
      );
    }
    return utf8.decode(resp.bodyBytes);
  }

  /// 上传 Vibe 到公共库(bot 模式;鉴权用 body 里的 session_id,后端自动记录上传者)。
  /// [vibeData] = 完整 .naiv4vibe JSON(含图/编码);[name] 为公共展示名。
  /// → (是否成功, 服务端文件名?, 文案)。非 2xx 抛 [BackendException](带 detail)。
  Future<({bool success, String? filename, String message})> uploadPublicVibe({
    required String sessionId,
    required Map<String, dynamic> vibeData,
    required String name,
  }) async {
    final j = await _postJson(
      '/vibes/upload',
      {'vibe_data': vibeData, 'name': name, 'session_id': sessionId},
      sessionId,
      const Duration(seconds: 30),
    );
    return (
      success: j['success'] == true,
      filename: j['filename'] as String?,
      message: (j['message'] as String?) ?? '',
    );
  }

  // ── 公共画师串 / OC / Tag 云备份(灵感页) ─────────────────

  String? _abs(Object? path) =>
      path is String && path.isNotEmpty ? '$baseUrl$path' : null;

  /// 列出公共画师串(登录:Bearer 头)。
  Future<List<PublicArtistMeta>> listPublicArtists(String sessionId) async {
    final j = await _getJson('/artists/list', sessionId);
    final artists = j['artists'];
    if (artists is! List) return const [];
    return [
      for (final a in artists)
        if (a is Map && a['name'] is String && a['artist_string'] is String)
          PublicArtistMeta(
            id: a['id'] is String ? a['id'] as String : a['name'] as String,
            name: a['name'] as String,
            artistString: a['artist_string'] as String,
            negative: a['negative'] is String ? a['negative'] as String : '',
            previewUrl: _abs(a['preview_url']),
            usageCount: (a['usage_count'] as num?)?.toInt() ?? 0,
            createdTime: (a['created_time'] as num?)?.toInt() ?? 0,
            addedBy: a['added_by'] as String?,
            ownerId: a['owner_id'] as String?,
            models: [
              for (final m in (a['models'] is List ? a['models'] as List : []))
                if (m is String && m.trim().isNotEmpty) m.trim(),
            ],
          ),
    ];
  }

  /// 列出公共 OC(登录:Bearer 头)。
  Future<List<PublicOcMeta>> listPublicOcs(String sessionId) async {
    final j = await _getJson('/oc/list', sessionId);
    final ocs = j['ocs'];
    if (ocs is! List) return const [];
    return [
      for (final o in ocs)
        if (o is Map && o['en_name'] is String && o['tag_group'] is String)
          PublicOcMeta(
            enName: o['en_name'] as String,
            zhName: o['zh_name'] as String?,
            aliases: o['zh_aliases'] is List
                ? [
                    for (final s in o['zh_aliases'] as List)
                      if (s is String) s,
                  ]
                : const [],
            tagGroup: o['tag_group'] as String,
            negativePrompt: o['negative_prompt'] is String
                ? o['negative_prompt'] as String
                : '',
            previewUrl: _abs(o['preview_url']),
            createdBy: o['created_by'] as String?,
            ownerId: o['owner_id'] as String?,
            createdAt: (o['created_at'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  /// 公共库作者目录(登录:Bearer 头)。只含在公共库里有条目的人 ——
  /// 灵感页拿它把 owner_id 那串数字显示成昵称,并作为作者筛选的候选名单。
  ///
  /// 老后端没有这个端点,调用方按空表处理(照旧显示 QQ 号)。
  Future<List<PublicAuthorMeta>> listPublicAuthors(String sessionId) async {
    final j = await _getJson('/public/authors', sessionId);
    final authors = j['authors'];
    if (authors is! List) return const [];
    return [
      for (final a in authors)
        if (a is Map &&
            a['user_id'] is String &&
            (a['user_id'] as String).isNotEmpty)
          PublicAuthorMeta(
            id: a['user_id'] as String,
            nickname: a['nickname'] is String ? a['nickname'] as String : null,
          ),
    ];
  }

  /// 发布 OC 到公共库(登录:Bearer 头)。en_name 缺省由服务端按拼音生成。
  /// → 服务端主键 en_name。失败抛 [BackendException](detail 直出)。
  Future<String> createPublicOc({
    required String sessionId,
    String? enName,
    required String zhName,
    List<String> aliases = const [],
    required String tagGroup,
    String negativePrompt = '',
    String? previewBase64,
    String? createdBy,
  }) async {
    final j = await _postJson(
      '/oc/create',
      {
        if (enName != null && enName.isNotEmpty) 'en_name': enName,
        'zh_name': zhName,
        'zh_aliases': aliases,
        'tag_group': tagGroup,
        'negative_prompt': negativePrompt,
        'preview_base64': ?previewBase64,
        'created_by': ?createdBy,
      },
      sessionId,
      const Duration(seconds: 30),
    );
    final oc = j['oc'];
    final en = oc is Map ? oc['en_name'] : null;
    if (en is! String || en.isEmpty) throw BackendException('发布失败:响应异常');
    return en;
  }

  /// 更新公共 OC(仅归属者;[createdBy] 单传即转让归属)。
  Future<void> updatePublicOc({
    required String sessionId,
    required String enName,
    String? zhName,
    List<String>? aliases,
    String? tagGroup,
    String? negativePrompt,
    String? previewBase64,
    String? createdBy,
  }) async {
    await _putJson(
      '/oc/${Uri.encodeComponent(enName)}',
      {
        'zh_name': ?zhName,
        'zh_aliases': ?aliases,
        'tag_group': ?tagGroup,
        'negative_prompt': ?negativePrompt,
        'preview_base64': ?previewBase64,
        'created_by': ?createdBy,
      },
      sessionId,
      const Duration(seconds: 30),
    );
  }

  Future<void> deletePublicOc(String sessionId, String enName) async {
    await _handle(
      () => http.delete(
        _u('/oc/${Uri.encodeComponent(enName)}'),
        headers: _headers(sessionId),
      ),
    );
  }

  /// 发布画师串(登录:Bearer 头)。name 缺省服务端自动编号。
  /// → (id, name)。重名/重复内容 400,detail 直出。
  Future<({String id, String name})> createPublicArtist({
    required String sessionId,
    String? name,
    required String artistString,
    String negative = '',
    String? previewBase64,
    String? addedBy,
    List<String>? models,
  }) async {
    final j = await _postJson(
      '/artists/create',
      {
        if (name != null && name.isNotEmpty) 'name': name,
        'artist_string': artistString,
        'negative': negative,
        'preview_base64': ?previewBase64,
        'added_by': ?addedBy,
        // 适用模型;不传 = 通用。服务端会再清洗一遍(去空/去重/截断)
        'models': ?models,
      },
      sessionId,
      const Duration(seconds: 30),
    );
    final a = j['artist'];
    if (a is! Map || a['name'] is! String) {
      throw BackendException('发布失败:响应异常');
    }
    return (
      id: a['id'] is String ? a['id'] as String : a['name'] as String,
      name: a['name'] as String,
    );
  }

  /// 更新公共画师串(仅归属者;[addedBy] 单传即转让归属)。
  ///
  /// [models] 的 null 与 `[]` **不同义**:null = 本次不改,`[]` = 用户把标注全
  /// 取消了、改回通用。服务端按同一口径判,别在这里合并成「空就不发」。
  Future<void> updatePublicArtist({
    required String sessionId,
    required String id,
    String? artistString,
    String? negative,
    String? previewBase64,
    String? addedBy,
    List<String>? models,
  }) async {
    await _putJson(
      '/artists/${Uri.encodeComponent(id)}',
      {
        'artist_string': ?artistString,
        'negative': ?negative,
        'preview_base64': ?previewBase64,
        'added_by': ?addedBy,
        'models': ?models,
      },
      sessionId,
      const Duration(seconds: 30),
    );
  }

  Future<void> deletePublicArtist(String sessionId, String id) async {
    await _handle(
      () => http.delete(
        _u('/artists/${Uri.encodeComponent(id)}'),
        headers: _headers(sessionId),
      ),
    );
  }

  /// 公共画师串使用计数上报(确认插入时调,fire-and-forget,失败不打扰)。
  Future<void> reportArtistUse(String sessionId, String artistId) async {
    try {
      await _postJson(
        '/artists/${Uri.encodeComponent(artistId)}/use',
        null,
        sessionId,
      );
    } catch (_) {}
  }

  /// 拉取个人 Tag 云备份(登录:Bearer 头)。web 端备份可能内嵌 base64
  /// 预览,体积达数十 MB,超时放宽到 60s。
  /// → (四类条目原始 JSON, 更新时间秒, 各类计数)。从未备份过时四类为空数组。
  Future<
    ({Map<String, dynamic> categories, int updatedAt, Map<String, int> counts})
  >
  getTagBackup(String sessionId) async {
    final j = await _getJson(
      '/user-tag-backup',
      sessionId,
      const Duration(seconds: 60),
    );
    final rawCounts = j['counts'];
    return (
      categories: j['categories'] is Map<String, dynamic>
          ? j['categories'] as Map<String, dynamic>
          : const <String, dynamic>{},
      updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      counts: {
        if (rawCounts is Map)
          for (final e in rawCounts.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      },
    );
  }

  /// 备份/恢复操作日志(与 web 共用一份,按 bot_user_id 存;
  /// ⚠️ 鉴权走 body 里的 session_id)。失败不打扰主流程。
  Future<void> recordBackupLog({
    required String sessionId,
    required String device,
    required String action, // backup | restore
    required int count,
    required String detail,
  }) async {
    try {
      await _postJson('/user-vibes/backup-log', {
        'session_id': sessionId,
        'device': device,
        'action': action,
        'vibe_count': count,
        'detail': detail,
      }, sessionId);
    } catch (_) {}
  }

  /// 上传个人 Tag 云备份(整体覆盖;⚠️ 该端点鉴权走 body 里的 session_id)。
  Future<void> uploadTagBackup({
    required String sessionId,
    required Map<String, List<Map<String, dynamic>>> categories,
  }) async {
    await _postJson(
      '/user-tag-backup',
      {'session_id': sessionId, 'categories': categories},
      sessionId,
      const Duration(seconds: 30),
    );
  }

  // ── 个人云端 Vibe 库(与 web 桌面端共用一份,按 bot_user_id 存)────────
  // Tag 备份是「一个 JSON blob 整体覆盖」,Vibe 不同:云端**逐文件**存放,
  // 所以走列表 + 单文件读写,靠 hash 做增量(vibe 带 base64 原图,重传很贵)。

  /// 云端 vibe 统计(`GET /user-vibes/state`),用于弹层顶部「云端 N 条 · 时间」。
  Future<({int count, int updatedAt})> getUserVibesState(
    String sessionId,
  ) async {
    final j = await _getJson('/user-vibes/state', sessionId);
    return (
      count: (j['count'] as num?)?.toInt() ?? 0,
      updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// 云端 vibe 列表(仅元数据 + 双 hash,不含图/编码本体)。
  Future<List<CloudVibeMeta>> listUserVibes(String sessionId) async {
    final j = await _getJson(
      '/user-vibes/list',
      sessionId,
      const Duration(seconds: 30),
    );
    final vibes = j['vibes'];
    if (vibes is! List) return const [];
    return [
      for (final v in vibes)
        if (v is Map<String, dynamic>)
          if (CloudVibeMeta.fromJson(v) case final CloudVibeMeta m) m,
    ];
  }

  /// 拉取单条云端 vibe 完整文件(含 base64 原图与编码,较重)。
  Future<Map<String, dynamic>> getUserVibeFile(
    String sessionId,
    String filename,
  ) async {
    return _getJson(
      '/user-vibes/file/${Uri.encodeComponent(filename)}',
      sessionId,
      const Duration(seconds: 60),
    );
  }

  /// 整包推送一条 vibe(⚠️ 鉴权走 body 里的 session_id)。
  /// [filename] 非空 = 定向覆盖云端该文件;为空时后端按 id 去重,
  /// 找得到同 id 就覆盖那个文件,避免改过名/丢了 cloudFilename 时产生重复。
  Future<
    ({
      bool success,
      String? filename,
      String? imageHash,
      String? metaHash,
      String message,
    })
  >
  uploadUserVibe({
    required String sessionId,
    required Map<String, dynamic> vibeData,
    List<String>? tags,
    String? filename,
  }) async {
    try {
      final j = await _postJson(
        '/user-vibes/upload',
        {
          'session_id': sessionId,
          'vibe_data': vibeData,
          'tags': ?tags,
          'filename': ?filename,
        },
        sessionId,
        const Duration(seconds: 90),
      );
      return (
        success: j['success'] == true,
        filename: j['filename'] as String?,
        imageHash: j['image_hash'] as String?,
        metaHash: j['meta_hash'] as String?,
        message: '',
      );
    } on BackendException catch (e) {
      return (
        success: false,
        filename: null,
        imageHash: null,
        metaHash: null,
        message: e.message,
      );
    }
  }

  /// 只改云端元数据(名称/标签/默认参数),不重传图片。
  Future<({bool success, String? imageHash, String? metaHash})>
  updateUserVibeMeta({
    required String sessionId,
    required String filename,
    String? name,
    List<String>? tags,
    double? defaultStrength,
    double? defaultInfoExtracted,
  }) async {
    try {
      final j =
          await _putJson('/user-vibes/file/${Uri.encodeComponent(filename)}', {
            'session_id': sessionId,
            'name': ?name,
            'tags': ?tags,
            'default_strength': ?defaultStrength,
            'default_info_extracted': ?defaultInfoExtracted,
          }, sessionId);
      return (
        success: j['success'] != false,
        imageHash: j['image_hash'] as String?,
        metaHash: j['meta_hash'] as String?,
      );
    } on BackendException {
      return (success: false, imageHash: null, metaHash: null);
    }
  }

  /// 云端 vibe 标签池。
  Future<List<String>> getUserVibeTagPool(String sessionId) async {
    final j = await _getJson('/user-vibes/tag-pool', sessionId);
    final tags = j['tags'];
    if (tags is! List) return const [];
    return [
      for (final t in tags)
        if (t is String && t.isNotEmpty) t,
    ];
  }

  /// 整体覆盖云端标签池(⚠️ 鉴权走 body 里的 session_id)。
  Future<void> putUserVibeTagPool({
    required String sessionId,
    required List<String> tags,
  }) async {
    await _putJson('/user-vibes/tag-pool', {
      'session_id': sessionId,
      'tags': tags,
    }, sessionId);
  }

  /// 备份/恢复操作记录(最近 20 条,与 web 共用)。失败给空表,不打扰主流程。
  Future<List<BackupLogEntry>> getBackupLog(String sessionId) async {
    try {
      final j = await _getJson('/user-vibes/backup-log', sessionId);
      final log = j['log'];
      if (log is! List) return const [];
      return [
        for (final e in log)
          if (e is Map<String, dynamic>) BackupLogEntry.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// NAI 官方超分(bot 模式;登录:Bearer 头)。后端按 [mode] 分流到两个并存的端点:
  ///  - `legacy`(默认):api 子域传统超分,4×,仅 832×1216/1216×832/1024²,固定 7 点
  ///  - `nai5`:image 子域 V5 扩散超分,固定 2×、输入尺寸无白名单,按源图 1–4 点
  ///
  /// 后端要远程转发 NAI,给足超时(V5 扩散比传统超分慢得多)。
  /// ⚠️ 失败也返 200,看 success/message。→ (是否成功, 结果图 base64?, 文案)
  Future<({bool success, String? imageBase64, String message})> upscale({
    required String sessionId,
    required String imageBase64,
    required int width,
    required int height,
    int scale = 4,
    String mode = 'legacy',
    String? model,
    double? declaredBlurSigma,
  }) async {
    final j = await _postJson(
      '/upscale',
      {
        'image': imageBase64,
        'width': width,
        'height': height,
        'scale': scale,
        'mode': mode,
        'model': ?model,
        'declared_blur_sigma': ?declaredBlurSigma,
      },
      sessionId,
      Duration(seconds: mode == 'nai5' ? 300 : 120),
    );
    return (
      success: j['success'] == true,
      imageBase64: j['image'] as String?,
      message: (j['message'] as String?) ?? '',
    );
  }

  /// WD Tagger 图片标签反推(bot 模式;登录:Bearer 头)。后端转发 HuggingFace
  /// Space,较慢,给足 2 分钟。⚠️ 失败也返 200,看 success/error。
  /// → (是否成功, 标签串, 识别角色, 文案)
  Future<({bool success, String tags, String character, String message})>
  wdTagger({required String sessionId, required String imageBase64}) async {
    final j = await _postJson(
      '/wd-tagger',
      {'image': imageBase64},
      sessionId,
      const Duration(seconds: 120),
    );
    return (
      success: j['success'] == true,
      tags: (j['tags'] as String?) ?? '',
      character: (j['character'] as String?) ?? '',
      message: (j['error'] as String?) ?? '',
    );
  }

  // ── 统计 / 账单(个人中心,对齐 web)────────────────
  // 除 online/count 外全部要求 Bearer 会话。会话**只走 Authorization 头,不进
  // query** —— URL 会原样落进服务端与各级代理的访问日志(S1A-01)。后端
  // require_session 目前还留着 `?session_id=` 回退,但那只为兼容老 web,新客户端
  // 一律不用。time_range ∈ today/week/month(累计尝试 all,后端不支持时由调用方
  // 按失败兜底)。

  /// 个人统计(bot 账号,跨端汇总)。
  Future<UsageStats> userStats(String sessionId, String range) async {
    final j = await _getJson('/user/stats?time_range=$range', sessionId);
    return UsageStats.fromJson(j);
  }

  /// 个人逐日(今日档为逐小时)统计。
  Future<List<DailyStat>> userStatsDaily(String sessionId, String range) async {
    final j = await _getJson('/user/stats/daily?time_range=$range', sessionId);
    final data = j['data'];
    if (data is! List) return const [];
    return [
      for (final d in data)
        if (d is Map)
          DailyStat(
            date: d['date']?.toString() ?? '',
            imageCalls: (d['image_calls'] as num?)?.toInt() ?? 0,
            pointsSpent: (d['points_spent'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  /// 平台当期统计。
  Future<UsageStats> platformStats(String sessionId, String range) async {
    final j = await _getJson('/platform/stats?time_range=$range', sessionId);
    return UsageStats.fromJson(j);
  }

  /// 平台历史全局统计。
  Future<UsageStats> platformStatsAll(String sessionId) async {
    return UsageStats.fromJson(
      await _getJson('/platform/stats/all', sessionId),
    );
  }

  /// 平台 24 小时热力图(负载/活跃人数/平均耗时)。
  Future<HourlyHeat> platformHourly(
    String sessionId,
    HourlyKind kind,
    int days,
  ) async {
    final j = await _getJson(
      '/platform/stats/${kind.path}?days=$days',
      sessionId,
    );
    final raw = j['heatmap'];
    if (raw is! List) return const HourlyHeat();
    return HourlyHeat(
      totalDays: (j['total_days'] as num?)?.toInt() ?? 1,
      cells: [
        for (final c in raw)
          if (c is Map)
            (
              hour: (c['hour'] as num?)?.toInt() ?? 0,
              avg: (c[kind.avgKey] as num?)?.toDouble() ?? 0,
              total: (c[kind.totalKey] as num?)?.toDouble() ?? 0,
            ),
      ],
    );
  }

  /// 当前在线人数(公开端点)。
  Future<int> onlineCount() async {
    final j = await _getJson('/online/count');
    return (j['count'] as num?)?.toInt() ?? 0;
  }

  /// 本期费用预估(当前 27 日周期,含阶梯边界与各阶分布)。
  Future<BillingReport> billingEstimate(String sessionId) async {
    return BillingReport.fromJson(
      await _getJson('/billing/estimate', sessionId),
    );
  }

  /// 指定窗口的消耗明细。窗口传当天 00:00 ~ 次日 00:00 即得「当日逐笔」。
  /// 归属由后端从会话强制取(`user_id = session.bot_user_id`,只能查自己),
  /// 早先那个 `user_id` query 线上已被忽略 —— 一并去掉,别白送 bot 账号进日志。
  Future<UsageDetails> usageDetails({
    required String sessionId,
    required DateTime from,
    required DateTime to,
  }) async {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}T00:00:00';
    final j = await _getJson(
      '/billing/user/details'
      '?period_start=${Uri.encodeComponent(iso(from))}'
      '&period_end=${Uri.encodeComponent(iso(to))}',
      sessionId,
      const Duration(seconds: 30),
    );
    final recs = j['recent_records'];
    final bd = j['type_breakdown'];
    return UsageDetails(
      records: [
        for (final r in recs is List ? recs : const [])
          if (r is Map<String, dynamic>) PointRecord.fromJson(r),
      ],
      breakdown: [
        for (final b in bd is List ? bd : const [])
          if (b is Map)
            (
              reason: b['reason']?.toString() ?? '未知',
              points: (b['total_points'] as num?)?.toInt() ?? 0,
              count: (b['count'] as num?)?.toInt() ?? 0,
              v5Points: (b['v5_points'] as num?)?.toInt() ?? 0,
              v5Count: (b['v5_count'] as num?)?.toInt() ?? 0,
            ),
      ],
      v5Calls: (j['total_v5_calls'] as num?)?.toInt() ?? 0,
      v5Points: (j['total_v5_points'] as num?)?.toInt() ?? 0,
      localCalls: (j['total_local_calls'] as num?)?.toInt() ?? 0,
      imageCalls: (j['total_image_calls'] as num?)?.toInt() ?? 0,
      points: (j['total_points'] as num?)?.toInt() ?? 0,
    );
  }

  /// 逐笔生成明细(含分辨率/步数/模型)。窗口传当天 00:00 ~ 次日 00:00。
  /// 需要服务端 `/api/user/stats/calls`(未部署该接口时抛 404,调用方降级)。
  Future<List<CallRecord>> callRecords({
    required String sessionId,
    required DateTime from,
    required DateTime to,
  }) async {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}T00:00:00';
    final j = await _getJson(
      '/user/stats/calls'
      '?period_start=${Uri.encodeComponent(iso(from))}'
      '&period_end=${Uri.encodeComponent(iso(to))}',
      sessionId,
      const Duration(seconds: 30),
    );
    final recs = j['records'];
    return [
      for (final r in recs is List ? recs : const [])
        if (r is Map<String, dynamic>) CallRecord.fromJson(r),
    ];
  }

  /// 点数逐笔(按 today/week/month 取,服务端上限 50 条)。
  /// [usageDetails] 拿不到归属 id 时的兜底。
  Future<List<PointRecord>> pointRecords(String sessionId, String range) async {
    final j = await _getJson('/user/stats/points?time_range=$range', sessionId);
    final recs = j['records'];
    return [
      for (final r in recs is List ? recs : const [])
        if (r is Map<String, dynamic>) PointRecord.fromJson(r),
    ];
  }

  /// 上期结算(含阶梯边界/分布与支付状态;付款流程留在 web)。
  Future<BillingReport> billingSettlement(String sessionId) async {
    return BillingReport.fromJson(
      await _getJson('/billing/settlement', sessionId),
    );
  }

  // ── LoRA 管理(anima / krea 出图渠道,契约对齐 web loraService.ts) ──
  //
  // 全线带 [base]:anima(2B 自研 DiT)与 krea2(12B DiT)的权重互不通用,
  // 挂错了 ComfyUI 不报错、只是静默无效 —— 所以隔离做在库层,列表默认就按底模
  // 裁好,不给前端「选错」的机会。base 也决定文件落 Volume 的哪个子目录。

  /// 机房已装 LoRA 全集(登录:Bearer 头 → 每张卡带 favorited)。
  /// 「我的库」= 其中 favorited 的;「公共库」= 全集。
  Future<List<LoraCardInfo>> listLoras(
    String sessionId, {
    String base = 'anima',
  }) async {
    final j = await _getJson(
      '/lora/list?base=${Uri.encodeComponent(base)}',
      sessionId,
    );
    if (j['ok'] == false) {
      throw BackendException(j['message']?.toString() ?? 'LoRA 列表加载失败');
    }
    return [
      for (final e in j['items'] is List ? j['items'] as List : const [])
        if (e is Map<String, dynamic>) LoraCardInfo.fromJson(e),
    ];
  }

  /// 加入我的库(纯改收藏关系,不涉及下载)。
  Future<({bool ok, int? favoriteCount, String message})> favoriteLora({
    required String sessionId,
    required String lrId,
  }) async {
    final j = await _postJson(
      '/lora/${Uri.encodeComponent(lrId)}/favorite',
      const {},
      sessionId,
    );
    return (
      ok: j['ok'] == true,
      favoriteCount: (j['favorite_count'] as num?)?.toInt(),
      message: j['message']?.toString() ?? '',
    );
  }

  /// 移出我的库。[deleted] = 机房已无人拥有,该 web 条目连库一起回收。
  Future<({bool ok, bool deleted, int? favoriteCount, String message})>
  unfavoriteLora({required String sessionId, required String lrId}) async {
    final j = await _postJson(
      '/lora/${Uri.encodeComponent(lrId)}/unfavorite',
      const {},
      sessionId,
    );
    return (
      ok: j['ok'] == true,
      deleted: j['deleted'] == true,
      favoriteCount: (j['favorite_count'] as num?)?.toInt(),
      message: j['message']?.toString() ?? '',
    );
  }

  /// Civitai 在线搜索(服务端代理,公开端点)。[cursor] 翻页游标;
  /// [base] 决定 Civitai 那边按 baseModel=Anima 还是 Krea 2 过滤;
  /// [tag] 是 Civitai 标签过滤(如 `anime`),**服务端去 Civitai 侧筛**、
  /// 不是页内过滤,所以改了它必须重发请求。空 = 不筛。
  Future<({List<CivitaiLoraInfo> items, String? nextCursor})> searchLoras({
    String query = '',
    String? cursor,
    int limit = 24,
    String base = 'anima',
    String tag = '',
  }) async {
    final q = <String>[
      if (query.isNotEmpty) 'query=${Uri.encodeComponent(query)}',
      if (cursor != null && cursor.isNotEmpty)
        'cursor=${Uri.encodeComponent(cursor)}',
      'nsfw=true', // 对齐 web:不做 R18 过滤开关
      'limit=$limit',
      'base=${Uri.encodeComponent(base)}',
      if (tag.isNotEmpty) 'tag=${Uri.encodeComponent(tag)}',
    ].join('&');
    final j = await _getJson('/lora/search?$q', null, _timeout * 2);
    if (j['ok'] == false) {
      throw BackendException(j['message']?.toString() ?? 'Civitai 搜索失败');
    }
    return (
      items: [
        for (final e in j['items'] is List ? j['items'] as List : const [])
          if (e is Map<String, dynamic>) CivitaiLoraInfo.fromJson(e),
      ],
      nextCursor: j['next_cursor']?.toString(),
    );
  }

  /// 安装任务的进度**与结果**(`GET /api/lora/install/progress`)。
  ///
  /// `/lora/install` 现在开始下载就返回了(见 [installLora]),所以结论只能从
  /// 这条读:轮到 [state] 变成 `done` / `failed` 才算有结果。
  ///  - [phase] `downloading` 从 Civitai 拉 / `uploading` 拉完再传进库 ——
  ///    走租用实例时这两段各占一半,不区分的话进度条会在 100% 上干等好几分钟;
  ///  - [total] = 0 表示对面没给 content-length,只能显示「已下多少 MB」;
  ///  - [stale] = 超过 60s 没动静(服务端判的,别自己缩短:传 R2 那段是 boto3
  ///    内部一次 upload_file,中间不回调,大文件很容易安静超过半分钟)。
  Future<
    List<
      ({
        int versionId,
        String name,
        String state,
        String phase,
        int downloaded,
        int total,
        String lrId,
        String message,
        bool stale,
      })
    >
  >
  loraInstallProgress() async {
    final j = await _getJson('/lora/install/progress');
    return [
      for (final e in j['items'] is List ? j['items'] as List : const [])
        if (e is Map<String, dynamic>)
          (
            versionId: (e['version_id'] as num?)?.toInt() ?? 0,
            name: e['name']?.toString() ?? '',
            state: e['state']?.toString() ?? 'running',
            phase: e['phase']?.toString() ?? 'downloading',
            downloaded: (e['downloaded'] as num?)?.toInt() ?? 0,
            total: (e['total'] as num?)?.toInt() ?? 0,
            lrId: e['lr_id']?.toString() ?? '',
            message: e['message']?.toString() ?? '',
            stale: e['stale'] == true,
          ),
    ];
  }

  /// 认领图片元数据里的 LoRA 引用(`POST /api/lora/resolve`)。
  ///
  /// 服务端三级判定:SHA 前缀 → 名称 → Civitai by-hash → 找不到。别人的私有
  /// LoRA 一律按未命中返回(不暴露其存在)。带上会话才能认领到自己的私有条目。
  Future<List<LoraResolveResult>> resolveLoras({
    String? sessionId,
    required List<
      ({String name, String hash, double? weight, double? clipWeight})
    >
    items,
  }) async {
    final j = await _postJson(
      '/lora/resolve',
      {
        'items': [
          for (final it in items)
            {
              'name': it.name,
              'hash': it.hash,
              'weight': it.weight,
              'clip_weight': it.clipWeight,
            },
        ],
      },
      sessionId,
      _timeout * 2, // 未命中的会去查 Civitai,比普通接口慢
    );
    return [
      for (final e in j['items'] is List ? j['items'] as List : const [])
        if (e is Map<String, dynamic>) LoraResolveResult.fromJson(e),
    ];
  }

  /// 在线「下载到我的库」。两种结果,**必须分开处理**:
  ///  - 已在库(sha / 版本撞上)→ `pending=false`,同步完成,只加了收藏;
  ///  - 要下载 → `pending=true`,**只是开始了** —— 结论去 [loraInstallProgress]
  ///    轮询到 `done` / `failed` 才算数。
  ///
  /// 服务端从前是下完才返回的,现在不是了:走租用实例时一个大 LoRA 前后好几
  /// 分钟,挂在这个请求上必被超时掐断 —— 用户看到「连接后端超时」,而文件其实
  /// 下完了也进了库。所以这里不再等下载,超时按普通接口给。
  Future<({bool ok, bool pending, String? lrId, String message})> installLora({
    required String sessionId,
    required int versionId,
    String base = 'anima',
  }) async {
    final j = await _postJson('/lora/install', {
      'version_id': versionId,
      'base': base,
    }, sessionId);
    return (
      ok: j['ok'] == true,
      pending: j['pending'] == true,
      lrId: j['lr_id']?.toString(),
      message: j['message']?.toString() ?? '',
    );
  }

  /// 上传自己的 LoRA(`POST /api/lora/upload`,multipart)。
  ///
  /// 文件从磁盘边读边发,不整份读进内存(动辄几百 MB);[onProgress] 回报已发出
  /// 的比例(0~1)。**不设总时限** —— 大文件走移动网络本来就慢,断线由 socket
  /// 自己报错。
  ///
  /// 服务端收完只做校验与登记就返回,推进机房是它的后台任务:拿到 lrId 后要
  /// 轮询 [loraUploadStatus] 到 synced 才算就绪。[dedup] = SHA 撞上库里已有
  /// 条目,没新建,已替你收藏那条。
  ///
  /// [triggerGroups] 每条是一个「组/套装」(组内可含逗号),与注册表语义一致。
  Future<({bool ok, String? lrId, bool dedup, String message})> uploadLora({
    required String sessionId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String displayName,
    required List<String> triggerGroups,
    required String type,
    required bool public,
    String base = 'anima',
    void Function(double progress)? onProgress,
  }) async {
    if (baseUrl.isEmpty) throw BackendException('未配置后端地址');
    var sent = 0;
    final body = File(filePath).openRead().map((chunk) {
      sent += chunk.length;
      if (fileSize > 0) onProgress?.call(sent / fileSize);
      return chunk;
    });
    final req = http.MultipartRequest('POST', _u('/lora/upload'))
      ..headers['Authorization'] = 'Bearer $sessionId'
      ..fields['display_name'] = displayName
      ..fields['trigger_words'] = jsonEncode(triggerGroups)
      ..fields['lora_type'] = type
      ..fields['visibility'] = public ? 'public' : 'private'
      ..fields['base'] = base
      ..files.add(
        http.MultipartFile('file', body, fileSize, filename: fileName),
      );

    final http.Response resp;
    try {
      resp = await http.Response.fromStream(await req.send());
    } catch (_) {
      throw BackendException('上传中断,请检查网络后重试');
    }
    final j = _decode(resp);
    return (
      ok: j['ok'] == true,
      lrId: j['lr_id']?.toString(),
      dedup: j['dedup'] == true,
      message: j['message']?.toString() ?? '',
    );
  }

  /// 上传件推进机房的进度:uploading / synced / failed / missing(条目已不在)。
  Future<({bool ok, String status, String? error})> loraUploadStatus(
    String lrId,
  ) async {
    final j = await _getJson(
      '/lora/upload/${Uri.encodeComponent(lrId)}/status',
    );
    return (
      ok: j['ok'] == true,
      status: j['status']?.toString() ?? 'missing',
      error: j['error']?.toString(),
    );
  }

  /// 推送失败后重来(复用服务端留着的那份临时文件,不用重传)。仅上传者本人。
  Future<({bool ok, String message})> retryLoraUpload({
    required String sessionId,
    required String lrId,
  }) async {
    final j = await _postJson(
      '/lora/${Uri.encodeComponent(lrId)}/retry_upload',
      const {},
      sessionId,
    );
    return (ok: j['ok'] == true, message: j['message']?.toString() ?? '');
  }

  /// 自然语言补强(anima 专属;登录:Bearer 头)。读当前正向词,产出可追加到
  /// 其末尾的英文句子 —— anima 是 tag + 自然语言混训,句子负责空间关系/构图/
  /// 光影/动作因果。一次 LLM 往返、非流式。
  ///
  /// [mode] 只接受 `characters`(多角色区分)/ `enhance`(整体补强);
  /// [positive] 须是剥净仅编辑期语法的定稿(app 里即 `GenerateState.prompt`),
  /// 空则服务端 400。[loras] 形如 `[{name, trigger_words}]`,仅作角色识别线索。
  ///
  /// 超时给 60s:服务端自己 45s 掐(504 带人话 detail),本地先断就只剩
  /// 「连接后端超时」这句没信息量的兜底。
  Future<AnimaNlResult> animaNl({
    required String sessionId,
    required String mode,
    required String positive,
    String extra = '',
    String existingNl = '',
    List<Map<String, dynamic>> loras = const [],
  }) async {
    final j = await _postJson(
      '/agent/web/anima-nl',
      {
        'mode': mode,
        'positive': positive,
        'extra': extra,
        'existing_nl': existingNl,
        'loras': loras,
      },
      sessionId,
      const Duration(seconds: 60),
    );
    return AnimaNlResult.fromJson(j);
  }

  /// 提示词整理(krea 专属;登录:Bearer 头)。读当前正向词,产出**整条新的**
  /// 正向词 —— k2 用 Qwen3-VL 做文本编码器,吃的是连贯自然语言,不吃 tag 串。
  ///
  /// [mode] 只接受 `rewrite`(tag 串 → 完整语句)/ `enrich`(不改主体,补光线、
  /// 材质、镜头与氛围);[positive] 须是剥净仅编辑期语法的定稿,空则服务端 400。
  /// [loras] 形如 `[{name, trigger_words}]` —— 触发短语是权重开关,服务端会
  /// 要求原样保留进结果。**只管正向**,排除内容不在本模块职责内(故无该字段)。
  ///
  /// 超时同 [animaNl] 给 60s:服务端自己 45s 掐(504 带人话 detail)。
  Future<KreaPromptResult> kreaPrompt({
    required String sessionId,
    required String mode,
    required String positive,
    String extra = '',
    List<Map<String, dynamic>> loras = const [],
  }) async {
    final j = await _postJson(
      '/agent/web/krea-prompt',
      {'mode': mode, 'positive': positive, 'extra': extra, 'loras': loras},
      sessionId,
      const Duration(seconds: 60),
    );
    return KreaPromptResult.fromJson(j);
  }
}

/// 用当前后端基址构造 client(基址变更自动重建)。
final backendClientProvider = Provider<BackendClient>((ref) {
  final base = ref.watch(backendBaseProvider).value ?? '';
  return BackendClient(base);
});

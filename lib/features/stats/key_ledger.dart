import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../l10n/l10n.dart';

/// 直连 Key 模式的本机记账。服务端只记 bot 用量,直连生成不经过后端,
/// 统计只能在本机落账:生成按天聚合(张数/免费张/点数),Vibe 编码与
/// NAI 超分按笔记录。点数一律为估算值(与生成按钮的费用预估同一公式,
/// 免费档为 0);bot 模式的用量由服务端记,这里不落。
class KeyDayAgg {
  KeyDayAgg({
    this.images = 0,
    this.free = 0,
    this.pts = 0,
    this.v5 = 0,
    this.v5Pts = 0,
  });

  int images;
  int free;
  int pts;

  /// 其中 V5 的张数与点数。点数要单列 —— V5 扣点是 V4.5 的 1.5 倍,
  /// 光看张数看不出真实消耗(与服务端 `/api/user/stats` 的 v5_calls/v5_points
  /// 同一口径)。免费档那些张照样计进 [v5]:它问的是「出了几张 V5」。
  int v5;
  int v5Pts;
}

/// 单笔计费操作。[type]:`vibe` | `upscale`。
class KeyOp {
  const KeyOp({required this.ts, required this.type, required this.pts});

  /// 毫秒时间戳。
  final int ts;
  final String type;
  final int pts;
}

/// 单次生成记录(逐笔,供「生成详情」查当日每一张)。
/// 按天聚合能覆盖全部历史,这里只留最近 [KeyLedgerStore.maxGens] 条明细。
class KeyGen {
  const KeyGen({
    required this.ts,
    required this.pts,
    required this.width,
    required this.height,
    required this.steps,
    required this.model,
    this.inpaint = false,
  });

  final int ts;

  /// 估算点数;0 = 免费档。
  final int pts;
  final int width;
  final int height;
  final int steps;
  final String model;
  final bool inpaint;
}

/// 趋势图一个柱:[label] 轴标(小时/星期/日),[full] 选中详情用的日期文案。
class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.full,
    required this.images,
    required this.pts,
  });

  final String label;
  final String full;
  final int images;
  final int pts;
}

/// 账本流水一行:生成日聚合([gen] 非空)或单笔操作([op] 非空),二选一。
class KeyLedgerRow {
  const KeyLedgerRow({required this.ts, this.day, this.gen, this.op});

  final int ts;
  final String? day;
  final KeyDayAgg? gen;
  final KeyOp? op;
}

class KeyLedgerStore {
  KeyLedgerStore(Directory root)
    : _file = File(
        '${root.path}${Platform.pathSeparator}stats'
        '${Platform.pathSeparator}key_ledger.json',
      );

  final File _file;

  /// `yyyy-MM-dd` → 当日生成聚合。
  final Map<String, KeyDayAgg> days = {};

  /// 单笔计费操作,新的在前;上限 [maxOps]。
  final List<KeyOp> ops = [];

  /// 逐笔生成明细,新的在前;上限 [maxGens](聚合数据不受影响)。
  final List<KeyGen> gens = [];

  /// 当天逐小时生成桶(今日档趋势图用;跨天自动重置)。
  /// 只留当天一份——历史小时级明细没人看,不值得成倍存储。
  String hourDay = '';
  final List<int> hourImages = List.filled(24, 0);
  final List<int> hourPts = List.filled(24, 0);

  int totalImages = 0;
  int totalFree = 0;
  int totalGenPts = 0;
  int totalVibePts = 0;
  int totalUpsPts = 0;
  int totalV5 = 0;
  int totalV5Pts = 0;

  int get totalPts => totalGenPts + totalVibePts + totalUpsPts;

  /// 数据版本号,每次落账 +1(统计页监听刷新)。
  final ValueNotifier<int> rev = ValueNotifier(0);

  static const maxOps = 200;
  static const maxGens = 400;
  static const _maxDays = 400;

  Timer? _debounce;
  Future<void> _chain = Future.value();

  /// 排队中的写全部落盘(测试用)。
  Future<void> get idle => _chain;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString());
      if (j is! Map<String, dynamic>) return;
      final rawDays = j['days'];
      if (rawDays is Map) {
        for (final e in rawDays.entries) {
          final v = e.value;
          if (v is List && v.length >= 3) {
            // 后两项是后加的:老档只有三项,读不到就是 0(那时还没有 V5)
            days[e.key.toString()] = KeyDayAgg(
              images: (v[0] as num?)?.toInt() ?? 0,
              free: (v[1] as num?)?.toInt() ?? 0,
              pts: (v[2] as num?)?.toInt() ?? 0,
              v5: (v.elementAtOrNull(3) as num?)?.toInt() ?? 0,
              v5Pts: (v.elementAtOrNull(4) as num?)?.toInt() ?? 0,
            );
          }
        }
      }
      final rawOps = j['ops'];
      if (rawOps is List) {
        for (final v in rawOps) {
          if (v is List && v.length >= 3) {
            ops.add(
              KeyOp(
                ts: (v[0] as num?)?.toInt() ?? 0,
                type: v[1]?.toString() ?? 'vibe',
                pts: (v[2] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
        if (ops.length > maxOps) ops.removeRange(maxOps, ops.length);
      }
      final t = j['totals'];
      if (t is List && t.length >= 5) {
        totalImages = (t[0] as num?)?.toInt() ?? 0;
        totalFree = (t[1] as num?)?.toInt() ?? 0;
        totalGenPts = (t[2] as num?)?.toInt() ?? 0;
        totalVibePts = (t[3] as num?)?.toInt() ?? 0;
        totalUpsPts = (t[4] as num?)?.toInt() ?? 0;
        // 同上:老档只有五项
        totalV5 = (t.elementAtOrNull(5) as num?)?.toInt() ?? 0;
        totalV5Pts = (t.elementAtOrNull(6) as num?)?.toInt() ?? 0;
      }
      final rawGens = j['gens'];
      if (rawGens is List) {
        for (final v in rawGens) {
          if (v is! List || v.length < 6) continue;
          gens.add(
            KeyGen(
              ts: (v[0] as num?)?.toInt() ?? 0,
              pts: (v[1] as num?)?.toInt() ?? 0,
              width: (v[2] as num?)?.toInt() ?? 0,
              height: (v[3] as num?)?.toInt() ?? 0,
              steps: (v[4] as num?)?.toInt() ?? 0,
              model: v[5]?.toString() ?? '',
              inpaint: v.length > 6 && v[6] == 1,
            ),
          );
        }
        if (gens.length > maxGens) gens.removeRange(maxGens, gens.length);
      }
      final h = j['hours'];
      if (h is List && h.length >= 3 && h[1] is List && h[2] is List) {
        hourDay = h[0]?.toString() ?? '';
        for (var i = 0; i < 24; i++) {
          hourImages[i] =
              ((h[1] as List).elementAtOrNull(i) as num?)?.toInt() ?? 0;
          hourPts[i] =
              ((h[2] as List).elementAtOrNull(i) as num?)?.toInt() ?? 0;
        }
      }
      _pruneDays();
    } catch (_) {
      // 脏档按空账本降级,不 brick 启动
    }
  }

  /// 直连生成完成落一笔([pts]=0 记免费张)。
  /// 带上参数就同时留一条逐笔明细(「生成详情」按天查)。
  void recordGen({
    required int pts,
    DateTime? at,
    int? width,
    int? height,
    int? steps,
    String? model,
    bool inpaint = false,
    bool v5 = false,
  }) {
    final t = at ?? DateTime.now();
    final key = dayKey(t);
    if (width != null && height != null) {
      gens.insert(
        0,
        KeyGen(
          ts: t.millisecondsSinceEpoch,
          pts: pts,
          width: width,
          height: height,
          steps: steps ?? 0,
          model: model ?? '',
          inpaint: inpaint,
        ),
      );
      if (gens.length > maxGens) gens.removeRange(maxGens, gens.length);
    }
    final d = days.putIfAbsent(key, KeyDayAgg.new);
    d.images++;
    if (pts <= 0) {
      d.free++;
      totalFree++;
    } else {
      d.pts += pts;
      totalGenPts += pts;
    }
    if (v5) {
      d.v5++;
      totalV5++;
      // 免费档那张记进张数但不记点数,与上面 pts<=0 那支同一口径
      if (pts > 0) {
        d.v5Pts += pts;
        totalV5Pts += pts;
      }
    }
    totalImages++;
    _touchHourDay(key);
    if (hourDay == key) {
      hourImages[t.hour]++;
      hourPts[t.hour] += pts > 0 ? pts : 0;
    }
    _pruneDays();
    _bump();
  }

  /// 跨天后小时桶清零改挂新的一天。
  void _touchHourDay(String key) {
    if (hourDay == key) return;
    hourDay = key;
    hourImages.fillRange(0, 24, 0);
    hourPts.fillRange(0, 24, 0);
  }

  /// 直连单笔计费操作(Vibe 编码 / NAI 超分)落一笔。
  void recordOp(String type, int pts, {DateTime? at}) {
    ops.insert(
      0,
      KeyOp(
        ts: (at ?? DateTime.now()).millisecondsSinceEpoch,
        type: type,
        pts: pts,
      ),
    );
    if (ops.length > maxOps) ops.removeRange(maxOps, ops.length);
    if (type == 'upscale') {
      totalUpsPts += pts;
    } else {
      totalVibePts += pts;
    }
    _bump();
  }

  // ── 查询(内存态,时间范围按本地时区) ────────────────

  /// [range] ∈ today/week(周一起)/month(1 号起)。
  ({
    int images,
    int free,
    int genPts,
    int vibePts,
    int upsPts,
    int v5,
    int v5Pts,
  })
  sumRange(String range, {DateTime? now}) {
    final from = _rangeStart(range, now ?? DateTime.now());
    final fromKey = dayKey(from);
    final fromMs = from.millisecondsSinceEpoch;
    var images = 0, free = 0, genPts = 0, vibePts = 0, upsPts = 0;
    var v5 = 0, v5Pts = 0;
    for (final e in days.entries) {
      if (e.key.compareTo(fromKey) < 0) continue;
      images += e.value.images;
      free += e.value.free;
      genPts += e.value.pts;
      v5 += e.value.v5;
      v5Pts += e.value.v5Pts;
    }
    for (final o in ops) {
      if (o.ts < fromMs) break; // 新在前,过界即止
      if (o.type == 'upscale') {
        upsPts += o.pts;
      } else {
        vibePts += o.pts;
      }
    }
    return (
      images: images,
      free: free,
      genPts: genPts,
      vibePts: vibePts,
      upsPts: upsPts,
      v5: v5,
      v5Pts: v5Pts,
    );
  }

  /// 某天的逐笔生成(新→旧)。超出 [maxGens] 窗口的老日子会是空表,
  /// 但当天的按天聚合数仍在(详情页据此提示「明细已滚出保留窗口」)。
  List<KeyGen> gensForDay(String day) => [
    for (final g in gens)
      if (dayKey(DateTime.fromMillisecondsSinceEpoch(g.ts)) == day) g,
  ];

  /// 某天的逐笔计费操作(Vibe 编码 / 超分)。
  List<KeyOp> opsForDay(String day) => [
    for (final o in ops)
      if (dayKey(DateTime.fromMillisecondsSinceEpoch(o.ts)) == day) o,
  ];

  /// 趋势图序列:today=24 小时;week=本周一起 7 天;month=本月 1 号至今。
  /// 点数含生成 + 单笔操作(Vibe/超分),与账单口径一致。
  List<TrendPoint> seriesFor(String range, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (range == 'today') {
      final today = dayKey(n);
      final opsByHour = List.filled(24, 0);
      for (final o in ops) {
        final t = DateTime.fromMillisecondsSinceEpoch(o.ts);
        if (dayKey(t) != today) continue;
        opsByHour[t.hour] += o.pts;
      }
      final live = hourDay == today;
      return [
        for (var h = 0; h < 24; h++)
          TrendPoint(
            label: '$h',
            full: l10nNow.todayHour(h.toString().padLeft(2, '0')),
            images: live ? hourImages[h] : 0,
            pts: (live ? hourPts[h] : 0) + opsByHour[h],
          ),
      ];
    }

    final start = _rangeStart(range, n);
    final count = range == 'week'
        ? 7 // 整周(未来几天留空柱,星期标尺才对得齐)
        : n.day;
    final opsByDay = <String, int>{};
    for (final o in ops) {
      final k = dayKey(DateTime.fromMillisecondsSinceEpoch(o.ts));
      opsByDay[k] = (opsByDay[k] ?? 0) + o.pts;
    }
    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];
    return [
      for (var i = 0; i < count; i++)
        () {
          final day = DateTime(start.year, start.month, start.day + i);
          final k = dayKey(day);
          final agg = days[k];
          return TrendPoint(
            label: range == 'week' ? weekLabels[i] : '${day.day}',
            full: k.substring(5),
            images: agg?.images ?? 0,
            pts: (agg?.pts ?? 0) + (opsByDay[k] ?? 0),
          );
        }(),
    ];
  }

  /// 流水:近 [maxDays] 天的生成日行 + 单笔操作,时间倒序,截 [cap] 行。
  List<KeyLedgerRow> recentRows({
    int maxDays = 14,
    int cap = 40,
    DateTime? now,
  }) {
    final end = now ?? DateTime.now();
    final from = DateTime(
      end.year,
      end.month,
      end.day,
    ).subtract(Duration(days: maxDays - 1));
    final fromMs = from.millisecondsSinceEpoch;
    final rows = <KeyLedgerRow>[];
    for (var i = 0; i < maxDays; i++) {
      final day = end.subtract(Duration(days: i));
      final key = dayKey(day);
      final agg = days[key];
      if (agg == null || agg.images == 0) continue;
      // 日行排在当天末尾(今天=此刻),晚于当天的单笔操作
      final ts = i == 0
          ? end.millisecondsSinceEpoch
          : DateTime(
              day.year,
              day.month,
              day.day,
              23,
              59,
              59,
            ).millisecondsSinceEpoch;
      rows.add(KeyLedgerRow(ts: ts, day: key, gen: agg));
    }
    for (final o in ops) {
      if (o.ts < fromMs) break;
      rows.add(KeyLedgerRow(ts: o.ts, op: o));
    }
    rows.sort((a, b) => b.ts.compareTo(a.ts));
    return rows.length > cap ? rows.sublist(0, cap) : rows;
  }

  static DateTime _rangeStart(String range, DateTime now) => switch (range) {
    'today' => DateTime(now.year, now.month, now.day),
    'week' => DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1)),
    _ => DateTime(now.year, now.month, 1),
  };

  // ── 落盘(防抖 + 串行链,与其他 store 同款) ────────────────

  void _bump() {
    rev.value++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _write);
  }

  void _write() {
    _debounce?.cancel();
    _debounce = null;
    final payload = jsonEncode({
      'v': 1,
      'days': {
        for (final e in days.entries)
          e.key: [
            e.value.images,
            e.value.free,
            e.value.pts,
            e.value.v5,
            e.value.v5Pts,
          ],
      },
      'ops': [
        for (final o in ops) [o.ts, o.type, o.pts],
      ],
      'totals': [
        totalImages,
        totalFree,
        totalGenPts,
        totalVibePts,
        totalUpsPts,
        totalV5,
        totalV5Pts,
      ],
      'gens': [
        for (final g in gens)
          [g.ts, g.pts, g.width, g.height, g.steps, g.model, g.inpaint ? 1 : 0],
      ],
      'hours': [hourDay, hourImages, hourPts],
    });
    _chain = _chain.then((_) async {
      try {
        await _file.parent.create(recursive: true);
        await _file.writeAsString(payload, flush: true);
      } catch (_) {}
    });
  }

  /// 退后台/失焦立即落盘。
  Future<void> flush() {
    if (_debounce != null) _write();
    return _chain;
  }

  void _pruneDays() {
    if (days.length <= _maxDays) return;
    final keys = days.keys.toList()..sort();
    for (final k in keys.take(days.length - _maxDays)) {
      days.remove(k);
    }
  }
}

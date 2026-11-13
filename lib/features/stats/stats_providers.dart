import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/nai_client.dart' show NaiUsage;
import '../../l10n/l10n.dart';

export '../../core/net/anlas_provider.dart' show walletSummaryProvider;

/// 统计页的数据源。服务端端点(除在线人数)都要 Bot 会话;
/// 失败/未授权一律回 null,由页面按「—」/未授权提示降级,不弹错。
/// range ∈ today/week/month。

Future<T?> _withSession<T>(
  Ref ref,
  Future<T> Function(BackendClient c, String sid) run,
) async {
  final session = await ref.watch(botSessionProvider.future);
  if (session == null) return null;
  try {
    return await run(ref.watch(backendClientProvider), session.sessionId);
  } catch (_) {
    return null;
  }
}

/// 个人统计(bot 账号,跨端)。range ∈ today/week/month。
final userStatsProvider = FutureProvider.autoDispose
    .family<UsageStats?, String>(
      (ref, range) => _withSession(ref, (c, sid) => c.userStats(sid, range)),
    );

/// 个人历史累计。后端 `_time_bounds` 对任何非 today/week/month 的值
/// 返回空边界 → 不加时间过滤即全量(源码核实),故传 `all` 取累计。
final userStatsAllProvider = FutureProvider.autoDispose<UsageStats?>(
  (ref) => _withSession(ref, (c, sid) => c.userStats(sid, 'all')),
);

/// 个人逐日序列。today 档后端给的是逐小时点(date 形如 `HH:mm`),
/// 主页趋势图用。
final userDailyProvider = FutureProvider.autoDispose
    .family<List<DailyStat>?, String>(
      (ref, range) =>
          _withSession(ref, (c, sid) => c.userStatsDaily(sid, range)),
    );

/// 平台当期统计。
final platformStatsProvider = FutureProvider.autoDispose
    .family<UsageStats?, String>(
      (ref, range) =>
          _withSession(ref, (c, sid) => c.platformStats(sid, range)),
    );

/// 平台历史全局。
final platformAllProvider = FutureProvider.autoDispose<UsageStats?>(
  (ref) => _withSession(ref, (c, sid) => c.platformStatsAll(sid)),
);

/// 平台 24 小时热力图;参数 (种类, 统计天数)。
final platformHourlyProvider = FutureProvider.autoDispose
    .family<HourlyHeat?, (HourlyKind, int)>(
      (ref, arg) =>
          _withSession(ref, (c, sid) => c.platformHourly(sid, arg.$1, arg.$2)),
    );

/// 某一天的钱包流水(扣款与入账,新→旧)。参数为该天 00:00。
///
/// 当天的合计要拿全量算,所以按页拉齐再交出去。一张中转图就是一笔,平常一页
/// 就够;拉满 [_kDayLedgerPages] 页还没到底就停,`nextCursor` 原样留着,
/// 页面据此注明只列了一部分。
final dayDetailsProvider = FutureProvider.autoDispose
    .family<WalletLedger?, DateTime>(
      (ref, day) => _withSession(ref, (c, sid) async {
        final until = day.add(const Duration(days: 1));
        final items = <WalletEntry>[];
        String? cursor;
        for (var i = 0; i < _kDayLedgerPages; i++) {
          final page = await c.walletLedger(
            sid,
            limit: 100,
            cursor: cursor,
            since: day,
            until: until,
          );
          items.addAll(page.items);
          // 空页还带游标不该出现;真遇上就当到底,别对着空页一直翻
          cursor = page.items.isEmpty ? null : page.nextCursor;
          if (cursor == null) break;
        }
        return WalletLedger(items: items, nextCursor: cursor);
      }),
    );

/// 某一天的流水最多翻几页(每页 100 笔)。
const _kDayLedgerPages = 20;

/// 某一天的逐笔生成明细(服务端 `/api/user/stats/calls`,最多 1000 条)。
/// 拉不到时返回 null,页面合计显示「—」、逐笔那里说暂时查不到。
final dayCallsProvider = FutureProvider.autoDispose
    .family<List<CallRecord>?, DateTime>(
      (ref, day) => _withSession(
        ref,
        (c, sid) => c.callRecords(
          sessionId: sid,
          from: day,
          to: day.add(const Duration(days: 1)),
        ),
      ),
    );

/// 共享号池的 NAI 官方额度(全平台水位)。**公开端点,不要会话** —— 所以不走
/// [_withSession];全平台统计页在没授权时本来就整页不可见,不必再挡一道。
final poolUsageProvider = FutureProvider.autoDispose<NaiUsage?>((ref) async {
  try {
    return await ref.watch(backendClientProvider).poolUsage();
  } catch (_) {
    return null; // 老服务端没这个端点 → 那块不画
  }
});

/// 钱包金额(分 → 文案),和服务端同一种写法:扣款 `-¥0.03`、入账 `+¥20.00`。
/// [sign] = false 时正数不带 +(余额、合计用),负数照样带 -。
String fmtFen(int fen, {bool sign = true}) {
  final head = fen < 0 ? '-' : (sign && fen > 0 ? '+' : '');
  return '$head¥${(fen.abs() / 100).toStringAsFixed(2)}';
}

/// 各项占总和的整数百分比,合计恰为 100(最大余数法,与 web `sharePercents` 一致)。
/// 总和不大于 0 时全为 0。
List<int> sharePercents(List<int> amounts) {
  final total = amounts.fold(0, (s, a) => s + a);
  if (total <= 0) return [for (final _ in amounts) 0];
  final raw = [for (final a in amounts) a * 100 / total];
  final out = [for (final r in raw) r.floor()];
  // 余数一样时靠前的先补
  final order = List.generate(amounts.length, (i) => i)
    ..sort((a, b) {
      final c = (raw[b] - out[b]).compareTo(raw[a] - out[a]);
      return c != 0 ? c : a - b;
    });
  final missing = 100 - out.fold(0, (s, p) => s + p);
  for (var k = 0; k < missing; k++) {
    out[order[k]]++;
  }
  return out;
}

/// 千分位(App 无 intl 依赖,手搓)。
String fmtInt(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return v < 0 ? '-$b' : b.toString();
}

Map<String, String> get rangeLabels => {
  'today': l10nNow.rangeToday,
  'week': l10nNow.rangeWeek,
  'month': l10nNow.rangeMonth,
};

/// 时间范围 → 热力图统计天数(对齐 web)。
const rangeDays = {'today': 1, 'week': 7, 'month': 30};

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/store/ui_prefs.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/store/app_stores.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show sharedAxisRoute;
import 'day_detail_page.dart';
import 'key_ledger.dart';
import 'platform_page.dart';
import 'stats_providers.dart';
import 'stats_widgets.dart';
import 'wallet_page.dart';

/// 统计主页:右上角下拉切数据源(Bot 服务端 / 直连 Key 本机),
/// 主体是纯数据——时间范围 + hero 大数字 + 随范围变化的可点趋势图
/// + 六格指标;钱包与全平台统计各自二级页(都只在 Bot 下列出)。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

/// 趋势图柱区高度(加载占位与图表共用,保证两态等高)。
const double _kChartH = 46;

class _StatsPageState extends ConsumerState<StatsPage> {
  late bool _bot;

  /// 时间范围。**与平台页共用一份记忆** —— 两页问的是同一件事:
  /// 我习惯看多长时间。
  late String _range = ref.read(uiPrefsProvider).statsRange;

  /// 趋势图选中柱;换范围/换数据源都清空。
  int? _picked;

  @override
  void initState() {
    super.initState();
    // 默认跟当前接入方式;下拉可随时切看另一套
    _bot = ref.read(authModeProvider).value != AuthMode.token;
  }

  void _push(Widget page) => Navigator.of(context).push(sharedAxisRoute(page));

  void _setRange(String v) {
    ref.read(uiPrefsProvider.notifier).patch((p) => p.copyWith(statsRange: v));
    setState(() {
      _range = v;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(botSessionProvider).value;
    final ledger = ref.watch(appStoresProvider).ledger;

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          _ModePill(
            bot: _bot,
            onChanged: (v) => setState(() {
              _bot = v;
              _picked = null;
            }),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: ListenableBuilder(
        listenable: ledger.rev,
        builder: (context, _) {
          final children = <Widget>[
            RangeChips(range: _range, onChanged: _setRange),
            const SizedBox(height: 14),
          ];

          if (_bot && session == null) {
            children.add(
              const StatsCard(
                child: Text('尚未 Bot 授权。在「我的 → 账号与接入」完成授权后,可查看用量统计与钱包。'),
              ),
            );
          } else {
            children.addAll(_dataSection(context));
          }
          // 钱包(服务端计费)与全平台大盘都只对 Bot 有意义,Key 模式不列
          if (_bot) {
            if (session != null) {
              children.add(const SizedBox(height: 12));
              children.add(_walletEntry(context));
            }
            children.add(const SizedBox(height: 10));
            children.add(_platformEntry(context));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userStatsProvider);
              ref.invalidate(userStatsAllProvider);
              ref.invalidate(userDailyProvider);
              ref.invalidate(walletSummaryProvider);
              ref.invalidate(platformHourlyProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: children,
            ),
          );
        },
      ),
    );
  }

  /// 首屏数据是否还在拉(Key 侧读本机账本,恒 false)。
  bool get _loading =>
      _bot &&
      (ref.watch(userStatsProvider(_range)).isLoading ||
          ref.watch(userDailyProvider(_range)).isLoading);

  /// hero(随选中改写)+ 裸排细柱,下接六格指标卡。
  List<Widget> _dataSection(BuildContext context) {
    final scheme = context.scheme;
    final loading = _loading;
    final series = _series();
    final picked = _picked != null && _picked! < series.length
        ? series[_picked!]
        : null;

    // 未选中:范围合计取服务端/账本口径(权威);选中:取该柱明细。
    final int? images;
    final int? pts;
    if (picked != null) {
      images = picked.images;
      pts = picked.pts;
    } else if (_bot) {
      final st = ref.watch(userStatsProvider(_range)).value;
      images = st?.imageCalls;
      pts = st?.pointsSpent;
    } else {
      final sum = ref.read(appStoresProvider).ledger.sumRange(_range);
      images = sum.images;
      pts = sum.genPts + sum.vibePts + sum.upsPts;
    }
    final scope = picked?.full ?? rangeLabels[_range]!;

    return [
      // 各槽位一律按最终文本的行高预留(骨架用同 style 的透明样本撑高),
      // 数字到位时高度不变,页面不跳。
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (loading && images == null)
            SkeletonText(
              sample: '0,000',
              style: mono(context, size: 34, weight: FontWeight.w700),
              width: 92,
            )
          else
            Text(
              images == null ? '—' : fmtInt(images),
              style: mono(context, size: 34, weight: FontWeight.w700),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '张 · $scope生图',
              style: context.texts.bodyMedium!.copyWith(
                color: picked != null
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: loading && pts == null
            ? SkeletonText(
                sample: '消耗 0,000 点',
                style: context.texts.labelSmall!,
                width: 76,
              )
            : Text(
                '消耗 ${pts == null ? '—' : fmtInt(pts)} 点',
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
      ),
      const SizedBox(height: 10),
      // 图表位高度固定(柱高 + 触控留白),加载态占同样高度
      SizedBox(
        height: _kChartH + 12,
        child: loading && series.isEmpty
            ? const Align(
                alignment: Alignment.bottomLeft,
                child: SkeletonBox(
                  width: double.infinity,
                  height: _kChartH,
                  radius: 8,
                ),
              )
            : TrendChart(
                points: [
                  for (final p in series)
                    (
                      label: p.label,
                      full: p.full,
                      images: p.images,
                      pts: p.pts,
                    ),
                ],
                selected: _picked,
                onSelect: (i) => setState(() => _picked = i),
                height: _kChartH,
              ),
      ),
      // 选中行常驻占位,选与不选高度一致(点柱子不会顶动下面的卡片)
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          picked == null ? '' : '已选 ${picked.full}',
          style: context.texts.labelSmall!.copyWith(color: scheme.primary),
        ),
      ),
      const SizedBox(height: 6),
      _tilesGrid(context, series, picked),
    ];
  }

  /// 指标明细:跟随时间范围;选中某柱后整组换成该{日|时段}的读数。
  /// 不套卡片,裸排在页面底色上,行间用细线分隔,与上面的 hero/柱条一体。
  ///
  /// 未选中 6 格 = 3 行(第三行是 V5 两项),选中 4 格 = 2 行 —— 选中态会矮一行:
  /// 趋势序列只有「张数 / 点数」两个数,拆不出某一柱里 V5 占多少,与其在那儿
  /// 摆两个跟着**整段范围**走的数(和上面两格不同口径),不如让它空着。
  Widget _tilesGrid(
    BuildContext context,
    List<TrendPoint> series,
    TrendPoint? picked,
  ) {
    final scheme = context.scheme;
    final today = _range == 'today';
    final unit = today ? '时段' : '单日';

    // 选中某柱:第一行两个读数,第二行两个当日明细入口
    if (picked != null) {
      final t = _pickedTiles(context, series, picked);
      return Column(
        children: [
          Divider(
            height: 18,
            thickness: .5,
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
          Row(
            children: [
              Expanded(child: t[0]),
              Expanded(child: t[1]),
            ],
          ),
          Divider(
            height: 22,
            thickness: .5,
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
          Row(
            children: [
              Expanded(
                child: () {
                  final (:n, :loading) = _billedCount(picked);
                  return _DetailEntry(
                    icon: _bot
                        ? Icons.account_balance_wallet_outlined
                        : Icons.toll_outlined,
                    label: _bot
                        ? DayDetailMode.points.botTitle
                        : DayDetailMode.points.title,
                    value: n == null ? null : fmtInt(n),
                    unit: '笔',
                    loading: loading,
                    onTap: () => _openDay(picked, DayDetailMode.points),
                  );
                }(),
              ),
              Expanded(
                child: _DetailEntry(
                  icon: Icons.photo_library_outlined,
                  label: '生成详情',
                  value: fmtInt(picked.images),
                  unit: '张',
                  onTap: () => _openDay(picked, DayDetailMode.gens),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final List<StatTile> tiles;
    {
      // 峰值 / 活跃格数:服务端没有这两项,按当前序列现算
      TrendPoint? peak;
      var active = 0;
      for (final p in series) {
        if (peak == null || p.images > peak.images) peak = p;
        if (p.images > 0) active++;
      }
      final peakOk = peak != null && peak.images > 0;
      final seriesLoading = _loading;
      final avg = active == 0
          ? null
          : fmtInt(series.fold(0, (s, p) => s + p.images) / active);

      if (_bot) {
        final stAsync = ref.watch(userStatsProvider(_range));
        final st = stAsync.value;
        tiles = [
          StatTile(
            icon: Icons.toll_outlined,
            label: '点数消耗',
            value: st == null ? null : fmtInt(st.pointsSpent),
            loading: stAsync.isLoading,
          ),
          StatTile(
            icon: Icons.calendar_today_outlined,
            label: today ? '活跃时段' : '活跃天数',
            value: series.isEmpty ? null : '$active',
            suffix: series.isEmpty ? null : '/ ${series.length}',
            loading: seriesLoading,
          ),
          StatTile(
            icon: Icons.trending_up,
            label: '最高$unit',
            value: peakOk ? fmtInt(peak.images) : null,
            suffix: peakOk ? peak.full : null,
            loading: seriesLoading,
          ),
          StatTile(
            icon: Icons.equalizer,
            label: today ? '段均生图' : '日均生图',
            value: avg ?? (seriesLoading ? null : '0'),
            loading: seriesLoading,
          ),
          // V5 两项。张数和点数都要:V5 扣点是 V4.5 的 1.5 倍,只看张数
          // 看不出真实消耗。没用过 V5 就是两个 0 —— 指标格本来就该摆满。
          StatTile(
            icon: Icons.auto_awesome_outlined,
            label: 'V5 生图',
            value: st == null ? null : fmtInt(st.v5Calls),
            loading: stAsync.isLoading,
          ),
          StatTile(
            icon: Icons.toll,
            label: 'V5 点数',
            value: st == null ? null : fmtInt(st.v5Points),
            loading: stAsync.isLoading,
          ),
        ];
      } else {
        // 与 Bot 同一套四格,仅数据源换成本机账本(口径注明「估算」)
        final sum = ref.read(appStoresProvider).ledger.sumRange(_range);
        tiles = [
          StatTile(
            icon: Icons.toll_outlined,
            label: '估算消耗',
            value: fmtInt(sum.genPts + sum.vibePts + sum.upsPts),
          ),
          StatTile(
            icon: Icons.calendar_today_outlined,
            label: today ? '活跃时段' : '活跃天数',
            value: '$active',
            suffix: '/ ${series.length}',
          ),
          StatTile(
            icon: Icons.trending_up,
            label: '最高$unit',
            value: peakOk ? fmtInt(peak.images) : null,
            suffix: peakOk ? peak.full : null,
          ),
          StatTile(
            icon: Icons.equalizer,
            label: today ? '段均生图' : '日均生图',
            value: avg ?? '0',
          ),
          // 与 Bot 同口径,数据源换成本机账本(见 KeyDayAgg.v5)
          StatTile(
            icon: Icons.auto_awesome_outlined,
            label: 'V5 生图',
            value: fmtInt(sum.v5),
          ),
          StatTile(icon: Icons.toll, label: 'V5 点数', value: fmtInt(sum.v5Pts)),
        ];
      }
    }

    return Column(
      children: [
        // 行数按格数来,不写死 —— 加一对指标不该还要回来改这里
        for (var row = 0; row * 2 < tiles.length; row++) ...[
          Divider(
            height: row == 0 ? 18 : 22,
            thickness: .5,
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
          Row(
            children: [
              Expanded(child: tiles[row * 2]),
              Expanded(child: tiles[row * 2 + 1]),
            ],
          ),
        ],
      ],
    );
  }

  /// 选中某柱时的两个读数:该格消耗 + 与上一格的增减。
  List<StatTile> _pickedTiles(
    BuildContext context,
    List<TrendPoint> series,
    TrendPoint picked,
  ) {
    final i = series.indexOf(picked);
    final prev = i > 0 ? series[i - 1] : null;
    final delta = prev == null ? null : picked.images - prev.images;

    return [
      StatTile(
        icon: Icons.toll_outlined,
        label: _bot ? '点数消耗' : '估算消耗',
        value: fmtInt(picked.pts),
      ),
      StatTile(
        icon: delta == null || delta == 0
            ? Icons.remove
            : (delta > 0 ? Icons.north_east : Icons.south_east),
        label: _range == 'today' ? '较上一时段' : '较上一日',
        value: delta == null
            ? '—'
            : (delta == 0 ? '持平' : '${delta > 0 ? '+' : ''}${fmtInt(delta)}'),
        suffix: delta == null || delta == 0 ? null : '张',
      ),
    ];
  }

  /// 该格笔数:Key 数本机(计费生成 + 单笔操作);
  /// Bot 数当天的钱包流水(与详情页同一 provider,进页时命中缓存)。
  /// 拉取中 loading 为真 → 入口数值位显示骨架;拉不到 n 为 null → 「—」。
  ({int? n, bool loading}) _billedCount(TrendPoint p) {
    if (!_bot) {
      final ledger = ref.read(appStoresProvider).ledger;
      final key = KeyLedgerStore.dayKey(_dayOf(p));
      return (
        n:
            ledger.gensForDay(key).where((g) => g.pts > 0).length +
            ledger.opsForDay(key).length,
        loading: false,
      );
    }
    final day = ref.watch(dayDetailsProvider(_dayOf(p)));
    return (n: day.value?.items.length, loading: day.isLoading);
  }

  /// 选中格归属的日期(今日档整天;其余按 `MM-dd` 配当前年份还原)。
  DateTime _dayOf(TrendPoint p) {
    final now = DateTime.now();
    if (_range == 'today') return DateTime(now.year, now.month, now.day);
    final parts = p.full.split('-');
    final m = int.tryParse(parts.first) ?? now.month;
    final d = parts.length > 1 ? (int.tryParse(parts[1]) ?? now.day) : now.day;
    return DateTime(now.year, m, d);
  }

  /// 打开选中格所属那天的明细。今日档选的是时段,归属仍是今天。
  void _openDay(TrendPoint picked, DayDetailMode mode) {
    _push(
      DayDetailPage(
        bot: _bot,
        day: _dayOf(picked),
        label: _range == 'today' ? '今天' : picked.full,
        mode: mode,
      ),
    );
  }

  /// 当前范围与数据源对应的趋势序列。
  ///
  /// Bot 侧要自己补齐日历:后端 `stats/daily` 只回「有记录的天」
  /// (源码 `all_days = sorted(set(...))`),空档天直接缺席,不补会让
  /// 柱子挤在一起、日期对不上。今日档后端按 3 小时一段(`range(0,24,3)`,
  /// 共 8 段),app 端无法凭空细化到逐小时,按段展示并在标签写明区间。
  List<TrendPoint> _series() {
    if (!_bot) {
      return ref.read(appStoresProvider).ledger.seriesFor(_range);
    }
    final daily = ref.watch(userDailyProvider(_range)).value;
    if (daily == null) return const [];
    final byKey = {for (final d in daily) d.date: d};
    final now = DateTime.now();

    if (_range == 'today') {
      return [
        for (var h = 0; h < 24; h += 3)
          () {
            final k = '${h.toString().padLeft(2, '0')}:00';
            final d = byKey[k];
            final end = (h + 3) % 24;
            return TrendPoint(
              label: '$h',
              full: '今天 $k–${end.toString().padLeft(2, '0')}:00',
              images: d?.imageCalls ?? 0,
              pts: d?.pointsSpent ?? 0,
            );
          }(),
      ];
    }

    final start = _range == 'week'
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1))
        : DateTime(now.year, now.month, 1);
    final count = _range == 'week' ? 7 : now.day;
    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];
    return [
      for (var i = 0; i < count; i++)
        () {
          final day = DateTime(start.year, start.month, start.day + i);
          final k =
              '${day.year.toString().padLeft(4, '0')}-'
              '${day.month.toString().padLeft(2, '0')}-'
              '${day.day.toString().padLeft(2, '0')}';
          final d = byKey[k];
          return TrendPoint(
            label: _range == 'week' ? weekLabels[i] : '${day.day}',
            full: k.substring(5),
            images: d?.imageCalls ?? 0,
            pts: d?.pointsSpent ?? 0,
          );
        }(),
    ];
  }

  /// 钱包入口(Bot)。
  ///
  /// 这里原来是两本账 ——「NAI 账单」(按月阶梯分摊)和「算力账单」(租卡 +
  /// 视频按次实付);2026-10-18 起服务端并成了一个钱包,副行直接报余额。
  Widget _walletEntry(BuildContext context) {
    final scheme = context.scheme;
    final async = ref.watch(walletSummaryProvider);
    final w = async.value;
    final style = context.texts.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final Widget sub;
    if (async.isLoading && w == null) {
      sub = SkeletonText(
        sample: '余额 ¥000.00',
        style: context.texts.labelSmall!,
        width: 84,
      );
    } else if (w == null) {
      sub = Text('余额 · 流水 · 充值', style: style);
    } else {
      sub = Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: '余额 '),
            TextSpan(
              text: fmtFen(w.balanceFen, sign: false),
              // 欠着钱标警示色:不点进去也该看得出来
              style: w.owing
                  ? TextStyle(color: scheme.error, fontWeight: FontWeight.w600)
                  : null,
            ),
            if (w.pendingRentalCount > 0) const TextSpan(text: ' · 租卡进行中'),
          ],
        ),
        style: style,
      );
    }
    return _EntryCard(
      icon: Icons.account_balance_wallet_outlined,
      title: '钱包',
      subWidget: sub,
      onTap: () => _push(const WalletPage()),
    );
  }

  Widget _platformEntry(BuildContext context) {
    final scheme = context.scheme;
    final heatAsync = ref.watch(platformHourlyProvider((HourlyKind.calls, 7)));
    final heat = heatAsync.value;
    // 副行三态(骨架 / 文案 / 热力条)高度不一,统一装进等高槽位
    Widget sub;
    if (heatAsync.isLoading && heat == null) {
      sub = const SkeletonBox(width: 178, height: 8, radius: 3);
    } else if (heat == null || heat.cells.isEmpty) {
      sub = Text(
        '当期指标 · 负载时段 · 平均耗时',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.labelSmall!.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    } else {
      final byHour = {for (final c in heat.cells) c.hour: c.avg};
      final max = heat.cells.fold(0.0, (m, c) => c.avg > m ? c.avg : m);
      sub = Row(
        children: [
          for (var h = 0; h < 24; h += 2)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Container(
                width: 13,
                height: 8,
                decoration: BoxDecoration(
                  color: HeatCard.cellColor(
                    scheme,
                    max <= 0 ? 0 : (byHour[h] ?? 0) / max,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      );
    }
    return _EntryCard(
      icon: Icons.public,
      title: '全平台统计',
      subWidget: SizedBox(
        height: 16,
        child: Align(alignment: Alignment.centerLeft, child: sub),
      ),
      onTap: () => _push(const PlatformPage()),
    );
  }
}

/// 明细入口:内部结构与 [StatTile] 完全一致(标签行 + 数值行),
/// 只在数值右侧多一个箭头 —— 这样和相邻的指标格严格等高,选中态不跳版。
class _DetailEntry extends StatelessWidget {
  const _DetailEntry({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;

  /// 数值位(如笔数/张数);null 时显示「—」。
  final String? value;
  final String unit;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (loading && value == null)
            SkeletonText(
              sample: '0,000',
              style: mono(context, size: 17),
              width: 44,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value ?? '—', style: mono(context, size: 17)),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 16, color: scheme.outline),
              ],
            ),
        ],
      ),
    );
  }
}

/// 右上角数据源下拉:当前值 + 展开箭头,菜单里两项带选中勾。
class _ModePill extends StatelessWidget {
  const _ModePill({required this.bot, required this.onChanged});

  final bool bot;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    PopupMenuItem<bool> item(bool isBot, IconData icon, String label) =>
        PopupMenuItem(
          value: isBot,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon),
            title: Text(label),
            trailing: bot == isBot
                ? Icon(Icons.check, size: 18, color: scheme.primary)
                : null,
          ),
        );

    return PopupMenuButton<bool>(
      tooltip: '数据源',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        item(true, Icons.smart_toy_outlined, 'Bot 授权'),
        item(false, Icons.key, '直连 Key'),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
        decoration: ShapeDecoration(
          shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              bot ? Icons.smart_toy_outlined : Icons.key,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              bot ? 'Bot' : 'Key',
              style: context.texts.labelMedium!.copyWith(
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 入口卡(同「我的」页版式:图标块 + 标题/副行 + 尾注 + chevron)。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subWidget,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget subWidget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 11, 13),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.texts.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      subWidget,
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

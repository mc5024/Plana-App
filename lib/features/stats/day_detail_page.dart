import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/backend_client.dart';
import '../../core/store/app_stores.dart';
import '../../core/theme/app_theme.dart';
import '../generate/models.dart' show modelName;
import 'key_ledger.dart';
import 'stats_providers.dart';
import 'stats_widgets.dart';
import 'wallet_page.dart' show WalletEntryRow;
import '../../l10n/l10n.dart';

enum DayDetailMode {
  points('钱包流水'),
  gens('生成详情');

  const DayDetailMode(this._botTitle);

  String get title => switch (this) {
    points => l10nNow.pointsDetails,
    gens => l10nNow.genDetails,
  };

  final String _botTitle;

  /// Bot 下的叫法:服务端 2026-10-18 起改成钱包记账,这一格看的是当天钱包里
  /// 进出的钱,不再是点数。
  String get botTitle => this == gens ? l10nNow.genDetails : _botTitle;
}

/// 某一天的逐笔明细。
///
/// - 点数:Key 合并本机的计费生成与 Vibe 编码 / 超分操作;
///   Bot 换成当天的钱包流水(扣款与入账)。
/// - 生成:Key 有本机逐笔;Bot 取 `/api/user/stats/calls`(含分辨率/步数/模型)。
class DayDetailPage extends ConsumerWidget {
  const DayDetailPage({
    super.key,
    required this.bot,
    required this.day,
    required this.label,
    required this.mode,
  });

  final bool bot;

  /// 当天 00:00。
  final DateTime day;

  /// 标题里的日期文案(今天 / 07-24)。
  final String label;
  final DayDetailMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$label · ${bot ? mode.botTitle : mode.title}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: bot ? _botBody(context, ref) : _keyBody(context, ref),
      ),
    );
  }

  // ── Bot:服务端明细 ────────────────

  List<Widget> _botBody(BuildContext context, WidgetRef ref) =>
      mode == DayDetailMode.points
      ? _botWallet(context, ref)
      : _botGens(context, ref);

  /// 当天的钱包流水:扣款 / 入账两个合计 + 逐笔。
  List<Widget> _botWallet(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final async = ref.watch(dayDetailsProvider(day));
    final w = async.value;
    final loading = async.isLoading && w == null;

    if (!async.isLoading && w == null) {
      return const [StatsCard(child: Text('当天的流水暂时查不到,稍后再试'))];
    }

    // 扣款和入账分开合计:两件事,轧差没有意义(那是余额的事)
    var charged = 0, credited = 0, nCharge = 0, nCredit = 0;
    for (final e in w?.items ?? const <WalletEntry>[]) {
      if (e.amountFen < 0) {
        charged -= e.amountFen;
        nCharge++;
      } else if (e.amountFen > 0) {
        credited += e.amountFen;
        nCredit++;
      }
    }

    return [
      StatsCard(
        child: Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.remove_circle_outline,
                label: '当日扣款',
                value: w == null ? null : fmtFen(charged, sign: false),
                suffix: nCharge > 0 ? '$nCharge 笔' : null,
                loading: loading,
              ),
            ),
            Expanded(
              child: StatTile(
                icon: Icons.add_circle_outline,
                label: '当日入账',
                value: w == null ? null : fmtFen(credited, sign: false),
                suffix: nCredit > 0 ? '$nCredit 笔' : null,
                loading: loading,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      StatsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '逐笔流水',
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            if (w == null)
              ..._skeletonRows(4)
            else if (w.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '当天没有钱包流水',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
              )
            else ...[
              for (final e in w.items)
                WalletEntryRow(entry: e, withDate: false),
              // 翻页到上限还没到底(见 dayDetailsProvider):合计也只算了列出来的这些
              if (w.nextCursor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    '当天流水较多,只列出了最近 ${fmtInt(w.items.length)} 笔',
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    ];
  }

  /// 当天的逐笔生成(`/api/user/stats/calls`):合计按逐笔现算。
  List<Widget> _botGens(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(dayCallsProvider(day));
    final calls = callsAsync.value;
    final loading = callsAsync.isLoading && calls == null;

    return [
      StatsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.image_outlined,
                    label: '当日生图',
                    value: calls == null ? null : fmtInt(calls.length),
                    loading: loading,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    icon: Icons.toll_outlined,
                    label: '点数消耗',
                    value: calls == null
                        ? null
                        : fmtInt(calls.fold(0, (s, c) => s + c.anlas)),
                    loading: loading,
                  ),
                ),
              ],
            ),
            if (calls != null) ...[
              const CardDivider(),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.redeem_outlined,
                      label: '免费张数',
                      value: fmtInt(calls.where((c) => c.anlas == 0).length),
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      icon: Icons.straighten,
                      label: '平均步数',
                      value: () {
                        final ok = calls.where((c) => c.steps > 0).toList();
                        return ok.isEmpty
                            ? '—'
                            : fmtInt(
                                ok.fold(0, (s, c) => s + c.steps) / ok.length,
                              );
                      }(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      StatsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '逐笔生成',
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            ..._callRows(context, calls, callsAsync.isLoading),
          ],
        ),
      ),
    ];
  }

  /// 逐笔生成行:时间 · 分辨率 · 步数 · 模型 · 扣点/免费。
  List<Widget> _callRows(
    BuildContext context,
    List<CallRecord>? calls,
    bool loading,
  ) {
    final scheme = context.scheme;
    if (loading && calls == null) return _skeletonRows(4);
    if (calls == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '当天的生成明细暂时查不到,稍后再试',
            style: context.texts.bodySmall!.copyWith(color: scheme.outline),
          ),
        ),
      ];
    }
    if (calls.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '该日无生成记录',
            style: context.texts.bodySmall!.copyWith(color: scheme.outline),
          ),
        ),
      ];
    }
    return [
      for (final c in calls)
        LedgerRow(
          icon: c.img2img ? Icons.brush_outlined : Icons.image_outlined,
          title: c.hasParams
              ? '${c.width}×${c.height}'
                    '${c.steps > 0 ? ' · ${c.steps} 步' : ''}'
                    '${c.img2img ? ' · 图生图' : ''}'
                    '${c.charRefs > 0 ? ' · 角色参考×${c.charRefs}' : ''}'
              : '生成',
          sub: [
            if (c.time != null) _hhmm(c.time!),
            if (c.model.isNotEmpty) modelName(modelLabel(c.model)),
          ].join(' · '),
          trailing: c.anlas > 0 ? '-${fmtInt(c.anlas)} 点' : '免费',
          trailingColor: c.anlas > 0 ? scheme.primary : scheme.tertiary,
        ),
    ];
  }

  List<Widget> _skeletonRows(int n) => [
    for (var i = 0; i < n; i++)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SkeletonBox(width: 30, height: 30, radius: 9),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(width: 120, height: 12)),
          ],
        ),
      ),
  ];

  // ── Key:本机逐笔 ────────────────

  List<Widget> _keyBody(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final ledger = ref.watch(appStoresProvider).ledger;
    final key = KeyLedgerStore.dayKey(day);
    final agg = ledger.days[key];
    final gens = ledger.gensForDay(key);
    final ops = ledger.opsForDay(key);

    final rows = <Widget>[];
    if (mode == DayDetailMode.gens) {
      for (final g in gens) {
        rows.add(
          LedgerRow(
            icon: g.inpaint ? Icons.brush_outlined : Icons.image_outlined,
            title:
                '${g.width}×${g.height}'
                '${g.steps > 0 ? ' · ${context.l10n.stepsN(g.steps)}' : ''}'
                '${g.inpaint ? ' · ${context.l10n.inpaint}' : ''}',
            sub:
                '${_hhmm(DateTime.fromMillisecondsSinceEpoch(g.ts))}'
                '${g.model.isEmpty ? '' : ' · ${modelName(g.model)}'}',
            trailing: g.pts > 0
                ? context.l10n.minusPts(fmtInt(g.pts))
                : context.l10n.free,
            trailingColor: g.pts > 0 ? scheme.primary : scheme.tertiary,
          ),
        );
      }
    } else {
      // 点数详情:计费生成 + 单笔操作,按时间倒序合并
      final merged = <({int ts, Widget row})>[
        for (final g in gens)
          if (g.pts > 0)
            (
              ts: g.ts,
              row: LedgerRow(
                icon: g.inpaint ? Icons.brush_outlined : Icons.image_outlined,
                title:
                    '${context.l10n.genSize(g.width, g.height)}'
                    '${g.steps > 0 ? ' · ${context.l10n.stepsN(g.steps)}' : ''}',
                sub: _hhmm(DateTime.fromMillisecondsSinceEpoch(g.ts)),
                trailing: context.l10n.minusPts(fmtInt(g.pts)),
              ),
            ),
        for (final o in ops)
          (
            ts: o.ts,
            row: LedgerRow(
              icon: o.type == 'upscale'
                  ? Icons.zoom_in
                  : Icons.palette_outlined,
              title: o.type == 'upscale'
                  ? context.l10n.upscale4x
                  : context.l10n.vibeEncoding,
              sub: _hhmm(DateTime.fromMillisecondsSinceEpoch(o.ts)),
              trailing: context.l10n.minusPts(fmtInt(o.pts)),
            ),
          ),
      ]..sort((a, b) => b.ts.compareTo(a.ts));
      rows.addAll(merged.map((e) => e.row));
    }

    final opsPts = ops.fold(0, (s, o) => s + o.pts);
    // 明细窗口只保留最近若干条,老日子可能只剩聚合数
    final rolled = (agg?.images ?? 0) > 0 && gens.isEmpty;

    return [
      StatsCard(
        child: Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.image_outlined,
                label: context.l10n.dayGens,
                value: fmtInt(agg?.images ?? 0),
                suffix: (agg?.free ?? 0) > 0
                    ? context.l10n.freeN(agg!.free)
                    : null,
              ),
            ),
            Expanded(
              child: StatTile(
                icon: Icons.toll_outlined,
                label: context.l10n.estimatedSpend,
                value: fmtInt((agg?.pts ?? 0) + opsPts),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      StatsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              mode == DayDetailMode.points
                  ? context.l10n.perItemSpend
                  : context.l10n.perItemGens,
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  rolled
                      ? context.l10n.detailsRolledOff
                      : context.l10n.noRecordsDay,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
              )
            else
              ...rows,
          ],
        ),
      ),
    ];
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 服务端模型 id → 展示名(`nai-diffusion-4-5-full` → `NAI 4.5 Full`)。
String modelLabel(String id) {
  final s = id.toLowerCase();
  if (!s.startsWith('nai-diffusion')) return id;
  // 5.0 用 startsWith 判:contains('5') 会误吞 4-5 系,这是唯一稳的写法。
  // 不加这行,nai-diffusion-5-* 会一路漏到 '3' 分支错标成「NAI 3 Full」。
  final ver = s.startsWith('nai-diffusion-5')
      ? '5.0'
      : s.contains('4-5')
      ? '4.5'
      : s.contains('4')
      ? '4.0'
      : '3';
  final tier = s.contains('curated')
      ? ' Curated'
      : s.contains('medium')
      ? ' Full Medium'
      : ' Full';
  return 'NAI $ver${s.contains('-3') && ver == '3' ? '' : tier}';
}

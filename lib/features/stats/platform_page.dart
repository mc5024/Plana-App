import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/store/ui_prefs.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/anlas_panel.dart' show UsageCard;
import 'stats_providers.dart';
import 'stats_widgets.dart';

/// 全平台统计二级页:共享号池额度 + 当期四指标 + 历史全局(含 V5 两项)
/// + 三张 24 小时热力图(负载/活跃人数/平均耗时)。数据与接入模式无关,
/// 但服务端要求 Bot 会话;在线人数为公开端点,无会话也显示。
class PlatformPage extends ConsumerStatefulWidget {
  const PlatformPage({super.key});

  @override
  ConsumerState<PlatformPage> createState() => _PlatformPageState();
}

class _PlatformPageState extends ConsumerState<PlatformPage> {
  /// 与统计页共用同一份记忆(见 [UiPrefs.statsRange])。
  late String _range = ref.read(uiPrefsProvider).statsRange;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(botSessionProvider).value;
    final days = rangeDays[_range] ?? 7;

    return Scaffold(
      appBar: AppBar(title: const Text('全平台统计')),
      body: session == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: const [StatsCard(child: Text('暂未开放'))],
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(platformStatsProvider);
                ref.invalidate(platformAllProvider);
                ref.invalidate(platformHourlyProvider);
                ref.invalidate(poolUsageProvider);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                children: [
                  RangeChips(
                    range: _range,
                    onChanged: (v) {
                      ref
                          .read(uiPrefsProvider.notifier)
                          .patch((p) => p.copyWith(statsRange: v));
                      setState(() => _range = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  _poolCard(context),
                  _statTiles(context),
                  const SizedBox(height: 10),
                  _allCard(context),
                  const SizedBox(height: 10),
                  HeatCard(
                    icon: Icons.stacked_line_chart,
                    title: '每日负载时段',
                    heat: ref.watch(
                      platformHourlyProvider((HourlyKind.calls, days)),
                    ),
                    peakText: (t) => '峰值 ${t.hour}:00(日均 ${fmtInt(t.avg)} 次)',
                    legend: true,
                  ),
                  const SizedBox(height: 10),
                  HeatCard(
                    icon: Icons.group_outlined,
                    title: '用户活跃时段',
                    heat: ref.watch(
                      platformHourlyProvider((HourlyKind.users, days)),
                    ),
                    peakText: (t) => '峰值 ${t.hour}:00(日均 ${fmtInt(t.avg)} 人)',
                  ),
                  const SizedBox(height: 10),
                  HeatCard(
                    icon: Icons.schedule,
                    title: '平均生成耗时',
                    heat: ref.watch(
                      platformHourlyProvider((HourlyKind.duration, days)),
                    ),
                    peakText: (t) =>
                        '最慢 ${t.hour}:00(平均 ${t.avg.toStringAsFixed(t.avg >= 10 ? 0 : 1)}s)',
                  ),
                ],
              ),
            ),
    );
  }

  /// 共享号池的 NAI 官方额度。放在最顶上:它是「全平台还能免费出多少图」的
  /// 总闸门,下面那些用量数字都受它约束,先看它才读得懂后面的。
  ///
  /// 复用创作页那张卡,两处必须长得一样(见 [UsageCard])。一个 Opus 号都没有
  /// 时服务端回 null,整块不渲染 —— 画个空电池比不画更误导。
  Widget _poolCard(BuildContext context) {
    final usage = ref.watch(poolUsageProvider).value;
    if (usage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: UsageCard(usage: usage),
    );
  }

  /// 数值格:大数一行、标签一行。
  Widget _cell(BuildContext context, String label, int? v, bool loading) =>
      Expanded(
        child: Column(
          children: [
            if (loading && v == null)
              SkeletonText(
                sample: '0,000,000',
                style: mono(context, size: 13),
                width: 46,
              )
            else
              Text(v == null ? '—' : fmtInt(v), style: mono(context, size: 13)),
            const SizedBox(height: 2),
            Text(
              label,
              style: context.texts.labelSmall!.copyWith(
                color: context.scheme.outline,
              ),
            ),
          ],
        ),
      );

  Widget _statTiles(BuildContext context) {
    final async = ref.watch(platformStatsProvider(_range));
    final st = async.value;
    final loading = async.isLoading;
    return StatsCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.image_outlined,
                  label: '生图次数',
                  value: st == null ? null : fmtInt(st.imageCalls),
                  loading: loading,
                ),
              ),
              Expanded(
                child: StatTile(
                  icon: Icons.chat_bubble_outline,
                  label: 'AI 对话',
                  value: st == null ? null : fmtInt(st.aiCalls),
                  loading: loading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.toll_outlined,
                  label: '点数消耗',
                  value: st == null ? null : fmtInt(st.pointsSpent),
                  loading: loading,
                ),
              ),
              Expanded(
                child: StatTile(
                  icon: Icons.group_outlined,
                  label: '活跃用户',
                  value: st == null ? null : fmtInt(st.activeUsers),
                  loading: loading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _allCard(BuildContext context) {
    final scheme = context.scheme;
    final async = ref.watch(platformAllProvider);
    final all = async.value;
    final since = all?.firstRecord?.split('T').first;
    Widget cell(String label, int? v) =>
        _cell(context, label, v, async.isLoading);
    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '历史全局',
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                since == null ? '' : '$since 起',
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 一律三列两行:四个一行、三个一行地混排,列宽两行对不齐,一眼看去
          // 就是歪的。宁可让「总用户」下移到第二行,也要两行同宽。
          Row(
            children: [
              cell('总生图', all?.imageCalls),
              cell('总对话', all?.aiCalls),
              cell('总消耗', all?.pointsSpent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              cell('总用户', all?.totalUsers),
              cell('V5 生图', all?.v5Calls),
              cell('V5 点数', all?.v5Points),
            ],
          ),
        ],
      ),
    );
  }
}

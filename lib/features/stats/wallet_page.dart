import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/remote_image.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show hintSnack;
import 'stats_providers.dart';
import 'stats_widgets.dart';

/// 钱包二级页(Bot):余额 + 一本流水 + 充值入口。
///
/// 2026-10-18 起服务端把原来的两本账 ——「NAI 账单」(中转按月出账)和
/// 「算力账单」(租卡 / 视频由管理员手动结算)—— 并成了一个钱包:每人一个余额,
/// 消费成功就实时扣、可以扣成负数,充值由管理员登记。所以这页没有账期、
/// 结算日、支付状态,只有余额和流水。
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

/// 流水筛选:服务端的 `kind` → 胶囊上的字。
const _kFilters = {'all': '全部', 'charge': '扣款', 'credit': '充值'};

class _WalletPageState extends ConsumerState<WalletPage> {
  /// 每页笔数。一张中转图就是一笔,50 笔大约两三屏。
  static const _kPage = 50;

  final _scroll = ScrollController();

  String _kind = 'all';
  List<WalletEntry> _items = const [];

  /// 下一页游标;null = 到底了。
  String? _cursor;

  /// 第一页回来过没有(成功失败都算)—— 分清「还在拉」和「真的没有」。
  bool _loaded = false;
  bool _loading = false;

  /// 上一次请求失败了。续页失败后不再跟着滚动自动重试(滚一下就发一次),
  /// 改由列表尾的按钮手点。
  bool _failed = false;

  /// 发号作废:换筛选 / 下拉刷新时自增,慢一拍回来的旧请求对不上号就整个丢掉,
  /// 不然旧筛选的那一页会混进新列表里。
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 放到首帧之后:_load 一上来就 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_failed && _scroll.position.extentAfter < 400) _load(reset: false);
  }

  /// 拉一页。[reset] = 从第一页重来(进页、换筛选、下拉刷新),否则续下一页。
  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _cursor == null)) return;
    final seq = ++_seq;
    // 游标属于产出它的那个筛选:续页用发请求那一刻的快照
    final kind = _kind;
    final cursor = reset ? null : _cursor;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final session = await ref.read(botSessionProvider.future);
      if (session == null) throw StateError('未授权');
      final page = await ref
          .read(backendClientProvider)
          .walletLedger(
            session.sessionId,
            limit: _kPage,
            cursor: cursor,
            kind: kind,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        // 空页还带游标不该出现;真遇上就当到底,免得滚动监听对着空页一直翻
        _cursor = page.items.isEmpty ? null : page.nextCursor;
        _loading = false;
        _loaded = true;
      });
      _fillIfShort();
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _loaded = true;
        _failed = true;
      });
    }
  }

  /// 一页没铺满一屏(平板,或筛出来的笔数少)时滚动监听不会触发,
  /// 每页落地后补判一次,有下一页就接着翻。
  void _fillIfShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.extentAfter < 400) _load(reset: false);
    });
  }

  void _setKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _items = const [];
      _cursor = null;
      _loaded = false;
    });
    _load(reset: true);
  }

  /// 下拉刷新:余额和流水一起重拉。旧列表留到新的一页回来再换,不闪空。
  Future<void> _refresh() async {
    final summary = ref.refresh(walletSummaryProvider.future);
    await _load(reset: true);
    await summary;
  }

  void _showTopUp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TopUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final summary = ref.watch(walletSummaryProvider);
    final w = summary.value;
    final cats = [
      for (final c in w?.categories ?? const <WalletCategory>[])
        if (c.amountFen > 0) c,
    ];
    final showList = _loaded && _items.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('钱包')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          // 带了 controller 就不再是 primary,不显式给的话内容不满一屏时拉不动刷新
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              sliver: SliverToBoxAdapter(
                child: _BalanceCard(summary: summary, onTopUp: _showTopUp),
              ),
            ),
            if (cats.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                sliver: SliverToBoxAdapter(
                  child: _CategoryCard(categories: cats, owing: w!.owing),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              // 流水可以很长,行要懒建;卡片底色交给 DecoratedSliver 整块画,
              // 拆成一行一个色块的话,小数像素的接缝处会透出细线
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: context.edgeBorder,
                ),
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(child: _listHeader(context)),
                      if (showList) ...[
                        SliverList.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) =>
                              WalletEntryRow(entry: _items[i]),
                        ),
                        SliverToBoxAdapter(
                          child: _listFooter(context, summary.value),
                        ),
                      ] else
                        SliverToBoxAdapter(child: _listState(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        Text(
          '流水',
          style: context.texts.bodyMedium!.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _KindSeg(kind: _kind, onChanged: _setKind),
      ],
    ),
  );

  /// 列表还没有行时那一块:骨架 / 拉不到 / 真的没有。
  Widget _listState(BuildContext context) {
    final scheme = context.scheme;
    // 失败后点重试的那一趟也走骨架,别先闪一下「还没有流水」
    if (!_loaded || _loading) {
      // 骨架行与 LedgerRow 等高(图标 30 + 上下各 7),数据到位不跳版
      return Column(
        children: [
          for (var i = 0; i < 4; i++)
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
        ],
      );
    }
    final hint = context.texts.bodySmall!.copyWith(color: scheme.outline);
    if (_failed) {
      return Row(
        children: [
          Expanded(child: Text('流水暂时查不到', style: hint)),
          TextButton(
            onPressed: () => _load(reset: true),
            child: const Text('重试'),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(switch (_kind) {
        'charge' => '还没有扣款记录',
        'credit' => '还没有充值记录',
        _ => '还没有流水',
      }, style: hint),
    );
  }

  /// 列表尾:加载中转圈;续页失败给重试;还有下一页给个手点入口(列表短到
  /// 滚不动时的退路);到底了说一声,顺带写上流水从哪天开始。
  Widget _listFooter(BuildContext context, WalletSummary? summary) {
    final scheme = context.scheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed || _cursor != null) {
      return Center(
        child: TextButton(
          // 没有游标还失败了,只能是下拉刷新那一趟没成 —— 那就从第一页重来
          onPressed: () => _load(reset: _cursor == null),
          child: Text(_failed ? '加载失败,点此重试' : '加载更多'),
        ),
      );
    }
    final from = summary?.startFrom ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        from.isEmpty ? '没有更多了' : '没有更多了 · 流水从 $from 开始',
        textAlign: TextAlign.center,
        style: context.texts.labelSmall!.copyWith(color: scheme.outline),
      ),
    );
  }
}

/// 余额卡:大号余额 + 充值入口,下接累计扣款 / 充值,有在跑的租卡再补一行。
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary, required this.onTopUp});

  final AsyncValue<WalletSummary?> summary;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final w = summary.value;
    final loading = summary.isLoading && w == null;
    final owing = w?.owing ?? false;
    final big = mono(
      context,
      size: 30,
      weight: FontWeight.w700,
      color: owing ? scheme.error : null,
    );
    final btnStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 14),
    );
    const btnIcon = Icon(Icons.qr_code_2, size: 16);
    const btnLabel = Text('充值');

    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '余额',
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 欠着钱时换成实心按钮:这时候充值是这页最要紧的事
              if (owing)
                FilledButton.icon(
                  onPressed: onTopUp,
                  icon: btnIcon,
                  label: btnLabel,
                  style: btnStyle,
                )
              else
                FilledButton.tonalIcon(
                  onPressed: onTopUp,
                  icon: btnIcon,
                  label: btnLabel,
                  style: btnStyle,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            SkeletonText(sample: '¥000.00', style: big, width: 112)
          else if (w == null)
            Text(
              '余额暂时查不到,下拉重试',
              style: context.texts.bodyMedium!.copyWith(color: scheme.outline),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(fmtFen(w.balanceFen, sign: false), style: big),
                if (owing) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '余额为负,请充值',
                      style: context.texts.labelMedium!.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          const CardDivider(),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.remove_circle_outline,
                  label: '累计扣款',
                  value: w == null ? null : fmtFen(w.chargedFen, sign: false),
                  loading: loading,
                ),
              ),
              Expanded(
                child: StatTile(
                  icon: Icons.add_circle_outline,
                  label: '累计充值',
                  value: w == null ? null : fmtFen(w.creditedFen, sign: false),
                  loading: loading,
                ),
              ),
            ],
          ),
          // 在跑的租卡关机时才扣,还不在余额里 —— 不提一句,关机那一下余额
          // 突然掉一截,用户会以为扣错了
          if (w != null && w.pendingRentalCount > 0) ...[
            const CardDivider(),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '租卡进行中'
                    '${w.pendingRentalCount > 1 ? '(${w.pendingRentalCount} 台)' : ''}'
                    ' ${fmtFen(w.pendingRentalFen, sign: false)},关机时扣',
                    style: context.texts.bodySmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 消费构成:扣款按类目汇总,花得多的在前,每类一条占比条;
/// 欠着钱时标题换成「欠费集中在」。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.categories, required this.owing});

  final List<WalletCategory> categories;
  final bool owing;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final pcts = sharePercents([for (final c in categories) c.amountFen]);
    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_outline,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                owing ? '欠费集中在' : '消费构成',
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          for (var i = 0; i < categories.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _CategoryRow(category: categories[i], pct: pcts[i]),
            ),
        ],
      ),
    );
  }
}

/// 一个类目:标题 · 笔数 … 金额 占比,下接占比条。
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.pct});

  final WalletCategory category;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final c = category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                c.title.isNotEmpty ? c.title : '其他',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${c.count} 笔',
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
            const Spacer(),
            Text(
              fmtFen(c.amountFen, sign: false),
              style: mono(context, size: 12, weight: FontWeight.w600),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$pct%',
                textAlign: TextAlign.right,
                style: mono(context, size: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Container(
          height: 6,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            // 太小的类目也留一截看得见的条
            widthFactor: (pct < 2 ? 2 : pct) / 100,
            heightFactor: 1,
            child: ColoredBox(
              color: c.kind == 'adjust' ? scheme.error : scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 全部 / 扣款 / 充值 切换胶囊。
class _KindSeg extends StatelessWidget {
  const _KindSeg({required this.kind, required this.onChanged});

  final String kind;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    Widget seg(String k, String label) {
      final on = kind == k;
      return Material(
        color: on ? context.selectedFill : Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: context.texts.labelSmall!.copyWith(
                color: on ? context.onSelectedFill : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final e in _kFilters.entries) seg(e.key, e.value)],
      ),
    );
  }
}

/// 一笔钱包流水:图标(按类型)+ 标题 / 时间 · 说明 + 金额。
/// 钱包页和统计里「某一天」的明细共用。
class WalletEntryRow extends StatelessWidget {
  const WalletEntryRow({super.key, required this.entry, this.withDate = true});

  final WalletEntry entry;

  /// 时间带不带日期。同一天的列表里(某日明细)只写时分。
  final bool withDate;

  static IconData _iconOf(String kind) => switch (kind) {
    'nai' => Icons.image_outlined,
    'video' => Icons.movie_outlined,
    'rental' => Icons.developer_board,
    'topup' => Icons.account_balance_wallet_outlined,
    'adjust' => Icons.edit_note,
    _ => Icons.receipt_long_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final e = entry;
    return LedgerRow(
      icon: _iconOf(e.kind),
      iconColor: e.isCredit ? scheme.tertiary : null,
      title: e.title.isNotEmpty ? e.title : (e.isCredit ? '入账' : '扣款'),
      sub: [
        withDate ? e.shortTime : e.clock,
        if (e.note.isNotEmpty) e.note,
      ].join(' · '),
      trailing: fmtFen(e.amountFen),
      // 入账用正向色;扣款是常态,用正文色 —— 满屏红字反而看不出哪笔要紧
      trailingColor: e.isCredit ? scheme.tertiary : scheme.onSurface,
    );
  }
}

/// 充值:微信 / 支付宝收款码。转账后由管理员手动入账,App 这边不经手钱。
class _TopUpSheet extends ConsumerStatefulWidget {
  const _TopUpSheet();

  @override
  ConsumerState<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<_TopUpSheet> {
  String _type = 'wechat';
  bool _saving = false;

  /// 收款码原图存相册。字节取显示时落下的那份缓存,和屏幕上的是同一张。
  Future<void> _save(String url) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok = await Gal.hasAccess() || await Gal.requestAccess();
      if (!ok) {
        if (mounted) hintSnack(context, '未获相册权限', icon: Icons.error_outline);
        return;
      }
      final bytes = await fetchRemoteImageBytes(url);
      await Gal.putImageBytes(bytes, name: 'plana_payment_qr_$_type');
      if (mounted) {
        hintSnack(context, '已保存到相册', icon: Icons.check_circle_outline);
      }
    } catch (_) {
      if (mounted) hintSnack(context, '保存失败', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final url = ref.watch(backendClientProvider).paymentQrUrl(_type);
    Widget box(Widget child) => Container(
      width: 240,
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '充值',
            style: context.texts.titleSmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'wechat', label: Text('微信')),
              ButtonSegment(value: 'alipay', label: Text('支付宝')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          // 保存按钮跟着码一起出:码加载出来才有,待配置时不出
          Center(
            child: RemoteImage(
              url,
              key: ValueKey(url),
              fit: BoxFit.contain,
              decodeWidth: 240,
              frameBuilder: (context, child, frame, _) => frame == null
                  ? box(
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 码垫白底:透明底的二维码放在深色主题上扫不出来
                        box(
                          ColoredBox(
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: child,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _saving ? null : () => _save(url),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('保存到相册'),
                        ),
                      ],
                    ),
              errorBuilder: (context, _, _) => box(
                Center(
                  child: Text(
                    '收款码待配置',
                    style: context.texts.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '扫码转账后联系管理员入账',
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/auth/nai_keys.dart';
import '../../core/net/nai_client.dart';
import '../../core/net/nai_key_status.dart';
import '../../core/net/nai_proxy.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart'
    show confirmDialog, hintSnack, sharedAxisRoute;
import '../stats/stats_providers.dart' show fmtInt;
import 'bot_auth_panel.dart';
import 'token_manage_page.dart';
import '../../core/util/haptics.dart';

/// 账号与接入(我的页二级):接入方式切换、Token / Bot 凭据、直连代理、标签补全来源。
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  void _openTokens() =>
      Navigator.of(context).push(sharedAxisRoute(const TokenManagePage()));

  Future<void> _makePrimary(String id) async {
    await ref.read(naiKeysStoreProvider.notifier).makePrimary(id);
    if (mounted) Haptics.selection();
  }

  Future<void> _selectMode(AuthMode m) async {
    if (m == ref.read(authModeProvider).value) return;
    await ref.read(authModeProvider.notifier).set(m);
  }

  Future<void> _revokeBot() async {
    final ok = await confirmDialog(
      context,
      title: '解除 Bot 授权',
      message: '将从本机删除会话,需重新授权才能用后端生成。',
      confirmLabel: '解除',
    );
    if (!ok) return;
    await ref.read(botSessionProvider.notifier).clear();
    if (!mounted) return;
    Haptics.medium();
    hintSnack(context, '已解除授权', icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(naiKeysStoreProvider).value ?? const <NaiKey>[];
    final hasSaved = keys.isNotEmpty;

    final mode = ref.watch(authModeProvider).value ?? AuthMode.token;
    final session = ref.watch(botSessionProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('账号与接入')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          // 两者不是二选一:Token 与 Bot 授权各自独立配置,都可以同时存在。
          // 顶部这张只决定「付费操作走哪条路」,不再决定下面显示哪张卡。
          _RouteCard(
            mode: mode,
            onSelect: _selectMode,
            tokenReady: hasSaved,
            botReady: session != null,
          ),
          const SizedBox(height: 12),
          _TokenCard(
            keys: keys,
            onPrimary: _makePrimary,
            onManage: _openTokens,
          ),
          const SizedBox(height: 12),
          _ProxyCard(
            on: ref.watch(naiProxyProvider),
            onChanged: (v) => ref.read(naiProxyProvider.notifier).set(v),
          ),
          const SizedBox(height: 12),
          _BotCard(session: session, onRevoke: _revokeBot),
        ],
      ),
    );
  }
}

/// 「账号与接入」里的 Token 卡:参与生成的令牌一块一块摆出来(一行两块,
/// 点哪块哪块就是主账号)、左下角是这几个号加起来的点数与额度、
/// 右下角进[TokenManagePage]。
///
/// 这里**没有接口地址**:地址跟着每把令牌走(见 [NaiKey.endpoint]),在
/// [TokenManagePage] 的「添加令牌 → 第三方」里和 key 一起填。
///
/// 只摆**真会被用到**的:这一块回答的是「现在直连拿哪几个号在跑」,没勾并发
/// 生成的属于管理范畴,归二级页。细节(完整读数、单项开关、增删)也全在二级页。
///
/// 最多摆 [_kQuickSwitchMax] 块:这张卡是「随手换个号」,不是号池的全景。
class _TokenCard extends StatelessWidget {
  const _TokenCard({
    required this.keys,
    required this.onPrimary,
    required this.onManage,
  });

  /// 已存的全部 Key(含没参与生成的;下面只摆参与的那几块)。
  final List<NaiKey> keys;

  /// 换主账号(圆钮选中了谁)。
  final ValueChanged<String> onPrimary;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 摆出来的就是**真会被用到**的:主账号恒在,副账号勾了任一个参与条件才算。
    final on = [
      for (final k in keys)
        if (k.joins) k,
    ];
    final shown = _quickSwitchSlice(on);

    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'NovelAI Token',
                    style: context.texts.labelMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _StatusChip(saved: on.isNotEmpty, onLabel: '${on.length} 账号'),
                ],
              ),
              const SizedBox(height: 12),
              if (on.isEmpty)
                Text(
                  keys.isEmpty
                      ? '直连生成需要你自己的 NovelAI 令牌,仅加密存储在本机'
                      : '存了 ${keys.length} 把,但一把都没参与生成',
                  style: context.texts.labelSmall!.copyWith(
                    color: keys.isEmpty ? scheme.outline : scheme.error,
                  ),
                )
              else
                // 圆钮在这儿也能换主账号 —— 不必为了换个号专门进二级页。
                // 分组套在整片外面,每块只报自己的 id(同令牌管理页)。
                RadioGroup<String>(
                  groupValue: naiPrimaryKey(keys)?.id,
                  onChanged: (id) {
                    if (id != null) onPrimary(id);
                  },
                  child: Column(
                    children: [
                      // 一行两块:一块只写名字(或尾号)+ 档位,认得出是谁就够了。
                      // 更细的读数在二级页,这里挤三块就只剩省略号了。
                      for (var i = 0; i < shown.length; i += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _KeyChipTile(
                                  k: shown[i],
                                  onTap: () => onPrimary(shown[i].id),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: i + 1 < shown.length
                                    ? _KeyChipTile(
                                        k: shown[i + 1],
                                        onTap: () => onPrimary(shown[i + 1].id),
                                      )
                                    // 奇数个时留空占位,免得最后那块拉成整行宽
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  // 左下角是这几个号**加起来**的家底:单个号的读数在二级页,
                  // 这里要回答的是「直连这条路现在总共还剩多少」。
                  Expanded(child: _TotalsLine(keys: on)),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.tune, size: 17),
                    label: const Text('管理令牌'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 代理开关:官方那几把改经 Plana 的 Worker 转发(见 `kNaiProxyBase`),
/// 手机够不着 NovelAI 时开。第三方的 key 不受影响。
///
/// 单独一张而不塞进上面的 Token 卡:那张只摆号不摆地址,这个开关也不属于
/// 哪一把 Key。
class _ProxyCard extends StatelessWidget {
  const _ProxyCard({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: context.scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          value: on,
          onChanged: onChanged,
          title: Text(
            '代理访问 NovelAI',
            style: context.texts.bodyMedium!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            kNaiProxyHint,
            style: context.texts.labelSmall!.copyWith(
              color: context.scheme.outline,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
        ),
      ),
    );
  }
}

/// 账号页这张卡最多摆几块。存得下十几把,但这里是「随手换个号」的地方:
/// 一行两块,再多就把生成方式、Bot、补全那几张卡全顶到屏外了。看全的、
/// 调顺序的、增删的都在[TokenManagePage]。
const _kQuickSwitchMax = 6;

/// 摆哪几块:按令牌管理页里的顺序取前 [_kQuickSwitchMax] 个 —— 常用的自己拖到
/// 前面去。**主账号一定在里面**:它排在第七往后时顶掉末位那块,不然这片圆钮
/// 一个都不亮,看着就是「没选中任何账号」。
List<NaiKey> _quickSwitchSlice(List<NaiKey> on) {
  if (on.length <= _kQuickSwitchMax) return on;
  final head = on.take(_kQuickSwitchMax).toList();
  final at = on.indexWhere((k) => k.primary);
  // at < 0 也走这支:一把都没认领主账号时本来就没有圆钮该亮,不必顶谁。
  if (at < _kQuickSwitchMax) return head;
  return [...head.take(_kQuickSwitchMax - 1), on[at]];
}

/// 参与生成的这几个号**加起来**的点数与额度 —— 只算 app 真会动用的那部分:
/// 点数只加勾了「参与点数生成」的号,额度只加勾了「参与免费生成」的号。只参与
/// 免费生成的号,它的点数一分都不会被花,算进来就是虚数。
///
/// 额度按**相加**算(两个号各 87% / 50% → 137%),不是取平均:平均水位看着像
/// 单号的电量,跟「一共还能出多少张」对不上 —— 这套口径与 [NaiUsageX.batteryPct]
/// 一致(那边给 bot 的号池用的也是相加)。
///
/// 还没查到的号不计入,所以查询过程中数字是**往上长**的,不会先给个偏小的定值。
class _TotalsLine extends ConsumerWidget {
  const _TotalsLine({required this.keys});

  final List<NaiKey> keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final small = context.texts.labelSmall!;
    if (keys.isEmpty) return const SizedBox.shrink();

    var anlas = 0;
    var pct = 0.0;
    var got = 0;
    var hasUsage = false;
    for (final k in keys) {
      final sub = ref.watch(naiKeyStatusProvider(naiTargetOf(k))).value;
      if (sub == null) continue;
      got++;
      if (k.joinPaid) anlas += sub.anlas;
      final u = sub.usage;
      if (u != null && k.joinFree) {
        hasUsage = true;
        pct += u.batteryPct;
      }
    }
    if (got == 0) {
      return Text('查询账户状态…', style: small.copyWith(color: scheme.outline));
    }
    return Text(
      [
        'Anlas ${fmtInt(anlas)}',
        // 额度只有拿得到才写:官方没承诺过这块字段,读不到就干脆不提。
        if (hasUsage) '额度 ${pct.round()}%',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: small.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 一块令牌缩略:圆钮 + 名字/尾号 + 档位。**整块可点**,点了就换主账号 ——
/// 圆钮本身只有二十来像素,单指点它容易落空。
class _KeyChipTile extends ConsumerWidget {
  const _KeyChipTile({required this.k, required this.onTap});

  final NaiKey k;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final named = k.label.trim().isNotEmpty;
    final tier = ref.watch(naiKeyStatusProvider(naiTargetOf(k))).value;
    final onSel = context.onSolidFill(scheme.onPrimaryContainer);
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standard,
      decoration: BoxDecoration(
        color: k.primary
            ? context.solidFill(scheme.primaryContainer)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
        // 描边两态同宽,只变色 —— 变宽度会让两列跟着抖。
        border: Border.all(
          color: k.primary ? scheme.primary : Colors.transparent,
        ),
      ),
      // 内边距在 InkWell **里面**:搁在外层 AnimatedContainer 上的话,水波只
      // 铺到内容区,右边那截 padding 落在水波之外 —— 看着就是「按下去比色块小
      // 一圈」。圆角也跟外层对齐(11),不然水波的角会切在色块角里面。
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: k.primary ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 10, 3),
            child: Row(
              children: [
                // 圆钮不接手势:点在它上面时只出一小圈水波,和点别处不是一个反馈。
                IgnorePointer(
                  child: Radio<String>(
                    value: k.id,
                    fillColor: k.primary && context.skin.float
                        ? WidgetStatePropertyAll(onSel)
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    naiKeyTitle(k),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: named
                        ? context.texts.labelMedium!.copyWith(
                            fontWeight: FontWeight.w600,
                            color: k.primary ? onSel : null,
                          )
                        : mono(
                            context,
                            size: 11.5,
                          ).copyWith(color: k.primary ? onSel : null),
                  ),
                ),
                // 档位查到了才写:查询中/失败时这块留空,不占位、不闪动。
                if (tier != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    naiTierName(tier.tier),
                    style: context.texts.labelSmall!.copyWith(
                      color: k.primary
                          ? onSel.withValues(alpha: .8)
                          : scheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.saved,
    this.onLabel = '已保存',
    this.offLabel = '未设置',
  });

  final bool saved;
  final String onLabel;
  final String offLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final Color bg = saved
        ? context.solidFill(scheme.primaryContainer)
        : scheme.surfaceContainerHighest;
    final Color fg = saved
        ? context.onSolidFill(scheme.onPrimaryContainer)
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            saved ? Icons.check_circle : Icons.error_outline,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            saved ? onLabel : offLabel,
            style: context.texts.labelMedium!.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 生成方式卡:生成 / 放大 / Vibe 编码这些**消耗 Anlas** 的操作走哪条路。
/// 只有这类操作是二选一(一次请求只能由一个账号执行);公共库、云备份、
/// 增强补全等纯后端功能只看有没有 Bot 会话,与这里的选择无关。
class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.mode,
    required this.onSelect,
    required this.tokenReady,
    required this.botReady,
  });

  final AuthMode mode;
  final ValueChanged<AuthMode> onSelect;
  final bool tokenReady;
  final bool botReady;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 选中的那条路没配凭据 → 现在根本生成不了,必须说破
    final missing = mode == AuthMode.token ? !tokenReady : !botReady;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '生成方式',
                style: context.texts.labelMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AuthMode>(
                  segments: const [
                    ButtonSegment(
                      value: AuthMode.token,
                      label: Text('直连 Token'),
                      icon: Icon(Icons.vpn_key, size: 16),
                    ),
                    ButtonSegment(
                      value: AuthMode.bot,
                      label: Text('使用 Bot 账户'),
                      icon: Icon(Icons.smart_toy_outlined, size: 16),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => onSelect(s.first),
                  showSelectedIcon: false,
                ),
              ),
              const SizedBox(height: 10),
              // 缺凭据的警告直接顶替常驻说明的位置(同一行槽,高度不变)
              Text(
                missing
                    ? (mode == AuthMode.token
                          ? '尚未保存 Token,当前无法生成'
                          : '尚未授权 Bot,当前无法生成')
                    : (mode == AuthMode.token
                          ? '使用你的 NovelAI 账户生成图片'
                          : '使用 Bot 账户生成图片,费用从钱包扣除'),
                style: context.texts.labelSmall!.copyWith(
                  color: missing ? scheme.error : scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bot 授权卡:显示会话归属/有效期;卡内直接取码授权([BotAuthPanel]),
/// 已授权时提供 重新授权 / 解除授权。
class _BotCard extends StatelessWidget {
  const _BotCard({required this.session, required this.onRevoke});

  final BotSession? session;
  final VoidCallback onRevoke;

  static const _spinner = SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  static String _fmtExpiry(int? ms) {
    if (ms == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final s = session;
    final authorized = s != null;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Bot 授权',
                    style: context.texts.labelMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _StatusChip(
                    saved: authorized,
                    onLabel: '已授权',
                    offLabel: '未授权',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (authorized) ...[
                _row(context, '账号', s.botUserId ?? '—'),
                const SizedBox(height: 8),
                _row(context, '有效期至', _fmtExpiry(s.expiresAtMs)),
                const SizedBox(height: 16),
              ],
              // 固定在末位并带 key:授权成功切到已授权布局时,面板状态不丢
              BotAuthPanel(
                key: const ValueKey('bot-auth'),
                idleBuilder: (start, loading) => authorized
                    ? Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: start,
                            icon: loading
                                ? _spinner
                                : const Icon(Icons.refresh, size: 18),
                            label: const Text('重新授权'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: onRevoke,
                            icon: Icon(
                              Icons.link_off,
                              size: 18,
                              color: scheme.error,
                            ),
                            label: Text(
                              '解除授权',
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                        ],
                      )
                    : FilledButton.icon(
                        onPressed: start,
                        icon: loading
                            ? _spinner
                            : const Icon(Icons.smart_toy_outlined, size: 18),
                        label: const Text('获取授权码'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = context.scheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: context.texts.bodyMedium!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

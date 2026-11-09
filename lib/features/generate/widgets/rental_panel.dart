import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../gpu_rental.dart';
import 'common.dart' show hintSnack;
import 'top_bar_status.dart';

/// 算力来源:模型弹层里 Anima / Krea 两页共用的那一块,以及顶栏那枚状态胶囊。
///
/// 「一个实例同时服务两家模型」这件事在结构上看不出来(型号还是按厂商分页),
/// 只能靠这一块把它说清楚:两页放的是**同一个**控件、同一份状态,再配一行
/// 「Anima 与 Krea 2 共用同一实例」。

/// 每秒滴答:运行中的计时与费用要走字。只有实例活着时才建,别让空闲页面白刷。
final _tickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().millisecondsSinceEpoch,
  ).map((v) => v),
);

int _now() => DateTime.now().millisecondsSinceEpoch;

/// 模型弹层标题行右侧那枚算力来源胶囊:报当前通道与实例状态,点开才是配置。
///
/// 位置换过两轮 —— 整块摆列表顶上会把 0.7 屏高的弹层吃掉一半;收成一行钉页脚
/// 又占着列表的底边。最后落在标题行:那一行本来就存在、右侧一直空着,
/// **列表的可用高度一点没少**,而状态照样一眼可见。
class RentalSourceChip extends ConsumerWidget {
  const RentalSourceChip({super.key, this.height = 32, this.compact = false});

  /// 弹层标题行的胶囊高度；compact 模式由融合顶栏统一约束。
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final prefs = ref.watch(rentalPrefsProvider).value ?? const RentalPrefs();
    final s = ref.watch(gpuRentalProvider);
    final rented = prefs.channel == ModalChannel.rented;
    // 实例活着时读数每秒走字;没活着就别订阅那个心跳
    final now = s.active ? (ref.watch(_tickProvider).value ?? _now()) : 0;

    // 标题行装不下长句:只留最要紧的那一段(跑了多久 / 花了多少),
    // 完整状态在点开的弹层里
    final String value = switch (s.status) {
      RentalStatus.creating => '启动中',
      RentalStatus.ready =>
        '${fmtUptime(s.elapsedAt(now))} · ${fmtYuan(s.priceAt(now))}',
      RentalStatus.ending => '关机中',
      RentalStatus.failed => '开机失败',
      RentalStatus.none => rented ? '独享 · 未启动' : '免费共享',
    };
    // 在跑的时候**只有那个点是彩的**,底色和字都照常。
    // 这枚胶囊常驻顶栏,底色一染就成了长期挂在那儿的装饰色块,喧宾夺主;
    // 一个点足够说明"有台机器在烧钱"了。彩色留给真正需要抢注意的失败态。
    final failed = s.status == RentalStatus.failed;
    final fg = failed ? scheme.error : scheme.onSurfaceVariant;

    if (compact) {
      return TopBarStatus(
        tooltip: '算力与费用',
        // 没开机时只报一句:共享通道「免费共享」,独享通道「未启动」(图标已分开两条线)
        value: s.status == RentalStatus.ready
            ? fmtUptime(s.elapsedAt(now))
            : switch (s.status) {
                RentalStatus.none => rented ? '未启动' : '免费共享',
                _ => value,
              },
        detail: s.status == RentalStatus.ready
            ? fmtYuan(s.priceAt(now))
            : switch (s.status) {
                RentalStatus.none => null,
                RentalStatus.failed => '查看详情',
                _ => '独享算力',
              },
        icon: failed
            ? Icons.error_outline
            : (s.active || rented ? Icons.memory : Icons.groups_outlined),
        valueColor: failed || s.active
            ? (failed ? scheme.error : scheme.primary)
            : fg,
        onTap: () => showRentalSheet(context),
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(height / 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showRentalSheet(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(height >= 40 ? 13 : 10, 0, 6, 0),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.active)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Icon(
                    failed
                        ? Icons.error_outline
                        : (rented ? Icons.memory : Icons.groups_outlined),
                    size: 15,
                    color: fg,
                  ),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: s.status == RentalStatus.ready
                      ? mono(
                          context,
                          size: 12,
                          weight: FontWeight.w700,
                        ).copyWith(color: fg)
                      : context.texts.labelMedium!.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                ),
                Icon(Icons.expand_more, size: 17, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 算力来源整块(分段 + 独享时的配置/运行卡)。只在弹层里出现。
class RentalSourceBlock extends ConsumerWidget {
  const RentalSourceBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final prefs = ref.watch(rentalPrefsProvider).value ?? const RentalPrefs();
    final rental = ref.watch(gpuRentalProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Anima 与 Krea 2 共用同一实例',
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
        ),
        // 实例在跑时锁在「独享」上,免费那段置灰:切档不该顺手把用户正在付费的
        // 机器关掉,关机只有下面「关机并结账」那一个入口(web 同款规则)。
        // 顺带这也让开关不再可能说谎 —— 显示的档位恒等于真实分流去向。
        _ChannelToggle(
          channel: rental.active ? ModalChannel.rented : prefs.channel,
          lockFree: rental.active,
          onChanged: (c) {
            Haptics.selection();
            ref
                .read(rentalPrefsProvider.notifier)
                .patch((p) => p.copyWith(channel: c));
          },
        ),
        const SizedBox(height: 10),
        // 两侧各有一张卡,切换时高度差只剩配置项那几行,不再是「一整块有无」;
        // 剩下那点差由 AnimatedSize 走完,弹层跟着长/收,不跳。
        // 实例卡在通道切回免费时**也留着** —— 切通道不等于机器停了,那台还在
        // 烧钱,关机入口不能跟着藏起来。
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: prefs.channel == ModalChannel.rented || rental.active
              ? const RentalCard()
              : const _FreeCard(),
        ),
      ],
    );
  }
}

/// 免费共享那一侧的卡。留着它一半是为了说清「免费=排队」,
/// 一半是为了让两个通道的卡高度接近 —— 一侧有卡一侧空着,切换时弹层会整块蹦。
class _FreeCard extends StatelessWidget {
  const _FreeCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_outlined,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '共享队列',
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '不计费',
                style: mono(context, size: 13, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '免费公共算力池,不稳定,生成较慢。',
            style: context.texts.labelSmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 免费共享 / 独享实例 的分段控件。
class _ChannelToggle extends StatelessWidget {
  const _ChannelToggle({
    required this.channel,
    required this.onChanged,
    this.lockFree = false,
  });

  final ModalChannel channel;
  final ValueChanged<ModalChannel> onChanged;

  /// 锁住「免费共享」那一段(实例在跑时):置灰且点不动。
  final bool lockFree;

  static const _h = 40.0;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      height: _h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_h / 2),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final segW = c.maxWidth / 2;
          return Stack(
            // Stack 默认 topStart:非定位子节点拿宽松约束,那个 Row 只有文字
            // 自身的高度、被顶在内容框顶上(滑块因为写了显式高度才看着正常)。
            alignment: Alignment.center,
            children: [
              AnimatedAlign(
                duration: Motion.medium,
                curve: Motion.emphasized,
                alignment: channel == ModalChannel.free
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  width: segW,
                  height: _h - 6,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular((_h - 6) / 2),
                  ),
                ),
              ),
              Row(
                children: [
                  _seg(
                    context,
                    '免费共享',
                    Icons.groups_outlined,
                    channel == ModalChannel.free,
                    () => onChanged(ModalChannel.free),
                    locked: lockFree,
                  ),
                  _seg(
                    context,
                    '独享实例',
                    Icons.memory,
                    channel == ModalChannel.rented,
                    () => onChanged(ModalChannel.rented),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _seg(
    BuildContext context,
    String label,
    IconData icon,
    bool active,
    VoidCallback onTap, {
    bool locked = false,
  }) {
    final scheme = context.scheme;
    final fg = locked
        ? scheme.outlineVariant
        : (active ? scheme.onPrimary : scheme.onSurfaceVariant);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked ? null : onTap,
        // 撑满滑块那么高:一来文字自然居中,二来整段都可点 ——
        // 不写高度的话可点区域只有文字那一截,边上按不动
        child: SizedBox(
          height: _h - 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 实例卡:未启动时是配置(机型 / 空闲关机 / 启动),运行中是状态(计时 / 费用 / 关机)。
class RentalCard extends ConsumerWidget {
  const RentalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final s = ref.watch(gpuRentalProvider);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        // 卡框不跟着状态变色:在跑这件事由里面那个点说,一处一说。
        // 描边一染色,整张卡就成了个常驻的高亮块,而它下面还压着模型列表。
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 路由没接通时,开机等于白花钱。这条摆在卡最上面、两种状态都出:
          // 开机前拦一道(别开),开机后交代清楚(这台没在被用)。
          if (!kRentalRoutingReady && s.authed) ...[
            _routingWarning(context),
            const SizedBox(height: 10),
          ],
          switch (s) {
            // 端点全要 Bot 会话,没会话时连状态都问不到 —— 先说清为什么
            RentalState(authed: false) => const _RentalNoAuth(),
            RentalState(status: RentalStatus.failed) => const _RentalFailed(),
            RentalState(status: RentalStatus.none) => const _RentalConfig(),
            _ => const _RentalRunning(),
          },
        ],
      ),
    );
  }

  Widget _routingWarning(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '生成路由尚未接通:出图仍走免费共享队列,'
              '这台机器不会被使用 —— 现在开机只会白付租金。',
              style: context.texts.labelSmall!.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// 未启动:机型 + 空闲关机 + 启动。
class _RentalConfig extends ConsumerStatefulWidget {
  const _RentalConfig();

  @override
  ConsumerState<_RentalConfig> createState() => _RentalConfigState();
}

class _RentalConfigState extends ConsumerState<_RentalConfig> {
  /// 这一单开几台。**刻意不进偏好**:档位是「我惯用哪种卡」,台数是
  /// 「这회要几台」—— 后者存下来的话,下次打开面板会顶着上次那个 4,
  /// 一按就是四台的钱,而按之前界面上没有任何东西提醒你它还记着。
  /// 每次重开面板都从 1 起。
  int _count = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final s = ref.watch(gpuRentalProvider);
    final prefs = ref.watch(rentalPrefsProvider).value ?? const RentalPrefs();
    // 用户存的档位可能不在服务端当前的清单里(服务端改过 choices):落回服务端默认
    final idle = s.idleChoices.contains(prefs.idleSeconds)
        ? prefs.idleSeconds
        : s.idleDefault;
    // 用户存的档位可能已经不在服务端清单里(改过 IMG_TIERS):退回默认档 ——
    // 显示的必须是真会开出来的那一档,服务端对不认识的键就是静默回落。
    final tier = s.resolveTier(prefs.tier);
    // 老服务端不下发 tiers,那时候只有一种机型,还原成原来的只读行。
    final pickable = s.tiers.length > 1;
    final rate = tier?.ratePerHour ?? s.ratePerHour;
    final spec = tier?.spec ?? s.spec;
    // 上限是服务端下发的,status 到货前兜底是 1 —— 夹一遍,免得停在一个
    // 已经不合法的台数上(界面写 4、服务端只肯给 2)
    final count = _count.clamp(1, s.maxCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 档位清单由服务端下发(config.IMG_TIERS → status.tiers),**别在这边
        // 写死**:加档位是改服务端那张表,这里跟着渲染。
        //
        // 三档**直接摊在卡上**,不做成「点进去再选」:一共就三行,而且这是笔
        // 花钱的决定 —— 价差和「会不会被收走」得跟「启动实例」那颗按钮摆在
        // 同一屏里,而不是藏在再下一层弹层、选完就看不见了。
        if (pickable)
          for (final t in s.tiers)
            _TierRow(
              tier: t,
              selected: t.key == tier?.key,
              onTap: () {
                Haptics.selection();
                ref
                    .read(rentalPrefsProvider.notifier)
                    .patch((p) => p.copyWith(tier: t.key));
              },
            )
        else ...[
          // 老服务端不下发 tiers:那时只有一种机型,还原成原来的只读行
          Row(
            children: [
              Icon(
                Icons.developer_board,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  spec.name,
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${rate.toStringAsFixed(2)} 元/时',
                style: mono(context, size: 13, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              spec.detail,
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
          ),
        ],
        Divider(height: 15, color: scheme.outlineVariant.withValues(alpha: .5)),
        InkWell(
          onTap: () => _pickIdle(context, ref, s),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '空闲自动关机',
                    style: context.texts.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  idleLabel(idle),
                  style: mono(
                    context,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Icon(Icons.chevron_right, size: 17, color: scheme.outline),
              ],
            ),
          ),
        ),
        // 一次开几台。服务端**并发建**,所以开 4 台和开 1 台等的时间差不多;
        // 但钱是 4 份 —— 所以按钮上把台数和总价一起写出来,别让人按完才发现。
        if (s.maxCount > 1) ...[
          Divider(
            height: 15,
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
          Row(
            children: [
              Icon(
                Icons.dns_outlined,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '台数',
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _CountPicker(
                value: count,
                max: s.maxCount,
                onPick: (v) {
                  Haptics.selection();
                  setState(() => _count = v);
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // 开机/首图的等待时长不写在这:按下去之后的运行卡会实时说(见
        // _RentalRunning 的启动中那段),提前铺两行反而把「启动实例」推下去。
        FilledButton.icon(
          onPressed: s.busy
              ? null
              : () {
                  Haptics.medium();
                  unawaited(
                    ref
                        .read(gpuRentalProvider.notifier)
                        .start(idle, tier: tier?.key ?? '', count: count),
                  );
                },
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(
            count > 1
                ? '启动 $count 台 · ${(rate * count).toStringAsFixed(2)} 元/时'
                : '启动实例',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }

  Future<void> _pickIdle(
    BuildContext context,
    WidgetRef ref,
    RentalState s,
  ) async {
    final cur = s.idleSeconds;
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle(ctx, '空闲自动关机'),
            for (final v in s.idleChoices)
              ListTile(
                onTap: () => Navigator.pop(ctx, v),
                title: Text(idleLabel(v), style: ctx.texts.bodyMedium),
                // 「不自动关」听着像能跑一整夜 —— 硬上限这句必须跟在它后面
                subtitle: v == 0
                    ? Text(
                        '仍受 ${s.maxUptimeS ~/ 3600} 小时硬上限约束',
                        style: ctx.texts.bodySmall!.copyWith(
                          color: ctx.scheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                trailing: v == cur
                    ? Icon(Icons.check, size: 18, color: ctx.scheme.primary)
                    : null,
                dense: true,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref.read(gpuRentalProvider.notifier).setIdle(picked);
    }
  }
}

/// 台数分段选择(1..max)。方角,与创作页那排张数同一种说法。
class _CountPicker extends StatelessWidget {
  const _CountPicker({
    required this.value,
    required this.max,
    required this.onPick,
  });

  final int value;
  final int max;
  final ValueChanged<int> onPick;

  static const _h = 30.0;
  static const _segW = 34.0;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      height: _h,
      width: _segW * max + 6,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedAlign(
            duration: Motion.medium,
            curve: Motion.emphasized,
            // -1..1 的对齐值:第 i 段的中心
            alignment: Alignment(
              max == 1 ? 0 : (value - 1) / (max - 1) * 2 - 1,
              0,
            ),
            child: Container(
              width: _segW,
              height: _h - 6,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Row(
            children: [
              for (var n = 1; n <= max; n++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(n),
                  child: SizedBox(
                    width: _segW,
                    height: _h - 6,
                    child: Center(
                      child: Text(
                        '$n',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: n == value
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: n == value
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一档机型:名字与单价一行,规格与风险跟在下面。
///
/// **三档全写全**,不做「选中才展开」:选机型要的就是横着比,
/// 一台 24G 一台 32G、一台会被收走一台不会 —— 藏起来两档只留价格,
/// 等于逼人一档一档点开来回记。抢占那句风险原样用服务端的文案
/// (它同时交代了「会被收走」和「收走了怎么算钱」),别自己改写成
/// 「更便宜」之类的话,那是在替用户低估风险。
class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final RentalTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 17,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tier.label,
                    style: context.texts.bodyMedium!.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? null : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${tier.ratePerHour.toStringAsFixed(2)} 元/时',
                  style: mono(
                    context,
                    size: 13,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tier.spec.detail,
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                  if (tier.desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      tier.desc,
                      style: context.texts.labelSmall!.copyWith(
                        // 抢占那句是风险,独享那句(「不会被回收」)是卖点,
                        // 两者不该同色 —— 一个要人多看一眼,一个不用
                        color: tier.spot ? scheme.tertiary : scheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 启动中 / 运行中 / 关机中。
class _RentalRunning extends ConsumerWidget {
  const _RentalRunning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final s = ref.watch(gpuRentalProvider);
    final now = ref.watch(_tickProvider).value ?? _now();
    final ending = s.status == RentalStatus.ending;
    final multi = s.machines.length > 1;
    // 「启动中」这句只在**一台都还没就绪**时说。多台时先起来的那几台已经在
    // 出图、在收钱了,整卡挂着「启动中」既不准也让人不敢用。
    final booting = !s.billing && s.status == RentalStatus.creating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _dot(scheme.primary),
            const SizedBox(width: 8),
            Text(
              booting
                  ? '启动中'
                  : ending
                  ? '关机中'
                  : '运行中',
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // 一台就报它的档位名(比卡名信息量大:同是 5090 还分独享和
                // 抢占);多台各不相同,这里只报台数,明细在下面逐台列。
                multi ? '${s.count} 台' : s.runningLabel,
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (booting)
          // 开机是**后台建机 + 轮询报状态**(服务端 2026-08-19 起不再阻塞到
          // 就绪),这段界面靠 6 秒一次的轮询等它翻成「运行中」。
          // 不写读数:服务端在就绪前 billed_seconds 恒为 0,摆个 ¥0.00 反倒
          // 像「这段不要钱」—— 其实就绪后会连这段一起算进去。
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在建实例并等待服务就绪,通常约 ${s.bootHintS} 秒;'
                  '就绪后首张图还要约 ${s.firstImageHintS} 秒加载权重。'
                  // 服务端只在 state=ready 时分流,启动中出的图会回落免费档 ——
                  // 不说的话用户以为已经在用自己那台了
                  '这段时长计入租用,且就绪之前出图仍走免费队列。',
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              _stat(context, '已计费', fmtUptime(s.elapsedAt(now))),
              const SizedBox(width: 16),
              _stat(context, '费用', fmtYuan(s.priceAt(now))),
              const SizedBox(width: 16),
              _stat(context, '出图', '${s.jobsDone}'),
              const SizedBox(width: 16),
              _stat(context, '空闲关机', idleLabel(s.idleSeconds)),
            ],
          ),
        // 逐台明细。只在多台时列 —— 一台的话上面那行已经把它说完了,
        // 再抄一遍是纯噪音。每台自带关机键:这个端点不带 instance_id 就是
        // 全停,「只停这一台」必须有自己的入口,否则就是替人做没授权的决定。
        if (multi) ...[
          const SizedBox(height: 10),
          for (final m in s.machines)
            _MachineRow(
              machine: m,
              fetchedAtMs: s.fetchedAtMs,
              now: now,
              busy: s.busy || ending,
              onStop: () => _stopOne(context, ref, s, m, now),
            ),
        ],
        if (s.error.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '状态同步失败:${s.error}',
            style: context.texts.labelSmall!.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: 10),
        // 加开。服务端 start 在已有机器时就是「加开到 N+count」,所以这颗按钮
        // 和配置卡上那颗「启动实例」走的是同一个端点。
        if (s.room > 0 && !ending) ...[
          const _AddMoreButton(),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: (ending || s.busy)
              ? null
              : () async {
                  final ok = await _confirmStopAll(context, s, now);
                  if (!ok || !context.mounted) return;
                  Haptics.medium();
                  final r = await ref.read(gpuRentalProvider.notifier).stop();
                  if (!context.mounted) return;
                  final yuan = (r?['price'] as num?)?.toDouble() ?? 0;
                  hintSnack(
                    context,
                    r == null
                        ? '关机失败,稍后再试'
                        : '已关机 · ${r['minutes']} 分钟 · ${fmtYuan(yuan)}',
                    icon: r == null
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                  );
                },
          icon: const Icon(Icons.power_settings_new, size: 18),
          // 多台时按钮上必须写「全部」:这个端点不带 instance_id 就是全停,
          // 而那几台里可能有一台是在 web 上开的、用户以为只关手机上这台。
          label: Text(
            ending ? '关机中…' : (multi ? '全部关机并结账(${s.count} 台)' : '关机并结账'),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 42),
            shape: const StadiumBorder(),
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: .5)),
          ),
        ),
      ],
    );
  }

  /// 只停一台。同一个端点,带上 instance_id 就只关那一台。
  Future<void> _stopOne(
    BuildContext context,
    WidgetRef ref,
    RentalState s,
    RentalMachine m,
    int now,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('关掉「${m.label}」'),
        content: Text(
          '这一台结算 ${fmtUptime(m.elapsedAt(s.fetchedAtMs, now))}(${fmtYuan(m.priceAt(s.fetchedAtMs, now))})。'
          '其余 ${s.count - 1} 台继续跑。\n\n'
          '实例会被销毁而不是挂起,机器上的内容一并清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('关掉这台'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Haptics.medium();
    final r = await ref
        .read(gpuRentalProvider.notifier)
        .stop(instanceId: m.instanceId);
    if (!context.mounted) return;
    final yuan = (r?['price'] as num?)?.toDouble() ?? 0;
    hintSnack(
      context,
      r == null ? '关机失败,稍后再试' : '已关掉 ${m.label} · ${fmtYuan(yuan)}',
      icon: r == null ? Icons.error_outline : Icons.check_circle_outline,
    );
  }

  Future<bool> _confirmStopAll(
    BuildContext context,
    RentalState s,
    int now,
  ) async {
    final multi = s.count > 1;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(multi ? '全部关机并结账' : '关机并结账'),
        // 「停止 = 销毁」这件事必须说 —— 用户以为是暂停,回来发现要重开机
        content: Text(
          // 多台时先把「关的是几台」摆在最前面:这个端点没有「只关这一台」
          // 的用法,而在 web 上加开的那几台用户在这个界面上根本看不见。
          '${multi ? '这会关掉你名下全部 ${s.count} 台。\n\n' : ''}'
          '本次将结算 ${fmtUptime(s.elapsedAt(now))}(${fmtYuan(s.priceAt(now))})。\n\n'
          '实例会被销毁而不是挂起,机器上的内容一并清除;'
          '下次使用要重新开机(约 ${s.bootHintS} 秒)。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('关机'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Widget _dot(Color c) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.texts.labelSmall!.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 1),
        Text(value, style: mono(context, size: 13, weight: FontWeight.w700)),
      ],
    );
  }
}

/// 逐台一行:档位名 + 自己的读数 + 只关这一台。
class _MachineRow extends StatelessWidget {
  const _MachineRow({
    required this.machine,
    required this.fetchedAtMs,
    required this.now,
    required this.busy,
    required this.onStop,
  });

  final RentalMachine machine;
  final int fetchedAtMs;
  final int now;
  final bool busy;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final m = machine;
    final ready = m.status == RentalStatus.ready;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            ready ? Icons.circle : Icons.more_horiz,
            size: ready ? 7 : 14,
            color: ready ? scheme.primary : scheme.outline,
          ),
          SizedBox(width: ready ? 10 : 5),
          Expanded(
            child: Text(
              m.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelMedium!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            // 没就绪的那台没有读数(服务端 billed_seconds 在 ready 之前恒为 0),
            // 摆一串 00:00 · ¥0.00 会看着像「这台白跑」
            ready
                ? '${fmtUptime(m.elapsedAt(fetchedAtMs, now))} · ${fmtYuan(m.priceAt(fetchedAtMs, now))}'
                : '启动中',
            style: ready
                ? mono(context, size: 12, color: scheme.onSurfaceVariant)
                : context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
          IconButton(
            onPressed: busy ? null : onStop,
            tooltip: '只关这一台',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(Icons.power_settings_new, size: 16, color: scheme.error),
          ),
        ],
      ),
    );
  }
}

/// 加开一台。用的是偏好里存的那一档 —— 运行卡上没有档位选择器,
/// 所以档位名写进按钮,别让人盲按。
class _AddMoreButton extends ConsumerWidget {
  const _AddMoreButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gpuRentalProvider);
    final prefs = ref.watch(rentalPrefsProvider).value ?? const RentalPrefs();
    final tier = s.resolveTier(prefs.tier);
    final name = tier?.label ?? s.spec.name;
    return OutlinedButton.icon(
      onPressed: s.busy
          ? null
          : () {
              Haptics.medium();
              unawaited(
                ref
                    .read(gpuRentalProvider.notifier)
                    .start(s.idleSeconds, tier: tier?.key ?? '', addMore: true),
              );
            },
      icon: const Icon(Icons.add, size: 18),
      label: Text('再开一台 · $name', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// 开机失败:服务端那条路径会自动销毁实例而且**一分不收**,这句得原样说出来。
class _RentalFailed extends ConsumerWidget {
  const _RentalFailed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final s = ref.watch(gpuRentalProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 17, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.note.isEmpty ? '开机失败' : s.note,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.error,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '实例已自动销毁,没有产生费用。',
          style: context.texts.labelSmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () =>
              ref.read(gpuRentalProvider.notifier).dismissFailure(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 42),
            shape: const StadiumBorder(),
          ),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

/// 没有 Bot 会话:租卡整条路都走不通(端点全要 session),只说暂未开放。
class _RentalNoAuth extends StatelessWidget {
  const _RentalNoAuth();

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 17, color: scheme.onSurfaceVariant),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '独享实例暂未开放',
            style: context.texts.labelSmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 算力来源弹层。模型弹层标题行那枚胶囊、创作页顶栏那枚,点的都是它 ——
/// 通道切换、卡型、空闲关机、开关机全在这一处,不在两个地方各摆一半。
Future<void> showRentalSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_sheetTitle(ctx, '算力来源'), const RentalSourceBlock()],
          ),
        ),
      ),
    );

Widget _sheetTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: context.texts.titleMedium!.copyWith(fontWeight: FontWeight.w700),
    ),
  ),
);

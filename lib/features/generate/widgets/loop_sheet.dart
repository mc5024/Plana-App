import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/anlas_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../cost.dart';
import '../gen_modules.dart';
import '../generate_state.dart';
import '../generation_controller.dart';
import '../loop_controller.dart';
import '../models.dart';
import '../vibe_encoder.dart';
import 'common.dart' show confirmDialog, hintSnack;
import '../../../l10n/l10n.dart';

/// 循环生成面板:选张数 → 看预估 → 开始;运行中切换为批次进度 + 停止。
/// 抓手由 BottomSheetTheme(showDragHandle: true)统一提供。
Future<void> showLoopSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LoopSheet(),
  );
}

class _LoopSheet extends ConsumerWidget {
  const _LoopSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(loopStatusProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: loop.active ? _Running(loop: loop) : const _Setup(),
    );
  }
}

/// 配置态:张数档位(直接写回全局参数)+ 成本预估 + 开始。
class _Setup extends ConsumerWidget {
  const _Setup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final s = ref.watch(generateProvider);
    final p = s.params;
    final gen = ref.watch(genStatusProvider);
    final isOpus = ref.watch(anlasProvider).asData?.value?.isOpus ?? false;
    final v5Charged = ref.watch(v5ChargedProvider);
    // 与吸底栏同口径:按剥离隐藏模块后的实际发送内容估价
    final mods =
        ref.watch(genModulesProvider).value ?? const GenModuleSettings();
    final sent = stripHiddenModules(s, mods);
    // 与吸底栏同口径:未缓存的 Vibe 编码费要算进去(见 vibeEncodeFeeProvider)。
    // 注意编码费只在**首张**发生,之后进缓存;所以总价按「单张 × N + 一次编码费」。
    final vibeFee =
        ref.watch(vibeEncodeFeeProvider(vibeEncodeFeeKey(sent))).value ?? 0;
    final cost = estimateCost(sent, isOpus: isOpus, v5Charged: v5Charged);
    final n = p.loop.count;

    final l = context.l10n;
    final free = cost == 0 && vibeFee == 0;
    final costText = free
        ? l.free
        : n > 0
        ? l.costPerImageTotal(cost, cost * n + vibeFee)
        : '${l.costPerImage(cost)}'
              '${vibeFee > 0 ? l.costEncodeExtra(vibeFee) : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.loopGenerate,
          style: context.texts.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l.loopIntro,
          style: context.texts.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(l.imageCount, style: context.texts.bodyMedium),
            ),
            SegmentedButton<LoopCount>(
              segments: [
                for (final l in LoopCount.values)
                  ButtonSegment(
                    value: l,
                    label: l == LoopCount.infinite
                        ? const Icon(Icons.all_inclusive, size: 15)
                        : Text(l.label),
                  ),
              ],
              selected: {p.loop},
              onSelectionChanged: (sel) =>
                  ref.read(generateProvider.notifier).setLoop(sel.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -3, vertical: -3),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(l.estimatedCost, style: context.texts.bodyMedium),
            ),
            // 「12/张 · 共 246 Anlas」这类串在窄屏会顶破一行,收进 Flexible
            Flexible(
              child: Text(
                costText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                // 要扣点就上粉,与主按钮那颗费用胶囊同一个语义;免费档留常规
                // 字色,不必特意醒目。这里是**字**不是徽章,所以取 tertiary 而
                // 不是胶囊那支 tertiaryContainer —— 后者是给底色用的调子,
                // 当字色压在浅色面上根本读不出来。同一族,深浅各就各位。
                style: mono(
                  context,
                  size: 13,
                  color: free ? null : scheme.tertiary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: gen.busy
              ? null
              : () async {
                  // 无限 + 收费档:没有张数上限就没有花费上限,且退到后台仍会继续,
                  // 所以开跑前确认一次。免费档或有限张数不打扰。
                  if (n == 0 && (cost > 0 || vibeFee > 0)) {
                    final ok = await confirmDialog(
                      context,
                      title: l.infiniteLoopTitle,
                      message: vibeFee > 0
                          ? l.infiniteLoopBodyFee(cost, vibeFee)
                          : l.infiniteLoopBody(cost),
                      confirmLabel: l.start,
                    );
                    if (!ok || !context.mounted) return;
                  }
                  // 循环每轮重读当前参数,开跑前先把缺编码的纯编码 Vibe 停掉并提示
                  final skipped = ref
                      .read(generateProvider.notifier)
                      .disableVibesMissingEncoding();
                  if (skipped > 0) {
                    hintSnack(
                      context,
                      l.vibesDisabledNoEncoding(skipped),
                      icon: Icons.visibility_off_outlined,
                    );
                  }
                  final notifier = ref.read(loopStatusProvider.notifier);
                  Navigator.pop(context);
                  unawaited(notifier.start());
                },
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Text(
            gen.busy ? l.generationBusy : l.startLoop(n > 0 ? '×$n' : '∞'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// 运行态:第 n/N 张 + 合成进度(张数 + 当前张流式进度)+ 停止。
class _Running extends ConsumerWidget {
  const _Running({required this.loop});

  final LoopStatus loop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final gen = ref.watch(genStatusProvider);
    final progress = loop.total > 0
        ? (((loop.batch - 1) + (gen.progress ?? 0)) / loop.total).clamp(
            0.0,
            1.0,
          )
        : null; // ∞:不确定进度

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.loopRunning,
          style: context.texts.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              loop.total > 0
                  ? context.l10n.loopImageOf(loop.batch, loop.total)
                  : context.l10n.loopImage(loop.batch),
              style: context.texts.titleLarge!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (gen.total > 0 && gen.step > 0)
              Text(
                '${gen.step}/${gen.total}',
                style: mono(
                  context,
                  size: 13,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 6),
        ),
        const SizedBox(height: 18),
        // 与吸底栏同规则:软停后不置灰,升级为强制取消 —— 当前张卡住时
        // (断网最常见)这是唯一能中断请求的入口,置灰等于关掉退路。
        FilledButton.tonal(
          onPressed: loop.stopping
              ? () => ref.read(generationProvider.notifier).cancel()
              : () => ref.read(loopStatusProvider.notifier).stop(),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Text(
            loop.stopping
                ? context.l10n.loopStopping
                : context.l10n.loopStopAfterThis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

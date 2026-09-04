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

    final free = cost == 0 && vibeFee == 0;
    final costText = free
        ? '免费'
        : n > 0
        ? '$cost/张 · 共 ${cost * n + vibeFee} Anlas'
        : '$cost Anlas/张${vibeFee > 0 ? ' + 编码 $vibeFee' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '循环生成',
          style: context.texts.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '按当前参数一张接一张地出图,种子留空就每张随机。'
          '中途出错会自动停下,也可以退到后台,进度在通知栏继续。',
          style: context.texts.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('张数', style: context.texts.bodyMedium)),
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
            Expanded(child: Text('预估消耗', style: context.texts.bodyMedium)),
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
                      title: '无限循环会持续扣点',
                      message:
                          '当前参数每张约 $cost Anlas'
                          '${vibeFee > 0 ? '(另首张含 $vibeFee 点 Vibe 编码费)' : ''}'
                          ',张数为无限——不点停止就会一直生成,退到后台也会继续。确定开始?',
                      confirmLabel: '开始',
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
                      '$skipped 个 Vibe 缺当前模型编码,已停用',
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
            gen.busy ? '当前有生成进行中' : '开始循环 ${n > 0 ? '×$n' : '∞'}',
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
          '循环生成中',
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
                  ? '第 ${loop.batch} / ${loop.total} 张'
                  : '第 ${loop.batch} 张',
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
            loop.stopping ? '本张后停止' : '停止(本张跑完后)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/live_progress/live_progress.dart';
import '../shell/shell_state.dart';
import 'gen_queue.dart';
import 'generate_state.dart';
import 'generation_controller.dart';
import '../gallery/albums/album_state.dart';

/// 循环生成状态。batch 为当前第几张(1-based);total 0 表示无限;
/// stopping 表示已请求停止,本张跑完后不再续。
class LoopStatus {
  const LoopStatus({
    this.active = false,
    this.batch = 0,
    this.total = 0,
    this.stopping = false,
  });

  final bool active;
  final int batch;
  final int total;
  final bool stopping;

  LoopStatus copyWith({bool? active, int? batch, int? total, bool? stopping}) =>
      LoopStatus(
        active: active ?? this.active,
        batch: batch ?? this.batch,
        total: total ?? this.total,
        stopping: stopping ?? this.stopping,
      );
}

final loopStatusProvider = NotifierProvider<LoopNotifier, LoopStatus>(
  LoopNotifier.new,
);

/// 循环控制器:顺序连跑 N 张(对齐 web:每轮重读当前编辑器参数、seed 留空
/// 则每轮随机、停止让当前张跑完)。与 web 不同:单张失败即停(移动端挂机
/// 连续失败无意义),错误由单张生成流程弹出。
class LoopNotifier extends Notifier<LoopStatus> {
  @override
  LoopStatus build() => const LoopStatus();

  bool get _appForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> start() async {
    // 手动生成中不再让位:并行之后手动那条只是池子里的一员,循环照常投。
    if (state.active || ref.read(genQueueProvider).active) return;
    final total = ref.read(generateProvider).params.loop.count; // 开跑时锁档位
    final galleryTarget = ref.read(gallerySaveTargetProvider);
    state = LoopStatus(active: true, total: total);
    // 只在开跑时切一次图库;之后每张不再强拉(generate 里按 _inLoop 跳过)
    ref.read(shellIndexProvider.notifier).select(kTabGallery);

    final gen = ref.read(generationProvider.notifier);
    var dispatched = 0; // 已投出的张数(含在跑的)
    var done = 0; // 成功张数
    var ok = true;

    // 一个 worker 就是一个并发槽:同时最多投这么多条,每条跑完立刻补下一条。
    // 不是「一次性把 N 张全塞进池子」—— 那样「失败即停」就没意义了(全投出去
    // 才发现第一张就挂了),而且会把 20 条的池子上限一次撑满。
    Future<void> worker() async {
      while (ok && !state.stopping && (total == 0 || dispatched < total)) {
        dispatched++;
        // 非 ok 一律停(含用户取消):挂机连续失败无意义,也不该替用户决定重试
        if (await gen.generate(galleryTarget: galleryTarget) != GenOutcome.ok) {
          ok = false;
          break;
        }
        done++;
        state = state.copyWith(batch: done + 1);
      }
    }

    final workers = await gen.concurrency();
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    state = const LoopStatus();

    // 循环期间单张不撤/不留通知(见 generation_controller._inLoop),
    // 统一在此收尾:岛上先显示完成态;前台不留通知,后台留一条汇总可点回应用。
    await LiveProgress.instance.finish(
      title: ok ? '循环完成' : (done > 0 ? '循环中止' : '生成失败'),
      text: _appForeground ? '' : (done > 0 ? '已出 $done 张 · 点按查看' : '点按回到应用'),
      short: ok ? '完成' : '中止',
      keep: !_appForeground,
    );
    // 循环收尾后放行排队任务(失败中止时不放行,先让用户处理错误)
    if (ok) unawaited(ref.read(genQueueProvider.notifier).maybeStart());
  }

  /// 请求停止:当前张跑完后不再续(不打断进行中的生成)。
  void stop() {
    if (state.active) state = state.copyWith(stopping: true);
  }
}

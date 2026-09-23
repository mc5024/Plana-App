import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/live_progress/live_progress.dart';
import 'gen_modules.dart';
import 'generate_state.dart';
import 'generation_controller.dart';
import 'loop_controller.dart';
import 'models.dart';
import '../gallery/albums/album_models.dart';
import '../gallery/albums/album_state.dart';

/// 排队任务:入队瞬间的完整参数快照,之后随便改编辑器不影响已排的。
class QueuedTask {
  const QueuedTask({
    required this.id,
    required this.snapshot,
    this.galleryTarget = const GallerySaveTarget.all(),
  });

  final int id;
  final GenerateState snapshot;
  final GallerySaveTarget galleryTarget;
}

/// items 为待跑任务(不含正在跑的);active = 消费中;
/// done 为本轮已完成张数;stopping = 当前张跑完后暂停。
class GenQueueState {
  const GenQueueState({
    this.items = const [],
    this.active = false,
    this.done = 0,
    this.stopping = false,
  });

  final List<QueuedTask> items;
  final bool active;
  final int done;
  final bool stopping;

  int get batch => done + 1;
  int get total => done + 1 + items.length;

  GenQueueState copyWith({
    List<QueuedTask>? items,
    bool? active,
    int? done,
    bool? stopping,
  }) => GenQueueState(
    items: items ?? this.items,
    active: active ?? this.active,
    done: done ?? this.done,
    stopping: stopping ?? this.stopping,
  );
}

final genQueueProvider = NotifierProvider<GenQueueNotifier, GenQueueState>(
  GenQueueNotifier.new,
);

/// 生成队列:生成中点排队把当前参数快照排进来,当前张/循环跑完自动顺序消费。
/// 消费间隙的手动生成可插队,成功后队列自动续。单张失败重试一次,仍失败
/// 放回队首并暂停(队列面板「继续」或下一次手动生成成功后恢复)。
/// 队列不落盘:与进行中的生成同属临时工作,重启即清。
class GenQueueNotifier extends Notifier<GenQueueState> {
  static const cap = 20;

  int _seq = 0;

  @override
  GenQueueState build() => const GenQueueState();

  bool get _appForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// 当前编辑器状态快照入队;满则拒绝。
  bool enqueue() {
    if (state.items.length >= cap) return false;
    // 与手动生成同语义:入队即按模块配置剥离,消费时不再看配置
    final snap = stripHiddenModules(
      ref.read(generateProvider),
      ref.read(genModulesProvider).value ?? const GenModuleSettings(),
    );
    state = state.copyWith(
      items: [
        ...state.items,
        QueuedTask(
          id: _seq++,
          snapshot: snap,
          galleryTarget: ref.read(gallerySaveTargetProvider),
        ),
      ],
    );
    return true;
  }

  void remove(int id) {
    state = state.copyWith(
      items: [
        for (final t in state.items)
          if (t.id != id) t,
      ],
    );
  }

  void clear() {
    state = state.copyWith(items: const []);
  }

  /// 当前张跑完后暂停(不打断进行中的生成)。
  void stopAfterCurrent() {
    if (state.active) state = state.copyWith(stopping: true);
  }

  /// 有排队任务时开始消费;循环中让位,由对方收尾时再拉起。
  /// 手动生成中不再让位:并行之后手动那条只是池子里的一员,不挡队列。
  Future<void> maybeStart() async {
    if (state.active || state.items.isEmpty) return;
    if (ref.read(loopStatusProvider).active) return;
    await _drain();
  }

  Future<void> _drain() async {
    state = state.copyWith(active: true, done: 0, stopping: false);
    final gen = ref.read(generationProvider.notifier);
    var failed = false;

    // 同循环:一个 worker 一个并发槽。取队首与写回之间没有 await,
    // 单线程下两个 worker 不会抢到同一条。
    Future<void> worker() async {
      while (!state.stopping && !failed && state.items.isNotEmpty) {
        final task = state.items.first;
        state = state.copyWith(items: state.items.sublist(1));
        var outcome = await gen.generate(
          using: task.snapshot,
          galleryTarget: task.galleryTarget,
        );
        // **只有「确定未扣点」才重试。** 流中断 / 超时 / 内容审核这类失败,NAI
        // 可能已经受理并扣了点,盲目重试就是第二次扣费,而且没有任何用户动作。
        // 用户取消(stopping)同样不重试。见 S1B-01。
        // `rejected`(额度/资格被拒)虽然也确定没扣点,但重试必然同样被拒 ——
        // 它单独一个值就是为了在这里落到「不重试」这一边。
        if (outcome == GenOutcome.notCharged && !state.stopping) {
          outcome = await gen.generate(
            using: task.snapshot,
            galleryTarget: task.galleryTarget,
          );
        }
        if (outcome != GenOutcome.ok) {
          failed = true; // 让别的 worker 也收手,剩下的留在队里等用户处置
          state = state.copyWith(items: [task, ...state.items]); // 放回队首
          break;
        }
        state = state.copyWith(done: state.done + 1);
      }
    }

    final workers = await gen.concurrency();
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);

    final done = state.done;
    final left = state.items.length;
    state = GenQueueState(items: state.items);

    // 与循环同款收尾:岛上先显示完成态;前台不留通知,后台留一条汇总可点回应用
    final all = left == 0;
    await LiveProgress.instance.finish(
      title: all ? '队列完成' : '队列暂停',
      text: _appForeground ? '' : (all ? '共 $done 张 · 点按查看' : '剩 $left 项'),
      short: all ? '完成' : '暂停',
      keep: !_appForeground,
    );
  }
}

import '../../core/util/log.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../gallery/albums/album_models.dart';
import '../gallery/albums/album_state.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/live_progress/live_progress.dart';
import '../../core/net/anlas_provider.dart';
import '../../core/store/gen_settings.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/backend_config.dart';
import '../../core/net/bot_stream.dart';
import '../../core/net/gen_abort.dart';
import '../../core/auth/nai_keys.dart';
import '../../core/net/nai_gate.dart';
import '../../core/net/nai_client.dart';
import '../../core/net/nai_key_status.dart';
import '../../core/store/app_stores.dart';
import '../../core/util/image_ops.dart';
import '../../core/util/transparency.dart';
import '../gallery/gallery_state.dart';
import '../gallery/upscale_model.dart' show enhanceMaxTargetSize;
import '../gallery/models.dart' show ResultBadge;
import '../inpaint/inpaint_ops.dart';
import '../shell/shell_state.dart';
import 'bot_request.dart';
import 'canvas_history.dart';
import 'canvas_state.dart';
import 'cost.dart';
import 'gen_jobs.dart';
import 'gen_modules.dart';
import 'gen_queue.dart';
import 'generate_state.dart';
import 'loop_controller.dart';
import 'models.dart';
import 'nai_request.dart';
import 'prompt_presets.dart';
import 'vibe_encoder.dart';
import '../char_library/char_library.dart';
import '../vibe_library/naiv4vibe_codec.dart' show kModelToEncodingKey;
import '../vibe_library/vibe_library.dart';

/// 生成状态。error 为哨兵 `no-token` 时表示未设置令牌(引导去我的页)。
/// busy 期间 step/total/preview 驱动图库的「生成中」画布。
class GenStatus {
  const GenStatus({
    this.busy = false,
    this.saving = false,
    this.error,
    this.step = 0,
    this.total = 0,
    this.prepPct = -1,
    this.width = 0,
    this.height = 0,
    this.preview,
    this.note,
    this.pasteUnder,
    this.pasteAt,
  });

  final bool busy;
  final bool saving;
  final String? error;
  final int step;
  final int total;

  /// 采样开始之前那段(拉 LoRA / 加载模型)的百分比 0..100;-1 = 没有可量化进度。
  final int prepPct;

  final int width;
  final int height;
  final Uint8List? preview;

  /// 局部重绘的预览底与贴回位置(见 [GenJob.pasteUnder])。
  final Uint8List? pasteUnder;
  final ({int x, int y, int w, int h})? pasteAt;

  /// 进度未知阶段的状态文案(bot 排队「排队中 · 第 N 位」等),
  /// 画布进度胶囊优先显示;null 时显「准备中」。
  final String? note;

  bool get noToken => error == 'no-token';

  /// 真的在逐步出图。读数只有这时候才有意义 —— 准备阶段和收尾阶段都不是。
  bool get sampling => total > 0 && step > 0;

  /// 0..1;null → 走不确定进度。采样开始前借「拉 LoRA」的百分比,见 [GenJob.progress]。
  double? get progress => sampling
      ? (step / total).clamp(0.0, 1.0)
      : (prepPct >= 0 ? (prepPct / 100).clamp(0.0, 1.0) : null);
}

/// 单张生成的结局 —— 关键是**能不能安全重试**。
///
/// 原先 `generate()` 只返回 `bool`,信息量不够:队列拿到 `false` 就无条件重试
/// 一次,可是「失败」里既有"请求根本没发出"也有"NAI 已经受理并扣了点",后者
/// 重试就是**第二次扣费,且没有任何用户动作**。见 S1B-01 / S2-07。
enum GenOutcome {
  ok,

  /// 用户主动取消 —— 不重试,也不报错。
  cancelled,

  /// **确定未扣点**:请求还没发出(前置校验失败、载荷未拼成),或服务端明确
  /// 拒收(401/402/404/405/429)。重试不花钱。
  notCharged,

  /// **可能已扣点**:请求已发出且服务端没有明确拒收 —— 流中途断开、超时、
  /// 内容审核、非流式回退失败。**绝不自动重试**;分不清就按最坏情况算。
  maybeCharged,

  /// **确定未扣点,但重试也不会好**:额度/资格类拒绝(见 [isNai5QuotaBlock])。
  /// 和 [notCharged] 的区别只在重试策略 —— 队列不该立刻再打一次:那几种情况下
  /// 第二次必然同样被拒,只会把失败翻倍、还多让用户等一轮。
  rejected,
}

/// NAI 5 额度/资格类拒绝的识别。
///
/// 三条文案都由服务端拼装(`NO_NAI_QUOTA_ELIGIBILITY_MSG` 没资格 /
/// `_nai_quota_exhausted_msg` 个人额度用尽 / `NO_V5_QUOTA_MSG` 共享号电池见底),
/// 共同点是都带「NAI5」这个**无空格**写法 —— 服务端别处一律写「NAI 5」或
/// `nai-diffusion-5`,所以这个标记足够窄。
///
/// 认不出也只是退回旧行为(多重试一次),不会误伤;所以宁可窄一点。
bool isNai5QuotaBlock(String msg) =>
    msg.contains('NAI5') && (msg.contains('额度') || msg.contains('资格'));

/// 服务端明确拒收的状态码:请求没被受理,重试不花钱。
/// 401 令牌无效 · 402 点数不足 · 404/405 端点不可用 · 429 限流。
bool _rejectedOutright(int? status) =>
    status == 401 ||
    status == 402 ||
    status == 404 ||
    status == 405 ||
    status == 429;

/// 生成任务池。**这是唯一的写入方**:任务的增删、进度、选中全在这里。
final generationProvider = NotifierProvider<GenerationNotifier, GenPool>(
  GenerationNotifier.new,
);

/// 兼容视图:把「画布正在跟随的那条任务」摊平成并行之前那份 [GenStatus]。
///
/// 画布、进度胶囊、底部栏本来就只关心「我正看着的那张跑到哪了」,并行之后这个
/// 问题的答案就是选中的那条 —— 让它们继续读一份扁平状态,比在每个 widget 里
/// 各自从池子里捞一遍要稳。**想知道「有没有任务在跑」请读 [generationProvider]
/// 的 `jobs`**,别拿这里的 `busy`:它只代表被跟随的那条。
final genStatusProvider = Provider<GenStatus>((ref) {
  final pool = ref.watch(generationProvider);
  final j = pool.selected;
  return j == null ? GenStatus(error: pool.error) : _statusOf(j);
});

/// 重绘任务的扁平视图 —— 全池最多一条(见 [GenJobKind.inpaint])。
/// 重绘面板只跟自己这条:后台的普通出图不该把面板的进度和收尾带跑。
final inpaintStatusProvider = Provider<GenStatus>((ref) {
  for (final j in ref.watch(generationProvider).jobs) {
    if (j.kind == GenJobKind.inpaint) return _statusOf(j);
  }
  return const GenStatus();
});

GenStatus _statusOf(GenJob j) => GenStatus(
  busy: true,
  saving: j.stage == GenJobStage.saving,
  total: j.total,
  width: j.width,
  height: j.height,
  step: j.step,
  prepPct: j.prepPct,
  preview: j.preview,
  note: j.note,
  pasteUnder: j.pasteUnder,
  pasteAt: j.pasteAt,
);

/// 同时**在跑**的任务数上限。
///
/// bot 模式固定 5:服务端 anima/krea 的本地并发准入也是 5(两边各一份队列),
/// 再多只是把任务堆在服务端队列里,自己这头还白占内存。
const kMaxRunningBot = 5;

/// 池子总量上限(在跑 + 等位)。沿用并入前那条队列的 cap:超出就拒收,
/// 免得手滑连点砸出一串图。
const kMaxPoolJobs = 20;

/// 生成过程中的一次性非致命提醒(目前只有 LoRA 超上限被丢弃)。
/// 单独开一个 provider 而不是塞进 [GenStatus]:警告在出图途中到达,而 GenStatus
/// 每来一帧进度就整体重建,挂在上面会被立刻冲掉。app_shell 监听后弹 snack 并置空。
final genNoticeProvider = NotifierProvider<GenNoticeNotifier, String?>(
  GenNoticeNotifier.new,
);

class GenNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String msg) => state = msg;
  void clear() => state = null;
}

/// 一条任务的运行时句柄(不进 UI 状态:中止令牌和 Key 槽位对渲染没意义)。
class _JobRun {
  _JobRun(this.abort, this.presets);

  final GenAbort abort;

  /// 受理时捕获预设库快照，等位期间切画布/改预设不改变这一单。
  final Future<PromptPresetsState> presets;

  /// 服务端任务 id(bot 模式提交成功后才有),取消排队要用。
  String? taskId;

  /// 占用的并发槽位;直连模式下它同时是「用第几把 Key」。-1 = 还没拿到。
  int slot = -1;

  /// 直连:闸门在取槽时一并定下的令牌(bot 线为 null)。
  String? token;

  /// 直连:那把 Key 打哪台机器(空 = 官方)。跟令牌一起由闸门定下 ——
  /// 这里自己再查一次会在中途增删 Key 时错位,把请求发到别人那台上。
  String base = '';

  /// 从哪张画布发起;出图入库后记进那张画布的历史。null = 不记(图库重新生成等)。
  CanvasOrigin? origin;
}

class GenerationNotifier extends Notifier<GenPool> {
  @override
  GenPool build() => const GenPool();

  DateTime? _lastPush; // 通知节流游标
  final _runs = <String, _JobRun>{}; // 每条任务的运行时,键同 GenJob.id
  var _seq = 0; // 提交序号,只增
  int _focusRevision = 0;

  // ---- 并发闸门 ----
  // 槽位用**下标**而不是计数:直连模式下「第 i 个槽」就是「第 i 把 Key」,
  // 一把 Key 同时只跑一条 —— NAI 按账号限流,同 Key 并发只会自己打自己。
  final _busySlots = <int>{};
  final _waiters = <Completer<void>>[];

  bool get _appForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  // ---- 池的读写(只有这几个方法碰 state.jobs)----

  GenJob? _job(String id) {
    for (final j in state.jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// 就地改一条任务;任务已经收尾(被移除)时静默丢弃 —— 迟到的进度帧很正常
  /// (WS 与轮询交错、取消后还在路上的那一帧),不该让它把任务复活。
  void _patch(String id, GenJob Function(GenJob) f) {
    final i = state.jobs.indexWhere((j) => j.id == id);
    if (i < 0) return;
    final next = [...state.jobs];
    next[i] = f(next[i]);
    state = state.copyWith(jobs: next);
  }

  /// 摘掉一条任务。它正被画布跟随时把跟随一并解除 —— 由调用方决定接下来
  /// 画布看什么(成功→看成图,失败/取消→回历史图)。
  void _remove(String id) {
    final next = [...state.jobs]..removeWhere((j) => j.id == id);
    final wasSelected = state.selectedId == id;
    state = state.copyWith(
      jobs: next,
      clearSelected: wasSelected,
      selectedId: wasSelected ? null : state.selectedId,
    );
    _runs.remove(id);
  }

  /// 画布跟随哪条(null = 看成图/历史图)。
  void select(String? jobId) {
    _focusRevision++;
    state = jobId == null
        ? state.copyWith(clearSelected: true)
        : state.copyWith(selectedId: jobId);
  }

  // ---- 并发闸门 ----

  /// 同时在跑的上限。bot 固定 [kMaxRunningBot];直连 = 参与出图的把数,由
  /// [NaiGate] 说了算。
  ///
  /// [isBot] 由调用方传而不是在这里现读:`generate()` 已经判过一次接入方式,
  /// 两处各读各的会在冷启动那一小段(authMode 还是 loading)得出不同答案 ——
  /// 最坏是「按直连提交、按 bot 放行 5 条并发」,正好是不该松的那个方向。
  Future<int> _runLimit(bool isBot) async =>
      isBot ? kMaxRunningBot : await ref.read(naiGateProvider).limit();

  /// 同时能跑几条 —— 循环/队列据此决定**同时投几条**。
  /// 投多了也不会失控(闸门会拦),但投的数量正好等于并发数时,派发者不用自己
  /// 维护「等谁跑完再补一条」的逻辑:每个 worker 天然就是一个槽位。
  ///
  /// 直连**循环**只数能接这张图的号:循环一批出的都是面板当前这一张,只在花
  /// 点数时参与的副账号接不了免费单,按参与的总把数投的话,它在免费循环里白占
  /// 一个 worker,挂一张一直「等待中」的卡。队列一单一个快照、贵贱不一,仍按
  /// 总把数。
  Future<int> concurrency() async {
    final mode = await ref.read(authModeProvider.future);
    if (mode != AuthMode.bot && _inLoop) {
      final freeOn = _freeOn(_panelJob());
      return ref
          .read(naiGateProvider)
          .limit(paid: freeOn == null, freeOn: freeOn);
    }
    return _runLimit(mode == AuthMode.bot);
  }

  /// 当前画布和它此刻的内容(面板发起的单子记历史用)。
  CanvasOrigin currentCanvasOrigin() => (
    canvasId: ref.read(canvasWorkspaceProvider).activeId,
    content: CanvasPrompts.of(ref.read(generateProvider)),
  );

  /// 面板当前这一单:按模块配置剥离了隐藏模块的数据(与手动生成、入队同一口径)。
  GenerateState _panelJob() => stripHiddenModules(
    ref.read(generateProvider),
    ref.read(genModulesProvider).value ?? const GenModuleSettings(),
  );

  /// 取一个空槽;满了就排队等别人释放。返回槽位下标,等位期间被取消返回 -1。
  Future<int> _acquireSlot(int limit, GenAbort abort) async {
    while (!abort.aborted) {
      for (var i = 0; i < limit; i++) {
        if (_busySlots.add(i)) return i;
      }
      final w = Completer<void>();
      _waiters.add(w);
      // 等位期间被取消也要醒过来,否则这条任务会一直挂着占着池子的名额
      abort.whenAbort(() {
        if (!w.isCompleted) w.complete();
      });
      await w.future;
    }
    return -1;
  }

  void _releaseSlot(int slot) {
    if (slot < 0) return;
    _busySlots.remove(slot);
    // 唤醒下一个等位的。跳过已完成的:那是等位期间被取消的任务留下的空壳。
    while (_waiters.isNotEmpty) {
      final w = _waiters.removeAt(0);
      if (!w.isCompleted) {
        w.complete();
        return;
      }
    }
  }

  // ---- 取消 ----

  /// 取消画布正在跟随的那条(底部栏那颗按钮的语义);没跟随任何一条时取消最新的。
  /// 同时请求所在批量流程停止,避免中止当前张后循环/队列又续下一张。
  void cancel() {
    final id = state.selectedId ?? state.newestFirst.firstOrNull?.id;
    if (id == null) return;
    ref.read(loopStatusProvider.notifier).stop();
    ref.read(genQueueProvider.notifier).stopAfterCurrent();
    cancelJob(id);
  }

  /// 取消指定任务(任务卡上的取消入口)。不动循环/队列 —— 那是「停这一条」,
  /// 不是「别再续了」。
  void cancelJob(String id) {
    // 终图已收到后必须完成本地保存，不能再向服务端发送取消。
    if (_job(id)?.stage == GenJobStage.saving) return;
    final run = _runs[id];
    logi('[gen] cancel job=$id run=${run != null}');
    if (run == null) return;
    // 顺手撤掉服务端那条任务。不判「现在是不是在排队」:本地这个判断可能是旧的
    // (轮询/WS 都有延迟),而服务端对已开跑的任务本来就回 400、我们照单收下。
    // 不撤的话点了取消也只是本地不等了,NAI 那边照扣点、Modal 那边照占容器。
    final taskId = run.taskId;
    if (taskId != null) {
      // 撤单也要带会话（服务端已加鉴权）。这里拿不到现成的 session 变量，
      // 从 provider 现取；取不到就带 null 发出去，服务端会 401，而 401 被
      // cancelTask 当「没撤成」吞掉 —— 和以前撤不动是同一种表现，不会更糟。
      unawaited(() async {
        final s = await ref.read(botSessionProvider.future);
        await ref
            .read(backendClientProvider)
            .cancelTask(taskId, sessionId: s?.sessionId);
      }());
    }
    run.abort.abort();
  }

  /// 用户取消一条:摘掉它(不弹错误)。池子空了才撤通知 —— 还有别的在跑时
  /// 通知得留着,批量流程的收尾仍归其控制器。
  GenOutcome _cancelled(String jobId) {
    logi('[gen] cancelled job=$jobId → 剩 ${state.jobs.length - 1} 条');
    _remove(jobId);
    if (state.jobs.isEmpty && !_inFlow) LiveProgress.instance.stop();
    return GenOutcome.cancelled;
  }

  /// 激活的提示词预设拼进正/负提示词(web buildParamsFromState 同款)。
  /// 只用于构造请求;入库仍存原始提示词,避免「重新生成」时二次拼接。
  ///
  /// 正面拼前还是拼后由预设自己说了算(V5 档是后缀,见 [PromptPreset.suffixPositive])。
  /// 当前模型看不到的档(切了模型但档没跟着换)先映射到同强度的那一档 ——
  /// 否则 4.5 的质量词会被拼进 V5 的请求里。
  ({GenerateState state, String presetId, bool qualityToggle}) _applyPreset(
    GenerateState s,
    PromptPresetsState ps,
  ) {
    final id = remapPromptPresetId(
      selectedPromptPresetId(s, ps),
      ps.presets,
      s.params.model,
    );
    final p = ps.presets.where((e) => e.id == id).firstOrNull;
    final qt = p != null && p.positive.isNotEmpty;
    if (p == null || (p.positive.isEmpty && p.negative.isEmpty)) {
      return (state: s, presetId: id, qualityToggle: qt);
    }
    final merged = applyPromptPreset(p, s.prompt, s.negativePrompt);
    return (
      state: s.copyWith(
        prompt: merged.positive,
        negativePrompt: merged.negative,
      ),
      presetId: id,
      qualityToggle: qt,
    );
  }

  /// [using] 非空时用该快照跑(图库「重新生成」按本图参数复现),不动用户当前编辑器状态。
  /// 返回本张的结局:循环据此决定续跑/中止,队列据此决定能不能安全重试。
  /// [onJob] 在占位卡挂上去那一刻同步回调,给调用方一个跟住这一单的把手 ——
  /// AI 助手要拿它在对话里画逐帧预览和进度条。**建卡之前没有 await**,
  /// 所以同步调用方拿到它时这一单必定已经在池子里了。
  /// [origin] 是这一单来自哪张画布,出图后记进它的历史;面板发起的不用传。
  Future<GenOutcome> generate({
    GallerySaveTarget? galleryTarget,
    GenerateState? using,
    bool stay = false,
    void Function(String jobId)? onJob,
    CanvasOrigin? origin,
  }) async {
    // 池满拒收。守卫与建卡之间**不能有 await**:按钮不再禁用,连点两下会各自
    // 走一遍这里,中间插一个 await 就等于没守。
    if (state.jobs.length >= kMaxPoolJobs) {
      ref
          .read(genNoticeProvider.notifier)
          .show('同时最多 $kMaxPoolJobs 条任务,等前面的出完再提交');
      return GenOutcome.notCharged;
    }

    // 面板发起(using == null)按模块配置剥离隐藏模块的数据;
    // 快照复跑(图库重新生成等)忠实执行,不受当前模块配置影响。
    // 快照在这一刻定死:之后随便改编辑器都不影响已提交的这条。
    final GenerateState s = using ?? _panelJob();

    final isBot = ref.read(authModeProvider).value == AuthMode.bot;

    // 前置拒收:压根不该受理的,不挂占位卡 —— 挂一张再立刻撤掉只会闪一下。
    if (isModalModel(s.params.model)) {
      final modalName = isKreaModel(s.params.model) ? 'Krea 2' : 'Anima';
      // 服务端只认文生图,重绘/图生图快照(图库重绘、1.5× 放大)直接拦。
      if (s.inpaint != null || s.img2img?.image != null) {
        return _reject('$modalName 不支持重绘/图生图');
      }
      // Anima / Krea 走服务端 Modal 后端,直连 token 模式没有服务器会话,无从代理。
      if (!isBot) {
        return _reject(
          ref.read(botSessionProvider).value == null
              ? '$modalName 暂未开放'
              : '$modalName 仅 Bot 账户可用,请切换生成方式',
        );
      }
    }

    // 池子空着时这条才是「这一批的头一条」—— 只有它会把页面拽去图库,见下方。
    final firstOfBatch = state.jobs.isEmpty;

    // 挂占位卡:等位/拼载荷都可能要几秒,这段时间也得让用户看见任务已受理。
    final job = GenJob(
      galleryTarget: galleryTarget ?? ref.read(gallerySaveTargetProvider),
      id: 'job${_seq++}',
      kind: s.inpaint != null ? GenJobKind.inpaint : GenJobKind.normal,
      stage: GenJobStage.waiting,
      width: s.params.width,
      height: s.params.height,
      seq: _seq,
      total: s.params.activeSteps,
      // 已经有别的在跑 → 这条多半要等位,先说清楚是在等而不是在准备
      note: state.jobs.isEmpty ? null : '等待中',
      // 局部重绘:流帧只是那块裁切区,画布要拿整张原图垫底才看得出在改哪儿。
      pasteUnder: s.inpaint?.paste?.original,
      pasteAt: switch (s.inpaint?.paste) {
        final p? => (x: p.sendX, y: p.sendY, w: p.tightW, h: p.tightH),
        _ => null,
      },
    );
    final run = _JobRun(GenAbort(), ref.read(promptPresetsProvider.future))
      ..origin = origin ?? (using == null ? currentCanvasOrigin() : null);
    _focusRevision++;
    _runs[job.id] = run;
    state = state.copyWith(
      jobs: [...state.jobs, job],
      selectedId: job.id, // 新提交的这条接管画布(与并行前「点了就看着它」一致)
      clearError: true,
    );
    onJob?.call(job.id);

    // 只有「这一批的头一条」才把页面拽去图库看预览。并行之后连点是常态,
    // 每点一次都强拉一次等于把人按在图库页上 —— 想连投几条再回创作页改参数
    // 都做不到。池子空了之后的下一条重新算作头一条,又会切一次。
    // 循环/队列续张同样不强拉(循环开始时已切过一次,期间允许自由切页)。
    //
    // [stay] 是调用方说「这一单我自己显示,别切页」—— AI 助手开了「图片显示在
    // 对话里」就走这条:图照常入库,只是不把人从对话里拽走。
    if (firstOfBatch && !_inFlow && !stay) {
      ref.read(shellIndexProvider.notifier).select(kTabGallery);
    }

    // 直连挑号时逐把问这一单免不免费;null = 落在哪把上都要扣点(见 [_freeOn])。
    final freeOn = isBot ? null : _freeOn(s);
    // 免费尺寸的 V5 吃的是落到的那个号的额度,跑完它的读数就旧了(见 finally)。
    final drainsQuota = freeOn != null && isNai5Model(s.params.model);

    try {
      // 等位:bot 5 条(池内计数);直连按 Key 数,且要和图库超分、标签预览
      // **抢同一个闸门** —— 它们打的是同一个 NAI 账号、同一个限流桶。
      if (isBot) {
        run.slot = await _acquireSlot(kMaxRunningBot, run.abort);
      } else {
        final pass = await ref
            .read(naiGateProvider)
            .acquire(paid: freeOn == null, freeOn: freeOn, abort: run.abort);
        run.slot = pass.slot;
        run.token = pass.token;
        run.base = pass.base;
        // 等位期间被取消,闸门给的也是 -1 + null —— 得先认出来。当成「没有令牌」
        // 报错的话,队列会把它当成没扣点的失败,把用户刚取消的这一单再跑一遍。
        if (run.abort.aborted) return _cancelled(job.id);
        // 一把可用的都没有 → 闸门给 -1 + null。不能当成「被取消」静静收掉,
        // 那样点了生成什么都不会发生。
        //
        // 「压根没存」和「存了但都不可用」得分开说:后者跑去设置页会看到令牌
        // 明明在那儿,只是参与条件没勾 —— 报「未设置」会把人送错方向。
        if (pass.token == null) {
          final saved =
              (ref.read(naiKeysStoreProvider).value ?? const <NaiKey>[])
                  .isNotEmpty;
          return _fail(
            job.id,
            saved ? '没有能接这一单的令牌(检查各令牌的参与条件)' : 'no-token',
            GenOutcome.notCharged,
          );
        }
      }
      if (run.slot < 0) return _cancelled(job.id);
      _patch(
        job.id,
        (j) => j.copyWith(stage: GenJobStage.preparing, clearNote: true),
      );
      return isBot
          ? await _generateViaBot(s, job.id, run)
          : await _generateDirect(s, job.id, run);
    } finally {
      if (isBot) {
        _releaseSlot(run.slot);
      } else {
        // **先报额度再还槽**:还槽会叫醒等位的单,它们挑号要看这一张之后的额度。
        final token = run.token;
        if (drainsQuota && token != null) {
          ref.read(naiKeyStatusCacheProvider).spent((
            token: token,
            base: run.base,
          ));
        }
        ref.read(naiGateProvider).release(run.slot);
      }
      _remove(job.id); // 各分支正常都已摘掉,这里兜住异常路径不留幽灵卡
    }
  }

  /// 还没受理就退回:写池级错误(创作页那条统一提示),不挂卡。
  GenOutcome _reject(String msg) {
    state = state.copyWith(error: msg);
    return GenOutcome.notCharged;
  }

  /// bot 线的失败出口:额度/资格类拒绝走 [GenOutcome.rejected] 并顺手把配额
  /// 拉一次 —— 顶栏那格立刻显示真实余额(用尽 / 免额度窗口),否则用户看到的
  /// 还是被拒之前那个数,只会以为「明明还有额度却出不了图」。
  GenOutcome _botFail(String jobId, String msg, GenOutcome fallback) {
    if (!isNai5QuotaBlock(msg)) return _fail(jobId, msg, fallback);
    unawaited(ref.read(naiQuotaProvider.notifier).refresh());
    return _fail(jobId, msg, GenOutcome.rejected);
  }

  /// 一条任务失败:摘掉它并把错误交出去。
  ///
  /// 全停了才写池级错误(创作页那条常驻提示);还有别的在跑时只弹一条 snack ——
  /// 后台某一条失败不该把正在看的那条的画面换成错误页。
  GenOutcome _fail(String jobId, String msg, GenOutcome outcome) {
    _remove(jobId);
    if (state.jobs.isEmpty) {
      state = state.copyWith(error: msg);
    } else {
      ref
          .read(genNoticeProvider.notifier)
          .show(msg == 'no-token' ? '未设置 NovelAI 令牌' : msg);
    }
    if (!_inFlow) _endIsland(success: false);
    return outcome;
  }

  /// 直连(token 模式)生成。[run] 的槽位下标同时是「用第几把 Key」。
  Future<GenOutcome> _generateDirect(
    GenerateState s,
    String jobId,
    _JobRun run,
  ) async {
    // 等 storage 读完再判(懒加载 AsyncNotifier 冷启动首读是 loading,
    // 直接取 .value 会把「还没读出来」误判成「没配置」)。
    // 用哪把由闸门在取槽时一并定了(它按可用集合挑,顺序即优先级),
    // 这里不再自己查列表 —— 两处各查一次会在中途增删 Key 时错位。
    final token = run.token;
    if (token == null) {
      return _fail(jobId, 'no-token', GenOutcome.notCharged); // 弹「去设置」
    }

    final total = s.params.naiSteps;

    // 打哪台机器:闸门给的那把 Key 自己的地址(第三方的 key 只在它那台上有效)。
    final client = ref.read(naiClientProvider(run.base));

    // 走流式还是一次性,整单开头定一次:中途设置变了不该让这一单换端点。
    // 接口没有逐步预览(OpenAI 兼容)时按一次性走,进度条显示不确定态。
    final streaming = _streamGen && client.streams;

    final abort = run.abort;

    // 后台进度:首张开前台服务;续张就地刷新(不重拉服务,避免岛一张一闪)。
    // 传 total(采样步数):从「准备」起就是确定态进度条,立即上岛,不必等步数。
    await _beginIsland(total);

    ({Map<String, dynamic> body, int seed})? built;

    Future<void> finish(Uint8List bytes, int seed) async {
      // NAI 直连一单一张:batch 是 anima / krea 走 ComfyUI 才有的东西
      await _storeResult(s, [bytes], seed, jobId: jobId);
      // 直连不经过后端,统计在本机落账(bot 由服务端记)
      _recordKeyGen(s, (token: token, base: run.base));
      unawaited(ref.read(anlasProvider.notifier).refresh()); // 点数已扣
      // 循环期间通知由循环控制器统一收尾(保持挂机进度连续、只弹一条汇总)
      if (!_inFlow) {
        _endIsland(success: true);
        _kickQueue();
      }
    }

    var attempt429 = 0;
    while (true) {
      try {
        // 1. 先编码启用的 Vibe 参考(缓存优先;每次新编码费 2 Anlas)
        final prepared = await _prepareVibes(s);
        // 2. 图生图底图 cover 到目标分辨率
        final img2img = await _processImg2Img(s);
        // 3. 角色参考:contain 处理底图(无编码调用,载荷层按模型 gate)
        final charRefs = await _processCharRefs(s);
        // 4. 拼载荷 + 流式生成
        final preset = _applyPreset(s, await run.presets);
        built = buildNaiPayload(
          preset.state,
          presetId: preset.presetId,
          qualityToggle: preset.qualityToggle,
          straightAlpha: _straightAlpha,
          thirdParty: run.base.isNotEmpty,
          vibes: [
            for (final v in prepared)
              (encoded: v.encoded, strength: v.strength),
          ],
          img2img: img2img,
          charRefs: charRefs,
        );
        if (abort.aborted) return _cancelled(jobId);
        Uint8List? last;
        if (streaming) {
          await for (final f in client.generateImageStream(
            token: token,
            body: built.body,
            abort: abort,
          )) {
            last = f.bytes;
            final step = f.isFinal ? total : (f.step ?? 0);
            _patch(
              jobId,
              (j) => j.copyWith(
                stage: GenJobStage.running,
                step: step,
                total: total,
                preview: f.bytes,
                clearNote: true,
              ),
            );
            _pushProgress();
            if (f.isFinal) break;
          }
        } else {
          // 关了流式:整张画完才回来,期间没有步数 —— 置 step 0 走不确定进度条
          // (GenJob.progress 见 sampling),别摆一根永远停在 0% 的确定态条。
          _patch(
            jobId,
            (j) => j.copyWith(
              stage: GenJobStage.running,
              step: 0,
              total: total,
              clearNote: true,
            ),
          );
          _pushProgress();
          last = await client.generateImage(
            token: token,
            body: built.body,
            abort: abort,
          );
          // 取消赶在连接建立之前的话,这一发拦不住、会正常回来一张图 ——
          // 那也不能入库:任务卡此刻已在等这个返回值才肯消失。
          if (abort.aborted) return _cancelled(jobId);
        }
        if (last == null) throw NaiException('未收到图片数据');
        await finish(last, built.seed);
        return GenOutcome.ok;
      } on NaiException catch (e) {
        if (abort.aborted) return _cancelled(jobId);
        logd('[gen] NaiException status=${e.status} ${e.message}');
        // 流式端点不可用(404/405 = 请求没被受理,未扣点)→ 非流式回退。
        // 本来就没走流式的不再回退:同一个端点再打一遍只会同样 404。
        if (streaming &&
            (e.status == 404 || e.status == 405) &&
            built != null) {
          try {
            final bytes = await client.generateImage(
              token: token,
              body: built.body,
            );
            await finish(bytes, built.seed);
            return GenOutcome.ok;
          } on NaiException catch (e2) {
            logd('[gen] fallback failed status=${e2.status} ${e2.message}');
            // 非流式回退已把请求发出去了,失败原因未知 → 按最坏情况算
            return _fail(jobId, e2.message, GenOutcome.maybeCharged);
          }
        }
        if (await _wait429(jobId, e.status, attempt429)) {
          attempt429++;
          continue;
        }
        // built == null 说明载荷还没拼出来(vibe 编码/图片预处理阶段就挂了),
        // 生成请求根本没发出;否则只认服务端明确拒收的状态码。
        return _fail(
          jobId,
          e.message,
          built == null || _rejectedOutright(e.status)
              ? GenOutcome.notCharged
              : GenOutcome.maybeCharged,
        );
      } catch (e) {
        if (abort.aborted) return _cancelled(jobId);
        logd('[gen] $e');
        return _fail(
          jobId,
          '生成失败:$e',
          built == null ? GenOutcome.notCharged : GenOutcome.maybeCharged,
        );
      }
    }
  }

  /// 限流(429)且开着自动重试且还有机会:提示 + 按设置的固定间隔等待,
  /// 返回 true 让调用方重跑。429 = 请求被拒,未扣点,重试不花钱。
  Future<bool> _wait429(String jobId, int? status, int attempt) async {
    if (status != 429) return false;
    final gs = ref.read(genSettingsProvider).value ?? const GenSettings();
    if (!gs.retryOn429 || attempt >= gs.retryCount) return false;
    final secs = gs.retryDelaySecs;
    final label = secs > 0
        ? '限流 · ${secs}s 后重试(${attempt + 1}/${gs.retryCount})'
        : '限流 · 立即重试(${attempt + 1}/${gs.retryCount})';
    _patch(
      jobId,
      (j) => j.copyWith(stage: GenJobStage.preparing, step: 0, note: label),
    );
    _lastPush = null; // 绕过通知节流,提示立即可见
    _pushIndeterminate(label, '限流');
    if (secs > 0) await Future<void>.delayed(Duration(seconds: secs));
    return true;
  }

  // ---- 流程上下文(循环/队列:通知文案注入张数;单发时为空串) ----

  bool get _inLoop => ref.read(loopStatusProvider).active;
  bool get _inQueue => ref.read(genQueueProvider).active;

  /// 批量流程(循环或队列)运行中:单张不切页/不撤/不留通知,收尾归流程控制器。
  bool get _inFlow => _inLoop || _inQueue;

  /// 生成通知总开关(我的 → 生成设置)。关了就整条静默:不开前台服务、不上岛。
  bool get _notify => ref.read(genSettingsProvider).value?.genNotify ?? true;

  /// 透明图的 alpha 编码约定(见 [GenSettings.straightAlpha])。
  bool get _straightAlpha =>
      ref.read(genSettingsProvider).value?.straightAlpha ?? true;

  /// 直连走不走流式端点(见 [GenSettings.streamGen])。bot 线不看这个。
  bool get _streamGen => ref.read(genSettingsProvider).value?.streamGen ?? true;

  /// 这一单**实际**按多大的图计价。Max ✨ 放大重绘的输出尺寸是**服务端**定的,
  /// params 里还留着原图尺寸 —— 按原尺寸估会系统性少算(边长 ×2 = 四倍像素),
  /// 所以按官方那套算法先把实际尺寸算出来。数值倍率不用管:那几档是客户端
  /// 自己把 params 的宽高改好再发的。
  GenerateState _billed(GenerateState s) {
    if (s.img2img?.upscaledEnhance != true) return s;
    final m = enhanceMaxTargetSize(s.params.width, s.params.height);
    return s.copyWith(
      params: s.params.copyWith(width: m.w, height: m.h),
    );
  }

  /// 这一单落在某个号上花几点(与费用胶囊同一公式;重绘按发送尺寸/强度折算)。
  /// [s] 须先过 [_billed]。
  int _costOn(
    GenerateState s, {
    required bool isOpus,
    required bool v5Charged,
  }) {
    final job = s.inpaint;
    return job != null
        ? estimateInpaintCost(
            s,
            isOpus: isOpus,
            sendW: s.params.width,
            sendH: s.params.height,
            strength: effectiveInpaintStrength(s.params.model, job.strength),
            v5Charged: v5Charged,
          )
        : estimateCost(s, isOpus: isOpus, v5Charged: v5Charged);
  }

  /// 挑号时逐把问「这一单在它上面免不免费」—— 副账号接不接,看的就是这个和它
  /// 勾的参与条件(见 [naiKeysForJob])。返回 null = 落在哪个号上都要扣点(大图、
  /// 高步数、附加费),整单按付费挑,不必去查各号状态。
  ///
  /// **按每个号自己的档位和 V5 额度算**,不能只看主账号:免费尺寸图在 Opus 且
  /// 额度没见底的号上是 0 点,在额度见底或不是 Opus 的号上照扣 Anlas,NAI 还不
  /// 报错。只看主账号的话,主账号额度还在、副账号已经见底时,这一单会被当成
  /// 免费派给只参与免费生成的副账号,悄悄花掉它的点。第三方中转、以及主账号
  /// 这份查不到时,跟按钮走(见 [naiFreeOnPerKey])。
  NaiFreeOn? _freeOn(GenerateState s) {
    final b = _billed(s);
    try {
      if (_costOn(b, isOpus: true, v5Charged: false) > 0) return null;
    } catch (_) {
      return null; // 算不出来按付费挑:宁可少用一把,也不误花只该免费出图的号
    }
    final statuses = ref.read(naiKeyStatusCacheProvider);
    return naiFreeOnPerKey(
      buttonFree: () => _buttonFree(b),
      onKey: (k) async {
        final sub = await statuses.get(naiTargetOf(k));
        if (sub == null) return null;
        final pts = _costOn(
          b,
          isOpus: sub.isOpus,
          v5Charged: sub.usage?.isNegative ?? false,
        );
        return pts == 0;
      },
    );
  }

  /// 生成按钮上那个口径:按主账号的读数([anlasProvider])算这一单免不免费;
  /// 读数没到时同按钮一样按非 Opus 算。第三方中转、查不到状态的主账号跟它走。
  bool _buttonFree(GenerateState b) {
    final main = ref.read(anlasProvider).asData?.value;
    try {
      return _costOn(
            b,
            isOpus: main?.isOpus ?? false,
            v5Charged: ref.read(v5ChargedProvider),
          ) ==
          0;
    } catch (_) {
      return false;
    }
  }

  /// 手动单发成功后顺手放行排队任务(循环/队列自身收尾各自拉起,不经此)。
  void _kickQueue() {
    ref.read(genQueueProvider.notifier).maybeStart();
  }

  /// 通知副行:批量流程里说明这是第几张,单发时为空(空则不渲染那一行)。
  String get _flowNote {
    final lp = ref.read(loopStatusProvider);
    if (lp.active) {
      return lp.total > 0 ? '第 ${lp.batch}/${lp.total} 张' : '第 ${lp.batch} 张';
    }
    final q = ref.read(genQueueProvider);
    if (q.active) return '队列 ${q.batch}/${q.total}';
    return '';
  }

  /// 批量中状态栏胶囊改显张数(挂机时比步数有用)。
  String get _flowShort {
    final lp = ref.read(loopStatusProvider);
    if (lp.active) {
      return lp.total > 0 ? '${lp.batch}/${lp.total}' : '${lp.batch}·∞';
    }
    final q = ref.read(genQueueProvider);
    if (q.active) return '${q.batch}/${q.total}';
    return '';
  }

  /// 通知里的汇总口径。
  ///
  /// Android 前台服务只该有**一条**通知,所以多条在跑时把步数各自求和合成一条
  /// 进度条(3 张 28 步就是 0/84);只有一条时它就是那条自己的进度。
  ({int step, int total, int count}) get _agg {
    var step = 0, total = 0;
    for (final j in state.jobs) {
      step += j.step;
      total += j.total;
    }
    return (step: step, total: total, count: state.jobs.length);
  }

  /// 进度推到通知,≤~1/s 节流(系统对通知更新有限流,终帧必推)。
  void _pushProgress() {
    if (!_notify) return;
    final a = _agg;
    final step = a.step;
    final total = a.total;
    final finalish = total > 0 && step >= total;
    final now = DateTime.now();
    if (!finalish &&
        _lastPush != null &&
        now.difference(_lastPush!).inMilliseconds < 800) {
      return;
    }
    _lastPush = now;
    final ls = _flowShort;
    // 多条在跑时标题给张数(挂机时「3 张在跑」比「37/84」有用得多),
    // 状态栏胶囊同理;批量流程里仍优先显示流程自己的「第几/共几」。
    final many = a.count > 1;
    final short = ls.isNotEmpty ? ls : (many ? '${a.count} 张' : '$step/$total');
    if (step <= 0) {
      // 还没步数也走确定态 0/total:保持同一条可上岛的进度条,不在准备/首帧
      // 之间闪成转圈再变回来。
      LiveProgress.instance.update(
        step: 0,
        total: total,
        title: many ? '生成中 · ${a.count} 张' : '生成中…',
        text: _flowNote,
        short: short,
      );
    } else {
      LiveProgress.instance.update(
        step: step,
        total: total,
        title: many ? '生成中 · ${a.count} 张 ($step/$total)' : '生成中 $step/$total',
        text: _flowNote,
        short: short,
      );
    }
  }

  /// 起步:首张开前台服务 + 初始通知;循环/队列续张时服务已在,只就地刷新准备态。
  /// 关键是续张别再走 start()——重复 startForegroundService 会让灵动岛胶囊消失再弹出,
  /// 一张一闪;就地 update 才是连续的一条。[total]<=0 走不确定态(bot 无步数)。
  Future<void> _beginIsland(int total) async {
    if (!_notify) return;
    // 已经有别的任务在跑:通知归汇总管,别把它打回「准备生成…」。
    if (state.jobs.length > 1) {
      _lastPush = null;
      _pushProgress();
      return;
    }
    _lastPush = null;
    // 通知/前台服务是旁路能力,平台通道抛异常绝不能连累生成本身 ——
    // 这里在主 try 之外调用,不接住就会变成未捕获的 async 异常。
    try {
      await LiveProgress.instance.ensurePermission();
      if (LiveProgress.instance.active) {
        unawaited(
          LiveProgress.instance.update(
            step: 0,
            total: total,
            indeterminate: total <= 0,
            title: '准备生成…',
            text: _flowNote,
            short: _flowShort.isEmpty
                ? (total > 0 ? '0/$total' : '准备')
                : _flowShort,
          ),
        );
      } else {
        await LiveProgress.instance.start(
          title: '准备生成…',
          text: _flowNote,
          total: total,
        );
      }
    } catch (e) {
      logd('[gen] 进度通知起步失败(不影响生成): $e');
    }
  }

  /// 收尾:岛上先显示完成态再落地。前台不留通知(结果已在眼前),
  /// 后台留一条可点按回应用的。
  void _endIsland({required bool success}) {
    if (!_notify) return;
    // 还有别的在跑:这条只是先出来的一张,通知得留给剩下的那些。
    if (state.jobs.isNotEmpty) {
      _lastPush = null;
      _pushProgress();
      return;
    }
    LiveProgress.instance.finish(
      title: success ? '生成完成' : '生成失败',
      text: _appForeground ? '' : (success ? '点按查看' : '点按回到应用'),
      short: success ? '完成' : '失败',
      keep: !_appForeground,
    );
  }

  /// bot 模式:后端代理生成。编码 vibe(缓存)→ 提交任务 → WS 流式(逐步预览)
  /// + 轮询兜底 → base64 入库 → 刷新点数。CR / 图生图与直连同一套离线处理。
  Future<GenOutcome> _generateViaBot(
    GenerateState s,
    String jobId,
    _JobRun run,
  ) async {
    // 同 generate():await future,避免冷启动 loading 态误报未授权/未配置。
    // 同样在主 try 之外,读失败要就地转成错误态,不能让异常逃出去。
    final BotSession? session;
    final String base;
    try {
      session = await ref.read(botSessionProvider.future);
      base = await ref.read(backendBaseProvider.future);
    } catch (e) {
      return _fail(jobId, '读取授权信息失败:$e', GenOutcome.notCharged);
    }
    if (session == null) {
      return _fail(jobId, '暂未开放', GenOutcome.notCharged);
    }
    if (base.isEmpty) {
      return _fail(jobId, '未配置后端地址,请在「我的」页或授权页填写', GenOutcome.notCharged);
    }

    final total = s.params.activeSteps;
    final abort = run.abort;

    // bot 无逐步步数,走不确定态;续张同样就地刷新不重拉服务。
    await _beginIsland(0);

    final client = ref.read(backendClientProvider);
    final seed = _resolveSeed(s.params.seed);

    // 任务是否已提交成功(拿到 taskId):之后再失败就分不清服务端有没有开跑,
    // 按最坏情况算,不让队列自动重试。
    var submitted = false;

    var attempt429 = 0;
    while (true) {
      try {
        // 参考图:CR / 图生图离线处理;vibe 走统一编码服务(缓存,避免重复扣 2 Anlas)
        final img2img = await _processImg2Img(s);
        final charRefs = await _processCharRefs(s);
        final prepared = await _prepareVibes(s);
        final styleRefs = await _processKreaStyleRefs(s);
        final preset = _applyPreset(s, await run.presets);
        final params = buildBotParams(
          preset.state,
          seed: seed,
          presetId: preset.presetId,
          qualityToggle: preset.qualityToggle,
          straightAlpha: _straightAlpha,
          img2img: img2img,
          charRefs: charRefs,
          vibes: [
            for (final v in prepared)
              (
                encodedVibe: v.encoded,
                strength: v.strength,
                infoExtracted: v.infoExtracted,
              ),
          ],
          kreaStyleRefs: styleRefs,
        );

        if (abort.aborted) return _cancelled(jobId);
        final sub = await client.botGenerate(
          sessionId: session.sessionId,
          params: params,
          // anima / krea → 服务端 Modal ComfyUI 后端(共用同一条队列与 WS 通道,
          // 任务表也与 NAI 共用);两者的参数各进自己的 *_extra。
          imageBackend: switch (providerOfModel(s.params.model)) {
            GenProvider.anima => 'anima',
            GenProvider.krea => 'krea',
            GenProvider.nai => 'novelai',
          },
        );
        if (!sub.success || sub.taskId == null || sub.taskId!.isEmpty) {
          throw BackendException(sub.message.isEmpty ? '任务提交失败' : sub.message);
        }
        submitted = true;
        run.taskId = sub.taskId; // 供 cancelJob() 撤单
        _patch(jobId, (j) => j.copyWith(taskId: sub.taskId));

        // 提交在路上时点的取消:那会儿 taskId 还是 null,cancelJob 没东西可撤,
        // 而任务其实已经在服务端建好了 —— 不在这补一刀,它会照常排队、照常出图、
        // 照常收钱,而 app 这边显示的是「已取消」。
        if (abort.aborted) {
          unawaited(
            client.cancelTask(sub.taskId!, sessionId: session.sessionId),
          );
          return _cancelled(jobId);
        }

        // 流式:WS 逐步预览 + 轮询兜底
        final bytes = await streamBotTask(
          baseUrl: base,
          sessionId: session.sessionId,
          taskId: sub.taskId!,
          client: client,
          onProgress: (step, tot, preview, text) {
            // 采样前那段服务端报 total=0,照抄的话会把建任务时按档位算好的
            // 总步数抹成 0,进度条分母就没了
            final t = tot > 0 ? tot : total;
            _patch(
              jobId,
              (j) => j.copyWith(
                stage: GenJobStage.running,
                step: step,
                total: t,
                // 服务端在同一条消息里既给读数也给阶段文案(「生成中 3/36」、
                // 采样跑满之后的「取图中」)。一律清掉的话那句「取图中」会被
                // 这条消息自己抹掉 —— 而那正是用户盯着满进度条等图的几秒。
                // 没带文案才清(免费档、以及残留的排队位次)。
                note: text.isEmpty ? null : text,
                clearNote: text.isEmpty,
                prepPct: -1, // 有读数了,准备阶段那根条的百分比作废
                preview: preview,
              ),
            );
            _pushProgress();
          },
          onQueue: (pos) {
            // 轮询兜底可能晚于 WS 进度到达:已在出图就忽略迟到的排队消息
            if ((_job(jobId)?.step ?? 0) > 0) return;
            // 位次用 `#N` 而不是「第 N」:与 web 的状态条同一种写法,也短 ——
            // 这串要塞进重绘面板那条窄 CTA(实测「排队 · 第 12」会顶出界),
            // 状态栏胶囊那格更只装得下两三个字符。
            final text = pos > 0 ? '排队 #$pos' : '排队中';
            _patch(
              jobId,
              (j) => j.copyWith(stage: GenJobStage.queued, note: text),
            );
            _pushIndeterminate(text, pos > 0 ? '#$pos' : '排队');
          },
          onWarning: (msg) => ref.read(genNoticeProvider.notifier).show(msg),
          onStage: (note, pct) {
            // **没有步数**那几段的文案:anima Modal 冷启动,以及付费档实例在
            // 采样开始前下发的 stage_text(准备 LoRA / 加载模型)。
            //
            // 采样跑满之后的「取图中」不走这里 —— 它带着满读数,由 onProgress
            // 连文案一起收下。之前那次是分两条回调发的,后到的读数把文案抹了。
            //
            // pct 每次都要重写(-1 也写):换阶段服务端就不再下发这个字段,
            // 沿用上一条的话「加载模型」会顶着「拉 LoRA」留下的 100% 不动。
            _patch(jobId, (j) => j.copyWith(note: note, prepPct: pct));
            _pushIndeterminate(note, '生成中');
          },
          abort: abort,
        );

        await _storeResult(s, bytes, seed, jobId: jobId);
        unawaited(
          ref.read(anlasProvider.notifier).refresh(),
        ); // 生成后刷新点数(对齐 web)
        // nai5 出一张就扣一张自己的配额,顶栏那格得跟着动。其它模型不扣,
        // 但也照拉 —— 免额度窗口开合、回充推进同样会让读数变。
        unawaited(ref.read(naiQuotaProvider.notifier).refresh());
        if (!_inFlow) {
          _endIsland(success: true);
          _kickQueue();
        }
        return GenOutcome.ok;
      } on BackendException catch (e) {
        if (abort.aborted) return _cancelled(jobId);
        if (await _wait429(jobId, e.status, attempt429)) {
          attempt429++;
          continue;
        }
        logi('[gen/bot] 失败: ${e.message} (submitted=$submitted)');
        // 任务已提交成功(拿到 taskId)之后再失败,服务端很可能已经开跑并计费。
        // 例外是额度类拒绝:服务端会把预扣退回去,而且退了也白搭 —— 交给 _botFail。
        return _botFail(
          jobId,
          e.message,
          !submitted || _rejectedOutright(e.status)
              ? GenOutcome.notCharged
              : GenOutcome.maybeCharged,
        );
      } catch (e) {
        if (abort.aborted) return _cancelled(jobId);
        logi('[gen/bot] 失败: $e (submitted=$submitted)');
        return _botFail(
          jobId,
          '生成失败:$e',
          submitted ? GenOutcome.maybeCharged : GenOutcome.notCharged,
        );
      }
    }
  }

  /// 启用的 Vibe → 编码串+参数,直连/bot 共用(统一编码服务:内容寻址缓存
  /// 优先,miss 按当前授权线现场编码扣 2 Anlas)。
  /// 纯编码 vibe(库导入、无原图)直接取当前模型的编码,取不到则跳过。
  Future<List<({String encoded, double strength, double infoExtracted})>>
  _prepareVibes(GenerateState s) async {
    final vibes = s.vibes.where((v) => v.enabled).toList();
    if (vibes.isEmpty) return const [];
    final model = naiModelId(s.params.model);
    final encoder = ref.read(vibeEncoderProvider);
    final out = <({String encoded, double strength, double infoExtracted})>[];
    for (final v in vibes) {
      final img = v.image;
      final String enc;
      if (img != null) {
        // 哈希缺失(不应发生)时现算,保证仍走缓存不重复扣点
        final hash = v.imageHash ?? sha256HexOfBytes(img);
        enc = await encoder.encode(
          image: img,
          imageHash: hash,
          model: model,
          infoExtracted: v.infoExtracted,
        );
      } else {
        final byModel = v.encodedByModel?[kModelToEncodingKey[model] ?? model];
        if (byModel == null) {
          logd('[vibe] ${v.name} 无 $model 编码且无原图,跳过');
          continue;
        }
        enc = byModel;
      }
      out.add((
        encoded: enc,
        strength: v.strength,
        infoExtracted: v.infoExtracted,
      ));
    }
    return out;
  }

  int _resolveSeed(String seedStr) {
    final v = seedStr.trim();
    if (v.isEmpty) return Random().nextInt(4294967296);
    return int.tryParse(v) ?? Random().nextInt(4294967296);
  }

  /// 不确定态进度(排队中),≤~1/s 节流。[short] 是状态栏胶囊那几个字,
  /// 别再传省略号——胶囊上只显示得下它,写「…」等于什么都没说。
  void _pushIndeterminate(String text, String short) {
    if (!_notify) return;
    final now = DateTime.now();
    if (_lastPush != null && now.difference(_lastPush!).inMilliseconds < 800) {
      return;
    }
    _lastPush = now;
    final ls = _flowShort;
    LiveProgress.instance.update(
      indeterminate: true,
      title: text,
      text: _flowNote,
      short: ls.isEmpty ? short : ls,
    );
  }

  /// 图生图底图:cover 到当前目标分辨率 → PNG base64。无底图返回 null。
  /// 快照带重绘任务时跳过(重绘与图生图互斥,inpaint 优先)。
  Future<Img2ImgRef?> _processImg2Img(GenerateState s) async {
    if (s.inpaint != null) return null;
    final cfg = s.img2img;
    final img = cfg?.image;
    if (cfg == null || img == null) return null;
    // 源图真带 alpha 才保住它:透明图垫黑底 = 把透明区烧成黑色,
    // 而不透明图垫不垫都看不见(cover 铺满画布),维持旧行为即可。
    final png = await coverResizePng(
      img,
      s.params.width,
      s.params.height,
      keepAlpha: await pngHasAlpha(img),
    );
    return (
      image: base64Encode(png),
      strength: cfg.strength,
      noise: cfg.noise,
      upscaledEnhance: cfg.upscaledEnhance,
    );
  }

  /// 结果入库(直连/bot 共用):局部重绘先把结果贴回原图,
  /// 重绘任务统一打「重绘」角标;快照原样入库供「重新生成」复现。
  /// 一次采样的产出入库。[batch] 是这一批的全部 PNG —— anima / krea 的
  /// `batch_size` 让一次采样出 N 张(NAI 那条路恒为 1)。
  ///
  /// N 张各自成为一条图库记录,但**只有第 0 张可能抢画布**:
  /// ① 它是「主」的那张(seed 直接对应它);
  /// ② 后面几张跟着抢焦点的话,画布会在入库过程中连闪 N 次。
  Future<void> _storeResult(
    GenerateState s,
    List<Uint8List> batch,
    int seed, {
    required String jobId,
  }) async {
    if (batch.isEmpty) return;
    // 画布正跟着这条 → 出图后把画布交给成图;跟着别的(或在看历史)→ 只前插、
    // **不夺焦点**。并行之后这条最要紧:后台某一张出完就把你正看着的画面换掉,
    // 比不显示还糟。
    //
    // 先记住跟随意图；异步保存期间用户切图或跟随其他任务时不再抢回画布。
    final followed = state.selectedId == jobId;
    final focusRevision = _focusRevision;
    final galleryTarget =
        _job(jobId)?.galleryTarget ?? const GallerySaveTarget.all();
    // 保存/缩略图/图库归属都有异步间隙。此时撤任务会让画布短暂露出旧图，
    // 必须保留终图，等主图选中（或建立跨图库临时预览）后再交给历史。
    _patch(
      jobId,
      (j) => j.copyWith(
        stage: GenJobStage.saving,
        preview: batch.first,
        step: j.total > 0 ? j.total : 1,
        total: j.total > 0 ? j.total : 1,
        prepPct: -1,
        note: '保存中',
      ),
    );
    final origin = _runs[jobId]?.origin;
    final ids = <String>[];
    for (var i = 0; i < batch.length; i++) {
      ids.add(
        await _storeOne(
          s,
          batch[i],
          seed,
          batchIndex: batch.length > 1 ? i : -1,
          select: followed && i == 0,
          galleryTarget: galleryTarget,
          canSelect: () => _focusRevision == focusRevision,
        ),
      );
    }
    _remove(jobId);
    if (origin != null) _recordHistory(origin, ids);
    // 库来源的 vibe 回写「最近使用」(fire-and-forget,失败无害)
    final usedVibeIds = {
      for (final v in s.vibes)
        if (v.enabled && v.sourceId != null) v.sourceId!,
    };
    if (usedVibeIds.isNotEmpty) {
      unawaited(ref.read(vibeLibraryProvider.notifier).markUsed(usedVibeIds));
    }
    // 库来源的角色参考回写「最近使用」(内容哈希即库条目 id)
    final usedCharRefIds = {
      for (final r in s.charRefs)
        if (r.enabled && r.imageHash != null) r.imageHash!,
    };
    if (usedCharRefIds.isNotEmpty) {
      unawaited(
        ref.read(charLibraryProvider.notifier).markUsed(usedCharRefIds),
      );
    }
  }

  /// 出的图记进发起那张画布的历史;那张画布已经删了就不记。
  void _recordHistory(CanvasOrigin origin, List<String> ids) {
    if (ref.read(canvasWorkspaceProvider).find(origin.canvasId) == null) return;
    final history = ref.read(appStoresProvider).history;
    unawaited(
      history.record(origin.canvasId, origin.content, ids).then((_) {
        if (ref.mounted) ref.invalidate(canvasHistoryProvider(origin.canvasId));
      }),
    );
  }

  /// 批里的一张入库(重绘贴回 + 落盘),返回图库 id。[batchIndex] < 0 = 不是批次产物。
  Future<String> _storeOne(
    GenerateState s,
    Uint8List bytes,
    int seed, {
    required int batchIndex,
    required bool select,
    required GallerySaveTarget galleryTarget,
    required bool Function() canSelect,
  }) async {
    final job = s.inpaint;
    var out = bytes;
    var w = s.params.width;
    var h = s.params.height;
    final paste = job?.paste;
    if (paste != null) {
      try {
        out = await pasteBack(
          original: paste.original,
          patch: bytes,
          send: (x: paste.sendX, y: paste.sendY, w: w, h: h),
          tight: (
            x: paste.tightX,
            y: paste.tightY,
            w: paste.tightW,
            h: paste.tightH,
          ),
        );
        w = paste.outW;
        h = paste.outH;
      } catch (e) {
        logd('[gen] pasteBack failed: $e'); // 贴回失败退化为子图入库
      }
    } else if (pngSizeOf(bytes) case (final pw, final ph)) {
      // 按成图实际尺寸记:Max 放大重绘、Anima 重绘放大的出图都比请求宽高大
      w = pw;
      h = ph;
    }
    final r = await ref
        .read(galleryProvider.notifier)
        .addResultToGallery(
          target: galleryTarget,
          canSelect: canSelect,
          notify: batchIndex <= 0,
          bytes: out,
          width: w,
          height: h,
          seed: seed,
          batchIndex: batchIndex,
          badge: job != null ? ResultBadge.inpaint : ResultBadge.none,
          // 「按住对比」要拿原图,只记 id —— 源图本来就在库里。
          inpaintFrom: job?.sourceId,
          input: s, // 参数快照,供图库「重新生成」按本图参数复现
          select: select,
        );
    return r.id;
  }

  /// Krea 风格参考:每张启用的下采样成 JPEG base64。非 krea 模型返回空
  /// (数据本身留在工作区,切回来还在;剥离层也会先把不可见模块的清掉)。
  Future<List<String>> _processKreaStyleRefs(GenerateState s) async {
    if (!isKreaModel(s.params.model)) return const [];
    final refs = s.activeKreaStyleRefs;
    if (refs.isEmpty) return const [];
    final out = <String>[];
    for (final r in refs) {
      final jpg = await styleRefResizeJpg(
        r.image!,
        maxDim: kKreaStyleRefMaxDim,
      );
      out.add(base64Encode(jpg));
    }
    return out;
  }

  /// 角色参考:每张启用且有图的 contain 处理成 PNG base64(无编码调用、免 Anlas)。
  /// 是否真正下发由载荷层按模型 gate(仅 4.5)。
  Future<List<CharRefPayload>> _processCharRefs(GenerateState s) async {
    final refs = s.charRefs.where((r) => r.enabled && r.image != null).toList();
    if (refs.isEmpty) return const [];
    final out = <CharRefPayload>[];
    for (final r in refs) {
      final png = await crResizePng(r.image!);
      out.add((
        image: base64Encode(png),
        mode: r.mode.api,
        strength: r.strength,
        fidelity: r.infoExtracted,
      ));
    }
    return out;
  }

  /// 直连生成落一笔本机账。点数为估算(与费用胶囊同一公式,免费档 0;
  /// 重绘按发送尺寸/强度折算);记账失败不打扰生成主流程。
  ///
  /// 按**这一单实际落在的那个号**([t])算:它是不是 Opus、V5 额度见没见底,
  /// 决定了这张是 0 点还是照扣 —— 一律按主账号记的话,副账号实扣了点,账上是 0。
  /// 读数优先用挑号时查到的那份:额度就是这一张花掉的,跑完再查只会看到花过
  /// 之后的数。
  void _recordKeyGen(GenerateState s, NaiTarget t) {
    final statuses = ref.read(naiKeyStatusCacheProvider);
    final atDispatch = statuses.peek(t);
    unawaited(() async {
      try {
        // 挑号时没查(这一单在哪个号上都扣点,挑号用不着)就现查。查不到按收费
        // 记:回退成 false 而不是 true —— 订阅拉不到时按钮上显示的也是收费,
        // 两边口径必须一致;回退 true 会让账本在网络最不稳的时候系统性少记,
        // 而那正是最需要记准的时候。见 S1B-02。
        final sub = atDispatch ?? await statuses.get(t);
        final b = _billed(s);
        final job = b.inpaint;
        ref
            .read(appStoresProvider)
            .ledger
            .recordGen(
              pts: _costOn(
                b,
                isOpus: sub?.isOpus ?? false,
                // V5 额度见底后免费尺寸是照扣 Anlas 的,本机账本不能记 0
                v5Charged: sub?.usage?.isNegative ?? false,
              ),
              width: b.params.width,
              height: b.params.height,
              steps: b.params.naiSteps,
              model: b.params.model,
              inpaint: job != null,
              // 判定留在这边而不是让账本去解析 model 串:那是存储层,不该认识
              // 产品的展示名规则(改一次命名两处就会分叉)
              v5: isNai5Model(b.params.model),
            );
      } catch (_) {}
    }());
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../util/log.dart';
import '../util/webp_to_png.dart';
import 'backend_client.dart';
import 'bot_socket.dart';
import 'gen_abort.dart';

/// 跑一个 bot 生成任务的实时链路:WebSocket `/ws/bot`(逐步进度 + 中间预览图)
/// 为主,HTTP 轮询 `GET /api/bot/task/{id}` 为兜底(防 WS 丢消息/连不上)。
/// 首个到达完成/失败的通道胜出。失败抛 [BackendException]。
///
/// 返回的是**这一批的全部 PNG**:anima / krea 的 `batch_size` 让一次采样出
/// N 张(上限 4),它们共用一条任务、一份进度,只在结果里分开。单张时列表
/// 长度就是 1 —— 调用方不用分两条路走。
///
/// - [onProgress] `(step, total, preview?, stageText)`:逐步进度。同一条消息里
///   可能**既有读数也有阶段文案**(「生成中 3/36」、采样跑满之后的「取图中」),
///   所以文案跟着这一路一起给 —— 分两次回调的话后到的那次会把先到的抹掉。
///
///   ⚠ 预览帧走的是 WS 的**二进制帧**(2026-09-04 起),不再是 `task_progress`
///   里的 base64 字段:省 33% 体积,也省掉这边先 base64Decode 出一个上兆
///   字节数组那一步。服务端先发 JSON 读数、紧接着发二进制帧,所以拿到帧时
///   用记住的那份读数回调即可。**帧数没有抽稀**,流畅度和以前一致。
/// - [onQueue] `(queuePos)`:排队中。
/// - [onStage] `(note, pct)`:**没有步数**那几段的文案。两个来源 ——
///   ① anima Modal 冷启动(`status=starting`),pct 恒为 -1;
///   ② 服务端在 `task_progress` 里下发的 `stage_text`(付费档实例给的:
///      准备 LoRA / 加载模型;免费档暂时不带这个字段)。
///   ⚠ 轮询兜底那条路**没有** stage_text(GetTaskResponse 里没这个字段),
///     WS 断了就退回原来的表现,不是 bug。
/// - [onWarning] `(msg)`:非致命提醒(如 LoRA 超上限被丢弃),图照常出,只触发一次。
/// 读一条 `task_progress`:阶段文案、准备阶段百分比,以及**这条里的步数读数
/// 能不能采信**。
///
/// 采样开始**之前**那几十秒(拉 LoRA、加载模型)服务端也会推进度消息,那时真实
/// step/total 都是 0。这段该显示的是文案和 [pct],不是步数。
///
/// [useSteps] 挡的是**老服务端**:它当年把 0 按 `max(step,1)/max(total,1)` 夹成
/// 1/1 下发(为的是让自己那条 `step > 0` 的推送条件成立),照单全收的话进度条会
/// 在装模型时就顶到满格然后停住 —— 比没有进度更糟。判据是「有阶段文案 + 读数
/// 恰好是那个 1/1」:免费档不带 stage_text,所以 NAI 真的只跑一步(step=1,
/// total=1)时不受影响,照常按 1/1 显示。新服务端直接报 0/0,这条自然也成立。
///
/// [pct] 是准备阶段的百分比(0..100),-1 = 这段没有可量化进度。现在只有「拉
/// LoRA」给得出来,加载模型那段是 -1。⚠ **换阶段服务端就不再下发这个字段**,
/// 所以取不到时必须回到 -1、不能沿用上一条 —— 否则「加载模型」会顶着上一段
/// 留下的 100% 不动,比没有进度条更像卡死。
({String stage, int step, int total, int pct, bool useSteps}) readProgressMsg(
  Map<String, dynamic> m,
) {
  final stage = (m['stage_text'] as String? ?? '').trim();
  final step = (m['step'] as num?)?.toInt() ?? 0;
  final total = (m['total_steps'] as num?)?.toInt() ?? 0;
  final pct = (m['phase_pct'] as num?)?.toInt() ?? -1;
  return (
    stage: stage,
    step: step,
    total: total,
    pct: pct < 0 ? -1 : (pct > 100 ? 100 : pct),
    useSteps: !(stage.isNotEmpty && step <= 1 && total <= 1),
  );
}

Future<List<Uint8List>> streamBotTask({
  required String baseUrl,
  required String sessionId,
  required String taskId,
  required BackendClient client,
  void Function(int step, int total, Uint8List? preview, String stageText)?
  onProgress,
  void Function(int queuePos)? onQueue,
  void Function(String note, int pct)? onStage,
  void Function(String msg)? onWarning,
  GenAbort? abort,
  // 成图保持后端发来的 WebP,不还原成 PNG(生成设置「保持图片格式」)
  bool keepWebp = false,
  // 必须**大于**服务端的 MODAL_ANIMA_GEN_TIMEOUT(现 720s),否则这边先喊超时、
  // 服务端却还在跑并占着并发槽,用户看到的是一条比真实情况更早也更没用的错误。
  // 13 分钟留了 60s 余量吸收轮询间隔与网络往返(与 web botService 同值)。
  // 此前是 5 分钟,与当时的服务端总预算 300s 撞在一起,k2 raw 高步数把两边都顶穿了。
  //
  // ⚠ 这是**采样期**的预算,不含准备阶段 —— 见下面 armWatchdog 的说明。
  Duration timeout = const Duration(minutes: 13),
}) async {
  final completer = Completer<List<Uint8List>>();
  final sw = Stopwatch()..start();
  var lastStep = -1;
  // WS 和轮询都会带同一条 warning,只报一次
  var warned = false;

  void fail(Object e) {
    if (!completer.isCompleted) {
      logi('[bot] $taskId fail: $e');
      completer.completeError(
        e is BackendException ? e : BackendException('$e'),
      );
    }
  }

  /// 完成。[urls] 是这一批全部图的 URL(单张时长度 1)—— 控制平面只给 URL,
  /// 字节在这里**并发取一次**。整批要么全成要么整批失败:半批图入库比没有图
  /// 更糟,用户看不出少了哪张。
  ///
  /// [fetching] 挡的是重复取:WS 和轮询都会报 completed,让两边各取一遍就把
  /// 省下来的流量又花回去了。
  ///
  /// **失败重试一次**:图已经画完了(钱也花了),这一步再丢就太亏。移动网络
  /// 上一次瞬时失败很常见,而结果在服务端只留 10 分钟 —— 值得赌这一次,但
  /// 不值得赌第二次。
  var fetching = false;
  // WS 推来的成图(序号 → 字节),先于完成消息到达。收齐了就不用再下载。
  final pushed = <int, Uint8List>{};

  /// 提交时声明了 result_format=webp(见 BackendClient.botGenerate):NAI 的成图是原样的
  /// 无损 WebP,按 [keepWebp] 原样交或还原成 PNG。本地还原不了就取后端现转的 PNG。
  Future<Uint8List> toPng(Uint8List b, String url) async {
    if (keepWebp || !isWebp(b)) return b;
    try {
      return await compute(webpToPng, b);
    } catch (e) {
      logi('[bot] $taskId WebP 本地还原失败,改取后端还原的 PNG: $e');
      return client.fetchResultImage('$url?fmt=png');
    }
  }

  Future<void> finish(
    List<Uint8List> raw,
    List<String> urls,
    String via,
  ) async {
    try {
      final out = await Future.wait([
        for (var i = 0; i < raw.length; i++) toPng(raw[i], urls[i]),
      ]);
      logi(
        '[bot] $taskId done$via: ${out.length} 张 / '
        '${raw.fold<int>(0, (a, b) => a + b.length)}B',
      );
      if (!completer.isCompleted) completer.complete(out);
    } catch (e) {
      fail(e is BackendException ? e : BackendException('取结果图失败: $e'));
    }
  }

  Future<void> done(List<String> urls) async {
    if (completer.isCompleted || fetching) return;
    fetching = true;
    if (pushed.length == urls.length &&
        Iterable<int>.generate(urls.length).every(pushed.containsKey)) {
      await finish(
        [for (var i = 0; i < urls.length; i++) pushed[i]!],
        urls,
        '(WS 推送)',
      );
      return;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      if (completer.isCompleted) return;
      final List<Uint8List> raw;
      try {
        raw = await Future.wait([
          for (final u in urls) client.fetchResultImage(u),
        ]);
      } catch (e) {
        if (attempt == 0) {
          logi('[bot] $taskId 取结果图失败,重试一次: $e');
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        fail(e is BackendException ? e : BackendException('取结果图失败: $e'));
        return;
      }
      await finish(raw, urls, '');
      return;
    }
  }

  // 取消:停止等待(WS/轮询在 finally 里一并收);后端任务由控制器据 aborted
  // 判定为取消,不入库。服务端那条任务由控制器 cancel() 调
  // `DELETE /api/task/{id}` 撤(只对排队中的有效),这里只管收手不等。
  abort?.whenAbort(() {
    logi('[bot] $taskId abort hook fired');
    fail(BackendException('已取消生成'));
  });

  void warn(String? msg) {
    if (warned || msg == null || msg.isEmpty) return;
    warned = true;
    logi('[bot] $taskId warning: $msg');
    onWarning?.call(msg);
  }

  // ⚠ **这里不做单调递增守卫**。步数回退是**合法的**:anima 的重绘放大
  // (hires 二段)先出小图定构图、放大后再低 denoise 采样一遍,第二段的 step
  // 从 1 重新开始 —— 挡了它整段进度都被吃掉,条卡在满格不动直到出图。
  // WS 本身保证消息有序,不需要这层防护;真正会乱序的是下面那条 HTTP 轮询
  // 兜底,防回退放在它自己那边。
  // 预览帧是独立的二进制消息,到达时手里没有读数 —— 记住紧挨着它的那条
  // task_progress 的读数,配着一起回调。
  var lastTotal = 0;
  var lastStage = '';

  void progress(int step, int total, Uint8List? preview, String stageText) {
    lastStep = step;
    lastTotal = total;
    lastStage = stageText;
    onProgress?.call(step, total, preview, stageText);
  }

  // 超时看门狗。**准备阶段(拉 LoRA / 加载模型)会把它重新上弦** ——
  // 服务端那 600s 出图预算是**采样期单独**的,不含准备:跨境把一个 448MB 的
  // LoRA 拉下来,R2 慢的时候只有 0.84 MB/s,那就是 9 分钟,加载模型那段更是
  // 一个事件都没有。用同一把尺子量会在正常出图时把自己掐掉,而服务端还在跑、
  // 还在计费,用户拿到的是一条比真实情况更早也更没用的错误。
  Timer? watchdog;
  void armWatchdog() {
    watchdog?.cancel();
    watchdog = Timer(timeout, () => fail(BackendException('生成超时,请稍后在图库确认')));
  }

  armWatchdog();

  /// 一帧二进制预览(头已由 [BotSocket] 解掉)。帧头里的 step/total 只供调试,
  /// **进度以 task_progress 为准** —— 那条紧挨着二进制帧发送,而且带着「准备
  /// 阶段读数不可采信」那套判据(readProgressMsg 的 useSteps)。
  void handleBinary(Uint8List preview) {
    onProgress?.call(
      lastStep < 0 ? 0 : lastStep,
      lastTotal,
      preview,
      lastStage,
    );
  }

  void handle(Map<String, dynamic> m) {
    switch (m['action']) {
      case 'task_progress':
        // 预览帧不在这条消息里了(走二进制帧),这里只有读数和文案
        final r = readProgressMsg(m);
        if (r.useSteps) {
          progress(r.step, r.total, null, r.stage);
        } else if (r.stage.isNotEmpty) {
          // 准备阶段:没有步数,只有文案和百分比。这段可能真要好几分钟,
          // 每收到一条就把死线往后推,别让正常出图被自己的超时掐掉。
          armWatchdog();
          onStage?.call(r.stage, r.pct);
        }
        break;
      case 'task_update':
        logi('[bot] $taskId ws: status=${m['status']}');
        warn(m['warning'] as String?);
        switch (m['status']) {
          case 'completed':
            // batch:结果里额外带了 urls(含第一张);单张时只有 url。
            // 两条都空才是真没图 —— 见 botResultUrls。
            final all = botResultUrls(m['result']);
            if (all.isNotEmpty) {
              unawaited(done(all));
            } else {
              // completed 但没带图:不能吞掉,否则会一直卡在最后一步等结果
              logi('[bot] $taskId ws completed 无图,等轮询取结果');
            }
            break;
          case 'failed':
          case 'cancelled':
            fail(BackendException((m['error'] as String?) ?? '生成失败'));
            break;
          case 'queued':
            onQueue?.call((m['queue_position'] as num?)?.toInt() ?? 0);
            break;
          case 'starting': // anima:Modal 容器冷启动(约 20~60 秒)
            onStage?.call('模型启动中…', -1);
            break;
        }
        break;
    }
  }

  // —— WS 主链路:共用常驻连接(连不上就纯靠轮询兜底)——
  final wsSub = BotSocket.instance.subscribe(
    base: baseUrl,
    sessionId: sessionId,
    taskId: taskId,
    onJson: handle,
    onBinary: handleBinary,
    onResult: (i, _, bytes) => pushed[i] = bytes,
  );

  // —— HTTP 轮询兜底(每 2.5s)——
  // 连续失败计数:断网时 WS 已死、轮询静默空转,原先只能干等满 [timeout](5 分钟)。
  // 20 秒内一次都联系不上后端就判定断链 —— 此时 WS 走的是同一条网络,不可能还活着。
  var pollFails = 0;
  const maxPollFails = 8; // × 2.5s = 20s
  String? lastPolled; // 状态转移才记日志,避免 2.5s 一条刷屏

  // 轮询是**兜底,不是并行通道**:WS 活着时结果和进度都从那边来,这边只需要
  // 一个低频的存活探测。2.5s 一轮打满一次生成要二十多个请求,全是白问。
  // WS 一断立刻回到 2.5s,兜底能力不变。
  var lastPollAt = 0;
  final poll = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
    if (completer.isCompleted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final gap = wsSub.live ? 30000 : 2500;
    if (now - lastPollAt < gap) return;
    lastPollAt = now;
    try {
      final t = await client.getTask(sessionId: sessionId, taskId: taskId);
      pollFails = 0; // 联系上了就清零
      if (t.status != lastPolled) {
        lastPolled = t.status;
        logi(
          '[bot] $taskId poll: status=${t.status} ${t.step}/${t.totalSteps}',
        );
      }
      if (!t.success) return; // 尚未可见,继续
      warn(t.warning);
      if (t.completed) {
        if (t.urls.isNotEmpty) {
          await done(t.urls);
        } else {
          logi('[bot] $taskId poll completed 但 result 无图');
        }
      } else if (t.failed) {
        fail(BackendException(t.error ?? '生成失败'));
      } else if (t.status == 'queued') {
        onQueue?.call(t.queuePosition);
      } else if (t.status == 'starting') {
        onStage?.call('模型启动中…', -1);
      } else {
        // ⚠ WS 通着的时候**轮询一律不碰进度**:它粒度粗、还可能是几秒前的旧值,
        //   和 WS 抢着写只会让进度条抖;而且它分不清「重绘二段合法归零」和
        //   「过期数据回退」,让它出手就会误判。
        if (wsSub.live) return;
        if (t.step < lastStep) return; // WS 已死,这条兜底自己防回退
        progress(t.step, t.totalSteps, null, '');
      }
    } on BackendException catch (e) {
      if (e.status == 401) {
        fail(e); // 会话失效直接终止
      } else if (++pollFails >= maxPollFails) {
        fail(BackendException('与后端失去连接,请检查网络'));
      }
    } catch (_) {
      if (++pollFails >= maxPollFails) {
        fail(BackendException('与后端失去连接,请检查网络'));
      }
    }
  });

  try {
    final out = await completer.future;
    final kib = out.fold<int>(0, (a, b) => a + b.length) ~/ 1024;
    logi('[bot] $taskId 收图 ${sw.elapsedMilliseconds}ms · $kib KiB');
    return out;
  } finally {
    watchdog?.cancel();
    poll.cancel();
    wsSub.cancel();
  }
}

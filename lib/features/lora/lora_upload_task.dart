import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/backend_client.dart';
import 'lora_providers.dart';

/// 后台上传 LoRA(跨页面存活,同 [loraInstallQueueProvider] 的范式)。
///
/// 跨境上传一个几百兆的 LoRA 要好几分钟,以前传输跑在管理器页里,退出页面结果
/// 就没人接了,只能钉在那页干等。现在上传和之后盯「推送机房」都跑在 provider 上:
/// 表单交上来就能返回去出图,生成页的 LoRA 卡显示进度,结束时交给订阅方提示。
///
/// 同一时间只传一个(入口在传的时候是禁用的)。
enum LoraUploadPhase { sending, verifying, pushing }

class LoraUploadJob {
  const LoraUploadJob({
    required this.name,
    required this.base,
    this.pct = 0,
    this.phase = LoraUploadPhase.sending,
  });

  final String name;

  /// 传进哪个底模的库。开始时定死:传的过程中用户可能已经切走模型。
  final String base;

  /// 0~100,发出去的比例。
  final int pct;
  final LoraUploadPhase phase;

  /// 「45%」/「校验中」/「推送中」
  String get progressText => switch (phase) {
    LoraUploadPhase.sending => '$pct%',
    LoraUploadPhase.verifying => '校验中',
    LoraUploadPhase.pushing => '推送中',
  };
}

/// 一次上传的结论。[ok] 为假时 [message] 是给人看的原因。
class LoraUploadOutcome {
  const LoraUploadOutcome({
    required this.name,
    required this.base,
    required this.ok,
    this.lrId,
    this.dedup = false,
    this.message = '',
  });

  final String name;
  final String base;
  final bool ok;
  final String? lrId;

  /// 同一个文件库里已经有了,没重复存,直接替你收藏了那条。
  final bool dedup;
  final String message;
}

final loraUploadTaskProvider = NotifierProvider<LoraUploadTask, LoraUploadJob?>(
  LoraUploadTask.new,
);

class LoraUploadTask extends Notifier<LoraUploadJob?> {
  @override
  LoraUploadJob? build() => null;

  /// 结论的订阅方,**后注册的先问**,谁返回 true 谁就接走了(不再往下传)。
  /// 管理器页开着时它最后注册,由它替用户选上并提示;不在时落到生成页的卡片。
  final _handlers = <bool Function(LoraUploadOutcome)>[];

  void Function() onFinished(bool Function(LoraUploadOutcome) h) {
    _handlers.add(h);
    return () => _handlers.remove(h);
  }

  bool get busy => state != null;

  /// 开始上传;已经有一个在传就返回 false。
  bool start({
    required String sessionId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String displayName,
    required List<String> triggerGroups,
    required String type,
    required bool public,
    required String base,
  }) {
    if (busy) return false;
    state = LoraUploadJob(name: displayName, base: base);
    unawaited(
      _run(
        sessionId: sessionId,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        displayName: displayName,
        triggerGroups: triggerGroups,
        type: type,
        public: public,
        base: base,
      ),
    );
    return true;
  }

  Future<void> _run({
    required String sessionId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String displayName,
    required List<String> triggerGroups,
    required String type,
    required bool public,
    required String base,
  }) async {
    LoraUploadOutcome outcome;
    final backend = ref.read(backendClientProvider);
    try {
      final r = await backend.uploadLora(
        sessionId: sessionId,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        displayName: displayName,
        triggerGroups: triggerGroups,
        type: type,
        public: public,
        base: base,
        onProgress: (p) {
          // 每块都回调(几百兆能有几千次),整数百分比不变就不重建
          final v = (p * 100).clamp(0, 100).round();
          final cur = state;
          if (cur == null || v == cur.pct) return;
          state = LoraUploadJob(
            name: displayName,
            base: base,
            pct: v,
            // 发完之后还要等服务端校验完整份文件才回执
            phase: v >= 100
                ? LoraUploadPhase.verifying
                : LoraUploadPhase.sending,
          );
        },
      );
      if (!r.ok || r.lrId == null) {
        outcome = LoraUploadOutcome(
          name: displayName,
          base: base,
          ok: false,
          message: r.message.isEmpty ? '上传失败' : r.message,
        );
      } else if (r.dedup) {
        outcome = LoraUploadOutcome(
          name: displayName,
          base: base,
          ok: true,
          lrId: r.lrId,
          dedup: true,
          message: r.message,
        );
      } else {
        state = LoraUploadJob(
          name: displayName,
          base: base,
          pct: 100,
          phase: LoraUploadPhase.pushing,
        );
        outcome = await _waitPushed(backend, r.lrId!, displayName, base);
      }
    } catch (e) {
      outcome = LoraUploadOutcome(
        name: displayName,
        base: base,
        ok: false,
        message: '$e',
      );
    }
    state = null;
    // 「我的」列表要出现这条 / 状态要变:管理器开没开都刷一下缓存
    unawaited(ref.read(installedLorasProvider(base).notifier).reload());
    for (final h in _handlers.reversed.toList()) {
      if (h(outcome)) break;
    }
  }

  /// 服务端收完只做校验登记就回执,推进机房是它的后台活:3 秒一问到有结论。
  /// 网络抖一下不算数;问了 10 分钟还没结论就不等了(卡片上能看到状态)。
  Future<LoraUploadOutcome> _waitPushed(
    BackendClient backend,
    String lrId,
    String name,
    String base,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final st = await backend.loraUploadStatus(lrId);
        if (st.status == 'synced') {
          return LoraUploadOutcome(
            name: name,
            base: base,
            ok: true,
            lrId: lrId,
          );
        }
        if (st.status == 'failed' || st.status == 'missing') {
          return LoraUploadOutcome(
            name: name,
            base: base,
            ok: false,
            lrId: lrId,
            message: st.status == 'failed'
                ? '推送机房失败:${st.error ?? '未知原因'},可在卡片上重试'
                : '这条已经不在了',
          );
        }
      } catch (_) {}
    }
    return LoraUploadOutcome(
      name: name,
      base: base,
      ok: false,
      lrId: lrId,
      message: '还在推送机房,稍后到管理器里看',
    );
  }
}

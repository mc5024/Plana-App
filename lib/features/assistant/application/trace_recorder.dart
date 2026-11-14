import 'dart:async';

import '../agent_trace.dart';
import '../domain/agent_event.dart';
import 'session_repository.dart';

/// 当前对话每一轮的调试记录(见 [AgentTrace]),助手设置里导出用。
///
/// 一轮的记录由 [begin] 开,事件流经 [track] 时在 [AgentDone] / 失败处自动收尾;
/// 停下由调用方 [finish]。开新对话、打开历史会话时 [clear] —— 导出的是「当前对话」。
class TraceRecorder {
  TraceRecorder(this._repo) : _traces = _repo.initialTraces;

  final SessionRepository _repo;
  List<AgentTrace> _traces;
  AgentTrace? _live;

  /// 当前对话记了几轮。
  int get count => _traces.length;

  List<AgentTrace> get traces => _traces;

  AgentTrace begin({required String route, required String userText}) =>
      _live = AgentTrace(
        startedAt: DateTime.now().millisecondsSinceEpoch,
        route: route,
        userText: userText,
        settings: <String, Object?>{},
      );

  /// 跟着事件流收尾:拿到结果算完成,流报错按错误收尾。
  Stream<AgentEvent> track(Stream<AgentEvent> events) => events.transform(
    StreamTransformer.fromHandlers(
      handleData: (e, sink) {
        if (e is AgentDone) finish(null);
        sink.add(e);
      },
      handleError: (Object e, st, sink) {
        finish('$e');
        sink.addError(e, st);
      },
    ),
  );

  /// 正在记的那一轮收尾:[error] 为 null 是正常完成。没有在记的就什么都不做。
  void finish(String? error) {
    final t = _live;
    if (t == null) return;
    _live = null;
    t
      ..endedAt = DateTime.now().millisecondsSinceEpoch
      ..error = error;
    final all = [..._traces, t];
    _traces = all.length > SessionRepository.maxTraces
        ? all.sublist(all.length - SessionRepository.maxTraces)
        : all;
    unawaited(_repo.saveTraces(_traces));
  }

  void clear() {
    _live = null;
    if (_traces.isEmpty) return;
    _traces = const [];
    unawaited(_repo.saveTraces(const []));
  }
}

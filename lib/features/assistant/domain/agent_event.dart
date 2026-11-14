/// 一轮 AI 对话吐出的事件流。每个 [AgentRuntime] 都吐这一套,最后一个必是 [AgentDone];
/// 失败以 [AgentFailure] 结束流。
library;

import 'agent_result.dart';

sealed class AgentEvent {
  const AgentEvent();
}

/// 模型开始调一个工具。
class AgentToolCall extends AgentEvent {
  const AgentToolCall(this.name, this.args);

  final String name;
  final Map<String, dynamic> args;
}

/// 工具返回。[summary] 非空即视为完成。
class AgentToolResult extends AgentEvent {
  const AgentToolResult(this.name, this.summary);

  final String name;
  final String summary;
}

/// 模型正在写这一跳的回复。
///
/// 带的是**到此刻为止的全量**,不是增量:`</Think>` 收尾、换一跳重写时正文会整段
/// 挪位,拿到就整块替换。
class AgentDelta extends AgentEvent {
  const AgentDelta({this.text = '', this.reasoning = ''});

  /// 能直接摆进气泡的正文:`<Think>` 段与 ```tool_call / ```nai_draw 围栏已剔掉。
  final String text;

  /// 思考过程:模型原生的 reasoning 字段 + 正文里的 `<Think>` 段。
  final String reasoning;
}

/// 终态。拿到它这一轮就结束了。
class AgentDone extends AgentEvent {
  const AgentDone(this.result);

  final AgentResult result;
}

/// 一轮失败。[message] 是原始错误内容(上游状态码 + 原文、异常原文),界面原样显示。
class AgentFailure implements Exception {
  AgentFailure(this.message, {this.status, this.retryable = true});

  /// HTTP 状态码 + 响应原文。原文过长时截断,免得一整页 HTML 进对话存档。
  factory AgentFailure.http(int status, String body, {bool retryable = true}) {
    final text = body.trim();
    return AgentFailure(
      text.isEmpty
          ? 'HTTP $status'
          : 'HTTP $status\n${text.length > kMaxBody ? '${text.substring(0, kMaxBody)}…' : text}',
      status: status,
      retryable: retryable,
    );
  }

  /// 响应原文最多留这么多字。
  static const kMaxBody = 4000;

  final String message;
  final int? status;

  /// 降级重试有没有用。后端已经重掷过的拒绝、后端自己拒掉的请求为 false。
  final bool retryable;

  @override
  String toString() => message;
}

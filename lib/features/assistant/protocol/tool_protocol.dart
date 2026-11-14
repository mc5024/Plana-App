/// 工具在对话里怎么表达:系统提示里怎么讲、回复里怎么认出调用、结果怎么回灌给模型。
///
/// 现在只有文本围栏一种([FencedToolProtocol]):任何中转都能用,而且调不调工具是模型完整推理的
/// 一部分。原生 function calling 以后作为另一个实现加进来。
library;

import '../runtime/prompt_assets.dart';
import '../tools/agent_tool.dart';

class ToolCall {
  const ToolCall(this.name, this.args);

  final String name;
  final Map<String, dynamic> args;
}

/// 写坏了认不出的一块:原文 + 哪里不对。
class BrokenToolCall {
  const BrokenToolCall(this.body, this.error);

  final String body;
  final String error;
}

/// 一条回复里认出的调用,以及写坏了认不出的那几块。
class ParsedToolCalls {
  const ParsedToolCalls(this.calls, {this.broken = const []});

  final List<ToolCall> calls;
  final List<BrokenToolCall> broken;

  bool get isEmpty => calls.isEmpty && broken.isEmpty;
}

/// 一次调用的结果。[error] 非空 = 没执行成;[repeat] = 和本轮之前某次同工具同参数,
/// 给的是上次的结果。
class ToolCallResult {
  const ToolCallResult(this.call, {this.data, this.error, this.repeat = false});

  final ToolCall call;
  final Object? data;
  final String? error;
  final bool repeat;
}

abstract interface class ToolProtocol {
  /// 通用调用约定,挂在规则的 role 后面。
  Future<String> conventions();

  /// 工具清单:每个工具的名字、参数、说明,拼在系统提示末尾。没有工具时是空串。
  Future<String> toolList(List<AgentTool> tools);

  ParsedToolCalls parse(String reply);

  /// 工具结果回灌给模型的那条消息,写坏的调用一并说明。
  String resultMessage(
    List<ToolCallResult> results,
    List<BrokenToolCall> broken,
    PromptTexts texts,
  );
}

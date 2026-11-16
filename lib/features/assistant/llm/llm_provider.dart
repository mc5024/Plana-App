/// 能对话的模型。agent 循环只认 [LlmProvider],不管背后是哪家的接口。
library;

import 'package:http/http.dart' as http;

import '../assistant_settings.dart' show ThinkLevel;

/// 附图:MIME + base64。
typedef LlmImage = ({String mime, String data});

/// 发给模型的一条消息。[images] 只挂在本轮用户那条上,历史里的图不回带。
typedef LlmMessage = ({String role, String content, List<LlmImage> images});

/// 回复文字:正文 + 原生思考。
typedef LlmText = ({String text, String reasoning});

class LlmRequest {
  const LlmRequest({
    required this.system,
    required this.messages,
    this.think = ThinkLevel.auto,
    this.turnStart = 0,
  });

  final String system;
  final List<LlmMessage> messages;
  final ThinkLevel think;

  /// `messages[turnStart]` 是本轮的用户消息,前面是历史,后面是这一轮里的工具往返与回灌。
  final int turnStart;
}

/// 模型支持什么。界面按它置灰对应的设置。
class LlmCapabilities {
  const LlmCapabilities({required this.streaming, required this.thinking});

  /// 回复能边写边显示。
  final bool streaming;

  /// 思考等级会随请求发出。
  final bool thinking;
}

abstract interface class LlmProvider {
  LlmCapabilities get capabilities;

  /// 选的档位在这个模型上没有、发送时换成了别的档,说一句换成了什么;原样发的返回 null。
  String? thinkNote(ThinkLevel level);

  /// 发一次对话。
  ///
  /// [stream] 为 true 时边收边吐,每帧是**到此刻为止的全量**;为 false 时收完只吐一帧。
  /// 最后一帧就是整段回复(正文里的 `<Think>` 段与围栏原样留着,由调用方解析)。
  /// [timeout] 是等响应头、两帧之间、等整段各自的上限;null = 不限。
  /// 失败抛 `AgentFailure`,内容是原始错误。
  Stream<LlmText> chat(
    LlmRequest request, {
    required http.Client client,
    bool stream = true,
    Duration? timeout,
  });
}

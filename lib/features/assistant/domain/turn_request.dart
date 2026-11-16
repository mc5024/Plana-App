/// 跑一轮要的全部输入。控制器组装好交给 [AgentRuntime],runtime 只认它。
library;

import 'dart:typed_data';

import '../assistant_settings.dart' show AssistantSettings, ThinkLevel;
import '../presets/preset_rule.dart' show PresetRule;
import '../runtime/refusal.dart' show kRefusalKeywords;
import '../tools/tool_settings.dart' show ToolSettings;

/// 引用创作页时带给 AI 的画面。字段与发出去的形状一致:角色站位已换算成 `"x,y"`。
class CanvasSnapshot {
  const CanvasSnapshot({
    required this.positive,
    required this.negative,
    required this.characters,
  });

  final String positive;
  final String negative;

  /// `{name, positive, negative, position}`,只含启用的角色。
  final List<Map<String, dynamic>> characters;
}

class AgentTurnRequest {
  const AgentTurnRequest({
    required this.userText,
    required this.imageModel,
    this.images = const [],
    this.history = const [],
    this.canvas,
    this.customRules,
    this.modeKeys = const [],
    this.tools = const ToolSettings(),
    this.artists = const [],
    this.ocs = const [],
    this.resources = const {},
    this.think = ThinkLevel.auto,
    this.stream = true,
    this.retries = AssistantSettings.retriesDefault,
    this.rerolls = AssistantSettings.rerollsDefault,
    this.refusalKeywords = kRefusalKeywords,
  });

  final String userText;

  /// 用户这轮附的图(原始字节)。
  final List<Uint8List> images;

  /// 已完成回合的历史 `[{role, content}]`,已按上下文轮数截好。
  final List<Map<String, String>> history;

  /// null = 这轮不给画布。
  final CanvasSnapshot? canvas;

  /// 图片生成模型档位(`agentImageModel` 的产物),决定用哪份规则。
  final String imageModel;

  /// 自定义过的规则主体;null = 用默认规则。
  final List<PresetRule>? customRules;

  /// 用户选的模式(`comic`、`mode:comic` 这类),拿来挑条件段。
  final List<String> modeKeys;

  /// 工具页的开关。
  final ToolSettings tools;

  /// 用户自己的画风库 / OC 库(`{'id','name','prompt'}` /
  /// `{'en_name','zh_name','zh_aliases','tag_group'}`)。
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> ocs;

  /// 上一轮记下的沿用资源账本。
  final Map<String, Map<String, String>> resources;

  final ThinkLevel think;
  final bool stream;

  /// 出错后重发几次 / 回复像拒绝时重掷几次,见 [AssistantSettings]。
  final int retries;
  final int rerolls;

  /// 回复命中就算拒绝的词。
  final List<String> refusalKeywords;
}

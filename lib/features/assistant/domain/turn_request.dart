/// 跑一轮要的全部输入。控制器组装好交给 [AgentRuntime],runtime 只认它。
library;

import 'dart:typed_data';

import '../assistant_settings.dart' show ThinkLevel;
import '../preset_rules.dart' show PresetRule;

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
    this.image,
    this.history = const [],
    this.historyTurns = 20,
    this.canvas,
    this.customRules,
    this.modeKeys = const [],
    this.artists = const [],
    this.ocs = const [],
    this.resources = const {},
    this.libraryScope = 'local',
    this.ocPlaceholders = false,
    this.think = ThinkLevel.auto,
    this.stream = true,
    this.backendModel = '',
  });

  final String userText;

  /// 用户这轮附的图(原始字节)。
  final Uint8List? image;

  /// 已完成回合的历史 `[{role, content}]`,已按 [historyTurns] 截好。
  final List<Map<String, String>> history;
  final int historyTurns;

  /// null = 这轮不给画布。
  final CanvasSnapshot? canvas;

  /// 图片生成模型档位(`agentImageModel` 的产物),决定用哪份规则。
  final String imageModel;

  /// 自定义过的规则主体;null = 用默认规则。
  final List<PresetRule>? customRules;

  /// 用户选的模式(`comic`、`mode:comic` 这类),拿来挑条件段。
  final List<String> modeKeys;

  /// 用户自己的画师串库 / OC 库(`{'id','name','prompt'}` /
  /// `{'en_name','zh_name','zh_aliases','tag_group'}`)。
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> ocs;

  /// 上一轮记下的沿用资源账本。
  final Map<String, Map<String, String>> resources;

  /// 资料库范围(`none` / `local` / `all`)。
  final String libraryScope;

  final bool ocPlaceholders;
  final ThinkLevel think;
  final bool stream;

  /// 后端渠道 key;空串 = 后端的全局默认。只有后端那条用。
  final String backendModel;
}

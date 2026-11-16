/// AI 助手一轮的产出。两条链路(后端 / 自定义接口)都收成这一份,下游只认它。
library;

/// 一个分角色分区(`characters[i]`)。
///
/// [position] 是站位坐标串 `"x,y"`(两个 0~1 四位小数,**y 向下增大**),与
/// `CharacterPrompt.position` 同格式,不用换算。**空串 = AI 没指定**,不是
/// 「放正中」—— 写回时由 `buildAgentCharacters` 挑空格。
class AgentCharacter {
  const AgentCharacter({
    required this.name,
    required this.positive,
    this.negative = '',
    this.position = '',
  });

  final String name;
  final String positive;
  final String negative;
  final String position;

  Map<String, dynamic> toJson() => {
    'name': name,
    'positive': positive,
    'negative': negative,
    'position': position,
  };

  factory AgentCharacter.fromJson(Map<String, dynamic> j) => AgentCharacter(
    name: j['name']?.toString() ?? '',
    positive: j['positive']?.toString() ?? '',
    negative: j['negative']?.toString() ?? '',
    position: j['position']?.toString() ?? '',
  );
}

/// 一轮的终态。
///
/// 没有 `should_draw`:这一轮改没改画面看 [hasDraw]。纯聊天轮 positive / characters
/// 全空,据此不出结果卡、不写创作页、不点导航角标。
class AgentResult {
  const AgentResult({
    this.replyText = '',
    this.reasoning = '',
    this.positive = '',
    this.negative = '',
    this.characters = const [],
    this.resources = const {},
  });

  /// 发给用户的正文。
  final String replyText;

  /// 模型原生思考。不进对话历史,只供当轮展示 / 排查。
  final String reasoning;

  final String positive;
  final String negative;
  final List<AgentCharacter> characters;

  /// 沿用中的资源账本(画师串 / OC):`{kind: {名字: 内容}}`。挂到这一轮的 AI 消息上,
  /// 下一轮原样带回去。
  final Map<String, Map<String, String>> resources;

  bool get hasDraw => positive.trim().isNotEmpty || characters.isNotEmpty;
}

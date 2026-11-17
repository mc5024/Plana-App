/// AI 助手的对话数据:一条消息、一次写回、以及撤销要用的两份快照。
///
/// 落盘形状即这里的 `toJson`(见 [SessionRepository])。用户带的图不进 JSON,
/// 只存 blob 键 —— 与工作台存档同一条路子。旧存档的字段兼容统一在
/// [SessionRepository.migrate] 里做,这里只认当前版本。
library;

import 'dart:convert';

import '../../generate/models.dart'
    show CharacterPrompt, CharTab, PromptSection;
import '../../generate/state_codec.dart' show decodeSections, encodeSections;
import '../../../l10n/l10n.dart';
import '../assistant_mode.dart';
import '../prompt_diff.dart';
import 'agent_result.dart';
import 'image_gen.dart';

enum MsgRole { user, ai, error }

/// 一次知识库工具调用。[summary] 空 = 还在跑(只收到 `tool_call`)。
class ToolTrace {
  const ToolTrace({required this.name, this.subject = '', this.summary = ''});

  /// 后端工具名。展示前经 [toolLabel] 换成中文。
  final String name;

  /// 这次查的**是什么** —— 从 `tool_call` 的参数里挑出来的角色名/关键词/tag。
  ///
  /// 展开后显示的就只有它和库名:「角色库 普拉娜」一眼能确认 AI 找的方向对不对,
  /// 而这已经是用户想知道的全部。
  final String subject;

  /// 工具回的结果计数。
  ///
  /// **不显示** —— 试过一版摆在行尾,又长又没用:用户要的是「查了什么」,
  /// 不是「命中几条」。留着是因为它同时是**完成信号**([done] 就看它非空),
  /// 归档回来时靠它把圆点点亮。
  final String summary;

  bool get done => summary.isNotEmpty;

  ToolTrace copyWith({String? summary}) =>
      ToolTrace(name: name, subject: subject, summary: summary ?? this.summary);

  Map<String, dynamic> toJson() => {
    'name': name,
    if (subject.isNotEmpty) 'subject': subject,
    if (summary.isNotEmpty) 'summary': summary,
  };

  factory ToolTrace.fromJson(Map<String, dynamic> j) => ToolTrace(
    name: j['name']?.toString() ?? '',
    subject: j['subject']?.toString() ?? '',
    summary: j['summary']?.toString() ?? '',
  );
}

/// 旧版后端软降级时合成的那条轨迹的工具名,只在旧会话里还有。不是真工具,但走同一条展示链路。
const kDegradedTool = 'degraded';

/// 工具名 → 界面上的中文。与灵感页的分类名对齐(那边叫「画风」,不叫画师串)。
String toolLabel(String name) => switch (name) {
  'search_character' => l10nNow.toolCharLib,
  'search_oc' => l10nNow.toolOcLib,
  'search_artist' || 'random_artist' => l10nNow.toolStyleLib,
  'lookup_tag' => l10nNow.toolTagWiki,
  kDegradedTool => l10nNow.toolSafeMode,
  _ => name,
};

/// 从 `tool_call` 的参数里挑出「查的是什么」。
///
/// 四个工具的参数名各不相同(`query` / `keyword` / `origin` / `artist_ids` /
/// `count`),但**都只有一个字段是人想看的**,所以按优先级挑第一个非空的就够,
/// 不必按工具名分支 —— 后端加一个新工具时也能顺带认出来。
String toolSubject(Map<String, dynamic> args) {
  for (final k in const ['query', 'keyword', 'origin']) {
    final v = args[k]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  final ids = args['artist_ids'];
  if (ids is List && ids.isNotEmpty) {
    return [for (final e in ids) '$e'].join(' ');
  }
  // random_artist 只有个数,那也是信息:「随机 3 个」比空着强
  final n = args['count'];
  if (n is num && n > 0) return l10nNow.randomN(n.toInt());
  return '';
}

/// 折叠时那一行。
///
/// 只报处数,不列库名 —— 折叠态本来就是「不想看细节」的那一档,把库名铺进来
/// 只是把展开态压扁了塞进一行,长了还得省略号。
///
/// [kDegradedTool] 那条不算「查资料」(它是降级通知,搭同一条展示链路而已);
/// 一处都没查、只有它时直接报它,不能报「查了 0 处」。
String toolHeadline(List<ToolTrace> tools) {
  final n = tools.where((t) => t.name != kDegradedTool).length;
  return n > 0 ? l10nNow.lookedUpN(n) : toolLabel(kDegradedTool);
}

/// AI 助手会写到创作页的那几样东西的快照。
///
/// **只装助手自己会动的字段** —— 正向、负向、主提示词分区、角色、站位开关。
/// 尺寸/采样/Vibe/LoRA 一概不碰也不存:撤销只该回滚 AI 干过的事,把用户这期间
/// 调的步数一起吞掉是越权。
class PromptSnapshot {
  const PromptSnapshot({
    this.positive = '',
    this.negative = '',
    this.sections,
    this.characters = const [],
    this.useCoords = false,
  });

  final String positive;
  final String negative;

  /// null = 有分区之前的老记录,撤销时分区不动、比对时不看。
  final List<PromptSection>? sections;

  final List<CharacterPrompt> characters;
  final bool useCoords;

  Map<String, dynamic> toJson() => {
    'positive': positive,
    'negative': negative,
    if (sections != null) 'sections': encodeSections(sections!),
    'useCoords': useCoords,
    'characters': [
      for (final c in characters)
        {
          'id': c.id,
          'name': c.name,
          'positive': c.positive,
          'negative': c.negative,
          'enabled': c.enabled,
          if (c.position != null) 'position': c.position,
          if (c.avatar != null) 'avatar': c.avatar,
        },
    ],
  };

  factory PromptSnapshot.fromJson(Map<String, dynamic> j) => PromptSnapshot(
    positive: j['positive']?.toString() ?? '',
    negative: j['negative']?.toString() ?? '',
    sections: j.containsKey('sections') ? decodeSections(j['sections']) : null,
    useCoords: j['useCoords'] == true,
    characters: [
      for (final e in (j['characters'] as List? ?? const []))
        if (e is Map && e['id'] is String)
          CharacterPrompt(
            id: e['id'] as String,
            name: e['name']?.toString() ?? '角色',
            positive: e['positive']?.toString() ?? '',
            negative: e['negative']?.toString() ?? '',
            enabled: e['enabled'] != false,
            position: e['position'] as String?,
            activeTab: CharTab.positive,
            avatar: e['avatar'] as String?,
          ),
    ],
  );

  /// 与另一份快照的正负向、分区、角色串、站位是否一字不差。
  /// 用来判断「用户在 AI 写回之后有没有自己又改过」—— 撤销前要问这一句。
  bool sameAs(PromptSnapshot o) {
    if (positive != o.positive || negative != o.negative) return false;
    if (useCoords != o.useCoords) return false;
    final a = sections, b = o.sections;
    if (a != null && b != null) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].id != b[i].id ||
            a[i].name != b[i].name ||
            a[i].positive != b[i].positive ||
            a[i].negative != b[i].negative ||
            a[i].enabled != b[i].enabled) {
          return false;
        }
      }
    }
    if (characters.length != o.characters.length) return false;
    for (var i = 0; i < characters.length; i++) {
      final a = characters[i];
      final b = o.characters[i];
      if (a.positive != b.positive ||
          a.negative != b.negative ||
          a.name != b.name ||
          a.position != b.position ||
          a.enabled != b.enabled) {
        return false;
      }
    }
    return true;
  }
}

/// 把一轮 AI 回复还原成**模型当初写出来的样子**:正文 + 末尾一个 ```nai_draw 围栏。
///
/// 回带历史时要用这个形状,不能只回正文。围栏里装的是**完整提示词不是增量**,
/// 所以最新那条就等于「当前这幅画的全部内容」—— bot 端历史深度需求之所以浅,
/// 正是因为它一直这么存(见服务端 `history_adapter` 的滑窗说明)。
///
/// 只回正文的后果:模型看不见自己上一轮写了什么,下一句「把头发改成金色」只能
/// 从头推一遍,连角色、画风都要**重新查一次工具** —— 用户看到的就是「怎么又查了一遍」。
String replayText(AssistantMsg m) {
  final d = m.draw;
  if (d == null) return m.text;
  return '${m.text}\n```nai_draw\n${jsonEncode(d.toJson())}\n```';
}

/// `{kind: {名字: 内容}}` 的宽松解码。形状不对一律当空 —— 账本读坏了
/// 最坏是「这轮忘了画风」,不该让整段会话打不开。
Map<String, Map<String, String>> decodeResources(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, String>>{};
  raw.forEach((k, v) {
    if (v is! Map) return;
    final slot = <String, String>{};
    v.forEach((name, value) => slot['$name'] = '$value');
    if (slot.isNotEmpty) out['$k'] = slot;
  });
  return out;
}

/// 最新那条 AI 消息记着的账本;一条都没有就是空的。
Map<String, Map<String, String>> latestResources(List<AssistantMsg> msgs) {
  for (var i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role == MsgRole.ai) return msgs[i].resources;
  }
  return const {};
}

/// 这段对话现在的模式:最后一条用户消息用的那个。一条都没有就是「无」。
AssistantMode conversationMode(List<AssistantMsg> msgs) {
  for (var i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role == MsgRole.user) return msgs[i].mode;
  }
  return AssistantMode.normal;
}

/// 一份提议的纯文本版本。「纯文本格式」开着时这么显示([AssistantMsg.promptAsText])。
///
/// 写法沿用预设「写tag模式」的展示格式,也是法典 / web 解析器认的那套(见
/// `codex_char_split.dart`):全局正向在前,每个角色一行 `charN: 正向`,角色有负向就
/// 紧跟一行 `[charN-] 负向`。全局负向单独一块,正向框、负向框各贴各的。
/// 站位不写:纯文本里没有它的位置。
({String positive, String negative}) promptTextOf(DrawProposal d) {
  final lines = <String>[if (d.positive.trim().isNotEmpty) d.positive.trim()];
  for (var i = 0; i < d.characters.length; i++) {
    final c = d.characters[i];
    lines.add('char${i + 1}: ${c.positive.trim()}'.trimRight());
    if (c.negative.trim().isNotEmpty) {
      lines.add('[char${i + 1}-] ${c.negative.trim()}');
    }
  }
  return (positive: lines.join('\n'), negative: d.negative.trim());
}

/// [id] 那条消息**上一轮**的提议;它前面一直没出过图就是 null。
///
/// 结果条的差异基线。中间夹几轮纯聊天很常见,所以是「上一份提议」而不是
/// 「上一条消息」。
DrawProposal? prevProposal(List<AssistantMsg> msgs, String id) {
  final i = msgs.indexWhere((m) => m.id == id);
  if (i < 0) return null;
  for (var k = i - 1; k >= 0; k--) {
    final d = msgs[k].draw;
    if (d != null) return d;
  }
  return null;
}

/// 只留最近 [turns] 轮,更早的整轮丢掉。一轮从一句 user 算起 —— 与服务端
/// `history_adapter.apply_turn_window` 同一种数法,开头不会剩一句没头没尾的回复。
/// 不足 [turns] 轮就全留。
List<Map<String, String>> recentTurns(
  List<Map<String, String>> history,
  int turns,
) {
  if (turns <= 0) return history;
  var left = turns;
  for (var i = history.length - 1; i >= 0; i--) {
    if (history[i]['role'] != 'user') continue;
    if (--left == 0) return history.sublist(i);
  }
  return history;
}

/// 回带历史时,哪几轮该带上 `nai_draw` 围栏 —— 从后往前数最近 [keep] 个有产出的
/// AI 轮,返回它们的消息 id。
///
/// 只留最近几个而不是全带:围栏装的是完整提示词不是增量,再往前翻是同一幅画的
/// 旧版本,按每个一两百 token 算,一屏历史堆下来比整份预设还大,每个请求都付一遍。
///
/// 也不能只留一个:最新那条说的是**现在**什么样,而「还是把刚才那个加回来吧」
/// 指的是上一版 —— 只留一个模型就看不见刚被去掉的是什么。
Set<String> historyFenceIds(List<AssistantMsg> msgs, int keep) {
  final out = <String>{};
  if (keep <= 0) return out;
  for (var i = msgs.length - 1; i >= 0; i--) {
    final m = msgs[i];
    if (m.role != MsgRole.ai || m.draw == null) continue;
    out.add(m.id);
    if (out.length >= keep) break;
  }
  return out;
}

/// AI 这一轮**提议**的画面。**它不会自己写进创作页** —— 用户点「导入」才写
/// (或者不导入、直接拿它生成)。
///
/// 存的是 AI 的原始产出:角色没有 id,站位可能是空串(AI 只在用户明说方位时才给)。
/// 真正落到创作页时由 [GenerateNotifier.applyAgentCharacters] 补 id、给没摆位的挑空格。
class DrawProposal {
  const DrawProposal({
    this.positive = '',
    this.negative = '',
    this.characters = const [],
  });

  final String positive;
  final String negative;
  final List<AgentCharacter> characters;

  int get charCount => characters.length;

  Map<String, dynamic> toJson() => {
    'positive': positive,
    'negative': negative,
    'characters': [for (final c in characters) c.toJson()],
  };

  factory DrawProposal.fromJson(Map<String, dynamic> j) => DrawProposal(
    positive: j['positive']?.toString() ?? '',
    negative: j['negative']?.toString() ?? '',
    characters: [
      for (final e in (j['characters'] as List? ?? const []))
        if (e is Map<String, dynamic>) AgentCharacter.fromJson(e),
    ],
  );
}

/// 一次**已经落到创作页**的写回:改了什么 + 回滚要用的两份快照。
///
/// [before] 是写回**前**的状态(撤销就恢复它);[after] 是写回**后**的状态,
/// 撤销时拿它与当前值比 —— 不一致说明用户自己又改过,得先问一句再回滚,
/// 否则会连他的改动一起吃掉。
class AssistantChange {
  const AssistantChange({
    required this.before,
    required this.after,
    this.undone = false,
    this.canvasId,
  });

  final PromptSnapshot before;
  final PromptSnapshot after;

  /// 导入到的那张画布;撤销回滚到它身上。null = 多画布之前的老记录(按当前画布)。
  final String? canvasId;

  final bool undone;

  /// 新增的 tag / 句子,按 [after] 里的顺序(怎么算见 [diffPrompt])。
  List<String> get added => [
    for (final u in diffPrompt(before.positive, after.positive).added) u.text,
  ];

  /// 被移除的 tag / 句子,按 [before] 里的顺序。
  List<String> get removed => [
    for (final u in diffPrompt(before.positive, after.positive).removed) u.text,
  ];

  int get charCount => after.characters.length;

  /// 角色列表整个被换掉了吗(数量或任一条目不同)。多角色场景据此换一种回执说法。
  bool get charsChanged {
    if (before.characters.length != after.characters.length) return true;
    for (var i = 0; i < after.characters.length; i++) {
      if (before.characters[i].positive != after.characters[i].positive ||
          before.characters[i].name != after.characters[i].name) {
        return true;
      }
    }
    return false;
  }

  AssistantChange copyWith({bool? undone}) => AssistantChange(
    before: before,
    after: after,
    undone: undone ?? this.undone,
    canvasId: canvasId,
  );

  Map<String, dynamic> toJson() => {
    'before': before.toJson(),
    'after': after.toJson(),
    if (undone) 'undone': true,
    if (canvasId != null) 'canvasId': canvasId,
  };

  factory AssistantChange.fromJson(Map<String, dynamic> j) => AssistantChange(
    before: PromptSnapshot.fromJson(
      j['before'] is Map<String, dynamic>
          ? j['before'] as Map<String, dynamic>
          : const {},
    ),
    after: PromptSnapshot.fromJson(
      j['after'] is Map<String, dynamic>
          ? j['after'] as Map<String, dynamic>
          : const {},
    ),
    undone: j['undone'] == true,
    canvasId: j['canvasId'] is String ? j['canvasId'] as String : null,
  );
}

/// 对话里的一条消息。
class AssistantMsg {
  const AssistantMsg({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.imageHashes = const [],
    this.withCanvas = false,
    this.mode = AssistantMode.normal,
    this.noDraw = false,
    this.imageIds = const [],
    this.imageBatch = 1,
    this.resources = const {},
    this.tools = const [],
    this.draw,
    this.change,
    this.imageGen,
    this.imageModel,
  });

  final String id;
  final MsgRole role;

  /// 正文。user = 用户输入;ai = `AgentResult.replyText`;error = 原始错误内容。
  final String text;

  /// UNIX 毫秒。
  final int at;

  /// 用户这条带的图(blob 键,按附上的顺序)。仅 [MsgRole.user]。
  final List<String> imageHashes;

  /// 从这一轮的提议出过的图(图库条目 id,新的在后)。仅 [MsgRole.ai]。
  ///
  /// NAI 出的只在「图片显示在对话里」开着时才攒 —— 关着的时候出图会把页面切去图库,
  /// 对话里再挂一份是重复;图像模型出的始终攒。图本身**始终**入库,这里存的只是个引用;库里删了
  /// 就查不到,界面按「没有」处理,不留破图。
  final List<String> imageIds;

  /// 最近一批出了几张,即 [imageIds] 末尾这几张一起画。图像模型一轮出多张时大于 1。
  final int imageBatch;

  /// 这一轮结束时的**沿用资源账本**(画师串 / OC)。仅 [MsgRole.ai]。
  ///
  /// 每轮收尾时在本机按「还在不在这幅画里」筛(见 `mergeLedger`),随结果挂在这条消息上,
  /// 下一轮原样带回去。
  ///
  /// 挂在消息上而不是单存一份:这样它跟着会话一起落盘、一起归档,
  /// 「从这里重新开始」也天然把账本退回那一轮 —— 单存一份的话这三件事
  /// 都得各写一遍。发请求时取**最新那条 AI 消息**的。
  final Map<String, Map<String, String>> resources;

  /// **这一轮把创作页的提示词给了 AI**。用户消息与它那条回复上都记一份。
  ///
  /// 与导入同一个道理:AI 读画布也是用户按出来的,不自动发生。存下来是为了事后
  /// 能回答「这轮它到底看没看见我写的词」—— 光看回复分不出来。
  ///
  final bool withCanvas;

  /// 发这一轮时选着的模式(输入框上方的「模式」按钮)。用户消息和它那条回复上都记一份。
  ///
  /// 记的是**用户选的**,不是这一轮实际生效的:换到一份没写这个模式的预设时那一轮
  /// 什么都不加,但对话还是那段漫画对话,换回来得接着是漫画。打开历史时靠用户消息上的
  /// 这份恢复模式。
  final AssistantMode mode;

  /// 发这一轮时助手设置里「纯文本格式」开没开,决定提议怎么显示([promptAsText])。
  /// 仅 [MsgRole.ai]。
  final bool noDraw;

  /// 这一轮的提议**显示成纯文本**:「纯文本格式」开着时发的,只给复制,不出结果卡、
  /// 不导入、不出图。
  ///
  /// 看的是这一轮发出去时开没开,不是现在的设置:关掉之后,前面已经显示出来的东西
  /// 不跟着变样。
  bool get promptAsText => role == MsgRole.ai && draw != null && noDraw;

  /// 这一轮查了哪些资料。仅 [MsgRole.ai]。
  final List<ToolTrace> tools;

  /// AI 这一轮**提议**的画面。仅 [MsgRole.ai] 且有绘图产出时非空 ——
  /// 纯聊天轮为 null,界面据此不出结果卡。
  ///
  /// **有提议不等于改过创作页**:写回要用户在卡上点「导入」。
  final DrawProposal? draw;

  /// 用户点过「导入」之后才有:那一次写回的记录(含撤销要用的两份快照)。
  final AssistantChange? change;

  /// 选着图像模型时这一轮的出图请求。仅 [MsgRole.ai];这种消息没有正文,出的图在 [imageIds]。
  final ImageGenSpec? imageGen;

  /// [imageGen] 用的图像模型(`image_gen/image_models.dart` 的 key),重新生成照用它。
  final String? imageModel;

  AssistantMsg copyWith({
    String? text,
    List<ToolTrace>? tools,
    AssistantChange? change,
    List<String>? imageIds,
    int? imageBatch,
  }) => AssistantMsg(
    id: id,
    role: role,
    text: text ?? this.text,
    at: at,
    imageHashes: imageHashes,
    withCanvas: withCanvas,
    mode: mode,
    noDraw: noDraw,
    imageIds: imageIds ?? this.imageIds,
    imageBatch: imageBatch ?? this.imageBatch,
    resources: resources,
    tools: tools ?? this.tools,
    draw: draw,
    change: change ?? this.change,
    imageGen: imageGen,
    imageModel: imageModel,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'at': at,
    if (imageHashes.isNotEmpty) 'imageHashes': imageHashes,
    if (withCanvas) 'withCanvas': true,
    if (mode != AssistantMode.normal) 'mode': mode.name,
    if (noDraw) 'noDraw': true,
    if (imageIds.isNotEmpty) 'imageIds': imageIds,
    if (imageBatch > 1) 'imageBatch': imageBatch,
    if (resources.isNotEmpty) 'resources': resources,
    if (tools.isNotEmpty) 'tools': [for (final t in tools) t.toJson()],
    if (draw != null) 'draw': draw!.toJson(),
    if (change != null) 'change': change!.toJson(),
    if (imageGen != null) 'imageGen': imageGen!.toJson(),
    'imageModel': ?imageModel,
  };

  factory AssistantMsg.fromJson(Map<String, dynamic> j) => AssistantMsg(
    id: j['id']?.toString() ?? '',
    role: MsgRole.values.asNameMap()[j['role']] ?? MsgRole.ai,
    text: j['text']?.toString() ?? '',
    at: (j['at'] as num?)?.toInt() ?? 0,
    imageHashes: [
      for (final e in (j['imageHashes'] as List? ?? const [])) '$e',
      // 只带一张图时代的存档
      if (j['imageHash'] case final String h when h.isNotEmpty) h,
    ],
    withCanvas: j['withCanvas'] == true,
    mode: AssistantMode.values.asNameMap()[j['mode']] ?? AssistantMode.normal,
    noDraw: j['noDraw'] == true,
    imageIds: [for (final e in (j['imageIds'] as List? ?? const [])) '$e'],
    imageBatch: ((j['imageBatch'] as num?)?.toInt() ?? 1).clamp(
      1,
      kMaxImageCount,
    ),
    resources: decodeResources(j['resources']),
    tools: [
      for (final e in (j['tools'] as List? ?? const []))
        if (e is Map<String, dynamic>) ToolTrace.fromJson(e),
    ],
    draw: j['draw'] is Map<String, dynamic>
        ? DrawProposal.fromJson(j['draw'] as Map<String, dynamic>)
        : null,
    change: j['change'] is Map<String, dynamic>
        ? AssistantChange.fromJson(j['change'] as Map<String, dynamic>)
        : null,
    imageGen: ImageGenSpec.fromJson(j['imageGen']),
    imageModel: j['imageModel'] as String?,
  );
}

/// 一段归档的对话。
class ArchivedSession {
  const ArchivedSession({
    required this.id,
    required this.msgs,
    required this.at,
  });

  /// = 归档时刻的 UNIX 毫秒,同时作为列表键。
  final int id;
  final List<AssistantMsg> msgs;

  /// 最后一条消息的时间(列表按它排)。
  final int at;

  /// 标题取第一句用户输入。
  String get title {
    for (final m in msgs) {
      if (m.role == MsgRole.user && m.text.trim().isNotEmpty) {
        return m.text.trim();
      }
    }
    return l10nNow.untitledChat;
  }

  /// 副行取最后一句 AI 回复。
  String get preview {
    for (final m in msgs.reversed) {
      if (m.role == MsgRole.ai && m.text.trim().isNotEmpty) {
        return m.text.trim();
      }
    }
    return '';
  }

  int get turns => msgs.where((m) => m.role == MsgRole.user).length;

  bool get hasError => msgs.any((m) => m.role == MsgRole.error);

  /// 这段对话最终攒出多少 tag —— 用户回头找它的真正理由,所以列表上只显示这个数。
  /// 和结果条上「生成了 N tag」同一个数法([countTags])。
  int get tagCount {
    for (final m in msgs.reversed) {
      final c = m.change;
      if (c != null && !c.undone) {
        return countTags(c.after.positive, [
          for (final ch in c.after.characters)
            if (ch.enabled) ch.positive,
        ]);
      }
      final d = m.draw;
      if (d != null) {
        return countTags(d.positive, [
          for (final ch in d.characters) ch.positive,
        ]);
      }
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at,
    'msgs': [for (final m in msgs) m.toJson()],
  };

  factory ArchivedSession.fromJson(Map<String, dynamic> j) {
    final msgs = [
      for (final e in (j['msgs'] as List? ?? const []))
        if (e is Map<String, dynamic>) AssistantMsg.fromJson(e),
    ];
    return ArchivedSession(
      id: (j['id'] as num?)?.toInt() ?? 0,
      msgs: msgs,
      at: (j['at'] as num?)?.toInt() ?? (msgs.isEmpty ? 0 : msgs.last.at),
    );
  }
}

import '../runtime/placeholders.dart';
import '../runtime/prompt_assets.dart';
import 'my_library.dart';
import 'tool_settings.dart';

/// 离线词库里的一条。[category] 是 Danbooru 类目(0 一般 / 1 画师 / 3 作品 / 4 角色 / 5 meta)。
typedef TagRecord = ({String tag, String zh, int count, int category});

/// 离线词库查询:查角色、查 tag 的离线来源与 [角色候选] 预取。
abstract interface class TagLookup {
  /// 这句话里按中文名字面点到的角色,过热度门槛后最多 [limit] 条,热度高的在前。
  Future<List<TagRecord>> roleCandidates(String text, {int limit = 5});

  /// 按名字查角色;[origin] 用来消除重名,只给 [origin] 时按出处列。
  Future<List<TagRecord>> characters({
    String query = '',
    String origin = '',
    int limit = 10,
  });

  /// 按名字查 tag(不含画师);[category] 只看这一类。
  Future<List<TagRecord>> tags(String query, {int? category, int limit = 10});
}

/// 语义搜词的一条。[zh] 是中文名(可能连着出处等别名),[wiki] 是一句话介绍,可能为空。
typedef SemanticHit = ({String tag, String zh, int count, String wiki});

/// 联网的标签服务:语义搜词、Wiki 摘要与编辑页补全共用后端 `/api/tags/*`,角色候选筛选走
/// `/api/agent/role-filter`。拿不到一律返回空,不抛。
abstract interface class OnlineTags {
  /// 语义搜角色,按名字整体查,不拆词。
  Future<List<SemanticHit>> characters(String query, {int limit = 10});

  /// tag 的 Wiki 摘要。
  Future<String?> wiki(String tag);

  /// 字面预匹配出的候选角色交给后端逐条判是不是用户说的那个,返回留下的 tag(原顺序);
  /// 判不了返回 null,调用方全留。
  Future<List<String>?> filterRoles(String userText, List<String> tags);
}

/// 一轮里工具能用到的东西。
class ToolContext {
  ToolContext({
    required this.userText,
    required this.settings,
    required this.texts,
    this.artists = const [],
    this.ocs = const [],
    this.remembered = const {},
    this.offline,
    this.online,
    ArtistPlan? artistPlan,
    OcPlan? ocPlan,
  }) : artistPlan = artistPlan ?? ArtistPlan(),
       ocPlan = ocPlan ?? OcPlan();

  /// 用户这轮的原话(预取用)。
  final String userText;
  final ToolSettings settings;
  final PromptTexts texts;

  /// 画风库 / OC 库。
  final List<LibArtist> artists;
  final List<LibOc> ocs;

  /// 上一轮记下的账本。
  final Map<String, Map<String, String>> remembered;

  /// 这一轮的占位符映射。
  final ArtistPlan artistPlan;
  final OcPlan ocPlan;

  /// 离线词库;null = 读不出来。
  final TagLookup? offline;

  /// 联网的标签服务;null = 没有后端地址。
  final OnlineTags? online;
}

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'suggestions.dart';
import 'tag_index.dart';

/// 离线 Danbooru 标签库(源数据 `assets/danbooru.tsv`,**含中文翻译**,已按热度降序;
/// 进包的是构建期编好的索引,见 [TagIndex])。
/// 英文补全以它为准——**完全离线**,不碰网络,天然绕开 Cloudflare。
/// 行格式(tab 分隔):`tag<TAB>post_count<TAB>中文<TAB>alias1,alias2<TAB>category`;
/// tag 用下划线,app 内展示/插入转空格。
///
/// **2026-09-19 换成上游新词库**(Auto-NovelAI-Refactor 的 `danbooru_tags_full_zh.csv`,
/// 由 tool/import_tag_dict.dart 导入):热度 ≥50 的 12.7 万行,每行都有中文,
/// category 列是完整的 Danbooru 类目(0 一般 / 1 画师 / 3 作品 / 4 角色 / 5 meta)。
/// 上游不再收录的几百条旧 tag 原样沿用旧词库(那几行的 category 可能留空 = 未定类)。
/// 角色取并集:上游把几十条角色(罗小黑、赛马娘的衣装变体)标成了一般 tag,
/// 旧词库那份经后端建库产物交叉验证的角色标记仍然算数。
class LocalTagDb {
  Future<TagIndex?>? _index;

  /// 读进索引。Android 端这个 asset 不压缩存(见 android/app/build.gradle.kts),
  /// 引擎直接 mmap,拿到的 ByteData 就是那段映射 —— 不拷贝、不解析,几毫秒。
  /// 压缩存的话,引擎会在 UI 线程上把近 10MB 整份解压出来。
  ///
  /// 读不出来(不该发生)时各查询一律按查不到处理。
  Future<TagIndex?> get _ready => _index ??= () async {
    try {
      return TagIndex(await rootBundle.load(kTagIndexAsset));
    } catch (e) {
      debugPrint('离线词库索引读取失败:$e');
      return null;
    }
  }();

  /// 索引本身;读不出来是 null。
  Future<TagIndex?> get index => _ready;

  /// 读进索引并装给注音层 / 词条栏的同步反查([translationOf] / [countOf])。
  /// 开机在 runApp 之前调,从第一帧起就查得到。
  Future<void> install() async {
    offlineTagMeta = await _ready;
  }

  /// 英文补全,口径同后端补全。取前 [limit] 条。见 [TagIndex.search]。
  Future<List<TagHit>> search(String query, {int limit = 15}) async =>
      (await _ready)?.search(query, limit: limit) ?? const [];

  /// 拼写纠错,口径同 Danbooru。见 [TagIndex.correct]。
  Future<List<TagHit>> correct(String query, {int limit = 15}) async =>
      (await _ready)?.correct(query, limit: limit) ?? const [];

  // ---- 角色反查(离线) ----

  /// 提示词分词集合 → 命中的角色标签,**按热度降序**(库本身即热度序)。
  ///
  /// 分词用 `tokenizeSet`,与索引的键同走 `cleanPromptToken`,下划线/括号/权重
  /// 记号两边同归一。词库读不出来时得空表,调用方按「没有角色」处理即可,不必区分。
  Future<List<CharacterTag>> charactersIn(Set<String> tokens) async {
    if (tokens.isEmpty) return const [];
    return (await _ready)?.charactersIn(tokens) ?? const [];
  }

  // ---- 帖子数反查(图库归类加权用) ----

  /// 分词后的词(`cleanPromptToken` 口径)→ 词库帖子数;词库没收、或冷门到
  /// 建库时被滤掉的回 0。
  ///
  /// 图库按角色 / 画风归类时拿它掂量灵感库条目里每个词的分量:「1girl」几百万帖,
  /// 「红冠鹤主题」一帖没有,两者对「这张图用没用这个 OC」的说服力差着数量级。
  Future<Map<String, int>> postCountsOf(Iterable<String> tokens) async {
    final idx = await _ready;
    return {for (final t in tokens) t: idx?.postCountOf(t) ?? 0};
  }

  /// 分词后的词里词库标成画师的那些。图库按画风归类时拿它数一张图用了几个画师。
  Future<Set<String>> artistsIn(Iterable<String> tokens) async =>
      (await _ready)?.artistsIn(tokens) ?? const {};
}

/// 全局单例。main 里开机就 new 一个、装好再注进来;没注的地方(测试)第一次查询时懒加载。
final localTagDbProvider = Provider<LocalTagDb>((ref) => LocalTagDb());

import '../../editor/data/tag_completion.dart';
import 'tool_context.dart';

/// 联网的标签服务:就是编辑页补全那一套(`TagCompletion`),语义搜词与 Wiki 摘要都走它。
class CompletionOnlineTags implements OnlineTags {
  CompletionOnlineTags(this._tags);

  final TagCompletion _tags;

  @override
  Future<List<SemanticHit>> characters(String query, {int limit = 10}) async => [
    for (final h in await _tags.searchCharacters(query, limit: limit))
      (
        tag: h.tag,
        // 上游的中文名是逗号串:正名在前,后面是出处、别名
        zh: h.cnName
            .split(RegExp(r'[,，]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join('、'),
        count: h.count,
        wiki: h.wiki,
      ),
  ];

  @override
  Future<String?> wiki(String tag) async {
    final w = await _tags.fetchWiki(tag);
    final zh = w?.summaryZh?.trim() ?? '';
    if (zh.isNotEmpty) return zh;
    final en = w?.summary?.trim() ?? '';
    return en.isEmpty ? null : en;
  }
}

import 'package:flutter/material.dart' show Icons, IconData;

import '../../../l10n/l10n.dart';
import 'agent_tool.dart';
import 'my_library.dart';
import 'tool_context.dart';

const kRoleBlock = '[角色候选]';

/// 语义搜词、离线词库各取几条合并:两路出错的地方正好互补 —— 离线按字面认,出处容易认错;
/// 语义按意思认,有的热门角色召不回来。
const _mergeEach = 5;

final _originSuffix = RegExp(r'_\(([^()]+)\)$');

/// tag 末尾 `_(作品)` 里的出处,没有是空串。
String originOfTag(String tag) =>
    _originSuffix.firstMatch(tag)?.group(1)?.replaceAll('_', ' ') ?? '';

/// 搜索角色:动漫 / 游戏角色的 Danbooru tag。离线词库(本机)和语义搜词(经后端)两路一起查。
class SearchCharacterTool extends AgentTool {
  const SearchCharacterTool();

  @override
  String get name => 'search_character';

  @override
  String get label => l10nNow.toolSearchCharacter;

  @override
  IconData get icon => Icons.person_search_outlined;

  @override
  List<ToolParam> get params => const [
    ToolParam('query', 'string'),
    ToolParam('origin', 'string'),
    ToolParam('limit', 'integer'),
  ];

  /// 原话里按中文名点到的角色 → [角色候选] 块(离线词库字面匹配)。有后端时
  /// 再交后端逐条判一遍,名字撞上的别的角色丢掉。
  @override
  Future<ToolBlock?> prefetch(ToolContext ctx) async {
    final offline = ctx.offline;
    if (offline == null) return null;
    var rows = await offline.roleCandidates(ctx.userText);
    final online = ctx.online;
    if (rows.isNotEmpty && online != null) {
      final kept = await online.filterRoles(ctx.userText, [
        for (final r in rows) r.tag,
      ]);
      if (kept != null) {
        rows = [
          for (final r in rows)
            if (kept.contains(r.tag)) r,
        ];
      }
    }
    if (rows.isEmpty) return null;
    return ToolBlock(
      [
        kRoleBlock,
        for (final r in rows)
          [
            '${r.tag} → 中文: ${r.zh}',
            if (originOfTag(r.tag) case final o when o.isNotEmpty) '出处: $o',
          ].join(' / '),
      ].join('\n'),
    );
  }

  @override
  Future<ToolOutcome> call(ToolContext ctx, Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}'.trim();
    final origin = '${args['origin'] ?? ''}'.trim();
    final limit = intArg(args['limit'], 10).clamp(1, 100);
    if (query.isEmpty && origin.isEmpty) return const ToolOutcome([]);

    final online = ctx.online;
    final offline = ctx.offline;
    // 只给出处是在列一个作品的角色,语义搜词按相关度只回十几条,做不了这个
    final semantic = online != null && query.isNotEmpty
        ? await online.characters('$origin $query'.trim())
        : const <SemanticHit>[];
    final local = offline != null
        ? await offline.characters(
            query: query,
            origin: origin,
            limit: limit < _mergeEach * 2 ? _mergeEach * 2 : limit,
          )
        : const <TagRecord>[];

    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};
    if (semantic.isNotEmpty) {
      for (final h in semantic.take(_mergeEach)) {
        if (!seen.add(h.tag)) continue;
        rows.add({
          'tag': h.tag,
          'zh': h.zh,
          'origin': originOfTag(h.tag),
          'post_count': h.count,
          'wiki': h.wiki,
        });
      }
    }
    final localCap = semantic.isNotEmpty ? _mergeEach : limit;
    var added = 0;
    for (final r in local) {
      if (added >= localCap) break;
      if (!seen.add(r.tag)) continue;
      rows.add({
        'tag': r.tag,
        'zh': r.zh,
        'origin': originOfTag(r.tag),
        'post_count': r.count,
        'wiki': '',
      });
      added++;
    }
    return ToolOutcome(rows.take(limit).toList());
  }
}

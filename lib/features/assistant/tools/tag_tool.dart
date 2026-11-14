import 'dart:async';

import 'package:flutter/material.dart' show Icons, IconData;

import '../../../l10n/l10n.dart';
import 'agent_tool.dart';
import 'my_library.dart';
import 'tool_context.dart';

/// 前几条结果去拉 Wiki 摘要。每条一个请求,多了慢。
const _wikiTop = 3;

const _categories = {
  'general': 0,
  'copyright': 3,
  'character': 4,
  'meta': 5,
};

String _categoryName(int c) => switch (c) {
  0 => 'general',
  3 => 'copyright',
  4 => 'character',
  5 => 'meta',
  _ => '',
};

/// 查 tag:某个 tag / 角色 / 作品是什么意思。来源:离线词库(本机)、Wiki 摘要(经后端)。
class LookupTagTool extends AgentTool {
  const LookupTagTool();

  @override
  String get name => 'lookup_tag';

  @override
  String get label => l10nNow.toolLookupTag;

  @override
  String get desc => l10nNow.toolLookupTagDesc;

  @override
  IconData get icon => Icons.menu_book_outlined;

  @override
  List<ToolParam> get params => const [
    ToolParam('query', 'string', required: true),
    ToolParam('category', 'string'),
    ToolParam('limit', 'integer'),
  ];

  @override
  List<ToolSource> get sources => [
    ToolSource('offline', () => l10nNow.toolSourceOffline),
    ToolSource('wiki', () => l10nNow.toolSourceWiki, online: true),
  ];

  @override
  Future<ToolOutcome> call(ToolContext ctx, Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) return const ToolOutcome([]);
    final category = _categories['${args['category'] ?? ''}'.trim()];
    final limit = intArg(args['limit'], 10).clamp(1, 20);
    final offline = ctx.offline;
    final wiki = ctx.sourceOn(name, 'wiki') ? ctx.online : null;

    final List<TagRecord> found;
    if (offline != null && ctx.sourceOn(name, 'offline')) {
      found = await offline.tags(query, category: category, limit: limit);
    } else if (wiki != null) {
      // 没有离线词库可查:把原话当成 tag 直接问 Wiki
      found = [
        (
          tag: query.toLowerCase().replaceAll(' ', '_'),
          zh: '',
          count: 0,
          category: -1,
        ),
      ];
    } else {
      found = const [];
    }

    final wikis = wiki != null
        ? await Future.wait([
            for (final r in found.take(_wikiTop))
              wiki
                  .wiki(r.tag)
                  .timeout(const Duration(seconds: 10), onTimeout: () => null)
                  .catchError((Object _) => null),
          ])
        : const <String?>[];
    return ToolOutcome([
      for (final (i, r) in found.indexed)
        {
          'tag': r.tag,
          'zh': r.zh,
          'category': _categoryName(r.category),
          'post_count': r.count,
          'wiki': i < wikis.length ? wikis[i] ?? '' : '',
        },
    ]);
  }
}

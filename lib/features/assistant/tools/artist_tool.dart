import 'package:flutter/material.dart' show Icons, IconData;

import '../../../l10n/l10n.dart';
import 'agent_tool.dart';
import 'my_library.dart';
import 'tool_context.dart';

const kArtistBlock = '[画师串]';

/// 使用画风库:用户画风库里的画师串。给模型的是占位符,完整串留在本机。
class SearchArtistTool extends AgentTool {
  const SearchArtistTool();

  @override
  String get name => 'search_artist';

  @override
  String get label => l10nNow.toolSearchArtist;

  @override
  IconData get icon => Icons.palette_outlined;

  @override
  List<ToolParam> get params => const [
    ToolParam('artist_ids', 'array'),
    ToolParam('keyword', 'string'),
  ];

  /// 原话里点到的画师串(编号 / 名字)→ [画师串] 块。这轮没点到就把账本里记着的补上:
  /// 用户没再提「A1」,出处也不该断。
  @override
  Future<ToolBlock?> prefetch(ToolContext ctx) async {
    final hits = matchArtists(ctx.userText, ctx.artists);
    final shown = hits.isNotEmpty
        ? hits
        : [
            for (final e in (ctx.remembered['artist'] ?? const {}).entries)
              (e.key, e.value),
          ];
    final lines = [
      for (final (name, content) in shown)
        if (name.isNotEmpty && content.isNotEmpty)
          '$name → ${ctx.artistPlan.add(name, content)}',
    ];
    if (lines.isEmpty) return null;
    return ToolBlock(
      [kArtistBlock, ctx.texts.get('artist_block_note'), ...lines].join('\n'),
      resources: {
        'artist': {for (final (name, content) in hits) name: content},
      },
    );
  }

  @override
  Future<ToolOutcome> call(ToolContext ctx, Map<String, dynamic> args) async {
    final found = searchArtists(ctx.artists, args);
    return ToolOutcome(
      [for (final a in found) artistToolEntry(a)],
      resources: {
        'artist': {for (final a in found) a.label: a.prompt},
      },
    );
  }
}

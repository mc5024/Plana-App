import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inspiration/tag_models.dart';
import 'suggestions.dart';
import '../../../l10n/l10n.dart';

/// 本地画风 + OC 补全匹配(只检索本机灵感库,不访问公共库)。
class ArtistOcLibrary {
  const ArtistOcLibrary();

  /// 画风与 OC 均按名字或别名子串匹配,各自最多返回 [limit] 条。
  (List<Suggestion>, List<Suggestion>) search(
    String query, {
    int limit = 5,
    List<TagEntry> localArtists = const [],
    List<TagEntry> localOcs = const [],
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return (const <Suggestion>[], const <Suggestion>[]);
    return (
      _searchEntries(
        q,
        localArtists,
        kind: SuggestionKind.artist,
        limit: limit,
      ),
      _searchEntries(
        q,
        localOcs,
        kind: SuggestionKind.oc,
        source: l10nNow.localLibrary,
        limit: limit,
      ),
    );
  }

  static List<Suggestion> _searchEntries(
    String q,
    List<TagEntry> entries, {
    required SuggestionKind kind,
    String? source,
    required int limit,
  }) {
    final out = <Suggestion>[];
    for (final e in entries) {
      if (out.length >= limit) break;
      final name = e.name.trim(), group = e.positive.trim();
      if (name.isEmpty || group.isEmpty || !_hit(q, name, e.aliases)) {
        continue;
      }
      out.add(
        Suggestion(
          text: name,
          kind: kind,
          source: source,
          insertText: group,
          local: true,
        ),
      );
    }
    return out;
  }

  static bool _hit(String q, String name, List<String> aliases) =>
      name.toLowerCase().contains(q) ||
      aliases.any((x) => x.toLowerCase().contains(q));
}

final artistOcLibraryProvider = Provider<ArtistOcLibrary>(
  (_) => const ArtistOcLibrary(),
);

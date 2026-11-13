import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/auth/bot_session_store.dart';
import '../../../core/net/backend_config.dart';
import '../../inspiration/tag_models.dart';
import 'suggestions.dart';
import '../../../l10n/l10n.dart';

/// 画师串 + OC 库(需 Bearer session)。
/// `GET /api/artists/list` + `GET /api/oc/list`,内存缓存(会话生命周期)。
/// **画师插 `artist_string`、OC 插 `tag_group`**——web 包成 `<<marker>>` 但发送前会被
/// `cleanPromptMarkers` 剥成裸内容,故直接插裸载荷等价。归属默认 all(不按 mine 过滤)。
///
/// `/api/oc/list` 是**公共库**。补全时再并上本机灵感库的角色条目(见 [search]);
/// 公共库的 OC 底行写作者,所以顺带拉一份作者目录 `GET /api/public/authors`。
class ArtistOcLibrary {
  ArtistOcLibrary(this.baseUrl, this.sessionId, this._client);

  final String baseUrl;
  final String? sessionId;
  final http.Client _client;

  List<_Artist>? _artists;
  List<_Oc>? _ocs;

  /// 归属 id(QQ 号)→ 昵称。拉不到就是空表,底行回落成归属 id。
  Map<String, String> _authors = const {};
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    if (_artists != null && _ocs != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    if (baseUrl.isEmpty || sessionId == null || sessionId!.isEmpty) {
      _artists = const [];
      _ocs = const [];
      return;
    }
    final headers = {'Authorization': 'Bearer $sessionId'};
    // 三份互不依赖,并行拉 —— 第一次补全要等它们齐了才出结果。各自 fail-soft。
    Future<T> fetch<T>(
      String path,
      T Function(http.Response) parse,
      T empty,
    ) async {
      try {
        final r = await _client
            .get(Uri.parse('$baseUrl$path'), headers: headers)
            .timeout(const Duration(seconds: 15));
        return parse(r);
      } catch (_) {
        return empty;
      }
    }

    final (artists, ocs, authors) = await (
      fetch('/api/artists/list', _parseArtists, const <_Artist>[]),
      fetch('/api/oc/list', _parseOcs, const <_Oc>[]),
      fetch('/api/public/authors', _parseAuthors, const <String, String>{}),
    ).wait;
    _artists = artists;
    _ocs = ocs;
    _authors = authors;
  }

  List<_Artist> _parseArtists(http.Response r) {
    if (r.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final list = (j is Map) ? j['artists'] : null;
    if (list is! List) return const [];
    final out = <_Artist>[];
    for (final a in list) {
      if (a is! Map) continue;
      final name = a['name'] as String?;
      final str = a['artist_string'] as String?;
      if (name == null || name.isEmpty || str == null || str.isEmpty) continue;
      out.add(_Artist(name, str));
    }
    return out;
  }

  List<_Oc> _parseOcs(http.Response r) {
    if (r.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final list = (j is Map) ? j['ocs'] : null;
    if (list is! List) return const [];
    final out = <_Oc>[];
    for (final o in list) {
      if (o is! Map) continue;
      final en = o['en_name'] as String?;
      final zh = o['zh_name'] as String?;
      final group = o['tag_group'] as String?;
      final name = (zh != null && zh.isNotEmpty) ? zh : en;
      if (name == null || name.isEmpty || group == null || group.isEmpty) {
        continue;
      }
      final aliases = <String>[];
      final al = o['zh_aliases'];
      if (al is List) {
        for (final x in al) {
          if (x is String && x.isNotEmpty) aliases.add(x);
        }
      }
      out.add(_Oc(name, en, group, aliases, _ownerOf(o)));
    }
    return out;
  }

  /// 条目归属:owner_id 优先,存量数据回退 created_by(同服务端 `_author_key`)。
  /// 老数据那一栏可能是数字,也可能直接写的名字。
  static String? _ownerOf(Map o) {
    for (final v in [o['owner_id'], o['created_by']]) {
      final s = v is String ? v.trim() : (v is int ? '$v' : '');
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  Map<String, String> _parseAuthors(http.Response r) {
    if (r.statusCode != 200) return const {};
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final list = (j is Map) ? j['authors'] : null;
    if (list is! List) return const {};
    final out = <String, String>{};
    for (final a in list) {
      if (a is! Map) continue;
      final id = a['user_id'], nick = a['nickname'];
      if (id is String && nick is String && nick.trim().isNotEmpty) {
        out[id] = nick.trim();
      }
    }
    return out;
  }

  /// 画师匹配名字子串;OC 匹配名字/别名子串。→ (artists, ocs)。
  ///
  /// OC 两处来源,各取前 [limit] 个:[localOcs](本机灵感库的角色条目)在前,底行
  /// 写「本地库」;公共库的接在后面,底行写作者。公共库里本地已经有的(收藏来的 /
  /// 自己发布的副本,按 publicId 或同名认,同 `TagLibrary.isCollected`)不再出第二遍。
  Future<(List<Suggestion>, List<Suggestion>)> search(
    String query, {
    int limit = 5,
    List<TagEntry> localOcs = const [],
  }) async {
    try {
      await _ensureLoaded();
    } catch (_) {
      // 拉不到公共库:本地库照样补
    }
    final artists = _artists ?? const <_Artist>[];
    final ocs = _ocs ?? const <_Oc>[];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return (const <Suggestion>[], const <Suggestion>[]);

    final aOut = <Suggestion>[];
    for (final a in artists) {
      if (a.name.toLowerCase().contains(q)) {
        aOut.add(
          Suggestion(
            text: a.name,
            kind: SuggestionKind.artist,
            insertText: a.artistString,
          ),
        );
        if (aOut.length >= limit) break;
      }
    }

    final localOut = _searchLocal(query, localOcs, limit: limit);
    final mineIds = <String>{}, mineNames = <String>{};
    for (final e in localOcs) {
      final name = e.name.trim();
      if (name.isEmpty || e.positive.trim().isEmpty) continue;
      mineNames.add(name);
      if (e.publicId case final id?) mineIds.add(id);
    }
    final publicOut = <Suggestion>[];
    for (final o in ocs) {
      if (publicOut.length >= limit) break;
      if (mineIds.contains(o.en) || mineNames.contains(o.name.trim())) continue;
      if (!_ocHit(q, o.name, o.aliases)) continue;
      publicOut.add(
        Suggestion(
          text: o.name,
          kind: SuggestionKind.oc,
          trans: (o.en != null && o.en != o.name) ? o.en : null,
          // 目录里没有昵称就写归属 id(QQ 号,老数据里也可能就是名字),
          // 连归属都没有才写「公共库」
          source: _authors[o.owner] ?? o.owner ?? '公共库',
          insertText: o.tagGroup,
        ),
      );
    }
    return (aOut, [...localOut, ...publicOut]);
  }

  /// 本机灵感库的角色条目里,名字 / 别名含 [query] 的前 [limit] 个,底行写「本地库」。
  static List<Suggestion> _searchLocal(
    String query,
    List<TagEntry> localOcs, {
    int limit = 5,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Suggestion>[];
    for (final e in localOcs) {
      if (out.length >= limit) break;
      final name = e.name.trim(), group = e.positive.trim();
      if (name.isEmpty || group.isEmpty || !_ocHit(q, name, e.aliases)) {
        continue;
      }
      out.add(
        Suggestion(
          text: name,
          kind: SuggestionKind.oc,
          source: l10nNow.localLibrary,
          insertText: group,
          local: true,
        ),
      );
    }
    return out;
  }

  static bool _ocHit(String q, String name, List<String> aliases) =>
      name.toLowerCase().contains(q) ||
      aliases.any((x) => x.toLowerCase().contains(q));
}

class _Artist {
  _Artist(this.name, this.artistString);
  final String name;
  final String artistString;
}

class _Oc {
  _Oc(this.name, this.en, this.tagGroup, this.aliases, this.owner);
  final String name;
  final String? en;
  final String tagGroup;
  final List<String> aliases;

  /// 归属 id,见 [ArtistOcLibrary._ownerOf]。
  final String? owner;
}

/// 按后端基址 + 会话构造(任一变即重建,缓存刷新)。
final artistOcLibraryProvider = Provider<ArtistOcLibrary>((ref) {
  final base = ref.watch(backendBaseProvider).value ?? '';
  final sid = ref.watch(botSessionProvider).value?.sessionId;
  return ArtistOcLibrary(base, sid, http.Client());
});

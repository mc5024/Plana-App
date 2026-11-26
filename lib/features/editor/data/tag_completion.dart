import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/net/backend_config.dart';
import '../../../core/net/backend_http.dart';
import '../../inspiration/tag_library.dart';
import '../../inspiration/tag_models.dart';
import 'artist_oc_library.dart';
import 'local_tag_db.dart';
import 'suggestions.dart';
import '../../../l10n/l10n.dart';

/// 请求 Danbooru / Safebooru 图床时附带的客户端 UA(避免默认脚本 UA 被拦截)。
const Map<String, String> kBooruImageHeaders = {
  'User-Agent': 'PlanaApp/1.2 (Flutter)',
};

/// Danbooru wiki 预览:标题 + 中/英摘要 + 别名 + 示例图链接。
class WikiPreview {
  WikiPreview({
    this.title,
    this.summary,
    this.summaryZh,
    this.otherNames = const [],
    this.images = const [],
  });
  final String? title;
  final String? summary;
  final String? summaryZh;
  final List<String> otherNames;
  final List<String> images;
  bool get hasText =>
      (summary != null && summary!.isNotEmpty) ||
      (summaryZh != null && summaryZh!.isNotEmpty) ||
      otherNames.isNotEmpty;

  WikiPreview copyWith({
    String? title,
    String? summary,
    String? summaryZh,
    List<String>? otherNames,
    List<String>? images,
  }) => WikiPreview(
    title: title ?? this.title,
    summary: summary ?? this.summary,
    summaryZh: summaryZh ?? this.summaryZh,
    otherNames: otherNames ?? this.otherNames,
    images: images ?? this.images,
  );
}

/// 标签补全引擎。以离线词库 [LocalTagDb](assets/danbooru.tsv)为准,后端只做兜底:
///  - 英文查离线词库(含拼写纠错),还是一条没有才问后端 `/autocomplete`;
///  - 中文过后端 `/tags/search` 语义搜词;
///  - 画风与 OC 仅来自本机灵感库,不拉取公共库。
/// 后端的几路一律静默:连不上、出错都退回本地能给的,不弹错。
/// query→result 结果缓存;顺带回填注音/热度缓存([cacheTagMeta]),供词下注音层与词条栏反查。
class TagCompletion {
  TagCompletion({
    required this.baseUrl,
    required this.localDb,
    this.artistOcLib = const ArtistOcLibrary(),
    this.localArtists,
    this.localOcs,
    http.Client? client,
  }) : _client = client ?? backendHttpClient();

  /// 后端基址,形如 `https://nai.sora214.top`,末尾无斜杠。
  final String baseUrl;

  /// 离线 Danbooru 标签库。
  final LocalTagDb localDb;

  /// 本地画风 / OC 匹配器。
  final ArtistOcLibrary artistOcLib;

  /// 本机灵感库的画风条目。
  final Future<List<TagEntry>>? localArtists;

  /// 本机灵感库的角色(OC)条目。
  final Future<List<TagEntry>>? localOcs;

  final http.Client _client;

  static const _timeout = Duration(seconds: 12);
  static const _limit = 12;

  // 查询缓存(键=查询串)。超过阈值整表清空,防长会话无界增长——
  // 清空只损失命中率,下次查询重新拉取。
  static const _cacheCap = 500;
  final _cache = <String, SuggestResult>{};
  final _relatedCache = <String, List<String>>{};
  final _originChars = <String, List<String>>{}; // 作品 → 该作品下的角色池
  final _safebooruCache = <String, List<String>>{}; // tag → Safebooru 示例图
  final _rand = Random();

  static void _capped<K, V>(Map<K, V> m, K k, V v) {
    if (m.length > _cacheCap) m.clear();
    m[k] = v;
  }

  static bool _cjk(String s) => s.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);

  // 下划线↔空格:app 内标签用空格,Danbooru 用下划线。
  static String _spaces(String s) => s.replaceAll('_', ' ');
  static String _unders(String s) => s.trim().replaceAll(' ', '_');

  /// 查询当前词的补全。失败静默返回空结果(与 web 一致,不弹错)。
  Future<SuggestResult> query(String raw) async {
    final q = raw.trim();
    final cjk = _cjk(q);
    if (cjk ? q.isEmpty : q.length < 2) return const SuggestResult();

    final key = q.toLowerCase();
    final hit = _cache[key];
    if (hit != null) return hit;

    SuggestResult res;
    try {
      res = await _complete(q, cjk);
    } catch (_) {
      res = const SuggestResult();
    }
    if (!res.isEmpty) _capped(_cache, key, res);
    return res;
  }

  /// 关联共现标签(词条栏「关联」)。走后端 `/api/tags/related`
  /// (DanbooruSearch 共现,web tagRelated.ts 同款参数),拿不到就用内置静态表。
  /// 空结果也缓存——后端同参 24h 缓存,重复问无意义;
  /// 网络失败不缓存,下次再试。顺带把 cn_name 回填注音缓存。
  Future<List<String>> relatedOf(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final hit = _relatedCache[key];
    if (hit != null) return hit;
    if (baseUrl.isEmpty) return relatedTags(key);
    try {
      final r = await _retry(
        () => _client.post(
          Uri.parse('$baseUrl/api/tags/related'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'tags': [_unders(key)],
            'limit': 16,
            'show_nsfw': true,
          }),
        ),
      );
      if (r.statusCode != 200) return relatedTags(key);
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final results = j is Map ? j['results'] : null;
      final out = <String>[];
      if (results is List) {
        for (final e in results) {
          if (e is! Map) continue;
          final tag = e['tag'];
          if (tag is! String || tag.isEmpty) continue;
          final t = _spaces(tag);
          out.add(t);
          final cn = e['cn_name'];
          if (cn is String && cn.isNotEmpty) cacheTagMeta(t, trans: cn);
        }
      }
      _capped(_relatedCache, key, out);
      return out;
    } catch (_) {
      return relatedTags(key);
    }
  }

  /// 作品行骰子:按需拉 `/api/tags/related` 获取该作品下高共现角色池并随机抽一名。
  /// 传入 [exclude] 时尽量避开该角色(池内有多个角色时不重复抽到同一名)。
  Future<String?> randomCharacterOf(String work, {String? exclude}) async {
    final key = _unders(work).toLowerCase();
    if (key.isEmpty || baseUrl.isEmpty) return null;
    var pool = _originChars[key];
    if (pool == null) {
      try {
        final r = await _retry(
          () => _client.post(
            Uri.parse('$baseUrl/api/tags/related'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'tags': [key],
              'limit': 40,
              'show_nsfw': true,
              'categories': ['Character'],
            }),
          ),
        );
        if (r.statusCode != 200) return null;
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final results = j is Map ? j['results'] : null;
        final out = <String>[];
        if (results is List) {
          for (final e in results) {
            if (e is! Map) continue;
            final tag = e['tag'];
            if (tag is! String || tag.isEmpty) continue;
            final t = _spaces(tag);
            out.add(t);
            final cn = _cnHead((e['cn_name'] as String?)?.trim());
            if (cn != null) cacheTagMeta(t, trans: cn);
          }
        }
        if (out.isEmpty) return null;
        _capped(_originChars, key, out);
        pool = out;
      } catch (_) {
        return null;
      }
    }
    if (exclude != null && pool.length > 1) {
      final ex = exclude.trim().toLowerCase();
      final filtered = [
        for (final c in pool)
          if (c.toLowerCase() != ex) c,
      ];
      if (filtered.isNotEmpty) {
        return filtered[_rand.nextInt(filtered.length)];
      }
    }
    return pool[_rand.nextInt(pool.length)];
  }

  // 复用的持久连接偶发被服务端关闭(“Connection closed before full header”)或瞬断,
  // 抛异常就换新连接重试一次。返回码类错误(403/500 等)有响应、不抛异常,不会到这里。
  Future<http.Response> _retry(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(_timeout);
    } catch (_) {
      return await send().timeout(_timeout);
    }
  }

  // ---- 标签 + 画师/OC 库,并行合并 ----
  //
  // 角色与作品按类目归组:英文是离线词库 / autocomplete 的 category 3/4,
  // 中文是语义搜词的 Copyright/Character。
  Future<SuggestResult> _complete(String q, bool cjk) async {
    final tagsF = cjk ? _chineseTags(q) : _englishTags(q);
    final artistsF = localArtists ?? Future.value(const <TagEntry>[]);
    final ocsF = localOcs ?? Future.value(const <TagEntry>[]);
    final (tags, localArt, localOc) = await (tagsF, artistsF, ocsF).wait;
    final (artists, ocs) = artistOcLib.search(
      q,
      localArtists: localArt,
      localOcs: localOc,
    );
    return _group(tags, artists, ocs);
  }

  /// 标签按类目分组,与画师 / OC 合成一份结果。
  SuggestResult _group(
    List<Suggestion> tags,
    List<Suggestion> artists,
    List<Suggestion> ocs,
  ) {
    // 上游标签里也有画师类条目,与库实体同名时两行重复 → tags 剔除同名(实体行
    // 信息更全,保实体);顺手把同名 tag 的热度转给实体(库条目无热度,补上便于排序)。
    String norm(String s) => s.trim().toLowerCase().replaceAll('_', ' ');
    final tagCount = <String, int>{
      for (final t in tags)
        if (t.count > 0) norm(t.text): t.count,
    };
    List<Suggestion> fill(List<Suggestion> xs) => [
      for (final s in xs)
        s.count == 0 && (tagCount[norm(s.text)] ?? 0) > 0
            ? s.copyWith(count: tagCount[norm(s.text)])
            : s,
    ];
    final entityNames = <String>{
      for (final s in [...artists, ...ocs]) norm(s.text),
    };
    final kept = [
      for (final t in tags)
        if (!entityNames.contains(norm(t.text))) t,
    ];
    return SuggestResult(
      tags: [
        for (final t in kept)
          if (t.kind == SuggestionKind.tag) t,
      ],
      characters: [
        for (final t in kept)
          if (t.kind == SuggestionKind.character) t,
      ],
      works: [
        for (final t in kept)
          if (t.kind == SuggestionKind.work) t,
      ],
      artists: fill(artists),
      ocs: ocs,
    );
  }

  /// 英文:先查离线词库(匹配口径同后端补全,见 [LocalTagDb.search]),译名用词库的;
  /// 一条都没有就按拼错纠一次(见 [LocalTagDb.correct])。还是没有(多半是词库之后的
  /// 新标签)才问后端,问不到就空着。
  Future<List<Suggestion>> _englishTags(String q) async {
    var hits = await localDb.search(q, limit: _limit);
    if (hits.isEmpty) hits = await localDb.correct(q, limit: _limit);
    if (hits.isEmpty) {
      try {
        return await _backendAutocomplete(q);
      } catch (_) {
        return const [];
      }
    }
    return _rankEnglish([
      for (final h in hits)
        _tagSuggestion(_spaces(h.tag), h.count, h.category, trans: h.zh),
    ], q);
  }

  /// 中文:语义搜词(`/api/tags/search`)。
  ///
  /// 这里原先还并着一路「AI 推荐 / AI 直译」(中文查询 → LLM 猜 Danbooru 标签),
  /// 2026-08-24 停用、2026-08-28 删除:它打的是 `/api/translate/en2zh` —— 一个
  /// 收任意 messages 的通用 chat 代理,那个端点已被收编成固定格式的翻译接口。
  /// web 那半边(aiRecommendTags / aiDirectTranslate)同时删掉。
  Future<List<Suggestion>> _chineseTags(String q) async {
    final List<Suggestion> found;
    try {
      found = await _backendSearch(q);
    } catch (_) {
      return const []; // 连不上后端:中文只剩本地库的角色,翻译行也不出
    }
    final seen = <String>{};
    final out = <Suggestion>[];
    // 去重保留:上游同一次搜索里角色与作品分类可能给出同名条目。
    for (final s in found) {
      if (seen.add(s.text.toLowerCase())) out.add(s);
    }
    // 「翻译为英文」行:含中文逗号或 >3 个 CJK 字 → 顶部插一条整句翻译入口
    final cjkCount = q.runes.where((r) => r >= 0x4E00 && r <= 0x9FFF).length;
    if (q.contains('，') || cjkCount > 3) {
      out.insert(
        0,
        Suggestion(
          text: q,
          kind: SuggestionKind.tag,
          trans: l10nNow.translateToEnglish,
          natural: true,
        ),
      );
    }
    return out;
  }

  /// 「翻译为英文」:中文整句 → 流畅英文短句(非标签)。仅选中该行时调。
  ///
  /// 提示词 2026-08-28 收进了服务端(`_NATURALIZE_INSTRUCTION`),这边只递一句中文。
  /// 原先走 `/api/translate/en2zh` —— 那是个收任意 `messages` 的通用 chat 代理,
  /// 提示词握在客户端手里等于对外开了个免费 LLM;它现已收紧成模板路由,只认已发布
  /// 版本写死的那几套 prompt(所以旧 APK 照常能用)。
  Future<String?> translateNatural(String zh) async {
    if (baseUrl.isEmpty) return null;
    try {
      final r = await _client
          .post(
            Uri.parse('$baseUrl/api/tags/naturalize'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': zh}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final text = j is Map ? j['text'] : null;
      return text is String && text.trim().isNotEmpty ? text.trim() : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Suggestion>> _backendAutocomplete(String q) async {
    final uri = Uri.parse(
      '$baseUrl/api/tags/autocomplete',
    ).replace(queryParameters: {'query': q, 'limit': '$_limit'});
    final resp = await _retry(() => _client.get(uri));
    if (resp.statusCode != 200) return const [];
    return _parseDanbooru(resp.bodyBytes, q);
  }

  /// 上游的 `cn_name` 是逗号串(建库时一起写进去的中文名 + 出处 + 分类词),
  /// 例如 `五条悟,咒术回战,特级咒术师,五条家`。译名只要第一段 ——
  /// 原先整串塞进 `Suggestion.trans`,而 [transOf] 优先用它,于是中文搜角色时
  /// 副标题就是那一长条(只有 [cacheTagMeta] 那一路被 `_firstTrans` 截过)。
  /// 第一段不含汉字 = 上游没译出来(原样回了英文 tag),当作没有中文名,
  /// 让 wiki 那一路兜底。对齐 web `cnHead()`。
  static String? _cnHead(String? cn) {
    if (cn == null) return null;
    var cut = cn.length;
    for (final sep in const [',', '，']) {
      final i = cn.indexOf(sep);
      if (i >= 0 && i < cut) cut = i;
    }
    final head = cn.substring(0, cut).trim();
    return (head.isEmpty || !_cjk(head)) ? null : head;
  }

  Future<List<Suggestion>> _backendSearch(String q) async {
    final resp = await _retry(
      () => _client.post(
        Uri.parse('$baseUrl/api/tags/search'),
        headers: {'Content-Type': 'application/json'},
        // 显式带上类目:服务端默认值 2026-08-12 才从 ['General'] 放开到
        // ['General','Character'],不写死的话新旧服务端搜出来的东西不一样。
        body: jsonEncode({
          'query': q,
          // 取服务端允许的最大值,条数由服务端分数线决定。
          'limit': 200,
          'show_nsfw': true,
          // Copyright(作品/出处)是本地角色库退役后作品行的唯一来源。
          'target_categories': ['General', 'Character', 'Copyright'],
        }),
      ),
    );
    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final results = (body is Map) ? body['results'] : null;
    if (results is! List) return const [];
    final out = <Suggestion>[];
    for (final r in results) {
      if (r is! Map) continue;
      final tag = (r['tag'] as String?)?.trim();
      if (tag == null || tag.isEmpty) continue;
      final text = _spaces(tag);
      final cnRaw = (r['cn_name'] as String?)?.trim();
      final cn = _cnHead(cnRaw);
      final count = (r['count'] as num?)?.toInt() ?? 0;
      cacheTagMeta(text, trans: cn, count: count);
      // 语义搜索这边的 category 是字符串('Character'/'Copyright'),与 autocomplete
      // 的数字 4/3 是同一件事,两条路都要认。
      final kind = switch ((r['category'] as String?)?.trim().toLowerCase()) {
        'character' => SuggestionKind.character,
        'copyright' => SuggestionKind.work,
        _ => SuggestionKind.tag,
      };
      out.add(
        Suggestion(
          text: text,
          kind: kind,
          trans: cn,
          count: count,
        ),
      );
    }
    return out;
  }

  /// 语义搜角色(AI 助手查角色用):只搜角色类,名字整体查、不拆词 —— 拆开的话
  /// 「芙兰朵露」会被切成「芙兰 / 朵 / 露」,命中别作品里同名的冷门角色。
  /// 拿不到返回空表,不抛。
  Future<List<({String tag, String cnName, int count, String wiki})>>
  searchCharacters(String query, {int limit = 10}) async {
    final q = query.trim();
    if (baseUrl.isEmpty || q.isEmpty) return const [];
    try {
      final resp = await _retry(
        () => _client.post(
          Uri.parse('$baseUrl/api/tags/search'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query': q,
            'limit': limit,
            'top_k': 50,
            'show_nsfw': true,
            'target_categories': ['Character'],
            'use_segmentation': false,
          }),
        ),
      );
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final results = body is Map ? body['results'] : null;
      if (results is! List) return const [];
      return [
        for (final r in results)
          if (r is Map && '${r['tag'] ?? ''}'.trim().isNotEmpty)
            (
              tag: '${r['tag']}'.trim(),
              cnName: '${r['cn_name'] ?? ''}'.trim(),
              count: (r['count'] as num?)?.toInt() ?? 0,
              wiki: '${r['wiki'] ?? ''}'.trim(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 解析 Danbooru `autocomplete.json` 数组 → 标签建议(前缀优先 → 热度降序,剔除 <50 冷门)。
  List<Suggestion> _parseDanbooru(List<int> bytes, String q) {
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! List) return const [];
    final out = <Suggestion>[];
    for (final e in data) {
      if (e is! Map) continue;
      final value = (e['value'] ?? e['name']) as String?;
      if (value == null || value.isEmpty) continue;
      final count = (e['post_count'] as num?)?.toInt() ?? 0;
      if (count != 0 && count < 50) continue; // 冷门标签剔除
      final text = _spaces(value);
      cacheTagMeta(text, count: count);
      out.add(_tagSuggestion(text, count, (e['category'] as num?)?.toInt()));
    }
    return _rankEnglish(out, q);
  }

  /// Danbooru 的 category 是数字:4 = 角色、3 = 作品(copyright)。各自归组 ——
  /// 混在几十条普通标签里根本挑不出来(对齐 web isCharacter/isOrigin)。
  Suggestion _tagSuggestion(
    String text,
    int count,
    int? category, {
    String? trans,
  }) {
    final kind = switch (category) {
      4 => SuggestionKind.character,
      3 => SuggestionKind.work,
      _ => SuggestionKind.tag,
    };
    return Suggestion(
      text: text,
      kind: kind,
      trans: trans,
      count: count,
    );
  }

  /// 英文结果排序:以输入开头的在前,再按热度降序。
  static List<Suggestion> _rankEnglish(List<Suggestion> xs, String q) {
    final ql = q.toLowerCase();
    return xs..sort((a, b) {
      final ap = a.text.toLowerCase().startsWith(ql);
      final bp = b.text.toLowerCase().startsWith(ql);
      if (ap != bp) return ap ? -1 : 1;
      return b.count.compareTo(a.count);
    });
  }

  /// 拉某标签的 Danbooru wiki 预览(标题、摘要、别名与最多 3 张安全示例图)。
  /// 中文摘要若未命中成品表则由 [fetchWikiZh] 异步补拉。
  Future<WikiPreview?> fetchWiki(String tag, {int examples = 3}) async {
    final t = _wikiTag(tag);
    if (t == null) return null;
    try {
      final pv = await _retry(
        () => _client.get(
          Uri.parse('$baseUrl/api/tags/wiki-preview').replace(
            queryParameters: {'tag': t, 'examples': '$examples'},
          ),
        ),
      );
      if (pv.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(pv.bodyBytes));
      if (j is! Map || j['hasWiki'] != true) return null;
      final other = <String>[];
      final on = j['otherNames'];
      if (on is List) {
        for (final x in on) {
          if (x is String && x.isNotEmpty) other.add(x);
        }
      }
      final images = <String>[];
      final exs = j['examples'];
      if (exs is List) {
        for (final e in exs) {
          if (e is! Map) continue;
          final u = e['previewUrl'];
          if (u is String && u.isNotEmpty && !images.contains(u)) {
            images.add(u);
          }
        }
      }
      if (images.isEmpty && j['example'] is Map) {
        final u = (j['example'] as Map)['previewUrl'];
        if (u is String && u.isNotEmpty) images.add(u);
      }
      return WikiPreview(
        title: j['title'] as String?,
        summary: j['summary'] as String?,
        summaryZh: j['summaryZh'] as String?,
        otherNames: other,
        images: images,
      );
    } catch (_) {
      return null;
    }
  }

  /// Safebooru 公开 API 兜底拉取安全示例图(按高分优先)。失败返回空表,不抛。
  Future<List<String>> fetchSafebooruImages(String tag, {int limit = 3}) async {
    final t = tag.trim().toLowerCase().replaceAll(' ', '_');
    if (t.isEmpty) return const [];
    final hit = _safebooruCache[t];
    if (hit != null) return hit;

    Future<List<String>> queryOnce(String tagsParam) async {
      final uri = Uri.https('safebooru.org', '/index.php', {
        'page': 'dapi',
        's': 'post',
        'q': 'index',
        'json': '1',
        'limit': '${limit * 3}',
        'tags': tagsParam,
      });
      final resp = await _client
          .get(uri, headers: kBooruImageHeaders)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const [];
      final raw = utf8.decode(resp.bodyBytes).trim();
      if (raw.isEmpty) return const [];
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      const exts = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
      final out = <String>[];
      for (final item in data) {
        if (item is! Map) continue;
        final candidate = [
          item['sample_url'],
          item['file_url'],
          item['preview_url'],
        ].whereType<String>().firstWhere((u) => u.isNotEmpty, orElse: () => '');
        if (candidate.isEmpty) continue;
        final lower = candidate.toLowerCase();
        if (!exts.any(lower.endsWith)) continue;
        if (!out.contains(candidate)) out.add(candidate);
        if (out.length >= limit) break;
      }
      return out;
    }

    try {
      var urls = await queryOnce('$t sort:score:desc');
      if (urls.isEmpty) urls = await queryOnce(t);
      if (urls.isNotEmpty) _capped(_safebooruCache, t, urls);
      return urls;
    } catch (_) {
      return const [];
    }
  }

  /// 补拉中文摘要(慢路径,见 [fetchWiki])。拿不到 / 空串一律返回 null。
  Future<String?> fetchWikiZh(String tag) async {
    final t = _wikiTag(tag);
    if (t == null) return null;
    try {
      final zh = await _retry(
        () => _client.get(
          Uri.parse(
            '$baseUrl/api/tags/wiki-preview-summary-zh',
          ).replace(queryParameters: {'tag': t}),
        ),
      );
      if (zh.statusCode != 200) return null;
      final zj = jsonDecode(utf8.decode(zh.bodyBytes));
      if (zj is Map) {
        final s = zj['summaryZh'];
        if (s is String && s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  /// wiki 两个接口共用的规范化:没有基址、空串一律 null(不发请求)。
  String? _wikiTag(String tag) {
    if (baseUrl.isEmpty) return null;
    final t = tag.trim().toLowerCase().replaceAll(' ', '_');
    return t.isEmpty ? null : t;
  }

  void dispose() => _client.close();
}

/// 按后端基址 + 会话构造补全引擎;任一变化即重建(缓存随之刷新)。
final tagCompletionProvider = Provider<TagCompletion>((ref) {
  final base = ref.watch(backendBaseProvider).value ?? '';
  final libFuture = ref.watch(tagLibraryProvider.future);
  final tc = TagCompletion(
    baseUrl: base,
    localDb: ref.watch(localTagDbProvider),
    artistOcLib: ref.watch(artistOcLibraryProvider),
    localArtists: libFuture.then(
      (lib) => lib.of(TagCategory.artist),
      onError: (Object _) => const <TagEntry>[],
    ),
    localOcs: libFuture.then(
      (lib) => lib.of(TagCategory.character),
      onError: (Object _) => const <TagEntry>[],
    ),
  );
  ref.onDispose(tc.dispose);
  return tc;
});

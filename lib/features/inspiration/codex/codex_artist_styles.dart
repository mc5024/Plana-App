/// v5 画师词典「单画师词典」按画风重排 —— 照原站 `site/assets/app/artist-style.js`:
/// 目录从「来源 › 测试集」换成「画风大类 › 小类」,一位画师一张卡,组内按 post
/// 降序。画风归属在原站的 `data/artist_styles.json`(schema 3),与法典正文分开发布。
library;

import 'codex_models.dart';

const artistStylesCodexId = 'artist_nai5_personal';
const artistStylesFile = 'artist_styles.json';

const _singleRoot = '单画师词典';
const _unsorted = '未归类';

/// 同一画师多来源时取例图的先后(原站 SPECIMEN_SOURCE_ORDER)。
const _sourceOrder = ['花枝鱼', 'AgIzT', '九七', '雨燕', 'MayRain', 'wwuumm'];

class ArtistStyles {
  const ArtistStyles(this.parents, this.groups, this.artists);

  /// 大类:名字 + 下属小类下标(按展示顺序)。
  final List<({String name, List<int> groups})> parents;

  /// 小类:名字 + 所属大类下标。
  final List<({String name, int parent})> groups;

  /// 画师:代表词条 id、其余来源词条 id、规范标题所在词条 id、post、小类下标。
  final List<
    ({
      String entryId,
      List<String> otherIds,
      String canonicalId,
      int? post,
      int group,
    })
  >
  artists;
}

/// 解析 artist_styles.json;格式不认或不是这本书的数据返回 null(按来源显示)。
ArtistStyles? parseArtistStyles(Object? raw) {
  if (raw is! Map<String, dynamic> ||
      raw['schema'] != 3 ||
      raw['codexId'] != artistStylesCodexId ||
      raw['parents'] is! List ||
      raw['groups'] is! List ||
      raw['artists'] is! List) {
    return null;
  }
  final prefix = raw['idPrefix'] is String ? raw['idPrefix'] as String : '';
  final groups = <({String name, int parent})>[];
  final parents = <({String name, List<int> groups})>[];
  final artists = <
    ({
      String entryId,
      List<String> otherIds,
      String canonicalId,
      int? post,
      int group,
    })
  >[];
  for (final g in raw['groups'] as List) {
    if (g is! Map || g['name'] is! String || g['parent'] is! int) return null;
    groups.add((name: g['name'] as String, parent: g['parent'] as int));
  }
  for (final p in raw['parents'] as List) {
    if (p is! Map || p['name'] is! String || p['groups'] is! List) return null;
    final gs = [
      for (final g in p['groups'] as List)
        if (g is int && g >= 0 && g < groups.length) g,
    ];
    parents.add((name: p['name'] as String, groups: gs));
  }
  for (final a in raw['artists'] as List) {
    if (a is! Map || a['e'] is! String) return null;
    final g = a['g'];
    if (g is! int || g < 0 || g >= groups.length) return null;
    final e = a['e'] as String;
    artists.add((
      entryId: '$prefix$e',
      otherIds: [
        if (a['x'] is List)
          for (final x in a['x'] as List)
            if (x is String) '$prefix$x',
      ],
      canonicalId: '$prefix${a['c'] is String ? a['c'] : e}',
      post: (a['p'] as num?)?.toInt(),
      group: g,
    ));
  }
  if (parents.isEmpty || groups.isEmpty || artists.isEmpty) return null;
  return ArtistStyles(parents, groups, artists);
}

/// 来源优先级:比较时去掉来源名尾部的「(无原图)」。
int _sourceRank(CodexEntry e) {
  final src = e.path.length > 1 ? e.path[1] : '';
  final i = _sourceOrder.indexOf(
    src.replaceFirst(RegExp(r'\s*[（(]无原图[)）]\s*$'), '').trim(),
  );
  return i < 0 ? _sourceOrder.length : i;
}

/// 把画风数据套到法典上:单画师词条的 path 换成 `单画师词典/大类/小类`
/// (认不出的进「未归类」)、标题换成规范标题,目录树重建(计数 = 画师数),
/// 词条按目录顺序排、同小类内 post 降序。数据与词条对不上号时原样返回。
CodexData applyArtistStyles(CodexData d, ArtistStyles s) {
  if (d.meta.id != artistStylesCodexId) return d;
  final byId = {for (final e in d.entries) e.id: e};
  final artistOf = <String, int>{};
  for (var i = 0; i < s.artists.length; i++) {
    final a = s.artists[i];
    for (final id in [a.entryId, ...a.otherIds]) {
      if (!byId.containsKey(id)) return d;
      artistOf[id] = i;
    }
  }

  List<String> groupPath(int g) => [
    _singleRoot,
    s.parents[s.groups[g].parent].name,
    s.groups[g].name,
  ];

  final present = <int>{};
  var unsorted = 0;
  final specimens = <String, ({int artist, int rank})>{};
  final entries = <CodexEntry>[];
  for (final e in d.entries) {
    if (e.path.isEmpty || e.path.first != _singleRoot) {
      entries.add(e);
      continue;
    }
    final i = artistOf[e.id];
    if (i == null) {
      unsorted++;
      entries.add(e.copyWith(path: const [_singleRoot, _unsorted]));
      continue;
    }
    final a = s.artists[i];
    present.add(i);
    final pos = e.id == a.entryId ? 0 : a.otherIds.indexOf(e.id) + 1;
    specimens[e.id] = (artist: i, rank: _sourceRank(e) * 100000 + pos);
    entries.add(
      e.copyWith(
        path: groupPath(a.group),
        title: byId[a.canonicalId]?.title ?? e.title,
      ),
    );
  }
  if (present.isEmpty) return d;

  final perGroup = <int, int>{};
  for (final i in present) {
    final g = s.artists[i].group;
    perGroup[g] = (perGroup[g] ?? 0) + 1;
  }
  final styleChildren = <CodexNode>[
    for (final p in s.parents)
      if (p.groups.any((g) => (perGroup[g] ?? 0) > 0))
        CodexNode(
          p.name,
          p.groups.fold(0, (n, g) => n + (perGroup[g] ?? 0)),
          [
            for (final g in p.groups)
              if ((perGroup[g] ?? 0) > 0)
                CodexNode(s.groups[g].name, perGroup[g]!, const []),
          ],
        ),
    if (unsorted > 0) CodexNode(_unsorted, unsorted, const []),
  ];
  final baseTree = d.effectiveTree;
  final tree = [
    for (final n in baseTree)
      n.name == _singleRoot
          ? CodexNode(n.name, present.length + unsorted, styleChildren)
          : n,
  ];

  // 目录顺序:先序遍历的节点序号;同节点内按 post 降序(未知垫底),同一画师的
  // 各来源例图挨在一起
  final order = <String, int>{};
  void walk(List<CodexNode> nodes, String prefix) {
    for (final n in nodes) {
      final k = prefix.isEmpty ? n.name : '$prefix\u0000${n.name}';
      order[k] = order.length;
      walk(n.children, k);
    }
  }

  walk(tree, '');
  // 路径不是树上节点(比树深)时取最长的那段前缀
  int rankOf(List<String> path) {
    for (var n = path.length; n > 0; n--) {
      final r = order[path.sublist(0, n).join('\u0000')];
      if (r != null) return r;
    }
    return order.length;
  }

  // 排序键先算成整数数组,比较器里只比整数(artist = -1 表示不是画师例图)
  final n = entries.length;
  final rank = List<int>.filled(n, 0);
  final artist = List<int>.filled(n, -1);
  final post = List<int>.filled(n, -1);
  for (var i = 0; i < n; i++) {
    rank[i] = rankOf(entries[i].path);
    final sp = specimens[entries[i].id];
    if (sp != null) {
      artist[i] = sp.artist;
      post[i] = s.artists[sp.artist].post ?? -1;
    }
  }
  final sorted = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      var c = rank[a].compareTo(rank[b]);
      if (c != 0) return c;
      if (artist[a] >= 0 && artist[b] >= 0) {
        c = post[b].compareTo(post[a]);
        if (c != 0) return c;
        c = artist[a].compareTo(artist[b]);
        if (c != 0) return c;
      }
      return a.compareTo(b);
    });

  return CodexData(
    meta: d.meta,
    entries: [for (final i in sorted) entries[i]],
    tree: tree,
    specimens: specimens,
  );
}

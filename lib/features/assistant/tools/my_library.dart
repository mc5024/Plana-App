/// 「我的库」:灵感页里用户自己的画风库 / OC 库。查画风、查 OC 两个工具与它们的预取都从这里取,
/// 库的内容只在本机用。
library;

import 'dart:collection';
import 'dart:math';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../runtime/placeholders.dart' show artistPlaceholder;

// ---- 规范化 ----

final _punctOrSpace = RegExp(r'[\p{P}\s]', unicode: true);

/// 名字比对用的规范化:NFKC、小写、去掉标点和空白。
/// 库里存 DeepSeek,用户写 deepseek、deep seek 都要对得上。
String normalizeName(String s) =>
    unorm.nfkc(s).toLowerCase().replaceAll(_punctOrSpace, '');

/// 按码点数长度,名字里带表情时和 UTF-16 长度不一样。
int nameLength(String s) => s.runes.length;

/// 按 [key] 从大到小排,一样大的保持原来的先后(Dart 的 sort 不保证稳定)。
List<T> largestFirst<T>(List<T> items, int Function(T) key) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = key(b.$2).compareTo(key(a.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

// ---- 库条目 ----

/// 一条画师串。
class LibArtist {
  const LibArtist({required this.id, required this.name, required this.prompt});

  final String id;
  final String name;

  /// 完整画师串。
  final String prompt;

  /// 块里、占位符里用的名字:有编号用编号。
  String get label => id.isNotEmpty ? id : name;
}

/// 一个 OC。
class LibOc {
  const LibOc({
    required this.enName,
    required this.zhName,
    required this.aliases,
    required this.tagGroup,
  });

  final String enName;
  final String zhName;
  final List<String> aliases;
  final String tagGroup;

  /// 给模型看的名字:有中文名用中文名。
  String get label => zhName.isNotEmpty ? zhName : enName;
}

String _field(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v'.trim();
  }
  return '';
}

/// 控制器拼好的画风库(`{'id','name','prompt'}`)→ 条目。没内容的丢掉、重复的去掉。
List<LibArtist> libArtistsOf(List<Map<String, dynamic>> raw) {
  final seen = <String>{};
  final out = <LibArtist>[];
  for (final m in raw) {
    final id = _field(m, const ['id', 'name']);
    final name = _field(m, const ['name']);
    final prompt = _field(m, const ['prompt', 'artist_string']);
    if ((id.isEmpty && name.isEmpty) || prompt.isEmpty) continue;
    final a = LibArtist(
      id: id.isNotEmpty ? id : name,
      name: name.isNotEmpty ? name : id,
      prompt: prompt,
    );
    if (seen.add('${a.id.toUpperCase()}|${a.name.toUpperCase()}|${a.prompt}')) {
      out.add(a);
    }
  }
  return out;
}

/// 控制器拼好的 OC 库(`{'en_name','zh_name','zh_aliases','tag_group'}`)→ 条目。
List<LibOc> libOcsOf(List<Map<String, dynamic>> raw) {
  final seen = <String>{};
  final out = <LibOc>[];
  for (final m in raw) {
    final name = _field(m, const ['name', 'zh_name', 'id']);
    final en = _field(m, const ['en_name', 'id']);
    final zh = _field(m, const ['zh_name', 'zhName']);
    final tags = _field(m, const ['tag_group', 'positive']);
    final enName = en.isNotEmpty ? en : name;
    final zhName = zh.isNotEmpty ? zh : name;
    if ((enName.isEmpty && zhName.isEmpty) || tags.isEmpty) continue;
    final rawAliases = m['zh_aliases'] ?? m['aliases'];
    final oc = LibOc(
      enName: enName,
      zhName: zhName,
      aliases: [
        if (rawAliases is List)
          for (final a in rawAliases)
            if (a != null && '$a'.trim().isNotEmpty) '$a',
      ],
      tagGroup: tags,
    );
    if (seen.add('${oc.enName.toLowerCase()}|${oc.zhName}|${oc.tagGroup}')) {
      out.add(oc);
    }
  }
  return out;
}

// ---- 字面匹配(预取用) ----

final _artistIdRe = RegExp(r'(?<![A-Za-z])([A-Za-z])(\d+)');

/// 编号形状的名字(A1、b12)。
final _artistIdShape = RegExp(r'^[A-Za-z]\d+$');

/// 一块最多几条。
const kBlockMax = 10;

/// 这句话点到的画师串 → [(块里的名字, 完整串)],按块里的顺序。
///
/// 两条路:编号(A1 / b12)、名字(规范化后至少 2 个字,越长越靠前)。编号形状的名字
/// 只走编号那条,「A12」里不会再撞出 A1。最多 10 条。
List<(String, String)> matchArtists(String text, List<LibArtist> artists) {
  final out = <(String, String)>[];
  final seen = <String>{};
  for (final m in _artistIdRe.allMatches(text)) {
    final id = '${m[1]!.toUpperCase()}${m[2]}';
    for (final a in artists) {
      if (a.id.toUpperCase() != id && a.name.toUpperCase() != id) continue;
      if (!seen.add(a.label.toUpperCase())) continue;
      out.add((a.label, a.prompt));
      break;
    }
  }
  final textNorm = normalizeName(text);
  final byName = <(int, String, String)>[];
  for (final a in artists) {
    if (a.name.isEmpty ||
        _artistIdShape.hasMatch(a.name.trim()) ||
        seen.contains(a.label.toUpperCase())) {
      continue;
    }
    final n = normalizeName(a.name);
    if (nameLength(n) < 2 || !textNorm.contains(n)) continue;
    seen.add(a.label.toUpperCase());
    byName.add((nameLength(n), a.name, a.prompt));
  }
  for (final (_, name, prompt) in largestFirst(byName, (e) => e.$1)) {
    out.add((name, prompt));
  }
  return out.take(kBlockMax).toList();
}

/// 这句话点到的 OC → [(命中的名字、以顿号连起来, tag 组)]。中文名、别名、去掉 `OC_`
/// 的键名都认,命中的名字越长越靠前,最多 10 个。
List<(String, String)> matchOcs(String text, List<LibOc> ocs) {
  final textNorm = normalizeName(text);
  final hits = <(int, String, String)>[];
  for (final oc in ocs) {
    final bare = oc.enName.toLowerCase().startsWith('oc_')
        ? oc.enName.substring(3)
        : oc.enName;
    final names = [
      for (final n in [oc.zhName, ...oc.aliases, bare])
        if (n.trim().isNotEmpty) n.trim(),
    ];
    final hit = [
      for (final n in names)
        if (normalizeName(n) case final k
            when k.isNotEmpty && textNorm.contains(k))
          n,
    ];
    if (hit.isEmpty) continue;
    hits.add((
      hit.map(nameLength).reduce(max),
      LinkedHashSet.of(hit).join('、'),
      oc.tagGroup,
    ));
  }
  return [
    for (final (_, label, tags) in largestFirst(
      hits,
      (e) => e.$1,
    ).take(kBlockMax))
      (label, tags),
  ];
}

// ---- 查询(工具用) ----

/// 查画风返回的一条。
Map<String, dynamic> artistToolEntry(LibArtist a) => {
  'id': a.id,
  'name': a.name,
  'prompt': a.prompt,
  'placeholder': artistPlaceholder(a.label),
};

List<String> _stringList(Object? v) => switch (v) {
  final List l => [
    for (final e in l)
      if (e != null && '$e'.trim().isNotEmpty) '$e'.trim(),
  ],
  final String s when s.trim().isNotEmpty => [s.trim()],
  _ => const [],
};

/// 工具参数里的整数,模型写成字符串也认。
int intArg(Object? v, int fallback) => switch (v) {
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()) ?? fallback,
  _ => fallback,
};

/// 按编号 / 名字列表,或者按关键词(名字和画师串里找)查画风库。
List<LibArtist> searchArtists(
  List<LibArtist> artists,
  Map<String, dynamic> args,
) {
  final ids = {
    for (final i in _stringList(args['artist_ids'])) i.toUpperCase(),
  };
  if (ids.isNotEmpty) {
    return [
      for (final a in artists)
        if (ids.contains(a.id.toUpperCase()) ||
            ids.contains(a.name.toUpperCase()))
          a,
    ];
  }
  final k = '${args['keyword'] ?? ''}'.trim().toLowerCase();
  if (k.isEmpty) return const [];
  return [
    for (final a in artists)
      if ('${a.name} ${a.prompt}'.toLowerCase().contains(k)) a,
  ];
}

/// 按名字 / 别名查 OC 库。
List<LibOc> searchOcs(List<LibOc> ocs, String query) {
  final q = normalizeName(query);
  if (q.isEmpty) return const [];
  return [
    for (final oc in ocs)
      if (normalizeName(oc.enName).contains(q) ||
          normalizeName(oc.zhName).contains(q) ||
          oc.aliases.any((a) => normalizeName(a).contains(q)))
        oc,
  ];
}

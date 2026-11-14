/// 画师串 / OC 占位符:发给模型的是 `__ARTIST_A1__` / `__OC_小小纺__`,完整内容留在本机,
/// 出图前换回来。
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../tools/my_library.dart' show LibArtist;

/// 画师串占位符 `__ARTIST_A1__`。写歪了也认:大小写、两头多了空格。
final artistTokenRe = RegExp(
  r'__\s*ARTIST\s*_\s*([^\s,，_]+(?:_[^\s,，_]+)*)\s*__',
  caseSensitive: false,
);

/// 名字 → 占位符主体:全角半角统一,空白和逗号换成下划线,连续下划线并成一个。
String artistTokenBody(String name) => unorm
    .nfkc(name)
    .trim()
    .replaceAll(RegExp(r'[\s,，]+'), '_')
    .replaceAll(RegExp(r'_{2,}'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String artistPlaceholder(String name) => '__ARTIST_${artistTokenBody(name)}__';

String _tokenKey(String body) => artistTokenBody(body).toLowerCase();

typedef ArtistHit = ({String name, String content});

/// 这一轮的画师串占位符映射:主体 → (显示名, 完整画师串)。同名先到先得。
class ArtistPlan {
  final _entries = <String, ArtistHit>{};

  bool get isEmpty => _entries.isEmpty;

  /// 记一条,返回它的占位符。
  String add(String name, String content) {
    final hit = _entries.putIfAbsent(
      _tokenKey(name),
      () => (name: name, content: content),
    );
    return artistPlaceholder(hit.name);
  }

  ArtistHit? get(String body) => _entries[_tokenKey(body)];

  /// 占位符 → 完整内容。折历史和画布用,调试记录里也记这份。
  Map<String, String> get tokens => {
    for (final e in _entries.values) artistPlaceholder(e.name): e.content,
  };
}

/// OC 占位符 `__OC_小小纺__`。模型只看名字和占位符,完整 tag 组留在本机。
final ocTokenRe = RegExp(
  r'__\s*OC\s*_\s*([^\s,，_]+(?:_[^\s,，_]+)*)\s*__',
  caseSensitive: false,
);

String ocPlaceholder(String name) => '__OC_${artistTokenBody(name)}__';

class OcPlan {
  final _entries = <String, ArtistHit>{};

  String add(String name, String tags) {
    final key = _tokenKey(name);
    if (key.isNotEmpty && tags.isNotEmpty) {
      _entries.putIfAbsent(key, () => (name: name, content: tags));
    }
    return ocPlaceholder(name);
  }

  ArtistHit? get(String body) => _entries[_tokenKey(body)];

  Map<String, String> get tokens => {
    for (final e in _entries.values) ocPlaceholder(e.name): e.content,
  };
}

/// 文字里认得出的完整串折成占位符(映射见 [ArtistPlan.tokens] / [OcPlan.tokens])。
///
/// 画布、历史里的画师串都是当初逐字填进去的,逐字比就对得上;用户在创作页改过的对不上,
/// 原样给模型。长的先换,免得短串吃掉长串的一截。
String collapseArtistStrings(String text, Map<String, String> tokens) {
  final entries = [
    for (final e in tokens.entries)
      if (e.value.isNotEmpty) e,
  ]..sort((a, b) => b.value.length.compareTo(a.value.length));
  var out = text;
  for (final e in entries) {
    out = out.replaceAll(e.value, e.key);
  }
  return out;
}

// ---- 还原 ----

typedef ArtistResolver = ArtistHit? Function(String body);

/// 占位符主体 → (显示名, 完整串)。先查本轮映射,查不到再查画风库;库里查到的顺手记进映射。
ArtistResolver artistResolver(ArtistPlan plan, List<LibArtist> artists) {
  Map<String, ArtistHit>? library;
  return (body) {
    final hit = plan.get(body);
    if (hit != null) return hit;
    if (library == null) {
      final lib = <String, ArtistHit>{};
      for (final a in artists) {
        for (final n in [a.id, a.name]) {
          if (n.trim().isEmpty) continue;
          lib.putIfAbsent(
            _tokenKey(n),
            () => (name: a.name.isNotEmpty ? a.name : n, content: a.prompt),
          );
        }
      }
      library = lib;
    }
    final found = library![_tokenKey(body)];
    if (found != null) plan.add(found.name, found.content);
    return found;
  };
}

const _keep = '\u0000'; // 占位:这里要填回第 n 条完整内容
const _drop = '\u0001'; // 占位:这里删掉了一个占位符
final _dropRe = RegExp(r'\s*\x01\s*,\s*|\s*,\s*\x01|\x01');
final _keepRe = RegExp(r'\x00(\d+)\x00');

/// 占位符删掉之后留下的空壳:`1.2::::`、`{}`、`[]`
final _emptyWrap = RegExp(r'-?\d*\.?\d+::\s*::|\{\s*\}|\[\s*\]');

String _dropMarks(String s) {
  final cleaned = s.replaceAll(_dropRe, '');
  final wrapped = cleaned.replaceAll(_emptyWrap, _drop);
  return wrapped != cleaned ? wrapped.replaceAll(_dropRe, '') : cleaned;
}

/// 一段 tag 里的画师串占位符 → 完整画师串。
///
///   · 认不出的删掉(编号是模型编的,或者库里已经没有了);
///   · 同一个占位符写了两遍,第二遍起删掉;
///   · 完整内容已经在这段里了(模型自己又抄了一遍)只删占位符。
///
/// 填回去的内容**逐字**不动:先删、收拾删出来的逗号和空壳,最后才把内容填进去。
({String text, List<String> used, List<String> notes}) expandArtistText(
  String text,
  ArtistResolver resolve,
) {
  if (text.isEmpty || !artistTokenRe.hasMatch(text)) {
    return (text: text, used: const [], notes: const []);
  }
  final used = <String>[];
  final notes = <String>[];
  final seen = <String>{};
  final fills = <String>[];
  var out = text.replaceAllMapped(artistTokenRe, (m) {
    final body = m[1]!;
    final hit = resolve(body);
    if (hit == null) {
      notes.add('${m[0]} 在资料库里找不到，已删掉');
      return _drop;
    }
    if (!seen.add(_tokenKey(body))) return _drop;
    if (text.contains(hit.content)) {
      notes.add('${m[0]} 的完整内容已经写在里面了，占位符删掉');
      return _drop;
    }
    used.add(hit.name);
    fills.add(hit.content);
    return '$_keep${fills.length - 1}$_keep';
  });
  if (out.contains(_drop)) out = _dropMarks(out).trim();
  out = out.replaceAllMapped(_keepRe, (m) => fills[int.parse(m[1]!)]);
  return (text: out, used: used, notes: notes);
}

/// 画面里要换占位符的那几段文字:正负向词,以及每个角色的正负向词。
Iterable<String> drawTexts(Map<String, dynamic> draw) sync* {
  for (final k in const ['positive', 'negative']) {
    if (draw[k] != null) yield '${draw[k]}';
  }
  if (draw['characters'] case final List chars) {
    for (final c in chars) {
      if (c is! Map) continue;
      for (final k in const ['positive', 'negative']) {
        if (c[k] != null) yield '${c[k]}';
      }
    }
  }
}

/// 画面里每段文字都过一遍 [fix]。
Map<String, dynamic> _mapDrawTexts(
  Map<String, dynamic> draw,
  String Function(Object?) fix,
) => {
  ...draw,
  if (draw['positive'] != null) 'positive': fix(draw['positive']),
  if (draw['negative'] != null) 'negative': fix(draw['negative']),
  if (draw['characters'] is List)
    'characters': [
      for (final c in draw['characters'] as List)
        c is Map<String, dynamic>
            ? {
                ...c,
                if (c['positive'] != null) 'positive': fix(c['positive']),
                if (c['negative'] != null) 'negative': fix(c['negative']),
              }
            : c,
    ],
};

/// 画面里各处的画师串占位符都换回完整串。没有占位符原样返回(同一个对象)。
Map<String, dynamic>? expandDraw(
  Map<String, dynamic>? draw,
  ArtistResolver resolve,
) {
  if (draw == null || !drawTexts(draw).any(artistTokenRe.hasMatch)) {
    return draw;
  }
  return _mapDrawTexts(draw, (v) => expandArtistText('$v', resolve).text);
}

/// 一段文字里的 OC 占位符 → 完整 tag 组。规则同 [expandArtistText]。
String expandOcText(String text, OcPlan plan) {
  if (!ocTokenRe.hasMatch(text)) return text;
  final seen = <String>{};
  final fills = <String>[];
  var out = text.replaceAllMapped(ocTokenRe, (m) {
    final body = m[1]!;
    final hit = plan.get(body);
    if (hit == null ||
        !seen.add(_tokenKey(body)) ||
        text.contains(hit.content)) {
      return _drop;
    }
    fills.add(hit.content);
    return '$_keep${fills.length - 1}$_keep';
  });
  if (out.contains(_drop)) out = _dropMarks(out).trim();
  return out.replaceAllMapped(_keepRe, (m) => fills[int.parse(m[1]!)]);
}

/// 画面里各处的 OC 占位符都换回完整 tag 组。没有占位符原样返回(同一个对象)。
Map<String, dynamic>? expandOcDraw(Map<String, dynamic>? draw, OcPlan plan) {
  if (draw == null || !drawTexts(draw).any(ocTokenRe.hasMatch)) return draw;
  return _mapDrawTexts(draw, (v) => expandOcText('$v', plan));
}

/// 给用户看的正文里出现的 OC 占位符换成名字。
String namesInOcReply(String text, OcPlan plan) =>
    text.replaceAllMapped(ocTokenRe, (m) => plan.get(m[1]!)?.name ?? m[1]!);

/// 给用户看的正文里出现的画师串占位符换成名字(`A1`),不换成一长串 tag。
String namesInReply(String text, ArtistResolver resolve) =>
    text.replaceAllMapped(artistTokenRe, (m) => resolve(m[1]!)?.name ?? m[1]!);

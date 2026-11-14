/// 沿用资源账本:这一轮用到的画师串(OC 占位符模式下还有 OC),挂在 AI 消息上,
/// 下一轮带回来。用户这轮没再提「A1」,块里照样补上,出处不会断。
library;

import 'dart:math';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../tools/my_library.dart' show LibArtist;

/// 账本里只记下了第一行的多行画师串,按画风库里同名那条补全。
Map<String, Map<String, String>> healRememberedArtists(
  Map<String, Map<String, String>> remembered,
  List<LibArtist> artists,
) {
  final slot = remembered['artist'];
  if (slot == null || slot.isEmpty) return remembered;
  final library = <String, String>{};
  for (final a in artists) {
    if (!a.prompt.contains('\n')) continue;
    for (final n in [a.id, a.name]) {
      if (n.trim().isNotEmpty) {
        library.putIfAbsent(n.trim().toUpperCase(), () => a.prompt);
      }
    }
  }
  if (library.isEmpty) return remembered;
  return {
    ...remembered,
    'artist': {
      for (final e in slot.entries)
        e.key: switch (library[e.key.trim().toUpperCase()]) {
          final full?
              when e.value.isNotEmpty &&
                  full.split('\n').first.trim() == e.value.trim() =>
            full,
          _ => e.value,
        },
    },
  };
}

final _wPrefix = RegExp(
  r'^\s*-?\d*\.?\d+\s*::',
); // 1.2::tag:: / -1::tag:: / .8::tag::
final _wSuffix = RegExp(r':\s*-?\d*\.?\d+\s*\)?$'); // (tag:1.2)
final _spaces = RegExp(r'\s+');

// 切 tag:英文 / 中文逗号、换行,以及句末标点后面跟空白(「artist:a. A girl…」)
final _tagSplit = RegExp(r'[,，\n\r]|(?<=[.!?。！？])\s+');
final _wAny = RegExp(r'-?\d*\.?\d+\s*::');
final _wSd = RegExp(r':\s*-?\d*\.?\d+\s*\)');
final _artistPrefix = RegExp(r'^artist\s*:\s*');
const _tagEdges = '{}[]() \t.。!?！？';

String _stripChars(String s, String chars) {
  var start = 0;
  var end = s.length;
  while (start < end && chars.contains(s[start])) {
    start++;
  }
  while (end > start && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}

/// 一枚 tag 规范化成比较用的样子:权重语法、全角半角、大小写、下划线和空格、转义括号、
/// `artist:` 前缀、句末标点,这些差别都不算换了一枚 tag。
String _normTag(String raw) {
  var t = unorm.nfkc(raw).trim();
  t = t.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
  t = t.replaceFirst(_wPrefix, '').replaceAll('::', '');
  t = t.replaceFirst(_wSuffix, '');
  t = _stripChars(t, _tagEdges).replaceAll('_', ' ');
  t = t.replaceAll(_spaces, ' ').trim().toLowerCase();
  return t.replaceFirst(_artistPrefix, '');
}

Set<String> _bareTags(String text) => {
  for (final raw in text.split(_tagSplit))
    if (_normTag(raw) case final t when t.isNotEmpty) t,
};

/// 整段提示词规范化,给 [_phraseIn] 用:权重语法抹掉,括号本身留着。
String _normText(String text) {
  var t = unorm.nfkc(text);
  t = t.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
  t = t.replaceAll(_wAny, ' ').replaceAll('::', ' ');
  t = t.replaceAll(_wSd, ')');
  t = t.replaceAll(RegExp(r'[{}\[\]]'), ' ').replaceAll('_', ' ');
  return t.replaceAll(_spaces, ' ').toLowerCase();
}

/// 规范化后的 tag 作为完整词组出现在整段文字里。英文按词边界认,中文照子串认。
bool _phraseIn(String tag, String text) {
  if (tag.isEmpty) return false;
  if (tag.codeUnits.every((c) => c < 128)) {
    return RegExp(
      '(?<![a-z0-9])${RegExp.escape(tag)}(?![a-z0-9])',
    ).hasMatch(text);
  }
  return text.contains(tag);
}

/// 这轮实际发出的画面里还有没有这份资源。
///
/// 整串原样在里面就算在用;否则按 tag 比,规范化后逐枚比、比不上的再看有没有作为词组
/// 写进句子里,命中 ≥2 枚算在用(只有 1 枚的 ≥1)。故意偏松:误留只是多发一个块,
/// 误删则下一轮又得重新认领。
bool resourceStillInUse(String value, Map<String, dynamic> spec) {
  final v = value.trim();
  final texts = [
    '${spec['positive'] ?? ''}',
    if (spec['characters'] case final List chars)
      for (final c in chars)
        if (c is Map) '${c['positive'] ?? ''}',
  ];
  if (v.isNotEmpty && texts.any((t) => t.contains(v))) return true;
  final want = _bareTags(v);
  if (want.isEmpty) return false;
  final have = {for (final t in texts) ..._bareTags(t)};
  final joined = texts.map(_normText).join(' , ');
  final hits = want
      .where((w) => have.contains(w) || _phraseIn(w, joined))
      .length;
  return hits >= min(2, want.length);
}

/// 收尾记账:本轮命中的 ∪ 上轮记着的,再按「还在不在这幅画里」筛一遍。
/// [spec] 为 null(这轮没出图)时不筛 —— 没出图不代表用户放弃了这套画风。
Map<String, Map<String, String>> mergeLedger(
  Map<String, Map<String, String>> remembered,
  Map<String, Map<String, String>> thisTurn,
  Map<String, dynamic>? spec, {
  bool rememberOcs = false,
}) {
  final out = <String, Map<String, String>>{};
  // 默认只记画师串;OC 占位符模式下才保留仍在使用的 OC
  for (final kind in [if (rememberOcs) 'oc', 'artist']) {
    final slot = {...?remembered[kind], ...?thisTurn[kind]};
    if (spec != null) slot.removeWhere((_, v) => !resourceStillInUse(v, spec));
    if (slot.isNotEmpty) out[kind] = slot;
  }
  return out;
}

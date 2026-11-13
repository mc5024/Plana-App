/// 法典源自带的 tag 中文对照(原站 `data/tag_zh/`,2026-09 上线):
/// `core.json` 装全站高频 tag,`<法典id>.json` 装只在那一部里出现的长尾与整句,
/// 两边的键互不重叠。每张表分三组译名,优先级 人工校对(m)> 社区词库(d)>
/// AI 机翻(a),一个键只落在其中一组。
///
/// 这些表是原站**照着法典词条逐条建的**:法典里的自然语言碎片(`1.blue horn-shaped
/// hair ornaments…`)、质量词(`very aesthetic`、`year 2025`)离线词库一概不认识,
/// 这里基本都有;常见 tag 的译名也比离线词库准(`cowboy shot` 不是「牛仔镜头」)。
///
/// 查表键必须与原站**逐条一致** —— 前端 `site/assets/app/tag-zh-core.js` 的
/// tagZhKey、构建端 `tools/build_tag_zh.py` 的 tag_key,两边共用
/// `tools/fixtures/tag_zh_keys.json` 防漂移;那份夹具原样搬进了
/// codex_tag_zh_test.dart。键算得不一样,表里有也查不到。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' show md5;

import 'codex_models.dart' show CodexMeta;

final _weightPrefix = RegExp(r'^-?\d+(?:\.\d+)?::');
final _sdWeightSuffix = RegExp(r':\s*-?\d+(?:\.\d+)?$');
final _latin = RegExp('[a-z]', caseSensitive: false);
final _spaces = RegExp(r'\s+');
const _maxKeyLength = 300;

String _trimChars(String s, String chars) {
  var a = 0, b = s.length;
  while (a < b && chars.contains(s[a])) {
    a++;
  }
  while (b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

int _count(String s, String ch) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ch) n++;
  }
  return n;
}

/// 一段 tag 原文 → 查表键:剥 NAI 的 `{}` `[]` 与 `1.2::`、SD 的 `(tag:1.2)`,
/// 下划线当空格、压空白、小写。空、无英文字母、`artist:` 前缀、超长的返回空串
/// (不查)。逐行照搬原站 tagZhKey,别顺手「优化」。
String tagZhKey(String piece) {
  var text = piece.replaceAll(r'\(', '').replaceAll(r'\)', '');
  for (var i = 0; i < 12; i++) {
    final before = text;
    text = text.trim().replaceFirst(_weightPrefix, '');
    if (text.endsWith('::')) text = text.substring(0, text.length - 2);
    text = _trimChars(text, '{}[]"');
    while (text.startsWith('(') && _count(text, '(') > _count(text, ')')) {
      text = text.substring(1);
    }
    while (text.endsWith(')') && _count(text, ')') > _count(text, '(')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.startsWith('(') && text.endsWith(')')) {
      text = text.substring(1, text.length - 1);
    }
    text = text.replaceFirst(_sdWeightSuffix, '');
    if (text == before) break;
  }
  text = text.replaceAll('', '(').replaceAll('', ')');
  final key = text
      .replaceAll('_', ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .toLowerCase();
  if (key.isEmpty ||
      !_latin.hasMatch(key) ||
      key.startsWith('artist:') ||
      key.runes.length > _maxKeyLength) {
    return '';
  }
  return key;
}

/// 一张对照表(core 或某部法典的分片)。
class TagZhShard {
  const TagZhShard({
    this.m = const {},
    this.d = const {},
    this.a = const {},
    this.shards = const [],
  });

  /// 人工校对:维护者手订,也用来纠正词库在提示词语境里译错的词。
  final Map<String, String> m;

  /// 社区词库(Auto-NovelAI-Refactor,GPL-3.0)。
  final Map<String, String> d;

  /// AI 机翻:只补前两组都没有的长尾。
  final Map<String, String> a;

  /// 只有 core 带:哪些法典另有分片。不在单里的书只有 core,别去拉那个 404。
  final List<String> shards;

  static const schema = 1;

  /// 形态不对(不是对象、schema 不认)返回 null,当作没有对照表。
  /// 译名不是字符串或是空白的条目丢掉(原站 normalizeTagZhShard 同口径)。
  static TagZhShard? fromJson(Object? j) {
    if (j is! Map || j['schema'] != schema) return null;
    Map<String, String> group(Object? v) => v is Map
        ? {
            for (final e in v.entries)
              if (e.key is String &&
                  e.value is String &&
                  (e.value as String).trim().isNotEmpty)
                e.key as String: e.value as String,
          }
        : const {};
    final shards = j['shards'];
    return TagZhShard(
      m: group(j['m']),
      d: group(j['d']),
      a: group(j['a']),
      shards: shards is List
          ? [
              for (final s in shards)
                if (s is String) s,
            ]
          : const [],
    );
  }
}

/// 一部法典查译名用的表:core + 该书分片(没有分片的书只有 core)。
class CodexTagZh {
  const CodexTagZh(this.core, [this.shard]);

  final TagZhShard core;
  final TagZhShard? shard;

  /// [tag](芯片上的名字或整段原文都行,键会再归一一遍)的中文对照,查不到
  /// 返回 null。组间 人工 > 词库 > AI,同组先 core 后分片,与原站同序。
  String? lookup(String tag) {
    final k = tagZhKey(tag);
    if (k.isEmpty) return null;
    final s = shard;
    return core.m[k] ?? s?.m[k] ?? core.d[k] ?? s?.d[k] ?? core.a[k] ?? s?.a[k];
  }
}

/// isolate 里解析一张对照表(core 1MB 出头、三万来条)。顶层函数(compute 要求);
/// 坏 JSON 也回 null,不往外抛。
TagZhShard? tagZhParsePayload(String raw) {
  try {
    return TagZhShard.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

/// 对照表落盘缓存的戳:索引里各部 `id@版本` 的摘要。
///
/// 不能只看本书的版本号 —— 原站按全站统计挑 core(出现在两部以上、或三条词条
/// 以上才进),任何一部更新都可能把某个词在 core 与各书分片之间挪来挪去。戳跟着
/// 全站走,读出来的 core 与分片就始终是同一批构建的。
/// (原站不认 If-None-Match,带 ETag 照样回 200 全量,条件请求这条路走不通。)
String codexIndexStamp(List<CodexMeta> index) {
  final parts = [for (final m in index) '${m.id}@${m.version}']..sort();
  return md5.convert(utf8.encode(parts.join('\n'))).toString().substring(0, 12);
}

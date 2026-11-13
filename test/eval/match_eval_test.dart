// 图库「按角色 / 按画风」归类的命中率评测 —— 不是回归测试。
//
// 读外部真实数据(公共 OC 库、公共画师串库、社区法典),按各种改写条件造提示词,
// 跑 app 里真正的匹配链路(normalizeSearchText → tokenizeSet → OcMatcher /
// StyleMatcher,帖子数取自离线词库),打印命中率 / 串味率 / 误命中率表,
// 外加 OC 门槛扫描。改 gallery_groups.dart 的判据或门槛之前先跑一遍。
//
// 数据目录由环境变量 MATCH_EVAL_DIR 指定(内含 oc_data.json、artist_strings.json、
// nai_common.json);没设就整个跳过,不影响常规测试。报告另写到 MATCH_EVAL_OUT。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/util/prompt_tokens.dart';
import 'package:plana_app/features/editor/data/local_tag_db.dart';
import 'package:plana_app/features/editor/data/tag_index.dart';
import 'package:plana_app/features/gallery/gallery_groups.dart';
import 'package:plana_app/features/gallery/gallery_search.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

// ── 管线 ───────────────────────────────────────────────

List<String> pieces(String s) => [
  for (final p in s.split(RegExp(r'[,，]')))
    if (p.trim().isNotEmpty) p.trim(),
];

String joinP(Iterable<String> ps) => ps.join(', ');

/// 与图库检索索引同一口径:正向 + 角色正向拼起来 → normalizeSearchText。
String imageText(String prompt, [List<String> chars = const []]) =>
    normalizeSearchText(
      [prompt, ...chars].where((t) => t.trim().isNotEmpty).join(', '),
    );

/// 同上,再分词。
Set<String> imageToks(String prompt, [List<String> chars = const []]) =>
    tokenizeSet(imageText(prompt, chars));

class Ent {
  Ent(this.key, this.raw) : ps = pieces(raw);
  final String key;
  final String raw;
  final List<String> ps;
  late final Set<String> toks = tokenizeSet(raw);
  int get n => toks.length;

  /// 自然语言型(整句描述):三成以上片段是 5 个词以上的句子。
  late final bool prose =
      ps.where((p) => p.split(RegExp(r'\s+')).length >= 5).length >=
      ps.length * .3;
}

/// [also] = 同一张图里另一个理应命中的条目(两个 OC 同框),不算串味。
typedef Scn = ({String prompt, List<String> chars, String? also});

Scn bare(String prompt, [List<String> chars = const []]) =>
    (prompt: prompt, chars: chars, also: null);

class Cond {
  const Cond(this.name, this.make, {this.random = true});
  final String name;
  final bool random;

  /// 返回 null = 这个条目不适用(比如压根没有年份标签可改)。
  final Scn? Function(Ent e, Random r) make;
}

/// 一种判定方案:吃一张图(主提示词 + 角色槽),吐命中的条目 key。
class Variant {
  Variant(this.name, this.judge);
  final String name;
  final List<String> Function(Scn s) judge;
}

class Stat {
  int trials = 0, hit = 0, confused = 0, confusedReal = 0;
  final pairs = <String, int>{};
  double get recall => trials == 0 ? double.nan : hit / trials;
}

String pct(double v) => v.isNaN ? '—' : '${(v * 100).toStringAsFixed(1)}%';

// ── 随机改写 ───────────────────────────────────────────

T pick<T>(List<T> xs, Random r) => xs[r.nextInt(xs.length)];

List<String>? dropK(List<String> ps, int k, Random r) {
  if (k <= 0 || ps.length <= k) return null;
  final idx = List.generate(ps.length, (i) => i)..shuffle(r);
  final gone = idx.take(k).toSet();
  return [
    for (var i = 0; i < ps.length; i++)
      if (!gone.contains(i)) ps[i],
  ];
}

List<String>? replaceK(List<String> ps, int k, List<String> pool, Random r) {
  if (k <= 0 || ps.length <= k) return null;
  final own = tokenizeSet(joinP(ps));
  final idx = List.generate(ps.length, (i) => i)..shuffle(r);
  final out = [...ps];
  for (final i in idx.take(k)) {
    var t = pick(pool, r);
    for (var g = 0; g < 50 && own.contains(cleanPromptToken(t)); g++) {
      t = pick(pool, r);
    }
    out[i] = t;
  }
  return out;
}

List<String> insertK(List<String> ps, int k, List<String> pool, Random r) {
  final out = [...ps];
  for (var j = 0; j < k; j++) {
    out.insert(1 + r.nextInt(max(1, out.length - 1)), pick(pool, r));
  }
  return out;
}

List<String> adjSwap(List<String> ps, int k, Random r) {
  final out = [...ps];
  if (out.length < 2) return out;
  for (var j = 0; j < k; j++) {
    final i = r.nextInt(out.length - 1);
    final t = out[i];
    out[i] = out[i + 1];
    out[i + 1] = t;
  }
  return out;
}

List<String>? moveBlock(List<String> ps, int len, Random r) {
  if (ps.length <= len + 1) return null;
  final s = r.nextInt(ps.length - len);
  return [
    ...ps.sublist(0, s),
    ...ps.sublist(s + len),
    ...ps.sublist(s, s + len),
  ];
}

String weightWrap(String t, Random r) => switch (r.nextInt(5)) {
  0 => '{$t}',
  1 => '[$t]',
  2 => '{{$t}}',
  3 => '1.2::$t::',
  _ => '0.8::$t::',
};

List<String> weightPct(List<String> ps, double p, Random r) => [
  for (final t in ps) r.nextDouble() < p ? weightWrap(t, r) : t,
];

String joinEvery(List<String> ps, int every, String sep) {
  final b = StringBuffer();
  for (var i = 0; i < ps.length; i++) {
    if (i > 0) b.write(i % every == 0 ? sep : ', ');
    b.write(ps[i]);
  }
  return b.toString();
}

// ── 画师串专用 ─────────────────────────────────────────

/// NAI 专有的质量 / 美学 / 年份 / 控制词(Danbooru 词库里没有,得单列)。
final _naiExtraRe = RegExp(
  r'^(year ?\d{4}|masterpiece|best quality|amazing quality|great quality|'
  r'good quality|normal quality|bad quality|worst quality|very aesthetic|'
  r'aesthetic|very awa|incredibly absurdres|artist collaboration|no text|'
  r'newest|recent|old|early|mid|highly finished|ultra-detailed|'
  r'ultra detailed|detailed|4k|8k|hd|sfw|nsfw|location|'
  r'cinematic lighting|volumetric lighting|soft shadows)$',
);

bool isExtra(String piece) => _naiExtraRe.hasMatch(cleanPromptToken(piece));

/// 片段前面的权重 / 括号记号与核心分开,好只动核心。
final _headRe = RegExp(r'^([\s{\[]*(?:-?\d+(?:\.\d+)?::)?[\s{\[]*)(.*)$');

String unweight(String s) => s
    .replaceAll(RegExp(r'-?\d+(?:\.\d+)?::'), '')
    .replaceAll('::', '')
    .replaceAll(RegExp(r'[{}\[\]]'), '');

/// 服装与配饰:换装时会被整套换掉的那部分(发色、瞳色、耳朵尾巴这些身体特征不算)。
final _outfitRe = RegExp(
  r'\b(dress|skirt|shirt|blouse|jacket|coat|uniform|shorts|pants|trousers|'
  r'jeans|thighhighs|pantyhose|tights|socks|stockings|shoes|boots|heels|'
  r'sandals|slippers?|gloves|hat|cap|beret|hood|hoodie|sweater|cardigan|vest|'
  r'necktie|bowtie|scarf|cape|cloak|kimono|yukata|hanfu|bikini|swimsuit|'
  r'leotard|bodysuit|apron|sleeves?|collar|belt|choker|necklace|earrings?|'
  r'bracelet|glasses|mask|armor|frills?|lace|garter|sailor|blazer|overalls|'
  r'robe|gown|maid|headdress|crown|tiara|veil|ribbon|bow|hairband|headband|'
  r'hair ornament|hairclip|hairpin|bag|backpack|buttons?|zipper|straps?|bra|'
  r'panties|lingerie|cheongsam|serafuku|jersey|tank top|crop top|'
  r'bare shoulders|cuffs|footwear|legwear|clothes|clothing|outfit|costume)\b',
);

bool isOutfit(String piece) => _outfitRe.hasMatch(cleanPromptToken(piece));

final _artistPrefixRe = RegExp(r'artist:\s*', caseSensitive: false);
String stripArtistPrefix(String s) => s.replaceAll(_artistPrefixRe, '');

// ── 评测主体 ───────────────────────────────────────────

void main() {
  final dir = Platform.environment['MATCH_EVAL_DIR'];
  final skip = dir == null || !File('$dir/oc_data.json').existsSync();

  test('归类命中率评测', () async {
    TestWidgetsFlutterBinding.ensureInitialized(); // 离线词库从 asset 读
    final out = StringBuffer();
    void say(String s) {
      out.writeln(s);
      // ignore: avoid_print
      print(s);
    }

    Map<String, dynamic> readMap(String f) =>
        jsonDecode(File('$dir/$f').readAsStringSync()) as Map<String, dynamic>;

    final ocs = [
      for (final e in readMap('oc_data.json').entries)
        if (e.value is Map && ((e.value as Map)['tag_group'] ?? '') != '')
          Ent(e.key, '${(e.value as Map)['tag_group']}'),
    ];
    final arts = [
      for (final e in readMap('artist_strings.json').entries)
        if (e.value is Map && ((e.value as Map)['artist_string'] ?? '') != '')
          Ent(e.key, '${(e.value as Map)['artist_string']}'),
    ];
    final canon =
        (jsonDecode(File('$dir/nai_common.json').readAsStringSync()) as List)
            .cast<Map>();
    List<String> cat(String c) => [
      for (final it in canon)
        if (it['category'] == c && '${it['content'] ?? ''}'.trim().isNotEmpty)
          '${it['content']}'.trim(),
    ];
    final scenes = cat('场景类'),
        outfits = cat('服装类'),
        chars = cat('角色类'),
        styles = cat('风格类');
    const quality = [
      'masterpiece, best quality, very aesthetic, absurdres',
      'best quality, amazing quality, very aesthetic',
      'very aesthetic, masterpiece, no text',
      'year 2024, best quality',
    ];

    // 条目里每个词的帖子数:和 app 同一个来源(离线词库,建库时滤掉了 50 帖以下)
    final posts = await LocalTagDb().postCountsOf({
      for (final e in [...ocs, ...arts]) ...e.toks,
    });
    int postCount(String t) => posts[t] ?? 0;
    // 图里的画师:和 app 同一个来源(词库类目 + `artist:` 前缀)
    final tagIdx = TagIndex(await rootBundle.load(kTagIndexAsset));
    Set<String> artistsOf(Scn s) => {
      ...tagIdx.artistsIn(imageToks(s.prompt, s.chars)),
      ...taggedArtists(imageText(s.prompt, s.chars)),
    };

    // 词池:外观 / 服装词取自全体 OC 与服装法典,动作表情取自场景法典,
    // 画师取自全体画师串 —— 用真实用词做替换,别让随机串一眼就对不上。
    bool tagLike(String p) =>
        p.split(RegExp(r'\s+')).length <= 4 && !p.contains('.');
    final appearance = <String>{
      for (final e in ocs)
        for (final p in e.ps)
          if (tagLike(p)) unweight(p).trim(),
      for (final o in outfits)
        for (final p in pieces(o))
          if (tagLike(p)) unweight(p).trim(),
    }.where((p) => p.isNotEmpty).toList();
    final actions = <String>{
      for (final s in scenes)
        for (final p in pieces(s))
          if (tagLike(p)) unweight(p).trim(),
    }.where((p) => p.isNotEmpty).toList();
    final artistPool = <String>{
      for (final e in arts)
        for (final p in pieces(e.raw))
          if (!isExtra(p)) stripArtistPrefix(unweight(p)).trim(),
    }.where((p) => p.isNotEmpty).toList();

    Scn ctx(List<String> ps, Random r) => bare(
      '${pick(quality, r)}, 1girl, solo, ${joinP(ps)}, ${pick(scenes, r)}',
    );
    Scn? ctxOr(List<String>? ps, Random r) => ps == null ? null : ctx(ps, r);

    // ── OC 条件 ──
    final ocConds = <Cond>[
      Cond('原样粘贴', (e, r) => bare(e.raw), random: false),
      Cond('前后加质量词和场景', (e, r) => ctx(e.ps, r)),
      Cond(
        '放进角色槽',
        (e, r) =>
            bare('${pick(quality, r)}, ${pick(scenes, r)}', [joinP(e.ps)]),
      ),
      Cond('删 1 枚', (e, r) => ctxOr(dropK(e.ps, 1, r), r)),
      Cond('删 3 枚', (e, r) => ctxOr(dropK(e.ps, 3, r), r)),
      Cond(
        '删 30%',
        (e, r) => ctxOr(dropK(e.ps, (e.ps.length * .3).round(), r), r),
      ),
      Cond('换 1 枚', (e, r) => ctxOr(replaceK(e.ps, 1, appearance, r), r)),
      Cond('换 3 枚', (e, r) => ctxOr(replaceK(e.ps, 3, appearance, r), r)),
      Cond(
        '换 30%',
        (e, r) =>
            ctxOr(replaceK(e.ps, (e.ps.length * .3).round(), appearance, r), r),
      ),
      Cond('中间插 3 枚', (e, r) => ctx(insertK(e.ps, 3, actions, r), r)),
      Cond('换装:换 2 枚再接一段服装', (e, r) {
        final ps = replaceK(e.ps, 2, appearance, r);
        return ps == null ? null : ctx([...ps, pick(outfits, r)], r);
      }),
      Cond('整套换装:服装配饰全换', (e, r) {
        final kept = [
          for (final p in e.ps)
            if (!isOutfit(p)) p,
        ];
        if (kept.length == e.ps.length || kept.isEmpty) return null;
        return ctx([...kept, pick(outfits, r)], r);
      }),
      Cond('整套换装再挪动几枚', (e, r) {
        final kept = [
          for (final p in e.ps)
            if (!isOutfit(p)) p,
        ];
        if (kept.length == e.ps.length || kept.length < 5) return null;
        return ctx([...adjSwap(kept, 2, r), pick(outfits, r)], r);
      }),
      Cond('相邻交换 3 次', (e, r) => ctx(adjSwap(e.ps, 3, r), r)),
      Cond('挪 3 枚到末尾', (e, r) => ctxOr(moveBlock(e.ps, 3, r), r)),
      Cond('完全打乱', (e, r) => ctx([...e.ps]..shuffle(r), r)),
      Cond('三成标签加权重', (e, r) => ctx(weightPct(e.ps, .3, r), r)),
      Cond(
        '下划线↔空格',
        (e, r) => ctx([
          for (final p in e.ps)
            p.contains('_') ? p.replaceAll('_', ' ') : p.replaceAll(' ', '_'),
        ], r),
        random: false,
      ),
      Cond(
        '只换行不写逗号',
        (e, r) => bare(
          '${pick(quality, r)}\n${joinEvery(e.ps, 4, '\n')}\n${pick(scenes, r)}',
        ),
      ),
      Cond('全角逗号', (e, r) => bare(e.ps.join('，')), random: false),
      Cond('两个 OC 同框', (e, r) {
        var o = pick(ocs, r);
        while (o.key == e.key) {
          o = pick(ocs, r);
        }
        return (
          prompt: '${pick(quality, r)}, 2girls, ${joinP(e.ps)}, ${joinP(o.ps)}',
          chars: const [],
          also: o.key,
        );
      }),
      Cond('外观进角色槽、服装留主提示词', (e, r) {
        final h = e.ps.length ~/ 2;
        return bare('${pick(quality, r)}, ${joinP(e.ps.sublist(h))}', [
          joinP(e.ps.sublist(0, h)),
        ]);
      }),
      Cond('日常综合:换1删1插2加权重', (e, r) {
        final a = replaceK(e.ps, 1, appearance, r);
        final b = a == null ? null : dropK(a, 1, r);
        if (b == null) return null;
        return ctx(weightPct(insertK(b, 2, actions, r), .2, r), r);
      }),
    ];

    // OC 难负例:同一个 OC,但只剩「谁都可能有」的那部分外观 —— 这张图多半是
    // 另一个长得像的角色,归进来就是误判。通用度 = 该词出现在多少个 OC / 角色法典里。
    final docFreq = <String, int>{};
    for (final t in [
      for (final e in ocs) e.toks,
      for (final c in chars) tokenizeSet(c),
    ]) {
      for (final x in t) {
        docFreq[x] = (docFreq[x] ?? 0) + 1;
      }
    }
    final ocNegConds = <Cond>[
      Cond('只剩最通用的一半外观', (e, r) {
        final ranked = [...e.ps]
          ..sort(
            (a, b) => (docFreq[cleanPromptToken(b)] ?? 0).compareTo(
              docFreq[cleanPromptToken(a)] ?? 0,
            ),
          );
        final keep = ranked.take((e.ps.length / 2).ceil()).toSet();
        return ctx([
          for (final p in e.ps)
            if (keep.contains(p)) p,
        ], r);
      }),
      Cond('通用词全留,特有词全换成别的', (e, r) {
        // 特有 = 词库帖子数不到 5000(或词库里压根没有)。留下来的全是
        // 「长发、红瞳、微笑」这种谁都有的 —— 这是另一个长得像的角色。
        final generic = [
          for (final p in e.ps) postCount(cleanPromptToken(p)) >= 5000,
        ];
        if (!generic.contains(true) || !generic.contains(false)) return null;
        return ctx([
          for (var i = 0; i < e.ps.length; i++)
            generic[i] ? e.ps[i] : pick(appearance, r),
        ], r);
      }),
    ];

    Scn actx(String s, Random r) =>
        bare('$s, 1girl, ${pick(chars, r)}, ${pick(scenes, r)}');

    List<String> artistsPieces(Ent e) => [
      for (final p in e.ps)
        if (!isExtra(p)) p,
    ];
    List<String> others(Ent e, int k, Random r) {
      final own = tokenizeSet(e.raw);
      final out = <String>[];
      for (var g = 0; out.length < k && g < 500; g++) {
        final t = pick(artistPool, r);
        if (!own.contains(cleanPromptToken(t)) && !out.contains(t)) out.add(t);
      }
      return out;
    }

    // ── 画师串条件 ── 上下文里不放质量 / 年份词,免得碰巧把删掉的那枚补回来
    final artConds = <Cond>[
      Cond('原样粘贴', (e, r) => bare(e.raw), random: false),
      Cond('放开头,后接角色场景', (e, r) => actx(e.raw, r)),
      Cond(
        '放末尾',
        (e, r) =>
            bare('1girl, ${pick(chars, r)}, ${pick(scenes, r)}, ${e.raw}'),
      ),
      Cond('打乱顺序', (e, r) => actx(([...e.ps]..shuffle(r)).join(','), r)),
      Cond('改权重数值', (e, r) {
        final nums = RegExp(r'(\d+(?:\.\d+)?)::');
        if (nums.hasMatch(e.raw)) {
          return actx(
            e.raw.replaceAllMapped(
              nums,
              (_) => '${(.5 + r.nextDouble()).toStringAsFixed(2)}::',
            ),
            r,
          );
        }
        final i = r.nextInt(e.ps.length);
        return actx(([...e.ps]..[i] = weightWrap(e.ps[i], r)).join(','), r);
      }),
      Cond('去掉全部权重', (e, r) => actx(unweight(e.raw), r), random: false),
      Cond('删 1 个画师', (e, r) {
        final idx = [
          for (var i = 0; i < e.ps.length; i++)
            if (!isExtra(e.ps[i])) i,
        ];
        if (idx.length < 2) return null;
        final gone = pick(idx, r);
        return actx(
          [
            for (var i = 0; i < e.ps.length; i++)
              if (i != gone) e.ps[i],
          ].join(','),
          r,
        );
      }),
      Cond('删 1 个质量/年份词', (e, r) {
        final idx = [
          for (var i = 0; i < e.ps.length; i++)
            if (isExtra(e.ps[i])) i,
        ];
        if (idx.isEmpty) return null;
        final gone = pick(idx, r);
        return actx(
          [
            for (var i = 0; i < e.ps.length; i++)
              if (i != gone) e.ps[i],
          ].join(','),
          r,
        );
      }),
      Cond('加 1 个画师', (e, r) => actx('${e.raw}, ${pick(artistPool, r)}', r)),
      Cond(
        '加 2 个画师',
        (e, r) => actx([e.raw, ...others(e, 2, r)].join(', '), r),
      ),
      Cond('artist: 前缀增删', (e, r) {
        final has = e.raw.toLowerCase().contains('artist:');
        final s = has
            ? stripArtistPrefix(e.raw)
            : [
                for (final p in e.ps)
                  if (isExtra(p))
                    p
                  else
                    p.replaceFirstMapped(
                      _headRe,
                      (m) => '${m[1]}artist:${m[2]}',
                    ),
              ].join(',');
        return actx(s, r);
      }, random: false),
      Cond('artist: 后多一个空格', (e, r) {
        if (!e.raw.contains('artist:')) return null;
        return actx(e.raw.replaceAll('artist:', 'artist: '), r);
      }, random: false),
      Cond('括号写法 x(y) → x (y)', (e, r) {
        if (!RegExp(r'\w\(').hasMatch(e.raw)) return null;
        return actx(
          e.raw.replaceAllMapped(RegExp(r'(\w)\('), (m) => '${m[1]} ('),
          r,
        );
      }, random: false),
      Cond('年份改一年', (e, r) {
        final y = RegExp(r'year ?(\d{4})');
        if (!y.hasMatch(e.raw)) return null;
        return actx(
          e.raw.replaceAllMapped(y, (m) => 'year ${int.parse(m[1]!) + 1}'),
          r,
        );
      }, random: false),
      Cond('日常综合:改权重+打乱+删一个质量词', (e, r) {
        final s = e.raw.replaceAllMapped(
          RegExp(r'(\d+(?:\.\d+)?)::'),
          (_) => '${(.5 + r.nextDouble()).toStringAsFixed(2)}::',
        );
        final ps = pieces(s)..shuffle(r);
        final ex = [
          for (var i = 0; i < ps.length; i++)
            if (isExtra(ps[i])) i,
        ];
        if (ex.isNotEmpty) ps.removeAt(pick(ex, r));
        return actx(ps.join(','), r);
      }),
    ];

    // 画师串难负例:只用了这个串里一半的画师,另一半换成别人 —— 那是另一个组合。
    final artNegConds = <Cond>[
      Cond('整串夹在另一套组合里(再加同样多的画师)', (e, r) {
        final n = artistsPieces(e).length;
        if (n == 0) return null;
        return actx([e.raw, ...others(e, n, r)].join(', '), r);
      }),
      Cond('一半画师换成别人', (e, r) {
        final idx = [
          for (var i = 0; i < e.ps.length; i++)
            if (!isExtra(e.ps[i])) i,
        ]..shuffle(r);
        if (idx.length < 2) return null;
        final swap = idx.take(idx.length ~/ 2).toSet();
        return actx(
          [
            for (var i = 0; i < e.ps.length; i++)
              if (swap.contains(i)) pick(artistPool, r) else e.ps[i],
          ].join(','),
          r,
        );
      }),
    ];

    TagEntry te(TagCategory c, Ent e) =>
        TagEntry(id: e.key, category: c, name: e.key, positive: e.raw);
    final ocEntries = [for (final e in ocs) te(TagCategory.character, e)];
    final artEntries = [for (final e in arts) te(TagCategory.artist, e)];

    Variant ocAt(String name, double cover, [int minKeep = kOcMinKeep]) {
      final m = OcMatcher(
        ocEntries,
        postCount: postCount,
        cover: cover,
        minKeep: minKeep,
      );
      return Variant(
        name,
        (s) => [for (final h in m.match(imageToks(s.prompt, s.chars))) h.key],
      );
    }

    final ocVariants = [
      ocAt('现行', kOcMatchCover),
      for (final (c, k) in const [
        (.55, 4),
        (.65, 4),
        (.7, 4),
        (.75, 4),
        (.7, 5),
      ])
        if (c != kOcMatchCover || k != kOcMinKeep) ocAt('$c/$k', c, k),
    ];
    Variant styleAt(String name, double share, [List<TagEntry>? entries]) {
      final m = StyleMatcher(
        entries ?? artEntries,
        postCount: postCount,
        share: share,
      );
      return Variant(
        name,
        (s) => [
          for (final h in m.match(
            imageToks(s.prompt, s.chars),
            artists: artistsOf(s),
          ))
            h.key,
        ],
      );
    }

    final artVariants = [
      styleAt('现行', kStyleArtistShare),
      for (final x in const [0.0, .5, .67, .75])
        if (x != kStyleArtistShare) styleAt('占比$x', x),
    ];

    const trials = 6;

    /// 静态重复:拿条目自己的原文去跑,顺带命中的别的条目 —— 库里同一角色 /
    /// 同一组合的几个版本。算串味时把它们单列,那不是匹配规则能分开的。
    Map<String, Set<String>> staticDupes(List<Ent> ents, Variant v) => {
      for (final e in ents)
        e.key: {
          for (final h in v.judge(bare(e.raw)))
            if (h != e.key) h,
        },
    };

    void runSuite(
      String title,
      List<Ent> ents,
      List<Cond> conds,
      List<Variant> variants, {
      bool negative = false,
    }) {
      final dupes = {for (final v in variants) v.name: staticDupes(ents, v)};
      final stats = {
        for (final v in variants)
          v.name: {for (final c in conds) c.name: Stat()},
      };
      final na = {for (final c in conds) c.name: 0};
      final r = Random(20260915);
      for (final c in conds) {
        for (final e in ents) {
          for (var t = 0; t < (c.random ? trials : 1); t++) {
            final s = c.make(e, r);
            if (s == null) {
              if (t == 0) na[c.name] = na[c.name]! + 1;
              break;
            }
            for (final v in variants) {
              final hits = v.judge(s);
              final st = stats[v.name]![c.name]!;
              st.trials++;
              if (hits.contains(e.key)) st.hit++;
              final others = [
                for (final h in hits)
                  if (h != e.key && h != s.also) h,
              ];
              if (others.isNotEmpty) {
                st.confused++;
                final real = others.where(
                  (o) => !dupes[v.name]![e.key]!.contains(o),
                );
                if (real.isNotEmpty) {
                  st.confusedReal++;
                  for (final o in real) {
                    st.pairs['${e.key} → $o'] =
                        (st.pairs['${e.key} → $o'] ?? 0) + 1;
                  }
                }
              }
            }
          }
        }
      }

      say('\n## $title\n');
      if (negative) {
        say('这些图**不该**归进被改写的那个条目,表里数字越低越好。\n');
      }
      final head = negative ? '误归率' : '命中率';
      say(
        '| 条件 | ${[for (final v in variants) '$head · ${v.name}'].join(' | ')} | 不适用 |',
      );
      say('|---|${[for (final _ in variants) '---:'].join('|')}|---:|');
      for (final c in conds) {
        say(
          '| ${c.name} | '
          '${[for (final v in variants) pct(stats[v.name]![c.name]!.recall)].join(' | ')} | '
          '${na[c.name]} |',
        );
      }
      if (negative) return;

      say('\n串味率(命中了别的条目;括号里是剔掉库内重复版本之后):\n');
      say('| 方案 | 库内有重复版本的条目 | 全部条件平均串味 |');
      say('|---|---:|---:|');
      for (final v in variants) {
        var n = 0, cAll = 0, cReal = 0;
        for (final st in stats[v.name]!.values) {
          n += st.trials;
          cAll += st.confused;
          cReal += st.confusedReal;
        }
        final withDupes = dupes[v.name]!.values.where((d) => d.isNotEmpty);
        say(
          '| ${v.name} | ${withDupes.length} | '
          '${pct(cAll / n)}(${pct(cReal / n)}) |',
        );
      }
      final pairs = <String, int>{};
      for (final st in stats[variants.first.name]!.values) {
        st.pairs.forEach((k, v) => pairs[k] = (pairs[k] ?? 0) + v);
      }
      final top = pairs.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (top.isNotEmpty) {
        say('\n剔掉重复版本后仍串味最多的组合:');
        for (final p in top.take(6)) {
          say('- ${p.key}:${p.value} 次');
        }
      }
    }

    // 条目画像
    final lens = [for (final e in ocs) e.n]..sort();
    say('# 归类命中率评测\n');
    say(
      'OC 库 ${ocs.length} 个:标签数最少 ${lens.first},中位 '
      '${lens[lens.length ~/ 2]},最多 ${lens.last};自然语言型 '
      '${ocs.where((e) => e.prose).length} 个',
    );
    final alens = [for (final e in arts) e.n]..sort();
    say(
      '画师串库 ${arts.length} 个:标签数最少 ${alens.first},中位 '
      '${alens[alens.length ~/ 2]},最多 ${alens.last}',
    );
    final outfitShare = [
      for (final e in ocs) e.ps.where(isOutfit).length / e.ps.length,
    ]..sort();
    say(
      'OC 标签里服装配饰的占比:中位 ${pct(outfitShare[outfitShare.length ~/ 2])},'
      '超过 25% 的 ${outfitShare.where((x) => x > .25).length} 个',
    );
    say('随机条件每个条目跑 $trials 次,固定种子。');

    runSuite('OC 命中率', ocs, ocConds, ocVariants);
    runSuite('OC 难负例', ocs, ocNegConds, ocVariants, negative: true);

    // OC 按类型 / 长度拆开看几个关键条件
    say('\n### OC 按类型与长度拆分\n');
    final buckets = <String, bool Function(Ent)>{
      '标签型 ≤15 枚': (e) => !e.prose && e.n <= 15,
      '标签型 16–25 枚': (e) => !e.prose && e.n > 15 && e.n <= 25,
      '标签型 >25 枚': (e) => !e.prose && e.n > 25,
      '自然语言型': (e) => e.prose,
    };
    final keyConds = [
      ...ocConds.where(
        (c) => const ['整套换装:服装配饰全换', '日常综合:换1删1插2加权重'].contains(c.name),
      ),
      ...ocNegConds,
    ];
    say('| 分组 | 条目数 | ${[for (final c in keyConds) c.name].join(' | ')} |');
    say('|---|---:|${[for (final _ in keyConds) '---:'].join('|')}|');
    for (final b in buckets.entries) {
      final group = ocs.where(b.value).toList();
      if (group.isEmpty) continue;
      final cells = <String>[];
      for (final c in keyConds) {
        final r = Random(7);
        var n = 0, h = 0;
        for (final e in group) {
          for (var t = 0; t < trials; t++) {
            final s = c.make(e, r);
            if (s == null) break;
            n++;
            if (ocVariants.first.judge(s).contains(e.key)) h++;
          }
        }
        cells.add(n == 0 ? '—' : pct(h / n));
      }
      say('| ${b.key} | ${group.length} | ${cells.join(' | ')} |');
    }

    // ── OC 门槛扫描:只看几个关键指标,找命中与误归的平衡点 ──
    say('\n### OC 门槛扫描\n');
    final swapCond = ocConds.firstWhere((c) => c.name == '整套换装:服装配饰全换');
    final dailyCond = ocConds.firstWhere((c) => c.name == '日常综合:换1删1插2加权重');
    final rep30 = ocConds.firstWhere((c) => c.name == '换 30%');
    final lookalike = ocNegConds.firstWhere((c) => c.name.startsWith('通用词全留'));
    final genericHalf = ocNegConds.firstWhere(
      (c) => c.name.startsWith('只剩最通用'),
    );
    final charPrompts = [
      for (final c in chars) 'masterpiece, best quality, 1girl, solo, $c',
    ];
    say(
      '| 门槛 | 整套换装 | 换 30% | 日常综合 | 长得像的另一个(误归) | '
      '只剩通用一半(误归) | 角色法典误命中 |',
    );
    say('|---:|---:|---:|---:|---:|---:|---:|');
    for (final th in const [.5, .55, .6, .65, .7, .75, .8]) {
      final v = ocAt('$th', th);
      String rate(Cond c) {
        final r = Random(20260915);
        var n = 0, h = 0;
        for (final e in ocs) {
          for (var t = 0; t < trials; t++) {
            final s = c.make(e, r);
            if (s == null) break;
            n++;
            if (v.judge(s).contains(e.key)) h++;
          }
        }
        return pct(h / n);
      }

      final fp =
          charPrompts.where((p) => v.judge(bare(p)).isNotEmpty).length /
          charPrompts.length;
      say(
        '| $th${th == kOcMatchCover ? '(现行)' : ''} | ${rate(swapCond)} | '
        '${rate(rep30)} | ${rate(dailyCond)} | ${rate(lookalike)} | '
        '${rate(genericHalf)} | ${pct(fp)} |',
      );
    }

    runSuite('画师串命中率', arts, artConds, artVariants);
    runSuite('画师串难负例', arts, artNegConds, artVariants, negative: true);

    // 一两个画师的小画风:用户自己存的库里常见,公共画师串库里没有这种。
    final smallR = Random(31);
    final smalls = [
      for (var i = 0; i < 80; i++)
        Ent(
          'S$i',
          (List.of(artistPool)..shuffle(smallR)).take(1 + i % 2).join(', '),
        ),
    ];
    final smallEntries = [for (final e in smalls) te(TagCategory.artist, e)];
    final smallVariants = [
      styleAt('现行', kStyleArtistShare, smallEntries),
      for (final x in const [0.0, .5, .67, .75])
        if (x != kStyleArtistShare) styleAt('占比$x', x, smallEntries),
    ];
    runSuite('小画风(1–2 个画师)命中率', smalls, [
      Cond('放开头,后接角色场景', (e, r) => actx(e.raw, r)),
      Cond(
        '加 1 个画师',
        (e, r) => actx([e.raw, ...others(e, 1, r)].join(', '), r),
      ),
    ], smallVariants);
    runSuite(
      '小画风难负例',
      smalls,
      [
        Cond(
          '夹在另一套组合里(再加 3 个画师)',
          (e, r) => actx([e.raw, ...others(e, 3, r)].join(', '), r),
        ),
      ],
      smallVariants,
      negative: true,
    );

    // 误命中:拿法典里不含条目的提示词整句去跑
    say('\n## 误命中(法典提示词整句被归进了某个条目)\n');
    say('| 被测 | 提示词来源 | 条数 | 误命中率 | 最常误中的条目 |');
    say('|---|---|---:|---:|---|');
    void neg(String who, Variant v, String src, List<String> prompts) {
      var bad = 0;
      final by = <String, int>{};
      for (final p in prompts) {
        final hits = v.judge(bare(p));
        if (hits.isEmpty) continue;
        bad++;
        for (final h in hits) {
          by[h] = (by[h] ?? 0) + 1;
        }
      }
      final top = (by.entries.toList()..sort((a, b) => b.value - a.value))
          .take(4)
          .map((e) => '${e.key}×${e.value}')
          .join(', ');
      say(
        '| $who | $src | ${prompts.length} | '
        '${pct(prompts.isEmpty ? double.nan : bad / prompts.length)} | $top |',
      );
    }

    final r = Random(99);
    List<String> sample(List<String> xs, int k) =>
        xs.length <= k ? xs : ([...xs]..shuffle(r)).take(k).toList();
    neg('OC', ocVariants.first, '角色类法典', charPrompts);
    neg('OC', ocVariants.first, '服装类法典', [
      for (final c in sample(outfits, 900)) 'best quality, 1girl, solo, $c',
    ]);
    neg('画师串', artVariants.first, '风格类法典', [
      for (final c in styles) '$c, masterpiece, best quality, 1girl',
    ]);
    neg('画师串', artVariants.first, '场景类法典', [
      for (final c in sample(scenes, 900)) 'very aesthetic, 1girl, $c',
    ]);

    final to = Platform.environment['MATCH_EVAL_OUT'];
    if (to != null) File(to).writeAsStringSync(out.toString());
  }, skip: skip ? '未设 MATCH_EVAL_DIR,跳过评测' : false);
}

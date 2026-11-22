/// 两张图的元数据比对:提示词按标签对齐,生成参数逐项比,
/// NAI 原始 JSON 里没单列的字段按原键名补在参数后面。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../l10n/app_localizations.dart';
import '../editor/editor_models.dart' show parseToks;
import '../import/image_metadata.dart';

/// 一枚标签从 A 到 B 的变化。
enum TagChange { same, onlyA, onlyB, weight, moved }

class TagDiff {
  const TagDiff(this.change, this.text, {this.weightA, this.weightB});

  final TagChange change;

  /// 原文写法:[TagChange.onlyA] 取 A 的,其余取 B 的。
  final String text;

  /// [TagChange.weight] 两边的有效倍率。
  final double? weightA;
  final double? weightB;
}

bool tagsDiffer(List<TagDiff> d) => d.any((t) => t.change != TagChange.same);

class _Tag {
  const _Tag(this.key, this.raw, this.mult);

  final String key;
  final String raw;
  final double mult;
}

final _spaces = RegExp(r'\s+');

List<_Tag> _tagsOf(String text) => [
  for (final t in parseToks(text))
    if (t.name.trim().isNotEmpty)
      _Tag(
        t.name.replaceAll(_spaces, ' ').trim().toLowerCase(),
        text.substring(t.segStart, t.segEnd).trim(),
        t.effMult,
      ),
];

bool _sameWeight(double a, double b) => (a - b).abs() < 0.005;

/// A→B 的标签级差异:按名字取最长公共子序列对齐,对上的再比权重;
/// 两边都有、但没对上的按名字配对,算挪了位置。
List<TagDiff> diffTags(String a, String b) {
  final ta = _tagsOf(a), tb = _tagsOf(b);
  final n = ta.length, m = tb.length;
  final lcs = List.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = ta[i].key == tb[j].key
          ? lcs[i + 1][j + 1] + 1
          : math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  final ops = <(int?, int?)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (ta[i].key == tb[j].key) {
      ops.add((i++, j++));
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      ops.add((i++, null));
    } else {
      ops.add((null, j++));
    }
  }
  while (i < n) {
    ops.add((i++, null));
  }
  while (j < m) {
    ops.add((null, j++));
  }

  final looseA = <String, List<int>>{};
  for (final (ia, ib) in ops) {
    if (ia != null && ib == null) (looseA[ta[ia].key] ??= []).add(ia);
  }
  final movedFrom = <int, int>{}; // B 下标 → 配上的 A 下标
  for (final (ia, ib) in ops) {
    if (ia != null || ib == null) continue;
    final q = looseA[tb[ib].key];
    if (q != null && q.isNotEmpty) movedFrom[ib] = q.removeAt(0);
  }
  final pairedA = movedFrom.values.toSet();

  TagDiff matched(_Tag x, _Tag y, TagChange same) => _sameWeight(x.mult, y.mult)
      ? TagDiff(same, y.raw)
      : TagDiff(TagChange.weight, y.raw, weightA: x.mult, weightB: y.mult);

  final out = <TagDiff>[];
  for (final (ia, ib) in ops) {
    if (ia != null && ib != null) {
      out.add(matched(ta[ia], tb[ib], TagChange.same));
    } else if (ia != null) {
      if (!pairedA.contains(ia)) out.add(TagDiff(TagChange.onlyA, ta[ia].raw));
    } else if (movedFrom[ib] case final k?) {
      out.add(matched(ta[k], tb[ib!], TagChange.moved));
    } else {
      out.add(TagDiff(TagChange.onlyB, tb[ib!].raw));
    }
  }
  return out;
}

/// 一个角色(按下标对齐)的差异;只在一边有的角色,另一边为 null。
class CharDiff {
  const CharDiff({
    required this.index,
    required this.prompt,
    required this.uc,
    this.posA,
    this.posB,
  });

  final int index;
  final List<TagDiff> prompt;
  final List<TagDiff> uc;

  /// 坐标 `(x, y)`;没这个角色、或那张图没按坐标出(AI's Choice)为 null。
  final String? posA;
  final String? posB;

  bool get differs => tagsDiffer(prompt) || tagsDiffer(uc) || posA != posB;
}

String? _pos(CharacterMeta? c, bool? useCoords) {
  if (c == null || useCoords == false) return null;
  final x = c.centerX, y = c.centerY;
  if (x == null || y == null) return null;
  return '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

List<CharDiff> diffCharacters(ImageMetadata a, ImageMetadata b) => [
  for (var i = 0; i < math.max(a.characters.length, b.characters.length); i++)
    _charDiff(
      i,
      a.characters.elementAtOrNull(i),
      b.characters.elementAtOrNull(i),
      a.useCoords,
      b.useCoords,
    ),
];

CharDiff _charDiff(
  int i,
  CharacterMeta? ca,
  CharacterMeta? cb,
  bool? coordsA,
  bool? coordsB,
) => CharDiff(
  index: i,
  prompt: diffTags(ca?.prompt ?? '', cb?.prompt ?? ''),
  uc: diffTags(ca?.uc ?? '', cb?.uc ?? ''),
  posA: _pos(ca, coordsA),
  posB: _pos(cb, coordsB),
);

/// 参数表的一行;a / b 为 null = 那张图没有这项。
class ParamRow {
  const ParamRow(this.label, this.a, this.b, {this.rawKey = false});

  final String label;
  final String? a;
  final String? b;

  /// [label] 是 NAI 原始 JSON 的键名。
  final bool rawKey;

  bool get differs => a != b;
}

List<ParamRow> diffParams(
  ImageMetadata a,
  ImageMetadata b,
  AppLocalizations l,
) {
  String? yn(bool? v) => v == null ? null : (v ? l.yes : l.no);
  String? alpha(bool? straight) => straight == null
      ? null
      : (straight ? l.alphaStraight : l.alphaPremultiplied);
  String? autoPos(ImageMetadata m) =>
      m.characters.isEmpty || m.useCoords == null ? null : yn(!m.useCoords!);
  String? vibe(VibeMeta? v) {
    if (v == null) return null;
    final data = v.image ?? v.encoding;
    return [
      l.vibeStrengthLabel(_fmtNum(v.strength)),
      l.vibeExtractedLabel(_fmtNum(v.informationExtracted ?? 1)),
      if (data != null) '#${_hash(data)}',
    ].join('\n');
  }

  String? lora(ImageMetadata m) => m.loras.isEmpty
      ? null
      : m.loras.map((x) => '${x.name}:${_fmtNum(x.weight)}').join('\n');

  final rows = <ParamRow>[
    _modelRow(a, b, l),
    if (a.sourceType != b.sourceType)
      ParamRow(l.format, a.sourceType.name, b.sourceType.name),
    ParamRow(l.size, '${a.width}×${a.height}', '${b.width}×${b.height}'),
    ParamRow('Seed', _orNull(a.seed), _orNull(b.seed)),
    ParamRow('Steps', _numStr(a.steps), _numStr(b.steps)),
    ParamRow('CFG Scale', _numStr(a.scale), _numStr(b.scale)),
    ParamRow('Sampler', a.sampler, b.sampler),
    ParamRow('Noise Schedule', a.noiseSchedule, b.noiseSchedule),
    ParamRow('CFG Rescale', _numStr(a.cfgRescale), _numStr(b.cfgRescale)),
    ParamRow(l.varietyPlus, yn(a.varietyPlus), yn(b.varietyPlus)),
    ParamRow(l.aiChoicePosition, autoPos(a), autoPos(b)),
    ParamRow(
      l.transparentBg,
      yn(a.transparentBackground),
      yn(b.transparentBackground),
    ),
    ParamRow('Alpha', alpha(a.straightAlpha), alpha(b.straightAlpha)),
    for (var i = 0; i < math.max(a.vibes.length, b.vibes.length); i++)
      ParamRow(
        'Vibe ${i + 1}',
        vibe(a.vibes.elementAtOrNull(i)),
        vibe(b.vibes.elementAtOrNull(i)),
      ),
    ParamRow('LoRA', lora(a), lora(b)),
  ]..removeWhere((r) => r.a == null && r.b == null);
  return rows..addAll(_rawRows(a, b));
}

/// 模型:展示名一样、指纹不一样时(同版本不同权重)改报原串。
ParamRow _modelRow(ImageMetadata a, ImageMetadata b, AppLocalizations l) {
  String? rawSource(ImageMetadata m) =>
      m.raw is Map ? (m.raw as Map)['Source']?.toString() : null;
  final ra = rawSource(a), rb = rawSource(b);
  if (a.source == b.source && ra != null && rb != null && ra != rb) {
    return ParamRow(l.model, ra, rb);
  }
  return ParamRow(l.model, a.source, b.source);
}

String? _orNull(String s) => s.isEmpty ? null : s;

String? _numStr(String? s) {
  if (s == null) return null;
  final v = num.tryParse(s);
  return v == null ? s : _fmtNum(v);
}

/// 5.0 → 5,0.999 原样;JSON 里同一个数有时写整数有时写小数,统一了再比。
String _fmtNum(num v) {
  if (v is int) return '$v';
  if (v.isFinite && v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// 有效倍率的读数:两位小数、去尾零。
String fmtWeight(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// 短指纹(FNV-1a),长值只给开头时靠它区分。
String _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0').substring(0, 6);
}

/// 上面已单列、或每张图都不一样的字段(签名)。
const _handled = {
  'prompt',
  'uc',
  'characterPrompts',
  'seed',
  'steps',
  'scale',
  'sampler',
  'noise_schedule',
  'cfg_rescale',
  'width',
  'height',
  'skip_cfg_above_sigma',
  'tag_hint_transparent_background',
  'straight_alpha',
  'reference_image_multiple',
  'reference_strength_multiple',
  'reference_information_extracted_multiple',
  'signed_hash',
  'v4_prompt.caption',
  'v4_prompt.use_coords',
  'v4_negative_prompt.caption',
};

Map<String, dynamic>? _commentOf(ImageMetadata m) {
  final raw = m.raw;
  if (!m.isNovelAI || raw is! Map) return null;
  final c = raw['Comment'];
  try {
    if (c is String) return (jsonDecode(c) as Map).cast<String, dynamic>();
  } catch (_) {
    return null;
  }
  return c is Map ? c.cast<String, dynamic>() : null;
}

void _flatten(
  Map<dynamic, dynamic> map,
  String prefix,
  Map<String, Object?> out,
) {
  for (final MapEntry(:key, :value) in map.entries) {
    final path = '$prefix$key';
    if (_handled.contains(path)) continue;
    if (value is Map && value.isNotEmpty) {
      _flatten(value, '$path.', out);
    } else {
      out[path] = value;
    }
  }
}

String _show(Object? v) {
  if (v is num) return _fmtNum(v);
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= 64) return s;
  return '${s.substring(0, 28)}… #${_hash(s)}';
}

List<ParamRow> _rawRows(ImageMetadata a, ImageMetadata b) {
  final ca = _commentOf(a), cb = _commentOf(b);
  if (ca == null || cb == null) return const [];
  final fa = <String, Object?>{}, fb = <String, Object?>{};
  _flatten(ca, '', fa);
  _flatten(cb, '', fb);
  // extra_noise_seed 默认跟着 seed 走,两边都没单独设就不列,免得和 Seed 重复
  bool followsSeed(Map<String, dynamic> c) =>
      c['extra_noise_seed'] == null ||
      '${c['extra_noise_seed']}' == '${c['seed']}';
  if (followsSeed(ca) && followsSeed(cb)) {
    fa.remove('extra_noise_seed');
    fb.remove('extra_noise_seed');
  }
  return [
    for (final k in {...fa.keys, ...fb.keys})
      ParamRow(
        k,
        fa.containsKey(k) ? _show(fa[k]) : null,
        fb.containsKey(k) ? _show(fb[k]) : null,
        rawKey: true,
      ),
  ];
}

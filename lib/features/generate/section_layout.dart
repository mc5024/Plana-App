import 'dart:convert';
import 'dart:typed_data';

import '../../core/util/png_meta.dart' show withPngITxt;
import 'models.dart';
import 'prompt_sections.dart' show joinSections;

/// 主提示词分区随图保存:PNG 里另加一个 iTXt 块,官方的 Comment 与 alpha
/// 隐写都不动。只存进了载荷的那几格(见 [GenerateState.composedSections])。
const kSectionLayoutKey = 'plana:sections';

/// 把 [rows] 写进 PNG;没有分区、不是 PNG 或写失败原样返回。
Uint8List withSectionLayout(Uint8List png, List<PromptSection> rows) {
  if (rows.isEmpty) return png;
  try {
    return withPngITxt(png, kSectionLayoutKey, encodeSectionLayout(rows));
  } catch (_) {
    return png;
  }
}

String encodeSectionLayout(List<PromptSection> rows) => jsonEncode({
  'v': 1,
  'rows': [
    for (final r in rows)
      {
        'name': r.name,
        if (r.isMain) 'main': true,
        if (r.artist) 'artist': true,
        'p': r.positive,
        'n': r.negative,
      },
  ],
});

/// 读回的那几格(主体的词写在主体行里);格式不对返回 null。
List<PromptSection>? decodeSectionLayout(String? text) {
  if (text == null || text.isEmpty) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map || j['rows'] is! List) return null;
    final out = <PromptSection>[];
    var i = 0;
    for (final r in j['rows'] as List) {
      if (r is! Map) return null;
      final main = r['main'] == true;
      out.add(
        PromptSection(
          id: main ? kMainSectionId : 'img${i++}',
          name: (r['name'] ?? '').toString(),
          positive: (r['p'] ?? '').toString(),
          negative: (r['n'] ?? '').toString(),
          artist: r['artist'] == true,
        ),
      );
    }
    if (out.where((x) => x.isMain).length > 1) return null;
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

/// [rows] 拼出来是不是 [text](逗号两边的空白不计)。
bool sectionLayoutMatches(
  List<PromptSection> rows,
  String text, {
  required bool positive,
}) {
  final main = rows.where((x) => x.isMain).firstOrNull;
  final joined = joinSections(
    [for (final r in rows) r.isMain ? PromptSection.main(name: r.name) : r],
    main == null ? '' : (positive ? main.positive : main.negative),
    positive: positive,
  );
  return _norm(joined) == _norm(text);
}

String _norm(String s) => s
    .split(RegExp(r'[,，]'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .join(',');

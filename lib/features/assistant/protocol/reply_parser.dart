/// 模型回复怎么读:正文、思考类标签、```nai_draw 出图块,以及流到一半时气泡里该显示什么。
///
/// 出图块能无损修好的就地修(记进 [ParsedReply.repairs]);信息本身缺了、硬修只能编的,
/// 抛 [OutputFailure] 让模型重写。
library;

import 'dart:convert';

import '../../generate/char_position.dart' show formatFreeformPosition;
import '../domain/agent_event.dart' show AgentDelta;
import '../llm/llm_provider.dart' show LlmText;
import '../runtime/prompt_assets.dart';
import 'fenced_protocol.dart' show toolFence;

final _drawFence = RegExp(
  r'```[ \t]*nai_draw[ \t]*\r?\n(.*?)```',
  dotAll: true,
  caseSensitive: false,
);

/// 只认开标记:分清「没想出图」和「想写围栏但没写完」。
final _drawOpen = RegExp(r'```[ \t]*nai_draw[ \t]*\r?\n', caseSensitive: false);

/// 任意围栏。围栏名写错时扫全场,靠字段名认出哪个装着出图块。
final _anyFence = RegExp(
  r'```[ \t]*([A-Za-z0-9_-]*)[ \t]*\r?\n(.*?)```',
  dotAll: true,
);

/// 连内容一起从正文剥掉的成对标签。Think 与 thinking_process 是思考,流式时划到思考那边。
const _hiddenTags = 'Think|thinking_process|Reference_Example';
final _pairedTag = RegExp(
  '<\\s*($_hiddenTags)\\s*>.*?<\\s*/\\s*\\1\\s*>',
  dotAll: true,
  caseSensitive: false,
);
final _halfTag = RegExp(
  '<\\s*/?\\s*(?:$_hiddenTags)\\s*>',
  caseSensitive: false,
);

/// 出图块里该有的字段,认「写坏的围栏」用。
const _drawKeys = ['positive', 'negative', 'characters'];

/// 角色分区留下的字段。
const _charKeys = {'name', 'positive', 'negative', 'position'};

final _gridPos = RegExp(r'^\s*([A-Ea-e])\s*([1-5])\s*$');
final _xyPos = RegExp(r'^\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)\s*$');

class ParsedReply {
  const ParsedReply(this.reply, this.draw, [this.repairs = const []]);

  /// 给用户看的正文。
  final String reply;

  /// 出图块;null = 这轮不出图。
  final Map<String, dynamic>? draw;

  /// 就地修好的格式问题,记进调试记录。
  final List<String> repairs;
}

/// 回复读不出来,要模型重写。[instruction] 回灌给模型。
class OutputFailure implements Exception {
  const OutputFailure(this.instruction);

  final String instruction;

  @override
  String toString() => instruction;
}

/// 一条回复 → 正文 + 出图块。思考类标签和全部围栏(工具调用的也算)都从正文剥掉。
///
/// 出图块取**最后一个**非空的:模型偶尔先写一版再改一版,后写的是它的结论。
ParsedReply parseReply(String raw, PromptTexts texts) {
  final repairs = <String>[];
  var text = raw.replaceAll(_pairedTag, '').replaceAll(toolFence, '');
  Map<String, dynamic>? draw;
  final fences = _drawFence.allMatches(text).toList();
  if (fences.isNotEmpty) {
    final chosen = fences.reversed
        .where((m) => m[1]!.trim().isNotEmpty)
        .firstOrNull;
    if (chosen != null) draw = _decodeDraw(chosen[1]!.trim(), texts);
    text = text.replaceAll(_drawFence, '');
    if (fences.length > 1) {
      repairs.add('${fences.length} 个 nai_draw 围栏,取了最后一个非空的');
    }
  } else {
    (draw, text) = _salvage(text, texts, repairs);
  }
  return ParsedReply(
    text.replaceAll(_halfTag, '').trim(),
    draw == null ? null : checkDraw(draw, texts, repairs),
    repairs,
  );
}

Map<String, dynamic> _decodeDraw(String body, PromptTexts texts) {
  Object? v;
  try {
    v = jsonDecode(body);
  } on FormatException catch (e) {
    throw OutputFailure(texts.get('draw_bad_json', {'detail': e.message}));
  }
  if (v is Map<String, dynamic>) return v;
  throw OutputFailure(
    texts.get('draw_bad_json', {'detail': texts.get('draw_not_object')}),
  );
}

/// 没有完整的 ```nai_draw 围栏时的抢救。返回 (出图块或 null, 剔掉它之后的正文)。
///
/// 能无损修好的直接收下:围栏名写错(```json 里装着出图块)、漏了收尾的 ```、忘了写围栏
/// (正文里裸着一个出图对象)。开标记在、后面的 JSON 却不完整(多半被截断)的修不动。
(Map<String, dynamic>?, String) _salvage(
  String text,
  PromptTexts texts,
  List<String> repairs,
) {
  for (final m in _anyFence.allMatches(text)) {
    if (_asDraw(_tryDecode(m[2]!.trim())) case final draw?) {
      repairs.add('围栏名写成了 ```${m[1]!.isEmpty ? '(空)' : m[1]},已按出图块收下');
      return (draw, text.replaceRange(m.start, m.end, ''));
    }
  }

  final open = _drawOpen.firstMatch(text);
  if (open != null) {
    final start = text.indexOf('{', open.end);
    final obj = start < 0 ? null : _objectAt(text, start);
    final v = obj == null ? null : _tryDecode(obj);
    if (v == null) {
      throw OutputFailure(
        texts.get('draw_unfinished', {'detail': texts.get('draw_truncated')}),
      );
    }
    final draw = _asDraw(v);
    if (draw == null) {
      throw OutputFailure(
        texts.get('draw_unfinished', {'detail': texts.get('draw_no_payload')}),
      );
    }
    repairs.add('围栏漏了收尾的 ```,已按出图块收下');
    return (draw, text.substring(0, open.start));
  }

  // 一个个 { 试过去:NAI 的加权语法 {tag} 解不成 JSON,跳过它整段接着找
  for (var i = text.indexOf('{'); i >= 0; i = text.indexOf('{', i + 1)) {
    final obj = _objectAt(text, i);
    if (obj == null) continue;
    if (_asDraw(_tryDecode(obj)) case final draw?) {
      repairs.add('出图块没套围栏,已收下');
      return (draw, text.replaceRange(i, i + obj.length, ''));
    }
    // 解不出来的整段跳过:里面的角色分区单拎出来也像出图块
    i += obj.length - 1;
  }
  return (null, text);
}

Object? _tryDecode(String s) {
  try {
    return jsonDecode(s);
  } on FormatException {
    return null;
  }
}

/// 真能解析成对象、且带至少一个出图字段才算。只看字段名会误伤正文里讲 positive 是什么的回复。
Map<String, dynamic>? _asDraw(Object? v) =>
    v is Map<String, dynamic> && _drawKeys.any(v.containsKey) ? v : null;

/// 从 [start] 处的 `{` 起配平花括号(跳过字符串里的),取到配对的 `}`;配不平返回 null。
String? _objectAt(String s, int start) {
  var depth = 0;
  var inStr = false;
  var escape = false;
  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (inStr) {
      if (escape) {
        escape = false;
      } else if (ch == r'\') {
        escape = true;
      } else if (ch == '"') {
        inStr = false;
      }
    } else if (ch == '"') {
      inStr = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}' && --depth == 0) {
      return s.substring(start, i + 1);
    }
  }
  return null;
}

/// 出图块的结构校验。positive 缺了、角色分区没有 tag 这类修不动的让模型重写;
/// 数组忘了拼、单个对象忘了套数组、position 写歪这类就地修。
Map<String, dynamic> checkDraw(
  Map<String, dynamic> spec,
  PromptTexts texts,
  List<String> repairs,
) {
  final fixed = Map<String, dynamic>.of(spec);

  final pos = _tagString(spec['positive']);
  if (pos == null) {
    throw OutputFailure(
      spec.containsKey('positive')
          ? texts.get('draw_positive_type', {
              'type': _jsonType(spec['positive']),
            })
          : texts.get('draw_no_positive'),
    );
  }
  if (spec['positive'] is! String) {
    fixed['positive'] = pos;
    repairs.add('positive 写成了数组,已拼成字符串');
  }
  if (pos.trim().isEmpty) throw OutputFailure(texts.get('draw_positive_empty'));

  if (spec.containsKey('negative')) {
    final neg = _tagString(spec['negative']);
    if (neg == null) {
      fixed['negative'] = '';
      repairs.add('negative 类型不对,已置空');
    } else if (spec['negative'] is! String) {
      fixed['negative'] = neg;
      repairs.add('negative 写成了数组,已拼成字符串');
    }
  }

  var chars = spec['characters'];
  if (chars != null && chars is! List) {
    if (chars is Map<String, dynamic>) {
      chars = [chars];
      repairs.add('characters 是单个对象,已套成数组');
    } else if (chars is String && chars.trim().isNotEmpty) {
      // 光秃秃一个角色名:想分区却没给分区 tag,编不出来
      throw OutputFailure(
        texts.get('draw_characters_string', {'value': jsonEncode(chars)}),
      );
    } else {
      chars = const <Object?>[];
      repairs.add('characters 是 ${_jsonType(spec['characters'])},已按单角色处理');
    }
  }
  if (chars is List && chars.isNotEmpty) {
    final bad = [
      for (final c in chars)
        if (c is! Map<String, dynamic>) c,
    ];
    if (bad.isNotEmpty) {
      throw OutputFailure(
        texts.get('draw_characters_not_object', {
          'count': '${bad.length}',
          'sample': jsonEncode(bad.take(2).toList()),
        }),
      );
    }
    final cleaned = <Map<String, dynamic>>[];
    var extraKeys = false;
    for (final (i, c) in chars.cast<Map<String, dynamic>>().indexed) {
      final name = c['name']?.toString() ?? '';
      final cpos = _tagString(c['positive']);
      if (cpos == null || cpos.trim().isEmpty) {
        throw OutputFailure(
          texts.get('draw_character_no_positive', {
            'index': '${i + 1}',
            'name': jsonEncode(name),
          }),
        );
      }
      final item = <String, dynamic>{
        'name': name,
        'positive': cpos,
        'negative': _tagString(c['negative']) ?? '',
      };
      // 空串不写进去:没指定站位就别带这个字段
      final (xy, why) = _position(c['position']);
      if (xy.isNotEmpty) item['position'] = xy;
      if (why != null) repairs.add('characters[$i] 的 $why');
      if (c.keys.any((k) => !_charKeys.contains(k))) extraKeys = true;
      cleaned.add(item);
    }
    if (extraKeys) repairs.add('characters 里有多余字段,已剔除');
    chars = cleaned;
  }
  if (chars != null) fixed['characters'] = chars;
  return fixed;
}

/// tag 字段 → 字符串,数组拼成逗号分隔;别的类型返回 null。
String? _tagString(Object? v) => switch (v) {
  String() => v,
  List() => [
    for (final x in v)
      if (x != null && '$x'.trim().isNotEmpty) '$x'.trim(),
  ].join(', '),
  _ => null,
};

String _jsonType(Object? v) => switch (v) {
  null => 'null',
  bool() => 'boolean',
  num() => 'number',
  String() => 'string',
  List() => 'array',
  _ => 'object',
};

double? _num(Object? v) => switch (v) {
  num() => v.toDouble(),
  String() => double.tryParse(v.trim()),
  _ => null,
};

/// 站位 → (规整后的坐标串, 修了什么)。只认坐标串 "x,y" 和网格 id,同一格式的几种写歪法
/// 就地救回;认不出的给空串,交给下游自动排布。
(String, String?) _position(Object? v) {
  double? x, y;
  switch (v) {
    case null:
      return ('', null);
    case Map():
      x = _num(v['x']);
      y = _num(v['y']);
      if (x == null || y == null) return ('', 'position 是对象但取不出 x/y,已忽略');
    case List():
      if (v.length != 2) return ('', 'position 是 ${v.length} 个元素的数组,已忽略');
      x = _num(v[0]);
      y = _num(v[1]);
      if (x == null || y == null) return ('', 'position 数组里不是数字,已忽略');
    case String():
      if (v.trim().isEmpty) return ('', null);
      final g = _gridPos.firstMatch(v);
      if (g != null) {
        final norm = '${g[1]!.toUpperCase()}${g[2]}';
        return (norm, norm == v ? null : 'position $v 规整成了 $norm');
      }
      final m = _xyPos.firstMatch(v);
      if (m == null) return ('', 'position $v 不是坐标串,已忽略');
      x = double.parse(m[1]!);
      y = double.parse(m[2]!);
    default:
      return ('', 'position 是 ${_jsonType(v)},已忽略');
  }
  // 两个分量都落在 (1, 100] 且至少一个上到两位数:把 25% 写成了 25。
  // 不救的话夹边会把它压成 (1,1),几个角色静默堆到右下角
  final pct = x > 1 && x <= 100 && y > 1 && y <= 100 && (x >= 10 || y >= 10);
  final out = pct
      ? formatFreeformPosition(x / 100, y / 100)
      : formatFreeformPosition(x, y);
  return (out, pct ? 'position 按百分比读成了 $out' : null);
}

// 流到一半时切正文用的几把尺子(见 [streamView])。流中途的标签多半还没收尾,
// 得按「开标签之后全是它」算。
final _hiddenOpen = RegExp('<\\s*($_hiddenTags)\\s*>', caseSensitive: false);
final _hiddenClose = {
  for (final t in _hiddenTags.toLowerCase().split('|'))
    t: RegExp('<\\s*/\\s*$t\\s*>', caseSensitive: false),
};
final _liveFenceOpen = RegExp(
  r'```[ \t]*(?:tool_call|nai_draw)',
  caseSensitive: false,
);

/// 收到一半的标签 / 围栏头(`<Thi`、` ```na `):下一帧本来就会被认出来,少显示一帧不亏。
///
/// 反引号后面**必须跟着字母**才算:光秃秃的 ``` 多半是代码块的收尾、`…` 是行内代码的收尾。
final _liveTail = RegExp(r'(?:<[A-Za-z_/]{0,18}|`{1,3}[ \t]*[A-Za-z_]{1,9})$');

/// 流到一半的原文 → 气泡里该显示的两块。
///
/// 每帧拿全量原文重算:标签收尾那一刻正文会整段挪位。正文到第一个 ```tool_call /
/// ```nai_draw 围栏为止;普通的 ``` 代码块照留。思考类标签(含还没收尾的)划到思考那边,
/// Reference_Example 直接不显示。
({String body, String think}) streamView(String raw) {
  final think = <String>[];
  final body = StringBuffer();
  var pos = 0;
  while (pos < raw.length) {
    final open = _hiddenOpen.allMatches(raw, pos).firstOrNull;
    if (open == null) break;
    body.write(raw.substring(pos, open.start));
    final name = open[1]!.toLowerCase();
    final close = _hiddenClose[name]!.allMatches(raw, open.end).firstOrNull;
    if (name != 'reference_example') {
      think.add(raw.substring(open.end, close?.start ?? raw.length));
    }
    pos = close?.end ?? raw.length;
  }
  if (pos < raw.length) body.write(raw.substring(pos));
  var text = body.toString();
  final fence = _liveFenceOpen.firstMatch(text);
  if (fence != null) text = text.substring(0, fence.start);
  return (
    body: text.replaceFirst(_liveTail, '').trim(),
    think: think.join('\n').trim(),
  );
}

/// 模型这一刻的全量回复 → 气泡里实时显示的那一帧。
AgentDelta liveDeltaOf(LlmText c) {
  final v = streamView(c.text);
  return AgentDelta(
    text: v.body,
    reasoning: [
      c.reasoning.trim(),
      v.think,
    ].where((s) => s.isNotEmpty).join('\n'),
  );
}

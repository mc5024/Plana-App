/// OpenAI 兼容中转的出图格式:`POST …/v1/chat/completions`,NAI 参数写成
/// JSON 对象放进 user 消息,图以 `data:image/png;base64,…` 回在消息内容里。
///
/// 消息内容 = 官方参数原样(认不认由对面定)+ 这种格式自己的字段:
///  · `prompt`;`size` 是 `[宽, 高]`;
///  · `quality: false` / `uc_preset: "none"`:预设文本已并进提示词,不让对面再补;
///  · 多角色 `characters[{prompt, negative_prompt, position, center}]`,
///    `position` 是 `A1`..`E5` 格子,`center` 是原始坐标;
///  · 图生图 `i2i{image, strength, noise}`,重绘 `inpaint{image, mask, strength}`,
///    `model` 发底模;
///  · 角色参考 `character_references[{image, type, fidelity, strength}]`。
/// 搬进这些字段的图片不在官方参数里重复发,流式参数和预设开关也不带。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'nai_client.dart' show NaiException;

/// 官方请求体(`buildNaiPayload` 那份)→ chat 请求体。
///
/// 预设文本在拼载荷前已并进提示词,`quality` / `uc_preset` 恒关。
Map<String, dynamic> naiChatBody(Map<String, dynamic> body) {
  final p = body['parameters'] is Map
      ? (body['parameters'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};
  final action = body['action'];
  final chars = p['characterPrompts'];
  final refs = p['director_reference_images'];
  final payload = <String, dynamic>{
    for (final e in p.entries)
      if (!_notPassed.contains(e.key)) e.key: e.value,
    'prompt': body['input'],
    'negative_prompt': p['negative_prompt'] ?? '',
    'size': [p['width'], p['height']],
    'quality': false,
    'uc_preset': 'none',
    if (chars is List && chars.isNotEmpty) ...{
      'use_coords': p['use_coords'] == true,
      'characters': [
        for (final c in chars.whereType<Map>())
          {
            'prompt': c['prompt'],
            'negative_prompt': c['uc'] ?? '',
            'position': _gridCell(c['center']),
            'center': c['center'],
          },
      ],
    },
    if (action == 'img2img')
      'i2i': {
        'image': p['image'],
        'strength': p['strength'],
        'noise': p['noise'],
      },
    if (action == 'infill')
      'inpaint': {
        'image': p['image'],
        'mask': p['mask'],
        'strength': p['strength'],
      },
    if (refs is List && refs.isNotEmpty)
      'character_references': [
        for (var i = 0; i < refs.length; i++) _charRef(p, refs, i),
      ],
  };
  return {
    'model': _baseModel('${body['model']}'),
    'messages': [
      {'role': 'user', 'content': jsonEncode(payload)},
    ],
  };
}

/// 不随官方参数原样发的:已搬进专用字段的图片与尺寸、流式参数、预设开关。
const _notPassed = {
  'image',
  'mask',
  'strength',
  'noise',
  'width',
  'height',
  'director_reference_images',
  'director_reference_descriptions',
  'director_reference_information_extracted',
  'director_reference_strength_values',
  'director_reference_secondary_strength_values',
  'stream',
  'qualityToggle',
  'ucPreset',
};

Map<String, dynamic> _charRef(Map<String, dynamic> p, List refs, int i) {
  Object? at(String k) {
    final l = p[k];
    return l is List && i < l.length ? l[i] : null;
  }

  final desc = at('director_reference_descriptions');
  final caption = desc is Map && desc['caption'] is Map
      ? (desc['caption'] as Map)['base_caption']
      : null;
  final secondary = at('director_reference_secondary_strength_values');
  final strength = at('director_reference_strength_values');
  return {
    'image': refs[i],
    'type': caption is String ? caption : 'character&style',
    'fidelity': (1 - (secondary is num ? secondary : 0)).clamp(0, 1),
    'strength': strength is num ? strength : 1,
  };
}

/// 中心坐标 → 它落在的格子(同官方 floor 分桶)。
String _gridCell(Object? center) {
  int ix(Object? v) => v is num ? (5 * v).floor().clamp(0, 4) : 2;
  final c = center is Map ? center : const {};
  return '${'ABCDE'[ix(c['x'])]}${ix(c['y']) + 1}';
}

/// 中转只列底模,重绘模型它自己挑。
String _baseModel(String m) => m.endsWith('-inpainting')
    ? m.substring(0, m.length - '-inpainting'.length)
    : m;

final _dataImage = RegExp(r'data:image/\w+;base64,([A-Za-z0-9+/=]+)');

/// chat 响应 → 图片字节。内容里没有图时把那段文字当错误报出来。
Uint8List naiChatImage(String responseBody) {
  Object? content;
  try {
    final j = jsonDecode(responseBody);
    final choices = j is Map ? j['choices'] : null;
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final msg = first is Map ? first['message'] : null;
    content = msg is Map ? msg['content'] : null;
  } catch (_) {
    throw NaiException('接口返回的不是 JSON');
  }
  if (content is! String) throw NaiException('未收到图片数据');
  final m = _dataImage.firstMatch(content);
  if (m == null) {
    final text = content.trim();
    throw NaiException(text.isEmpty ? '未收到图片数据' : text);
  }
  return base64Decode(m.group(1)!);
}

/// 发给模型的固定文字,都在 `assets/prompts/` 下;读一次缓存住。
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

final _cache = <String, Future<String>>{};

/// `assets/prompts/[path]` 的全文(去掉首尾空白)。
Future<String> promptAsset(String path) => _cache[path] ??= rootBundle
    .loadString('assets/prompts/$path')
    .then((s) => s.trim());

/// 出图代码块的格式说明。
Future<String> outputFormatText() => promptAsset('output_format.md');

/// 工具调用的通用约定(各工具自己的说明不在这里)。
Future<String> toolLayerText() => promptAsset('tool_layer.md');

final _var = RegExp(r'\{(\w+)\}');

/// `assets/prompts/texts.yaml`:零碎的固定文字,按键取,`{名字}` 换成传进来的值。
class PromptTexts {
  const PromptTexts(this._map);

  final Map<String, String> _map;

  static Future<PromptTexts>? _loaded;

  static Future<PromptTexts> load() => _loaded ??= promptAsset(
    'texts.yaml',
  ).then((raw) => PromptTexts.parse(raw));

  /// YAML 文本 → 文字表。只认顶层的字符串值。
  factory PromptTexts.parse(String raw) {
    final doc = loadYaml(raw);
    return PromptTexts({
      if (doc is Map)
        for (final e in doc.entries)
          if (e.value is String) '${e.key}': (e.value as String).trim(),
    });
  }

  /// 没有这个键返回空串。没给值的 `{名字}` 原样留着。
  String get(String key, [Map<String, String> vars = const {}]) =>
      (_map[key] ?? '').replaceAllMapped(_var, (m) => vars[m[1]] ?? m[0]!);
}

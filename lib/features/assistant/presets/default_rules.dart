/// 默认规则(Nyako):包里内置的那份是唯一来源(`assets/prompts/nai45.json` / `nai5.json`)。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preset_rule.dart';
import 'rules_library.dart';

/// 默认规则:规则主体,连同 meta 里的名称、作者、版本。
class DefaultRules {
  const DefaultRules({
    required this.name,
    required this.author,
    required this.version,
    required this.rules,
  });

  final String name;
  final String author;

  /// `v4.5` / `v5` 这类,只拼进 [displayName]。
  final String version;
  final List<PresetRule> rules;

  /// 显示名:两份默认规则同名,带上版本(「Nyako v5」)才分得开。
  String get displayName => '$name $version'.trim();

  /// 内置 JSON → 默认规则。缺的 meta 用占位值补上,规则一段都没有返回 null。
  static DefaultRules? fromJson(Object? j, RulesFamily f) {
    if (j is! Map) return null;
    final rules = [
      if (j['rules'] is List)
        for (final e in j['rules'] as List) ?PresetRule.fromJson(e),
    ];
    if (rules.isEmpty) return null;
    String pick(Object? v, String fallback) =>
        '${v ?? ''}'.trim().isEmpty ? fallback : '$v'.trim();
    return DefaultRules(
      name: pick(j['name'], kDefaultRulesName),
      author: pick(j['author'], kDefaultRulesAuthor),
      version: pick(j['version'], defaultRulesVersionOf(f)),
      rules: rules,
    );
  }
}

final _cache = <RulesFamily, Future<DefaultRules>>{};

/// 包里内置的那份。读一次缓存住。
Future<DefaultRules> bundledDefaultRules(RulesFamily f) =>
    _cache[f] ??= () async {
      final raw = await rootBundle.loadString('assets/prompts/${f.name}.json');
      return DefaultRules.fromJson(jsonDecode(raw), f) ??
          DefaultRules(
            name: kDefaultRulesName,
            author: kDefaultRulesAuthor,
            version: defaultRulesVersionOf(f),
            rules: const [],
          );
    }();

/// 只要规则内容的简写。
Future<List<PresetRule>> bundledRules(RulesFamily f) async =>
    (await bundledDefaultRules(f)).rules;

/// 读出来之前的占位显示名。
String defaultRulesFallbackName(RulesFamily f) =>
    '$kDefaultRulesName ${defaultRulesVersionOf(f)}';

/// 规则预设页显示默认规则那两项用:名称、作者。
final defaultRulesProvider = FutureProvider.family<DefaultRules, RulesFamily>(
  (ref, f) => bundledDefaultRules(f),
);

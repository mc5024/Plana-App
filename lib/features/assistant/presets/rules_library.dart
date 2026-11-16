/// 规则预设库:导入过的预设,以及每个模型在用哪一份。
///
/// 每个模型各选一份:NAI4.5 和 NAI5 的写法差得多,一份预设可以只支持其中一个,
/// 也可以两个都支持。选默认规则就用包里内置的那份(见 default_rules.dart)。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../l10n/l10n.dart';
import 'preset_rule.dart';

const _key = 'assistant_rule_presets';

/// 上一版的存法(每个模型一份无名规则)。读到就迁成预设,见 [RulesLibraryNotifier.build]。
const _legacyKey = 'assistant_rules';

/// 一份规则预设。
class RulesPreset {
  const RulesPreset({
    required this.id,
    required this.name,
    required this.author,
    required this.models,
    required this.rules,
  });

  final String id;
  final String name;

  /// 空 = 没署名。
  final String author;

  /// 支持的模型。至少一个。
  final Set<RulesFamily> models;

  final List<PresetRule> rules;

  /// 默认规则那两项。老版本存过一个两边共用的 `default`,一并认。
  bool get isDefault => id.startsWith('default');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'models': [
      for (final m in RulesFamily.values)
        if (models.contains(m)) m.name,
    ],
    'rules': [for (final r in rules) r.toJson()],
  };

  static RulesPreset? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}'.trim();
    final name = '${j['name'] ?? ''}'.trim();
    final models = decodeModels(j['models']);
    final rules = [
      if (j['rules'] is List)
        for (final r in j['rules'] as List)
          if (PresetRule.fromJson(r) case final rule?)
            if (rule.name != kToolLayerName) rule,
    ];
    if (id.isEmpty || id.startsWith('default') || name.isEmpty) return null;
    // 一段都没有的也收:新建的预设从空的开始
    if (models.isEmpty) return null;
    return RulesPreset(
      id: id,
      name: name,
      author: '${j['author'] ?? ''}'.trim(),
      models: models,
      rules: rules,
    );
  }
}

/// 默认规则:每个模型一份,**不存规则内容** —— 内容在包里(见 default_rules.dart)。
/// 名称、作者、版本以内置那份的 meta 为准,这里的几个值只是占位。
RulesPreset defaultPresetOf(RulesFamily f) => RulesPreset(
  id: 'default-${f.name}',
  name: kDefaultRulesName,
  author: kDefaultRulesAuthor,
  models: {f},
  rules: const [],
);

const kDefaultRulesName = 'Nyako';
const kDefaultRulesAuthor = '夏夜浮梦';
String defaultRulesVersionOf(RulesFamily f) =>
    f == RulesFamily.nai5 ? 'v5' : 'v4.5';

class RulesLibrary {
  const RulesLibrary({this.presets = const [], this.active = const {}});

  /// 导入过的预设,按导入先后。**不含**默认规则那一项。
  final List<RulesPreset> presets;

  /// 模型 → 在用的预设 id。没有这一项 = 用默认规则。
  final Map<RulesFamily, String> active;

  /// 列表里展示的全部:两份默认规则排在最前。
  List<RulesPreset> get all => [
    for (final f in RulesFamily.values) defaultPresetOf(f),
    ...presets,
  ];

  /// 这个模型在用的那一份。选的预设被删了、或者它不支持这个模型,都回落默认。
  RulesPreset activeFor(RulesFamily f) {
    final id = active[f];
    if (id == null) return defaultPresetOf(f);
    for (final p in presets) {
      if (p.id == id && p.models.contains(f)) return p;
    }
    return defaultPresetOf(f);
  }

  /// 副本的名字:「原名 (副本)」,重名再往后加数字。
  String copyNameOf(String base) {
    final taken = {for (final p in presets) p.name};
    final first = '$base ${l10nNow.copySuffix}';
    var name = first;
    for (var n = 2; taken.contains(name); n++) {
      name = '$first $n';
    }
    return name;
  }

  /// 这个模型自定义过的规则;用默认规则时是 null。
  List<PresetRule>? customRulesFor(RulesFamily f) {
    final p = activeFor(f);
    return p.isDefault ? null : p.rules;
  }

  Map<String, dynamic> toJson() => {
    'presets': [for (final p in presets) p.toJson()],
    'active': {for (final e in active.entries) e.key.name: e.value},
  };

  static RulesLibrary fromJson(Object? j) {
    if (j is! Map) return const RulesLibrary();
    final presets = [
      if (j['presets'] is List)
        for (final p in j['presets'] as List) ?RulesPreset.fromJson(p),
    ];
    final active = <RulesFamily, String>{};
    if (j['active'] is Map) {
      (j['active'] as Map).forEach((k, v) {
        final f = RulesFamily.values.where((f) => f.name == '$k').firstOrNull;
        if (f != null && '$v'.isNotEmpty) active[f] = '$v';
      });
    }
    return RulesLibrary(presets: presets, active: active);
  }
}

final rulesLibraryProvider =
    AsyncNotifierProvider<RulesLibraryNotifier, RulesLibrary>(
      RulesLibraryNotifier.new,
    );

class RulesLibraryNotifier extends AsyncNotifier<RulesLibrary> {
  var _idSeq = 0;

  @override
  Future<RulesLibrary> build() async {
    final prefs = ref.read(prefsStoreProvider);
    try {
      final raw = await prefs.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        return RulesLibrary.fromJson(jsonDecode(raw));
      }
      // 上一版每个模型存一份无名规则:迁成「导入的 NAI 5 规则」这样的预设,并且照旧在用
      final legacy = await prefs.read(key: _legacyKey);
      if (legacy == null || legacy.isEmpty) return const RulesLibrary();
      final j = jsonDecode(legacy);
      final presets = <RulesPreset>[];
      final active = <RulesFamily, String>{};
      for (final f in RulesFamily.values) {
        final rules = [
          if (j is Map && j[f.name] is List)
            for (final r in j[f.name] as List) ?PresetRule.fromJson(r),
        ];
        if (rules.isEmpty) continue;
        final id = 'legacy-${f.name}';
        presets.add(
          RulesPreset(
            id: id,
            name: '导入的 ${rulesFamilyLabel(f)} 规则',
            author: '',
            models: {f},
            rules: rules,
          ),
        );
        active[f] = id;
      }
      final lib = RulesLibrary(presets: presets, active: active);
      await _write(lib);
      await prefs.delete(key: _legacyKey);
      return lib;
    } catch (_) {
      // 读坏了当没导入过:最坏是回到默认规则,不该让助手整个用不了
      return const RulesLibrary();
    }
  }

  RulesLibrary get _lib => state.value ?? const RulesLibrary();

  /// 加一份预设,返回它的 id。
  Future<String> add({
    required String name,
    required String author,
    required Set<RulesFamily> models,
    required List<PresetRule> rules,
  }) async {
    final id = 'r${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';
    await _save(
      RulesLibrary(
        presets: [
          ..._lib.presets,
          RulesPreset(
            id: id,
            name: name,
            author: author,
            models: Set.unmodifiable(models),
            rules: List.unmodifiable(rules),
          ),
        ],
        active: _lib.active,
      ),
    );
    return id;
  }

  /// 改一份预设(规则页的全文编辑)。id 不变,在用它的模型照旧用它;
  /// 改完不再支持的模型回到默认规则。
  Future<void> replace(
    String id, {
    required String name,
    required String author,
    required Set<RulesFamily> models,
    required List<PresetRule> rules,
  }) => _save(
    RulesLibrary(
      presets: [
        for (final p in _lib.presets)
          p.id == id
              ? RulesPreset(
                  id: id,
                  name: name,
                  author: author,
                  models: Set.unmodifiable(models),
                  rules: List.unmodifiable(rules),
                )
              : p,
      ],
      active: {..._lib.active}
        ..removeWhere((f, v) => v == id && !models.contains(f)),
    ),
  );

  /// 删一份预设。正在用它的模型回落默认规则。
  Future<void> remove(String id) => _save(
    RulesLibrary(
      presets: [
        for (final p in _lib.presets)
          if (p.id != id) p,
      ],
      active: {..._lib.active}..removeWhere((_, v) => v == id),
    ),
  );

  /// 让 [f] 用 [id] 这份。传默认规则的 id 就是回到默认。
  Future<void> use(RulesFamily f, String id) => _save(
    RulesLibrary(
      presets: _lib.presets,
      active: id.startsWith('default')
          ? ({..._lib.active}..remove(f))
          : {..._lib.active, f: id},
    ),
  );

  Future<void> _save(RulesLibrary next) async {
    state = AsyncData(next);
    await _write(next);
  }

  Future<void> _write(RulesLibrary lib) => ref
      .read(prefsStoreProvider)
      .write(key: _key, value: jsonEncode(lib.toJson()));
}

/// AI 助手的**规则预设**:预设中间那一整段规则(role → output_specification),
/// 加上名字、作者、支持哪些模型。
///
/// 预设 = 外壳 + 规则主体。外壳(开头清空上下文、任务开始那套框架,结尾的思考格式)
/// 留在服务端;规则主体可以由 app 自带:
///   · 走服务端渠道 —— 随请求发过去,服务端套上外壳,把自己那段换成这份
///   · 走自定义接口 —— 直接拿它当系统提示,不套外壳
/// 两条链路用同一份。选的是**默认规则**就什么都不发,服务端用它自己那份(永远是
/// 最新的),自定义接口从服务端取默认那份。
///
/// 每个模型各选一份在用:NAI4.5 和 NAI5 的写法差得多,一份预设可以只支持其中一个,
/// 也可以两个都支持(那就是同一份规则两边共用)。
///
/// **预设只讲怎么写提示词,不讲工具。** 怎么调工具、系统塞进来的数据块怎么读,是
/// app 自己的**工具层**(`assets/prompts/tool_layer.md`),发出去之前挂到在用的预设
/// 上([withToolLayer])。原先这段长在预设里,用户自己写的预设不照抄就调不了工具。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_config.dart';
import '../../core/store/app_stores.dart';
import '../../l10n/l10n.dart';

const _key = 'assistant_rule_presets';

/// 上一版的存法(每个模型一份无名规则)。读到就迁成预设,见 [RulesLibraryNotifier.build]。
const _legacyKey = 'assistant_rules';

/// 与服务端 `schemas.PRESET_RULES_MAX_*` 一致。导入时就卡住,别等发出去才被拒。
const kRulesMaxSections = 40;
const kRulesMaxChars = 60000;

/// 工具层那一段的段名。预设里有同名段一律当旧货丢掉 —— 工具层只认 app 自带的那份,
/// 两份一起发,模型会看到两套可能对不上的调用说明。
const kToolLayerName = 'tool_usage';

/// 导入时给工具层留的余量:发出去的是「预设 + 工具层」,整份还得在服务端上限里。
const _toolLayerReserveChars = 6000;

enum RulesFamily { nai45, nai5 }

String rulesFamilyLabel(RulesFamily f) => switch (f) {
  RulesFamily.nai45 => 'NAI 4.5',
  RulesFamily.nai5 => 'NAI 5',
};

/// 图片模型档位(`agentImageModel` 的产物) → 用哪一份规则。
/// 与服务端 `base_preset_and_backend` 同一个分法:`nai_v5` 开头的是 5,其余回落 4.5。
RulesFamily rulesFamilyOf(String imageModel) =>
    imageModel.startsWith('nai_v5') ? RulesFamily.nai5 : RulesFamily.nai45;

/// 取默认规则时发给服务端的图片模型档位。
String _imageModelOf(RulesFamily f) =>
    f == RulesFamily.nai5 ? 'nai_v5_full' : 'nai_v45_full';

/// 开头的空行(含只有空白的行)。
final _leadingBlankLines = RegExp(r'^(?:[ \t]*\r?\n)+');

class PresetRule {
  const PresetRule({required this.name, required this.content, this.when = ''});

  /// 段名,与服务端预设 yaml 的 name 同义。
  final String name;
  final String content;

  /// 条件段的模式名(如 `comic`),空 = 常驻。
  final String when;

  Map<String, dynamic> toJson() => {
    'name': name,
    'content': content,
    if (when.isNotEmpty) 'when': when,
  };

  static PresetRule? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = '${j['name'] ?? ''}'.trim();
    // 只去掉首尾的空行和行尾空白,**不动第一行的缩进** —— trim() 会把它一起吃掉,
    // 导出去再导回来就不是原样了。YAML 的 `|` 块还会在末尾补一个换行,也在这儿去掉。
    final content = '${j['content'] ?? ''}'
        .replaceFirst(_leadingBlankLines, '')
        .trimRight();
    if (name.isEmpty || content.isEmpty) return null;
    return PresetRule(
      name: name,
      content: content,
      when: '${j['when'] ?? ''}'.trim(),
    );
  }
}

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
    if (models.isEmpty || rules.isEmpty) return null;
    return RulesPreset(
      id: id,
      name: name,
      author: '${j['author'] ?? ''}'.trim(),
      models: models,
      rules: rules,
    );
  }
}

/// 默认规则:每个模型一份,**不存规则内容** —— 内容在服务端,选它就是「什么都不发」。
///
/// 名称、作者、版本以服务端预设顶层 meta 里写的为准(见 [defaultRulesProvider]),
/// 这里的几个值只在还没取到时占位。
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

/// `['nai45', 'nai5']` 这类写法 → 模型集合,认不出的忽略。
Set<RulesFamily> decodeModels(Object? raw) {
  final names = switch (raw) {
    final List l => [for (final e in l) '$e'.trim()],
    final String s => s.split(RegExp(r'[,\s]+')),
    _ => const <String>[],
  };
  return {
    for (final n in names)
      ?RulesFamily.values.where((f) => f.name == n).firstOrNull,
  };
}

/// 模式段的 when 前缀:`mode:comic`、`mode:natural` 这类是**用户手动选的模式**
/// (输入框上方的模式开关,见 assistant_mode.dart),与服务端 `prompts.MODE_WHEN_PREFIX` 一致。
const kModeWhenPrefix = 'mode:';

/// when 前面加 `!` = 没命中才发,给「某个模式下要换掉的段」用(与服务端
/// `prompts.WHEN_NOT_PREFIX` 一致)。默认规则里混合写法的 prompt_construction 写
/// `!mode:natural`,选了仅自然语言就换成 natural_construction。
const kWhenNotPrefix = '!';

/// 按本轮模式挑段,拼成一整块。与服务端 `prompts.when_wanted` 同一条规则:
///   · 不带条件的永远留;
///   · 模式段(`mode:` 开头)只在用户选了那个模式时留([chosen]);
///   · 其余条件段(`comic` 这类)判到了才留([modes] 或 [chosen] 里有);
///   · `!` 开头的反过来,没命中才留。
///
/// [modes] 是预匹配顺带判回来的;null = **判不出来**(预匹配那一步失败了)→ 其余条件段
/// 全发。多发一段的代价是几千字,漏发的代价是用户要的漫画画成一张普通图 —— 与服务端
/// 同一个取舍方向。模式段不跟着全发:它写的是用户现在选了什么,没选就不该出现。
String renderRules(
  List<PresetRule> rules,
  List<String>? modes, {
  List<String> chosen = const [],
}) => [
  for (final r in rules)
    if (_whenWanted(r.when, modes, chosen)) r.content,
].join('\n\n');

bool _whenWanted(String when, List<String>? modes, List<String> chosen) {
  if (when.isEmpty) return true;
  if (when.startsWith(kWhenNotPrefix)) {
    final key = when.substring(kWhenNotPrefix.length).trim();
    return !chosen.contains(key) && !(modes?.contains(key) ?? false);
  }
  if (chosen.contains(when)) return true;
  if (when.startsWith(kModeWhenPrefix)) return false;
  return modes == null || modes.contains(when);
}

/// 超限时的提示,没超限返回 null。[reserveChars] 是给之后挂上去的工具层留的。
String? rulesLimitError(List<PresetRule> rules, {int reserveChars = 0}) {
  if (rules.length + (reserveChars > 0 ? 1 : 0) > kRulesMaxSections) {
    return l10nNow.rulesTooManySections(
      kRulesMaxSections - (reserveChars > 0 ? 1 : 0),
    );
  }
  final total = rules.fold<int>(
    0,
    (n, r) => n + r.name.length + r.content.length,
  );
  final cap = kRulesMaxChars - reserveChars;
  if (total > cap) return l10nNow.rulesTooLong(cap);
  return null;
}

/// 把 app 的工具层挂到一份预设上。
///
/// 预设里原有的同名段先丢掉(老版本导入的预设里可能还带着服务端那份);工具层放在
/// `role` 后面 —— 默认规则原本就是这个顺序,自定义接口那条发出去和以前逐字一样;
/// 没有 `role` 段的预设接在最后,别把工具说明顶到人设前面。
List<PresetRule> withToolLayer(List<PresetRule> rules, String toolLayer) {
  final body = [
    for (final r in rules)
      if (r.name != kToolLayerName) r,
  ];
  if (toolLayer.trim().isEmpty) return body;
  final layer = PresetRule(name: kToolLayerName, content: toolLayer.trim());
  final i = body.indexWhere((r) => r.name == 'role');
  // 别写成 `i < 0 ? [...] : [...]..insert(...)`:级联 `..` 的优先级比三元低,
  // 会作用在整个三元的结果上,没有 role 时工具层被插两遍
  if (i < 0) return [...body, layer];
  return [...body]..insert(i + 1, layer);
}

String? _toolLayerCache;
String? _outputFormatCache;

/// app 自带的工具层:怎么调工具、系统塞进来的数据块怎么读。
Future<String> appToolLayer() async => _toolLayerCache ??=
    (await rootBundle.loadString('assets/prompts/tool_layer.md')).trim();

/// 出图代码块的格式。**只给自定义接口那条用** —— 服务端那条由后端代码自己发一份
/// 同样的说明;自定义接口没有后端外壳,预设里又不再讲这个,不补上模型写不出能解析的块。
Future<String> appOutputFormat() async => _outputFormatCache ??=
    (await rootBundle.loadString('assets/prompts/output_format.md')).trim();

// ---- 规则文件 ----
//
// 用 YAML,而且段落写法与服务端预设文件一致(name / when / content: |)。你改服务端
// 预设用的就是这种写法,两边的段可以直接互相复制;导入时也认一整份服务端预设文件,
// 只取其中 group: rules 那段。

const _fileFormat = 'plana-rules';

/// 读出来的规则文件。名字、作者、模型文件里可能没写(比如一整份服务端预设),
/// 由导入界面让用户补上。
class RulesFile {
  const RulesFile({
    required this.name,
    required this.author,
    required this.models,
    required this.rules,
  });

  final String name;
  final String author;
  final Set<RulesFamily> models;
  final List<PresetRule> rules;
}

/// 预设 → 文件文本。
String encodeRulesFile({
  required String name,
  required String author,
  required Set<RulesFamily> models,
  required List<PresetRule> rules,
}) {
  final b = StringBuffer()
    ..writeln(l10nNow.rulesHeader1)
    ..writeln(l10nNow.rulesHeader2)
    ..writeln(l10nNow.rulesHeader3)
    ..writeln(l10nNow.rulesHeader4)
    ..writeln('format: $_fileFormat')
    ..writeln('version: 2')
    // 名字、作者用 JSON 字符串写:JSON 的双引号串本身就是合法 YAML,
    // 里面带冒号、井号也不会被读歪
    ..writeln('name: ${jsonEncode(name)}')
    ..writeln('author: ${jsonEncode(author)}')
    ..writeln(
      'models: [${[for (final m in RulesFamily.values)
        if (models.contains(m)) m.name].join(', ')}]',
    )
    ..writeln('sections:');
  for (final r in rules) {
    b.writeln('  - name: ${jsonEncode(r.name)}');
    if (r.when.isNotEmpty) b.writeln('    when: ${jsonEncode(r.when)}');
    final lines = r.content.split('\n');
    // 第一行以空格开头时必须写缩进指示符,否则 YAML 会把那几个空格当成缩进吃掉
    final firstIndented = lines
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .startsWith(RegExp(r'\s'));
    b.writeln('    content: |${firstIndented ? '2' : ''}');
    for (final l in lines) {
      b.writeln(l.isEmpty ? '' : '      $l');
    }
  }
  return b.toString();
}

/// 文件文本 → 规则文件。认三种:本 app 导出的预设(v2)、上一版导出的无名规则
/// (v1,只有一个 `model`),以及一整份服务端预设。
///
/// [fileName] 用来补缺:文件里没写名字就用文件名;服务端预设文件名里带着
/// `nai5` / `nai45`,顺手认出支持的模型。
RulesFile decodeRulesFile(String text, {String fileName = ''}) {
  final Object? doc;
  try {
    doc = loadYaml(text);
  } on YamlException catch (e) {
    // 带上行号:全文编辑里改坏了,几万字的规则光说一句「格式不对」没法找
    final line = e.span?.start.line;
    throw FormatException(
      line == null
          ? l10nNow.badFileFormat(e.message)
          : l10nNow.badFileFormatLine(line + 1, e.message),
    );
  }
  if (doc is! Map) throw FormatException(l10nNow.noSections);

  final sections = doc['sections'];
  if (sections is! List) throw FormatException(l10nNow.noSections);

  // 带 group 字段的是一整份服务端预设:只取规则主体那段,外壳不要
  final isServerPreset = sections.any(
    (s) => s is Map && s.containsKey('group'),
  );
  final rules = <PresetRule>[];
  for (final s in sections) {
    if (s is! Map) continue;
    if (isServerPreset && '${s['group'] ?? ''}'.trim() != 'rules') continue;
    // 工具层 app 自带:服务端预设里标了 layer: tools 的、以及老文件里同名的那段都不要
    if ('${s['layer'] ?? ''}'.trim() == 'tools') continue;
    final rule = PresetRule.fromJson(s);
    if (rule == null || rule.name == kToolLayerName) continue;
    rules.add(rule);
  }
  if (rules.isEmpty) throw FormatException(l10nNow.noUsableRules);
  final err = rulesLimitError(rules, reserveChars: _toolLayerReserveChars);
  if (err != null) throw FormatException(err);

  final base = fileName.replaceFirst(RegExp(r'\.[^.]*$'), '').trim();
  var models = decodeModels(doc['models']);
  if (models.isEmpty) models = decodeModels(doc['model']); // v1
  if (models.isEmpty && isServerPreset) {
    // prompts_nai5.yaml / prompts_nai45.yaml 这类:按文件名认
    final m = RegExp(r'nai(45|5)(?![0-9])').firstMatch(base.toLowerCase());
    if (m != null) models = decodeModels('nai${m.group(1)}');
  }
  return RulesFile(
    name: '${doc['name'] ?? ''}'.trim().isNotEmpty
        ? '${doc['name']}'.trim()
        : base,
    author: '${doc['author'] ?? ''}'.trim(),
    models: models,
    rules: rules,
  );
}

// ---- 存储 ----

/// 规则预设库:导入过的预设,以及每个模型在用哪一份。
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

  /// 这个模型要随请求发出去的规则;用默认规则时是 null(= 什么都不发)。
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
      // 上一版每个模型存一份无名规则:迁成「导入的 NAI 5 规则」这样的预设,
      // 并且照旧是那个模型在用的 —— 升级之后不该悄悄换回默认
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

// ---- 默认规则 ----

/// 默认规则:服务端预设里那份规则主体,连同顶层 meta 里的名称、作者、版本。
class DefaultRules {
  const DefaultRules({
    required this.name,
    required this.author,
    required this.version,
    required this.rules,
  });

  final String name;
  final String author;

  /// `v4.5` / `v5` 这类,显示成「v5 版」。
  final String version;
  final List<PresetRule> rules;

  /// 接口响应或内置 JSON → 默认规则。缺的 meta 用占位值补上,规则一段都没有返回 null。
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

/// 默认规则:先问服务端要最新那份,拿不到才用包里内置的。
///
/// 服务端那份就是它自己在用的规则主体,你改了服务端预设这里会跟上;包里那份是打包
/// 时的快照,只在连不上后端时兜底 —— 自定义接口那条没它就没有系统提示可发。
///
/// 发消息时走缓存,十分钟内不重复取:两万字的规则不值得每轮都下一遍。导出这种用户
/// 主动点的操作传 [fresh],拿最新的。
final _defaultCache = <RulesFamily, ({DefaultRules value, DateTime at})>{};
const _defaultTtl = Duration(minutes: 10);

Future<DefaultRules> fetchDefaultRules(
  RulesFamily f, {
  required String backendBase,
  required String sessionId,
  bool fresh = false,
  http.Client? client,
}) async {
  final hit = _defaultCache[f];
  if (!fresh &&
      hit != null &&
      DateTime.now().difference(hit.at) < _defaultTtl) {
    return hit.value;
  }
  // 没有 Bot 授权也照样取:服务端对这个端点不要求会话(自定义接口那条要它当系统提示)
  if (backendBase.isNotEmpty) {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(
            Uri.parse(
              '$backendBase/api/agent/preset-rules?image_model=${_imageModelOf(f)}',
            ),
            headers: sessionId.isEmpty
                ? const {}
                : {'Authorization': 'Bearer $sessionId'},
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final got = DefaultRules.fromJson(
          jsonDecode(utf8.decode(r.bodyBytes)),
          f,
        );
        if (got != null) {
          _defaultCache[f] = (value: got, at: DateTime.now());
          return got;
        }
      }
    } catch (_) {
      // 老后端没有这个端点、或者网络抖了:落到下面
    } finally {
      if (client == null) c.close();
    }
  }
  // 取不到新的:手上有旧的就先用旧的,比包里那份新
  return hit?.value ?? bundledDefaultRules(f);
}

/// 只要规则内容的简写。
Future<List<PresetRule>> defaultRules(
  RulesFamily f, {
  required String backendBase,
  required String sessionId,
  bool fresh = false,
}) async => (await fetchDefaultRules(
  f,
  backendBase: backendBase,
  sessionId: sessionId,
  fresh: fresh,
)).rules;

/// 规则预设页显示默认规则那两项用:名称、作者、版本。
final defaultRulesProvider = FutureProvider.family<DefaultRules, RulesFamily>((
  ref,
  f,
) async {
  final base = ref.read(backendBaseProvider).value ?? '';
  final sid = (await ref.read(botSessionProvider.future))?.sessionId ?? '';
  return fetchDefaultRules(f, backendBase: base, sessionId: sid);
});

/// 包里内置的那份(`assets/prompts/*.json`,由服务端预设生成)。
Future<DefaultRules> bundledDefaultRules(RulesFamily f) async {
  final raw = await rootBundle.loadString('assets/prompts/${f.name}.json');
  return DefaultRules.fromJson(jsonDecode(raw), f) ??
      DefaultRules(
        name: kDefaultRulesName,
        author: kDefaultRulesAuthor,
        version: defaultRulesVersionOf(f),
        rules: const [],
      );
}

/// 只要规则内容的简写。
Future<List<PresetRule>> bundledRules(RulesFamily f) async =>
    (await bundledDefaultRules(f)).rules;

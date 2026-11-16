/// 自定义 AI 接口:用户自己填的大模型地址,助手可以不走 Plana 后端直连它。
///
/// **存在加密存储里**,因为条目带 API Key —— 与 NAI 令牌同一条规矩
/// (见 `secure_storage.dart`:读写点一律走共享的那份配置,别自建)。
///
/// 选了它,整轮在本机跑(见 `runtime/direct_runtime.dart`),报文格式见 `llm/`。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/auth/secure_storage.dart';

const _key = 'assistant_endpoints';

/// 接口的报文格式。三家的鉴权头、请求体、模型列表路径都不一样。
enum AgentApiFormat {
  /// OpenAI 兼容(`/chat/completions`,`Authorization: Bearer`)。
  /// 绝大多数第三方中转、本地推理都是这个。
  openai,

  /// Google Gemini(`/models/{model}:generateContent`,`x-goog-api-key`)。
  google,

  /// Anthropic(`/messages`,`x-api-key` + `anthropic-version`)。
  anthropic,
}

/// 分段选择器上那三个字。用大家叫得出口的名字(Gemini / Claude),
/// 不用公司名 —— 三段并排放不下「Google Gemini」这种长度。
String agentApiFormatLabel(AgentApiFormat f) => switch (f) {
  AgentApiFormat.openai => 'OpenAI',
  AgentApiFormat.google => 'Gemini',
  AgentApiFormat.anthropic => 'Claude',
};

/// 各家默认基址。用户留空时用它,省得为官方地址还要查一遍文档。
String agentApiDefaultBase(AgentApiFormat f) => switch (f) {
  AgentApiFormat.openai => 'https://api.openai.com/v1',
  AgentApiFormat.google => 'https://generativelanguage.googleapis.com/v1beta',
  AgentApiFormat.anthropic => 'https://api.anthropic.com/v1',
};

/// 各家的对话接口路径。中转服务改路径是常事,所以它可填。
///
/// Gemini 那条**把模型名写在路径里**,所以用 `{model}` 占位,发请求时替换。
String agentApiDefaultPath(AgentApiFormat f) => switch (f) {
  AgentApiFormat.openai => '/chat/completions',
  AgentApiFormat.google => '/models/{model}:generateContent',
  AgentApiFormat.anthropic => '/messages',
};

/// 添加接口时可以直接选的服务:格式和地址都带好。不在表里的走「自定义」自己填。
class EndpointPreset {
  const EndpointPreset(this.label, this.format, this.base, this.keyUrl);

  final String label;
  final AgentApiFormat format;
  final String base;

  /// 创建 API Key 的页面。
  final String keyUrl;

  /// 这个格式的官方服务;选择页分在「官方」一组。
  bool get official => base == agentApiDefaultBase(format);
}

const kEndpointPresets = [
  EndpointPreset(
    'OpenAI',
    AgentApiFormat.openai,
    'https://api.openai.com/v1',
    'https://platform.openai.com/api-keys',
  ),
  EndpointPreset(
    'Gemini',
    AgentApiFormat.google,
    'https://generativelanguage.googleapis.com/v1beta',
    'https://aistudio.google.com/apikey',
  ),
  EndpointPreset(
    'Claude',
    AgentApiFormat.anthropic,
    'https://api.anthropic.com/v1',
    'https://console.anthropic.com/settings/keys',
  ),
  EndpointPreset(
    'DeepSeek',
    AgentApiFormat.openai,
    'https://api.deepseek.com/v1',
    'https://platform.deepseek.com/api_keys',
  ),
  EndpointPreset(
    'OpenRouter',
    AgentApiFormat.openai,
    'https://openrouter.ai/api/v1',
    'https://openrouter.ai/keys',
  ),
];

/// 按格式 + 地址认出是哪一家;认不出(中转、自建)返回 null。地址留空的按该格式的官方地址算。
EndpointPreset? endpointPresetOf(AgentApiFormat format, String baseUrl) {
  String norm(String u) =>
      u.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
  final b = norm(baseUrl.isEmpty ? agentApiDefaultBase(format) : baseUrl);
  for (final p in kEndpointPresets) {
    if (p.format == format && norm(p.base) == b) return p;
  }
  return null;
}

/// 填进来的地址 → 基址:去掉末尾斜杠,连对话路径一起贴进来的把路径切掉
/// (`…/v1/chat/completions` → `…/v1`),不然发请求时路径会拼两遍。
String normalizeEndpointBase(String raw, AgentApiFormat format) {
  var b = raw.trim().replaceAll(RegExp(r'/+$'), '');
  final tail = switch (format) {
    AgentApiFormat.openai => RegExp(
      r'/chat/completions$',
      caseSensitive: false,
    ),
    AgentApiFormat.anthropic => RegExp(r'/messages$', caseSensitive: false),
    AgentApiFormat.google => RegExp(
      r'/models/[^/]+:(?:stream)?generateContent.*$',
      caseSensitive: false,
    ),
  };
  b = b.replaceFirst(tail, '');
  return b.replaceAll(RegExp(r'/+$'), '');
}

class CustomEndpoint {
  const CustomEndpoint({
    required this.id,
    required this.name,
    required this.format,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.models = const [],
    this.imageModels = const [],
    this.apiPath = '',
    this.headers = const {},
  });

  final String id;

  /// 界面上显示的名字。空的话按地址认出的服务名或主机名。
  final String name;

  final AgentApiFormat format;

  /// 末尾无斜杠。空 = 用 [agentApiDefaultBase]。
  final String baseUrl;

  final String apiKey;

  /// 这一次请求用的模型 id,如 `gpt-5.6-luna` / `gemini-3.7-flash` / `claude-sonnet-4-6`。
  /// 读存档时是 [models] 的第一个,选了别的用 [forModel] 换。
  final String model;

  /// 这个接口下存的全部模型。
  final List<String> models;

  /// 出图模型(「生成图片」用),和对话模型分开存。Claude 格式不出图,恒为空。
  final List<String> imageModels;

  /// 这个接口能不能出图:格式支持、填了 Key、有出图模型。
  bool get canDraw =>
      format != AgentApiFormat.anthropic &&
      apiKey.trim().isNotEmpty &&
      imageModels.isNotEmpty;

  /// [models] 为空时(只给了 [model] 的)按 [model] 一个算。
  List<String> get allModels =>
      models.isNotEmpty ? models : [if (model.isNotEmpty) model];

  /// 换成用 [m] 发请求。
  CustomEndpoint forModel(String m) => copyWith(model: m);

  /// 对话接口路径。空 = 用 [agentApiDefaultPath]。`{model}` 会被替换成模型名。
  final String apiPath;

  /// 自定义请求头,对话和拉模型列表都带。
  final Map<String, String> headers;

  /// [builtIn] 叠上 [headers]。头名不分大小写,同名的以 [headers] 为准。
  Map<String, String> withHeaders(Map<String, String> builtIn) {
    if (headers.isEmpty) return builtIn;
    final own = {for (final k in headers.keys) k.toLowerCase()};
    return {
      for (final h in builtIn.entries)
        if (!own.contains(h.key.toLowerCase())) h.key: h.value,
      ...headers,
    };
  }

  String get displayName =>
      name.trim().isNotEmpty ? name.trim() : providerLabel;

  /// 地址认得出是哪家就写那家,认不出写主机名。
  String get providerLabel =>
      endpointPresetOf(format, baseUrl)?.label ??
      Uri.tryParse(effectiveBase)?.host ??
      effectiveBase;

  String get effectiveBase {
    final b = baseUrl.trim();
    return (b.isEmpty ? agentApiDefaultBase(format) : b).replaceAll(
      RegExp(r'/+$'),
      '',
    );
  }

  /// 拼在 [effectiveBase] 后面的那一段。开头补斜杠,`{model}` 就地替换。
  String get effectivePath {
    final raw = apiPath.trim().isEmpty
        ? agentApiDefaultPath(format)
        : apiPath.trim();
    final withSlash = raw.startsWith('/') ? raw : '/$raw';
    return withSlash.replaceAll('{model}', model.trim());
  }

  /// 完整的对话接口地址(非流式)。流式地址各家不同,见 `llm/` 下的实现。
  Uri get chatUri => Uri.parse('$effectiveBase$effectivePath');

  /// 填全了才能用。缺一样就发不出去,列表里置灰。
  bool get usable => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  CustomEndpoint copyWith({
    String? name,
    AgentApiFormat? format,
    String? baseUrl,
    String? apiKey,
    String? model,
    List<String>? models,
    List<String>? imageModels,
    String? apiPath,
    Map<String, String>? headers,
  }) => CustomEndpoint(
    id: id,
    name: name ?? this.name,
    format: format ?? this.format,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    models: models ?? this.models,
    imageModels: imageModels ?? this.imageModels,
    apiPath: apiPath ?? this.apiPath,
    headers: headers ?? this.headers,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'format': format.name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': allModels.firstOrNull ?? '',
    'models': allModels,
    if (imageModels.isNotEmpty) 'imageModels': imageModels,
    if (apiPath.isNotEmpty) 'apiPath': apiPath,
    if (headers.isNotEmpty) 'headers': headers,
  };

  static CustomEndpoint? fromJson(Object? e) {
    if (e is! Map) return null;
    final id = e['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final single = e['model']?.toString() ?? '';
    final models = switch (e['models']) {
      final List l => [
        for (final m in l)
          if ('$m'.trim().isNotEmpty) '$m'.trim(),
      ],
      _ => [if (single.isNotEmpty) single],
    };
    return CustomEndpoint(
      id: id,
      name: e['name']?.toString() ?? '',
      format:
          AgentApiFormat.values.asNameMap()[e['format']] ??
          AgentApiFormat.openai,
      baseUrl: e['baseUrl']?.toString() ?? '',
      apiKey: e['apiKey']?.toString() ?? '',
      model: models.firstOrNull ?? '',
      models: models,
      imageModels: [
        if (e['imageModels'] case final List l)
          for (final m in l)
            if ('$m'.trim().isNotEmpty) '$m'.trim(),
      ],
      apiPath: e['apiPath']?.toString() ?? '',
      headers: switch (e['headers']) {
        final Map h => {
          for (final x in h.entries)
            if ('${x.key}'.isNotEmpty) '${x.key}': x.value?.toString() ?? '',
        },
        _ => const {},
      },
    );
  }
}

final _headerName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
final _headerValue = RegExp(r'^[\x20-\x7E\t]*$');

/// 「名称: 值」一行一条 → 请求头。空行跳过,同名(不分大小写)后写的为准。
/// [bad] 是第一条不合格的行号(从 1 起),全合格为 null。
({Map<String, String> headers, int? bad}) parseHeaderLines(String text) {
  final out = <String, String>{};
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final at = line.indexOf(':');
    final name = at < 0 ? '' : line.substring(0, at).trim();
    final value = at < 0 ? '' : line.substring(at + 1).trim();
    if (!_headerName.hasMatch(name) || !_headerValue.hasMatch(value)) {
      return (headers: out, bad: i + 1);
    }
    out.removeWhere((k, _) => k.toLowerCase() == name.toLowerCase());
    out[name] = value;
  }
  return (headers: out, bad: null);
}

/// [parseHeaderLines] 的反向。
String formatHeaderLines(Map<String, String> headers) =>
    [for (final h in headers.entries) '${h.key}: ${h.value}'].join('\n');

final customEndpointsProvider =
    AsyncNotifierProvider<CustomEndpointsNotifier, List<CustomEndpoint>>(
      CustomEndpointsNotifier.new,
    );

class CustomEndpointsNotifier extends AsyncNotifier<List<CustomEndpoint>> {
  // 必须用共享的 secureStorageProvider,不能自建一个:两者当前配置相同,
  // 但一旦给共享那个加上 AndroidOptions(resetOnError 等),自建的这份会是
  // **唯一没跟上的**,而且编译器和 lint 都不会提醒。
  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);

  var _seq = 0;

  String newId() => 'ep${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  @override
  Future<List<CustomEndpoint>> build() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const [];
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      return [for (final e in j) ?CustomEndpoint.fromJson(e)];
    } catch (_) {
      // Keystore 还没就绪 / 读坏了 —— 按「没存过」处理,不崩。
      return const [];
    }
  }

  Future<void> _save(List<CustomEndpoint> next) async {
    state = AsyncData(next);
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode([for (final e in next) e.toJson()]),
      );
    } catch (_) {
      // 写不进去只影响下次冷启动,这一程照常能用
    }
  }

  /// 新增或就地替换(按 id)。
  Future<void> put(CustomEndpoint e) async {
    final list = [...state.value ?? const <CustomEndpoint>[]];
    final i = list.indexWhere((x) => x.id == e.id);
    if (i < 0) {
      list.add(e);
    } else {
      list[i] = e;
    }
    await _save(list);
  }

  Future<void> remove(String id) async {
    final list = [
      for (final e in state.value ?? const <CustomEndpoint>[])
        if (e.id != id) e,
    ];
    await _save(list);
  }

  /// [to] 按 `onReorderItem` 语义,已经是移除 [from] 之后的位置。
  Future<void> reorder(int from, int to) async {
    final list = [...state.value ?? const <CustomEndpoint>[]];
    if (from == to || from < 0 || from >= list.length) return;
    if (to < 0 || to >= list.length) return;
    list.insert(to, list.removeAt(from));
    await _save(list);
  }
}

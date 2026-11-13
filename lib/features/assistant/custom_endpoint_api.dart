/// 自定义接口的**模型列表**拉取。三家的路径、鉴权头、返回形状都不一样。
///
/// 只做这一件事:让用户不必手抄模型 id。抄错一个字符的表现是「发出去 404」,
/// 而 404 在中转服务上又常被包成别的错,查半天查不到根因。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'custom_endpoint.dart';
import '../../l10n/l10n.dart';

/// 拉模型列表。失败一律抛 [EndpointException],消息是给用户看的原话。
Future<List<String>> fetchModelList(
  CustomEndpoint e, {
  http.Client? client,
}) async {
  final own = client == null;
  final c = client ?? http.Client();
  try {
    final (uri, headers) = switch (e.format) {
      // OpenAI:GET {base}/models
      AgentApiFormat.openai => (
        Uri.parse('${e.effectiveBase}/models'),
        {'Authorization': 'Bearer ${e.apiKey.trim()}'},
      ),
      // Google:GET {base}/models,key 走头(放 query 会进日志)
      AgentApiFormat.google => (
        Uri.parse('${e.effectiveBase}/models'),
        {'x-goog-api-key': e.apiKey.trim()},
      ),
      // Anthropic:GET {base}/models,版本头必带
      AgentApiFormat.anthropic => (
        Uri.parse('${e.effectiveBase}/models'),
        {'x-api-key': e.apiKey.trim(), 'anthropic-version': '2023-06-01'},
      ),
    };

    final http.Response resp;
    try {
      resp = await c
          .get(uri, headers: e.withHeaders(headers))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw EndpointException(l10nNow.epCantConnect(uri.host));
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw EndpointException(l10nNow.epBadKey(resp.statusCode));
    }
    if (resp.statusCode == 404) {
      throw EndpointException(l10nNow.epNoModelList);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw EndpointException(l10nNow.epFetchFailed(resp.statusCode));
    }
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final out = parseModelList(e.format, body);
    if (out.isEmpty) throw EndpointException(l10nNow.epNoModels);
    return out;
  } finally {
    if (own) c.close();
  }
}

/// 响应 → 模型 id 列表。抽成纯函数是因为三家的形状各不相同,而**认错字段的
/// 表现是「列表空着」**,和网络失败长得一样,不单测根本分不出是哪一头的问题。
List<String> parseModelList(AgentApiFormat format, Object? body) {
  if (body is! Map) return const [];
  final raw = switch (format) {
    // {"data":[{"id":"gpt-4o"}]}
    AgentApiFormat.openai || AgentApiFormat.anthropic => body['data'],
    // {"models":[{"name":"models/gemini-3.7-flash"}]}
    AgentApiFormat.google => body['models'],
  };
  if (raw is! List) return const [];
  final out = <String>[];
  for (final m in raw) {
    if (m is! Map) continue;
    // Google 用 name 且带 `models/` 前缀;另外两家用 id
    final id = (m['id'] ?? m['name'])?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    final bare = id.startsWith('models/') ? id.substring(7) : id;
    if (bare.isNotEmpty && !out.contains(bare)) out.add(bare);
  }
  out.sort();
  return out;
}

class EndpointException implements Exception {
  const EndpointException(this.message);

  final String message;

  @override
  String toString() => message;
}

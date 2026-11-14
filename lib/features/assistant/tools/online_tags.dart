import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/net/backend_http.dart';
import '../../editor/data/tag_completion.dart';
import 'tool_context.dart';

/// 角色候选筛选最多等多久:后端那边判一次 0.3~1 秒,超时就全留。
const _roleFilterTimeout = Duration(seconds: 5);

/// 联网的标签服务:语义搜词与 Wiki 摘要就是编辑页补全那一套(`TagCompletion`),
/// 角色候选筛选打后端的 `/api/agent/role-filter`。
class CompletionOnlineTags implements OnlineTags {
  CompletionOnlineTags(this._tags, {this.sessionId = '', http.Client? client})
    : _client = client ?? backendHttpClient();

  final TagCompletion _tags;

  /// 空串 = 没有 Bot 授权,后端按 IP 限流。
  final String sessionId;

  final http.Client _client;

  @override
  Future<List<SemanticHit>> characters(String query, {int limit = 10}) async =>
      [
        for (final h in await _tags.searchCharacters(query, limit: limit))
          (
            tag: h.tag,
            // 上游的中文名是逗号串:正名在前,后面是出处、别名
            zh: h.cnName
                .split(RegExp(r'[,，]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .join('、'),
            count: h.count,
            wiki: h.wiki,
          ),
      ];

  @override
  Future<String?> wiki(String tag) async {
    final w = await _tags.fetchWiki(tag);
    final zh = w?.summaryZh?.trim() ?? '';
    if (zh.isNotEmpty) return zh;
    final en = w?.summary?.trim() ?? '';
    return en.isEmpty ? null : en;
  }

  @override
  Future<List<String>?> filterRoles(String userText, List<String> tags) async {
    final base = _tags.baseUrl;
    if (base.isEmpty || tags.isEmpty) return null;
    try {
      final resp = await _client
          .post(
            Uri.parse('$base/api/agent/role-filter'),
            headers: {
              'Content-Type': 'application/json',
              if (sessionId.isNotEmpty) 'Authorization': 'Bearer $sessionId',
            },
            body: jsonEncode({'user_text': userText, 'tags': tags}),
          )
          .timeout(_roleFilterTimeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final kept = body is Map ? body['kept'] : null;
      if (kept is! List) return null;
      return [
        for (final t in kept)
          if (t is String) t,
      ];
    } catch (_) {
      return null;
    }
  }
}

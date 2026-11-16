/// 用户自填接口的三家格式共用的传输:发请求、收流、非流式回落、拉模型列表、连通测试。
/// 各家只管地址、鉴权头、请求体和响应字段(见 openai / gemini / anthropic 三个实现)。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../l10n/l10n.dart';
import '../assistant_settings.dart' show ThinkLevel;
import '../custom_endpoint.dart';
import '../domain/agent_event.dart' show AgentFailure;
import 'anthropic_provider.dart';
import 'gemini_provider.dart';
import 'llm_provider.dart';
import 'openai_provider.dart';

/// 这个接口按它的格式该用哪家实现。
HttpLlmProvider llmProviderFor(CustomEndpoint e) => switch (e.format) {
  AgentApiFormat.openai => OpenAiProvider(e),
  AgentApiFormat.google => GeminiProvider(e),
  AgentApiFormat.anthropic => AnthropicProvider(e),
};

/// 两帧之间至少隔这么久。快的模型一秒吐几十个 token,每个都推一帧等于每秒几十次整块重建。
const _frameMs = 60;

abstract class HttpLlmProvider implements LlmProvider {
  HttpLlmProvider(this.endpoint);

  final CustomEndpoint endpoint;

  String get apiKey => endpoint.apiKey.trim();

  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(streaming: true, thinking: true);

  /// 对话地址。
  Uri chatUri({required bool stream}) => endpoint.chatUri;

  /// 这家必带的头(鉴权、版本)。对话和拉模型列表都带。
  Map<String, String> get authHeaders;

  /// 请求体。带图的那条消息图在前、字在后,只发图时不塞空的文字段。
  Map<String, dynamic> requestBody(LlmRequest request, {required bool stream});

  /// 思考等级 → 请求体里的字段。[ThinkLevel.auto] 不发档位。
  Map<String, dynamic> thinkFields(ThinkLevel level);

  /// 流式响应的一帧 → 这一帧新增的字。认不出的帧当没字,不抛。
  LlmText parseDelta(Object? frame);

  /// 非流式响应 → 正文。思考摘要不算正文。形状不对返回空串。
  String parseResponse(Object? body);

  /// 模型列表地址。
  Uri get modelsUri => Uri.parse('${endpoint.effectiveBase}/models');

  /// 模型列表响应 → 模型 id,去重、排序。形状不对返回空表。
  List<String> parseModels(Object? body);

  /// [parseModels] 共用的取法:每项取 `id`(没有取 `name`),去掉 `models/` 前缀。
  List<String> modelIdsOf(Object? list) {
    if (list is! List) return const [];
    final out = <String>[];
    for (final m in list) {
      if (m is! Map) continue;
      final id = (m['id'] ?? m['name'])?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final bare = id.startsWith('models/') ? id.substring(7) : id;
      if (bare.isNotEmpty && !out.contains(bare)) out.add(bare);
    }
    out.sort();
    return out;
  }

  @override
  Stream<LlmText> chat(
    LlmRequest request, {
    required http.Client client,
    bool stream = true,
    Duration? timeout,
  }) async* {
    final uri = chatUri(stream: stream);
    final req = http.Request('POST', uri)
      ..headers.addAll(
        endpoint.withHeaders({
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          ...authHeaders,
        }),
      )
      ..bodyBytes = utf8.encode(
        jsonEncode(requestBody(request, stream: stream)),
      );

    final noReply = AgentFailure(
      l10nNow.modelNoReplyIn('${timeout?.inSeconds}'),
    );
    Future<T> limited<T>(Future<T> f) async {
      if (timeout == null) return f;
      try {
        return await f.timeout(timeout);
      } on TimeoutException {
        throw noReply;
      }
    }

    Future<String> readAll(http.StreamedResponse r) =>
        limited(r.stream.bytesToString());

    final http.StreamedResponse resp;
    try {
      resp = await limited(client.send(req));
    } on AgentFailure {
      rethrow;
    } catch (e) {
      throw AgentFailure('$e');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AgentFailure.http(resp.statusCode, await readAll(resp));
    }
    final Stream<String> lines;
    if (stream &&
        (resp.headers['content-type'] ?? '').toLowerCase().contains(
          'event-stream',
        )) {
      final all = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      lines = timeout == null
          ? all
          : all.timeout(timeout, onTimeout: (sink) => sink.addError(noReply));
    } else {
      // 没开流,或者中转不认流式:收完整段按非流式解析
      final raw = await readAll(resp);
      final text = parseResponse(_tryJson(raw));
      if (text.isNotEmpty || !stream || !raw.contains('data:')) {
        yield (text: text, reasoning: '');
        return;
      }
      // 类型写着 json、身子却是一串 SSE 帧:按帧收,只是整段一起到
      lines = Stream.fromIterable(const LineSplitter().convert(raw));
    }

    final text = StringBuffer();
    final reasoning = StringBuffer();
    var lastFrame = 0;
    await for (final line in lines) {
      // `event:` 行与 `:` 心跳不看:三家的 data 自带类型
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final frame = _tryJson(data);
      // Claude 的报错是流中间的一帧,不是 HTTP 状态码
      if (frame is Map && frame['type'] == 'error') throw AgentFailure(data);
      final d = parseDelta(frame);
      if (d.text.isEmpty && d.reasoning.isEmpty) continue;
      text.write(d.text);
      reasoning.write(d.reasoning);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastFrame < _frameMs) continue;
      lastFrame = now;
      yield (text: text.toString(), reasoning: reasoning.toString());
    }
    // 收尾补一帧:最后几个字多半还卡在上面那道攒帧里
    yield (text: text.toString(), reasoning: reasoning.toString());
  }

  /// 拉模型列表。失败抛 [AgentFailure],内容是原始错误。
  Future<List<String>> listModels({http.Client? client}) async {
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final http.Response resp;
      try {
        resp = await c
            .get(modelsUri, headers: endpoint.withHeaders(authHeaders))
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        throw AgentFailure('$e');
      }
      final body = utf8.decode(resp.bodyBytes);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw AgentFailure.http(resp.statusCode, body);
      }
      final out = parseModels(_tryJson(body));
      if (out.isEmpty) throw AgentFailure(l10nNow.epNoModels);
      return out;
    } finally {
      if (own) c.close();
    }
  }

  /// 发一条最短的对话,确认地址、Key、模型、格式对得上。成功返回用时;
  /// 失败抛 [AgentFailure]。等两分钟为止。
  Future<Duration> ping({http.Client? client}) async {
    final own = client == null;
    final c = client ?? http.Client();
    final sw = Stopwatch()..start();
    try {
      final reply = await chat(
        const LlmRequest(
          system: 'Reply with the single word OK.',
          messages: [(role: 'user', content: 'ping', images: [])],
        ),
        client: c,
        stream: false,
        timeout: const Duration(seconds: 120),
      ).last;
      if (reply.text.trim().isEmpty) {
        throw AgentFailure(l10nNow.replyUnreadable);
      }
      return sw.elapsed;
    } finally {
      if (own) c.close();
    }
  }
}

Object? _tryJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

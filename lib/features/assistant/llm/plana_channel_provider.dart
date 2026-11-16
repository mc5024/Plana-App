/// 后端模型:`POST /api/agent/channel`,一跳调一次模型。外壳、渠道参数、Jev 拒绝判据在后端,
/// 规则、工具、回复解析与重试和自定义接口一样在本机跑。响应是 SSE,整段一帧返回。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../../l10n/l10n.dart';
import '../assistant_settings.dart' show ThinkLevel;
import '../domain/agent_event.dart' show AgentFailure;
import 'llm_provider.dart';

/// 后端渠道:思考深度由服务端按渠道定,回复整段返回。
const kChannelCapabilities = LlmCapabilities(streaming: false, thinking: false);

final _random = Random.secure();

String _newTurnId() => [
  for (var i = 0; i < 8; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

class PlanaChannelProvider implements LlmProvider {
  PlanaChannelProvider({
    required this.baseUrl,
    required this.sessionId,
    required this.model,
    required this.imageModel,
    String? turnId,
  }) : turnId = turnId ?? _newTurnId();

  final String baseUrl;

  /// 空串 = 没有 Bot 授权(只能用免费模型)。
  final String sessionId;

  /// 后端渠道 key;空串 = 后端的全局默认。
  final String model;

  /// 图片生成模型档位,后端按它挑外壳。
  final String imageModel;

  /// 这一轮的 id:同一轮的几跳共用,后端按轮限流。
  final String turnId;

  /// 两次收到数据之间最多等多久。后端静默期每 15 秒推一行心跳。
  static const idleTimeout = Duration(seconds: 90);

  @override
  LlmCapabilities get capabilities => kChannelCapabilities;

  @override
  String? thinkNote(ThinkLevel level) => null;

  /// 发给后端的请求体:messages 在 [LlmRequest.turnStart] 处切成历史与本轮。
  Map<String, Object?> requestBody(LlmRequest r) {
    final split = r.turnStart.clamp(0, r.messages.length);
    Map<String, Object?> msg(LlmMessage m) => {
      'role': m.role,
      'content': m.content,
      // 老后端只认 image(一张),新后端认 images:两个都发,image 放第一张
      if (m.images.firstOrNull case final i?)
        'image': {'mime': i.mime, 'data': i.data},
      if (m.images.isNotEmpty)
        'images': [
          for (final i in m.images) {'mime': i.mime, 'data': i.data},
        ],
    };
    return {
      'model': model,
      'image_model': imageModel,
      'system': r.system,
      'history': [for (final m in r.messages.take(split)) msg(m)],
      'messages': [for (final m in r.messages.skip(split)) msg(m)],
      'turn_id': turnId,
    };
  }

  @override
  Stream<LlmText> chat(
    LlmRequest request, {
    required http.Client client,
    bool stream = true,
    Duration? timeout,
  }) async* {
    if (baseUrl.isEmpty) throw AgentFailure(l10nNow.backendUnset);
    final req = http.Request('POST', Uri.parse('$baseUrl/api/agent/channel'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        if (sessionId.isNotEmpty) 'Authorization': 'Bearer $sessionId',
      })
      ..bodyBytes = utf8.encode(jsonEncode(requestBody(request)));

    final silent = AgentFailure(l10nNow.noDataIn('${idleTimeout.inSeconds}'));
    final http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(idleTimeout);
    } on TimeoutException {
      throw silent;
    } catch (e) {
      throw AgentFailure('$e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // 鉴权、限流、超限这些后端自己拒的,再问一遍也一样;网关错可能是一时的
      throw AgentFailure.http(
        resp.statusCode,
        await resp.stream.bytesToString(),
        retryable: resp.statusCode >= 500,
      );
    }

    // 一帧 = 若干行 + 一个空行。`event:` 定类型,`data:` 装 JSON;`:` 开头的是心跳
    var event = '';
    final data = StringBuffer();
    final lines = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(idleTimeout, onTimeout: (sink) => sink.addError(silent));
    await for (final line in lines) {
      if (line.isNotEmpty) {
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(5).trim());
        }
        continue;
      }
      final raw = data.toString();
      final name = event;
      event = '';
      data.clear();
      Object? payload;
      try {
        payload = jsonDecode(raw);
      } on FormatException {
        payload = null;
      }
      final map = payload is Map ? payload : const {};
      switch (name) {
        case 'final':
          yield (
            text: '${map['text'] ?? ''}',
            reasoning: '${map['reasoning'] ?? ''}',
          );
          return;
        case 'error':
          final message = '${map['message'] ?? ''}'.trim();
          throw AgentFailure(
            message.isEmpty ? raw : message,
            status: (map['status'] as num?)?.toInt(),
            // refused:后端已经原地重掷过;timeout:一跳已经等满,再来一遍也一样
            retryable: map['code'] == 'upstream',
          );
      }
    }
    throw AgentFailure(l10nNow.channelEndedEarly);
  }
}

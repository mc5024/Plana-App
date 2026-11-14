/// 后端模型那条:`POST /api/agent/web/generate-prompt`,响应是 SSE。
///
/// 事件只认 `tool_call` / `tool_result` / `degraded` / `final` / `error`,其余丢弃。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../agent_trace.dart';
import '../domain/agent_event.dart';
import '../domain/agent_result.dart';
import '../domain/turn_request.dart';
import '../preset_rules.dart' show appToolLayer, withToolLayer;
import 'agent_runtime.dart';

class BackendAgentRuntime implements AgentRuntime {
  BackendAgentRuntime({required this.baseUrl, required this.sessionId});

  final String baseUrl;

  /// 空串 = 没有 Bot 授权(只能用免费模型)。
  final String sessionId;

  @override
  String get route => AgentTrace.routeBackend;

  @override
  Stream<AgentEvent> run(AgentTurnRequest req, {AgentTrace? trace}) async* {
    // 没自定义就不发规则,服务端用它自己那份;自定义的挂上 app 的工具层再发
    final custom = req.customRules;
    final presetRules = custom == null
        ? const <Map<String, dynamic>>[]
        : [for (final r in withToolLayer(custom, await appToolLayer())) r.toJson()];
    final image = req.image;
    final canvas = req.canvas;
    yield* streamAgentPrompt(
      baseUrl: baseUrl,
      sessionId: sessionId,
      userRequest: req.userText,
      model: req.backendModel,
      imageModel: req.imageModel,
      imageB64: image == null ? null : base64Encode(image),
      history: req.history,
      historyTurns: req.historyTurns,
      currentPositive: canvas?.positive ?? '',
      currentNegative: canvas?.negative ?? '',
      currentCharacters: canvas?.characters ?? const [],
      webArtists: req.artists,
      webOcs: req.ocs,
      resources: req.resources,
      libraryScope: req.libraryScope,
      presetRules: presetRules,
      modes: req.modeKeys,
      onRequest: trace == null ? null : (body) => trace.request = body,
      onEvent: trace?.event,
    );
  }
}

/// 跑一轮。
///
/// 画布三项([currentPositive] / [currentNegative] / [currentCharacters])都留空 = 这轮不给画布。
/// 角色项形如 `{name, positive, negative, position}`。
///
/// [libraryScope] 为 `none` 时必须显式发:不发库服务端会回落公共库。
///
/// 发了 [webArtists] 后服务端会把正向词里认出的画师串包成 `<<artist:名字:内容>>`,
/// 收到后用 `stripArtistMarkers` 剥掉。
///
/// [idleTimeout] 是**静默超时**:等响应头、两个事件之间都按它算,只有建连限 20 秒。
/// 服务端从最后一次工具结果到出最终答案之间不发事件,那一段就是一整次 LLM 生成。
///
/// 失败抛 [AgentFailure],内容是原始错误。
Stream<AgentEvent> streamAgentPrompt({
  required String baseUrl,
  required String sessionId,
  required String userRequest,
  String model = '',
  String imageModel = '',
  String? imageB64,
  List<Map<String, String>> history = const [],
  int historyTurns = 20,
  String currentPositive = '',
  String currentNegative = '',
  List<Map<String, dynamic>> currentCharacters = const [],
  List<Map<String, dynamic>> webArtists = const [],
  List<Map<String, dynamic>> webOcs = const [],
  Map<String, Map<String, String>> resources = const {},
  String libraryScope = 'local',

  /// 自定义过的规则主体(`[{name, content, when}]`)。空 = 用服务端预设自己那份,不发。
  List<Map<String, dynamic>> presetRules = const [],

  /// 用户选的模式;空 = 不发。
  List<String> modes = const [],
  Duration idleTimeout = const Duration(seconds: 120),

  /// 调试记录:发出去的请求体,图片换成大小。
  void Function(Map<String, Object?> body)? onRequest,

  /// 调试记录:收到的每一帧,原样(解不开 JSON 的给原文)。
  void Function(String event, Object? data)? onEvent,
}) async* {
  if (baseUrl.isEmpty) throw AgentFailure('未配置后端地址');

  final client = IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 20),
  );
  final silent = AgentFailure('${idleTimeout.inSeconds} 秒内没有收到数据');
  try {
    final hasImage = imageB64 != null && imageB64.isNotEmpty;
    final body = <String, Object?>{
      'user_request': userRequest,
      'model': model,
      'image_model': imageModel,
      if (hasImage) 'image_b64': imageB64,
      'history': history,
      'history_turns': historyTurns,
      'current_positive': currentPositive,
      'current_negative': currentNegative,
      'current_characters': currentCharacters,
      'web_artists': webArtists,
      'web_ocs': webOcs,
      'resources': resources,
      'library_scope': libraryScope,
      if (presetRules.isNotEmpty) 'preset_rules': presetRules,
      if (modes.isNotEmpty) 'modes': modes,
    };
    onRequest?.call({
      ...body,
      if (hasImage) 'image_b64': '<图片 base64 ${imageB64.length} 字符>',
    });
    final req =
        http.Request(
            'POST',
            Uri.parse('$baseUrl/api/agent/web/generate-prompt'),
          )
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            if (sessionId.isNotEmpty) 'Authorization': 'Bearer $sessionId',
          })
          ..bodyBytes = utf8.encode(jsonEncode(body));

    final http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(idleTimeout);
    } on TimeoutException {
      throw silent;
    } catch (e) {
      throw AgentFailure('$e');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AgentFailure.http(
        resp.statusCode,
        await resp.stream.bytesToString(),
      );
    }

    // 一帧 = 若干行 + 一个空行。`event:` 定类型,`data:` 装 JSON。
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
          // 同一帧的多条 data 行按 SSE 规范用换行拼接
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(5).trim());
        }
        continue;
      }

      final raw = data.toString();
      final name = event;
      event = '';
      data.clear();
      if (name.isEmpty) continue;

      Object? payload;
      try {
        payload = jsonDecode(raw);
      } catch (_) {
        payload = null;
      }
      onEvent?.call(name, payload ?? raw);
      final map = payload is Map<String, dynamic>
          ? payload
          : const <String, dynamic>{};

      switch (name) {
        case 'tool_call':
          yield AgentToolCall(
            map['name']?.toString() ?? '',
            map['arguments'] is Map<String, dynamic>
                ? map['arguments'] as Map<String, dynamic>
                : const {},
          );
        case 'tool_result':
          yield AgentToolResult(
            map['name']?.toString() ?? '',
            map['summary']?.toString() ?? '',
          );
        case 'degraded':
          yield const AgentDegraded();
        case 'error':
          final message = map['message']?.toString().trim() ?? '';
          final code = map['code']?.toString().trim() ?? '';
          throw AgentFailure(
            message.isEmpty ? raw : (code.isEmpty ? message : '$message ($code)'),
          );
        case 'final':
          yield AgentDone(_resultOf(map));
          return;
      }
    }

    throw AgentFailure('连接在收到结果前结束了');
  } finally {
    client.close();
  }
}

/// `final` 事件的 data → 结果。服务端的 `thinking` 装的是发给用户的正文,
/// 原生思考在 `reasoning`。
AgentResult _resultOf(Map<String, dynamic> j) => AgentResult(
  replyText: j['thinking']?.toString().trim() ?? '',
  reasoning: j['reasoning']?.toString().trim() ?? '',
  positive: j['positive']?.toString() ?? '',
  negative: j['negative']?.toString() ?? '',
  characters: [
    for (final c in (j['characters'] as List? ?? const []))
      if (c is Map<String, dynamic>) AgentCharacter.fromJson(c),
  ],
  resources: {
    for (final e in (j['resources'] as Map? ?? const {}).entries)
      if (e.value is Map)
        '${e.key}': {
          for (final r in (e.value as Map).entries) '${r.key}': '${r.value}',
        },
  },
);

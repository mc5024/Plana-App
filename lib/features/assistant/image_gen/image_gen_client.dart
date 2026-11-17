/// 出一张图:后端渠道(`POST /api/agent/image`,SSE)或自定义接口
/// (OpenAI 格式走 Images 接口,Gemini 格式走 generateContent 出图)。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../../l10n/l10n.dart';
import '../custom_endpoint.dart';
import '../domain/agent_event.dart' show AgentFailure;
import '../llm/llm_provider.dart' show LlmImage;
import 'image_models.dart';

/// [size] / [aspect] 空 = 交给出图模型。
typedef ImageGenInput = ({
  String prompt,
  List<LlmImage> images,
  String size,
  String aspect,
});

abstract interface class ImageGenClient {
  Future<Uint8List> generate(
    ImageGenInput input, {
    required http.Client client,
  });
}

/// 同时跑 [count] 次 [one],结果按次序排;抛错的和返回 null 的跳过。
/// 返回出成的和第一个错。
Future<(List<T>, Object?)> drawBatch<T extends Object>(
  int count,
  Future<T?> Function() one,
) async {
  Object? error;
  final results = await Future.wait([
    for (var i = 0; i < count; i++)
      one().then<T?>(
        (r) => r,
        onError: (Object e) {
          error ??= e;
          return null;
        },
      ),
  ]);
  return ([for (final r in results) ?r], error);
}

ImageGenClient imageGenClientFor(
  ImageModelChoice c, {
  required String backendBase,
  required String sessionId,
}) {
  final e = c.endpoint;
  if (e == null) {
    return PlanaImageClient(
      baseUrl: backendBase,
      sessionId: sessionId,
      channel: c.model,
    );
  }
  return e.format == AgentApiFormat.google
      ? GeminiImageClient(e, c.model)
      : OpenAiImageClient(e, c.model);
}

/// 自定义接口一张图最多等多久。
const _customTimeout = Duration(minutes: 5);

/// 错误响应 → 能看懂的一句:取 JSON 里的 message / detail,取不到原文照给。
AgentFailure _httpError(int status, String body) {
  try {
    final j = jsonDecode(body);
    final e = j is Map ? (j['error'] ?? j['detail'] ?? j['message']) : null;
    final m = e is Map ? e['message'] : e;
    if (m is String && m.trim().isNotEmpty) {
      return AgentFailure('HTTP $status · ${m.trim()}', status: status);
    }
  } catch (_) {}
  return AgentFailure.http(status, body);
}

Future<String> _send(
  http.Client client,
  http.BaseRequest req,
  Duration timeout,
) async {
  final noReply = AgentFailure(l10nNow.modelNoReplyIn('${timeout.inSeconds}'));
  try {
    final resp = await client.send(req).timeout(timeout);
    final body = await resp.stream.bytesToString().timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _httpError(resp.statusCode, body);
    }
    return body;
  } on TimeoutException {
    throw noReply;
  } on AgentFailure {
    rethrow;
  } catch (e) {
    throw AgentFailure('$e');
  }
}

Object? _json(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// 后端渠道:扣用户自己的免费额度,要 Bot 授权。
class PlanaImageClient implements ImageGenClient {
  PlanaImageClient({
    required this.baseUrl,
    required this.sessionId,
    required this.channel,
  });

  final String baseUrl;
  final String sessionId;
  final String channel;

  /// 两次收到数据之间最多等多久。后端静默期每 15 秒推一行心跳。
  static const idleTimeout = Duration(seconds: 90);

  @override
  Future<Uint8List> generate(
    ImageGenInput input, {
    required http.Client client,
  }) async {
    if (baseUrl.isEmpty) throw AgentFailure(l10nNow.backendUnset);
    final req = http.Request('POST', Uri.parse('$baseUrl/api/agent/image'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $sessionId',
      })
      ..bodyBytes = utf8.encode(
        jsonEncode({
          'channel': channel,
          'prompt': input.prompt,
          'images': [
            for (final i in input.images) 'data:${i.mime};base64,${i.data}',
          ],
          'aspect': input.aspect,
          'size': input.size,
        }),
      );
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
      throw _httpError(resp.statusCode, await resp.stream.bytesToString());
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
      final map = switch (_json(raw)) {
        final Map m => m,
        _ => const {},
      };
      switch (name) {
        case 'final':
          final b64 = map['image'];
          if (b64 is! String || b64.isEmpty) break;
          return base64Decode(b64);
        case 'error':
          final message = '${map['message'] ?? ''}'.trim();
          throw AgentFailure(message.isEmpty ? raw : message);
      }
    }
    throw AgentFailure(l10nNow.channelEndedEarly);
  }
}

/// OpenAI 格式:没参考图走 `/images/generations`,有就走 `/images/edits`(multipart)。
class OpenAiImageClient implements ImageGenClient {
  OpenAiImageClient(this.endpoint, this.model);

  final CustomEndpoint endpoint;
  final String model;

  /// 比例 → Images 接口的三档尺寸;别的比例和空都不发,由模型定。
  static String? sizeOf(String aspect) => switch (aspect) {
    '1:1' => '1024x1024',
    '2:3' => '1024x1536',
    '3:2' => '1536x1024',
    _ => null,
  };

  Map<String, String> get _auth => endpoint.withHeaders({
    'Authorization': 'Bearer ${endpoint.apiKey.trim()}',
  });

  @override
  Future<Uint8List> generate(
    ImageGenInput input, {
    required http.Client client,
  }) async {
    final base = endpoint.effectiveBase;
    final size = sizeOf(input.aspect);
    final http.BaseRequest req;
    if (input.images.isEmpty) {
      req = http.Request('POST', Uri.parse('$base/images/generations'))
        ..headers.addAll({'Content-Type': 'application/json', ..._auth})
        ..bodyBytes = utf8.encode(
          jsonEncode({
            'model': model,
            'prompt': input.prompt,
            'n': 1,
            'size': ?size,
          }),
        );
    } else {
      final field = input.images.length > 1 ? 'image[]' : 'image';
      req = http.MultipartRequest('POST', Uri.parse('$base/images/edits'))
        ..headers.addAll(_auth)
        ..fields.addAll({
          'model': model,
          'prompt': input.prompt,
          'n': '1',
          'size': ?size,
        })
        ..files.addAll([
          for (final (i, img) in input.images.indexed)
            http.MultipartFile.fromBytes(
              field,
              base64Decode(img.data),
              filename: 'image$i.${img.mime.split('/').last}',
              contentType: MediaType.parse(img.mime),
            ),
        ]);
    }
    final body = _json(await _send(client, req, _customTimeout));
    final first = body is Map && body['data'] is List
        ? (body['data'] as List).firstOrNull
        : null;
    if (first is Map) {
      if (first['b64_json'] case final String b64 when b64.isNotEmpty) {
        return base64Decode(b64);
      }
      if (first['url'] case final String url when url.isNotEmpty) {
        final r = await client.get(Uri.parse(url)).timeout(_customTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
        throw AgentFailure.http(r.statusCode, r.body);
      }
    }
    throw AgentFailure(l10nNow.imageGenNoImage);
  }
}

/// Gemini 格式:`generateContent`,要图片输出;参考图跟在文字后面。
class GeminiImageClient implements ImageGenClient {
  GeminiImageClient(this.endpoint, this.model);

  final CustomEndpoint endpoint;
  final String model;

  @override
  Future<Uint8List> generate(
    ImageGenInput input, {
    required http.Client client,
  }) async {
    final req = http.Request('POST', endpoint.forModel(model).chatUri)
      ..headers.addAll(
        endpoint.withHeaders({
          'Content-Type': 'application/json',
          'x-goog-api-key': endpoint.apiKey.trim(),
        }),
      )
      ..bodyBytes = utf8.encode(
        jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': input.prompt},
                for (final i in input.images)
                  {
                    'inlineData': {'mimeType': i.mime, 'data': i.data},
                  },
              ],
            },
          ],
          'generationConfig': {
            'responseModalities': ['TEXT', 'IMAGE'],
            if (input.aspect.isNotEmpty || input.size.isNotEmpty)
              'imageConfig': {
                if (input.aspect.isNotEmpty) 'aspectRatio': input.aspect,
                if (input.size.isNotEmpty) 'imageSize': input.size,
              },
          },
        }),
      );
    final body = _json(await _send(client, req, _customTimeout));
    final texts = <String>[];
    if (body is Map && body['candidates'] is List) {
      for (final c in body['candidates'] as List) {
        final parts = c is Map && c['content'] is Map
            ? (c['content'] as Map)['parts']
            : null;
        for (final p in parts is List ? parts : const []) {
          if (p is! Map) continue;
          final inline = p['inlineData'] ?? p['inline_data'];
          if (inline is Map && inline['data'] is String) {
            return base64Decode(inline['data'] as String);
          }
          if (p['text'] case final String t when t.trim().isNotEmpty) {
            texts.add(t.trim());
          }
        }
      }
    }
    // 没出图:模型回了一段话(多半是拒绝)就给那段话
    throw AgentFailure(
      texts.isNotEmpty ? texts.join('\n') : l10nNow.imageGenNoImage,
    );
  }
}

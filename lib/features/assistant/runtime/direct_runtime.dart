/// 自定义接口那条:在本机跑 agent 循环。规则、工具、资料、占位符、账本全在手机上做;
/// 只有工具的联网来源(语义搜词、Wiki 摘要)会请求后端的 `/api/tags/*`。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../l10n/l10n.dart';
import '../agent_trace.dart';
import '../domain/agent_event.dart';
import '../domain/agent_result.dart';
import '../domain/turn_request.dart';
import '../llm/llm_image.dart';
import '../llm/llm_provider.dart';
import '../presets/default_rules.dart';
import '../presets/preset_rule.dart';
import '../protocol/fenced_protocol.dart';
import '../protocol/reply_parser.dart';
import '../protocol/tool_protocol.dart';
import '../tools/agent_tool.dart';
import '../tools/my_library.dart';
import '../tools/tool_context.dart';
import '../tools/tool_registry.dart';
import 'agent_runtime.dart';
import 'ledger.dart';
import 'placeholders.dart';
import 'prompt_assets.dart';
import 'prompt_composer.dart';

/// 一轮里最多跑几跳(每跳 = 一次模型调用)。模型连查三轮还定不下来,多半是在原地打转。
const _maxHops = 4;

class DirectAgentRuntime implements AgentRuntime {
  DirectAgentRuntime({
    required this.provider,
    this.offline,
    this.online,
    this.tools = kAgentTools,
    this.protocol = const FencedToolProtocol(),
  });

  final LlmProvider provider;

  /// 离线词库;null = 读不出来。
  final TagLookup? offline;

  /// 联网的标签服务;null = 没有后端地址。
  final OnlineTags? online;

  /// 全部工具;这一轮用哪些看工具设置。
  final List<AgentTool> tools;

  final ToolProtocol protocol;

  @override
  String get route => AgentTrace.routeCustom;

  @override
  Stream<AgentEvent> run(AgentTurnRequest req, {AgentTrace? trace}) async* {
    final client = http.Client();
    try {
      final texts = await PromptTexts.load();
      final rules =
          req.customRules ?? await bundledRules(rulesFamilyOf(req.imageModel));
      final active = enabledTools(req.tools, tools);
      final placeholders = req.tools.ocPlaceholders;
      final artists = libArtistsOf(req.artists);
      final remembered = healRememberedArtists(req.resources, artists);
      final ctx = ToolContext(
        userText: req.userText,
        settings: req.tools,
        texts: texts,
        artists: artists,
        ocs: libOcsOf(req.ocs),
        remembered: remembered,
        offline: offline,
        online: online,
      );

      // 各工具的预取彼此不相干,和附图压缩一起并着做
      final image = req.image;
      final (blocks, img) = await (
        Future.wait([for (final t in active) _prefetch(t, ctx)]),
        image == null ? Future<LlmImage?>.value() : prepareLlmImage(image),
      ).wait;
      // 账本里记着的画师串都进映射:历史里的完整串要折回占位符
      for (final e in (remembered['artist'] ?? const {}).entries) {
        if (e.key.isNotEmpty && e.value.isNotEmpty) {
          ctx.artistPlan.add(e.key, e.value);
        }
      }
      final thisTurn = <String, Map<String, String>>{};
      for (final b in blocks.nonNulls) {
        _mergeResources(thisTurn, b.resources);
      }
      final block = [for (final b in blocks.nonNulls) b.text].join('\n\n');

      final system = composeSystemPrompt(
        rules: rules,
        modes: req.modeKeys,
        toolLayer: active.isEmpty ? '' : await protocol.conventions(),
        outputFormat: await outputFormatText(),
        toolList: await protocol.toolList(active),
        notes: [for (final t in active) await t.systemNote(ctx)],
      );
      final artistTokens = ctx.artistPlan.tokens;
      final ocTokens = ctx.ocPlan.tokens;
      trace
        ?..prequery = {
          'tools': [for (final t in active) t.name],
          'block': block,
          'this_turn': thisTurn,
          'artist_placeholders': artistTokens,
          if (placeholders) 'oc_placeholders': ocTokens,
        }
        ..system = system;

      // 用户输入、画布和历史里认得出的完整资源折成占位符 —— 模型看到的「自己上次写的」
      // 就是占位符,不会照着抄完整串
      String collapse(String v) =>
          collapseArtistStrings(collapseArtistStrings(v, artistTokens), ocTokens);
      final canvas = req.canvas;
      final canvasBlock = canvas == null
          ? ''
          : canvasBlockOf(canvas, texts.get('canvas_intro'));
      final msgs = <LlmMessage>[
        for (final h in req.history)
          (
            role: h['role'] ?? 'user',
            content: collapse(h['content'] ?? ''),
            image: null,
          ),
        (
          role: 'user',
          content: [
            placeholders ? collapse(req.userText) : req.userText,
            collapse(canvasBlock),
            block,
          ].where((s) => s.isNotEmpty).join('\n\n'),
          image: img,
        ),
      ];
      trace?.messages = [
        for (final m in msgs)
          {
            'role': m.role,
            'content': m.content,
            if (m.image case final i?)
              'image': '<${i.mime} base64 ${i.data.length} 字符>',
          },
      ];

      for (var hop = 0; hop < _maxHops; hop++) {
        final hopStart = trace?.sinceStart() ?? 0;
        var raw = '';
        await for (final c in provider.chat(
          LlmRequest(system: system, messages: msgs, think: req.think),
          client: client,
          stream: req.stream,
        )) {
          raw = c.text;
          // 关着逐字显示时一帧都不推:气泡老老实实转圈到出结果
          if (req.stream) yield liveDeltaOf(c);
        }
        if (raw.trim().isEmpty) throw AgentFailure(l10nNow.modelEmptyReply);
        final hopRec = <String, Object?>{
          't': hopStart,
          'ms': (trace?.sinceStart() ?? 0) - hopStart,
          'reply': raw,
        };
        trace?.hops.add(hopRec);

        final calls = active.isEmpty
            ? const <ToolCall>[]
            : protocol.parse(raw).calls;
        if (calls.isEmpty || hop == _maxHops - 1) {
          final parsed = parseReply(raw);
          final resolve = artistResolver(ctx.artistPlan, artists);
          final expanded = expandDraw(parsed.draw, resolve);
          final draw = placeholders
              ? expandOcDraw(expanded, ctx.ocPlan)
              : expanded;
          final named = namesInReply(parsed.reply, resolve);
          final reply = placeholders ? namesInOcReply(named, ctx.ocPlan) : named;
          final ledger = mergeLedger(
            remembered,
            thisTurn,
            draw,
            rememberOcs: placeholders,
          );
          trace?.event('final', {
            'reply': reply,
            'draw': parsed.draw,
            if (draw != parsed.draw) 'draw_expanded': draw,
            'resources': ledger,
          });
          yield AgentDone(_resultOf(reply, draw, ledger));
          return;
        }

        msgs.add((role: 'assistant', content: raw, image: null));
        hopRec['tool_calls'] = [
          for (final c in calls) {'name': c.name, 'arguments': c.args},
        ];
        final results = <ToolCallResult>[];
        for (final c in calls) {
          yield AgentToolCall(c.name, c.args);
          final r = await _call(c, active, ctx, texts);
          final outcome = r.outcome;
          if (outcome != null) {
            // 工具查到的画师串记进映射:模型照着返回的 placeholder 写,出图前要认得出来
            for (final e in (outcome.resources['artist'] ?? const {}).entries) {
              ctx.artistPlan.add(e.key, e.value);
            }
            _mergeResources(thisTurn, outcome.resources);
          }
          yield AgentToolResult(c.name, outcome?.summary ?? r.error ?? '');
          results.add(ToolCallResult(c, data: outcome?.data, error: r.error));
        }
        final message = protocol.resultMessage(results, texts);
        hopRec['tool_results'] = message;
        msgs.add((role: 'user', content: message, image: null));
      }
    } finally {
      client.close();
    }
  }

  /// 预取失败不拖垮这一轮:没有这块资料,模型还能自己调工具查。
  static Future<ToolBlock?> _prefetch(AgentTool t, ToolContext ctx) async {
    try {
      return await t.prefetch(ctx);
    } catch (_) {
      return null;
    }
  }

  static Future<({ToolOutcome? outcome, String? error})> _call(
    ToolCall c,
    List<AgentTool> active,
    ToolContext ctx,
    PromptTexts texts,
  ) async {
    final tool = active.where((t) => t.name == c.name).firstOrNull;
    if (tool == null) {
      return (outcome: null, error: texts.get('unknown_tool', {'name': c.name}));
    }
    try {
      return (outcome: await tool.call(ctx, c.args), error: null);
    } catch (e) {
      return (outcome: null, error: '$e');
    }
  }

  static void _mergeResources(
    Map<String, Map<String, String>> into,
    Map<String, Map<String, String>> add,
  ) {
    for (final e in add.entries) {
      if (e.value.isEmpty) continue;
      (into[e.key] ??= {}).addAll(e.value);
    }
  }
}

AgentResult _resultOf(
  String reply,
  Map<String, dynamic>? draw,
  Map<String, Map<String, String>> resources,
) {
  final d = draw ?? const <String, dynamic>{};
  return AgentResult(
    replyText: reply.isNotEmpty ? reply : l10nNow.replyHereFallback,
    positive: d['positive']?.toString() ?? '',
    negative: d['negative']?.toString() ?? '',
    characters: [
      for (final c in (d['characters'] as List? ?? const []))
        if (c is Map<String, dynamic>) AgentCharacter.fromJson(c),
    ],
    // 并好的账本原样带出去。不能回空:下一轮拿最新那条 AI 消息的账本发,回空等于冲掉记着的画风
    resources: resources,
  );
}

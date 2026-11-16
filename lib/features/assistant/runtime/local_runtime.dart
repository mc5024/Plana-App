/// 在本机跑 agent 循环:规则、工具、资料、占位符、账本、回复解析与重试全在手机上做。
/// 模型经 [LlmProvider]:自定义接口直连,后端模型经后端的模型通道。工具的联网来源
/// (语义搜词、Wiki 摘要、角色候选筛选)请求后端的公开接口。
///
/// 出错后按设置重发几次,重发时剥掉附图。
/// 一次尝试里,工具结果和写坏的出图块回灌给模型接着跑;回复像拒绝就原地重掷。
library;

import 'dart:async';
import 'dart:convert';

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
import 'refusal.dart';

/// 一次尝试里最多几轮工具调用。模型连查三轮还定不下来,多半是在原地打转。
const _maxToolRounds = 3;

/// 一次尝试里回灌让模型重写的次数上限(出图块写坏、工具轮数用完还在调)。
const _maxFixes = 2;

class LocalAgentRuntime implements AgentRuntime {
  LocalAgentRuntime({
    required this.provider,
    this.route = AgentTrace.routeCustom,
    this.offline,
    this.online,
    this.tools = kAgentTools,
    this.protocol = const FencedToolProtocol(),
  });

  final LlmProvider provider;

  @override
  final String route;

  /// 离线词库;null = 读不出来。
  final TagLookup? offline;

  /// 联网的标签服务;null = 没有后端地址。
  final OnlineTags? online;

  /// 全部工具;这一轮用哪些看工具设置。
  final List<AgentTool> tools;

  final ToolProtocol protocol;

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
      final (blocks, imgs) = await (
        Future.wait([for (final t in active) _prefetch(t, ctx)]),
        Future.wait([for (final i in req.images) prepareLlmImage(i)]),
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
      String collapse(String v) => collapseArtistStrings(
        collapseArtistStrings(v, artistTokens),
        ocTokens,
      );
      final canvas = req.canvas;
      final canvasBlock = canvas == null
          ? ''
          : canvasBlockOf(canvas, texts.get('canvas_intro'));
      final history = <LlmMessage>[
        for (final h in req.history)
          (
            role: h['role'] ?? 'user',
            content: collapse(h['content'] ?? ''),
            images: const <LlmImage>[],
          ),
      ];
      final asked = [
        placeholders ? collapse(req.userText) : req.userText,
        collapse(canvasBlock),
      ].where((s) => s.isNotEmpty);

      // 本轮这条用户消息。重发时剥掉图,末尾补一句说明
      List<LlmMessage> messagesFor({required bool noImage}) {
        final parts = [...asked, if (block.isNotEmpty) block];
        if (noImage) {
          if (parts.isEmpty) parts.add(texts.get('retry_image_only'));
          parts.add(texts.get('retry_no_image'));
        }
        return [
          ...history,
          (
            role: 'user',
            content: parts.join('\n\n'),
            images: noImage ? const <LlmImage>[] : imgs,
          ),
        ];
      }

      // 逐字显示要设置开着、模型也能边写边吐
      final live = req.stream && provider.capabilities.streaming;
      final turn = _Turn(
        req: req,
        live: live,
        trace: trace,
        client: client,
        provider: provider,
        protocol: protocol,
        texts: texts,
        active: active,
        ctx: ctx,
        system: system,
        artists: artists,
        remembered: remembered,
        thisTurn: thisTurn,
      );
      final attempts = req.retries + 1;
      for (var attempt = 0; ; attempt++) {
        final msgs = messagesFor(noImage: attempt > 0 && imgs.isNotEmpty);
        if (attempt == 0) {
          trace?.messages = [
            for (final m in msgs)
              {
                'role': m.role,
                'content': m.content,
                if (m.images.isNotEmpty)
                  'images': [
                    for (final i in m.images)
                      '<${i.mime} base64 ${i.data.length} 字符>',
                  ].join(' '),
              },
          ];
        }
        try {
          await for (final e in turn.attempt(msgs)) {
            yield e;
          }
          return;
        } on _Refused catch (e) {
          // 同一份上下文重掷过还在拒绝,降级也救不回来。报错收场,这一轮不进历史
          throw AgentFailure(
            l10nNow.assistantRefused('${req.rerolls}', e.keyword),
          );
        } catch (e) {
          if (attempt + 1 >= attempts || !_retryable(e)) rethrow;
          trace?.event('retry', {'error': '$e', 'no_image': imgs.isNotEmpty});
          if (live) yield const AgentDelta();
        }
      }
    } finally {
      client.close();
    }
  }

  /// 密钥不对、没有这个模型、后端那边已经判死的:换个说法再问也一样。
  static bool _retryable(Object e) =>
      !(e is AgentFailure &&
          (!e.retryable || const {401, 403, 404}.contains(e.status)));

  /// 预取失败不拖垮这一轮:没有这块资料,模型还能自己调工具查。
  static Future<ToolBlock?> _prefetch(AgentTool t, ToolContext ctx) async {
    try {
      return await t.prefetch(ctx);
    } catch (_) {
      return null;
    }
  }
}

typedef _CallResult = ({ToolOutcome? outcome, String? error});

/// 原地重掷用完仍像拒绝。
class _Refused implements Exception {
  const _Refused(this.keyword);

  final String keyword;
}

/// 一轮里各次尝试共用的东西。
class _Turn {
  _Turn({
    required this.req,
    required this.live,
    required this.trace,
    required this.client,
    required this.provider,
    required this.protocol,
    required this.texts,
    required this.active,
    required this.ctx,
    required this.system,
    required this.artists,
    required this.remembered,
    required this.thisTurn,
  });

  final AgentTurnRequest req;

  /// 逐字显示:每帧推给气泡。
  final bool live;
  final AgentTrace? trace;
  final http.Client client;
  final LlmProvider provider;
  final ToolProtocol protocol;
  final PromptTexts texts;
  final List<AgentTool> active;
  final ToolContext ctx;
  final String system;
  final List<LibArtist> artists;
  final Map<String, Map<String, String>> remembered;

  /// 本轮命中的资源(预取块 + 工具结果)。
  final Map<String, Map<String, String>> thisTurn;

  /// 拒绝重掷已用的次数。
  var rerolls = 0;

  /// 一次尝试:从 [base] 起一跳跳问模型,直到交出能用的回复。
  Stream<AgentEvent> attempt(List<LlmMessage> base) async* {
    final msgs = List.of(base);
    // 同工具同参数的结果,一次尝试里只真跑一次
    final cache = <String, ToolOutcome>{};
    var rounds = 0;
    var fixes = 0;
    while (true) {
      final hopStart = trace?.sinceStart() ?? 0;
      var raw = '';
      await for (final c in provider.chat(
        LlmRequest(
          system: system,
          messages: msgs,
          think: req.think,
          turnStart: base.length - 1,
        ),
        client: client,
        stream: live,
      )) {
        raw = c.text;
        // 关着逐字显示时一帧都不推:气泡老老实实转圈到出结果
        if (live) yield liveDeltaOf(c);
      }
      final hop = <String, Object?>{
        't': hopStart,
        'ms': (trace?.sinceStart() ?? 0) - hopStart,
        'reply': raw,
      };
      trace?.hops.add(hop);
      if (raw.trim().isEmpty) throw AgentFailure(l10nNow.modelEmptyReply);

      final calls = active.isEmpty
          ? const ParsedToolCalls([])
          : protocol.parse(raw);
      if (!calls.isEmpty) {
        if (rounds < _maxToolRounds) {
          rounds++;
          msgs.add((role: 'assistant', content: raw, images: const []));
          hop['tool_calls'] = [
            for (final c in calls.calls) {'name': c.name, 'arguments': c.args},
            for (final b in calls.broken) {'broken': b.body, 'error': b.error},
          ];
          final results = <ToolCallResult>[];
          await for (final e in _runCalls(calls.calls, cache, results)) {
            yield e;
          }
          final message = protocol.resultMessage(results, calls.broken, texts);
          hop['tool_results'] = message;
          msgs.add((role: 'user', content: message, images: const []));
          continue;
        }
        if (fixes < _maxFixes) {
          fixes++;
          _feedback(msgs, hop, raw, texts.get('tool_limit'));
          continue;
        }
      }

      final ParsedReply parsed;
      try {
        parsed = parseReply(raw, texts);
      } on OutputFailure catch (e) {
        if (fixes >= _maxFixes) {
          throw AgentFailure(
            _clip('${l10nNow.modelBadDraw('$_maxFixes')}\n${raw.trim()}'),
          );
        }
        fixes++;
        _feedback(msgs, hop, raw, e.instruction);
        continue;
      }
      if (parsed.repairs.isNotEmpty) hop['repairs'] = parsed.repairs;
      if (parsed.reply.isEmpty && parsed.draw == null) {
        throw AgentFailure(l10nNow.modelEmptyReply);
      }
      // 重掷关着就不判拒绝,回复照常交出去
      if (parsed.draw == null && req.rerolls > 0) {
        if (refusalHit(parsed.reply, req.refusalKeywords) case final hit?) {
          hop['refusal'] = hit;
          if (rerolls >= req.rerolls) throw _Refused(hit);
          rerolls++;
          // 原地重掷:什么都不回灌,同一份上下文再要一次。拒绝的话进了上下文,
          // 模型看着自己刚说过的更容易顺着说下去
          if (live) yield const AgentDelta();
          continue;
        }
      }
      yield AgentDone(_finish(parsed));
      return;
    }
  }

  /// 同一跳的调用并行跑。同工具同参数只真跑一次,重复的给上次结果 + 提醒:
  /// 直接报错反而容易让模型换个写法再试。
  Stream<AgentEvent> _runCalls(
    List<ToolCall> calls,
    Map<String, ToolOutcome> cache,
    List<ToolCallResult> results,
  ) async* {
    final keys = [for (final c in calls) _signature(c)];
    final pending = <String, Future<_CallResult>>{};
    final repeat = <bool>[];
    for (final (i, c) in calls.indexed) {
      yield AgentToolCall(c.name, c.args);
      final cached = cache[keys[i]];
      repeat.add(cached != null || pending.containsKey(keys[i]));
      pending[keys[i]] ??= cached != null
          ? Future.value((outcome: cached, error: null))
          : _call(c);
    }
    final done = <String, _CallResult>{};
    for (final e in pending.entries) {
      done[e.key] = await e.value;
    }
    for (final (i, c) in calls.indexed) {
      final r = done[keys[i]]!;
      final outcome = r.outcome;
      if (outcome != null && !repeat[i]) {
        cache[keys[i]] = outcome;
        // 工具查到的画师串记进映射:模型照着返回的 placeholder 写,出图前要认得出来
        for (final e in (outcome.resources['artist'] ?? const {}).entries) {
          ctx.artistPlan.add(e.key, e.value);
        }
        _mergeResources(thisTurn, outcome.resources);
      }
      yield AgentToolResult(c.name, outcome?.summary ?? r.error ?? '');
      results.add(
        ToolCallResult(
          c,
          data: outcome?.data,
          error: r.error,
          repeat: repeat[i] && outcome != null,
        ),
      );
    }
  }

  Future<_CallResult> _call(ToolCall c) async {
    final tool = active.where((t) => t.name == c.name).firstOrNull;
    if (tool == null) {
      return (
        outcome: null,
        error: texts.get('unknown_tool', {'name': c.name}),
      );
    }
    try {
      return (outcome: await tool.call(ctx, c.args), error: null);
    } catch (e) {
      return (outcome: null, error: '$e');
    }
  }

  /// 回复读不出来:把它和要求重写的话接进消息里,让模型再写一次。
  void _feedback(
    List<LlmMessage> msgs,
    Map<String, Object?> hop,
    String raw,
    String instruction,
  ) {
    hop['feedback'] = instruction;
    msgs
      ..add((role: 'assistant', content: raw, images: const []))
      ..add((role: 'user', content: instruction, images: const []));
  }

  AgentResult _finish(ParsedReply parsed) {
    final placeholders = req.tools.ocPlaceholders;
    final resolve = artistResolver(ctx.artistPlan, artists);
    final expanded = expandDraw(parsed.draw, resolve);
    final draw = placeholders ? expandOcDraw(expanded, ctx.ocPlan) : expanded;
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
    return _resultOf(reply, draw, ledger);
  }
}

/// 同工具同参数的认法:参数按键排好再编码,键序不同也算同一次。
String _signature(ToolCall c) => '${c.name}:${jsonEncode(_sorted(c.args))}';

Object? _sorted(Object? v) => switch (v) {
  Map() => {
    for (final k in v.keys.map((k) => '$k').toList()..sort()) k: _sorted(v[k]),
  },
  List() => [for (final x in v) _sorted(x)],
  _ => v,
};

void _mergeResources(
  Map<String, Map<String, String>> into,
  Map<String, Map<String, String>> add,
) {
  for (final e in add.entries) {
    if (e.value.isEmpty) continue;
    (into[e.key] ??= {}).addAll(e.value);
  }
}

String _clip(String s) => s.length > AgentFailure.kMaxBody
    ? '${s.substring(0, AgentFailure.kMaxBody)}…'
    : s;

AgentResult _resultOf(
  String reply,
  Map<String, dynamic>? draw,
  Map<String, Map<String, String>> resources,
) {
  final d = draw ?? const <String, dynamic>{};
  return AgentResult(
    // 只有出图块没有正文时空着,界面按有没有出图补一句
    replyText: reply,
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

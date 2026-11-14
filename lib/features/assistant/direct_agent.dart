/// 直连自定义接口那条:在 app 里跑一遍 agent 循环,吐出与 `streamAgentPrompt`
/// 完全一样的 [AgentEvent] 流。
///
/// **下游一个字都不用改**:结果卡、导入、生成、内联出图只认这几个事件和
/// [AgentResult],不知道字节是从 Plana 后端来的还是从用户自己的模型来的。
/// (逐字显示的 [AgentDelta] 目前只有这条发 —— 服务端那条还没开流,见 runtime/backend_runtime.dart。)
///
/// 三件事和服务端那条对齐,不能自己另发明一套:
///   · **提示词**用规则主体([PresetRule]),与服务端那条是同一份:自定义过就用自定义的,
///     没有就是服务端的默认那份。只是不套外壳 —— 外壳是服务端消息编排用的;
///   · **条件段**(漫画规则这类)发不发,判据与服务端同一条([detectPromptModes]);
///     用户手动选的模式(漫画、仅自然语言)由调用方传进来,挑段规则见 [renderRules];
///   · **本地库**(画师串 / OC)的预匹配、占位符、记账、查库工具**全在手机上做**,
///     库的内容不出本机 —— 见 local_library.dart。模型用的是你自己的接口,没道理把
///     你的库传到 Plana 后端去;
///   · **服务端自己的数据**(角色索引、tag 百科、选了「+ 公共库」时的公共库)还是去后端查,
///     打 `/api/agent/prequery`、`/api/agent/tools/call`,发过去的只有查询词和资料库范围;
///   · **调用约定**(```tool_call 围栏、```nai_draw 围栏)由服务端渲染好的
///     「可用工具」块带过来,app 不拼这段 —— 加一个工具就得两边一起改的话,
///     漏一边的表现是模型调了个不存在的工具。
///
/// 与服务端那条**没有**的:降级阶梯、拒绝重掷、tag 哨兵。跑失败就是失败。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'agent_trace.dart';
import 'domain/conversation.dart' show decodeResources;
import 'assistant_settings.dart';
import 'domain/agent_event.dart';
import 'domain/agent_result.dart';
import 'llm/llm_image.dart';
import 'llm/llm_provider.dart';
import 'local_library.dart';
import 'preset_rules.dart';
import '../../l10n/l10n.dart';

/// 一轮里最多跑几跳(每跳 = 一次模型调用)。
///
/// 服务端那条也是这个量级。放大没用:模型连查三轮还定不下来,多半是它在原地
/// 打转,再给它两跳只是多烧两次钱。
const _maxHops = 4;

final _toolFence = RegExp(
  r'```[ \t]*tool_call[ \t]*\r?\n(.*?)```',
  dotAll: true,
  caseSensitive: false,
);
final _drawFence = RegExp(
  r'```[ \t]*nai_draw[ \t]*\r?\n(.*?)```',
  dotAll: true,
  caseSensitive: false,
);
final _thinkTag = RegExp(
  r'<Think>.*?</Think>',
  dotAll: true,
  caseSensitive: false,
);

// 流到一半时切正文用的几把尺子(见 [directStreamView])。整段的 [_thinkTag] 在这里
// 不够用 —— 流中途的 `<Think>` 多半还没收尾,那就得按「开标签之后全是思考」算。
final _thinkOpen = RegExp(r'<Think>', caseSensitive: false);
final _thinkClose = RegExp(r'</Think>', caseSensitive: false);
final _liveFenceOpen = RegExp(
  r'```[ \t]*(?:tool_call|nai_draw)',
  caseSensitive: false,
);

/// 收到一半的标签 / 围栏头(`<Thi`、` ```na `)。显示出来是一闪一闪的乱码,
/// 而下一帧它们本来就会被认出来,少显示一帧不亏。
///
/// 反引号后面**必须跟着字母**才算:光秃秃的 ``` 多半是代码块的收尾、`…` 是行内
/// 代码的收尾,切掉反而把好好的块拆了。
final _liveTail = RegExp(r'(?:<[A-Za-z/]{0,6}|`{1,3}[ \t]*[A-Za-z_]{1,9})$');

/// 文字里认得出的完整画师串折成占位符(映射见 [ArtistPlan.tokens])。
///
/// 画布、历史里的画师串都是当初逐字填进去的,逐字比就对得上;用户在创作页改过的对不上,
/// 原样给模型。长的先换,免得短串吃掉长串的一截。
String collapseArtistStrings(String text, Map<String, String> tokens) {
  final entries = [
    for (final e in tokens.entries)
      if (e.value.isNotEmpty) e,
  ]..sort((a, b) => b.value.length.compareTo(a.value.length));
  var out = text;
  for (final e in entries) {
    out = out.replaceAll(e.value, e.key);
  }
  return out;
}

/// 正文里的 ```nai_draw 围栏 → 画面;剥掉围栏和 `<Think>` 之后剩下的就是回复。
///
/// 抽成纯函数是因为模型写坏围栏的花样很多(写成 ```json、忘了收尾的 ```、
/// 一条回复里写两个),而写坏的表现是「这轮没出图」,和「模型决定不出图」
/// 长得一模一样 —— 不单测根本分不出来。
({String reply, Map<String, dynamic>? draw}) parseDirectReply(String raw) {
  var text = raw.replaceAll(_thinkTag, '');
  Map<String, dynamic>? draw;
  // 取**最后**一个围栏:模型偶尔会先写一版再改一版,后写的是它的结论
  for (final m in _drawFence.allMatches(text)) {
    try {
      final j = jsonDecode(m.group(1)!.trim());
      if (j is Map<String, dynamic>) draw = j;
    } catch (_) {
      // 围栏里不是合法 JSON —— 当这轮没出图,正文照常发出去
    }
  }
  text = text.replaceAll(_drawFence, '');
  return (reply: text.trim(), draw: draw);
}

/// 正文里的 ```tool_call 围栏 → 待执行的调用。解析不了的那条跳过,不整轮作废。
List<({String name, Map<String, dynamic> args})> parseToolCalls(String raw) {
  final out = <({String name, Map<String, dynamic> args})>[];
  for (final m in _toolFence.allMatches(raw)) {
    try {
      final j = jsonDecode(m.group(1)!.trim());
      if (j is! Map) continue;
      final name = j['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final args = j['arguments'];
      out.add((
        name: name,
        args: args is Map<String, dynamic> ? args : const {},
      ));
    } catch (_) {
      // 不是合法 JSON:跳过这一块。服务端那条会回灌一条「解析失败」让模型重写,
      // 直连这边不做 —— 没有重试预算的概念,多跑一跳不如让它凭已有信息作答。
    }
  }
  return out;
}

/// 自定义接口那条的系统提示:规则(已挂好工具层) + 出图格式 + 工具表。
///
/// 顺序对着服务端那条:规则主体在前,代码侧的「输出格式」「可用工具」两块在后。
/// [modes] 是预匹配判回来的,[chosen] 是用户选的模式,挑段规则见 [renderRules]。
String directSystemPrompt({
  required List<PresetRule> rules,
  required List<String>? modes,
  List<String> chosen = const [],
  required String outputFormat,
  required String toolsBlock,
}) => [
  renderRules(rules, modes, chosen: chosen),
  outputFormat.trim(),
  toolsBlock.trim(),
].where((s) => s.isNotEmpty).join('\n\n');

/// 跑一轮。事件序列与 [streamAgentPrompt] 一致,最后一个必是 [AgentDone]。
Stream<AgentEvent> streamDirectPrompt({
  required LlmProvider provider,
  required String backendBase,

  /// 空串 = 没有 Bot 授权。角色候选、服务端工具照样打后端,只是用不了公共库。
  required String sessionId,
  required String userRequest,

  /// 用户这轮附的图(原始字节)。挂在本轮 user 消息上,每一跳都带着。
  Uint8List? image,

  /// 这一轮用的规则(预设 + app 工具层,见 [withToolLayer])。按段给,条件段在这里筛。
  required List<PresetRule> rules,

  /// 出图代码块的格式说明([appOutputFormat])。服务端那条由后端代码发,这条得自己带。
  String outputFormat = '',

  /// 画布那段([当前画面提示词] 块),不带就是这轮不给画布。
  ///
  /// 和 [userRequest] 分开收、拼进同一条 user 消息 —— 与服务端 parts 的形状一致。
  /// **不能让它进预匹配**:整串画布 tag 拿去做字面匹配会把一堆无关角色匹出来
  /// (服务端那条也踩过,所以那边至今不回写 req.user_request)。
  String canvasBlock = '',
  List<Map<String, String>> history = const [],

  /// 本地的画师串库 / OC 库([libArtistsOf] / [libOcsOf] 认的形状)。只在本机用,不发出去。
  List<Map<String, dynamic>> webArtists = const [],
  List<Map<String, dynamic>> webOcs = const [],
  bool ocPlaceholders = false,

  /// 上一轮记下的沿用资源(画师串 / 占位符模式下的 OC)。本轮没点到的补进资料块,收尾时连同本轮命中的
  /// 一起并成新账本,随 [AgentResult.resources] 回去。
  Map<String, Map<String, String>> resources = const {},

  /// 设置里的「资料库范围」(`none` / `local` / `all`)。
  /// 预匹配和查库工具都吃这一项,两处必须同口径。
  String libraryScope = 'local',

  /// 用户选的模式(见 assistant_mode.dart),和预匹配判回来的一起挑段。
  List<String> chosenModes = const [],
  ThinkLevel think = ThinkLevel.auto,

  /// 逐字显示(助手设置里的开关)。关掉就是老样子:整段收完再一次出。
  bool stream = true,

  /// 调试记录:系统提示、消息、每一跳的模型原话和工具结果都记进去。
  AgentTrace? trace,
}) async* {
  final client = http.Client();
  try {
    final artists = libArtistsOf(webArtists);
    final ocs = libOcsOf(webOcs);
    final remembered = healRememberedArtists(resources, artists);

    // 后端那两块彼此不相干,并着取 —— 串着取等于在第一次模型调用前白等两个往返。
    // 附图要缩的话也在这时候缩。
    final (toolsBlock, server, img) = await (
      _fetchToolsBlock(client, backendBase, sessionId),
      _fetchServerPrequery(
        client,
        backendBase,
        sessionId,
        text: userRequest,
        libraryScope: libraryScope,
      ),
      image == null ? Future<LlmImage?>.value() : prepareLlmImage(image),
    ).wait;
    final pre = buildLocalPrequery(
      text: userRequest,
      artists: artists,
      ocs: ocs,
      remembered: remembered,
      useLibrary: libraryScope != 'none',
      publicArtists: server.artists,
      publicOcs: server.ocs,
      roleBlock: server.roleBlock,
      ocPlaceholders: ocPlaceholders,
    );
    final tokens = pre.plan.tokens;
    final ocTokens = pre.ocPlan.tokens;
    String collapseResources(String value) =>
        collapseArtistStrings(collapseArtistStrings(value, tokens), ocTokens);
    // 判模式看这一轮发出去的全部文字:用户原话、画布、历史(「上一轮画过分格图」)。
    // 资料块不算 —— 画师串里带个 comic 不代表这轮在画漫画。
    final modes = detectPromptModes([
      userRequest,
      canvasBlock,
      for (final h in history) h['content'] ?? '',
    ]);
    final system =
        directSystemPrompt(
          rules: rules,
          modes: modes,
          chosen: chosenModes,
          outputFormat: outputFormat,
          toolsBlock: toolsBlock,
        ) +
        (ocPlaceholders
            ? '\n\n[OC 占位符模式]\n$kOcBlockNote。search_character 返回的 OC tags 也是占位符；不要猜测或展开其内容。'
            : '');
    trace
      ?..prequery = {
        'block': pre.block,
        'this_turn': pre.thisTurn,
        'modes': modes,
        'artist_placeholders': tokens,
        if (ocPlaceholders) 'oc_placeholders': ocTokens,
      }
      ..system = system;

    // 消息流:历史 + 本轮。工具结果以 user 文本回灌,与服务端那条同一种形状。
    // 用户那段 + 画布拼成一条 user 消息,资料块跟在后面。
    // 用户输入、画布和历史里认得出的完整资源折成占位符 —— 模型看到的「自己上次写的」就是占位符,
    // 不会照着抄完整串(服务端那条在 run_chat_with_retries 里做同一件事)。
    final msgs = <LlmMessage>[
      for (final h in history)
        (
          role: h['role'] ?? 'user',
          content: collapseResources(h['content'] ?? ''),
          image: null,
        ),
      (
        role: 'user',
        content: [
          ocPlaceholders ? collapseResources(userRequest) : userRequest,
          collapseResources(canvasBlock),
          pre.block,
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
        LlmRequest(system: system, messages: msgs, think: think),
        client: client,
        stream: stream,
      )) {
        raw = c.text;
        // 关着逐字显示时一帧都不推:气泡老老实实转圈到出结果
        if (stream) yield liveDeltaOf(c);
      }
      if (raw.trim().isEmpty) throw AgentFailure(l10nNow.modelEmptyReply);
      final hopRec = <String, Object?>{
        't': hopStart,
        'ms': (trace?.sinceStart() ?? 0) - hopStart,
        'reply': raw,
      };
      trace?.hops.add(hopRec);
      final calls = parseToolCalls(raw);
      if (calls.isEmpty || hop == _maxHops - 1) {
        final parsed = parseDirectReply(raw);
        final resolve = artistResolver(pre.plan, artists);
        if (libraryScope == 'all' && parsed.draw != null) {
          await _resolvePublicArtists(
            client,
            backendBase,
            sessionId,
            draw: parsed.draw!,
            resolve: resolve,
            plan: pre.plan,
          );
        }
        final draw = ocPlaceholders
            ? expandOcDraw(expandDraw(parsed.draw, resolve), pre.ocPlan)
            : expandDraw(parsed.draw, resolve);
        final reply = ocPlaceholders
            ? namesInOcReply(namesInReply(parsed.reply, resolve), pre.ocPlan)
            : namesInReply(parsed.reply, resolve);
        final ledger = mergeLedger(
          remembered,
          pre.thisTurn,
          draw,
          rememberOcs: ocPlaceholders,
        );
        trace?.event('final', {
          'reply': reply,
          'draw': parsed.draw,
          if (draw != parsed.draw) 'draw_expanded': draw,
          'resources': ledger,
        });
        yield AgentDone(_toResult(reply, draw, ledger));
        return;
      }

      msgs.add((role: 'assistant', content: raw, image: null));
      hopRec['tool_calls'] = [
        for (final c in calls) {'name': c.name, 'arguments': c.args},
      ];
      final chunks = <String>[];
      for (final c in calls) {
        yield AgentToolCall(c.name, c.args);
        String summary;
        Object? result;
        try {
          result = await _runTool(
            client,
            backendBase,
            sessionId,
            c,
            artists: artists,
            ocs: ocs,
            libraryScope: libraryScope,
          );
          if (c.name == 'search_artist' || c.name == 'random_artist') {
            rememberToolArtists(pre.plan, result);
          }
          if (ocPlaceholders && c.name == 'search_character') {
            if (result is List) {
              for (final row in result) {
                if (row is Map && row['source'] == 'oc') {
                  final name = '${row['name'] ?? ''}'.trim();
                  final tags = '${row['tags'] ?? ''}'.trim();
                  if (name.isNotEmpty && tags.isNotEmpty) {
                    pre.thisTurn['oc']![name] = tags;
                  }
                }
              }
            }
            result = maskOcToolResults(result, pre.ocPlan);
          }
          summary = result is List ? '${result.length} 条' : '已返回';
        } catch (e) {
          result = null;
          summary = '$e';
        }
        yield AgentToolResult(c.name, summary);
        chunks.add(
          '[${c.name}] ${result == null ? "执行失败:$summary" : jsonEncode(result)}',
        );
      }
      hopRec['tool_results'] = chunks.join('\n\n');
      msgs.add((
        role: 'user',
        content:
            '[tool_result 共 ${calls.length} 条] 以下是你上一条回复里 tool_call 的执行结果。'
            '请基于结果给出**最终回复**(不要再重复调用同样的工具)。\n\n'
            '${chunks.join("\n\n")}',
        image: null,
      ));
    }
  } finally {
    client.close();
  }
}

AgentResult _toResult(
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
    // 并好的账本原样带出去。**不能回空** —— 调用方是拿最新那条 AI
    // 消息的账本发下一轮的,回空等于把之前记着的画风冲掉。
    resources: resources,
  );
}

/// 服务端那份预匹配:[角色候选](角色索引在服务端),选了「+ 公共库」时再加上公共库
/// 命中的画师串 / OC。
///
/// **只发这句话和资料库范围** —— 本地库、账本、画布一样不带,本地那份在
/// [buildLocalPrequery] 里做。「不使用」时服务端什么都不给,不打。
/// 拿不到就空着走 —— 没有候选模型还能靠工具自己查,为此整轮失败不划算。
Future<
  ({String roleBlock, Map<String, String> artists, Map<String, String> ocs})
>
_fetchServerPrequery(
  http.Client c,
  String base,
  String sessionId, {
  required String text,
  required String libraryScope,
}) async {
  const empty = (
    roleBlock: '',
    artists: <String, String>{},
    ocs: <String, String>{},
  );
  if (base.isEmpty || libraryScope == 'none' || text.trim().isEmpty) {
    return empty;
  }
  try {
    final r = await c
        .post(
          Uri.parse('$base/api/agent/prequery'),
          headers: {'Content-Type': 'application/json', ..._auth(sessionId)},
          body: jsonEncode({
            'user_request': text,
            'library_scope': libraryScope,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return empty;
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map) return empty;
    // 本地库没发过去,服务端命中的画师串 / OC 只可能来自公共库
    final hits = decodeResources(j['this_turn']);
    return (
      roleBlock: pickBlock(j['block']?.toString() ?? '', kRoleBlock),
      artists: hits['artist'] ?? const <String, String>{},
      ocs: hits['oc'] ?? const <String, String>{},
    );
  } catch (_) {
    return empty;
  }
}

/// 画面里还有认不出的占位符(工具在上一轮查到的公共库画师)→ 按编号去公共库查一次,
/// 查到的记进映射。只在「+ 公共库」时调,发过去的只有编号。
Future<void> _resolvePublicArtists(
  http.Client c,
  String base,
  String sessionId, {
  required Map<String, dynamic> draw,
  required ArtistResolver resolve,
  required ArtistPlan plan,
}) async {
  final missing = {
    for (final t in drawTexts(draw))
      for (final m in artistTokenRe.allMatches(t))
        if (resolve(m[1]!) == null) m[1]!,
  };
  if (missing.isEmpty) return;
  try {
    rememberToolArtists(
      plan,
      await _serverTool(c, base, sessionId, (
        name: 'search_artist',
        args: {'artist_ids': missing.toList()},
      ), 'all'),
    );
  } catch (_) {
    // 查不到就算了:认不出的占位符还原时会被删掉
  }
}

/// 「可用工具」块。拿不到就返回空串 —— 没有工具照样能出词,只是查不了资料;
/// 为此整轮失败不划算。
Future<String> _fetchToolsBlock(
  http.Client c,
  String base,
  String sessionId,
) async {
  if (base.isEmpty) return '';
  try {
    final r = await c
        .get(Uri.parse('$base/api/agent/tools'), headers: _auth(sessionId))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return '';
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return (j is Map ? j['block']?.toString() : null) ?? '';
  } catch (_) {
    return '';
  }
}

/// 执行一次工具调用。
///
/// 查本地库的(search_artist、random_artist,search_character 的 OC 那半)在本机做,库不出本机;
/// 服务端自己的数据 —— 角色索引、tag 百科、选了「+ 公共库」时的公共库 —— 去后端查,
/// 发过去的只有工具参数。两边都有的,本地的排前面。
Future<Object?> _runTool(
  http.Client c,
  String base,
  String sessionId,
  ({String name, Map<String, dynamic> args}) call, {
  required List<LibArtist> artists,
  required List<LibOc> ocs,
  required String libraryScope,
}) async {
  final mine = libraryScope != 'none';
  final withPublic = libraryScope == 'all';

  // 本地已经查到东西时,后端那半挂了不该让整个工具失败
  Future<List<Object?>> remote({required bool quiet}) async {
    try {
      final r = await _serverTool(c, base, sessionId, call, libraryScope);
      return r is List ? r : const [];
    } catch (_) {
      if (quiet) return const [];
      rethrow;
    }
  }

  switch (call.name) {
    case 'search_artist':
      final local = mine
          ? searchLocalArtists(artists, call.args)
          : const <Map<String, dynamic>>[];
      if (!withPublic) return local;
      final seen = {
        for (final a in local) ...[
          '${a['id']}'.toUpperCase(),
          '${a['name']}'.toUpperCase(),
        ],
      };
      return [
        ...local,
        for (final a in await remote(quiet: local.isNotEmpty))
          if (a is Map &&
              !seen.contains('${a['id']}'.toUpperCase()) &&
              !seen.contains('${a['name']}'.toUpperCase()))
            a,
      ];
    case 'random_artist':
      final count = intArg(call.args['count'], 1).clamp(1, 5);
      final pool = <Object?>[
        if (mine)
          for (final a in artists) artistToolEntry(a),
        if (withPublic) ...await remote(quiet: mine && artists.isNotEmpty),
      ]..shuffle();
      return pool.take(count).toList();
    case 'search_character':
      final args = call.args;
      if ('${args['query'] ?? ''}'.trim().isEmpty &&
          '${args['origin'] ?? ''}'.trim().isEmpty) {
        return const <Object?>[];
      }
      final local = mine
          ? searchLocalOcs(ocs, args)
          : const <Map<String, dynamic>>[];
      final limit = intArg(args['limit'], 30).clamp(1, 200);
      return [
        ...local,
        ...await remote(quiet: local.isNotEmpty),
      ].take(limit).toList();
    default:
      return _serverTool(c, base, sessionId, call, libraryScope);
  }
}

/// 后端代调一个工具。**不带本地库** —— 服务端拿到的只有工具参数和资料库范围。
Future<Object?> _serverTool(
  http.Client c,
  String base,
  String sessionId,
  ({String name, Map<String, dynamic> args}) call,
  String libraryScope,
) async {
  if (base.isEmpty) throw AgentFailure('没有后端地址,查不了资料');
  final r = await c
      .post(
        Uri.parse('$base/api/agent/tools/call'),
        headers: {'Content-Type': 'application/json', ..._auth(sessionId)},
        body: jsonEncode({
          'name': call.name,
          'arguments': call.args,
          'library_scope': libraryScope,
        }),
      )
      .timeout(const Duration(seconds: 30));
  final body = utf8.decode(r.bodyBytes);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw AgentFailure.http(r.statusCode, body);
  }
  final j = jsonDecode(body);
  return j is Map ? j['result'] : null;
}

/// 有 Bot 授权才带会话;没有就匿名打,后端对匿名调用不给公共库。
Map<String, String> _auth(String sessionId) =>
    sessionId.isEmpty ? const {} : {'Authorization': 'Bearer $sessionId'};

/// 流到一半的原文 → 气泡里该显示的两块。
///
/// 纯函数,每帧拿全量原文重算:`</Think>` 收尾那一刻正文会整段挪位,增量式拼接
/// 得为这一下单独留一套回退。
///
/// 正文到第一个 ```tool_call / ```nai_draw 围栏为止 —— 围栏里是给机器看的 JSON,
/// 而且收完才解析得了。普通的 ``` 代码块照留(回复里列 tag 会用到)。
/// `<Think>` 段(含还没收尾的)整段划到思考那边。
({String body, String think}) directStreamView(String raw) {
  final think = <String>[];
  final body = StringBuffer();
  var pos = 0;
  for (final m in _thinkOpen.allMatches(raw)) {
    if (m.start < pos) continue; // 上一段 <Think> 内部的,不重复处理
    body.write(raw.substring(pos, m.start));
    final close = _thinkClose.firstMatch(raw.substring(m.end));
    if (close == null) {
      think.add(raw.substring(m.end)); // 还没收尾:后面全算思考
      pos = raw.length;
      break;
    }
    think.add(raw.substring(m.end, m.end + close.start));
    pos = m.end + close.end;
  }
  if (pos < raw.length) body.write(raw.substring(pos));
  var text = body.toString();
  final fence = _liveFenceOpen.firstMatch(text);
  if (fence != null) text = text.substring(0, fence.start);
  return (
    body: text.replaceFirst(_liveTail, '').trim(),
    think: think.join('\n').trim(),
  );
}

/// 模型这一刻的全量回复 → 气泡里实时显示的那一帧。
AgentDelta liveDeltaOf(LlmText c) {
  final v = directStreamView(c.text);
  return AgentDelta(
    text: v.body,
    reasoning: [
      c.reasoning.trim(),
      v.think,
    ].where((s) => s.isNotEmpty).join('\n'),
  );
}

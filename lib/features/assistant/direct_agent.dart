/// 直连自定义接口那条:在 app 里跑一遍 agent 循环,吐出与 `streamAgentPrompt`
/// 完全一样的 [AgentEvent] 流。
///
/// **下游一个字都不用改**:结果卡、导入、生成、内联出图只认这几个事件和
/// [AgentResult],不知道字节是从 Plana 后端来的还是从用户自己的模型来的。
/// (逐字显示的 [AgentDelta] 目前只有这条发 —— 服务端那条还没开流,见 agent_stream。)
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

import '../../core/net/agent_stream.dart';
import '../../core/net/backend_client.dart';
import '../../core/util/image_ops.dart' show styleRefResizeJpg;
import 'agent_trace.dart';
import 'assistant_models.dart' show decodeResources;
import 'assistant_settings.dart';
import 'custom_endpoint.dart';
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

/// 附图:MIME + base64。
typedef DirectImage = ({String mime, String data});

/// 发给模型的一条消息。[image] 只挂在本轮用户那条上 —— 历史里的图不回带,
/// 与服务端那条一致。
typedef DirectMsg = ({String role, String content, DirectImage? image});

/// 按文件头认图片类型,认不出按 PNG —— 与服务端 `_sniff_image_mime` 同一张表。
/// 标签和字节对不上时有的接口整条拒收,而相册里挑的多半是 JPEG。
String imageMimeOf(Uint8List b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
  if (at(0, 'GIF87a'.codeUnits) || at(0, 'GIF89a'.codeUnits)) {
    return 'image/gif';
  }
  return 'image/png';
}

/// 附图超过这个字节数就先缩再发。
///
/// 卡的是 Claude:单张图 base64 超过 5MB 整条请求被拒,放大过的图随便就过线。
/// 服务端那条原样转发,失败了还有「剥图重试」兜着;直连没有重试,一次就得发得出去。
const kDirectImageMaxBytes = 3500000;

/// 附图 → 发给模型的那份。超过 [kDirectImageMaxBytes] 的按长边 2048 转 JPEG,
/// 画面内容看得清就够写提示词了。转不动(解不开的格式)就原样发,让接口自己判。
Future<DirectImage> prepareDirectImage(Uint8List bytes) async {
  if (bytes.length > kDirectImageMaxBytes) {
    try {
      final jpg = await styleRefResizeJpg(bytes, maxDim: 2048, quality: 90);
      return (mime: 'image/jpeg', data: base64Encode(jpg));
    } catch (_) {}
  }
  return (mime: imageMimeOf(bytes), data: base64Encode(bytes));
}

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
  required CustomEndpoint endpoint,
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
      image == null ? Future<DirectImage?>.value() : prepareDirectImage(image),
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
    final msgs = <DirectMsg>[
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
      final buf = StringBuffer();
      await for (final d in directModelStream(
        client,
        endpoint,
        system: system,
        msgs: msgs,
        think: think,
        stream: stream,
        out: buf,
      )) {
        yield d;
      }
      final raw = buf.toString();
      if (raw.trim().isEmpty) throw BackendException(l10nNow.modelEmptyReply);
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
  if (base.isEmpty) throw BackendException('没有后端地址,查不了资料');
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
  final j = jsonDecode(utf8.decode(r.bodyBytes));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    final detail =
        (j is Map ? j['detail']?.toString() : null) ?? '${r.statusCode}';
    throw BackendException(detail);
  }
  return j is Map ? j['result'] : null;
}

/// 有 Bot 授权才带会话;没有就匿名打,后端对匿名调用不给公共库。
Map<String, String> _auth(String sessionId) =>
    sessionId.isEmpty ? const {} : {'Authorization': 'Bearer $sessionId'};

/// 两帧之间至少隔这么久。快的模型一秒吐几十个 token,一个 token 推一帧等于每秒
/// 几十次整块重建(气泡里是按围栏分块的富文本);60ms 一帧看着仍然是连续在写。
const _liveFrameMs = 60;

/// 打一次模型,边收边吐。
///
/// 每帧 [AgentDelta] 带的是**到此刻为止**的正文与思考(整块替换,理由见那边),
/// 整段原文写进 [out] —— 这条链路的产出是「一段回复 + 一个围栏」,围栏收完才解析
/// 得了,所以**流只管显示**,解析照旧在 [parseDirectReply] / [parseToolCalls]。
///
/// [timeout] 是「等响应头」「两帧之间」「等整段」各自的上限;null = 不限,等到用户取消。
///
/// 中转不认流式(回的不是 `text/event-stream`)时,收完整个 body 按老路解析,
/// 只是没有逐字效果 —— 不能因为这个就让人用不了。
Stream<AgentDelta> directModelStream(
  http.Client c,
  CustomEndpoint e, {
  required String system,
  required List<DirectMsg> msgs,
  required ThinkLevel think,
  required StringBuffer out,
  Duration? timeout,

  /// 关掉就是老样子:一个 POST 收完整段,一帧都不推。
  bool stream = true,
}) async* {
  // 路径可配(中转改路径是常事),Gemini 那条还把模型名写在路径里、开流还要换方法名
  // —— 都由 CustomEndpoint 处理,这儿不再各拼各的。
  final uri = stream ? e.chatStreamUri : e.chatUri;
  final (headers, body) = directRequest(
    e,
    system: system,
    msgs: msgs,
    think: think,
    stream: stream,
  );
  final req = http.Request('POST', uri)
    ..headers.addAll(
      e.withHeaders({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        ...headers,
      }),
    )
    ..bodyBytes = utf8.encode(jsonEncode(body));

  final noReply = BackendException(
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
    resp = await limited(c.send(req));
  } on BackendException {
    rethrow;
  } catch (_) {
    throw BackendException(l10nNow.cantConnectHost(uri.host));
  }

  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    final raw = await readAll(resp);
    throw BackendException(_errorOf(_tryJson(raw), resp.statusCode));
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
    final raw = await readAll(resp);
    final text = extractReplyText(e.format, _tryJson(raw));
    if (text.isNotEmpty || !stream || !raw.contains('data:')) {
      out.write(text); // 空的话由调用方报「模型回了一段空的」
      // 关着开关时一帧都不推:气泡就该老老实实转圈到出结果
      if (text.isNotEmpty && stream) yield _liveDelta(out, StringBuffer());
      return;
    }
    // 类型写着 json、身子却是一串 SSE 帧 —— 有的中转就这德行。按帧收,
    // 只是整段一起到,没有逐字效果。
    lines = Stream.fromIterable(const LineSplitter().convert(raw));
  }

  final reason = StringBuffer();
  var lastFrame = 0;
  await for (final line in lines) {
    // `event:` 行与 `:` 心跳不看:三家的 data 自带类型,光看 data 就够
    if (!line.startsWith('data:')) continue;
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') continue;
    final frame = _tryJson(data);
    // Claude 的报错是流中间的一帧,不是 HTTP 状态码
    if (frame is Map && frame['type'] == 'error') {
      throw BackendException(_errorOf(frame, resp.statusCode));
    }
    final d = directDelta(e.format, frame);
    if (d.text.isEmpty && d.reasoning.isEmpty) continue;
    out.write(d.text);
    reason.write(d.reasoning);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastFrame < _liveFrameMs) continue;
    lastFrame = now;
    yield _liveDelta(out, reason);
  }
  // 收尾补一帧:最后几个字多半还卡在上面那道攒帧里
  yield _liveDelta(out, reason);
}

AgentDelta _liveDelta(StringBuffer raw, StringBuffer reason) {
  final v = directStreamView(raw.toString());
  return AgentDelta(
    text: v.body,
    reasoning: [
      reason.toString().trim(),
      v.think,
    ].where((s) => s.isNotEmpty).join('\n'),
  );
}

Object? _tryJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null; // 不是 JSON:当没有错误体,按状态码报
  }
}

/// 流式响应的一帧 → 这一帧新增的字。三家形状各不相同,抽出来单测 —— 认错字段的
/// 表现是「一路空白、最后整段蹦出来」,跟模型自己慢分不出来。
///
/// 思考在三家都是正文之外的另一个字段,所以分两路回:
///   · OpenAI:`delta.reasoning_content`(DeepSeek 那套)或 `delta.reasoning`(OpenRouter)
///   · Gemini:`parts[]` 里 `thought` 为真的那几段
///   · Claude:`thinking_delta`
({String text, String reasoning}) directDelta(
  AgentApiFormat format,
  Object? frame,
) {
  const none = (text: '', reasoning: '');
  if (frame is! Map) return none;
  switch (format) {
    case AgentApiFormat.openai:
      final choices = frame['choices'];
      if (choices is! List || choices.isEmpty) return none;
      final first = choices.first;
      if (first is! Map) return none;
      final d = first['delta'];
      // 老式补全接口没有 delta,只有 text
      if (d is! Map) {
        return (
          text: first['text'] is String ? first['text'] as String : '',
          reasoning: '',
        );
      }
      final r = d['reasoning_content'] ?? d['reasoning'];
      return (
        text: d['content'] is String ? d['content'] as String : '',
        reasoning: r is String ? r : '',
      );
    case AgentApiFormat.google:
      final cands = frame['candidates'];
      if (cands is! List || cands.isEmpty) return none;
      final first = cands.first;
      if (first is! Map) return none;
      final parts = (first['content'] as Map?)?['parts'];
      if (parts is! List) return none;
      final text = StringBuffer();
      final think = StringBuffer();
      for (final p in parts) {
        if (p is! Map || p['text'] is! String) continue;
        (p['thought'] == true ? think : text).write(p['text']);
      }
      return (text: text.toString(), reasoning: think.toString());
    case AgentApiFormat.anthropic:
      final d = frame['delta'];
      if (d is! Map) return none;
      return switch (d['type']) {
        'text_delta' => (
          text: d['text'] is String ? d['text'] as String : '',
          reasoning: '',
        ),
        'thinking_delta' => (
          text: '',
          reasoning: d['thinking'] is String ? d['thinking'] as String : '',
        ),
        // message_delta(停止原因)这类也带 delta,但不带字
        _ => none,
      };
  }
}

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

/// 一次模型调用的请求头与请求体。三家的形状各不相同,抽出来单测 ——
/// 附图字段写错的表现是「模型说没看到图」,和它自己看走眼分不出来。
///
/// 带图的那条 content 从字符串换成分段数组,**图在前、字在后**
/// (Claude 与 Gemini 的文档都建议单图时这么摆,OpenAI 不挑)。
(Map<String, String>, Map<String, dynamic>) directRequest(
  CustomEndpoint e, {
  required String system,
  required List<DirectMsg> msgs,
  required ThinkLevel think,

  /// 开流式。Gemini 不在体里开 —— 它换的是路径,见 [CustomEndpoint.chatStreamUri]。
  bool stream = false,
}) {
  final key = e.apiKey.trim();
  return switch (e.format) {
    AgentApiFormat.openai => (
      {'Authorization': 'Bearer $key'},
      {
        'model': e.model,
        'messages': [
          {'role': 'system', 'content': system},
          for (final m in msgs)
            {
              'role': m.role,
              'content': switch (m.image) {
                final i? => [
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:${i.mime};base64,${i.data}'},
                  },
                  if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
                ],
                null => m.content,
              },
            },
        ],
        if (stream) 'stream': true,
        ...thinkFields(AgentApiFormat.openai, think),
      },
    ),
    AgentApiFormat.google => (
      {'x-goog-api-key': key},
      {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          for (final m in msgs)
            {
              // Gemini 只认 user / model 两种
              'role': m.role == 'assistant' ? 'model' : 'user',
              'parts': [
                if (m.image case final i?)
                  {
                    'inlineData': {'mimeType': i.mime, 'data': i.data},
                  },
                if (m.image == null || m.content.isNotEmpty)
                  {'text': m.content},
              ],
            },
        ],
        ...thinkFields(AgentApiFormat.google, think, model: e.model),
      },
    ),
    AgentApiFormat.anthropic => (
      {'x-api-key': key, 'anthropic-version': '2023-06-01'},
      {
        'model': e.model,
        // Anthropic 必填,且没有"不限"这一档。开了思考还得**大于**思考预算,
        // 否则整条请求会被拒:那笔预算是从 max_tokens 里切出去的。
        'max_tokens': 4096 + _anthropicBudget(think),
        'system': system,
        'messages': [
          for (final m in msgs)
            {
              'role': m.role,
              'content': switch (m.image) {
                final i? => [
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': i.mime,
                      'data': i.data,
                    },
                  },
                  if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
                ],
                null => m.content,
              },
            },
        ],
        if (stream) 'stream': true,
        ...thinkFields(AgentApiFormat.anthropic, think),
      },
    ),
  };
}

/// Anthropic 的思考预算(token)。0 = 不开。下限是它自己规定的 1024。
int _anthropicBudget(ThinkLevel l) => switch (l) {
  ThinkLevel.auto || ThinkLevel.off => 0,
  ThinkLevel.low => 1024,
  ThinkLevel.medium => 4096,
  ThinkLevel.high => 8192,
  ThinkLevel.ultra => 16384,
};

/// Gemini 的思考旋钮按代分两种:2.x 及更早给 token 预算(`thinkingBudget`),
/// 3 及以后(含 Gemini 4 的 Argon / Carbon / Hydrogen)给档位(`thinkingLevel`)。
/// 发错一种会被 400 拒掉,两种一起发也拒。
enum GeminiThinking { budget, level }

/// 按模型名认是哪一种。不带 gemini 字样的(中转挂的别家模型)按预算发。
GeminiThinking geminiThinkingOf(String model) {
  final m = model.trim().toLowerCase();
  if (RegExp(r'gemini-[12](?:[.\-]|$)').hasMatch(m)) {
    return GeminiThinking.budget;
  }
  if (RegExp(r'gemini|argon|carbon|hydrogen').hasMatch(m)) {
    return GeminiThinking.level;
  }
  return GeminiThinking.budget;
}

/// 只有 Gemini 4 Hydrogen 有 XHIGH。
bool _geminiHasXHigh(String model) => model.toLowerCase().contains('hydrogen');

/// 思考等级 → 各家请求体里的那几个字段。
///
/// 三家的旋钮完全不是一回事:OpenAI 给的是档位字符串,Claude 要 **token 预算**,
/// Gemini 按代分预算和档位(见 [geminiThinkingOf])。
/// [ThinkLevel.auto] 不发档位,让模型/服务方用自己的默认;Gemini 3 及以后照样带
/// `includeThoughts`,让流里有思考摘要可显示。
/// 中转不认这些字段时通常直接忽略,所以发了也不至于把请求打死。
Map<String, dynamic> thinkFields(
  AgentApiFormat format,
  ThinkLevel level, {
  String model = '',
}) {
  if (format == AgentApiFormat.google &&
      geminiThinkingOf(model) == GeminiThinking.level) {
    return {
      'generationConfig': {
        'thinkingConfig': {
          'includeThoughts': true,
          if (level != ThinkLevel.auto)
            // 没有「关」:MINIMAL Gemini 4 不收,3.x 上多轮还要带思考签名,统一落到 LOW
            'thinkingLevel': switch (level) {
              ThinkLevel.medium => 'MEDIUM',
              ThinkLevel.high => 'HIGH',
              ThinkLevel.ultra => _geminiHasXHigh(model) ? 'XHIGH' : 'HIGH',
              _ => 'LOW',
            },
        },
      },
    };
  }
  if (level == ThinkLevel.auto) return const {};
  switch (format) {
    case AgentApiFormat.openai:
      return {
        'reasoning_effort': switch (level) {
          // OpenAI 两头都封顶:没有「关」,minimal 是最低;也没有「超高」,
          // high 是最高 —— 所以这两档各自撞在端点上,不是写漏了。
          ThinkLevel.off => 'minimal',
          ThinkLevel.low => 'low',
          ThinkLevel.high || ThinkLevel.ultra => 'high',
          _ => 'medium',
        },
      };
    case AgentApiFormat.google:
      return {
        'generationConfig': {
          'thinkingConfig': {
            'thinkingBudget': switch (level) {
              ThinkLevel.off => 0,
              ThinkLevel.low => 1024,
              ThinkLevel.high => 16384,
              ThinkLevel.ultra => 24576,
              _ => 8192,
            },
            if (level != ThinkLevel.off) 'includeThoughts': true,
          },
        },
      };
    case AgentApiFormat.anthropic:
      final budget = _anthropicBudget(level);
      // 「关」在 Anthropic 这边就是不带 thinking 字段
      if (budget == 0) return const {};
      return {
        'thinking': {'type': 'enabled', 'budget_tokens': budget},
      };
  }
}

/// 选的档位在这个接口上没有、发送时换成了别的档,说一句换成了什么;原样发的返回 null。
String? thinkLevelNote(CustomEndpoint e, ThinkLevel level) {
  switch (e.format) {
    case AgentApiFormat.openai:
      return switch (level) {
        ThinkLevel.off => l10nNow.thinkNoOffFormat,
        ThinkLevel.ultra => l10nNow.thinkNoUltraFormat,
        _ => null,
      };
    case AgentApiFormat.google:
      if (geminiThinkingOf(e.model) != GeminiThinking.level) return null;
      return switch (level) {
        ThinkLevel.off => l10nNow.thinkNoOffModel,
        ThinkLevel.ultra when !_geminiHasXHigh(e.model) =>
          l10nNow.thinkNoUltraModel,
        _ => null,
      };
    case AgentApiFormat.anthropic:
      return null;
  }
}

/// 发一条最短的对话,确认地址、Key、模型、格式对得上。成功返回用时;
/// 失败抛 [BackendException],消息是给用户看的原话。测试等两分钟为止。
Future<Duration> testEndpoint(CustomEndpoint e, {http.Client? client}) async {
  final own = client == null;
  final c = client ?? http.Client();
  final sw = Stopwatch()..start();
  try {
    final out = StringBuffer();
    await directModelStream(
      c,
      e,
      system: 'Reply with the single word OK.',
      msgs: const [(role: 'user', content: 'ping', image: null)],
      think: ThinkLevel.auto,
      timeout: const Duration(seconds: 120),
      out: out,
      stream: false,
    ).drain<void>();
    if (out.toString().trim().isEmpty) {
      throw BackendException(l10nNow.replyUnreadable);
    }
    return sw.elapsed;
  } finally {
    if (own) c.close();
  }
}

/// 三家的响应 → 正文。认错字段的表现是「模型回了一段空的」,和真的空回
/// 长得一样,所以抽出来单测。
String extractReplyText(AgentApiFormat format, Object? body) {
  if (body is! Map) return '';
  switch (format) {
    case AgentApiFormat.openai:
      final choices = body['choices'];
      if (choices is! List || choices.isEmpty) return '';
      final first = choices.first;
      if (first is! Map) return '';
      final msg = first['message'];
      if (msg is Map) return msg['content']?.toString() ?? '';
      return first['text']?.toString() ?? '';
    case AgentApiFormat.google:
      final cands = body['candidates'];
      if (cands is! List || cands.isEmpty) return '';
      final first = cands.first;
      if (first is! Map) return '';
      final parts = (first['content'] as Map?)?['parts'];
      if (parts is! List) return '';
      return [
        for (final p in parts)
          // 思考摘要(thought: true)不算正文
          if (p is Map && p['text'] != null && p['thought'] != true)
            p['text'].toString(),
      ].join();
    case AgentApiFormat.anthropic:
      final content = body['content'];
      if (content is! List) return '';
      return [
        for (final p in content)
          if (p is Map && p['type'] == 'text') p['text']?.toString() ?? '',
      ].join();
  }
}

/// 错误体 → 给用户看的一句话。三家都把话装在 `error` 里,但形状不同。
String _errorOf(Object? body, int status) {
  if (body is Map) {
    final err = body['error'];
    if (err is Map) {
      final m = err['message']?.toString();
      if (m != null && m.isNotEmpty) return m;
    }
    if (err is String && err.isNotEmpty) return err;
    final m = body['message']?.toString();
    if (m != null && m.isNotEmpty) return m;
  }
  return l10nNow.modelReturned('$status');
}

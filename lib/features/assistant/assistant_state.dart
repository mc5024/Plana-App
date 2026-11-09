/// AI 助手的状态机:跑一轮对话、把结果写进创作页、撤销、会话归档。
///
/// 写回规则只有一条 —— **这一轮 AI 给了绘图产出([AgentResult.hasDraw]),才写
/// 创作页、才出结果卡、才点亮导航角标**。纯聊天轮三样都不做。这条规则是整套
/// 设计的地基:每轮都弹一张卡,卡就退化成背景板了。
///
/// **读画布恒为一次性**:发送前点一下「引用创作页」([send] 的 `withCanvas`),
/// 发完就回到关,没有「总是引用」那档设置。写画布默认也要点「导入」
/// ([applyProposal]),但可以在设置里改成自动([AssistantSettings.autoImport])。
///
/// 两个方向不对称是有意的:自动写进去的词,下一轮要是又被自动读回来当基底,
/// 用户改的和 AI 改的就分不清谁覆盖谁了。读那一头每轮现按一次,这种咬合不成立。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart' show kAppVersion;
import '../../core/auth/bot_session_store.dart';
import '../../core/net/agent_stream.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/backend_config.dart';
import '../../core/store/app_stores.dart';
import '../generate/agent_chars.dart';
import '../generate/canvas_state.dart';
import '../generate/char_position.dart';
import '../gallery/gallery_state.dart' show galleryProvider;
import '../generate/gen_modules.dart';
import '../generate/generate_state.dart';
import '../generate/generation_controller.dart'
    show GenOutcome, generationProvider;
import '../generate/models.dart'
    show GenerateState, isAnimaModel, isKreaModel, isNai5Model;
import '../generate/prompt_sections.dart'
    show SectionImport, importPromptsInto, joinSections;
import '../inspiration/public_tags.dart' show publicTagsProvider;
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import 'agent_model.dart';
import 'agent_trace.dart';
import 'assistant_mode.dart';
import 'assistant_models.dart';
import 'assistant_settings.dart';
import 'custom_endpoint.dart' show CustomEndpoint;
import 'direct_agent.dart';
import 'preset_rules.dart';
import 'session_store.dart';

/// 正在跑时发的那几句:排着,上一轮跑完依次发出去。不落盘。
///
/// 发出去时那条用户消息沿用这里的 [id],对话里的气泡原地转正。
class QueuedAsk {
  const QueuedAsk({
    required this.id,
    required this.text,
    required this.at,
    this.image,
    this.withCanvas = false,
  });

  final String id;
  final String text;

  /// 排进来的时刻(UNIX 毫秒)。
  final int at;
  final Uint8List? image;

  /// 这一句要不要引用创作页。读的是发出去那一刻的画布。
  final bool withCanvas;
}

class AssistantState {
  const AssistantState({
    this.msgs = const [],
    this.sessions = const [],
    this.running = false,
    this.queue = const [],
    this.liveTools = const [],
    this.stage = '',
    this.liveText = '',
    this.liveReasoning = '',
    this.changedUnseen = false,
    this.jobs = const {},
    this.mode = AssistantMode.normal,
  });

  /// 当前这段对话。
  final List<AssistantMsg> msgs;

  /// 输入框上方选着的模式。跟着对话走:开新对话回到「无」,打开历史回到它最后用的
  /// 那个(见 [conversationMode])。
  ///
  /// 不单独落盘:发出去的每条用户消息都记着当时的模式,重启后从最后一条读回来;
  /// 选了还没发就重启,丢了也无妨。
  final AssistantMode mode;

  /// 已归档的历史(新的在前)。
  final List<ArchivedSession> sessions;

  final bool running;

  /// 排着等发的几句(先进先出)。停下或出错后不自动接着发,等用户再按一次发送。
  /// 队首那句在用户消息真追进 [msgs] 的同一刻才出队。
  final List<QueuedAsk> queue;

  /// 正在跑的那一轮已经查了哪些资料。跑完并进 [AssistantMsg.tools],这里清空。
  final List<ToolTrace> liveTools;

  /// 等待期的阶段文案。一轮要 20~40 秒,光转圈会让人以为死了。
  final String stage;

  /// 正在写的这一跳的正文(自填接口那条才有,见 [AgentDelta])。每帧整块替换,
  /// 不是往后拼;换一跳会从头再来。跑完并进 [AssistantMsg.text],这里清空。
  final String liveText;

  /// 同上,模型这一跳的思考过程。跑完**不留**:最终消息里本来就不带它。
  final String liveReasoning;

  /// 正在为某条消息出的图:消息 id → 出图任务 id。**只在「图片显示在对话里」
  /// 开着时才记** —— 关了的话页面已经切去图库看进度了,对话里再画一条是重复。
  ///
  /// 不落盘:任务 id 是本次运行内的序号,重启就没了,而那时候任务本来也没了。
  final Map<String, String> jobs;

  /// 有写回、但用户还没切去创作页看过 —— 底部导航「创作」上那颗角标。
  /// 独立 tab 没有「改动就在眼皮底下」的同屏感,这颗点是全部的补偿。
  final bool changedUnseen;

  bool get isEmpty => msgs.isEmpty;

  AssistantState copyWith({
    List<AssistantMsg>? msgs,
    List<ArchivedSession>? sessions,
    bool? running,
    List<QueuedAsk>? queue,
    List<ToolTrace>? liveTools,
    String? stage,
    String? liveText,
    String? liveReasoning,
    bool? changedUnseen,
    Map<String, String>? jobs,
    AssistantMode? mode,
  }) => AssistantState(
    msgs: msgs ?? this.msgs,
    sessions: sessions ?? this.sessions,
    running: running ?? this.running,
    queue: queue ?? this.queue,
    liveTools: liveTools ?? this.liveTools,
    stage: stage ?? this.stage,
    liveText: liveText ?? this.liveText,
    liveReasoning: liveReasoning ?? this.liveReasoning,
    changedUnseen: changedUnseen ?? this.changedUnseen,
    jobs: jobs ?? this.jobs,
    mode: mode ?? this.mode,
  );
}

/// 当前显示模型 → 后端 agent 认的**图片生成模型**档位。
///
/// 服务端只看三件事:是不是 `anima`、是不是 `krea`、是不是以 `nai_v5` 开头,
/// 其余一律回落 4.5(见 `agent_router/router.py:resolve_preset_and_backend`)。
/// 所以这里的后缀写什么都行,分档正确即可。
///
/// 不发这个字段的话服务端恒用 4.5 的预设 —— 对 krea 来说基本等于没写提示词。
String agentImageModel(String displayModel) {
  if (isAnimaModel(displayModel)) return 'anima';
  if (isKreaModel(displayModel)) return 'krea';
  if (isNai5Model(displayModel)) return 'nai_v5_full';
  return 'nai_v45_full';
}

/// 这个图片模型能不能用 AI 助手。
///
/// Anima / Krea 一律不行:那两条走服务端 Modal,提示词体系与 NAI 完全不同
/// (krea 吃的是连贯自然语言),而助手的预设、工具、`nai_draw` 围栏都是按 NAI 写的。
/// 硬跑也出得来东西,只是对那两个模型基本等于没写 —— 挡住比让人对着一个看不出
/// 哪儿不对的结果琢磨强。将来自定义接口那条也照这个判,内置预设同样只有 NAI 两份。
bool assistantSupportsModel(String displayModel) =>
    !isAnimaModel(displayModel) && !isKreaModel(displayModel);

/// 一份提议**拿去生成**时发出的状态。纯函数,不碰任何 provider。
///
/// **沿用创作页的只有参数、Vibe 和主提示词分区。** 正向、负向按 [mode] 写进
/// 主提示词(与导入同一个 [importPromptsInto],「直接生成」和「导入后再生成」
/// 出同一张图);角色分区一律只认 AI 这份,没给就是空;模型、尺寸、采样、
/// 种子照创作页现在的来。
///
/// 四个图像模块里只留 Vibe:它管的是画风氛围,套在谁的提示词上都成立。
/// 角色参考、图生图、重绘不留 —— 这三样是**冲着某张具体的图、某个具体的角色**
/// 配的,AI 写了一个全新的画面,再拿画布上那张底图去图生图、那块遮罩去重绘、
/// 那个角色去做参考,出来的只会是两边拧在一起的东西。
///
/// 原先是「拿画布当底、AI 给了的提示词字段盖上去」,于是 AI 没写角色分区时,
/// 出图会带上画布里原有的角色 —— 用户没点过引用,AI 也没见过它们,图里却有。
///
/// 坐标开关虽然挂在参数里,却是**角色分区的一部分**:它决定分区里那几个坐标
/// 算不算数。分区只认 AI 的,开关也跟着 AI 走 —— 沿用画布上开着的开关,
/// AI 没摆位时那几个默认空格就会被当成用户指定的站位发出去。
GenerateState proposalSendState(
  GenerateState canvas,
  DrawProposal r,
  SectionImport mode, {
  required String Function() newId,
}) {
  final built = buildAgentCharacters(
    [
      for (final c in r.characters)
        (
          name: c.name,
          positive: c.positive,
          negative: c.negative,
          position: c.position,
        ),
    ],
    model: canvas.params.model,
    newId: newId,
  );
  return importPromptsInto(
    canvas,
    r.positive,
    r.negative,
    mode,
    newId: newId,
  ).copyWith(
    characters: built.chars,
    charRefs: const [],
    img2img: null,
    inpaint: null,
    params: canvas.params.copyWith(useCoords: built.placed),
  );
}

/// 提议里用到的库内画师串,把它们的负面补进负向(去重,同灵感页加画风)。
///
/// 画师串是占位符换回来的,内容逐字不动,按整串出现在正向(含角色正向)里认。
String withArtistNegatives(DrawProposal r, Iterable<TagEntry> artists) {
  final texts = [r.positive, for (final c in r.characters) c.positive];
  final used = [
    for (final e in artists)
      if (e.negative.trim().isNotEmpty &&
          e.positive.trim().isNotEmpty &&
          texts.any((t) => t.contains(e.positive.trim())))
        e,
  ];
  return used.isEmpty ? r.negative : appendTagNegatives(r.negative, used);
}

/// 创作页有没有可带给 AI 的东西。全空时「引用创作页」那颗按钮没意义,置灰。
///
/// 角色要连正向词一起看:一个刚加出来、名字都还没填的空角色带过去等于噪音。
bool canvasHasContent(GenerateState g) =>
    canvasPositive(g).trim().isNotEmpty ||
    canvasNegative(g).trim().isNotEmpty ||
    g.characters.any((c) => c.enabled && c.positive.trim().isNotEmpty);

/// 引用创作页时发给 AI 的正负向:主体和启用的分区拼好的整串,与出图时一致。
String canvasPositive(GenerateState g) =>
    joinSections(g.sections, g.prompt, positive: true);
String canvasNegative(GenerateState g) =>
    joinSections(g.sections, g.negativePrompt, positive: false);

final assistantProvider = NotifierProvider<AssistantNotifier, AssistantState>(
  AssistantNotifier.new,
);

/// 历史里保留 `nai_draw` 围栏的 AI 轮数。取舍见 [historyFenceIds]。
const _keepFences = 2;

class AssistantNotifier extends Notifier<AssistantState> {
  StreamSubscription<AgentEvent>? _sub;

  /// 发号作废:取消 / 又发了一次时,回来的旧事件对不上号,整轮丢弃。
  int _seq = 0;

  /// [send] 已经进门、还没把 running 立起来(前面在等授权、存图)。
  bool _starting = false;

  bool get _busy => state.running || _starting;

  int _idSeq = 0;

  AssistantStore get _store => ref.read(appStoresProvider).assistant;

  /// 当前对话每一轮的调试记录(见 [AgentTrace]),助手设置里导出用。
  /// 开新对话、打开历史会话时清掉 —— 导出的是「当前对话」。
  List<AgentTrace> _traces = const [];

  /// 正在跑的那一轮的记录。收尾(完成、失败、停下)时进 [_traces]。
  AgentTrace? _liveTrace;

  @override
  AssistantState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    final s = _store;
    _traces = s.initialTraces;
    return AssistantState(
      msgs: s.initialCurrent,
      sessions: s.initialSessions,
      mode: conversationMode(s.initialCurrent),
    );
  }

  /// 换模式。只影响之后发的消息,已经发出去的那几轮不动。
  void setMode(AssistantMode mode) {
    if (state.mode == mode) return;
    _set(state.copyWith(mode: mode), persist: false);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  AssistantMsg? _msg(String id) =>
      state.msgs.where((m) => m.id == id).firstOrNull;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// 先改状态(立即生效),再尽力落盘。[persist] = false 用于纯运行态
  /// (工具轨迹、阶段文案)的改动,不值得为它写盘。
  void _set(AssistantState next, {bool persist = true}) {
    state = next;
    if (persist) _store.schedule(next.msgs, next.sessions);
  }

  // ---- 排队 ----

  /// 发一句。正在跑或前面还排着别的,就排到队尾,按顺序一句句发。
  Future<void> submit(
    String text, {
    Uint8List? image,
    bool withCanvas = false,
  }) {
    if (text.trim().isEmpty && image == null) return Future.value();
    _set(
      state.copyWith(
        queue: [
          ...state.queue,
          QueuedAsk(
            id: _newId(),
            text: text,
            at: _now,
            image: image,
            withCanvas: withCanvas,
          ),
        ],
      ),
      persist: false,
    );
    return _drain();
  }

  /// 停下 / 出错之后接着发排着的。
  Future<void> resumeQueue() => _drain();

  void unqueue(String id) => _set(
    state.copyWith(
      queue: [
        for (final q in state.queue)
          if (q.id != id) q,
      ],
    ),
    persist: false,
  );

  Future<void> _drain() {
    if (_busy || state.queue.isEmpty) return Future.value();
    final next = state.queue.first;
    return send(
      next.text,
      image: next.image,
      withCanvas: next.withCanvas,
      queuedId: next.id,
    );
  }

  // ---- 发一轮 ----

  /// 已完成回合的对话历史。**这条链路服务端不存历史**,不回带就等于每轮都是新对话。
  ///
  /// AI 轮要带上当初那个 `nai_draw` 围栏(见 [replayText])。只回正文的话模型看不见
  /// 自己上一轮写了什么,「把头发改成金色」得从头推一遍,连角色和画风都要重新查
  /// 一次工具 —— 用户看到的就是「怎么又查了一遍」。
  ///
  /// 但**只留最近 [_keepFences] 个**。围栏装的是完整提示词不是增量,再往前翻是同一幅画的
  /// 旧版本,按每个一两百 token 算,一屏历史堆下来比整份预设还大,而且每个请求都付一遍。
  ///
  /// 为什么不是只留一个:最新那条说的是**现在**什么样,而「还是把刚才那个加回来吧」
  /// 指的是上一版 —— 只留一个的话模型看不见刚被去掉的是什么。再往前的只留正文,
  /// 正文本来就写着「给你加了氛围词」这类交代,读起来不断。
  ///
  /// bot 那条是每轮都堆的(它的历史落在服务端,那边另有取舍),这儿不跟。
  ///
  /// 失败的那一轮连同它的用户提问一起丢掉:留一条没有回复的 user 轮在历史里,
  /// 下一轮模型会以为自己上次没答上来。
  ///
  /// 轮数按助手设置里的「上下文轮数」截([recentTurns])。两条路都在这儿截:自定义接口
  /// 没人替它截;后端那条服务端也按同一个数截(随请求发过去),两边对得上。
  ///
  /// **不往这里补「用户手改了什么」的合成消息。** 试过一版,撤了:用户要让模型
  /// 看见自己改成什么样,勾一下「引用创作页」就是了,那份是全量的、也不会说错;
  /// 合成消息反而会跟用户打架 —— 它写死「别改回去」,而用户下一句完全可能就是
  /// 「还是把刚才那个加回来吧」。
  List<Map<String, String>> _history() {
    final withFence = historyFenceIds(state.msgs, _keepFences);
    final out = <Map<String, String>>[];
    String? pendingUser;
    for (final m in state.msgs) {
      switch (m.role) {
        case MsgRole.user:
          pendingUser = m.text;
        case MsgRole.ai:
          if (pendingUser != null) {
            out.add({'role': 'user', 'content': pendingUser});
            pendingUser = null;
          }
          final replay = withFence.contains(m.id) ? replayText(m) : m.text;
          if (replay.trim().isNotEmpty) {
            out.add({'role': 'assistant', 'content': replay});
          }
        case MsgRole.error:
          pendingUser = null;
      }
    }
    return recentTurns(out, assistantSettingsOf(ref).historyTurns);
  }

  /// 当前画面的角色,转成后端要的形状。
  ///
  /// **站位要换算**:app 里存的是网格 id(`B2`)或自由坐标,后端认的是归一化
  /// `"x,y"` 四位小数。直接发 `B2` 模型看不懂,构图信息等于没给。
  List<Map<String, dynamic>> _charsForAgent(GenerateState g) => [
    for (final c in g.characters)
      if (c.enabled)
        {
          'name': c.name,
          'positive': c.positive,
          'negative': c.negative,
          'position': switch (resolveCharacterCenter(c.position)) {
            final p? => formatFreeformPosition(p.x, p.y),
            null => '',
          },
        },
  ];

  /// 用户自己那份画师串 / OC(灵感页的库)。
  ///
  /// **发上去之后服务端就只认这份**,不再并进它本机那份公共库 —— 预查询和
  /// `search_artist` / `search_character` 里的 OC 那半边,口径都变成「用户手里有的」。
  /// 公共库里有一万个画师串,而用户想用的是自己收藏的那几十个;拿全量去和
  /// 一句话做匹配,捞上来的多半是他没见过的东西。
  ///
  /// 字段名按服务端 `_load_artists_from_web` / `_load_ocs_from_web` 认的那几个填。
  /// 画师的 `id` 就是名字(`A1` 这种编号在公共库里本来就是主键),预查询按编号
  /// 精确比对的正是它。
  ///
  /// **要 await**:灵感页没被打开过的话这个 provider 还没读过盘,同步取到的是
  /// null,整份库就悄悄没发出去 —— 而服务端见「一份都没发」会回落它自己那份
  /// 公共库,于是冷启动后的第一句话用的是公共库,和用户选的「本地库」正好相反。
  Future<({List<Map<String, dynamic>> artists, List<Map<String, dynamic>> ocs})>
  _webLibrary() async {
    TagLibraryState? lib;
    try {
      lib = await ref.read(tagLibraryProvider.future);
    } catch (_) {
      lib = null; // 库文件读坏了:这轮不带库,总比整轮发不出去强
    }
    if (lib == null) {
      return (
        artists: const <Map<String, dynamic>>[],
        ocs: const <Map<String, dynamic>>[],
      );
    }
    return (
      artists: [
        for (final e in lib.entries)
          if (e.category == TagCategory.artist && e.positive.trim().isNotEmpty)
            {'id': e.name, 'name': e.name, 'prompt': e.positive},
      ],
      ocs: [
        for (final e in lib.entries)
          if (e.category == TagCategory.character &&
              e.positive.trim().isNotEmpty)
            {
              // 没发布过的本地 OC 没有 en_name,拿本地 id 顶上(服务端只拿它当键)
              'en_name': e.publicId ?? e.id,
              'zh_name': e.name,
              'zh_aliases': e.aliases,
              'tag_group': e.positive,
            },
      ],
    );
  }

  /// 当前画面那一块,直连那条自己拼。
  ///
  /// 走后端时这块由 `_build_current_prompt_context` 生成并入用户那段(见那边);
  /// 直连没有那条通路,所以在这儿照同一个形状拼一份 —— 字段名必须一致
  /// (positive / negative / characters + position),内置预设里讲的就是这几个名字。
  String _canvasBlock(GenerateState g) {
    final pos = canvasPositive(g), neg = canvasNegative(g);
    final lines = <String>[
      '请在下面这份提示词的基础上改:没让你动的部分原样留着;characters 连 '
          'position 一起带回来,不带会把我摆好的构图打乱。除非我明说要全新主题 / '
          '重做,否则都按这份改。',
      '[当前画面提示词]',
      'positive: ${pos.trim().isEmpty ? "(空)" : pos}',
      'negative: ${neg.trim().isEmpty ? "(空)" : neg}',
    ];
    final chars = _charsForAgent(g);
    if (chars.isNotEmpty) {
      lines.add('characters:');
      for (final c in chars) {
        lines.add('  - name: ${c['name']}');
        final pos = (c['positive'] as String? ?? '').trim();
        lines.add('    positive: ${pos.isEmpty ? "(空)" : pos}');
        final neg = (c['negative'] as String? ?? '').trim();
        if (neg.isNotEmpty) lines.add('    negative: $neg');
        final at = (c['position'] as String? ?? '').trim();
        if (at.isNotEmpty) lines.add('    position: $at');
      }
    }
    return lines.join('\n');
  }

  /// 发一轮。[image] 是用户带的图(原始字节),会 base64 发给模型并存进 blob。
  ///
  /// [withCanvas] = 把创作页**当前**的正向/负向/角色一并发过去,让 AI 在它上面改。
  /// **默认不发**,与「导入」同一个道理:AI 碰用户的画布,两个方向都得用户按一下。
  /// 自动发的毛病在于「画个赛博朋克少女」这种明明想从头来的请求,也会被预设里那句
  /// 「把它作为基线改写」拽着把旧词拖进来,而用户看不出是谁干的。
  ///
  /// 不发时后端那块 `current_prompt_context` 整块不拼(三项全空即视为没有),
  /// 所以这里传空串/空表就够,不需要另加开关字段。
  ///
  /// 模式用输入框上方现在选着的([AssistantState.mode]),重新生成也是 —— 按钮上写着
  /// 什么就按什么发。「纯文本格式」看助手设置里现在的开关。
  ///
  /// [queuedId] = 发的是队里那一句:用户消息用它当 id,并在同一刻出队。发之前就被拦下
  /// (没授权、模型不支持)的话它留在队里。
  Future<void> send(
    String text, {
    Uint8List? image,
    bool withCanvas = false,
    String? queuedId,
  }) async {
    if (_busy) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && image == null) return;
    _starting = true;
    try {
      await _send(
        trimmed,
        image: image,
        withCanvas: withCanvas,
        queuedId: queuedId,
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _send(
    String trimmed, {
    Uint8List? image,
    required bool withCanvas,
    String? queuedId,
  }) async {
    // 界面已经挡了(见 _ModelGate),这儿再挡一道:自动生成、重试这些不经过界面。
    final model = ref.read(generateProvider).params.model;
    if (!assistantSupportsModel(model)) {
      _pushError(
        'AI 助手暂不支持 Anima / Krea,去创作页换成 NAI 再来',
        AssistErrorKind.unknown,
      );
      return;
    }

    final base = ref.read(backendBaseProvider).value ?? '';
    final sid = (await ref.read(botSessionProvider.future))?.sessionId ?? '';
    // 选了自定义接口就在本机跑 agent 循环,否则打 Plana 后端那条 SSE。
    // 没有 Bot 授权时后端那条只能用免费模型:列表得先到货才知道是哪条。
    final endpoint = ref.read(assistantEndpointProvider);
    if (sid.isEmpty && endpoint == null) {
      try {
        await ref.read(agentModelsProvider.future);
      } catch (_) {}
      if (ref.read(assistantModelKeyProvider).isEmpty) {
        _pushError('内置模型暂未开放,先在顶部选一个自定义接口', AssistErrorKind.auth);
        return;
      }
    }

    // 历史必须在把这条 user 消息追进去**之前**取,否则本轮问题会重复一遍。
    final history = _history();

    // 画布是空的就当没勾 —— 记在消息上的也是这个结果,免得气泡挂着「引用了创作页」
    // 而实际什么都没发出去。
    final g = ref.read(generateProvider);
    final canvas = withCanvas && canvasHasContent(g);
    // 回复回来时人可能已经切去别的画布,自动导入 / 出图只对发问时这张生效
    final sourceCanvasId = ref.read(canvasWorkspaceProvider).activeId;
    final picked = state.mode;
    final noDraw = assistantSettingsOf(ref).noDraw;

    String? hash;
    String? b64;
    if (image != null) {
      b64 = base64Encode(image);
      hash = await _store.putImage(image);
    }

    final seq = ++_seq;
    _set(
      state.copyWith(
        msgs: [
          ...state.msgs,
          AssistantMsg(
            id: queuedId ?? _newId(),
            role: MsgRole.user,
            text: trimmed,
            at: _now,
            imageHash: hash,
            withCanvas: canvas,
            mode: picked,
          ),
        ],
        queue: [
          for (final q in state.queue)
            if (q.id != queuedId) q,
        ],
        running: true,
        liveTools: const [],
        liveText: '',
        liveReasoning: '',
        // 一开始是模型在想,不是在查资料:大多数轮次根本不调工具,开场就报「查资料」
        // 是在说一件还没发生、多半也不会发生的事。真调了工具再切过去(见下面的事件)。
        stage: '思考中',
      ),
    );
    // 记录跟着这条提问一起开:下面还要等灵感库、规则这些,这期间按了停止也得收尾。
    // 设置快照等那些取齐了再补上。
    final trace = AgentTrace(
      startedAt: _now,
      route: endpoint != null
          ? AgentTrace.routeCustom
          : AgentTrace.routeBackend,
      userText: trimmed,
      settings: <String, Object?>{},
    );
    _liveTrace = trace;

    // 「资料库范围」:默认只认用户自己那份库,选了「+ 公共库」才让服务端并进去,
    // 选了「不使用」则一份都不发、也让服务端别回落公共库。
    // 预匹配、工具代查、直连那条都吃同一个值 —— 分开传迟早有一处漏掉。
    // 公共库要 Bot 授权,没授权时按本地库发(后端对匿名调用也只给本地库)。
    final scope = effectiveLibraryScope(
      assistantSettingsOf(ref).libraryScope,
      botAuthorized: sid.isNotEmpty,
    );
    // 公共库画师串的负面收尾时要用(见 [_libArtists]),先取着,不等它
    if (scope == LibraryScope.all) {
      unawaited(
        ref
            .read(publicTagsProvider(TagCategory.artist).future)
            .then((_) {}, onError: (_) {}),
      );
    }
    final lib = scope == LibraryScope.none
        ? (
            artists: const <Map<String, dynamic>>[],
            ocs: const <Map<String, dynamic>>[],
          )
        : await _webLibrary();
    final tools = <ToolTrace>[];

    // 两条路([endpoint] 在上面取的)吐的是同一串事件、同一个 AgentResult,
    // 下面这段 listen 不用分叉。
    final imageModel = agentImageModel(g.params.model);
    // 规则主体:自定义过就用自定义的。**要 await** —— 和灵感库同一个坑,偏好没读完
    // 同步取到的是 null,会悄悄当成「没自定义」发出去。
    final family = rulesFamilyOf(imageModel);
    List<PresetRule>? custom;
    try {
      custom = (await ref.read(
        rulesLibraryProvider.future,
      )).customRulesFor(family);
    } catch (_) {
      custom = null;
    }
    // 模式靠预设里那一段:在用的预设没写就什么都不加 —— 比如 NAI5 的对话里选了漫画,
    // 创作页又换成了 4.5,而 4.5 的预设里没有漫画段。消息上照旧记着用户选的那个。
    // 「无」不用查:走服务端又没自定义规则时,这一查就是白取一份默认规则。
    // 认的是和界面同一份([assistantModesProvider]):按钮上显示成「无」,就什么都不加。
    var effective = picked;
    if (modeNeedsPresetSection(picked)) {
      Set<AssistantMode> supported;
      try {
        supported = await ref.read(assistantModesProvider(family).future);
      } catch (_) {
        supported = const {AssistantMode.normal};
      }
      if (!supported.contains(picked)) effective = AssistantMode.normal;
    }
    final modeKeys = assistantModeKeys(effective);
    trace.settings.addAll({
      ..._modelSnapshot(endpoint),
      'image_model': imageModel,
      'rules': '${family.name} · ${custom == null ? '默认' : '自定义'}',
      'mode': effective.name,
      'mode_keys': modeKeys,
      'no_draw': noDraw,
      'library_scope': scope.name,
      'oc_placeholders':
          endpoint != null && assistantSettingsOf(ref).ocPlaceholders,
      'history_turns': assistantSettingsOf(ref).historyTurns,
      'history_entries': history.length,
      'with_canvas': canvas,
      if (image != null) 'image_bytes': image.length,
    });
    final stream = endpoint != null
        ? streamDirectPrompt(
            endpoint: endpoint,
            backendBase: base,
            sessionId: sid,
            userRequest: trimmed,
            image: image,
            // 直连没有外壳,规则直接当系统提示:在用的预设(没自定义就是服务端默认那份)
            // 挂上 app 的工具层,再补上出图格式 —— 这两样后端那条由服务端自己发
            rules: withToolLayer(
              custom ??
                  await defaultRules(family, backendBase: base, sessionId: sid),
              await appToolLayer(),
            ),
            outputFormat: await appOutputFormat(),
            // 直连没有独立的「当前画面」通道,画布当一段文本发过去
            canvasBlock: canvas ? _canvasBlock(g) : '',
            history: history,
            // 库只在本机用:预匹配、占位符、记账、查库工具都在 app 里做,
            // 不发给后端(见 local_library.dart)
            webArtists: lib.artists,
            webOcs: lib.ocs,
            ocPlaceholders: assistantSettingsOf(ref).ocPlaceholders,
            resources: latestResources(state.msgs),
            libraryScope: libraryScopeWire(scope),
            chosenModes: modeKeys,
            think: assistantSettingsOf(ref).thinkLevel,
            stream: assistantSettingsOf(ref).stream,
            trace: trace,
          )
        : streamAgentPrompt(
            baseUrl: base,
            sessionId: sid,
            userRequest: trimmed,
            // 空串 = 用后端的全局默认。用户在顶栏选过才带 key 出去。
            model: ref.read(assistantModelKeyProvider),
            imageModel: imageModel,
            imageB64: b64,
            history: history,
            historyTurns: assistantSettingsOf(ref).historyTurns,
            currentPositive: canvas ? canvasPositive(g) : '',
            currentNegative: canvas ? canvasNegative(g) : '',
            currentCharacters: canvas ? _charsForAgent(g) : const [],
            webArtists: lib.artists,
            webOcs: lib.ocs,
            // 沿用中的画风 / OC:预匹配逐条消息做,用户这轮没再提「A1」块就不出现,
            // 出处断在那儿。账本由服务端算、客户端存(这条链路没有服务端会话)。
            resources: latestResources(state.msgs),
            libraryScope: libraryScopeWire(scope),
            // 没自定义就不发,服务端用它自己那份(自带工具说明,永远是最新的);
            // 自定义的预设只讲写提示词,挂上 app 的工具层再发 —— 服务端换掉的是
            // 整段规则主体,不挂的话它自己那份工具说明也跟着被换没了
            presetRules: [
              if (custom != null)
                for (final r in withToolLayer(custom, await appToolLayer()))
                  r.toJson(),
            ],
            modes: modeKeys,
            onRequest: (body) => trace.request = body,
            onEvent: trace.event,
          );
    // 上面几处 await(读规则、灵感库,慢的时候十几秒)期间可能已经点了停止,
    // 或者又发了一条:这一轮作废。两个流都是 listen 才发请求,在这儿拦住就不花钱,
    // 也不会把新一轮刚挂上的订阅掐掉。
    if (seq != _seq) return;
    await _sub?.cancel();
    if (seq != _seq) return;
    _sub = stream.listen(
      (ev) {
        if (seq != _seq) return;
        switch (ev) {
          case AgentToolCall(:final name, :final args):
            // 参数里的「查什么」当场留下 —— tool_result 只回计数,过了这一刻
            // 就再也拿不到「查的是普拉娜」这件事了。
            tools.add(ToolTrace(name: name, subject: toolSubject(args)));
            _set(
              state.copyWith(liveTools: List.of(tools), stage: '查资料中'),
              persist: false,
            );
          case AgentToolResult(:final name, :final summary):
            final i = tools.lastIndexWhere((t) => t.name == name && !t.done);
            if (i >= 0) {
              tools[i] = tools[i].copyWith(summary: summary);
            } else {
              tools.add(ToolTrace(name: name, summary: summary));
            }
            _set(
              // 结果回来之后模型接着想:可能再查一轮,可能出图,也可能只是回答个问题
              // (「芙兰是谁」查完就答,没有提示词可写)—— 所以不报「写提示词」
              state.copyWith(liveTools: List.of(tools), stage: '思考中'),
              persist: false,
            );
          case AgentDelta(:final text, :final reasoning):
            // 整块替换,不往后拼(见 AgentDelta 的说明)。这一段不落盘 ——
            // 半截话没有存的价值,真存了下次启动还得当完整回复显示。
            _set(
              state.copyWith(liveText: text, liveReasoning: reasoning),
              persist: false,
            );
          case AgentDegraded():
            tools.add(
              const ToolTrace(name: kDegradedTool, summary: '已降级到安全模式'),
            );
            _set(state.copyWith(liveTools: List.of(tools)), persist: false);
          case AgentDone(:final result):
            _finish(
              result,
              tools,
              canvas,
              picked,
              noDraw,
              sourceCanvasId,
              scope,
            );
        }
      },
      onError: (Object e) {
        if (seq != _seq) return;
        // 没授权被后端拒了:多半是那条免费模型刚被收回,重取列表换一条
        if (sid.isEmpty &&
            endpoint == null &&
            e is BackendException &&
            (e.status == 401 || e.status == 403)) {
          ref.invalidate(agentModelsProvider);
        }
        final msg = e is BackendException ? e.message : '$e';
        _pushError(msg, _kindOf(e));
      },
      onDone: () {
        if (seq != _seq) return;
        // final 已经把 running 收掉了;还开着说明流是空落地的。
        if (state.running) {
          _pushError('AI 这轮没跑完就断了,再试一次', AssistErrorKind.network);
        }
      },
      cancelOnError: true,
    );
  }

  AssistErrorKind _kindOf(Object e) {
    if (e is! BackendException) return AssistErrorKind.unknown;
    if (e.status == 401 || e.status == 403) return AssistErrorKind.auth;
    if (e.message.contains('没等到回复') ||
        e.message.contains('超时') ||
        e.message.contains('无法连接')) {
      return AssistErrorKind.network;
    }
    if (e.message.contains('拒绝') || e.message.contains('白卷')) {
      return AssistErrorKind.refusal;
    }
    return AssistErrorKind.unknown;
  }

  /// 「用的哪个模型」,调试记录用。自定义接口只记名字、格式、模型和域名,不记密钥。
  Map<String, Object?> _modelSnapshot(CustomEndpoint? e) => e == null
      // 空串 = 后端的全局默认
      ? {'model': ref.read(assistantModelKeyProvider)}
      : {
          'endpoint': {
            'name': e.name,
            'format': e.format.name,
            'model': e.model,
            'host': e.chatUri.host,
          },
        };

  /// 这一轮的调试记录收尾:[error] 为 null 是正常完成。
  void _finishTrace(String? error) {
    final t = _liveTrace;
    if (t == null) return;
    _liveTrace = null;
    t
      ..endedAt = _now
      ..error = error;
    final all = [..._traces, t];
    _traces = all.length > AssistantStore.maxTraces
        ? all.sublist(all.length - AssistantStore.maxTraces)
        : all;
    unawaited(_store.saveTraces(_traces));
  }

  void _clearTraces() {
    _liveTrace = null;
    if (_traces.isEmpty) return;
    _traces = const [];
    unawaited(_store.saveTraces(const []));
  }

  /// 当前对话记了几轮。
  int get traceCount => _traces.length;

  /// 助手设置里「导出对话记录」的全文,见 [renderTraceExport]。
  String exportTrace() => renderTraceExport(
    traces: _traces,
    settings: {
      ..._modelSnapshot(ref.read(assistantEndpointProvider)),
      ...assistantSettingsOf(ref).toJson()..remove('introVersion'),
    },
    nextHistory: _history(),
    resources: latestResources(state.msgs),
    messages: [for (final m in state.msgs) m.toJson()],
    now: _now,
    appVersion: kAppVersion,
  );

  void _pushError(String msg, AssistErrorKind kind) {
    _finishTrace(msg);
    _sub?.cancel();
    _sub = null;
    _set(
      state.copyWith(
        msgs: [
          ...state.msgs,
          AssistantMsg(
            id: _newId(),
            role: MsgRole.error,
            text: msg,
            at: _now,
            errorKind: kind,
          ),
        ],
        running: false,
        liveTools: const [],
        stage: '',
        liveText: '',
        liveReasoning: '',
      ),
    );
  }

  /// 补负面用的画师串条目:本地库,选了「+ 公共库」再并上已经取到的公共库。
  List<TagEntry> _libArtists(LibraryScope scope) => [
    for (final e in ref.read(tagLibraryProvider).value?.entries ?? const [])
      if (e.category == TagCategory.artist) e,
    if (scope == LibraryScope.all)
      ...?ref.read(publicTagsProvider(TagCategory.artist)).value,
  ];

  void _finish(
    AgentResult r,
    List<ToolTrace> tools,
    bool canvas,
    AssistantMode mode,
    bool noDraw,
    String sourceCanvasId,
    LibraryScope scope,
  ) {
    _finishTrace(null);
    // **不写创作页**。AI 的产出先当成一份「提议」挂在这条消息上,用户在结果卡上
    // 点「导入」才落地(或者不导入、直接拿它生成)。
    //
    // 早先是自动写回的,改掉是因为:画布是用户和 AI 共写的,自动覆盖会在用户
    // 眼皮底下吃掉他刚改的东西 —— 而「等待期改过」这类情况又只能靠事后提示补救。
    // 现在卡上实时按当前画面算差异,导入前就看得见会变成什么样。
    // 剥画师串标记:发了 web_artists 的那些轮,服务端会把正向词里认出来的画师串
    // 包成 `<<artist:名字:内容>>` 给 web 渲染芯片。app 不渲染芯片,不剥就把尖括号
    // 原样写进用户的提示词了。分角色那几段同理 —— 包装函数只碰全局正向,
    // 但这儿一并过一道,将来它扩到角色也不用再想起这件事。
    final stripped = r.hasDraw
        ? DrawProposal(
            positive: stripArtistMarkers(r.positive),
            negative: r.negative,
            characters: [
              for (final c in r.characters)
                AgentCharacter(
                  name: c.name,
                  positive: stripArtistMarkers(c.positive),
                  negative: c.negative,
                  position: c.position,
                ),
            ],
          )
        : null;
    final draw = stripped == null || scope == LibraryScope.none
        ? stripped
        : DrawProposal(
            positive: stripped.positive,
            negative: withArtistNegatives(stripped, _libArtists(scope)),
            characters: stripped.characters,
          );
    final text = r.replyText.trim().isNotEmpty
        ? r.replyText.trim()
        : (draw != null ? '改好了喵~' : '这轮没什么可说的喵…');
    final id = _newId();
    _set(
      state.copyWith(
        msgs: [
          ...state.msgs,
          AssistantMsg(
            id: id,
            role: MsgRole.ai,
            text: text,
            at: _now,
            tools: List.of(tools),
            draw: draw,
            resources: r.resources,
            // 结果卡据此定差异基线(见 AssistantMsg.withCanvas)
            withCanvas: canvas,
            mode: mode,
            // 「纯文本格式」这一轮的提议显示成纯文本(见 AssistantMsg.promptAsText)
            noDraw: noDraw,
          ),
        ],
        running: false,
        liveTools: const [],
        stage: '',
        liveText: '',
        liveReasoning: '',
      ),
    );
    // 纯文本那种只给复制:不自动导入、不自动出图
    if (draw != null && !noDraw) _autoAfterDraw(id, sourceCanvasId);
    unawaited(_drain());
  }

  /// 「总是读写创作页」/「出词后自动生成」这两个开关的落点。
  ///
  /// 顺序是**先导入再出图**:两件事各自独立(不导入也能照 AI 那份出图),但
  /// 如果两个开关都开着,先导入能让画布和这张图对得上 —— 出完图回创作页一看
  /// 提示词还是旧的,那才叫见鬼。
  ///
  /// 发问之后切去了别的画布,两样都不自动做:回复是照着原来那张要的,自动写进
  /// (或照它出图到)眼下这张都不对。提议照常挂在消息上,用户自己点导入 / 生成。
  void _autoAfterDraw(String msgId, String sourceCanvasId) {
    if (ref.read(canvasWorkspaceProvider).activeId != sourceCanvasId) return;
    final settings = assistantSettingsOf(ref);
    if (settings.autoImport) applyProposal(msgId);
    if (settings.autoGenerate) unawaited(generateFrom(msgId));
  }

  /// 拿某条消息的提议出一张图。**这是出图的唯一入口** —— 结果卡上的「生成」和
  /// 自动生成都走它,免得「要不要切页、要不要把图挂回对话」两处各写一遍。
  ///
  /// 显示成纯文本的那种提议([AssistantMsg.promptAsText])不出图。界面上本来就没有
  /// 按钮,这里再挡一道:以后加的入口也都得从这儿过。
  Future<void> generateFrom(String msgId) async {
    if (_msg(msgId)?.promptAsText ?? false) return;
    final sent = previewSendState(msgId);
    if (sent == null) return;
    final inline = assistantSettingsOf(ref).inlineImage;
    // 出图前记下库里最新那张,回来一比就知道这一单产出的是哪张。
    // 控制器不回传 id,而这条链路一路 await 到入库才返回,所以这么比是准的。
    final before = ref.read(galleryProvider).results.firstOrNull?.id;
    final GenOutcome ok;
    try {
      ok = await ref
          .read(generationProvider.notifier)
          .generate(
            using: sent,
            stay: inline,
            // 只有内联显示才跟单:不然页面已经切去图库看进度了,
            // 对话里再画一条进度条是重复。
            onJob: inline ? (jobId) => _trackJob(msgId, jobId) : null,
          );
    } finally {
      _trackJob(msgId, null);
    }
    if (!inline || ok != GenOutcome.ok) return;
    final now = ref.read(galleryProvider).results.firstOrNull?.id;
    if (now == null || now == before) return;
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return; // 出图这段时间里被截断/归档了
    final msgs = [...state.msgs];
    msgs[i] = msgs[i].copyWith(imageIds: [...msgs[i].imageIds, now]);
    _set(state.copyWith(msgs: msgs));
  }

  /// 记 / 清「这条消息正在出哪一单」。
  void _trackJob(String msgId, String? jobId) {
    final next = {...state.jobs};
    if (jobId == null) {
      if (next.remove(msgId) == null) return;
    } else {
      next[msgId] = jobId;
    }
    _set(state.copyWith(jobs: next), persist: false);
  }

  /// 停:掐掉这一轮。服务端那次 LLM 已经在跑,掐不掉,但用户不用再干等。
  void stop() {
    if (!state.running) return;
    _finishTrace('手动停止');
    _seq++;
    _sub?.cancel();
    _sub = null;
    _set(
      state.copyWith(
        running: false,
        liveTools: const [],
        stage: '',
        liveText: '',
        liveReasoning: '',
      ),
      persist: false,
    );
  }

  // ---- 写回 / 撤销 ----

  PromptSnapshot _snapshot() {
    final g = ref.read(generateProvider);
    return PromptSnapshot(
      positive: g.prompt,
      negative: g.negativePrompt,
      sections: List.of(g.sections),
      characters: List.of(g.characters),
      useCoords: g.params.useCoords,
    );
  }

  /// 某张画布眼下那组词。null = 当前画布(切画布之前的老记录没记画布);
  /// 画布已经删了返回 null。
  PromptSnapshot? _snapshotOf(String? canvasId) {
    final w = ref.read(canvasWorkspaceProvider);
    if (canvasId == null || canvasId == w.activeId) return _snapshot();
    final p = w.find(canvasId)?.prompts;
    if (p == null) return null;
    return PromptSnapshot(
      positive: p.prompt,
      negative: p.negativePrompt,
      sections: List.of(p.sections),
      characters: List.of(p.characters),
      useCoords: p.useCoords,
    );
  }

  /// 这条提议**如果拿去生成**会发出什么 —— 不改任何状态。
  ///
  /// 供结果卡的「不导入直接生成」与费用估算用。角色走 [buildAgentCharacters]
  /// 那一份共用规则,所以「直接生成」和「导入后再生成」出的是同一张图。
  ///
  /// 尺寸 / 采样 / Vibe / LoRA 全部沿用创作页现在的设置,AI 只负责画面内容。
  GenerateState? previewSendState(String msgId) {
    final msg = state.msgs.where((m) => m.id == msgId).firstOrNull;
    final r = msg?.draw;
    if (r == null) return null;
    var seq = 0;
    final sent = proposalSendState(
      ref.read(generateProvider),
      r,
      assistantSettingsOf(ref).importTo,
      newId: () => 'preview${seq++}',
    );
    final mods =
        ref.read(genModulesProvider).value ?? const GenModuleSettings();
    return stripHiddenModules(sent, mods);
  }

  /// 把某条 AI 消息的提议**导入**创作页。由用户在结果卡上点触发,不自动发生。
  ///
  /// 幂等:已经导入且没撤销过就直接返回 true。撤销之后可以再导入一次。
  ///
  /// **空值不覆盖**:AI 常常只给正向、负向留空,照写会把用户的负面词洗掉。
  bool applyProposal(String msgId) {
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return false;
    final msg = state.msgs[i];
    final r = msg.draw;
    // 纯文本那种只给复制,不导入(同 [generateFrom] 那道)
    if (r == null || msg.promptAsText) return false;
    if (msg.change != null && !msg.change!.undone) return true;

    final before = _snapshot();
    final gen = ref.read(generateProvider.notifier);
    // **整份替换,不留画布上的旧值**:AI 没给负向就是空负向,没给角色分区就是
    // 没有分区。「空值不覆盖」那条撤了 —— 它等于导入时悄悄读了一次画布,把你的
    // 旧词和 AI 的新词拼成一份谁都没写过的提示词。导入本身就是手动的那次交集,
    // 误导入了按撤销,before 快照里提示词、分区、角色、坐标开关一样不少。
    // 主提示词分区按设置处置(见 [SectionImport])。
    //
    // Vibe、角色参考、图生图这些 AI 不产出的东西**不动** —— 导入写的是 AI 那份
    // 提示词,不是清空你的工作区。和直接生成是同一条线(见 [proposalSendState])。
    gen.importPrompts(
      r.positive,
      r.negative,
      assistantSettingsOf(ref).importTo,
    );
    final placed = gen.applyAgentCharacters([
      for (final c in r.characters)
        (
          name: c.name,
          positive: c.positive,
          negative: c.negative,
          position: c.position,
        ),
    ]);
    // 坐标开关同样跟着 AI 这份走:摆了位就开,没摆就关。只开不关的话,
    // 画布上留着的开关会让 AI 那几个默认空格被当成真站位发出去。
    gen.setUseCoords(placed);
    final msgs = [...state.msgs];
    msgs[i] = msg.copyWith(
      // 撤销过再导入:非空的 change 直接覆盖掉那条 undone 的记录。
      change: AssistantChange(
        before: before,
        after: _snapshot(),
        canvasId: ref.read(canvasWorkspaceProvider).activeId,
      ),
    );
    _set(state.copyWith(msgs: msgs, changedUnseen: true));
    return true;
  }

  /// 导入的那张画布与那一轮写回时是否还一致。false = 用户之后自己又改过。
  /// 那张画布已经删了就无从比较,按一致算(撤销只是把这条记成已撤销)。
  bool inSyncWith(AssistantChange c) =>
      _snapshotOf(c.canvasId)?.sameAs(c.after) ?? true;

  /// 撤销一条 AI 消息的写回:把 [AssistantChange.before] 整份恢复回去。
  ///
  /// 回滚的是**整份快照**(正负向 + 分区 + 角色 + 站位开关),不是逐条 —— AI 那一轮是
  /// 整体重写的,逐条回滚拼不出原状。尺寸/采样/Vibe 一概不碰:撤销只该回滚 AI
  /// 干过的事。
  ///
  /// 返回 false = **没有回滚**,因为用户在写回之后自己又改过提示词,直接恢复会
  /// 把他那些改动一起吃掉。调用方要先问一句,再带 `force: true` 来第二次。
  bool undo(String msgId, {bool force = false}) {
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return true;
    final c = state.msgs[i].change;
    if (c == null || c.undone) return true;
    if (!force && !inSyncWith(c)) return false;

    // 回滚到导入的那张画布上,不碰眼下这张;画布删了就只记成已撤销。
    final target = c.canvasId;
    final w = ref.read(canvasWorkspaceProvider);
    if (target == null || target == w.activeId) {
      final gen = ref.read(generateProvider.notifier);
      gen.setPrompts(positive: c.before.positive, negative: c.before.negative);
      if (c.before.sections != null) gen.replaceSections(c.before.sections!);
      gen.replaceCharacters(c.before.characters);
      gen.setUseCoords(c.before.useCoords);
    } else if (w.find(target) != null) {
      final b = c.before;
      ref
          .read(canvasWorkspaceProvider.notifier)
          .updatePrompts(
            target,
            (p) => p.copyWith(
              prompt: b.positive,
              // 同 setPrompts:词变了,编辑器草稿随之作废
              promptRaw: b.positive == p.prompt ? p.promptRaw : '',
              negativePrompt: b.negative,
              negativePromptRaw: b.negative == p.negativePrompt
                  ? p.negativePromptRaw
                  : '',
              sections: b.sections == null ? null : List.of(b.sections!),
              characters: List.of(b.characters),
              useCoords: b.useCoords,
            ),
          );
    }

    final msgs = [...state.msgs];
    msgs[i] = msgs[i].copyWith(change: c.copyWith(undone: true));
    _set(state.copyWith(msgs: msgs));
    return true;
  }

  /// 用户切去创作页看过了,角标熄灭。
  void markSeen() {
    if (!state.changedUnseen) return;
    _set(state.copyWith(changedUnseen: false), persist: false);
  }

  // ---- 消息级操作 ----

  /// 「从这里重新开始」:丢掉这条及之后的全部消息,返回它的原文供输入框回填。
  String? truncateFrom(String msgId) {
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return null;
    final text = state.msgs[i].text;
    _set(state.copyWith(msgs: state.msgs.take(i).toList()));
    return text;
  }

  /// 从某一句提问重新来:丢掉它和之后的对话,把原话再发一次。
  Future<void> retryFrom(String userMsgId) async {
    if (_busy) return;
    final i = state.msgs.indexWhere(
      (m) => m.id == userMsgId && m.role == MsgRole.user,
    );
    if (i < 0) return;
    final m = state.msgs[i];
    final img = await _store.image(m.imageHash);
    _set(state.copyWith(msgs: state.msgs.take(i).toList()));
    // 重来一次得连「引没引创作页」一起重来,否则同一句话换了上下文,
    // 用户看到的是「重试之后 AI 答得完全不一样」。模式用按钮上现在选着的(见 [send])。
    await send(m.text, image: img, withCanvas: m.withCanvas);
  }

  /// 「这轮重新生成」:回到最后一次提问之前,把原话再发一次。
  Future<void> retryLast() async {
    for (var i = state.msgs.length - 1; i >= 0; i--) {
      if (state.msgs[i].role == MsgRole.user) {
        return retryFrom(state.msgs[i].id);
      }
    }
  }

  /// 某条 AI 回复 / 报错回的是哪一句:往前找最近的那条提问。
  AssistantMsg? askOf(String msgId) {
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    for (var j = i - 1; j >= 0; j--) {
      if (state.msgs[j].role == MsgRole.user) return state.msgs[j];
    }
    return null;
  }

  /// 这一句提问之后还有没有别的提问。有的话从它重来会把后面那几轮一起丢掉。
  bool hasLaterAsks(String userMsgId) {
    final i = state.msgs.indexWhere((m) => m.id == userMsgId);
    return i >= 0 && state.msgs.skip(i + 1).any((m) => m.role == MsgRole.user);
  }

  // ---- 会话 ----

  /// 「新对话」:当前这段存进历史,清空。返回是否真的归档了(空对话不入库)。
  /// 模式回到「无」 —— 模式跟着对话走,新对话从「无」开始。
  bool archiveCurrent() {
    _clearTraces();
    final cur = state.msgs;
    if (!cur.any((m) => m.role == MsgRole.user)) {
      if (cur.isNotEmpty || state.mode != AssistantMode.normal) {
        _set(
          state.copyWith(
            msgs: const [],
            mode: AssistantMode.normal,
            queue: const [],
          ),
        );
      }
      return false;
    }
    final s = ArchivedSession(id: _now, msgs: cur, at: cur.last.at);
    _set(
      state.copyWith(
        msgs: const [],
        mode: AssistantMode.normal,
        queue: const [],
        sessions: [
          s,
          ...state.sessions,
        ].take(AssistantStore.maxSessions).toList(),
      ),
    );
    return true;
  }

  /// 打开一段历史:它变成当前对话;当前那段(非空)顺手归档,不丢。
  /// 模式回到那段对话最后用的那个。
  void openSession(int id) {
    final i = state.sessions.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final target = state.sessions[i];
    _clearTraces();
    final rest = [...state.sessions]..removeAt(i);
    final cur = state.msgs;
    if (cur.any((m) => m.role == MsgRole.user)) {
      rest.insert(0, ArchivedSession(id: _now, msgs: cur, at: cur.last.at));
    }
    _set(
      state.copyWith(
        msgs: target.msgs,
        sessions: rest,
        mode: conversationMode(target.msgs),
        queue: const [],
      ),
    );
  }

  void deleteSession(int id) => _set(
    state.copyWith(
      sessions: [
        for (final s in state.sessions)
          if (s.id != id) s,
      ],
    ),
  );

  void clearSessions() => _set(state.copyWith(sessions: const []));
}

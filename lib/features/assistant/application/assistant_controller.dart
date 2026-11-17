/// AI 助手的控制器:排队发问、调 [AgentRuntime] 跑一轮、把结果记进对话、会话归档。
///
/// 写回规则只有一条 —— **这一轮给了绘图产出([AgentResult.hasDraw]),才出结果卡**;
/// 写创作页要用户点「导入」(设置里可改成自动),读创作页恒为一次性的「引用创作页」。
/// 两个方向不对称:自动写进去的词下一轮又被自动读回来当基底,用户改的和 AI 改的就分不清了。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/app_info.dart' show kAppVersion;
import '../../../core/auth/bot_session_store.dart';
import '../../../core/live_progress/live_progress.dart';
import '../../../core/net/backend_config.dart';
import '../../../core/store/app_stores.dart';
import '../../../core/store/gen_settings.dart' show genSettingsProvider;
import '../../../core/util/image_ops.dart' show decodeImageSize, ensurePng;
import '../../../l10n/l10n.dart';
import '../../gallery/albums/album_state.dart' show gallerySaveTargetProvider;
import '../../gallery/gallery_state.dart' show galleryProvider;
import '../../generate/canvas_state.dart';
import '../../generate/generate_state.dart';
import '../../generate/models.dart' show GenerateState, imageSizeOf;
import '../../inspiration/public_tags.dart'
    show mergeMineTags, publicTagsProvider;
import '../../inspiration/tag_library.dart';
import '../../inspiration/tag_models.dart';
import '../agent_model.dart';
import '../agent_trace.dart';
import '../assistant_mode.dart';
import '../assistant_settings.dart';
import '../custom_endpoint.dart' show CustomEndpoint, customEndpointsProvider;
import '../domain/agent_event.dart';
import '../domain/agent_result.dart';
import '../domain/conversation.dart';
import '../domain/image_gen.dart';
import '../domain/image_model.dart';
import '../domain/turn_request.dart';
import '../../editor/data/tag_completion.dart' show tagCompletionProvider;
import '../image_gen/image_gen_client.dart';
import '../image_gen/image_models.dart';
import '../llm/llm_image.dart' show prepareLlmImage;
import '../presets/preset_rule.dart';
import '../presets/rules_library.dart';
import '../runtime/agent_runtime.dart';
import '../tools/offline_tags.dart';
import '../tools/online_tags.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_settings.dart';
import 'proposal_service.dart';
import 'session_repository.dart';
import 'trace_recorder.dart';

/// 正在跑时发的那几句:排着,上一轮跑完依次发出去。不落盘。
///
/// 发出去时那条用户消息沿用这里的 [id],对话里的气泡原地转正。
class QueuedAsk {
  const QueuedAsk({
    required this.id,
    required this.text,
    required this.at,
    this.images = const [],
    this.withCanvas = false,
  });

  final String id;
  final String text;

  /// 排进来的时刻(UNIX 毫秒)。
  final int at;
  final List<Uint8List> images;

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
    this.imageRuns = const {},
    this.imageErrors = const {},
    this.mode = AssistantMode.normal,
  });

  /// 当前这段对话。
  final List<AssistantMsg> msgs;

  /// 输入框上方选着的模式。跟着对话走:开新对话回到「无」,打开历史回到它最后用的
  /// 那个(见 [conversationMode])。不单独落盘,重启后从最后一条用户消息读回来。
  final AssistantMode mode;

  /// 已归档的历史(新的在前)。
  final List<ArchivedSession> sessions;

  final bool running;

  /// 排着等发的几句(先进先出)。停下或出错后不自动接着发,等用户再按一次发送。
  /// 队首那句在用户消息真追进 [msgs] 的同一刻才出队。
  final List<QueuedAsk> queue;

  /// 正在跑的那一轮已经查了哪些资料。跑完并进 [AssistantMsg.tools],这里清空。
  final List<ToolTrace> liveTools;

  /// 等待期的阶段文案。
  final String stage;

  /// 正在写的这一跳的正文(见 [AgentDelta])。每帧整块替换;跑完并进 [AssistantMsg.text]。
  final String liveText;

  /// 同上,模型这一跳的思考过程。跑完不留。
  final String liveReasoning;

  /// 正在为某条消息出的图:消息 id → 出图任务 id。只在「图片显示在对话里」开着时才记。
  /// 不落盘:任务 id 是本次运行内的序号。
  final Map<String, String> jobs;

  /// 正在用图像模型重新生成的消息 id。不落盘。
  final Set<String> imageRuns;

  /// 图像模型重新生成没出成的原因:消息 id → 错误原文。不落盘,再出一次就清掉。
  final Map<String, String> imageErrors;

  /// 有写回、但用户还没切去创作页看过 —— 底部导航「创作」上那颗角标。
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
    Set<String>? imageRuns,
    Map<String, String>? imageErrors,
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
    imageRuns: imageRuns ?? this.imageRuns,
    imageErrors: imageErrors ?? this.imageErrors,
    mode: mode ?? this.mode,
  );
}

final assistantProvider = NotifierProvider<AssistantController, AssistantState>(
  AssistantController.new,
);

/// 历史里保留 `nai_draw` 围栏的 AI 轮数(见 [historyFenceIds])。
const _keepFences = 2;

/// 发一轮时等公共库列表(我发布的画风 / OC)最多多久,过了这轮只用本机条目。
const _publicLibraryWait = Duration(seconds: 5);

/// 等后端图像模型列表最多多久,过了只看自定义接口。
const _imageChannelsWait = Duration(seconds: 5);

class AssistantController extends Notifier<AssistantState> {
  StreamSubscription<AgentEvent>? _sub;

  /// 正在跑的那一轮图像模型请求;停的时候关掉它。
  http.Client? _imageClient;

  /// 发号作废:取消 / 又发了一次时,回来的旧事件对不上号,整轮丢弃。
  int _seq = 0;

  /// [send] 已经进门、还没把 running 立起来(前面在等授权、存图)。
  bool _starting = false;

  bool get _busy => state.running || _starting;

  bool get _appForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  int _idSeq = 0;

  SessionRepository get _repo => ref.read(appStoresProvider).assistant;

  late TraceRecorder _traces;
  late ProposalService _proposals;

  @override
  AssistantState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
      LiveProgress.instance.cancelAssistant();
    });
    final repo = _repo;
    _traces = TraceRecorder(repo);
    _proposals = ProposalService(ref);
    return AssistantState(
      msgs: repo.initialCurrent,
      sessions: repo.initialSessions,
      mode: conversationMode(repo.initialCurrent),
    );
  }

  /// 换模式。只影响之后发的消息。
  void setMode(AssistantMode mode) {
    if (state.mode == mode) return;
    _set(state.copyWith(mode: mode), persist: false);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  AssistantMsg? _msg(String id) =>
      state.msgs.where((m) => m.id == id).firstOrNull;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// 先改状态(立即生效),再尽力落盘。[persist] = false 用于纯运行态的改动。
  void _set(AssistantState next, {bool persist = true}) {
    state = next;
    if (persist) _repo.schedule(next.msgs, next.sessions);
  }

  // ---- 排队 ----

  /// 发一句。正在跑或前面还排着别的,就排到队尾,按顺序一句句发。
  Future<void> submit(
    String text, {
    List<Uint8List> images = const [],
    bool withCanvas = false,
  }) {
    if (text.trim().isEmpty && images.isEmpty) return Future.value();
    _set(
      state.copyWith(
        queue: [
          ...state.queue,
          QueuedAsk(
            id: _newId(),
            text: text,
            at: _now,
            images: images,
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
      images: next.images,
      withCanvas: next.withCanvas,
      queuedId: next.id,
    );
  }

  // ---- 发一轮 ----

  /// 已完成回合的对话历史,按「上下文轮数」截好。
  ///
  /// AI 轮带上当初那个 `nai_draw` 围栏(见 [replayText]),但只留最近 [_keepFences] 个:
  /// 围栏装的是完整提示词,最新那条是「现在什么样」,上一条是「刚才那版」,再往前只留正文。
  /// 失败的那一轮连同它的提问一起丢掉。
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

  /// 用户自己那份画师串 / OC,和灵感页「我的」同一份:本机条目 + 公共库里我发布、
  /// 本机没副本的(见 [mergeMineTags])。
  ///
  /// 要 await:灵感页没打开过时 provider 还没读盘,同步取到的是 null。
  /// 公共库列表灵感页拉过就用现成的,没拉过最多等 [_publicLibraryWait];
  /// 没授权、拉不到就只用本机条目。
  Future<({List<Map<String, dynamic>> artists, List<Map<String, dynamic>> ocs})>
  _webLibrary() async {
    TagLibraryState? lib;
    try {
      lib = await ref.read(tagLibraryProvider.future);
    } catch (_) {
      lib = null; // 库文件读坏了:这轮不带库
    }
    if (lib == null) {
      return (
        artists: const <Map<String, dynamic>>[],
        ocs: const <Map<String, dynamic>>[],
      );
    }
    final local = lib;
    String? myId;
    try {
      myId = (await ref.read(botSessionProvider.future))?.botUserId;
    } catch (_) {}
    Future<List<TagEntry>> mine(TagCategory c) async {
      List<TagEntry>? pub;
      if (myId != null) {
        try {
          pub = await ref
              .read(publicTagsProvider(c).future)
              .timeout(_publicLibraryWait);
        } catch (_) {}
      }
      return mergeMineTags(local.of(c), myId, pub);
    }

    final (artists, ocs) = await (
      mine(TagCategory.artist),
      mine(TagCategory.character),
    ).wait;
    return (
      artists: [
        for (final e in artists)
          if (e.positive.trim().isNotEmpty)
            {'id': e.name, 'name': e.name, 'prompt': e.positive},
      ],
      ocs: [
        for (final e in ocs)
          if (e.positive.trim().isNotEmpty)
            {
              // 没发布过的本地 OC 没有 en_name,拿本地 id 顶上(只当键用)
              'en_name': e.publicId ?? e.id,
              'zh_name': e.name,
              'zh_aliases': e.aliases,
              'tag_group': e.positive,
            },
      ],
    );
  }

  /// 发一轮。[images] 是用户带的图(原始字节),发给模型并存进 blob。
  ///
  /// [withCanvas] = 把创作页**当前**的正向 / 负向 / 角色一并发过去,让 AI 在它上面改。
  /// 模式用输入框上方现在选着的,「纯文本格式」看助手设置里现在的开关。
  ///
  /// [queuedId] = 发的是队里那一句:用户消息用它当 id,并在同一刻出队。发之前就被拦下
  /// (没授权、模型不支持)的话它留在队里。
  Future<void> send(
    String text, {
    List<Uint8List> images = const [],
    bool withCanvas = false,
    String? queuedId,
  }) async {
    if (_busy) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && images.isEmpty) return;
    _starting = true;
    try {
      await _send(
        trimmed,
        images: images,
        withCanvas: withCanvas,
        queuedId: queuedId,
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _send(
    String trimmed, {
    List<Uint8List> images = const [],
    required bool withCanvas,
    String? queuedId,
  }) async {
    // 选着图像模型:不走对话模型,原话直接交给它出图
    final imageKey = imageChoiceKeyOf(
      ref.read(assistantModelPrefProvider).value ?? '',
    );
    if (imageKey != null) {
      return _sendImage(
        trimmed,
        images: images,
        queuedId: queuedId,
        modelKey: imageKey,
      );
    }
    // 界面已经挡了,这儿再挡一道:自动生成、重试这些不经过界面
    final model = ref.read(generateProvider).params.model;
    if (!assistantSupportsModel(model)) {
      _pushError(l10nNow.assistantNoModal);
      return;
    }

    final base = ref.read(backendBaseProvider).value ?? '';
    final sid = (await ref.read(botSessionProvider.future))?.sessionId ?? '';
    final endpoint = ref.read(assistantEndpointProvider);
    // 没有 Bot 授权时后端那条只能用免费模型:列表得先到货才知道是哪条
    if (sid.isEmpty && endpoint == null) {
      try {
        await ref.read(agentModelsProvider.future);
      } catch (_) {}
      if (ref.read(assistantModelKeyProvider).isEmpty) {
        _pushError(l10nNow.builtinModelUnavailable);
        return;
      }
    }

    // 历史必须在把这条 user 消息追进去之前取
    final history = _history();

    // 画布是空的就当没勾 —— 记在消息上的也是这个结果
    final g = ref.read(generateProvider);
    final canvas = withCanvas && canvasHasContent(g);
    // 回复回来时人可能已经切去别的画布,自动导入 / 出图只对发问时这张生效
    final sourceCanvasId = ref.read(canvasWorkspaceProvider).activeId;
    final picked = state.mode;
    final settings = assistantSettingsOf(ref);
    final noDraw = settings.noDraw;

    final hashes = [for (final i in images) ?await _repo.putImage(i)];

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
            imageHashes: hashes,
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
        stage: l10nNow.thinking,
      ),
    );
    // 跟出图共用那条前台服务:退到后台等回复时进程不被冻结 / 回收
    if (ref.read(genSettingsProvider).value?.genNotify ?? true) {
      LiveProgress.instance.beginAssistant();
    }
    final imageModel = agentImageModel(g.params.model);
    final runtime = agentRuntimeFor(
      endpoint: endpoint,
      backendBase: base,
      sessionId: sid,
      backendModel: ref.read(assistantModelKeyProvider),
      imageModel: imageModel,
      offline: ref.read(offlineTagsProvider),
      online: base.isEmpty
          ? null
          : CompletionOnlineTags(
              ref.read(tagCompletionProvider),
              sessionId: sid,
            ),
    );
    // 记录跟着这条提问一起开:下面还要等灵感库、规则,这期间按了停止也得收尾
    final trace = _traces.begin(route: runtime.route, userText: trimmed);

    final lib = await _webLibrary();
    ToolSettings toolSettings;
    try {
      toolSettings = await ref.read(toolSettingsProvider.future);
    } catch (_) {
      toolSettings = const ToolSettings();
    }

    final family = rulesFamilyOf(imageModel);
    List<PresetRule>? custom;
    try {
      custom = (await ref.read(
        rulesLibraryProvider.future,
      )).customRulesFor(family);
    } catch (_) {
      custom = null;
    }
    // 模式靠预设里那一段:在用的预设没写就什么都不加,消息上照旧记着用户选的那个
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
      'tools': [for (final t in enabledTools(toolSettings)) t.name],
      'oc_placeholders': toolSettings.ocPlaceholders,
      'history_turns': settings.historyTurns,
      'retries': settings.retries,
      'rerolls': settings.rerolls,
      if (!settings.defaultRefusalKeywords)
        'refusal_keywords': settings.refusalKeywords,
      'history_entries': history.length,
      'with_canvas': canvas,
      if (images.isNotEmpty) 'image_bytes': [for (final i in images) i.length],
    });
    final request = AgentTurnRequest(
      userText: trimmed,
      images: images,
      history: history,
      canvas: canvas ? canvasSnapshotOf(g) : null,
      imageModel: imageModel,
      customRules: custom,
      modeKeys: modeKeys,
      tools: toolSettings,
      artists: lib.artists,
      ocs: lib.ocs,
      resources: latestResources(state.msgs),
      think: settings.thinkLevel,
      stream: settings.stream,
      retries: settings.retries,
      rerolls: settings.rerolls,
      refusalKeywords: settings.refusalKeywords,
    );
    // 上面几处 await 期间可能已经点了停止,或者又发了一条:这一轮作废。
    // runtime 只有 listen 才发请求,在这儿拦住就不花钱。
    if (seq != _seq) return;
    await _sub?.cancel();
    if (seq != _seq) return;
    final tools = <ToolTrace>[];
    _sub = _traces
        .track(runtime.run(request, trace: trace))
        .listen(
          (ev) {
            if (seq != _seq) return;
            switch (ev) {
              case AgentToolCall(:final name, :final args):
                // 参数里的「查什么」当场留下 —— tool_result 只回计数
                tools.add(ToolTrace(name: name, subject: toolSubject(args)));
                _set(
                  state.copyWith(
                    liveTools: List.of(tools),
                    stage: l10nNow.lookingUp,
                  ),
                  persist: false,
                );
              case AgentToolResult(:final name, :final summary):
                // 同一跳的结果按调用顺序回来,配最早那个还没结果的
                final i = tools.indexWhere((t) => t.name == name && !t.done);
                if (i >= 0) {
                  tools[i] = tools[i].copyWith(summary: summary);
                } else {
                  tools.add(ToolTrace(name: name, summary: summary));
                }
                _set(
                  state.copyWith(
                    liveTools: List.of(tools),
                    stage: l10nNow.thinking,
                  ),
                  persist: false,
                );
              case AgentDelta(:final text, :final reasoning):
                // 整块替换,不落盘
                _set(
                  state.copyWith(liveText: text, liveReasoning: reasoning),
                  persist: false,
                );
              case AgentDone(:final result):
                _finish(result, tools, canvas, picked, noDraw, sourceCanvasId);
            }
          },
          onError: (Object e) {
            if (seq != _seq) return;
            // 没授权被后端拒了:多半是那条免费模型刚被收回,重取列表
            if (sid.isEmpty &&
                endpoint == null &&
                e is AgentFailure &&
                (e.status == 401 || e.status == 403)) {
              ref.invalidate(agentModelsProvider);
            }
            _pushError('$e');
          },
          onDone: () {
            if (seq != _seq) return;
            if (state.running) _pushError(l10nNow.turnInterrupted);
          },
          cancelOnError: true,
        );
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

  /// 当前对话记了几轮。
  int get traceCount => _traces.count;

  /// 助手设置里「导出对话记录」的全文,见 [renderTraceExport]。
  String exportTrace() => renderTraceExport(
    traces: _traces.traces,
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

  /// 记一条错误消息。[msg] 原样显示。
  void _pushError(String msg) {
    _traces.finish(msg);
    _sub?.cancel();
    _sub = null;
    LiveProgress.instance.endAssistant(success: false, keep: !_appForeground);
    _set(
      state.copyWith(
        msgs: [
          ...state.msgs,
          AssistantMsg(id: _newId(), role: MsgRole.error, text: msg, at: _now),
        ],
        running: false,
        liveTools: const [],
        stage: '',
        liveText: '',
        liveReasoning: '',
      ),
    );
  }

  /// 补负面用的画师串条目:画风库。
  List<TagEntry> _libArtists() => [
    for (final e in ref.read(tagLibraryProvider).value?.entries ?? const [])
      if (e.category == TagCategory.artist) e,
  ];

  void _finish(
    AgentResult r,
    List<ToolTrace> tools,
    bool canvas,
    AssistantMode mode,
    bool noDraw,
    String sourceCanvasId,
  ) {
    LiveProgress.instance.endAssistant(success: true, keep: !_appForeground);
    // 产出先当成一份「提议」挂在这条消息上,用户在结果卡上点「导入」才落地。
    final proposal = r.hasDraw
        ? DrawProposal(
            positive: r.positive,
            negative: r.negative,
            characters: r.characters,
          )
        : null;
    final draw = proposal == null
        ? null
        : DrawProposal(
            positive: proposal.positive,
            negative: withArtistNegatives(proposal, _libArtists()),
            characters: proposal.characters,
          );
    final text = r.replyText.trim().isNotEmpty
        ? r.replyText.trim()
        : (draw != null
              ? l10nNow.replyDoneFallback
              : l10nNow.replyEmptyFallback);
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
            withCanvas: canvas,
            mode: mode,
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

  // ---- 图像模型 ----

  /// 选着图像模型时发一轮:原话交给图像模型出图,不走对话模型,附的图当参考图
  /// (要改对话里的图就点图上的「引用」附上)。分辨率 / 比例 / 张数按输入框上方那排,
  /// 这个模型出不了的档按自动。
  Future<void> _sendImage(
    String text, {
    List<Uint8List> images = const [],
    String? queuedId,
    required String modelKey,
  }) async {
    final hashes = [for (final i in images) ?await _repo.putImage(i)];
    final settings = assistantSettingsOf(ref);
    final seq = ++_seq;
    _set(
      state.copyWith(
        msgs: [
          ...state.msgs,
          AssistantMsg(
            id: queuedId ?? _newId(),
            role: MsgRole.user,
            text: text,
            at: _now,
            imageHashes: hashes,
            mode: state.mode,
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
        stage: l10nNow.drawingImage,
      ),
    );
    if (ref.read(genSettingsProvider).value?.genNotify ?? true) {
      LiveProgress.instance.beginAssistant();
    }
    final client = _imageClient = http.Client();
    try {
      if (text.isEmpty) throw AgentFailure(l10nNow.imagePromptEmpty);
      final choice = imageModelOf(await _imageChoices(), modelKey);
      if (choice == null) throw AgentFailure(l10nNow.imageGenNoModel);
      final spec = ImageGenSpec(
        prompt: text,
        attached: images.isNotEmpty,
        size: choice.sizes.contains(settings.imageSize)
            ? settings.imageSize
            : '',
        aspect: choice.aspects.contains(settings.imageAspect)
            ? settings.imageAspect
            : '',
        count: settings.imageCount,
      );
      final (ids, partial) = await _drawImages(
        choice,
        spec,
        attached: images,
        client: client,
        keep: () => seq == _seq,
      );
      if (seq != _seq) return;
      LiveProgress.instance.endAssistant(success: true, keep: !_appForeground);
      final id = _newId();
      _set(
        state.copyWith(
          msgs: [
            ...state.msgs,
            AssistantMsg(
              id: id,
              role: MsgRole.ai,
              text: '',
              at: _now,
              imageIds: ids,
              imageBatch: ids.length,
              imageGen: spec,
              imageModel: modelKey,
            ),
          ],
          running: false,
          stage: '',
          // 没出齐:出成的照挂,原因写在图下面
          imageErrors: partial == null
              ? null
              : {...state.imageErrors, id: partial},
        ),
      );
      unawaited(_drain());
    } catch (e) {
      if (seq != _seq) return;
      _pushError('$e');
    } finally {
      client.close();
      if (identical(_imageClient, client)) _imageClient = null;
    }
  }

  /// 图上的「重新生成」:照这条消息的请求再出一批,在原框里换。
  Future<void> generateImage(String msgId) async {
    final msg = _msg(msgId);
    final spec = msg?.imageGen;
    final key = msg?.imageModel;
    if (spec == null || key == null || state.imageRuns.contains(msgId)) return;
    _set(
      state.copyWith(
        imageRuns: {...state.imageRuns, msgId},
        imageErrors: {...state.imageErrors}..remove(msgId),
      ),
      persist: false,
    );
    String? error;
    var ids = const <String>[];
    final client = http.Client();
    try {
      final choice = imageModelOf(await _imageChoices(), key);
      if (choice == null) throw AgentFailure(l10nNow.imageGenNoModel);
      final attached = <Uint8List>[
        if (spec.attached)
          for (final h in askOf(msgId)?.imageHashes ?? const <String>[])
            ?await _repo.image(h),
      ];
      (ids, error) = await _drawImages(
        choice,
        spec,
        attached: attached,
        client: client,
      );
    } catch (e) {
      error = '$e';
    } finally {
      client.close();
    }
    final errors = {...state.imageErrors}..remove(msgId);
    if (error != null) errors[msgId] = error;
    var msgs = state.msgs;
    final i = msgs.indexWhere((m) => m.id == msgId);
    // 出图这段时间里被截断/归档了就不挂
    final attach = ids.isNotEmpty && i >= 0;
    if (attach) {
      msgs = [...msgs];
      msgs[i] = msgs[i].copyWith(
        imageIds: [...msgs[i].imageIds, ...ids],
        imageBatch: ids.length,
      );
    }
    _set(
      state.copyWith(
        msgs: msgs,
        imageRuns: {...state.imageRuns}..remove(msgId),
        imageErrors: errors,
      ),
      persist: attach,
    );
  }

  /// 按 [spec] 让 [choice] 同时出 [ImageGenSpec.count] 张、存进图库。
  /// 按次序返回条目 id 和第一张没出成的原因;一张都没出成就抛这个原因。
  /// [attached] 是这轮提问附的图;[keep] 返回 false 之后出好的不存。
  Future<(List<String>, String?)> _drawImages(
    ImageModelChoice choice,
    ImageGenSpec spec, {
    List<Uint8List> attached = const [],
    required http.Client client,
    bool Function()? keep,
  }) async {
    final images = [for (final b in attached) await prepareLlmImage(b)];
    final sid = (await ref.read(botSessionProvider.future))?.sessionId ?? '';
    final gen = imageGenClientFor(
      choice,
      backendBase: ref.read(backendBaseProvider).value ?? '',
      sessionId: sid,
    );
    final ImageGenInput input = (
      prompt: spec.prompt,
      images: images,
      size: spec.size,
      aspect: spec.aspect,
    );
    final (ids, error) = await drawBatch(spec.count, () async {
      final png = await ensurePng(await gen.generate(input, client: client));
      if (keep != null && !keep()) return null;
      return _saveImage(png);
    });
    if (ids.isEmpty) throw error ?? AgentFailure(l10nNow.imageGenNoImage);
    return (ids, error == null ? null : '$error');
  }

  /// 出好的图进图库,返回条目 id。
  Future<String> _saveImage(Uint8List png) async {
    final (w, h) = imageSizeOf(png) ?? await decodeImageSize(png);
    final r = await ref
        .read(galleryProvider.notifier)
        .addResultToGallery(
          bytes: png,
          width: w,
          height: h,
          seed: 0,
          target: ref.read(gallerySaveTargetProvider),
        );
    return r.id;
  }

  /// 全部图像模型。后端渠道列表最多等 [_imageChannelsWait]。
  Future<List<ImageModelChoice>> _imageChoices() async {
    PlanaImageChannels? plana;
    try {
      plana = await ref
          .read(planaImageChannelsProvider.future)
          .timeout(_imageChannelsWait);
    } catch (_) {}
    List<CustomEndpoint> endpoints;
    try {
      endpoints = await ref.read(customEndpointsProvider.future);
    } catch (_) {
      endpoints = const [];
    }
    return imageModelChoices(plana, endpoints);
  }

  /// 「自动写入创作页」/「出词后自动生成」两个开关的落点:先导入再出图。
  /// 发问之后切去了别的画布,两样都不自动做。
  void _autoAfterDraw(String msgId, String sourceCanvasId) {
    if (ref.read(canvasWorkspaceProvider).activeId != sourceCanvasId) return;
    final settings = assistantSettingsOf(ref);
    if (settings.autoImport) applyProposal(msgId);
    if (settings.autoGenerate) unawaited(generateFrom(msgId));
  }

  /// 拿某条消息的提议出一张图。结果卡上的「生成」和自动生成都走这里。
  /// 显示成纯文本的那种提议不出图。
  Future<void> generateFrom(String msgId) async {
    if (_msg(msgId)?.promptAsText ?? false) return;
    final sent = previewSendState(msgId);
    if (sent == null) return;
    final inline = assistantSettingsOf(ref).inlineImage;
    final String? imageId;
    try {
      imageId = await _proposals.generate(
        sent,
        inline: inline,
        // 只有内联显示才跟单:不然页面已经切去图库看进度了
        onJob: inline ? (jobId) => _trackJob(msgId, jobId) : null,
      );
    } finally {
      _trackJob(msgId, null);
    }
    if (imageId == null) return;
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return; // 出图这段时间里被截断/归档了
    final msgs = [...state.msgs];
    msgs[i] = msgs[i].copyWith(imageIds: [...msgs[i].imageIds, imageId]);
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

  /// 停:掐掉这一轮。已经发出去的那次 LLM 调用掐不掉,但用户不用再干等。
  void stop() {
    if (!state.running) return;
    _traces.finish('手动停止');
    _seq++;
    _sub?.cancel();
    _sub = null;
    _imageClient?.close();
    _imageClient = null;
    LiveProgress.instance.cancelAssistant();
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

  /// 这条提议如果拿去生成会发出什么 —— 不改任何状态。结果卡的费用估算也用它。
  GenerateState? previewSendState(String msgId) {
    final r = _msg(msgId)?.draw;
    return r == null ? null : _proposals.sendState(r);
  }

  /// 把某条 AI 消息的提议导入创作页。幂等:已经导入且没撤销过就直接返回 true。
  bool applyProposal(String msgId) {
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return false;
    final msg = state.msgs[i];
    final r = msg.draw;
    if (r == null || msg.promptAsText) return false;
    if (msg.change != null && !msg.change!.undone) return true;
    final msgs = [...state.msgs];
    // 撤销过再导入:新的 change 直接覆盖那条 undone 的记录
    msgs[i] = msg.copyWith(change: _proposals.importProposal(r));
    _set(state.copyWith(msgs: msgs, changedUnseen: true));
    return true;
  }

  /// 导入的那张画布与那一轮写回时是否还一致。false = 用户之后自己又改过。
  bool inSyncWith(AssistantChange c) => _proposals.inSync(c);

  /// 撤销一条 AI 消息的写回:把导入前的快照整份恢复回去。
  ///
  /// 返回 false = 没有回滚,因为用户在写回之后自己又改过;调用方先问一句,
  /// 再带 `force: true` 来第二次。
  bool undo(String msgId, {bool force = false}) {
    final i = state.msgs.indexWhere((m) => m.id == msgId);
    if (i < 0) return true;
    final c = state.msgs[i].change;
    if (c == null || c.undone) return true;
    if (!force && !_proposals.inSync(c)) return false;
    _proposals.revert(c);
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

  /// 从某一句提问重新来:丢掉它和之后的对话,把原话连同「引没引创作页」再发一次。
  Future<void> retryFrom(String userMsgId) async {
    if (_busy) return;
    final i = state.msgs.indexWhere(
      (m) => m.id == userMsgId && m.role == MsgRole.user,
    );
    if (i < 0) return;
    final m = state.msgs[i];
    final images = [for (final h in m.imageHashes) ?await _repo.image(h)];
    _set(state.copyWith(msgs: state.msgs.take(i).toList()));
    await send(m.text, images: images, withCanvas: m.withCanvas);
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

  /// 「新对话」:当前这段存进历史,清空,模式回到「无」。返回是否真的归档了(空对话不入库)。
  bool archiveCurrent() {
    _traces.clear();
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
        ].take(SessionRepository.maxSessions).toList(),
      ),
    );
    return true;
  }

  /// 打开一段历史:它变成当前对话;当前那段(非空)顺手归档。模式回到那段最后用的那个。
  void openSession(int id) {
    final i = state.sessions.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final target = state.sessions[i];
    _traces.clear();
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

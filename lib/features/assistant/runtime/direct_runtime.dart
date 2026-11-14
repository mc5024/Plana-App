import '../agent_trace.dart';
import '../custom_endpoint.dart' show CustomEndpoint;
import '../direct_agent.dart' show streamDirectPrompt;
import '../domain/agent_event.dart';
import '../domain/turn_request.dart';
import '../preset_rules.dart'
    show appOutputFormat, appToolLayer, defaultRules, rulesFamilyOf, withToolLayer;
import 'agent_runtime.dart';

/// 自定义接口那条:在本机跑 agent 循环,见 `streamDirectPrompt`。
class DirectAgentRuntime implements AgentRuntime {
  DirectAgentRuntime({
    required this.endpoint,
    required this.backendBase,
    required this.sessionId,
  });

  final CustomEndpoint endpoint;
  final String backendBase;
  final String sessionId;

  @override
  String get route => AgentTrace.routeCustom;

  @override
  Stream<AgentEvent> run(AgentTurnRequest req, {AgentTrace? trace}) async* {
    // 规则直接当系统提示:在用的预设(没自定义就是默认那份)挂上工具层,再补出图格式
    final rules = withToolLayer(
      req.customRules ??
          await defaultRules(
            rulesFamilyOf(req.imageModel),
            backendBase: backendBase,
            sessionId: sessionId,
          ),
      await appToolLayer(),
    );
    final canvas = req.canvas;
    yield* streamDirectPrompt(
      endpoint: endpoint,
      backendBase: backendBase,
      sessionId: sessionId,
      userRequest: req.userText,
      image: req.image,
      rules: rules,
      outputFormat: await appOutputFormat(),
      canvasBlock: canvas == null ? '' : canvasBlockOf(canvas),
      history: req.history,
      webArtists: req.artists,
      webOcs: req.ocs,
      ocPlaceholders: req.ocPlaceholders,
      resources: req.resources,
      libraryScope: req.libraryScope,
      chosenModes: req.modeKeys,
      think: req.think,
      stream: req.stream,
      trace: trace,
    );
  }
}

/// 画布 → `[当前画面提示词]` 块。字段名(positive / negative / characters + position)
/// 与规则里讲的一致。
String canvasBlockOf(CanvasSnapshot c) {
  final lines = <String>[
    '请在下面这份提示词的基础上改:没让你动的部分原样留着;characters 连 '
        'position 一起带回来,不带会把我摆好的构图打乱。除非我明说要全新主题 / '
        '重做,否则都按这份改。',
    '[当前画面提示词]',
    'positive: ${c.positive.trim().isEmpty ? "(空)" : c.positive}',
    'negative: ${c.negative.trim().isEmpty ? "(空)" : c.negative}',
  ];
  if (c.characters.isNotEmpty) {
    lines.add('characters:');
    for (final ch in c.characters) {
      lines.add('  - name: ${ch['name']}');
      final pos = (ch['positive'] as String? ?? '').trim();
      lines.add('    positive: ${pos.isEmpty ? "(空)" : pos}');
      final neg = (ch['negative'] as String? ?? '').trim();
      if (neg.isNotEmpty) lines.add('    negative: $neg');
      final at = (ch['position'] as String? ?? '').trim();
      if (at.isNotEmpty) lines.add('    position: $at');
    }
  }
  return lines.join('\n');
}

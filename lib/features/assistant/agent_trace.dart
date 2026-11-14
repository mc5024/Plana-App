/// 一轮 AI 对话的调试记录:这一轮发出去了什么、收回来了什么。
///
/// 助手设置里「导出对话记录」导出的就是它:调预设、查「它为什么没照我说的改」。
/// 两条路都在 app 里跑,模型看到的全在这儿 —— 系统提示全文、消息、每一跳的模型原话、
/// 工具结果、回灌与重试。后端渠道另外套的外壳在服务端,要看得开服务端的 AGENT_DEBUG_DUMP。
///
/// **不记密钥**:自定义接口只记名字、格式、模型和域名。用户带的图只记大小。
library;

import 'dart:convert';

class AgentTrace {
  AgentTrace({
    required this.startedAt,
    required this.route,
    required this.userText,
    this.settings = const {},
  });

  /// 开始的时刻(毫秒时间戳)。
  final int startedAt;

  /// [routeBackend] 或 [routeCustom]。
  final String route;

  static const routeBackend = 'backend';
  static const routeCustom = 'custom';

  final String userText;

  /// 发这一轮时的设置快照:模型、模式、资料库范围、上下文轮数……
  final Map<String, Object?> settings;

  /// 结束的时刻。null = app 在这一轮中途被杀了。
  int? endedAt;

  /// 失败 / 被停下的原因。null = 正常收尾。
  String? error;

  /// 旧版后端渠道发出去的请求体,只在旧记录里有。
  Map<String, Object?>? request;

  /// 系统提示全文。
  String? system;

  /// 自定义接口:预匹配回来的东西(资料块、本轮命中的资源、条件段模式)。
  Map<String, Object?>? prequery;

  /// 自定义接口:第一跳发出去的消息(历史 + 本轮)。后面几跳在这之上接着模型原话
  /// 和工具结果,见 [hops]。
  List<Map<String, String>>? messages;

  /// 自定义接口:每一跳 `{t, ms, reply, tool_calls?, tool_results?, repairs?, feedback?,
  /// refusal?}`,t 是距开始的毫秒数,ms 是这一跳模型调用花了多久。
  final List<Map<String, Object?>> hops = [];

  /// 收到的事件,按到达顺序 `{t, event, data}`。
  final List<Map<String, Object?>> events = [];

  /// 距开始多少毫秒。
  int sinceStart() => DateTime.now().millisecondsSinceEpoch - startedAt;

  void event(String name, Object? data) =>
      events.add({'t': sinceStart(), 'event': name, 'data': data});

  Map<String, Object?> toJson() => {
    'started_at': startedAt,
    'ended_at': endedAt,
    'route': route,
    'user_text': userText,
    'settings': settings,
    'error': error,
    if (request != null) 'request': request,
    if (system != null) 'system': system,
    if (prequery != null) 'prequery': prequery,
    if (messages != null) 'messages': messages,
    if (hops.isNotEmpty) 'hops': hops,
    'events': events,
  };

  /// 读坏的字段一律当没有 —— 调试记录读不全,也不该拖累整份存档。
  factory AgentTrace.fromJson(Map<String, dynamic> j) {
    Map<String, Object?>? map(Object? v) =>
        v is Map ? v.map((k, v) => MapEntry('$k', v)) : null;
    List<Map<String, Object?>> maps(Object? v) => [
      if (v is List)
        for (final e in v) ?map(e),
    ];
    final t = AgentTrace(
      startedAt: (j['started_at'] as num?)?.toInt() ?? 0,
      route: j['route']?.toString() ?? routeBackend,
      userText: j['user_text']?.toString() ?? '',
      settings: map(j['settings']) ?? const {},
    );
    t
      ..endedAt = (j['ended_at'] as num?)?.toInt()
      ..error = j['error']?.toString()
      ..request = map(j['request'])
      ..system = j['system']?.toString()
      ..prequery = map(j['prequery'])
      ..messages = j['messages'] is List
          ? [
              for (final m in maps(j['messages']))
                {
                  'role': m['role']?.toString() ?? '',
                  'content': m['content']?.toString() ?? '',
                },
            ]
          : null;
    t.hops.addAll(maps(j['hops']));
    t.events.addAll(maps(j['events']));
    return t;
  }
}

const _pretty = JsonEncoder.withIndent('  ');

String _json(Object? v) => _pretty.convert(v);

String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-09-15 20:58:03`
String traceTimestamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${_two(d.month)}-${_two(d.day)} '
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

String _secs(int ms) => '${(ms / 1000).toStringAsFixed(1)} 秒';

/// 导出成一份人读的文本。
///
/// 结构:当前设置 → 下一轮会带上的上下文 → 每一轮的记录(含失败和重试)→
/// 对话消息原样。JSON 都缩进排好,贴给人看、贴给 AI 看都行。
///
/// 只出一个文件而不是服务端那样文本 + JSON 两份:手机上存两个文件要点两次保存,
/// 而这里每一轮的原始参数本来就不多,排进同一份里读得下。
String renderTraceExport({
  required List<AgentTrace> traces,
  required Map<String, Object?> settings,
  required List<Map<String, String>> nextHistory,
  required Map<String, Map<String, String>> resources,
  required List<Map<String, dynamic>> messages,
  required int now,
  required String appVersion,
}) {
  final b = StringBuffer();
  void head(String title) => b
    ..writeln()
    ..writeln('════════ $title ════════');
  void sub(String title) => b
    ..writeln()
    ..writeln('── $title ──');

  b
    ..writeln('Plana App · AI 助手对话记录')
    ..writeln('导出时间: ${traceTimestamp(now)}')
    ..writeln('App 版本: $appVersion')
    ..writeln('记录轮数: ${traces.length}(本对话里发出过的每一轮,含失败和重试)');

  head('当前设置');
  b.writeln(_json(settings));

  head('下一轮会带上的上下文');
  if (nextHistory.isEmpty) {
    b.writeln('(没有历史)');
  }
  for (final h in nextHistory) {
    b
      ..writeln('[${h['role']}]')
      ..writeln(h['content'])
      ..writeln();
  }
  sub('沿用资源账本');
  b.writeln(resources.isEmpty ? '(空)' : _json(resources));

  for (final (i, t) in traces.indexed) {
    final end = t.endedAt;
    final status = end == null
        ? '没有收尾(中途被关掉了)'
        : t.error == null
        ? '完成'
        : '失败:${t.error}';
    head(
      '第 ${i + 1} 轮 · ${traceTimestamp(t.startedAt)} · '
      '${t.route == AgentTrace.routeCustom ? '自定义接口' : '后端渠道'}'
      '${end == null ? '' : ' · ${_secs(end - t.startedAt)}'} · $status',
    );
    b
      ..writeln('用户: ${t.userText}')
      ..writeln();
    sub('设置');
    b.writeln(_json(t.settings));

    if (t.request != null) {
      sub('请求体');
      b.writeln(_json(t.request));
    }
    if (t.prequery != null) {
      sub('预匹配');
      b.writeln(_json(t.prequery));
    }
    if (t.system != null) {
      sub('系统提示');
      b.writeln(t.system);
    }
    if (t.messages != null) {
      sub('消息');
      for (final m in t.messages!) {
        b
          ..writeln('[${m['role']}]')
          ..writeln(m['content'])
          ..writeln();
      }
    }
    for (final (k, h) in t.hops.indexed) {
      sub(
        '第 ${k + 1} 跳 · +${_secs((h['t'] as num? ?? 0).toInt())}'
        '${h['ms'] is num ? ' · 模型用时 ${_secs((h['ms'] as num).toInt())}' : ''}',
      );
      b.writeln(h['reply']);
      if (h['tool_calls'] != null) {
        b
          ..writeln()
          ..writeln('工具调用:')
          ..writeln(_json(h['tool_calls']));
      }
      if (h['tool_results'] != null) {
        b
          ..writeln()
          ..writeln('工具结果:')
          ..writeln(h['tool_results']);
      }
      if (h['repairs'] != null) {
        b
          ..writeln()
          ..writeln('就地修好:')
          ..writeln(_json(h['repairs']));
      }
      if (h['feedback'] != null) {
        b
          ..writeln()
          ..writeln('回灌重写:')
          ..writeln(h['feedback']);
      }
      if (h['refusal'] != null) {
        b
          ..writeln()
          ..writeln('像拒绝:命中「${h['refusal']}」');
      }
    }
    if (t.events.isNotEmpty) {
      sub('收到的事件');
      for (final e in t.events) {
        b.writeln(
          '+${_secs((e['t'] as num? ?? 0).toInt())}  ${e['event']}  '
          '${_json(e['data'])}',
        );
      }
    }
  }

  head('对话消息(存档原样)');
  b.writeln(_json(messages));
  return b.toString();
}

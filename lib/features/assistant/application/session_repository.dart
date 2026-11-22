import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/store/atomic_file.dart';
import '../../../core/store/blob_store.dart';
import '../../../core/util/log.dart';
import '../agent_trace.dart';
import '../domain/conversation.dart';

/// AI 助手的对话存档(`<support>/assistant/sessions.json`):当前这段对话 +
/// 已归档的历史。防抖 800ms 写、原子落盘、退后台由 `AppStores.flushNow` 即刻冲刷。
///
/// 用户带的图不进 JSON,只留 blob 键 —— 所以 [liveRefs] 必须接进
/// `AppStores.postBootMaintenance` 的 GC 引用清单。
class SessionRepository {
  SessionRepository(this._blobs, Directory supportRoot)
    : _file = File('${supportRoot.path}/assistant/sessions.json');

  final BlobStore _blobs;
  final File _file;

  /// 存档格式版本。读到更低的先过 [migrate]。
  static const schemaVersion = 2;

  /// 启动读出的当前对话;空 = 首启/无存档。
  List<AssistantMsg> initialCurrent = const [];

  /// 启动读出的历史会话(新的在前)。
  List<ArchivedSession> initialSessions = const [];

  /// 历史最多留这么多段。
  static const maxSessions = 30;

  /// 启动读出的调试记录(当前对话的每一轮,见 [AgentTrace])。
  List<AgentTrace> initialTraces = const [];

  /// 调试记录最多留这么多轮。自定义接口那条一轮带着整份系统提示,几十 KB。
  static const maxTraces = 30;

  /// 调试记录单独一个文件,免得每改一个字就把几百 KB 的记录重写一遍。
  File get _traceFile => File('${_file.parent.path}/traces.json');

  /// 旧版存档 → 当前版本。
  ///
  /// v1 → v2:「纯文本格式」曾是模式之一,消息上写的是 `mode: noDraw`,改记成 `noDraw: true`;
  /// 错误消息上的 `errorKind` 不再使用。
  static Map<String, dynamic> migrate(Map<String, dynamic> j) {
    final v = (j['v'] as num?)?.toInt() ?? 1;
    if (v >= schemaVersion) return j;
    Object? msg(Object? m) {
      if (m is! Map<String, dynamic>) return m;
      final out = {...m}..remove('errorKind');
      if (out['mode'] == 'noDraw') {
        out
          ..remove('mode')
          ..['noDraw'] = true;
      }
      return out;
    }

    List<Object?> msgs(Object? l) => [
      if (l is List)
        for (final m in l) msg(m),
    ];
    return {
      ...j,
      'v': schemaVersion,
      'current': msgs(j['current']),
      'sessions': [
        if (j['sessions'] is List)
          for (final s in j['sessions'] as List)
            s is Map<String, dynamic> ? {...s, 'msgs': msgs(s['msgs'])} : s,
      ],
    };
  }

  Future<void> load() async {
    initialTraces = await _loadTraces();
    try {
      if (!await _file.exists()) return;
      final path = _file.path;
      final raw = await _decodeFileInIsolate(path);
      if (raw is! Map<String, dynamic>) return;
      final j = migrate(raw);
      initialCurrent = [
        for (final e in (j['current'] as List? ?? const []))
          if (e is Map<String, dynamic>) AssistantMsg.fromJson(e),
      ];
      initialSessions = [
        for (final e in (j['sessions'] as List? ?? const []))
          if (e is Map<String, dynamic>) ArchivedSession.fromJson(e),
      ];
    } catch (e) {
      logd('[assistant] 载入失败(按首启处理): $e');
      initialCurrent = const [];
      initialSessions = const [];
    }
  }

  Future<List<AgentTrace>> _loadTraces() async {
    try {
      if (!await _traceFile.exists()) return const [];
      final j = jsonDecode(await _traceFile.readAsString());
      return [
        for (final e in (j is Map ? j['traces'] : null) as List? ?? const [])
          if (e is Map<String, dynamic>) AgentTrace.fromJson(e),
      ];
    } catch (e) {
      logd('[assistant] 调试记录载入失败(当作没有): $e');
      return const [];
    }
  }

  /// 调试记录落盘。一轮收尾才写一次,不必防抖;和对话存档排同一条写队列。
  Future<void> saveTraces(List<AgentTrace> traces) {
    final snapshot = [for (final t in traces) t.toJson()];
    return _chain = _chain.then((_) async {
      try {
        await _traceFile.parent.create(recursive: true);
        await writeStringAtomic(
          _traceFile,
          jsonEncode({'v': 1, 'traces': snapshot}),
        );
      } catch (e) {
        logd('[assistant] 调试记录保存失败: $e');
      }
    });
  }

  /// 存一张用户带的图,返回 blob 键。失败返回 null(带图这一轮照发,只是不留存)。
  Future<String?> putImage(Uint8List bytes) async {
    try {
      return await _blobs.put(bytes);
    } catch (e) {
      logd('[assistant] 存图失败: $e');
      return null;
    }
  }

  Future<Uint8List?> image(String? hash) async {
    if (hash == null || hash.isEmpty) return null;
    try {
      return await _blobs.get(hash);
    } catch (_) {
      return null;
    }
  }

  List<AssistantMsg>? _pendingCurrent;
  List<ArchivedSession>? _pendingSessions;
  Timer? _timer;
  Future<void> _chain = Future.value();

  /// 状态一变就排队;真正写盘在防抖窗口后。
  void schedule(List<AssistantMsg> current, List<ArchivedSession> sessions) {
    _pendingCurrent = List.of(current);
    _pendingSessions = List.of(sessions);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), flush);
  }

  void flush() {
    final cur = _pendingCurrent;
    final ses = _pendingSessions;
    if (cur == null || ses == null) return;
    _pendingCurrent = null;
    _pendingSessions = null;
    _timer?.cancel();
    _chain = _chain.then((_) async {
      try {
        await _file.parent.create(recursive: true);
        await writeStringAtomic(
          _file,
          jsonEncode({
            'v': schemaVersion,
            'refs': _refsOf(cur, ses).toList(),
            'current': [for (final m in cur) m.toJson()],
            'sessions': [for (final s in ses) s.toJson()],
          }),
        );
      } catch (e) {
        logd('[assistant] 保存失败: $e');
      }
    });
  }

  static Set<String> _refsOf(
    List<AssistantMsg> current,
    List<ArchivedSession> sessions,
  ) => {
    for (final m in current) ...m.imageHashes,
    for (final s in sessions)
      for (final m in s.msgs) ...m.imageHashes,
  };

  /// 盘上存档引用的 blob 哈希(启动 GC 的引用清单)。
  Future<Set<String>> liveRefs() async {
    try {
      if (!await _file.exists()) return {};
      final path = _file.path;
      return await _refsInIsolate(path);
    } catch (_) {}
    return {};
  }
}

Future<Object?> _decodeFileInIsolate(String path) =>
    Isolate.run(() => jsonDecode(File(path).readAsStringSync()));

Future<Set<String>> _refsInIsolate(String path) => Isolate.run(() {
  final j = jsonDecode(File(path).readAsStringSync());
  return <String>{
    if (j is Map && j['refs'] is List)
      for (final r in j['refs'] as List)
        if (r is String) r,
  };
});

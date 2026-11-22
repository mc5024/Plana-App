import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/log.dart';

/// 一个任务在 [BotSocket] 上的订阅。
class BotSubscription {
  BotSubscription._(
    this._socket,
    this.taskId,
    this._onJson,
    this._onBinary,
    this._onResult,
  );

  final BotSocket _socket;
  final String taskId;
  final void Function(Map<String, dynamic> msg) _onJson;
  final void Function(Uint8List preview) _onBinary;
  final void Function(int index, int count, Uint8List bytes)? _onResult;

  bool _acked = false;
  bool _cancelled = false;

  /// 连接开着且服务端确认了这条订阅:进度和结果会从 WS 推过来。
  bool get live => _acked && _socket.isOpen;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _socket._unsubscribe(this);
  }
}

/// `/ws/bot` 常驻连接:进程内一条,连上即绑定会话,任务按 task_id 订阅分发。
///
/// 常驻([warm] 带 resident)时应用在前台就一直连着,断线自动重连;退到后台且
/// 没有订阅满 [_idleClose] 才关。有订阅时不论前后台都重连并重新订阅。订阅发出
/// [_ackTimeout] 内没收到确认,按连接已失效处理(手机切网后的半开连接)。
class BotSocket {
  BotSocket._();

  static final instance = BotSocket._();

  static const _connectTimeout = Duration(seconds: 12);
  static const _heartbeatEvery = Duration(seconds: 25);
  static const _ackTimeout = Duration(seconds: 5);
  static const _idleClose = Duration(minutes: 5);
  static const _graceClose = Duration(seconds: 30);

  String _base = '';
  String _sid = '';
  WebSocket? _ws;
  Future<void>? _connecting;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _idle;
  Timer? _reconnect;
  var _reconnectDelay = 1;
  DateTime _lastRx = DateTime.now();
  final _subs = <String, BotSubscription>{};
  final _ackTimers = <String, Timer>{};
  var _keep = false;
  var _foreground = true;

  bool get isOpen => _ws?.readyState == WebSocket.open;

  bool get _wanted => _subs.isNotEmpty || (_keep && _foreground);

  /// 提前连上并绑定;同一会话已连着(或正在连)时不做事。[resident] 为 true
  /// 之后前台常驻,否则没有订阅满 [_graceClose] 就关。
  void warm(String base, String sessionId, {bool resident = false}) {
    if (base.isEmpty || sessionId.isEmpty) return;
    if (resident) _keep = true;
    unawaited(_ensure(base, sessionId));
    if (_subs.isEmpty) _armIdle();
  }

  /// 不再常驻(退出 bot 模式 / 会话没了)。在跑的订阅不受影响,跑完即关。
  void stop() {
    _keep = false;
    if (_subs.isEmpty) _drop();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) {
      _idle?.cancel();
    } else if (_subs.isEmpty) {
      _armIdle();
    }
  }

  /// 订阅 [taskId] 的进度与结果。连接没好时先记下,连上后补发。
  /// [onResult] 收服务端推来的成图(先于完成消息到达;旧服务端不推)。
  BotSubscription subscribe({
    required String base,
    required String sessionId,
    required String taskId,
    required void Function(Map<String, dynamic> msg) onJson,
    required void Function(Uint8List preview) onBinary,
    void Function(int index, int count, Uint8List bytes)? onResult,
  }) {
    final sub = BotSubscription._(this, taskId, onJson, onBinary, onResult);
    _subs[taskId] = sub;
    _idle?.cancel();
    if (isOpen && base == _base && sessionId == _sid) {
      _sendSubscribe(sub);
    } else {
      unawaited(_ensure(base, sessionId));
    }
    return sub;
  }

  void _unsubscribe(BotSubscription sub) {
    if (_subs[sub.taskId] != sub) return;
    _subs.remove(sub.taskId);
    _ackTimers.remove(sub.taskId)?.cancel();
    if (isOpen) {
      _send({'action': 'unsubscribe_task', 'task_id': sub.taskId});
    }
    if (_subs.isEmpty) _armIdle();
  }

  Future<void> _ensure(String base, String sid) {
    if (base != _base || sid != _sid) {
      _drop();
      _base = base;
      _sid = sid;
      _connecting = null; // 旧会话那次连接回来时发现会话变了,会自己关掉
    }
    if (isOpen) return Future.value();
    final pending = _connecting;
    if (pending != null) return pending;
    late final Future<void> f;
    f = _connect().whenComplete(() {
      if (identical(_connecting, f)) _connecting = null;
    });
    return _connecting = f;
  }

  Future<void> _connect() async {
    _reconnect?.cancel();
    final base = _base;
    final sid = _sid;
    final url = '${base.replaceFirst(RegExp(r'^http'), 'ws')}/ws/bot';
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(url).timeout(_connectTimeout);
    } catch (e) {
      logi('[bot-ws] 连接失败: $e');
      _scheduleReconnect();
      return;
    }
    if (base != _base || sid != _sid) {
      unawaited(ws.close());
      return;
    }
    _ws = ws;
    _lastRx = DateTime.now();
    _reconnectDelay = 1;
    _sub = ws.listen(
      _onData,
      onDone: () => _onClosed(ws),
      onError: (_) => _onClosed(ws),
      cancelOnError: true,
    );
    _send({'action': 'bind_session', 'session_id': sid, 'result_frames': true});
    for (final s in _subs.values) {
      _sendSubscribe(s);
    }
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) => _beat());
    if (_subs.isEmpty) _armIdle();
  }

  void _beat() {
    if (!isOpen) return;
    // 服务端每个心跳都回 heartbeat_ack,两轮多没收到任何消息就是连接失效
    if (DateTime.now().difference(_lastRx) > _heartbeatEvery * 2.4) {
      logi('[bot-ws] 心跳无应答,重连');
      _restart();
      return;
    }
    _send({'action': 'heartbeat'});
  }

  void _sendSubscribe(BotSubscription s) {
    s._acked = false;
    _send({'action': 'subscribe_task', 'task_id': s.taskId});
    final ws = _ws;
    _ackTimers.remove(s.taskId)?.cancel();
    _ackTimers[s.taskId] = Timer(_ackTimeout, () {
      _ackTimers.remove(s.taskId);
      if (identical(ws, _ws) && _subs[s.taskId] == s && !s._acked) {
        logi('[bot-ws] ${s.taskId} 订阅无确认,重连');
        _restart();
      }
    });
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _onData(dynamic raw) {
    _lastRx = DateTime.now();
    if (raw is List<int>) {
      _onFrame(raw);
      return;
    }
    if (raw is! String) return;
    final Map<String, dynamic> m;
    try {
      final d = jsonDecode(raw);
      if (d is! Map<String, dynamic>) return;
      m = d;
    } catch (_) {
      return;
    }
    final id = m['task_id'];
    if (id is! String) return;
    final s = _subs[id];
    if (s == null) return;
    if (m['action'] == 'subscribed') {
      _ackTimers.remove(id)?.cancel();
      s._acked = m['success'] == true;
      return;
    }
    s._onJson(m);
  }

  /// 二进制帧:头 24 字节 ver(1) type(1) step(2) total(2) fmt(1) 保留(1)
  /// task_id(16 ASCII),其余是图片字节。type 1 = 预览帧;type 2 = 成图帧,
  /// 此时 step / total 是这张在批里的序号和张数。
  void _onFrame(List<int> raw) {
    if (raw.length <= 24) return;
    final b = raw is Uint8List ? raw : Uint8List.fromList(raw);
    if (b[0] != 1) return;
    var id = '';
    for (var i = 8; i < 24 && b[i] != 0; i++) {
      id += String.fromCharCode(b[i]);
    }
    final s = _subs[id];
    if (s == null) return;
    switch (b[1]) {
      case 1:
        s._onBinary(Uint8List.sublistView(b, 24));
      case 2:
        s._onResult?.call(
          (b[2] << 8) | b[3],
          (b[4] << 8) | b[5],
          b.sublist(24),
        );
    }
  }

  void _onClosed(WebSocket ws) {
    if (!identical(ws, _ws)) return;
    _teardown();
    _scheduleReconnect();
  }

  /// 换一条新连接,订阅照旧。
  void _restart() {
    _drop();
    if (_wanted) unawaited(_ensure(_base, _sid));
  }

  void _scheduleReconnect() {
    if (!_wanted || _reconnect?.isActive == true) return;
    final delay = Duration(seconds: _reconnectDelay);
    _reconnectDelay = _reconnectDelay >= 8 ? 10 : _reconnectDelay * 2;
    _reconnect = Timer(delay, () {
      if (_wanted) unawaited(_ensure(_base, _sid));
    });
  }

  /// 常驻:前台不关,后台没有订阅满 [_idleClose] 关。不常驻:满 [_graceClose] 关。
  void _armIdle() {
    _idle?.cancel();
    if (_keep && _foreground) return;
    _idle = Timer(_keep ? _idleClose : _graceClose, () {
      if (_subs.isEmpty) _drop();
    });
  }

  void _teardown() {
    _heartbeat?.cancel();
    _heartbeat = null;
    for (final t in _ackTimers.values) {
      t.cancel();
    }
    _ackTimers.clear();
    for (final s in _subs.values) {
      s._acked = false;
    }
    unawaited(_sub?.cancel());
    _sub = null;
    _ws = null;
  }

  void _drop() {
    final ws = _ws;
    _teardown();
    _reconnect?.cancel();
    _idle?.cancel();
    if (ws != null) unawaited(ws.close());
  }
}

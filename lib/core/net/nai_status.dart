import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/app_stores.dart';
import '../../l10n/l10n.dart';
import 'backend_client.dart';

/// NovelAI 官方服务状态(后端 `/api/nai-status`,转发自 status.io)。
///
/// 判断规则与 web 端 `naiStatus.ts` 一致:只看图像生成;登录、支付、官网的
/// 事故不算,开始超过一天的事故不算。

/// status.io 状态码:100 正常、200 维护、300 性能下降、400 部分中断、
/// 500 服务中断、600 安全事件。
const kNaiStatusOk = 100;

class NaiStatusComponent {
  const NaiStatusComponent({
    required this.name,
    required this.status,
    this.code,
  });

  final String name;
  final String status;
  final int? code;
}

class NaiStatusIncident {
  const NaiStatusIncident({
    required this.id,
    required this.name,
    required this.status,
    required this.components,
    required this.url,
    this.code,
    this.datetime,
  });

  final String id;
  final String name;
  final String status;
  final int? code;
  final List<String> components;
  final String url;
  final String? datetime;
}

class NaiStatusData {
  const NaiStatusData({
    required this.components,
    required this.incidents,
    required this.pageUrl,
  });

  final List<NaiStatusComponent> components;
  final List<NaiStatusIncident> incidents;
  final String pageUrl;
}

/// 需要提醒的一次异常。
class NaiStatusAlert {
  const NaiStatusAlert({
    required this.code,
    required this.title,
    required this.url,
    required this.keys,
  });

  /// 严重度(取最严重的事故,没有事故时取图像生成组件的状态码)。
  final int? code;

  /// 官方填的事故名;只有组件异常、没有事故时为 null。
  final String? title;

  /// 事故页,没有事故时是状态页首页。
  final String url;

  /// 提醒去重用的键:每条事故一个,只有组件异常时是 `image:<code>`。
  final List<String> keys;
}

const kNaiStatusPageUrl = 'https://status.novelai.net/';

int? _int(Object? v) => switch (v) {
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

/// 解析 `/api/nai-status` 的响应;`ok` 为 false(后端还没抓到过)时返回 null。
NaiStatusData? parseNaiStatus(Map<String, dynamic> j) {
  final data = j['data'];
  if (j['ok'] != true || data is! Map) return null;
  final components = [
    for (final c in (data['components'] as List?) ?? const [])
      if (c is Map)
        NaiStatusComponent(
          name: _str(c['name']),
          status: _str(c['status']),
          code: _int(c['code']),
        ),
  ];
  final pageUrl = _str(data['page_url']);
  final incidents = [
    for (final i in (data['incidents'] as List?) ?? const [])
      if (i is Map)
        NaiStatusIncident(
          id: _str(i['id']),
          name: _str(i['name']),
          status: _str(i['status']),
          code: _int(i['code']),
          components: [
            for (final c in (i['components'] as List?) ?? const [])
              if (c is String) c,
          ],
          url: _str(i['url']),
          datetime: i['datetime'] is String ? i['datetime'] as String : null,
        ),
  ];
  return NaiStatusData(
    components: components,
    incidents: incidents,
    pageUrl: pageUrl.isEmpty ? kNaiStatusPageUrl : pageUrl,
  );
}

bool _isImageComponent(String name) =>
    name.trim().toLowerCase() == 'image generation';

bool _affectsImage(NaiStatusIncident i) => i.components.any(_isImageComponent);

/// 开始超过一天;开始时间读不出的算没过期。
bool _isStale(NaiStatusIncident i, DateTime now) {
  final t = i.datetime == null ? null : DateTime.tryParse(i.datetime!);
  return t != null && now.difference(t) > const Duration(hours: 24);
}

/// 当前要提醒的异常,没有返回 null。
///
/// 有影响图像生成、开始不到一天的事故就提醒;没有这类事故但图像生成组件
/// 不是正常状态也提醒。影响出图的事故都已超过一天时不提醒。
NaiStatusAlert? naiStatusAlert(NaiStatusData? data, {DateTime? now}) {
  if (data == null) return null;
  final at = now ?? DateTime.now();
  final incidents = [
    for (final i in data.incidents)
      if (_affectsImage(i) && !_isStale(i, at)) i,
  ];
  if (incidents.isNotEmpty) {
    final primary = incidents.reduce(
      (a, b) => (b.code ?? 0) > (a.code ?? 0) ? b : a,
    );
    return NaiStatusAlert(
      code: primary.code,
      title: primary.name.isEmpty ? null : primary.name,
      url: primary.url.isEmpty ? data.pageUrl : primary.url,
      keys: [
        for (final i in incidents)
          i.id.isNotEmpty
              ? i.id
              : [i.name, i.datetime, i.code].whereType<Object>().join(':'),
      ],
    );
  }
  if (data.incidents.any(_affectsImage)) return null;
  final code = data.components
      .where((c) => _isImageComponent(c.name))
      .firstOrNull
      ?.code;
  if (code == null || code == kNaiStatusOk) return null;
  return NaiStatusAlert(
    code: code,
    title: null,
    url: data.pageUrl,
    keys: ['image:$code'],
  );
}

/// 提示里的状态那一行。
String naiStatusLine(AppLocalizations l, NaiStatusAlert alert) =>
    l.naiStatusLine(switch (alert.code ?? 0) {
      >= 600 => l.naiStateSecurity,
      >= 500 => l.naiStateDown,
      >= 400 => l.naiStatePartial,
      >= 300 => l.naiStateDegraded,
      200 => l.naiStateMaintenance,
      _ => l.naiStateIssue,
    });

/// 前台轮询间隔。
const kNaiStatusPoll = Duration(minutes: 5);

const _seenKey = 'nai_status_seen';

/// 最近一次拿到的状态;拉取失败保留上次结果。
final naiStatusProvider = NotifierProvider<NaiStatusNotifier, NaiStatusData?>(
  NaiStatusNotifier.new,
);

class NaiStatusNotifier extends Notifier<NaiStatusData?> {
  Timer? _timer;
  DateTime? _fetchedAt;
  Future<void>? _inflight;

  /// 已提醒过的去重键(见 [NaiStatusAlert.keys])。
  late final Set<String> _seen = _loadSeen();

  @override
  NaiStatusData? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// 前台:立即拉一次,之后每 [kNaiStatusPoll] 拉一次;后台:停止。
  void setForeground(bool on) {
    _timer?.cancel();
    _timer = null;
    if (!on) return;
    unawaited(refresh());
    _timer = Timer.periodic(kNaiStatusPoll, (_) => unawaited(refresh()));
  }

  /// 拉一次;距上次成功不到 [maxAge] 时跳过。
  Future<void> refresh({Duration maxAge = Duration.zero}) {
    final at = _fetchedAt;
    if (at != null && DateTime.now().difference(at) < maxAge) {
      return Future.value();
    }
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<void> _fetch() async {
    try {
      final j = await ref.read(backendClientProvider).getNaiStatus();
      _fetchedAt = DateTime.now();
      final data = parseNaiStatus(j);
      if (data != null) _pruneSeen(naiStatusAlert(data)?.keys ?? const []);
      state = data;
    } catch (_) {}
  }

  /// 当前异常里还没提醒过的那次,没有返回 null。
  NaiStatusAlert? unseenAlert() {
    final alert = naiStatusAlert(state);
    if (alert == null || alert.keys.every(_seen.contains)) return null;
    return alert;
  }

  void markSeen(NaiStatusAlert alert) {
    if (_seen.containsAll(alert.keys)) return;
    _seen.addAll(alert.keys);
    _saveSeen();
  }

  /// 只留眼下还挂着的键:异常结束后再出现同样的组件状态会重新提醒。
  void _pruneSeen(List<String> active) {
    final before = _seen.length;
    _seen.retainAll(active);
    if (_seen.length != before) _saveSeen();
  }

  Set<String> _loadSeen() {
    try {
      final raw = ref.read(prefsStoreProvider).get(_seenKey);
      if (raw == null) return {};
      return {...(jsonDecode(raw) as List).whereType<String>()};
    } catch (_) {
      return {};
    }
  }

  void _saveSeen() {
    try {
      unawaited(
        ref
            .read(prefsStoreProvider)
            .write(
              key: _seenKey,
              value: _seen.isEmpty ? null : jsonEncode(_seen.toList()),
            ),
      );
    } catch (_) {}
  }
}

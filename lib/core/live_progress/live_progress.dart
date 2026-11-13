import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';

/// 该设备/权限下的上岛能力(供 UI 决定是否提示"仅新系统可上岛")。
class LiveCaps {
  const LiveCaps({this.sdkInt = 0, this.canPromote = false});

  final int sdkInt;

  /// API 36+ 且已获准时为 true:进度会被系统提升到状态栏胶囊/锁屏(灵动岛)。
  final bool canPromote;
}

/// 后台生成进度:前台服务(保活)+ 常驻通知,API 36 自动上灵动岛/状态栏胶囊。
///
/// 纯原生实现,见 android/.../LiveProgressService.kt。非 Android 平台全部 no-op,
/// 且所有调用都吞异常——通知只是锦上添花,绝不能因它拖垮生成主流程。
///
/// [start] / [update] / [finish] / [stop] 归出图用;AI 助手一轮走
/// [beginAssistant] / [endAssistant] / [cancelAssistant],两边共用同一条服务与通知:
/// 出图在跑时显示归出图,助手只记一笔;出图先收尾时常驻那条交还给助手,服务不停。
class LiveProgress {
  LiveProgress._();
  static final LiveProgress instance = LiveProgress._();

  static const MethodChannel _ch = MethodChannel('plana/live_progress');

  static String get _assistantTitle => l10nNow.lpAssistantThinking;
  static String get _assistantShort => l10nNow.lpAssistantThinkingShort;

  bool get _on => Platform.isAndroid;
  bool _permAsked = false;

  /// 出图占着通知:[start] 起,[finish] / [stop] 止。
  bool _gen = false;

  /// AI 助手一轮在跑。
  bool _assistant = false;

  /// 出图是否已占着通知。循环、队列续张时据此就地 [update],而不是再 [start]
  /// ——重复 start 会 startForegroundService 重拉,让灵动岛胶囊消失再弹出。
  bool get active => _gen;

  /// 首次使用前拉起通知权限(API 33+),幂等;失败静默。
  Future<void> ensurePermission() async {
    if (!_on || _permAsked) return;
    _permAsked = true;
    await _quiet('requestNotificationPermission');
  }

  Future<LiveCaps> capabilities() async {
    if (!_on) return const LiveCaps();
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('capabilities');
      return LiveCaps(
        sdkInt: (m?['sdkInt'] as int?) ?? 0,
        canPromote: (m?['canPromote'] as bool?) ?? false,
      );
    } catch (_) {
      return const LiveCaps();
    }
  }

  /// 开启前台服务 + 初始通知。[total]>0 时用确定态进度条(0/total),这样从
  /// 「准备」起就走可上岛的 ProgressStyle(而非等有步数才提升,单图会错过整段)。
  ///
  /// [title] 是通知的主行,**要带状态**:通知头已经写着应用名了,主行再写一遍
  /// 「Plana」等于白占一行。[text] 是副行,没有可留空(留空则不渲染那一行)。
  Future<void> start({String? title, String text = '', int total = 0}) {
    title ??= l10nNow.lpPreparing;
    final running = _gen || _assistant;
    _gen = true;
    // 服务已被 AI 助手拉起:就地换成出图的样子
    if (running) {
      return update(
        total: total,
        indeterminate: total <= 0,
        title: title,
        text: text,
        short: total > 0 ? '0/$total' : l10nNow.shortPreparing,
      );
    }
    return _quiet('start', {
      'title': title,
      'text': text,
      'total': total,
      'short': total > 0 ? '0/$total' : l10nNow.shortPreparing,
    });
  }

  /// 刷新进度。[step]<=0 或 [indeterminate] 走不确定态;否则 step/total 进度条。
  /// [short] 是状态栏胶囊文案(≤7 字符最稳,如 "14/28")。
  Future<void> update({
    int step = 0,
    int total = 0,
    bool indeterminate = false,
    String title = 'Plana',
    String text = '',
    String short = '',
  }) {
    // 出图已收尾、通知交还给了 AI 助手:迟到的进度帧不再覆盖
    if (!_gen && _assistant) return Future.value();
    return _quiet('update', {
      'cur': step,
      'total': total,
      'indeterminate': indeterminate,
      'title': title,
      'text': text,
      'short': short,
    });
  }

  /// 收尾。能上岛时先把岛改成完成态停留几秒(否则岛是直接消失的,没有完成反馈),
  /// 再按 [keep] 落地:
  ///  - [keep] true(应用在后台):留一条非常驻、可点开的通知当回来的入口;
  ///  - [keep] false(应用在前台):通知一并撤掉,结果本来就在眼前。
  ///
  /// AI 助手还在跑时,完成态停留完服务不停,常驻那条换回助手的状态。
  Future<void> finish({
    String? title,
    String text = '',
    String? short,
    bool keep = true,
  }) {
    _gen = false;
    return _quiet('finish', {
      'title': title ?? l10nNow.lpGenDone,
      'text': text,
      'short': short ?? l10nNow.shortDone,
      'keep': keep,
      if (_assistant) 'next': _assistantTitle,
      if (_assistant) 'nextShort': _assistantShort,
    });
  }

  /// 静默撤掉通知与服务(前台时用)。AI 助手还在跑时只换回助手的状态。
  Future<void> stop() {
    _gen = false;
    if (_assistant) return _showAssistant();
    return _quiet('stop');
  }

  /// AI 助手一轮开始:拉起前台服务保活。出图占着时服务已在,只记一笔。
  ///
  /// 几条通道调用之间不 await:要保证先于随后可能到来的 [endAssistant] 送到原生侧。
  void beginAssistant() {
    if (_assistant) return;
    _assistant = true;
    if (_gen) return;
    unawaited(ensurePermission());
    unawaited(
      _quiet('start', {'title': _assistantTitle, 'text': '', 'total': 0}),
    );
    unawaited(_showAssistant());
  }

  String? _channelLang;

  /// 系统设置里两条通知渠道的名字跟界面语言走。同一语言只发一次。
  void syncChannelNames(AppLocalizations l) {
    if (!_on || _channelLang == l.localeName) return;
    _channelLang = l.localeName;
    unawaited(
      _quiet('channels', {
        'progress': l.channelProgress,
        'progressDesc': l.channelProgressDesc,
        'done': l.channelDone,
        'doneDesc': l.channelDoneDesc,
      }),
    );
  }

  /// AI 助手一轮结束。出图占着时不动通知;否则同出图的 [finish]。
  void endAssistant({required bool success, required bool keep}) {
    if (!_assistant) return;
    _assistant = false;
    if (_gen) return;
    unawaited(
      _quiet('finish', {
        'title': success
            ? l10nNow.lpAssistantReplied
            : l10nNow.lpAssistantFailed,
        'text': keep ? (success ? l10nNow.tapToView : l10nNow.tapToReturn) : '',
        'short': success ? l10nNow.shortDone : l10nNow.shortFailed,
        'keep': keep,
      }),
    );
  }

  /// AI 助手这轮被停下:静默撤掉。出图占着时不动通知。
  void cancelAssistant() {
    if (!_assistant) return;
    _assistant = false;
    if (!_gen) unawaited(_quiet('stop'));
  }

  Future<void> _showAssistant() => _quiet('update', {
    'cur': 0,
    'total': 0,
    'indeterminate': true,
    'title': _assistantTitle,
    'text': '',
    'short': _assistantShort,
  });

  Future<void> _quiet(String method, [Object? args]) async {
    if (!_on) return;
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {
      // 通知层任何失败都不应影响生成
    }
  }
}

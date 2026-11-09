import 'package:flutter/widgets.dart';

/// 正文滚动 → 顶栏与权重面板该收还是该放(浏览器地址栏同款):往下翻收起;
/// 往回翻、翻回顶上、或在顶上继续往下拽,放出来。
///
/// 纯判定,不碰界面:页面把正文的 [ScrollNotification] 喂给 [update],拿回
/// 新状态(null = 不变),自己去收放。单独拎出来是为了能脱离整页单测 —— 这里
/// 的坑全是「收起那一下视口变高、位置被夹回」这种只有真滚起来才碰得到的。
///
/// 正文的滚动视图要配 [AlwaysScrollableScrollPhysics]:收起之后正文可能一屏
/// 就放得下,那时滚动视图不再接拖动,「顶上往下拽」这条放出的路就断了。
class ChromeScrollTracker {
  ChromeScrollTracker({this.hideAfter = 16, this.showAfter = 28});

  /// 同一方向上连续拖多远才收 / 才放。放比收多要一截:往下翻的途中手指
  /// 稍微回一下,不该让两块东西闪出来。
  final double hideAfter;
  final double showAfter;

  /// 本次手势里同向连续拖动的累计位移(带符号,正 = 往下翻)。
  double _run = 0;

  /// [hidden] 是眼下收着没有。
  bool? update(ScrollNotification n, {required bool hidden}) {
    // 只认正文自己那一层:芯片输入框、文本框内部的滚动都在更深处
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return null;
    final m = n.metrics;
    final atTop = m.pixels <= m.minScrollExtent;
    switch (n) {
      case ScrollStartNotification():
        _run = 0; // 每次起手重攒,不沿用上一把
      case OverscrollNotification(:final overscroll, :final dragDetails):
        // 已经在顶上还往下拽:没有「往回翻」的距离可攒了,直接放
        if (hidden && dragDetails != null && overscroll < 0) return false;
      case ScrollUpdateNotification(:final scrollDelta, :final dragDetails):
        if (dragDetails == null) {
          // 惯性 / 回弹:只有往回甩、一路甩到顶才放。往下翻收起后视口变高,
          // 越界的位置会被弹回去,弹到顶也算「到顶」—— 可那时攒的是往下翻,
          // 这时候放出来就是收起 → 弹回顶 → 又放出,来回闪。
          if (hidden && atTop && _run < 0) return false;
          return null;
        }
        final d = scrollDelta ?? 0;
        if (d == 0) return null;
        if ((d > 0) != (_run > 0)) _run = 0; // 换向重攒
        _run += d;
        if (!hidden && _run >= hideAfter) return true;
        if (hidden && (_run <= -showAfter || atTop)) return false;
    }
    return null;
  }
}

/// 正文视口变矮(权重面板弹出 / 顶栏放出 / 补全展开层顶上来)时,该不该把
/// 「刚点的那一处」拉回视野。
///
/// 滚动位置按顶边记,视口从底下变矮,底下那截就被吃掉 —— 刚点的词正好在下面,
/// 面板一出来就把它盖住。键盘升起时框架自己会追光标(`EditableText.didChangeMetrics`),
/// 面板和顶栏没人管,这里补上。
///
/// 只管「点了之后还没手动滚过」的:自己滚走了的,视口再怎么变也不往回拽。
/// 正文那层把通知原样喂给 [update];视口每帧矮一点就追一下,面板展开的动画
/// 期间是一路跟着走的。
class KeepInViewTracker {
  double? _viewport;
  bool _armed = false;

  /// 点了一处(落光标 / 点芯片):之后视口变矮,把它留在视野里。
  void arm() => _armed = true;

  /// true = 视口刚变矮,该把目标拉回视野了。
  bool update(Notification n) {
    // 只认正文自己那一层,同 [ChromeScrollTracker]
    if (n is! ViewportNotificationMixin || n.depth != 0) return false;
    switch (n) {
      case ScrollStartNotification(dragDetails: _?):
        _armed = false; // 手动滚了
      case ScrollMetricsNotification(:final metrics)
          when metrics.axis == Axis.vertical:
        final was = _viewport;
        _viewport = metrics.viewportDimension;
        return _armed && was != null && metrics.viewportDimension < was;
    }
    return false;
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 图片加载完淡入,但**只淡第一次**:缓存命中的同步图不淡,之后同一张图再换流
/// (换解码宽、内容更新)也不淡。
///
/// 后一条是给能换列数的网格准备的。解码宽跟着格宽变,Image 换流时会把帧号清回
/// null —— gaplessPlayback 下旧图其实还挂着,可「帧号为 null 就透明」的
/// frameBuilder 会让整屏卡片先暗下去再亮起来。
class FadeInOnce extends StatefulWidget {
  const FadeInOnce({
    super.key,
    required this.source,
    required this.builder,
    this.hold = false,
    this.onShown,
  });

  /// 图的身份(URL / 路径)。变了就是换了一张图,照常淡入。
  final Object? source;

  /// 出帧了也先不露面;放开时才淡入。
  final bool hold;

  /// 这张图头一回出帧时回调(排在这一帧之后,回调里可以直接 setState)。
  final VoidCallback? onShown;

  /// 拿着 frameBuilder 造出 Image。
  final Widget Function(BuildContext context, ImageFrameBuilder frameBuilder)
  builder;

  @override
  State<FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<FadeInOnce> {
  /// 这张图出过帧了。
  bool _shown = false;

  @override
  void didUpdateWidget(FadeInOnce old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _shown = false;
  }

  Widget _frame(BuildContext context, Widget child, int? frame, bool wasSync) {
    if (frame != null && !_shown) {
      _shown = true;
      if (widget.onShown case final cb?) {
        WidgetsBinding.instance.addPostFrameCallback((_) => cb());
      }
    }
    // 同步命中时首帧就带着帧号,opacity 从 1 起步,不会有动画
    return AnimatedOpacity(
      opacity: _shown && !widget.hold ? 1 : 0,
      duration: Motion.medium,
      curve: Curves.easeOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _frame);
}

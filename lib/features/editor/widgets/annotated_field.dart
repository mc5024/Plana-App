import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart' show computePanSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart';
import '../chrome_scroll.dart';
import '../data/suggestions.dart' show transCacheRev;
import '../editor_models.dart';
import 'rich_tag_controller.dart';

/// 行距分配策略:注音行高(2.0)默认按**比例**分配行距,会把绝大部分行距塞到
/// 基线**上方**(升部权重远大于降部),基线下方几乎不留白——结果正文连同权重
/// 底色被压到行槽下半部,上方空一截,看着「偏下」。改为 even(均分):正文回到
/// 行槽垂直居中,权重底色随之居中,译文改用基线下方那半行距落位。
/// TextField 与权重底色层 / 注音层三者必须共用同款,否则垂直不同构、底色再度错位。
const TextHeightBehavior _kEvenLeading = TextHeightBehavior(
  leadingDistribution: TextLeadingDistribution.even,
);

/// 表面 · 注音流(光标驱动富文本):
/// 一个真正可编辑的 [TextField](光标点哪改哪、词内可改字、权重原样显示),
/// 下叠 [_FuriganaPainter],按每枚标签**名字范围**把中文当「注音」画在下方。
/// 二者共用同一套文本布局,故翻译与词严格对齐。
/// (排序模式由 SortChipsView 整体替换本视图,这里不再承担排序职责。)
class AnnotatedField extends StatefulWidget {
  const AnnotatedField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.showTrans = true,
    this.showWeightWash = true,
    this.fontSize = 16,
    this.onCursorDrag,
    this.scrollController,
    this.onFoldTap,
  });

  final RichTagController controller;
  final FocusNode focusNode;
  final String hint;

  /// 注音翻译开关(编辑器设置):关=摘除注音层,行高收紧不再为译文留白。
  final bool showTrans;

  /// 权重底色开关(编辑器设置):关=整层摘除,正文回到纯文本。
  final bool showWeightWash;

  /// 正文字号(编辑器设置):TextField 与注音测量层必须同字号(布局同构)。
  final double fontSize;

  /// 正在拖水滴手柄挪光标 / 拽选区:true=起拖,false=松手。
  /// 页面据此把吸底的词条栏收起来 —— 拖光标时它正好压在手指下方那一片。
  final ValueChanged<bool>? onCursorDrag;

  final ScrollController? scrollController;

  /// 单击折叠标题 `#名字`:一次性解散(记号删掉、内容平铺)。
  final void Function(String name)? onFoldTap;

  @override
  State<AnnotatedField> createState() => _AnnotatedFieldState();
}

class _AnnotatedFieldState extends State<AnnotatedField> {
  /// 底色层 / 注音层是按设置条件挂进 Stack 的,开关一动 TextField 的兄弟下标
  /// 就变了 —— 没有这把全局 key,框架会按位置改嫁,把输入框连同焦点和选区
  /// 一起重建。
  final _fieldKey = GlobalKey();

  late final _handles = _WatchedHandles(this);

  /// 手柄上按住的那根指头起点,以及是否已经越过 slop 判成「在拖」。
  Offset? _fingerDown;
  bool _dragging = false;

  void _setDragging(bool v) {
    if (_dragging == v) return;
    _dragging = v;
    widget.onCursorDrag?.call(v);
  }

  void _pointerDown(PointerDownEvent e) => _fingerDown = e.position;

  /// 按下不等于在拖:点手柄是弹工具栏,不该把词条栏也一起收走。走够
  /// [computePanSlop] 才算 —— 那正是框架那颗 pan 认账、光标开始跟着走的门槛。
  void _pointerMove(PointerMoveEvent e) {
    final from = _fingerDown;
    if (from == null || _dragging) return;
    final slop = computePanSlop(e.kind, MediaQuery.gestureSettingsOf(context));
    if ((e.position - from).distance > slop) _setDragging(true);
  }

  void _pointerUp() {
    _fingerDown = null;
    if (_dragging) {
      // 最后一下拖动排在帧尾的那次滚动可能松手后才跑:这一帧照样拦着,
      // 不然松手那一下会被拽去露选区末尾(见 [_HandleDragReveal])
      _revealHold = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealHold = false);
    }
    _setDragging(false);
  }

  /// 松手后还要再拦一帧,见 [_pointerUp]。
  bool _revealHold = false;

  /// 拖手柄时贴边滚动留的边距,算法照抄 `EditableText._scheduleShowCaretOnScreen`:
  /// 四边 20(TextField.scrollPadding 的默认值),底下再让出手柄。手柄尺寸与锚点
  /// 都和行高无关,行高传 0 即可。
  EdgeInsets get _revealPadding {
    final h = _handles.getHandleSize(0).height;
    final center =
        h / 2 -
        _handles.getHandleAnchor(TextSelectionHandleType.collapsed, 0).dy;
    return const EdgeInsets.all(20).copyWith(
      bottom: math.max(center + math.max(h, kMinInteractiveDimension) / 2, 20),
    );
  }

  /// 权重面板 / 补全展开层把视口压矮时,光标那一行别被盖住。见 [KeepInViewTracker]。
  final _keep = KeepInViewTracker();
  TextSelection? _lastSel;

  /// 光标挪了(点词、改字、面板加减权重)= 手上操作的就是这一处。
  void _onController() {
    final sel = widget.controller.selection;
    if (sel == _lastSel) return;
    _lastSel = sel;
    _keep.arm();
  }

  /// 把光标那一行拉回视野,留边与框架露光标同一套([_revealPadding])。
  void _revealCaret() {
    final sel = widget.controller.selection;
    final ed = widget.focusNode.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.renderEditable;
    if (!sel.isValid || ed == null || !ed.attached) return;
    ed.showOnScreen(
      rect: _revealPadding.inflateRect(ed.getLocalRectForCaret(sel.extent)),
    );
  }

  /// 兜底:手柄只在有焦点时挂着,焦点一丢它连同上面那层 [Listener] 一起拆掉,
  /// 松手事件就没人收了 —— 不在这里补一刀,拖动态会卡住,词条栏再也不出来。
  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _pointerUp();
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    _lastSel = widget.controller.selection;
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(AnnotatedField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final pal = context.editor;
    final scaler = MediaQuery.textScalerOf(context);
    final base = kEditorBaseStyle.copyWith(
      fontSize: widget.fontSize,
      height: widget.showTrans ? null : 1.5,
    );

    return NotificationListener<Notification>(
      onNotification: (n) {
        if (_keep.update(n)) _revealCaret();
        return false;
      },
      child: SingleChildScrollView(
        controller: widget.scrollController,
        // 一屏放得下也照样接拖动:编辑页滚动收起顶栏后,靠「顶上往下拽」
        // 放出来(见 ChromeScrollTracker)
        physics: const AlwaysScrollableScrollPhysics(),
        // 顶部只留 2:第一行 2 倍行高自带约 6 的上半行距,再多就和顶栏隔得太开
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                // 折叠底纹层(最底):标题 `#名字` 一颗药丸,点它即解散。
                // 不受权重高亮开关影响:折叠是结构,不是权重。
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: widget.controller,
                      builder: (_, _) => CustomPaint(
                        painter: _FoldPainter(
                          text: widget.controller.text,
                          bodies: widget.controller.foldBodies,
                          base: base,
                          maxWidth: width - _kCaretMargin,
                          scaler: scaler,
                          withSpacing: widget.showTrans,
                          title: scheme.primary.withValues(alpha: .16),
                          revision: transCacheRev,
                        ),
                      ),
                    ),
                  ),
                ),
                // 权重底色层:贴字形高度的圆角色带,范围含权重记号,
                // 组=开记号到闭记号整条;嵌套/叠加权重=多层半透明叠色。
                if (widget.showWeightWash)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: widget.controller,
                        builder: (_, _) => CustomPaint(
                          painter: _WeightWashPainter(
                            text: widget.controller.text,
                            base: base,
                            maxWidth: width - _kCaretMargin,
                            scaler: scaler,
                            withSpacing: widget.showTrans,
                            pal: pal,
                            sdWash: scheme.tertiary,
                            disabledWash: scheme.onSurface,
                            revision: transCacheRev,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.showTrans)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: widget.controller,
                        builder: (_, _) => CustomPaint(
                          painter: _FuriganaPainter(
                            text: widget.controller.text,
                            base: base,
                            // RenderEditable 排版时给光标留 cursorWidth+1 的边距,
                            // 注音层必须用同一宽度重排,否则临界行折点不一致,
                            // 折点一岔开整行注音全错位(真机截图踩过)。
                            maxWidth: width - _kCaretMargin,
                            color: scheme.onSurfaceVariant,
                            scaler: scaler,
                            revision: transCacheRev,
                          ),
                        ),
                      ),
                    ),
                  ),
                // EditableText 无 textHeightBehavior 直参,靠 DefaultTextHeightBehavior
                // 下发 even——与上面两个绘制层同款行距,底色/注音才与字严格对齐。
                _HandleDragReveal(
                  active: () => _dragging || _revealHold,
                  padding: _revealPadding,
                  child: DefaultTextHeightBehavior(
                    textHeightBehavior: _kEvenLeading,
                    child: TextField(
                      key: _fieldKey,
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      style: base.copyWith(color: scheme.onSurface),
                      maxLines: null,
                      cursorColor: pal.cursor,
                      cursorWidth: _kCursorWidth,
                      selectionControls: _handles,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: base.copyWith(color: scheme.outline),
                      ),
                    ),
                  ),
                ),
                // 折叠标题点击层(最上):**只**覆盖 `#名字` 矩形,单击 = 一次性解散。
                // 独立热区而不是靠光标落点驱动 —— 光标移动/方向键/选择经过折叠时
                // 不再误触发;矩形之外没有 widget,点击照常穿透给 TextField 定位
                // 光标。同一 controller 布局,矩形与绘制层严格对齐。
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: widget.controller,
                    builder: (_, _) {
                      final rects = _foldTitleRects(
                        widget.controller.text,
                        widget.controller.foldBodies,
                        base: base,
                        maxWidth: width - _kCaretMargin,
                        scaler: scaler,
                      );
                      if (rects.isEmpty) return const SizedBox.shrink();
                      return Stack(
                        children: [
                          for (final (name, r) in rects)
                            Positioned(
                              left: r.left,
                              top: r.top,
                              width: r.width,
                              height: r.height,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => widget.onFoldTap?.call(name),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 拖手柄时,贴边滚动只跟着**挪动的那一端**走。
///
/// 安卓上拖起点手柄,框架每挪一下滚两次:当场把起点拉进视口(往上,
/// `_bringIntoViewBySelectionState`),帧尾再带动画滚一次去露「选区末尾」
/// (`_scheduleShowCaretOnScreen`:base 在前就露最后一段)—— 可拖起点时 base 照样
/// 在前,露的是没动的那一头(往下)。一上一下,往上划选就来回抽。往下拖时两次都
/// 指向末尾,所以只坏往上这一边。
///
/// 拖动期间:带动画的那次丢掉,当场那次补上框架原本会留的边距 —— 往下拖、拖单个
/// 光标,最后停的位置和原来一样。
class _HandleDragReveal extends SingleChildRenderObjectWidget {
  const _HandleDragReveal({
    required this.active,
    required this.padding,
    super.child,
  });

  /// 现读,不等重建:拖动状态由手柄上的 [Listener] 同步改,框架的滚动请求紧跟着就到。
  final bool Function() active;
  final EdgeInsets padding;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHandleDragReveal(active, padding);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHandleDragReveal renderObject,
  ) {
    renderObject
      ..active = active
      ..padding = padding;
  }
}

class _RenderHandleDragReveal extends RenderProxyBox {
  _RenderHandleDragReveal(this.active, this.padding);

  bool Function() active;
  EdgeInsets padding;

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (active()) {
      if (duration > Duration.zero) return;
      if (rect != null) rect = padding.inflateRect(rect);
    }
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }
}

const _kCursorWidth = 2.0;

/// RenderEditable 的 _caretMargin = cursorWidth + _kCaretGap(1)。
const _kCaretMargin = _kCursorWidth + 1.0;

/// 手柄的触摸盒。框架会把手柄的可点区域补到 [kMinInteractiveDimension] 见方,
/// 补出来的那圈内边距不属于 buildHandle 返回的 widget —— 而 [Listener] 只收
/// 落在自己身上的指头。所以报 48、自己居中放本体,整块触摸盒都在观察范围内。
const _kHandleTouch = kMinInteractiveDimension;

/// 观察手柄:外观、拖动手感、放大镜、点击弹工具栏,全都是框架原样那一套。
///
/// 这里只多套一层 [Listener] —— 它不进手势竞技场,不和框架那颗 pan 抢,
/// 纯粹是「有没有指头在手柄上拖」的探针,拿来通知页面把词条栏收起来。
class _WatchedHandles extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  _WatchedHandles(this.owner);

  final _AnnotatedFieldState owner;

  @override
  Size getHandleSize(double textLineHeight) =>
      const Size(_kHandleTouch, _kHandleTouch);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      super.getHandleAnchor(type, textLineHeight) + _inset(textLineHeight);

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: owner._pointerDown,
      onPointerMove: owner._pointerMove,
      onPointerUp: (_) => owner._pointerUp(),
      onPointerCancel: (_) => owner._pointerUp(),
      child: SizedBox.square(
        dimension: _kHandleTouch,
        child: Center(
          child: super.buildHandle(context, type, textHeight, onTap),
        ),
      ),
    );
  }

  /// 本体居中放进触摸盒后,锚点(与光标重合的那个点)要跟着往右下挪这么多。
  Offset _inset(double textLineHeight) {
    final glyph = super.getHandleSize(textLineHeight);
    return Offset(
      (_kHandleTouch - glyph.width) / 2,
      (_kHandleTouch - glyph.height) / 2,
    );
  }
}

/// 折叠标题 `#名字` 的命中矩形(跨行则多条)→ (名字, 行盒)。与绘制层同一
/// measureSpan 布局,盒子坐标与底纹/注音严格对齐;取 max 行盒(含行距)让
/// 热区顶满整行,窄标题也好点。
List<(String, Rect)> _foldTitleRects(
  String text,
  Map<String, String> bodies, {
  required TextStyle base,
  required double maxWidth,
  required TextScaler scaler,
}) {
  final refs = parseFoldRefs(text, bodies);
  if (refs.isEmpty || maxWidth <= 0) return const [];
  final tp = TextPainter(
    text: measureSpan(text, scaler, base: base),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    textHeightBehavior: _kEvenLeading,
    maxLines: null,
  )..layout(maxWidth: maxWidth);
  final out = <(String, Rect)>[];
  for (final r0 in refs) {
    final (a, b) = r0.titleRange;
    for (final box in tp.getBoxesForSelection(
      TextSelection(baseOffset: a, extentOffset: b),
      boxHeightStyle: BoxHeightStyle.max,
    )) {
      final r = box.toRect();
      if (r.width > 0.5) out.add((r0.name, r));
    }
  }
  tp.dispose();
  return out;
}

/// 折叠底纹层:占位符标题 `#名字` 范围一颗圆角药丸——「这是一枚折叠、点我
/// 解散」全靠它(加 primary 字色)说清楚。占位符是真实正文字符,零布局技巧。
class _FoldPainter extends CustomPainter {
  _FoldPainter({
    required this.text,
    required this.bodies,
    required this.base,
    required this.maxWidth,
    required this.scaler,
    required this.withSpacing,
    required this.title,
    required this.revision,
  });

  final String text;
  final Map<String, String> bodies;
  final TextStyle base;
  final double maxWidth;
  final TextScaler scaler;
  final bool withSpacing;
  final Color title;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || maxWidth <= 0) return;
    final refs = parseFoldRefs(text, bodies);
    if (refs.isEmpty) return;

    final layout = TextPainter(
      text: withSpacing
          ? measureSpan(text, scaler, base: base)
          : TextSpan(text: text, style: base),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      textHeightBehavior: _kEvenLeading,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    final paint = Paint()..color = title;
    for (final r0 in refs) {
      final (a, b) = r0.titleRange; // `#名字`
      for (final box in layout.getBoxesForSelection(
        TextSelection(baseOffset: a, extentOffset: b),
      )) {
        final r = box.toRect();
        if (r.width <= 0.5) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(r.left - 3, r.top - 1.5, r.right + 3, r.bottom + 1.5),
            const Radius.circular(5),
          ),
          paint,
        );
      }
    }
    layout.dispose();
  }

  @override
  bool shouldRepaint(covariant _FoldPainter old) =>
      old.text != text ||
      !mapEquals(old.bodies, bodies) ||
      old.base != base ||
      old.maxWidth != maxWidth ||
      old.withSpacing != withSpacing ||
      old.title != title ||
      old.revision != revision;
}

/// 权重底色层(web WeightHighlightExtension 移植):
/// - 范围**含权重记号**:单词条=整段语法,跨词条组=开记号画到闭记号
/// - 贴字形高度(tight 字形盒 + 竖向 1.5px 余量 + 圆角),不染注音区
/// - 嵌套组 / 组内自带权重 = 多条区间半透明叠色,内层自然更深
/// - SD 语法 tertiary 按词条段绘制,优先于权重色带之上
class _WeightWashPainter extends CustomPainter {
  _WeightWashPainter({
    required this.text,
    required this.base,
    required this.maxWidth,
    required this.scaler,
    required this.withSpacing,
    required this.pal,
    required this.sdWash,
    required this.disabledWash,
    required this.revision,
  });

  final String text;

  /// TextField 实际渲染的基准样式(字号/行高),测量层必须同款。
  final TextStyle base;

  final double maxWidth;
  final TextScaler scaler;

  /// 是否启用译文宽度补偿(注音开时必须与 TextField 布局同构)。
  final bool withSpacing;

  /// 权重色相与强度曲线来源([EditorPalette.weightWash])。
  final EditorPalette pal;

  final Color sdWash;

  /// 禁用词条那层中性底色(调用方给 onSurface,这里再压透明度)。
  final Color disabledWash;

  /// 翻译缓存版本:补偿间距随译文变化会挪断行,必须跟着重绘。
  final int revision;

  static const _vPad = 1.5;
  static const _radius = Radius.circular(4);

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || maxWidth <= 0) return;
    final spans = <WeightSpan>[];
    final toks = parseToks(text, weightSpans: spans);

    // 词条级警示区间(SD tertiary),画在权重色带之上
    final overlays = <(int, int, Color)>[];
    // 禁用词条的区间。**它们不铺权重色带** —— 一枚关掉的词还顶着一片加权蓝,
    // 说的是两件互相矛盾的事;chip 那边早就是这个规矩(禁用不铺色),正文这边
    // 一直漏了。改成铺一层中性灰:划掉 + 压暗 + 一层底,三样一起才看得出来。
    final off = <(int, int)>[];
    for (final t in toks) {
      if (t.disabled) {
        off.add((t.segStart, t.segEnd));
        overlays.add((
          t.segStart,
          t.segEnd,
          disabledWash.withValues(alpha: .1),
        ));
        continue;
      }
      if (isSdWeightSeg(text.substring(t.segStart, t.segEnd))) {
        overlays.add((t.segStart, t.segEnd, sdWash.withValues(alpha: .16)));
      }
    }
    if (spans.isEmpty && overlays.isEmpty) return;
    bool isOff(int a, int b) => off.any((r) => a >= r.$1 && b <= r.$2);

    final layout = TextPainter(
      text: withSpacing
          ? measureSpan(text, scaler, base: base)
          : TextSpan(text: text, style: base),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      textHeightBehavior: _kEvenLeading,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    final spacing = withSpacing
        ? tagExtraSpacing(text, scaler, base: base)
        : const <int, double>{};

    void drawRange(int start, int end, Color color) {
      if (end <= start) return;
      final boxes = layout.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      if (boxes.isEmpty) return;
      final paint = Paint()..color = color;
      // 末字符若带译文补偿间距,回收那截空推距(色带不越过词面)
      final trim = spacing[end - 1] ?? 0.0;
      for (var i = 0; i < boxes.length; i++) {
        var r = boxes[i].toRect();
        if (i == boxes.length - 1 && trim > 0) {
          r = Rect.fromLTRB(
            r.left,
            r.top,
            (r.right - trim).clamp(r.left, double.infinity),
            r.bottom,
          );
        }
        if (r.width <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              r.left - 1,
              r.top - _vPad,
              r.right + 1,
              r.bottom + _vPad,
            ),
            _radius,
          ),
          paint,
        );
      }
    }

    for (final s in spans) {
      if (isOff(s.start, s.end)) continue; // 见上:禁用不铺权重色
      final c = pal.weightWash(s.mult);
      if (c != null) drawRange(s.start, s.end, c);
    }
    for (final (a, b, c) in overlays) {
      drawRange(a, b, c);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightWashPainter old) =>
      old.text != text ||
      old.base != base ||
      old.maxWidth != maxWidth ||
      old.withSpacing != withSpacing ||
      old.pal != pal ||
      old.sdWash != sdWash ||
      old.disabledWash != disabledWash ||
      old.revision != revision;
}

/// 翻译当「注音」:始终单行,左端钉词首;地皮由词尾宽度补偿保证
/// (tag 占位 = max(英文, 译文));行尾放不下先回夹再尾截兜底。
class _FuriganaPainter extends CustomPainter {
  _FuriganaPainter({
    required this.text,
    required this.base,
    required this.maxWidth,
    required this.color,
    required this.scaler,
    required this.revision,
  });

  final String text;

  /// TextField 实际渲染的基准样式(字号可调),测量层必须同款。
  final TextStyle base;

  final double maxWidth;
  final Color color;
  final TextScaler scaler;

  /// 翻译缓存版本(suggestions.transCacheRev):文本没变但缓存灌到了也要重绘。
  final int revision;

  static const _transSize = 9.5;
  static const _gap = 3.0; // 基线到译文顶的间距

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || maxWidth <= 0) return;

    final layout = TextPainter(
      // measureSpan:与 TextField 同款字号 + 宽度补偿 + 折叠隐藏,布局同构
      text: measureSpan(text, scaler, base: base),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      textHeightBehavior: _kEvenLeading,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    final lines = layout.computeLineMetrics();
    if (lines.isEmpty) return;
    final lineTops = <double>[];
    var acc = 0.0;
    for (final l in lines) {
      lineTops.add(acc);
      acc += l.height;
    }

    final transStyle = TextStyle(fontSize: _transSize, height: 1, color: color);

    // 收集(行号, 词左端, 译文, 排好版的画笔),按行从左到右画
    final items = <(int, double, String, TextPainter)>[];
    for (final tok in parseToks(text)) {
      final tr = tok.trans;
      if (tr == null || tr.isEmpty || tok.nameEnd <= tok.nameStart) continue;

      final boxes = layout.getBoxesForSelection(
        TextSelection(baseOffset: tok.nameStart, extentOffset: tok.nameEnd),
      );
      if (boxes.isEmpty) continue;

      final tp = TextPainter(
        text: TextSpan(text: tr, style: transStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();

      // 跨行折断的词:首段右侧全是本词自己的延续(无邻居竞争地皮),
      // 译文放得下就画首段(阅读起点);放不下(首段顶在行尾)才退到
      // 带宽度预算的末段。单行词首末同段,无差。
      final b = (boxes.length == 1 || tp.width <= maxWidth - boxes.first.left)
          ? boxes.first
          : boxes.last;
      final mid = (b.top + b.bottom) / 2;
      var li = 0;
      for (var i = 0; i < lines.length; i++) {
        if (mid >= lineTops[i] && mid < lineTops[i] + lines[i].height) {
          li = i;
          break;
        }
      }
      items.add((li, b.left, tr, tp));
    }
    items.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.compareTo(b.$2));

    // 常规:左端钉词首,原样完整绘制。行尾/文本尾的长译文兜底:
    // 先向左回夹到右边界,撞到同行前一条译文即止(防重叠),
    // 仍放不下才尾部省略(只有这个物理极限场景才截)。
    var lastLine = -1;
    var lastRight = double.negativeInfinity;
    for (final (li, left, tr, tp0) in items) {
      if (li != lastLine) {
        lastLine = li;
        lastRight = double.negativeInfinity;
      }
      var tp = tp0;
      var x = left;
      if (x + tp.width > maxWidth) x = maxWidth - tp.width; // 行尾回夹
      final floor = lastRight.isFinite ? lastRight + 6 : 0.0;
      if (x < floor) x = floor; // 防重叠/防出左界
      if (x + tp.width > maxWidth) {
        tp.dispose();
        tp = TextPainter(
          text: TextSpan(text: tr, style: transStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: (maxWidth - x).clamp(0.0, maxWidth));
      }
      tp.paint(canvas, Offset(x, lines[li].baseline + _gap));
      lastRight = x + tp.width;
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _FuriganaPainter old) =>
      old.text != text ||
      old.base != base ||
      old.maxWidth != maxWidth ||
      old.color != color ||
      old.revision != revision;
}

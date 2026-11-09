import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart';
import '../chrome_scroll.dart';
import '../editor_models.dart';
import 'rich_tag_controller.dart';
import '../../../core/util/haptics.dart';

/// 尾部输入框的定宽(有词条时)。约五个汉字宽,够看清正在打的词,
/// 又不至于自己独占一行把芯片流顶开。
const double _kInputWidth = 168;

/// 尾部输入框里常驻的**零宽占位符**。
///
/// 为什么要塞一个看不见的字符:Android 上输入框真空时,输入法的退格走的是
/// `deleteSurroundingText`,删无可删就什么都不发 —— app 这头收不到任何信号,
/// 「空框退格删掉上一枚标签」这个芯片输入的常规操作根本接不上。走键盘事件
/// 那条路也不保准:各家输入法对 KEYCODE_DEL 的转发口径不一,中文输入法尤其。
///
/// 框里永远留一个零宽空格,退格就**必定**产生一次真实删除;占位符被删掉即
/// 「在空框上按了退格」(见 editor_page 的 `_onInputChanged`)。零宽空格不占
/// 宽度、不参与断行,光标看着就贴在框首。
///
/// 代价是这个框对 TextField 而言永远非空,自带的 hintText 不会出现 ——
/// 占位提示改由本视图自己画(见 [_inputBox])。
const String kChipInputPad = '\u200b';

/// 去掉占位符后的**有效**文本。页面与本视图共用一处,免得两边各写各的。
String chipInputBody(String raw) => raw.replaceAll(kChipInputPad, '');

/// 把选中的这批搬到间隙 [g] 之后顺序完全没变 → 这个落点是空操作。
/// 直接按 moveUnits 的换算跑一遍新序,与原序比对,省得逐种情况讨论。
bool _noOpGap(Set<int> sel, int g, int n) {
  var at = 0;
  for (var i = 0; i < g && i < n; i++) {
    if (!sel.contains(i)) at++;
  }
  final sorted = sel.toList()..sort();
  final next = [
    for (var i = 0; i < n; i++)
      if (!sel.contains(i)) i,
  ]..insertAll(at.clamp(0, n - sel.length), sorted);
  for (var i = 0; i < n; i++) {
    if (next[i] != i) return false;
  }
  return true;
}

/// 哪些间隙是**有意义**的落点(纯下标运算,不依赖布局)。
///
/// ⊕ 画在哪儿、以及面板上那颗「移动」要不要能点,读的都是这一份 ——
/// 两处各写各的判据,迟早出现「按钮亮着但一个 ⊕ 都没有」。
Set<int> chipValidGaps(Set<int> sel, int n) {
  if (sel.isEmpty || n == 0 || sel.length >= n) return const {};
  final out = <int>{};
  for (var g = 0; g <= n; g++) {
    // 落点等于原位就没意义:间隙两侧都被选中(搬过去还是那儿),或者
    // 紧贴选中块的两端。判据 —— 间隙左右各自是不是选中项。
    final leftSel = g > 0 && sel.contains(g - 1);
    final rightSel = g < n && sel.contains(g);
    if (leftSel && rightSel) continue;
    if (_noOpGap(sel, g, n)) continue;
    out.add(g);
  }
  return out;
}

/// 译文相对正文的字号差与行高倍数(chip 内两行的排版基准)。
/// 行高显式给死是**故意**的:译文是异步到货的,这一行的高度必须在译文来之前
/// 就能算出来,才好预留(见 [_TagChip] 里的占位)。
const double _kTransDrop = 4;
const double _kTransLine = 1.25;

/// 译文行占的高度(含与正文之间的 1px 间隙)。
double _transRowHeight(double fontSize) =>
    (fontSize - _kTransDrop) * _kTransLine + 1;

/// 芯片流视图(web 移动端 FullscreenEditor 芯片模式的形态):整体替换注音
/// 富文本,每个**顶层单元**一颗 chip —— 散标签是普通词条 chip(英文+译文双行,
/// 带权重角标/禁用删除线),折叠段是一颗 `#名字` chip(和普通标签同款外观,
/// 只多个折叠符号与主色边)。
///
/// 交互分两个阶段:
///  1. 选:点 chip 加选/取消(可多选)。这个阶段点什么都不会移动东西。
///     **长按**则一步到位 —— 直接把它(或已选那一批)拿起来进落位阶段。
///  2. 放:在底部面板点「移动」进入([placing])。⊕ 只在这个阶段出现,点它落位。
///     这个阶段**照样能点芯片加减选中** —— 搬到一半发现漏了一个,不必退出来
///     重选;选空或选到没落点时由外层自动退回选择阶段。
///
/// 折叠 chip 和散标签一视同仁,选中即整块移动(moveUnits 保证记号跟随不卷入)。
/// 选中后的操作(权重/禁用/删除/解散)全在底部面板上 —— 这里没有光标,正文里
/// 那套「点标题解散」在本视图不存在。
///
/// 末尾跟一个输入框:芯片模式下这是唯一的打字入口,补全照常吸在键盘上。
/// 没选中时点空白 = 聚焦它(直接接着打字,不用瞄准那个小框)。
class ChipFlowView extends StatefulWidget {
  const ChipFlowView({
    super.key,
    required this.controller,
    required this.foldBodies,
    required this.selection,
    required this.onSelectionChanged,
    required this.onMove,
    required this.onLongPressChip,
    required this.input,
    required this.inputFocus,
    required this.onInputChanged,
    required this.onInputSubmitted,
    required this.translating,
    this.placing = false,
    this.showTrans = true,
    this.fontSize = 16,
  });

  final RichTagController controller;

  /// 折叠表(名字 -> 折叠体):识别占位符 + 数成员。
  final Map<String, String> foldBodies;

  /// 已选顶层单元下标。**状态提在页面上** —— 底部批量操作条要读它,
  /// 而且改完文本后要由页面决定清不清选中。
  final Set<int> selection;
  final ValueChanged<Set<int>> onSelectionChanged;

  /// 把已选单元整批移到间隙 [to](原序下标)。
  final void Function(int to) onMove;

  /// **落位阶段**:⊕ 只在这个阶段出现,芯片则暂时不响应点击。
  ///
  /// 为什么要分这么一个阶段:⊕ 是浮在芯片上的,两件事共用同一片区域就必然
  /// 互相误触 —— 想点芯片改选中,结果压到 ⊕ 上把整批搬走了。分开之后,
  /// 选择阶段根本没有 ⊕ 可点,落位阶段点芯片也不会改选中。
  ///
  /// 靶子仍是 ⊕ 本身,**没有**放大成整片区域:大靶子换来的是另一种误触
  /// (随手一点就搬走),而选择阶段已经不会被 ⊕ 干扰,不需要再拿命中率换。
  final bool placing;

  /// 长按某颗芯片:直接进落位阶段(见外层 `_chipLongPress`)。
  final void Function(int index) onLongPressChip;

  /// 尾部输入框(页面持有:补全管线要读它的文本)。
  final TextEditingController input;
  final FocusNode inputFocus;

  /// 每次输入:页面据此跑补全,并在遇到逗号时把前半截落成标签。
  final ValueChanged<String> onInputChanged;

  /// 回车/完成:整条落成标签。
  final ValueChanged<String> onInputSubmitted;

  /// 译文行开关(编辑器设置的注音开关):关=chip 收成单行。
  final bool showTrans;

  /// 这枚标签的译文是否还在路上(排队/在问)。离线补全模式恒 false ——
  /// 那边没人去问,挂着加载动画等于骗人。
  final bool Function(String name) translating;

  /// 正文字号(编辑器设置 14/16/18):chip 整体大小跟着走,和注音富文本同一档。
  final double fontSize;

  @override
  State<ChipFlowView> createState() => _ChipFlowViewState();
}

class _ChipFlowViewState extends State<ChipFlowView>
    with TickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _chipKeys = [];
  final Map<int, GlobalKey> _bandKeys = {}; // 组首成员下标 → 组框
  List<(int, Offset)> _anchors = const []; // (gap, 加号中心) 内容坐标

  // FLIP 插入动画:每颗 chip 从旧槽位滑到新槽位(不闪跳)。
  late final AnimationController _moveAnim =
      AnimationController(vsync: this, duration: Motion.medium)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed &&
              mounted &&
              _startOffsets.isNotEmpty) {
            setState(() => _startOffsets = const {});
          }
        });
  Map<int, Offset> _startOffsets = const {}; // 单元下标 → 起始位移(内容坐标)

  /// 译文加载态的脉动:整片 chip 共用一个 ticker,且只在**真有词在等**时才转
  /// (没人等还空转 = 白烧一整屏的帧)。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );
  bool _pulsing = false;

  @override
  void dispose() {
    _moveAnim.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// 起停脉动。**必须挪到帧后**:repeat/stop 会同步 notifyListeners,
  /// build 期间通知已经挂上的 AnimatedBuilder 会撞 markNeedsBuild 断言。
  void _syncPulse(bool on) {
    if (on == _pulsing) return;
    _pulsing = on;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pulsing) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    });
  }

  Set<int> get _sel => widget.selection;

  /// 权重面板 / 补全展开层把视口压矮时,刚点的那颗(或正在打字的输入框)
  /// 别被盖住。见 [KeepInViewTracker]。
  final _keep = KeepInViewTracker();
  int? _focusChip; // null = 尾部输入框
  final _inputKey = GlobalKey();

  void _focusOn(int? i) {
    _focusChip = i;
    _keep.arm();
  }

  void _revealFocus() {
    final i = _focusChip;
    final GlobalKey key;
    if (i == null) {
      key = _inputKey;
    } else {
      if (!_sel.contains(i) || i >= _chipKeys.length) return;
      key = _chipKeys[i];
    }
    final b = key.currentContext?.findRenderObject() as RenderBox?;
    if (b == null || !b.attached || !b.hasSize) return;
    b.showOnScreen(
      rect: const EdgeInsets.all(12).inflateRect(Offset.zero & b.size),
    );
  }

  void _longPressChip(int i) {
    _focusOn(i);
    widget.onLongPressChip(i);
  }

  void _tapChip(int i) {
    Haptics.selection();
    // 在途滑动先归位并清位移,保证下次插入量到干净布局
    if (_startOffsets.isNotEmpty) {
      _moveAnim.value = 1;
      _startOffsets = const {};
    }
    final next = {...widget.selection};
    if (!next.remove(i)) {
      next.add(i);
      _focusOn(i);
    }
    widget.onSelectionChanged(next);
  }

  /// 量各 chip 相对 Stack 的矩形(未布局返回 null)。
  List<Rect>? _measureRects(int count) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return null;
    final rects = <Rect>[];
    for (var i = 0; i < count; i++) {
      final b = _chipKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.hasSize) return null;
      final tl = b.localToGlobal(Offset.zero, ancestor: stackBox);
      rects.add(tl & b.size);
    }
    return rects;
  }

  void _insert(int gap) {
    final sel = _sel.toList()..sort();
    if (sel.isEmpty) return;
    Haptics.medium();
    final n = topLevelUnits(widget.controller.text, widget.foldBodies).length;
    // 收前先把在途动画归位(value=1 → 现有 Transform 位移为 0,量到干净布局)
    _moveAnim.value = 1;
    final oldRects = _measureRects(n);
    widget.onMove(gap); // 改文本 + 清选中 → 触发重建(chip 跳到新槽)
    if (oldRects == null) return; // 量不到就不动画,内容已更新

    // 新下标 j 处的 chip 来自旧下标 order[j] —— 与 moveUnits 同一套换算
    var at = 0;
    for (var i = 0; i < gap && i < n; i++) {
      if (!_selWas(sel, i)) at++;
    }
    final order = [
      for (var i = 0; i < n; i++)
        if (!_selWas(sel, i)) i,
    ]..insertAll(at.clamp(0, n - sel.length), sel);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final newRects = _measureRects(n);
      if (newRects == null) return;
      final starts = <int, Offset>{};
      for (var j = 0; j < n; j++) {
        final delta = oldRects[order[j]].topLeft - newRects[j].topLeft;
        if (delta.distance > 0.5) starts[j] = delta;
      }
      if (starts.isEmpty) return;
      setState(() => _startOffsets = starts);
      _moveAnim.forward(from: 0);
    });
  }

  static bool _selWas(List<int> sorted, int i) => sorted.contains(i);

  /// 布局后按 chip 实际位置计算间隙加号锚点(浮层,不占 Wrap 位——
  /// 加号出现/消失时 chip 一动不动)。结果收敛才 setState,防循环。
  void _scheduleAnchors(int count, List<UnitGroup> groups) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sel = _sel;
      // 落位阶段的 ⊕ 跟着选中实时重算:加减选中之后能落的位置本来就变了。
      final gaps = widget.placing ? chipValidGaps(sel, count) : const <int>{};
      if (gaps.isEmpty) {
        if (_anchors.isNotEmpty) setState(() => _anchors = const []);
        return;
      }
      final stackBox =
          _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null) return;
      final rects = <Rect>[];
      for (final k in _chipKeys.take(count)) {
        final b = k.currentContext?.findRenderObject() as RenderBox?;
        if (b == null || !b.hasSize) return;
        final tl = b.localToGlobal(Offset.zero, ancestor: stackBox);
        rects.add(tl & b.size);
      }
      Rect? bandRect(UnitGroup b) {
        final box =
            _bandKeys[b.first]?.currentContext?.findRenderObject()
                as RenderBox?;
        if (box == null || !box.hasSize) return null;
        return box.localToGlobal(Offset.zero, ancestor: stackBox) & box.size;
      }

      final next = <(int, Offset)>[];
      for (var g = 0; g <= rects.length; g++) {
        if (!gaps.contains(g)) continue;
        Offset pos;
        if (g == rects.length) {
          final r = rects.last;
          pos = Offset(r.right + 4, r.center.dy);
        } else {
          final r = rects[g];
          pos = Offset(r.left - 4, r.center.dy);
        }
        // 组框边上的 ⊕ 按落下后在框内还是框外摆
        Offset? edge;
        for (final b in groups) {
          if (g == b.last + 1 &&
              joinsGroupOnMove(b.first, b.last, sel, g, count)) {
            final r = rects[b.last];
            edge = Offset(r.right + 4, r.center.dy);
          }
        }
        if (edge == null) {
          for (final b in groups) {
            final atFirst = g == b.first;
            if (!atFirst && !(g == count && g == b.last + 1)) continue;
            if (atFirst && joinsGroupOnMove(b.first, b.last, sel, g, count)) {
              continue;
            }
            final band = bandRect(b);
            if (band == null) continue;
            edge = atFirst
                ? Offset(band.left - 4, rects[g].center.dy)
                : Offset(band.right + 4, rects[b.last].center.dy);
          }
        }
        pos = edge ?? pos;
        next.add((g, Offset(pos.dx.clamp(12.0, double.maxFinite), pos.dy)));
      }
      if (!_sameAnchors(next)) setState(() => _anchors = next);
    });
  }

  bool _sameAnchors(List<(int, Offset)> next) {
    if (next.length != _anchors.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i] != _anchors[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _moveAnim]),
      builder: (context, _) {
        final text = widget.controller.text;
        final units = topLevelUnits(text, widget.foldBodies);
        final sel = {
          for (final i in _sel)
            if (i < units.length) i,
        };
        while (_chipKeys.length < units.length) {
          _chipKeys.add(GlobalKey());
        }
        final groups = unitGroups(text, units);
        _scheduleAnchors(units.length, groups);
        bool pendingOf(TopUnit u) =>
            widget.showTrans &&
            !u.isFold &&
            u.tok!.trans == null &&
            widget.translating(u.tok!.name);
        _syncPulse(units.any(pendingOf));
        final t = Curves.easeOutCubic.transform(_moveAnim.value);
        return GestureDetector(
          // 没选中时点空白 = 聚焦输入框:芯片之间的缝隙本来什么也不是,
          // 让它接管「我要接着打字」这个最高频的意图。
          // 选中着东西时它什么也不做 —— 理由见 [_tapBlank]。
          behavior: HitTestBehavior.opaque,
          onTap: _tapBlank,
          child: NotificationListener<Notification>(
            onNotification: (n) {
              if (_keep.update(n)) _revealFocus();
              return false;
            },
            child: SingleChildScrollView(
              // 一屏放得下也照样接拖动:编辑页滚动收起顶栏后,靠「顶上往下拽」
              // 放出来(见 ChromeScrollTracker)
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              child: Stack(
                key: _stackKey,
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Wrap(
                      // 缝只要够把两颗分开就行:chip 自带底色和边框,靠不上
                      // 留白来断句。横向比纵向再紧一档 —— 一行里缝出现的次数
                      // 多得多,同样的数看着就更松。
                      spacing: 6,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ..._rows(text, units, groups, sel, pendingOf, t),
                        _inputBox(units.isEmpty),
                      ],
                    ),
                  ),
                  if (sel.isNotEmpty)
                    for (final (g, pos) in _anchors)
                      Positioned(
                        left: pos.dx - 15,
                        top: pos.dy - 15,
                        child: _PlusDot(onTap: () => _insert(g)),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 点空白。**选中着东西时什么都不做** —— 这是有意的。
  ///
  /// 插入点 ⊕ 只有 30px,浮在缝隙上;而缝隙以外的一切都是这块空白。原来这里
  /// 会清空选中,于是「⊕ 点歪几个像素」的代价是**辛苦选的一批全没了**,
  /// 收益和代价完全不对称 —— 拖动那套点歪最多是落错位置(还有撤销),
  /// 所以用户宁可要拖动。把代价拉平比换手势更要紧。
  ///
  /// 取消选中改走显式入口:面板右上的 ✕、返回键(见 editor_page 的 PopScope)、
  /// 或者再点一次那几枚芯片。选中态下也不抢焦点:那会弹起键盘挡住底部面板。
  void _tapBlank() {
    if (_sel.isNotEmpty) return;
    widget.inputFocus.requestFocus();
  }

  /// 尾部输入框。Wrap 里的孩子拿不到「本行剩余宽度」,所以给定宽:空正文时
  /// 占满一行(那时它就是整个编辑区),有词条时 [_kInputWidth] 跟在最后一颗
  /// chip 后面,放不下自动换行。文本超出宽度由 TextField 自己横向滚。
  Widget _inputBox(bool empty) {
    final scheme = context.scheme;
    final fs = widget.fontSize;
    const pad = EdgeInsets.symmetric(vertical: 7);
    final hintStyle = TextStyle(fontSize: fs, color: scheme.outline);
    return SizedBox(
      key: _inputKey,
      width: empty ? double.infinity : _kInputWidth,
      child: Stack(
        children: [
          // 占位提示自己画:框里常驻 [kChipInputPad],TextField 眼里永远非空,
          // 自带的 hintText 一次都不会出现。跟着 input 重建 —— 打第一个字就得
          // 让位,而页面不保证每次击键都 setState。
          AnimatedBuilder(
            animation: widget.input,
            builder: (_, _) => chipInputBody(widget.input.text).isEmpty
                ? Padding(
                    padding: pad,
                    child: Text(
                      empty ? '输入标签,可输入中文自动翻译' : '继续添加…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hintStyle,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          TextField(
            controller: widget.input,
            focusNode: widget.inputFocus,
            onChanged: (v) {
              _focusOn(null);
              widget.onInputChanged(v);
            },
            onSubmitted: (v) {
              widget.onInputSubmitted(chipInputBody(v));
              widget.inputFocus.requestFocus(); // 落一枚接着打下一枚
            },
            textInputAction: TextInputAction.done,
            style: TextStyle(fontSize: fs, color: scheme.onSurface),
            cursorColor: scheme.primary,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: pad,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipFor(
    String text,
    TopUnit u,
    int i,
    Set<int> sel,
    bool translating,
    double band,
  ) {
    if (u.isFold) {
      return _FoldChip(
        key: _chipKeys[i],
        name: u.fold!.name,
        count: _memberCount(u.fold!),
        fontSize: widget.fontSize,
        selected: sel.contains(i),
        onTap: () => _tapChip(i),
        onLongPress: () => _longPressChip(i),
      );
    }
    final tok = u.tok!;
    return _TagChip(
      key: _chipKeys[i],
      tok: tok,
      sd: isSdWeightSeg(text.substring(tok.segStart, tok.segEnd)),
      showTrans: widget.showTrans,
      translating: translating,
      pulse: _pulse,
      fontSize: widget.fontSize,
      band: band,
      selected: sel.contains(i),
      onTap: () => _tapChip(i),
      onLongPress: () => _longPressChip(i),
    );
  }

  int _memberCount(FoldRef f) =>
      parseToks(widget.foldBodies[f.name] ?? '').length;

  /// 落位阶段里被选中的那几枚是**搬运物**:淡出读作「已拿起」,好让用户一眼
  /// 分清「要搬的」和「可以落在哪儿」。点击本身由 [_tapChip] 挡掉。
  /// 铺 Wrap 的孩子:被同一个权重罩着的连续几枚收进一只 [_GroupBand],
  /// 其余原样单颗上。**下标不变** —— 组只是套了层框,`_chipKeys[i]`、选中集、
  /// 落点 ⊕ 那一套照旧按顶层单元下标算,框里框外一视同仁。
  List<Widget> _rows(
    String text,
    List<TopUnit> units,
    List<UnitGroup> groups,
    Set<int> sel,
    bool Function(TopUnit u) pendingOf,
    double t,
  ) {
    // own=false:这颗的选中态归外面那只框管,高亮和落位半透明都别再来一遍。
    Widget one(int i, double band, {bool own = true}) {
      final mine = own ? sel : const <int>{};
      return _slide(
        i,
        t,
        _place(
          i,
          mine,
          _chipFor(text, units[i], i, mine, pendingOf(units[i]), band),
        ),
      );
    }

    final out = <Widget>[];
    for (var i = 0; i < units.length; i++) {
      // 正文里的换行在这儿断行:芯片模式**不新增**排版能力,只是把注音模式
      // 已经存在的分段照着显示出来 —— 否则用户粘进来的多段提示词在这边糊成
      // 一片,一切回去又变回三段,同一份文本两种样子。
      //
      // 分隔符本来就一直留在原文里(topLevelUnits 只圈标签本身,不碰缝隙),
      // 所以这里只是读,不写。
      final gap = _newlinesBefore(text, units, i);
      if (gap > 0) out.add(_LineBreak(blank: gap > 1));

      final g = groups.where((r) => r.first == i).firstOrNull;
      if (g == null) {
        out.add(one(i, 1));
        continue;
      }
      // 「选中整组」把成员一次收齐 —— 那时选中的是**这只框**,里头几颗回到
      // 常态。每颗各自再高亮一遍既吵,也说不清选中的到底是框还是某一颗。
      final whole = g.coversExactly(sel.toList()..sort());
      final band = _GroupBand(
        mult: g.mult,
        fontSize: widget.fontSize,
        selected: whole,
        children: [
          for (var k = g.first; k <= g.last; k++) one(k, g.mult, own: !whole),
        ],
      );
      // 整只被拿起来时整只压暗 —— 和单颗芯片落位时一个待遇
      out.add(
        KeyedSubtree(
          key: _bandKeys.putIfAbsent(g.first, GlobalKey.new),
          child: widget.placing && whole
              ? Opacity(opacity: .45, child: band)
              : band,
        ),
      );
      i = g.last;
    }
    return out;
  }

  /// 第 [i] 枚之前的缝里有几个换行(0 = 不断行)。
  ///
  /// 只看**紧邻的**上一枚到这一枚之间那段原文;第 0 枚看的是正文开头到它之前
  /// (粘贴进来常带一个前导空行,那也是用户的排版)。
  int _newlinesBefore(String text, List<TopUnit> units, int i) {
    final from = i == 0 ? 0 : units[i - 1].end;
    final gap = text.substring(from, units[i].start);
    var n = 0;
    for (var k = 0; k < gap.length; k++) {
      if (gap[k] == '\n') n++;
    }
    return n;
  }

  Widget _place(int i, Set<int> sel, Widget chip) =>
      widget.placing && sel.contains(i)
      ? Opacity(opacity: .45, child: chip)
      : chip;

  /// FLIP:动画中把第 [i] 颗 chip 从起始位移滑回 0(paint-time,不改布局)。
  Widget _slide(int i, double t, Widget child) {
    final start = _startOffsets[i];
    if (start == null || t >= 1) return child;
    return Transform.translate(offset: start * (1 - t), child: child);
  }
}

/// Wrap 里的强制断行:宽度撑满就把后面的孩子挤到下一行去。
///
/// [blank] = 原文那儿是**空行**(两个及以上换行),多留一截高度把段落隔开 ——
/// 不然连着两次断行看着和一次没区别,用户分的段就白分了。
///
/// 高度不能给 0:Wrap 的 runSpacing 只作用在行与行之间,零高的行会被上下两条
/// 缝夹成一道莫名其妙的宽缝。给个小正数,它自己就是那道缝。
class _LineBreak extends StatelessWidget {
  const _LineBreak({this.blank = false});

  final bool blank;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: double.infinity, height: blank ? 10 : 0.01);
}

/// 权重组的连体框:`1.3::empty eyes, panting::` 这种一个权重罩住好几枚词的
/// 写法,过去在芯片模式下摊成「每颗各挂一个 ×1.3」—— 同一件事说 N 遍,还看不
/// 出这几枚是**一起**被加权的。现在圈成一块,读数只在框头报一次。
///
/// 成员仍是各自独立的芯片(照常点选、长按、加减权重),框只是背景 —— 它不
/// 拦手势,点框内空处和点别处一样落到底层那层空白手势上。
class _GroupBand extends StatelessWidget {
  const _GroupBand({
    required this.mult,
    required this.fontSize,
    required this.selected,
    required this.children,
  });

  final double mult;
  final double fontSize;

  /// 成员被一次选齐(词条栏的「选中整组」)= 选中的是整只框。
  /// 这时它接管高亮,搬动也带着记号一起走(见 [moveUnits])。
  final bool selected;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pal = context.editor;
    final scheme = context.scheme;
    final up = mult > 1;
    final i = up
        ? ((mult - 1) / 1.5).clamp(0.0, 1.0)
        : ((1 - mult) / 0.7).clamp(0.0, 1.0);
    final line = up ? pal.weightUpBorder : pal.weightDownBorder;
    // 框比芯片淡:它是底,芯片才是要读的东西。压不下去就成了一块色斑,
    // 里面那几颗反而看不清。
    final wash = pal.weightWash(mult);
    final pad = fontSize * 0.3;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer
            : wash == null
            ? null
            : Color.alphaBlend(
                wash.withValues(alpha: wash.a * .38),
                scheme.surface,
              ),
        border: Border.all(
          color: selected
              ? scheme.primary
              : line.withValues(alpha: .35 + i * .3),
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(fontSize * 0.7),
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              // 读数贴着左边那道框,和第一颗芯片之间留出与缝同宽的距离
              padding: EdgeInsets.only(left: pad * 0.5),
              child: Text(
                '${fmtMult(mult)}×',
                style: TextStyle(
                  fontSize: fontSize - _kTransDrop,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : up
                      ? pal.weightUp
                      : pal.weightDown,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 折叠 chip:和普通标签同款外观(单行,主色系),前缀 `#` 折叠符号 + 成员数。
/// 点它选中/移动,和散标签一视同仁;解散在正文点标题做。
class _FoldChip extends StatelessWidget {
  const _FoldChip({
    super.key,
    required this.name,
    required this.count,
    required this.fontSize,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String name;
  final int count;
  final double fontSize;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: selected
          ? scheme.primaryContainer
          : scheme.primary.withValues(alpha: .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.primary.withValues(alpha: .45),
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.7,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: mono(
                  context,
                  size: fontSize - _kTransDrop,
                  weight: FontWeight.w700,
                ).copyWith(color: scheme.primary.withValues(alpha: .8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    super.key,
    required this.tok,
    required this.showTrans,
    required this.translating,
    required this.pulse,
    required this.fontSize,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.band = 1,
    this.sd = false,
  });

  final Tok tok;

  /// 译文行:开着就**恒占一行**(有没有译文都占)。
  final bool showTrans;

  /// 译文还在路上:那一行画一条脉动占位条,而不是空着。
  final bool translating;

  /// 加载态共用的脉动(整片 chip 一个 ticker,不是一颗一个)。
  final Animation<double> pulse;

  final double fontSize;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 外面那只 [_GroupBand] 已经替本颗报掉的组倍率(不在组里=1)。
  /// 底色与读数都按**扣掉它之后**剩下的那点权重算 —— 框说过一遍的事,
  /// 每颗再说一遍就成了刷屏,而且看不出这几枚是一起被加权的。
  final double band;

  /// SD 权重语法 `(tag:1.2)`:tertiary 底提示可转换。
  final bool sd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final pal = context.editor;
    final mult = band == 0 ? tok.effMult : tok.effMult / band;
    final weightColor = mult > 1.0001
        ? pal.weightUp
        : mult < 0.9999
        ? pal.weightDown
        : null;
    // 权重底色/边框(web getWeightStyle 同款):越偏离 1 越深,禁用不铺色。
    // 浮卡样式:芯片用卡片色(深色再提亮一档),禁用的沉到页面底色。
    final float = context.skin.float;
    final base = !float
        ? scheme.surfaceContainerHigh
        : Theme.of(context).brightness == Brightness.dark
        ? Color.alphaBlend(
            scheme.onSurface.withValues(alpha: .06),
            scheme.surfaceContainerLow,
          )
        : scheme.surfaceContainerLow;
    var chipBg = base;
    var chipBorder = scheme.outlineVariant;
    if (tok.disabled) {
      // 禁用要一眼看得出来。原先只是「正常 chip + 灰字 + 一道细划线」,
      // 底和边框和旁边的普通 chip 一模一样,扫过去根本分不出来(实测反馈)。
      // 改成往下沉一档的底 + 淡到几乎没有的边:整颗 chip 从这一片里退出去。
      chipBg = float ? scheme.surface : scheme.surfaceContainerLowest;
      chipBorder = scheme.outlineVariant.withValues(alpha: .4);
    } else if (sd && !tok.disabled) {
      chipBg = Color.alphaBlend(scheme.tertiary.withValues(alpha: .14), base);
      chipBorder = scheme.tertiary.withValues(alpha: .55);
    } else if (weightColor != null && !tok.disabled) {
      // 与正文色带同源:EditorPalette.weightWash 统一色相与强度曲线
      final up = mult > 1;
      final i = up
          ? ((mult - 1) / 1.5).clamp(0.0, 1.0)
          : ((1 - mult) / 0.7).clamp(0.0, 1.0);
      chipBg = Color.alphaBlend(pal.weightWash(mult)!, base);
      chipBorder = (up ? pal.weightUpBorder : pal.weightDownBorder).withValues(
        alpha: .45 + i * .35,
      );
    }
    return Material(
      color: selected ? scheme.primaryContainer : chipBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: selected ? scheme.primary : chipBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.7,
            vertical: 6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 读数在名字**前**:和组框那只同一个位置、同一副写法,
                  // 扫一眼就知道「这一份加权管到哪儿为止」。
                  if (weightColor != null) ...[
                    Text(
                      '${fmtMult(mult)}×',
                      // 读数只报数,不跟着权重变红蓝 —— 高低看 chip 底色与边框
                      style: TextStyle(
                        fontSize: fontSize - _kTransDrop,
                        fontWeight: FontWeight.w700,
                        color: tok.disabled ? scheme.outline : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      tok.name,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: tok.disabled ? scheme.outline : scheme.onSurface,
                        decoration: tok.disabled
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: scheme.outline,
                        decorationThickness: 2,
                      ),
                    ),
                  ),
                ],
              ),
              // 译文行恒占位:译文是异步到货的,不预留高度的话每回一批就有
              // 一片 chip 先矮后长,整屏跟着重排 —— 那一下比没有译文难受得多。
              // 高度按字号算死(不靠内容撑),空着/加载中/有字三态严格等高。
              if (showTrans)
                SizedBox(
                  height: _transRowHeight(fontSize),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    // widthFactor 必须给。不给 = Align 撑满可用宽度,
                    // Column 跟着变满宽,整颗 chip 独占一整行。
                    widthFactor: 1,
                    child: tok.trans != null
                        ? Text(
                            tok.trans!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: fontSize - _kTransDrop,
                              height: _kTransLine,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : translating
                        ? _TransPulse(pulse: pulse, fontSize: fontSize)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 译文加载中的占位条。那一行本来就留着(见 [_transRowHeight]),与其空着,
/// 不如让它自己说明「在路上」—— 否则用户分不清是没译文还是还没到。
/// 只画一条脉动的小色块:文字版(「翻译中…」)比多数译文还长,一到货整行宽度
/// 就跳一下,反倒把预留高度省下的那点安定感又赔进去。
class _TransPulse extends StatelessWidget {
  const _TransPulse({required this.pulse, required this.fontSize});

  final Animation<double> pulse;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.scheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Container(
        width: fontSize * 2.4,
        height: (fontSize - _kTransDrop) * 0.66,
        decoration: BoxDecoration(
          color: c.withValues(alpha: .10 + .16 * pulse.value),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// chip 间的插入加号(选中词条后浮现)。
class _PlusDot extends StatelessWidget {
  const _PlusDot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.primaryContainer,
      shape: CircleBorder(
        side: BorderSide(color: scheme.primary.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.add, size: 18, color: scheme.primary),
        ),
      ),
    );
  }
}

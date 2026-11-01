import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';

/// 灵感页顶栏的分类页签:一条连续的横滚标签,选中项放大加深、下面一道与字同宽的主色线。
/// [position] 是正文翻页的位置(可在两页之间),短线和字跟着它过渡,标签条跟着滚,
/// 让当前项保持在中间。行末固定一颗「类别管理」(三横),标签条渐隐进它;
/// [capsule] 时两者一起包进一颗浅底胶囊,选中项改成白底滑块(不画下划线)。
class CategoryTabs extends StatefulWidget {
  const CategoryTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onTap,
    this.position,
    this.onManage,
    this.leftPad = 14,
    this.capsule = false,
    this.capsuleColor,
    this.rightPad = 4,
  });

  final List<String> labels;

  /// 当前页签;[position] 还没有值时按它画。
  final int index;
  final ValueChanged<int> onTap;
  final ValueListenable<double>? position;

  /// null = 不出行末的「类别管理」。
  final VoidCallback? onManage;
  final double leftPad;

  /// 整条(含行末的类别管理)包进一颗浅底胶囊。
  final bool capsule;

  /// 胶囊底色;默认按压在页面上取色。
  final Color? capsuleColor;

  /// 胶囊右边离外面的距离(后面还跟着按钮时留一点缝,贴边时与左边对称)。
  final double rightPad;

  @override
  State<CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<CategoryTabs> {
  /// 页签两侧留白;胶囊里放宽,每类更宽、整条更扁。
  double get _padH => widget.capsule ? 16 : 11;

  /// 选中项放大的比例。字号不变、只做缩放,页签宽度就是固定的,短线好对位。
  static const _grow = .2;

  /// 标签内容离滚动区左边的距离(胶囊里就从胶囊内边算)。
  double get _contentLeft => widget.capsule ? 3 : widget.leftPad - _padH;

  final _scroll = ScrollController();
  final _stripKey = GlobalKey();
  final _keys = <GlobalKey>[];

  /// 各页签中心在标签条里的横坐标、字宽(量出来的);没量到之前不画短线。
  List<double> _centers = const [];
  List<double> _widths = const [];

  /// 按翻页位置画;还没有位置时按 [CategoryTabs.index]。
  double get _pos {
    final p = widget.position?.value;
    if (p == null || widget.labels.isEmpty) return widget.index.toDouble();
    return p.clamp(0.0, widget.labels.length - 1.0);
  }

  @override
  void initState() {
    super.initState();
    widget.position?.addListener(_follow);
    _measureLater();
  }

  @override
  void didUpdateWidget(covariant CategoryTabs old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position?.removeListener(_follow);
      widget.position?.addListener(_follow);
    }
    if (old.labels.join('\n') != widget.labels.join('\n')) _measureLater();
    if (old.index != widget.index) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _centerOn(_pos));
    }
  }

  void _follow() {
    if (!mounted) return;
    setState(() {});
    _centerOn(_pos);
  }

  void _measureLater() =>
      SchedulerBinding.instance.addPostFrameCallback((_) => _measure());

  void _measure() {
    if (!mounted) return;
    final strip = _stripKey.currentContext?.findRenderObject() as RenderBox?;
    if (strip == null || !strip.hasSize) return;
    final centers = <double>[];
    final widths = <double>[];
    for (final k in _keys.take(widget.labels.length)) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      centers.add(
        box.localToGlobal(Offset(box.size.width / 2, 0), ancestor: strip).dx,
      );
      widths.add(box.size.width - _padH * 2);
    }
    setState(() {
      _centers = centers;
      _widths = widths;
    });
    _centerOn(_pos);
  }

  /// 位置 [p] 处(可在两个页签之间)的中心横坐标。
  double? _centerAt(double p) {
    if (_centers.isEmpty) return null;
    final c = p.clamp(0.0, _centers.length - 1.0);
    final i = c.floor(), j = c.ceil();
    return _centers[i] + (_centers[j] - _centers[i]) * (c - i);
  }

  /// 位置 [p] 处短线的宽度:跟字一样宽(选中项放大过,也乘上),两页之间渐变。
  double _widthAt(double p) {
    final c = p.clamp(0.0, _widths.length - 1.0);
    final i = c.floor(), j = c.ceil();
    return (_widths[i] + (_widths[j] - _widths[i]) * (c - i)) * (1 + _grow);
  }

  /// 胶囊里滑块的宽度:字宽加两侧留白,两页之间渐变。
  double _pillWidthAt(double p) {
    final c = p.clamp(0.0, _widths.length - 1.0);
    final i = c.floor(), j = c.ceil();
    return _widths[i] + (_widths[j] - _widths[i]) * (c - i) + _padH * 2;
  }

  void _centerOn(double p) {
    final x = _centerAt(p);
    if (x == null || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (x + _contentLeft - pos.viewportDimension / 2).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() > .5) _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    widget.position?.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    while (_keys.length < widget.labels.length) {
      _keys.add(GlobalKey());
    }
    final pos = _pos;
    final x = _centerAt(pos);
    final row = Row(
      children: [
        Expanded(
          // 右缘渐隐进后面的类别管理钮,两者看着是一条
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              colors: const [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 1 - 28 / rect.width.clamp(56, double.infinity), 1],
            ).createShader(rect),
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              // 右边留出渐隐那一截,滚到底时最后一个页签不被压暗
              padding: EdgeInsets.only(left: _contentLeft, right: 28),
              child: Stack(
                key: _stripKey,
                children: [
                  // 胶囊里:选中项垫一块圆头白底滑块(底色、阴影同「我的 / 公共」分段),跟着翻页滑
                  if (x != null && widget.capsule)
                    Positioned(
                      left: x - _pillWidthAt(pos) / 2,
                      top: 3,
                      bottom: 3,
                      child: Container(
                        width: _pillWidthAt(pos),
                        decoration: BoxDecoration(
                          color: context.segThumb,
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.labels.length; i++)
                        _tab(context, i, pos, scheme),
                    ],
                  ),
                  if (x != null && !widget.capsule)
                    Positioned(
                      left: x - _widthAt(pos) / 2,
                      bottom: 4,
                      child: Container(
                        width: _widthAt(pos),
                        height: 3,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 固定在页签外面,页签再多也不会被挤到滚动区后头。用和页签字同色的
        // 三横,下移一点对齐页签的字
        if (widget.onManage != null)
          Padding(
            padding: EdgeInsets.only(top: widget.capsule ? 0 : 4),
            child: IconButton(
              tooltip: '类别管理',
              visualDensity: widget.capsule ? VisualDensity.compact : null,
              onPressed: widget.onManage,
              icon: Icon(
                Icons.menu_rounded,
                size: 24,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
    if (!widget.capsule) return SizedBox(height: 48, child: row);
    return SizedBox(
      height: 48,
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.leftPad, 4, widget.rightPad, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: widget.capsuleColor ?? context.pageControlFill,
            child: row,
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i, double pos, ColorScheme scheme) {
    final t = (1 - (i - pos).abs()).clamp(0.0, 1.0);
    return GestureDetector(
      key: _keys[i],
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(i),
      child: Padding(
        padding: EdgeInsets.fromLTRB(_padH, 0, _padH, widget.capsule ? 0 : 12),
        child: Align(
          // 胶囊里字居中、不放大,选中靠滑块和主色字;外面照旧底对齐 + 放大
          alignment: widget.capsule ? Alignment.center : Alignment.bottomCenter,
          child: Transform.scale(
            scale: widget.capsule ? 1 : 1 + _grow * t,
            alignment: Alignment.bottomCenter,
            child: Text(
              widget.labels[i],
              maxLines: 1,
              style: context.texts.titleMedium!.copyWith(
                fontSize: 15,
                height: 1.2,
                // 字重也不变:换字重会改宽度,短线就对不准了
                fontWeight: FontWeight.w700,
                color: Color.lerp(
                  scheme.onSurfaceVariant,
                  widget.capsule
                      ? context.segLabel(scheme.primary)
                      : scheme.onSurface,
                  t,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

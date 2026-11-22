import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 每条主轴长度各不相同的长列表。按给定的起点表定位、布局时二分查找;
/// [SliverVariedExtentList] 每次布局都从第 0 条累加,滚到几万条之后每帧都在算。
class SliverPrefixExtentList extends SliverMultiBoxAdaptorWidget {
  const SliverPrefixExtentList({
    super.key,
    required super.delegate,
    required this.offsets,
  });

  /// 第 i 条的起点,长度 = 条数 + 1,末项是总长。
  final List<double> offsets;

  @override
  RenderSliverFixedExtentBoxAdaptor createRenderObject(BuildContext context) =>
      RenderSliverPrefixExtentList(
        childManager: context as SliverMultiBoxAdaptorElement,
        offsets: offsets,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverPrefixExtentList renderObject,
  ) {
    renderObject.offsets = offsets;
  }
}

/// [SliverPrefixExtentList] 的渲染对象。
class RenderSliverPrefixExtentList extends RenderSliverFixedExtentBoxAdaptor {
  RenderSliverPrefixExtentList({
    required super.childManager,
    required List<double> offsets,
  }) : _offsets = offsets; // ignore: prefer_initializing_formals

  List<double> _offsets;
  set offsets(List<double> v) {
    if (identical(v, _offsets)) return;
    _offsets = v;
    markNeedsLayout();
  }

  int get _count => _offsets.length - 1;

  @override
  double? get itemExtent => null;

  @override
  ItemExtentBuilder? get itemExtentBuilder => _extentAt;

  double? _extentAt(int i, SliverLayoutDimensions _) =>
      i >= 0 && i < _count ? _offsets[i + 1] - _offsets[i] : null;

  @override
  double indexToLayoutOffset(double itemExtent, int index) =>
      _offsets[index.clamp(0, _count)];

  /// 与父类同口径:第一条终点 ≥ [scrollOffset] 的下标;超出总长给最后一条。
  int _indexAt(double scrollOffset) {
    if (scrollOffset == 0.0) return 0;
    if (_count == 0) return -1;
    var lo = 0, hi = _count - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_offsets[mid + 1] >= scrollOffset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _indexAt(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _indexAt(scrollOffset);

  @override
  double computeMaxScrollOffset(
    SliverConstraints constraints,
    double itemExtent,
  ) => _offsets[_count];
}

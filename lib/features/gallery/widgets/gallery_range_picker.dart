import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../core/util/haptics.dart';

/// Material 风格的范围日历；只有蓝色端点接管拖动，其余位置仍交给月份滚动。
class GalleryRangePicker extends StatefulWidget {
  const GalleryRangePicker({
    super.key,
    required this.initialRange,
    required this.firstDate,
    required this.lastDate,
    this.currentDate,
  });

  final DateTimeRange initialRange;
  final DateTime firstDate, lastDate;
  final DateTime? currentDate;

  @override
  State<GalleryRangePicker> createState() => _GalleryRangePickerState();
}

class _GalleryRangePickerState extends State<GalleryRangePicker>
    with SingleTickerProviderStateMixin {
  late DateTime _start = DateUtils.dateOnly(widget.initialRange.start);
  late DateTime? _end = DateUtils.dateOnly(widget.initialRange.end);
  late final DateTime _today = DateUtils.dateOnly(
    widget.currentDate ?? DateTime.now(),
  );
  late final int _initialMonth = DateUtils.monthDelta(widget.firstDate, _start);
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _after = UniqueKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Offset? _pointer, _down;
  DateTime? _anchor, _origin, _lastDragDay;
  (DateTime, DateTime?)? _beforeDrag;
  bool _dragging = false, _moved = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_autoScroll);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _enabled(DateTime day) =>
      !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);

  DateTime? _dayAt(Offset position) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      position,
      View.of(context).viewId,
    );
    for (final entry in hit.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is _RangeDay) {
        final day = (target.metaData as _RangeDay).date;
        if (_enabled(day)) return day;
      }
    }
    return null;
  }

  bool _canDrag(Offset position) {
    if (_dragging) return false;
    final day = _dayAt(position);
    return day != null && (day == _start || day == _end);
  }

  void _startDrag(Offset position) {
    final day = _dayAt(position)!;
    _beforeDrag = (_start, _end);
    _origin = _lastDragDay = day;
    // 固定另一端；越过它时自动交换起止，不产生反向或无效范围。
    _anchor = day == _start && _end != null && _end != _start ? _end : _start;
    _pointer = _down = position;
    _moved = false;
    _lastTick = Duration.zero;
    setState(() => _dragging = true);
    _ticker.start();
  }

  void _moveDrag(Offset position) {
    _pointer = position;
    _moved = _moved || (position - _down!).distance > kTouchSlop;
    if (!_moved) return;
    final day = _dayAt(position);
    if (day == null || day == _lastDragDay) return;
    _lastDragDay = day;
    final anchor = _anchor!;
    setState(() {
      _start = day.isBefore(anchor) ? day : anchor;
      _end = day.isBefore(anchor) ? anchor : day;
    });
    Haptics.selection();
  }

  void _endDrag(Offset position) {
    _moveDrag(position);
    _ticker.stop();
    final tap = !_moved;
    final origin = _origin!;
    setState(() => _dragging = false);
    if (tap) _pick(origin);
  }

  void _cancelDrag() {
    _ticker.stop();
    final previous = _beforeDrag;
    if (!mounted || previous == null) return;
    setState(() {
      _dragging = false;
      _start = previous.$1;
      _end = previous.$2;
    });
  }

  void _autoScroll(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (!_moved || !_scroll.hasClients) return;
    final box = _viewport.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final point = _pointer!;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    if (point.dx < bounds.left || point.dx > bounds.right) return;
    const edge = 48.0;
    final speed = point.dy < bounds.top + edge
        ? -280 * ((bounds.top + edge - point.dy) / edge).clamp(0.0, 1.0)
        : point.dy > bounds.bottom - edge
        ? 280 * ((point.dy - bounds.bottom + edge) / edge).clamp(0.0, 1.0)
        : 0.0;
    if (speed == 0) return;
    final position = _scroll.position;
    final next = (position.pixels + speed * math.min(dt, .05)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return;
    _scroll.jumpTo(next);
    // 滚动布局完成后再按实际命中的日期更新，避免使用旧格子坐标。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dragging) _moveDrag(_pointer!);
    });
  }

  void _pick(DateTime day) {
    if (_dragging) return;
    Haptics.selection();
    setState(() {
      if (_end == null && !day.isBefore(_start)) {
        _end = day;
      } else {
        _start = day;
        _end = null;
      }
    });
  }

  Future<void> _input() async {
    final pickerContext = context;
    final range = await showDateRangePicker(
      context: context,
      builder: (_, child) =>
          Localizations.override(context: pickerContext, child: child),
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      currentDate: _today,
      initialDateRange: DateTimeRange(start: _start, end: _end ?? _start),
      initialEntryMode: DatePickerEntryMode.inputOnly,
      helpText: '选择起止日期（包含结束当天）',
      cancelText: '返回日历',
      confirmText: '应用',
      fieldStartLabelText: '开始日期',
      fieldEndLabelText: '结束日期',
    );
    if (range != null && mounted) Navigator.pop(context, range);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final localizations = MaterialLocalizations.of(context);
    final header =
        colors.rangePickerHeaderForegroundColor ??
        defaults.rangePickerHeaderForegroundColor;
    final textStyle =
        colors.rangePickerHeaderHeadlineStyle ??
        defaults.rangePickerHeaderHeadlineStyle;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    String dateLabel(DateTime day) =>
        day.year == _today.year && _start.year == (_end ?? _start).year
        ? localizations.formatShortMonthDay(day)
        : localizations.formatShortDate(day);
    final input = IconButton(
      tooltip: localizations.inputDateModeButtonLabel,
      onPressed: _dragging ? null : _input,
      icon: const Icon(Icons.edit_outlined),
    );
    final monthCount =
        DateUtils.monthDelta(widget.firstDate, widget.lastDate) + 1;
    final calendarWidth = landscape ? 384.0 : 480.0;
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor:
            colors.rangePickerBackgroundColor ??
            defaults.rangePickerBackgroundColor,
        appBar: AppBar(
          backgroundColor:
              colors.rangePickerHeaderBackgroundColor ??
              defaults.rangePickerHeaderBackgroundColor,
          foregroundColor: header,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: '取消',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (landscape) input,
            TextButton(
              style: TextButton.styleFrom(foregroundColor: header),
              onPressed: _end == null || _dragging
                  ? null
                  : () => Navigator.pop(
                      context,
                      DateTimeRange(start: _start, end: _end!),
                    ),
              child: const Text('应用'),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              math.max(
                80,
                80 * MediaQuery.textScalerOf(context).scale(14) / 14,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: MediaQuery.sizeOf(context).width < 360 ? 24 : 56,
                right: 8,
                bottom: 16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择起止日期（包含结束当天）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (colors.rangePickerHeaderHelpStyle ??
                                      defaults.rangePickerHeaderHelpStyle)
                                  ?.copyWith(color: header),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            '${dateLabel(_start)} – ${_end == null ? '结束日期' : dateLabel(_end!)}',
                            style: textStyle?.copyWith(color: header),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!landscape) input,
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: calendarWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      height: 42,
                      child: Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: ExcludeSemantics(
                                child: Center(
                                  child: Text(
                                    localizations.narrowWeekdays[(i +
                                            localizations.firstDayOfWeekIndex) %
                                        7],
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: RawGestureDetector(
                  gestures: {
                    _EndpointDrag:
                        GestureRecognizerFactoryWithHandlers<_EndpointDrag>(
                          _EndpointDrag.new,
                          (gesture) => gesture
                            ..canStart = _canDrag
                            ..onStart = _startDrag
                            ..onMove = _moveDrag
                            ..onEnd = _endDrag
                            ..onCancel = _cancelDrag,
                        ),
                  },
                  child: CustomScrollView(
                    key: _viewport,
                    controller: _scroll,
                    center: _after,
                    slivers: [
                      SliverList.builder(
                        itemCount: _initialMonth,
                        itemBuilder: (_, index) =>
                            _month(_initialMonth - index - 1, calendarWidth),
                      ),
                      SliverList.builder(
                        key: _after,
                        itemCount: monthCount - _initialMonth,
                        itemBuilder: (_, index) =>
                            _month(_initialMonth + index, calendarWidth),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _month(int index, double maxWidth) {
    final month = DateUtils.addMonthsToMonthDate(widget.firstDate, index);
    final labels = MaterialLocalizations.of(context);
    final offset = DateUtils.firstDayOffset(month.year, month.month, labels);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = (offset + days + 6) ~/ 7;
    final height = math.max(
      42.0,
      MediaQuery.textScalerOf(context).scale(20) + 16,
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: AlignmentDirectional.centerStart,
              child: Text(labels.formatMonthYear(month)),
            ),
            for (var row = 0; row < rows; row++)
              Padding(
                padding: EdgeInsets.only(bottom: row == rows - 1 ? 12 : 8),
                child: SizedBox(
                  height: height,
                  child: CustomPaint(
                    painter: _RangeBand(
                      start: _start,
                      end: _end,
                      month: month,
                      firstDay: row * 7 - offset + 1,
                      daysInMonth: days,
                      color:
                          DatePickerTheme.of(
                            context,
                          ).rangeSelectionBackgroundColor ??
                          DatePickerTheme.defaults(
                            context,
                          ).rangeSelectionBackgroundColor!,
                      direction: Directionality.of(context),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        for (var column = 0; column < 7; column++)
                          Expanded(
                            child:
                                row * 7 + column - offset + 1 < 1 ||
                                    row * 7 + column - offset + 1 > days
                                ? const SizedBox.shrink()
                                : _day(
                                    DateTime(
                                      month.year,
                                      month.month,
                                      row * 7 + column - offset + 1,
                                    ),
                                  ),
                          ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _day(DateTime day) {
    final theme = Theme.of(context);
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final labels = MaterialLocalizations.of(context);
    final enabled = _enabled(day);
    final start = day == _start, end = day == _end;
    final selected = start || end;
    final inside = _end != null && !day.isBefore(_start) && !day.isAfter(_end!);
    final states = {
      if (selected) WidgetState.selected,
      if (!enabled) WidgetState.disabled,
    };
    final shape =
        picker.dayShape?.resolve(states) ??
        defaults.dayShape?.resolve(states) ??
        const CircleBorder();
    final color =
        picker.dayForegroundColor?.resolve(states) ??
        defaults.dayForegroundColor?.resolve(states);
    final background =
        picker.dayBackgroundColor?.resolve(states) ??
        defaults.dayBackgroundColor?.resolve(states);
    final today = day == _today;
    final dayText = labels.formatDecimal(day.day);
    var semantics = '$dayText, ${labels.formatFullDate(day)}';
    if (today) semantics += ', ${labels.currentDateLabel}';
    if (start) semantics = labels.dateRangeStartDateSemanticLabel(semantics);
    if (end) semantics = labels.dateRangeEndDateSemanticLabel(semantics);
    return MetaData(
      key: ValueKey<DateTime>(day),
      metaData: _RangeDay(day),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: enabled ? () => _pick(day) : null,
              customBorder: shape,
              containedInkWell: true,
              child: Container(
                alignment: Alignment.center,
                decoration: selected
                    ? ShapeDecoration(color: background, shape: shape)
                    : today && !inside
                    ? ShapeDecoration(
                        shape: shape.copyWith(
                          side: picker.todayBorder ?? defaults.todayBorder!,
                        ),
                      )
                    : null,
                child: Semantics(
                  label: semantics,
                  hint: selected ? '可直接拖动调整日期' : null,
                  selected: selected,
                  child: ExcludeSemantics(
                    child: Text(
                      dayText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: today && !inside && !selected
                            ? theme.colorScheme.primary
                            : color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeDay {
  const _RangeDay(this.date);
  final DateTime date;
}

/// 每周只画一条连续色带，避免半透明格子边缘叠色，并延伸到周行边缘。
class _RangeBand extends CustomPainter {
  const _RangeBand({
    required this.start,
    required this.end,
    required this.month,
    required this.firstDay,
    required this.daysInMonth,
    required this.color,
    required this.direction,
  });
  final DateTime start, month;
  final DateTime? end;
  final int firstDay, daysInMonth;
  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final end = this.end;
    if (end == null || end == start) return;
    final first = DateTime(month.year, month.month, math.max(1, firstDay));
    final last = DateTime(
      month.year,
      month.month,
      math.min(daysInMonth, firstDay + 6),
    );
    if (end.isBefore(first) || start.isAfter(last)) return;
    final tile = (size.width - 16) / 7;
    final firstColumn = first.day - firstDay;
    final lastColumn = last.day - firstDay;
    final left = !start.isBefore(first)
        ? 8 + (start.day - firstDay + .5) * tile
        : firstColumn == 0
        ? 0.0
        : 8 + firstColumn * tile;
    final right = !end.isAfter(last)
        ? 8 + (end.day - firstDay + .5) * tile
        : lastColumn == 6
        ? size.width
        : 8 + (lastColumn + 1) * tile;
    canvas.drawRect(
      Rect.fromLTRB(
        direction == TextDirection.rtl ? size.width - right : left,
        0,
        direction == TextDirection.rtl ? size.width - left : right,
        size.height,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RangeBand old) =>
      old.start != start ||
      old.end != end ||
      old.month != month ||
      old.firstDay != firstDay ||
      old.daysInMonth != daysInMonth ||
      old.color != color ||
      old.direction != direction;
}

/// 端点按下即接管指针，避免纵向拖动被月份 Scrollable 抢走。
/// 识别器挂在视口上，端点随拖动换格或滚出屏幕时不会丢失手势。
class _EndpointDrag extends OneSequenceGestureRecognizer {
  bool Function(Offset)? canStart;
  ValueChanged<Offset>? onStart, onMove, onEnd;
  VoidCallback? onCancel;
  int? _pointer;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null &&
      (canStart?.call(event.position) ?? false) &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event.position);
  }

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    // 普通日期不入场；额外手指也不能取消已经接管的端点指针。
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) onMove?.call(event.position);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (event is PointerUpEvent) {
        onEnd?.call(event.position);
      } else {
        onCancel?.call();
      }
      stopTrackingPointer(event.pointer);
      _pointer = null;
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) {
      onCancel?.call();
      stopTrackingPointer(pointer);
      _pointer = null;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'gallery date endpoint';
}

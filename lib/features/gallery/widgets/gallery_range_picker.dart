import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;

import '../../../core/util/haptics.dart';
import '../../../l10n/l10n.dart';

// 尺寸与行高取 showDatePicker(Material 3)的数值:和「指定日期」那只弹窗
// 并排看是同一套东西。Flutter 自带的范围日历只有全屏一种,所以这里自己画。
const _portraitSize = Size(360, 568);
const _landscapeSize = Size(496, 346);
const _headerHeight = 120.0;
const _headerLandscapeWidth = 152.0;
const _subHeaderHeight = 52.0;
const _actionsHeight = 52.0;
// 字号上限同 showDateRangePicker;再大六周排不下。
const _maxTextScale = 1.3;
const _monthDuration = Duration(milliseconds: 200);
// 端点拖出日历后先停一下再翻,免得拖过头一路翻走;按住不放则接着翻。
const _flipDelay = Duration(milliseconds: 450);
const _flipRepeat = Duration(milliseconds: 700);

/// 日期范围弹窗:标题、年月切换、按月翻页、取消 / 应用,版式同单日选择器。
///
/// 点选:先点起点再点终点;范围完整时再点一天就从那天重新开始。
/// 蓝色端点按下即可拖动;拖到日历上方 / 下方停一下,翻到上 / 下个月接着拖。
/// 其余位置照常左右滑动翻月。
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

class _GalleryRangePickerState extends State<GalleryRangePicker> {
  late DateTime _start = DateUtils.dateOnly(widget.initialRange.start);
  late DateTime? _end = DateUtils.dateOnly(widget.initialRange.end);
  late final DateTime _today = DateUtils.dateOnly(
    widget.currentDate ?? DateTime.now(),
  );
  late final DateTime _first = DateUtils.dateOnly(widget.firstDate);
  late final DateTime _last = DateUtils.dateOnly(widget.lastDate);
  late final int _monthCount = DateUtils.monthDelta(_first, _last) + 1;
  late PageController _pages = _pagesAt(_pageOf(_start));
  late DateTime _month = _monthAt(_pages.initialPage);
  bool _years = false;
  final _grid = GlobalKey();
  Timer? _flip;
  int _flipDir = 0;
  Offset? _pointer, _down;
  DateTime? _anchor, _origin, _lastDragDay;
  (DateTime, DateTime?)? _beforeDrag;
  bool _dragging = false, _moved = false;

  int _pageOf(DateTime day) =>
      DateUtils.monthDelta(_first, day).clamp(0, _monthCount - 1);
  DateTime _monthAt(int page) => DateUtils.addMonthsToMonthDate(_first, page);

  // 从年份列表回来要换新控制器;keepPage 关掉,免得被 PageStorage 拉回旧页。
  PageController _pagesAt(int page) =>
      PageController(initialPage: page, keepPage: false);

  @override
  void dispose() {
    _flip?.cancel();
    _pages.dispose();
    super.dispose();
  }

  bool _enabled(DateTime day) => !day.isBefore(_first) && !day.isAfter(_last);

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
    if (_dragging || _years) return false;
    final day = _dayAt(position);
    return day != null && (day == _start || day == _end);
  }

  void _startDrag(Offset position) {
    final day = _dayAt(position)!;
    _beforeDrag = (_start, _end);
    _origin = _lastDragDay = day;
    // 固定另一端;越过它时自动交换起止,不产生反向或无效范围。
    _anchor = day == _start && _end != null && _end != _start ? _end : _start;
    _pointer = _down = position;
    _moved = false;
    setState(() => _dragging = true);
  }

  void _moveDrag(Offset position) {
    _pointer = position;
    _moved = _moved || (position - _down!).distance > kTouchSlop;
    if (!_moved) return;
    _updateFlip(position);
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
    _stopFlip();
    final tap = !_moved;
    final origin = _origin!;
    setState(() => _dragging = false);
    if (tap) _pick(origin);
  }

  void _cancelDrag() {
    _stopFlip();
    final previous = _beforeDrag;
    if (!mounted || previous == null) return;
    setState(() {
      _dragging = false;
      _start = previous.$1;
      _end = previous.$2;
    });
  }

  /// 手指在日历上方 → 往前翻,在下方 → 往后翻,回到日历里就停。
  void _updateFlip(Offset position) {
    final box = _grid.currentContext?.findRenderObject();
    var dir = 0;
    if (box is RenderBox && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      dir = position.dy < rect.top
          ? -1
          : position.dy > rect.bottom
          ? 1
          : 0;
    }
    if (dir == _flipDir) return;
    _stopFlip();
    _flipDir = dir;
    if (dir != 0) _flip = Timer(_flipDelay, _flipMonth);
  }

  void _stopFlip() {
    _flip?.cancel();
    _flip = null;
    _flipDir = 0;
  }

  void _flipMonth() {
    if (!mounted || !_dragging || !_pages.hasClients) return;
    final page = _pages.page!.round() + _flipDir;
    if (page < 0 || page >= _monthCount) return;
    Haptics.selection();
    _pages
        .animateToPage(page, duration: _monthDuration, curve: Curves.ease)
        .then((_) {
          // 翻完按手指实际压着的那天再算一次,不沿用翻页前的格子。
          if (mounted && _dragging) _moveDrag(_pointer!);
        });
    _flip = Timer(_flipRepeat, _flipMonth);
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

  void _showMonth(DateTime month) {
    // 年份列表期间月份页不在树上,旧控制器已脱离,可以直接换掉。
    final old = _pages;
    final page = _pageOf(month);
    setState(() {
      _years = false;
      _pages = _pagesAt(page);
      _month = _monthAt(page);
    });
    old.dispose();
  }

  Future<void> _input() async {
    final pickerContext = context;
    final range = await showDateRangePicker(
      context: context,
      builder: (_, child) =>
          Localizations.override(context: pickerContext, child: child),
      firstDate: _first,
      lastDate: _last,
      currentDate: _today,
      initialDateRange: DateTimeRange(start: _start, end: _end ?? _start),
      initialEntryMode: DatePickerEntryMode.inputOnly,
      helpText: context.l10n.selectDateRange,
      cancelText: context.l10n.backToCalendar,
      confirmText: context.l10n.applyLabel,
      fieldStartLabelText: context.l10n.startDate,
      fieldEndLabelText: context.l10n.endDate,
    );
    if (range != null && mounted) Navigator.pop(context, range);
  }

  @override
  Widget build(BuildContext context) {
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final scale =
        MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: _maxTextScale).scale(14) /
        14;
    final size = (landscape ? _landscapeSize : _portraitSize) * scale;
    return Dialog(
      backgroundColor: picker.backgroundColor ?? defaults.backgroundColor,
      elevation: picker.elevation ?? defaults.elevation,
      shadowColor: picker.shadowColor ?? defaults.shadowColor,
      surfaceTintColor: picker.surfaceTintColor ?? defaults.surfaceTintColor,
      shape: picker.shape ?? defaults.shape,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _maxTextScale,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final calendar = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _monthBar(),
                  Expanded(child: _years ? _yearList() : _pager(landscape)),
                  _actions(),
                ],
              );
              if (landscape) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(landscape: true),
                    VerticalDivider(width: 0, color: picker.dividerColor),
                    Expanded(child: calendar),
                  ],
                );
              }
              // 分屏之类的矮窗口先让出标题栏,日历本身保持能用。
              final roomy =
                  constraints.maxHeight >=
                  _headerHeight + _subHeaderHeight + _actionsHeight + 7 * 32;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (roomy) ...[
                    _header(landscape: false),
                    Divider(height: 0, color: picker.dividerColor),
                  ],
                  Expanded(child: calendar),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header({required bool landscape}) {
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final labels = MaterialLocalizations.of(context);
    final foreground =
        picker.headerForegroundColor ?? defaults.headerForegroundColor;
    final help = Text(
      context.l10n.selectDateRange,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (picker.headerHelpStyle ?? defaults.headerHelpStyle)?.copyWith(
        color: foreground,
      ),
    );
    String label(DateTime day) =>
        day.year == _today.year && _start.year == (_end ?? _start).year
        ? labels.formatShortMonthDay(day)
        : labels.formatShortDate(day);
    final text =
        '${label(_start)} – ${_end == null ? labels.dateRangeEndLabel : label(_end!)}';
    final titleStyle =
        (picker.headerHeadlineStyle ?? defaults.headerHeadlineStyle)?.copyWith(
          color: foreground,
        );
    final input = IconButton(
      tooltip: labels.inputDateModeButtonLabel,
      color: foreground,
      onPressed: _dragging ? null : _input,
      icon: const Icon(Icons.edit_outlined),
    );
    final background =
        picker.headerBackgroundColor ?? defaults.headerBackgroundColor;
    if (landscape) {
      return SizedBox(
        width: _headerLandscapeWidth,
        child: Material(
          color: background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: help,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 8,
                  end: 4,
                  bottom: 6,
                ),
                child: input,
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: _headerHeight,
      child: Material(
        color: background,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 24,
            end: 12,
            bottom: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              help,
              const Flexible(child: SizedBox(height: 38)),
              Row(
                children: [
                  Expanded(
                    // 跨年时两端都带年份,缩一号也不折行。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(text, style: titleStyle),
                    ),
                  ),
                  input,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthBar() {
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final labels = MaterialLocalizations.of(context);
    final color =
        picker.subHeaderForegroundColor ?? defaults.subHeaderForegroundColor;
    final page = _pageOf(_month);
    return SizedBox(
      height: _subHeaderHeight,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  label: labels.selectYearSemanticsLabel,
                  button: true,
                  child: InkWell(
                    onTap: _dragging
                        ? null
                        : _years
                        ? () => _showMonth(_month)
                        : () => setState(() => _years = true),
                    child: SizedBox(
                      height: _subHeaderHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                labels.formatMonthYear(_month),
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (picker.toggleButtonTextStyle ??
                                            defaults.toggleButtonTextStyle)
                                        ?.apply(color: color),
                              ),
                            ),
                            Icon(
                              _years
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              color: color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_years) ...[
              IconButton(
                color: color,
                tooltip: page == 0 ? null : labels.previousMonthTooltip,
                onPressed: page == 0 || _dragging
                    ? null
                    : () => _pages.previousPage(
                        duration: _monthDuration,
                        curve: Curves.ease,
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                color: color,
                tooltip: page == _monthCount - 1
                    ? null
                    : labels.nextMonthTooltip,
                onPressed: page == _monthCount - 1 || _dragging
                    ? null
                    : () => _pages.nextPage(
                        duration: _monthDuration,
                        curve: Curves.ease,
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _yearList() => YearPicker(
    currentDate: _today,
    firstDate: _first,
    lastDate: _last,
    selectedDate: _month,
    onChanged: _showMonth,
  );

  Widget _pager(bool landscape) => RawGestureDetector(
    key: _grid,
    gestures: {
      _EndpointDrag: GestureRecognizerFactoryWithHandlers<_EndpointDrag>(
        _EndpointDrag.new,
        (gesture) => gesture
          ..canStart = _canDrag
          ..onStart = _startDrag
          ..onMove = _moveDrag
          ..onEnd = _endDrag
          ..onCancel = _cancelDrag,
      ),
    },
    // 墨水涟漪画在透明 Material 上,翻页过渡时不越出日历。
    child: Material(
      type: MaterialType.transparency,
      child: PageView.builder(
        controller: _pages,
        itemCount: _monthCount,
        onPageChanged: (page) => setState(() => _month = _monthAt(page)),
        itemBuilder: (_, page) => _monthGrid(_monthAt(page), landscape),
      ),
    ),
  );

  Widget _monthGrid(DateTime month, bool landscape) {
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final labels = MaterialLocalizations.of(context);
    final offset = DateUtils.firstDayOffset(month.year, month.month, labels);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = (offset + days + 6) ~/ 7;
    final inset = landscape ? 8.0 : 12.0;
    final pad = landscape ? 2.0 : 4.0;
    final band =
        picker.rangeSelectionBackgroundColor ??
        defaults.rangeSelectionBackgroundColor!;
    DateTime? dayAt(int row, int column) {
      final n = row * 7 + column - offset + 1;
      return n < 1 || n > days ? null : DateTime(month.year, month.month, n);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 表头 + 最多六周;放不下时按高度均分,和 showDatePicker 一样。
        final rowHeight = math.min(
          landscape ? 42.0 : 48.0,
          constraints.maxHeight / 7,
        );
        return Column(
          children: [
            SizedBox(
              height: rowHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: ExcludeSemantics(
                          child: Center(
                            child: Text(
                              labels.narrowWeekdays[(i +
                                      labels.firstDayOfWeekIndex) %
                                  7],
                              style:
                                  picker.weekdayStyle ?? defaults.weekdayStyle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (var row = 0; row < rows; row++)
              SizedBox(
                height: rowHeight,
                child: CustomPaint(
                  painter: _bandFor(
                    [for (var c = 0; c < 7; c++) dayAt(row, c)],
                    inset: inset,
                    pad: pad,
                    color: band,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      children: [
                        for (var c = 0; c < 7; c++)
                          Expanded(
                            child: switch (dayAt(row, c)) {
                              final day? => _day(day, pad),
                              null => const SizedBox.shrink(),
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  _RangeBand? _bandFor(
    List<DateTime?> week, {
    required double inset,
    required double pad,
    required Color color,
  }) {
    final end = _end;
    if (end == null || end == _start) return null;
    int? from, to;
    for (var c = 0; c < 7; c++) {
      final day = week[c];
      if (day == null || day.isBefore(_start) || day.isAfter(end)) continue;
      from ??= c;
      to = c;
    }
    if (from == null) return null;
    return _RangeBand(
      from: from,
      to: to!,
      openStart: week[from] != _start,
      openEnd: week[to] != end,
      inset: inset,
      pad: pad,
      color: color,
      direction: Directionality.of(context),
    );
  }

  Widget _day(DateTime day, double pad) {
    final theme = Theme.of(context);
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final labels = MaterialLocalizations.of(context);
    final enabled = _enabled(day);
    final start = day == _start, end = day == _end;
    final selected = start || end;
    final inside = _end != null && !day.isBefore(_start) && !day.isAfter(_end!);
    final today = day == _today;
    final states = {
      if (selected) WidgetState.selected,
      if (!enabled) WidgetState.disabled,
    };
    T? resolve<T>(
      WidgetStateProperty<T>? Function(DatePickerThemeData theme) property,
    ) => (property(picker) ?? property(defaults))?.resolve(states);
    final shape = resolve((t) => t.dayShape) ?? const CircleBorder();
    final foreground = inside && !selected && enabled
        ? theme.colorScheme.onSecondaryContainer
        : resolve((t) => today ? t.todayForegroundColor : t.dayForegroundColor);
    final background = resolve(
      (t) => today ? t.todayBackgroundColor : t.dayBackgroundColor,
    );
    final decoration = selected
        ? ShapeDecoration(color: background, shape: shape)
        : today && !inside
        ? ShapeDecoration(
            shape: shape.copyWith(
              side: (picker.todayBorder ?? defaults.todayBorder!).copyWith(
                color: foreground,
              ),
            ),
          )
        : null;
    final dayText = labels.formatDecimal(day.day);
    var semantics = '$dayText, ${labels.formatFullDate(day)}';
    if (today) semantics += ', ${labels.currentDateLabel}';
    if (start) semantics = labels.dateRangeStartDateSemanticLabel(semantics);
    if (end) semantics = labels.dateRangeEndDateSemanticLabel(semantics);
    return MetaData(
      key: ValueKey<DateTime>(day),
      metaData: _RangeDay(day),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Semantics(
          label: semantics,
          hint: selected ? context.l10n.dragToAdjustDate : null,
          button: true,
          selected: selected,
          enabled: enabled,
          excludeSemantics: true,
          child: InkResponse(
            onTap: enabled ? () => _pick(day) : null,
            customBorder: shape,
            containedInkWell: true,
            overlayColor: picker.dayOverlayColor ?? defaults.dayOverlayColor,
            // 不能用 Ink:Ink 画在底下的 Material 上,会被这一行的色带盖住半边。
            child: Container(
              decoration: decoration,
              alignment: Alignment.center,
              child: Text(
                dayText,
                style: (picker.dayStyle ?? defaults.dayStyle)?.apply(
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final picker = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _actionsHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OverflowBar(
            spacing: 8,
            children: [
              TextButton(
                style: picker.cancelButtonStyle ?? defaults.cancelButtonStyle,
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                style: picker.confirmButtonStyle ?? defaults.confirmButtonStyle,
                onPressed: _end == null || _dragging
                    ? null
                    : () => Navigator.pop(
                        context,
                        DateTimeRange(start: _start, end: _end!),
                      ),
                child: Text(context.l10n.applyLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeDay {
  const _RangeDay(this.date);
  final DateTime date;
}

/// 每周一条连续色带,垫在端点圆后面。端点从格子中心起画;范围延续到
/// 上 / 下一周时画到弹窗边缘,月头月尾不满一周时停在最后一个日期格。
class _RangeBand extends CustomPainter {
  const _RangeBand({
    required this.from,
    required this.to,
    required this.openStart,
    required this.openEnd,
    required this.inset,
    required this.pad,
    required this.color,
    required this.direction,
  });
  final int from, to;
  final bool openStart, openEnd;
  final double inset, pad;
  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = (size.width - inset * 2) / 7;
    double x(double column) => inset + column * tile;
    final left = !openStart
        ? x(from + .5)
        : from == 0
        ? 0.0
        : x(from.toDouble());
    final right = !openEnd
        ? x(to + .5)
        : to == 6
        ? size.width
        : x(to + 1.0);
    // 色带与端点圆同高:圆的直径取格子较短边,色带高了接头处会比圆粗一圈。
    final height = math.min(tile, size.height) - pad * 2;
    final top = (size.height - height) / 2;
    final rtl = direction == TextDirection.rtl;
    canvas.drawRect(
      Rect.fromLTRB(
        rtl ? size.width - right : left,
        top,
        rtl ? size.width - left : right,
        top + height,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RangeBand old) =>
      old.from != from ||
      old.to != to ||
      old.openStart != openStart ||
      old.openEnd != openEnd ||
      old.inset != inset ||
      old.pad != pad ||
      old.color != color ||
      old.direction != direction;
}

/// 端点按下即接管指针,不让左右翻月的 PageView 抢走这一笔。
/// 识别器挂在整个日历上,端点随拖动换格、甚至翻到别的月时也不会丢失手势。
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
    // 普通日期不入场;额外手指也不能取消已经接管的端点指针。
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

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../gallery_date_filter.dart';
import 'gallery_range_picker.dart';

Widget _calendarLocale(BuildContext context, Widget? child) =>
    Localizations.override(
      context: context,
      locale: const Locale('zh', 'CN'),
      delegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: child,
    );

Future<GalleryDateFilter?> showGalleryDateFilter(
  BuildContext context,
  GalleryDateFilter current,
) async {
  final kind = await showModalBottomSheet<GalleryDateKind>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DateFilterSheet(current: current),
  );
  if (kind == null || !context.mounted) return null;
  if (kind != GalleryDateKind.day && kind != GalleryDateKind.range) {
    return GalleryDateFilter(kind);
  }
  final now = DateTime.now();
  final first = DateTime(1900), last = DateTime(now.year + 1, 12, 31);
  final initial =
      current.start != null &&
          !current.start!.isBefore(first) &&
          !current.start!.isAfter(last)
      ? current.start!
      : DateTime(now.year, now.month, now.day);
  if (kind == GalleryDateKind.day) {
    final day = await showDatePicker(
      context: context,
      builder: _calendarLocale,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '应用',
      fieldLabelText: '日期',
      fieldHintText: '年/月/日',
    );
    return day == null
        ? null
        : GalleryDateFilter(
            kind,
            start: DateTime(day.year, day.month, day.day),
          );
  }
  final end = current.end;
  final range = await showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _calendarLocale(
      context,
      GalleryRangePicker(
        firstDate: first,
        lastDate: last,
        initialRange: DateTimeRange(
          start: initial,
          end: end != null && !end.isBefore(initial) && !end.isAfter(last)
              ? end
              : initial,
        ),
      ),
    ),
  );
  return range == null
      ? null
      : GalleryDateFilter(kind, start: range.start, end: range.end);
}

class _DateFilterSheet extends StatelessWidget {
  const _DateFilterSheet({required this.current});

  final GalleryDateFilter current;

  String _date(DateTime value) => '${value.year}/${value.month}/${value.day}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.bodySmall!.copyWith(
      fontWeight: FontWeight.w600,
    );
    final start = current.start;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '按日期筛选',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // 与历史筛选胶囊同字号和高度；按文字宽度排布，窄屏自然换行。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, title) in const [
                  (GalleryDateKind.all, '全部'),
                  (GalleryDateKind.today, '今天'),
                  (GalleryDateKind.week, '近 7 天'),
                  (GalleryDateKind.month, '近 30 天'),
                ])
                  Semantics(
                    selected: current.kind == value,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: labelStyle,
                        backgroundColor: current.kind == value
                            ? scheme.secondaryContainer
                            : scheme.surfaceContainerHigh,
                        foregroundColor: current.kind == value
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.pop(context, value),
                      child: Text(title, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _CustomDateOption(
              title: '指定日期',
              subtitle: current.kind == GalleryDateKind.day && start != null
                  ? _date(start)
                  : '选择某一天',
              icon: Icons.event_outlined,
              selected: current.kind == GalleryDateKind.day,
              onTap: () => Navigator.pop(context, GalleryDateKind.day),
            ),
            const SizedBox(height: 10),
            _CustomDateOption(
              title: '日期范围',
              subtitle: current.kind == GalleryDateKind.range && start != null
                  ? '${_date(start)} 至 ${_date(current.end ?? start)}'
                  : '选择开始与结束日期',
              icon: Icons.date_range_outlined,
              selected: current.kind == GalleryDateKind.range,
              onTap: () => Navigator.pop(context, GalleryDateKind.range),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomDateOption extends StatelessWidget {
  const _CustomDateOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final radius = BorderRadius.circular(16);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium!.copyWith(
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected ? Icons.check_circle_outline : Icons.chevron_right,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

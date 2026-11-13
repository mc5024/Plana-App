import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../gallery_date_filter.dart';
import 'gallery_range_picker.dart';
import '../../../l10n/l10n.dart';

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
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      helpText: context.l10n.selectDate,
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.applyLabel,
      fieldLabelText: context.l10n.dateLabel,
      fieldHintText: context.l10n.dateFieldHint,
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
    builder: (context) => GalleryRangePicker(
      firstDate: first,
      lastDate: last,
      initialRange: DateTimeRange(
        start: initial,
        end: end != null && !end.isBefore(initial) && !end.isAfter(last)
            ? end
            : initial,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.filterByDate,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: current.active
                      ? () => Navigator.pop(context, GalleryDateKind.all)
                      : null,
                  child: Text(context.l10n.reset),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 与历史筛选胶囊同字号和高度；按文字宽度排布，窄屏自然换行。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, title) in [
                  (GalleryDateKind.all, context.l10n.all),
                  (GalleryDateKind.today, context.l10n.today),
                  (GalleryDateKind.week, context.l10n.last7Days),
                  (GalleryDateKind.month, context.l10n.last30Days),
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
                            ? context.selectedFill
                            : scheme.surfaceContainerHigh,
                        foregroundColor: current.kind == value
                            ? context.onSelectedFill
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
              title: context.l10n.specificDate,
              subtitle: current.kind == GalleryDateKind.day && start != null
                  ? _date(start)
                  : context.l10n.pickADay,
              icon: Icons.event_outlined,
              selected: current.kind == GalleryDateKind.day,
              onTap: () => Navigator.pop(context, GalleryDateKind.day),
            ),
            const SizedBox(height: 10),
            _CustomDateOption(
              title: context.l10n.dateRange,
              subtitle: current.kind == GalleryDateKind.range && start != null
                  ? context.l10n.dateRangeValue(
                      _date(start),
                      _date(current.end ?? start),
                    )
                  : context.l10n.pickStartEnd,
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
    final foreground = selected
        ? context.onSolidFill(scheme.onPrimaryContainer)
        : scheme.onSurface;
    final radius = BorderRadius.circular(16);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? context.solidFill(scheme.primaryContainer)
            : scheme.surfaceContainer,
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
                              ? context.onSolidFill(scheme.onPrimaryContainer)
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

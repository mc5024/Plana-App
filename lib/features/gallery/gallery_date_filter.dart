/// 日期只保存日历值；查询时才按当前设备时区构造边界。
enum GalleryDateKind { all, today, week, month, day, range }

class GalleryDateFilter {
  const GalleryDateFilter.all()
    : kind = GalleryDateKind.all,
      start = null,
      end = null;
  const GalleryDateFilter(this.kind, {this.start, this.end});

  final GalleryDateKind kind;
  final DateTime? start;
  final DateTime? end;
  bool get active => kind != GalleryDateKind.all;

  factory GalleryDateFilter.legacy(int days) =>
      GalleryDateFilter(switch (days) {
        1 => GalleryDateKind.today,
        7 => GalleryDateKind.week,
        30 => GalleryDateKind.month,
        _ => GalleryDateKind.all,
      });

  bool matches(int timestamp, DateTime now) {
    if (!active) return true;
    if (timestamp <= 0) return false;
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (kind) {
      GalleryDateKind.today => today,
      GalleryDateKind.week => now.subtract(const Duration(days: 7)),
      GalleryDateKind.month => now.subtract(const Duration(days: 30)),
      _ =>
        start == null ? null : DateTime(start!.year, start!.month, start!.day),
    };
    if (from == null) return false;
    if (timestamp < from.millisecondsSinceEpoch) return false;
    if (kind == GalleryDateKind.day || kind == GalleryDateKind.range) {
      final last = kind == GalleryDateKind.day ? from : (end ?? from);
      return timestamp <
          DateTime(last.year, last.month, last.day + 1).millisecondsSinceEpoch;
    }
    return true;
  }

  String label(DateTime now) {
    String date(DateTime? d) => d == null
        ? ''
        : '${d.year == now.year ? '' : '${d.year}/'}${d.month}/${d.day}';
    return switch (kind) {
      GalleryDateKind.all => '日期',
      GalleryDateKind.today => '今天',
      GalleryDateKind.week => '近 7 天',
      GalleryDateKind.month => '近 30 天',
      GalleryDateKind.day => date(start),
      GalleryDateKind.range => '${date(start)}–${date(end)}',
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (start != null) 'start': [start!.year, start!.month, start!.day],
    if (end != null) 'end': [end!.year, end!.month, end!.day],
  };

  static DateTime? _date(Object? value) {
    if (value is! List || value.length != 3 || !value.every((e) => e is int)) {
      return null;
    }
    final y = value[0] as int, m = value[1] as int, d = value[2] as int;
    if (y < 1 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final result = DateTime(y, m, d);
    return result.month == m && result.day == d ? result : null;
  }

  factory GalleryDateFilter.fromJson(Object? raw, {int legacyDays = 0}) {
    if (raw is! Map) return GalleryDateFilter.legacy(legacyDays);
    final kind = GalleryDateKind.values
        .where((k) => k.name == raw['kind'])
        .firstOrNull;
    if (kind == null) return GalleryDateFilter.legacy(legacyDays);
    final start = _date(raw['start']), end = _date(raw['end']);
    if ((kind == GalleryDateKind.day || kind == GalleryDateKind.range) &&
        start == null) {
      return const GalleryDateFilter.all();
    }
    if (kind == GalleryDateKind.range &&
        (end == null || end.isBefore(start!))) {
      return const GalleryDateFilter.all();
    }
    return GalleryDateFilter(kind, start: start, end: end);
  }
}

/// 日期只保存日历值；查询时才按当前设备时区构造边界。
library;

import '../../l10n/l10n.dart';

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

  /// 指定日期 / 日期范围(相对「今天」滚动的那几档之外)。
  bool get fixed =>
      kind == GalleryDateKind.day || kind == GalleryDateKind.range;

  /// 重启后恢复的筛选:相对日期照旧;指定日期只在本次运行内有效 ——
  /// 否则过几天再打开图库,之后生成的新图全被那天的日期挡在外面。
  GalleryDateFilter get restored =>
      fixed ? const GalleryDateFilter.all() : this;

  factory GalleryDateFilter.legacy(int days) =>
      GalleryDateFilter(switch (days) {
        1 => GalleryDateKind.today,
        7 => GalleryDateKind.week,
        30 => GalleryDateKind.month,
        _ => GalleryDateKind.all,
      });

  bool matches(int timestamp, DateTime now) => matcher(now)(timestamp);

  /// 按 [now] 先算好毫秒边界 [from, to),逐张只比两个整数。
  /// 构造本地时间的 DateTime 要查时区,几千张图每次重建都逐张算一遍会卡。
  bool Function(int timestamp) matcher(DateTime now) {
    if (!active) return (_) => true;
    int midnight(DateTime d, [int plusDays = 0]) =>
        DateTime(d.year, d.month, d.day + plusDays).millisecondsSinceEpoch;
    const open = 8640000000000000; // DateTime 能表示的最大毫秒数
    final start = this.start;
    final (from, to) = switch (kind) {
      GalleryDateKind.today => (midnight(now), open),
      GalleryDateKind.week => (
        now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
        open,
      ),
      GalleryDateKind.month => (
        now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
        open,
      ),
      GalleryDateKind.day when start != null => (
        midnight(start),
        midnight(start, 1),
      ),
      GalleryDateKind.range when start != null => (
        midnight(start),
        midnight(end ?? start, 1),
      ),
      _ => (0, 0),
    };
    return (t) => t > 0 && t >= from && t < to;
  }

  String label(DateTime now) {
    String date(DateTime? d) => d == null
        ? ''
        : '${d.year == now.year ? '' : '${d.year}/'}${d.month}/${d.day}';
    return switch (kind) {
      GalleryDateKind.all => l10nNow.dateLabel,
      GalleryDateKind.today => l10nNow.today,
      GalleryDateKind.week => l10nNow.last7Days,
      GalleryDateKind.month => l10nNow.last30Days,
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

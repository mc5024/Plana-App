/// 图库展开页的时间工具:按天分组键/段头文案 + 缩略图时刻徽标。
/// 纯函数无 IO,now 一律显式传入(可测,也免得跨日瞬间各处读到不同"今天")。
library;

import '../../l10n/l10n.dart';

/// 本地日 → 分组键(yyyymmdd 数值)。0/负时间戳归 0(「更早」段)。
int galleryDayKey(int createdAtMs) {
  if (createdAtMs <= 0) return 0;
  final d = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  return d.year * 10000 + d.month * 100 + d.day;
}

/// 段头文案:今天 / 昨天 / M月d日(今年)/ yyyy年M月d日(跨年);0 = 更早。
String galleryDayLabel(int dayKey, DateTime now) {
  final l = l10nNow;
  if (dayKey <= 0) return l.earlier;
  final today = now.year * 10000 + now.month * 100 + now.day;
  if (dayKey == today) return l.today;
  final y1 = now.subtract(const Duration(days: 1));
  if (dayKey == y1.year * 10000 + y1.month * 100 + y1.day) return l.yesterday;
  final y = dayKey ~/ 10000, m = (dayKey ~/ 100) % 100, d = dayKey % 100;
  return y == now.year ? l.dayMonthDay('$m', d) : l.dayYearMonthDay(y, '$m', d);
}

/// [ms] 那天到 [now] 那天隔了几个自然日(同一天为 0)。
int galleryDaysSince(int ms, DateTime now) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
}

/// 缩略图右下角时刻(HH:mm)。段头已给出日期,逐张再标日期是纯重复,
/// 标时刻才是段内的增量信息。无时间戳返回空串(不画)。
String galleryTimeBadge(int createdAtMs) {
  if (createdAtMs <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

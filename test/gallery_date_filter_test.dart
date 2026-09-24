import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/ui_prefs.dart';
import 'package:plana_app/features/gallery/gallery_date_filter.dart';

void main() {
  final now = DateTime(2026, 9, 21, 12);
  bool matches(GalleryDateFilter f, DateTime d) =>
      f.matches(d.millisecondsSinceEpoch, now);
  test('单日包含完整一天，排除前后两日和未知时间', () {
    final f = GalleryDateFilter(
      GalleryDateKind.day,
      start: DateTime(2026, 9, 9),
    );
    expect(matches(f, DateTime(2026, 9, 9)), isTrue);
    expect(matches(f, DateTime(2026, 9, 9, 23, 59, 59, 999)), isTrue);
    expect(matches(f, DateTime(2026, 9, 8, 23, 59, 59, 999)), isFalse);
    expect(matches(f, DateTime(2026, 9, 10)), isFalse);
    expect(f.matches(0, now), isFalse);
  });
  test('范围支持跨年、闰日和同日起止', () {
    for (final (start, end) in [
      (DateTime(2025, 12, 31), DateTime(2026, 1, 2)),
      (DateTime(2024, 2, 28), DateTime(2024, 2, 29)),
      (DateTime(2026, 9, 9), DateTime(2026, 9, 9)),
    ]) {
      final f = GalleryDateFilter(
        GalleryDateKind.range,
        start: start,
        end: end,
      );
      expect(matches(f, start), isTrue);
      expect(
        matches(f, DateTime(end.year, end.month, end.day, 23, 59, 59, 999)),
        isTrue,
      );
      expect(matches(f, DateTime(end.year, end.month, end.day + 1)), isFalse);
    }
  });
  test('保留近七天滚动窗口，今天按日历日', () {
    expect(
      matches(
        const GalleryDateFilter(GalleryDateKind.week),
        DateTime(2026, 9, 14, 11, 59),
      ),
      isFalse,
    );
    expect(
      matches(
        const GalleryDateFilter(GalleryDateKind.week),
        DateTime(2026, 9, 14, 12),
      ),
      isTrue,
    );
    expect(
      matches(
        const GalleryDateFilter(GalleryDateKind.today),
        DateTime(2026, 9, 21),
      ),
      isTrue,
    );
    expect(const GalleryDateFilter.all().matches(0, now), isTrue);
  });
  test('旧偏好迁移，新日期按年月日往返，坏值不破坏其他偏好', () {
    expect(
      UiPrefs.fromJson({'galleryDaysFilter': 7}).dateFilter.kind,
      GalleryDateKind.week,
    );
    final p = UiPrefs(
      galleryDateFilter: GalleryDateFilter(
        GalleryDateKind.range,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 9),
      ),
    );
    final back = UiPrefs.fromJson(p.toJson()).dateFilter;
    expect(back.start, DateTime(2026, 9, 1));
    expect(back.end, DateTime(2026, 9, 9));
    for (final raw in [
      {
        'kind': 'day',
        'start': [2026, 2, 30],
      },
      {
        'kind': 'range',
        'start': [2026, 9, 9],
        'end': [2026, 9, 1],
      },
      {'kind': 'day', 'start': 'bad'},
    ]) {
      final invalid = UiPrefs.fromJson({
        'galleryDateFilter': raw,
        'galleryColumns': 4,
      });
      expect(invalid.dateFilter.kind, GalleryDateKind.all);
      expect(invalid.galleryColumns, 4);
    }
  });
}

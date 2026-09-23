import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/widgets/gallery_range_picker.dart';

void main() {
  DateTimeRange? result;
  Future<void> mount(
    WidgetTester tester, {
    DateTime? start,
    DateTime? end,
    DateTime? first,
    DateTime? last,
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
  }) async {
    result = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<DateTimeRange>(
                  context: context,
                  builder: (_) => GalleryRangePicker(
                    initialRange: DateTimeRange(
                      start: start ?? DateTime(2026, 9, 3),
                      end: end ?? DateTime(2026, 9, 11),
                    ),
                    firstDate: first ?? DateTime(1900),
                    lastDate: last ?? DateTime(2027, 12, 31),
                    currentDate: DateTime(2026, 9, 21),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  Finder date(DateTime day) => find.byKey(ValueKey<DateTime>(day));
  Finder day(int n) => date(DateTime(2026, 9, n));
  Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
    final target = tester.getCenter(to);
    final gesture = await tester.startGesture(tester.getCenter(from));
    // 没有长按等待，第一笔移动就调整端点。
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.text('应用').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('直接纵向拖动终点，不滚动月份', (tester) async {
    await mount(tester);
    final before = tester.getTopLeft(day(3));
    await drag(tester, day(11), day(25));
    expect(tester.getTopLeft(day(3)), before);
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 25)),
    );
  });

  testWidgets('拖动起点保留另一端，越过另一端后交换起止', (tester) async {
    await mount(tester);
    await drag(tester, day(3), day(9));
    await drag(tester, day(9), day(16));
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 9, 11), end: DateTime(2026, 9, 16)),
    );
  });

  testWidgets('同一天范围可直接向前扩展', (tester) async {
    await mount(tester, start: DateTime(2026, 9, 11));
    await drag(tester, day(11), day(3));
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 11)),
    );
  });

  testWidgets('普通日期仍可滑动月份，点选仍可重新选择范围', (tester) async {
    await mount(tester);
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    await tester.drag(day(15), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(scroll.pixels, greaterThan(0));
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(day(5));
    await tester.pumpAndSettle();
    await tester.tap(day(13));
    await tester.pumpAndSettle();
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 9, 5), end: DateTime(2026, 9, 13)),
    );
  });

  testWidgets('拖动被取消时恢复原范围，关闭页面不应用草稿', (tester) async {
    await mount(tester);
    final gesture = await tester.startGesture(tester.getCenter(day(11)));
    await gesture.moveTo(tester.getCenter(day(20)));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 11)),
    );
    await mount(tester);
    await drag(tester, day(11), day(20));
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  for (final (start, end, target) in [
    (DateTime(2026, 9, 3), DateTime(2026, 9, 11), DateTime(2026, 10, 2)),
    (DateTime(2026, 12, 25), DateTime(2026, 12, 30), DateTime(2027, 1, 2)),
    (DateTime(2024, 2, 28), DateTime(2024, 2, 29), DateTime(2024, 3, 1)),
  ]) {
    testWidgets('拖动跨月、跨年与闰日：$end → $target', (tester) async {
      await mount(tester, start: start, end: end);
      await drag(tester, date(end), date(target));
      await apply(tester);
      expect(result, DateTimeRange(start: start, end: target));
    });
  }

  testWidgets('端点滚出屏幕后仍能拖动，边缘自动滚动并选中后续月份', (tester) async {
    await mount(tester);
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final gesture = await tester.startGesture(tester.getCenter(day(11)));
    await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 4));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(day(11).hitTestable(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    await apply(tester);
    expect(result!.start, DateTime(2026, 9, 3));
    expect(result!.end.isAfter(DateTime(2026, 10, 1)), isTrue);
  });

  testWidgets('起点可向前自动滚动到上个月', (tester) async {
    await mount(tester);
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final gesture = await tester.startGesture(tester.getCenter(day(3)));
    await gesture.moveTo(Offset(viewport.center.dx, viewport.top + 4));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await apply(tester);
    expect(result!.start.isBefore(DateTime(2026, 9, 1)), isTrue);
    expect(result!.end, DateTime(2026, 9, 11));
  });

  testWidgets('拖动中关闭页面不会遗留滚动或提交日期', (tester) async {
    await mount(tester);
    final gesture = await tester.startGesture(tester.getCenter(day(11)));
    await gesture.moveTo(tester.getCenter(day(20)));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('额外手指轻触不会中断端点拖动', (tester) async {
    await mount(tester);
    final drag = await tester.startGesture(
      tester.getCenter(day(11)),
      pointer: 1,
    );
    await drag.moveTo(tester.getCenter(day(18)));
    await tester.pump();
    final other = await tester.startGesture(
      tester.getCenter(day(9)),
      pointer: 2,
    );
    await other.up();
    await tester.pump();
    await drag.moveTo(tester.getCenter(day(25)));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 25)),
    );
  });

  testWidgets('拖到范围之外的禁用日期不会选中', (tester) async {
    await mount(
      tester,
      first: DateTime(2026, 9, 1),
      last: DateTime(2026, 9, 20),
    );
    await drag(tester, day(11), day(30));
    await apply(tester);
    expect(result!.end, DateTime(2026, 9, 11));
  });

  testWidgets('手输日期保持中文，返回日历保留拖动结果，应用只需一次', (tester) async {
    await mount(tester);
    await drag(tester, day(11), day(20));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回日历'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(
      Localizations.localeOf(
        tester.element(find.byType(DateRangePickerDialog)),
      ).languageCode,
      'zh',
    );
    await tester.enterText(find.byType(TextField).first, '2026/10/01');
    await tester.enterText(find.byType(TextField).last, '2026/10/04');
    await apply(tester);
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 4)),
    );
  });

  for (final (size, scale, dark) in [
    (const Size(320, 640), 1.5, true),
    (const Size(844, 390), 1.0, false),
  ]) {
    testWidgets('拖动日历适应窄屏大字体和横屏：$size', (tester) async {
      await mount(tester, size: size, scale: scale, dark: dark);
      expect(tester.takeException(), isNull);
      await apply(tester);
      expect(result!.end, DateTime(2026, 9, 11));
    });
  }
}

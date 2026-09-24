import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/ui_prefs.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/gallery_date_filter.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/gallery/widgets/gallery_grid_sheet.dart';
import 'package:plana_app/features/gallery/widgets/gallery_range_picker.dart';
import 'package:plana_app/features/gallery/widgets/result_thumb.dart';

void main() {
  testWidgets('现有图库按日期筛选后只显示匹配作品，选全部可恢复', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stores = AppStores.ephemeral();
    final bytes = File('assets/app_icon.png').readAsBytesSync();
    final now = DateTime.now();
    final old = DateTime(now.year, now.month, now.day - 2);
    stores.gallery.initialResults = [
      ResultImage(
        id: 'gen2',
        width: 64,
        height: 64,
        seed: 2,
        createdAt: now.millisecondsSinceEpoch,
        bytes: bytes,
      ),
      ResultImage(
        id: 'gen1',
        width: 64,
        height: 64,
        seed: 1,
        createdAt: old.millisecondsSinceEpoch,
        bytes: bytes,
      ),
    ];
    await tester.runAsync(
      () => stores.prefs.write(key: 'hint_grid_longpress', value: '1'),
    );
    final container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultThumb), findsNWidgets(2));
    expect(find.text('按时间'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').last);
    await tester.pumpAndSettle();
    expect(find.byType(ResultThumb), findsOneWidget);
    expect(
      container.read(uiPrefsProvider).dateFilter.kind,
      GalleryDateKind.today,
    );
    expect(find.text('按时间'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultThumb), findsNWidgets(2));
    expect(
      container.read(uiPrefsProvider).dateFilter.kind,
      GalleryDateKind.all,
    );

    await tester.tap(find.byKey(const ValueKey('gallery-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日期范围'));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryRangePicker), findsOneWidget);
    await tester.tap(find.text('应用').last);
    await tester.pumpAndSettle();
    expect(find.byType(ResultThumb), findsOneWidget);
    expect(
      container.read(uiPrefsProvider).dateFilter.kind,
      GalleryDateKind.range,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期筛选保留现有图库的分组设置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stores = AppStores.ephemeral();
    final container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(container.dispose);
    container
        .read(uiPrefsProvider.notifier)
        .patch((p) => p.copyWith(galleryGroupBy: 'style'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('按画风'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gallery-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近 7 天'));
    await tester.pumpAndSettle();
    expect(container.read(uiPrefsProvider).galleryGroupBy, 'style');
    expect(find.text('按画风'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

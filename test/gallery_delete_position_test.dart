import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/gallery_page.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/gallery/widgets/film_strip.dart';
import 'package:plana_app/features/gallery/widgets/result_canvas.dart';
import 'package:plana_app/features/gallery/widgets/result_thumb.dart';

void main() {
  testWidgets('删除图库图片后预览页和胶片条保持在相邻作品', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stores = AppStores.ephemeral();
    final container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(container.dispose);
    final gallery = container.read(galleryProvider.notifier);
    final bytes = File('assets/app_icon.png').readAsBytesSync();
    final ids = [
      for (var i = 0; i < 4; i++)
        gallery.addResult(bytes: bytes, width: 64, height: 64, seed: i).id,
    ];
    gallery.select(ids[2]);
    await tester.runAsync(() async {
      await stores.prefs.write(key: 'hint_save_longpress', value: '1');
      await stores.prefs.write(key: 'hint_strip_swipe', value: '1');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: GalleryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    void expectSelection(String id) {
      expect(container.read(galleryProvider).selectedId, id);
      expect(
        tester.widget<ResultChrome>(find.byType(ResultChrome)).result.id,
        id,
      );
      expect(tester.widget<FilmStrip>(find.byType(FilmStrip)).selectedId, id);
      final page = tester.widget<PageView>(find.byType(PageView));
      final index = container
          .read(galleryProvider)
          .results
          .indexWhere((r) => r.id == id);
      expect(page.controller?.page?.round(), index);
      expect(tester.takeException(), isNull);
    }

    expectSelection(ids[2]);
    tester.widget<FilmStrip>(find.byType(FilmStrip)).onDelete(ids[2]);
    await tester.pumpAndSettle();
    expectSelection(ids[1]); // 中间图片被删，停在相邻的旧图。

    tester.widget<FilmStrip>(find.byType(FilmStrip)).onDelete(ids[3]);
    await tester.pumpAndSettle();
    expectSelection(ids[1]); // 删除前面的其他图片，当前预览不变。

    tester.widget<FilmStrip>(find.byType(FilmStrip)).onSelect(ids[0]);
    await tester.pumpAndSettle();
    expectSelection(ids[0]);
    tester.widget<FilmStrip>(find.byType(FilmStrip)).onDelete(ids[0]);
    await tester.pumpAndSettle();
    expectSelection(ids[1]); // 最后一张被删，停在上一张。

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('删除图片后胶片条不滚回选中项', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stores = AppStores.ephemeral();
    final container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(container.dispose);
    final gallery = container.read(galleryProvider.notifier);
    final bytes = File('assets/app_icon.png').readAsBytesSync();
    final ids = [
      for (var i = 0; i < 16; i++)
        gallery.addResult(bytes: bytes, width: 64, height: 64, seed: i).id,
    ];
    gallery.select(ids.last);
    await tester.runAsync(() async {
      await stores.prefs.write(key: 'hint_save_longpress', value: '1');
      await stores.prefs.write(key: 'hint_strip_swipe', value: '1');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: GalleryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byType(FilmStrip);
    final list = find.descendant(
      of: strip,
      matching: find.byType(CustomScrollView),
    );
    final scroll = tester.widget<CustomScrollView>(list).controller!;
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(500, 1));

    tester.widget<FilmStrip>(strip).onDelete(ids[5]);
    await tester.pumpAndSettle();
    expect(container.read(galleryProvider).selectedId, ids.last);
    expect(scroll.offset, closeTo(500, 1));

    // 删的是视野左边那张:少了一格(88),视野里的图原地不动
    tester.widget<FilmStrip>(strip).onDelete(ids.last);
    await tester.pumpAndSettle();
    expect(container.read(galleryProvider).selectedId, ids[14]);
    expect(scroll.offset, closeTo(500 - _slot, 1));

    tester.widget<FilmStrip>(strip).onSelect(ids.first);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(500)); // 主动选图仍会定位到选中项。

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('新图插到头部:滚开时视野不动,停在最左头时新图滑进来', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stores = AppStores.ephemeral();
    final container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(container.dispose);
    final gallery = container.read(galleryProvider.notifier);
    final bytes = File('assets/app_icon.png').readAsBytesSync();
    final ids = [
      for (var i = 0; i < 16; i++)
        gallery.addResult(bytes: bytes, width: 64, height: 64, seed: i).id,
    ];
    gallery.select(ids[8]);
    await tester.runAsync(() async {
      await stores.prefs.write(key: 'hint_save_longpress', value: '1');
      await stores.prefs.write(key: 'hint_strip_swipe', value: '1');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: GalleryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byType(FilmStrip);
    final list = find.descendant(
      of: strip,
      matching: find.byType(CustomScrollView),
    );
    final scroll = tester.widget<CustomScrollView>(list).controller!;
    scroll.jumpTo(500);
    await tester.pumpAndSettle();

    gallery.addResult(
      bytes: bytes,
      width: 64,
      height: 64,
      seed: 99,
      select: false,
    );
    await tester.pump();
    expect(scroll.offset, closeTo(500 + _slot, 1));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(500 + _slot, 1));

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final head = find.descendant(
      of: strip,
      matching: find.byWidgetPredicate(
        (w) => w is ResultThumb && w.result.id == ids.last,
      ),
    );
    final x0 = tester.getTopLeft(head).dx;
    gallery.addResult(
      bytes: bytes,
      width: 64,
      height: 64,
      seed: 100,
      select: false,
    );
    await tester.pump();
    // 新图从 0 宽长起:这一帧原来打头那张还没动,之后被推开一格
    expect(scroll.offset, 0);
    expect(tester.getTopLeft(head).dx, closeTo(x0, 1));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(tester.getTopLeft(head).dx, closeTo(x0 + _slot, 1));

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

/// 方图在胶片条上的一格:图宽 72 + 内衬与边框 8 + 分隔 8。
const _slot = 88.0;

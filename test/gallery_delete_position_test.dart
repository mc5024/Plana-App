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
}

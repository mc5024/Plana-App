import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/ui_prefs.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/features/gallery/albums/album_state.dart';
import 'package:plana_app/features/gallery/albums/album_ui.dart';
import 'package:plana_app/features/gallery/albums/import_album_options.dart';
import 'package:plana_app/features/gallery/gallery_date_filter.dart';
import 'package:plana_app/features/gallery/gallery_groups.dart';
import 'package:plana_app/features/gallery/gallery_page.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/gallery/widgets/gallery_date_sheet.dart';
import 'package:plana_app/features/gallery/widgets/gallery_grid_sheet.dart';
import 'package:plana_app/features/gallery/widgets/film_strip.dart';
import 'package:plana_app/features/gallery/widgets/result_canvas.dart';
import 'package:plana_app/features/gallery/widgets/result_thumb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['PLANA_UI_FONT'];
  setUpAll(() async {
    if (fontPath != null) {
      final loader = FontLoader('GalleryUiPreview')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await loader.load();
      final iconPath = Platform.environment['PLANA_ICON_FONT'];
      if (iconPath != null) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(File(iconPath).readAsBytes().then(ByteData.sublistView));
        await icons.load();
      }
    }
  });
  late AppStores stores;
  late ProviderContainer c;
  late String albumId, imageId;
  final capture = GlobalKey();
  setUp(() async {
    stores = AppStores.ephemeral();
    c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    for (final key in [
      'hint_grid_longpress',
      'hint_save_longpress',
      'hint_strip_swipe',
    ]) {
      await stores.prefs.write(key: key, value: '1');
    }
    albumId = await c.read(albumsProvider.notifier).create('表情包');
    final bytes = await File('assets/app_icon.png').readAsBytes();
    imageId =
        (await c
                .read(galleryProvider.notifier)
                .addResultToGallery(
                  bytes: bytes,
                  width: 256,
                  height: 256,
                  seed: 123,
                  target: GallerySaveTarget.album(albumId),
                ))
            .id;
  });
  tearDown(() async {
    stores.flushNow();
    await stores.gallery.idle;
    await stores.albums.idle;
    c.dispose();
  });

  Widget app(Widget body, {double scale = 1, bool dark = false}) =>
      UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: (dark ? AppTheme.dark() : AppTheme.light()).copyWith(
              textTheme: (dark ? AppTheme.dark() : AppTheme.light()).textTheme
                  .apply(
                    fontFamily: fontPath == null ? null : 'GalleryUiPreview',
                  ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: body),
          ),
        ),
      );

  Future<void> screenshot(WidgetTester tester, String name) async {
    final directory = Platform.environment['PLANA_CAPTURE_UI'];
    if (directory == null) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('图库卡片预览不切换，勾选一起切换后才修改保存位置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAlbumLibrary(context),
            child: const Text('打开图库'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开图库'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'album-selector');
    await tester.tap(find.byType(AlbumCoverImage).last);
    await tester.pumpAndSettle();
    expect(c.read(galleryBrowseAlbumProvider), isNull);
    expect(c.read(gallerySaveTargetProvider).albumId, isNull);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('新图也保存到这里'));
    await tester.tap(find.text('加载图库'));
    await tester.pumpAndSettle();
    expect(c.read(galleryBrowseAlbumProvider), albumId);
    expect(c.read(gallerySaveTargetProvider).albumId, albumId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入选项默认关闭，勾选与取消只修改草稿', (tester) async {
    var choice = const ImportAlbumChoice();
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => ListView(
            children: [
              ImportAlbumOptions(
                origin: GalleryImportOrigin(imageId: imageId),
                choice: choice,
                onChanged: (v) => setState(() => choice = v),
              ),
            ],
          ),
        ),
      ),
    );
    expect(choice.enabled, isFalse);
    await tester.tap(find.text('切换到图片所属图库'));
    await tester.pumpAndSettle();
    expect(choice.enabled, isTrue);
    expect(choice.target!.albumId, albumId);
    expect(choice.alsoSave, isFalse);
    expect(c.read(galleryBrowseAlbumProvider), isNull);
    await tester.tap(find.text('新图也保存到该图库'));
    await tester.tap(find.text('切换到图片所属图库'));
    await tester.pumpAndSettle();
    expect(choice.enabled, isFalse);
    expect(choice.target, isNull);
    expect(choice.alsoSave, isFalse);
    expect(c.read(gallerySaveTargetProvider).albumId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期筛选取消日历不会应用新条件', (tester) async {
    GalleryDateFilter? picked;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showGalleryDateFilter(
                context,
                const GalleryDateFilter(GalleryDateKind.week),
              );
            },
            child: const Text('筛选'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定日期'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('日历使用中文且年月日输入能正确应用', (tester) async {
    GalleryDateFilter? picked;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showGalleryDateFilter(
                context,
                const GalleryDateFilter.all(),
              );
            },
            child: const Text('筛选'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定日期'));
    await tester.pumpAndSettle();
    final dialog = tester.element(find.byType(DatePickerDialog));
    expect(Localizations.localeOf(dialog).languageCode, 'zh');
    final labels = MaterialLocalizations.of(dialog);
    await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2026/09/09');
    await screenshot(tester, 'date-input');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(picked?.start, DateTime(2026, 9, 9));
  });

  testWidgets('日期范围完整恢复起止日，应用后保留结束日', (tester) async {
    GalleryDateFilter? picked;
    final current = GalleryDateFilter(
      GalleryDateKind.range,
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 9),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showGalleryDateFilter(context, current);
            },
            child: const Text('筛选'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日期范围'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'date-range');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(picked?.start, current.start);
    expect(picked?.end, current.end);
  });

  testWidgets('日期入口恢复按天分组，取消日历不改变当前分组', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('打开历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分组'));
    await tester.pumpAndSettle();
    expect(find.text('按时间'), findsNothing);
    await tester.tap(find.text('按角色'));
    await tester.pumpAndSettle();
    expect(
      c.read(uiPrefsProvider).galleryGroupBy,
      GalleryGroupBy.character.name,
    );

    await tester.tap(find.text('日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      c.read(uiPrefsProvider).galleryGroupBy,
      GalleryGroupBy.character.name,
    );
    expect(c.read(uiPrefsProvider).dateFilter.active, isFalse);

    await tester.tap(find.text('日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近 7 天'));
    await tester.pumpAndSettle();
    expect(c.read(uiPrefsProvider).galleryGroupBy, GalleryGroupBy.day.name);
    expect(c.read(uiPrefsProvider).dateFilter.kind, GalleryDateKind.week);
    expect(find.text('分组'), findsOneWidget);

    await tester.tap(find.text('分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按画风'));
    await tester.pumpAndSettle();
    expect(c.read(uiPrefsProvider).galleryGroupBy, GalleryGroupBy.style.name);
    expect(c.read(uiPrefsProvider).dateFilter.kind, GalleryDateKind.week);
    await tester.tap(find.text('近 7 天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(c.read(uiPrefsProvider).galleryGroupBy, GalleryGroupBy.day.name);
    expect(c.read(uiPrefsProvider).dateFilter.active, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final (size, scale, name) in [
    (const Size(320, 640), 1.5, 'album-narrow'),
    (const Size(844, 390), 1.0, 'album-landscape'),
  ]) {
    testWidgets('长图库名与预览布局：$name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => c
            .read(albumsProvider.notifier)
            .rename(albumId, '很长的图库名称用于检查文字省略和按钮布局'),
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAlbumLibrary(context),
              child: const Text('打开图库'),
            ),
          ),
          scale: scale,
        ),
      );
      await tester.tap(find.text('打开图库'));
      await tester.pumpAndSettle();
      await screenshot(tester, name);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(AlbumCoverImage).last);
      await tester.pumpAndSettle();
      expect(find.text('加载图库'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('历史弹层中移动后的撤销可点击并恢复归属', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final albums = c.read(albumsProvider.notifier);
    final target = await tester.runAsync(() => albums.create('移动目标'));
    albums.browse(albumId);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('打开历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResultThumb));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动目标'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('移动 (1)').last);
      await stores.albums.idle;
    });
    await tester.pumpAndSettle();
    expect(c.read(albumsProvider).ofImage(imageId), {target});
    // 只找到文字还不够：SnackBar 在 modal route 下时存在但无法点到。
    expect(find.text('撤销').hitTestable(), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('撤销').hitTestable());
      await stores.albums.idle;
    });
    await tester.pumpAndSettle();
    expect(c.read(albumsProvider).ofImage(imageId), {albumId});
    expect(find.byType(ResultThumb), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final scoped in [false, true]) {
    testWidgets('${scoped ? '指定图库' : '全部作品'}上滑删除保持相邻预览及胶片条选中', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gallery = c.read(galleryProvider.notifier);
      final albums = c.read(albumsProvider.notifier);
      final bytes = c.read(galleryProvider).selected!.bytes!;
      final ids = [imageId];
      await tester.runAsync(() async {
        final other = await albums.create('其他图库');
        for (var seed = 1; seed < 4; seed++) {
          ids.add(
            (await gallery.addResultToGallery(
              bytes: bytes,
              width: 256,
              height: 256,
              seed: seed,
              target: GallerySaveTarget.album(albumId),
            )).id,
          );
          if (scoped) {
            await gallery.addResultToGallery(
              bytes: bytes,
              width: 256,
              height: 256,
              seed: seed + 10,
              target: GallerySaveTarget.album(other),
            );
          }
        }
        albums.setSave(other);
        albums.browse(scoped ? albumId : null);
        gallery.select(ids[2]);
        await tester.pumpWidget(app(const GalleryPage()));
        await tester.pumpAndSettle();

        Future<void> swipeDelete(String id, String expected) async {
          final thumb = find.byWidgetPredicate(
            (widget) => widget is Draggable<String> && widget.data == id,
          );
          final start = tester.getCenter(thumb);
          final gesture = await tester.startGesture(start);
          await gesture.moveBy(const Offset(0, -40));
          await tester.pumpAndSettle();
          final target = tester.getCenter(find.text('拖到这里删除'));
          await gesture.moveTo(Offset(start.dx, target.dy));
          await tester.pumpAndSettle();
          expect(find.text('松手删除'), findsOneWidget);
          await gesture.up();
          await stores.gallery.idle;
          await stores.albums.idle;
          await tester.pumpAndSettle();
          expect(c.read(galleryViewProvider).selectedId, expected);
          expect(
            tester.widget<ResultChrome>(find.byType(ResultChrome)).result.id,
            expected,
          );
          expect(
            tester.widget<FilmStrip>(find.byType(FilmStrip)).selectedId,
            expected,
          );
          expect(
            c.read(galleryProvider).results.any((r) => r.id == id),
            isFalse,
          );
          expect(tester.takeException(), isNull);
        }

        await swipeDelete(ids[2], ids[1]); // 中间图片 → 下一张。
        await swipeDelete(ids[3], ids[1]); // 删除前面的其他图片 → 预览不动。
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is Draggable<String> && widget.data == ids[0],
          ),
        );
        await tester.pumpAndSettle();
        await swipeDelete(ids[0], ids[1]); // 最后一张 → 上一张。
        expect(c.read(galleryBrowseAlbumProvider), scoped ? albumId : null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    });
  }

  for (final scope in ['所有照片', '保存目标图库', '其他图库']) {
    testWidgets('浏览$scope时连续新图入库不会被自动翻页改回旧图', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final albums = c.read(albumsProvider.notifier);
      final gallery = c.read(galleryProvider.notifier);
      final target = scope == '其他图库'
          ? (await tester.runAsync(() => albums.create('新图目标')))!
          : albumId;
      albums.setSave(target);
      if (scope != '所有照片') albums.browse(albumId);
      final bytes = c.read(galleryProvider).selected!.bytes!;
      await tester.pumpWidget(app(const GalleryPage()));
      await tester.pumpAndSettle();
      for (final seed in [456, 789]) {
        final saved = (await tester.runAsync(() async {
          final pending = gallery.addResultToGallery(
            bytes: bytes,
            width: 256,
            height: 256,
            seed: seed,
            target: GallerySaveTarget.album(target),
          );
          // 让入库期间的布局和页码同步实际执行，覆盖异步保存与翻页的竞争。
          await tester.pumpAndSettle();
          return await pending;
        }))!;
        await tester.pumpAndSettle();
        expect(c.read(albumsProvider).ofImage(saved.id), {target});
        expect(
          c.read(galleryBrowseAlbumProvider),
          scope == '所有照片' ? null : albumId,
        );
        expect(c.read(gallerySaveTargetProvider).albumId, target);
        expect(
          tester.widget<ResultChrome>(find.byType(ResultChrome)).result.id,
          saved.id,
        );
        if (scope == '其他图库') {
          expect(c.read(galleryResultPreviewProvider)?.imageId, saved.id);
          expect(c.read(galleryViewProvider).selectedId, imageId);
        } else {
          expect(c.read(galleryViewProvider).selectedId, saved.id);
          expect(
            tester.widget<FilmStrip>(find.byType(FilmStrip)).selectedId,
            saved.id,
          );
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('新图落盘期间手动翻图，完成后保留用户选择', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gallery = c.read(galleryProvider.notifier);
    final bytes = c.read(galleryProvider).selected!.bytes!;
    await tester.runAsync(
      () => gallery.addResultToGallery(
        bytes: bytes,
        width: 256,
        height: 256,
        seed: 456,
        target: GallerySaveTarget.album(albumId),
      ),
    );
    await tester.pumpWidget(app(const GalleryPage()));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final pending = gallery.addResultToGallery(
        bytes: bytes,
        width: 256,
        height: 256,
        seed: 789,
        target: GallerySaveTarget.album(albumId),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-390, 0));
      await tester.pumpAndSettle();
      expect(c.read(galleryViewProvider).selectedId, imageId);
      await pending;
    });
    await tester.pumpAndSettle();
    expect(c.read(galleryViewProvider).selectedId, imageId);
    expect(
      tester.widget<ResultChrome>(find.byType(ResultChrome)).result.id,
      imageId,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('图库胶囊分别切换浏览范围与新图保存位置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(app(const GalleryPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('浏览图库：全部作品'));
      await tester.pumpAndSettle();
      expect(find.text('选择图库'), findsOneWidget);
      await tester.tap(find.byType(AlbumCoverImage).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载图库'));
      await tester.pumpAndSettle();
      expect(c.read(galleryBrowseAlbumProvider), albumId);
      expect(c.read(gallerySaveTargetProvider).albumId, isNull);

      await tester.tap(find.byTooltip('新图保存到：全部作品'));
      await tester.pumpAndSettle();
      expect(find.text('新图保存到'), findsOneWidget);
      await tester.tap(find.byType(AlbumCoverImage).last);
      await tester.pumpAndSettle();
      expect(find.text('新图也保存到这里'), findsNothing);
      await tester.tap(find.text('新图保存到这里'));
      await tester.pumpAndSettle();
      expect(c.read(galleryBrowseAlbumProvider), albumId);
      expect(c.read(gallerySaveTargetProvider).albumId, albumId);

      await tester.tap(find.byTooltip('浏览图库：表情包'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AlbumCoverImage).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载图库'));
      await tester.pumpAndSettle();
      expect(c.read(galleryBrowseAlbumProvider), isNull);
      expect(c.read(gallerySaveTargetProvider).albumId, albumId);
      expect(find.bySemanticsLabel('浏览图库：全部作品'), findsOneWidget);
      expect(find.bySemanticsLabel('新图保存到：表情包'), findsOneWidget);
      await screenshot(tester, 'gallery-context-pills');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('窄屏大字体图库和历史操作栏无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longName = '表情包与日常灵感收藏的长图库名称';
    await tester.runAsync(() async {
      final albums = c.read(albumsProvider.notifier);
      await albums.rename(albumId, longName);
      albums.browse(albumId, alsoSave: true);
    });
    await tester.pumpWidget(app(const GalleryPage(), scale: 1.5, dark: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('浏览图库：$longName'), findsOneWidget);
    expect(find.byTooltip('新图保存到：$longName'), findsOneWidget);
    await screenshot(tester, 'gallery-dark-narrow');
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => stores.prefs.write(key: 'hint_grid_longpress', value: '1'),
    );
    final context = tester.element(find.byType(GalleryPage));
    unawaited(showGalleryGrid(context));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'history-dark-multiselect');
    expect(find.text('移动 (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/core/store/ui_prefs.dart';
import 'package:plana_app/features/gallery/albums/album_state.dart';
import 'package:plana_app/features/gallery/albums/album_ui.dart';
import 'package:plana_app/features/gallery/gallery_page.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/gallery/widgets/film_strip.dart';
import 'package:plana_app/features/gallery/widgets/gallery_grid_sheet.dart';
import 'package:plana_app/features/gallery/widgets/result_thumb.dart';
import 'package:plana_app/features/gallery/widgets/stack_card.dart';

void main() {
  late AppStores stores;
  late ProviderContainer container;
  late String albumId;

  setUp(() async {
    stores = AppStores.ephemeral();
    final bytes = File('assets/app_icon.png').readAsBytesSync();
    stores.gallery.initialResults = [
      for (var i = 0; i < 3; i++)
        ResultImage(
          id: 'gen$i',
          width: 64,
          height: 64,
          seed: i,
          createdAt: DateTime.now().millisecondsSinceEpoch - i * 1000,
          bytes: bytes,
        ),
    ];
    // 同真实加载:发号器续在最大 id 之后,新图不跟预置的 gen0 撞号。
    stores.gallery.seq = 3;
    for (final key in [
      'hint_grid_longpress',
      'hint_save_longpress',
      'hint_strip_swipe',
    ]) {
      await stores.prefs.write(key: key, value: '1');
    }
    container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    albumId = await container.read(albumsProvider.notifier).create('旅行');
    await container.read(albumsProvider.notifier).organize({'gen1'}, {albumId});
  });
  tearDown(() {
    container.dispose();
  });

  Widget app(Widget body) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: body),
    ),
  );

  testWidgets('相册卡片可以设置新图保存相册并切换主页胶片条', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Column(
          children: [
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
            ),
            const Expanded(child: GalleryPage()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilmStrip>(find.byType(FilmStrip)).results,
      hasLength(3),
    );

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);
    await tester.longPress(find.text('旅行'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为保存相册'));
    await tester.pumpAndSettle();
    expect(container.read(gallerySaveTargetProvider).albumId, albumId);
    expect(container.read(galleryBrowseAlbumProvider), albumId);
    // 相册平铺封面,叠影只留给按角色 / 画风分的堆。
    expect(
      tester
          .widgetList<GalleryStackCard>(find.byType(GalleryStackCard))
          .map((c) => c.stacked),
      everyElement(isFalse),
    );

    // 封面角上的收件箱只是标记:点在上面照常进相册。
    await tester.tap(find.byIcon(Icons.move_to_inbox));
    await tester.pumpAndSettle();
    expect(find.byTooltip('回到相册'), findsOneWidget);
    expect(find.text('1 张'), findsWidgets);
    await tester.tap(find.byTooltip('回到相册'));
    await tester.pumpAndSettle();

    await tester.drag(find.text('相册'), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilmStrip>(find.byType(FilmStrip)).results.single.id,
      'gen1',
    );
    expect(find.text('保存到 旅行'), findsOneWidget);
    await tester.tap(find.text('保存到 旅行'));
    await tester.pumpAndSettle();
    expect(find.text('保存到'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-album-choice-all')));
    await tester.pumpAndSettle();
    expect(container.read(gallerySaveTargetProvider).albumId, isNull);
    expect(container.read(galleryBrowseAlbumProvider), isNull);
    expect(
      tester.widget<FilmStrip>(find.byType(FilmStrip)).results,
      hasLength(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按相册卡设保存相册、改名和删除，保存相册封面角上有标记', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('设为保存相册'), findsNothing);
    // 卡上不放开关;新图默认存全部相册,只有它的封面角上有收件箱标记。
    expect(find.byIcon(Icons.move_to_inbox_outlined), findsNothing);
    Finder saveTag(String album) => find.descendant(
      of: find.ancestor(
        of: find.text(album),
        matching: find.byType(GalleryStackCard),
      ),
      matching: find.byIcon(Icons.move_to_inbox),
    );
    expect(find.byIcon(Icons.move_to_inbox), findsOneWidget);
    expect(saveTag('全部相册'), findsOneWidget);

    Future<void> longPress(String name) async {
      await tester.longPress(find.text(name));
      // 抬起前最多等 300ms 预读原图,测试里读不出来就按超时走。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    // 保存相册只在长按菜单里设。
    final card = tester.getRect(
      find
          .ancestor(of: find.text('旅行'), matching: find.byType(GestureDetector))
          .first,
    );
    await longPress('旅行');
    // 封面抬起成方框、留在按住的这张卡上,菜单左缘与它对齐(靠右那列的卡
    // 菜单放不下,贴着屏幕右边距)。
    final frame = tester.getRect(find.byKey(const ValueKey('lift-frame')));
    expect(frame.width, moreOrLessEquals(frame.height));
    expect(frame.width, lessThanOrEqualTo(card.width * 1.4));
    expect((frame.center.dx - card.center.dx).abs(), lessThan(card.width / 4));
    expect(
      tester
          .getRect(
            find
                .ancestor(of: find.text('重命名'), matching: find.byType(Material))
                .first,
          )
          .left,
      moreOrLessEquals(frame.left.clamp(16.0, 390 - 200 - 16.0).toDouble()),
    );
    expect(find.text('设为保存相册'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除相册'), findsOneWidget);
    await tester.tap(find.text('设为保存相册'));
    await tester.pumpAndSettle();
    expect(container.read(gallerySaveTargetProvider).albumId, albumId);
    expect(saveTag('旅行'), findsOneWidget);
    expect(saveTag('全部相册'), findsNothing);
    await longPress('旅行');
    expect(find.text('设为保存相册'), findsNothing);
    await tester.tapAt(const Offset(8, 8)); // 点遮罩收起菜单
    await tester.pumpAndSettle();

    // 全部相册只有这一项,没有改名和删除。
    await longPress('全部相册');
    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除相册'), findsNothing);
    await tester.tap(find.text('设为保存相册'));
    await tester.pumpAndSettle();
    expect(container.read(gallerySaveTargetProvider).albumId, isNull);

    await longPress('旅行');
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '出游');
    await tester.runAsync(() async {
      await tester.tap(find.text('保存').last);
      await stores.albums.idle;
    });
    await tester.pumpAndSettle();
    expect(container.read(albumsProvider).name(albumId), '出游');

    await longPress('出游');
    await tester.tap(find.text('删除相册'));
    await tester.pumpAndSettle();
    expect(find.text('删除「出游」？'), findsOneWidget);
    await tester.tap(find.text('删除相册').last);
    // 删除在确认框关掉后的回调里发起:真实时间让文件写完,pump 推进回调,
    // 两边交替到删除落盘为止。
    for (
      var i = 0;
      i < 50 && container.read(albumsProvider).exists(albumId);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(container.read(albumsProvider).exists(albumId), isFalse);
    expect(find.text('出游'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('相册页的返回箭头与相册首页标题左对齐', (tester) async {
    tester.view.physicalSize = const Size(369, 821);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    final titleLeft = tester.getTopLeft(find.text('相册')).dx;
    await tester.tap(find.text('全部相册'));
    await tester.pumpAndSettle();
    final arrow = tester.getRect(find.byIcon(Icons.arrow_back));
    // arrow_back 的图形在 24 格里从 4 起笔。
    expect(arrow.left + arrow.width * 4 / 24, moreOrLessEquals(titleLeft));
    // 回到首页再结束:面板会记住关闭时停在哪一页。
    await tester.tap(find.byTooltip('回到相册'));
    await tester.pumpAndSettle();
    expect(find.text('新建'), findsOneWidget);
  });

  testWidgets('多选移动：选一个相册就移过去，可以撤销', (tester) async {
    tester.view.physicalSize = const Size(369, 821);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late String other;
    await tester.runAsync(() async {
      other = await container.read(albumsProvider.notifier).create('表情包');
    });
    // 移动在选完相册之后才写盘:真实时间让文件写完,pump 推进回调。
    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 50 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResultThumb).first);
    await tester.pumpAndSettle();
    // 保存 / 移动 / 删除同一行,不再有单独一行的整理按钮。
    expect(find.text('整理到相册'), findsNothing);
    expect(
      tester.getCenter(find.text('移动')).dy,
      moreOrLessEquals(tester.getCenter(find.text('保存 (1)')).dy),
    );
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();
    // 在旅行里:可以移回全部相册(即移出旅行),旅行自己不在列表里。
    expect(find.text('移动到'), findsOneWidget);
    // 和相册首页同一种封面卡。
    expect(find.byType(GalleryStackCard), findsNWidgets(3));
    expect(find.byKey(const ValueKey('move-album-choice-all')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('move-album-choice-$favoritesId')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('move-album-choice-$albumId')), findsNothing);
    await tester.tap(find.byKey(ValueKey('move-album-choice-$other')));
    await settle(() => container.read(albumsProvider).contains(other, 'gen1'));
    final albums = container.read(albumsProvider);
    expect(albums.contains(other, 'gen1'), isTrue);
    expect(albums.contains(albumId, 'gen1'), isFalse);
    expect(find.text('已移动 1 张到「表情包」'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await settle(
      () => container.read(albumsProvider).contains(albumId, 'gen1'),
    );
    expect(container.read(albumsProvider).contains(albumId, 'gen1'), isTrue);
    expect(container.read(albumsProvider).contains(other, 'gen1'), isFalse);

    // 回到首页再结束:面板会记住关闭时停在哪一页。
    await tester.tap(find.byTooltip('回到相册'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('空相册页的「选择相册」点一本就切过去', (tester) async {
    tester.view.physicalSize = const Size(369, 821);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late String empty;
    await tester.runAsync(() async {
      empty = await container.read(albumsProvider.notifier).create('空相册');
    });
    container.read(albumsProvider.notifier).browse(empty);
    await tester.pumpWidget(app(const GalleryPage()));
    await tester.pumpAndSettle();
    expect(find.text('这个相册还没有照片'), findsOneWidget);
    expect(find.text('从全部作品添加'), findsNothing);
    expect(find.text('将新图保存到这里'), findsNothing);
    expect(find.byType(FilmStrip), findsNothing);

    await tester.tap(find.text('选择相册'));
    await tester.pumpAndSettle();
    // 和「保存到」同一个点选面板,当前这本描边;不是打开网格面板。
    // 收藏不作浏览相册,不列出来。
    expect(find.byType(GalleryStackCard), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('browse-album-choice-$favoritesId')),
      findsNothing,
    );
    expect(find.text('新建'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('browse-album-choice-$albumId')));
    await tester.pumpAndSettle();
    expect(container.read(galleryBrowseAlbumProvider), albumId);
    expect(
      tester.widget<FilmStrip>(find.byType(FilmStrip)).results.single.id,
      'gen1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('「保存到」胶囊在画布左下角，字加粗，种子不再显示', (tester) async {
    tester.view.physicalSize = const Size(369, 821);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const GalleryPage()));
    await tester.pumpAndSettle();
    final label = find.text('保存到 全部相册');
    expect(tester.widget<Text>(label).style!.fontWeight, FontWeight.w700);
    expect(tester.widget<Text>(label).style!.fontSize, 13);
    final chip = tester.getRect(
      find.ancestor(of: label, matching: find.byType(Material)).first,
    );
    final strip = tester.getRect(find.byType(FilmStrip));
    expect(chip.left, moreOrLessEquals(12));
    expect(chip.bottom, moreOrLessEquals(strip.top - 4));
    expect(find.byIcon(Icons.grain), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('相册首页多选：勾整本相册，全部相册不能选，删除只删相册', (tester) async {
    tester.view.physicalSize = const Size(369, 821);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late String other;
    await tester.runAsync(() async {
      other = await container.read(albumsProvider.notifier).create('表情包');
    });
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个相册'), findsOneWidget);
    // 首行三颗:保存 / 打包 ZIP / 删除,没有图片多选那两行。
    expect(find.text('打包 ZIP'), findsOneWidget);
    expect(find.text('移动'), findsNothing);

    // 全部相册点不上。
    await tester.tap(find.text('全部相册'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个相册'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个相册'), findsOneWidget);
    await tester.tap(find.text('全不选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('表情包'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个相册'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 1 个相册？'), findsOneWidget);
    await tester.tap(find.text('删除相册'));
    // 删除在确认框关掉后才写盘:真实时间让文件写完,pump 推进回调。
    for (
      var i = 0;
      i < 50 && container.read(albumsProvider).exists(other);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(container.read(albumsProvider).exists(other), isFalse);
    expect(container.read(albumsProvider).exists(albumId), isTrue);
    // 图片不跟着删,多选也退了。
    expect(container.read(galleryProvider).results, hasLength(3));
    expect(find.text('多选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('临时预览条「浏览相册」切过去停在新图上，不回到上次看的旧图', (tester) async {
    tester.view.physicalSize = const Size(369, 821);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late String other;
    await tester.runAsync(() async {
      other = await container.read(albumsProvider.notifier).create('表情包');
      await container.read(albumsProvider.notifier).organize({'gen2'}, {other});
    });
    // 先在表情包里看过旧图 gen2,再回旅行浏览;新图存进表情包。
    final albums = container.read(albumsProvider.notifier);
    albums.browse(other);
    container.read(galleryProvider.notifier).select('gen2');
    albums.browse(albumId);
    container
        .read(uiPrefsProvider.notifier)
        .patch((p) => p.copyWith(gallerySaveAlbum: other));
    await tester.pumpWidget(app(const GalleryPage()));
    await tester.pumpAndSettle();

    late String fresh;
    await tester.runAsync(() async {
      final r = await container
          .read(galleryProvider.notifier)
          .addResultToGallery(
            bytes: File('assets/app_icon.png').readAsBytesSync(),
            width: 64,
            height: 64,
            seed: 9,
            target: GallerySaveTarget.album(other),
          );
      fresh = r.id;
    });
    await tester.pumpAndSettle();
    expect(find.text('已保存到 表情包'), findsOneWidget);
    expect(find.text('浏览图库'), findsNothing);

    await tester.tap(find.text('浏览相册'));
    await tester.pumpAndSettle();
    expect(container.read(galleryBrowseAlbumProvider), other);
    expect(container.read(galleryProvider).selectedId, fresh);
    expect(find.text('已保存到 表情包'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设完保存相册，下次打开图库直接进这本，之后照常记忆', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Column(
          children: [
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
            ),
            const Expanded(child: GalleryPage()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final home = find.byKey(const PageStorageKey<String>('gallery-albums'));
    Finder photos(String key) =>
        find.byKey(PageStorageKey<String>('gallery-photos-$key'));
    Future<void> open() async {
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
    }

    Future<void> backHome() async {
      await tester.tap(find.byTooltip('回到相册'));
      await tester.pumpAndSettle();
    }

    Future<void> pickSave(String key) async {
      await tester.tap(find.textContaining('保存到 '));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('save-album-choice-$key')));
      await tester.pumpAndSettle();
    }

    // 在相册首页长按设的:关掉再开,直接是这本。
    await open();
    expect(home, findsOneWidget);
    await tester.longPress(find.text('旅行'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为保存相册'));
    await tester.pumpAndSettle();
    // 等顶部提示条自己收起,它盖在「历史」上。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await close();
    await open();
    expect(photos(albumId), findsOneWidget);

    // 只跳这一次,之后按关闭时停的那页。
    await backHome();
    await close();
    await open();
    expect(home, findsOneWidget);
    await close();

    // 画布上的胶囊设的也一样;全部相册就进全部相册的时间列表。
    await pickSave('all');
    await open();
    expect(photos('all'), findsOneWidget);
    await backHome();
    await close();

    // 设完又把胶片条切去了别的相册:以后来那次为准,不跳。
    await pickSave(albumId);
    container.read(albumsProvider.notifier).browse(null);
    await tester.pumpAndSettle();
    await open();
    expect(home, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('面板停在别的相册时点图，胶片条跟过去，画布上就是点的这张', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late String other;
    await tester.runAsync(() async {
      other = await container.read(albumsProvider.notifier).create('表情包');
      await container.read(albumsProvider.notifier).organize({'gen2'}, {other});
    });
    await tester.pumpWidget(
      app(
        Column(
          children: [
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
            ),
            const Expanded(child: GalleryPage()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    // 面板关在旅行;胶片条在外面切去了表情包(比如预览条的「浏览相册」)。
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    container.read(albumsProvider.notifier).browse(other);
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('回到相册'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ResultThumb),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(galleryBrowseAlbumProvider), albumId);
    expect(container.read(galleryViewProvider).selectedId, 'gen1');

    // 回到首页再结束:面板会记住关闭时停在哪一页。
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回到相册'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开收藏胶片条不跟过去；在收藏里点图，胶片条里有就不动，没有就回全部相册', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final albums = container.read(albumsProvider.notifier);
    // 旅行里只有 gen1;收藏 gen1、gen2。
    await tester.runAsync(() async {
      await albums.setFavorite('gen1', true);
      await albums.setFavorite('gen2', true);
    });
    // 记下的浏览 / 保存相册是收藏时,一律按全部相册算。
    container
        .read(uiPrefsProvider.notifier)
        .patch(
          (p) => p.copyWith(
            galleryBrowseAlbum: favoritesId,
            gallerySaveAlbum: favoritesId,
          ),
        );
    expect(container.read(galleryBrowseAlbumProvider), isNull);
    expect(container.read(gallerySaveTargetProvider).albumId, isNull);
    expect(() => albums.browse(favoritesId), throwsStateError);

    albums.browse(albumId);
    await tester.pumpWidget(
      app(
        Column(
          children: [
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
            ),
            const Expanded(child: GalleryPage()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder thumb(String id) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byWidgetPredicate(
        (w) => w is ResultThumb && w.result.id == id,
      ),
    );

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('回到相册'), findsOneWidget);
    expect(container.read(galleryBrowseAlbumProvider), albumId);

    await tester.tap(thumb('gen1'));
    await tester.pumpAndSettle();
    expect(container.read(galleryBrowseAlbumProvider), albumId);
    expect(container.read(galleryViewProvider).selectedId, 'gen1');

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(thumb('gen2'));
    await tester.pumpAndSettle();
    expect(container.read(galleryBrowseAlbumProvider), isNull);
    expect(container.read(galleryViewProvider).selectedId, 'gen2');

    // 回到首页再结束:面板会记住关闭时停在哪一页。
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回到相册'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按图片设为这本的封面，再长按可以取消', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 旅行里有 gen1、gen2,默认封面是较新的 gen1。
    await tester.runAsync(
      () =>
          container.read(albumsProvider.notifier).organize({'gen2'}, {albumId}),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    String coverOf(String album) => tester
        .widget<ResultThumb>(
          find.descendant(
            of: find.ancestor(
              of: find.text(album),
              matching: find.byType(GalleryStackCard),
            ),
            matching: find.byType(ResultThumb),
          ),
        )
        .result
        .id;
    expect(coverOf('旅行'), 'gen1');

    Future<void> longPressImage(String id) async {
      await tester.longPress(
        find.byWidgetPredicate((w) => w is MetaData && w.metaData == id),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    // 写盘在菜单关掉之后:真实时间让文件写完,pump 推进回调。
    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 50 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    // 等顶部提示条收起,它会盖住面板顶上的返回键。
    Future<void> backHome() async {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('回到相册'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    await longPressImage('gen2');
    expect(find.text('取消封面'), findsNothing);
    await tester.tap(find.text('设为封面'));
    await settle(
      () =>
          container.read(albumsProvider).cover(albumId)?.sourceImageId ==
          'gen2',
    );
    expect(find.text('已设为「旅行」的封面'), findsOneWidget);
    await backHome();
    expect(coverOf('旅行'), 'gen2');
    // 只动这一本:全部相册还是最新那张。
    expect(coverOf('全部相册'), 'gen0');

    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    await longPressImage('gen2');
    expect(find.text('设为封面'), findsNothing);
    await tester.tap(find.text('取消封面'));
    await settle(() => container.read(albumsProvider).cover(albumId) == null);
    await backHome();
    expect(coverOf('旅行'), 'gen1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按图片收藏，固定的「收藏」相册里可以取消', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    Finder card(String album) => find.ancestor(
      of: find.text(album),
      matching: find.byType(GalleryStackCard),
    );
    // 「收藏」紧跟在「全部相册」后面,空的时候也在。
    expect(
      tester
          .widgetList<GalleryStackCard>(find.byType(GalleryStackCard))
          .map((c) => c.group.label),
      ['全部相册', '收藏', '旅行', '回收站'],
    );
    expect(
      find.descendant(of: card('收藏'), matching: find.text('0 张')),
      findsOneWidget,
    );
    // 固定相册的长按菜单只有「排序」,没有改名和删除。
    await tester.longPress(card('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('排序'), findsOneWidget);
    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除相册'), findsNothing);
    await tester.tapAt(const Offset(8, 8)); // 点遮罩收起菜单
    await tester.pumpAndSettle();

    Future<void> longPressImage(String id) async {
      await tester.longPress(
        find.byWidgetPredicate((w) => w is MetaData && w.metaData == id),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 50 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> backHome() async {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('回到相册'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('全部相册'));
    await tester.pumpAndSettle();
    await longPressImage('gen2');
    expect(find.text('取消收藏'), findsNothing);
    await tester.tap(find.text('收藏'));
    await settle(() => container.read(albumsProvider).isFavorite('gen2'));
    expect(find.text('已收藏'), findsOneWidget);
    await backHome();
    expect(
      find.descendant(of: card('收藏'), matching: find.text('1 张')),
      findsOneWidget,
    );
    // 封面固定是图标,不取图。
    expect(
      find.descendant(of: card('收藏'), matching: find.byType(ResultThumb)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: card('收藏'),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    await longPressImage('gen2');
    expect(find.text('设为封面'), findsNothing);
    await tester.tap(find.text('取消收藏'));
    await settle(() => !container.read(albumsProvider).isFavorite('gen2'));
    expect(find.text('已取消收藏'), findsOneWidget);
    expect(find.text('这个相册还没有图片'), findsOneWidget);
    // 撤销:图回到收藏里。
    await tester.tap(find.text('撤销'));
    await settle(() => container.read(albumsProvider).isFavorite('gen2'));
    expect(
      find.byWidgetPredicate((w) => w is MetaData && w.metaData == 'gen2'),
      findsOneWidget,
    );
    await backHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除进回收站，回收站里点图恢复，回到原相册', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    Finder card(String album) => find.ancestor(
      of: find.text(album),
      matching: find.byType(GalleryStackCard),
    );
    Finder image(String id) =>
        find.byWidgetPredicate((w) => w is MetaData && w.metaData == id);
    // 回收站排在最后,空的时候也在;空着时长按只有「排序」。
    expect(
      find.descendant(of: card('回收站'), matching: find.text('0 张')),
      findsOneWidget,
    );
    await tester.longPress(card('回收站'));
    await tester.pumpAndSettle();
    expect(find.text('排序'), findsOneWidget);
    expect(find.text('全部恢复'), findsNothing);
    expect(find.text('清空回收站'), findsNothing);
    await tester.tapAt(const Offset(8, 8)); // 点遮罩收起菜单
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部相册'));
    await tester.pumpAndSettle();
    await tester.longPress(image('gen1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('已移到回收站'), findsOneWidget);
    expect(image('gen1'), findsNothing);
    expect(container.read(galleryProvider).trash.single.image.id, 'gen1');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回到相册'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card('回收站'), matching: find.text('1 张')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card('回收站'), matching: find.byType(ResultThumb)),
      findsNothing,
    );
    expect(
      find.descendant(of: card('旅行'), matching: find.text('0 张')),
      findsOneWidget,
    );

    await tester.tap(find.text('回收站'));
    await tester.pumpAndSettle();
    expect(find.text('1 张 · $kTrashKeepDays 天后删除'), findsOneWidget);
    expect(find.byTooltip('搜索提示词标签'), findsNothing);
    // 点一下就抬起,菜单里是恢复和彻底删除。
    await tester.tap(image('gen1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('彻底删除'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('回收站是空的'), findsOneWidget);
    expect(container.read(galleryProvider).trash, isEmpty);
    expect(
      [for (final r in container.read(galleryProvider).results) r.id],
      ['gen0', 'gen1', 'gen2'],
    );
    expect(container.read(albumsProvider).contains(albumId, 'gen1'), isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('「收藏」不出现在「保存到」里，多选时不能勾', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showGalleryGrid(context),
                child: const Text('历史'),
              ),
              TextButton(
                onPressed: () => showGallerySaveAlbumPicker(context),
                child: const Text('保存目标'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-album-choice-all')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('save-album-choice-$favoritesId')),
      findsNothing,
    );
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个相册'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建相册时可以直接设为保存相册', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGalleryGrid(context),
            child: const Text('历史'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.text('设为保存相册'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '新相册');
    await tester.tap(find.text('设为保存相册'));
    await tester.runAsync(() async {
      await tester.tap(find.text('保存').last);
      await stores.albums.idle;
    });
    await tester.pumpAndSettle();
    final created = container.read(albumsProvider).albums.first;
    expect(created.name, '新相册');
    expect(container.read(gallerySaveTargetProvider).albumId, created.id);
    expect(container.read(galleryBrowseAlbumProvider), created.id);
    expect(find.text('新相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

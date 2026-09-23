import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/ui_prefs.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/features/gallery/albums/album_state.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/generate/gen_queue.dart';

final png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0,
  0,
  0,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0,
  0,
  0,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x62,
  0,
  0x01,
  0,
  0,
  0x05,
  0,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0,
  0,
  0,
  0,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppStores stores;
  late ProviderContainer c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('plana_album_state_');
    stores = await AppStores.open(rootOverride: root);
    c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
  });
  tearDown(() async {
    stores.flushNow();
    await stores.gallery.idle;
    await stores.albums.idle;
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (var attempt = 0; ; attempt++) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  for (final scoped in [false, true]) {
    test('${scoped ? '指定图库' : '全部作品'}删除后选相邻图片，删除其他图片不改选', () async {
      final albums = c.read(albumsProvider.notifier);
      final album = await albums.create('浏览图库');
      final other = await albums.create('其他图库');
      final gallery = c.read(galleryProvider.notifier);
      final ids = <String>[];
      for (var seed = 0; seed < 5; seed++) {
        ids.add(
          (await gallery.addResultToGallery(
            bytes: png,
            width: 1,
            height: 1,
            seed: seed,
            target: GallerySaveTarget.album(album),
          )).id,
        );
        if (scoped) {
          await gallery.addResultToGallery(
            bytes: png,
            width: 1,
            height: 1,
            seed: seed + 10,
            target: GallerySaveTarget.album(other),
          );
        }
      }
      albums.browse(scoped ? album : null);
      albums.setSave(other);
      gallery.select(ids[2]);
      gallery.deleteResults([ids[2]]);
      expect(c.read(galleryViewProvider).selectedId, ids[1]);
      expect(c.read(galleryProvider).selectedId, ids[1]);

      // 删除左侧未选中的缩略图，不改变当前预览。
      gallery.deleteResults([ids[4]]);
      expect(c.read(galleryViewProvider).selectedId, ids[1]);

      // 最后一张没有下一张时，选最近的上一张。
      gallery.select(ids[0]);
      gallery.deleteResults([ids[0]]);
      expect(c.read(galleryViewProvider).selectedId, ids[1]);

      // 连续/批量删除跳过一起删除的项，选中结果也持久化。
      gallery.deleteResults([ids[1], ids[2]]);
      expect(c.read(galleryViewProvider).selectedId, ids[3]);
      stores.flushNow();
      await stores.gallery.idle;
      await stores.albums.idle;
      final restored = await AppStores.open(rootOverride: root);
      expect(restored.gallery.initialSelectedId, ids[3]);

      gallery.deleteResults([ids[3]]);
      expect(c.read(galleryViewProvider).results, isEmpty);
      expect(c.read(galleryViewProvider).selectedId, isNull);
      expect(c.read(galleryProvider).selectedId, isNull);
      expect(c.read(galleryProvider).results, hasLength(scoped ? 5 : 0));
      expect(c.read(galleryBrowseAlbumProvider), scoped ? album : null);
      expect(c.read(gallerySaveTargetProvider).albumId, other);
    });
  }

  test('批量删除跳过一并删除的相邻图片，正在入库的新图不抢回选择', () async {
    final gallery = c.read(galleryProvider.notifier);
    final ids = <String>[];
    for (var seed = 0; seed < 5; seed++) {
      ids.add(
        (await gallery.addResultToGallery(
          bytes: png,
          width: 1,
          height: 1,
          seed: seed,
          target: const GallerySaveTarget.all(),
        )).id,
      );
    }
    gallery.select(ids[3]);
    final pending = gallery.addResultToGallery(
      bytes: png,
      width: 1,
      height: 1,
      seed: 5,
      target: const GallerySaveTarget.all(),
    );
    gallery.deleteResults([ids[3], ids[2]]);
    expect(c.read(galleryProvider).selectedId, ids[1]);
    await pending;
    expect(c.read(galleryViewProvider).selectedId, ids[1]);
  });

  test('落盘期间改选图片，旧结果只提示；主动跟随结果使用临时预览', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A'), b = await albums.create('B');
    final gallery = c.read(galleryProvider.notifier);
    final old = await gallery.addResultToGallery(
      bytes: png,
      width: 1,
      height: 1,
      seed: 1,
      target: GallerySaveTarget.album(b),
    );
    albums.browse(b);
    final pending = gallery.addResultToGallery(
      bytes: png,
      width: 1,
      height: 1,
      seed: 2,
      target: GallerySaveTarget.album(a),
    );
    gallery.select(old.id);
    final saved = await pending;
    expect(c.read(galleryViewProvider).selectedId, old.id);
    expect(c.read(galleryResultPreviewProvider), isNull);
    expect(c.read(gallerySavedNoticeProvider)?.imageId, saved.id);
    final followed = await gallery.addResultToGallery(
      bytes: png,
      width: 1,
      height: 1,
      seed: 3,
      target: GallerySaveTarget.album(a),
    );
    expect(c.read(galleryResultPreviewProvider)?.imageId, followed.id);
    expect(c.read(galleryBrowseAlbumProvider), b);
    expect(c.read(galleryViewProvider).selectedId, old.id);
    gallery.select(old.id);
    expect(c.read(galleryResultPreviewProvider), isNull);
  });

  test('清空期间的旧入库不会恢复已清除的图片、图库或关系', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A');
    albums.browse(a, alsoSave: true);
    final gallery = c.read(galleryProvider.notifier);
    final pending = gallery.addResultToGallery(
      bytes: png,
      width: 1,
      height: 1,
      seed: 1,
      target: GallerySaveTarget.album(a),
    );
    final clearing = gallery.clearAll();
    await pending;
    await clearing;
    await stores.gallery.idle;
    await stores.albums.idle;
    expect(c.read(galleryProvider).results, isEmpty);
    expect(c.read(albumsProvider).albums, isEmpty);
    expect(c.read(albumsProvider).memberships, isEmpty);
    expect(c.read(galleryBrowseAlbumProvider), isNull);
    expect(c.read(gallerySaveTargetProvider).albumId, isNull);
    await stores.prefs.write(key: '_test_barrier', value: '1');
    final back = await AppStores.open(rootOverride: root);
    expect(back.gallery.initialResults, isEmpty);
    expect(back.albums.data.albums, isEmpty);
  });

  test('浏览和保存独立，入队时冻结目标', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A'), b = await albums.create('B');
    albums.setSave(a);
    c.read(genQueueProvider.notifier).enqueue();
    albums.browse(b);
    expect(c.read(gallerySaveTargetProvider).albumId, a);
    albums.setSave(b);
    expect(c.read(genQueueProvider).items.single.galleryTarget.albumId, a);
    expect(c.read(galleryBrowseAlbumProvider), b);
  });

  test('旧目标入库不会改当前图库，重启恢复关系且原图仅一份', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A'), b = await albums.create('B');
    albums.setSave(a);
    final captured = c.read(gallerySaveTargetProvider);
    albums.browse(b, alsoSave: true);
    final image = await c
        .read(galleryProvider.notifier)
        .addResultToGallery(
          bytes: png,
          width: 1,
          height: 1,
          seed: 42,
          target: captured,
          select: false,
        );
    expect(c.read(galleryBrowseAlbumProvider), b);
    expect(c.read(galleryViewProvider).results, isEmpty);
    expect(c.read(albumsProvider).ofImage(image.id), {a});
    await albums.organize({image.id}, {b});
    expect(c.read(galleryViewProvider).results.single.id, image.id);
    expect(await Directory('${root.path}/gallery/images').list().length, 1);
    await stores.prefs.write(key: '_test_barrier', value: '1');
    final back = await AppStores.open(rootOverride: root);
    final restoredPrefs = UiPrefs.fromJson(
      jsonDecode(back.prefs.get('ui_prefs')!),
    );
    expect(restoredPrefs.galleryBrowseAlbum, b);
    expect(restoredPrefs.gallerySaveAlbum, b);
    expect(back.albums.data.ofImage(image.id), {a, b});
    expect(back.gallery.initialResults.single.id, image.id);
  });

  test('未勾选或取消勾选的导入绝不写回旧图库，即使只有一个候选', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A'), b = await albums.create('B');
    final image = await c
        .read(galleryProvider.notifier)
        .addResultToGallery(
          bytes: png,
          width: 1,
          height: 1,
          seed: 1,
          target: GallerySaveTarget.album(a),
        );
    final origin = GalleryImportOrigin(imageId: image.id);
    albums.browse(b, alsoSave: true);
    albums.applyImportChoice(origin, const ImportAlbumChoice());
    expect(c.read(galleryBrowseAlbumProvider), b);
    expect(c.read(gallerySaveTargetProvider).albumId, b);
    albums.applyImportChoice(
      origin,
      ImportAlbumChoice(
        enabled: false,
        target: GallerySaveTarget.album(a),
        alsoSave: true,
      ),
    );
    expect(c.read(galleryBrowseAlbumProvider), b);
    expect(c.read(gallerySaveTargetProvider).albumId, b);
    albums.applyImportChoice(
      origin,
      ImportAlbumChoice(enabled: true, target: GallerySaveTarget.album(a)),
    );
    expect(c.read(galleryBrowseAlbumProvider), a);
    expect(c.read(gallerySaveTargetProvider).albumId, b);
    albums.applyImportChoice(
      origin,
      ImportAlbumChoice(
        enabled: true,
        target: GallerySaveTarget.album(a),
        alsoSave: true,
      ),
    );
    expect(c.read(gallerySaveTargetProvider).albumId, a);
  });

  test('总图库显示多个导入候选，具体来源只允许该图库；失效后沿用当前', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A'), b = await albums.create('B');
    final image = await c
        .read(galleryProvider.notifier)
        .addResultToGallery(
          bytes: png,
          width: 1,
          height: 1,
          seed: 1,
          target: GallerySaveTarget.album(a),
        );
    await albums.organize({image.id}, {b});
    expect(
      albums.importCandidates(GalleryImportOrigin(imageId: image.id)),
      hasLength(2),
    );
    final origin = GalleryImportOrigin(imageId: image.id, albumId: a);
    expect(albums.importCandidates(origin).single.id, a);
    albums.browse(b);
    expect(
      albums.applyImportChoice(
        origin,
        ImportAlbumChoice(enabled: true, target: GallerySaveTarget.album(b)),
      ),
      contains('已变化'),
    );
    await albums.delete(a);
    albums.applyImportChoice(
      origin,
      ImportAlbumChoice(enabled: true, target: GallerySaveTarget.album(a)),
    );
    expect(c.read(galleryBrowseAlbumProvider), b);
  });

  test('切空图库不会退回全量图片；删除目标后结果保留在所有照片', () async {
    final albums = c.read(albumsProvider.notifier);
    final a = await albums.create('A'), b = await albums.create('B');
    final image = await c
        .read(galleryProvider.notifier)
        .addResultToGallery(
          bytes: png,
          width: 1,
          height: 1,
          seed: 1,
          target: GallerySaveTarget.album(a),
        );
    albums.browse(b);
    expect(c.read(galleryViewProvider).selected, isNull);
    await albums.delete(a);
    final other = await c
        .read(galleryProvider.notifier)
        .addResultToGallery(
          bytes: png,
          width: 1,
          height: 1,
          seed: 2,
          target: GallerySaveTarget.album(a),
          select: false,
        );
    expect(
      c.read(galleryProvider).results.map((r) => r.id),
      containsAll([image.id, other.id]),
    );
    expect(c.read(albumsProvider).ofImage(other.id), isEmpty);
  });
}

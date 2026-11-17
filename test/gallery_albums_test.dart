import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/blob_store.dart';
import 'package:plana_app/features/gallery/gallery_store.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/features/gallery/albums/album_store.dart';

AlbumsData fixture() => AlbumsData(
  albums: [
    const GalleryAlbum(id: 'a', name: 'A', createdAt: 1),
    const GalleryAlbum(id: 'b', name: 'B', createdAt: 2),
    const GalleryAlbum(id: 'c', name: 'C', createdAt: 3),
  ],
  memberships: {
    'one': {'a', 'c'},
    'two': {'c'},
  },
);

void main() {
  test('索引写入失败不能被串行队列吞掉并误认为可以提交图库关系', () async {
    final root = await Directory.systemTemp.createTemp(
      'plana_album_index_failure_',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = GalleryStore(BlobStore(root), root);
    await Directory('${root.path}/gallery/index.json').create(recursive: true);
    store.scheduleIndex(results: [], selectedId: null, seq: 1);
    await expectLater(store.flushIndex(), throwsA(isA<FileSystemException>()));
    await store.idle;
    await expectLater(store.flushIndex(), throwsA(isA<FileSystemException>()));
  });
  test('清空后备份不复活旧数据', () async {
    final root = await Directory.systemTemp.createTemp('plana_album_reset_');
    addTearDown(() => root.delete(recursive: true));
    final store = AlbumStore(root);
    await store.update((_) => fixture());
    await store.update((_) => AlbumsData(), reset: true);
    expect(store.data.albums, isEmpty);
    expect(store.data.allPhotosCover, isNull);
    await File('${root.path}/gallery/albums.json').writeAsString('broken');
    final restored = AlbumStore(root);
    await restored.load();
    expect(restored.data.albums, isEmpty);
    expect(restored.data.memberships, isEmpty);
  });

  test('索引校验清理失效图片与来源封面，写入失败不报告已修改', () async {
    final root = await Directory.systemTemp.createTemp('plana_album_failure_');
    addTearDown(() => root.delete(recursive: true));
    final store = AlbumStore(root);
    await store.update(
      (_) => fixture().withCover(
        'a',
        const AlbumCover('cover', sourceImageId: 'one'),
      ),
    );
    final reopened = AlbumStore(root);
    await reopened.load(liveImages: {'two'});
    expect(reopened.data.ofImage('one'), isEmpty);
    expect(reopened.data.cover('a'), isNull);
    final file = File('${root.path}/gallery/albums.json');
    await file.delete();
    await Directory(file.path).create();
    await expectLater(
      reopened.update((d) => d.deleteAlbum('a')),
      throwsA(isA<FileSystemException>()),
    );
    expect(reopened.data.exists('a'), isTrue);
  });

  test('一万条归属可筛选、去重及批量移动，不创建额外原图记录', () {
    final data = fixture().copyWith(
      memberships: {
        for (var i = 0; i < 10000; i++) 'image$i': {i.isEven ? 'a' : 'b', 'c'},
      },
    );
    final watch = Stopwatch()..start();
    final selected = data.memberships.keys
        .where((id) => data.contains('a', id))
        .toSet();
    expect(selected, hasLength(5000));
    final next = data.organize(selected, {'b'}, sources: {'a'});
    expect(next.memberships, hasLength(10000));
    expect(next.memberships.values.every((ids) => ids.contains('c')), isTrue);
    expect(
      next.memberships.values.where((ids) => ids.contains('b')),
      hasLength(10000),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
  test('移动只移出指定来源，其他归属保留；添加不重复', () {
    final before = fixture();
    final moved = before.organize({'one', 'two'}, {'b'}, sources: {'a'});
    expect(moved.ofImage('one'), {'b', 'c'});
    expect(moved.ofImage('two'), {'c'});
    expect(moved.contains(null, 'one'), isTrue);
    final added = moved.organize({'one'}, {'b', 'a'});
    expect(added.ofImage('one'), {'a', 'b', 'c'});
    expect(added.organize({'one'}, {'b'}).ofImage('one'), {'a', 'b', 'c'});
    expect(
      () => before.organize({'one'}, {'a'}, sources: {'a'}),
      throwsStateError,
    );
  });
  test('撤销只恢复这次变更，图片/图库删除后不复活', () {
    final before = fixture();
    final after = before.organize({'one'}, {'b'}, sources: {'a'});
    final change = AlbumChange(before, after, {'one'});
    expect(change.count, 1);
    expect(change.undo(after, {'one', 'two'}).ofImage('one'), {'a', 'c'});
    expect(change.undo(after.deleteAlbum('a'), {'one', 'two'}).ofImage('one'), {
      'c',
    });
    expect(
      change.undo(after.removeImages({'one'}), {'two'}).ofImage('one'),
      isEmpty,
    );
  });
  test('删除图库保留其他关系，删除图片清掉来源封面', () {
    final data = fixture().withCover(
      'a',
      const AlbumCover('cover', sourceImageId: 'one'),
    );
    expect(data.deleteAlbum('a').ofImage('one'), {'c'});
    final removed = data.removeImages({'one'});
    expect(removed.ofImage('one'), isEmpty);
    expect(removed.cover('a'), isNull);
    expect(removed.ofImage('two'), {'c'});
  });
  test('排序:收藏、回收站也能排,新建的插在第一本用户相册前,顺序能往返;没变不写', () {
    final data = fixture();
    expect(data.order, [favoritesId, 'a', 'b', 'c', trashId]);
    expect(identical(data.reorder([...data.order]), data), isTrue);
    final moved = data.reorder([trashId, 'c', favoritesId, 'a', 'b']);
    expect([for (final a in moved.albums) a.id], ['c', 'a', 'b']);
    expect(moved.memberships, data.memberships);
    final back = AlbumsData.fromJson(jsonDecode(jsonEncode(moved.toJson())));
    expect(back.order, [trashId, 'c', favoritesId, 'a', 'b']);
    final added = back.copyWith(
      albums: [
        const GalleryAlbum(id: 'd', name: 'D', createdAt: 4),
        ...back.albums,
      ],
    );
    expect(added.order, [trashId, 'd', 'c', favoritesId, 'a', 'b']);
    expect(added.deleteAlbum('c').order, [trashId, 'd', favoritesId, 'a', 'b']);
    final none = AlbumsData().copyWith(
      albums: [const GalleryAlbum(id: 'e', name: 'E', createdAt: 5)],
    );
    expect(none.order, [favoritesId, 'e', trashId]);
  });

  test('图库数据往返，拒绝路径形式的封面 ID', () {
    final back = AlbumsData.fromJson(
      jsonDecode(jsonEncode(fixture().toJson())),
    );
    expect(back.ofImage('one'), {'a', 'c'});
    expect(back.name('b'), 'B');
    expect(AlbumCover.parse({'key': '../outside'}), isNull);
  });
  test('收藏是固定相册:收藏 / 取消只动这一项，归属能往返，没有封面', () {
    final data = fixture()
        .favorite({'one', 'two'}, true)
        .withCover(favoritesId, const AlbumCover('k', sourceImageId: 'two'));
    expect(data.cover(favoritesId), isNull);
    expect(data.exists(favoritesId), isTrue);
    expect(data.name(favoritesId), favoritesName);
    expect(data.albums.map((a) => a.id), ['a', 'b', 'c']);
    expect(data.ofImage('one'), {'a', 'c', favoritesId});
    expect(data.isFavorite('two'), isTrue);
    final off = data.favorite({'one'}, false);
    expect(off.ofImage('one'), {'a', 'c'});
    expect(off.isFavorite('two'), isTrue);

    final back = AlbumsData.fromJson(jsonDecode(jsonEncode(data.toJson())));
    expect(back.ofImage('one'), {'a', 'c', favoritesId});
    expect(back.albums.map((a) => a.id), ['a', 'b', 'c']);
  });
  test('串行修改、重启、坏主档恢复有效备份', () async {
    final root = await Directory.systemTemp.createTemp('plana_albums_');
    addTearDown(() => root.delete(recursive: true));
    final store = AlbumStore(root);
    await store.load();
    await store.update((_) => fixture());
    await Future.wait([
      store.update((d) => d.organize({'one'}, {'b'})),
      store.update((d) => d.organize({'two'}, {'a'})),
    ]);
    final reopened = AlbumStore(root);
    await reopened.load();
    expect(reopened.data.ofImage('one'), {'a', 'b', 'c'});
    expect(reopened.data.ofImage('two'), {'a', 'c'});
    await File('${root.path}/gallery/albums.json').writeAsString('broken');
    final recovered = AlbumStore(root);
    await recovered.load();
    expect(recovered.readOnly, isFalse);
    expect(recovered.data.ofImage('one'), {'a', 'b', 'c'});
    expect(recovered.warning, isNotNull);
  });
  test('唯一坏档不能被普通写操作覆盖', () async {
    final root = await Directory.systemTemp.createTemp('plana_albums_corrupt_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/gallery/albums.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('broken');
    final store = AlbumStore(root);
    await store.load();
    expect(store.readOnly, isTrue);
    await expectLater(store.update((_) => fixture()), throwsStateError);
    expect(await file.readAsString(), 'broken');
  });
}

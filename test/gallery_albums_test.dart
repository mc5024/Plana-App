import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  test('封面独立复制、重启可读；清空使旧封面提交失效且备份不复活数据', () async {
    final root = await Directory.systemTemp.createTemp('plana_album_cover_');
    addTearDown(() => root.delete(recursive: true));
    final store = AlbumStore(root);
    await store.update((_) => fixture());
    final bytes = Uint8List.fromList([1, 2, 3]);
    await store.setCover('a', bytes);
    final key = store.data.cover('a')!.key;
    bytes[0] = 9;
    final reopened = AlbumStore(root);
    await reopened.load();
    expect(await reopened.readCover(key), [1, 2, 3]);
    final clearing = store.update((_) => AlbumsData(), reset: true);
    final pending = store.setCover(null, Uint8List.fromList([4, 5]));
    final rejected = expectLater(pending, throwsStateError);
    await clearing;
    await rejected;
    expect(store.data.albums, isEmpty);
    expect(store.data.allPhotosCover, isNull);
    expect(
      await Directory('${root.path}/gallery/album_covers').list().length,
      0,
    );
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
  test('图库数据往返，拒绝路径形式的封面 ID', () {
    final back = AlbumsData.fromJson(
      jsonDecode(jsonEncode(fixture().toJson())),
    );
    expect(back.ofImage('one'), {'a', 'c'});
    expect(back.name('b'), 'B');
    expect(AlbumCover.parse({'key': '../outside'}), isNull);
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

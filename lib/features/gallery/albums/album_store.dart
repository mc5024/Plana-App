import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/store/atomic_file.dart';
import 'album_models.dart';

/// 图库归属不能从 PNG 重建：原子提交，保留有效备份，坏档只读。
class AlbumStore {
  AlbumStore(Directory support) : root = Directory('${support.path}/gallery');
  final Directory root;
  AlbumsData data = AlbumsData();
  String? warning;
  bool readOnly = false;
  Future<void> _tail = Future.value();
  final _pendingCovers = <String>{};
  int _resetVersion = 0;
  Future<void> get idle => _tail;
  File get _file => File('${root.path}/albums.json');
  File get _backup => File('${root.path}/albums.json.bak');
  File _cover(String key) {
    if (!validGalleryId(key)) throw const FormatException('封面 ID 无效');
    return File('${root.path}/album_covers/$key.png');
  }

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

  Future<void> load({Set<String>? liveImages}) async {
    if (!await _file.exists() && !await _backup.exists()) return;
    for (final f in [_file, _backup]) {
      try {
        data = AlbumsData.fromJson(jsonDecode(await f.readAsString()));
        if (liveImages != null) {
          final referenced = <String>{
            ...data.memberships.keys,
            if (data.allPhotosCover?.sourceImageId != null)
              data.allPhotosCover!.sourceImageId!,
            for (final a in data.albums)
              if (a.cover?.sourceImageId != null) a.cover!.sourceImageId!,
          };
          final missing = referenced.difference(liveImages);
          if (missing.isNotEmpty) data = data.removeImages(missing);
        }
        if (f.path == _backup.path) warning = '图库数据已从最近一次备份恢复';
        return;
      } catch (_) {}
    }
    readOnly = true;
    warning = '图库归属数据暂时无法读取，原文件已保留；全部作品仍可查看';
  }

  Future<AlbumsData> update(
    AlbumsData Function(AlbumsData) change, {
    bool reset = false,
  }) {
    final work = _tail.then((_) async {
      if (readOnly && !reset) throw StateError('图库数据需要恢复，暂时不能修改');
      final next = change(data);
      if (identical(next, data)) return data;
      // 备份只来自已校验的内存状态，不把磁盘上的坏档抄成有效备份。
      if (!readOnly || reset) {
        await writeStringAtomic(
          _backup,
          jsonEncode((reset ? next : data).toJson()),
        );
      }
      await writeStringAtomic(_file, jsonEncode(next.toJson()));
      data = next;
      if (reset) {
        _resetVersion++;
        readOnly = false;
        warning = null;
      }
      await _cleanCovers();
      return data;
    });
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  Future<AlbumsData> setCover(
    String? albumId,
    Uint8List? png, {
    String? sourceImageId,
    bool Function(String)? imageExists,
  }) async {
    AlbumCover? cover;
    final version = _resetVersion;
    try {
      if (png != null) {
        cover = AlbumCover(newId(), sourceImageId: sourceImageId);
        _pendingCovers.add(cover.key);
        await writeBytesAtomic(_cover(cover.key), png);
      }
      return await update((d) {
        if (version != _resetVersion) throw StateError('图库已清空，请重新选择封面');
        if (!d.exists(albumId)) throw StateError('图库已被删除');
        if (sourceImageId != null &&
            imageExists?.call(sourceImageId) == false) {
          throw StateError('封面来源图片已被删除，请重新选择');
        }
        return d.withCover(albumId, cover);
      });
    } catch (_) {
      if (cover != null) {
        try {
          await _cover(cover.key).delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (cover != null) _pendingCovers.remove(cover.key);
    }
  }

  Future<Uint8List?> readCover(String key) async {
    try {
      return await _cover(key).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _cleanCovers() async {
    // 保留最近有效备份引用的封面，恢复时仍可展示。
    final keys = <String>{
      ..._pendingCovers,
      if (data.allPhotosCover != null) data.allPhotosCover!.key,
      for (final a in data.albums)
        if (a.cover != null) a.cover!.key,
    };
    try {
      final backup = AlbumsData.fromJson(
        jsonDecode(await _backup.readAsString()),
      );
      if (backup.allPhotosCover != null) keys.add(backup.allPhotosCover!.key);
      keys.addAll(backup.albums.map((a) => a.cover?.key).whereType<String>());
    } catch (_) {}
    try {
      await for (final f in Directory('${root.path}/album_covers').list()) {
        if (f is! File || !f.path.endsWith('.png')) continue;
        final key = f.uri.pathSegments.last.replaceFirst(RegExp(r'\.png$'), '');
        if (!keys.contains(key)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

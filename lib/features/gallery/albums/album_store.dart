import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/store/atomic_file.dart';
import 'album_models.dart';
import '../../../l10n/l10n.dart';

/// 相册归属不能从 PNG 重建：原子提交，保留有效备份，坏档只读。
class AlbumStore {
  AlbumStore(Directory support) : root = Directory('${support.path}/gallery');
  final Directory root;
  AlbumsData data = AlbumsData();
  String? warning;
  bool readOnly = false;
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  File get _file => File('${root.path}/albums.json');
  File get _backup => File('${root.path}/albums.json.bak');

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
        if (f.path == _backup.path) warning = l10nNow.albumsRestored;
        return;
      } catch (_) {}
    }
    readOnly = true;
    warning = l10nNow.albumsUnreadable;
  }

  Future<AlbumsData> update(
    AlbumsData Function(AlbumsData) change, {
    bool reset = false,
  }) {
    final work = _tail.then((_) async {
      if (readOnly && !reset) throw StateError(l10nNow.albumsReadOnly);
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
        readOnly = false;
        warning = null;
      }
      return data;
    });
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }
}

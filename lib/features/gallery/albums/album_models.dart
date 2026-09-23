import 'package:flutter/foundation.dart' show setEquals;

const allPhotosName = '全部作品';
bool validGalleryId(String id) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);

/// null 是明确的“仅全部作品”；参数本身为 null 才表示读取当前设置。
class GallerySaveTarget {
  const GallerySaveTarget.all() : albumId = null;
  const GallerySaveTarget.album(String id) : albumId = id;
  final String? albumId;
}

class GalleryImportOrigin {
  const GalleryImportOrigin({required this.imageId, this.albumId});
  final String imageId;
  final String? albumId;
}

class ImportAlbumChoice {
  const ImportAlbumChoice({
    this.enabled = false,
    this.target,
    this.alsoSave = false,
  });
  final bool enabled;
  final GallerySaveTarget? target;
  final bool alsoSave;
}

class AlbumCover {
  const AlbumCover(this.key, {this.sourceImageId});
  final String key;
  final String? sourceImageId;
  Map<String, Object?> toJson() => {'key': key, 'source': sourceImageId};
  static AlbumCover? parse(Object? raw) {
    if (raw is! Map ||
        raw['key'] is! String ||
        !validGalleryId(raw['key'] as String)) {
      return null;
    }
    return AlbumCover(
      raw['key'] as String,
      sourceImageId: raw['source'] is String ? raw['source'] as String : null,
    );
  }
}

class GalleryAlbum {
  const GalleryAlbum({
    required this.id,
    required this.name,
    required this.createdAt,
    this.cover,
  });
  final String id;
  final String name;
  final int createdAt;
  final AlbumCover? cover;
  GalleryAlbum copyWith({
    String? name,
    AlbumCover? cover,
    bool clearCover = false,
  }) => GalleryAlbum(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    cover: clearCover ? null : (cover ?? this.cover),
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'cover': cover?.toJson(),
  };
}

class AlbumsData {
  AlbumsData({
    Iterable<GalleryAlbum> albums = const [],
    Map<String, Set<String>> memberships = const {},
    this.allPhotosCover,
  }) : albums = List.unmodifiable(albums),
       memberships = Map.unmodifiable({
         for (final e in memberships.entries)
           e.key: Set<String>.unmodifiable(e.value),
       });
  final List<GalleryAlbum> albums;
  final Map<String, Set<String>> memberships;
  final AlbumCover? allPhotosCover;
  GalleryAlbum? album(String? id) =>
      albums.where((a) => a.id == id).firstOrNull;
  bool exists(String? id) => id == null || album(id) != null;
  String name(String? id) => album(id)?.name ?? allPhotosName;
  bool contains(String? albumId, String imageId) =>
      albumId == null ||
      (exists(albumId) && (memberships[imageId]?.contains(albumId) ?? false));
  Set<String> ofImage(String imageId) => memberships[imageId] ?? const {};
  AlbumCover? cover(String? id) =>
      id == null ? allPhotosCover : album(id)?.cover;

  AlbumsData copyWith({
    Iterable<GalleryAlbum>? albums,
    Map<String, Set<String>>? memberships,
    AlbumCover? allPhotosCover,
    bool clearAllCover = false,
  }) => AlbumsData(
    albums: albums ?? this.albums,
    memberships: memberships ?? this.memberships,
    allPhotosCover: clearAllCover
        ? null
        : allPhotosCover ?? this.allPhotosCover,
  );

  AlbumsData withCover(String? id, AlbumCover? cover) => id == null
      ? copyWith(allPhotosCover: cover, clearAllCover: cover == null)
      : copyWith(
          albums: [
            for (final a in albums)
              a.id == id
                  ? a.copyWith(cover: cover, clearCover: cover == null)
                  : a,
          ],
        );

  AlbumsData removeImages(Set<String> ids) {
    bool removed(AlbumCover? cover) =>
        cover != null && ids.contains(cover.sourceImageId);
    return copyWith(
      memberships: {
        for (final e in memberships.entries)
          if (!ids.contains(e.key)) e.key: e.value,
      },
      albums: [
        for (final a in albums)
          removed(a.cover) ? a.copyWith(clearCover: true) : a,
      ],
      clearAllCover: removed(allPhotosCover),
    );
  }

  AlbumsData deleteAlbum(String id) => copyWith(
    albums: albums.where((a) => a.id != id),
    memberships: {
      for (final e in memberships.entries)
        if (e.value.any((v) => v != id))
          e.key: e.value.where((v) => v != id).toSet(),
    },
  );

  /// sources=null 表示添加；移动仅处理属于明确来源的图片。
  AlbumsData organize(
    Set<String> imageIds,
    Set<String> targets, {
    Set<String>? sources,
  }) {
    if (targets.any((id) => !exists(id)) ||
        sources?.any((id) => !exists(id)) == true) {
      throw StateError('图库已不存在，请重新选择');
    }
    if (sources != null &&
        (sources.isEmpty || sources.intersection(targets).isNotEmpty)) {
      throw StateError('请选择不同的来源和目标图库');
    }
    final next = {...memberships};
    for (final id in imageIds) {
      final old = ofImage(id);
      if (sources != null && old.intersection(sources).isEmpty) continue;
      final value = {...old}
        ..removeAll(sources ?? const {})
        ..addAll(targets);
      if (value.isEmpty) {
        next.remove(id);
      } else {
        next[id] = value;
      }
    }
    return copyWith(memberships: next);
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'albums': [for (final a in albums) a.toJson()],
    'memberships': {
      for (final e in memberships.entries) e.key: e.value.toList(),
    },
    'allPhotosCover': allPhotosCover?.toJson(),
  };

  factory AlbumsData.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['v'] != 1 ||
        raw['albums'] is! List ||
        raw['memberships'] is! Map) {
      throw const FormatException('图库数据格式无效');
    }
    final albums = <GalleryAlbum>[];
    final ids = <String>{};
    for (final a in raw['albums'] as List) {
      if (a is! Map ||
          a['id'] is! String ||
          a['name'] is! String ||
          !validGalleryId(a['id'] as String) ||
          (a['name'] as String).trim().isEmpty ||
          !ids.add(a['id'] as String)) {
        continue;
      }
      albums.add(
        GalleryAlbum(
          id: a['id'] as String,
          name: a['name'] as String,
          createdAt: a['createdAt'] is num
              ? (a['createdAt'] as num).toInt()
              : 0,
          cover: AlbumCover.parse(a['cover']),
        ),
      );
    }
    return AlbumsData(
      albums: albums,
      allPhotosCover: AlbumCover.parse(raw['allPhotosCover']),
      memberships: {
        for (final e in (raw['memberships'] as Map).entries)
          if (e.key is String && e.value is List)
            e.key as String: (e.value as List)
                .whereType<String>()
                .where(ids.contains)
                .toSet(),
      },
    );
  }
}

/// 仅撤销本次变化的关系；保留此后新增加的其他归属。
class AlbumChange {
  AlbumChange(AlbumsData before, AlbumsData after, Set<String> images)
    : before = {
        for (final id in images)
          if (!setEquals(before.ofImage(id), after.ofImage(id)))
            id: before.ofImage(id),
      },
      after = {
        for (final id in images)
          if (!setEquals(before.ofImage(id), after.ofImage(id)))
            id: after.ofImage(id),
      };
  final Map<String, Set<String>> before, after;
  int get count => before.length;
  AlbumsData undo(AlbumsData current, Set<String> liveImages) {
    final next = {...current.memberships};
    for (final id in before.keys.where(liveImages.contains)) {
      final added = after[id]!.difference(before[id]!);
      final removed = before[id]!.difference(after[id]!);
      final value = {...current.ofImage(id)}
        ..removeAll(added)
        ..addAll(removed.where(current.exists));
      if (value.isEmpty) {
        next.remove(id);
      } else {
        next[id] = value;
      }
    }
    return current.copyWith(memberships: next);
  }
}

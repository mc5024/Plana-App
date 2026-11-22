import 'package:flutter/foundation.dart' show listEquals, setEquals;
import '../../../l10n/l10n.dart';

String get allPhotosName => l10nNow.allAlbumsName;

/// 固定的「收藏」相册:和用户相册一样记在 memberships 里,但不在 [AlbumsData.albums]
/// 列表中,不能改名、删除,也不能设为保存相册;封面是固定的图标。
const favoritesId = 'favorites';
String get favoritesName => l10nNow.favorites;

/// 相册墙末尾的「回收站」:不是相册,只在图库面板里当一本来浏览,
/// 图来自 `GalleryState.trash`。
const trashId = 'trash';
String get trashName => l10nNow.trashName;
bool validGalleryId(String id) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);

/// null 是明确的“仅全部作品”；参数本身为 null 才表示读取当前设置。
class GallerySaveTarget {
  const GallerySaveTarget.all() : albumId = null;
  const GallerySaveTarget.album(String id) : albumId = id;
  final String? albumId;
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
  factory AlbumsData({
    Iterable<GalleryAlbum> albums = const [],
    Map<String, Set<String>> memberships = const {},
    AlbumCover? allPhotosCover,
    Iterable<String> order = const [],
  }) {
    final list = albums.toList();
    final seq = _sequence(list, order);
    final byId = {for (final a in list) a.id: a};
    return AlbumsData._(
      [for (final id in seq) ?byId[id]],
      memberships,
      allPhotosCover,
      seq,
    );
  }

  AlbumsData._(
    List<GalleryAlbum> albums,
    Map<String, Set<String>> memberships,
    this.allPhotosCover,
    List<String> order,
  ) : albums = List.unmodifiable(albums),
      order = List.unmodifiable(order),
      memberships = Map.unmodifiable({
        for (final e in memberships.entries)
          e.key: Set<String>.unmodifiable(e.value),
      });

  /// 用户相册,按 [order] 里的先后。
  final List<GalleryAlbum> albums;

  /// 相册墙上「全部相册」之后的顺序:收藏、回收站和每本用户相册各一次。
  final List<String> order;
  final Map<String, Set<String>> memberships;
  final AlbumCover? allPhotosCover;

  /// [raw] 里认不得的、重复的丢掉;收藏缺了放最前,回收站缺了放最后;
  /// 没排过的用户相册(新建的)插在第一本用户相册前,一本都没有就跟在收藏后。
  static List<String> _sequence(
    List<GalleryAlbum> albums,
    Iterable<String> raw,
  ) {
    final own = {for (final a in albums) a.id};
    final seen = <String>{};
    final seq = [
      for (final id in raw)
        if ((id == favoritesId || id == trashId || own.contains(id)) &&
            seen.add(id))
          id,
    ];
    if (!seen.contains(favoritesId)) seq.insert(0, favoritesId);
    if (!seen.contains(trashId)) seq.add(trashId);
    final fresh = [
      for (final a in albums)
        if (!seen.contains(a.id)) a.id,
    ];
    final first = seq.indexWhere(own.contains);
    seq.insertAll(first < 0 ? seq.indexOf(favoritesId) + 1 : first, fresh);
    return seq;
  }

  GalleryAlbum? album(String? id) =>
      albums.where((a) => a.id == id).firstOrNull;
  bool exists(String? id) =>
      id == null || id == favoritesId || album(id) != null;
  String name(String? id) =>
      id == favoritesId ? favoritesName : album(id)?.name ?? allPhotosName;
  bool contains(String? albumId, String imageId) =>
      albumId == null ||
      (exists(albumId) && (memberships[imageId]?.contains(albumId) ?? false));
  bool isFavorite(String imageId) => contains(favoritesId, imageId);
  Set<String> ofImage(String imageId) => memberships[imageId] ?? const {};
  AlbumCover? cover(String? id) =>
      id == null ? allPhotosCover : album(id)?.cover;

  AlbumsData copyWith({
    Iterable<GalleryAlbum>? albums,
    Map<String, Set<String>>? memberships,
    AlbumCover? allPhotosCover,
    bool clearAllCover = false,
    Iterable<String>? order,
  }) => AlbumsData(
    albums: albums ?? this.albums,
    memberships: memberships ?? this.memberships,
    allPhotosCover: clearAllCover
        ? null
        : allPhotosCover ?? this.allPhotosCover,
    order: order ?? this.order,
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
    // 都不在任何相册里:返回自身,存储那边就不重写
    if (!ids.any(memberships.containsKey) &&
        !removed(allPhotosCover) &&
        !albums.any((a) => removed(a.cover))) {
      return this;
    }
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

  /// 相册墙改按 [order] 排;顺序没变返回自身。
  AlbumsData reorder(List<String> order) {
    final next = copyWith(order: order);
    return listEquals(next.order, this.order) ? this : next;
  }

  /// 收藏 / 取消收藏。
  AlbumsData favorite(Set<String> imageIds, bool on) => on
      ? organize(imageIds, {favoritesId})
      : organize(imageIds, const {}, sources: {favoritesId});

  /// sources=null 表示添加；移动仅处理属于明确来源的图片。
  AlbumsData organize(
    Set<String> imageIds,
    Set<String> targets, {
    Set<String>? sources,
  }) {
    if (targets.any((id) => !exists(id)) ||
        sources?.any((id) => !exists(id)) == true) {
      throw StateError(l10nNow.galleryGone);
    }
    if (sources != null &&
        (sources.isEmpty || sources.intersection(targets).isNotEmpty)) {
      throw StateError(l10nNow.chooseDifferentAlbums);
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
    'order': order,
  };

  factory AlbumsData.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['v'] != 1 ||
        raw['albums'] is! List ||
        raw['memberships'] is! Map) {
      throw const FormatException('图库数据格式无效');
    }
    final albums = <GalleryAlbum>[];
    final ids = <String>{favoritesId};
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
      order: raw['order'] is List
          ? (raw['order'] as List).whereType<String>()
          : const [],
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

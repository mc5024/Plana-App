import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/store/ui_prefs.dart';
import '../../generate/generation_controller.dart';
import '../gallery_state.dart';
import '../models.dart';
import 'album_models.dart';
import '../../../l10n/l10n.dart';

final albumsProvider = NotifierProvider<AlbumsNotifier, AlbumsData>(
  AlbumsNotifier.new,
);

/// 记下的相册 id → 实际生效的那本:空、已删除、「收藏」都按全部相册算。
/// 「收藏」只在网格面板里看,不作胶片条的浏览范围,也不作保存相册。
String? _scopeOf(AlbumsData albums, String id) =>
    id.isEmpty || id == favoritesId || !albums.exists(id) ? null : id;

final galleryBrowseAlbumProvider = Provider<String?>(
  (ref) => _scopeOf(
    ref.watch(albumsProvider),
    ref.watch(uiPrefsProvider).galleryBrowseAlbum,
  ),
);

final gallerySaveTargetProvider = Provider<GallerySaveTarget>((ref) {
  final id = _scopeOf(
    ref.watch(albumsProvider),
    ref.watch(uiPrefsProvider).gallerySaveAlbum,
  );
  return id == null
      ? const GallerySaveTarget.all()
      : GallerySaveTarget.album(id);
});

/// 相册卡的封面:长按设过、而且还在这本里的那张;否则是最新一张。
ResultImage? albumCoverOf(
  AlbumsData albums,
  String? id,
  List<ResultImage> items,
) {
  final pinned = albums.cover(id)?.sourceImageId;
  return items.where((r) => r.id == pinned).firstOrNull ?? items.firstOrNull;
}

/// 当前浏览范围里的图。只跟着结果列表 / 范围 / 相册变,换选中不重算,
/// 列表对象保持不变(胶片条按对象缓存排布)。
final _galleryScopeImagesProvider = Provider<List<ResultImage>>((ref) {
  final results = ref.watch(galleryProvider.select((s) => s.results));
  final scope = ref.watch(galleryBrowseAlbumProvider);
  if (scope == null) return results;
  final albums = ref.watch(albumsProvider);
  return results.where((r) => albums.contains(scope, r.id)).toList();
});

/// 全量结果留在 galleryProvider；这里只派生浏览集合。
final galleryViewProvider = Provider<GalleryState>((ref) {
  final selectedId = ref.watch(galleryProvider.select((s) => s.selectedId));
  final images = ref.watch(_galleryScopeImagesProvider);
  final id = images.any((r) => r.id == selectedId)
      ? selectedId
      : images.firstOrNull?.id;
  return GalleryState(results: images, selectedId: id);
});

class GalleryResultPreview {
  const GalleryResultPreview(this.imageId, this.target);
  final String imageId;
  final GallerySaveTarget target;
}

final galleryResultPreviewProvider =
    NotifierProvider<GalleryResultPreviewNotifier, GalleryResultPreview?>(
      GalleryResultPreviewNotifier.new,
    );

/// 后台结果的轻提示；点击查看才打开临时预览，不自动切库。
final gallerySavedNoticeProvider =
    NotifierProvider<GalleryResultPreviewNotifier, GalleryResultPreview?>(
      GalleryResultPreviewNotifier.new,
    );

class GalleryResultPreviewNotifier extends Notifier<GalleryResultPreview?> {
  @override
  GalleryResultPreview? build() => null;
  void show(String id, GallerySaveTarget target) =>
      state = GalleryResultPreview(id, target);
  void clear() => state = null;
}

class AlbumsNotifier extends Notifier<AlbumsData> {
  final _lastSelected = <String, String>{};

  /// 刚设过的保存相册:网格面板下次打开直接进这本,之后照常按它自己的记忆。
  ({String? id})? _gridLanding;
  @override
  AlbumsData build() => ref.watch(appStoresProvider).albums.data;
  Set<String> get _live => {
    for (final r in ref.read(galleryProvider).results) r.id,
  };

  Future<void> _edit(
    AlbumsData Function(AlbumsData) change, {
    bool reset = false,
  }) async {
    final store = ref.read(appStoresProvider).albums;
    await store.update(change, reset: reset);
    if (ref.mounted) state = store.data;
  }

  void _validateName(String name, {String? except}) {
    if (name.isEmpty || name.characters.length > 40) {
      throw StateError(l10nNow.albumNameInvalid);
    }
    if (name == allPhotosName ||
        name == favoritesName ||
        name == trashName ||
        state.albums.any((a) => a.id != except && a.name == name)) {
      throw StateError(l10nNow.albumNameExists);
    }
  }

  Future<String> create(String name) async {
    name = name.trim();
    _validateName(name);
    final id = ref.read(appStoresProvider).albums.newId();
    await _edit((d) {
      if (d.albums.any((a) => a.name == name)) {
        throw StateError(l10nNow.albumNameExists);
      }
      return d.copyWith(
        albums: [
          GalleryAlbum(
            id: id,
            name: name,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          ...d.albums,
        ],
      );
    });
    return id;
  }

  Future<void> rename(String id, String name) async {
    if (id == favoritesId) {
      throw StateError(l10nNow.cantRenameFav(favoritesName));
    }
    name = name.trim();
    _validateName(name, except: id);
    await _edit((d) {
      if (!d.exists(id)) throw StateError(l10nNow.albumDeleted);
      if (d.albums.any((a) => a.id != id && a.name == name)) {
        throw StateError(l10nNow.albumNameExists);
      }
      return d.copyWith(
        albums: [
          for (final a in d.albums) a.id == id ? a.copyWith(name: name) : a,
        ],
      );
    });
  }

  Future<void> delete(String id) async {
    if (id == favoritesId) {
      throw StateError(l10nNow.cantDeleteFav(favoritesName));
    }
    await _edit((d) => d.deleteAlbum(id));
    if (!ref.mounted) return;
    final prefs = ref.read(uiPrefsProvider);
    if (prefs.galleryBrowseAlbum == id) browse(null);
    if (prefs.gallerySaveAlbum == id) {
      ref
          .read(uiPrefsProvider.notifier)
          .patch((p) => p.copyWith(gallerySaveAlbum: ''));
    }
    _lastSelected.remove(id);
  }

  Future<void> reorder(List<String> order) => _edit((d) => d.reorder(order));

  void browse(
    String? id, {
    bool alsoSave = false,
    bool keepGeneration = false,
  }) {
    if (id == favoritesId) {
      throw StateError(l10nNow.cantBrowseFav(favoritesName));
    }
    if (!state.exists(id)) throw StateError(l10nNow.albumDeleted);
    final old = _scopeOf(state, ref.read(uiPrefsProvider).galleryBrowseAlbum);
    final all = ref.read(galleryProvider);
    final oldImages = all.results.where((r) => state.contains(old, r.id));
    final selected = oldImages.any((r) => r.id == all.selectedId)
        ? all.selectedId
        : oldImages.firstOrNull?.id;
    if (selected != null) _lastSelected[old ?? ''] = selected;
    final images = ref
        .read(galleryProvider)
        .results
        .where((r) => state.contains(id, r.id));
    final candidate = selected != null && state.contains(id, selected)
        ? selected
        : _lastSelected[id ?? ''];
    final next = images.any((r) => r.id == candidate)
        ? candidate
        : images.firstOrNull?.id;
    if (!keepGeneration) ref.read(generationProvider.notifier).select(null);
    ref.read(galleryResultPreviewProvider.notifier).clear();
    ref
        .read(uiPrefsProvider.notifier)
        .patch(
          (p) => p.copyWith(
            galleryBrowseAlbum: id ?? '',
            gallerySaveAlbum: alsoSave ? id ?? '' : null,
          ),
        );
    ref.read(galleryProvider.notifier).select(next);
    if (alsoSave) _gridLanding = (id: id);
  }

  void setSave(String? id) {
    if (id == favoritesId) throw StateError(l10nNow.cantSaveFav(favoritesName));
    if (!state.exists(id)) throw StateError(l10nNow.albumDeleted);
    browse(id, alsoSave: true, keepGeneration: true);
  }

  /// 长按图片「设为封面」:只记下是哪一张(key 只是编号,不另存裁剪图),
  /// 展示时按 sourceImageId 取原图。[imageId] 为 null 即取消,回到最新一张。
  Future<void> setCover(String? albumId, String? imageId) {
    if (imageId != null && !_live.contains(imageId)) {
      throw StateError(l10nNow.imageWasDeleted);
    }
    final key = ref.read(appStoresProvider).albums.newId();
    return _edit((d) {
      if (!d.exists(albumId)) throw StateError(l10nNow.albumDeleted);
      return d.withCover(
        albumId,
        imageId == null ? null : AlbumCover(key, sourceImageId: imageId),
      );
    });
  }

  /// 取一次即清。设完之后胶片条又被切去别的相册,就以后来那次为准,不再跳。
  ({String? id})? takeGridLanding() {
    final land = _gridLanding;
    _gridLanding = null;
    final scope = _scopeOf(state, ref.read(uiPrefsProvider).galleryBrowseAlbum);
    return land != null && land.id == scope ? land : null;
  }

  Future<AlbumChange> organize(
    Set<String> images,
    Set<String> targets, {
    Set<String>? sources,
  }) async {
    late AlbumChange change;
    await _edit((d) {
      final live = images.intersection(_live);
      final next = d.organize(live, targets, sources: sources);
      change = AlbumChange(d, next, live);
      return next;
    });
    return change;
  }

  Future<void> setFavorite(String imageId, bool on) async {
    if (!_live.contains(imageId)) throw StateError(l10nNow.imageWasDeleted);
    await _edit((d) => d.favorite({imageId}, on));
  }

  Future<void> undo(AlbumChange change) => _edit((d) => change.undo(d, _live));

  /// 删图时清掉它的相册归属。相册数据读不出来(只读)时不清:内存里本来就是
  /// 空的,等读得出来那次载入会按现存图片清掉悬空的引用。
  Future<void> removeImages(Set<String> ids) async {
    if (ref.read(appStoresProvider).albums.readOnly) return;
    await _edit((d) => d.removeImages(ids));
  }

  Future<void> clearAll() async {
    await _edit((_) => AlbumsData(), reset: true);
    if (!ref.mounted) return;
    _lastSelected.clear();
    ref.read(galleryResultPreviewProvider.notifier).clear();
    ref
        .read(uiPrefsProvider.notifier)
        .patch((p) => p.copyWith(galleryBrowseAlbum: '', gallerySaveAlbum: ''));
  }
}

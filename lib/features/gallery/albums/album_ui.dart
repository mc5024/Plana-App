import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/image_ops.dart';
import '../../../core/util/image_pick.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../../inpaint/inpaint_overlay.dart' show inpaintSessionProvider;
import '../gallery_date_filter.dart';
import '../gallery_search.dart';
import '../gallery_state.dart';
import '../models.dart';
import '../widgets/gallery_date_sheet.dart';
import '../widgets/result_thumb.dart';
import 'album_models.dart';
import 'album_state.dart';

void albumError(BuildContext context, Object error) => hintSnack(
  context,
  error.toString().replaceFirst('Bad state: ', ''),
  icon: Icons.error_outline,
);

Future<void> showAlbumLibrary(BuildContext context, {bool saveOnly = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: _AlbumLibrary(saveOnly: saveOnly),
      ),
    );

class GallerySaveTargetRow extends ConsumerWidget {
  const GallerySaveTargetRow({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(gallerySaveTargetProvider);
    final label = ref.watch(albumsProvider).name(target.albumId);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size(0, compact ? 36 : 40),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => showAlbumLibrary(context, saveOnly: true),
        icon: const Icon(Icons.drive_file_move_outline, size: 17),
        label: Text(
          '${compact ? '新图' : '新图保存到'}：$label ▾',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class GalleryContextBar extends ConsumerWidget {
  const GalleryContextBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(galleryBrowseAlbumProvider);
    final target = ref.watch(gallerySaveTargetProvider);
    final albums = ref.watch(albumsProvider);
    return Material(
      // 与胶片条共用底色，让图库选择成为缩略图区的一部分。
      color: context.scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // 按内容收紧，最长各占半行；只省略图库名，保留用途和下拉入口。
        child: Row(
          children: [
            Flexible(
              child: _GalleryContextPill(
                label: '浏览',
                albumName: albums.name(scope),
                semanticLabel: '浏览图库：${albums.name(scope)}',
                icon: Icons.photo_library_outlined,
                onPressed: () => showAlbumLibrary(context),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: _GalleryContextPill(
                label: '新图',
                albumName: albums.name(target.albumId),
                semanticLabel: '新图保存到：${albums.name(target.albumId)}',
                icon: Icons.drive_file_move_outline,
                onPressed: () => showAlbumLibrary(context, saveOnly: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryContextPill extends StatelessWidget {
  const _GalleryContextPill({
    required this.label,
    required this.albumName,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String albumName;
  final String semanticLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          // 视觉上是小胶囊，触摸范围仍保留 48dp。
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          shape: const StadiumBorder(),
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: context.texts.bodySmall,
        ),
        onPressed: onPressed,
        child: Semantics(
          label: semanticLabel,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 5),
              Text(label),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  albumName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> showAlbumName(BuildContext context, {GalleryAlbum? album}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _AlbumNameDialog(album: album),
    );

class _AlbumNameDialog extends ConsumerStatefulWidget {
  const _AlbumNameDialog({this.album});
  final GalleryAlbum? album;
  @override
  ConsumerState<_AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends ConsumerState<_AlbumNameDialog> {
  late final _name = TextEditingController(text: widget.album?.name);
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = ref.read(albumsProvider.notifier);
      final id = widget.album?.id;
      final result = id ?? await n.create(_name.text);
      if (id != null) await n.rename(id, _name.text);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.album == null ? '新建图库' : '重命名图库'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 40,
      enabled: !_busy,
      decoration: InputDecoration(labelText: '图库名称', errorText: _error),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? '保存中…' : '保存'),
      ),
    ],
  );
}

class AlbumCoverImage extends ConsumerWidget {
  const AlbumCoverImage({super.key, this.albumId});
  final String? albumId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(albumsProvider);
    final all = ref.watch(galleryProvider).results;
    final cover = data.cover(albumId);
    final valid =
        cover != null &&
        (cover.sourceImageId == null ||
            all.any((r) => r.id == cover.sourceImageId));
    final bytes = valid ? ref.watch(albumCoverProvider(cover.key)).value : null;
    final first = all.where((r) => data.contains(albumId, r.id)).firstOrNull;
    return LayoutBuilder(
      builder: (context, size) {
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: size.maxWidth,
              height: size.maxHeight,
              fit: BoxFit.cover,
            ),
          );
        }
        if (first != null) {
          return ResultThumb(
            result: first,
            width: size.maxWidth,
            height: size.maxHeight,
            radius: 12,
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(
              Icons.photo_library_outlined,
              size: 40,
              color: context.scheme.outline,
            ),
          ),
        );
      },
    );
  }
}

class _AlbumLibrary extends ConsumerStatefulWidget {
  const _AlbumLibrary({required this.saveOnly});
  final bool saveOnly;
  @override
  ConsumerState<_AlbumLibrary> createState() => _AlbumLibraryState();
}

class _AlbumLibraryState extends ConsumerState<_AlbumLibrary> {
  bool _preview = false, _alsoSave = false;
  String? _id;
  Future<void> _create() async {
    final id = await showAlbumName(context);
    if (id != null && mounted) {
      setState(() {
        _id = id;
        _preview = true;
      });
    }
  }

  Future<void> _menu(String? id, String action) async {
    final data = ref.read(albumsProvider);
    if (action == 'name') {
      await showAlbumName(context, album: data.album(id));
      return;
    }
    if (action == 'cover') {
      await _setCover(id);
      return;
    }
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${data.name(id)}」？'),
        content: const Text('只删除这个图库，图片仍保存在全部作品和其他所属图库中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除图库'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ref.read(albumsProvider.notifier).delete(id);
    } catch (e) {
      if (mounted) albumError(context, e);
    }
    if (mounted && _id == id) {
      setState(() {
        _preview = false;
        _id = null;
      });
    }
  }

  Future<void> _setCover(String? id) async {
    final hasImages = ref
        .read(galleryProvider)
        .results
        .any((r) => ref.read(albumsProvider).contains(id, r.id));
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('从本图库选择'),
              subtitle: hasImages ? null : const Text('图库还没有图片'),
              enabled: hasImages,
              onTap: () => Navigator.pop(context, 'current'),
            ),
            ListTile(
              title: const Text('从全部作品选择'),
              onTap: () => Navigator.pop(context, 'all'),
            ),
            ListTile(
              title: const Text('从手机相册选择'),
              onTap: () => Navigator.pop(context, 'device'),
            ),
            ListTile(
              title: const Text('恢复自动封面'),
              onTap: () => Navigator.pop(context, 'auto'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      if (source == 'auto') {
        await ref.read(albumsProvider.notifier).setCover(id, null);
        return;
      }
      Uint8List? bytes;
      String? imageId;
      if (source == 'device') {
        bytes = (await pickImageFile(context))?.bytes;
      } else {
        final image = await pickAlbumPhoto(
          context,
          albumId: source == 'current' ? id : null,
        );
        if (image == null || !mounted) return;
        imageId = image.id;
        bytes =
            image.bytes ??
            await ref.read(appStoresProvider).gallery.readImage(image.id);
      }
      if (bytes == null || !mounted) return;
      final png = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => _CoverCrop(bytes: bytes!)),
      );
      if (png == null || !mounted) return;
      await ref
          .read(albumsProvider.notifier)
          .setCover(id, png, sourceImageId: imageId);
    } catch (e) {
      if (mounted) albumError(context, e);
    }
  }

  void _load() {
    try {
      final notifier = ref.read(albumsProvider.notifier);
      if (widget.saveOnly) {
        notifier.setSave(_id);
      } else {
        notifier.browse(_id, alsoSave: _alsoSave);
      }
      Navigator.pop(context);
    } catch (e) {
      albumError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(albumsProvider);
    final all = ref.watch(galleryProvider).results;
    final browse = ref.watch(galleryBrowseAlbumProvider);
    final save = ref.watch(gallerySaveTargetProvider).albumId;
    final editing = ref.watch(inpaintSessionProvider) != null;
    final store = ref.watch(appStoresProvider).albums;
    final valid = data.exists(_id);
    final photos = all.where((r) => data.contains(_id, r.id)).toList();
    return PopScope(
      canPop: !_preview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _preview = false);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                if (_preview)
                  IconButton(
                    onPressed: () => setState(() => _preview = false),
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    _preview
                        ? data.name(_id)
                        : widget.saveOnly
                        ? '新图保存到'
                        : '选择图库',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: store.readOnly ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('新建'),
                ),
              ],
            ),
          ),
          if (store.warning != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(store.warning!, style: context.texts.bodySmall),
            ),
          Expanded(
            child: _preview
                ? photos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.photo_library_outlined,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(valid ? '这个图库还没有照片' : '图库已被删除'),
                              if (_id != null && valid)
                                TextButton(
                                  onPressed: () async {
                                    final photo = await pickAlbumPhoto(context);
                                    if (photo == null ||
                                        !mounted ||
                                        !context.mounted) {
                                      return;
                                    }
                                    try {
                                      await ref
                                          .read(albumsProvider.notifier)
                                          .organize({photo.id}, {_id!});
                                    } catch (e) {
                                      if (mounted && context.mounted) {
                                        albumError(context, e);
                                      }
                                    }
                                  },
                                  child: const Text('从全部作品添加'),
                                ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          key: PageStorageKey('album_preview/$_id'),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: photos.length,
                          itemBuilder: (context, i) => InkWell(
                            onTap: () => showAlbumPhoto(context, photos[i]),
                            child: LayoutBuilder(
                              builder: (_, size) => ResultThumb(
                                result: photos[i],
                                width: size.maxWidth,
                                height: size.maxHeight,
                              ),
                            ),
                          ),
                        )
                : LayoutBuilder(
                    builder: (context, size) {
                      final columns = (size.maxWidth / 260).ceil().clamp(1, 6);
                      final coverWidth =
                          (size.maxWidth - 32 - 14 * (columns - 1)) / columns;
                      final detailsHeight =
                          48 + MediaQuery.textScalerOf(context).scale(36);
                      return GridView.builder(
                        key: const PageStorageKey('album_library_cards'),
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: coverWidth + detailsHeight,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: data.albums.length + 1,
                        itemBuilder: (context, i) {
                          final id = i == 0 ? null : data.albums[i - 1].id;
                          final count = all
                              .where((r) => data.contains(id, r.id))
                              .length;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: coverWidth,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() {
                                    _id = id;
                                    _preview = true;
                                    _alsoSave = false;
                                  }),
                                  child: AlbumCoverImage(albumId: id),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      data.name(id),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.texts.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    enabled: !store.readOnly,
                                    onSelected: (a) => _menu(id, a),
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'cover',
                                        child: Text('更换封面'),
                                      ),
                                      if (id != null) ...[
                                        const PopupMenuItem(
                                          value: 'name',
                                          child: Text('重命名'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除图库'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                '$count 张${browse == id ? ' · 正在浏览' : ''}${save == id ? ' · 新图保存' : ''}',
                                maxLines: 2,
                                style: context.texts.bodySmall?.copyWith(
                                  color: context.scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
          if (_preview)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.saveOnly)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('新图也保存到这里'),
                        value: _alsoSave,
                        onChanged: (v) =>
                            setState(() => _alsoSave = v ?? false),
                      ),
                    if (editing && !widget.saveOnly) const Text('结束编辑后可切换图库'),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: valid && (!editing || widget.saveOnly)
                            ? _load
                            : null,
                        icon: Icon(
                          widget.saveOnly
                              ? Icons.drive_file_move_outline
                              : Icons.photo_library_outlined,
                        ),
                        label: Text(widget.saveOnly ? '新图保存到这里' : '加载图库'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<ResultImage?> pickAlbumPhoto(BuildContext context, {String? albumId}) =>
    Navigator.of(context).push<ResultImage>(
      MaterialPageRoute(builder: (_) => _AlbumPhotoPicker(albumId: albumId)),
    );

class _AlbumPhotoPicker extends ConsumerStatefulWidget {
  const _AlbumPhotoPicker({this.albumId});
  final String? albumId;
  @override
  ConsumerState<_AlbumPhotoPicker> createState() => _AlbumPhotoPickerState();
}

class _AlbumPhotoPickerState extends ConsumerState<_AlbumPhotoPicker> {
  String _query = '';
  GalleryDateFilter _date = const GalleryDateFilter.all();
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(albumsProvider);
    final search = ref.watch(gallerySearchProvider);
    final terms = searchTerms(_query);
    final now = DateTime.now();
    final photos = ref
        .watch(galleryProvider)
        .results
        .where(
          (r) =>
              data.contains(widget.albumId, r.id) &&
              _date.matches(r.createdAt, now) &&
              (terms.isEmpty ||
                  searchMatch(search.byId[r.id]?.text ?? '', terms)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('从${data.name(widget.albumId)}选择')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索提示词',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(_date.label(now)),
                  onPressed: () async {
                    final d = await showGalleryDateFilter(context, _date);
                    if (d != null && mounted) setState(() => _date = d);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: photos.isEmpty
                ? const Center(child: Text('没有符合条件的照片'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemBuilder: (context, i) => InkWell(
                      onTap: () => Navigator.pop(context, photos[i]),
                      child: LayoutBuilder(
                        builder: (_, size) => ResultThumb(
                          result: photos[i],
                          width: size.maxWidth,
                          height: size.maxHeight,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAlbumPhoto(BuildContext context, ResultImage photo) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _AlbumPhotoPreview(photo: photo)),
    );

class _AlbumPhotoPreview extends ConsumerWidget {
  const _AlbumPhotoPreview({required this.photo});
  final ResultImage photo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = photo.bytes == null
        ? ref.watch(galleryImageProvider(photo.id))
        : null;
    final bytes = photo.bytes ?? loaded?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('图片预览')),
      body: Center(
        child: bytes == null
            ? loaded?.isLoading == true
                  ? const CircularProgressIndicator()
                  : const Text('这张图片暂时无法读取')
            : InteractiveViewer(maxScale: 8, child: Image.memory(bytes)),
      ),
    );
  }
}

class _CoverCrop extends StatefulWidget {
  const _CoverCrop({required this.bytes});
  final Uint8List bytes;
  @override
  State<_CoverCrop> createState() => _CoverCropState();
}

class _CoverCropState extends State<_CoverCrop> {
  double _x = 0, _y = 0;
  bool _busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('调整封面')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                widget.bytes,
                fit: BoxFit.cover,
                alignment: Alignment(_x, _y),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('水平位置'),
          Slider(
            value: _x,
            min: -1,
            max: 1,
            onChanged: _busy ? null : (v) => setState(() => _x = v),
          ),
          const Text('垂直位置'),
          Slider(
            value: _y,
            min: -1,
            max: 1,
            onChanged: _busy ? null : (v) => setState(() => _y = v),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      final png = await coverResizePng(
                        widget.bytes,
                        512,
                        512,
                        keepAlpha: true,
                        alignX: _x,
                        alignY: _y,
                      );
                      if (context.mounted) Navigator.pop(context, png);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() => _busy = false);
                        albumError(context, e);
                      }
                    }
                  },
            child: Text(_busy ? '保存中…' : '使用此封面'),
          ),
        ],
      ),
    ),
  );
}

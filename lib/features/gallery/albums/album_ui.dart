import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../gallery_state.dart';
import '../widgets/stack_card.dart';
import 'album_models.dart';
import 'album_state.dart';
import '../../../l10n/l10n.dart';

void albumError(BuildContext context, Object error) => hintSnack(
  context,
  error.toString().replaceFirst('Bad state: ', ''),
  icon: Icons.error_outline,
);

/// 收藏、回收站的固定封面图标;其余相册取图做封面,返回 null。
IconData? albumCoverIcon(String? id) => switch (id) {
  favoritesId => Icons.favorite_border,
  trashId => Icons.delete_outline,
  _ => null,
};

/// 收藏 / 取消收藏这一张。取消时给撤销:在「收藏」里看着的话,图会随即离开。
Future<void> toggleFavorite(BuildContext context, String imageId) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final albums = container.read(albumsProvider.notifier);
  final on = !container.read(albumsProvider).isFavorite(imageId);
  try {
    await albums.setFavorite(imageId, on);
  } catch (e) {
    if (context.mounted) albumError(context, e);
    return;
  }
  if (!context.mounted) return;
  hintSnack(
    context,
    on ? context.l10n.favorited : context.l10n.unfavoritedSnack,
    icon: on ? Icons.favorite : Icons.favorite_border,
    actionLabel: on ? null : context.l10n.undo,
    onAction: on
        ? null
        : () => unawaited(
            albums.setFavorite(imageId, true).catchError((Object _) {}),
          ),
  );
}

Future<void> showGallerySaveAlbumPicker(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final pick = await _pickAlbum(
    context,
    title: context.l10n.saveTo,
    keyPrefix: 'save-album-choice',
    includeFavorites: false,
    checked: (id: container.read(gallerySaveTargetProvider).albumId),
  );
  if (pick == null) return;
  try {
    container.read(albumsProvider.notifier).setSave(pick.id);
  } catch (e) {
    if (context.mounted) albumError(context, e);
  }
}

/// 选一个相册来浏览(空相册页的「选择相册」):点一张就切过去。
Future<void> showAlbumBrowsePicker(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final pick = await _pickAlbum(
    context,
    title: context.l10n.chooseAlbum,
    keyPrefix: 'browse-album-choice',
    includeFavorites: false,
    checked: (id: container.read(galleryBrowseAlbumProvider)),
  );
  if (pick == null) return;
  try {
    container.read(albumsProvider.notifier).browse(pick.id);
  } catch (e) {
    if (context.mounted) albumError(context, e);
  }
}

/// 多选「移动到」。在某个相册里:移到别的相册,选「全部相册」即移出本相册;
/// 在全部相册里:放进所选相册,原来所在的相册不动。没选返回 null。
Future<({String? id})?> showAlbumMovePicker(
  BuildContext context, {
  String? sourceAlbum,
}) => _pickAlbum(
  context,
  title: context.l10n.moveTo,
  keyPrefix: 'move-album-choice',
  exclude: sourceAlbum,
  includeAll: sourceAlbum != null,
);

Future<({String? id})?> _pickAlbum(
  BuildContext context, {
  required String title,
  required String keyPrefix,
  String? exclude,
  bool includeAll = true,
  bool includeFavorites = true,
  ({String? id})? checked,
}) => showModalBottomSheet<({String? id})>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _AlbumChoiceSheet(
    title: title,
    keyPrefix: keyPrefix,
    exclude: exclude,
    includeAll: includeAll,
    includeFavorites: includeFavorites,
    checked: checked,
  ),
);

/// 选一个相册的面板,「保存到」「选择相册」「移动到」共用。点一本即选中并关闭,
/// 返回 `(id: …)`(null 是全部相册);「新建」建完直接选它。
/// 面板只管选,选完由调用方去做:连点两下也只会关一次。
class _AlbumChoiceSheet extends ConsumerWidget {
  const _AlbumChoiceSheet({
    required this.title,
    required this.keyPrefix,
    this.exclude,
    this.includeAll = true,
    this.includeFavorites = true,
    this.checked,
  });

  final String title;
  final String keyPrefix;

  /// 不列出的相册(移动时的来源相册)。
  final String? exclude;
  final bool includeAll;
  final bool includeFavorites;

  /// 打勾的那一项;null = 不打勾。
  final ({String? id})? checked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final photos = ref.watch(galleryProvider).results;
    final cols = ref.watch(uiPrefsProvider).galleryColumns;
    // 照相册墙的顺序,回收站不在其列
    final ids = <String?>[
      if (includeAll) null,
      for (final id in albums.order)
        if (id != trashId &&
            id != exclude &&
            (includeFavorites || id != favoritesId))
          id,
    ];
    final checked = this.checked;
    // 标题行、按钮、网格照相册首页(gallery_grid_sheet)那一页来,当前那本另外
    // 打勾。高度跟着内容走,相册多了才封顶在和图库同样的 82%。
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: ref.watch(appStoresProvider).albums.readOnly
                        ? null
                        : () async {
                            final id = await showAlbumName(context);
                            if (id != null && context.mounted) {
                              Navigator.pop(context, (id: id));
                            }
                          },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.l10n.newLabel),
                  ),
                ],
              ),
            ),
          ),
          // 与相册首页同一种封面卡、同样的列数(跟着那边捏合调的走)。
          Flexible(
            child: LayoutBuilder(
              builder: (context, box) {
                const pad = 12.0, gap = 6.0;
                final cellW =
                    (box.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
                final textH = 44 * MediaQuery.textScalerOf(context).scale(1);
                // 相册少时也留两行半,和图库面板的最低高度一样
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: GalleryStackCard.wallMinHeight(
                      context,
                      box.maxWidth,
                      cols,
                    ),
                  ),
                  child: GridView.builder(
                    // 相册就那么几本,收缩包裹的开销可以忽略
                    shrinkWrap: true,
                    // 面板贴着屏幕底,最后一行要让开手势条
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      0,
                      pad,
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: gap,
                      mainAxisExtent: cellW + textH,
                    ),
                    itemCount: ids.length,
                    itemBuilder: (context, index) {
                      final id = ids[index];
                      final items = [
                        for (final r in photos)
                          if (albums.contains(id, r.id)) r,
                      ];
                      final on = checked != null && checked.id == id;
                      return GalleryStackCard(
                        key: ValueKey('$keyPrefix-${id ?? 'all'}'),
                        group: (
                          key: id ?? '',
                          label: albums.name(id),
                          items: items,
                        ),
                        cover: albumCoverOf(albums, id, items),
                        coverIcon: albumCoverIcon(id),
                        // 当前那本:描边 + 左上角的勾,借多选的勾选圈来画;
                        // 其余几本不画空圈,免得看着像能多选
                        selecting: on,
                        picked: on,
                        stacked: false,
                        onTap: () => Navigator.pop(context, (id: id)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
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
  bool _saveNewImages = false;
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
      if (id == null && _saveNewImages) n.setSave(result);
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
    title: Text(
      widget.album == null ? context.l10n.newAlbum : context.l10n.renameAlbum,
    ),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: context.l10n.albumName,
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
        if (widget.album == null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.setAsSaveAlbum),
            value: _saveNewImages,
            onChanged: _busy
                ? null
                : (value) => setState(() => _saveNewImages = value ?? false),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? context.l10n.savingEllipsis : context.l10n.save),
      ),
    ],
  );
}

/// 从图库挑图的面板,别处要用图库里的图时用(AI 助手带图、灵感库封面)。
///
/// 先是相册封面墙(全部相册、收藏和各相册,同「选择相册」面板那一页),点一本进去是
/// 这本的图,左上角返回、系统返回键也回到封面墙。单选点一张就回;多选点一下勾上、
/// 再点取消,角上标第几张,挑满了其余压暗点不动,换相册接着挑不丢,「完成」一起交回。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../../../l10n/l10n.dart';
import '../albums/album_models.dart';
import '../albums/album_state.dart';
import '../albums/album_ui.dart';
import '../gallery_state.dart';
import '../models.dart';
import 'result_thumb.dart';
import 'stack_card.dart';

/// 挑中的图库条目 id,按点选顺序;关掉是空的。[max] 为 1 是单选。
Future<List<String>> showGalleryPickSheet(
  BuildContext context, {
  required String title,
  int max = 1,
}) async {
  final picked = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GalleryPickSheet(title: title, max: max),
  );
  return picked ?? const [];
}

class _GalleryPickSheet extends ConsumerStatefulWidget {
  const _GalleryPickSheet({required this.title, required this.max});

  final String title;
  final int max;

  @override
  ConsumerState<_GalleryPickSheet> createState() => _GalleryPickSheetState();
}

class _GalleryPickSheetState extends ConsumerState<_GalleryPickSheet> {
  /// 进了哪本;null = 在封面墙。全部相册是 `(id: null)`。
  ({String? id})? _album;
  final _picked = <String>[];

  bool get _multi => widget.max > 1;

  // 几何同相册首页 / 选相册面板:两侧 12、列距 6、行距 12
  static const _pad = 12.0;
  static const _gap = 6.0;

  void _tapImage(String id) {
    if (!_multi) {
      Navigator.pop(context, [id]);
      return;
    }
    setState(() {
      if (!_picked.remove(id)) {
        if (_picked.length >= widget.max) return;
        _picked.add(id);
      }
    });
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider);
    final album = _album;
    return PopScope(
      canPop: album == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _album = null);
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(album == null ? widget.title : albums.name(album.id)),
            Flexible(
              child: AnimatedSize(
                duration: Motion.medium,
                curve: Motion.emphasized,
                alignment: Alignment.topCenter,
                child: album == null
                    ? _wall(albums)
                    : _photos(albums, album.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(
    padding: EdgeInsets.fromLTRB(_album == null ? 20 : 4, 4, 12, 8),
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          if (_album != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => setState(() => _album = null),
              icon: const Icon(Icons.arrow_back),
            ),
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
          if (_multi)
            FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.pop(context, [..._picked]),
              child: Text(context.l10n.done),
            ),
        ],
      ),
    ),
  );

  /// 封面墙:全部相册、收藏,再是各相册;回收站不在其列。
  Widget _wall(AlbumsData albums) {
    final photos = ref.watch(galleryProvider).results;
    final cols = ref.watch(uiPrefsProvider).galleryColumns;
    final ids = <String?>[
      null,
      favoritesId,
      for (final a in albums.albums) a.id,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final cellW = (box.maxWidth - _pad * 2 - _gap * (cols - 1)) / cols;
        final textH = 44 * MediaQuery.textScalerOf(context).scale(1);
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: GalleryStackCard.wallMinHeight(
              context,
              box.maxWidth,
              cols,
            ),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              _pad,
              0,
              _pad,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: _gap,
              mainAxisExtent: cellW + textH,
            ),
            itemCount: ids.length,
            itemBuilder: (context, i) {
              final id = ids[i];
              final items = [
                for (final r in photos)
                  if (albums.contains(id, r.id)) r,
              ];
              return GalleryStackCard(
                key: ValueKey('pick-album-${id ?? 'all'}'),
                group: (key: id ?? '', label: albums.name(id), items: items),
                cover: albumCoverOf(albums, id, items),
                coverIcon: albumCoverIcon(id),
                selecting: false,
                picked: false,
                stacked: false,
                onTap: () => setState(() => _album = (id: id)),
              );
            },
          ),
        );
      },
    );
  }

  /// 一本相册里的图,新的在前。按内容长,最低两行半,封顶交给外面那层。
  Widget _photos(AlbumsData albums, String? id) {
    final photos = [
      for (final r in ref.watch(galleryProvider).results)
        if (albums.contains(id, r.id)) r,
    ];
    final cols = ref.watch(uiPrefsProvider).galleryColumns;
    final bottom = 16 + MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, box) {
        final minH = GalleryStackCard.wallMinHeight(
          context,
          box.maxWidth,
          cols,
        );
        if (photos.isEmpty) {
          return SizedBox(
            height: minH,
            child: Center(
              child: Text(
                context.l10n.albumNoImages,
                style: context.texts.bodyMedium!.copyWith(
                  color: context.scheme.outline,
                ),
              ),
            ),
          );
        }
        final cell = (box.maxWidth - _pad * 2 - _gap * (cols - 1)) / cols;
        final rows = (photos.length / cols).ceil();
        final gridH = rows * cell + (rows - 1) * _gap + bottom;
        final full = _picked.length >= widget.max;
        return SizedBox(
          height: gridH < minH ? minH : gridH,
          child: GridView.builder(
            key: PageStorageKey('pick-photos-${id ?? 'all'}'),
            padding: EdgeInsets.fromLTRB(_pad, 0, _pad, bottom),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final r = photos[i];
              final order = _picked.indexOf(r.id);
              return _PickThumb(
                result: r,
                order: _multi ? order : null,
                dim: _multi && full && order < 0,
                onTap: () => _tapImage(r.id),
              );
            },
          ),
        );
      },
    );
  }
}

/// 一张图。多选时左上角是勾选圆标(选上的写第几张),选上的描主题色边。
class _PickThumb extends StatelessWidget {
  const _PickThumb({
    required this.result,
    required this.order,
    required this.dim,
    required this.onTap,
  });

  final ResultImage result;

  /// 多选:第几个选上的(从 0 起),没选上 -1;单选是 null。
  final int? order;

  /// 挑满了,这张点不动。
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final order = this.order;
    final on = order != null && order >= 0;
    return GestureDetector(
      onTap: dim ? null : onTap,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            ResultThumb(
              result: result,
              width: c.maxWidth,
              height: c.maxHeight,
              radius: 10,
            ),
            if (dim)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            if (on)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.primary, width: 2.5),
                  ),
                ),
              ),
            if (order != null && !dim)
              Positioned(
                left: 5,
                top: 5,
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? scheme.primary
                        : Colors.black.withValues(alpha: .35),
                    border: on
                        ? null
                        : Border.all(
                            color: Colors.white.withValues(alpha: .85),
                            width: 1.5,
                          ),
                  ),
                  child: on
                      ? Text(
                          '${order + 1}',
                          style: context.texts.labelSmall!.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

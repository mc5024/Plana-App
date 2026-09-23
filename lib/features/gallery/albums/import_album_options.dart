import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/expand_body.dart';
import '../gallery_state.dart';
import 'album_models.dart';
import 'album_state.dart';

class ImportAlbumOptions extends ConsumerWidget {
  const ImportAlbumOptions({
    super.key,
    required this.origin,
    required this.choice,
    required this.onChanged,
  });
  final GalleryImportOrigin? origin;
  final ImportAlbumChoice choice;
  final ValueChanged<ImportAlbumChoice> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = origin;
    if (source == null) return const SizedBox.shrink();
    final data = ref.watch(albumsProvider);
    final exists = ref
        .watch(galleryProvider)
        .results
        .any((r) => r.id == source.imageId);
    final candidates = data.albums
        .where(
          (a) =>
              exists &&
              data.contains(a.id, source.imageId) &&
              (source.albumId == null || source.albumId == a.id),
        )
        .toList();
    final targets = <GallerySaveTarget>[
      if (exists && candidates.isEmpty && source.albumId == null)
        const GallerySaveTarget.all(),
      for (final a in candidates) GallerySaveTarget.album(a.id),
    ];
    final selected = choice.target;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: context.scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: Icon(
                Icons.photo_library_outlined,
                color: context.scheme.primary,
              ),
              title: const Text('切换到图片所属图库'),
              subtitle: Text(
                targets.isEmpty
                    ? '来源图库已变化，沿用当前图库'
                    : choice.enabled
                    ? '完成导入后生效'
                    : '未勾选，沿用当前图库',
              ),
              value: choice.enabled,
              onChanged: (v) => onChanged(
                v == true
                    ? ImportAlbumChoice(
                        enabled: true,
                        target: targets.length == 1 ? targets.first : null,
                      )
                    : const ImportAlbumChoice(),
              ),
            ),
            ExpandBody(
              expanded: choice.enabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final target in targets)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                        left: 28,
                        right: 14,
                      ),
                      title: Text(data.name(target.albumId)),
                      value:
                          selected != null &&
                          selected.albumId == target.albumId,
                      onChanged: (_) => onChanged(
                        ImportAlbumChoice(
                          enabled: true,
                          target: target,
                          alsoSave: choice.alsoSave,
                        ),
                      ),
                    ),
                  if (targets.length > 1 && selected == null)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('选择一个图库；未选定时沿用当前图库'),
                    ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    title: const Text('新图也保存到该图库'),
                    value: choice.alsoSave,
                    onChanged: selected == null
                        ? null
                        : (v) => onChanged(
                            ImportAlbumChoice(
                              enabled: true,
                              target: selected,
                              alsoSave: v ?? false,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

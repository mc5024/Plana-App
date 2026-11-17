/// 输入框左下角「带图」:先选从系统相册还是图库挑;图库那支是四列网格多选,
/// 点一下选上、再点取消,角上标第几张,挑满了其余压暗点不动。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../../../core/util/image_pick.dart';
import '../../gallery/gallery_state.dart'
    show galleryProvider, galleryThumbProvider;
import '../../generate/widgets/common.dart' show dropFocusSoon, hintSnack;
import '../../../l10n/l10n.dart';

enum AttachSource { photos, gallery }

/// 从哪儿挑(居中弹窗);关掉是 null。
Future<AttachSource?> showAttachSourceDialog(BuildContext context) async {
  final picked = await showDialog<AttachSource>(
    context: context,
    builder: (context) {
      Widget row(AttachSource s, IconData icon, String label) => ListTile(
        onTap: () => Navigator.pop(context, s),
        leading: Icon(icon, size: 21, color: context.scheme.primary),
        title: Text(
          label,
          style: context.texts.bodyLarge!.copyWith(fontWeight: FontWeight.w500),
        ),
      );
      return AlertDialog(
        title: Text(context.l10n.attachImage),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(
              AttachSource.photos,
              Icons.phone_android_outlined,
              context.l10n.systemAlbum,
            ),
            row(
              AttachSource.gallery,
              Icons.photo_library_outlined,
              context.l10n.gallery,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        ],
      );
    },
  );
  dropFocusSoon();
  return picked;
}

/// 从图库挑最多 [max] 张,按点选顺序读出原图;图库空着说一句,关掉是空的。
Future<List<PickedImage>> pickGalleryImages(
  BuildContext context,
  WidgetRef ref, {
  required int max,
}) async {
  if (ref.read(galleryProvider).results.isEmpty) {
    hintSnack(
      context,
      context.l10n.galleryNoImages,
      icon: Icons.photo_library_outlined,
    );
    return const [];
  }
  final ids = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => _GalleryPickSheet(max: max),
  );
  dropFocusSoon();
  final out = <PickedImage>[];
  for (final id in ids ?? const <String>[]) {
    final r = ref.read(galleryProvider).results.where((r) => r.id == id);
    final bytes =
        r.firstOrNull?.bytes ??
        await ref.read(appStoresProvider).gallery.readImage(id);
    if (bytes != null && bytes.isNotEmpty) out.add(PickedImage('image', bytes));
  }
  return out;
}

class _GalleryPickSheet extends ConsumerStatefulWidget {
  const _GalleryPickSheet({required this.max});

  final int max;

  @override
  ConsumerState<_GalleryPickSheet> createState() => _GalleryPickSheetState();
}

class _GalleryPickSheetState extends ConsumerState<_GalleryPickSheet> {
  final _picked = <String>[];

  static const _cols = 4;
  static const _gap = 6.0;
  static const _pad = 14.0;

  void _toggle(String id) {
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
    final scheme = context.scheme;
    final results = ref.watch(galleryProvider).results;
    final full = _picked.length >= widget.max;
    return Material(
      color: context.raisedFill(scheme.surfaceContainer),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, _pad, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.gallery,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.pop(context, [..._picked]),
                    child: Text(context.l10n.done),
                  ),
                ],
              ),
            ),
            // 按内容长:最低两行半,封顶交给外面那层
            Flexible(
              child: LayoutBuilder(
                builder: (context, box) {
                  final cell =
                      (box.maxWidth - _pad * 2 - _gap * (_cols - 1)) / _cols;
                  final rows = (results.length / _cols).ceil();
                  final grid = rows * cell + math.max(rows - 1, 0) * _gap;
                  final bottom = MediaQuery.viewPaddingOf(context).bottom + 12;
                  return SizedBox(
                    height: math.max(grid, cell * 2.5 + _gap * 2) + bottom,
                    child: GridView.builder(
                      padding: EdgeInsets.fromLTRB(_pad, 0, _pad, bottom),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _cols,
                            mainAxisSpacing: _gap,
                            crossAxisSpacing: _gap,
                          ),
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final id = results[i].id;
                        final order = _picked.indexOf(id);
                        return _PickCell(
                          id: id,
                          order: order,
                          dim: full && order < 0,
                          onTap: () => _toggle(id),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickCell extends ConsumerWidget {
  const _PickCell({
    required this.id,
    required this.order,
    required this.dim,
    required this.onTap,
  });

  final String id;

  /// 第几个选上的(从 0 起);没选上是 -1。
  final int order;

  /// 挑满了,这张点不动。
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final thumb = ref.watch(galleryThumbProvider(id)).value;
    final on = order >= 0;
    return GestureDetector(
      onTap: dim ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerHigh),
            if (thumb != null)
              Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true),
            if (dim) ColoredBox(color: scheme.surface.withValues(alpha: .6)),
            if (on)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.primary, width: 3),
                ),
              ),
            if (!dim)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? scheme.primary
                        : Colors.black.withValues(alpha: .25),
                    border: on
                        ? null
                        : Border.all(color: Colors.white, width: 1.5),
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

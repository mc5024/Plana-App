/// 输入框左下角「带图」:先选从系统相册还是图库挑;图库那支见 [showGalleryPicker]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/image_pick.dart';
import '../../gallery/gallery_state.dart' show galleryProvider;
import '../../gallery/widgets/gallery_grid_sheet.dart' show showGalleryPicker;
import '../../generate/widgets/common.dart' show dropFocusSoon, hintSnack;
import '../../../l10n/l10n.dart';

enum AttachSource { photos, gallery }

/// 从哪儿挑(居中弹窗);关掉是 null。[title] 缺省为「带图」。
Future<AttachSource?> showAttachSourceDialog(
  BuildContext context, {
  String? title,
}) async {
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
        title: Text(title ?? context.l10n.attachImage),
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
  final ids = await showGalleryPicker(context, max: max);
  dropFocusSoon();
  final out = <PickedImage>[];
  for (final id in ids) {
    final r = ref.read(galleryProvider).results.where((r) => r.id == id);
    final bytes =
        r.firstOrNull?.bytes ??
        await ref.read(appStoresProvider).gallery.readImage(id);
    if (bytes != null && bytes.isNotEmpty) out.add(PickedImage('image', bytes));
  }
  return out;
}

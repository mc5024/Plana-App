import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';

import 'models.dart';
import 'phone_image_date.dart';
import 'save_settings.dart';

/// 保存顺序独立于历史的展示/分组/勾选顺序。未知日期放最后；同一毫秒
/// 生成的图片按入库序号排列，批次共用 seed 也不会丢失或打乱。
List<ResultImage> oldestFirstForSave(Iterable<ResultImage> images) =>
    images.toList()..sort((a, b) {
      final aKnown = a.createdAt > 0;
      final bKnown = b.createdAt > 0;
      if (aKnown != bKnown) return aKnown ? -1 : 1;
      final time = aKnown ? a.createdAt.compareTo(b.createdAt) : 0;
      return time != 0
          ? time
          : _imageOrderKey(a.id).compareTo(_imageOrderKey(b.id));
    });

String _imageOrderKey(String id) {
  final generated = RegExp(r'^gen(\d+)$').firstMatch(id);
  if (generated != null) return 'gen${generated[1]!.padLeft(12, '0')}';
  return id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

/// 固定宽度的本地生成时间在种子号前，手机按名称升序也能按时间排列。
/// 包含入库 ID，避免同 seed / 同毫秒的不同图片撞名。不伪造未知时间。
String phoneGalleryImageName(ResultImage image) {
  var stamp = 'unknown';
  if (image.createdAt > 0) {
    final at = DateTime.fromMillisecondsSinceEpoch(image.createdAt);
    String pad(int value, [int width = 2]) =>
        value.toString().padLeft(width, '0');
    stamp =
        '${pad(at.year, 4)}${pad(at.month)}${pad(at.day)}_'
        '${pad(at.hour)}${pad(at.minute)}${pad(at.second)}_${pad(at.millisecond, 3)}';
  }
  return 'plana_${stamp}_${_imageOrderKey(image.id)}_${image.seed}';
}

/// 字节已经经过 processForSave；只补充生成日期，不修改像素及 PNG 提示词。
/// 日期写进 EXIF，保证系统重新扫描后仍保留。DATE_ADDED 由系统
/// 记录真实添加时刻。旧版 Android / 其他平台沿用 gal 的相册兼容路径。
/// 调用方先按原逻辑申请保存权限；写入异常直接交回，不能盲目重试而重复存图。
Future<int> saveProcessedImageToPhone(
  Uint8List bytes, {
  required ResultImage image,
  required SaveFormat format,
  String? album,
}) async {
  final name = phoneGalleryImageName(image);
  final dated = withPhoneCaptureDate(bytes, image.createdAt, format);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final sdk = int.tryParse(await PhotoManager.systemVersion()) ?? 0;
    if (sdk >= 29) {
      final filename = '$name.${format.name}';
      await PhotoManager.editor.saveImage(
        dated,
        filename: filename,
        title: filename,
        relativePath: album == null ? 'Pictures/' : 'Pictures/$album/',
        creationDate: image.createdAt > 0
            ? DateTime.fromMillisecondsSinceEpoch(image.createdAt)
            : null,
      );
      return dated.length;
    }
  }
  await Gal.putImageBytes(dated, name: name, album: album);
  return dated.length;
}

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../../core/util/png_meta.dart';
import '../../core/util/webp_to_png.dart';
import 'save_settings.dart';

/// 按保存设置处理图片字节(对齐 web `processImageForSave`):
/// - PNG + 原始:原字节直出(图库里存的是 WebP 的无损还原成 PNG,像素 / 隐写 / 参数不变);
///   PNG + 清除/自定义:走 png_meta 写入端;
/// - JPG:重编码(透明合白底),有损无元数据,清除/自定义等同。
/// 估算大小 = 真实走一遍取长度,估算即实际。
Future<Uint8List> processForSave(Uint8List bytes, SaveSettings o) async {
  if (o.format == SaveFormat.jpg) {
    return compute(_encodeJpg, (
      bytes,
      (o.quality * 100).round().clamp(10, 100),
    ));
  }
  return switch (o.meta) {
    SaveMeta.original => isWebp(bytes) ? compute(webpToPng, bytes) : bytes,
    SaveMeta.clean => cleanImagePng(bytes),
    SaveMeta.custom => writeCustomMetadataPng(bytes, o.customPrompt),
  };
}

/// 后台 isolate:解码 → 合成白底(JPG 无透明)→ 按质量编码。
Uint8List _encodeJpg((Uint8List, int) arg) {
  final (bytes, quality) = arg;
  final src = img.decodeImage(bytes);
  if (src == null) throw StateError('图片解码失败');
  final canvas = img.Image(
    width: src.width,
    height: src.height,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, src);
  return Uint8List.fromList(img.encodeJpg(canvas, quality: quality));
}

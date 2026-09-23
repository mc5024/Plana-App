import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// 解码图片像素尺寸 (宽, 高)。
Future<(int, int)> decodeImageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final size = (img.width, img.height);
  img.dispose();
  return size;
}

/// img2img 目标分辨率(与 web `setImg2imgWithAutoRes` 一致):
/// 各边取整到 64 的倍数、最小 64;总像素超 1024×3072 则等比缩回。
({int w, int h}) img2imgResolution(int rawW, int rawH) {
  int w = math.max(64, (rawW / 64).round() * 64);
  int h = math.max(64, (rawH / 64).round() * 64);
  const maxPixels = 1024 * 3072; // 3,145,728
  if (w * h > maxPixels) {
    final scale = math.sqrt(maxPixels / (w * h));
    w = math.max(64, ((w * scale) / 64).floor() * 64);
    h = math.max(64, ((h * scale) / 64).floor() * 64);
  }
  return (w: w, h: h);
}

/// 把图 cover(填满,居中裁切)到目标尺寸、黑底兜底,输出 PNG 字节。
/// 复刻 web `processImg2ImgImage` 的 canvas.drawImage 行为。
Future<Uint8List> coverResizePng(
  Uint8List src,
  int targetW,
  int targetH, {

  /// true = 不垫黑底,源图的 alpha 原样带过去。
  ///
  /// 黑底本来只是 cover 的边缘保险(cover 铺满整块画布,底色看不见)——
  /// 可它对**透明图**是致命的:透过 alpha 显出来,缩略图变黑方块、图生图底图
  /// 变黑底。所以凡是要保透明的调用方(缩略图、透明底图)都该传 true。
  bool keepAlpha = false,
  double alignX = 0,
  double alignY = 0,
}) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final img = frame.image;

  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  final tw = targetW.toDouble();
  final th = targetH.toDouble();
  final scale = math.max(tw / iw, th / ih); // cover
  final sw = iw * scale;
  final sh = ih * scale;
  final dx = (tw - sw) * (alignX.clamp(-1.0, 1.0) + 1) / 2;
  final dy = (th - sh) * (alignY.clamp(-1.0, 1.0) + 1) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, tw, th));
  if (!keepAlpha) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, tw, th),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
  }
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, iw, ih),
    ui.Rect.fromLTWH(dx, dy, sw, sh),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(targetW, targetH);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);

  img.dispose();
  out.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// Krea 风格参考预处理,复刻 web `applyKreaStyleRefFile`:长边缩到
/// [maxDim] 以内(不放大、不裁切、不加黑边)→ 合白底 → JPEG。
///
/// 与角色参考(CR)那套刻意不同:服务端的 FluxKontextImageScale 会自己把参考图
/// 缩到 ~1024² 的像素预算,填黑边只会让黑色也进参考;JPEG 而不是 PNG 是因为
/// 最多三张一起进请求体,PNG 能把一次生成的载荷撑到十几 MB。
///
/// 跑在后台 isolate(解码 + 重采样 + 编码对主线程来说太重,会掉帧)。
Future<Uint8List> styleRefResizeJpg(
  Uint8List src, {
  int maxDim = 1024,
  int quality = 92,
}) => compute(_styleRefResizeJpg, (src, maxDim, quality));

Uint8List _styleRefResizeJpg((Uint8List, int, int) arg) {
  final (src, maxDim, quality) = arg;
  final decoded = img.decodeImage(src);
  if (decoded == null) throw StateError('图片解码失败');
  final longest = math.max(decoded.width, decoded.height);
  final scaled = longest > maxDim
      ? img.copyResize(
          decoded,
          width: longest == decoded.width ? maxDim : null,
          height: longest == decoded.height ? maxDim : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  // 白底而不是黑底:透明像素在 JPEG 里会变成纯黑,一块黑斑照样会被当画风搬走。
  final canvas = img.Image(
    width: scaled.width,
    height: scaled.height,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, scaled);
  return Uint8List.fromList(img.encodeJpg(canvas, quality: quality));
}

/// 角色参考(CR)预处理,复刻 web `processCRImage`:按宽高比选目标画布,
/// contain(整图可见、按比例缩放)+ 黑边居中填充,输出 PNG。
/// 方形(0.8≤AR≤1.25)→1472²;横图→1536×1024;竖图→1024×1536。
Future<Uint8List> crResizePng(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final img = frame.image;

  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  final ar = iw / ih;

  int cw, ch;
  if (ar >= 0.8 && ar <= 1.25) {
    cw = 1472;
    ch = 1472;
  } else if (iw > ih) {
    cw = 1536;
    ch = 1024;
  } else {
    cw = 1024;
    ch = 1536;
  }

  final twd = cw.toDouble();
  final thd = ch.toDouble();
  final scale = math.min(twd / iw, thd / ih); // contain
  final sw = iw * scale;
  final sh = ih * scale;
  final dx = (twd - sw) / 2;
  final dy = (thd - sh) / 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, twd, thd));
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, twd, thd),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, iw, ih),
    ui.Rect.fromLTWH(dx, dy, sw, sh),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(cw, ch);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);

  img.dispose();
  out.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

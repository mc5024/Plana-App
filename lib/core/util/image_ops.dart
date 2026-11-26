import 'dart:isolate' show TransferableTypedData;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'transparency.dart' show rgbaHasAlpha;
import 'webp_to_png.dart' show isWebp, webpToPng;

/// 解码图片像素尺寸 (宽, 高)。
Future<(int, int)> decodeImageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final size = (img.width, img.height);
  img.dispose();
  return size;
}

/// NAI 收的图片格式(PNG / JPEG / WebP),只看文件头。
bool isNaiImageFormat(Uint8List b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  return at(0, const [0x89, 0x50, 0x4E, 0x47]) ||
      at(0, const [0xFF, 0xD8, 0xFF]) ||
      (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits));
}

/// 转成 PNG:本来就是 PNG 的原样返回;WebP 无损还原(像素 / alpha 隐写 / 参数都在,
/// 见 webp_to_png);其余格式(JPEG 等)解码后重编码。
Future<Uint8List> ensurePng(Uint8List src) async {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  var isPng = src.length >= sig.length;
  for (var i = 0; isPng && i < sig.length; i++) {
    isPng = src[i] == sig[i];
  }
  if (isPng) return src;
  if (isWebp(src)) {
    try {
      return await compute(webpToPng, src);
    } catch (_) {} // 有损 / 动图之类 webpToPng 解不了的,走下面通用那条
  }
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (data == null) throw StateError('PNG 编码失败');
  return data.buffer.asUint8List();
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
  final dx = (tw - sw) / 2;
  final dy = (th - sh) / 2;

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

/// 缩略图短边像素。
const kThumbShortSide = 512;

/// 缩略图:等比缩到短边 [kThumbShortSide]、长边不超过三倍短边(不放大、不裁切)。
/// 不透明的编 JPEG,带透明的编 PNG。
Future<({Uint8List bytes, bool jpeg})> makeThumb(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final iw = image.width, ih = image.height;
  final scale = math.min(
    1.0,
    math.min(
      kThumbShortSide / math.min(iw, ih),
      kThumbShortSide * 3 / math.max(iw, ih),
    ),
  );
  final tw = math.max(1, (iw * scale).round());
  final th = math.max(1, (ih * scale).round());

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
  );
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, iw.toDouble(), ih.toDouble()),
    ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(tw, th);
  try {
    final raw = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    if (!rgbaHasAlpha(rgba)) {
      return (bytes: await compute(_thumbJpg, (rgba, tw, th)), jpeg: true);
    }
    final png = (await out.toByteData(format: ui.ImageByteFormat.png))!;
    return (bytes: png.buffer.asUint8List(), jpeg: false);
  } finally {
    image.dispose();
    out.dispose();
    picture.dispose();
  }
}

Uint8List _thumbJpg((Uint8List, int, int) arg) {
  final (rgba, w, h) = arg;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
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

/// V4.5 角色参考目标画布尺寸:方形(0.8≤AR≤1.25)→1472²;横图→1536×1024;竖图→1024×1536。
({int w, int h}) cr45CanvasSize(int width, int height) {
  final ar = math.max(width, 1) / math.max(height, 1);
  if (ar >= 0.8 && ar <= 1.25) return (w: 1472, h: 1472);
  return width > height ? (w: 1536, h: 1024) : (w: 1024, h: 1536);
}

/// 交给后端缩放角色参考图时的原图最大像素预算(避免超大分辨率占用后端解码内存)。
const kRawCharRefMaxPixels = 4096 * 4096;

/// 高压缩原图(如 JPEG/WebP)的体积阈值:不高于此值且像素在预算内时直发原图,
/// 避免本地重编码成 1MP–2MP 无损 PNG 反而变大。
const kRawCharRefSmallBytes = 512 * 1024;

/// 后端支持角色参考缩放(`char_ref_fit`)时,判断是否应跳过本地缩放直接发原图。
bool shouldPreferRawCharRef({
  required int srcW,
  required int srcH,
  required int srcBytes,
  required bool useBucket,
}) {
  if (srcW <= 0 || srcH <= 0) return false;
  final pixels = srcW * srcH;
  if (pixels > kRawCharRefMaxPixels) return false;
  final target = useBucket
      ? pickV5CrBucket(srcW, srcH)
      : cr45CanvasSize(srcW, srcH);
  return pixels <= target.w * target.h || srcBytes <= kRawCharRefSmallBytes;
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
  final size = cr45CanvasSize(img.width, img.height);
  final cw = size.w;
  final ch = size.h;

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

/// V5 精确参考官方 97 档分辨率桶表 (宽, 高)。
const kV5CrBuckets = <(int, int)>[
  (256, 4096),
  (256, 4032),
  (256, 3968),
  (256, 3904),
  (256, 3840),
  (256, 3776),
  (256, 3712),
  (256, 3648),
  (256, 3584),
  (256, 3520),
  (256, 3456),
  (256, 3392),
  (256, 3328),
  (320, 3264),
  (320, 3200),
  (320, 3136),
  (320, 3072),
  (320, 3008),
  (320, 2944),
  (320, 2880),
  (320, 2816),
  (320, 2752),
  (384, 2688),
  (384, 2624),
  (384, 2560),
  (384, 2496),
  (384, 2432),
  (384, 2368),
  (448, 2304),
  (448, 2240),
  (448, 2176),
  (448, 2112),
  (512, 2048),
  (512, 1984),
  (512, 1920),
  (512, 1856),
  (576, 1792),
  (576, 1728),
  (576, 1664),
  (640, 1600),
  (640, 1536),
  (704, 1472),
  (704, 1408),
  (768, 1344),
  (768, 1280),
  (832, 1216),
  (896, 1152),
  (960, 1088),
  (1024, 1024),
  (1088, 960),
  (1152, 896),
  (1216, 832),
  (1280, 768),
  (1344, 768),
  (1408, 704),
  (1472, 704),
  (1536, 640),
  (1600, 640),
  (1664, 576),
  (1728, 576),
  (1792, 576),
  (1856, 512),
  (1920, 512),
  (1984, 512),
  (2048, 512),
  (2112, 448),
  (2176, 448),
  (2240, 448),
  (2304, 448),
  (2368, 384),
  (2432, 384),
  (2496, 384),
  (2560, 384),
  (2624, 384),
  (2688, 384),
  (2752, 320),
  (2816, 320),
  (2880, 320),
  (2944, 320),
  (3008, 320),
  (3072, 320),
  (3136, 320),
  (3200, 320),
  (3264, 320),
  (3328, 256),
  (3392, 256),
  (3456, 256),
  (3520, 256),
  (3584, 256),
  (3648, 256),
  (3712, 256),
  (3776, 256),
  (3840, 256),
  (3904, 256),
  (3968, 256),
  (4032, 256),
  (4096, 256),
];

/// V5 精确参考选桶:按对数宽高比距离最小匹配 [kV5CrBuckets]。
({int w, int h}) pickV5CrBucket(int width, int height) {
  final targetLog = math.log(math.max(width, 1) / math.max(height, 1));
  var best = kV5CrBuckets.first;
  var bestDiff = double.infinity;
  for (final b in kV5CrBuckets) {
    final diff = (targetLog - math.log(b.$1 / b.$2)).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = b;
    }
  }
  return (w: best.$1, h: best.$2);
}

/// V5 精确参考 Cover 裁切参数(纯计算,供 [crBucketResizePng] 与单测共用)。
///
/// 对齐 `floor(x + 0.5)` 取整与整数居中裁切偏移 `((resize - bucket) ~/ 2)`。
({int bucketW, int bucketH, int resizeW, int resizeH, int left, int top})
v5CrBucketLayout(int width, int height) {
  final w = math.max(width, 1);
  final h = math.max(height, 1);
  final bucket = pickV5CrBucket(w, h);
  final bw = bucket.w;
  final bh = bucket.h;
  if (w == bw && h == bh) {
    return (
      bucketW: bw,
      bucketH: bh,
      resizeW: bw,
      resizeH: bh,
      left: 0,
      top: 0,
    );
  }
  final scale = math.max(bw / w, bh / h);
  final resizeW = math.max((w * scale + 0.5).floor(), bw);
  final resizeH = math.max((h * scale + 0.5).floor(), bh);
  final left = (resizeW - bw) ~/ 2;
  final top = (resizeH - bh) ~/ 2;
  return (
    bucketW: bw,
    bucketH: bh,
    resizeW: resizeW,
    resizeH: resizeH,
    left: left,
    top: top,
  );
}

/// V5 精确参考(PR)预处理:按 [kV5CrBuckets] 97 档桶表 Cover 居中裁切输出 PNG
/// (不填黑底,保留透明通道)。源图尺寸恰好命中目标桶时直接走 [ensurePng] 不重绘。
Future<Uint8List> crBucketResizePng(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final layout = v5CrBucketLayout(image.width, image.height);
    if (image.width == layout.bucketW && image.height == layout.bucketH) {
      return ensurePng(src);
    }
    final bw = layout.bucketW;
    final bh = layout.bucketH;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, bw.toDouble(), bh.toDouble()),
    );
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(
        -layout.left.toDouble(),
        -layout.top.toDouble(),
        layout.resizeW.toDouble(),
        layout.resizeH.toDouble(),
      ),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(bw, bh);
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG 编码失败');
      return data.buffer.asUint8List();
    } finally {
      out.dispose();
      picture.dispose();
    }
  } finally {
    image.dispose();
  }
}

/// NAI Vibe 编码图片像素上限（4096×4096）与单边上限。
const kVibeEncodeMaxPixels = 4096 * 4096;
const kVibeEncodeMaxSide = 16383;

/// 计算不超 [maxPixels] 与单边 [maxSide] 的等比目标尺寸；未超限返回 null。
({int w, int h})? fitImageWithinLimits(
  int width,
  int height, {
  int maxPixels = kVibeEncodeMaxPixels,
  int maxSide = kVibeEncodeMaxSide,
}) {
  if (width <= 0 || height <= 0) return null;
  if (width <= maxSide && height <= maxSide && width * height <= maxPixels) {
    return null;
  }
  final scale = math.min(
    math.sqrt(maxPixels / (width * height)),
    math.min(maxSide / width, maxSide / height),
  );
  var tw = math.min(maxSide, math.max(1, (width * scale).floor()));
  var th = math.min(maxSide, math.max(1, (height * scale).floor()));
  while (tw * th > maxPixels) {
    if (tw >= th && tw > 1) {
      tw--;
    } else if (th > 1) {
      th--;
    } else {
      break;
    }
  }
  return (w: tw, h: th);
}

/// 缩小超过 NAI Vibe 编码尺寸上限的图片；未超限或无法解码时原样返回。
/// 不透明图片编码为 JPEG，带透明通道的图片保留 PNG。
Future<Uint8List> shrinkForVibeEncode(
  Uint8List src, {
  int maxPixels = kVibeEncodeMaxPixels,
  int maxSide = kVibeEncodeMaxSide,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? decoded;
  ui.Image? out;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(src);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final target = fitImageWithinLimits(
      descriptor.width,
      descriptor.height,
      maxPixels: maxPixels,
      maxSide: maxSide,
    );
    if (target == null) return src;

    codec = await descriptor.instantiateCodec(
      targetWidth: target.w,
      targetHeight: target.h,
    );
    decoded = (await codec.getNextFrame()).image;

    final ui.Image finalImg;
    final exact = fitImageWithinLimits(
      decoded.width,
      decoded.height,
      maxPixels: maxPixels,
      maxSide: maxSide,
    );
    if (exact == null) {
      finalImg = decoded;
    } else {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, exact.w.toDouble(), exact.h.toDouble()),
      );
      canvas.drawImageRect(
        decoded,
        ui.Rect.fromLTWH(
          0,
          0,
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, exact.w.toDouble(), exact.h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        out = await picture.toImage(exact.w, exact.h);
      } finally {
        picture.dispose();
      }
      finalImg = out;
    }

    final raw = await finalImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return src;
    final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    if (!rgbaHasAlpha(rgba)) {
      final transfer = TransferableTypedData.fromList([rgba]);
      return compute(_encodeRgbaJpg, (
        transfer,
        finalImg.width,
        finalImg.height,
        92,
      ));
    }
    final png = await finalImg.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return src;
    return png.buffer.asUint8List();
  } catch (_) {
    return src;
  } finally {
    out?.dispose();
    decoded?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Uint8List _encodeRgbaJpg((TransferableTypedData, int, int, int) arg) {
  final (data, w, h, quality) = arg;
  final rgba = data.materialize().asUint8List();
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

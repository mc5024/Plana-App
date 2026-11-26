import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/core/util/image_ops.dart';

Uint8List _makePng(int w, int h, {bool transparent = false}) {
  final im = img.Image(width: w, height: h, numChannels: transparent ? 4 : 3);
  if (transparent) {
    img.fill(im, color: img.ColorRgba8(255, 128, 64, 120));
  } else {
    img.fill(im, color: img.ColorRgb8(64, 128, 255));
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fitImageWithinLimits', () {
    test('未超限或非法尺寸返回 null', () {
      expect(fitImageWithinLimits(0, 100), isNull);
      expect(fitImageWithinLimits(100, -1), isNull);
      expect(fitImageWithinLimits(1024, 1024), isNull);
      expect(fitImageWithinLimits(4096, 4096), isNull);
      expect(fitImageWithinLimits(16383, 1024), isNull);
    });

    test('总像素超限时等比缩回上限内', () {
      final t = fitImageWithinLimits(4200, 5800)!;
      expect(t.w * t.h, lessThanOrEqualTo(kVibeEncodeMaxPixels));
      expect(t.w, lessThanOrEqualTo(kVibeEncodeMaxSide));
      expect(t.h, lessThanOrEqualTo(kVibeEncodeMaxSide));
      expect((t.w / t.h - 4200 / 5800).abs(), lessThan(0.002));

      final sq = fitImageWithinLimits(4097, 4097)!;
      expect(sq, (w: 4096, h: 4096));
    });

    test('像素未超但单边超限时按单边等比缩放', () {
      final wide = fitImageWithinLimits(20000, 200)!;
      expect(wide.w, kVibeEncodeMaxSide);
      expect(wide.h, lessThanOrEqualTo(200));
      expect(wide.w * wide.h, lessThanOrEqualTo(kVibeEncodeMaxPixels));

      final tall = fitImageWithinLimits(200, 20000)!;
      expect(tall.h, kVibeEncodeMaxSide);
      expect(tall.w, lessThanOrEqualTo(200));
    });
  });

  group('shrinkForVibeEncode', () {
    test('未超限图片原样返回', () async {
      final src = _makePng(64, 48);
      final out = await shrinkForVibeEncode(src, maxPixels: 4096, maxSide: 128);
      expect(identical(out, src), isTrue);
    });

    test('超限不透明图缩小为 JPEG 且满足尺寸上限', () async {
      final src = _makePng(200, 100);
      final out = await shrinkForVibeEncode(src, maxPixels: 5000, maxSide: 200);
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      final (w, h) = await decodeImageSize(out);
      expect(w * h, lessThanOrEqualTo(5000));
      expect(w, lessThanOrEqualTo(200));
      expect(h, lessThanOrEqualTo(200));
      expect((w / h - 2.0).abs(), lessThan(0.05));
    });

    test('超限透明图缩小后保留 PNG 透明通道', () async {
      final src = _makePng(200, 100, transparent: true);
      final out = await shrinkForVibeEncode(src, maxPixels: 5000, maxSide: 200);
      expect(out.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final decoded = img.decodePng(out)!;
      expect(decoded.width * decoded.height, lessThanOrEqualTo(5000));
      expect(decoded.numChannels, 4);
      expect(decoded.getPixel(0, 0).a, lessThan(254));
    });

    test('单边超限图片缩小到单边以内', () async {
      final src = _makePng(300, 20);
      final out = await shrinkForVibeEncode(src, maxPixels: 100000, maxSide: 150);
      final (w, h) = await decodeImageSize(out);
      expect(w, lessThanOrEqualTo(150));
      expect(h, greaterThanOrEqualTo(1));
    });

    test('非图片字节不抛异常并原样返回', () async {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      final out = await shrinkForVibeEncode(junk);
      expect(identical(out, junk), isTrue);
    });
  });
}

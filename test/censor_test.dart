// 打码:遮罩格 → 马赛克/纯色的纯像素逻辑。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/features/inpaint/censor_ops.dart';
import 'package:plana_app/features/inpaint/inpaint_ops.dart';

/// 每个像素颜色互不相同的测试图(x/y 直接当通道值),便于断言"哪些动了"。
Uint8List makePng(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, x * 4 % 256, y * 4 % 256, (x + y) * 2 % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

/// 涂一格(格坐标)。
MaskGrid gridWith(int w, int h, List<(int, int)> cells) {
  final g = MaskGrid(w, h);
  for (final (gx, gy) in cells) {
    g.cells[gy * g.gw + gx] = 1;
  }
  return g;
}

img.Image decode(Uint8List b) => img.decodeImage(b)!;

(int, int, int) px(img.Image im, int x, int y) {
  final p = im.getPixel(x, y);
  return (p.r.toInt(), p.g.toInt(), p.b.toInt());
}

void main() {
  group('马赛克', () {
    test('涂抹格填所在块的均值,块内其余格不动', () {
      const w = 32, h = 32;
      final src = makePng(w, h);
      // block = 2 格 = 16px。涂 (0,0) 一格,它属于 16×16 的块。
      final out = decode(
        censorPngSync((
          png: src,
          mask: gridWith(w, h, [(0, 0)]).encode(),
          style: CensorStyle.mosaic,
          block: 2,
          color: kCensorColorDefault,
        )),
      );
      final ref = decode(src);

      // 期望值 = 16×16 块的均值
      var r = 0, g = 0, b = 0;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final p = px(ref, x, y);
          r += p.$1;
          g += p.$2;
          b += p.$3;
        }
      }
      final want = (r ~/ 256, g ~/ 256, b ~/ 256);

      // 涂的那一格 8×8 全是均值
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          expect(px(out, x, y), want, reason: '($x,$y) 应被抹平');
        }
      }
      // 同一块里没涂的格(8..15)原样
      for (var y = 8; y < 16; y++) {
        for (var x = 8; x < 16; x++) {
          expect(px(out, x, y), px(ref, x, y), reason: '($x,$y) 未涂不该动');
        }
      }
    });

    test('遮罩外一个像素都不动', () {
      const w = 64, h = 64;
      final src = makePng(w, h);
      final out = decode(
        censorPngSync((
          png: src,
          mask: gridWith(w, h, [(2, 2)]).encode(),
          style: CensorStyle.mosaic,
          block: 3,
          color: kCensorColorDefault,
        )),
      );
      final ref = decode(src);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final inCell = x >= 16 && x < 24 && y >= 16 && y < 24;
          if (!inCell) {
            expect(px(out, x, y), px(ref, x, y), reason: '($x,$y) 在遮罩外');
          }
        }
      }
    });

    test('块大小越大抹得越平:相邻两格取到同一块均值', () {
      const w = 32, h = 32;
      final src = makePng(w, h);
      // block = 4 格 = 32px = 整图一块 → 所有涂抹格颜色相同
      final out = decode(
        censorPngSync((
          png: src,
          mask: gridWith(w, h, [(0, 0), (3, 3)]).encode(),
          style: CensorStyle.mosaic,
          block: 4,
          color: kCensorColorDefault,
        )),
      );
      expect(px(out, 0, 0), px(out, 24, 24));
    });
  });

  group('纯色', () {
    test('涂抹格盖成不透明黑', () {
      const w = 32, h = 32;
      final src = makePng(w, h);
      final out = decode(
        censorPngSync((
          png: src,
          mask: gridWith(w, h, [(1, 1)]).encode(),
          style: CensorStyle.solid,
          block: 4,
          color: kCensorColorDefault,
        )),
      );
      final p = out.getPixel(12, 12);
      expect(
        (p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()),
        (0, 0, 0, 255),
      );
      // 边界外不动
      expect(px(out, 7, 7), px(decode(src), 7, 7));
    });

    test('用指定颜色填,alpha 一律丢弃', () {
      const w = 32, h = 32;
      final src = makePng(w, h);
      final out = decode(
        censorPngSync((
          png: src,
          mask: gridWith(w, h, [(1, 1)]).encode(),
          style: CensorStyle.solid,
          block: 4,
          // 半透明白:alpha 该被忽略,填成不透明白
          color: 0x40FFFFFF,
        )),
      );
      final p = out.getPixel(12, 12);
      expect(
        (p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()),
        (255, 255, 255, 255),
      );
    });

    test('预设色都有中文名,非预设回落十六进制', () {
      for (final (c, name) in [
        (0xFF000000, '黑'),
        (0xFF444444, '深灰'),
        (0xFFBBBBBB, '浅灰'),
        (0xFFFFFFFF, '白'),
      ]) {
        expect(kCensorColors, contains(c));
        expect(censorColorLabel(c), name);
      }
      expect(censorColorLabel(0xFF123456), '#123456');
    });
  });

  group('兜底', () {
    test('遮罩尺寸与图不符 → 原样返回,不乱盖', () {
      final src = makePng(32, 32);
      final wrong = gridWith(64, 64, [(0, 0)]).encode();
      expect(
        censorPngSync((
          png: src,
          mask: wrong,
          style: CensorStyle.mosaic,
          block: 2,
          color: kCensorColorDefault,
        )),
        same(src),
        reason: '尺寸对不上应原字节返回',
      );
    });

    test('空遮罩 → 像素不变', () {
      const w = 32, h = 32;
      final src = makePng(w, h);
      final out = decode(
        censorPngSync((
          png: src,
          mask: MaskGrid(w, h).encode(),
          style: CensorStyle.mosaic,
          block: 2,
          color: kCensorColorDefault,
        )),
      );
      final ref = decode(src);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          expect(px(out, x, y), px(ref, x, y));
        }
      }
    });

    test('块大小越界被夹回合法档', () {
      const w = 32, h = 32;
      final src = makePng(w, h);
      final mask = gridWith(w, h, [(0, 0)]).encode();
      // 0 格会让 bpx=0 除零;负数同理。夹回 kCensorBlockMin 后应正常出图。
      expect(
        () => censorPngSync((
          png: src,
          mask: mask,
          style: CensorStyle.mosaic,
          block: 0,
          color: kCensorColorDefault,
        )),
        returnsNormally,
      );
      expect(
        () => censorPngSync((
          png: src,
          mask: mask,
          style: CensorStyle.mosaic,
          block: 9999,
          color: kCensorColorDefault,
        )),
        returnsNormally,
      );
    });
  });

  group('默认块大小', () {
    test('按长边缩放,不写死像素', () {
      // 长边 /40/8 四舍五入:1216 → 3.8 → 4 格(32px)
      expect(defaultCensorBlock(832, 1216), 4);
      // 小图不至于糊成一块
      expect(defaultCensorBlock(256, 256), 2);
      // 大图也不无限增长
      expect(
        defaultCensorBlock(4096, 4096),
        lessThanOrEqualTo(kCensorBlockMax),
      );
    });

    test('结果永远落在合法档内', () {
      for (final s in [64, 512, 1024, 2048, 8192]) {
        final b = defaultCensorBlock(s, s);
        expect(b, inInclusiveRange(kCensorBlockMin, kCensorBlockMax));
      }
    });
  });
}

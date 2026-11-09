// 重绘成图混回:羽化 alpha 的范围、混回位置、元数据搬运。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/core/util/png_meta.dart';
import 'package:plana_app/features/inpaint/inpaint_ops.dart';

Uint8List solidPng(int w, int h, int r, int g, int b) {
  final im = img.Image(width: w, height: h, numChannels: 3)
    ..clear(img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(im));
}

(int, int, int) px(img.Image im, int x, int y) {
  final p = im.getPixel(x, y);
  return (p.r.toInt(), p.g.toInt(), p.b.toInt());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('羽化 alpha', () {
    // 256×256,重绘区是正中 6×6 格 [104,152)²(约一笔 48px 的方刷)
    Uint8List alpha() {
      const gw = 32, gh = 32;
      final cells = Uint8List(gw * gh);
      for (var gy = 13; gy < 19; gy++) {
        for (var gx = 13; gx < 19; gx++) {
          cells[gy * gw + gx] = 1;
        }
      }
      return inpaintBlendAlpha(cells, gw, gh, 256, 256);
    }

    test('遮罩里取成图,远处全留原图', () {
      final a = alpha();
      int at(int x, int y) => a[y * 256 + x];
      expect(at(128, 128), 255);
      expect(at(140, 110), 255);
      expect(at(150, 128), greaterThan(250)); // 遮罩边上几乎全是成图
      // 外扩 32px、再模糊 40px 以外的碰不到
      expect(at(104 - 73, 128), 0);
      expect(at(128, 152 + 73), 0);
      expect(at(0, 0), 0);
    });

    test('过渡带在遮罩外圈,往外单调变小', () {
      final a = alpha();
      int at(int x) => a[128 * 256 + x];
      var prev = 255;
      for (var x = 128; x < 256; x++) {
        expect(at(x), lessThanOrEqualTo(prev));
        prev = at(x);
      }
      expect(at(152 + 32), inExclusiveRange(0, 255)); // 外扩边上正在过渡
    });
  });

  testWidgets('混回发送框:遮罩处换成图,框内远处与框外不动', (tester) async {
    await tester.runAsync(() async {
      // 原图 512² 蓝;发送框 (128,128) 256²;遮罩只涂框里正中 [104,152)²
      final mask = img.Image(width: 256, height: 256, numChannels: 3)
        ..clear(img.ColorRgb8(0, 0, 0));
      img.fillRect(
        mask,
        x1: 104,
        y1: 104,
        x2: 151,
        y2: 151,
        color: img.ColorRgb8(255, 255, 255),
      );
      final r = await blendInpaintResult(
        base: solidPng(512, 512, 0, 0, 255),
        patch: solidPng(256, 256, 255, 0, 0),
        mask: Uint8List.fromList(img.encodePng(mask)),
        x: 128,
        y: 128,
      );
      expect((r.width, r.height), (512, 512));
      final out = img.decodePng(r.png)!;
      expect(px(out, 128 + 128, 128 + 128), (255, 0, 0));
      expect(px(out, 128 + 2, 128 + 2), (0, 0, 255)); // 框内远离遮罩
      expect(px(out, 10, 10), (0, 0, 255)); // 框外
      final edge = px(out, 128 + 152 + 32, 128 + 128);
      expect(edge.$1, inExclusiveRange(0, 255)); // 羽化带里新旧都有
    });
  });

  testWidgets('成图与遮罩尺寸不符直接报错', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        blendInpaintResult(
          base: solidPng(256, 256, 0, 0, 255),
          patch: solidPng(32, 32, 255, 0, 0),
          mask: solidPng(256, 256, 255, 255, 255),
        ),
        throwsStateError,
      );
    });
  });

  test('文本块搬到新图上,像素不动', () {
    final withText = withPngITxt(solidPng(8, 8, 1, 2, 3), 'Comment', '{"a":1}');
    final plain = solidPng(8, 8, 4, 5, 6);
    final out = withPngTextFrom(plain, withText);
    expect(chunkTypes(out), [
      ...chunkTypes(plain)..remove('IEND'),
      'iTXt',
      'IEND',
    ]);
    expect(String.fromCharCodes(out), contains('Comment'));
    expect(px(img.decodePng(out)!, 0, 0), (4, 5, 6));
    // 来源没有文本块 / 不是 PNG:原样返回
    expect(withPngTextFrom(plain, solidPng(8, 8, 0, 0, 0)), same(plain));
    expect(withPngTextFrom(plain, Uint8List(4)), same(plain));
  });
}

/// PNG 里依次出现的块类型。
List<String> chunkTypes(Uint8List png) {
  final d = ByteData.sublistView(png);
  final out = <String>[];
  for (var o = 8; o + 12 <= png.length; o += d.getUint32(o) + 12) {
    out.add(String.fromCharCodes(png, o + 4, o + 8));
  }
  return out;
}

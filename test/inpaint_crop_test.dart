import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inpaint/inpaint_ops.dart';

/// 局部框封顶(长边 2048、面积 ≤ 1024²):放得下不动;放不下先盖遮罩、
/// 余下面积匀给留白,窗口再留用户拉过的框、最后贴遮罩居中,起点始终沿 64 网格。
const _side = 2048;
const _px = 1024 * 1024;

void main() {
  test('放得下原样返回', () {
    const r = (x: 64, y: 128, w: 1024, h: 640);
    expect(capSendRect(r, _side, _px), r);
  });

  test('超面积:先盖满遮罩,余下面积匀给留白', () {
    final r = capSendRect(
      (x: 0, y: 0, w: 1536, h: 1024),
      _side,
      _px,
      focus: (x: 300, y: 300, w: 700, h: 300),
    );
    expect(r, (x: 0, y: 64, w: 1344, h: 768));
  });

  test('长条遮罩:超过 1024 宽也整条框住', () {
    final g = MaskGrid(1536, 1536);
    // 遮罩 [200,1400)×[600,704)
    for (var gy = 75; gy <= 87; gy++) {
      for (var gx = 25; gx <= 174; gx++) {
        g.cells[gy * g.gw + gx] = 1;
      }
    }
    final r = cropForMask(g, _side, _px)!;
    expect(r, (x: 64, y: 448, w: 1472, h: 384));
    expect(g.hasCellsOutside(r), isFalse);
  });

  test('遮罩本身超面积:按遮罩比例缩,框贴遮罩取一段', () {
    final r = capSendRect(
      (x: 64, y: 256, w: 1472, h: 1216),
      _side,
      _px,
      focus: (x: 200, y: 400, w: 1200, h: 900),
    );
    expect(r, (x: 192, y: 384, w: 1152, h: 896));
  });

  test('用户拉过的框:遮罩盖满的前提下尽量留住它', () {
    const union = (x: 0, y: 0, w: 1536, h: 1024);
    const mask = (x: 1100, y: 400, w: 200, h: 100);
    const userBox = (x: 0, y: 0, w: 1024, h: 1024);
    expect(capSendRect(union, _side, _px, focus: mask, keep: userBox), (
      x: 0,
      y: 64,
      w: 1344,
      h: 768,
    ));
    // 对照:不管用户的框就只贴遮罩居中,左边留白丢掉一截
    expect(capSendRect(union, _side, _px, focus: mask), (
      x: 192,
      y: 64,
      w: 1344,
      h: 768,
    ));
  });

  test('长边封顶;遮罩优先于用户的框', () {
    final r = capSendRect(
      (x: 0, y: 0, w: 3072, h: 512),
      _side,
      _px,
      focus: (x: 2600, y: 0, w: 400, h: 512),
      keep: (x: 0, y: 0, w: 640, h: 512),
    );
    expect(r, (x: 1024, y: 0, w: 2048, h: 512));
  });

  test('fitCropArea:锁一边只缩另一边,不锁按比例缩,都取 64 倍数', () {
    expect(fitCropArea(1024, 768, _px), (w: 1024, h: 768));
    expect(fitCropArea(1600, 768, _px, lockH: true), (w: 1344, h: 768));
    expect(fitCropArea(512, 2048, _px, lockW: true), (w: 512, h: 2048));
    expect(fitCropArea(1280, 2048, _px, lockW: true), (w: 1280, h: 768));
    expect(fitCropArea(1088, 1088, _px), (w: 1024, h: 1024));
    expect(fitCropArea(2048, 1024, _px), (w: 1408, h: 704));
  });

  test('cropForMask:一处涂抹框得住,两处离得远框不下', () {
    final g = MaskGrid(1536, 1024);
    expect(cropForMask(g, _side, _px), isNull);
    g.paintDot(200, 200, 48);
    final one = cropForMask(g, _side, _px)!;
    expect(one.x % 64 + one.y % 64, 0);
    expect(g.hasCellsIn(one), isTrue);
    expect(g.hasCellsOutside(one), isFalse);

    // 第二笔在对角:外接矩形铺满整图,框只能盖住其中一段
    g.paintDot(1400, 900, 48);
    final two = cropForMask(g, _side, _px)!;
    expect(two.w * two.h, lessThanOrEqualTo(_px));
    expect(two.w % 64 + two.h % 64, 0);
    expect(g.hasCellsOutside(two), isTrue);
  });

  test('cropForMask:用户拉过的框只扩不缩', () {
    final g = MaskGrid(1536, 1024)..paintDot(600, 500, 48);
    const keep = (x: 256, y: 256, w: 768, h: 512);
    final r = cropForMask(g, _side, _px, keep: keep)!;
    expect(r.x <= keep.x && r.y <= keep.y, isTrue);
    expect(
      r.x + r.w >= keep.x + keep.w && r.y + r.h >= keep.y + keep.h,
      isTrue,
    );
  });

  test('focusSendSize:不足 80 万像素放大到约 100 万,宽高取 64 倍数', () {
    expect(focusSendSize(448, 448), (w: 1024, h: 1024));
    expect(focusSendSize(256, 256), (w: 1024, h: 1024));
    expect(focusSendSize(1024, 256), (w: 2048, h: 512));
    expect(focusSendSize(1024, 768), (w: 1152, h: 832));
    expect(focusSendSize(1024, 832), (w: 1024, h: 832)); // 够大不放大
    for (final (w, h) in const [(320, 704), (576, 384), (1024, 512)]) {
      final s = focusSendSize(w, h);
      expect(s.w % 64 + s.h % 64, 0);
      expect(s.w * s.h, lessThanOrEqualTo(1024 * 1024));
    }
  });

  test('hasCellsOutside:按格心判,框边上的格不算出界', () {
    final g = MaskGrid(512, 512)..cells[8 * 64 + 8] = 1; // 格 (8,8) = [64,72)²
    expect(g.hasCellsOutside((x: 64, y: 64, w: 64, h: 64)), isFalse);
    expect(g.hasCellsOutside((x: 72, y: 64, w: 64, h: 64)), isTrue);
    expect(g.hasCellsOutside((x: 0, y: 128, w: 512, h: 64)), isTrue);
  });

  test('maskBounds:空遮罩 null,末格按图边夹住;tightCropRect 结果不变', () {
    final g = MaskGrid(512, 512);
    expect(maskBounds(g), isNull);
    expect(tightCropRect(g), isNull);
    g.paintDot(100, 100, 8);
    expect(maskBounds(g), (x: 96, y: 96, w: 8, h: 8));
    expect(tightCropRect(g), (x: 0, y: 0, w: 256, h: 256));

    final odd = MaskGrid(100, 100); // 最后一格只有 4px 在图里
    odd.cells[odd.cells.length - 1] = 1;
    expect(maskBounds(odd), (x: 96, y: 96, w: 4, h: 4));
  });
}

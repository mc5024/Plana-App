import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inpaint/inpaint_ops.dart';

/// 局部框单边封顶:放得下不动;放不下先盖遮罩、再留用户拉过的框、
/// 最后贴遮罩居中,起点始终沿 64 网格。
void main() {
  test('放得下原样返回', () {
    const r = (x: 64, y: 128, w: 1024, h: 640);
    expect(capSendRect(r, 1024), r);
  });

  test('遮罩比上限小:整块装进框里,留白两侧分', () {
    final r = capSendRect(
      (x: 448, y: 0, w: 1088, h: 512),
      1024,
      focus: (x: 600, y: 64, w: 800, h: 200),
    );
    expect(r, (x: 512, y: 0, w: 1024, h: 512));
  });

  test('遮罩比上限大:走完整条管线,框贴遮罩中心取一段', () {
    final g = MaskGrid(1536, 1536);
    // 遮罩 [200,1400)×[600,704)
    for (var gy = 75; gy <= 87; gy++) {
      for (var gx = 25; gx <= 174; gx++) {
        g.cells[gy * g.gw + gx] = 1;
      }
    }
    final want = alignSendRect(tightCropRect(g)!, 1536, 1536);
    expect(want.w, greaterThan(1024));
    final r = capSendRect(want, 1024, focus: maskBounds(g));
    expect(r, (x: 256, y: 448, w: 1024, h: 384));
  });

  test('用户拉过的框:遮罩盖满的前提下尽量留住它', () {
    const union = (x: 0, y: 0, w: 1280, h: 512);
    const mask = (x: 896, y: 96, w: 208, h: 96);
    const userBox = (x: 0, y: 0, w: 1024, h: 512);
    expect(capSendRect(union, 1024, focus: mask, keep: userBox), (
      x: 128,
      y: 0,
      w: 1024,
      h: 512,
    ));
    // 对照:不管用户的框就只贴遮罩居中,左边留白全丢
    expect(capSendRect(union, 1024, focus: mask), (
      x: 256,
      y: 0,
      w: 1024,
      h: 512,
    ));
  });

  test('遮罩优先于用户的框:新涂抹离得太远,框整个挪过去', () {
    final r = capSendRect(
      (x: 0, y: 0, w: 2048, h: 512),
      1024,
      focus: (x: 1400, y: 0, w: 400, h: 512),
      keep: (x: 0, y: 0, w: 640, h: 512),
    );
    expect(r, (x: 1024, y: 0, w: 1024, h: 512));
  });

  test('cropForMask:一处涂抹框得住,两处离得远框不下', () {
    final g = MaskGrid(1536, 1024);
    expect(cropForMask(g, 1024), isNull);
    g.paintDot(200, 200, 48);
    final one = cropForMask(g, 1024)!;
    expect(one.x % 64 + one.y % 64, 0);
    expect(g.hasCellsIn(one), isTrue);
    expect(g.hasCellsOutside(one), isFalse);

    // 第二笔在对角:外接矩形铺满整图,框只能盖住其中一段
    g.paintDot(1400, 900, 48);
    final two = cropForMask(g, 1024)!;
    expect(two.w, lessThanOrEqualTo(1024));
    expect(g.hasCellsOutside(two), isTrue);
  });

  test('cropForMask:用户拉过的框只扩不缩', () {
    final g = MaskGrid(1536, 1024)..paintDot(600, 500, 48);
    const keep = (x: 256, y: 256, w: 768, h: 512);
    final r = cropForMask(g, 1024, keep: keep)!;
    expect(r.x <= keep.x && r.y <= keep.y, isTrue);
    expect(
      r.x + r.w >= keep.x + keep.w && r.y + r.h >= keep.y + keep.h,
      isTrue,
    );
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

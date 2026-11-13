/// 打码纯图像逻辑:吃 [MaskGrid] 的 8×8 格子,就地产出打好码的 PNG。
///
/// **与重绘共用同一张遮罩** —— 涂一次,既能送去 infill,也能就地打码,
/// 不必退出面板换个工具重涂。所以这里不自建遮罩结构,直接复用 MaskGrid。
///
/// 格子边长 8px、块大小按格数计,两者天然整除 —— 马赛克块永远落在网格上,
/// 涂到哪盖到哪,不会出现半块错位。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../../l10n/l10n.dart';
import 'inpaint_ops.dart' show MaskGrid;

/// 打码样式。
///
/// 刻意**不提供高斯模糊**:弱模糊在数学上可反卷积、ML 去模糊也能恢复个大概,
/// 给了滑杆就一定有人调到最弱那档,等于没打。要遮就遮死。
enum CensorStyle {
  /// 马赛克:块内取均值填平。
  mosaic,

  /// 纯色:整块盖死(强制不透明 —— 透明像素也要覆盖,否则形状还在)。
  solid,
}

extension CensorStyleX on CensorStyle {
  String get label => switch (this) {
    CensorStyle.mosaic => l10nNow.censorMosaic,
    CensorStyle.solid => l10nNow.censorSolid,
  };
}

/// 块大小档位(单位:格,1 格 = 8px)。
const int kCensorBlockMin = 1;
const int kCensorBlockMax = 12;

/// 纯色档的可选填充色(0xAARRGGBB)。
///
/// 只给中性灰阶:打码是**遮盖**,不是装饰 —— 花哨的颜色只会把视线更往那儿引。
/// 黑白两端覆盖了绝大多数成品的做法,中间两档留给深浅背景上的过渡。
const List<int> kCensorColors = [
  0xFF000000,
  0xFF444444,
  0xFFBBBBBB,
  0xFFFFFFFF,
];

const int kCensorColorDefault = 0xFF000000;

/// 颜色名(不在预设里时回落成十六进制)。
String censorColorLabel(int color) => switch (color) {
  0xFF000000 => l10nNow.colorBlack,
  0xFF444444 => l10nNow.colorDarkGray,
  0xFFBBBBBB => l10nNow.colorLightGray,
  0xFFFFFFFF => l10nNow.colorWhite,
  _ => '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
};

/// [censorPngSync] 的入参。具名字段而不是位置元组 —— 五个同类型参数排一起,
/// 位置写错编译器不会拦。
typedef CensorReq = ({
  Uint8List png,
  Uint8List mask,
  CensorStyle style,
  int block,
  int color,
});

/// 按图长边给的默认块大小(格)。
///
/// **块大小必须随图缩放**,写死像素的话同一套参数在 512 和 2048 的图上
/// 强度差四倍。取长边的 ~1/40:1216 长边 → 32px,视觉强度和常见成品一致。
int defaultCensorBlock(int w, int h) =>
    (math.max(w, h) / 40 / 8).round().clamp(2, kCensorBlockMax);

/// 在 [png] 上按 [mask] 打码,返回新的 PNG 字节(后台 isolate)。
///
/// [mask] 是 [MaskGrid.encode] 的字节;[block] 单位为格;[color] 是纯色档的
/// 填充色(0xAARRGGBB,alpha 会被忽略 —— 打码必须不透明)。
Future<Uint8List> censorPng(
  Uint8List png,
  Uint8List mask, {
  required CensorStyle style,
  required int block,
  int color = kCensorColorDefault,
}) => compute(censorPngSync, (
  png: png,
  mask: mask,
  style: style,
  block: block,
  color: color,
));

/// [censorPng] 的同步实现(isolate 入口 / 单测直调)。
///
/// 解码失败或**遮罩尺寸与图不符**时原样返回 —— 尺寸对不上多半是扩图/裁切后
/// 拿了旧遮罩,这时候硬打只会盖错地方,不如什么都不做交给上层报错。
Uint8List censorPngSync(CensorReq arg) {
  final png = arg.png;
  final mask = arg.mask;
  final style = arg.style;
  final blockArg = arg.block;
  final src = img.decodeImage(png);
  if (src == null) return png;
  final grid = MaskGrid(src.width, src.height);
  if (!grid.decodeInto(mask)) return png;

  final block = blockArg.clamp(kCensorBlockMin, kCensorBlockMax);
  final bpx = block * 8;
  final w = src.width, h = src.height;
  // alpha 一律丢弃:半透明的"码"等于没打
  final sr = (arg.color >> 16) & 0xFF;
  final sg = (arg.color >> 8) & 0xFF;
  final sb = arg.color & 0xFF;

  /// 块均值缓存:同一块里的多个格子只算一次。key = 块左上角的像素行主序下标
  /// (bx < w,故 by*w+bx 唯一;别拿格数 gw 当行宽,那会撞键)。
  final avg = <int, (int, int, int)>{};

  (int, int, int) blockAvg(int bx, int by) {
    final x1 = math.min(w, bx + bpx), y1 = math.min(h, by + bpx);
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = by; y < y1; y++) {
      for (var x = bx; x < x1; x++) {
        final p = src.getPixel(x, y);
        r += p.r.toInt();
        g += p.g.toInt();
        b += p.b.toInt();
        n++;
      }
    }
    if (n == 0) return (0, 0, 0);
    return (r ~/ n, g ~/ n, b ~/ n);
  }

  for (var gy = 0; gy < grid.gh; gy++) {
    for (var gx = 0; gx < grid.gw; gx++) {
      if (grid.cells[gy * grid.gw + gx] == 0) continue;
      final cx = gx * 8, cy = gy * 8;
      final cx1 = math.min(w, cx + 8), cy1 = math.min(h, cy + 8);
      if (style == CensorStyle.solid) {
        for (var y = cy; y < cy1; y++) {
          for (var x = cx; x < cx1; x++) {
            src.setPixelRgba(x, y, sr, sg, sb, 255);
          }
        }
        continue;
      }
      // 马赛克:填所在**块**的均值,但只填这一格 —— 块对齐保证观感是
      // 整齐的马赛克,按格填保证不越出用户涂的范围(不多盖也不少盖)。
      final bx = cx ~/ bpx * bpx, by = cy ~/ bpx * bpx;
      final (r, g, b) = avg.putIfAbsent(by * w + bx, () => blockAvg(bx, by));
      for (var y = cy; y < cy1; y++) {
        for (var x = cx; x < cx1; x++) {
          src.setPixelRgb(x, y, r, g, b);
        }
      }
    }
  }
  return Uint8List.fromList(img.encodePng(src));
}

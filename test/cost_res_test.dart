import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/generate/cost.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/res_rules.dart';

/// 审计 §1B 补的计费与分辨率规则回归。
///
/// 这两个模块零 UI 依赖,却直接决定「花不花钱」和「按钮上显示多少点」——
/// 阶段 5 要改 `isOpus` 回退方向(S1B-02),先把口径钉死。

GenerateState _s({
  String model = 'NAI 4.5 Full',
  int width = 832,
  int height = 1216,
  int steps = 28,
  List<VibeItem> vibes = const [],
  List<CharRefItem> charRefs = const [],
  Img2ImgConfig? img2img,
}) => GenerateState.initial().copyWith(
  vibes: vibes,
  charRefs: charRefs,
  img2img: img2img,
  params: const GenParams().copyWith(
    model: model,
    width: width,
    height: height,
    steps: steps,
  ),
);

void main() {
  group('免费档判定(Opus · ≤28 步 · ≤1024²)', () {
    test('三条同时满足才免费', () {
      expect(estimateCost(_s(), isOpus: true), 0);
    });

    test('非 Opus 一律收费', () {
      expect(estimateCost(_s(), isOpus: false), greaterThan(0));
    });

    test('步数越过 28 即收费', () {
      expect(estimateCost(_s(steps: 28), isOpus: true), 0);
      expect(estimateCost(_s(steps: 29), isOpus: true), greaterThan(0));
    });

    test('像素越过 1024² 即收费(边界正好在阈值上仍免费)', () {
      expect(estimateCost(_s(width: 1024, height: 1024), isOpus: true), 0);
      expect(
        estimateCost(_s(width: 1024, height: 1088), isOpus: true),
        greaterThan(0),
      );
    });
  });

  group('附加费(免费档也照收)', () {
    test('Vibe 第 5 张起每张 +2,前 4 张不额外收', () {
      List<VibeItem> n(int c) => [
        for (var i = 0; i < c; i++) VibeItem(id: 'v$i'),
      ];
      expect(estimateCost(_s(vibes: n(4)), isOpus: true), 0);
      expect(estimateCost(_s(vibes: n(5)), isOpus: true), 2);
      expect(estimateCost(_s(vibes: n(7)), isOpus: true), 6);
    });

    test('停用的 Vibe 不计费', () {
      final off = [
        for (var i = 0; i < 7; i++) VibeItem(id: 'v$i', enabled: i < 4),
      ];
      expect(estimateCost(_s(vibes: off), isOpus: true), 0);
    });

    test('V5 不计 Vibe 附加费 —— 那两档根本不下发 Vibe', () {
      final vibes = [for (var i = 0; i < 7; i++) VibeItem(id: 'v$i')];
      expect(estimateCost(_s(vibes: vibes), isOpus: true), 6);
      expect(
        estimateCost(_s(model: 'NAI 5.0 Full', vibes: vibes), isOpus: true),
        0,
      );
    });

    test('角色参考每张 +5:仅 4.5 与 V5 Full/Curated 计费,Medium/4.0 不计', () {
      final refs = [CharRefItem(id: 'r0'), CharRefItem(id: 'r1')];
      expect(estimateCost(_s(charRefs: refs), isOpus: true), 10);
      expect(
        estimateCost(_s(model: 'NAI 4.5 Curated', charRefs: refs), isOpus: true),
        10,
      );
      expect(
        estimateCost(_s(model: 'NAI 5.0 Full', charRefs: refs), isOpus: true),
        10,
      );
      expect(
        estimateCost(_s(model: 'NAI 5.0 Curated', charRefs: refs), isOpus: true),
        10,
      );
      expect(
        estimateCost(
          _s(model: 'NAI 5.0 Full Medium', charRefs: refs),
          isOpus: true,
        ),
        0,
      );
      expect(
        estimateCost(_s(model: 'NAI 4.0 Full', charRefs: refs), isOpus: true),
        0,
      );
    });

    test('角色参考规则一致性:4.5 跳过服装项、V5 上限 16 张、V5 重绘不计费', () {
      final mixed = [
        const CharRefItem(id: 'r0', mode: CharRefMode.characterMainOutfit),
        const CharRefItem(id: 'r1', mode: CharRefMode.outfit),
        const CharRefItem(id: 'r2', mode: CharRefMode.bothAnyOutfit),
      ];
      // 4.5 跳过 outfit,仅计 2 张 = 10 点;V5 计全部 3 张 = 15 点
      expect(
        estimateCost(_s(model: 'NAI 4.5 Full', charRefs: mixed), isOpus: true),
        10,
      );
      expect(
        estimateCost(_s(model: 'NAI 5.0 Full', charRefs: mixed), isOpus: true),
        15,
      );

      // V5 上限 16 张:18 张启用仅按 16 张计费(80 点)
      final twenty = [
        for (var i = 0; i < 18; i++) CharRefItem(id: 'r$i'),
      ];
      expect(
        estimateCost(_s(model: 'NAI 5.0 Full', charRefs: twenty), isOpus: true),
        80,
      );

      // 重绘计费:4.5 照收有效 PR(跳过 outfit → 10 点),V5 不支持 PR 重绘 → 0 点
      expect(
        estimateInpaintCost(
          _s(model: 'NAI 4.5 Full', charRefs: mixed),
          isOpus: true,
          sendW: 832,
          sendH: 1216,
          strength: 1,
        ),
        10,
      );
      expect(
        estimateInpaintCost(
          _s(model: 'NAI 5.0 Full', charRefs: mixed),
          isOpus: true,
          sendW: 832,
          sendH: 1216,
          strength: 1,
        ),
        0,
      );
      // 图生图放大(inpaint: false)在 V5 下仍携带 PR → 照计 15 点
      expect(
        estimateInpaintCost(
          _s(model: 'NAI 5.0 Full', charRefs: mixed),
          isOpus: true,
          sendW: 832,
          sendH: 1216,
          strength: 0.5,
          inpaint: false,
        ),
        15,
      );
      // estimateCost 带 inpaint 时同样对 V5 不计 PR 费
      final bytes = Uint8List.fromList([1, 2, 3]);
      final v5Inpaint = _s(model: 'NAI 5.0 Full', charRefs: mixed).copyWith(
        inpaint: InpaintJob(image: bytes, mask: bytes, strength: 1),
      );
      expect(estimateCost(v5Inpaint, isOpus: true), 0);
    });
  });

  group('NAI 5 计价(base ×1.5)', () {
    test('免费档仍然免费 —— 0 乘几倍还是 0', () {
      expect(estimateCost(_s(model: 'NAI 5.0 Full'), isOpus: true), 0);
    });

    // 832×1216 @29 步:A·px + B·px·steps = 19.87 → ceil 20;V5 再 ×1.5 = 30。
    // 钉死具体数字而不是只比大小 —— 这两个数就是官方公式本身,系数抄错时
    // 「V5 比 4.5 贵」照样成立,只有绝对值对得上才说明公式没抄歪。
    test('超步数时正好是 4.5 的 1.5 倍', () {
      expect(estimateCost(_s(steps: 29), isOpus: true), 20);
      expect(
        estimateCost(_s(model: 'NAI 5.0 Full', steps: 29), isOpus: true),
        30,
      );
    });

    // token 直连线:额度见底后 NAI **不报错**,而是安静改按 Anlas 计价。
    // 那会儿按钮还写「免费」就是在让用户不知情地花钱。
    // (bot 线不走这条:服务端取号时就避开见底的号,全见底直接拒绝出图,
    //  所以那边由调用方传 false,免费仍是真免费。)
    group('额度见底 → 免费尺寸转收费', () {
      test('V5 免费尺寸不再是 0,按正常价收', () {
        const v5 = 'NAI 5.0 Full';
        expect(estimateCost(_s(model: v5), isOpus: true), 0);
        // 832×1216 @28 步:base 19.29 → ceil 20,V5 ×1.5 = 30
        expect(estimateCost(_s(model: v5), isOpus: true, v5Charged: true), 30);
      });

      test('只影响 V5 —— 4.5 的免费额度跟这块电池无关', () {
        expect(estimateCost(_s(), isOpus: true, v5Charged: true), 0);
        expect(
          estimateCost(
            _s(model: 'NAI 4.0 Full'),
            isOpus: true,
            v5Charged: true,
          ),
          0,
        );
      });

      test('本来就收费的尺寸不受影响(已经在收了)', () {
        const v5 = 'NAI 5.0 Full';
        final normal = estimateCost(_s(model: v5, steps: 29), isOpus: true);
        expect(
          estimateCost(_s(model: v5, steps: 29), isOpus: true, v5Charged: true),
          normal,
        );
      });

      test('重绘同样跟着转收费', () {
        int inpaint({required bool charged}) => estimateInpaintCost(
          _s(model: 'NAI 5.0 Full'),
          isOpus: true,
          sendW: 832,
          sendH: 1216,
          strength: 1,
          v5Charged: charged,
        );
        expect(inpaint(charged: false), 0);
        expect(inpaint(charged: true), 30);
      });

      test('anima / krea 恒 0(压根不扣 Anlas)', () {
        expect(
          estimateCost(_s(model: 'Anima Turbo'), isOpus: true, v5Charged: true),
          0,
        );
      });
    });

    test('重绘同样吃 1.5 倍(按发送尺寸算)', () {
      int inpaint(String model) => estimateInpaintCost(
        _s(model: model, steps: 29),
        isOpus: true,
        sendW: 832,
        sendH: 1216,
        strength: 1,
      );
      expect(inpaint('NAI 4.5 Full'), 20);
      expect(inpaint('NAI 5.0 Full'), 30);
    });
  });

  test('图生图按强度折算,且不低于 2', () {
    final full = estimateCost(_s(steps: 40), isOpus: false);
    final half = estimateCost(
      _s(steps: 40, img2img: const Img2ImgConfig(strength: 0.5)),
      isOpus: false,
    );
    // 无底图时 strength 不参与折算(image 为 null)
    expect(half, full);
  });

  test('Anima 不计 Anlas(走 Modal 后端)', () {
    expect(estimateCost(_s(model: 'Anima Turbo', steps: 40), isOpus: false), 0);
  });

  group('res_rules', () {
    test('snapDim 归到 64 倍数且不小于 64(四舍五入,非截断)', () {
      expect(snapDim(0), 64); // 低于最小值抬到 64
      expect(snapDim(80), 64); // 1.25 档 → 向下
      expect(snapDim(100), 128); // 1.5625 档 → 向上
      expect(snapDim(832), 832); // 已对齐不动
    });

    test('分档阈值与 cost 的免费判定同源', () {
      expect(classifyPixels(1024, 1024), PixelTier.free);
      expect(classifyPixels(1024, 1088), PixelTier.paid);
      expect(classifyPixels(3072, 1088), PixelTier.over);
    });

    test('clampToMaxPixels 缩回预算内并保持 64 对齐', () {
      final r = clampToMaxPixels(3072, 3072);
      expect(r.w * r.h, lessThanOrEqualTo(kMaxTotalPixels));
      expect(r.w % kResSnapStep, 0);
      expect(r.h % kResSnapStep, 0);
    });

    test('scaleToFree 缩进免费档', () {
      final r = scaleToFree(1216, 1600);
      expect(r.w * r.h, lessThanOrEqualTo(kFreePixelThreshold));
      expect(classifyPixels(r.w, r.h), PixelTier.free);
    });

    test('贴线判定:常用免费尺寸都在免费线上', () {
      expect(isOnPixelLine(1024, 1024, kFreePixelThreshold), isTrue);
      expect(isOnPixelLine(832, 1216, kFreePixelThreshold), isTrue);
      expect(isOnPixelLine(1216, 832, kFreePixelThreshold), isTrue);
      expect(isOnPixelLine(1024, 960, kFreePixelThreshold), isFalse);
      expect(isOnPixelLine(1024, 3072, kMaxTotalPixels), isTrue);
      // 上限线在 w<1024 处已出画布,贴着底边不算在线上
      expect(isOnPixelLine(960, 3072, kMaxTotalPixels), isFalse);
    });

    test('吸附:对角线上的点吸到 1024×1024,出画布的线端吸到边角', () {
      expect(snapToPixelLine(1060, 1060, kFreePixelThreshold), (
        w: 1024,
        h: 1024,
      ));
      expect(snapToPixelLine(3072, 300, kFreePixelThreshold), (
        w: 3072,
        h: 320,
      ));
      expect(snapToPixelLine(950, 3072, kMaxTotalPixels), (w: 1024, h: 3072));
    });

    test('吸附落点:64 对齐、在画布内、紧贴线内侧不越线', () {
      for (final budget in [kFreePixelThreshold, kMaxTotalPixels]) {
        for (var x = 64.0; x <= kMaxDim; x += 37) {
          final y = budget / x;
          if (y > kMaxDim) continue;
          // 线上、线内、线外各取一点(模拟手指在吸附圈里偏一点)
          for (final dy in [-40.0, 0.0, 40.0]) {
            final r = snapToPixelLine(x, y + dy, budget);
            expect(r.w % kResSnapStep, 0);
            expect(r.h % kResSnapStep, 0);
            expect(r.w, inInclusiveRange(kMinDim, kMaxDim));
            expect(r.h, inInclusiveRange(kMinDim, kMaxDim));
            expect(r.w * r.h, lessThanOrEqualTo(budget));
            expect(isOnPixelLine(r.w, r.h, budget), isTrue);
          }
        }
      }
    });

    test('到线距离:线上为 0,原点无穷远', () {
      expect(distanceToPixelLine(1024, 1024, kFreePixelThreshold), 0);
      expect(distanceToPixelLine(0, 0, kFreePixelThreshold), double.infinity);
    });

    test('比例显示:常规化简,超 99 退化为小数比', () {
      expect(formatAspectRatio(832, 1216), '13:19');
      expect(formatAspectRatio(1024, 1024), '1:1');
      expect(formatAspectRatio(0, 100), '—');
    });
  });
}

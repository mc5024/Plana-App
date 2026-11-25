import 'dart:math';

import '../gallery/upscale_model.dart' show enhanceMaxTargetSize;
import 'models.dart';

/// V5 涨价系数。官方前端:base 算完后 `if (family === v5) M *= 1.5`。
///
/// 只作用于 base(大图/高步的那部分),**不作用于**角色参考的 5 点/张、也不作用
/// 于 Vibe 附加费。免费尺寸本就 0 点,乘几倍还是 0 —— 所以「涨价」只有超尺寸/
/// 超步数的图才感受得到。
const _v5Multiplier = 1.5;

/// V5 Full Medium 档:步数那一项再乘的系数(官方前端原值)。
const _mediumStepFactor = 1 / 1.06521739;

/// 单张 base 点数(不含 Vibe / 角色参考附加费,也不含免费档判定与图生图折算)。
///
/// 逐字对齐官方前端 bundle(V5 上线后重扒,2026-08-23,与 web `costCalculator.ts`
/// 及后端 `calculate_anlas_cost` 同源):
///
///     M = ceil(A·px + B·px·steps·k)   // 无 SMEA(V4 起已废弃,本项目全程不发),系数恒 1
///                                     // k:Medium 档 1/1.06521739,其余 1
///     if V5: M *= 1.5
///     max(ceil(M), 2)
///
/// 原来写成 `5.773e-7·px·(steps+5)` 是等价近似(差 <0.4%),但两式在边界上会各自
/// 取整到不同的整数;既然官方原值扒到了就用原值,免得按钮上的预估和账单里记的账
/// 差 1 点 —— 那种差额没法解释,只会让人怀疑两边都不准。
///
/// ⚠ ×1.5 之后必须**再 ceil 一次**:括号里那步已经取整成整数,×1.5 会产生 .5。
int _baseCost(
  int pixels,
  int steps, {
  required bool isV5,
  bool medium = false,
}) {
  final k = medium ? _mediumStepFactor : 1.0;
  var cost =
      (2.951823174884865e-6 * pixels +
              5.753298233447344e-7 * pixels * steps * k)
          .ceilToDouble();
  if (isV5) cost *= _v5Multiplier;
  return max(2, cost.ceil());
}

/// V5 的免费尺寸是否**已经不免费**了。
///
/// V5 免费尺寸图吃的是 Opus 充电式额度([NaiUsage]),额度见底后 NAI **不报错**,
/// 而是安静地改按 Anlas 计价 —— 那会儿还显示「免费」,用户就是在不知情的状态下
/// 花钱。见 `v5ChargedProvider`(只对 token 直连线成立)。
bool _v5NoLongerFree(String model, bool v5Charged) =>
    v5Charged && isNai5Model(model);

/// 单张生成成本预估(对齐 web costCalculator):Opus 且 steps≤28 且
/// 像素≤1048576 免费;否则走 [_baseCost](NAI 5 两档在那里 ×1.5),最低 2。
/// 图生图按强度折算;Vibe 第 5 张起每张 +2、角色参考每张 +5(两者免费档也照收;
/// CR 仅 4.5 模型实际下发,故按模型计费)。
///
/// [v5Charged] = V5 额度已见底,免费尺寸转按 Anlas 计价,见 [_v5NoLongerFree]。
int estimateCost(
  GenerateState s, {
  required bool isOpus,
  bool v5Charged = false,
}) {
  final p = s.params;
  if (isModalModel(p.model)) return 0; // Anima / Krea 走 Modal 后端,不扣 Anlas
  final i2i = s.img2img;
  // Max 放大重绘发原图尺寸,按服务端放大后的尺寸计价
  final out = i2i?.upscaledEnhance == true
      ? enhanceMaxTargetSize(p.width, p.height)
      : (w: p.width, h: p.height);
  final pixels = out.w * out.h;
  final free =
      isOpus &&
      p.naiSteps <= 28 &&
      pixels <= 1048576 &&
      !_v5NoLongerFree(p.model, v5Charged);
  var baseCost = _baseCost(
    pixels,
    p.naiSteps,
    isV5: isNai5Model(p.model),
    medium: isNai5MediumModel(p.model),
  );
  if (i2i?.image != null) baseCost = max(2, (baseCost * i2i!.strength).ceil());
  // 两笔附加费都按**模型是否真会下发**计:V5 不支持 Vibe,精确参考仅 4.5 与
  // V5 Full / Curated 下发(V5 重绘不发、V4.5 跳过服装项、V5 上限 16 张)。
  final vibeExtra = vibeSupportsModel(p.model)
      ? max(0, s.enabledVibes - 4) * 2
      : 0;
  final crExtra =
      effectiveCrRefs(s.charRefs, p.model, inpaint: s.inpaint != null).length *
      5;
  return (free ? 0 : baseCost) + vibeExtra + crExtra;
}

/// 重绘成本预估:同一公式,但像素按**发送尺寸**算(局部=64 对齐后的
/// 裁切框,整图=原图),再按强度折算(对齐 web:局部重绘点数按小区算,
/// Opus 免费判定同样适用)。vibe/CR 附加费按模型及 [inpaint] 能力计收
/// (图生图放大借用此公式时传 `inpaint: false`)。
int estimateInpaintCost(
  GenerateState s, {
  required bool isOpus,
  required int sendW,
  required int sendH,
  required double strength,
  bool v5Charged = false,
  bool inpaint = true,
}) {
  final p = s.params;
  if (isModalModel(p.model)) return 0; // Anima / Krea 走 Modal 后端,不扣 Anlas
  final pixels = sendW * sendH;
  final free =
      isOpus &&
      p.naiSteps <= 28 &&
      pixels <= 1048576 &&
      !_v5NoLongerFree(p.model, v5Charged);
  var baseCost = _baseCost(
    pixels,
    p.naiSteps,
    isV5: isNai5Model(p.model),
    medium: isNai5MediumModel(p.model),
  );
  baseCost = max(2, (baseCost * strength).ceil());
  final vibeExtra = vibeSupportsModel(p.model)
      ? max(0, s.enabledVibes - 4) * 2
      : 0;
  final crExtra =
      effectiveCrRefs(s.charRefs, p.model, inpaint: inpaint).length * 5;
  return (free ? 0 : baseCost) + vibeExtra + crExtra;
}

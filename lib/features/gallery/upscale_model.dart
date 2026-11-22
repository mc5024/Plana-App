import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/store/prefs_store.dart';
import '../generate/models.dart' show EnhanceScale, Img2ImgUpscale, isNai5Model;
export '../generate/models.dart' show EnhanceScale;
import '../../l10n/l10n.dart';

/// 放大方式。全部走 NAI 远程、全部扣点 —— 本地 ncnn-vulkan 超分已于
/// 2026-08-24 整条砍掉(连 18MB 的 Real-ESRGAN native 一起),不再有离线档。
enum UpscaleMethod {
  /// NAI V5 扩散超分(image 子域,固定 2×,**输入尺寸无白名单**,按源图 1–4 点)。
  ///
  /// 旧的传统 4× 超分(api 子域、只收三种固定尺寸、固定 7 点)官方已下线,
  /// 2026-08-31 从本 app 整条摘掉 —— 存量偏好里那个 `nai` 由 [UpscaleSettings]
  /// 的 orElse 落到这一档。
  naiV5(badge: '2x', factor: 2),

  /// NAI 图生图重绘放大(倍率可选,会轻微改画面;走生成管线,扣点)。
  /// 倍率见 [EnhanceScale],所以 [factor] 无意义。
  redraw(badge: '1~2x', factor: 0);

  const UpscaleMethod({required this.badge, required this.factor});

  String get label => switch (this) {
    naiV5 => l10nNow.upscaleV5,
    redraw => l10nNow.redrawUpscale,
  };

  /// 角标里的倍率文案。
  final String badge;

  /// 固定倍率;0 = 由别处决定([redraw] 走 [EnhanceScale])。
  final int factor;
}

// ==================== NAI V5 扩散超分 ====================

/// 生成 / 超分的总像素上限(官方 3,145,728 = 1024×3072)。
const kNaiMaxPixels = 1024 * 3072;

/// V5 扩散超分的点数:官方按**源图**像素查表 1–4 点(与生成那套公式无关)。
/// 超过总像素上限官方不受理,返回 null。
int? naiV5UpscalePrice(int w, int h) {
  final px = w * h;
  if (px <= 0) return null;
  for (final e in const [
    (1048576, 1),
    (1747627, 2),
    (2446678, 3),
    (kNaiMaxPixels, 4),
  ]) {
    if (px <= e.$1) return e.$2;
  }
  return null;
}

/// 当前尺寸能否走 V5 超分。**没有分辨率白名单**,只卡源图总像素。
bool naiV5UpscaleSupportsSize(int w, int h) => naiV5UpscalePrice(w, h) != null;

/// V5 扩散超分的结果尺寸:**先把边长向下对齐到 16 的倍数,再 ×2**。
///
/// ⚠ 和放大重绘的 Max 档不一样,这里**没有总像素上限**(实测 1400×1200 →
/// 2784×2400 = 6.68M 像素,远超生成管线那个 3,145,728)。上限只卡在**源图**
/// 那一侧 —— 官方价格表对超过 3,145,728 的源图直接返回「不可用」。
/// 所以别拿 [enhanceMaxTargetSize] 来算这个,那个是会缩回上限的。
({int w, int h}) naiV5UpscaleTargetSize(int w, int h) =>
    (w: (w ~/ 16) * 16 * 2, h: (h ~/ 16) * 16 * 2);

// ==================== 图生图放大(重绘)的倍率档 ====================

/// 重绘默认强度/噪声(对齐 web MAGNITUDE_PRESETS 档 3)。
const kRedrawStrength = 0.5;
const kRedrawNoise = 0.0;

/// 官方阈值:源图像素必须小于 0.8×上限,才提供 Max 档。
const kEnhanceMaxSourceLimit = 2516582.4;

/// 832×1216 / 1216×832 —— 官方对这两个最常用尺寸做了特判,见 [enhanceScaleOptions]。
bool _isPortraitStd(int w, int h) =>
    (w == 832 && h == 1216) || (w == 1216 && h == 832);

/// 放大重绘 Max 档的结果尺寸 —— 逐行照抄官方 `RO()`。
///
/// ⚠ 不是「等比放大到总像素上限」。实测 512×512 的源图,服务端返回的是 1024×1024,
/// 正是这个函数算出来的值;按「放到上限」算会得到 1774×1774,价格预估高出三倍。
/// 规则实际是:**先向下对齐到 16 的倍数再 ×2**,只有超过总像素上限时才等比缩回,
/// 最后对齐到 32。
({int w, int h}) enhanceMaxTargetSize(int w, int h) {
  const mult = 2;
  const step = 8 * mult;
  final tw = (w ~/ step) * step * mult;
  final th = (h ~/ step) * step * mult;
  if (tw <= 0 || th <= 0) return (w: 0, h: 0);
  final k = min(1.0, sqrt(kNaiMaxPixels / (tw * th)));
  var outW = 32 * ((tw * k) / 32).round();
  var outH = 32 * ((th * k) / 32).round();
  if (outW * outH > kNaiMaxPixels) {
    outW = 32 * ((tw * k) / 32).floor();
    outH = 32 * ((th * k) / 32).floor();
  }
  return (w: outW, h: outH);
}

/// 图生图放大的结果尺寸。
///
/// 官方对数值倍率就是 `floor(边长 × 倍率)`,不额外对齐 —— 因为它只在**结果本来
/// 就 64 对齐**的前提下才放出那一档(见 [enhanceScaleOptions])。唯一的例外是
/// 832×1216 那两个特判尺寸:1.5× 出来是 1248×1824,并非 64 对齐,官方照发。
///
/// 我们比官方多一种情况:**用户可以导入任意尺寸的图**。那种图 floor 出来往往不
/// 对齐,直接发会被拒,所以这里补一次对齐。
({int w, int h}) enhanceTargetSize(int w, int h, EnhanceScale scale) {
  final f = scale.factor;
  if (f == null) return enhanceMaxTargetSize(w, h);
  final tw = (w * f).floor();
  final th = (h * f).floor();
  if ((tw % 64 == 0 && th % 64 == 0) || _isPortraitStd(w, h)) {
    return (w: tw, h: th);
  }
  return (
    w: max(64, (tw / 64).round() * 64),
    h: max(64, (th / 64).round() * 64),
  );
}

/// Max 档是否可用:只有 V5 有 maxEnhance 能力,且源图不能太大。
bool enhanceMaxAvailable(int w, int h, String displayModel) {
  final px = w * h;
  if (px <= 0 || px >= kEnhanceMaxSourceLimit) return false;
  return isNai5Model(displayModel);
}

/// 当前图片能选哪些放大倍率 —— 逐条照抄官方的筛选规则。
///
/// 规则本身有三处不直观:
/// 1. **必须 64 对齐**:`w×s` 和 `h×s` 都得是 64 的倍数,否则那一档不出现。
/// 2. **832×1216 / 1216×832 特判**成 1.5× / 1×。这两个是最常用的尺寸,而
///    832×1.5 = 1248 并不是 64 的倍数,按通则会被筛掉、只剩 1× —— 官方直接写死绕开。
/// 3. **1× = 同尺寸重绘**(只精修不放大),官方一直有这一档。
///
/// 我们比官方多一步兜底:官方的图永远是它自己生成的、必然 64 对齐,而我们允许
/// 导入任意尺寸的图 —— 那种图按通则会被筛得一档不剩。所以全空时仍给这几档,
/// 由 [enhanceTargetSize] 补对齐。
List<EnhanceScale> enhanceScaleOptions(int w, int h, String displayModel) {
  bool fits(EnhanceScale s) {
    final t = enhanceTargetSize(w, h, s);
    return t.w > 0 && t.h > 0 && t.w * t.h <= kNaiMaxPixels;
  }

  bool aligned(EnhanceScale s) =>
      (w * s.factor!) % 64 == 0 && (h * s.factor!) % 64 == 0;

  const numeric = [EnhanceScale.x2, EnhanceScale.x15, EnhanceScale.x1];
  var base = _isPortraitStd(w, h)
      ? const [EnhanceScale.x15, EnhanceScale.x1]
      : [
          for (final s in numeric)
            if (fits(s) && aligned(s)) s,
        ];
  if (base.isEmpty) {
    base = [
      for (final s in numeric)
        if (fits(s)) s,
    ];
  }
  return [
    if (enhanceMaxAvailable(w, h, displayModel)) EnhanceScale.max,
    ...base,
  ];
}

/// 图生图放大实际用的倍率:存的那档当前模型给不了(Max 只有 V5)时,落到可用的头一个数值档。
EnhanceScale effectiveEnhanceScale(Img2ImgUpscale u, String model) {
  final opts = enhanceScaleOptions(u.srcW, u.srcH, model);
  if (opts.contains(u.scale)) return u.scale;
  return opts.firstWhere(
    (s) => s.factor != null,
    orElse: () => EnhanceScale.x1,
  );
}

/// 图生图放大的发送尺寸:Max 发原图尺寸(服务端放大),数值档即 [enhanceTargetSize]。
({int w, int h}) img2imgUpscaleSendSize(
  EnhanceScale scale,
  int srcW,
  int srcH,
) => scale.factor == null
    ? (w: srcW, h: srcH)
    : enhanceTargetSize(srcW, srcH, scale);

// ==================== 面板的参数(整体持久化) ====================

/// 官方 Magnitude 五档:点一下同时设好强度与噪声,两个滑杆仍可继续微调。
/// 档 3 就是改成可调之前写死的那组值(0.5 / 0),所以老用户的手感不变。
const kMagnitudePresets = <({String label, double strength, double noise})>[
  (label: '1', strength: 0.2, noise: 0),
  (label: '2', strength: 0.4, noise: 0),
  (label: '3', strength: kRedrawStrength, noise: kRedrawNoise),
  (label: '4', strength: 0.6, noise: 0),
  (label: '5', strength: 0.7, noise: 0.1),
];

/// 强度/噪声正好命中哪一档 Magnitude;都不命中(手动微调过)= -1。
int magnitudeIndexOf(double strength, double noise) {
  for (var i = 0; i < kMagnitudePresets.length; i++) {
    final m = kMagnitudePresets[i];
    if ((m.strength - strength).abs() < 1e-6 &&
        (m.noise - noise).abs() < 1e-6) {
      return i;
    }
  }
  return -1;
}

/// 放大面板的全部选择。一次性持久化,下次打开原样恢复。
///
/// [method] 决定走哪条支路,其余三个只对重绘放大有意义。合成一个对象存是因为
/// 它们本来就是「上次怎么放大的」这一件事 —— 拆成四个 provider 只会让读写点散开。
class UpscaleSettings {
  const UpscaleSettings({
    this.method = UpscaleMethod.naiV5,
    this.enhanceScale = EnhanceScale.x15,
    this.strength = kRedrawStrength,
    this.noise = kRedrawNoise,
  });

  final UpscaleMethod method;
  final EnhanceScale enhanceScale;
  final double strength;
  final double noise;

  UpscaleSettings copyWith({
    UpscaleMethod? method,
    EnhanceScale? enhanceScale,
    double? strength,
    double? noise,
  }) => UpscaleSettings(
    method: method ?? this.method,
    enhanceScale: enhanceScale ?? this.enhanceScale,
    strength: strength ?? this.strength,
    noise: noise ?? this.noise,
  );

  /// 当前强度/噪声正好命中哪一档 Magnitude;都不命中(手动微调过)= -1。
  int get magnitudeIndex => magnitudeIndexOf(strength, noise);

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'enhanceScale': enhanceScale.name,
    'strength': strength,
    'noise': noise,
  };

  factory UpscaleSettings.fromJson(Map<String, dynamic> j) {
    // `redraw15x` 是重绘那一档改成可选倍率之前的名字,存量偏好照样认。
    // `localFast` / `localQuality`(砍掉的本地超分)与 `nai`(官方已下线的
    // 传统 4×)都没有对应档位了,由下面的 orElse 落到 V5 超分。
    final m = j['method'] == 'redraw15x' ? 'redraw' : j['method'];
    return UpscaleSettings(
      method: UpscaleMethod.values.firstWhere(
        (e) => e.name == m,
        orElse: () => UpscaleMethod.naiV5,
      ),
      enhanceScale: EnhanceScale.values.firstWhere(
        (e) => e.name == j['enhanceScale'],
        orElse: () => EnhanceScale.x15,
      ),
      strength: ((j['strength'] as num?)?.toDouble() ?? kRedrawStrength).clamp(
        kStrengthMin,
        kStrengthMax,
      ),
      noise: ((j['noise'] as num?)?.toDouble() ?? kRedrawNoise).clamp(
        0.0,
        kNoiseMax,
      ),
    );
  }
}

/// 强度/噪声的可调范围(对齐 web 两个滑杆的 min/max/step)。
const kStrengthMin = 0.1;
const kStrengthMax = 1.0;
const kNoiseMax = 0.5;

const _key = 'upscale_settings';
const _legacyMethodKey = 'upscale_method';

/// 放大面板的参数(持久化)。
final upscaleSettingsProvider =
    AsyncNotifierProvider<UpscaleSettingsNotifier, UpscaleSettings>(
      UpscaleSettingsNotifier.new,
    );

class UpscaleSettingsNotifier extends AsyncNotifier<UpscaleSettings> {
  PrefsStore get _storage => ref.read(prefsStoreProvider);

  @override
  Future<UpscaleSettings> build() async {
    try {
      final v = await _storage.read(key: _key);
      if (v != null && v.isNotEmpty) {
        return UpscaleSettings.fromJson(jsonDecode(v) as Map<String, dynamic>);
      }
      // 迁移:参数合并成一个对象之前只存了「上次用哪种方式」这一项。
      final legacy = await _storage.read(key: _legacyMethodKey);
      if (legacy != null && legacy.isNotEmpty) {
        return UpscaleSettings.fromJson({'method': legacy});
      }
    } catch (_) {} // 损坏按默认处理
    return const UpscaleSettings();
  }

  Future<void> set(UpscaleSettings s) async {
    state = AsyncData(s);
    try {
      await _storage.write(key: _key, value: jsonEncode(s.toJson()));
    } catch (_) {} // 写失败只影响下次恢复,不打扰这一次放大
  }
}

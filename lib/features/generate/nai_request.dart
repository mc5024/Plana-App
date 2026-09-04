import 'dart:convert';
import 'dart:math';

import '../../core/util/transparency.dart';
import 'auto_text.dart';
import 'char_position.dart';
import 'models.dart';
import 'prompt_presets.dart'
    show builtinPresetHasPositive, promptPresetTagHints, ucPresetValue;

/// UI 展示名 → NAI 模型 id
const _modelMap = <String, String>{
  // NAI 5 是按命名惯例猜的**占位 id**(官方未公布)。真实 id 不同也不用发版:
  // 后端 convert_web_params_to_stream 的 model_map 本就是「别名 → 真实 id」
  // 重写层(v4.5-full 就是这么映射的),上线时后端加一行把这俩改写掉即可。
  // 千万别漏了这张表只加 models.nai5Models —— naiModelId 对未知名兜底 4.5,
  // 那会静默生成错模型,是最难查的一类错。
  'NAI 5.0 Full': 'nai-diffusion-5-full',
  'NAI 5.0 Curated': 'nai-diffusion-5-curated',
  'NAI 4.5 Full': 'nai-diffusion-4-5-full',
  'NAI 4.5 Curated': 'nai-diffusion-4-5-curated',
  'NAI 4.0 Full': 'nai-diffusion-4-full',
  'NAI 4.0 Curated': 'nai-diffusion-4-curated-preview',
};

/// UI 展示名 → NAI 模型 id(编码 vibe 时也要用同一 id)。
String naiModelId(String displayModel) =>
    _modelMap[displayModel] ?? 'nai-diffusion-4-5-full';

/// 生成模型 id → inpainting 模型 id(对齐 web 后端:v3 特例,其余直接拼接)。
String inpaintModelId(String modelId) {
  if (modelId == 'nai-diffusion-3') return 'nai-diffusion-3-inpainting';
  // V5 Curated 重绘模型官方尚未上线,回退 V4.5 Curated 重绘(对齐 web novelai.ts);
  // V5 Full 重绘已上线,正常拼 -inpainting。
  if (modelId == 'nai-diffusion-5-curated') {
    return 'nai-diffusion-4-5-curated-inpainting';
  }
  return '$modelId-inpainting';
}

/// 该 **API 模型 id** 是否支持透明输出(官方能力表 transparency)。只有 V5 有。
///
/// 注意这个能力**不控制**要不要透明 —— 透明由提示词里的 `transparent background`
/// 触发(见 [anyPromptHasTransparentBackground])。它只决定 `straight_alpha` 要不要发。
bool naiSupportsTransparency(String modelId) =>
    modelId.startsWith('nai-diffusion-5');

/// UI 展示名 → NAI 采样器串(bot 模式构造 web 参数时复用同一映射)。
String naiSamplerId(String displaySampler) =>
    _samplerMap[displaySampler] ?? 'k_euler_ancestral';

/// 一个已编码的 vibe 参考:编码串 + 参考强度。
typedef EncodedVibe = ({String encoded, double strength});

/// 均衡强度:多张 Vibe 且合计 >1 时按比例缩到合计 1(规则与 web 一致)。
///
/// 两条线都得自己算 —— NAI 的 `normalize_reference_strength_multiple` 只对
/// 缓存模式生效,直传编码串时它不会动手;后端 `convert_web_params_to_stream`
/// 也只是把这个标记原样转发。标记照发,真活在这儿干。
List<double> normalizeVibeStrengths(
  List<double> strengths, {
  required bool on,
}) {
  if (!on || strengths.length <= 1) return strengths;
  final total = strengths.fold<double>(0, (a, b) => a + b);
  return total > 1 ? [for (final s in strengths) s / total] : strengths;
}

/// 图生图参考:已 cover 到目标分辨率的 PNG base64 + 强度 + 噪声。
/// [upscaledEnhance] = Max ✨ 放大重绘(见 [Img2ImgConfig.upscaledEnhance])。
typedef Img2ImgRef = ({
  String image,
  double strength,
  double noise,
  bool upscaledEnhance,
});

/// 一个待发的角色参考:已 contain 处理的 PNG base64 + 模式串 + 强度 + 保真度。
typedef CharRefPayload = ({
  String image,
  String mode,
  double strength,
  double fidelity,
});

/// UI 展示名 → NAI 采样器串
const _samplerMap = <String, String>{
  'Euler Ancestral': 'k_euler_ancestral',
  'Euler': 'k_euler',
  'DPM++ 2S A': 'k_dpmpp_2s_ancestral',
  'DPM++ 2M SDE': 'k_dpmpp_2m_sde',
  'DPM++ 2M': 'k_dpmpp_2m',
  'DPM++ SDE': 'k_dpmpp_sde',
};

/// 存量存档迁移用的旧「AUTO」坐标表 —— **不要用在新逻辑里**。
///
/// 2026-09-04 之前没有全局 use_coords 开关:恒发 `true`,而「AUTO」是每个角色
/// 各自的一个档位,发送时按角色下标从这张表里代一个坐标进去。那是我们自己发明
/// 的模型,官方没有(官方是位置区块上的 AI's Choice / Custom 全局二选一,新角色
/// 建的时候就有具体坐标)。
///
/// 现在只剩一个用途:把老存档里 `position == null` 的角色**按原样**补回坐标,
/// 让老提示词还能复现出同一张图。新角色一律走 [nextSpawnPosition]。
const kLegacyAutoCenters = <Map<String, double>>[
  {'x': 0.3, 'y': 0.5},
  {'x': 0.7, 'y': 0.5},
  {'x': 0.5, 'y': 0.3},
  {'x': 0.5, 'y': 0.7},
  {'x': 0.3, 'y': 0.3},
  {'x': 0.7, 'y': 0.7},
];

/// 角色中心点:网格 id('A1'..'E5')与自由坐标串('x,y',V5)统一解析。
///
/// 角色建出来就带坐标(见 GenerateNotifier._spawnPos),所以正常不会走到兜底;
/// 真解不出来时回落正中 —— 官方 25 格占满时也是这么兜的。
/// 「不指定站位」现在由全局 `use_coords=false` 表达,不再靠每个角色的空值。
Map<String, double> _center(String? pos) {
  final c = resolveCharacterCenter(pos);
  return c != null ? {'x': c.x, 'y': c.y} : {'x': 0.5, 'y': 0.5};
}

/// 由创作页状态构造 NAI `/ai/generate-image-stream` 请求体(镜像 web `services/novelai.ts`)。
/// 返回体 + 实际使用的种子(留空随机时也已定值,便于图库回显)。已覆盖:
/// 文生图 + 多角色带位置 + Vibe + 图生图 + 角色参考(4.5)+ 重绘(infill)。
({Map<String, dynamic> body, int seed}) buildNaiPayload(
  GenerateState s, {
  required String presetId,

  /// 「开了质量标签」= 激活的预设带正面文本(web `!!activePreset?.positive`)。
  /// 单靠 [presetId] 答不上来:自定义预设不在内置表里。调用方拿得到预设对象时
  /// 请传进来,不传则按内置表推断(对五个内置档恒正确)。
  bool? qualityToggle,

  /// 透明图的 alpha 编码约定(true=直通 Straight / false=预乘 Premultiplied)。
  /// 官方默认直通,见生成设置里的同名开关。
  bool straightAlpha = true,
  List<EncodedVibe> vibes = const [],
  Img2ImgRef? img2img,
  List<CharRefPayload> charRefs = const [],
}) {
  final p = s.params;
  final inpaint = s.inpaint;
  final model = naiModelId(p.model);
  // ⚠ **最终要发的** model,不是面板上选的:V5 Curated 的重绘会回退到 4.5
  //   Curated Inpainting。两处按能力分叉都得看它 —— 透明输出(transparency)、
  //   角色坐标要不要吸附到格心(freeformCharacterPosition)。载荷**结构**仍按
  //   底模判(下面的 isV4/isV5),那跟能力是两回事。
  final sendModel = inpaint != null ? inpaintModelId(model) : model;
  final sampler = _samplerMap[p.sampler] ?? 'k_euler_ancestral';
  final isV4 = model.startsWith('nai-diffusion-4');
  // V5 载荷与 V4/V4.5 同构:仍用 v4_prompt/v4_negative_prompt 结构化提示词,
  // 仅 params_version 3→4(见下)。二者共用同一套结构化提示词分支。
  final isV5 = model.startsWith('nai-diffusion-5');
  final usesV4Prompt = isV4 || isV5;

  final seedStr = p.seed.trim();
  final seed = seedStr.isEmpty
      ? Random().nextInt(4294967296)
      : (int.tryParse(seedStr) ?? Random().nextInt(4294967296));

  // 仅启用且有正向内容的角色参与
  final chars = s.characters
      .where((c) => c.enabled && c.positive.trim().isNotEmpty)
      .toList();
  // 官方的 use_coords 是位置区块上的 AI's Choice / Custom 全局二选一,**默认
  // false**。早先这里恒发 `chars.isNotEmpty`,那是我们自己的模型,不是官方行为。
  final useCoords = s.params.useCoords;
  final centers = [for (final c in chars) _center(c.position)];
  // 只有 V5 吃自由坐标(官方能力位 freeformCharacterPosition);其余模型官方在
  // 发送前把坐标吸附到 5×5 格心,存着的值不动。char_captions 发吸附后的,
  // characterPrompts 仍发原始坐标 —— 那是给导入回放用的,不该被这次请求对模型
  // 的迁就改掉(同官方)。
  final sentCenters = sendModel.startsWith('nai-diffusion-5')
      ? centers
      : centers.map((c) {
          final q = quantizeCenterToGrid(c['x']!, c['y']!);
          return {'x': q.x, 'y': q.y};
        }).toList();

  // autoText:引号内容自动转 `text:` 块,仅 V5 有这项能力。
  // 排在 centers 算完之后 —— 阅读顺序排序要用到每个角色的坐标。
  // s.prompt 到这里**已经拼过预设**(controller 的 _applyPreset),与 web 同序。
  final promptText = isV5
      ? applyAutoText(
          s.prompt,
          characters: [
            for (var i = 0; i < chars.length; i++)
              AutoTextChar(
                prompt: chars[i].positive,
                center: (x: centers[i]['x']!, y: centers[i]['y']!),
              ),
          ],
          useCoords: useCoords,
        )
      : s.prompt;

  // 档位提示:官方导入这张图时靠它决定「先试哪个档去把预设文本剥回去」。
  final tagHints = promptPresetTagHints(presetId);

  // 透明背景:由提示词里的 `transparent background` 触发,不是开关。
  // straight_alpha 跟官方一样「只要模型支持就无条件发」—— 它只是 alpha 的编码
  // 约定,跟这次到底透不透明无关;tag_hint 才是记录「这张是不是透明图」的那个。
  // 按 sendModel 判:4.5 Curated Inpainting 没有 transparency 能力,不该跟着发。
  final canTransparent = naiSupportsTransparency(sendModel);

  final params = <String, dynamic>{
    'params_version': isV5 ? 4 : 3,
    'width': p.width,
    'height': p.height,
    'scale': p.cfg,
    'sampler': sampler,
    'steps': p.steps,
    'n_samples': 1,
    // 下标按**最终要发的**模型算(重绘会换模型,数组长度可能跟着变);
    // 预设正/负前缀已在 controller 拼进 s
    'ucPreset': ucPresetValue(presetId, sendModel),
    'qualityToggle': qualityToggle ?? builtinPresetHasPositive(presetId),
    'tag_hint_qt': tagHints.qt,
    'tag_hint_uc_preset': tagHints.ucPreset,
    // Max ✨ 放大重绘:只有为真时才发。非 Max 路径带一个 false 会让官方按普通
    // img2img 处理,而这字段对老模型本就无意义,干脆不发。
    if (img2img?.upscaledEnhance == true) 'upscaled_enhance': true,
    if (canTransparent) ...{
      'straight_alpha': straightAlpha,
      'tag_hint_transparent_background': anyPromptHasTransparentBackground(
        promptText,
        [for (final c in chars) c.positive],
      ),
    },
    'autoSmea': false,
    'dynamic_thresholding': false,
    'controlnet_strength': 1,
    'legacy': false,
    'add_original_image': true,
    'cfg_rescale': p.cfgRescale,
    // 官方能力表里 V5 的 noiseSchedule / cfgDelay 都是 false:请求清洗会先删掉
    // noise_schedule 再硬写回 karras,skip_cfg_above_sigma 直接删。照它来 ——
    // 用户切到 V5 之前留下的值不该被带进来(bot 线由后端兜同一道)。
    'noise_schedule': isV5 ? 'karras' : p.noiseSchedule,
    'legacy_v3_extend': false,
    // Variety+ = 固定值 58(与 web 一致),关闭则 null
    'skip_cfg_above_sigma': isV5 || !p.varietyPlus ? null : 58,
    'use_coords': useCoords,
    'normalize_reference_strength_multiple': p.normalizeVibe,
    'inpaintImg2ImgStrength': 1,
    'seed': seed,
    'legacy_uc': false,
    'negative_prompt': s.negativePrompt,
    'deliberate_euler_ancestral_bug': false,
    'prefer_brownian': true,
    'image_format': 'png',
    'stream': 'msgpack',
  };

  // v4/v4.5/v5 共用的结构化提示词(v5 仍用 v4_prompt,仅 params_version 不同);
  // v3 走经典字段即可。
  if (usesV4Prompt) {
    params['v4_prompt'] = {
      'caption': {
        'base_caption': promptText,
        'char_captions': [
          for (var i = 0; i < chars.length; i++)
            {
              'char_caption': chars[i].positive.trim(),
              'centers': [sentCenters[i]],
            },
        ],
      },
      'use_coords': useCoords,
      'use_order': true,
    };
    params['v4_negative_prompt'] = {
      'caption': {
        'base_caption': s.negativePrompt,
        // 仅对负向非空的角色加(与 web 一致)
        'char_captions': [
          for (var i = 0; i < chars.length; i++)
            if (chars[i].negative.trim().isNotEmpty)
              {
                'char_caption': chars[i].negative.trim(),
                'centers': [sentCenters[i]],
              },
        ],
      },
      'legacy_uc': false,
    };
    params['characterPrompts'] = [
      for (var i = 0; i < chars.length; i++)
        {
          'enabled': true,
          'prompt': chars[i].positive.trim(),
          'uc': chars[i].negative.trim(),
          'center': centers[i],
        },
    ];
  }

  // Vibe 参考:编码串 + 强度。生成不发 info_extracted。
  if (vibes.isNotEmpty) {
    params['reference_image_multiple'] = [for (final v in vibes) v.encoded];
    params['reference_strength_multiple'] = normalizeVibeStrengths([
      for (final v in vibes) v.strength,
    ], on: p.normalizeVibe);
  }

  // 角色参考(Director/Precise Reference):仅 4.5 模型下发,其余静默不发。
  // 五个并列数组;information_extracted 恒 1;secondary_strength = 1 - fidelity。
  if (charRefs.isNotEmpty && crSupportsModel(p.model)) {
    params['director_reference_images'] = [for (final c in charRefs) c.image];
    params['director_reference_descriptions'] = [
      for (final c in charRefs)
        {
          'caption': {'base_caption': c.mode, 'char_captions': <dynamic>[]},
          'legacy_uc': false,
        },
    ];
    params['director_reference_information_extracted'] = [
      for (final _ in charRefs) 1,
    ];
    params['director_reference_strength_values'] = [
      for (final c in charRefs) c.strength,
    ];
    params['director_reference_secondary_strength_values'] = [
      for (final c in charRefs) 1 - c.fidelity,
    ];
  }

  // 重绘(infill):底图+黑白 mask(白=重绘),模型换 -inpainting;
  // 与图生图互斥且优先(对齐 web 后端 convert_web_params_to_stream)。
  if (inpaint != null) {
    params['image'] = base64Encode(inpaint.image);
    params['mask'] = base64Encode(inpaint.mask);
    params['strength'] = inpaint.strength;
    params['noise'] = 0;
    params['extra_noise_seed'] = seed;
  } else if (img2img != null) {
    // 图生图:action 改 img2img,底图(已 cover 到目标分辨率)+ 强度/噪声/噪声种子。
    params['image'] = img2img.image;
    params['strength'] = img2img.strength;
    params['noise'] = img2img.noise;
    params['extra_noise_seed'] = seed;
  }

  final body = <String, dynamic>{
    'input': promptText,
    'model': sendModel,
    'action': inpaint != null
        ? 'infill'
        : (img2img != null ? 'img2img' : 'generate'),
    'use_new_shared_trial': true,
    'parameters': params,
  };
  return (body: body, seed: seed);
}

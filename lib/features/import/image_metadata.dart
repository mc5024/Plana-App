import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/util/prompt_convert.dart' show stripInlineTags;

/// 图片元数据解析。移植自 web 桌面端 `utils/imageMetadata.ts`:
/// 支持 PNG tEXt/iTXt 块(NovelAI Comment / SD parameters / ComfyUI prompt)、
/// EXIF UserComment(WebP/JPEG)与 NovelAI alpha 通道 LSB 隐写(stealth_pngcomp)。

/// 图片来源类型:决定可导入的内容(仅 novelai 可导入角色/Vibe/生成设置)。
enum ImageSourceType { novelai, stableDiffusion, comfyui, unknown }

/// 提示词的权重方言。编辑器里存的始终是 NAI 语法,
/// 导入 a1111 语法(SD/ComfyUI)时才需要转换,转不转由导入目标决定。
enum PromptSyntax { nai, a1111 }

/// Lora 信息(SD/ComfyUI 提示词内联)。
class LoraInfo {
  const LoraInfo({
    required this.name,
    required this.weight,
    this.clipWeight,
    this.hash,
  });
  final String name;
  final double weight;

  /// `<lora:名:unet:clip>` 的第二个权重(A1111 双权重语法),null=跟随 weight。
  final double? clipWeight;

  /// 来自 `Lora hashes` 字段的 SHA256 前缀(通常 12 位)——跨部署认领 LoRA 的身份证。
  /// 图里的 lora_name 只是某个部署的内部编号(web/LRxx),换台机器就认不出。
  final String? hash;

  LoraInfo copyWith({String? hash}) => LoraInfo(
    name: name,
    weight: weight,
    clipWeight: clipWeight,
    hash: hash ?? this.hash,
  );
}

/// 元数据里的一个 Vibe。image=原始图 base64;encoding=纯编码;
/// needsLocalMatch=只有强度/IE 参数、需靠本地库匹配(无法直接导入)。
class VibeMeta {
  const VibeMeta({
    this.image,
    this.encoding,
    required this.strength,
    this.informationExtracted,
    this.needsLocalMatch = false,
  });

  final String? image;
  final String? encoding;
  final double strength;
  final double? informationExtracted;
  final bool needsLocalMatch;
}

/// 元数据里的一个角色提示词(含可选坐标与角色负向)。
class CharacterMeta {
  const CharacterMeta({
    required this.prompt,
    this.uc,
    this.centerX,
    this.centerY,
  });
  final String prompt;
  final String? uc;
  final double? centerX;
  final double? centerY;
}

/// 解析后的完整元数据。
class ImageMetadata {
  const ImageMetadata({
    required this.source,
    required this.sourceType,
    this.promptSyntax = PromptSyntax.nai,
    required this.prompt,
    required this.negativePrompt,
    required this.width,
    required this.height,
    required this.seed,
    this.steps,
    this.sampler,
    this.scale,
    this.noiseSchedule,
    this.cfgRescale,
    this.varietyPlus,
    this.tagHintQt,
    this.tagHintUcPreset,
    this.transparentBackground,
    this.straightAlpha,
    this.useCoords,
    this.characters = const [],
    this.vibes = const [],
    this.loras = const [],
    this.raw,
  });

  final String source;
  final ImageSourceType sourceType;

  /// 提示词原文的权重语法(默认 nai,兼容历史/手工构造的元数据)。
  final PromptSyntax promptSyntax;
  final String prompt;
  final String negativePrompt;
  final int width;
  final int height;
  final String seed;
  final String? steps;
  final String? sampler; // NAI 为 API id(如 k_euler_ancestral)
  final String? scale;
  final String? noiseSchedule;
  final String? cfgRescale;

  /// 多样性(Variety+):NAI 写 skip_cfg_above_sigma,数值=开、null=关;
  /// 字段整个缺失(老图)为 null,表示不可知、面板不显示该行。
  final bool? varietyPlus;

  /// 这张图是不是「按我摆的位置」出的(`v4_prompt.use_coords`)。
  /// `false` = 官方的 AI's Choice:坐标照写进元数据,但模型没理会。
  /// 不是 V4+ 的图(V3 / 非 NAI)则为 null。
  final bool? useCoords;

  /// 官方的档位提示:`tag_hint_qt`(质量档)/ `tag_hint_uc_preset`(负面档)。
  /// 导入时用来把预设候选排到队首 —— 只是提示,最终仍以「能不能把预设文本
  /// 干净剥掉」为准(见 `detectPromptPreset`)。老图/外部图没有这两个字段。
  final int? tagHintQt;
  final int? tagHintUcPreset;

  /// 透明背景(V5)。`tag_hint_transparent_background` 记录「这张图是不是带着
  /// `transparent background` 生成的」,`straight_alpha` 是 alpha 的编码约定
  /// (true=直通 / false=预乘)。老图和非 V5 图没有这两个字段,为 null。
  ///
  /// 导入时**不**拿它去改提示词 —— 那个 tag 本来就在提示词里,剥掉质量词后会
  /// 原样留下,用户再生成一次照样是透明的。这两个字段只用于展示与排查。
  final bool? transparentBackground;
  final bool? straightAlpha;

  final List<CharacterMeta> characters;
  final List<VibeMeta> vibes;
  final List<LoraInfo> loras;

  /// 原始解析对象(3b「原始数据」展示 + 复制用)。
  final Object? raw;

  bool get isNovelAI => sourceType == ImageSourceType.novelai;

  /// 换一份 LoRA 清单(ComfyUI 图用 A1111 块里的真名+哈希覆盖内部编号)。
  ImageMetadata copyWithLoras(List<LoraInfo> newLoras) => ImageMetadata(
    source: source,
    sourceType: sourceType,
    promptSyntax: promptSyntax,
    prompt: prompt,
    negativePrompt: negativePrompt,
    width: width,
    height: height,
    seed: seed,
    steps: steps,
    sampler: sampler,
    scale: scale,
    noiseSchedule: noiseSchedule,
    cfgRescale: cfgRescale,
    varietyPlus: varietyPlus,
    useCoords: useCoords,
    tagHintQt: tagHintQt,
    tagHintUcPreset: tagHintUcPreset,
    transparentBackground: transparentBackground,
    straightAlpha: straightAlpha,
    characters: characters,
    vibes: vibes,
    loras: newLoras,
    raw: raw,
  );
}

// ============ PNG tEXt/iTXt 文本块 ============

class _PngTextChunks {
  String? parameters; // SD WebUI
  String? comment; // NovelAI
  String? source; // NovelAI 模型来源
  String? prompt; // ComfyUI
  String? workflow; // ComfyUI 工作流
}

/// 逐块扫描 PNG,取出 tEXt/iTXt 里我们关心的键(小写匹配)。
_PngTextChunks _extractPngTextChunks(Uint8List bytes) {
  final result = _PngTextChunks();
  if (bytes.length < 8) return result;
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != sig[i]) return result;
  }
  final bd = ByteData.sublistView(bytes);
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = bd.getUint32(offset, Endian.big);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    final dataStart = offset + 8;
    if ((type == 'tEXt' || type == 'iTXt') &&
        dataStart + length <= bytes.length) {
      final text = utf8.decode(
        bytes.sublist(dataStart, dataStart + length),
        allowMalformed: true,
      );
      final nullIndex = text.indexOf('\u0000');
      if (nullIndex > 0) {
        final key = text.substring(0, nullIndex).toLowerCase();
        // iTXt 布局:keyword\0 压缩标志 压缩方法 语言标签\0 翻译关键字\0 文本。
        // 只按第一个 \0 切会把「标志+方法+两个空串终止符」留在正文头上 ——
        // parameters 是正则扫描无所谓,但 prompt 要 jsonDecode:**含中文的图
        // (PIL 遇非 latin-1 就写 iTXt)会整块解析失败**。按规范逐段跳过。
        String value;
        if (type == 'iTXt') {
          var p = nullIndex + 1;
          final compressed = p < text.length && text.codeUnitAt(p) != 0;
          p += 2; // 压缩标志 + 压缩方法
          for (var seg = 0; seg < 2 && p < text.length; seg++) {
            final end = text.indexOf('\u0000', p);
            if (end < 0) {
              p = text.length;
              break;
            }
            p = end + 1;
          }
          // 压缩的 iTXt 极罕见(我们和 ComfyUI 都不写),解不了就当没有
          value = compressed ? '' : text.substring(p.clamp(0, text.length));
        } else {
          value = text.substring(nullIndex + 1);
        }
        switch (key) {
          case 'parameters':
            result.parameters = value;
          case 'comment':
            result.comment = value;
          case 'source':
            result.source = value;
          case 'prompt':
            result.prompt = value;
          case 'workflow':
            result.workflow = value;
        }
      }
    }
    offset += 12 + length; // length(4)+type(4)+data+CRC(4)
  }
  return result;
}

// ============ NovelAI ============

/// V5 Full 的两个权重指纹(取自 NAI 官方前端白名单)。
const _v5FullHashes = ['657484a5', '0adf9ab7'];

/// 这串 Source 是不是 V5 Full。
///
/// ⚠ **V5 的 Source 串里不写 Full / Curated**,只有一串权重 hash,例如
/// `NovelAI Diffusion V5 657484A5`。官方的判法是白名单:命中 [_v5FullHashes]
/// 是 Full,其余 V5 一律 Curated(官方那边 Curated 就是 default 分支,压根没列
/// hash)。所以对 V5 用 `contains('curated')` **永远不成立** —— 那样写会把
/// 每一张 V5 图都认成 Full,2026-08-24 之前本仓两处都是这么错的。
///
/// 归一化之后的串(「NovelAI V5 Full」)也吃得下:那时 hash 已经没了,只能看字面。
bool naiSourceIsV5Full(String source) {
  final s = source.toLowerCase();
  if (s.contains('curated')) return false;
  if (s.contains('full')) return true;
  return _v5FullHashes.any(s.contains);
}

/// 模型指纹 → 展示名(取自 NAI 官方前端源码)。
const _naiModelNameMap = <String, String>{
  'NovelAI Diffusion V4.5 4BDE2A90': 'NovelAI V4.5 Full',
  'NovelAI Diffusion V4.5 1229B44F': 'NovelAI V4.5 Full Inpaint',
  'NovelAI Diffusion V4.5 B9F340FD': 'NovelAI V4.5 Full',
  'NovelAI Diffusion V4.5 F3D95188': 'NovelAI V4.5 Full',
  'NovelAI Diffusion V4.5 C02D4F98': 'NovelAI V4.5 Curated',
  'NovelAI Diffusion V4.5 5BB76870': 'NovelAI V4.5 Curated Inpaint',
  'NovelAI Diffusion V4.5 5AB81C7C': 'NovelAI V4.5 Curated',
  'NovelAI Diffusion V4.5 B5A2A797': 'NovelAI V4.5 Curated',
  'NovelAI Diffusion V4 44FD40FE': 'NovelAI V4 Full',
  'NovelAI Diffusion V4 37442FCA': 'NovelAI V4 Full',
  'NovelAI Diffusion V4 4F49EC75': 'NovelAI V4 Full',
  'NovelAI Diffusion V4 CA4B7203': 'NovelAI V4 Full',
  'NovelAI Diffusion V4 79F47848': 'NovelAI V4 Full',
  'NovelAI Diffusion V4 F6302A9D': 'NovelAI V4 Full',
  'NovelAI Diffusion V4 C5E578FD': 'NovelAI V4 Curated',
  'NovelAI Diffusion V4 7ABFFA2A': 'NovelAI V4 Curated',
  'NovelAI Diffusion V4 C1CCBA86': 'NovelAI V4 Curated',
  'NovelAI Diffusion V4 770A9E12': 'NovelAI V4 Curated',
  'NovelAI Diffusion V4 5AB81C7C': 'NovelAI V4.5 Curated',
  'NovelAI Diffusion V4 B5A2A797': 'NovelAI V4.5 Curated',
  'NovelAI Diffusion V3 F4D50568': 'NovelAI V3',
  'Stable Diffusion XL 4BE8C60C': 'NovelAI V3 Furry',
  'Stable Diffusion XL C8704949': 'NovelAI V3 Furry',
  'Stable Diffusion XL 37C2B166': 'NovelAI V3 Furry',
  'Stable Diffusion XL F306816B': 'NovelAI V3 Furry',
  'Stable Diffusion XL 9CC2F394': 'NovelAI V3 Furry',
};

String? _asString(Object? v) => v?.toString();

/// NAI 的 `{Source, Comment}` JSON → 元数据。各入口(tEXt / EXIF / LSB 隐写)
/// 拿到 JSON 后都汇到这里,测试也从这里进。
@visibleForTesting
ImageMetadata? parseNaiMetadataJson(Map<String, dynamic> data) =>
    _parseNai(data);

ImageMetadata? _parseNai(Map<String, dynamic> data) {
  try {
    final rawComment = data['Comment'];
    final Map<String, dynamic> comment = rawComment is String
        ? (jsonDecode(rawComment) as Map<String, dynamic>)
        : (rawComment is Map
              ? rawComment.cast<String, dynamic>()
              : <String, dynamic>{});

    // 负向
    var negative = '';
    final v4Neg = comment['v4_negative_prompt'];
    if (v4Neg is Map && v4Neg['caption'] is Map) {
      negative = (v4Neg['caption']['base_caption'] ?? '').toString();
    } else if (comment['uc'] != null) {
      negative = comment['uc'].toString();
    }

    // 角色负向按坐标索引:v4_negative_prompt 那份**只收负向非空的那几个**,
    // 下标跟正向对不上(正向有 3 个、只有第 2 个写了负向时,那边只有 1 条),
    // 只能按坐标认人。
    final negByCenter = <String, String>{};
    if (v4Neg is Map && v4Neg['caption'] is Map) {
      final nl = (v4Neg['caption'] as Map)['char_captions'];
      if (nl is List) {
        for (final c in nl) {
          if (c is! Map) continue;
          final t = (c['char_caption'] ?? '').toString();
          final ctr = c['centers'];
          if (t.isEmpty || ctr is! List || ctr.isEmpty || ctr.first is! Map) {
            continue;
          }
          final x = (ctr.first['x'] as num?)?.toDouble();
          final y = (ctr.first['y'] as num?)?.toDouble();
          if (x != null && y != null) negByCenter['$x,$y'] = t;
        }
      }
    }

    // 角色提示词。
    //
    // 正向与坐标读 v4_prompt.caption.char_captions;**负向不在那里** —— 那份结构
    // 里压根没有角色负向这个字段。它有两个出处,按可靠性依次取:
    //   1. `characterPrompts[].uc` —— 官方与本 app 都发,顺序与正向一一对应;
    //   2. `v4_negative_prompt` 那份,按坐标匹配(见上)。
    // 一个都不读的话,导入回来的角色负向永远是空的(本 app 2026-08-31 前就是)。
    final cps = comment['characterPrompts'];
    final chars = <CharacterMeta>[];
    final v4 = comment['v4_prompt'];
    // 官方导入也是从这里读回顶层 params 的 use_coords(AI's Choice / Custom)。
    // 它决定那些坐标到底算不算数 —— false 时坐标照写,但出图没用上。
    final useCoords = v4 is Map ? v4['use_coords'] as bool? : null;
    if (v4 is Map && v4['caption'] is Map) {
      final capt = v4['caption'] as Map;
      final list = capt['char_captions'];
      if (list is List) {
        for (var i = 0; i < list.length; i++) {
          final c = list[i];
          if (c is! Map) continue;
          double? cx, cy;
          final centers = c['centers'];
          if (centers is List && centers.isNotEmpty && centers.first is Map) {
            cx = (centers.first['x'] as num?)?.toDouble();
            cy = (centers.first['y'] as num?)?.toDouble();
          }
          var uc = (c['char_uc'] ?? '').toString();
          if (uc.isEmpty && cps is List && i < cps.length && cps[i] is Map) {
            uc = ((cps[i] as Map)['uc'] ?? '').toString();
          }
          if (uc.isEmpty && cx != null && cy != null) {
            uc = negByCenter['$cx,$cy'] ?? '';
          }
          chars.add(
            CharacterMeta(
              prompt: (c['char_caption'] ?? '').toString(),
              uc: uc,
              centerX: cx,
              centerY: cy,
            ),
          );
        }
      }
    }

    // Vibe
    final vibes = <VibeMeta>[];
    final vibeData = comment['reference_image_multiple'];
    final strengths = comment['reference_strength_multiple'];
    final infoEx = comment['reference_information_extracted_multiple'];
    final dataList = vibeData is List ? vibeData : const [];
    final strList = strengths is List ? strengths : const [];
    final ieList = infoEx is List ? infoEx : const [];
    final vibeCount = dataList.length > strList.length
        ? dataList.length
        : strList.length;
    for (var i = 0; i < vibeCount; i++) {
      final d = i < dataList.length ? dataList[i] : null;
      final strength = i < strList.length
          ? (strList[i] as num).toDouble()
          : 0.6;
      final info = i < ieList.length ? (ieList[i] as num).toDouble() : 1.0;
      if (d is String && d.isNotEmpty) {
        final isImage = d.startsWith('iVBORw0KGgo') || d.startsWith('/9j/');
        vibes.add(
          VibeMeta(
            image: isImage ? d : null,
            encoding: isImage ? null : d,
            strength: strength,
            informationExtracted: info,
          ),
        );
      } else {
        vibes.add(
          VibeMeta(
            strength: strength,
            informationExtracted: info,
            needsLocalMatch: true,
          ),
        );
      }
    }

    // 来源模型名
    final rawSource = (data['Source'] ?? '').toString();
    String source;
    if (_naiModelNameMap.containsKey(rawSource)) {
      source = _naiModelNameMap[rawSource]!;
    } else if (rawSource.isNotEmpty &&
        rawSource != 'NovelAI' &&
        rawSource != 'Stable Diffusion XL') {
      final m = RegExp(
        r'V(\d+(?:\.\d+)?)',
        caseSensitive: false,
      ).firstMatch(rawSource);
      if (m != null) {
        final ver = m.group(1);
        if (ver != null && ver.startsWith('5')) {
          // V5 的档次算得准(白名单,见 naiSourceIsV5Full),Full / Curated 都写出来。
          // 它的 Source 串里根本没有档次字样,不显式补上的话顶栏只会显示光秃秃
          // 一个「NovelAI V5」—— 而 V4/V4.5 那边有指纹表,一直是带档次的。
          final full = naiSourceIsV5Full(rawSource);
          source = 'NovelAI V$ver ${full ? 'Full' : 'Curated'}';
        } else {
          // 其余版本只能靠字面找 curated。**认不出就不写档次** —— 指纹表
          // (_naiModelNameMap)已经覆盖了官方在用的那批,落到这里的是没见过的
          // 指纹,硬挂一个 Full 上去是猜的。
          final curated = RegExp(
            'curated',
            caseSensitive: false,
          ).hasMatch(rawSource);
          source = 'NovelAI V$ver${curated ? ' Curated' : ''}';
        }
      } else {
        source = rawSource;
      }
    } else if (comment['v4_prompt'] != null) {
      source = 'NovelAI V4+';
    } else if (comment['sm'] != null || comment['sm_dyn'] != null) {
      source = 'NovelAI V3';
    } else {
      source = rawSource.isEmpty ? 'NovelAI' : rawSource;
    }

    return ImageMetadata(
      source: source,
      sourceType: ImageSourceType.novelai,
      promptSyntax: PromptSyntax.nai,
      useCoords: useCoords,
      prompt: (comment['prompt'] ?? '').toString(),
      negativePrompt: negative,
      width: (comment['width'] as num?)?.toInt() ?? 0,
      height: (comment['height'] as num?)?.toInt() ?? 0,
      seed: _asString(comment['seed']) ?? '',
      steps: _asString(comment['steps']),
      sampler: _asString(comment['sampler']),
      scale: _asString(comment['scale']),
      noiseSchedule: _asString(comment['noise_schedule']),
      cfgRescale: _asString(comment['cfg_rescale']),
      // containsKey 区分「字段为 null(关)」和「字段不存在(老图,不可知)」
      tagHintQt: (comment['tag_hint_qt'] as num?)?.toInt(),
      tagHintUcPreset: (comment['tag_hint_uc_preset'] as num?)?.toInt(),
      transparentBackground: comment['tag_hint_transparent_background'] is bool
          ? comment['tag_hint_transparent_background'] as bool
          : null,
      straightAlpha: comment['straight_alpha'] is bool
          ? comment['straight_alpha'] as bool
          : null,
      varietyPlus: comment.containsKey('skip_cfg_above_sigma')
          ? comment['skip_cfg_above_sigma'] != null
          : null,
      characters: chars,
      vibes: vibes,
      raw: data,
    );
  } catch (_) {
    return null;
  }
}

// ============ Stable Diffusion WebUI ============

List<LoraInfo> _extractLoras(String prompt) {
  final loras = <LoraInfo>[];
  for (final m in RegExp(
    r'<lora:([^:>]+):([^>]+)>',
    caseSensitive: false,
  ).allMatches(prompt)) {
    // 单权重 <lora:名:0.8> 与双权重 <lora:名:0.8:0.6>(后者是 unet:clip)
    final parts = m.group(2)!.split(':').map((s) => double.tryParse(s.trim()));
    final w = parts.isNotEmpty ? parts.first : null;
    final c = parts.length > 1 ? parts.elementAt(1) : null;
    loras.add(LoraInfo(name: m.group(1)!, weight: w ?? 1.0, clipWeight: c));
  }
  for (final m in RegExp(
    r'<lyco:([^:>]+):([^>]+)>',
    caseSensitive: false,
  ).allMatches(prompt)) {
    loras.add(
      LoraInfo(
        name: '${m.group(1)} (LyCORIS)',
        weight: double.tryParse(m.group(2)!) ?? 1.0,
      ),
    );
  }
  return loras;
}

ImageMetadata? _parseSd(String parametersStr) {
  try {
    var positive = '';
    var negative = '';
    var settingsPart = '';
    final stepsRe = RegExp(r'Steps:\s*\d+', dotAll: true);

    if (parametersStr.contains('Negative prompt:')) {
      final idx = parametersStr.indexOf('Negative prompt:');
      positive = parametersStr.substring(0, idx).trim();
      final remaining = parametersStr.substring(
        idx + 'Negative prompt:'.length,
      );
      final m = stepsRe.firstMatch(remaining);
      if (m != null) {
        settingsPart = remaining.substring(m.start);
        negative = remaining.substring(0, m.start).trim();
      } else {
        negative = remaining.trim();
      }
    } else {
      final m = stepsRe.firstMatch(parametersStr);
      if (m != null) {
        positive = parametersStr.substring(0, m.start).trim();
        settingsPart = parametersStr.substring(m.start);
      } else {
        positive = parametersStr.trim();
      }
    }

    var loras = _extractLoras(positive);
    // 只摘掉内联标签,权重语法保持原文 —— 转成 NAI 方言是导入时按目标决定的事
    positive = stripInlineTags(positive);
    negative = stripInlineTags(negative);

    String? grab(RegExp re) => re.firstMatch(settingsPart)?.group(1)?.trim();

    // `Lora hashes: "名: 哈希, 名2: 哈希2"` → 按名字贴回各条。
    // 哈希是跨部署认领的唯一可靠依据(名字可能重、可能被改过)。
    final loraHashes = grab(
      RegExp(r'Lora hashes:\s*"([^"]+)"', caseSensitive: false),
    );
    if (loraHashes != null && loras.isNotEmpty) {
      final byName = <String, String>{};
      for (final pair in loraHashes.split(',')) {
        final i = pair.lastIndexOf(':');
        if (i <= 0) continue;
        final n = pair.substring(0, i).trim().toLowerCase();
        final h = pair.substring(i + 1).trim();
        if (n.isNotEmpty && h.isNotEmpty) byName[n] = h;
      }
      loras = [
        for (final l in loras)
          byName[l.name.trim().toLowerCase()] == null
              ? l
              : l.copyWith(hash: byName[l.name.trim().toLowerCase()]),
      ];
    }

    final steps = grab(RegExp(r'Steps:\s*(\d+)', caseSensitive: false));
    final sampler = grab(RegExp(r'Sampler:\s*([^,]+)', caseSensitive: false));
    final scheduleType = grab(
      RegExp(r'Schedule type:\s*([^,]+)', caseSensitive: false),
    );
    final scale = grab(RegExp(r'CFG scale:\s*([\d.]+)', caseSensitive: false));
    final seed = grab(RegExp(r'Seed:\s*(\d+)', caseSensitive: false));
    final size = grab(RegExp(r'Size:\s*(\d+x\d+)', caseSensitive: false));
    final model = grab(
      RegExp(r'Model:\s*([^,]+?)(?:,|$)', caseSensitive: false),
    );
    final modelHash = grab(
      RegExp(r'Model hash:\s*([^,]+)', caseSensitive: false),
    );

    var width = 0, height = 0;
    if (size != null) {
      final sm = RegExp(r'(\d+)x(\d+)').firstMatch(size);
      if (sm != null) {
        width = int.parse(sm.group(1)!);
        height = int.parse(sm.group(2)!);
      }
    }

    var source = 'Stable Diffusion';
    if (model != null) {
      source = model;
    } else if (modelHash != null) {
      source = 'SD ($modelHash)';
    }

    return ImageMetadata(
      source: source,
      sourceType: ImageSourceType.stableDiffusion,
      promptSyntax: PromptSyntax.a1111,
      prompt: positive,
      negativePrompt: negative,
      width: width,
      height: height,
      seed: seed ?? '',
      steps: steps,
      sampler: sampler,
      scale: scale,
      noiseSchedule: scheduleType,
      loras: loras,
      raw: {'type': 'stable-diffusion', 'parameters': parametersStr},
    );
  } catch (_) {
    return null;
  }
}

// ============ ComfyUI ============
//
// ComfyUI 的 api-format `prompt` 是一张真图:节点之间用 `["12", 0]` 这样的引用连边。
// 所以解析必须**走图**,不能遍历节点碰运气 ——
//   · 正/负向就写在 KSampler 的 `positive` / `negative` 链接里,不需要靠
//     「文本里有没有 worst quality」去猜(正向里一个 "bad end" 就会把整段猜反);
//   · 带 hires fix 的图有两段 KSampler,遍历会取到随机一段;
//   · LoRA 是 LoraLoader 节点,不在提示词文本里,只扫 `<lora:>` 永远扫不到。
//
// 第三方节点包(Impact、Efficiency、rgthree…)的类型是无穷的,覆盖官方原生节点即可,
// **解不出就留空,绝不猜**。逻辑与 web `utils/imageMetadata.ts` 同构。

/// 节点引用形如 ["12", 0]。
bool _isNodeRef(Object? v) =>
    v is List &&
    v.length == 2 &&
    (v[0] is String || v[0] is num) &&
    v[1] is num;

String _refId(Object? ref) => (ref as List)[0].toString();

String _comfyClass(Map? node) => (node?['class_type'] ?? '').toString();

String _stripModelExt(String name) => name.replaceAll(
  RegExp(r'\.(safetensors|ckpt|pt|pth|bin)$', caseSensitive: false),
  '',
);

double? _asNum(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// 数值转文本:整数不带 .0(与 web `String(number)` 一致)。
String? _numText(double? v) {
  if (v == null) return null;
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// 取标量值。数值可能直接写在 inputs 里,也可能引用一个 primitive 节点
/// (PrimitiveNode / Constant Number / Seed 之类),需要顺着引用取。
Object? _resolveScalar(Map graph, Object? value, [int depth = 0]) {
  if (!_isNodeRef(value)) return value;
  if (depth > 8) return null;
  final node = graph[_refId(value)];
  final inputs = node is Map ? node['inputs'] : null;
  if (inputs is! Map) return null;
  for (final key in const [
    'value',
    'number',
    'int',
    'float',
    'seed',
    'Value',
    'text',
    'string',
  ]) {
    if (inputs.containsKey(key)) {
      return _resolveScalar(graph, inputs[key], depth + 1);
    }
  }
  return null;
}

/// 从一个引用出发沿 inputs 逆向 BFS,返回第一个命中的节点(带 id)。
MapEntry<String, Map>? _findUpstream(
  Map graph,
  Object? start,
  bool Function(Map node) match,
) {
  final queue = <Object?>[start];
  final seen = <String>{};
  while (queue.isNotEmpty && seen.length < 300) {
    final ref = queue.removeAt(0);
    if (!_isNodeRef(ref)) continue;
    final id = _refId(ref);
    if (!seen.add(id)) continue;
    final node = graph[id];
    if (node is! Map) continue;
    if (match(node)) return MapEntry(id, node);
    final inputs = node['inputs'];
    if (inputs is Map) {
      for (final v in inputs.values) {
        if (_isNodeRef(v)) queue.add(v);
      }
    }
  }
  return null;
}

/// 某个节点的全部上游 id(含自身)。
Set<String> _collectUpstreamIds(Map graph, String startId) {
  final seen = <String>{};
  final queue = <String>[startId];
  while (queue.isNotEmpty && seen.length < 300) {
    final id = queue.removeAt(0);
    if (!seen.add(id)) continue;
    final node = graph[id];
    final inputs = node is Map ? node['inputs'] : null;
    if (inputs is Map) {
      for (final v in inputs.values) {
        if (_isNodeRef(v)) queue.add(_refId(v));
      }
    }
  }
  return seen;
}

/// 采样节点按**结构**认,不按名字认:有 positive+negative(KSampler / SamplerCustom)
/// 或 steps+cfg 的就是。按名字匹配会把 KSamplerSelect 这种只挑采样器名的也算进来。
bool _isComfySampler(Object? node) {
  if (node is! Map) return false;
  final i = node['inputs'];
  if (i is! Map) return false;
  return (i.containsKey('positive') && i.containsKey('negative')) ||
      (i.containsKey('steps') && i.containsKey('cfg'));
}

/// 找出出图的那个采样节点:优先从输出节点回溯,其次取最下游的。
MapEntry<String, Map>? _findMainSampler(Map graph) {
  final outRe = RegExp(
    r'SaveImage|PreviewImage|SaveAnimated|SaveImageWebsocket',
    caseSensitive: false,
  );
  String? outputId;
  for (final id in graph.keys) {
    if (outRe.hasMatch(_comfyClass(graph[id] as Map?))) {
      outputId = id.toString();
      break;
    }
  }
  if (outputId != null) {
    final found = _findUpstream(graph, [outputId, 0], _isComfySampler);
    if (found != null) return found;
  }

  // 没有输出节点(被裁过的 api json):取不被其他采样节点当上游的那个 = 链路末端
  final samplerIds = [
    for (final id in graph.keys)
      if (_isComfySampler(graph[id])) id.toString(),
  ];
  if (samplerIds.isEmpty) return null;
  if (samplerIds.length == 1) {
    return MapEntry(samplerIds.first, graph[samplerIds.first] as Map);
  }
  final upstreams = {
    for (final id in samplerIds) id: _collectUpstreamIds(graph, id),
  };
  final tail = samplerIds.where(
    (a) => !samplerIds.any((b) => b != a && upstreams[b]!.contains(a)),
  );
  final pick = tail.isNotEmpty ? tail.first : samplerIds.last;
  return MapEntry(pick, graph[pick] as Map);
}

/// 顺着 conditioning 链找到文本。中间可能夹着 Combine/Concat/SetArea 等节点。
String? _resolveConditioningText(Map graph, Object? ref, [int depth = 0]) {
  if (!_isNodeRef(ref) || depth > 12) return null;
  final node = graph[_refId(ref)];
  if (node is! Map) return null;
  final inputs = node['inputs'];
  if (inputs is! Map) return null;

  // 编码节点自带文本(SDXL 双编码器取 text_g,与官方 UI 显示一致)
  for (final key in const ['text', 'text_g', 'text_l', 'prompt', 'string']) {
    final v = inputs[key];
    if (v is String) return v;
    if (_isNodeRef(v)) {
      final resolved = _resolveScalar(graph, v);
      if (resolved is String) return resolved;
    }
  }

  // 中间节点:只沿 conditioning 类输入继续找,避免窜到 model/clip 分支上
  final condRe = RegExp('cond', caseSensitive: false);
  for (final entry in inputs.entries) {
    if (!_isNodeRef(entry.value)) continue;
    if (!condRe.hasMatch(entry.key.toString())) continue;
    final text = _resolveConditioningText(graph, entry.value, depth + 1);
    if (text != null) return text;
  }
  return null;
}

/// 出图管线自己挂的基础设施 LoRA —— 不是用户选的,导入时必须剔掉。
/// 混进去的话用户会看到一条自己没挂过、库里也查不到的 LoRA。
///   krea2_style_reference   风格参考模块内部挂的官方权重(服务端节点 501)
///   krea2_turbo_lora        「把 raw 拉近 turbo」的官方补丁权重
///   anima-turbo-lora        anima 模板里的内置项(模板里强度已是 0,这里再兜一道)
final _infraLoraRe = RegExp(
  r'^(krea2_style_reference|krea2_turbo_lora|anima-turbo-lora)',
  caseSensitive: false,
);

/// 沿 model 链收集 LoraLoader。
List<LoraInfo> _collectComfyLoras(Map graph, Object? modelRef) {
  final loras = <LoraInfo>[];
  final seen = <String>{};
  Object? ref = modelRef;
  final loraRe = RegExp('LoraLoader', caseSensitive: false);
  while (_isNodeRef(ref) && seen.length < 60) {
    final id = _refId(ref);
    if (!seen.add(id)) break;
    final node = graph[id];
    if (node is! Map) break;
    final inputs = node['inputs'];
    if (inputs is! Map) break;
    final name = inputs['lora_name'];
    if (loraRe.hasMatch(_comfyClass(node)) && name is String) {
      final weight =
          _asNum(
            _resolveScalar(
              graph,
              inputs['strength_model'] ?? inputs['strength'],
            ),
          ) ??
          1.0;
      // lora_name 可能带子目录(krea/LR120.safetensors),取 basename 再判
      final bare = _stripModelExt(name).split(RegExp(r'[\\/]')).last;
      // 强度 0 = 挂着但没启用(Anima 模板里两个内置 LoRA 默认就是 0),不算数
      if (weight != 0 && !_infraLoraRe.hasMatch(bare)) {
        loras.add(LoraInfo(name: bare, weight: weight));
      }
    }
    ref = inputs['model'] ?? inputs['MODEL'];
  }
  return loras.reversed.toList(); // 沿链是从下游往上走,反转回加载顺序
}

/// 解析 ComfyUI 格式的 prompt JSON。
///
/// 注意:`sampler` / `noiseSchedule` 存的是 ComfyUI 的原生取值(`euler` / `simple`),
/// 与 NovelAI 图存的 NAI id 不是一套枚举 —— 消费方按 sourceType 分流。
ImageMetadata? _parseComfy(String promptJson, String? workflowJson) {
  try {
    final decoded = jsonDecode(promptJson);
    if (decoded is! Map) return null;
    final graph = decoded;

    final main = _findMainSampler(graph);
    final inputs = main?.value['inputs'];
    final si = inputs is Map ? inputs : const {};

    final positive = _resolveConditioningText(graph, si['positive']) ?? '';
    final negative = _resolveConditioningText(graph, si['negative']) ?? '';

    final seed = _asNum(_resolveScalar(graph, si['seed'] ?? si['noise_seed']));
    final steps = _asNum(_resolveScalar(graph, si['steps']));
    final cfg = _asNum(_resolveScalar(graph, si['cfg']));
    final samplerName = _resolveScalar(graph, si['sampler_name']);
    final scheduler = _resolveScalar(graph, si['scheduler']);

    // 尺寸:沿 latent 链找带 width/height 的节点(EmptyLatentImage / EmptySD3LatentImage…)
    final latent = _findUpstream(graph, si['latent_image'] ?? si['latent'], (
      n,
    ) {
      final i = n['inputs'];
      return i is Map &&
          _asNum(i['width']) != null &&
          _asNum(i['height']) != null;
    });
    final latentInputs = latent?.value['inputs'];
    final li = latentInputs is Map ? latentInputs : const {};
    final width = _asNum(_resolveScalar(graph, li['width']))?.toInt() ?? 0;
    final height = _asNum(_resolveScalar(graph, li['height']))?.toInt() ?? 0;

    // 模型:沿 model 链走到底的加载器
    final loader = _findUpstream(graph, si['model'], (n) {
      final i = n['inputs'];
      return i is Map && (i['ckpt_name'] is String || i['unet_name'] is String);
    });
    final loaderInputs = loader?.value['inputs'];
    final di = loaderInputs is Map ? loaderInputs : const {};
    final modelFile = di['ckpt_name'] ?? di['unet_name'];
    final source = modelFile is String ? _stripModelExt(modelFile) : 'ComfyUI';

    return ImageMetadata(
      source: source,
      sourceType: ImageSourceType.comfyui,
      // ComfyUI 用的是 A1111 那套 (text:1.2) 权重语法,转不转由导入目标决定
      promptSyntax: PromptSyntax.a1111,
      prompt: positive,
      negativePrompt: negative,
      width: width,
      height: height,
      seed: _numText(seed) ?? '',
      steps: _numText(steps),
      sampler: samplerName is String ? samplerName : null,
      noiseSchedule: scheduler is String ? scheduler : null,
      scale: _numText(cfg),
      loras: _collectComfyLoras(graph, si['model']),
      raw: {'type': 'comfyui', 'prompt': graph},
    );
  } catch (_) {
    return null;
  }
}

// ============ EXIF (WebP/JPEG) ============

String _detectMime(Uint8List b) {
  if (b.length >= 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/png';
}

ImageMetadata? _parseExif(Uint8List bytes) {
  try {
    final mime = _detectMime(bytes);
    var exifOffset = -1;
    var exifLength = 0;

    if (mime == 'image/jpeg') {
      var offset = 2;
      while (offset < bytes.length - 4) {
        if (bytes[offset] == 0xFF && bytes[offset + 1] == 0xE1) {
          final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          if (bytes[offset + 4] == 0x45 &&
              bytes[offset + 5] == 0x78 &&
              bytes[offset + 6] == 0x69 &&
              bytes[offset + 7] == 0x66) {
            exifOffset = offset + 10;
            exifLength = segLen - 8;
          }
          break;
        }
        if (bytes[offset] == 0xFF) {
          final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          offset += 2 + segLen;
        } else {
          break;
        }
      }
    } else if (mime == 'image/webp') {
      var offset = 12;
      while (offset < bytes.length - 8) {
        final chunkId = String.fromCharCodes(bytes, offset, offset + 4);
        final chunkSize =
            bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);
        if (chunkId == 'EXIF') {
          exifOffset = offset + 8;
          if (bytes[exifOffset] == 0x45 &&
              bytes[exifOffset + 1] == 0x78 &&
              bytes[exifOffset + 2] == 0x69 &&
              bytes[exifOffset + 3] == 0x66) {
            exifOffset += 6;
            exifLength = chunkSize - 6;
          } else {
            exifLength = chunkSize;
          }
          break;
        }
        offset += 8 + chunkSize + (chunkSize % 2);
      }
    }

    if (exifOffset < 0 || exifLength <= 0) return null;

    final tiffStart = exifOffset;
    final little = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    int u16(int off) => little
        ? bytes[off] | (bytes[off + 1] << 8)
        : (bytes[off] << 8) | bytes[off + 1];
    int u32(int off) => little
        ? bytes[off] |
              (bytes[off + 1] << 8) |
              (bytes[off + 2] << 16) |
              (bytes[off + 3] << 24)
        : (bytes[off] << 24) |
              (bytes[off + 1] << 16) |
              (bytes[off + 2] << 8) |
              bytes[off + 3];

    final ifd0 = tiffStart + u32(tiffStart + 4);
    final ifd0Count = u16(ifd0);
    var exifIfd = -1;
    for (var i = 0; i < ifd0Count; i++) {
      final e = ifd0 + 2 + i * 12;
      if (u16(e) == 0x8769) {
        exifIfd = tiffStart + u32(e + 8);
        break;
      }
    }
    if (exifIfd < 0) return null;

    final exifCount = u16(exifIfd);
    for (var i = 0; i < exifCount; i++) {
      final e = exifIfd + 2 + i * 12;
      if (u16(e) != 0x9286) continue; // UserComment
      final count = u32(e + 4);
      final dataOffset = count <= 4 ? e + 8 : tiffStart + u32(e + 8);
      final charset = String.fromCharCodes(
        bytes.sublist(dataOffset, dataOffset + 8),
      );
      final textStart = dataOffset + 8;
      final textLength = count - 8;
      if (textLength <= 0) return null;
      final textBytes = bytes.sublist(textStart, textStart + textLength);
      String comment;
      if (charset.startsWith('UNICODE')) {
        // UTF-16BE
        final codes = <int>[];
        for (var k = 0; k + 1 < textBytes.length; k += 2) {
          codes.add((textBytes[k] << 8) | textBytes[k + 1]);
        }
        comment = String.fromCharCodes(codes);
      } else {
        comment = utf8.decode(textBytes, allowMalformed: true);
      }
      comment = comment.replaceAll(RegExp('\u0000+\$'), '').trim();
      if (comment.isEmpty) return null;

      try {
        final data = jsonDecode(comment);
        if (data is Map &&
            (data['Source'] != null || data['Comment'] != null)) {
          return _parseNai(data.cast<String, dynamic>());
        }
      } catch (_) {}
      if (comment.contains('Steps:')) return _parseSd(comment);
      return null;
    }
    return null;
  } catch (_) {
    return null;
  }
}

// ============ LSB alpha 隐写 (stealth_pngcomp) ============

class _LsbExtractor {
  _LsbExtractor(this.data, this.width, this.height);
  final Uint8List data; // RGBA
  final int width;
  final int height;
  int _bits = 0;
  int _byte = 0;
  int _row = 0;
  int _col = 0;

  void _next() {
    if (_row < height && _col < width) {
      final index = (_row * width + _col) * 4 + 3; // alpha
      final bit = data[index] & 1;
      _bits++;
      _byte = (_byte << 1) | bit;
      _row++;
      if (_row == height) {
        _row = 0;
        _col++;
      }
    } else {
      throw StateError('end of image');
    }
  }

  int getByte() {
    while (_bits < 8) {
      _next();
    }
    final b = _byte;
    _bits = 0;
    _byte = 0;
    return b;
  }

  Uint8List getBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = getByte();
    }
    return out;
  }

  int getUint32() {
    final b = getBytes(4);
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }
}

Future<Map<String, dynamic>?> _extractLsb(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = img.width, h = img.height;
    img.dispose();
    if (bd == null) return null;
    final rgba = bd.buffer.asUint8List();

    final reader = _LsbExtractor(rgba, w, h);
    const magic = 'stealth_pngcomp';
    final magicBytes = reader.getBytes(magic.length);
    if (utf8.decode(magicBytes, allowMalformed: true) != magic) return null;

    final lenBits = reader.getUint32();
    final lenBytes = (lenBits / 8).ceil();
    if (lenBytes <= 0 || lenBytes > 50 * 1024 * 1024) return null;
    final compressed = reader.getBytes(lenBytes);

    List<int>? raw;
    try {
      raw = GZipDecoder().decodeBytes(compressed);
    } catch (_) {
      try {
        raw = const ZLibDecoder().decodeBytes(compressed, raw: true);
      } catch (_) {
        return null;
      }
    }
    final decoded = utf8.decode(raw, allowMalformed: true);
    final json = jsonDecode(decoded);
    return json is Map ? json.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

// ============ 入口 ============

/// 从图片字节解析元数据;无法解析返回 null。
Future<ImageMetadata?> extractImageMetadata(Uint8List bytes) async {
  try {
    final chunks = _extractPngTextChunks(bytes);

    if (chunks.prompt != null) {
      final r = _parseComfy(chunks.prompt!, chunks.workflow);
      if (r != null) {
        // 本项目出的图两块都有:ComfyUI 图给准确的生成参数,A1111 parameters 块给
        // LoRA 的**真名 + 哈希**(工作流里的 lora_name 只是内部编号 web/LRxx,
        // 换个部署就认不出是什么)。
        if (chunks.parameters != null) {
          try {
            final sd = _parseSd(chunks.parameters!);
            if (sd != null && sd.loras.isNotEmpty) {
              return r.copyWithLoras(sd.loras);
            }
          } catch (_) {}
        }
        return r;
      }
    }
    if (chunks.comment != null) {
      try {
        final j = jsonDecode(chunks.comment!);
        if (j is Map && (j['prompt'] != null || j['Comment'] != null)) {
          return _parseNai({'Source': chunks.source, 'Comment': j});
        }
      } catch (_) {}
    }
    if (chunks.parameters != null) {
      final r = _parseSd(chunks.parameters!);
      if (r != null) return r;
    }

    final exif = _parseExif(bytes);
    if (exif != null) return exif;

    final lsb = await _extractLsb(bytes);
    if (lsb != null) {
      final r = _parseNai(lsb);
      if (r != null) return r;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 尺寸类型(与 web `getPictureSizeType` 一致)。
String pictureSizeType(int w, int h) {
  if (w == 832 && h == 1216) return '竖图';
  if (w == 1216 && h == 832) return '横图';
  if (w == 1024 && h == 1024) return '方图';
  if (w == 1984 && h == 832) return '宽图';
  return '$w×$h';
}

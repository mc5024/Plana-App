/// 导入的模型类别路由 —— 与 web `utils/importOptions.ts` 同构。
///
/// Anima 的后端就是 Modal 上的 ComfyUI,出图参数(sampler `euler`、scheduler `simple`…)
/// 就是 ComfyUI 的原生取值,所以 **ComfyUI 图 ≡ Anima 类别**,两者参数 1:1 落;
/// 往 NovelAI 上落才是有损映射。
///
/// 规则:图的类别 == 当前模型类别 → 完整解析、全字段可导;
/// 跨类别 → 只导正/负向提示词,并给一个「切换到 xx 模型」的按钮,切过去再完整解析。
library;

import '../generate/models.dart'
    show
        GenProvider,
        animaCfgRange,
        animaSamplers,
        animaSchedulers,
        animaStepsRange,
        kreaCfgRange,
        kreaSamplers,
        kreaSchedulers,
        kreaStepsRange,
        providerOfModel;
import 'image_metadata.dart';
import '../../l10n/l10n.dart';

/// `comfy` 是历史名字,实际含义是 **Anima**(那时 ComfyUI 图只可能来自 anima)。
/// 后加的 `krea` 也跑在 ComfyUI 上,采样器那套甚至是同一张表,但档位不同、
/// LoRA 库互不通用 —— 「模型」那一项不能互认,当成同一个会让一张 k2 图静默
/// 导进 anima,参数看着都合法、出图完全不是那么回事。
enum ModelCategory { nai, comfy, krea }

String categoryLabel(ModelCategory c) => switch (c) {
  ModelCategory.comfy => 'Anima',
  ModelCategory.krea => 'Krea 2',
  ModelCategory.nai => 'NovelAI',
};

/// 模型家族 —— 图的**参数体系**属于哪一套。
///
/// ComfyUI 那套里 anima 和 krea 是同源的(sampler 叫 euler/er_sde、scheduler 叫
/// simple、CFG 语义一致),NAI 是完全另一套枚举。所以「能不能逐项导参数」看的是
/// 家族,不是具体哪个模型 —— 只有跨家族才真的没法对应,才退化成只导提示词。
enum ModelFamily { nai, comfy }

ModelFamily familyOfCategory(ModelCategory c) =>
    c == ModelCategory.nai ? ModelFamily.nai : ModelFamily.comfy;

/// 图的参数体系属于哪个家族。SD/未知来源两套都不沾,返回 null。
ModelFamily? familyOfImage(ImageMetadata? meta) => switch (meta?.sourceType) {
  ImageSourceType.novelai => ModelFamily.nai,
  ImageSourceType.comfyui => ModelFamily.comfy,
  _ => null,
};

/// 当前选中的模型属于哪个类别。
ModelCategory categoryOfModel(String displayModel) =>
    switch (providerOfModel(displayModel)) {
      GenProvider.anima => ModelCategory.comfy,
      GenProvider.krea => ModelCategory.krea,
      GenProvider.nai => ModelCategory.nai,
    };

/// 这张 ComfyUI 图用的是我们支持的哪个模型;**认不出返回 null,但这不代表
/// 不能导参数** —— ComfyUI 是通用的图执行器,第三方模型的图照样解析得出
/// steps/CFG/尺寸,认不认得出只决定「模型」那一项能不能导、提示语怎么写。
/// anima 与 krea 靠 UNET 文件名区分(krea2_* vs anima-*)。
ModelCategory? comfyModelOfImage(ImageMetadata? meta) {
  if (meta?.sourceType != ImageSourceType.comfyui) return null;
  if (kreaModelFromSource(meta!.source) != null) return ModelCategory.krea;
  if (animaModelFromSource(meta.source) != null) return ModelCategory.comfy;
  return null;
}

/// 这张图最匹配我们的哪个模型类别 —— 用于「切换到 xx 模型」按钮和提示语。
/// 认不出模型的 ComfyUI 图返回 null:没有可推荐的切换目标,但参数照导。
ModelCategory? categoryOfImage(ImageMetadata? meta) =>
    switch (familyOfImage(meta)) {
      ModelFamily.nai => ModelCategory.nai,
      ModelFamily.comfy => comfyModelOfImage(meta),
      null => null,
    };

/// 跨**家族** = 参数体系对不上,只允许导提示词。
///
/// ⚠ 同家族内的「模型对不上」(k2 图 → Anima 目标、或第三方 ComfyUI 图)
/// **不算跨类别**:那种情况照常逐项判断,能导的导、不能导的单项禁用并写明原因。
/// 整块封死会把「顺手抄个步数和尺寸」这种正当需求也一并掐掉。
bool isCrossCategory(ImageMetadata? meta, ModelCategory target) =>
    familyOfImage(meta) != familyOfCategory(target);

/// 「模型」这一项导不了时的原因 —— 说清是别的模型还是不认识的模型。
/// 只废掉这一格:其余参数仍按当前模型的支持范围逐项判断。
String foreignModelReason(ImageMetadata meta, ModelCategory target) {
  final other = comfyModelOfImage(meta);
  if (other != null && other != target) {
    return l10nNow.foreignModel(categoryLabel(other));
  }
  return l10nNow.notLocalModel;
}

/// 导入这段提示词到目标类别时要不要转换权重语法。
///
/// 编辑器里存的始终是 NAI 语法:发 NovelAI 原样送,发 Anima 由服务端翻成 ComfyUI 语法
/// (已是 Comfy 格式的原样放行)。所以只有「源是 a1111 语法、要进 NovelAI」才需要转。
bool needsPromptConversion(ImageMetadata? meta, ModelCategory target) =>
    meta?.promptSyntax == PromptSyntax.a1111 && target == ModelCategory.nai;

/// ComfyUI 图的模型文件名 → Anima 档位展示名。
/// 前缀严格匹配,避免 `sd_xl_base_1.0` 被当成 base 档。
String? animaModelFromSource(String? source) {
  if (source == null) return null;
  final s = source.toLowerCase();
  if (s.startsWith('anima-turbo')) return 'Anima Turbo';
  if (s.startsWith('anima-aesthetic')) return 'Anima Aesthetic';
  if (s.startsWith('anima-base')) return 'Anima Base';
  // 社区层扩展版的权重文件叫 Anima-2.9B-preview-v1.safetensors,
  // 命名规律和官方三档不一样(带版本号不带用途词),单列一条
  if (s.startsWith('anima-2.9b')) return 'Anima 2.9B Beta';
  return null;
}

/// Anima 采样器 id → 展示名;不在白名单返回 null。
String? animaSamplerLabel(String? id) {
  for (final o in animaSamplers) {
    if (o.id == id) return o.label;
  }
  return null;
}

/// Anima 调度器 id → 展示名;不在白名单返回 null。
String? animaSchedulerLabel(String? id) {
  for (final o in animaSchedulers) {
    if (o.id == id) return o.label;
  }
  return null;
}

/// 步数是否在本机支持范围内。
bool animaStepsSupported(int v) =>
    v >= animaStepsRange.min && v <= animaStepsRange.max;

/// CFG 是否在本机支持范围内。
bool animaCfgSupported(double v) =>
    v >= animaCfgRange.min && v <= animaCfgRange.max;

/// ComfyUI 图的模型文件名 → Krea 2 档位展示名。
/// 两个权重文件 krea2_turbo_fp8_scaled / krea2_raw_fp8_scaled,名字都带 krea2 前缀。
String? kreaModelFromSource(String? source) {
  if (source == null) return null;
  final s = source.toLowerCase();
  if (!s.startsWith('krea2')) return null;
  return s.contains('turbo') ? 'Krea 2 Turbo' : 'Krea 2 Raw';
}

/// Krea 采样器 id → 展示名;不在白名单返回 null。
/// 查的是 [kreaSamplers] 而不是 anima 那张表:两张表眼下内容相同,但它们是
/// 各自模型的约定(服务端也是两份白名单),不该互相借用。
String? kreaSamplerLabel(String? id) {
  for (final o in kreaSamplers) {
    if (o.id == id) return o.label;
  }
  return null;
}

/// Krea 调度器 id → 展示名;不在白名单返回 null。
String? kreaSchedulerLabel(String? id) {
  for (final o in kreaSchedulers) {
    if (o.id == id) return o.label;
  }
  return null;
}

bool kreaStepsSupported(int v) =>
    v >= kreaStepsRange.min && v <= kreaStepsRange.max;

bool kreaCfgSupported(double v) =>
    v >= kreaCfgRange.min && v <= kreaCfgRange.max;

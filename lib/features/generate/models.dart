/// 创作页 UI 状态模型。当前里程碑仅承载界面,后续接 NAI API 时补充序列化。
library;

import 'dart:typed_data';

import 'res_rules.dart' show kFreePixelThreshold;

const Object _unset = Object();

/// 角色提示词卡的张数上限(NAI 侧约定,web 同值)。V4 系 6,NAI 5 抬到 32
/// (对齐 web maxCharactersForModel)—— 取值一律问 [maxCharactersOf],这个基线
/// 常量只作 V4 兜底。手动新增 / 法典多角色导入 / 灵感页选择上限 / 卡头读数共用,别再各写一份。
const kMaxCharacters = 6;
const kMaxCharactersNai5 = 32;

int maxCharactersOf(String displayModel) =>
    isNai5Model(displayModel) ? kMaxCharactersNai5 : kMaxCharacters;

/// 角色提示词当前编辑面
enum CharTab { positive, negative }

class CharacterPrompt {
  const CharacterPrompt({
    required this.id,
    required this.name,
    this.positive = '',
    this.negative = '',
    this.positiveRaw = '',
    this.negativeRaw = '',
    this.enabled = true,
    this.position, // 'A1'..'E5';null = AUTO
    this.activeTab = CharTab.positive,
  });

  final String id;
  final String name;
  final String positive;
  final String negative;

  /// 编辑器原文草稿(含禁用 `~tag~` / 折叠 `<#名字: …>` 等仅编辑期语法),
  /// 空 = 与定稿无差别,不必单独存。有效性由读取侧判定,见 [pickEditorText]。
  final String positiveRaw;
  final String negativeRaw;

  final bool enabled;
  final String? position;
  final CharTab activeTab;

  CharacterPrompt copyWith({
    String? name,
    String? positive,
    String? negative,
    String? positiveRaw,
    String? negativeRaw,
    bool? enabled,
    Object? position = _unset,
    CharTab? activeTab,
  }) {
    return CharacterPrompt(
      id: id,
      name: name ?? this.name,
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      positiveRaw: positiveRaw ?? this.positiveRaw,
      negativeRaw: negativeRaw ?? this.negativeRaw,
      enabled: enabled ?? this.enabled,
      position: position == _unset ? this.position : position as String?,
      activeTab: activeTab ?? this.activeTab,
    );
  }
}

class VibeItem {
  const VibeItem({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.strength = 0.6,
    this.infoExtracted = 1.0,
    this.image,
    this.imageHash,
    this.encodedByModel,
    this.sourceId,
  });

  final String id;
  final String name; // 来源文件名/展示名
  final bool enabled;
  final double strength;
  final double infoExtracted;

  /// 原始图片字节(用户选的图);编码时用,缩略图也用它显示。
  final Uint8List? image;

  /// 图片内容哈希(sha256 hex),编码缓存键用——内容寻址,重选同图/重启后仍可命中。
  final String? imageHash;

  /// 纯编码 vibe(库导入的 type:'encoding' 文件,无原图):
  /// encodings 键(v4-5full 等)→ 编码串;生成时按当前模型取,取不到跳过。
  /// IE 随文件固定,不可调。
  final Map<String, String>? encodedByModel;

  /// 来源库条目 id(从 Vibe 库添加/自动入库时有),生成成功后回写「最近使用」。
  final String? sourceId;

  /// 只有编码没有原图(IE 滑条锁定,无法重编码)。
  bool get isEncodingOnly => image == null;

  VibeItem copyWith({bool? enabled, double? strength, double? infoExtracted}) =>
      VibeItem(
        id: id,
        name: name,
        enabled: enabled ?? this.enabled,
        strength: strength ?? this.strength,
        infoExtracted: infoExtracted ?? this.infoExtracted,
        image: image,
        imageHash: imageHash,
        encodedByModel: encodedByModel,
        sourceId: sourceId,
      );
}

/// 角色参考迁移模式。label 显示用;api 直接进载荷 base_caption(对齐 web)。
enum CharRefMode {
  character('角色', 'character'),
  style('风格', 'style'),
  both('角色&风格', 'character&style');

  const CharRefMode(this.label, this.api);
  final String label;
  final String api;
}

class CharRefItem {
  const CharRefItem({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.mode = CharRefMode.both,
    this.strength = 1.0,
    this.infoExtracted = 1.0,
    this.image,
    this.imageHash,
  });

  final String id;
  final String name;
  final bool enabled;
  final CharRefMode mode;
  final double strength;

  /// UI 上的「保真度 Fidelity」;载荷 secondary_strength = 1 - infoExtracted。
  /// (director_reference_information_extracted 本身恒为 1,故此字段其实是 Fidelity。)
  final double infoExtracted;
  final Uint8List? image;
  final String? imageHash;

  CharRefItem copyWith({
    bool? enabled,
    CharRefMode? mode,
    double? strength,
    double? infoExtracted,
  }) => CharRefItem(
    id: id,
    name: name,
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    strength: strength ?? this.strength,
    infoExtracted: infoExtracted ?? this.infoExtracted,
    image: image,
    imageHash: imageHash,
  );
}

/// 一次重绘任务的完整载荷(由重绘编辑器构造,只存在于生成快照中,
/// 不进创作页 UI)。image/mask 已按发送尺寸备好(整图或 64 对齐的局部框)。
class InpaintJob {
  const InpaintJob({
    required this.image,
    required this.mask,
    required this.strength,
    this.paste,
    this.sourceId,
    this.grid,
  });

  /// 发送底图 PNG(整图重绘=原图;局部=裁切子图)。
  final Uint8List image;

  /// 与 image 同尺寸的黑白 mask PNG(白=重绘区,已 8×8 对齐)。
  final Uint8List mask;

  final double strength;

  /// 局部重绘的贴回信息;null = 整图(结果直接入库)。
  final InpaintPaste? paste;

  /// 底图在图库里的 id;回编辑器时用它认「是不是同一张图」。
  /// 从无图库归属的入口进来时为 null。
  final String? sourceId;

  /// 涂抹网格的编码(`MaskGrid.encode()`)。[mask] 那张 PNG 是**发给服务端**的,
  /// 回不成可编辑的格子;要接着涂就得留这一份。
  ///
  /// 蒙版记忆因此不再需要图库那套按图存盘的实现 —— 遮罩跟着创作页状态走,
  /// 工作区一起持久化,重启也在。
  final Uint8List? grid;
}

/// 局部重绘贴回:结果(发送框尺寸)中 tight 区域贴回原图对应位置。
class InpaintPaste {
  const InpaintPaste({
    required this.original,
    required this.sendX,
    required this.sendY,
    required this.tightX,
    required this.tightY,
    required this.tightW,
    required this.tightH,
    required this.outW,
    required this.outH,
  });

  /// 原完整图 PNG(贴回底)。
  final Uint8List original;

  /// 发送框原点(相对原图;发送框尺寸即快照 params.width/height)。
  final int sendX, sendY;

  /// 贴回的紧凑区域(相对原图)。
  final int tightX, tightY, tightW, tightH;

  /// 入库尺寸(=原图尺寸)。
  final int outW, outH;
}

class Img2ImgConfig {
  const Img2ImgConfig({
    this.strength = 0.7,
    this.noise = 0.0,
    this.image,
    this.upscaledEnhance = false,
  });

  final double strength;
  final double noise;

  /// 原始底图字节;生成时 cover 到目标分辨率再编码发送。
  final Uint8List? image;

  /// 官方 Max ✨ 放大重绘:发**原图尺寸** + 此标志,由服务端放大到总像素上限。
  /// 仅 V5 支持(能力表 maxEnhance)。只有重绘放大的 Max 档会置 true —— 别的
  /// 倍率是客户端自己把 params 的宽高算好再发的。
  final bool upscaledEnhance;

  Img2ImgConfig copyWith({
    double? strength,
    double? noise,
    Uint8List? image,
    bool? upscaledEnhance,
  }) => Img2ImgConfig(
    strength: strength ?? this.strength,
    noise: noise ?? this.noise,
    image: image ?? this.image,
    upscaledEnhance: upscaledEnhance ?? this.upscaledEnhance,
  );
}

enum LoopCount {
  x4('4'),
  x8('8'),
  x16('16'),
  infinite('∞');

  const LoopCount(this.label);
  final String label;

  /// 循环张数;0 表示无限(手动停止或失败为止)。
  int get count => switch (this) {
    LoopCount.x4 => 4,
    LoopCount.x8 => 8,
    LoopCount.x16 => 16,
    LoopCount.infinite => 0,
  };
}

class SizePreset {
  const SizePreset(
    this.name,
    this.ratio,
    this.width,
    this.height, {
    this.free = false,
  });
  final String name;
  final String ratio;
  final int width;
  final int height;
  final bool free;
}

/// 分辨率三档
const sizeTabs = <String, List<SizePreset>>{
  '小图': [
    SizePreset('竖图', '2:3', 832, 1216, free: true),
    SizePreset('横图', '3:2', 1216, 832, free: true),
    SizePreset('方形', '1:1', 1024, 1024, free: true),
  ],
  '大图': [
    SizePreset('竖图', '2:3', 1024, 1536),
    SizePreset('横图', '3:2', 1536, 1024),
    SizePreset('方形', '1:1', 1472, 1472),
  ],
  '壁纸': [
    SizePreset('竖屏', '9:16', 1088, 1920),
    SizePreset('横屏', '16:9', 1920, 1088),
    SizePreset('手机', '15:34', 960, 2176),
  ],
};

// 对齐 web 移动端:只保留 V4/V4.5(V3 用另一套载荷,移动端不提供)。
const models = <String>[
  'NAI 4.5 Full',
  'NAI 4.5 Curated',
  'NAI 4.0 Full',
  'NAI 4.0 Curated',
];

/// NAI 5 两档(2026-08-20 上线)。**直连 + Bot 双线可用**:直连线 buildNaiPayload
/// 已支持 V5 载荷(仍用 v4_prompt,仅 params_version 3→4、centers 放开连续),
/// bot 线载荷由后端 convert 构造 —— 弹层两线都列(top_bar `nai5: true`)。
/// 已支持:两档、分角色提示词(自由定位)、图生图;角色参考 / Vibe 官方未放出,
/// 见各自门槛(crSupportsModel / vibeSupportsModel 仍排除 V5)。
const nai5Models = <String>['NAI 5.0 Full', 'NAI 5.0 Curated'];

bool isNai5Model(String displayModel) => displayModel.startsWith('NAI 5.0');

/// 角色参考(Director/Precise Reference)仅 4.5 系模型支持(对齐 web 门槛)。
/// 载荷构造 / 成本预估 / 卡片提示共用此判定,入参为 UI 展示名。
/// NAI 5 是否支持官方未公布,预载期按不支持处理(startsWith 天然排除)。
bool crSupportsModel(String displayModel) => displayModel.startsWith('NAI 4.5');

/// Vibe Transfer 门槛:NAI 5 官方未确认支持(编码接口是否兼容也未知),
/// 预载期整卡屏蔽 —— 渲染与载荷剥离都走模块可见性,这里一处管住。
/// 确认支持后放开这里,并给 naiv4vibe_codec.kModelToEncodingKey 补编码键。
bool vibeSupportsModel(String displayModel) => !isNai5Model(displayModel);

/// 提示词 token 上限(生成页卡头 / 编辑器顶栏的 x/上限 读数共用)。
/// V4 系 512;NAI 5 官方抬到 Curated 703 / Full 1471。
/// anima / krea 无官方口径,沿用 512 只作视觉参考。
int tokenLimitOf(String displayModel) => switch (displayModel) {
  'NAI 5.0 Full' => 1471,
  'NAI 5.0 Curated' => 703,
  _ => 512,
};

// ============================================================
// 模型父类(provider)与 Anima(Modal ComfyUI 后端,仅 Bot 授权可用)
// 与 NAI 是两套完全独立的采样枚举,不要混用(对齐 web animaOptions.ts)。
// ============================================================

/// 模型父类:决定功能模块可见集与出图后端。
enum GenProvider { nai, anima, krea }

GenProvider providerOfModel(String displayModel) =>
    displayModel.startsWith('Anima')
    ? GenProvider.anima
    : displayModel.startsWith('Krea')
    ? GenProvider.krea
    : GenProvider.nai;

bool isAnimaModel(String displayModel) =>
    providerOfModel(displayModel) == GenProvider.anima;

bool isKreaModel(String displayModel) =>
    providerOfModel(displayModel) == GenProvider.krea;

/// Anima 与 Krea 共走服务端那条 Modal 通道,一大批判断对两者一视同仁
/// (不扣 Anlas、不支持重绘/图生图、仅 Bot 授权可用)。这些地方一律问这个,
/// 别再各写各的 `isAnima || isKrea` —— 将来接第三个渠道时会漏掉其中几处。
bool isModalModel(String displayModel) =>
    providerOfModel(displayModel) != GenProvider.nai;

/// 一档 Modal 模型(anima / krea)的整套采样参数。档位推荐配方
/// ([animaTierDefaults] / [kreaTierDefaults])与 [GenParams.modalMem] 共用同一形状。
typedef ModalSampling = ({
  int steps,
  double cfg,
  String sampler,
  String scheduler,
});

/// 档位记忆的键(`anima:turbo` / `krea:raw` …)。NAI 无档位配方 → null。
/// 两条渠道混在一张表里,键自带前缀,不会撞名(anima 也有 turbo)。
String? modalTierKeyOf(String displayModel) =>
    switch (providerOfModel(displayModel)) {
      GenProvider.anima => 'anima:${animaTierOf(displayModel)}',
      GenProvider.krea => 'krea:${kreaTierOf(displayModel)}',
      GenProvider.nai => null,
    };

/// 该型号的官方推荐配方;NAI 无此概念 → null。
ModalSampling? modalTierDefaultsOf(String displayModel) =>
    switch (providerOfModel(displayModel)) {
      GenProvider.anima => animaTierDefaults(animaTierOf(displayModel)),
      GenProvider.krea => kreaTierDefaults(kreaTierOf(displayModel)),
      GenProvider.nai => null,
    };

/// 大类展示名(模型选择弹层的切换条;对齐 web MODEL_PROVIDERS.label)。
String providerLabel(GenProvider p) => switch (p) {
  GenProvider.nai => 'NovelAI',
  GenProvider.anima => 'Anima',
  GenProvider.krea => 'Krea 2',
};

/// 某大类下的全部型号,顺序即弹层里的顺序。[nai5] = 追加 NAI 5 两档(已上线,
/// 直连 + Bot 双线均 true,见 top_bar._pickModel);新旗舰按惯例排最前。
List<String> modelsOf(GenProvider p, {bool nai5 = false}) => switch (p) {
  GenProvider.nai => nai5 ? [...nai5Models, ...models] : models,
  GenProvider.anima => animaModels,
  GenProvider.krea => kreaModels,
};

/// Anima 四档模型(展示名末词即 anima_extra.model 档位)。
///
/// 「Beta」二字写进**名字**而不是只放副标题:副标题只在模型选择弹层露面,
/// 而图库参数快照、导入回填、通知文案这些地方都只带名字 —— 社区版这件事
/// 得跟着名字走(web 同款考虑)。
const animaModels = <String>[
  'Anima Turbo',
  'Anima Aesthetic',
  'Anima Base',
  'Anima 2.9B Beta',
];

/// 展示名 → 档位串(turbo/aesthetic/base/beta)。
String animaTierOf(String displayModel) => switch (displayModel) {
  'Anima Aesthetic' => 'aesthetic',
  'Anima Base' => 'base',
  'Anima 2.9B Beta' => 'beta',
  _ => 'turbo',
};

/// 模型选择弹层的副标题。**恒为单行**(渲染侧 ellipsis 兜底),内容取
/// web 两版之长:桌面端 `LeftSidebar` 那三句讲**用途**(适合初步生成 /
/// 适合尝试不同风格 / 标准版本),移动端 `MobileGeneratePage` 讲**规格**
/// (蒸馏版、步数)—— 这里合成「规格 · 用途」,一行内给出选型要看的两件事。
///
/// NAI 四档 web 两版一字不差,原样取用。步数与本 app [animaTierDefaults] /
/// [kreaTierDefaults] 的实际取值对得上(Anima turbo 12 / aesthetic·base 36,
/// Krea turbo 8 / raw 36),不是照抄的死文案 —— 改档位默认值时这几行要跟着改。
/// 唯一不写步数的是 Anima 2.9B Beta,原因见该行注释。
///
/// 去掉了 Anima Turbo 的「(默认)」:那在 web 指「anima 档位里的默认」,
/// 而本 app 默认模型是 NAI 4.5 Full,七档平铺一张表会被读成"app 的默认"。
/// 分隔符统一用 ` · `(web 的 NAI 用逗号、anima 用点,混着来一页两套版式)。
const modelDescriptions = <String, String>{
  // NAI 5 预载两行只写**已确认**的规格(token 上限官方已公布,SFW/NSFW 是
  // Curated/Full 的品牌惯例);不写「未上线」—— 描述是静态的,上线当天改的
  // 是后端,这三个字会一直挂着骗人。
  'NAI 5.0 Full': '新一代旗舰 · 1471 token · NSFW',
  'NAI 5.0 Curated': '新一代精选版 · 703 token · SFW',
  'NAI 4.5 Full': '最新旗舰模型 · NSFW',
  'NAI 4.5 Curated': '最新旗舰精选版 · SFW',
  'NAI 4.0 Full': 'V4 旧模型 · NSFW',
  'NAI 4.0 Curated': 'V4 旧模型精选版 · SFW',
  'Anima Turbo': '蒸馏版 · 12 步 · 快,适合初稿',
  'Anima Aesthetic': '画风美学微调 · 36 步 · 适合试风格',
  'Anima Base': '标准基础模型 · 36 步',
  // 社区把官方 aesthetic 从 28 层扩到 40 层再加训的版本,不是官方发布。
  // **这一档不写步数**(全表唯一):一行只装得下三段,而选这档要看的是
  // 「社区版 / 数据更新到几月 / LoRA 还准不准」——步数在高级面板里看得到,
  // 那三件事在别处都看不到。LoRA 那句指:挂得上但效果被稀释(容器侧有层号
  // 重映射补丁,只保证打在对应层上,新插的那 12 层 LoRA 根本不认识)。
  'Anima 2.9B Beta': '社区层扩展版 · 数据截至 7 月 · LoRA 效果打折',
  // 两档的真差别不是快慢而是「负向词还算不算数」(turbo 蒸馏后 CFG 固定 1),
  // 这比 web 那两句「出图最快 / 默认版本」更值得占这一行。
  'Krea 2 Turbo': '蒸馏版 · 8 步 · 最快,负向词不生效',
  'Krea 2 Raw': '标准基础模型 · 36 步 · 负向词生效',
};

/// 采样选项:id 直发服务端,label 供 UI。
class AnimaOption {
  const AnimaOption(this.id, this.label);

  final String id;
  final String label;
}

/// ⚠ UniPC 两项是 2026-08-10 随 web 补进来的,anima 侧**未实测**
/// (k2 那边同批加入,同样没测)。
const animaSamplers = <AnimaOption>[
  AnimaOption('euler', 'Euler'),
  AnimaOption('euler_ancestral', 'Euler Ancestral'),
  AnimaOption('er_sde', 'ER SDE'),
  AnimaOption('dpmpp_2m_sde_gpu', 'DPM++ 2M SDE'),
  AnimaOption('dpmpp_2m', 'DPM++ 2M'),
  AnimaOption('dpmpp_sde_gpu', 'DPM++ SDE'),
  AnimaOption('uni_pc', 'UniPC'),
  AnimaOption('uni_pc_bh2', 'UniPC BH2'),
  // 2026-08-12 为 2.9B 档补:模型作者给的两套配方之一是 res_multistep +
  // linear_quadratic(他说在高噪声步停留更久,构图明显更好)。表是 anima 全档
  // 共用的,官方三档也会看到,**未实测**。
  AnimaOption('res_multistep', 'Res Multistep'),
];

const animaSchedulers = <AnimaOption>[
  AnimaOption('simple', 'Simple'),
  AnimaOption('karras', 'Karras'),
  AnimaOption('normal', 'Normal'),
  AnimaOption('sgm_uniform', 'SGM Uniform'),
  AnimaOption('beta', 'Beta'),
  // 配 res_multistep 用,见上。作者还提到的 beta57 不在 ComfyUI 的 9 个调度器里
  // (那是 Forge/reForge 的东西),给不了。
  AnimaOption('linear_quadratic', 'Linear Quadratic'),
];

/// UI 推荐范围(对齐 web ANIMA_STEPS_RANGE / ANIMA_CFG_RANGE)。
/// 高级设置的滑块与元数据导入的可用性判断共用这一份,免得两处各自漂。
const animaStepsRange = (min: 6, max: 50);
const animaCfgRange = (min: 1.0, max: 7.0);

/// 一次最多出几张(anima / krea 的 `batch_size`)。
/// **和服务端同一个数**:`anima_provider` / `krea_provider` 里都是
/// `max(1, min(4, ...))`,这边放宽没用,服务端照样掐。
const kBatchMax = 4;

/// 各档位推荐采样参数(切档时自动套用;对齐 web ANIMA_TIER_DEFAULTS)。
///
/// 非蒸馏两档 36 步:官方模型卡给的是 30-50 步 / CFG 4-5。这里长期停在 28
/// (从更早那套 base+turbo-lora 旧配方继承来的,两头都不沾),2026-08-09 随
/// web 按官方区间校正。成本很小 —— 832×1216 每步约 0.3s,28→36 只多 2.4s,
/// 而端到端本就有 ~40s 固定开销。
ModalSampling animaTierDefaults(String tier) => switch (tier) {
  'aesthetic' ||
  'base' => (steps: 36, cfg: 4.5, sampler: 'er_sde', scheduler: 'simple'),
  // 2.9B(社区层扩展版)这组**不是**照抄上面两档,是模型作者给的配方:
  // 采样器 euler / res_multistep / er_sde,调度器 sgm_uniform / beta /
  // linear_quadratic,28-50 步、CFG 3.5-5;他自己常用 euler + sgm_uniform。
  // 注意上面两档用的 simple **不在**他给的列表里,所以这档单独配。
  'beta' => (steps: 32, cfg: 4.0, sampler: 'euler', scheduler: 'sgm_uniform'),
  _ => (steps: 12, cfg: 1.0, sampler: 'euler', scheduler: 'simple'),
};

// ============================================================
// Krea 2(12B DiT + Qwen3-VL 文本编码器)。与 Anima 共用同一条 Modal 通道和
// 同一个 GPU 队列,但**模型、采样参数、LoRA 库、功能模块全都各管各的**。
// 对齐 web `kreaOptions.ts` 与服务端 `krea_provider._KREA_TIERS`。
//
// 提示词是自然语言(中文可直写),服务端原样透传,不做 NAI 权重转换/括号转义。
// ============================================================

/// Krea 2 两档(展示名后缀即 krea_extra.model 档位)。官方只发了两个权重文件,
/// turbo **不是** raw 的降级版:它多了一轮审美调教,只是同时被蒸馏加速了,
/// 画风本就不同。
const kreaModels = <String>['Krea 2 Turbo', 'Krea 2 Raw'];

/// 展示名 → 档位串(turbo/raw)。未识别一律回落 raw(与服务端
/// normalize_krea_tier 同一默认:turbo 的 CFG=1 会让负向词静默失效,
/// 拿它兜底等于让「排除内容」变成一个没人告诉你它不工作的摆设)。
String kreaTierOf(String displayModel) =>
    displayModel == 'Krea 2 Turbo' ? 'turbo' : 'raw';

/// Krea 2 采样选项(对齐 web KREA_SAMPLERS / KREA_SCHEDULERS)。
///
/// 2026-08-10 之前这两项是模板里的常量、UI 不给控件。放开的理由:两边跑同一个
/// ComfyUI 的 KSampler,采样器名字是同一张表,从来不存在技术障碍 —— 当初没接
/// 只是因为 k2 两档同用 er_sde,没触发过这个需求。
///
/// 所以下面两张表眼下与 anima 那两张内容相同,**仍各存一份**:它们是各自模型的
/// 约定(默认值、风险项都不同),不该互相借用。
/// 服务端白名单:`krea_provider._KREA_SAMPLER_WHITELIST / _KREA_SCHEDULER_WHITELIST`,
/// 表外的值服务端静默回退档位默认,不报错。
const kreaSamplers = <AnimaOption>[
  AnimaOption('er_sde', 'ER SDE'),
  AnimaOption('euler', 'Euler'),
  AnimaOption('euler_ancestral', 'Euler Ancestral'),
  AnimaOption('dpmpp_2m_sde_gpu', 'DPM++ 2M SDE'),
  AnimaOption('dpmpp_2m', 'DPM++ 2M'),
  AnimaOption('dpmpp_sde_gpu', 'DPM++ SDE'),
  AnimaOption('uni_pc', 'UniPC'),
  AnimaOption('uni_pc_bh2', 'UniPC BH2'),
];

/// karras 排最后:它是唯一一个实测会坏事的,见 [kreaSchedulerRisky]。
const kreaSchedulers = <AnimaOption>[
  AnimaOption('simple', 'Simple'),
  AnimaOption('normal', 'Normal'),
  AnimaOption('sgm_uniform', 'SGM Uniform'),
  AnimaOption('beta', 'Beta'),
  AnimaOption('karras', 'Karras'),
];

/// 实测会把画面搞坏的调度器(对齐 web `kreaSchedulerIsRisky`)。
///
/// 2026-08-10 web 侧逐项实测:采样器前六个都能出正常图,差异在质感不在成败;
/// 唯独 karras 在 turbo 与 raw 两档都崩。留在表里是因为参数要全面放开,
/// 后端不替用户做主 —— UI 负责选中时当场说一句。
bool kreaSchedulerRisky(String id) => id == 'karras';

/// 各档推荐采样参数(切档时自动套用;对齐 web KREA_TIER_DEFAULTS)。
///
/// raw 36 步是个折中:官方 Raw 的配方其实是 52 步(且官方把 Raw 定位成微调
/// 底座、不建议直接出图),52 步耗时是 Turbo 的 3 倍。2026-08-09 随 web 由 28
/// 提到 36,与 anima 的非蒸馏档对齐。⚠ Raw 每步比 Turbo 贵约一倍(CFG>1 要
/// 正负各算一遍)。turbo 是蒸馏档,轨迹已烤进权重,多给步数不涨质量,照官方 8 步。
///
/// 两档采样器相同(都是官方配方 er_sde + simple)—— 这正是当初没建参数链的原因。
/// 切档时它们与 steps/cfg 走同一条路:该档没调过才套配方,见 [GenParams.modalMem]。
ModalSampling kreaTierDefaults(String tier) => tier == 'turbo'
    ? (steps: 8, cfg: 1.0, sampler: 'er_sde', scheduler: 'simple')
    : (steps: 36, cfg: 3.5, sampler: 'er_sde', scheduler: 'simple');

/// CFG=1 的蒸馏档:没有无条件分支可对比,负向提示词完全不参与引导。
bool kreaNegativeWorks(String tier) => kreaTierDefaults(tier).cfg > 1.0;

/// UI 推荐范围(对齐 web KREA_STEPS_RANGE / KREA_CFG_RANGE)。服务端硬夹
/// steps 1-60 / cfg 0.1-20,这里给的是合理区间 —— 上限留到 60 是给想手动
/// 往上试的人,但 30 步以后收益已经很有限。
const kreaStepsRange = (min: 4, max: 60);
const kreaCfgRange = (min: 1.0, max: 7.0);

/// 步数滑杆与高级面板共用的取值范围(三个父类各一套)。
({int min, int max}) stepsRangeOf(String displayModel) =>
    switch (providerOfModel(displayModel)) {
      GenProvider.anima => animaStepsRange,
      GenProvider.krea => kreaStepsRange,
      GenProvider.nai => (min: 1, max: 50),
    };

// ── 风格参考(krea 专属功能模块) ────────────────────────────

/// 同时下发上限。硬约束来自节点本身(TextEncodeKrea2OstrisEdit 只有
/// image1/2/3 三个槽),与服务端 krea_provider.MAX_STYLE_REFS 对齐;
/// 官方那个风格参考 LoRA 是按 1-2 张训的,第 3 张属于能插但没训过的区域。
const kMaxKreaStyleRefs = 3;

/// 参考图下采样上限。不是随手挑的:服务端 FluxKontextImageScale 会把参考图
/// 缩到 ~1024² 的像素预算,传更大只是白撑请求体,传更小反而要被放大回去、
/// 白丢细节(所以也不能复用角色参考那套 1024×1536 画布 + 黑边)。
const kKreaStyleRefMaxDim = 1024;

/// 参考强度钳制(服务端 `max(0, min(2, w))`)。
const kKreaStyleRefWeightMax = 2.0;

/// 一张 Krea 风格参考图。
///
/// 和 NAI 的角色参考(CR)是两回事:k2 这套走「参考图 + 官方风格参考 LoRA」,
/// 只搬画风、不认角色,也就没有迁移模式 / 保真度这些维度。强度全局只有一份
/// (就是那个 LoRA 的 strength),因此存在 [GenerateState.kreaStyleRefWeight]
/// 而不是每张一个。UI 壳照搬角色参考卡。
class KreaStyleRefItem {
  const KreaStyleRefItem({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.image,
    this.imageHash,
  });

  final String id;
  final String name;
  final bool enabled;

  /// 原始图片字节;发送前下采样到 [kKreaStyleRefMaxDim] 再编码。
  final Uint8List? image;

  /// 图片内容哈希(sha256 hex),入库去重与存档引用共用。
  final String? imageHash;

  KreaStyleRefItem copyWith({bool? enabled}) => KreaStyleRefItem(
    id: id,
    name: name,
    enabled: enabled ?? this.enabled,
    image: image,
    imageHash: imageHash,
  );
}

// ── LoRA(anima / krea 共用的功能模块) ─────────────────────
// 挂载语义两边完全一致(同一套 LoraLoader 链 / LR 编号 / 权重与 CLIP 分离),
// 差别只在**库按底模隔离**:anima(2B 自研 DiT)与 krea2(12B DiT)权重互不
// 通用,挂错了 ComfyUI 不报错、只是静默无效,所以列表/安装/挂载全程带 base。

/// 当前模型该用哪个 LoRA 库(直接进 `/api/lora/*` 的 `base` 参数)。
/// NAI 没有 LoRA 模块,取不到时按 anima 兜底(列表拉了也不会被渲染)。
String loraBaseOf(String displayModel) =>
    isKreaModel(displayModel) ? 'krea' : 'anima';

/// 同时挂载上限(与服务端 lora_resolver.MAX_LORAS_PER_GEN 一致)。
/// 是资源护栏不是画质建议——真正决定画质的是各条权重之和(LoRA 的效果直接相加,
/// 不会因为挂得多就自动摊薄),那个交给用户自己把握。
const kMaxActiveLoras = 20;

/// 权重钳制,与服务端 resolve_ui_loras / web LoraNumberInput 一致。
const kLoraWeightMax = 2.0;

/// 机房还没有这个文件——导入时先占位挂上,后台下载完再就地转正。
class LoraPending {
  const LoraPending({required this.versionId, this.failed});

  /// Civitai 版本号,与安装队列里的任务对齐(实时进度按它去队列取)。
  final int versionId;

  /// 下载失败原因;有值 = 停在失败态,等用户重试或移除。
  final String? failed;
}

/// 占位条目的 name:转正前没有真 LR 编号,用它做去重与选中标识。
String pendingLoraKey(int versionId) => 'pending:$versionId';

/// 类型徽标文案(character/style/concept → 中文;未知原样显示)。
String loraTypeLabel(String type) => switch (type) {
  'character' => '角色',
  'style' => '画风',
  'concept' => '概念',
  _ => type,
};

/// 挂载中的一个 LoRA。[name] 即服务端 LR 编号(LR1…),生成载荷只发它;
/// 其余字段来自注册表卡片,供 UI 展示与触发词交互。
class ActiveLora {
  const ActiveLora({
    required this.name,
    required this.displayName,
    this.weight = 0.8,
    this.enabled = true,
    this.clipWeight,
    this.hasTe,
    this.pending,
    this.triggerWords = const [],
    this.previewUrl = '',
    this.type = 'concept',
  });

  final String name;
  final String displayName;
  final double weight;
  final bool enabled;

  /// LoraLoader 的 strength_clip,与 strength_model 分离;null = 跟随 [weight](默认)。
  /// 叠多个 LoRA 后「prompt 不听话」是文本编码器被一起 patch 推偏导致的,
  /// 单独压低它能保住画面特征同时把语义拉回来。
  final double? clipWeight;

  /// 有没有文本编码器权重(服务端读 safetensors 头探得)。false = 只训了画面侧,
  /// [clipWeight] 调了不会有任何变化 → UI 不给调;null = 未知,按可调处理。
  final bool? hasTe;

  /// 非 null = 机房还没有这个文件(导入时占位挂上,后台下载中)。
  /// 期间 [name] 是 [pendingLoraKey] 生成的占位串,**绝不能进生成载荷**——
  /// 服务端查无此 LoRA 会静默丢弃,等于白跑一次生成。
  final LoraPending? pending;

  /// 全部可选触发词条目(一条可能是逗号分隔的整套 tag)。
  /// 是否写进正向词由用户在卡片上逐条点选(前端所见即所得),
  /// 载荷 triggers 恒传空数组告知服务端不要再拼。
  final List<String> triggerWords;
  final String previewUrl;
  final String type;

  /// [clearClipWeight] = true 时把 CLIP 强度退回「跟随 weight」——
  /// 命名参数传 null 表示「不改」,所以清空需要独立开关。
  ActiveLora copyWith({
    double? weight,
    bool? enabled,
    double? clipWeight,
    bool clearClipWeight = false,
    LoraPending? pending,
  }) => ActiveLora(
    name: name,
    displayName: displayName,
    weight: weight ?? this.weight,
    enabled: enabled ?? this.enabled,
    clipWeight: clearClipWeight ? null : (clipWeight ?? this.clipWeight),
    hasTe: hasTe,
    pending: pending ?? this.pending,
    triggerWords: triggerWords,
    previewUrl: previewUrl,
    type: type,
  );
}

// ── 重绘放大 hires(anima 专属功能模块) ─────────────────────

/// 「先超分后重绘」用的超分模型。**枚举名即服务端白名单键**
/// (`anima_provider._ANIMA_HIRES_UPSCALERS`),载荷直接发 [Enum.name],
/// 不认的键服务端兜底回 animesharp。
/// 三者的差异说明不在这儿:一律进「超分模型」那条参数说明(Help.hiresModel),
/// 免得卡片上再挂一行副标题。
enum HiresUpscaler {
  animesharp('AnimeSharp'),
  ultrasharp('UltraSharp'),
  anime6b('Anime 6B');

  const HiresUpscaler(this.label);

  final String label;
}

/// 二段步数下限:服务端 `max(4, min(50, steps))`。0 是「跟随主步数」的哨兵,
/// 不受此限;1~3 会被服务端悄悄抬到 4,故在 app 侧就钳住,免得读数骗人。
const kHiresStepsMin = 4;
const kHiresStepsMax = 50;

/// 重绘放大(hires two-pass):一段小图定构图 → 像素放大 → 低 denoise
/// 二段采样补细节。服务端 `_patch_anima_payload` 据此注入 320+ 节点链。
/// 各项取值范围与服务端钳制一致(scale 1.1~2.0 / denoise 0.2~0.75)。
class HiresConfig {
  const HiresConfig({
    this.enabled = false,
    this.scale = 1.5,
    this.denoise = 0.5,
    this.steps = 0,
    this.useModel = true,
    this.model = HiresUpscaler.animesharp,
  });

  final bool enabled;
  final double scale;
  final double denoise;

  /// 二段步数;0 = 跟随主步数(服务端读一段 KSampler 的 steps)。
  final int steps;

  /// true = 先超分后重绘(走 [model]);false = 直接重绘(lanczos 插值)。
  /// 与 [model] 分开存是为了来回切不丢用户选过的超分模型(对齐 web)。
  final bool useModel;
  final HiresUpscaler model;

  /// 载荷 `upscaler` 键:直接重绘发 `lanczos`,否则发超分模型键。
  String get upscalerKey => useModel ? model.name : 'lanczos';

  /// 二段目标尺寸,算法照抄服务端 `max(8, int(base * scale) // 8 * 8)`。
  (int, int) targetSize(int width, int height) =>
      (_align8(width * scale), _align8(height * scale));

  static int _align8(double v) {
    final n = v.toInt() ~/ 8 * 8;
    return n < 8 ? 8 : n;
  }

  HiresConfig copyWith({
    bool? enabled,
    double? scale,
    double? denoise,
    int? steps,
    bool? useModel,
    HiresUpscaler? model,
  }) => HiresConfig(
    enabled: enabled ?? this.enabled,
    scale: scale ?? this.scale,
    denoise: denoise ?? this.denoise,
    steps: steps ?? this.steps,
    useModel: useModel ?? this.useModel,
    model: model ?? this.model,
  );
}

const samplers = <String>[
  'Euler Ancestral',
  'Euler',
  'DPM++ 2S A',
  'DPM++ 2M SDE',
  'DPM++ 2M',
  'DPM++ SDE',
];

const noiseSchedules = <String>['karras', 'exponential', 'polyexponential'];

class GenParams {
  const GenParams({
    this.model = 'NAI 4.5 Full',
    this.width = 832,
    this.height = 1216,
    this.steps = 28,
    this.cfg = 5.0,
    this.varietyPlus = false,
    this.sampler = 'Euler Ancestral',
    this.noiseSchedule = 'karras',
    this.seed = '',
    this.cfgRescale = 0.0,
    this.normalizeVibe = true,
    this.loop = LoopCount.x8,
    this.animaSteps = 12,
    this.animaCfg = 1.0,
    this.animaSampler = 'euler',
    this.animaScheduler = 'simple',
    // 新建状态的兜底值 = raw 档配方(见 kreaTierDefaults);真正切到某一档时
    // setModel 会重新套一遍,这里只管「还没进过 Krea」和老存档缺键的情况。
    this.kreaSteps = 36,
    this.kreaCfg = 3.5,
    this.kreaSampler = 'er_sde',
    this.kreaScheduler = 'simple',
    this.hires = const HiresConfig(),
    this.batchCount = 1,
    this.modalMem = const {},
    this.useCoords = false,
  });

  final String model;
  final int width;
  final int height;
  final int steps;
  final double cfg;
  final bool varietyPlus;
  final String sampler;
  final String noiseSchedule;
  final String seed;
  final double cfgRescale;

  /// 多张 Vibe 时把强度按比例缩到合计 ≤1(关掉则各自独立相加)。
  final bool normalizeVibe;
  final LoopCount loop;

  // Anima 专属采样参数(与 NAI 的 steps/cfg/sampler 独立,两套不混用)。
  final int animaSteps;
  final double animaCfg;
  final String animaSampler;
  final String animaScheduler;

  // Krea 2 专属采样参数(与 anima 那套同样互不干扰)。
  final int kreaSteps;
  final double kreaCfg;
  final String kreaSampler;
  final String kreaScheduler;

  /// 重绘放大(anima 专属模块;非 anima 或模块隐藏时由剥离层置 enabled=false)。
  /// 角色定位：`false` = AI 自选（官方 "AI's Choice"），`true` = 用我摆的位置
  /// （"Custom"）。直接对应请求里的 `v4_prompt.use_coords`。
  ///
  /// **默认 false，与官方一致**。为 false 时坐标照发，只是模型不理会 —— 官方
  /// 也是这么发的，所以这个字段不影响 centers 怎么算。
  ///
  /// 早先没有这个开关、恒发 true，「AUTO」是每个角色各自的一个档位；那是我们
  /// 自己发明的模型，官方没有。存量存档在 [decodeGenerateState] 里迁移成
  /// `true` + 具体坐标，保证老提示词还能复现出同一张图。
  final bool useCoords;

  final HiresConfig hires;

  /// 一次采样出几张(anima / krea 的 `batch_size`)。**一条任务出 N 张**,
  /// 不是 N 条任务:同一次采样,所以进度共用、失败整批失败、取消整批取消。
  /// 真正会发出去的值见 [effectiveBatch] —— 这里存的只是用户的选择。
  final int batchCount;

  /// 各 Modal 档位记住自己那套采样参数(键见 [modalTierKeyOf])。
  ///
  /// anima 四档 / krea 两档共用上面那两组字段(生效的永远是当前这档),
  /// 所以切档必须有个地方安放上一档调好的值 —— 否则「Turbo 拉到 20 步 → 去
  /// Base 看一眼 → 切回来」步数就没了,连回 NAI 转一圈再回来都会没。
  ///
  /// 写入/取回都在 [rememberModalSampling] / [recallModalSampling],切模型时
  /// 成对调用。**没进过的档取不到值 → 套官方配方**,这样切到慢档不会挂着
  /// 蒸馏档的 12 步 CFG1 出糊图(切档联动的初衷,见 [animaTierDefaults])。
  final Map<String, ModalSampling> modalMem;

  /// 这一单**实际**会出几张。规则跟服务端对齐,不是界面上选什么就是什么:
  ///  - 只有 anima / krea 走 ComfyUI 的 `batch_size`,NAI 那条路没有这回事;
  ///  - anima 开着重绘放大时服务端**强制单张**(二段要跑 N × scale² 的量,
  ///    显存吃不消,见 `anima_provider` 里 `n28["batch_size"] = 1`)。
  ///
  /// 界面和载荷都走这一个口径 —— web 早期是服务端静默覆盖,用户选 4 出 1 张
  /// 且没有任何提示,那是最难查的一类「不一致」。
  int get effectiveBatch => switch (providerOfModel(model)) {
    GenProvider.anima => hires.enabled ? 1 : batchCount.clamp(1, kBatchMax),
    GenProvider.krea => batchCount.clamp(1, kBatchMax),
    GenProvider.nai => 1,
  };

  /// 这个模型支不支持一次出多张(决定界面上那颗「张数」显不显示)。
  bool get batchable => switch (providerOfModel(model)) {
    GenProvider.anima || GenProvider.krea => true,
    GenProvider.nai => false,
  };

  /// 当前模型实际生效的那份步数(三套互不干扰:切模型不会把对方的值带过去)。
  int get activeSteps => switch (providerOfModel(model)) {
    GenProvider.anima => animaSteps,
    GenProvider.krea => kreaSteps,
    GenProvider.nai => steps,
  };

  /// 写回当前模型那份步数(步数滑杆/输入框共用,免得每处都再判一次父类)。
  GenParams withActiveSteps(int v) => switch (providerOfModel(model)) {
    GenProvider.anima => copyWith(animaSteps: v),
    GenProvider.krea => copyWith(kreaSteps: v),
    GenProvider.nai => copyWith(steps: v),
  };

  /// 当前生效的那套 Modal 采样参数(NAI 下这两组都不参与出图,取 anima 那组
  /// 只是占位;调用方一律先判 [modalTierKeyOf] 再用)。
  ModalSampling get _modalSampling => isKreaModel(model)
      ? (
          steps: kreaSteps,
          cfg: kreaCfg,
          sampler: kreaSampler,
          scheduler: kreaScheduler,
        )
      : (
          steps: animaSteps,
          cfg: animaCfg,
          sampler: animaSampler,
          scheduler: animaScheduler,
        );

  /// **离开当前档位前**调:把这档调好的参数按档存进 [modalMem]。NAI 无档位,原样返回。
  GenParams rememberModalSampling() {
    final key = modalTierKeyOf(model);
    if (key == null) return this;
    return copyWith(modalMem: {...modalMem, key: _modalSampling});
  }

  /// **切到新模型之后**调:取回这档上次调好的参数;没进过这档就套官方配方。
  GenParams recallModalSampling() {
    final d = modalTierDefaultsOf(model);
    final key = modalTierKeyOf(model);
    if (d == null || key == null) return this; // NAI:没有档位这回事
    final s = modalMem[key] ?? d;
    return isKreaModel(model)
        ? copyWith(
            kreaSteps: s.steps,
            kreaCfg: s.cfg,
            kreaSampler: s.sampler,
            kreaScheduler: s.scheduler,
          )
        : copyWith(
            animaSteps: s.steps,
            animaCfg: s.cfg,
            animaSampler: s.sampler,
            animaScheduler: s.scheduler,
          );
  }

  /// Opus 免费判定(像素 ≤ 免费阈值 + ≤28 步),按像素而非预设成员,兼容自定义尺寸。
  bool get isFree => steps <= 28 && width * height <= kFreePixelThreshold;

  GenParams copyWith({
    String? model,
    int? width,
    int? height,
    int? steps,
    double? cfg,
    bool? varietyPlus,
    String? sampler,
    String? noiseSchedule,
    String? seed,
    double? cfgRescale,
    bool? normalizeVibe,
    LoopCount? loop,
    int? animaSteps,
    double? animaCfg,
    String? animaSampler,
    String? animaScheduler,
    int? kreaSteps,
    double? kreaCfg,
    String? kreaSampler,
    String? kreaScheduler,
    HiresConfig? hires,
    int? batchCount,
    bool? useCoords,
    Map<String, ModalSampling>? modalMem,
  }) {
    return GenParams(
      model: model ?? this.model,
      width: width ?? this.width,
      height: height ?? this.height,
      steps: steps ?? this.steps,
      cfg: cfg ?? this.cfg,
      varietyPlus: varietyPlus ?? this.varietyPlus,
      sampler: sampler ?? this.sampler,
      noiseSchedule: noiseSchedule ?? this.noiseSchedule,
      seed: seed ?? this.seed,
      cfgRescale: cfgRescale ?? this.cfgRescale,
      normalizeVibe: normalizeVibe ?? this.normalizeVibe,
      loop: loop ?? this.loop,
      animaSteps: animaSteps ?? this.animaSteps,
      animaCfg: animaCfg ?? this.animaCfg,
      animaSampler: animaSampler ?? this.animaSampler,
      animaScheduler: animaScheduler ?? this.animaScheduler,
      kreaSteps: kreaSteps ?? this.kreaSteps,
      kreaCfg: kreaCfg ?? this.kreaCfg,
      kreaSampler: kreaSampler ?? this.kreaSampler,
      kreaScheduler: kreaScheduler ?? this.kreaScheduler,
      hires: hires ?? this.hires,
      batchCount: batchCount ?? this.batchCount,
      useCoords: useCoords ?? this.useCoords,
      modalMem: modalMem ?? this.modalMem,
    );
  }
}

/// 折叠面板标识
enum Panel {
  prompt,
  characters,
  vibe,
  charRef,
  i2i,
  lora,
  hires,
  animaNl,
  kreaStyleRef,
  kreaPrompt,
}

class GenerateState {
  const GenerateState({
    required this.prompt,
    required this.negativePrompt,
    this.promptRaw = '',
    this.negativePromptRaw = '',
    required this.characters,
    required this.vibes,
    required this.charRefs,
    required this.img2img,
    required this.params,
    required this.anlas,
    required this.openPanels,
    this.loras = const [],
    this.kreaStyleRefs = const [],
    this.kreaStyleRefWeight = 1.0,
    this.inpaint,
  });

  factory GenerateState.initial() => const GenerateState(
    prompt: '',
    negativePrompt: '',
    characters: [],
    vibes: [], // 真实 Vibe:用户选图后才有
    charRefs: [],
    img2img: null,
    params: GenParams(),
    anlas: 8420,
    openPanels: {},
  );

  final String prompt;
  final String negativePrompt;

  /// 编辑器原文草稿(含禁用/折叠等仅编辑期语法),空 = 与定稿无差别。
  /// [prompt] 恒为定稿:发给 NAI 的、算 token 的、拼预设的都只看它,
  /// 草稿不参与生成链路的任何一环。有效性判定见 [pickEditorText]。
  final String promptRaw;
  final String negativePromptRaw;

  final List<CharacterPrompt> characters;
  final List<VibeItem> vibes;
  final List<CharRefItem> charRefs;
  final Img2ImgConfig? img2img;
  final GenParams params;
  final int anlas;
  final Set<Panel> openPanels;

  /// 挂载的 LoRA(anima / krea 共用一份;NAI 模型生成时由模块剥离层清掉)。
  /// 两边的库互不通用,切换父类时由 [GenerateNotifier.setModel] 清空。
  final List<ActiveLora> loras;

  /// Krea 风格参考图(krea 专属;其它父类生成时由剥离层清掉)。
  final List<KreaStyleRefItem> kreaStyleRefs;

  /// 风格参考强度 —— 全局一份(所有参考图共用官方那个 LoRA 的 strength)。
  final double kreaStyleRefWeight;

  /// 重绘任务载荷(底图 + 遮罩 + 强度 + 回贴信息)。与 [img2img] 互斥、优先生效
  /// —— 带遮罩的图生图就是重绘,两者不该同时存在。
  ///
  /// **是创作页的常驻状态,不再是一次性快照**(2026-08-31 改):遮罩编辑器只负责
  /// 把它存进来,发车统一交给主生成按钮 —— 对齐官网。所以它跟着工作区一起持久化
  /// (见 state_codec),也跟着「图生图」模块的显隐一起剥(见 stripHiddenModules)。
  final InpaintJob? inpaint;

  /// 粗略 token 估算(占位;正式版接 T5 分词)
  int get promptTokens => (prompt.length / 2.2).round().clamp(0, 999);
  int get negativeTokens => (negativePrompt.length / 2.2).round().clamp(0, 999);

  int get enabledVibes => vibes.where((v) => v.enabled).length;
  int get enabledCharRefs => charRefs.where((r) => r.enabled).length;
  int get enabledLoras => loras.where((l) => l.enabled).length;

  /// 真正会下发的风格参考(启用 + 截到节点槽位上限);卡片提示与载荷同一份判断。
  List<KreaStyleRefItem> get activeKreaStyleRefs => [
    for (final r in kreaStyleRefs)
      if (r.enabled && r.image != null) r,
  ].take(kMaxKreaStyleRefs).toList();

  GenerateState copyWith({
    String? prompt,
    String? negativePrompt,
    String? promptRaw,
    String? negativePromptRaw,
    List<CharacterPrompt>? characters,
    List<VibeItem>? vibes,
    List<CharRefItem>? charRefs,
    Object? img2img = _unset,
    GenParams? params,
    int? anlas,
    Set<Panel>? openPanels,
    List<ActiveLora>? loras,
    List<KreaStyleRefItem>? kreaStyleRefs,
    double? kreaStyleRefWeight,
    Object? inpaint = _unset,
  }) {
    return GenerateState(
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      promptRaw: promptRaw ?? this.promptRaw,
      negativePromptRaw: negativePromptRaw ?? this.negativePromptRaw,
      characters: characters ?? this.characters,
      vibes: vibes ?? this.vibes,
      charRefs: charRefs ?? this.charRefs,
      img2img: img2img == _unset ? this.img2img : img2img as Img2ImgConfig?,
      params: params ?? this.params,
      anlas: anlas ?? this.anlas,
      openPanels: openPanels ?? this.openPanels,
      loras: loras ?? this.loras,
      kreaStyleRefs: kreaStyleRefs ?? this.kreaStyleRefs,
      kreaStyleRefWeight: kreaStyleRefWeight ?? this.kreaStyleRefWeight,
      inpaint: inpaint == _unset ? this.inpaint : inpaint as InpaintJob?,
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import 'models.dart';
import 'prompt_sections.dart';

export 'models.dart'
    show GenProvider, isAnimaModel, providerLabel, providerOfModel;

/// 主页附属功能模块系统(对齐 web moduleConfig):
/// - 注册表定死可管理的模块,每个模块归属一个模型父类(provider,
///   定义在 models.dart),可带「组内按具体型号」的能力门槛(如角色参考仅 4.5);
/// - 用户配置只有「启用 + 每组顺序」;
/// - 主页可见 = 归属当前父类 + 已启用 + 当前型号支持,不满足的整卡不渲染,
///   面板发起的生成也不发其数据(工作区数据保留,条件恢复即回来);
/// - 图库快照按剥离后状态入库,「重新生成」忠实复现。
/// 新增模块 = 注册表加行(标 provider)+ 主页 `_moduleCard` 加卡。
enum GenModule {
  character,
  vibe,
  charRef,
  img2img,
  lora,
  hires,
  kreaStyleRef,
  kreaLora,
}

/// 注册表条目:图标与名称同主页卡片,管理页与卡片一眼对上。
class GenModuleDef {
  const GenModuleDef(
    this.key,
    this.icon,
    this.label, {
    this.provider = GenProvider.nai,
    this.supports,
  });

  final GenModule key;
  final IconData icon;
  final String label;
  final GenProvider provider;

  /// 组内按具体型号的能力门槛;null = 该组全部型号支持。
  final bool Function(String displayModel)? supports;

  bool supportsModel(String displayModel) =>
      supports?.call(displayModel) ?? true;
}

/// 新增模块 = 此处加一行 + 主页 `_moduleCard` 加一张卡。
const kGenModuleDefs = <GenModuleDef>[
  GenModuleDef(GenModule.character, Icons.group_outlined, '角色'),
  // NAI 5 预载期屏蔽(官方未确认支持),门槛见 vibeSupportsModel。
  GenModuleDef(
    GenModule.vibe,
    Icons.palette_outlined,
    'Vibe Transfer',
    supports: vibeSupportsModel,
  ),
  GenModuleDef(
    GenModule.charRef,
    Icons.face_retouching_natural,
    '角色参考',
    supports: crSupportsModel,
  ),
  GenModuleDef(GenModule.img2img, Icons.image_outlined, '图生图'),
  GenModuleDef(
    GenModule.lora,
    Icons.auto_awesome_outlined,
    'LoRA',
    provider: GenProvider.anima,
  ),
  GenModuleDef(
    GenModule.hires,
    Icons.bolt_outlined,
    '重绘放大',
    provider: GenProvider.anima,
  ),
  GenModuleDef(
    GenModule.kreaStyleRef,
    Icons.palette_outlined,
    '风格参考',
    provider: GenProvider.krea,
  ),
  // krea 的 LoRA 单开一个 key(不复用 [GenModule.lora]):启用位是按 key 全局
  // 存的,共用会导致在 Anima 里关掉 LoRA、Krea 那边也跟着关。底模不同、库也
  // 不同,本就该各管各的;但对用户而言就是同一个功能,所以图标与名称一字不差。
  GenModuleDef(
    GenModule.kreaLora,
    Icons.auto_awesome_outlined,
    'LoRA',
    provider: GenProvider.krea,
  ),
];

/// 当前模型该看哪个 LoRA 模块(两个 key 同一个功能,见 [GenModule.kreaLora])。
GenModule loraModuleOf(String displayModel) =>
    isKreaModel(displayModel) ? GenModule.kreaLora : GenModule.lora;

GenModuleDef genModuleDef(GenModule m) =>
    kGenModuleDefs.firstWhere((d) => d.key == m);

/// 各父类的默认顺序 = 注册表顺序。
const kDefaultOrderByProvider = <GenProvider, List<GenModule>>{
  GenProvider.nai: [
    GenModule.character,
    GenModule.vibe,
    GenModule.charRef,
    GenModule.img2img,
  ],
  GenProvider.anima: [GenModule.lora, GenModule.hires],
  // LoRA 在上:挂 LoRA 是每次出图都要过一眼的常规动作,风格参考是偶尔才用的
  // 附加项(还只有 Turbo 档好使),常用的放手边。
  GenProvider.krea: [GenModule.kreaLora, GenModule.kreaStyleRef],
};

class GenModuleSettings {
  const GenModuleSettings({
    this.enabled = const {},
    this.order = kDefaultOrderByProvider,
  });

  /// 每模块启用位,缺省视为启用。
  final Map<GenModule, bool> enabled;

  /// 每个模型父类组内的模块顺序(含已隐藏的;隐藏只影响可见性,不丢位置)。
  final Map<GenProvider, List<GenModule>> order;

  bool isEnabled(GenModule m) => enabled[m] ?? true;

  List<GenModule> orderOf(GenProvider p) =>
      order[p] ?? kDefaultOrderByProvider[p] ?? const [];

  /// 统一可见性谓词:归属该模型的父类 + 已启用 + 该型号支持。
  /// 渲染、请求剥离、生成前提示全部走同一判定,不允许分叉。
  bool isVisibleFor(GenModule m, String displayModel) {
    final def = genModuleDef(m);
    return def.provider == providerOfModel(displayModel) &&
        isEnabled(m) &&
        def.supportsModel(displayModel);
  }

  /// 主页可见序列。
  List<GenModule> visibleFor(String displayModel) => [
    for (final m in orderOf(providerOfModel(displayModel)))
      if (isVisibleFor(m, displayModel)) m,
  ];

  GenModuleSettings copyWith({
    Map<GenModule, bool>? enabled,
    Map<GenProvider, List<GenModule>>? order,
  }) => GenModuleSettings(
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
  );

  /// 容错读取:以默认为骨架 —— 每组过滤不属于该组/未知的项、去重,
  /// 新增模块补到组尾;旧版扁平 order(数组)直接归入 nai 组。
  factory GenModuleSettings.fromJson(Map<String, dynamic> j) {
    final byName = {for (final m in GenModule.values) m.name: m};
    final enabled = <GenModule, bool>{};
    final je = j['enabled'];
    if (je is Map) {
      for (final e in je.entries) {
        final m = byName[e.key];
        final v = e.value;
        if (m != null && v is bool) enabled[m] = v;
      }
    }

    List<GenModule> repair(GenProvider p, Object? raw) {
      final out = <GenModule>[];
      if (raw is List) {
        for (final name in raw) {
          final m = byName[name];
          if (m != null && genModuleDef(m).provider == p && !out.contains(m)) {
            out.add(m);
          }
        }
      }
      for (final m in kDefaultOrderByProvider[p] ?? const <GenModule>[]) {
        if (!out.contains(m)) out.add(m);
      }
      return out;
    }

    final jo = j['order'];
    final order = <GenProvider, List<GenModule>>{
      for (final p in GenProvider.values)
        p: repair(
          p,
          jo is Map
              ? jo[p.name]
              // 旧版扁平数组:全部归入 nai 组
              : (p == GenProvider.nai && jo is List ? jo : null),
        ),
    };
    return GenModuleSettings(enabled: enabled, order: order);
  }

  Map<String, dynamic> toJson() => {
    'enabled': {for (final e in enabled.entries) e.key.name: e.value},
    'order': {
      for (final e in order.entries)
        e.key.name: [for (final m in e.value) m.name],
    },
  };
}

/// 面板发起的生成前调用:清掉当前不可见模块的数据(隐藏、型号不支持、
/// 或不属当前模型父类 —— 如 anima 下的全部 NAI 模块;只影响本次快照,
/// 不动工作区)。入库的即此剥离后快照,「重新生成」不再受当时的模块配置影响。
///
/// 主提示词分区也在这里并成一整串(见 [composeSections]):面板发起的每条
/// 生成路线都过这一道,快照里就只有发给 NAI 的那串。挂着重绘时宽高也在这里
/// 换成重绘那块的发送尺寸(见 [InpaintJob.sendSize])。
GenerateState stripHiddenModules(GenerateState s, GenModuleSettings ms) {
  final model = s.params.model;
  bool on(GenModule m) => ms.isVisibleFor(m, model);
  var out = composeSections(s);
  if (!on(GenModule.character) && out.characters.isNotEmpty) {
    out = out.copyWith(characters: const []);
  }
  // 角色槽位按模型截断(nai5 攒的 20 张切回 V4 只有前 6 张进载荷):超出的
  // 发给 NAI 是未定义行为。截前 N 张与卡片顺序一致,卡头徽章同步标红,
  // token 读数(countedCharacters)也走同一口径 —— 读数与载荷不许分叉。
  final charCap = maxCharactersOf(model);
  if (on(GenModule.character) && out.characters.length > charCap) {
    out = out.copyWith(characters: out.characters.take(charCap).toList());
  }
  if (!on(GenModule.vibe) && out.vibes.isNotEmpty) {
    out = out.copyWith(vibes: const []);
  }
  if (!on(GenModule.charRef) && out.charRefs.isNotEmpty) {
    out = out.copyWith(charRefs: const []);
  }
  // 遮罩挂在图生图这张卡下面(带遮罩的图生图就是重绘),卡收走了它也得跟着走 ——
  // 否则卡片没了、重绘照跑,用户找不到地方关掉它。
  if (!on(GenModule.img2img)) {
    if (out.img2img != null) out = out.copyWith(img2img: null);
    if (out.inpaint != null) out = out.copyWith(inpaint: null);
  }
  out = withoutInpaintVibes(out);
  // LoRA 挂载列表两个父类共用一份,但启用位分两个 key —— 按当前模型那个判。
  if (!on(loraModuleOf(model)) && out.loras.isNotEmpty) {
    out = out.copyWith(loras: const []);
  }
  if (!on(GenModule.kreaStyleRef) && out.kreaStyleRefs.isNotEmpty) {
    out = out.copyWith(kreaStyleRefs: const []);
  }
  // hires 没有独立数据,「剥离」= 关掉开关(配置本身留着,模块恢复即回来)
  if (!on(GenModule.hires) && out.params.hires.enabled) {
    out = out.copyWith(
      params: out.params.copyWith(
        hires: out.params.hires.copyWith(enabled: false),
      ),
    );
  }
  // 重绘按它自己那块的尺寸发(局部是裁切区、扩图是垫大后的整张):存入后再改
  // 尺寸,画布那个尺寸就不是这块的了。请求、贴回、估价都读这份快照的宽高。
  if (out.inpaint?.sendSize case (final w, final h)
      when w != out.params.width || h != out.params.height) {
    out = out.copyWith(params: out.params.copyWith(width: w, height: h));
  }
  return out;
}

/// 重绘不带 Vibe(同官方:V4 / V4.5 的重绘不收 Vibe,V5 本来没有)。
/// 画布里的 Vibe 原样留着,去掉遮罩就照常发。
GenerateState withoutInpaintVibes(GenerateState s) =>
    s.inpaint != null && s.vibes.isNotEmpty ? s.copyWith(vibes: const []) : s;

/// 把快照适配到**另一个模型**:只按型号能力剥,不看用户的模块显隐。
///
/// 换模型重跑会碰到这件事(图库的「重绘放大」用创作页当前的模型跑一张老图):
/// 4.5 的快照带着 Vibe / 角色参考,换到 V5 就得整组去掉 —— V5 不支持它们,
/// 发过去是未定义行为,费用还会白算一笔。角色数上限同理(V5 32 / 其余 6)。
///
/// **刻意不复用 [stripHiddenModules]**:那个还会按用户当前的模块显隐剥,而快照
/// 该忠实执行自己的内容;更要命的是它会把 img2img 一起剥掉 —— 重绘放大的底图
/// 正是 img2img,剥了就等于这次放大白跑。
GenerateState retargetModel(GenerateState s, String model) {
  var out = s.copyWith(params: s.params.copyWith(model: model));
  if (!vibeSupportsModel(model) && out.vibes.isNotEmpty) {
    out = out.copyWith(vibes: const []);
  }
  if (!crSupportsModel(model) && out.charRefs.isNotEmpty) {
    out = out.copyWith(charRefs: const []);
  }
  final cap = maxCharactersOf(model);
  if (out.characters.length > cap) {
    out = out.copyWith(characters: out.characters.take(cap).toList());
  }
  return out;
}

/// 真正会进载荷、因而该计入 token 读数的角色串。
///
/// 除了各自的启用位,还整组过一遍模块可见性:角色模块对当前模型不可见时
/// (anima 下的 NAI 四件套、模块被用户关掉、型号不支持)一律为空 —— 这些角色
/// 已被 [stripHiddenModules] 从请求里剥掉,卡片也不渲染,读数里再算它们就是
/// 「切到 anima 数字自己变大」的幽灵。
///
/// 等价于切走时把 NAI 角色整组禁用、切回来再放开,但不动存量数据:手动关掉的
/// 角色切回去还是关着,anima 下被杀进程也不会把启用位丢掉。
List<CharacterPrompt> countedCharacters(GenerateState s, GenModuleSettings ms) {
  if (!ms.isVisibleFor(GenModule.character, s.params.model)) return const [];
  // take:槽位外的角色不进载荷(见 stripHiddenModules),读数也不许算它们。
  return [
    for (final c in s.characters.take(maxCharactersOf(s.params.model)))
      if (c.enabled) c,
  ];
}

const _key = 'gen_modules';

final genModulesProvider =
    AsyncNotifierProvider<GenModulesNotifier, GenModuleSettings>(
      GenModulesNotifier.new,
    );

class GenModulesNotifier extends AsyncNotifier<GenModuleSettings> {
  @override
  Future<GenModuleSettings> build() async {
    try {
      final raw = await ref.read(prefsStoreProvider).read(key: _key);
      if (raw == null || raw.isEmpty) return const GenModuleSettings();
      return GenModuleSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const GenModuleSettings();
    }
  }

  /// 先改状态(立即生效),再尽力持久化。
  Future<void> patch(
    GenModuleSettings Function(GenModuleSettings) change,
  ) async {
    final next = change(state.value ?? const GenModuleSettings());
    state = AsyncData(next);
    try {
      await ref
          .read(prefsStoreProvider)
          .write(key: _key, value: jsonEncode(next.toJson()));
    } catch (_) {}
  }
}

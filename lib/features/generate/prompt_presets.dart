import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/l10n.dart';
import 'auto_text.dart' show userTextMarker;
import 'models.dart' show isNai5Model, GenerateState;
import 'generate_state.dart';
import 'canvas_state.dart';

/// 提示词预设:生成时拼进正/负提示词,不占用输入框。
/// 对齐 web `utils/storage.ts` 的 PromptPresetData + LeftSidebar 预设弹窗:
/// 五档内置(legacy 两档 + V5 两档 + 无,不可改删)+ 自定义(可增删改),
/// 库在画布间共用,用哪一档每张画布各存一份;内置档按 [PromptPreset.scope] 只在对应模型系列下出现。
class PromptPreset {
  const PromptPreset({
    required this.id,
    required this.name,
    required this.positive,
    required this.negative,
    this.isDefault = false,
    this.createdAt,
    this.scope,
    this.suffixPositive = false,
  });

  final String id;
  final String name;
  final String positive;
  final String negative;
  final bool isDefault;
  final int? createdAt;

  /// 适用模型系列:`'v5'` 只在 V5 下出现,`'legacy'` 只在 V4.5 及更早出现。
  /// null(自定义预设)= 不限系列,两边都能选。
  ///
  /// 分组的原因:V5 的官方质量词/负面档与 V4.5 完全是两套文本(V5 还多一个
  /// 「轻度」正面档),混在一个列表里选会串味。
  final String? scope;

  /// 正面预设拼在提示词**末尾**而不是开头。
  ///
  /// 官方从 V4 起就把质量词放末尾(负面一律前缀)。内置档全部照此,
  /// 包括 heavy / light —— 它们历史上是前缀,1.0.7 起与官方对齐。
  ///
  /// ⚠ 这一改会让**存量用户的出图风格变一点**:同一份提示词,质量词从句首挪到
  /// 句尾,注意力权重不一样。是有意为之(与官方一致优先),但别当成无副作用的重构。
  ///
  /// 自定义预设默认 false —— 用户自己写的档没有"官方位置"这一说。
  final bool suffixPositive;

  PromptPreset copyWith({
    String? name,
    String? positive,
    String? negative,
    bool? suffixPositive,
  }) => PromptPreset(
    id: id,
    name: name ?? this.name,
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    isDefault: isDefault,
    createdAt: createdAt,
    scope: scope,
    suffixPositive: suffixPositive ?? this.suffixPositive,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'positive': positive,
    'negative': negative,
    if (createdAt != null) 'createdAt': createdAt,
    if (scope != null) 'scope': scope,
    if (suffixPositive) 'positivePlacement': 'suffix',
  };

  factory PromptPreset.fromJson(Map<String, dynamic> j) => PromptPreset(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '未命名',
    positive: (j['positive'] as String?) ?? '',
    negative: (j['negative'] as String?) ?? '',
    createdAt: (j['createdAt'] as num?)?.toInt(),
    scope: j['scope'] as String?,
    suffixPositive: j['positivePlacement'] == 'suffix',
  );
}

/// 内置五档,文本与 web `DEFAULT_PROMPT_PRESETS` 逐字一致(勿"修正"其中的
/// 重复词、少一个空格的 `absurdres,very aesthetic` —— 契约以 web 为准)。
///
/// 按系列分成两组:legacy 组是 V4.5 及更早的历史文本(**勿动**,存量用户的出图
/// 风格挂在上面),v5 组逐字对齐官方 Quality Preset + Undesired Content Preset。
const kDefaultPromptPresets = <PromptPreset>[
  // ===== V4.5 及更早(文本勿动;位置已与官方对齐成后缀)=====
  PromptPreset(
    id: 'heavy',
    name: 'Heavy (重度)',
    scope: 'legacy',
    suffixPositive: true,
    positive:
        'best quality, amazing quality, very aesthetic, absurdres,very aesthetic, masterpiece, no text',
    negative:
        'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page',
    isDefault: true,
  ),
  PromptPreset(
    id: 'light',
    name: 'Light (轻度)',
    scope: 'legacy',
    suffixPositive: true,
    positive: 'very aesthetic, masterpiece, no text',
    negative:
        'lowres, artistic error, scan artifacts, worst quality, bad quality, jpeg artifacts, multiple views, very displeasing, too many watermarks, negative space, blank page',
    isDefault: true,
  ),
  // ===== V5 =====
  // 官方 V5 把老的「质量标签开关」(布尔)换成了三档下拉 standard/light/none,
  // 且 Full 与 Curated 共用同一张表(不像 4.5 Curated 会额外塞 rating:general)。
  // 我们把「正面质量档」和「负面档」并成一条预设,配对沿用官方默认:
  //   标准 = quality standard + uc heavy    轻度 = quality light + uc light
  PromptPreset(
    id: 'v5-standard',
    name: 'Standard (标准)',
    scope: 'v5',
    suffixPositive: true,
    positive: 'very aesthetic, masterpiece, no text',
    negative:
        'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page',
    isDefault: true,
  ),
  PromptPreset(
    id: 'v5-light',
    name: 'Light (轻度)',
    scope: 'v5',
    suffixPositive: true,
    // V5 新增的正面档;负面 light 也和 4.5 不同,多了 0::ai-generated:: 这种零权重写法
    positive: 'very aesthetic, amazing quality, no text',
    negative:
        'lowres, bad hands, bad anatomy, artistic error, sepia, white haze, worst quality, very displeasing, jpeg artifacts, 0::ai-generated::',
    isDefault: true,
  ),
  PromptPreset(
    id: 'none',
    name: 'None (无)',
    positive: '',
    negative: '',
    isDefault: true,
  ),
];

/// 显示名:内置档按界面语言,自定义档原样。
String presetDisplayName(AppLocalizations l, PromptPreset p) {
  if (!p.isDefault) return p.name;
  return switch (p.id) {
    'heavy' => l.presetHeavy,
    'light' || 'v5-light' => l.presetLight,
    'v5-standard' => l.presetStandard,
    'none' => l.presetNone,
    _ => p.name,
  };
}

/// 预设库:内置档 + 自定义档,按用户排的顺序。用哪一档不在这里 —— 每张画布
/// 各存一份(见 [GenerateState.promptPresetId])。
class PromptPresetsState {
  const PromptPresetsState({required this.presets});

  final List<PromptPreset> presets;
}

/// 按保存下来的顺序(id 列表)排。表里没有的 —— 新版本新增的内置档、刚导入的
/// 自定义档 —— 按原序缀在末尾,不打乱用户已经排好的那一段。
/// 顺序表为空(老存档 / 从没拖过)= 原序:内置档在前,自定义档按建档先后。
List<PromptPreset> orderPromptPresets(
  List<PromptPreset> presets,
  List<String> order,
) {
  if (order.isEmpty) return presets;
  final rank = <String, int>{};
  for (var i = 0; i < order.length; i++) {
    rank.putIfAbsent(order[i], () => i);
  }
  return [
    ...[
      for (final p in presets)
        if (rank.containsKey(p.id)) p,
    ]..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!)),
    for (final p in presets)
      if (!rank.containsKey(p.id)) p,
  ];
}

final promptPresetsProvider =
    AsyncNotifierProvider<PromptPresetsNotifier, PromptPresetsState>(
      PromptPresetsNotifier.new,
    );

/// 这张画布实际用的档:记的那档后来被删了,按「无」算。
String selectedPromptPresetId(GenerateState s, PromptPresetsState presets) {
  final id = s.promptPresetId;
  return presets.presets.any((p) => p.id == id) ? id : 'none';
}

final activePromptPresetIdProvider = Provider<String>((ref) {
  final presets = ref.watch(promptPresetsProvider).value;
  final s = ref.watch(generateProvider);
  if (presets == null) return s.promptPresetId;
  return selectedPromptPresetId(s, presets);
});

final activePromptPresetProvider = Provider<PromptPreset?>((ref) {
  final presets = ref.watch(promptPresetsProvider).value;
  if (presets == null) return null;
  final s = ref.watch(generateProvider);
  final id = remapPromptPresetId(
    selectedPromptPresetId(s, presets),
    presets.presets,
    s.params.model,
  );
  return presets.presets.where((p) => p.id == id).firstOrNull;
});

/// 持久化:support 目录 `prompt_presets.json`,只存自定义预设和顺序
/// (默认预设恒用内置文本,web 同款——localStorage 里的默认项每次加载都被覆盖)。
class PromptPresetsNotifier extends AsyncNotifier<PromptPresetsState> {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/prompt_presets.json');
  }

  @override
  Future<PromptPresetsState> build() async {
    var custom = const <PromptPreset>[];
    var order = const <String>[];
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        custom = [
          for (final e in (j['custom'] as List? ?? const []))
            PromptPreset.fromJson(e as Map<String, dynamic>),
        ];
        order = [
          for (final e in (j['order'] as List? ?? const [])) e as String,
        ];
      }
    } catch (_) {} // 损坏按初始状态处理
    // 按 id 收一遍:手改坏的文件里若混进内置 id 或重复 id,列表里就会出现两条
    // 同 id 的项 —— 管理页的拖动排序拿 id 当 key,撞 key 直接崩。内置档优先。
    final byId = <String, PromptPreset>{
      for (final p in kDefaultPromptPresets) p.id: p,
    };
    for (final p in custom) {
      byId.putIfAbsent(p.id, () => p);
    }
    return PromptPresetsState(
      presets: orderPromptPresets(byId.values.toList(), order),
    );
  }

  Future<void> _write(PromptPresetsState s) async {
    state = AsyncData(s);
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'custom': [
            for (final p in s.presets)
              if (!p.isDefault) p.toJson(),
          ],
          // 内置档也能拖,顺序表因此连内置 id 一起存(自定义档的先后光看
          // custom 数组也读得出来,但那样内置档的位置就丢了)。
          'order': [for (final p in s.presets) p.id],
        }),
      );
    } catch (_) {} // 写失败只影响下次启动的恢复,忽略
  }

  /// 当前画布换成这一档。每张画布各存一份,别的画布不跟着变。
  Future<void> setActive(String id) async {
    // 在 await 之前记下画布:等库读完时人可能已经切去别的画布了
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final s = await future;
    if (!s.presets.any((p) => p.id == id)) return;
    ref
        .read(canvasWorkspaceProvider.notifier)
        .updatePrompts(canvasId, (p) => p.copyWith(promptPresetId: id));
  }

  /// 拖动排序(管理页长按拾起)。顺序不只管管理页 —— 高级设置那个下拉照它排,
  /// 常用的档拖到前面去就少翻一屏。
  ///
  /// **内置档也能拖**:动的只是位置,正/负文本仍恒用内置的(见 [_write])。
  ///
  /// 索引按 `onReorderItem` 语义:[to] 已经按「移除 [from] 之后」调整过。
  Future<void> reorder(int from, int to) async {
    final s = await future;
    if (from == to) return;
    if (from < 0 || from >= s.presets.length) return;
    if (to < 0 || to >= s.presets.length) return;
    final next = [...s.presets];
    next.insert(to, next.removeAt(from));
    await _write(PromptPresetsState(presets: next));
  }

  /// [suffixPositive] 缺省 false = 正向拼在提示词开头。
  /// 内置档已与官方对齐成后缀,但自定义档保持前缀作默认:没有这个键的存量预设
  /// 读出来也是 false,新建时跟着同一个默认才不会出现「同样没设置、行为却不同」。
  Future<void> add({
    required String name,
    String positive = '',
    String negative = '',
    bool suffixPositive = false,
  }) async {
    final s = await future;
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = PromptPreset(
      id: 'custom_$now', // web addPromptPreset 同款 id 形态
      name: name,
      positive: positive,
      negative: negative,
      createdAt: now,
      suffixPositive: suffixPositive,
    );
    await _write(PromptPresetsState(presets: [...s.presets, p]));
  }

  /// 仅自定义可改;默认预设恒内置文本(web 同款)。
  Future<void> updatePreset(
    String id, {
    String? name,
    String? positive,
    String? negative,
    bool? suffixPositive,
  }) async {
    final s = await future;
    final presets = [
      for (final p in s.presets)
        if (p.id == id && !p.isDefault)
          p.copyWith(
            name: name,
            positive: positive,
            negative: negative,
            suffixPositive: suffixPositive,
          )
        else
          p,
    ];
    await _write(PromptPresetsState(presets: presets));
  }

  /// 仅自定义可删;用着它的画布按「无」算(web handleDeletePreset 同款,见
  /// [selectedPromptPresetId])。
  Future<void> remove(String id) async {
    final s = await future;
    if (s.presets.any((p) => p.id == id && p.isDefault)) return;
    await _write(
      PromptPresetsState(presets: [...s.presets.where((p) => p.id != id)]),
    );
  }

  /// 批量导入(web 备份迁移用):**按 id upsert** —— 与 web `restoreBackup` 的
  /// 「相同 ID 覆盖、其余保留」同语义,重复导入同一份备份是幂等的。
  /// 沿用来源 id 而非 [add] 那样新发 —— 后者按毫秒发号,一次导入多条会撞 id。
  /// 内置三档的 id 一律跳过(app 侧恒用内置文本)。返回写入条数。
  /// [activeId](备份里用着的那一档)命中已有预设时,当前画布顺带换过去;命中
  /// 不了就不动。
  Future<int> importPresets(
    List<PromptPreset> incoming, {
    String? activeId,
  }) async {
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final s = await future;
    final byId = {for (final p in s.presets) p.id: p};
    var n = 0;
    for (final p in incoming) {
      if (kDefaultPromptPresets.any((d) => d.id == p.id)) continue;
      byId[p.id] = p;
      n++;
    }
    // byId 的插入序 = 当前显示顺序:覆盖已有档就地不动,新档缀在末尾 ——
    // 导入不该把用户拖出来的顺序重排掉。
    final merged = byId.values.toList();
    if (n > 0) await _write(PromptPresetsState(presets: merged));
    if (activeId != null && merged.any((p) => p.id == activeId)) {
      ref
          .read(canvasWorkspaceProvider.notifier)
          .updatePrompts(canvasId, (p) => p.copyWith(promptPresetId: activeId));
    }
    return n;
  }
}

/// 逗号拼接(web:`${a}, ${b}`);任一侧为空则不留悬空逗号。
String joinPromptParts(String a, String b) {
  final x = a.trim();
  if (x.isEmpty) return b;
  if (b.trim().isEmpty) return x;
  return '$x, $b';
}

/// 按用户手写的 `text:` 标记把提示词切成 (标记前, 标记及其之后)。没有标记则后半为空。
///
/// 为什么要切:`text:` 之后的内容会被模型**画到图上**。后缀质量词若直接拼在整条
/// 提示词末尾,就落进了 text: 块里 —— `very aesthetic, masterpiece, no text`
/// 会被当成要写的字画出来。官方那边也是先按这个标记切开、只拼到前半段末尾。
(String, String) _splitAtTextMarker(String prompt) {
  final m = userTextMarker.firstMatch(prompt);
  if (m == null) return (prompt, '');
  return (prompt.substring(0, m.start), prompt.substring(m.start));
}

/// 把处理过的前半段与 `text:` 那一段接回去,分隔符**统一规范成 `, `**。
///
/// 标记正则会把 `text:` 前面那个分隔符一起吃掉(`, text:` 里吃的是空格,逗号留在
/// 前半段末尾)。不规范的话,拼接与剥离两侧对分隔符的处理会不一致,导入时用户原本
/// 的逗号会消失。官方那版是拿匹配到的标记原样接回去,会拼出 `no text text:` 这种
/// 没有逗号的形态 —— 对模型等价,但往返不逐字。这里规范成逗号形式,两侧对称。
String _rejoinTextBlock(String merged, String rest) {
  if (rest.isEmpty) return merged;
  final tail = rest.replaceFirst(RegExp(r'^[\s,]+'), '');
  if (merged.isEmpty) return tail;
  return '$merged, $tail';
}

/// 把预设拼进提示词。正面按 [PromptPreset.suffixPositive] 决定前/后缀,
/// 负面一律前缀(同官方)。
///
/// 后缀拼在 `text:` **之前** —— 见 [_splitAtTextMarker]。
({String positive, String negative}) applyPromptPreset(
  PromptPreset? p,
  String positive,
  String negative,
) {
  if (p == null) return (positive: positive, negative: negative);
  var nextPositive = positive;
  if (p.positive.isNotEmpty) {
    if (p.suffixPositive) {
      final (head, rest) = _splitAtTextMarker(positive);
      nextPositive = _rejoinTextBlock(
        // joinPromptParts 只 trim 空白,末尾那个逗号得自己削,否则会拼出 `a,, b`
        joinPromptParts(head.replaceFirst(RegExp(r'[\s,]+$'), ''), p.positive),
        rest,
      );
    } else {
      // 前缀在最前面,天然就在 text: 之前,不用切
      nextPositive = joinPromptParts(p.positive, positive);
    }
  }
  return (
    positive: nextPositive,
    // 负面档一律前缀,同样天然在 text: 之前
    negative: p.negative.isEmpty
        ? negative
        : joinPromptParts(p.negative, negative),
  );
}

/// 内置档是否带正面质量词(= `qualityToggle` 的取值)。
/// 自定义预设不在这张表里,恒 false —— 拿得到预设对象的调用方应直接看
/// `preset.positive.isNotEmpty`,这个函数只是给拿不到对象的地方兜底。
bool builtinPresetHasPositive(String id) =>
    kDefaultPromptPresets.any((p) => p.id == id && p.positive.isNotEmpty);

// ==================== 预设 × 模型系列 ====================

/// 当前模型能看到哪些档:内置档按 [PromptPreset.scope] 过滤,
/// 自定义预设(无 scope)两边都留。
List<PromptPreset> promptPresetsForModel(
  List<PromptPreset> presets,
  String displayModel,
) {
  final want = isNai5Model(displayModel) ? 'v5' : 'legacy';
  return [
    for (final p in presets)
      if (p.scope == null || p.scope == want) p,
  ];
}

/// 同强度档在两个系列之间的对应;没列出的(自定义预设)不参与映射。
const _presetEquivalents = <String, String>{
  'heavy': 'v5-standard',
  'light': 'v5-light',
  'v5-standard': 'heavy',
  'v5-light': 'light',
};

/// 把当前档映射到目标模型可用的档(同官方:切模型会重算质量档)。
/// 仍然可选 → 原样保留;能对上同强度档 → 换过去;都不行 → 落到列表首项。
String remapPromptPresetId(
  String activeId,
  List<PromptPreset> presets,
  String displayModel,
) {
  final visible = promptPresetsForModel(presets, displayModel);
  if (visible.any((p) => p.id == activeId)) return activeId;
  final eq = _presetEquivalents[activeId];
  if (eq != null && visible.any((p) => p.id == eq)) return eq;
  return visible.isEmpty ? 'none' : visible.first.id;
}

// ==================== 档位提示(tag_hint) ====================

/// 官方 `tag_hint_qt` / `tag_hint_uc_preset` 共用的数字表。
/// ⚠ 它和发送时那个 `ucPreset` 数字**不是**一张表 —— 后者是档位数组的下标,
/// 这张是官方内部的档位枚举顺序。两者恰好都有 heavy/light,别看串了。
const _officialPresetHintOrder = <String>[
  'none',
  'standard',
  'heavy',
  'light',
  'humanFocus',
  'furryFocus',
  'lowQualityPlusBadAnatomy',
  'lowQuality',
  'badAnatomy',
];

/// 每条内置预设的文本实际取自哪个官方档。
///
/// 官方导入图片时拿这个提示决定「先拿哪个档去试着把预设文本剥掉」,剥不掉会
/// 自己暴力扫描兜底 —— 所以对不上就留空(= none),别硬凑一个看着像的。
/// heavy 的正面是 V3 + V4.5 两段官方文本拼出来的,不对应任何单一官方档,只报负面档。
const _presetOfficialSource = <String, ({String? quality, String? uc})>{
  'heavy': (quality: null, uc: 'heavy'),
  'light': (quality: 'standard', uc: 'light'),
  'v5-standard': (quality: 'standard', uc: 'heavy'),
  'v5-light': (quality: 'light', uc: 'light'),
  'none': (quality: null, uc: null),
};

int _hintNum(String? name) {
  if (name == null) return 0;
  final i = _officialPresetHintOrder.indexOf(name);
  return i < 0 ? 0 : i;
}

/// 随生成一起发出的档位提示;自定义预设 / 未知 id 一律 none(0)。
({int qt, int ucPreset}) promptPresetTagHints(String presetId) {
  final src = _presetOfficialSource[presetId];
  return (qt: _hintNum(src?.quality), ucPreset: _hintNum(src?.uc));
}

/// 两个提示数字 → 可能的预设 id(同一对官方档在两个系列各有一条)。
Set<String> _presetIdsFromTagHints(int? qt, int? ucPreset) {
  if (qt == null && ucPreset == null) return const {};
  String name(int? n) =>
      n == null || n < 0 || n >= _officialPresetHintOrder.length
      ? 'none'
      : _officialPresetHintOrder[n];
  final wantQuality = name(qt);
  final wantUc = name(ucPreset);
  return {
    for (final e in _presetOfficialSource.entries)
      if ((e.value.quality ?? 'none') == wantQuality &&
          (e.value.uc ?? 'none') == wantUc)
        e.key,
  };
}

// ==================== 导入时的预设识别 ====================
//
// 出图时预设文本是拼进提示词一起发的,所以图片元数据里的提示词是「预设 + 用户原文」。
// 导入若原样填回输入框,当前预设会在下次生成时**再拼一遍** —— 这才是这套识别的正题,
// 认出档位只是顺带。因此:**认不出就必须把档位切到「无」**,宁可少认也不能重复拼。
//
// 判据只有一条:能不能把某个预设的文本从提示词里**干净剥掉**。
// 元数据里的 tag_hint 只决定「先试哪个」,不作为结论 —— 同官方做法,省掉一堆特例分支。

class _TagPart {
  const _TagPart(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

/// 按 `,` / `，` 切成 tag，并保留每段在原文里的位置。
///
/// 预设匹配只看 trim 后的正文；命中后的剥离必须回到原字符串操作，否则粘贴或
/// 手写的换行、空行和间距会被 `join(', ')` 静默压成一行。
List<_TagPart> _splitTagParts(String text) {
  final out = <_TagPart>[];
  var start = 0;

  void add(int end) {
    final raw = text.substring(start, end);
    final value = raw.trim();
    if (value.isEmpty) return;
    final leading = raw.indexOf(value);
    final valueStart = start + leading;
    out.add(_TagPart(value, valueStart, valueStart + value.length));
  }

  for (final separator in RegExp('[,，]').allMatches(text)) {
    add(separator.start);
    start = separator.end;
  }
  add(text.length);
  return out;
}

List<String> _splitTags(String text) => [
  for (final part in _splitTagParts(text)) part.text,
];

/// 从 tag 列表的头部或尾部剥掉 needle 序列;对不上返回 null。
///
/// 按 tag 比而不是按字符串前缀比:我们自己的内置档里就有 `absurdres,very aesthetic`
/// 这种少一个空格的写法,字符串匹配一碰格式化就废。
String? _stripTagRun(
  String source,
  List<String> needle, {
  required bool suffix,
}) {
  if (needle.isEmpty) return source;
  final parts = _splitTagParts(source);
  if (needle.length > parts.length) return null;
  final start = suffix ? parts.length - needle.length : 0;
  final seg = suffix ? parts.sublist(start) : parts.sublist(0, needle.length);
  for (var i = 0; i < needle.length; i++) {
    if (seg[i].text.toLowerCase() != needle[i].toLowerCase()) return null;
  }

  if (needle.length == parts.length) return '';

  if (suffix) {
    final kept = parts[start - 1];
    final removed = parts[start];
    final between = source.substring(kept.end, removed.start);
    final separators = RegExp('[,，]').allMatches(between).toList();
    if (separators.isEmpty) return source.substring(0, kept.end);
    var whitespace = between.substring(separators.last.end);
    // applyPromptPreset 插入的是 `, `；只去掉这个连接空格，额外的换行仍归用户。
    if (whitespace.startsWith(' ')) whitespace = whitespace.substring(1);
    return '${source.substring(0, kept.end)}$whitespace';
  }

  final removed = parts[needle.length - 1];
  final kept = parts[needle.length];
  final between = source.substring(removed.end, kept.start);
  final separator = RegExp('[,，]').firstMatch(between);
  if (separator == null) return source.substring(kept.start);
  var whitespace = between.substring(separator.end);
  if (whitespace.startsWith(' ')) whitespace = whitespace.substring(1);
  return '$whitespace${source.substring(kept.start)}';
}

/// 认出这张图用的是哪条预设,并把预设文本从提示词里剥回去。
///
/// 命中条件(严,宁可漏不可错 —— 错认等于静默删掉用户自己写的词):
/// - **正负两边都要剥得掉**。我们的预设正负成对,这一条几乎把误判清零:用户手打
///   一个 `masterpiece` 不会命中,因为负面那十几个词不可能同时凑齐。
///   单边为空的预设退化成只验另一边。
/// - 认位置:前缀档从头剥,后缀档从尾剥。这不只是精确性 —— 4.5 的 Light 和 V5 的
///   Standard **正面文本完全相同**,只有位置能区分。
/// - 候选按 tag 总数倒序:长档先试,免得短档把长档的一部分先啃掉。
///
/// [hintQt] / [hintUcPreset] 是元数据里的档位提示,只用来把候选排到队首。
({PromptPreset preset, String positive, String negative})? detectPromptPreset(
  List<PromptPreset> presets,
  String positive,
  String negative, {
  int? hintQt,
  int? hintUcPreset,
}) {
  // 与 applyPromptPreset 对称:后缀是拼在 `text:` 之前的,剥的时候也只在那一段里剥
  final (posHead, posTextBlock) = _splitAtTextMarker(positive);
  final hinted = _presetIdsFromTagHints(hintQt, hintUcPreset);

  final candidates =
      [
        for (final p in presets)
          if (p.positive.isNotEmpty || p.negative.isNotEmpty)
            (
              preset: p,
              weight:
                  _splitTags(p.positive).length + _splitTags(p.negative).length,
            ),
      ]..sort((a, b) {
        final ha = hinted.contains(a.preset.id) ? 1 : 0;
        final hb = hinted.contains(b.preset.id) ? 1 : 0;
        return hb != ha ? hb - ha : b.weight - a.weight;
      });

  for (final c in candidates) {
    final wantPos = _splitTags(c.preset.positive);
    final wantNeg = _splitTags(c.preset.negative);
    // 正面**两端都试**,先试这条预设声明的那一端。
    //
    // 位置会变:heavy/light 历史上拼在句首,1.0.7 起改成句尾(与官方对齐)。
    // 只认当前那一端的话,**改版之前出的图、以及 web 端出的图全都认不出来** ——
    // 而认不出的后果正是这套识别要防的那件事:导回去再生成,质量词被拼第二遍。
    //
    // 放宽到两端不会松掉判据:真正把误判挡住的是「正负两边都要剥得掉」,
    // 而负面一律前缀、从没变过。
    final restPos = wantPos.isEmpty
        ? posHead
        : (_stripTagRun(posHead, wantPos, suffix: c.preset.suffixPositive) ??
              _stripTagRun(posHead, wantPos, suffix: !c.preset.suffixPositive));
    if (restPos == null) continue;
    final restNeg = wantNeg.isEmpty
        ? negative
        : _stripTagRun(negative, wantNeg, suffix: false);
    if (restNeg == null) continue;
    return (
      preset: c.preset,
      positive: _rejoinTextBlock(restPos, posTextBlock),
      negative: restNeg,
    );
  }
  return null;
}

/// 各模型的官方**负面档数组**——只留 id 顺序,档位正文 app 自己有。
/// 线上 `ucPreset` 字段发的就是某档在这个数组里的下标。
///
/// ⚠ **每个模型的数组长度都不一样**,不能写死一张表:`none` 在 V5/4.5Full 是 4、
/// 4.5Curated 是 3、V4 两档是 2、V3 是 3。4.5Curated 没有 furryFocus,V4 两档
/// 连 humanFocus 都没有。以前这里写死 4,对后四者就是错的(只污染元数据、不影响
/// 出图,但没理由留着)。2026-08-25 跟 web `officialPresets.ts` 的 OFFICIAL_UC 对齐。
const _ucTiers = <String, List<String>>{
  'v5': ['heavy', 'light', 'furryFocus', 'humanFocus', 'none'],
  'v4.5-full': ['heavy', 'light', 'furryFocus', 'humanFocus', 'none'],
  'v4.5-curated': ['heavy', 'light', 'humanFocus', 'none'],
  'v4-full': ['heavy', 'light', 'none'],
  'v4-curated': ['heavy', 'light', 'none'],
  'v3': ['heavy', 'light', 'humanFocus', 'none'],
};

/// **API 模型 id**(`nai-diffusion-*`)→ [_ucTiers] 的键。
/// 对齐 web `presetKeyForModel`;认不出一律按 v5 处理(与 web 同款兜底)。
String _ucKeyForModel(String modelId) {
  final m = modelId.toLowerCase();
  if (m.startsWith('v5') || m.startsWith('nai-diffusion-5')) return 'v5';
  if (m.contains('4.5') || m.contains('4-5')) {
    return m.contains('curated') ? 'v4.5-curated' : 'v4.5-full';
  }
  if (m.startsWith('v4') || m.startsWith('nai-diffusion-4')) {
    return m.contains('curated') ? 'v4-curated' : 'v4-full';
  }
  if (m.startsWith('v3') || m.startsWith('nai-diffusion-3')) return 'v3';
  return 'v5';
}

/// 预设 id → 它套用的官方负面档名。表外(自定义预设)一律 none:负面词是用户
/// 自己写的,不该再宣称套了官方档。`v5-*` 是把「正面质量档 + 负面档」并成一条
/// 预设后的内置 id,取值跟随其官方负面档。
String _ucTierOf(String presetId) => switch (presetId) {
  'heavy' || 'v5-standard' => 'heavy',
  'light' || 'v5-light' => 'light',
  'furryFocus' => 'furryFocus',
  'humanFocus' => 'humanFocus',
  _ => 'none',
};

/// 线上 `ucPreset` 发的数字 = 该档在 [modelId] 负面档数组里的下标。
///
/// 直连与 bot 两条线共用这一个函数。**别再按线拆成两份** —— bot 线历史上那套
/// 自造的反向取值(heavy→4 / none→0)就是这么跑偏的:web 改表时只有一张跟着改,
/// app 这边两张都留着,于是「重度」被记成了「无」。
///
/// 该模型没有的档(如 4.5Curated 的 furryFocus)落回它的 none 下标,同 web。
int ucPresetValue(String presetId, String modelId) {
  final tiers = _ucTiers[_ucKeyForModel(modelId)]!;
  final i = tiers.indexOf(_ucTierOf(presetId));
  if (i >= 0) return i;
  final none = tiers.indexOf('none');
  return none >= 0 ? none : tiers.length - 1;
}

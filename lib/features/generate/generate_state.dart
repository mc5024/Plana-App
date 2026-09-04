import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../vibe_library/naiv4vibe_codec.dart' show kModelToEncodingKey;
import 'char_position.dart';
import 'gen_modules.dart';
import 'lora_triggers.dart' show removeLoraTriggersFromPrompt;
import 'models.dart';
import 'nai_request.dart' show naiModelId;

final generateProvider = NotifierProvider<GenerateNotifier, GenerateState>(
  GenerateNotifier.new,
);

/// token 读数唯一的角色口径,规则见 [countedCharacters]:模块不可见
/// (anima 等)时整组不计,免得计数自己变大。
final countedCharactersProvider = Provider<List<CharacterPrompt>>((ref) {
  final ms = ref.watch(genModulesProvider).value ?? const GenModuleSettings();
  return countedCharacters(ref.watch(generateProvider), ms);
});

class GenerateNotifier extends Notifier<GenerateState> {
  int _idSeq = 100;

  @override
  GenerateState build() {
    // 启动水合 + 每次状态变更排队防抖落盘:重启回到原样工作台
    final ws = ref.watch(appStoresProvider).workspace;
    _idSeq = ws.idSeq;
    listenSelf((_, next) => ws.schedule(next, idSeq: _idSeq));
    return ws.initial ?? GenerateState.initial();
  }

  String _newId() => 'id${_idSeq++}';

  // ---- 面板开合 ----
  void togglePanel(Panel p) {
    final open = {...state.openPanels};
    open.contains(p) ? open.remove(p) : open.add(p);
    state = state.copyWith(openPanels: open);
  }

  void openPanel(Panel p) {
    if (state.openPanels.contains(p)) return;
    state = state.copyWith(openPanels: {...state.openPanels, p});
  }

  // ---- 角色 ----

  /// 换模型后收口:从尾巴往前停用角色,直到**启用**数落回新模型的上限内。
  ///
  /// V5 能摆 32 个,V4/V4.5 只有 6 个(见 [maxCharactersOf])。两条发送线都只按
  /// 「启用且正向非空」筛角色、**都不截断**,所以从 V5 切下来不收口的话,第 7 个
  /// 往后照样发出去 —— 卡头那句「超出的不进载荷」在此之前并不成立。
  ///
  /// 停用而不是删除:切回 V5 时人还在,勾一下就回来。
  ///
  /// 按启用数而不是按位置数:已经手动停用的不占额度,所以「10 张里自己停了 4 张」
  /// 这种本来就合规的配置一张都不会被动到 —— 换成按下标砍会把它砍到只剩 2 张。
  List<CharacterPrompt> _capEnabled(List<CharacterPrompt> chars, String model) {
    final cap = maxCharactersOf(model);
    if (chars.where((c) => c.enabled).length <= cap) return chars;
    var kept = 0;
    return [
      for (final c in chars)
        if (c.enabled && ++kept > cap) c.copyWith(enabled: false) else c,
    ];
  }

  /// 新角色的初始站位。**建的时候就定死**,不是发送时按下标现算 —— 后者会让
  /// 「删掉前面一个角色」把后面那些一起挪窝,用户什么都没动出图却变了。
  String _spawnPos([List<CharacterPrompt>? over]) => nextSpawnPosition(
    (over ?? state.characters).map((c) => c.position),
    freeform: isNai5Model(state.params.model),
  );

  /// 角色定位:AI 自选(false)/ 用我摆的位置(true)。对应请求里的
  /// `v4_prompt.use_coords`,官方默认 false。
  void setUseCoords(bool v) {
    if (state.params.useCoords == v) return;
    state = state.copyWith(params: state.params.copyWith(useCoords: v));
  }

  void addCharacter() {
    if (state.characters.length >= maxCharactersOf(state.params.model)) return;
    final c = CharacterPrompt(
      id: _newId(),
      name: '角色 ${state.characters.length + 1}',
      position: _spawnPos(),
    );
    state = state.copyWith(characters: [...state.characters, c]);
    openPanel(Panel.characters);
  }

  /// 追加若干张**已填好内容**的角色卡(法典多角色词条导入)。
  ///
  /// 超出上限的直接丢弃并返回**实际加进去的条数** —— 调用方据此告诉用户丢了
  /// 几个。静默截断是不行的:词条里明明有 4 个角色,进来只剩 2 个而不吭声,
  /// 用户只会以为是解析出了错。
  int addCharactersFilled(
    List<({String name, String positive, String negative})> items,
  ) {
    if (items.isEmpty) return 0;
    final room = maxCharactersOf(state.params.model) - state.characters.length;
    if (room <= 0) return 0;
    // 逐个挑位:每加一个都要把它自己算进「已占用」,否则整批全落同一格
    final add = <CharacterPrompt>[];
    for (final it in items.take(room)) {
      add.add(
        CharacterPrompt(
          id: _newId(),
          name: it.name,
          positive: it.positive,
          negative: it.negative,
          position: _spawnPos([...state.characters, ...add]),
        ),
      );
    }
    state = state.copyWith(characters: [...state.characters, ...add]);
    openPanel(Panel.characters);
    return add.length;
  }

  void updateCharacter(
    String id, {
    String? name,
    String? positive,
    String? negative,
    String? positiveRaw,
    String? negativeRaw,
    bool? enabled,
    Object? position = const Object(),
    CharTab? activeTab,
  }) {
    final useSentinel = position is! String?;
    state = state.copyWith(
      characters: [
        for (final c in state.characters)
          if (c.id == id)
            useSentinel
                ? c.copyWith(
                    name: name,
                    positive: positive,
                    negative: negative,
                    positiveRaw: positiveRaw,
                    negativeRaw: negativeRaw,
                    enabled: enabled,
                    activeTab: activeTab,
                  )
                : c.copyWith(
                    name: name,
                    positive: positive,
                    negative: negative,
                    positiveRaw: positiveRaw,
                    negativeRaw: negativeRaw,
                    enabled: enabled,
                    position: position,
                    activeTab: activeTab,
                  )
          else
            c,
      ],
    );
  }

  void removeCharacter(String id) {
    state = state.copyWith(
      characters: state.characters.where((c) => c.id != id).toList(),
    );
  }

  void clearCharacters() => state = state.copyWith(characters: const []);

  /// 参数导入:把元数据角色写入(replace=完全覆盖清空原有;否则额外追加),
  /// 尊重按模型的角色上限([maxCharactersOf])。追加时名称按最终位置续号。
  /// position 'A1'..'E5' 网格 id 或 'x,y' 自由坐标(V5),null=AUTO。
  void addCharactersFrom(
    List<({String positive, String negative, String? position})> chars, {
    required bool replace,
  }) {
    final cap = maxCharactersOf(state.params.model);
    final base = replace ? <CharacterPrompt>[] : [...state.characters];
    for (final c in chars) {
      if (base.length >= cap) break;
      base.add(
        CharacterPrompt(
          id: _newId(),
          name: '角色 ${base.length + 1}',
          positive: c.positive,
          negative: c.negative,
          // 导入带来的站位优先;没有(元数据里没坐标)就照官方挑一个空格
          position: c.position ?? _spawnPos(base),
        ),
      );
    }
    state = state.copyWith(characters: base);
    if (base.isNotEmpty) openPanel(Panel.characters);
  }

  /// 灵感页「加入角色」:带名追加(名字取自角色条目),尊重张数上限
  /// (按模型取,见 maxCharactersOf),超出静默截断(对齐 web
  /// availableSlots 语义)。返回实际加入条数。
  int addNamedCharactersFrom(
    List<({String name, String positive, String negative})> chars,
  ) {
    final cap = maxCharactersOf(state.params.model);
    final base = [...state.characters];
    var added = 0;
    for (final c in chars) {
      if (base.length >= cap) break;
      base.add(
        CharacterPrompt(
          id: _newId(),
          name: c.name.isNotEmpty ? c.name : '角色 ${base.length + 1}',
          positive: c.positive,
          negative: c.negative,
          position: _spawnPos(base),
        ),
      );
      added++;
    }
    if (added > 0) {
      state = state.copyWith(characters: base);
      openPanel(Panel.characters);
    }
    return added;
  }

  void moveCharacter(String id, int delta) {
    final list = [...state.characters];
    final i = list.indexWhere((c) => c.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    final c = list.removeAt(i);
    list.insert(j, c);
    state = state.copyWith(characters: list);
  }

  // ---- Vibe ↔ 角色参考 互斥 ----
  // 对齐 web「CR 和 Vibe 互斥」:启用/加入一方,即停用另一方的全部条目
  // (非破坏:另一方图片仍在列表里,只是禁用不发送;生成端只发启用的那一组)。
  List<CharRefItem> _charRefsDisabled() => [
    for (final r in state.charRefs)
      if (r.enabled) r.copyWith(enabled: false) else r,
  ];
  List<VibeItem> _vibesDisabled() => [
    for (final v in state.vibes)
      if (v.enabled) v.copyWith(enabled: false) else v,
  ];

  // ---- Vibe ----
  String addVibe({
    Uint8List? image,
    required String name,
    String? imageHash,
    double strength = 0.6,
    double infoExtracted = 1.0,
    Map<String, String>? encodedByModel,
    String? sourceId,
  }) {
    // 无图也无编码的条目无法参与生成,拒收
    if (image == null && (encodedByModel == null || encodedByModel.isEmpty)) {
      return '';
    }
    final id = _newId();
    state = state.copyWith(
      vibes: [
        ...state.vibes,
        VibeItem(
          id: id,
          name: name,
          image: image,
          imageHash: imageHash,
          strength: strength,
          infoExtracted: infoExtracted,
          encodedByModel: encodedByModel,
          sourceId: sourceId,
        ),
      ],
      charRefs: _charRefsDisabled(), // 与角色参考互斥
    );
    openPanel(Panel.vibe);
    return id;
  }

  void updateVibe(String id, {double? strength, double? infoExtracted}) {
    state = state.copyWith(
      vibes: [
        for (final v in state.vibes)
          if (v.id == id)
            v.copyWith(strength: strength, infoExtracted: infoExtracted)
          else
            v,
      ],
    );
  }

  void removeVibe(String id) {
    state = state.copyWith(
      vibes: state.vibes.where((v) => v.id != id).toList(),
    );
  }

  /// 停用「缺当前模型编码的纯编码 Vibe」:无原图无从现场编码,
  /// 生成时只会被静默跳过。生成入口调用,返回停用数量供提示。
  int disableVibesMissingEncoding() {
    // vibe 模块当前不可见(隐藏/父类不符)时本就不发送,不停用也不提示
    final mods =
        ref.read(genModulesProvider).value ?? const GenModuleSettings();
    if (!mods.isVisibleFor(GenModule.vibe, state.params.model)) return 0;
    final model = naiModelId(state.params.model);
    final key = kModelToEncodingKey[model] ?? model;
    bool missing(VibeItem v) =>
        v.enabled && v.isEncodingOnly && v.encodedByModel?[key] == null;
    final hit = state.vibes.where(missing).length;
    if (hit == 0) return 0;
    state = state.copyWith(
      vibes: [
        for (final v in state.vibes)
          missing(v) ? v.copyWith(enabled: false) : v,
      ],
    );
    return hit;
  }

  void setVibeEnabled(String id, bool enabled) {
    state = state.copyWith(
      vibes: [
        for (final v in state.vibes)
          if (v.id == id) v.copyWith(enabled: enabled) else v,
      ],
      // 启用 Vibe 即停用角色参考(互斥);停用时不动另一方
      charRefs: enabled ? _charRefsDisabled() : null,
    );
  }

  /// 整体替换 vibe 列表(Vibe 管理器 / 角色参考图库按**返回键**还原进入前
  /// 快照用;参数导入「完全覆盖」传 const [] 先清空再逐个 addVibe)。
  void restoreVibes(List<VibeItem> vibes) =>
      state = state.copyWith(vibes: vibes);

  // ---- 角色参考 ----
  String addCharRef({
    required Uint8List image,
    required String name,
    String? imageHash,
  }) {
    final id = _newId();
    state = state.copyWith(
      charRefs: [
        ...state.charRefs,
        CharRefItem(id: id, name: name, image: image, imageHash: imageHash),
      ],
      vibes: _vibesDisabled(), // 与 Vibe 互斥
    );
    openPanel(Panel.charRef);
    return id;
  }

  void updateCharRef(
    String id, {
    CharRefMode? mode,
    double? strength,
    double? infoExtracted,
  }) {
    state = state.copyWith(
      charRefs: [
        for (final r in state.charRefs)
          if (r.id == id)
            r.copyWith(
              mode: mode,
              strength: strength,
              infoExtracted: infoExtracted,
            )
          else
            r,
      ],
    );
  }

  void removeCharRef(String id) {
    state = state.copyWith(
      charRefs: state.charRefs.where((r) => r.id != id).toList(),
    );
  }

  void setCharRefEnabled(String id, bool enabled) {
    state = state.copyWith(
      charRefs: [
        for (final r in state.charRefs)
          if (r.id == id) r.copyWith(enabled: enabled) else r,
      ],
      // 启用角色参考即停用 Vibe(互斥);停用时不动另一方
      vibes: enabled ? _vibesDisabled() : null,
    );
  }

  /// 整体替换角色参考列表(角色参考图库 / Vibe 管理器按**返回键**还原进入前
  /// 快照用 —— 两边互斥,还原一方必须连另一方一起还)。
  void restoreCharRefs(List<CharRefItem> refs) =>
      state = state.copyWith(charRefs: refs);

  // ---- 风格参考(krea 专属) ----

  /// 加一张参考图。**满了就丢弃**(而不是顶掉已有的):用户一次选多张时,
  /// 先来的那几张才是他先挑中的。返回新条目 id;满员时返回空串。
  String addKreaStyleRef({
    required Uint8List image,
    required String name,
    String? imageHash,
  }) {
    if (state.kreaStyleRefs.length >= kMaxKreaStyleRefs) return '';
    final id = _newId();
    state = state.copyWith(
      kreaStyleRefs: [
        ...state.kreaStyleRefs,
        KreaStyleRefItem(
          id: id,
          name: name,
          image: image,
          imageHash: imageHash,
        ),
      ],
    );
    openPanel(Panel.kreaStyleRef);
    return id;
  }

  void setKreaStyleRefEnabled(String id, bool enabled) {
    state = state.copyWith(
      kreaStyleRefs: [
        for (final r in state.kreaStyleRefs)
          if (r.id == id) r.copyWith(enabled: enabled) else r,
      ],
    );
  }

  void removeKreaStyleRef(String id) {
    state = state.copyWith(
      kreaStyleRefs: state.kreaStyleRefs.where((r) => r.id != id).toList(),
    );
  }

  /// 参考强度(全局一份,所有参考图共用)。
  void setKreaStyleRefWeight(double v) => state = state.copyWith(
    kreaStyleRefWeight: v.clamp(0.0, kKreaStyleRefWeightMax),
  );

  // ---- LoRA(anima / krea 共用) ----
  /// LoRA 管理器「确认挂载」:按选中卡整体替换挂载列表。
  /// 已挂条目保留用户调过的 weight/enabled(注册表字段刷新),新条目用推荐值;
  /// 超出上限截断,返回实际挂载数供调用方提示。
  int applyLoraSelection(List<ActiveLora> picked) {
    final byName = {for (final l in state.loras) l.name: l};
    final next = <ActiveLora>[];
    for (final p in picked) {
      if (next.length >= kMaxActiveLoras) break;
      final old = byName[p.name];
      next.add(
        old == null
            ? p
            : p.copyWith(
                weight: old.weight,
                enabled: old.enabled,
                clipWeight: old.clipWeight,
              ),
      );
    }
    state = state.copyWith(loras: next);
    if (next.isNotEmpty) openPanel(Panel.lora);
    return next.length;
  }

  void updateLora(
    String name, {
    double? weight,
    bool? enabled,
    double? clipWeight,
    bool clearClipWeight = false,
  }) {
    state = state.copyWith(
      loras: [
        for (final l in state.loras)
          if (l.name == name)
            l.copyWith(
              weight: weight,
              enabled: enabled,
              clipWeight: clipWeight,
              clearClipWeight: clearClipWeight,
            )
          else
            l,
      ],
    );
  }

  /// 占位条转正:按占位 name 找到那条,原地换成装好的真条目。
  ///
  /// 位置不动(用户已经在心里给它排好序了),并保留下载期间他改过的权重/启停;
  /// 同一个 LoRA 已经从别处挂上了就把占位的撤掉,不留两条。
  ///
  /// **占位条不在了就什么都不做**(返回 false,调用方只报「已下载」)——
  /// 那意味着用户在下载期间把它移除了,或者中途载入了别的工作区/快照。
  /// 这两种情况下他手上的配置里都没有这一条,下载完再塞回去就是个幽灵改动:
  /// 明明点了移除,过几分钟它自己又回来了。装好的本体在库里,要用去挂载即可。
  bool promotePendingLora(String placeholder, ActiveLora real) {
    final idx = state.loras.indexWhere((l) => l.name == placeholder);
    if (idx < 0) return false;
    final old = state.loras[idx];
    final dup = state.loras.any((l) => l.name == real.name);
    state = state.copyWith(
      loras: [
        for (var i = 0; i < state.loras.length; i++)
          if (i != idx)
            state.loras[i]
          else if (!dup)
            real.copyWith(
              weight: old.weight,
              enabled: old.enabled,
              clipWeight: old.clipWeight,
            ),
      ],
    );
    return true;
  }

  /// 占位条下载失败:标红并停用,留在原地等用户处理(移除或重新导入)。
  void markLoraFailed(String placeholder, String reason) {
    if (!state.loras.any((l) => l.name == placeholder)) return;
    state = state.copyWith(
      loras: [
        for (final l in state.loras)
          if (l.name == placeholder)
            l.copyWith(
              enabled: false,
              pending: LoraPending(
                versionId: l.pending?.versionId ?? 0,
                failed: reason,
              ),
            )
          else
            l,
      ],
    );
  }

  void removeLora(String name) {
    final victim = [
      for (final l in state.loras)
        if (l.name == name) l,
    ];
    final rest = state.loras.where((l) => l.name != name).toList();
    state = state.copyWith(loras: rest);
    // 删 LoRA 连带收走它在场的触发词;其他在架 LoRA(含暂禁用的)仍占用
    // 的 tag 留下。setPrompts 顺带作废编辑器原文草稿(编辑器外改写语义)。
    if (victim.isEmpty || victim.first.triggerWords.isEmpty) return;
    final cleaned = removeLoraTriggersFromPrompt(
      state.prompt,
      victim.first.triggerWords,
      keepTriggers: [for (final l in rest) l.triggerWords],
    );
    if (cleaned != state.prompt) setPrompts(positive: cleaned);
  }

  // ---- 重绘放大(anima 专属) ----
  /// 局部更新 hires 配置。[steps] 除 0(跟随主步数)外钳进服务端可接受的
  /// [kHiresStepsMin]~[kHiresStepsMax] —— 否则滑杆停在 2、后端按 4 跑,读数骗人。
  /// 从关到开时顺手展开面板,和挂 LoRA / 选底图的手感一致。
  void updateHires({
    bool? enabled,
    double? scale,
    double? denoise,
    int? steps,
    bool? useModel,
    HiresUpscaler? model,
  }) {
    final cur = state.params.hires;
    final next = cur.copyWith(
      enabled: enabled,
      scale: scale,
      denoise: denoise,
      steps: steps == null || steps == 0
          ? steps
          : steps.clamp(kHiresStepsMin, kHiresStepsMax),
      useModel: useModel,
      model: model,
    );
    state = state.copyWith(params: state.params.copyWith(hires: next));
    if (next.enabled && !cur.enabled) openPanel(Panel.hires);
  }

  // ---- 图生图 ----
  /// 选定底图:存原图 + 自动把生成分辨率设成图片尺寸(64 对齐/像素封顶,调用方已算好)。
  void setImg2ImgImage({
    required Uint8List image,
    required int width,
    required int height,
  }) {
    final cur = state.img2img;
    state = state.copyWith(
      img2img: Img2ImgConfig(
        image: image,
        strength: cur?.strength ?? 0.7,
        noise: cur?.noise ?? 0.0,
      ),
      params: state.params.copyWith(width: width, height: height),
    );
    openPanel(Panel.i2i);
  }

  void updateImg2Img({double? strength, double? noise}) {
    final cur = state.img2img;
    if (cur == null) return;
    state = state.copyWith(
      img2img: cur.copyWith(strength: strength, noise: noise),
    );
  }

  void disableImg2Img() => state = state.copyWith(img2img: null);

  // ---- 重绘遮罩 ----

  /// 遮罩编辑器存盘:底图 + 遮罩 + 强度(+ 局部重绘的回贴信息)一起落进创作页
  /// 状态,发车交给主生成按钮。
  ///
  /// 顺带把生成分辨率设成**发送尺寸** —— 局部重绘发的是裁切区、扩图发的是垫大
  /// 之后的画布,两者都不是原图尺寸。不设的话下一次生成会按创作页那个旧尺寸发,
  /// 服务端收到的图和声明的尺寸对不上。
  ///
  /// 与 img2img 互斥:带遮罩的图生图就是重绘,留着另一份底图只会让发送层二选一。
  void setInpaint(InpaintJob job, {required int width, required int height}) {
    state = state.copyWith(
      inpaint: job,
      img2img: null,
      params: state.params.copyWith(width: width, height: height),
    );
    openPanel(Panel.i2i);
  }

  /// 改强度(遮罩不动)。
  void updateInpaintStrength(double strength) {
    final cur = state.inpaint;
    if (cur == null) return;
    state = state.copyWith(
      inpaint: InpaintJob(
        image: cur.image,
        mask: cur.mask,
        strength: strength,
        paste: cur.paste,
      ),
    );
  }

  void clearInpaint() => state = state.copyWith(inpaint: null);

  // ---- 提示词(编辑器实时回写) ----
  /// 提示词写入。[positiveRaw] / [negativeRaw] 是编辑器原文草稿(含禁用、
  /// 折叠等仅编辑期语法),**传了就照写**;不传则视为编辑器之外的写入方,
  /// 只有该侧定稿真的变了才清掉旧草稿(它必然已过期)。
  ///
  /// 「传了才写」这条不能简化成「定稿变了才写」:**折叠不改变定稿**
  /// (outputOf 会把记号剥掉),编辑器加一个折叠组时 positive 一字未变、
  /// 只有草稿变了,按定稿判断会把这次折叠直接丢掉。
  /// 反过来「没传就清」也不能简化成无条件清:外部写入方传入的值可能与
  /// 现值相同(灵感页去重后没有新增),那一侧的禁用词不该因此蒸发。
  void setPrompts({
    String? positive,
    String? negative,
    String? positiveRaw,
    String? negativeRaw,
  }) {
    final nextRawP =
        positiveRaw ??
        (positive != null && positive != state.prompt ? '' : state.promptRaw);
    final nextRawN =
        negativeRaw ??
        (negative != null && negative != state.negativePrompt
            ? ''
            : state.negativePromptRaw);
    // 编辑器防抖回写高频触发,同值短路避免无谓的状态通知与落盘
    if ((positive ?? state.prompt) == state.prompt &&
        (negative ?? state.negativePrompt) == state.negativePrompt &&
        nextRawP == state.promptRaw &&
        nextRawN == state.negativePromptRaw) {
      return;
    }
    state = state.copyWith(
      prompt: positive,
      negativePrompt: negative,
      promptRaw: nextRawP,
      negativePromptRaw: nextRawN,
    );
  }

  // ---- 参数 ----
  void applyParams(GenParams params) => state = state.copyWith(params: params);

  /// 参数导入:按元数据回填生成参数(仅传入非空字段生效,copyWith 忽略 null)。
  /// 元数据导入落地。只传要改的字段,null = 保持不动。
  ///
  /// NAI / Anima / Krea 是三套独立的采样参数(分别是 steps·cfg·sampler·
  /// noiseSchedule / anima* / krea*),width/height/seed 三边共用 ——
  /// 调用方按**当前模型**的类别决定传哪组。
  void applyImportedSettings({
    String? model,
    int? width,
    int? height,
    int? steps,
    double? cfg,
    double? cfgRescale,
    bool? varietyPlus,
    String? sampler,
    String? noiseSchedule,
    String? seed,
    int? animaSteps,
    double? animaCfg,
    String? animaSampler,
    String? animaScheduler,
    int? kreaSteps,
    double? kreaCfg,
    String? kreaSampler,
    String? kreaScheduler,
  }) {
    // 换档位时先把旧档那套收进记忆(与 setModel 同一套规矩)。**不**跟着取回
    // 新档的:导入面板给了哪些字段就落哪些,没勾的项保持不动是这条路的本意。
    var cur = state.params;
    if (model != null && model != cur.model) cur = cur.rememberModalSampling();
    state = state.copyWith(
      // 导入面板勾了模型这一项时也可能把槽位换小,同 setModel 一样收口。
      // 角色是在这之前落地的(导入面板先加角色再落设置),所以得在这儿再过一遍。
      characters: _capEnabled(state.characters, model ?? cur.model),
      params: cur.copyWith(
        model: model,
        width: width,
        height: height,
        steps: steps,
        cfg: cfg,
        cfgRescale: cfgRescale,
        varietyPlus: varietyPlus,
        sampler: sampler,
        noiseSchedule: noiseSchedule,
        seed: seed,
        animaSteps: animaSteps,
        animaCfg: animaCfg,
        animaSampler: animaSampler,
        animaScheduler: animaScheduler,
        kreaSteps: kreaSteps,
        kreaCfg: kreaCfg,
        kreaSampler: kreaSampler,
        kreaScheduler: kreaScheduler,
      ),
    );
  }

  void setSize(int width, int height) => state = state.copyWith(
    params: state.params.copyWith(width: width, height: height),
  );

  /// 切模型;Anima / Krea 的采样参数按档位存取:**这档调过就还原成调过的样子,
  /// 没进过才套官方推荐配方**(见 [GenParams.modalMem])。
  ///
  /// 比 web 的 applyAnimaTier / applyKreaTier 多了「记住」这一步 —— 那边每次
  /// 选中都无条件套默认值,于是回 NAI 转一圈再切回来、甚至在弹层里点一下当前
  /// 这档,调好的步数/CFG 就没了。联动的初衷(切到慢档别还挂着蒸馏档的 12 步)
  /// 由「没进过的档才套配方」保住。
  ///
  /// 换 LoRA 底模时连带清空已挂的:上一个库的 LR 编号在新库里查无此条,
  /// 留着发出去服务端会静默丢弃,等于白跑一次生成(对齐 web prevLoraBaseRef)。
  /// NAI 归在 anima 那一侧,所以 NAI↔Anima 来回切不动列表,只有进出 Krea 才清。
  void setModel(String model) {
    // 收好旧档 → 换名 → 取回新档,顺序不能反(两步各自认 params.model)
    final p = state.params
        .rememberModalSampling()
        .copyWith(model: model)
        .recallModalSampling();
    final baseChanged =
        loraBaseOf(model) != loraBaseOf(state.params.model) &&
        state.loras.isNotEmpty;
    state = state.copyWith(
      params: p,
      loras: baseChanged ? const [] : null,
      // 5 → 4/4.5 槽位从 32 掉到 6,超出的尾巴就地停用(见 [_capEnabled])
      characters: _capEnabled(state.characters, model),
    );
  }

  void setLoop(LoopCount l) =>
      state = state.copyWith(params: state.params.copyWith(loop: l));

  /// 一次出几张(anima / krea)。夹在服务端上限内 —— 那边也会夹一遍,
  /// 但界面上显示的必须是真会出的数。
  void setBatchCount(int n) => state = state.copyWith(
    params: state.params.copyWith(batchCount: n.clamp(1, kBatchMax)),
  );

  // ---- 长按拖动排序(onReorderItem 语义:newIndex 已按移除后调整)----

  List<T> _reordered<T>(List<T> src, int oldIndex, int newIndex) {
    final l = [...src];
    l.insert(newIndex, l.removeAt(oldIndex));
    return l;
  }

  void reorderCharacters(int oldIndex, int newIndex) => state = state.copyWith(
    characters: _reordered(state.characters, oldIndex, newIndex),
  );

  void reorderVibes(int oldIndex, int newIndex) => state = state.copyWith(
    vibes: _reordered(state.vibes, oldIndex, newIndex),
  );

  void reorderCharRefs(int oldIndex, int newIndex) => state = state.copyWith(
    charRefs: _reordered(state.charRefs, oldIndex, newIndex),
  );

  void reorderKreaStyleRefs(int oldIndex, int newIndex) =>
      state = state.copyWith(
        kreaStyleRefs: _reordered(state.kreaStyleRefs, oldIndex, newIndex),
      );

  void refreshAnlas() {
    // 占位:正式版调 NAI /user/subscription
    state = state.copyWith(anlas: state.anlas);
  }
}

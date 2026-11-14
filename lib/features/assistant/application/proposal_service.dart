/// 助手与创作页之间的读写:引用画布时读什么、提议导入 / 撤销 / 拿去生成时写什么。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gallery/gallery_state.dart' show galleryProvider;
import '../../generate/agent_chars.dart';
import '../../generate/canvas_state.dart';
import '../../generate/char_position.dart';
import '../../generate/gen_modules.dart';
import '../../generate/generate_state.dart';
import '../../generate/generation_controller.dart'
    show GenOutcome, generationProvider;
import '../../generate/models.dart' show GenerateState;
import '../../generate/prompt_sections.dart'
    show SectionImport, importPromptsInto, joinSections;
import '../../inspiration/tag_models.dart';
import '../assistant_settings.dart';
import '../domain/conversation.dart';
import '../domain/turn_request.dart';

/// 一份提议**拿去生成**时发出的状态。纯函数,不碰任何 provider。
///
/// 沿用创作页的只有参数、Vibe 和主提示词分区:正向、负向按 [mode] 写进主提示词
/// (与导入同一个 [importPromptsInto]);角色分区只认 AI 这份;模型、尺寸、采样、种子照创作页。
/// 四个图像模块里只留 Vibe:角色参考、图生图、重绘是冲着某张具体的图配的,套到 AI 写的
/// 新画面上只会拧在一起。坐标开关跟着 AI 的角色分区走。
GenerateState proposalSendState(
  GenerateState canvas,
  DrawProposal r,
  SectionImport mode, {
  required String Function() newId,
}) {
  final built = buildAgentCharacters(
    [
      for (final c in r.characters)
        (
          name: c.name,
          positive: c.positive,
          negative: c.negative,
          position: c.position,
        ),
    ],
    model: canvas.params.model,
    newId: newId,
  );
  return importPromptsInto(
    canvas,
    r.positive,
    r.negative,
    mode,
    newId: newId,
  ).copyWith(
    characters: built.chars,
    charRefs: const [],
    img2img: null,
    inpaint: null,
    params: canvas.params.copyWith(useCoords: built.placed),
  );
}

/// 提议里用到的库内画师串,把它们的负面补进负向(去重,同灵感页加画风)。
///
/// 画师串是占位符换回来的,内容逐字不动,按整串出现在正向(含角色正向)里认。
String withArtistNegatives(DrawProposal r, Iterable<TagEntry> artists) {
  final texts = [r.positive, for (final c in r.characters) c.positive];
  final used = [
    for (final e in artists)
      if (e.negative.trim().isNotEmpty &&
          e.positive.trim().isNotEmpty &&
          texts.any((t) => t.contains(e.positive.trim())))
        e,
  ];
  return used.isEmpty ? r.negative : appendTagNegatives(r.negative, used);
}

/// 创作页有没有可带给 AI 的东西。全空时「引用创作页」那颗按钮置灰。
/// 角色要连正向词一起看:名字都没填的空角色带过去等于噪音。
bool canvasHasContent(GenerateState g) =>
    canvasPositive(g).trim().isNotEmpty ||
    canvasNegative(g).trim().isNotEmpty ||
    g.characters.any((c) => c.enabled && c.positive.trim().isNotEmpty);

/// 引用创作页时发给 AI 的正负向:主体和启用的分区拼好的整串,与出图时一致。
String canvasPositive(GenerateState g) =>
    joinSections(g.sections, g.prompt, positive: true);
String canvasNegative(GenerateState g) =>
    joinSections(g.sections, g.negativePrompt, positive: false);

/// 引用创作页时带给 AI 的画面。角色站位从网格 id / 自由坐标换算成归一化 `"x,y"`。
CanvasSnapshot canvasSnapshotOf(GenerateState g) => CanvasSnapshot(
  positive: canvasPositive(g),
  negative: canvasNegative(g),
  characters: [
    for (final c in g.characters)
      if (c.enabled)
        {
          'name': c.name,
          'positive': c.positive,
          'negative': c.negative,
          'position': switch (resolveCharacterCenter(c.position)) {
            final p? => formatFreeformPosition(p.x, p.y),
            null => '',
          },
        },
  ],
);

/// 提议落到创作页的那几件事。不碰对话状态,由控制器记账。
class ProposalService {
  ProposalService(this.ref);

  final Ref ref;

  /// 当前画布上助手会动的那几样。
  PromptSnapshot snapshot() {
    final g = ref.read(generateProvider);
    return PromptSnapshot(
      positive: g.prompt,
      negative: g.negativePrompt,
      sections: List.of(g.sections),
      characters: List.of(g.characters),
      useCoords: g.params.useCoords,
    );
  }

  /// 某张画布眼下那组词。null = 当前画布;画布已经删了返回 null。
  PromptSnapshot? snapshotOf(String? canvasId) {
    final w = ref.read(canvasWorkspaceProvider);
    if (canvasId == null || canvasId == w.activeId) return snapshot();
    final p = w.find(canvasId)?.prompts;
    if (p == null) return null;
    return PromptSnapshot(
      positive: p.prompt,
      negative: p.negativePrompt,
      sections: List.of(p.sections),
      characters: List.of(p.characters),
      useCoords: p.useCoords,
    );
  }

  /// 这条提议**如果拿去生成**会发出什么 —— 不改任何状态。
  /// 尺寸 / 采样 / Vibe / LoRA 沿用创作页,AI 只负责画面内容。
  GenerateState sendState(DrawProposal r) {
    var seq = 0;
    final sent = proposalSendState(
      ref.read(generateProvider),
      r,
      assistantSettingsOf(ref).importTo,
      newId: () => 'preview${seq++}',
    );
    final mods =
        ref.read(genModulesProvider).value ?? const GenModuleSettings();
    return stripHiddenModules(sent, mods);
  }

  /// 把提议整份写进当前画布,返回这次写回的记录(撤销要用的两份快照)。
  ///
  /// 整份替换:AI 没给负向就是空负向,没给角色分区就是没有分区;主提示词分区按设置处置。
  /// Vibe、角色参考、图生图这些 AI 不产出的东西不动。
  AssistantChange importProposal(DrawProposal r) {
    final before = snapshot();
    final gen = ref.read(generateProvider.notifier);
    gen.importPrompts(r.positive, r.negative, assistantSettingsOf(ref).importTo);
    final placed = gen.applyAgentCharacters([
      for (final c in r.characters)
        (
          name: c.name,
          positive: c.positive,
          negative: c.negative,
          position: c.position,
        ),
    ]);
    // 坐标开关跟着 AI 这份走:摆了位就开,没摆就关
    gen.setUseCoords(placed);
    return AssistantChange(
      before: before,
      after: snapshot(),
      canvasId: ref.read(canvasWorkspaceProvider).activeId,
    );
  }

  /// 导入的那张画布与写回时是否还一致。false = 用户之后自己又改过。
  /// 那张画布已经删了就无从比较,按一致算。
  bool inSync(AssistantChange c) => snapshotOf(c.canvasId)?.sameAs(c.after) ?? true;

  /// 把 [AssistantChange.before] 整份恢复到导入的那张画布上;画布删了就什么都不做。
  /// 尺寸 / 采样 / Vibe 一概不碰。
  void revert(AssistantChange c) {
    final target = c.canvasId;
    final w = ref.read(canvasWorkspaceProvider);
    if (target == null || target == w.activeId) {
      final gen = ref.read(generateProvider.notifier);
      gen.setPrompts(positive: c.before.positive, negative: c.before.negative);
      if (c.before.sections != null) gen.replaceSections(c.before.sections!);
      gen.replaceCharacters(c.before.characters);
      gen.setUseCoords(c.before.useCoords);
    } else if (w.find(target) != null) {
      final b = c.before;
      ref
          .read(canvasWorkspaceProvider.notifier)
          .updatePrompts(
            target,
            (p) => p.copyWith(
              prompt: b.positive,
              // 同 setPrompts:词变了,编辑器草稿随之作废
              promptRaw: b.positive == p.prompt ? p.promptRaw : '',
              negativePrompt: b.negative,
              negativePromptRaw: b.negative == p.negativePrompt
                  ? p.negativePromptRaw
                  : '',
              sections: b.sections == null ? null : List.of(b.sections!),
              characters: List.of(b.characters),
              useCoords: b.useCoords,
            ),
          );
    }
  }

  /// 拿 [sent] 出一张图。[inline] = 图显示在对话里、不切去图库,这时返回这一单入库的
  /// 图库条目 id(没出成返回 null)。
  Future<String?> generate(
    GenerateState sent, {
    required bool inline,
    void Function(String jobId)? onJob,
  }) async {
    // 出图前记下库里最新那张,回来一比就知道这一单产出的是哪张
    final before = ref.read(galleryProvider).results.firstOrNull?.id;
    final ok = await ref
        .read(generationProvider.notifier)
        .generate(using: sent, stay: inline, onJob: onJob);
    if (!inline || ok != GenOutcome.ok) return null;
    final now = ref.read(galleryProvider).results.firstOrNull?.id;
    return now == null || now == before ? null : now;
  }
}

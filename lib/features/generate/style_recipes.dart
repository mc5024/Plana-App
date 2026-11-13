/// 画风推荐参数(见 [StyleRecipe])在出图这一侧的事:从当前参数记下、判断和
/// 当前模型对不对得上、套进画布。
///
/// 只动采样参数,不切模型:模型对不上就不弹窗,免得导入一条画风顺手把整张图的
/// 模型换掉。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../inspiration/artist_models.dart';
import '../inspiration/tag_models.dart';
import 'canvas_state.dart';
import 'generate_state.dart';
import 'models.dart';
import 'widgets/common.dart' show confirmDialog, hintSnack;
import '../../l10n/l10n.dart';

/// 采样参数能互通的范围:NAI 5 一套、NAI 4 / 4.5 一套,Anima / Krea 按档位
/// (Turbo 是蒸馏档,CFG 锁 1.0、步数也短,和其它档的配方不能混)。
String samplingSpaceOf(String model) =>
    modalTierKeyOf(model) ?? (isNai5Model(model) ? 'nai5' : 'nai4');

/// 推荐参数记下时的模型(展示名)。
String recipeModelName(StyleRecipe r) => artistModelName(r.model);

/// 这份推荐参数能不能套到 [model] 上。记下时的模型这边不认识(网页端后来才有
/// 的之类)一律算对不上:不知道它那套采样器 / 调度名在这边是什么意思,当成
/// NAI 4 / 4.5 套上去,出图就报错。
bool recipeFits(StyleRecipe r, String model) {
  final from = recipeModelName(r);
  final known = GenProvider.values.any(
    (p) => modelsOf(p, nai5: true).contains(from),
  );
  return known && samplingSpaceOf(from) == samplingSpaceOf(model);
}

/// 从当前参数记下推荐参数:只取当前模型那一套。
StyleRecipe recipeOf(GenParams p) {
  final model = _artistModelIdOf(p.model);
  return switch (providerOfModel(p.model)) {
    GenProvider.nai => StyleRecipe(
      model: model,
      steps: p.naiSteps,
      cfg: p.cfg,
      sampler: p.naiSampler,
      scheduler: p.noiseSchedule,
      cfgRescale: isNai5MediumModel(p.model) ? 0 : p.cfgRescale,
      varietyPlus: p.varietyPlus,
    ),
    GenProvider.anima => StyleRecipe(
      model: model,
      steps: p.animaSteps,
      cfg: p.animaCfg,
      sampler: p.animaSampler,
      scheduler: p.animaScheduler,
    ),
    GenProvider.krea => StyleRecipe(
      model: model,
      steps: p.kreaSteps,
      cfg: p.kreaCfg,
      sampler: p.kreaSampler,
      scheduler: p.kreaScheduler,
    ),
  };
}

/// 把推荐参数写进 [p] 当前模型那一套。先用 [recipeFits] 判过再调。
GenParams withRecipe(GenParams p, StyleRecipe r) =>
    switch (providerOfModel(p.model)) {
      GenProvider.nai => p.copyWith(
        steps: r.steps,
        cfg: r.cfg,
        sampler: r.sampler,
        noiseSchedule: r.scheduler,
        cfgRescale: r.cfgRescale,
        varietyPlus: r.varietyPlus,
      ),
      GenProvider.anima => p.copyWith(
        animaSteps: r.steps,
        animaCfg: r.cfg,
        animaSampler: r.sampler,
        animaScheduler: r.scheduler,
      ),
      GenProvider.krea => p.copyWith(
        kreaSteps: r.steps,
        kreaCfg: r.cfg,
        kreaSampler: r.sampler,
        kreaScheduler: r.scheduler,
      ),
    };

/// 短摘要:「NAI 4.5 Full · 28 步 · CFG 5」。
String recipeBrief(StyleRecipe r) =>
    '${modelName(recipeModelName(r))} · ${l10nNow.stepsN(r.steps)} · '
    'CFG ${_num(r.cfg)}';

/// 采样那几项:「28 步 · CFG 5 · Euler Ancestral · karras」,NAI 再带上
/// 不为 0 的 Rescale 和开着的 Variety+。
String recipeDetail(StyleRecipe r) {
  final model = recipeModelName(r);
  final nai = providerOfModel(model) == GenProvider.nai;
  return [
    l10nNow.stepsN(r.steps),
    'CFG ${_num(r.cfg)}',
    _samplerLabel(model, r.sampler),
    _schedulerLabel(model, r.scheduler),
    if (nai && r.cfgRescale != 0) 'Rescale ${_num(r.cfgRescale)}',
    if (nai && r.varietyPlus) 'Variety+',
  ].join(' · ');
}

/// 推荐参数排成参数表:模型占一整行,其余两列、一格一项(上面小字是项名,下面是
/// 值)。弹窗和画风编辑页共用。V5 的噪声调度不生效(高级设置里也藏了),这里不列。
class StyleRecipeTable extends StatelessWidget {
  const StyleRecipeTable(this.recipe, {super.key});

  final StyleRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final r = recipe;
    final model = recipeModelName(r);
    final nai = providerOfModel(model) == GenProvider.nai;
    final cells = <(String, String)>[
      (context.l10n.steps, '${r.steps}'),
      ('CFG', _num(r.cfg)),
      (context.l10n.sampler, _samplerLabel(model, r.sampler)),
      if (!isNai5Model(model))
        (
          nai ? context.l10n.noiseSchedule : context.l10n.scheduler,
          _schedulerLabel(model, r.scheduler),
        ),
      if (nai) ('CFG Rescale', _num(r.cfgRescale)),
      if (nai) ('Variety+', r.varietyPlus ? context.l10n.on : context.l10n.off),
    ];
    Widget cell((String, String) c) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.$1,
          style: context.texts.labelSmall!.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 2),
        Text(
          c.$2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.bodyMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cell((context.l10n.model, modelName(model))),
        const SizedBox(height: 10),
        for (var i = 0; i < cells.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell(cells[i])),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < cells.length
                    ? cell(cells[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 采样器 / 调度器的显示名:Anima、Krea 存的是 id,对照表里取名字;NAI 存的
/// 本来就是显示名。
String _samplerLabel(String model, String id) =>
    _optionLabel(switch (providerOfModel(model)) {
      GenProvider.anima => animaSamplers,
      GenProvider.krea => kreaSamplers,
      GenProvider.nai => const [],
    }, id);

String _schedulerLabel(String model, String id) =>
    _optionLabel(switch (providerOfModel(model)) {
      GenProvider.anima => animaSchedulers,
      GenProvider.krea => kreaSchedulers,
      GenProvider.nai => const [],
    }, id);

String _optionLabel(List<AnimaOption> options, String id) {
  for (final o in options) {
    if (o.id == id) return o.label;
  }
  return id;
}

/// 这批画风里(按选择顺序)第一条带推荐参数、且对得上 [model] 的。
TagEntry? recipeToOffer(Iterable<TagEntry> entries, String model) {
  for (final e in entries) {
    if (e.recipe case final r? when recipeFits(r, model)) return e;
  }
  return null;
}

/// 导入画风之后调:有对得上当前模型的推荐参数,就弹窗问套不套(点「套用」
/// 才写进 [canvasId] 那张画布,不切模型);没有就什么都不做。
Future<void> offerStyleRecipe(
  BuildContext context,
  WidgetRef ref,
  Iterable<TagEntry> entries, {
  required String canvasId,
}) async {
  final entry = recipeToOffer(entries, ref.read(generateProvider).params.model);
  if (entry == null) return;
  final canvases = ref.read(canvasWorkspaceProvider.notifier);
  final ok = await confirmDialog(
    context,
    title: context.l10n.applyRecipeTitle(entry.name),
    body: StyleRecipeTable(entry.recipe!),
    confirmLabel: context.l10n.apply,
    cancelLabel: context.l10n.dontApply,
    danger: false,
  );
  if (!ok || !context.mounted) return;
  _apply(context, canvases, canvasId, entry);
}

/// 套用并给撤销:只换那张画布的采样参数,撤销放回原样。
void _apply(
  BuildContext context,
  CanvasWorkspaceNotifier canvases,
  String canvasId,
  TagEntry entry,
) {
  final r = entry.recipe!;
  final before = canvases.updateSampling(
    canvasId,
    (p) => recipeFits(r, p.model) ? withRecipe(p, r) : p,
  );
  if (before == null || !context.mounted) return;
  hintSnack(
    context,
    context.l10n.recipeApplied(entry.name),
    icon: Icons.tune,
    actionLabel: context.l10n.undo,
    onAction: () =>
        canvases.updatePrompts(canvasId, (p) => p.copyWith(sampling: before)),
  );
}

String _artistModelIdOf(String displayModel) {
  for (final m in kArtistModels) {
    if (m.name == displayModel) return m.id;
  }
  return displayModel;
}

/// 5.0 → 5,4.50 → 4.5。
String _num(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

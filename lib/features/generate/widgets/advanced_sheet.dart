import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../generate_state.dart';
import '../models.dart';
import '../preset_manage_page.dart';
import '../prompt_presets.dart';
import 'common.dart';
import '../../../core/util/haptics.dart';

/// 高级设置 Sheet:分区滚动,底部「恢复默认 / 确认」固定。
/// Sheet 内编辑草稿,确认才写回全局状态。
Future<void> showAdvancedSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        const FractionallySizedBox(heightFactor: .86, child: _AdvancedSheet()),
  );
}

class _AdvancedSheet extends ConsumerStatefulWidget {
  const _AdvancedSheet();

  @override
  ConsumerState<_AdvancedSheet> createState() => _AdvancedSheetState();
}

class _AdvancedSheetState extends ConsumerState<_AdvancedSheet> {
  late GenParams draft;
  late final TextEditingController seedCtrl;

  /// 每次随机。**显式状态**,不再从输入框空不空反推 —— 反推的话「全选删掉
  /// 想重打一个」会在删空那一刻把输入框锁死,手打到一半被夺走。
  late bool randomSeed;

  /// 上一颗钉死的种子:开随机时输入框清空,关掉原样还回来,不用重打。
  String _lastFixed = '';

  @override
  void initState() {
    super.initState();
    draft = ref.read(generateProvider).params;
    seedCtrl = TextEditingController(text: draft.seed);
    randomSeed = draft.seed.trim().isEmpty;
    _lastFixed = draft.seed.trim();
  }

  @override
  void dispose() {
    seedCtrl.dispose();
    super.dispose();
  }

  void _set(GenParams next) => setState(() => draft = next);

  /// 开随机:种子留空(下发时才掷),输入框连内容一起收走。
  /// 关随机:把上一颗还回来;没有就现掷一颗(范围与出图时一致),
  /// 免得「固定」着一个空框、实际还是每次随机。
  void _setRandomSeed(bool v) {
    Haptics.selection();
    if (v) {
      _lastFixed = seedCtrl.text.trim();
      seedCtrl.clear();
    } else {
      seedCtrl.text = _lastFixed.isNotEmpty
          ? _lastFixed
          : '${Random().nextInt(4294967296)}';
    }
    setState(() {
      randomSeed = v;
      draft = draft.copyWith(seed: seedCtrl.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isAnima = isAnimaModel(draft.model);
    final isKrea = isKreaModel(draft.model);
    // V5 的 noise_schedule 请求前硬写回 karras;Medium 档步数、采样器固定,
    // CFG Rescale 不发。这几项置灰显示实际生效值(见 [LockedParam])。
    final isV5 = isNai5Model(draft.model);
    final isMedium = isNai5MediumModel(draft.model);
    final name = modelName(draft.model);
    final noiseSchedule = isV5 ? 'karras' : draft.noiseSchedule;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '高级设置',
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              // 预设选择即时生效(全局偏好,不随「恢复默认/确认」走草稿)。
              _SectionLabel('提示词预设'),
              const SizedBox(height: 10),
              _PresetRow(model: draft.model),
              const SizedBox(height: 4),
              Text(
                '生成时自动拼进正/负提示词,不占用输入框。V5 与 4.5 各有一套档。',
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
              const SizedBox(height: 18),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: .5),
                height: 1,
              ),
              const SizedBox(height: 14),
              _SectionLabel('采样'),
              const SizedBox(height: 10),
              if (isAnima) ...[
                // Anima:与 NAI 两套独立采样参数,范围对齐 web animaOptions
                ParamSlider(
                  label: '步数 Steps',
                  help: Help.animaSteps,
                  value: draft.animaSteps.toDouble(),
                  min: animaStepsRange.min.toDouble(),
                  max: animaStepsRange.max.toDouble(),
                  divisions: animaStepsRange.max - animaStepsRange.min,
                  valueText: '${draft.animaSteps}',
                  onChanged: (v) => _set(draft.copyWith(animaSteps: v.round())),
                ),
                const SizedBox(height: 8),
                ParamSlider(
                  label: '提示词引导 CFG',
                  help: Help.animaCfg,
                  value: draft.animaCfg,
                  min: animaCfgRange.min,
                  max: animaCfgRange.max,
                  divisions: ((animaCfgRange.max - animaCfgRange.min) * 2)
                      .round(), // step 0.5(对齐 web)
                  valueText: draft.animaCfg.toStringAsFixed(1),
                  onChanged: (v) => _set(draft.copyWith(animaCfg: v)),
                ),
                const SizedBox(height: 12),
                HelpLabel(
                  text: '采样器 Sampler',
                  help: Help.animaSampler,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 4.4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final s in animaSamplers)
                      _SelectTile(
                        label: s.label,
                        selected: draft.animaSampler == s.id,
                        onTap: () => _set(draft.copyWith(animaSampler: s.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                HelpLabel(
                  text: '调度器 Scheduler',
                  help: Help.animaScheduler,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 3.0,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final n in animaSchedulers)
                      _SelectTile(
                        label: n.label,
                        selected: draft.animaScheduler == n.id,
                        onTap: () => _set(draft.copyWith(animaScheduler: n.id)),
                      ),
                  ],
                ),
              ] else if (isKrea) ...[
                // Krea:**刻意只有这两项**。服务端 _patch_krea_payload 只认
                // steps/cfg/batch/loras,采样器固定 er_sde + simple —— 放出
                // 采样器/调度器选择框等于骗用户,所以连字段都不存。
                ParamSlider(
                  label: '步数 Steps',
                  help: Help.kreaSteps,
                  value: draft.kreaSteps.toDouble(),
                  min: kreaStepsRange.min.toDouble(),
                  max: kreaStepsRange.max.toDouble(),
                  divisions: kreaStepsRange.max - kreaStepsRange.min,
                  valueText: '${draft.kreaSteps}',
                  onChanged: (v) => _set(draft.copyWith(kreaSteps: v.round())),
                ),
                const SizedBox(height: 8),
                ParamSlider(
                  label: '提示词引导 CFG',
                  help: Help.kreaCfg,
                  value: draft.kreaCfg,
                  min: kreaCfgRange.min,
                  max: kreaCfgRange.max,
                  divisions: ((kreaCfgRange.max - kreaCfgRange.min) * 2)
                      .round(), // step 0.5(对齐 web)
                  valueText: draft.kreaCfg.toStringAsFixed(1),
                  onChanged: (v) => _set(draft.copyWith(kreaCfg: v)),
                ),
                // 只看 CFG 不看档位:web 那条额外判了 `!kreaNegativeWorks(tier)`,
                // 于是在 Raw 档手动把 CFG 拖到 1 时不提示 —— 可负向词照样是死的。
                // 这里按实际取值判,Turbo 默认档和手动拖到 1 的 Raw 都会提示。
                if (draft.kreaCfg <= 1.0) ...[
                  const SizedBox(height: 8),
                  const InfoNote(
                    'CFG=1,负面提示词不参与引导(没有无条件分支可对比)。'
                    '想让它生效,把 CFG 调过 1。',
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
                const SizedBox(height: 12),
                HelpLabel(
                  text: '采样器 Sampler',
                  help: Help.kreaSampler,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 4.4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final s in kreaSamplers)
                      _SelectTile(
                        label: s.label,
                        selected: draft.kreaSampler == s.id,
                        onTap: () => _set(draft.copyWith(kreaSampler: s.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                HelpLabel(
                  text: '调度器 Scheduler',
                  help: Help.kreaScheduler,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 3.0,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final n in kreaSchedulers)
                      _SelectTile(
                        label: n.label,
                        selected: draft.kreaScheduler == n.id,
                        onTap: () => _set(draft.copyWith(kreaScheduler: n.id)),
                      ),
                  ],
                ),
                // 选中了才提示:它是唯一实测会坏事的一项,不选就不用占版面。
                if (kreaSchedulerRisky(draft.kreaScheduler)) ...[
                  const SizedBox(height: 10),
                  const InfoNote(
                    'Karras 在 Krea 2 上实测效果不好,建议换回 Simple。',
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              ] else ...[
                LockedParam(
                  hint: isMedium ? '$name 步数固定为 $kNai5MediumSteps' : null,
                  child: ParamSlider(
                    label: '步数 Steps',
                    help: Help.steps,
                    value: draft.naiSteps.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    valueText: '${draft.naiSteps}',
                    trailing: AnimatedOpacity(
                      duration: Motion.fast,
                      opacity: draft.naiSteps <= 28 ? 1 : 0,
                      child: const CountBadge('≤28 免费'),
                    ),
                    onChanged: (v) => _set(draft.copyWith(steps: v.round())),
                  ),
                ),
                const SizedBox(height: 8),
                ParamSlider(
                  label: '提示词引导 CFG',
                  help: Help.cfg,
                  value: draft.cfg,
                  min: 0,
                  max: 25,
                  divisions: 250, // step 0.1(对齐 web)
                  valueText: draft.cfg.toStringAsFixed(1),
                  // Variety+ 借住在 CFG 这行,自己那份说明只能挂个独立问号
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TextToggle(
                        label: 'Variety+',
                        selected: draft.varietyPlus,
                        onTap: () {
                          Haptics.selection();
                          _set(draft.copyWith(varietyPlus: !draft.varietyPlus));
                        },
                      ),
                      const HelpDot(Help.varietyPlus, size: 30, iconSize: 17),
                    ],
                  ),
                  onChanged: (v) => _set(draft.copyWith(cfg: v)),
                ),
                const SizedBox(height: 12),
                LockedParam(
                  hint: isMedium ? '$name 采样器固定为 $kNai5MediumSampler' : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HelpLabel(
                        text: '采样器 Sampler',
                        help: Help.sampler,
                        style: context.texts.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 7,
                        crossAxisSpacing: 7,
                        childAspectRatio: 4.4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final s in samplers)
                            _SelectTile(
                              label: s,
                              selected: draft.naiSampler == s,
                              onTap: () => _set(draft.copyWith(sampler: s)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                LockedParam(
                  hint: isV5 ? '$name 噪声调度固定为 karras' : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HelpLabel(
                        text: '噪声调度 Noise Schedule',
                        help: Help.noiseSchedule,
                        style: context.texts.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final n in noiseSchedules) ...[
                            Expanded(
                              child: _SelectTile(
                                label: n,
                                selected: noiseSchedule == n,
                                height: 34,
                                onTap: () =>
                                    _set(draft.copyWith(noiseSchedule: n)),
                              ),
                            ),
                            if (n != noiseSchedules.last)
                              const SizedBox(width: 7),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: .5),
                height: 1,
              ),
              const SizedBox(height: 14),
              _SectionLabel('修正'),
              const SizedBox(height: 10),
              // 「随机」是开关不是动作:开着 = 每次随机,输入框一并锁死(灰掉、
              // 点不进去),要手填种子先关掉它。骰子原先挂在输入框的 suffixIcon
              // 上,而 isDense 的框只有 ~40dp 高、IconButton 要 48dp:越界那截
              // 落在父框外不参与命中测试,蹭到上下边就「点了没反应」。
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: seedCtrl,
                      enabled: !randomSeed,
                      keyboardType: TextInputType.number,
                      style: mono(context, size: 13),
                      decoration: InputDecoration(
                        labelText: '种子 Seed',
                        hintText: '每次随机',
                        // 标签常驻浮起,框里才腾得出「每次随机」这行灰字 ——
                        // 否则锁死状态下框里空空一片,只剩个灰标签
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => _set(draft.copyWith(seed: v)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 与输入框等高的裸图标键:亮=每次随机,灰空心=手填。
                  // 不再塞进 suffixIcon,48dp 点击区完整落在框外自己的地盘上。
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: randomSeed ? '每次随机 · 点击手填种子' : '手填种子 · 点击改为每次随机',
                      onPressed: () => _setRandomSeed(!randomSeed),
                      // 图标字体只有一档笔画,选中态靠外面这圈主色底托 + 描边撑。
                      // 方角:挨着输入框,圆角对齐它的 12
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: randomSeed
                            ? scheme.primary.withValues(alpha: .12)
                            : Colors.transparent,
                        side: randomSeed
                            ? BorderSide(
                                color: scheme.primary.withValues(alpha: .45),
                              )
                            : BorderSide.none,
                      ),
                      icon: Icon(
                        randomSeed ? Icons.casino : Icons.casino_outlined,
                        size: 22,
                        color: randomSeed
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // 输入框的浮动标签挂不住点击区,说明单独给个问号
                  const SizedBox(width: 2),
                  const HelpDot(Help.seed),
                ],
              ),
              // CFG Rescale 是 NAI 独有的;两个 Modal 渠道都没有这个参数
              if (!isAnima && !isKrea) ...[
                const SizedBox(height: 14),
                LockedParam(
                  hint: isMedium ? '$name 不支持「CFG Rescale」' : null,
                  child: ParamSlider(
                    label: 'CFG Rescale',
                    help: Help.cfgRescale,
                    value: isMedium ? 0 : draft.cfgRescale,
                    divisions: 100, // step 0.01(对齐 web)
                    onChanged: (v) => _set(draft.copyWith(cfgRescale: v)),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 底部固定按钮
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .5),
                width: .5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    var next = const GenParams().copyWith(
                      model: draft.model,
                      width: draft.width,
                      height: draft.height,
                    );
                    if (isAnima) {
                      // anima 默认 = 当前档位的推荐采样参数
                      final d = animaTierDefaults(animaTierOf(draft.model));
                      next = next.copyWith(
                        animaSteps: d.steps,
                        animaCfg: d.cfg,
                        animaSampler: d.sampler,
                        animaScheduler: d.scheduler,
                      );
                    } else if (isKrea) {
                      // krea 同理:回到当前档位的官方配方(不切档)
                      final d = kreaTierDefaults(kreaTierOf(draft.model));
                      next = next.copyWith(
                        kreaSteps: d.steps,
                        kreaCfg: d.cfg,
                        kreaSampler: d.sampler,
                        kreaScheduler: d.scheduler,
                      );
                    }
                    _set(next);
                    seedCtrl.clear();
                    randomSeed = true; // _set 已经 setState,这里跟着回默认
                    _lastFixed = '';
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    ref
                        .read(generateProvider.notifier)
                        .applyParams(
                          draft.copyWith(
                            seed: randomSeed ? '' : seedCtrl.text.trim(),
                          ),
                        );
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    '确认',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.texts.labelSmall!.copyWith(
        color: context.scheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 36,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return AnimatedContainer(
      duration: Motion.fast,
      height: height,
      decoration: BoxDecoration(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 文字开关胶囊:关着是细边圈住一行灰字;开了换成与采样器选中格同一套
/// (secondaryContainer 底 + 主色描边),字前多个对勾。
class _TextToggle extends StatelessWidget {
  const _TextToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: Motion.fast,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: AnimatedSize(
              duration: Motion.fast,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check, size: 14, color: fg),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 预设切换行:下拉单选即时生效(自定义多了 chip 行放不下,用户定稿下拉)
/// + 尾部「管理」进独立管理页。
class _PresetRow extends ConsumerWidget {
  const _PresetRow({required this.model});

  /// 当前(草稿里的)模型 —— 内置档按系列过滤要用。
  final String model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final s = ref.watch(promptPresetsProvider).value;
    if (s == null) return const SizedBox(height: 44);
    // V5 与 4.5 的内置档是两套文本,各只在自己那边出现;自定义档两边都留。
    final visible = promptPresetsForModel(s.presets, model);
    // 存的那个档在当前模型下可能根本不在列表里(切了模型、档没跟着换)。
    // 这里只是**显示**成同强度的那一档 —— 真正落地由 _applyPreset 再算一次,
    // 不在这儿写回:草稿里的模型用户还可能取消。
    final activeId = remapPromptPresetId(
      ref.watch(activePromptPresetIdProvider),
      s.presets,
      model,
    );
    return Row(
      children: [
        Expanded(
          // DropdownButton 受控 value(FormField 版的 value 已弃用且替代品
          // 不响应外部变化):管理页改名/删除回落后,返回时显示自动跟随。
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
            ),
            child: DropdownButton<String>(
              value: activeId,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              style: context.texts.bodyMedium!.copyWith(
                color: scheme.onSurface,
              ),
              items: [
                for (final p in visible)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                Haptics.selection();
                ref.read(promptPresetsProvider.notifier).setActive(id);
              },
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: '管理预设',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(
            context,
          ).push(sharedAxisRoute(const PromptPresetManagePage())),
          icon: Icon(Icons.edit_note, size: 22, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

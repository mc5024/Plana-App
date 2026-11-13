import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// 参数说明 —— 文案取自 web 桌面端 `LeftSidebar.tsx` 的 `<HelpTip>`,**连行前缀
/// 一起原样保留**:web 改文案时对着 diff 覆盖即可,不用在这边重新排版。
///
/// 行前缀约定(与 web 一致):
///   `·`  → 要点条目
///   `💡` → 使用提示(单独一块高亮区展示)
///   其余 → 普通说明行
class ParamHelp {
  const ParamHelp(this._title, this._body) : _id = null;

  /// 文案在 ARB 里,按界面语言取(见 [_helpTitle] / [_helpBody])。
  const ParamHelp.l10n(String id) : _id = id, _title = '', _body = '';

  final String? _id;
  final String _title;
  final String _body;

  String get title => switch (_id) {
    final id? => _helpTitle(l10nNow, id),
    null => _title,
  };

  String get body => switch (_id) {
    final id? => _helpBody(l10nNow, id),
    null => _body,
  };

  /// 说明区:`(是否列表项, 文本)`。
  List<(bool, String)> get points => [
    for (final l in _lines)
      if (!_isTip(l))
        l.startsWith('·') ? (true, l.substring(1).trim()) : (false, l),
  ];

  /// 使用提示区(已剥掉 💡 前缀)。
  List<String> get tips => [
    for (final l in _lines)
      if (_isTip(l)) l.replaceFirst(_tipHead, ''),
  ];

  List<String> get _lines => [
    for (final l in body.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];

  // 💡 后可以没有空格(web 的 Noise Schedule 就是这么写的),用 \s* 兜住。
  static final _tipHead = RegExp(r'^(💡|⚠️|⚠)\s*');

  static bool _isTip(String l) => _tipHead.hasMatch(l);
}

/// 全部参数说明的单一出处。
///
/// web 角色参考的两条提示里有「点击数字框可输入负值」——
/// app 的强度/保真度下限就是 0,照抄会教出一个做不到的操作,已删。
abstract final class Help {
  // ---- 画布 ----
  // app 独有的功能,web 没有对应的 HelpTip。

  static const canvas = ParamHelp.l10n('canvas');

  // ---- 分辨率 ----
  // web 没有对应的 HelpTip,这条是 app 自写的。

  static const resolution = ParamHelp.l10n('resolution');

  // ---- 图生图 ----

  static const img2imgStrength = ParamHelp.l10n('img2imgStrength');

  static const img2imgNoise = ParamHelp.l10n('img2imgNoise');

  // ---- Vibe ----

  static const vibeStrength = ParamHelp.l10n('vibeStrength');

  static const normalizeVibe = ParamHelp.l10n('normalizeVibe');

  static const infoExtracted = ParamHelp.l10n('infoExtracted');

  // ---- 角色参考 ----

  static const charRefStrength = ParamHelp.l10n('charRefStrength');

  static const fidelity = ParamHelp.l10n('fidelity');

  // ---- 采样(anima)----
  // 与 NAI 那套(steps / cfg / sampler / noiseSchedule)是两份独立文案:
  // 取值区间、默认值、各选项的性格全都不同,共用一份只会两头都不准。

  static const animaSteps = ParamHelp(
    '采样步数 (Steps)',
    '推荐区间随模型档切换:\n'
        '· Turbo 档: 8-12,默认 12。这一档往上加不会更好看\n'
        '· Aesthetic / Base 档: 30-50,默认 36。想要更精细可以往上调\n'
        '💡 切换模型档位会自动套用该档的推荐参数',
  );

  static const animaCfg = ParamHelp(
    '提示词引导强度 (CFG)',
    '控制画面对提示词的贴合程度:\n'
        '· Turbo 档: 固定 1.0,调高会崩。这一档「排除内容」不生效\n'
        '· Base 档: 4-5,默认 4.5\n'
        '· Aesthetic 档: 也吃 4-5,调到 3 左右往往更好看\n'
        '💡 调高更听话但容易生硬,调低更自由但可能跑题',
  );

  static const animaSampler = ParamHelp(
    '采样算法 (Sampler)',
    '官方点名的四个，各有性格:\n'
        '· ER SDE — 中性、平涂、线条锐利(非 Turbo 档默认)\n'
        '· Euler Ancestral — 更柔、线条更细，CFG 推高也不易糊\n'
        '· DPM++ 2M SDE — 接近 ER SDE，但变化更多\n'
        '· Euler — 基础款，比 ER SDE 稍有发挥(Turbo 档默认)\n'
        '· UniPC / UniPC BH2 — 主打少步数，还没试过，效果自己看\n'
        '💡 Turbo 档 Euler + Simple 最稳',
  );

  static const animaScheduler = ParamHelp(
    '噪声调度 (Scheduler)',
    '决定每步的噪声衰减节奏。\n'
        '· simple — Turbo 默认搭档\n'
        '· karras — 细节强化,配 DPM++ 系\n'
        '· normal / sgm_uniform / beta — 各有质感\n'
        '💡 改了 Sampler 后再相应调 Scheduler',
  );

  // ---- 采样(krea)----

  static const kreaSteps = ParamHelp(
    '采样步数 (Steps)',
    '推荐区间随模型档切换:\n'
        '· Turbo 档: 8 步,往上加不会更好看\n'
        '· Raw 档: 默认 36,最高可到 52(更精细,也更慢)\n'
        '💡 切换模型档位会自动套用该档的推荐参数\n'
        '💡 Raw 档比 Turbo 慢很多,步数越高越明显——'
        '建议先用 Turbo 试构图,满意了再换 Raw 出定稿',
  );

  static const kreaCfg = ParamHelp(
    '提示词引导强度 (CFG)',
    '控制画面对提示词的贴合程度:\n'
        '· Turbo 档: 固定 1.0,调高会崩。这一档「排除内容」不生效\n'
        '· Raw 档: 默认 3.5,可在 3-5 之间微调\n'
        '💡 调高更听话但容易生硬,调低更自由但可能跑题',
  );

  static const kreaSampler = ParamHelp(
    '采样算法 (Sampler)',
    '官方 Krea 2 配方是 ER SDE，默认也是它。\n'
        '前六个都实测过，都能出正常图，区别在质感不在成败，可以放心试:\n'
        '· Euler — 基础款\n'
        '· Euler Ancestral — 更柔、随机性更高\n'
        '· DPM++ 系 — 变化更多\n'
        '· UniPC / UniPC BH2 — 主打少步数，但这两个还没试过，效果自己看\n'
        '💡 真正要小心的是 Scheduler，别选 Karras',
  );

  static const kreaScheduler = ParamHelp(
    '噪声调度 (Scheduler)',
    '决定每步的噪声衰减节奏。\n'
        '· Simple — 官方配方搭档，默认\n'
        '· Normal / SGM Uniform / Beta — 都正常，质感略有不同\n'
        '· Karras — ⚠ 实测效果不好，两档都是，不建议用',
  );

  // ---- 风格参考(krea) ----

  static const kreaStyleRefStrength = ParamHelp(
    '参考强度 (Strength)',
    '参考图画风对结果的影响力,所有参考图共用此值。\n'
        '· 1.0 为官方默认，画风迁移最准确\n'
        '· 值越低 → 参考图仅作弱引导，更多听从提示词\n'
        '· 值越高 → 参考图的构图与物件也可能被一并带入\n'
        '💡 提示词中再描述画风会与参考图冲突，通常留空更准\n'
        '⚠ 只在 Turbo 档正常:官方这个参考 LoRA 是在 Turbo 上训的,'
        'Raw 是后训练之前的基础检查点,权重分布对不上',
  );

  // ---- LoRA(anima / krea) ----

  static const loraWeight = ParamHelp(
    'LoRA 权重 (Weight)',
    '控制该 LoRA 对画面的影响强度。\n'
        '· 值越高 → 该 LoRA 的角色/画风特征越强\n'
        '· 过高 → 易过拟合、畸变、盖过 prompt\n'
        '💡 常用起点:角色 0.8 / 画风 0.6 / 概念 0.7\n'
        '💡 单条上限 2(与出图后端一致)\n'
        '💡 挂多条时每条都要往下调:LoRA 的效果是直接相加的,'
        '不会因为挂得多就自动摊薄',
  );

  static const loraClip = ParamHelp(
    'CLIP 强度',
    '控制该 LoRA 对整体「提示词理解」的影响强度\n'
        'LoRA 的触发词机制会同时影响模型整体的提示词理解\n'
        '· 值越高 → 该 LoRA 越能左右提示词的含义\n'
        '· 值越低 → 提示词回归原本含义,画面特征仍由权重控制,'
        '但可能无法稳定触发 LoRA 效果\n'
        '💡 单 LoRA 时默认跟随权重\n'
        '💡 有些 LoRA 没训文本编码器,调它不会有任何变化',
  );

  // ---- 重绘放大(anima) ----

  static const hiresScale = ParamHelp(
    '放大倍率 (Scale)',
    '二段采样的目标尺寸倍数。\n'
        '· 1.5× → 832×1216 变 1248×1824\n'
        '· 2.0× → 变 1664×2432\n'
        '💡 越大越慢，推荐 1.5×',
  );

  static const hiresUpscaler = ParamHelp(
    '放大方式 (Upscaler)',
    '重绘前把小图放大到目标尺寸的方式。\n'
        '· 先超分后重绘：超分模型放大再重绘，底子更锐利（推荐）\n'
        '· 直接重绘：lanczos 插值放大后重绘，略快几秒',
  );

  static const hiresModel = ParamHelp(
    '超分模型',
    '先超分阶段用的放大模型（差异会被重绘部分稀释，重绘强度越低差异越明显）。\n'
        '· AnimeSharp：二次元特化，线条干净（推荐）\n'
        '· UltraSharp：通用锐利型，纹理偏写实\n'
        '· Anime 6B：官方 anime，涂抹柔和风',
  );

  static const hiresDenoise = ParamHelp(
    '重绘强度 (Denoise)',
    '重绘对画面的改动强度。\n'
        '· 低 → 忠实原构图，细节补得少\n'
        '· 高 → 细节更多，但可能改变构图\n'
        '💡 工作区间 0.35~0.6，默认 0.5',
  );

  static const hiresSteps = ParamHelp(
    '二段步数 (Hires Steps)',
    '二段采样的步数。\n'
        '拖到最左 = 跟随主采样步数。\n'
        '实际有效步数 ≈ 步数 × 重绘幅度',
  );

  // ---- 采样 ----

  static const steps = ParamHelp.l10n('steps');

  static const cfg = ParamHelp.l10n('cfg');

  static const varietyPlus = ParamHelp.l10n('varietyPlus');

  static const sampler = ParamHelp.l10n('sampler');

  static const noiseSchedule = ParamHelp.l10n('noiseSchedule');

  // ---- 修正 ----

  static const seed = ParamHelp.l10n('seed');

  static const cfgRescale = ParamHelp.l10n('cfgRescale');
}

/// 弹出参数说明。桌面端靠 hover 浮气泡,手机上没有 hover,也没地方稳稳浮一张
/// 卡片(参数本身就在 sheet 里),所以走底部弹层:拇指可达、挤不出屏幕。
Future<void> showParamHelp(BuildContext context, ParamHelp help) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // 采样算法那条有 6 条要点,默认高度装不下
    useSafeArea: true,
    builder: (_) => _ParamHelpSheet(help),
  );
}

class _ParamHelpSheet extends StatelessWidget {
  const _ParamHelpSheet(this.help);

  final ParamHelp help;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;
    final tips = help.tips;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            help.title,
            style: texts.titleSmall!.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: scheme.primary.withValues(alpha: .25), height: 1),
          const SizedBox(height: 12),
          for (final (bullet, text) in help.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: bullet
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: scheme.outline,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(child: _body(context, text)),
                      ],
                    )
                  : _body(context, text),
            ),
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .09),
                border: Border(
                  left: BorderSide(
                    color: scheme.primary.withValues(alpha: .5),
                    width: 3,
                  ),
                ),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 使用提示',
                    style: texts.labelMedium!.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final t in tips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .55),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(child: _body(context, t)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(BuildContext context, String text) => Text(
    text,
    style: context.texts.bodyMedium!.copyWith(
      color: context.scheme.onSurfaceVariant,
      height: 1.45,
    ),
  );
}

/// 参数标签 + 尾随问号。**整条标签带都是靶子**,问号只是「这里有说明」的视觉
/// 提示 —— 照搬 web 那个 12px 图标做点击区,手机上基本按不中。
class HelpLabel extends StatelessWidget {
  const HelpLabel({
    super.key,
    required this.text,
    required this.help,
    this.style,
    this.iconSize = 16,
  });

  final String text;
  final ParamHelp help;
  final TextStyle? style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showParamHelp(context, help),
      child: Padding(
        // 只加 4:标签行本身才 18dp 高,配上整行宽度已经够按了,
        // 再撑就把卡片里那几对滑杆的节奏拉散。
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Flexible(
              child: Text(
                text,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.help_outline,
              size: iconSize,
              color: context.scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// 光秃秃的问号按钮 —— 给挂不上 [HelpLabel] 的控件用(输入框、chip)。
class HelpDot extends StatelessWidget {
  const HelpDot(this.help, {super.key, this.size = 34, this.iconSize = 19});

  final ParamHelp help;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () => showParamHelp(context, help),
      radius: size / 2,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.help_outline,
          size: iconSize,
          color: context.scheme.outline,
        ),
      ),
    );
  }
}

String _helpTitle(AppLocalizations l, String id) => switch (id) {
  'canvas' => l.helpCanvasTitle,
  'resolution' => l.helpResolutionTitle,
  'img2imgStrength' => l.helpImg2imgStrengthTitle,
  'img2imgNoise' => l.helpImg2imgNoiseTitle,
  'vibeStrength' => l.helpVibeStrengthTitle,
  'normalizeVibe' => l.helpNormalizeVibeTitle,
  'infoExtracted' => l.helpInfoExtractedTitle,
  'charRefStrength' => l.helpCharRefStrengthTitle,
  'fidelity' => l.helpFidelityTitle,
  'steps' => l.helpStepsTitle,
  'cfg' => l.helpCfgTitle,
  'varietyPlus' => l.helpVarietyPlusTitle,
  'sampler' => l.helpSamplerTitle,
  'noiseSchedule' => l.helpNoiseScheduleTitle,
  'seed' => l.helpSeedTitle,
  'cfgRescale' => l.helpCfgRescaleTitle,
  _ => id,
};

String _helpBody(AppLocalizations l, String id) => switch (id) {
  'canvas' => l.helpCanvasBody,
  'resolution' => l.helpResolutionBody,
  'img2imgStrength' => l.helpImg2imgStrengthBody,
  'img2imgNoise' => l.helpImg2imgNoiseBody,
  'vibeStrength' => l.helpVibeStrengthBody,
  'normalizeVibe' => l.helpNormalizeVibeBody,
  'infoExtracted' => l.helpInfoExtractedBody,
  'charRefStrength' => l.helpCharRefStrengthBody,
  'fidelity' => l.helpFidelityBody,
  'steps' => l.helpStepsBody,
  'cfg' => l.helpCfgBody,
  'varietyPlus' => l.helpVarietyPlusBody,
  'sampler' => l.helpSamplerBody,
  'noiseSchedule' => l.helpNoiseScheduleBody,
  'seed' => l.helpSeedBody,
  'cfgRescale' => l.helpCfgRescaleBody,
  _ => '',
};

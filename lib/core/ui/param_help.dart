import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 参数说明 —— 文案取自 web 桌面端 `LeftSidebar.tsx` 的 `<HelpTip>`,**连行前缀
/// 一起原样保留**:web 改文案时对着 diff 覆盖即可,不用在这边重新排版。
///
/// 行前缀约定(与 web 一致):
///   `·`  → 要点条目
///   `💡` → 使用提示(单独一块高亮区展示)
///   其余 → 普通说明行
class ParamHelp {
  const ParamHelp(this.title, this.body);

  final String title;
  final String body;

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

  static const canvas = ParamHelp(
    '画布',
    '每张画布各存一套提示词和出图参数，随时切换。\n'
        '· 只有张数和循环档位是所有画布共用的\n'
        '💡 切换画布不影响进行中的出图\n'
        '💡「历史」保留最近 50 次出图，可恢复',
  );

  // ---- 分辨率 ----
  // web 没有对应的 HelpTip,这条是 app 自写的。

  static const resolution = ParamHelp(
    '分辨率',
    '按总像素(宽 × 高)分档:\n'
        '· 免费 → ≤ 1024×1024,即绿线以内;需 Opus 订阅、步数 ≤28\n'
        '· 消耗点数 → 超出绿线,尺寸越大越贵\n'
        '· 超出上限 → 超过 1024×3072(红线),无法生成',
  );

  // ---- 图生图 ----

  static const img2imgStrength = ParamHelp(
    '图生图强度 (Strength)',
    '控制原图对最终画面的影响程度。\n'
        '· 值越低 → 越接近原图，改动越少\n'
        '· 值越高 → 越自由发挥，重绘越多\n'
        '💡 0.01 时几乎不重绘；与 Noise 同时调到最低 → 完美复制原图\n'
        '💡 AI 过度忽略提示词时，可尝试提高 Prompt Guidance',
  );

  static const img2imgNoise = ParamHelp(
    '噪声 (Noise)',
    '在原图基础上额外注入随机扰动。\n'
        '· 0 → 完全基于原图，结果更稳定\n'
        '· 值越高 → 增加创作自由度，更多新元素\n'
        '💡 原图大面积空白时，调高可让 AI 主动补充细节\n'
        '💡 高 Noise 反复重生成可能产生视觉瑕疵',
  );

  // ---- Vibe ----

  static const vibeStrength = ParamHelp(
    '风格强度 (Reference Strength)',
    '控制 Vibe 风格对画面的影响力度。\n'
        '· 值越高 → 越接近参考图的风格、配色等视觉线索\n'
        '· 值越低 → 仅作轻微风格指引\n'
        '💡 多个 Vibe 同时使用时，强度总和建议 ≤ 1\n'
        '💡 过高时 AI 会开始忽略文字 prompt',
  );

  static const normalizeVibe = ParamHelp(
    '均衡强度 (Normalize)',
    '开启 → 所有 Vibe 的强度按比例缩小，合计强度 ≤ 1\n'
        '关闭 → 每个 Vibe 的强度独立相加',
  );

  static const infoExtracted = ParamHelp(
    '信息提取 (Information Extracted)',
    '从原图中提取的信息量。\n'
        '· 值越低 → 先丢失高频细节（纹理、风格），优先保留构图\n'
        '· 值越高 → 同时保留构图与纹理 / 风格细节\n'
        '💡 设置为新值时扣 2 点数，使用历史值时免费\n'
        '💡 无原图时无法重设该值',
  );

  // ---- 角色参考 ----

  static const charRefStrength = ParamHelp(
    '参考强度 (Strength)',
    '控制角色 / 风格参考对画面的整体影响力。\n'
        '· 值越高 → 越严格还原参考图特征\n'
        '· 值越低 → 参考图仅作弱引导\n'
        '💡 每张图额外消耗 5 Anlas，多个 PR 累加\n'
        '💡 过高时面部表情 / 角度 / 姿势会过度贴近参考图',
  );

  static const fidelity = ParamHelp(
    '还原度 (Fidelity)',
    '控制 prompt 能否压过参考图。\n'
        '· 值越高 → 参考图占主导，prompt 难以改变它\n'
        '· 值越低 → prompt 占主导，更易调整画面\n'
        '💡 实际效果可能因图而异，建议多尝试',
  );

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

  static const steps = ParamHelp(
    '采样步数 (Steps)',
    '采样步数，控制去噪迭代次数。\n'
        '步数越高画面越精细，但生成越慢。\n'
        '步数过多反而收益递减，甚至适得其反。\n'
        '💡 步数 ≤28 时不额外消耗 Anlas',
  );

  static const cfg = ParamHelp(
    '提示词引导强度 (CFG Scale)',
    '控制 AI 对提示词的遵循程度。\n'
        '· 值越低 → AI 越自由发挥，画面更绘画感、柔和、梦幻\n'
        '· 值越高 → 越严格遵循描述，细节更精细锐利\n'
        '💡 V3 及以上模型官方推荐 5~6\n'
        '💡 过高反而会反作用，色彩过饱和、画面崩坏',
  );

  static const varietyPlus = ParamHelp(
    '多样性增强模式 (Variety+)',
    '轻微调整采样过程，提升构图与姿势的多样性。\n'
        '开启 → 增加构图和姿势的变化\n'
        '关闭 → 出图更稳定一致\n'
        '💡 在低 Prompt Guidance 下效果更明显',
  );

  static const sampler = ParamHelp(
    '采样算法 (Sampler)',
    '决定去噪路径，影响画面风格与稳定性。\n'
        '· Euler Ancestral — 经典万能，随机性高\n'
        '· Euler — 确定性版本，构图更稳定\n'
        '· DPM++ 2S Ancestral — 细节丰富\n'
        '· DPM++ 2M SDE — 高质量 + 随机性\n'
        '· DPM++ 2M — 高质量确定性采样\n'
        '· DPM++ SDE — 兼具细节与多样性\n'
        '💡 建议保持默认或推荐 DPM++ 2M / Euler Ancestral\n'
        '💡 不同 sampler 的差异在低 Steps 时更明显',
  );

  static const noiseSchedule = ParamHelp(
    '噪声衰减曲线 (Noise Schedule)',
    '决定 Sampler 在每一步的噪声衰减节奏，影响画面质感。\n'
        '· karras — 最常用，出图稳定细节好\n'
        '· exponential — 指数衰减，对比度更强\n'
        '· polyexponential — 多项式衰减，过渡平滑\n'
        '💡建议保持默认 karras',
  );

  // ---- 修正 ----

  static const seed = ParamHelp(
    '随机种子 (Seed)',
    '随机种子，决定初始噪声。\n'
        '相同种子 + 相同参数 → 基本一致的画面\n'
        '适合微调时锁定构图。\n'
        '留空 → 每次随机生成不同结果\n'
        '💡 sampler 本身有微小随机性，相同种子也可能存在细微差别\n'
        '💡 NAI / Anima / Krea 三者的 seed 互不通用，与外部 Stable Diffusion 也不通用',
  );

  static const cfgRescale = ParamHelp(
    'CFG 引导修正系数 (Rescale)',
    '抑制高引导值带来的过饱和与色彩溢出。\n'
        '0 = 不修正，值越高 → 修正越强\n'
        '通常保持 0；Guidance >7 时可尝试 0.1~0.3\n'
        '💡 画面出现「边缘色彩过强 / 油炸感 (deepfried)」时调高',
  );
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

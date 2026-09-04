import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/anlas_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/param_input.dart';
import '../../../core/util/haptics.dart';
import '../cost.dart';
import '../gen_modules.dart';
import '../generate_state.dart';
import '../generation_controller.dart';
import '../loop_controller.dart';
import '../models.dart' show GenParams, kBatchMax, stepsRangeOf;
import '../vibe_encoder.dart';
import '../../import/import_panel.dart';
import 'advanced_sheet.dart';
import 'common.dart' show hintSnack;
import 'loop_sheet.dart';
import 'resolution_sheet.dart';

/// 吸底栏上方那一处浮动控件,现在是**谁开着**。
///
/// 几个读数共用创作页同一个位置,所以状态收成一个 —— 原先两个各存各的
/// open、还得互相 close 一把,再加一个就是三处两两配对。
enum FloatingPill { none, steps, batch }

/// 浮动控件的开合 + 拖动草稿。
///
/// 控件本体浮在创作页列表上([FloatingPillOverlay]),开关是吸底栏里的读数
/// 按钮,两处不在同一子树,靠这个 provider 连。**不能**塞进吸底栏——那样
/// 整条灰底会跟着一起抬高,不是「浮动」。
///
/// 拖动期间只写 [draft]:每帧改全局参数会连着整页和费用估算一起重建,读数与
/// 费用两个 AnimatedSwitcher 每帧重新起转,肉眼就是抖。松手才提交一次。
/// 同一时刻只可能有一根滑杆开着,所以草稿一份就够,切控件时跟着清掉。
class FloatingPillState {
  const FloatingPillState({this.which = FloatingPill.none, this.draft});

  final FloatingPill which;
  final double? draft;

  bool isOpen(FloatingPill p) => which == p;
}

final floatingPillProvider =
    NotifierProvider<FloatingPillNotifier, FloatingPillState>(
      FloatingPillNotifier.new,
    );

class FloatingPillNotifier extends Notifier<FloatingPillState> {
  @override
  FloatingPillState build() => const FloatingPillState();

  void toggle(FloatingPill p) => state = FloatingPillState(
    which: state.which == p ? FloatingPill.none : p,
  );

  void close() => state = const FloatingPillState();

  void drag(double v) =>
      state = FloatingPillState(which: state.which, draft: v);

  /// 松手 / 提交:留着开合状态,只把草稿清掉。
  void endDrag() => state = FloatingPillState(which: state.which);
}

/// 会**真正发出去**的那份参数(剥掉隐藏模块之后)。
///
/// 读数和浮动选择器都得按它显示:重绘放大模块被藏起来时 `hires.enabled`
/// 会被剥成 false,而载荷正是按剥离后那份拼的 —— 拿没剥的那份判,界面会说
/// 「锁定 1」而实际发 4。三处各自 strip 一遍迟早只改对一处,所以收在这里。
///
/// 大多数改动下 `stripHiddenModules` 会原样返回同一个 [GenParams] 实例,
/// 所以订阅方不会跟着整页重建。
final sentParamsProvider = Provider<GenParams>((ref) {
  final s = ref.watch(generateProvider);
  final mods = ref.watch(genModulesProvider).value ?? const GenModuleSettings();
  return stripHiddenModules(s, mods).params;
});

/// 吸底操作栏:参数读数 chips + 循环伴钮 + 生成主按钮
class BottomActionBar extends ConsumerStatefulWidget {
  const BottomActionBar({super.key});

  @override
  ConsumerState<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends ConsumerState<BottomActionBar> {
  /// 上一次算出的 Vibe 编码费。改 IE / 换模型都会生成新的查询键,新键从
  /// loading 起步、取值为 null —— 直接落 0 会让费用在「免费 ⇄ N」之间反复跳
  /// (快速改 IE 时肉眼可见地闪)。查缓存本就是毫秒级,沿用上次的值更稳。
  int _lastVibeFee = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generateProvider);
    final scheme = context.scheme;
    final p = state.params;
    final gen = ref.watch(genStatusProvider);
    final pool = ref.watch(generationProvider);
    final loop = ref.watch(loopStatusProvider);

    final isOpus = ref.watch(anlasProvider).asData?.value?.isOpus ?? false;
    // V5 额度见底后免费尺寸转扣 Anlas,那时「免费」得变回真实点数(见 provider)
    final v5Charged = ref.watch(v5ChargedProvider);
    // 成本按实际会发送的内容估:隐藏模块的数据不发也不计
    final mods =
        ref.watch(genModulesProvider).value ?? const GenModuleSettings();
    final sent = stripHiddenModules(state, mods);
    // 编码费单列:与 estimateCost 里的「第 5 张起 +2」是两笔钱,漏算会让新加
    // 一张 Vibe 时按钮写「免费」而实扣 2 点。异步查缓存,结果没到就沿用上次
    // (见 _lastVibeFee),避免费用在参数连改时来回跳。
    final fee = ref.watch(vibeEncodeFeeProvider(vibeEncodeFeeKey(sent))).value;
    if (fee != null) _lastVibeFee = fee;
    // 带遮罩(重绘)走另一条公式:像素按**发送尺寸**算、再按强度折算。
    // 用生成那条公式会把重绘的价钱报高 —— 重绘发的常常只是一小块裁切区。
    final job = sent.inpaint;
    final totalCost =
        (job != null
            ? estimateInpaintCost(
                sent,
                isOpus: isOpus,
                sendW: sent.params.width,
                sendH: sent.params.height,
                strength: job.strength,
                v5Charged: v5Charged,
              )
            : estimateCost(sent, isOpus: isOpus, v5Charged: v5Charged)) +
        (fee ?? _lastVibeFee);
    // 按**会发出去**的那份参数判(见 sentParamsProvider)
    final batchable = sent.params.batchable;

    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 两种排法,按有没有「张数」分:
            //  · anima / krea 四颗 —— 均分。左边挤成一堆的话 Spacer 被压没,
            //    张数会和「高级」贴在一起;
            //  · NAI 三颗 —— 还是「左边一串 + 高级钉右边」。三颗均分会把步数
            //    甩到正中间,中间那片空白比贴在一起更晃眼。
            Row(
              mainAxisAlignment: batchable
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.start,
              children: [
                _ReadoutChip(
                  caption: '尺寸',
                  value: '${p.width}×${p.height}',
                  onTap: () => showResolutionSheet(context),
                ),
                if (!batchable) const SizedBox(width: 8),
                const _StepsChip(),
                // 张数只有 anima / krea 有(NAI 那条路一单一张)。**不给它常驻
                // 一个位置**:NAI 下摆个恒为 1、点了还得解释「这个模型不支持」
                // 的读数,只是白占那条本来就挤的行。
                if (batchable) const _BatchChip() else const Spacer(),
                _ReadoutChip(
                  icon: Icons.tune,
                  value: '高级',
                  valueMuted: true,
                  onTap: () => showAdvancedSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 导入图片:选相册图 → 解析元数据/用作参考的全屏导入面板
                Tooltip(
                  message: '导入图片',
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: .9),
                        width: 1.5,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => openImportPanel(context),
                        child: Center(
                          child: Icon(
                            Icons.input,
                            size: 22,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                // 循环伴钮:进循环面板(选张数并开始);运行中高亮,面板里可停
                Tooltip(
                  message: '循环生成',
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: loop.active
                          ? scheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: loop.active
                            ? scheme.primary
                            : scheme.outline.withValues(alpha: .9),
                        width: 1.5,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => showLoopSheet(context),
                        child: Center(
                          child: Icon(
                            Icons.autorenew,
                            size: 22,
                            color: loop.active
                                ? scheme.onPrimaryContainer
                                : scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                // 生成主按钮。**并行之后它一直是「生成」**:再点就是再投一条。
                // 有任务在跑时按钮**内部**右侧长出一段停止区(带进度环)——
                // 创作页看不见图库的任务卡,没它就整页看不到进度、也没处取消。
                Expanded(
                  child: _GenerateButton(
                    cost: totalCost,
                    onGenerate: () {
                      _hintDisabledVibes(context, ref);
                      ref.read(generationProvider.notifier).generate();
                    },
                    progress: pool.busy ? gen.progress : null,
                    runningCount: pool.busy ? pool.jobs.length : 0,
                    stopIcon: loop.active && !loop.stopping
                        ? Icons.stop_rounded
                        : Icons.close_rounded,
                    // 循环:第一次点=软停(本张跑完后停),**再点一次=强制取消**。
                    // 软停后绝不能变成 null —— 那会在当前张卡住时(断网最常见)
                    // 关掉唯一的退路,只能干等超时。实测反馈。
                    onStop: loop.active && !loop.stopping
                        ? () => ref.read(loopStatusProvider.notifier).stop()
                        : () => ref.read(generationProvider.notifier).cancel(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 生成/排队前置检查:缺当前模型编码的纯编码 Vibe 无从现场编码,
/// 只会被静默跳过——直接停用并提示,别让人误以为它生效了。
void _hintDisabledVibes(BuildContext context, WidgetRef ref) {
  final n = ref.read(generateProvider.notifier).disableVibesMissingEncoding();
  if (n > 0) {
    hintSnack(
      context,
      '$n 个 Vibe 缺当前模型编码,已停用',
      icon: Icons.visibility_off_outlined,
    );
  }
}

/// 生成主按钮。有任务在跑时**按钮内部**右侧展开一段停止区:
/// 环 = 画布正跟随那条的进度(与图库画布上的进度胶囊同一条口径,不是全池平均
/// —— 平均值谁也对不上号),多条在跑时环里标数。
///
/// 做成一颗按钮而不是两颗并排:并排那版把主按钮挤窄了一截,而且「生成」和
/// 「停止」是同一件事的两面,分开两个方块反而要多想一下哪个是哪个。
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.cost,
    required this.onGenerate,
    required this.progress,
    required this.runningCount,
    required this.stopIcon,
    required this.onStop,
  });

  final int cost;
  final VoidCallback onGenerate;

  /// 跟随那条的进度;null = 还没出图(走不确定动画)。
  final double? progress;

  /// 在跑的条数;0 = 不显示停止区。
  final int runningCount;
  final IconData stopIcon;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final busy = runningCount > 0;
    return SizedBox(
      height: 52,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        // stretch:两段都要撑满 52 的高度。默认的 center 会让 InkWell 只拿到
        // 内容那点自然高度(≈28),按钮看着一大颗、实际只有中间一条窄带能点 ——
        // 表现就是「只有文字上点得动」。实测反馈。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: onGenerate,
                // 费用数字变长(编码费叠加后可到三位数)时这一行会顶破按钮 ——
                // 实测快速改 IE 会看到溢出围栏。两段文本都收进 Flexible +
                // 省略号,宁可挤扁不越界。
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 池子里已经有任务 → 换成加号:这一下是「再加一条」,
                    // 不是「开始生成」,图标得说清楚。
                    Icon(
                      busy ? Icons.add_rounded : Icons.auto_awesome,
                      size: busy ? 22 : 20,
                      color: scheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '生成',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      // 宽度滑过去而不是跳。胶囊自己按「两位数」定了最小宽,
                      // 免费与一位数都在这个宽度里,平时根本不动;三位数以上
                      // 才撑开,那一下由这层补成一段过渡 —— 不然「生成」两个字
                      // 会跟着横向弹一格。
                      child: AnimatedSize(
                        duration: Motion.fast,
                        curve: Motion.standard,
                        child: AnimatedSwitcher(
                          duration: Motion.fast,
                          child: CostPill(key: ValueKey(cost), cost: cost),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (busy) ...[
              // 竖细线:两段是两个可点区域,没有分界的话点哪儿全靠猜。
              // 包一层 Center —— 外层是 stretch,不包的话这道线会被撑到通高。
              Center(
                child: Container(
                  width: 1,
                  height: 30,
                  color: scheme.onPrimary.withValues(alpha: .28),
                ),
              ),
              Tooltip(
                message: runningCount > 1
                    ? '取消当前跟随的这条($runningCount 条在跑)'
                    : '取消生成',
                child: InkWell(
                  onTap: onStop,
                  child: SizedBox(
                    width: 58,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 2.5,
                            backgroundColor: scheme.onPrimary.withValues(
                              alpha: .28,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              scheme.onPrimary,
                            ),
                          ),
                        ),
                        Icon(stopIcon, size: 18, color: scheme.onPrimary),
                        if (runningCount > 1)
                          Positioned(
                            right: 6,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.onPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$runningCount',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 主按钮内的成本胶囊。
///
/// 「Anlas」这个词砍掉换成顶栏同款点数图标(重绘 CTA 早就这么做了,见
/// inpaint_overlay):按钮内部现在还要分一段给停止区,最长的那个词首先该让位,
/// 四位数也不必再靠省略号救。免费档保留中文 —— 一个图标表达不了「不要钱」。
///
/// 要扣点时整颗胶囊换成 tertiaryContainer 的浅粉,免费档留中性半透明。
/// 原先两档共用同一身皮,压在 primary 按钮上就是一块和底色同族的灰,
/// 「这一单要不要花钱」得盯着字读;现在扫一眼颜色就知道。
///
/// 粉色特意借 tertiaryContainer 那一对而不是自己定一支:角色的计数徽章、
/// 灵感页的「随机」徽章用的就是它([CountBadge] 同款),app 里的浅粉只此一种,
/// 换主题色时也跟着它们一起走,不会某天变成两种粉。
///
/// **公开只为可测**:这颗胶囊的不变量(免费与两位数等宽、两档等高、不撑满
/// 按钮)全是布局层面的,analyze 一条都查不出来,历史上连着栽过三次。
/// 直接 pump 它比经由整页去凑一个免费/收费状态可靠得多,见 widget_test。
class CostPill extends StatelessWidget {
  const CostPill({super.key, required this.cost});

  final int cost;

  static const _icon = 12.0;
  static const _gap = 3.0;
  static const _padH = 8.0;
  static const _padV = 3.0;

  /// 内容行的固定高。**别让它跟着文字走** —— 两档字号不同(11 / 12),各自的
  /// 自然行高会让胶囊在免费时高一点点;而把行高锁成 1 换来的是另一头的毛病:
  /// 行盒正好等于字号,胶囊就紧紧贴着字,比原来还矮一截。
  ///
  /// 所以行高照锁(两档等高),上下的余量由这个盒子给:12 的图标摆在 14 里,
  /// 各留 1;连同 [_padV] 一共 20 的胶囊,和左边「生成」那行字的分量对得上。
  static const _contentH = 14.0;

  /// 点数那档的字号。免费档要大一号 —— 见 [_freeSize]。
  static const _numSize = 11.0;

  /// 免费档的字号。两个方块字按 1em 走,11 号只有 22 宽,比点数那行整整窄
  /// 一截,两档轮流出现时看着就是大小不一。放到 12(= 24 宽)才和点数那行
  /// 的分量对得上。
  static const _freeSize = 12.0;

  /// 撑宽度的隐形替身:恒按「图标 + 间隔 + 两位数字」占位,画不出来但照样参与
  /// 布局(alpha 为 0 的 Opacity 只跳过绘制,语义也一并排除)。
  ///
  /// 为什么不写一个 minWidth 常数了:那得自己算「两位数字有多宽」,而数字宽度
  /// 是**字体的事**。先前按 Roboto 的 0.57em 估了 43.5,真机上的中文字体数字
  /// 比这宽一点点,于是两位数那档刚好越过下限、免费那档还卡在下限上 —— 差的
  /// 就是那零点几像素,表现为切到免费时左边「生成」两个字往左挪一格。
  /// 让替身去量,谁的字体都不用猜。
  Widget _ghost(TextStyle style) => Opacity(
    opacity: 0,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.toll, size: _icon),
        const SizedBox(width: _gap),
        Text('00', maxLines: 1, softWrap: false, style: style),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final paid = cost > 0;
    // 底色换了,字色得跟着换到配套的那支 —— onPrimary 是给按钮底色配的,
    // 压在浅粉上会在浅色主题下变成浅字压浅底。
    final fg = paid ? scheme.onTertiaryContainer : scheme.onPrimary;
    // height 1 = 行盒正好等于字号,两档(11 / 12)于是一样高;上下的呼吸留给
    // [_contentH] 那个盒子,不靠行高撑 —— 靠行高撑的话两档又会差回去。
    final style = TextStyle(
      fontSize: paid ? _numSize : _freeSize,
      height: 1,
      fontWeight: FontWeight.w700,
      color: fg,
    );
    // ⚠ 居中靠 Stack / Row 自己做,**不要**给这个 Container 加 alignment、
    // 也不要在里面套 Center:两者都会包出一个 Align,而 Align 在有界约束下
    // 直接取 constraints.biggest —— 胶囊会从「生成」一路撑到按钮右缘。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: _padV),
      decoration: BoxDecoration(
        color: paid
            ? scheme.tertiaryContainer
            : scheme.onPrimary.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(9),
      ),
      child: SizedBox(
        height: _contentH,
        // Stack 取最宽的那个孩子(loose fit 不会撑满约束),于是替身成了宽度
        // 的下限:免费、一位数都躲在它后面,三位数以上才把它顶出去 —— 那是
        // 少数情况,由外面的 AnimatedSize 滑过去。
        child: Stack(
          alignment: Alignment.center,
          children: [
            _ghost(style.copyWith(fontSize: _numSize)),
            // 免费档也走 Row(而不是一个光秃秃的 Text):高度与竖向居中就此
            // 两档同源,换一档不会连带着换一套对齐方式。
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: !paid
                  ? [Text('免费', maxLines: 1, softWrap: false, style: style)]
                  : [
                      Icon(Icons.toll, size: _icon, color: fg),
                      const SizedBox(width: _gap),
                      Flexible(
                        child: Text(
                          '$cost',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: style,
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 步数读数按钮:点开/收起浮动滑杆。拖动中显示草稿值(全局参数松手才变),
/// 所以按钮上的数字和滑杆上的始终一致。
class _StepsChip extends ConsumerWidget {
  const _StepsChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只订阅这一个数:拖动时不牵动整条栏重算成本
    final committed = ref.watch(
      generateProvider.select((s) => s.params.activeSteps),
    );
    final pill = ref.watch(floatingPillProvider);
    final open = pill.isOpen(FloatingPill.steps);
    return _ReadoutChip(
      caption: '步数',
      value: '${(open ? pill.draft?.round() : null) ?? committed}',
      active: open,
      // 拖动时逐帧换数,再叠淡入淡出只会糊成一团
      animateValue: !open,
      onTap: () =>
          ref.read(floatingPillProvider.notifier).toggle(FloatingPill.steps),
    );
  }
}

/// 一次出几张(anima / krea 的 `batch_size`)。
///
/// 摆在吸底栏而不是高级设置里:这是**每次都会变**的决策(想多看几个构图就
/// 调大,定稿了就调回 1),和「生成」这个动作绑在一起才顺手 —— 旁边那颗循环
/// 生成也是同一类东西。高级设置那一屏放的是调好就不常动的采样参数。
class _BatchChip extends ConsumerWidget {
  const _BatchChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按**会发出去**的那份参数显示,见 sentParamsProvider
    final p = ref.watch(sentParamsProvider);
    final open = ref.watch(
      floatingPillProvider.select((x) => x.isOpen(FloatingPill.batch)),
    );
    // 开着重绘放大时服务端强制单张(二段要跑 N × scale² 的量)。这里显示
    // **实际会出的张数**并且点不开选择器 —— web 早期是服务端静默覆盖,
    // 选 4 出 1 张且没有任何提示,那种不一致最难查。
    final locked = p.effectiveBatch != p.batchCount;
    return _ReadoutChip(
      caption: '张数',
      value: '${p.effectiveBatch}',
      // 锁着时把读数压灰(和「高级」那颗同一种「这不是可调的数」的说法),
      // 不加锁形图标:那会让这一格忽宽忽窄,整行跟着抖。为什么是 1,点一下才说。
      valueMuted: locked,
      active: open,
      onTap: () {
        if (locked) {
          hintSnack(
            context,
            '重绘放大开着时只能出 1 张:二段采样要按放大后的尺寸再跑一遍,'
            '显存吃不下一批。',
            icon: Icons.info_outline,
          );
          return;
        }
        ref.read(floatingPillProvider.notifier).toggle(FloatingPill.batch);
      },
    );
  }
}

/// 吸底栏上方那一处浮动控件。挂在创作页 Stack 顶层,浮在列表上方、吸底栏
/// 之上——不占布局,开合不会推动任何东西。视觉与重绘面板的浮动滑杆同款。
///
/// 三个读数共用这一处,由 [floatingPillProvider] 决定画哪个;
/// AnimatedSwitcher 顺带让「从步数切到 CFG」是一次交叉淡入,不是闪一下。
class FloatingPillOverlay extends ConsumerWidget {
  const FloatingPillOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(sentParamsProvider);
    var which = ref.watch(floatingPillProvider.select((x) => x.which));
    // 换模型 / 开重绘放大之后,对应那颗读数会消失或锁上,浮层得跟着收 ——
    // 不收的话下次切回来它会自己冒出来,像见了鬼。
    // (只在这儿判「还该不该画」,真正把状态清掉交给下面那次 listen。)
    final okFor = switch (which) {
      FloatingPill.batch => p.batchable && p.effectiveBatch == p.batchCount,
      _ => true,
    };
    if (!okFor) which = FloatingPill.none;
    ref.listen<bool>(
      sentParamsProvider.select(
        (x) => x.batchable && x.effectiveBatch == x.batchCount,
      ),
      (_, _) => ref.read(floatingPillProvider.notifier).close(),
    );
    return AnimatedSwitcher(
      duration: Motion.fast,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .3),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: switch (which) {
        FloatingPill.steps => const _StepsSliderPill(),
        FloatingPill.batch => const _BatchPickerPill(),
        FloatingPill.none => const SizedBox.shrink(),
      },
    );
  }
}

/// 浮动控件的外壳:药丸底 + 左侧标题。三个控件长得一样,只是里面装的不同。
class _PillShell extends StatelessWidget {
  const _PillShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return GestureDetector(
      // 不透明:否则药丸空白处的拖动会穿过去滚动底下的列表
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _BatchPickerPill extends ConsumerWidget {
  const _BatchPickerPill();

  static const _h = 36.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final cur = ref.watch(sentParamsProvider).batchCount.clamp(1, kBatchMax);
    return _PillShell(
      label: '张数',
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Container(
          height: _h,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            // 方角(与高级设置里那排选择块同款),不是药丸:外面那圈浮层已经是
            // 圆的了,里面再套一圈圆的会糊成一团
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final segW = c.maxWidth / kBatchMax;
              return Stack(
                // 默认 topStart 会让那排数字只拿到自身高度、被顶在框顶上
                alignment: Alignment.center,
                children: [
                  AnimatedAlign(
                    duration: Motion.medium,
                    curve: Motion.emphasized,
                    // -1..1 的对齐值:第 i 段的中心
                    alignment: Alignment(
                      kBatchMax == 1 ? 0 : (cur - 1) / (kBatchMax - 1) * 2 - 1,
                      0,
                    ),
                    child: Container(
                      width: segW,
                      height: _h - 6,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var n = 1; n <= kBatchMax; n++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Haptics.selection();
                              ref
                                  .read(generateProvider.notifier)
                                  .setBatchCount(n);
                              // 选完就收:1–4 是一下点中的事,
                              // 不像滑杆要留着来回拖
                              ref.read(floatingPillProvider.notifier).close();
                            },
                            // 撑满滑块那么高:整段都可点,不写高度的话只有
                            // 数字那一小块按得动
                            child: SizedBox(
                              height: _h - 6,
                              child: Center(
                                child: Text(
                                  '$n',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: n == cur
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: n == cur
                                        ? scheme.onPrimary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StepsSliderPill extends ConsumerWidget {
  const _StepsSliderPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // NAI / Anima / Krea 各有一套独立步数,范围也不同(与高级面板同源)
    final range = ref.watch(
      generateProvider.select((s) => stepsRangeOf(s.params.model)),
    );
    final committed = ref.watch(
      generateProvider.select((s) => s.params.activeSteps),
    );
    final min = range.min;
    final max = range.max;
    final steps =
        (ref.watch(floatingPillProvider.select((x) => x.draft))?.round() ??
                committed)
            .clamp(min, max);
    return _PillShell(
      label: '步数',
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: compactSliderTheme,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  value: steps.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  // 不传 divisions:离散 Slider 会用 75ms 曲线把滑块吸到刻度,
                  // 拖起来黏手。步长(整数)就地取整。
                  onChanged: (v) => ref
                      .read(floatingPillProvider.notifier)
                      .drag(v.roundToDouble()),
                  // 松手才写回全局:先提交再清草稿,同一帧生效,不会闪回旧值
                  onChangeEnd: (v) {
                    final p = ref.read(generateProvider).params;
                    ref
                        .read(generateProvider.notifier)
                        .applyParams(p.withActiveSteps(v.round()));
                    ref.read(floatingPillProvider.notifier).endDrag();
                  },
                ),
              ),
            ),
          ),
          ParamValueBox(
            text: '$steps',
            dense: true,
            onTap: () async {
              // 弹窗期间不能再动别的,提前把 notifier 和参数取好,
              // 醒来直接写 —— 不留 await 之后再摸 ref 的口子
              final notifier = ref.read(generateProvider.notifier);
              final pill = ref.read(floatingPillProvider.notifier);
              final p = ref.read(generateProvider).params;
              final v = await showParamInput(
                context,
                title: '步数 Steps',
                value: steps.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
              );
              if (v == null) return;
              notifier.applyParams(p.withActiveSteps(v.round()));
              pill.endDrag();
            },
          ),
        ],
      ),
    );
  }
}

class _ReadoutChip extends StatelessWidget {
  const _ReadoutChip({
    this.caption,
    this.icon,
    required this.value,
    this.valueMuted = false,
    this.active = false,
    this.animateValue = true,
    required this.onTap,
  });

  final String? caption;
  final IconData? icon;
  final String value;
  final bool valueMuted;

  /// 该读数的滑杆正展开着(描边高亮,与重绘面板的参数按钮同款)。
  final bool active;

  /// 数值变化是否走淡入淡出。逐帧变的值要关掉,否则一堆数字叠着糊。
  final bool animateValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = Text(
      value,
      key: ValueKey(value),
      style: valueMuted
          ? context.texts.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)
          : mono(context, size: 13),
    );
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          // 边框常在(不激活时透明):BoxDecoration 的边框会算进内边距,
          // 有无之间差 2px —— 只在激活时给,整行会跟着抖一下。
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: .6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
              ],
              if (caption != null) ...[
                Text(
                  caption!,
                  style: TextStyle(fontSize: 10, color: scheme.outline),
                ),
                const SizedBox(width: 5),
              ],
              if (animateValue)
                AnimatedSwitcher(duration: Motion.fast, child: text)
              else
                text,
            ],
          ),
        ),
      ),
    );
  }
}

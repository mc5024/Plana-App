import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/param_help.dart';
import '../../generate/generate_state.dart';
import '../../generate/gen_modules.dart' show retargetModel;
import '../../generate/generation_controller.dart';
import '../../generate/models.dart';
import '../../generate/cost.dart' show estimateInpaintCost;
import '../../generate/widgets/common.dart'
    show ParamSlider, hintSnack, sharedAxisRoute;
import '../../import/import_panel.dart';
import '../../inpaint/inpaint_overlay.dart';
import '../../../core/net/anlas_provider.dart';
import '../../../core/store/app_stores.dart';
import '../../../core/util/haptics.dart';
import '../../../core/util/image_ops.dart';
import '../gallery_state.dart';
import '../models.dart';
import '../save_pipeline.dart';
import '../save_settings.dart';
import '../upscale_model.dart';
import '../upscale_nai.dart';
import 'save_sheet.dart';

/// 持久大图层:有字节 → `Image.memory`(gaplessPlayback);否则画一个目标尺寸的空画框。
/// 生成/查看全程复用同一个 Image widget,借 gaplessPlayback 桥接逐帧预览与终图,消除切换闪烁。
///
/// 占位**不再用斜纹 CustomPaint**:斜纹是平行四边形路径,右端会伸出画布 size.height
/// 那么远,而 CustomPaint 默认不裁剪 —— 在 PageView 里横滑时整条纹直接糊到隔壁页上。
/// 现在这版只有 ColoredBox + Container,画不出界。
class GalleryImageLayer extends StatelessWidget {
  const GalleryImageLayer({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List? bytes;
  final int width;
  final int height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    if (bytes != null) {
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: Image.memory(
            bytes!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    // 空画框按目标宽高比撑到最大,落点与出图后 BoxFit.contain 的位置一致 ——
    // 图一到就在原地替换,不会跳位。尺寸未知(width/height 为 0)时只留底色。
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: (width > 0 && height > 0)
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: AspectRatio(
                  aspectRatio: width / height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .55,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .8),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$width × $height',
                        style: mono(
                          context,
                          size: 20,
                          weight: FontWeight.w600,
                          color: scheme.onSurfaceVariant.withValues(alpha: .55),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// 结果操作层:右侧竖排操作轨 + 左下 seed 芯片(叠在大图上)。
class ResultChrome extends StatelessWidget {
  const ResultChrome({super.key, required this.result});

  final ResultImage result;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(right: 12, bottom: 16, child: _ActionRail(result: result)),
        Positioned(left: 12, bottom: 16, child: _SeedChip(seed: result.seed)),
      ],
    );
  }
}

/// 浮动进度胶囊(浅色)。入场/离场的渐显渐隐由外层 AnimatedSwitcher 负责,这里只画静态样子。
///
/// 尾部那颗 × 取消**画布正跟随的这一条**(对齐 web:取消按钮长在状态条上)。
/// 早先试过把它做成胶片条任务卡右上角的小角标,22px 挤在 62px 高的缩略图上,
/// 和「点卡切换跟随」这个主手势离得太近 —— 想切图却取消掉一张的代价太大。
class ProgressPill extends StatelessWidget {
  const ProgressPill({super.key, required this.status, this.onCancel});

  final GenStatus status;
  final VoidCallback? onCancel;

  /// 胶囊上那行字:正在逐步出图 → `step/total`;其余(准备阶段、跑满之后的
  /// 收尾)→ 阶段文案,没有文案才退回「准备中」/「收尾中」。
  ///
  /// ⚠ 判据是 [GenStatus.sampling] 而不是「进度条有没有值」:准备阶段现在也
  /// 能借「拉 LoRA」的百分比画出条来,按有没有值判会在那几分钟里显示「0/0」。
  static String _label(GenStatus status) {
    if (status.sampling && status.step < status.total) {
      return '${status.step}/${status.total}';
    }
    return status.note ?? (status.sampling ? '收尾中' : '准备中');
  }

  /// 胶囊那一套配套的数。**别单独动其中一个** —— 它们互相定死了:
  ///
  /// - [_h] 定圆角(`h/2`)和取消钮直径([_btn],上下各留 4)。
  /// - 右内衬要按 **× 的字形**算光学间距,不是按圆钮的外框:那 [_btn] 是点击
  ///   热区,静止时看不见,照它对齐的话右边会比左边紧 `(_btn-_icon)/2`。
  ///   [_padR] 就是把这段差补回去,让左右看起来一样宽。
  static const double _h = 38;
  static const double _pad = 16;
  static const double _btn = _h - 8;
  static const double _icon = 18;
  static const double _padR = _pad - (_btn - _icon) / 2;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final p = status.progress;
    return Container(
      height: _h,
      padding: EdgeInsets.only(
        left: _pad,
        right: onCancel == null ? _pad : _padR,
      ),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(_h / 2),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 条细一点(原先 11 粗、116 长):粗的条压过了旁边的读数,看着像个
          // 进度块而不是一条进度。长度跟着胶囊一起收一点,免得细了之后显得太长。
          SizedBox(
            width: 104,
            height: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: p, // null = 准备中,走不确定动画
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            // 采样**跑满之后**还有一段(VAE 解码 / 存盘 / 跨境取图),那时
            // `36/36` 已经没有信息量了 —— 有阶段文案就换成文案,否则用户
            // 盯着一条满进度条不知道还在等什么。
            _label(status),
            // ⚠ 这行**会出现中文**(「加载模型」「取图中」「准备 LoRA」),
            // 所以不能走 mono():等宽字体里没有中文字,中文会掉到系统的 CJK
            // 回退上,和同一行里的等宽拉丁字母长得不像一家。
            // 最初这里只有纯数字,等宽没问题;接了阶段文案之后就不行了。
            // tabularFigures 留着 —— 数字仍然等宽,`9/36 → 10/36` 不会左右挤。
            // (web 同款教训,MainContent 那行注释里点名了这条。)
            style: context.texts.bodyMedium!.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: _btn,
              height: _btn,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onCancel,
                  child: Icon(
                    Icons.close_rounded,
                    size: _icon,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「按住对比」正按着时要显示的**源图**字节;没按住为 null。
///
/// 提到 provider 是因为按钮在操作轨上、画面在图库画布上,两棵子树互不相干。
/// 只存本次按住的这一份,松手即清 —— 它是个瞬时姿态,不该活过这一次按压。
final compareBytesProvider = NotifierProvider<CompareBytesNotifier, Uint8List?>(
  CompareBytesNotifier.new,
);

class CompareBytesNotifier extends Notifier<Uint8List?> {
  @override
  Uint8List? build() => null;

  void show(Uint8List bytes) => state = bytes;
  void hide() => state = null;
}

/// 右侧操作轨的收合状态。
///
/// **提到 provider 而不是留在 widget 里**:切页、换图都会把画布那棵子树重建掉,
/// 局部 state 跟着没 —— 用户看到的就是「明明收起了,回来又自己展开」。
///
/// 同步读:PrefsStore 的内存表在 AppStores.open 时已经装满,所以这里没有
/// 「首帧还没读出来」那一档 —— 那正是放大面板记忆坏掉的成因,别再踩一遍。
final railCollapsedProvider = NotifierProvider<RailCollapsedNotifier, bool>(
  RailCollapsedNotifier.new,
);

class RailCollapsedNotifier extends Notifier<bool> {
  static const _key = 'gallery_rail_collapsed';

  @override
  bool build() {
    try {
      return ref.read(prefsStoreProvider).get(_key) == '1';
    } catch (_) {
      return false; // 没有 AppStores 的场合(测试)按摊开算
    }
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      await ref.read(prefsStoreProvider).write(key: _key, value: v ? '1' : '0');
    } catch (_) {} // 写失败只影响下次恢复,不打扰这一次收合
  }
}

/// 手指还按在「对比」上没有?读盘是异步的,读完可能已经松手了。
final _holdingProvider = NotifierProvider<_HoldingNotifier, bool>(
  _HoldingNotifier.new,
);

class _HoldingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  set on(bool v) => state = v;
}

class _ActionRail extends ConsumerStatefulWidget {
  const _ActionRail({required this.result});

  final ResultImage result;

  @override
  ConsumerState<_ActionRail> createState() => _ActionRailState();
}

class _ActionRailState extends ConsumerState<_ActionRail> {
  ResultImage get result => widget.result;

  /// 收起 = 只留「重新生成」那一颗。四颗次要动作平时顺着右边缘占掉大半屏高,
  /// 挡的正好是竖图的主体;而看图的时候多半一颗都不用点。
  void _setCollapsed(bool v) {
    if (ref.read(railCollapsedProvider) == v) return;
    Haptics.selection();
    ref.read(railCollapsedProvider.notifier).set(v);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(railCollapsedProvider);
    return GestureDetector(
      // 竖向拖:上滑展开、下滑收起 —— 方向即语义,不用先找那颗小箭头在哪。
      // 只认速度不认位移:这条轨很窄,一路拖到底反而别扭,轻甩一下就该认。
      onVerticalDragEnd: (d) {
        final v = d.velocity.pixelsPerSecond.dy;
        if (v < -80) {
          _setCollapsed(false);
        } else if (v > 80) {
          _setCollapsed(true);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 收起的只有这四颗;「重新生成」永远露着 —— 它是这一屏的主动作,
          // 藏起来就等于把最常点的那颗也一起收走了。
          ClipRect(
            child: AnimatedAlign(
              duration: Motion.medium,
              curve: Motion.standard,
              alignment: Alignment.bottomRight,
              heightFactor: collapsed ? 0 : 1,
              child: AnimatedOpacity(
                duration: Motion.fast,
                opacity: collapsed ? 0 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _RailButton(
                      label: '重绘',
                      icon: Icons.brush,
                      onTap: () => _inpaint(context, ref),
                    ),
                    const SizedBox(height: 10),
                    _RailButton(
                      label: '放大',
                      icon: Icons.open_in_full,
                      onTap: () => _upscale(context, ref),
                    ),
                    const SizedBox(height: 10),
                    _RailButton(
                      label: '保存',
                      icon: Icons.download,
                      onTap: () => _download(context, ref),
                      onLongPress: () => _openSaveSheet(context, ref),
                    ),
                    const SizedBox(height: 10),
                    _RailButton(
                      label: '导入',
                      icon: Icons.input,
                      onTap: () => _import(context, ref),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
          _RailHandle(
            collapsed: collapsed,
            onTap: () => _setCollapsed(!collapsed),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 只有重绘产物才有「之前」可看;源图被删了也不给(取不到字节)。
              if (result.inpaintFrom != null) ...[
                _RailButton(
                  label: '对比',
                  icon: Icons.compare,
                  onHold: (down) => _compare(context, ref, down),
                  onTap: () {},
                ),
                const SizedBox(width: 10),
              ],
              _RailButton(
                label: '重新生成',
                icon: Icons.refresh,
                primary: true,
                onTap: () => _regenerate(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 按住看重绘前的原图,松手回到结果。
  ///
  /// 按下才去读盘:大多数时候没人按,提前读就是白占内存。读回来时可能已经松手了
  /// (`_holding` 那一道)—— 那时不该再把图糊上去。
  Future<void> _compare(BuildContext context, WidgetRef ref, bool down) async {
    final n = ref.read(compareBytesProvider.notifier);
    ref.read(_holdingProvider.notifier).on = down;
    if (!down) {
      n.hide();
      return;
    }
    final from = result.inpaintFrom;
    if (from == null) return;
    final bytes = await ref.read(appStoresProvider).gallery.readImage(from);
    if (bytes == null || !context.mounted) return;
    // 先解码再上屏:直接 setState 的话第一帧还没解出来,画面会白闪一下。
    await precacheImage(MemoryImage(bytes), context);
    if (ref.read(_holdingProvider)) n.show(bytes);
  }

  /// 字节:内存缓存优先,卸载/水合后按需读盘(读不到才是真无像素)。
  Future<Uint8List?> _bytesOf(WidgetRef ref) async =>
      result.bytes ??
      await ref.read(appStoresProvider).gallery.readImage(result.id);

  /// 参数快照:内存优先;盘上有(hasInput)则懒读,读失败/无快照为 null。
  Future<GenerateState?> _inputOf(WidgetRef ref) async =>
      result.input ??
      (result.hasInput
          ? await ref.read(appStoresProvider).gallery.readInput(result.id)
          : null);

  /// 重绘一次只能有一条 —— 回贴信息(裁切框/原图)是随会话共享的,两条同时跑会串。
  ///
  /// 普通出图**不再拦**:并行之后「重新生成」「1.5× 重绘」只是往池子里再投一条,
  /// 排不排得下由池子的上限说了算。
  bool _blockWhileInpainting(BuildContext context, WidgetRef ref) {
    if (!ref.read(inpaintStatusProvider).busy) return false;
    hintSnack(context, '重绘进行中,请稍候', icon: Icons.hourglass_top);
    return true;
  }

  /// 重绘:图库画布原地切入涂抹编辑面板(非路由页)。参数一律取创作页**当前**
  /// 状态(对齐 web `handleInpaintGenerate`:重绘用的是此刻编辑器里的提示词/
  /// 角色/vibe,不是这张图当初的快照)—— 想换个描述重画,改创作页就行,不必
  /// 先重新生成一张。这里只开面板、不传参数:参数由面板发车时现读,免得开着
  /// 面板去创作页改完步数切回来,价格和实际发送都还停在旧值。
  Future<void> _inpaint(BuildContext context, WidgetRef ref) async {
    if (_blockWhileInpainting(context, ref)) return;
    // 模型跟着创作页走,可能正停在 Anima / Krea:那两条 Modal 通道都没有 infill,
    // 让人涂完再报错太晚。面板发车前还有一道同样的拦截(期间可以切去换模型)。
    final model = ref.read(generateProvider).params.model;
    if (isModalModel(model)) {
      hintSnack(
        context,
        '${isKreaModel(model) ? 'Krea 2' : 'Anima'} 模型不支持重绘,请先切回 NovelAI 模型',
        icon: Icons.block,
      );
      return;
    }
    final bytes = await _bytesOf(ref);
    if (!context.mounted) return;
    if (bytes == null) {
      hintSnack(context, '此图无像素数据', icon: Icons.error_outline);
      return;
    }
    ref
        .read(inpaintSessionProvider.notifier)
        .open(imageBytes: bytes, sourceId: result.id);
  }

  /// 放大:弹参数面板 → 按方式分发 NAI 远程调用 → 进度 → 入库。
  /// 本地 ncnn 超分已整条下线,现在三条路全是远程的。
  Future<void> _upscale(BuildContext context, WidgetRef ref) async {
    final bytes = await _bytesOf(ref);
    if (!context.mounted) return;
    if (bytes == null) {
      hintSnack(context, '此图无像素数据', icon: Icons.error_outline);
      return;
    }
    final w = result.width, h = result.height;
    final naiV5Ok = naiV5UpscaleSupportsSize(w, h);
    // 重绘走生成管线。快照只负责提供**提示词与采样参数**,模型跟着创作页
    // 当前选的那个走 —— 重绘是一次新的生成,用哪个模型是用户此刻的选择,
    // 不是这张图当初拿什么出的。倍率表(Max 只有 V5 有)因此也按当前模型算,
    // 而且 _redraw 会把这个模型真的写进请求里,两边不会错位。
    final snapshot = result.hasInput ? await _inputOf(ref) : null;
    if (!context.mounted) return;
    final curModel = ref.read(generateProvider).params.model;
    // 换了模型的快照要按新模型的能力面重新裁一遍(V5 没有 Vibe / 角色参考)
    final redrawInput = snapshot == null
        ? null
        : retargetModel(snapshot, curModel);
    final scales = redrawInput == null || isModalModel(curModel)
        ? const <EnhanceScale>[]
        : enhanceScaleOptions(w, h, curModel);
    // 不可用时把**原因**一起算出来:三种原因差得远,看不见的缺席最难查。
    final redrawWhy = snapshot == null
        ? '这张图没有参数快照,重绘放大用不了(只有本机生成的图带快照)'
        : isModalModel(curModel)
        ? '$curModel 不支持图生图,重绘放大要先切回 NAI 模型'
        : scales.isEmpty
        ? '源图 $w×$h 已超过 NAI 的总像素上限,重绘放不出任何倍率'
        : null;

    // 1. 上次那套参数(不可用的方式/倍率就地回退,免得面板一开就是个死选项)。
    //
    // **await 而不是取 .value**:懒加载的 AsyncNotifier 首读期间 .value 是 null,
    // 那会把「还没读出来」当成「没存过」,于是本次会话第一次开面板永远是默认档
    // —— 用户看到的就是「上次选的没记住」。
    var init = const UpscaleSettings();
    try {
      init = await ref.read(upscaleSettingsProvider.future);
    } catch (_) {} // 读不出来就用默认档,不挡这一次放大
    if ((init.method == UpscaleMethod.naiV5 && !naiV5Ok) ||
        (init.method == UpscaleMethod.redraw && redrawWhy != null)) {
      // 两条路互为兜底:哪条能用就落哪条,别把面板开成一个死选项
      init = init.copyWith(
        method: naiV5Ok ? UpscaleMethod.naiV5 : UpscaleMethod.redraw,
      );
    }
    if (!context.mounted) return;
    if (!scales.contains(init.enhanceScale) && scales.isNotEmpty) {
      init = init.copyWith(enhanceScale: scales.first);
    }

    final picked = await showModalBottomSheet<UpscaleSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UpscalePanel(
        init: init,
        naiV5Enabled: naiV5Ok,
        redrawWhy: redrawWhy,
        redrawScales: scales,
        redrawInput: redrawInput,
        width: w,
        height: h,
      ),
    );
    if (picked == null || !context.mounted) return;
    await ref.read(upscaleSettingsProvider.notifier).set(picked);
    if (!context.mounted) return;
    final method = picked.method;

    // 重绘放大:走生成管线(画布流式预览),不弹放大对话框
    if (method == UpscaleMethod.redraw) {
      await _redraw(context, ref, bytes, picked, redrawInput);
      return;
    }

    // 2. 进度对话框:远程一次性调用没有逐步进度,只走阶段文案 + 不确定动画
    final stage = ValueNotifier<String>('准备…');
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpscaleProgressDialog(method: method, stage: stage),
      ),
    );

    // 3. 执行
    try {
      final r = await upscaleNai(
        ref,
        bytes,
        width: w,
        height: h,
        onStage: (s) => stage.value = s,
      );
      final png = r.png;
      final outW = r.width;
      final outH = r.height;
      // 入库:新条目 + 放大角标,沿用原图 seed/输入参数(快照懒读补齐)
      final input = await _inputOf(ref);
      ref
          .read(galleryProvider.notifier)
          .addResult(
            bytes: png,
            width: outW,
            height: outH,
            seed: result.seed,
            badge: ResultBadge.upscaled,
            input: input,
          );
      unawaited(ref.read(anlasProvider.notifier).refresh());
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        hintSnack(
          context,
          '${method.label}完成 $outW×$outH,已存入图库',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        hintSnack(context, '超分失败: $e', icon: Icons.error_outline);
      }
    } finally {
      stage.dispose();
    }
  }

  /// 重绘放大:img2img 重新生成(走生成管线,结果画布流式 + 自动入库)。
  ///
  /// 数值倍率是**客户端把目标宽高算好再发**;Max ✨ 档相反 —— 发原图尺寸 +
  /// `upscaled_enhance`,由服务端放大到总像素上限,所以这里不动 params 的宽高。
  ///
  /// [input] 是 _upscale 备好的快照:**模型已经换成创作页当前选的那个**。
  /// 别在这儿重新读一遍快照 —— 那样又会退回成「按这张图当初的模型跑」,
  /// 和面板上按当前模型算出来的倍率表对不上。
  Future<void> _redraw(
    BuildContext context,
    WidgetRef ref,
    Uint8List bytes,
    UpscaleSettings cfg,
    GenerateState? input,
  ) async {
    final scale = cfg.enhanceScale;
    if (input == null) {
      hintSnack(context, '缺少参数快照,无法重绘放大', icon: Icons.error_outline);
      return;
    }
    final isMax = scale.factor == null;
    final target = enhanceTargetSize(result.width, result.height, scale);
    final t = isMax
        ? (w: result.width, h: result.height)
        : img2imgResolution(target.w, target.h);
    unawaited(
      ref
          .read(generationProvider.notifier)
          .generate(
            using: input.copyWith(
              img2img: Img2ImgConfig(
                image: bytes,
                strength: cfg.strength,
                noise: cfg.noise,
                upscaledEnhance: isMax,
              ),
              params: input.params.copyWith(width: t.w, height: t.h, seed: ''),
            ),
          ),
    );
    hintSnack(
      context,
      isMax
          ? '开始 Max 重绘 ≈${target.w}×${target.h} · ${input.params.model}'
          : '开始 ${scale.label} 重绘 ${t.w}×${t.h} · ${input.params.model}',
      icon: Icons.auto_fix_high,
    );
  }

  /// 导入:当前图送进导入面板(解析内嵌元数据 / 用作参考),与创作页入口同一面板。
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final bytes = await _bytesOf(ref);
    if (!context.mounted) return;
    if (bytes == null) {
      hintSnack(context, '图片尚未就绪', icon: Icons.hourglass_empty);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        sharedAxisRoute(
          ImportImagePanel(
            bytes: bytes,
            fileName: 'plana_${result.seed}.png',
            displayName: 'plana_${result.seed}',
          ),
        ),
      ),
    );
  }

  /// 点按保存:按默认保存设置处理后存相册(gal;Android 10+ 免权限走 MediaStore)。
  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final bytes = await _bytesOf(ref);
    if (!context.mounted || bytes == null) return;
    try {
      final ok = await Gal.hasAccess() || await Gal.requestAccess();
      if (!ok) {
        if (context.mounted) {
          hintSnack(context, '未获相册权限', icon: Icons.error_outline);
        }
        return;
      }
      final settings = await ref.read(saveSettingsProvider.future);
      final out = await processForSave(bytes, settings);
      await Gal.putImageBytes(out, name: 'plana_${result.seed}');
      if (context.mounted) {
        hintSnack(context, '已保存到相册', icon: Icons.check_circle_outline);
      }
    } on GalException catch (_) {
      if (context.mounted) {
        hintSnack(context, '保存失败', icon: Icons.error_outline);
      }
    } catch (e) {
      if (context.mounted) {
        hintSnack(context, '保存失败: $e', icon: Icons.error_outline);
      }
    }
  }

  /// 长按保存:进保存设置面板(格式/质量/元数据/预估大小,单次或设为默认)。
  Future<void> _openSaveSheet(BuildContext context, WidgetRef ref) async {
    final bytes = await _bytesOf(ref);
    if (!context.mounted) return;
    if (bytes == null) {
      hintSnack(context, '图片尚未就绪', icon: Icons.hourglass_empty);
      return;
    }
    await showSaveSheet(context, bytes: bytes, seed: result.seed);
  }

  /// 按本图参数、换随机种子出一张新图(不改用户当前编辑器状态)。
  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final input = await _inputOf(ref);
    if (!context.mounted) return;
    if (input == null) {
      hintSnack(context, '缺少参数快照,无法重新生成', icon: Icons.error_outline);
      return;
    }
    unawaited(
      ref
          .read(generationProvider.notifier)
          .generate(
            using: input.copyWith(params: input.params.copyWith(seed: '')),
          ),
    );
  }
}

/// 收起/展开的把手。跟动作按钮同一套质感(实色 + 投影),做成横药丸而不是圆 ——
/// 一眼看得出它是这条轨上的控件、又不会被当成第五个动作。
///
/// 箭头指向**按下去会发生什么**(收起时朝上=还能展开,展开时朝下=可以收起)。
/// 拖动本来就能开合,但看不见的手势等于不存在 —— 这颗是那条手势的说明书,
/// 顺带自己也能点。不配文字标签:一个箭头已经说完了,再挂两个字反而与下面
/// 那排动作标签抢读。
class _RailHandle extends StatelessWidget {
  const _RailHandle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      elevation: 1.5,
      shadowColor: scheme.shadow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 28,
          child: AnimatedRotation(
            duration: Motion.medium,
            curve: Motion.standard,
            turns: collapsed ? 0 : .5,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 22,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.onHold,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 按住/松手(true = 按下)。给「对比」这种按着才生效的用。
  final void Function(bool down)? onHold;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final double d = primary ? 58 : 48;
    final Color circleColor = primary
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final Color iconColor = primary ? scheme.onPrimary : scheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: circleColor,
          shape: const CircleBorder(),
          elevation: primary ? 3 : 1.5,
          shadowColor: scheme.shadow,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            // 按住类动作走 highlight 回调:onTapDown/Up 收不到「手指划走」,
            // 划出去之后图就一直糊在那儿了。
            onHighlightChanged: onHold,
            child: SizedBox(
              width: d,
              height: d,
              child: Icon(icon, size: primary ? 27 : 22, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _SeedChip extends StatelessWidget {
  const _SeedChip({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: 1.5,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: '$seed'));
          if (!context.mounted) return;
          hintSnack(context, '已复制种子 $seed', icon: Icons.check);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grain, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Text('$seed', style: mono(context, size: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 放大面板。两条支路各自成段,底部一条全宽 CTA(结果尺寸 + 预估点数)——
/// 与重绘面板同一套「先把参数调好、再按一次开始」的手感,而不是点卡片就走。
///
/// 信息结构对齐 web `MobileUpscaleSheet`:
///  - **超分辨率**:只放大像素,画面内容不变。选处理方式(本地两档 / NAI 传统 /
///    V5 扩散),本地还能选倍率。
///  - **图生图放大**:以更高分辨率重新生成,画面会变。选倍率 + Magnitude 档,
///    强度/噪声两个滑杆可继续微调。
class _UpscalePanel extends ConsumerStatefulWidget {
  const _UpscalePanel({
    required this.init,
    required this.naiV5Enabled,
    required this.redrawWhy,
    required this.redrawScales,
    required this.redrawInput,
    required this.width,
    required this.height,
  });

  final UpscaleSettings init;
  final bool naiV5Enabled;

  /// 图生图那条支路不可用的原因;null = 可用。
  final String? redrawWhy;

  final List<EnhanceScale> redrawScales;

  /// 这张图的参数快照 —— 重绘走它,点数也按它估(null = 不能重绘)。
  final GenerateState? redrawInput;

  final int width;
  final int height;

  @override
  ConsumerState<_UpscalePanel> createState() => _UpscalePanelState();
}

class _UpscalePanelState extends ConsumerState<_UpscalePanel> {
  late UpscaleSettings _s = widget.init;

  /// 超分这条支路现在只剩 V5 一档;尺寸不合格时整条不可选。
  bool get _upscaleOk => widget.naiV5Enabled;

  bool get _isRedraw => _s.method == UpscaleMethod.redraw;

  /// [remember] = 顺手落盘。
  ///
  /// **不等确认**:只有点了 CTA 才存的话,开面板改一下再退出去等于没选过 ——
  /// 下次开又回上上次那档,用户看到的就是「没记住」。离散选择(方式 / 倍率 /
  /// 幅度档)都立刻存;两个滑杆变化太密,留给确认时跟着 picked 一起存。
  void _set(UpscaleSettings next, {bool remember = false}) {
    setState(() => _s = next);
    if (remember) {
      unawaited(ref.read(upscaleSettingsProvider.notifier).set(next));
    }
  }

  void _setMethod(UpscaleMethod m) =>
      _set(_s.copyWith(method: m), remember: true);

  /// 结果尺寸 —— 三条路三种算法,别互相套用(见各自函数的注释)。
  ({int w, int h}) get _target {
    final w = widget.width, h = widget.height;
    return switch (_s.method) {
      UpscaleMethod.redraw => enhanceTargetSize(w, h, _s.enhanceScale),
      UpscaleMethod.naiV5 => naiV5UpscaleTargetSize(w, h),
    };
  }

  /// 预估点数;null = 这条路当前给不出结果(CTA 禁用)。
  ///
  /// 两条路两种算法:V5 扩散按**源图**像素查表;图生图放大走生成公式
  /// (按**结果**尺寸 + 强度折算)。
  int? get _cost => switch (_s.method) {
    UpscaleMethod.naiV5 => naiV5UpscalePrice(widget.width, widget.height),
    UpscaleMethod.redraw => _redrawCost(),
  };

  /// 图生图放大的点数。借 [estimateInpaintCost] —— 它就是「同一套生成公式,
  /// 但像素按发送尺寸算、再按强度折算」,正好是重绘放大要的那个口径;
  /// 快照里的 Vibe / 角色参考附加费也照收(那些确实会跟着一起发出去)。
  int? _redrawCost() {
    final input = widget.redrawInput;
    if (input == null) return null;
    final t = _target;
    return estimateInpaintCost(
      input,
      isOpus: ref.read(anlasProvider).value?.isOpus ?? false,
      sendW: t.w,
      sendH: t.h,
      strength: _s.strength,
      v5Charged: ref.read(v5ChargedProvider),
    );
  }

  /// 超分那一句话说明(含价钱);尺寸不受理时说清为什么。
  String get _upscaleNote => _upscaleOk
      ? 'V5 扩散超分 · 固定 2× · '
            '${naiV5UpscalePrice(widget.width, widget.height)} 点'
      : '源图 ${widget.width}×${widget.height} 超过 3,145,728 像素,超分不受理';

  /// 当前倍率档在干什么。Max 档的尺寸是服务端定的,这里只能给估值。
  String get _scaleNote => switch (_s.enhanceScale) {
    EnhanceScale.x1 => '同尺寸重新生成,只精修细节、不放大',
    EnhanceScale.max => '发原图尺寸,由 NovelAI 放到最大后重绘',
    final s => '以 ${s.label} 分辨率重新生成,画面会变',
  };

  /// Max 档为什么没出现。**看不见的缺席最难查** —— 两个条件各有各的说法,
  /// 不写出来用户只会以为功能坏了。都满足时返回 null(那时它就在列表里)。
  String? get _maxMissingWhy {
    if (widget.redrawScales.contains(EnhanceScale.max)) return null;
    final model = widget.redrawInput?.params.model;
    if (model == null) return null;
    if (!isNai5Model(model)) {
      return 'Max 档只有 V5 有;当前模型是 $model,重绘也按它跑';
    }
    // 官方阈值:源图像素要小于 0.8×上限才提供 Max
    return 'Max 档要求源图小于 2,516,582 像素,'
        '这张 ${widget.width}×${widget.height} 太大了';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final t = _target;
    final cost = _cost;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 抓手由 BottomSheetTheme(showDragHandle: true)统一提供,这里不再自画。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Icon(
                  Icons.photo_size_select_large,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '放大',
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.width}×${widget.height}',
                  style: mono(
                    context,
                    size: 11,
                  ).copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 支路:超分 = 只放大像素;图生图放大 = 重新生成,画面会变
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: const Text('超分辨率'),
                        enabled: _upscaleOk,
                      ),
                      ButtonSegment(
                        value: true,
                        label: const Text('图生图放大'),
                        enabled: widget.redrawWhy == null,
                      ),
                    ],
                    selected: {_isRedraw},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => _setMethod(
                      v.first ? UpscaleMethod.redraw : UpscaleMethod.naiV5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.redrawWhy case final why?) ...[
                    _note(scheme, why),
                    const SizedBox(height: 10),
                  ] else
                    const SizedBox(height: 4),
                  if (_isRedraw)
                    ..._redrawSection(scheme)
                  else
                    ..._upscaleSection(scheme),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _cta(scheme, t, cost),
          ),
        ],
      ),
    );
  }

  // ---- 超分辨率支路:官方下线传统 4× 之后只剩 V5 一档,没什么可选的了 ----

  List<Widget> _upscaleSection(ColorScheme scheme) => [
    _note(scheme, _upscaleNote),
  ];

  // ---- 图生图放大支路:倍率与档位并成一行 ----

  List<Widget> _redrawSection(ColorScheme scheme) {
    final mag = _s.magnitudeIndex;
    return [
      // 两个都只有两三个选项,各占一整行太空 —— 并成一行两个下拉。
      Row(
        children: [
          Expanded(
            child: _dropdown<EnhanceScale>(
              scheme,
              label: '倍率',
              value: _s.enhanceScale,
              items: [
                for (final s in widget.redrawScales) (value: s, text: s.label),
              ],
              onChanged: (v) =>
                  _set(_s.copyWith(enhanceScale: v), remember: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dropdown<int>(
              scheme,
              label: '档位',
              value: mag,
              items: [
                for (var i = 0; i < kMagnitudePresets.length; i++)
                  (value: i, text: '档 ${kMagnitudePresets[i].label}'),
                // 两个滑杆微调过之后就不在任何一档上 —— 列一个占位项,
                // 否则 DropdownButton 的 value 不在 items 里会直接抛。
                if (mag < 0) (value: -1, text: '自定义'),
              ],
              onChanged: (i) {
                if (i < 0) return;
                _set(
                  _s.copyWith(
                    strength: kMagnitudePresets[i].strength,
                    noise: kMagnitudePresets[i].noise,
                  ),
                  remember: true,
                );
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _note(scheme, _scaleNote),
      if (_maxMissingWhy case final why?) ...[
        const SizedBox(height: 3),
        _note(scheme, why),
      ],
      const SizedBox(height: 6),
      ParamSlider(
        label: '强度 Strength',
        help: Help.img2imgStrength,
        value: _s.strength,
        min: kStrengthMin,
        max: kStrengthMax,
        divisions: ((kStrengthMax - kStrengthMin) / 0.05).round(),
        valueText: _s.strength.toStringAsFixed(2),
        dense: true,
        onChanged: (v) => _set(_s.copyWith(strength: v)),
      ),
      ParamSlider(
        label: '噪声 Noise',
        help: Help.img2imgNoise,
        value: _s.noise,
        max: kNoiseMax,
        divisions: (kNoiseMax / 0.01).round(),
        valueText: _s.noise.toStringAsFixed(2),
        dense: true,
        onChanged: (v) => _set(_s.copyWith(noise: v)),
      ),
    ];
  }

  Widget _note(ColorScheme scheme, String text) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(
      text,
      style: context.texts.labelSmall!.copyWith(color: scheme.outline),
    ),
  );

  /// 带前置标签的紧凑下拉(与高级设置里预设那一栏同款外壳)。
  Widget _dropdown<T>(
    ColorScheme scheme, {
    required String label,
    required T value,
    required List<({T value, String text})> items,
    required ValueChanged<T> onChanged,
  }) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    ),
    child: DropdownButton<T>(
      value: value,
      isExpanded: true,
      isDense: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(12),
      style: context.texts.bodyMedium!.copyWith(color: scheme.onSurface),
      items: [
        for (final e in items)
          DropdownMenuItem(
            value: e.value,
            child: Text(e.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        Haptics.selection();
        onChanged(v);
      },
    ),
  );

  /// 全宽 CTA:结果尺寸 + 点数胶囊,与创作页主按钮那颗同一套 —— 要扣点就是
  /// tertiaryContainer 的浅粉(角色计数、灵感「随机」徽章同款),
  /// 免费或算不出时才是中性半透明。
  Widget _cta(ColorScheme scheme, ({int w, int h}) t, int? cost) {
    final paid = cost != null && cost > 0;
    // 底色换了字色就得跟着换到配套那支;中性底那档才走按钮的 onPrimary。
    final fg = paid ? scheme.onTertiaryContainer : scheme.onPrimary;
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      ),
      onPressed: cost == null ? null : () => Navigator.of(context).pop(_s),
      // 整块等比缩,不让任何一段省略号 —— 窄屏 + 四位数点数时两边都装不下。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isRedraw ? Icons.auto_fix_high : Icons.photo_size_select_large,
              size: 18,
            ),
            const SizedBox(width: 7),
            const Text(
              '开始放大',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Text(
              _isRedraw && _s.enhanceScale == EnhanceScale.max
                  ? '≈${t.w}×${t.h}'
                  : '${t.w}×${t.h}',
              style: mono(
                context,
                size: 11,
              ).copyWith(color: scheme.onPrimary.withValues(alpha: .75)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: paid
                    ? scheme.tertiaryContainer
                    : scheme.onPrimary.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.toll, size: 12, color: fg),
                  const SizedBox(width: 3),
                  Text('${cost ?? '—'}', style: _pill(fg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _pill(Color fg) =>
      TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg);
}

/// 超分进度对话框。三条路都是远程一次性调用,拿不到逐步进度 ——
/// 只有阶段文案 + 不确定动画。
class _UpscaleProgressDialog extends StatelessWidget {
  const _UpscaleProgressDialog({required this.method, required this.stage});

  final UpscaleMethod method;
  final ValueNotifier<String> stage;

  IconData get _icon => switch (method) {
    UpscaleMethod.naiV5 => Icons.blur_on,
    UpscaleMethod.redraw => Icons.auto_fix_high,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(_icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            '${method.label} · ${method.badge}',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: stage,
            builder: (_, s, _) => Text(
              s,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

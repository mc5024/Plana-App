import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/image_ops.dart';
import '../../../core/util/image_pick.dart';
import '../../inpaint/inpaint_overlay.dart';
import '../../shell/shell_state.dart';
import '../canvas_state.dart';
import '../generate_state.dart';
import '../models.dart';
import '../nai_request.dart' show inpaintStrengthSupported;
import 'common.dart';
import 'section_card.dart';
import '../../../l10n/l10n.dart';

/// 选图设为图生图底图:解码尺寸 → 64 对齐/像素封顶改写生成分辨率 →
/// 写入状态并展开图生图面板;分辨率有变时提示一声。
/// 图生图卡「选择底图」与操作栏「底图」按钮共用。
Future<void> pickImg2ImgImage(BuildContext context, WidgetRef ref) async {
  final canvasId = ref.read(canvasWorkspaceProvider).activeId;
  final file = await pickImageFile(context);
  if (file == null || !context.mounted) return;
  final bytes = file.bytes;
  final (rw, rh) = await decodeImageSize(bytes); // 解码原始尺寸
  // 选图到解码完之间切走了画布:这张就不设了
  if (!context.mounted ||
      ref.read(canvasWorkspaceProvider).activeId != canvasId) {
    return;
  }
  final res = img2imgResolution(rw, rh); // 64 对齐 / 像素封顶
  final before = ref.read(generateProvider).params;
  ref
      .read(generateProvider.notifier)
      .setImg2ImgImage(image: bytes, width: res.w, height: res.h);
  // 底图会改写生成分辨率;和原来不同就提示一声,免得用户莫名其妙。
  if (before.width != res.w || before.height != res.h) {
    hintSnack(
      context,
      '分辨率已按底图调整为 ${res.w}×${res.h}',
      icon: Icons.aspect_ratio,
    );
  }
}

/// 图生图:选底图(自动匹配分辨率)+ 强度/噪声滑杆 + 移除。
///
/// **带遮罩时这张卡就是重绘卡**:遮罩编辑器只负责产出「底图 + 遮罩」,存进来之后
/// 发车统一交给主生成按钮(对齐官网)。两者互斥 —— 带遮罩的图生图就是重绘,
/// 所以卡里要么摆底图、要么摆遮罩,不会同时。
class Img2ImgCard extends ConsumerStatefulWidget {
  const Img2ImgCard({super.key, this.reorderIndex});

  final int? reorderIndex;

  @override
  ConsumerState<Img2ImgCard> createState() => _Img2ImgCardState();
}

class _Img2ImgCardState extends ConsumerState<Img2ImgCard> {
  Future<void> _onPick() => pickImg2ImgImage(context, ref);

  /// 拿这张底图去涂遮罩(点缩略图进来)。
  ///
  /// 走的是和图库「重绘」同一个编辑器,只是没有图库归属([InpaintSession.sourceId]
  /// 为 null)—— 所以它的产物没有「按住对比」可看,那要有源图在库里才谈得上。
  void _inpaintExternal(Uint8List bytes) {
    ref.read(inpaintSessionProvider.notifier).open(imageBytes: bytes);
    ref.read(shellIndexProvider.notifier).select(kTabGallery);
  }

  /// 回编辑器接着涂。编辑器嵌在图库页里,所以要先切过去。
  ///
  /// 底图给**原图**而不是 [InpaintJob.image] —— 局部重绘存的是裁切区,拿它回去
  /// 只能在那一小块里涂,想把范围挪到别处就没辙了。遮罩本身按 sourceId 从图库
  /// 的蒙版记忆里恢复,所以这里不用传。
  void _reenter(InpaintJob job) {
    ref
        .read(inpaintSessionProvider.notifier)
        .open(
          imageBytes: job.paste?.original ?? job.image,
          sourceId: job.sourceId,
        );
    ref.read(shellIndexProvider.notifier).select(kTabGallery);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generateProvider);
    final notifier = ref.read(generateProvider.notifier);
    final cfg = state.img2img;
    final job = state.inpaint;
    final expanded = state.openPanels.contains(Panel.i2i);
    final hasImage = cfg?.image != null;
    final hasMask = job != null;

    if (hasMask) return _maskBody(state, notifier, job, expanded);

    return SectionCard(
      icon: Icons.image_outlined,
      title: context.l10n.img2img,
      reorderIndex: widget.reorderIndex,
      badge: hasImage ? const CountBadge('1') : null,
      actions: [
        if (hasImage)
          RoundIconBtn(
            Icons.delete_outline,
            tooltip: '移除底图',
            color: context.scheme.error,
            onTap: notifier.disableImg2Img,
          ),
        RoundIconBtn(
          Icons.add,
          tooltip: hasImage ? '更换底图' : '选择底图',
          color: context.scheme.primary,
          onTap: _onPick,
        ),
      ],
      expanded: expanded && hasImage,
      onHeaderTap: () => notifier.togglePanel(Panel.i2i),
      body: !hasImage
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 缩略图整块可点 = 拿这张底图去涂遮罩,和重绘那一态同款,
                    // 省得为「换个玩法」专门去顶上找那颗画笔。
                    SizedBox(
                      width: 90,
                      height: 118,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          StripeThumb(
                            width: 90,
                            height: 118,
                            radius: 12,
                            image: cfg!.image,
                          ),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _inpaintExternal(cfg.image!),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  margin: const EdgeInsets.all(6),
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: context.scheme.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.brush,
                                    size: 15,
                                    color: context.scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          ParamSlider(
                            label: context.l10n.paramStrength,
                            help: Help.img2imgStrength,
                            value: cfg.strength,
                            min: 0.01, // 对齐 web:0 对 img2img 无效
                            max: 0.99,
                            divisions: 98, // step 0.01
                            onChanged: (v) =>
                                notifier.updateImg2Img(strength: v),
                          ),
                          const SizedBox(height: 6),
                          ParamSlider(
                            label: context.l10n.paramNoise,
                            help: Help.img2imgNoise,
                            value: cfg.noise,
                            max: 0.99, // 对齐 web(min 0 可)
                            divisions: 99, // step 0.01
                            onChanged: (v) => notifier.updateImg2Img(noise: v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const InfoNote('底图按当前分辨率裁剪填充。点缩略图可涂遮罩改成重绘。'),
              ],
            ),
    );
  }

  /// 带遮罩的形态:缩略图上叠一层遮罩、一条强度滑杆、一颗移除。
  ///
  /// 这里**不给「更换底图」** —— 遮罩是画在这张底图上的,换了图遮罩就对不上位。
  /// 要换就回图库对新图涂一遍。
  Widget _maskBody(
    GenerateState state,
    GenerateNotifier notifier,
    InpaintJob job,
    bool expanded,
  ) {
    final scheme = context.scheme;
    final model = state.params.model;
    final strengthOk = inpaintStrengthSupported(model);
    return SectionCard(
      icon: Icons.brush_outlined,
      title: context.l10n.inpaint,
      reorderIndex: widget.reorderIndex,
      badge: CountBadge('${state.params.width}×${state.params.height}'),
      actions: [
        RoundIconBtn(
          Icons.delete_outline,
          tooltip: context.l10n.removeMask,
          color: scheme.error,
          onTap: notifier.clearInpaint,
        ),
      ],
      expanded: expanded,
      onHeaderTap: () => notifier.togglePanel(Panel.i2i),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 底图上叠遮罩:遮罩 PNG 是黑底白区,半透明压上去白区正好提亮,
              // 一眼看得出这次要重画的是哪块。整块可点 = 回编辑器接着涂。
              SizedBox(
                width: 90,
                height: 118,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StripeThumb(
                      width: 90,
                      height: 118,
                      radius: 12,
                      image: job.image,
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Opacity(
                        opacity: .55,
                        child: Image.memory(
                          job.mask,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _reenter(job),
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 3),
                              ],
                            ),
                            child: Icon(
                              Icons.brush,
                              size: 15,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LockedParam(
                  hint: strengthOk ? null : '${modelName(model)} 不支持「重绘强度」',
                  child: ParamSlider(
                    label: context.l10n.paramStrength,
                    help: Help.img2imgStrength,
                    value: strengthOk ? job.strength : 1,
                    min: 0.01,
                    max: 1,
                    divisions: 99,
                    onChanged: notifier.updateInpaintStrength,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const InfoNote('遮罩已存好,点下方「生成」开始重绘;点缩略图回编辑器改涂抹范围。'),
        ],
      ),
    );
  }
}

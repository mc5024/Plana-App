/// 「图片显示在对话里」那一块:**一个图框**。在出图时是逐帧预览 + 进度条,出好了是
/// 这条消息最新的那张,右下角浮着一颗「重新生成」。
///
/// 开了这个设置之后用户就不会再切去图库了,所以图库那边有的东西这儿得补齐 ——
/// 逐帧预览、进度、以及不满意时再来一张。少了任何一样,用户还是得切页,
/// 那这个设置就白开了。
///
/// **再出一张不往下追加,就在这个框里换。** 原先每出一张多一格,不满意多点几次,
/// 对话里就堆起一列差不多的图。之前出的都还在图库里,这条消息也照样记着
/// ([AssistantMsg.imageIds]),只是不画。预览帧到之前垫着上一张(压暗),
/// 不闪一下斜纹。
///
/// 图**始终在图库里**,库里删掉的直接不画,不留一格破图 —— 最新那张删了就往前找一张。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../gallery/gallery_state.dart'
    show galleryImageProvider, galleryProvider, galleryThumbProvider;
import '../../gallery/models.dart' show ResultImage;
import '../../generate/gen_jobs.dart' show GenJob;
import '../../generate/generation_controller.dart' show generationProvider;
import '../../generate/widgets/common.dart' show StripeThumb;
import '../../shell/shell_state.dart';
import '../domain/conversation.dart';
import '../application/assistant_controller.dart';
import '../../../l10n/l10n.dart';

/// 单张最高多少。宽度撑满对话区,超过这个高度的竖图按高度回算宽度 ——
/// 不封顶的话一张 832×1216 能吃掉一整屏,往下翻不到按钮。
const _maxH = 340.0;

const _radius = 14.0;

class InlineImages extends ConsumerWidget {
  const InlineImages({super.key, required this.msg});

  final AssistantMsg msg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobId = ref.watch(assistantProvider.select((s) => s.jobs[msg.id]));
    GenJob? job;
    if (jobId != null) {
      for (final j in ref.watch(generationProvider).jobs) {
        if (j.id == jobId) job = j;
      }
    }
    // 这条消息出过的图里,还在库里的最新那张
    ResultImage? latest;
    if (msg.imageIds.isNotEmpty) {
      final all = ref.watch(galleryProvider).results;
      for (final id in msg.imageIds.reversed) {
        latest = all.where((r) => r.id == id).firstOrNull;
        if (latest != null) break;
      }
    }
    final running = job;

    // 开始出图、出完、失败时这一块的高度会变:让它长出来 / 收回去,不一下子顶开。
    // 没东西时也留着这层(零高),否则第一张出现时没有「从零长」的起点。
    return AnimatedSize(
      duration: Motion.medium,
      curve: Motion.emphasized,
      alignment: Alignment.topLeft,
      child: running == null && latest == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LayoutBuilder(
                // 「正在出」和「出好的」在同一个框里交叉淡入。两张尺寸可能不同:
                // 叠在左上角,长短交给外面那层 AnimatedSize,别居中了左右晃一下
                builder: (context, box) => AnimatedSwitcher(
                  duration: Motion.medium,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, ?current],
                  ),
                  child: running != null
                      ? _Running(
                          key: ValueKey('running:${running.id}'),
                          job: running,
                          under: latest,
                          maxW: box.maxWidth,
                        )
                      : _Done(
                          key: ValueKey(latest!.id),
                          msgId: msg.id,
                          result: latest,
                          maxW: box.maxWidth,
                        ),
                ),
              ),
            ),
    );
  }
}

/// 目标尺寸:宽度撑满,竖图按 [_maxH] 回算。
Size _box(int w, int h, double maxW) {
  final aspect = (w > 0 && h > 0) ? w / h : 1.0;
  final width = math.min(maxW, _maxH * aspect);
  return Size(width, width / aspect);
}

/// 图框:描一圈边 + 圆角裁切。
///
/// 对话背景和浅色图片之间没有分界,不描边的话白底图会糊在气泡区里看不出边界。
Widget _frame(BuildContext context, Size size, List<Widget> children) =>
    Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      // 边框自己占 1px,裁切半径要小掉这 1px 才不会在圆角处露出一牙底色
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius - 1),
        child: Stack(fit: StackFit.expand, children: children),
      ),
    );

/// 图的字节。**读原图,不读缩略图**:缩略图只有几百像素宽,在这个尺寸下重开 app 之后
/// 满屏都是糊的(内存里还留着 bytes 的那几张不糊,所以问题只在重启后出现,更难发现)。
/// 原图没读回来之前先垫缩略图,有个东西看总比空着强。
Uint8List? _bytesOf(WidgetRef ref, ResultImage r) =>
    r.bytes ??
    ref.watch(galleryImageProvider(r.id)).value ??
    ref.watch(galleryThumbProvider(r.id)).value;

class _Done extends ConsumerWidget {
  const _Done({
    super.key,
    required this.msgId,
    required this.result,
    required this.maxW,
  });

  final String msgId;
  final ResultImage result;
  final double maxW;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = _box(result.width, result.height, maxW);
    final bytes = _bytesOf(ref, result);
    return GestureDetector(
      // 点开切去图库看大图 —— 放大、超分、存盘那些都在那边。
      onTap: () {
        ref.read(galleryProvider.notifier).select(result.id);
        ref.read(shellIndexProvider.notifier).select(kTabGallery);
      },
      child: _frame(context, size, [
        if (bytes != null)
          _Bitmap(bytes: bytes, size: size)
        else
          StripeThumb(width: size.width, height: size.height, radius: 0),
        // 跑着的时候框里换成了进度,这颗跟着一起不在 —— 同一条消息连投两单,
        // 进度条只跟得住一单。
        Positioned(right: 10, bottom: 10, child: _AgainButton(msgId: msgId)),
      ]),
    );
  }
}

/// 解码尺寸按显示尺寸来。原图是 1216×832 这个量级,一条长对话里几张全尺寸位图
/// 就能把内存吃穿 —— `cacheWidth` 让解码器直接出小图,清晰度按屏幕像素给足即可。
class _Bitmap extends StatelessWidget {
  const _Bitmap({required this.bytes, required this.size});

  final Uint8List bytes;
  final Size size;

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    fit: BoxFit.cover,
    gaplessPlayback: true,
    cacheWidth: (size.width * MediaQuery.devicePixelRatioOf(context)).round(),
  );
}

/// 在跑的那一单:逐帧预览 + 底部细进度条,与图库胶片条同款。
///
/// 预览帧没到的时候:这条消息出过图就垫着上一张(压暗,看得出不是结果),
/// 第一次出图才显斜纹。
class _Running extends ConsumerWidget {
  const _Running({
    super.key,
    required this.job,
    required this.maxW,
    this.under,
  });

  final GenJob job;
  final double maxW;

  /// 这条消息上一张出好的图。
  final ResultImage? under;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final size = _box(job.width, job.height, maxW);
    final preview = job.preview;
    final note = job.note;
    final last = under;
    final lastBytes = preview == null && last != null
        ? _bytesOf(ref, last)
        : null;
    return _frame(context, size, [
      if (preview != null)
        Image.memory(preview, fit: BoxFit.cover, gaplessPlayback: true)
      else if (lastBytes != null) ...[
        _Bitmap(bytes: lastBytes, size: size),
        ColoredBox(color: Colors.black.withValues(alpha: .35)),
      ] else
        StripeThumb(width: size.width, height: size.height, radius: 0),
      // 排队位次、冷启动、限流倒计时 —— 这些只有文字说得清,进度条说不清
      if (note != null && note.isNotEmpty)
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              note,
              style: context.texts.labelSmall!.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SizedBox(
          height: 4,
          child: LinearProgressIndicator(
            value: job.progress, // null = 准备中,走不确定动画
            backgroundColor: Colors.black.withValues(alpha: .25),
            valueColor: AlwaysStoppedAnimation(scheme.primary),
          ),
        ),
      ),
    ]);
  }
}

/// 浮在图右下角的「重新生成」。
///
/// 摆图里而不是图下面:一颗按钮单独占一行,而它跟这张图是绑死的 —— 浮进去
/// 既省一行,也说清楚了「重出的是这张」。底色带半透明,压在深色浅色图上都看得见。
/// 48 见方:它压在一整张可点的图上,点偏了就被带去图库。
class _AgainButton extends ConsumerWidget {
  const _AgainButton({required this.msgId});

  final String msgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surface.withValues(alpha: .88),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 图本体点了是去图库,这颗要吃掉自己的点击,别顺着漏下去
        onTap: () => ref.read(assistantProvider.notifier).generateFrom(msgId),
        child: Tooltip(
          message: context.l10n.regenerate,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.refresh, size: 24, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

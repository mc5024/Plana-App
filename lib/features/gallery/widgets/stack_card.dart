import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../gallery_groups.dart';
import '../models.dart';
import 'result_thumb.dart';
import '../../../l10n/l10n.dart';

/// 堆的封面卡:封面图 + 身后两片露边的「还有更多」+ 名字 + 张数。
///
/// 叠影只在堆里不止一张时画 —— 一张的堆画了叠影是在说谎,而用户点进去就会发现。
///
/// 叠影用**堆里后面几张的真缩略图**,盖一层与底同色的薄纱压暗、往后推。纯色片
/// 也能表达「还有更多」,但露出的那两条边是死的;换成真图之后每一堆的边缘颜色
/// 都不一样,一眼能看出堆与堆的差别。缩略图本来就是懒读 + 有缓存的(见
/// [galleryThumbProvider]),多读两张不构成负担。
///
/// 张数不够时后面那片退回用第 2 张 —— 只露 6px 的一条边,重复看不出来,而让
/// 几何随张数变会使卡片大小参差不齐,那个更难看。
class GalleryStackCard extends StatelessWidget {
  const GalleryStackCard({
    super.key,
    required this.group,
    required this.selecting,
    required this.picked,
    required this.onTap,
    this.isSaveAlbum = false,
    this.onLongPress,
    this.stacked = true,
    this.cover,
    this.emptyIcon = Icons.photo_library_outlined,
    this.coverIcon,
  });

  final GalleryGroup group;
  final bool selecting;

  /// 多选态:这一堆是否**整堆**都已勾选。
  final bool picked;
  final VoidCallback onTap;

  /// 相册首页:这一本是新图保存的相册,封面右上角标一个收件箱图标。
  /// 只是标记、不接点击(点上去照常进相册);切换走长按菜单。
  final bool isSaveAlbum;

  /// 长按(改名 / 删除),参数是封面在屏幕上的矩形,抬起层从这里长出来。
  final void Function(Rect from)? onLongPress;

  /// 画不画身后的叠影。相册卡传 false:一本相册不是「一堆」,平铺一张封面;
  /// 叠影只留给按角色 / 画风分出来的堆。
  final bool stacked;

  /// 相册卡长按设过的封面;null 用堆里第一张(最新那张)。
  final ResultImage? cover;

  /// 没有图时封面上画的图标。
  final IconData emptyIcon;

  /// 固定的图标封面(收藏、回收站):不管有没有图都画它。
  final IconData? coverIcon;

  /// 封面墙所在面板的最低高度:两行半封面卡。相册、图片没几张时面板按内容缩,
  /// 但缩到这里为止。几何与相册首页、选相册面板的网格一致(两侧 12、列距 6、
  /// 行距 12、名字两行 44)。
  static double wallMinHeight(BuildContext context, double width, int cols) {
    const pad = 12.0, gap = 6.0, rowGap = 12.0;
    final cellW = (width - pad * 2 - gap * (cols - 1)) / cols;
    final textH = 44 * MediaQuery.textScalerOf(context).scale(1);
    return 2.5 * (cellW + textH + rowGap);
  }

  /// 每片叠影露出多少。两片,所以封面比整格窄 2 倍这个数。
  /// 6 是「看得出是张照片」和「别把封面挤小」之间的折中。
  static const _peek = 6.0;

  /// 堆里第 [i] 张;不够就 null。
  ResultImage? _at(int i) => i < group.items.length ? group.items[i] : null;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cover = coverIcon != null
        ? null
        : this.cover ?? group.items.firstOrNull;
    final piled = stacked && group.items.length > 1;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              // 封面是卡片左上那块正方形(边框 + 内距共 4),叠影露在它右下。
              final box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return;
              final side = box.size.width - (piled ? _peek * 2 : 0) - 8;
              onLongPress!(
                box.localToGlobal(const Offset(4, 4)) & Size.square(side),
              );
            },
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expanded 而不是 AspectRatio:格高由 childAspectRatio 定死,名字那两行
          // 在大字号下会变高,让图去吸收才不会溢出(溢出在 debug 下是黄条)。
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) {
                final side = math.min(c.maxWidth, c.maxHeight);
                final w = side - (piled ? _peek * 2 : 0);
                return SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    children: [
                      if (piled) ...[
                        _plate(scheme, _peek * 2, w, .62, _at(2) ?? _at(1)),
                        _plate(scheme, _peek, w, .38, _at(1)),
                      ],
                      Positioned(
                        left: 0,
                        top: 0,
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          curve: Motion.standard,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: picked
                                  ? scheme.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(1.5),
                            child: cover == null
                                ? Container(
                                    width: w - 8,
                                    height: w - 8,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      coverIcon ?? emptyIcon,
                                      size: 36,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  )
                                : ResultThumb(
                                    result: cover,
                                    width: w - 8,
                                    height: w - 8,
                                    radius: 10,
                                  ),
                          ),
                        ),
                      ),
                      if (isSaveAlbum && !selecting)
                        Positioned(
                          top: 8,
                          left: w - 34,
                          child: Semantics(
                            label: context.l10n.newImagesSaveHere,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.primary,
                              ),
                              child: Icon(
                                Icons.move_to_inbox,
                                size: 15,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      if (selecting)
                        Positioned(
                          left: 5,
                          top: 5,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: picked
                                  ? scheme.primary
                                  : Colors.black.withValues(alpha: .35),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .9),
                                width: 1.5,
                              ),
                            ),
                            child: picked
                                ? Icon(
                                    Icons.check,
                                    size: 14,
                                    color: scheme.onPrimary,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            group.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyMedium!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            context.l10n.imagesN(group.items.length),
            maxLines: 1,
            style: context.texts.bodySmall!.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }

  /// 一片叠影。[inset] 是相对封面左上角的偏移,越靠后越淡。
  /// 一片叠影。[inset] 是相对封面左上角的偏移,[veil] 是压在图上的薄纱浓度 ——
  /// 越靠后越浓。薄纱取 [ColorScheme.surface]:浅色主题下是提亮、深色下是压暗,
  /// 两边都读作「退到后面去了」,用黑色纱的话浅色主题里会变成一道脏影。
  Widget _plate(
    ColorScheme scheme,
    double inset,
    double side,
    double veil,
    ResultImage? img,
  ) => Positioned(
    left: inset,
    top: inset,
    child: SizedBox(
      width: side,
      height: side,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (img != null)
            ResultThumb(result: img, width: side, height: side, radius: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              // 没图(读不到 / 堆里就一张)时这层就是原来的纯色片
              color: img == null
                  ? scheme.surfaceContainerHighest.withValues(alpha: 1 - veil)
                  : scheme.surface.withValues(alpha: veil),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .55),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

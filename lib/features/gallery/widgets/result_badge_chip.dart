import 'package:flutter/material.dart';

import '../../generate/widgets/common.dart';
import '../models.dart';

/// 缩略图角标(4x / 重绘)—— 语义状态色小药丸,胶片条与网格共用。
class ResultBadgeChip extends StatelessWidget {
  const ResultBadgeChip({super.key, required this.badge, this.maxWidth});

  final ResultBadge badge;

  /// 文字角标宽过它就只画图标。
  final double? maxWidth;

  static const _style = TextStyle(
    fontSize: 10,
    height: 1,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final label = badge.label;
    if (label == null) return const SizedBox.shrink();
    final max = maxWidth;
    final iconOnly =
        max != null && measureText(context, label, _style) + 12 > max;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 2 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: badge.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: iconOnly
          ? Icon(
              switch (badge) {
                ResultBadge.censored => Icons.blur_on,
                ResultBadge.upscaled => Icons.open_in_full,
                _ => Icons.brush,
              },
              size: 10,
              color: Colors.white,
              semanticLabel: label,
            )
          : Text(label, style: _style),
    );
  }
}

/// 缩略图右上角「已存进相册」小圆标,胶片条与网格共用。底色与网格时刻角标同一层黑纱。
class SavedMark extends StatelessWidget {
  const SavedMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: .45),
      ),
      child: Icon(
        Icons.download_done,
        size: size * .7,
        color: Colors.white.withValues(alpha: .92),
      ),
    );
  }
}

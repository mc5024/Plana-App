import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart';
import '../data/suggestions.dart';
import '../../../l10n/l10n.dart';

/// 类型 → 图标 + 颜色(横向态与竖向态共用)
(IconData, Color) suggestionGlyph(BuildContext context, SuggestionKind kind) {
  final pal = context.editor;
  switch (kind) {
    case SuggestionKind.character:
      return (Icons.person, pal.character);
    case SuggestionKind.oc:
      return (Icons.face, pal.oc);
    case SuggestionKind.work:
      return (Icons.auto_stories_rounded, pal.work);
    case SuggestionKind.tag:
      return (Icons.label, context.scheme.onSurfaceVariant);
    case SuggestionKind.artist:
      return (Icons.brush, pal.artist);
  }
}

/// Danbooru 上有对应词条的类型(画风与 OC 为本机灵感库条目,无 Wiki 详情)。
bool canShowWiki(SuggestionKind kind) =>
    kind == SuggestionKind.tag ||
    kind == SuggestionKind.character ||
    kind == SuggestionKind.work;

/// 贴在补全条顶边右侧的连体耳片:显示命中总数,点按或上滑展开形态 B。
/// 与补全条同底色、仅描上/左/右发丝边,定位时下压 1px 盖掉重合的那段顶边线。
class CompletionExpandPill extends StatelessWidget {
  const CompletionExpandPill({
    super.key,
    required this.count,
    required this.onExpand,
    required this.onClose,
  });

  static const double _radius = 12;

  final int count;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    const topRadius = BorderRadius.vertical(top: Radius.circular(_radius));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -120) {
          onExpand();
        } else if (v > 120) {
          onClose();
        }
      },
      child: Tooltip(
        message: context.l10n.expand,
        child: CustomPaint(
          foregroundPainter: _TabEdgePainter(
            color: context.editorDockLine,
            radius: _radius,
          ),
          child: Material(
            color: context.editorDock,
            borderRadius: topRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onExpand,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 112),
                child: SizedBox(
                  height: 31,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 14, 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          context.l10n.all,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$count',
                          style: mono(
                            context,
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 仅描左、上圆角、右三条边,底部敞口与补全条顶边线衔接。
class _TabEdgePainter extends CustomPainter {
  const _TabEdgePainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.0;
    const half = stroke / 2;
    // 止于补全条顶边发丝线上沿,避免半透明线重叠出深色角点。
    final yEnd = (size.height - stroke).clamp(0.0, size.height);
    final r = radius.clamp(0.0, yEnd);
    final path = Path()
      ..moveTo(half, yEnd)
      ..lineTo(half, r + half)
      ..arcToPoint(Offset(r + half, half), radius: Radius.circular(r))
      ..lineTo(size.width - r - half, half)
      ..arcToPoint(
        Offset(size.width - half, r + half),
        radius: Radius.circular(r),
      )
      ..lineTo(size.width - half, yEnd);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_TabEdgePainter old) =>
      old.color != color || old.radius != radius;
}

/// 横向芯片条的行高与行距(补全条与收藏托盘共用,合开时三行等距)。
const double kCompletionRowH = 42;
const double kCompletionRowGap = 5;

/// 横向芯片条里的单枚标签卡(补全条与收藏托盘共用)。
/// 首行仅放标签名,分类图标、译文与引用数收在第二行以压缩横向宽度。
class DockTagChip extends StatelessWidget {
  const DockTagChip({
    super.key,
    required this.icon,
    required this.iconColor,
    this.iconSize = 11,
    required this.title,
    this.count,
    this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final String title;
  final String? count;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final sub = subtitle;
    final hasSub = sub != null && sub.isNotEmpty;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: iconSize, color: iconColor),
                    if (hasSub) ...[
                      const SizedBox(width: 4),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (count != null) ...[
                      SizedBox(width: hasSub ? 5 : 4),
                      Text(
                        count!,
                        style: mono(context, size: 9.5, color: scheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 形态 A · 默认横向态:吸在键盘正上方。
/// 自适应 1+1 —— 标签行常驻,实体行(画师/OC/角色/作品)命中时滑入。
/// 上滑 / 点顶边连体耳片 → 展开为形态 B;下滑 → 关闭补全条;长按支持 Wiki 的芯片弹出详情。
/// 内容三态(结果行 / 翻译中 / 空态)之间走高度 + 淡入过渡。
class CompletionBar extends StatelessWidget {
  const CompletionBar({
    super.key,
    required this.query,
    required this.result,
    this.loading = false,
    this.translating = false,
    required this.onPick,
    this.onLongPress,
    required this.onAddRaw,
    required this.onExpand,
    required this.onClose,
  });

  final String query;
  final SuggestResult result;

  /// 查询进行中(结果尚未到)
  final bool loading;

  /// 「翻译为英文」LLM 在途:整条切「翻译中…」行(结果行藏起,防重复点)
  final bool translating;

  final void Function(Suggestion) onPick;

  /// 长按支持详情弹窗的芯片(标签 / 角色 / 作品)时触发。
  final void Function(Suggestion)? onLongPress;

  /// 无匹配时把已输入文本直接加为新标签
  final VoidCallback onAddRaw;

  /// 上滑 → 展开形态 B
  final VoidCallback onExpand;

  /// 下滑 → 关闭补全条
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    // 自有库(画师串 / OC)排在上游结果之前,与形态 B 的分组顺序保持一致。
    final entities = [
      ...result.artists,
      ...result.ocs,
      ...result.characters,
      ...result.works,
    ];

    return GestureDetector(
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -120) {
          onExpand();
        } else if (v > 120) {
          onClose();
        }
      },
      child: Material(
        color: context.editorDock,
        shape: Border(top: BorderSide(color: context.editorDockLine)),
        child: AnimatedSize(
          duration: Motion.medium,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Motion.fast,
            child: KeyedSubtree(
              key: ValueKey(_bodyKey),
              child: _body(context, entities),
            ),
          ),
        ),
      ),
    );
  }

  /// 三态互切要过动画,同态内更新(打字刷新结果)原地换,不闪。
  String get _bodyKey => translating
      ? 'translating'
      : result.isEmpty
      ? (loading ? 'loading' : 'empty')
      : 'rows';

  Widget _body(BuildContext context, List<Suggestion> entities) {
    if (translating) return _busyHint(context, context.l10n.translating);
    if (result.isEmpty) {
      return loading
          ? _busyHint(context, context.l10n.querying(query))
          : _emptyHint(context);
    }
    // 底边贴着 EditorBottomBar 顶部的 6dp 内边距,不重复垫底以免双倍间距
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: entities.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: EdgeInsets.only(
                      bottom: result.tags.isEmpty ? 0 : kCompletionRowGap,
                    ),
                    child: _row(context, entities),
                  ),
          ),
          _row(context, result.tags),
        ],
      ),
    );
  }

  Widget _emptyHint(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onAddRaw,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            Icon(Icons.add, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.noMatchAddTag(query),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _busyHint(BuildContext context, String label) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 5),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, List<Suggestion> items) {
    if (items.isEmpty) return const SizedBox(width: double.infinity);
    return SizedBox(
      height: kCompletionRowH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => _chip(context, items[i]),
      ),
    );
  }

  /// chip 副标题。OC 写来源(「本地库」/ 公共库作者);画师串写类型名 ——
  /// 横向态没有分节标题,光靠图标不好认;角色带作品来源;其余用译文。
  ///
  /// 译文走 [transOf] 而非 `s.trans`:D 站来的行自带译名只有 wiki 那一路,
  /// 反查缓存(离线词库 / 共享翻译库 / LLM 回填)里的得现查。
  String? _subtitle(Suggestion s) {
    switch (s.kind) {
      case SuggestionKind.oc:
        return s.source;
      case SuggestionKind.artist:
        return l10nNow.sectionStyle;
      case SuggestionKind.character:
        final t = transOf(s);
        if (t == null || t.isEmpty) return s.source;
        return s.source != null ? '$t · ${s.source}' : t;
      case SuggestionKind.work:
      case SuggestionKind.tag:
        return transOf(s);
    }
  }

  Widget _chip(BuildContext context, Suggestion s) {
    final (icon, iconColor) = suggestionGlyph(context, s.kind);
    return DockTagChip(
      icon: icon,
      iconColor: iconColor,
      title: s.text,
      count: formatCount(s.count),
      subtitle: _subtitle(s),
      onTap: () => onPick(s),
      onLongPress: onLongPress != null && canShowWiki(s.kind)
          ? () => onLongPress!(s)
          : null,
    );
  }
}

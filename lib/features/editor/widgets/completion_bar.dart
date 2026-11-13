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
      return (Icons.casino, pal.work);
    case SuggestionKind.tag:
      return (Icons.label, context.scheme.onSurfaceVariant);
    case SuggestionKind.artist:
      return (Icons.brush, pal.artist);
  }
}

/// 抓手(横向态的上拉、竖向态的下收共用)。
///
/// 原来是一枚 `outline` 色的裸箭头,压在 surfaceContainer 上几乎看不出是个能点的
/// 东西 —— 而横向态那枚是**唯一**的展开入口(另一条路是盲上滑)。加个胶囊底
/// 把它托起来:形状本身就在说「这儿可以拉」。
///
/// 触摸区比胶囊大一圈:胶囊管看得见,外面那圈管按得着。
class CompletionGrip extends StatelessWidget {
  const CompletionGrip({
    super.key,
    required this.icon,
    required this.onTap,
    this.onDragEnd,
  });

  final IconData icon;
  final VoidCallback onTap;
  final void Function(DragEndDetails)? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: onDragEnd,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Container(
            width: 64,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 形态 A · 默认横向态:吸在键盘正上方。
/// 自适应 1+1 —— 标签行常驻,实体行(角色/OC/作品)仅命中时滑入。
/// 上滑 / 点把手 → 展开为形态 B。
/// 内容三态(结果行 / 翻译中 / 空态)之间走高度 + 淡入过渡。
class CompletionBar extends StatelessWidget {
  const CompletionBar({
    super.key,
    required this.query,
    required this.result,
    this.loading = false,
    this.translating = false,
    required this.onPick,
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

  /// 无匹配时把已输入文本直接加为新标签
  final VoidCallback onAddRaw;

  /// 上滑 / 点抓手 → 展开形态 B
  final VoidCallback onExpand;

  /// 下滑 → 关闭补全条
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    // 自有库(画师串 / OC)排在上游结果之前。
    //
    // 这一行是**横向滚动**的,手机上一屏就露两三个 —— 谁排在前面谁才算“提示”。
    // 而角色·作品退役本地库、全量改走上游之后条数明显变多(autocomplete 一次
    // 12 条、语义搜词不设上限),把 OC 挤出了屏幕:用户打自己 OC 的名字,得往右滑
    // 过一串 D 站角色才看得到。自有库条数少(各 limit 5)、匹配精确,而且会去打
    // 那个名字本来就是冲它来的,理应先露面;上游那些是补充。OC 里本地库的
    // 又排在公共库前面(引擎给的就是这个顺序)。
    //
    // 形态 B(展开面板)的分组顺序同理,两边保持一致。
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
        // 圆角顶 + 一圈发丝线:左右两条压在屏幕边上看不见,实际读到的
        // 就是顺着圆角走的上沿(和词条栏那条同一副写法)。
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: context.editorDockLine),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 把手:点一下或往上拉都展开
              CompletionGrip(
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: onExpand,
              ),
              AnimatedSize(
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
            ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 实体行(画师/角色/OC/作品)命中时才滑入,占上;标签行常驻在下。
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: entities.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: _row(context, entities),
                ),
        ),
        _row(context, result.tags),
      ],
    );
  }

  Widget _emptyHint(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onAddRaw,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
      height: 42,
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
    final scheme = context.scheme;
    final (icon, iconColor) = suggestionGlyph(context, s.kind);
    final count = formatCount(s.count);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onPick(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: iconColor),
                  const SizedBox(width: 5),
                  Text(
                    s.text,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      count,
                      style: mono(context, size: 9.5, color: scheme.outline),
                    ),
                  ],
                ],
              ),
              if (_subtitle(s) case final String sub when sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    sub,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

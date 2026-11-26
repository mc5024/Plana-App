import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/net/remote_image.dart';
import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../core/util/haptics.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../data/suggestions.dart';
import '../data/tag_completion.dart';
import '../data/tag_translation_service.dart';
import 'completion_bar.dart' show canShowWiki, suggestionGlyph;
import '../../../l10n/l10n.dart';

/// 补全条目的副标题(译文 / 来源),展开列表与详情弹窗共用。
String? suggestionSubtitle(Suggestion s) {
  switch (s.kind) {
    case SuggestionKind.character:
      return [
        transOf(s),
        s.source,
      ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    case SuggestionKind.work:
      return transOf(s);
    case SuggestionKind.oc:
      return s.source;
    case SuggestionKind.tag:
      return transOf(s);
    case SuggestionKind.artist:
      return s.trans;
  }
}

/// 弹出标签 / 角色 / 作品的居中详情弹窗(附图轮播 + Wiki 摘要/别名 + 外链 + 使用/重抽)。
/// [showUse] 为 false 时不展示「使用」按钮(如权重面板查看已有标签)。
/// 点「使用」时返回选中的条目,其余关闭路径返回 null。
Future<Suggestion?> showSuggestionWikiDialog(
  BuildContext context, {
  required Suggestion suggestion,
  required Map<String, WikiPreview> cache,
  Future<Suggestion?> Function(Suggestion current)? onReroll,
  bool showUse = true,
}) => showDialog<Suggestion>(
  context: context,
  builder: (ctx) => Theme(
    data: editorTheme(ctx),
    child: _WikiDialog(
      suggestion: suggestion,
      subtitleOf: suggestionSubtitle,
      cache: cache,
      onReroll: onReroll,
      showUse: showUse,
    ),
  ),
);

/// 形态 B · 展开态:分类竖向列表(键盘收起,腾出纵向空间)。
/// - 顶部抓手 + 查询标题/项数 + 排序胶囊 + 收起钮
/// - 命中 ≥2 个分类时显示横向筛选胶囊,选「全部」时保留轻量分节标
/// - 每行:命中高亮的词名/译文 · 热度 · ⓘ 弹窗看 Wiki(长按行亦可;作品行另附骰子抽角色)· `+` 连续插入
/// - ⓘ 给标签 / 角色 / 作品:画风与 OC 为本机灵感库条目,无 Danbooru 词条
class CompletionPanel extends ConsumerStatefulWidget {
  const CompletionPanel({
    super.key,
    required this.query,
    required this.result,
    required this.maxHeight,
    this.wikiCache,
    required this.onPick,
    required this.onInsert,
    required this.onCollapse,
  });

  final String query;
  final SuggestResult result;
  final double maxHeight;

  /// 与页面共享的 Wiki 会话缓存;未传时本弹层自建。
  final Map<String, WikiPreview>? wikiCache;

  /// 行主体点按:替换光标处半词并收起(交给页面)
  final void Function(Suggestion) onPick;

  /// `+` 连续插入:追加为新标签,面板保持展开
  final void Function(Suggestion) onInsert;

  /// 下滑 / 抓手 / 收起钮:收起回形态 A 并唤起键盘
  final VoidCallback onCollapse;

  @override
  ConsumerState<CompletionPanel> createState() => _CompletionPanelState();
}

class _CompletionPanelState extends ConsumerState<CompletionPanel> {
  // 排序:true=热度 / false=字母,跟随偏好持久化。
  late bool _byHeat = ref.read(uiPrefsProvider).completionByHeat;
  final ScrollController _scroll = ScrollController();

  /// 当前筛选分类;null 表示全部。
  SuggestionKind? _filter;

  /// 首次切换分类时锁定的弹层高度(取「全部」态渲染高度),防止切到少项分类时弹层塌缩跳动。
  double? _lockedHeight;

  /// 本次展开会话里通过 `+` 连续插入过的条目次数字典。
  final Map<String, int> _inserted = {};

  /// 本次会话内已成功拉取的 Wiki 预览缓存(失败不缓存,允许再点重试)。
  late final Map<String, WikiPreview> _wikiCache = widget.wikiCache ?? {};
  final Set<String> _dicing = {}; // 正在随机抽角色的作品

  /// 后端翻译通道:译文异步回填到货时触发本弹层刷新。
  late final TagTranslationService _transSvc;

  @override
  void initState() {
    super.initState();
    _transSvc = ref.read(tagTranslationServiceProvider)..addListener(_onTrans);
  }

  @override
  void didUpdateWidget(CompletionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxHeight != widget.maxHeight) {
      _lockedHeight = null;
    }
  }

  @override
  void dispose() {
    _transSvc.removeListener(_onTrans);
    _scroll.dispose();
    super.dispose();
  }

  void _onTrans() {
    if (mounted) setState(() {});
  }

  String _insertKey(Suggestion s) => '${s.kind.name}:${s.text}';

  /// 热度 / 字母只在组内排:本地库的 OC 始终在公共库前面(同 completion_bar)。
  List<Suggestion> _sorted(List<Suggestion> xs) {
    int cmp(Suggestion a, Suggestion b) => _byHeat
        ? b.count.compareTo(a.count)
        : a.text.toLowerCase().compareTo(b.text.toLowerCase());
    return [
      ...xs.where((s) => s.local).toList()..sort(cmp),
      ...xs.where((s) => !s.local).toList()..sort(cmp),
    ];
  }

  void _selectFilter(SuggestionKind? kind) {
    final next = _filter == kind ? null : kind;
    if (next == _filter) return;
    Haptics.selection();
    // 首次离开「全部」态时锁住当前弹层高度,保证后续切分类顶栏与胶囊不动。
    if (_lockedHeight == null) {
      final h = context.size?.height;
      if (h != null && h > 0) {
        _lockedHeight = h.clamp(0.0, widget.maxHeight);
      }
    }
    setState(() => _filter = next);
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.jumpTo(0);
    }
  }

  void _handleInsert(Suggestion s) {
    widget.onInsert(s);
    final key = _insertKey(s);
    setState(() => _inserted[key] = (_inserted[key] ?? 0) + 1);
  }

  /// 按作品随机抽取一名角色并封装成可展示详情的建议项。
  Future<Suggestion?> _rollCharacter(Suggestion work, {String? exclude}) async {
    final pick = await ref
        .read(tagCompletionProvider)
        .randomCharacterOf(work.text, exclude: exclude);
    if (pick == null) return null;
    final workName = transOf(work);
    return Suggestion(
      text: pick,
      kind: SuggestionKind.character,
      trans: translationOf(pick),
      source: (workName != null && workName.isNotEmpty) ? workName : work.text,
      count: countOf(pick) ?? 0,
    );
  }

  /// 居中词典弹窗查看 Wiki 摘要、别名与外链;点「使用」后将当前条目落地到编辑器。
  Future<void> _openWikiDialog(
    Suggestion s, {
    Future<Suggestion?> Function(Suggestion current)? onReroll,
  }) async {
    final picked = await showSuggestionWikiDialog(
      context,
      suggestion: s,
      cache: _wikiCache,
      onReroll: onReroll,
    );
    if (!mounted || picked == null) return;
    widget.onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    // 自有库(画师 / OC)在前,上游角色 / 作品 / 标签在后,与横向条一致。
    final allSections = <(SuggestionKind, String, List<Suggestion>)>[
      (SuggestionKind.artist, context.l10n.kindArtist, widget.result.artists),
      (SuggestionKind.oc, 'OC', widget.result.ocs),
      (
        SuggestionKind.character,
        context.l10n.characters,
        widget.result.characters,
      ),
      (SuggestionKind.work, context.l10n.kindWork, widget.result.works),
      (SuggestionKind.tag, context.l10n.kindTag, widget.result.tags),
    ].where((e) => e.$3.isNotEmpty).toList();

    final multiKind = allSections.length >= 2;
    final activeFilter =
        multiKind && allSections.any((e) => e.$1 == _filter) ? _filter : null;
    final visibleSections = activeFilter == null
        ? allSections
        : allSections.where((e) => e.$1 == activeFilter).toList();

    final rows = <Widget>[];
    for (var si = 0; si < visibleSections.length; si++) {
      final (kind, label, raw) = visibleSections[si];
      final items = _sorted(raw);
      // 仅在多分类且看「全部」时显示轻量分节标;单分类视图直接平铺列表。
      if (multiKind && activeFilter == null) {
        rows.add(_sectionHeader(kind, label, items.length, first: si == 0));
      }
      for (var i = 0; i < items.length; i++) {
        rows.add(_row(items[i], showDivider: i < items.length - 1));
      }
    }

    final locked = _lockedHeight != null;
    return Material(
      color: context.raisedFill(scheme.surfaceContainerLow),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: locked
            ? BoxConstraints.tightFor(height: _lockedHeight)
            : BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: locked ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _handle(),
            _header(),
            if (multiKind) _filterBar(allSections, activeFilter),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: .35),
            ),
            Flexible(
              fit: locked ? FlexFit.tight : FlexFit.loose,
              child: ListView(
                controller: _scroll,
                shrinkWrap: !locked,
                padding: EdgeInsets.only(
                  top: multiKind && activeFilter == null ? 2 : 4,
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
                ),
                children: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 抓手 / 头部 / 分类筛选 ----

  /// 顶部抓手条:仅响应轻点收起,下拉手势交给底部弹层原生跟手处理。
  Widget _handle() {
    final scheme = context.scheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onCollapse,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final scheme = context.scheme;
    final q = widget.query.trim();
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final colon = isZh ? '：' : ': ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    q.isNotEmpty ? q : context.l10n.completionResults,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.itemsCount(widget.result.total),
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 尺寸与下方分组筛选胶囊对齐(高 30,左右内衬 11,同字号)。
          SizedBox(
            height: 30,
            child: Material(
              color: scheme.surfaceContainerHighest,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Haptics.selection();
                  ref
                      .read(uiPrefsProvider.notifier)
                      .patch((p) => p.copyWith(completionByHeat: !_byHeat));
                  setState(() => _byHeat = !_byHeat);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Center(
                    child: Text.rich(
                      TextSpan(
                        style: context.texts.labelMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                        children: [
                          TextSpan(text: '${context.l10n.sort}$colon'),
                          TextSpan(
                            text: _byHeat ? context.l10n.byHeat : 'A–Z',
                            style: TextStyle(color: scheme.onSurface),
                          ),
                        ],
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.collapse,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: widget.onCollapse,
          ),
        ],
      ),
    );
  }

  Widget _filterBar(
    List<(SuggestionKind, String, List<Suggestion>)> sections,
    SuggestionKind? active,
  ) {
    final scheme = context.scheme;
    Widget pill({
      required String label,
      required int count,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
      Color? iconColor,
    }) {
      final bg = selected
          ? context.selectedFill
          : scheme.surfaceContainerHighest;
      final fg = selected ? context.onSelectedFill : scheme.onSurfaceVariant;
      final countColor = selected
          ? context.onSelectedFill.withValues(alpha: .82)
          : scheme.outline;
      return Material(
        color: bg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13.5, color: selected ? fg : iconColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: context.texts.labelMedium!.copyWith(
                    color: selected ? fg : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: mono(
                    context,
                    size: 11,
                    weight: FontWeight.w600,
                    color: countColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        children: [
          pill(
            label: context.l10n.all,
            count: widget.result.total,
            selected: active == null,
            onTap: () => _selectFilter(null),
          ),
          for (final (kind, label, items) in sections) ...[
            const SizedBox(width: 6),
            Builder(
              builder: (context) {
                final (icon, color) = suggestionGlyph(context, kind);
                return pill(
                  label: label,
                  count: items.length,
                  selected: active == kind,
                  icon: icon,
                  iconColor: color,
                  onTap: () => _selectFilter(kind),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ---- 分节头 / 行 ----

  Widget _sectionHeader(
    SuggestionKind kind,
    String label,
    int n, {
    required bool first,
  }) {
    final scheme = context.scheme;
    final (icon, color) = suggestionGlyph(context, kind);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, first ? 8 : 14, 20, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.texts.labelMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text('$n', style: mono(context, size: 11, color: scheme.outline)),
        ],
      ),
    );
  }

  Widget _row(Suggestion s, {required bool showDivider}) {
    final scheme = context.scheme;
    final isWork = s.kind == SuggestionKind.work;
    final canWiki = canShowWiki(s.kind);
    final subtitle = suggestionSubtitle(s);
    final count = isWork ? null : formatCount(s.count);
    final added = _inserted[_insertKey(s)] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => widget.onPick(s),
          onLongPress: canWiki
              ? () {
                  Haptics.selection();
                  _openWikiDialog(s);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 9, 14, 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _highlighted(
                        s.text,
                        widget.query,
                        context.texts.bodyMedium!.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                        scheme.primary,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: _highlighted(
                            subtitle,
                            widget.query,
                            context.texts.bodySmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            scheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    count,
                    style: mono(context, size: 11.5, color: scheme.outline),
                  ),
                ],
                const SizedBox(width: 8),
                if (isWork) ...[
                  _diceBtn(s),
                  const SizedBox(width: 4),
                ],
                if (canWiki) ...[
                  _infoBtn(s),
                  const SizedBox(width: 6),
                ],
                _plusBtn(s, added: added),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 20,
            endIndent: 14,
            color: scheme.outlineVariant.withValues(alpha: .32),
          ),
      ],
    );
  }

  /// 命中子串高亮(忽略大小写,且把 `_` 与空格视为等价)。
  Widget _highlighted(String text, String query, TextStyle base, Color accent) {
    final q = query.trim().toLowerCase().replaceAll('_', ' ');
    if (q.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final normalized = text.toLowerCase().replaceAll('_', ' ');
    final idx = normalized.indexOf(q);
    if (idx < 0 || idx + q.length > text.length) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: base.copyWith(color: accent, fontWeight: FontWeight.w700),
          ),
          if (idx + q.length < text.length)
            TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// ⓘ Wiki 词典卡入口(标签 / 角色 / 作品行)。
  Widget _infoBtn(Suggestion s) {
    final scheme = context.scheme;
    return _circleBtn(
      icon: Icons.info_outline_rounded,
      bg: Colors.transparent,
      fg: scheme.onSurfaceVariant,
      onTap: () => _openWikiDialog(s),
    );
  }

  /// 作品行:随机抽一名该作品下的角色并弹出详情弹窗(可在弹窗内重新抽取或使用)。
  Widget _diceBtn(Suggestion s) {
    final color = context.editor.work;
    final busy = _dicing.contains(s.text);
    return _circleBtn(
      icon: Icons.casino_outlined,
      bg: Colors.transparent,
      fg: color,
      busy: busy,
      onTap: () async {
        if (busy) return;
        setState(() => _dicing.add(s.text));
        final rolled = await _rollCharacter(s);
        if (!mounted) return;
        setState(() => _dicing.remove(s.text));
        if (rolled == null) {
          hintSnack(
            context,
            context.l10n.noCharacters,
            icon: Icons.info_outline,
          );
          return;
        }
        await _openWikiDialog(
          rolled,
          onReroll: (cur) => _rollCharacter(s, exclude: cur.text),
        );
      },
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, size: 21, color: fg),
        ),
      ),
    );
  }

  /// `+` 连续插入:常态为凹槽灰圆钮,点过后切换为主色已插反馈(仍可继续点击追加)。
  Widget _plusBtn(Suggestion s, {required int added}) {
    final scheme = context.scheme;
    final done = added > 0;
    final bg = done ? context.selectedFill : scheme.surfaceContainerHighest;
    final fg = done ? context.onSelectedFill : scheme.onSurface;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleInsert(s),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: added >= 2
                ? Text(
                    '+$added',
                    style: mono(
                      context,
                      size: 12,
                      weight: FontWeight.w700,
                      color: fg,
                    ),
                  )
                : Icon(
                    done ? Icons.check_rounded : Icons.add_rounded,
                    size: 22,
                    color: fg,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 居中词典弹窗:两段式加载 Wiki(先英文摘要/别名,再异步补中文),可直达外链、重抽(随机模式)或使用。
class _WikiDialog extends ConsumerStatefulWidget {
  const _WikiDialog({
    required this.suggestion,
    required this.subtitleOf,
    required this.cache,
    this.onReroll,
    this.showUse = true,
  });

  final Suggestion suggestion;
  final String? Function(Suggestion) subtitleOf;
  final Map<String, WikiPreview> cache;
  final Future<Suggestion?> Function(Suggestion current)? onReroll;
  final bool showUse;

  @override
  ConsumerState<_WikiDialog> createState() => _WikiDialogState();
}

class _WikiDialogState extends ConsumerState<_WikiDialog> {
  late Suggestion _current = widget.suggestion;
  WikiPreview? _wiki;
  bool _loading = false;
  bool _rerolling = false;
  int _loadGen = 0;

  final PageController _imgPager = PageController();
  List<String> _images = const [];
  bool _imagesLoading = false;
  bool _safebooruTried = false;
  int _imgPage = 0;

  @override
  void initState() {
    super.initState();
    final gen = _prepareWikiFor(_current);
    if (gen != null) unawaited(_fetchWiki(_current.text, gen));
  }

  @override
  void dispose() {
    _imgPager.dispose();
    super.dispose();
  }

  /// 同步重置当前词条的 Wiki 与附图展示态;需要发网络请求时返回本次加载序号。
  int? _prepareWikiFor(Suggestion target) {
    final gen = ++_loadGen;
    _wiki = widget.cache[metaKey(target.text)];
    final cachedImgs = _wiki?.images ?? const <String>[];
    _images = cachedImgs;
    _imgPage = 0;
    _safebooruTried = false;
    if (_imgPager.hasClients) _imgPager.jumpToPage(0);
    final needSummary = _wiki == null;
    final needZh = _wiki != null && !(_wiki!.summaryZh?.isNotEmpty ?? false);
    final needImgs = cachedImgs.isEmpty;
    _loading = needSummary;
    _imagesLoading = needImgs;
    return (needSummary || needZh || needImgs) ? gen : null;
  }

  Future<void> _fetchWiki(String tag, int gen) async {
    final tc = ref.read(tagCompletionProvider);
    final key = metaKey(tag);
    var w = _wiki;
    if (w == null) {
      w = await tc.fetchWiki(tag);
      if (!mounted || gen != _loadGen) return;
      final imgs = w?.images ?? const <String>[];
      setState(() {
        _loading = false;
        if (w != null) {
          _wiki = w;
          widget.cache[key] = w;
        }
        if (imgs.isNotEmpty) {
          _images = imgs;
          _imagesLoading = false;
        }
      });
    }
    if (_images.isEmpty) {
      unawaited(_fallbackToSafebooru(tag, gen));
    }
    if (w == null || (w.summaryZh?.isNotEmpty ?? false)) return;
    final zh = await tc.fetchWikiZh(tag);
    if (!mounted || gen != _loadGen || zh == null || zh.isEmpty) return;
    final base = _wiki ?? w;
    final merged = base.copyWith(summaryZh: zh);
    widget.cache[key] = merged;
    setState(() => _wiki = merged);
  }

  /// Danbooru 无例图或图片直连失败(如 403)时自动回落 Safebooru 高分安全图。
  Future<void> _fallbackToSafebooru(String tag, int gen) async {
    if (_safebooruTried) return;
    _safebooruTried = true;
    if (mounted && gen == _loadGen && !_imagesLoading) {
      setState(() => _imagesLoading = true);
    }
    final urls = await ref
        .read(tagCompletionProvider)
        .fetchSafebooruImages(tag, limit: 3);
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _images = urls;
      _imgPage = 0;
      _imagesLoading = false;
      if (urls.isNotEmpty) {
        final cur = _wiki ?? WikiPreview(title: tag);
        final updated = cur.copyWith(images: urls);
        _wiki = updated;
        widget.cache[metaKey(tag)] = updated;
      }
    });
    if (_imgPager.hasClients) _imgPager.jumpToPage(0);
  }

  void _onImageError(String url, int gen) {
    if (!mounted || gen != _loadGen) return;
    if (!_safebooruTried) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gen == _loadGen) {
          unawaited(_fallbackToSafebooru(_current.text, gen));
        }
      });
      return;
    }
    // 兜底图也加载失败时从列表移除,全部失败后自动收起图片区不留破图。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _loadGen) return;
      if (!_images.contains(url)) return;
      final rest = [
        for (final u in _images)
          if (u != url) u,
      ];
      setState(() {
        _images = rest;
        if (_imgPage >= rest.length) {
          _imgPage = rest.isEmpty ? 0 : rest.length - 1;
        }
      });
    });
  }

  void _openFullImage(int initialIndex) {
    if (_images.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .88),
      builder: (ctx) => _FullImageDialog(
        images: _images,
        initialIndex: initialIndex.clamp(0, _images.length - 1),
      ),
    );
  }

  Future<void> _reroll() async {
    final cb = widget.onReroll;
    if (cb == null || _rerolling) return;
    Haptics.selection();
    setState(() => _rerolling = true);
    final next = await cb(_current);
    if (!mounted) return;
    int? gen;
    setState(() {
      _rerolling = false;
      if (next != null) {
        _current = next;
        gen = _prepareWikiFor(next);
      }
    });
    if (next != null && gen != null) {
      unawaited(_fetchWiki(next.text, gen!));
    }
  }

  Future<void> _openWiki() async {
    final tag = _current.text.trim().replaceAll(' ', '_');
    final uri = Uri.https('danbooru.donmai.us', '/wiki_pages/$tag');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      hintSnack(
        context,
        context.l10n.cantOpenBrowser,
        icon: Icons.error_outline,
      );
    }
  }

  void _copyWiki() {
    final url = danbooruWikiUrl(_current.text);
    Clipboard.setData(ClipboardData(text: url));
    Haptics.selection();
    hintSnack(context, context.l10n.wikiLinkCopied(url), icon: Icons.check);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final s = _current;
    final subtitle = widget.subtitleOf(s);
    final (icon, iconColor) = suggestionGlyph(context, s.kind);
    final count = formatCount(s.count);
    final wiki = _wiki;

    String body;
    if (wiki != null && wiki.hasText) {
      body = (wiki.summaryZh != null && wiki.summaryZh!.isNotEmpty)
          ? wiki.summaryZh!
          : (wiki.summary ?? '');
    } else if (_loading) {
      body = '';
    } else {
      body = subtitle ?? '';
      if (body.isEmpty) body = context.l10n.wikiMissing;
    }
    final other = wiki?.otherNames ?? const <String>[];
    final subParts = [
      if (subtitle != null && subtitle.isNotEmpty) subtitle,
      ?count,
    ];

    return Dialog(
      backgroundColor: context.raisedFill(scheme.surfaceContainerLow),
      elevation: context.skin.float ? 0 : 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: context.skin.edge != null
            ? BorderSide(color: context.skin.edge!)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(icon, size: 17, color: iconColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleMedium!.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (subParts.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subParts.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodySmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: .35),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSize(
                      duration: Motion.fast,
                      curve: Motion.emphasized,
                      alignment: Alignment.topCenter,
                      child: (_imagesLoading || _images.isNotEmpty)
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _imageGallery(context),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              context.l10n.loadingWiki,
                              style: context.texts.bodySmall!.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      if (body.isNotEmpty)
                        Text(
                          body,
                          style: context.texts.bodyMedium!.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      if (other.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final alias in other.take(8))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  alias,
                                  style: context.texts.labelSmall!.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: .35),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: InkWell(
                        onTap: _openWiki,
                        onLongPress: _copyWiki,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Danbooru Wiki',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.labelLarge!.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 14,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onReroll != null) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: scheme.surfaceContainerHighest,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _rerolling ? null : _reroll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_rerolling)
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.casino_outlined,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              const SizedBox(width: 4),
                              Text(
                                context.l10n.shuffleAnother,
                                style: context.texts.labelLarge!.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.showUse) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: context.selectedFill,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _rerolling
                            ? null
                            : () => Navigator.of(context).pop(_current),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: Text(
                            context.l10n.use,
                            style: context.texts.labelLarge!.copyWith(
                              color: context.onSelectedFill,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 附图轮播:定高完整展示(BoxFit.contain),左右滑动切图,点按全屏缩放查看。
  Widget _imageGallery(BuildContext context) {
    final scheme = context.scheme;
    final gen = _loadGen;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 196,
        width: double.infinity,
        decoration: BoxDecoration(
          color: context.skin.float ? scheme.surface : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: context.edgeBorder,
        ),
        child: _images.isEmpty
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _imgPager,
                    itemCount: _images.length,
                    onPageChanged: (i) => setState(() => _imgPage = i),
                    itemBuilder: (_, i) {
                      final url = _images[i];
                      return GestureDetector(
                        onTap: () => _openFullImage(i),
                        child: RemoteImage(
                          url,
                          headers: kBooruImageHeaders,
                          fit: BoxFit.contain,
                          decodeWidth: 420,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.primary,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, _, _) {
                            _onImageError(url, gen);
                            return const SizedBox.shrink();
                          },
                        ),
                      );
                    },
                  ),
                  if (_images.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .36),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < _images.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 4),
                                  AnimatedContainer(
                                    duration: Motion.fast,
                                    width: i == _imgPage ? 14 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: i == _imgPage
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: .45),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 附图全屏查看器:支持左右滑切图与双指缩放。
class _FullImageDialog extends StatefulWidget {
  const _FullImageDialog({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_FullImageDialog> createState() => _FullImageDialogState();
}

class _FullImageDialogState extends State<_FullImageDialog> {
  late final PageController _ctrl = PageController(
    initialPage: widget.initialIndex,
  );
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _ctrl,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: RemoteImage(
                      widget.images[i],
                      headers: kBooruImageHeaders,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: .45),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (widget.images.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_page + 1} / ${widget.images.length}',
                          style: mono(context, size: 12, color: Colors.white),
                        ),
                      ),
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

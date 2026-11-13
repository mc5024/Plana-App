import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../data/suggestions.dart';
import '../data/tag_completion.dart';
import '../data/tag_translation_service.dart';
import 'completion_bar.dart' show CompletionGrip, suggestionGlyph;
import '../../../l10n/l10n.dart';

/// 形态 B · 展开态:分类竖向列表(键盘收起,腾出纵向空间)。
/// 由形态 A 上滑 / 点抓手进入;顶部抓手或下滑 / 底部提示 → 收起回形态 A。
///
/// 结构(只借设计稿布局,图标与配色沿用现有 [suggestionGlyph] + M3 语义色):
/// - 抓手 + 头部(`补全结果` · 项数 · 热度/字母排序切换)
/// - 分节:画师 / OC / 角色 / 作品 / 标签,各带彩色图标 + 计数 + 细分隔线,节标题点按折叠
/// - 每行:名 + 译文/来源 · 热度 · 👁 预览(作品行为骰子随机抽取)· `+` 连续插入
/// - 👁 只给标签 / 角色:画师串与 OC 在 Danbooru 上没有词条,点开必空
class CompletionPanel extends ConsumerStatefulWidget {
  const CompletionPanel({
    super.key,
    required this.result,
    required this.maxHeight,
    required this.onPick,
    required this.onInsert,
    required this.onCollapse,
  });

  final SuggestResult result;
  final double maxHeight;

  /// 行主体点按:替换光标处半词并收起(交给页面)
  final void Function(Suggestion) onPick;

  /// `+` 连续插入:追加为新标签,面板保持展开
  final void Function(Suggestion) onInsert;

  /// 下滑 / 抓手 / 底部提示:收起回形态 A 并唤起键盘
  final VoidCallback onCollapse;

  @override
  ConsumerState<CompletionPanel> createState() => _CompletionPanelState();
}

class _CompletionPanelState extends ConsumerState<CompletionPanel> {
  // 排序:true=热度 / false=字母。记住上次的 —— 习惯按字母找词的人
  // 不该每开一次补全都被拨回热度。
  late bool _byHeat = ref.read(uiPrefsProvider).completionByHeat;
  final Set<SuggestionKind> _collapsed = {}; // 折叠的分节
  String? _wikiOpen; // 当前展开 Wiki 预览的行(按 text 记)
  // text → 预览。**只存拿到的**:以前连 null 一起存,而 _loadWiki 开头是
  // containsKey 就 return —— 一次网络失败之后,这次面板里同一个词永远不再重试。
  final Map<String, WikiPreview> _wiki = {};
  final Set<String> _wikiLoading = {};
  final Set<String> _dicing = {}; // 正在为哪些作品行抽角色

  /// 后端翻译通道。面板拿的是查询快照,译文是之后才到货的 ——
  /// 不自己听一耳朵,展开态就得一直空着(编辑器那边的 setState 隔着路由传不进来)。
  late final TagTranslationService _transSvc;

  @override
  void initState() {
    super.initState();
    _transSvc = ref.read(tagTranslationServiceProvider)..addListener(_onTrans);
  }

  @override
  void dispose() {
    _transSvc.removeListener(_onTrans);
    super.dispose();
  }

  void _onTrans() {
    if (mounted) setState(() {});
  }

  /// 两段式:先把英文摘要/别名放出来(0.5~1s),中文摘要后补。
  /// 服务端那张 upstream 成品表目前是空的,`summaryZh` 几乎每个词都要现拓
  /// 正文喂模型(实测 2.3~4.4s)—— 原先拿整张卡片等它,点开只能看到一个
  /// 转四五秒的圈,和坏了没区别。
  Future<void> _loadWiki(String tag) async {
    if (_wiki.containsKey(tag) || _wikiLoading.contains(tag)) return;
    setState(() => _wikiLoading.add(tag));
    final tc = ref.read(tagCompletionProvider);
    final w = await tc.fetchWiki(tag);
    if (!mounted) return;
    setState(() {
      _wikiLoading.remove(tag);
      if (w != null) _wiki[tag] = w; // 失败不入缓存,再点一次还能重试
    });
    if (w == null || (w.summaryZh?.isNotEmpty ?? false)) return;
    final zh = await tc.fetchWikiZh(tag);
    if (!mounted || zh == null || zh.isEmpty || _wiki[tag] != w) return;
    setState(
      () => _wiki[tag] = WikiPreview(
        title: w.title,
        summary: w.summary,
        summaryZh: zh,
        otherNames: w.otherNames,
      ),
    );
  }

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

  /// 行副标题。译文走 [transOf] 而非 `s.trans`:D 站来的行自带译名只有
  /// wiki 那一路,反查缓存(离线词库 / 共享翻译库 / LLM 回填)里的得现查。
  String? _subtitle(Suggestion s) {
    switch (s.kind) {
      case SuggestionKind.character:
        return [
          transOf(s),
          s.source,
        ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
      case SuggestionKind.work:
        return [
          transOf(s),
          s.note,
        ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
      case SuggestionKind.oc:
        return s.source; // 「本地库」/ 公共库作者
      case SuggestionKind.tag:
        return transOf(s);
      case SuggestionKind.artist:
        return s.trans;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    // 自有库(画师 / OC)在前,上游的角色·作品在后 —— 同 completion_bar,
    // 理由见那里:上游角色条数多,夹在中间会把 OC 顶到要滚很久才看得到。
    // OC 一节里公共库别人的也在(底行写作者),所以节名不叫「我的 OC」。
    final sections = <(SuggestionKind, String, List<Suggestion>)>[
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

    final rows = <Widget>[];
    for (final (kind, label, raw) in sections) {
      final items = _sorted(raw);
      rows.add(_sectionHeader(kind, label, items.length));
      if (!_collapsed.contains(kind)) {
        for (final s in items) {
          rows.add(_row(s));
        }
      }
    }

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              _header(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: rows,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 抓手 / 头部 / 底部 ----

  /// 与横向态那枚同款(同一个 [CompletionGrip]):一上一下是同一个交互的两头,
  /// 一边有底一边裸着会显得是两个东西。
  Widget _handle() => Center(
    child: CompletionGrip(
      icon: Icons.keyboard_arrow_down_rounded,
      onTap: widget.onCollapse,
      onDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 120) widget.onCollapse();
      },
    ),
  );

  Widget _header() {
    final scheme = context.scheme;
    return Padding(
      // 右边距 4:排序按钮自带 8 内衬,合起来正好与下方行尾圆钮的 12 对齐
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 6),
      child: Row(
        children: [
          Text(
            context.l10n.completionResults,
            style: context.texts.titleSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            context.l10n.itemsCount(widget.result.total),
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                ref
                    .read(uiPrefsProvider.notifier)
                    .patch((p) => p.copyWith(completionByHeat: !_byHeat));
                setState(() => _byHeat = !_byHeat);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_vert, size: 16, color: scheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      _byHeat ? context.l10n.byHeat : 'A–Z',
                      style: context.texts.labelLarge!.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 分节头 / 行 / 预览卡 ----

  Widget _sectionHeader(SuggestionKind kind, String label, int n) {
    final scheme = context.scheme;
    final (icon, color) = suggestionGlyph(context, kind);
    final collapsed = _collapsed.contains(kind);
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(kind);
        } else {
          _collapsed.add(kind);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: context.texts.labelLarge!.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$n',
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: .6),
              ),
            ),
            if (collapsed) ...[
              const SizedBox(width: 8),
              Icon(Icons.expand_more, size: 16, color: scheme.outline),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Suggestion s) {
    final scheme = context.scheme;
    final isWork = s.kind == SuggestionKind.work;
    // 眼睛 = Danbooru Wiki 预览。画师串是自建条目、OC 是本地条目,
    // Danbooru 上没有对应词条,给了按钮点开也是空,所以这两类不出。
    final canWiki =
        s.kind == SuggestionKind.tag || s.kind == SuggestionKind.character;
    final subtitle = _subtitle(s);
    final count = isWork ? null : formatCount(s.count);
    final open = _wikiOpen == s.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => widget.onPick(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle,
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
                if (count != null) ...[
                  Text(
                    count,
                    style: mono(context, size: 12, color: scheme.outline),
                  ),
                  const SizedBox(width: 6),
                ],
                if (isWork) ...[
                  _diceBtn(s),
                  const SizedBox(width: 4),
                ] else if (canWiki) ...[
                  _eyeBtn(s, open),
                  const SizedBox(width: 4),
                ],
                _plusBtn(s),
              ],
            ),
          ),
        ),
        if (open && canWiki) _previewCard(s),
      ],
    );
  }

  /// 👁 Wiki 预览开关(标签 / 角色 / OC 行)
  Widget _eyeBtn(Suggestion s, bool open) {
    final scheme = context.scheme;
    return _circleBtn(
      icon: open ? Icons.visibility : Icons.visibility_outlined,
      fg: open ? scheme.primary : scheme.onSurfaceVariant,
      onTap: () {
        setState(() => _wikiOpen = open ? null : s.text);
        if (!open) _loadWiki(s.text);
      },
    );
  }

  /// 作品行:随机抽一个角色插入。**只有这个按钮**做抽取——点行主体和 `+`
  /// 都是直接插作品 tag 本身。本地角色库退役后没有预抽好的角色了,改成点下去
  /// 现拉(上游按共现度给该作品最常画的角色),所以会先转一下再插;拉不到就
  /// 退回插作品 tag 本身。
  Widget _diceBtn(Suggestion s) {
    final (icon, color) = suggestionGlyph(context, s.kind);
    final busy = _dicing.contains(s.text);
    return _circleBtn(
      icon: icon,
      fg: color,
      busy: busy,
      onTap: () async {
        if (busy) return;
        setState(() => _dicing.add(s.text));
        final pick = await ref
            .read(tagCompletionProvider)
            .randomCharacterOf(s.text);
        if (!mounted) return;
        setState(() => _dicing.remove(s.text));
        widget.onPick(pick == null ? s : s.copyWith(insertText: pick));
      },
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color fg,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(9),
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, size: 18, color: fg),
        ),
      ),
    );
  }

  /// `+` 连续插入
  Widget _plusBtn(Suggestion s) {
    final scheme = context.scheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onInsert(s),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.add, size: 19, color: scheme.onPrimary),
        ),
      ),
    );
  }

  Widget _previewCard(Suggestion s) {
    final scheme = context.scheme;
    final loading = _wikiLoading.contains(s.text);
    final wiki = _wiki[s.text];

    // 标签行和角色行都走后端 wiki(中文摘要优先)。原先只有 `isTag` 那支用 wiki,
    // 角色行拿到的词条直接丢掉、改显行里已经写过一遍的副标题 ——
    // 请求发了、结果不用,点角色行的眼睛必定看不到东西。
    String body;
    if (wiki != null && wiki.hasText) {
      body = (wiki.summaryZh != null && wiki.summaryZh!.isNotEmpty)
          ? wiki.summaryZh!
          : (wiki.summary ?? '');
    } else if (loading) {
      body = '';
    } else {
      body = _subtitle(s) ?? '';
      if (body.isEmpty) body = context.l10n.wikiMissing;
    }
    final other = wiki?.otherNames ?? const <String>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            Row(
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
                Text(
                  context.l10n.loadingWiki,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else ...[
            if (body.isNotEmpty)
              Text(
                body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            if (other.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.aliases(other.take(4).join(' / ')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ],
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _openWiki(s),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Danbooru Wiki',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.arrow_forward, size: 13, color: scheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openWiki(Suggestion s) {
    final url = danbooruWikiUrl(s.text);
    Clipboard.setData(ClipboardData(text: url));
    hintSnack(context, context.l10n.wikiLinkCopied(url), icon: Icons.check);
  }
}

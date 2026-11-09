import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/store/ui_prefs.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/fast_scroll_handle.dart';
import '../../core/ui/lift_menu.dart';
import '../../core/ui/pinch_columns.dart';
import '../../core/ui/scroll_memory.dart';
import '../../core/ui/selection_bar.dart';
import '../editor/editor_models.dart' show draftOf, outputOf, pickEditorText;
import '../generate/canvas_state.dart';
import '../generate/gen_modules.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart' show maxCharactersOf;
import '../generate/style_recipes.dart';
import '../generate/widgets/common.dart'
    show confirmDialog, hintSnack, sharedAxisRoute;
import '../shell/shell_state.dart';
import 'codex/codex_view.dart';
import 'artist_models.dart';
import 'public_tags.dart';
import 'tag_editor_page.dart';
import 'tag_library.dart';
import 'tag_models.dart';
import 'widgets/category_sheets.dart';
import 'widgets/category_tabs.dart';
import 'widgets/scope_seg_tabs.dart';
import 'widgets/tag_card.dart';
import 'widgets/tag_filter_chips.dart';
import 'widgets/tag_filter_sheet.dart';
import 'widgets/tag_sheets.dart';
import '../../core/util/haptics.dart';

/// 顶部各行统一的左右边距;行尾若是 IconButton,用 [_kIconEdge]
/// (减去按钮 8px 内衬)让图标视觉边与其他行对齐。
const _kEdge = 14.0;
const _kIconEdge = 6.0;

/// 网格分组:一个区头 + 该组条目(我的/收藏的/公共/各作者)。
/// 区头 null = 只有这一组、条数已在分段上,不再单起一行。
typedef _Group = ({Widget? header, List<TagEntry> items});

/// 网格卡片间距(骨架与真实网格共用,保证切换时不跳位)。
const _gap = 10.0;

/// 网格默认列数。双指捏合可在 1 列到该分类的上限之间换档,每个分类记各的。
const _kCols = 2;

/// 灵感页:web Tag 管理器的移动端形态(底部 tab 常驻页,非弹窗)。
/// 顶栏是分类页签,正文每个分类一页、左右滑切换;页里是搜索 + 我的/公共库
/// 分段 + 标签筛选 + 网格,底部操作条在外层。
class InspirationPage extends ConsumerStatefulWidget {
  const InspirationPage({super.key});

  @override
  ConsumerState<InspirationPage> createState() => _InspirationPageState();
}

class _InspirationPageState extends ConsumerState<InspirationPage>
    with AutomaticKeepAliveClientMixin {
  /// 当前页签的分类;在法典页时停在进法典之前那一类。
  TagCategory _cat = TagCategory.character;

  /// 当前在法典页。法典不属于 [TagCategory](无我的/公共库、无备份/新建),
  /// 故独立成一个模式位。
  bool _codex = false;
  static const _kCodexSel = '__codex__';

  /// 每页一页的正文;顶栏页签跟着它的位置走。
  PageController? _pc;
  final _pagePos = ValueNotifier<double>(0);

  /// 每分类已选 id(我的/公共库两 scope 共用一套,对齐 web selectionMap)。
  final Map<TagCategory, Set<String>> _selected = {};

  /// 每分类当前停在哪个 scope(0 = 我的,1 = 公共库),底栏按它换动作。
  final Map<TagCategory, int> _scopes = {};

  /// 批量操作进行中(禁重入)。
  bool _busy = false;

  /// 上次停在哪一页记在偏好里的键。
  static const _kLastPage = 'inspiration';

  @override
  void initState() {
    super.initState();
    // 回到上次停的那一页
    final last = ref.read(uiPrefsProvider).lastPages[_kLastPage];
    if (last == kCodexTabKey) {
      _codex = true;
    } else if (last != null) {
      _cat = tagCategoryByWebId(last) ?? TagCategory.character;
    }
  }

  @override
  void dispose() {
    _pc?.dispose();
    _pagePos.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  TagCategoryDef get _def => tagCategoryDef(_cat);

  Set<String> _selOf(TagCategory c) => _selected[c] ??= {};

  Set<String> get _sel => _selOf(_cat);

  void _toggle(TagCategory c, TagEntry e) {
    // 角色分类的单次可选数 = 角色卡槽位,跟当前模型走(NAI 5 是 20);
    // 其余分类仍用注册表里的静态上限。
    final cap = c == TagCategory.character
        ? maxCharactersOf(ref.read(generateProvider).params.model)
        : tagCategoryDef(c).maxSelectable;
    final sel = _selOf(c);
    setState(() {
      if (sel.contains(e.id)) {
        sel.remove(e.id);
      } else if (sel.length < cap) {
        sel.add(e.id);
      } else {
        hintSnack(context, '最多选 $cap 个', icon: Icons.block_outlined);
      }
    });
  }

  void _onScope(TagCategory c, int i) {
    if (_scopes[c] == i) return;
    setState(() => _scopes[c] = i);
  }

  // ---- 回填(语义对齐 web;app 编辑器无芯片协议,按约定插裸内容) ----

  List<TagEntry> _resolveSelected(TagLibraryState lib) {
    final byId = {for (final e in lib.of(_cat)) e.id: e};
    final pub = ref.read(publicTagsProvider(_cat)).value;
    if (pub != null) {
      for (final e in pub) {
        byId[e.id] = e;
      }
    }
    return [
      for (final id in _sel)
        if (byId[id] case final TagEntry e) e,
    ];
  }

  Future<void> _afterConfirm(List<TagEntry> used, String message) async {
    // 写进的是此刻的当前画布,提示条里的「套用」也按它回写
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    await ref.read(tagLibraryProvider.notifier).markUsed(_cat, [
      for (final e in used) e.id,
    ]);
    // 公共画师串使用计数上报(fire-and-forget)
    if (_cat == TagCategory.artist) {
      final session = ref.read(botSessionProvider).value;
      if (session != null) {
        final client = ref.read(backendClientProvider);
        for (final e in used) {
          if (e.id.startsWith('pub_') && e.publicId != null) {
            unawaited(client.reportArtistUse(session.sessionId, e.publicId!));
          }
        }
      }
    }
    setState(() => _sel.clear());
    if (!mounted) return;
    hintSnack(context, message, icon: Icons.check_circle_outline);
    ref.read(shellIndexProvider.notifier).select(kTabCreate);
    // 画风带推荐参数、且对得上当前模型的,弹窗问套不套
    if (_cat == TagCategory.artist) {
      await offerStyleRecipe(context, ref, used, canvasId: canvasId);
    }
  }

  /// 角色 → 加入角色卡(带名追加,上限按模型截断,见 maxCharactersOf)。
  Future<void> _confirmAsCharacters(TagLibraryState lib) async {
    final entries = _resolveSelected(lib);
    if (entries.isEmpty) return;
    final cap = maxCharactersOf(ref.read(generateProvider).params.model);
    final pubPreview = publicPreviewsOf(
      ref.read(publicTagsProvider(_cat)).value,
    );
    final added = ref.read(generateProvider.notifier).addNamedCharactersFrom([
      for (final e in entries)
        (
          name: e.name,
          positive: e.positive,
          negative: e.negative,
          avatar: tagPreviewOf(e, pubPreview),
        ),
    ]);
    if (added == 0) {
      hintSnack(context, '角色已满 $cap 个', icon: Icons.block_outlined);
      return;
    }
    await _afterConfirm(
      entries,
      added < entries.length ? '已加入 $added 个角色(超出 $cap 个截断)' : '已加入 $added 个角色',
    );
  }

  /// 角色「主提示词」/ 画风/场景/其他「确认选择」:正负向拼进主提示词。
  /// 主提示词分过区时,每个条目自成一格、不折叠(同提示词卡头的「灵感库」)。
  Future<void> _confirmToPrompt(TagLibraryState lib) async {
    final entries = _resolveSelected(lib);
    if (entries.isEmpty) return;
    final gen = ref.read(generateProvider);
    if (gen.sections.isNotEmpty) {
      ref.read(generateProvider.notifier).addEntrySections(entries);
      await _afterConfirm(entries, '已加入提示词');
      return;
    }
    // 追加到编辑器原文草稿(带回既有的禁用/折叠),每个条目自成一个折叠组;
    // 定稿由 outputOf 从草稿导出 —— 两者必须同时写,只写定稿的话草稿会被
    // 判过期作废,这次加进去的折叠(以及用户原有的禁用词)就一起没了。
    final draft = appendTagPositivesFolded(
      pickEditorText(gen.promptRaw, gen.prompt),
      entries,
    );
    final positive = outputOf(draft);
    ref
        .read(generateProvider.notifier)
        .setPrompts(
          positive: positive,
          negative: appendTagNegatives(gen.negativePrompt, entries),
          positiveRaw: draftOf(draft, positive),
        );
    await _afterConfirm(entries, '已加入提示词');
  }

  // ---- build ----

  /// 顶栏页签:按类别管理里排的顺序,藏起来的不出。
  List<Object> _tabKeys(TagLibraryState lib) => [
    for (final k in lib.visibleTabKeys)
      if (k == kCodexTabKey) _kCodexSel else ?tagCategoryByWebId(k),
  ];

  Object get _current => _codex ? _kCodexSel : _cat;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = context.scheme;
    final lib = ref.watch(tagLibraryProvider).value ?? const TagLibraryState();
    final keys = _tabKeys(lib);
    var index = keys.indexOf(_current);
    // 当前这一类被删了 / 藏起来了:回到角色
    if (index < 0) {
      _codex = false;
      _cat = TagCategory.character;
      index = keys.indexOf(_cat);
    }
    if (_pc == null) {
      _pc = PageController(initialPage: index)..addListener(_onPageScroll);
      _pagePos.value = index.toDouble();
    }
    final pc = _pc!;
    // 页签增删、换序后,页码对不上当前分类了:原地跳回去
    final sig = keys.map((k) => k is TagCategory ? k.name : _kCodexSel).join();
    if (_keysSig != null && _keysSig != sig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pc.hasClients) pc.jumpToPage(index);
      });
    }
    _keysSig = sig;

    return Scaffold(
      body: Column(
        children: [
          _topBar(scheme, keys, index),
          Expanded(
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (n) {
                if (n.depth == 0 && n.metrics.axis == Axis.horizontal) {
                  _settle(keys);
                }
                return false;
              },
              child: PageView.custom(
                controller: pc,
                // 当前分类等翻页停稳才换(见 _settle):翻到一半就整页重建会卡一帧
                childrenDelegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final k = keys[i];
                    return k is TagCategory
                        ? _CategoryPage(
                            key: ValueKey(k.name),
                            cat: k,
                            host: this,
                          )
                        : const _KeepAlive(
                            key: ValueKey(_kCodexSel),
                            // 只读浏览器,自带选法典、搜索与筛选,无选择栏
                            child: CodexView(),
                          );
                  },
                  childCount: keys.length,
                  findChildIndexCallback: (key) {
                    final v = (key as ValueKey<String>).value;
                    final i = keys.indexWhere(
                      (k) => (k is TagCategory ? k.name : _kCodexSel) == v,
                    );
                    return i < 0 ? null : i;
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _codex ? null : _selectionBar(scheme, lib),
    );
  }

  /// 上一次页签的排列(变了就把页码对回当前分类)。
  String? _keysSig;

  void _settle(List<Object> keys) {
    final page = _pc?.page;
    if (page == null) return;
    final i = page.round();
    if (i < 0 || i >= keys.length) return;
    final k = keys[i];
    if (k == _current) return;
    ref
        .read(uiPrefsProvider.notifier)
        .setLastPage(
          _kLastPage,
          k is TagCategory ? tagCategoryDef(k).webId : kCodexTabKey,
        );
    setState(() {
      if (k is TagCategory) {
        _cat = k;
        _codex = false;
      } else {
        _codex = true;
      }
    });
  }

  void _onPageScroll() {
    final page = _pc?.page;
    if (page != null) _pagePos.value = page;
  }

  Widget _topBar(ColorScheme scheme, List<Object> keys, int index) {
    return Padding(
      // 行尾是 IconButton:右边距减去它的内衬,图标视觉边与其他行对齐
      padding: const EdgeInsets.fromLTRB(0, 6, _kIconEdge, 0),
      child: Row(
        children: [
          Expanded(
            child: CategoryTabs(
              labels: [
                for (final k in keys)
                  k is TagCategory ? tagCategoryDef(k).label : codexTabLabel(),
              ],
              index: index,
              position: _pagePos,
              onTap: (i) => _pc?.animateToPage(
                i,
                duration: Motion.medium,
                curve: Motion.standard,
              ),
              onManage: () => showCategoryManagerSheet(context),
              leftPad: _kEdge,
              capsule: true,
            ),
          ),
          // 备份 / 新建:翻向法典页时跟着翻页进度收起、淡出,翻回来再展开
          ValueListenableBuilder(
            valueListenable: _pagePos,
            builder: (context, pos, child) {
              final ci = keys.indexOf(_kCodexSel);
              final hide = ci < 0
                  ? 0.0
                  : (1 - (pos - ci).abs()).clamp(0.0, 1.0).toDouble();
              final t = Curves.easeOut.transform(1 - hide);
              return IgnorePointer(
                ignoring: hide > .5,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: Opacity(opacity: t, child: child),
                  ),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '数据备份',
                  icon: const Icon(Icons.cloud_outlined),
                  onPressed: () => showTagBackupSheet(context, ref),
                ),
                IconButton(
                  tooltip: '新建',
                  icon: const Icon(Icons.add),
                  onPressed: () => _openNew(_cat),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 新建:标题可点换成页签上的任一类(建错类别时就地改)。
  void _openNew(TagCategory c) {
    final lib = ref.read(tagLibraryProvider).value ?? const TagLibraryState();
    Navigator.of(context).push(
      sharedAxisRoute(
        TagEditorPage(
          cat: c,
          categories: [
            for (final k in lib.visibleTabKeys)
              if (k != kCodexTabKey) ?tagCategoryByWebId(k),
          ],
        ),
      ),
    );
  }

  Future<void> _collect(TagEntry e) async {
    final ok = await ref.read(tagLibraryProvider.notifier).collect(e);
    if (!mounted) return;
    hintSnack(
      context,
      ok ? '已收藏到「我的」' : '已经收藏过了',
      icon: ok ? Icons.favorite : Icons.info_outline,
    );
  }

  // ---- 批量操作(底栏第一层) ----

  Future<void> _runBatch(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 批量贴标签:选一个标签(可现场新建)并入所有选中条目。
  Future<void> _batchTag(TagLibraryState lib) async {
    final entries = _resolveSelected(lib);
    if (entries.isEmpty) return;
    final tag = await pickTagSheet(context, ref, _cat);
    if (tag == null || !mounted) return;
    await _runBatch(() async {
      final notifier = ref.read(tagLibraryProvider.notifier);
      await notifier.addPoolTag(_cat, tag);
      var n = 0;
      for (final e in entries) {
        if (e.tags.contains(tag)) continue;
        await notifier.upsert(e.copyWith(tags: [...e.tags, tag]..sort()));
        n++;
      }
      if (mounted) {
        hintSnack(context, '已给 $n 项加上「$tag」', icon: Icons.sell_outlined);
      }
    });
  }

  Future<void> _batchDelete(TagLibraryState lib) =>
      _deleteEntries(_resolveSelected(lib));

  /// 删除条目:已发布的(created + publicId)连同公共库条目一并删。
  ///
  /// 卡片菜单和多选底栏走同一条 —— 早先卡片菜单只删本地、文案还恒写「仅删除
  /// 本地条目」,已发布的条目从库里消失、公共库那份却还挂着,之后连管理入口
  /// 都没有了。
  Future<void> _deleteEntries(List<TagEntry> entries) async {
    if (entries.isEmpty) return;
    // 三种来源三种后果(对齐 web 桌面端管理器的单卡菜单):
    //   created  发布过的 → 公共库条目 + 本地副本一起删
    //   favorited 收藏来的 → 只丢自己这份副本,公共库原作不动
    //   local     纯本地的 → 就是删本地
    final published = [
      for (final e in entries)
        if (e.origin == TagOrigin.created && e.publicId != null) e,
    ];
    final favorited = [
      for (final e in entries)
        if (e.origin == TagOrigin.favorited) e,
    ];
    final localOnly = entries.length - published.length - favorited.length;
    final one = entries.length == 1 ? entries.first : null;

    final String title, message;
    if (one != null) {
      if (published.isNotEmpty) {
        title = '删除「${one.name}」?';
        message = '将彻底删除公共库条目与本地副本,不可恢复。';
      } else if (favorited.isNotEmpty) {
        title = '删除收藏?';
        message = '将从本地移除「${one.name}」,公共库原作不受影响。';
      } else {
        title = '删除「${one.name}」?';
        message = '仅删除本地条目,不可恢复。';
      }
    } else {
      title = '删除 ${entries.length} 项?';
      final lines = [
        if (published.isNotEmpty) '· 你发布的 ${published.length} 项:连同公共库条目一起删',
        if (favorited.isNotEmpty) '· 收藏的 ${favorited.length} 项:只移除本地副本,原作不动',
        if (localOnly > 0) '· 本地的 $localOnly 项:仅删除本地',
      ];
      message = '${lines.join('\n')}\n\n不可恢复。';
    }
    final ok = await confirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    await _runBatch(() async {
      final notifier = ref.read(tagLibraryProvider.notifier);
      final client = ref.read(backendClientProvider);
      final session = ref.read(botSessionProvider).value;
      var done = 0, failed = 0;
      for (final e in entries) {
        try {
          if (e.origin == TagOrigin.created &&
              e.publicId != null &&
              session != null) {
            if (_cat == TagCategory.character) {
              await client.deletePublicOc(session.sessionId, e.publicId!);
            } else {
              await client.deletePublicArtist(session.sessionId, e.publicId!);
            }
          }
          await notifier.remove(e.id);
          done++;
        } catch (_) {
          failed++;
        }
      }
      if (published.isNotEmpty) ref.invalidate(publicTagsProvider(_cat));
      if (!mounted) return;
      setState(() => _sel.clear());
      hintSnack(
        context,
        failed > 0
            ? '已删除 $done 项,$failed 项失败'
            : (one != null ? '已删除' : '已删除 $done 项'),
        icon: Icons.delete_outline,
      );
    });
  }

  /// 批量收藏(公共库 scope)。
  Future<void> _batchCollect(TagLibraryState lib) async {
    final entries = _resolveSelected(lib);
    if (entries.isEmpty) return;
    await _runBatch(() async {
      final notifier = ref.read(tagLibraryProvider.notifier);
      var added = 0;
      for (final e in entries) {
        if (await notifier.collect(e)) added++;
      }
      if (!mounted) return;
      setState(() => _sel.clear());
      hintSnack(
        context,
        added == entries.length ? '已收藏 $added 项' : '已收藏 $added 项(其余已在库中)',
        icon: Icons.favorite,
      );
    });
  }

  // ---- 底部操作条 ----

  /// 角色模块对当前模型是否可见 —— 决定「加入角色」这个去处存不存在。
  /// anima 下 NAI 四件套整组收走(角色卡都不渲染),此时加进去的角色既不进
  /// 载荷也看不见,只会把提示词计数顶大,是个纯幽灵动作,故收起按钮。
  bool get _charModuleOn {
    final model = ref.watch(generateProvider.select((s) => s.params.model));
    final ms = ref.watch(genModulesProvider).value ?? const GenModuleSettings();
    return ms.isVisibleFor(GenModule.character, model);
  }

  /// 多选底栏(一行):✕ 取消 · 标签 / 收藏 · 删除 · 添加。
  /// 「添加」:角色加成角色卡;角色模块不可见时(anima 等)和其余分类一样
  /// 拼进主提示词。
  Widget _selectionBar(ColorScheme scheme, TagLibraryState lib) {
    final n = _sel.length;
    final publicScope = _def.hasPublic && _scopes[_cat] == 1;
    final asCharacters = _cat == TagCategory.character && _charModuleOn;
    return SelectionBar(
      visible: n > 0,
      compact: true,
      // shell 里的 tab 页,底部安全区由导航栏兜着
      safeArea: false,
      onClear: () => setState(() => _sel.clear()),
      actions: [
        if (publicScope)
          SelectionIconButton(
            icon: Icons.favorite_border,
            tooltip: '收藏',
            onTap: _busy ? null : () => _batchCollect(lib),
          )
        else
          SelectionIconButton(
            icon: Icons.sell_outlined,
            tooltip: '标签',
            onTap: _busy ? null : () => _batchTag(lib),
          ),
      ],
      destructive: publicScope
          ? null
          : SelectionIconButton(
              icon: Icons.delete_outline,
              tooltip: '删除',
              color: scheme.error,
              onTap: _busy ? null : () => _batchDelete(lib),
            ),
      primary: FilledButton.icon(
        onPressed: () =>
            asCharacters ? _confirmAsCharacters(lib) : _confirmToPrompt(lib),
        icon: Icon(asCharacters ? Icons.person_add_alt : Icons.add, size: 18),
        label: Text('添加 ($n)'),
        style: selectionPrimaryStyle(),
      ),
    );
  }
}

/// 一个分类的正文:搜索 + 我的/公共库分段 + 标签筛选 + 网格。每页各记各的
/// 搜索、筛选、分段与列数;选择与批量动作在外层 [_InspirationPageState]。
class _CategoryPage extends ConsumerStatefulWidget {
  const _CategoryPage({super.key, required this.cat, required this.host});

  final TagCategory cat;
  final _InspirationPageState host;

  @override
  ConsumerState<_CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<_CategoryPage>
    with
        AutomaticKeepAliveClientMixin,
        TickerProviderStateMixin,
        PinchColumnsMixin {
  TagCategory get _cat => widget.cat;

  late final TabController _tab = TabController(length: 2, vsync: this);
  late final _mineScroll = MemoScrollController.keyed(
    () => _scrollKey(_cat, false),
  );
  late final _pubScroll = MemoScrollController.keyed(
    () => _scrollKey(_cat, true),
  );

  /// 公共库里点开过原图的打码条目,本次运行内一直显示原图。
  final _revealed = <String>{};

  String _search = '';

  /// 筛选:null=全部;[_kFavFilter]=收藏;其余为标签名。
  String? _filter;
  static const _kFavFilter = TagFilterChips.favorites;

  /// 画风的「适用模型」筛选:null=全部;[kGenericModelFilter]=只看通用;
  /// 其余是 [ArtistModelGroup] 的 name。与 [_filter] 是两个正交的维度,
  /// 可以同时生效(「收藏的 + 标了 NAI 5 的」)。
  String? _modelFilter;

  /// 作者筛选:null=全部;其余是条目的归属键(QQ 号,存量数据可能是个名字串)。
  /// 角色/画风(有公共库的两类)都吃这一维,与 [_modelFilter] 同样正交。
  String? _authorFilter;

  /// 作者目录(QQ 号 → 昵称)。build 时从 [tagAuthorNamesProvider] 取一份存下来,
  /// 好让 [_matches] 这些深处的过滤函数不必层层传参;取不到就是空表(显示 QQ 号)。
  Map<String, String> _authorNames = const {};

  /// 排序档;null = 该分类原本的排法。
  TagSort? _sortOverride;

  TagSort get _sortMode => _sortOverride ?? defaultTagSort(_cat);

  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // 只在整数位变化时 setState(筛选行随 scope 显隐)。
    _tab.animation!.addListener(() {
      final i = _tab.animation!.value.round();
      if (i != _tabIndex && mounted) {
        setState(() => _tabIndex = i);
        widget.host._onScope(_cat, i);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _mineScroll.dispose();
    _pubScroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  TagCategoryDef get _def => tagCategoryDef(_cat);

  Set<String> get _sel => widget.host._selOf(_cat);

  static String _revealKey(TagEntry e) => '${e.category.name}/${e.id}';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = ref.watch(tagLibraryProvider).value ?? const TagLibraryState();
    _authorNames = ref.watch(tagAuthorNamesProvider).value ?? const {};
    return _tagBody(context.scheme, lib, _def);
  }

  /// 滚动记忆的账本 key:每个分类的两个 scope 各记各的。
  String _scrollKey(TagCategory c, bool pub) =>
      'inspiration.${c.name}.${pub ? 'public' : 'mine'}';

  // ---- 双指捏合改列数(见 PinchColumnsMixin) ----

  int _savedCols(TagCategory c) =>
      ref.read(uiPrefsProvider).inspirationColumns[c.name] ?? _kCols;

  @override
  int get initialGridColumns => _savedCols(_cat);

  @override
  int get minGridColumns => 1;

  /// 横幅卡(画风)封顶 3 列:再多一列,卡片矮到名字条和角上的按钮就把图盖满了。
  @override
  int get maxGridColumns => _def.previewAspect > 1 ? 3 : 4;

  @override
  ScrollController get pinchScrollController =>
      _def.hasPublic && _tabIndex == 1 ? _pubScroll : _mineScroll;

  @override
  void onGridColumnsChanged(int cols) {
    final key = _cat.name;
    ref
        .read(uiPrefsProvider.notifier)
        .patch(
          (p) => p.copyWith(
            inspirationColumns: {...p.inspirationColumns, key: cols},
          ),
        );
  }

  // ---- 数据 ----

  bool _matches(TagEntry e, String q) {
    if (q.isEmpty) return true;
    bool has(String s) => s.toLowerCase().contains(q);
    final author = e.createdBy?.trim();
    return has(e.name) ||
        has(e.positive) ||
        e.aliases.any(has) ||
        e.tags.any(has) ||
        // 作者:昵称和 QQ 号都算命中,搜索框里输哪个都能找到他发的东西。
        // ⚠ QQ 号要 5 位起才比 —— 画风名本身就是 A1..Z99 这种编号,再让「5」
        //   去撞每个作者的号码,一搜就是满屏不相干的串。
        (author != null &&
            author.isNotEmpty &&
            ((q.length >= 5 && has(author)) ||
                has(_authorNames[author] ?? '')));
  }

  /// 作者筛选。归属键为空的条目(纯本地 / 公共库里的无主老数据)不属于任何人,
  /// 筛作者时一律不出现。
  List<TagEntry> _byAuthor(List<TagEntry> list) => _authorFilter == null
      ? list
      : [
          for (final e in list)
            if (e.createdBy?.trim() == _authorFilter) e,
        ];

  /// 标签被删(标签池管理里删掉正在筛选的那个)后按「全部」处理,
  /// 不让列表空掉却没有任何选中态。
  String? _validFilter(TagLibraryState lib) {
    final f = _filter;
    if (f == null || f == _kFavFilter) return f;
    return lib.knownTags(_cat).contains(f) ? f : null;
  }

  /// 「我的」的完整来源 = 本地条目 + 公共库里我发布的(本地没副本的补进来,
  /// 标 created;对齐 web mineAll)。归属判定优先 owner_id,与服务端一致。
  List<TagEntry> _mineAll(TagLibraryState lib) => _def.hasPublic
      ? mergeMineTags(
          lib.of(_cat),
          ref.watch(botSessionProvider).value?.botUserId,
          ref.watch(publicTagsProvider(_cat)).value,
        )
      : lib.of(_cat);

  List<TagEntry> _mineList(TagLibraryState lib) {
    final q = _search.trim().toLowerCase();
    var list = [
      for (final e in _mineAll(lib))
        if (_matches(e, q)) e,
    ];
    final filter = _validFilter(lib);
    if (filter == _kFavFilter) {
      list = [
        for (final e in list)
          if (e.origin == TagOrigin.favorited) e,
      ];
    } else if (filter != null) {
      list = [
        for (final e in list)
          if (e.tags.contains(filter)) e,
      ];
    }
    list = _byAuthor(_byModel(list));
    _sort(list);
    return list;
  }

  /// 适用模型筛选(只对画风有意义;别的分类 [_modelFilter] 恒 null)。
  List<TagEntry> _byModel(List<TagEntry> list) => _modelFilter == null
      ? list
      : [
          for (final e in list)
            if (matchesArtistModelFilter(e.models, _modelFilter)) e,
        ];

  List<TagEntry> _publicList(List<TagEntry> all) {
    final q = _search.trim().toLowerCase();
    final list = [
      for (final e in all)
        if (_matches(e, q)) e,
    ];
    final out = _byAuthor(_byModel(list));
    _sort(out);
    return out;
  }

  void _sort(List<TagEntry> list) {
    switch (_sortMode) {
      case TagSort.number:
        list.sort((a, b) => naturalCompare(a.name, b.name));
      case TagSort.time:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // 按作者是**切组**不是排序:组内还是该分类原本的顺序,不然点开一栏
      // 里面又是一团乱序。
      case TagSort.author:
        _sortNatural(list);
    }
  }

  /// 分类原本的排法:画风按编号自然序(A1<A2<A10),其余最新在前。
  void _sortNatural(List<TagEntry> list) => _cat == TagCategory.artist
      ? list.sort((a, b) => naturalCompare(a.name, b.name))
      : list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Widget _tagBody(ColorScheme scheme, TagLibraryState lib, TagCategoryDef def) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  // 与右边的分段同高
                  height: 40,
                  child: TextField(
                    key: ValueKey('tag-search-${def.webId}'),
                    onChanged: (v) => setState(() => _search = v),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: def.searchHint,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      filled: true,
                      fillColor: context.pageControlFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.zero,
                      // 「作者 / 适用模型 / 排序」挂在搜索框里:它们和下面的标签筛选是
                      // 正交维度,塞进同一条 chip 行会让人以为是同一组单选。
                      // 只给有公共库的两类(角色/画风)—— 场景/其他的条目全是自己的。
                      suffixIcon: def.hasPublic ? _filterButton(scheme) : null,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        maxWidth: 130,
                        maxHeight: 40,
                      ),
                    ),
                  ),
                ),
              ),
              if (def.hasPublic) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 132,
                  child: ScopeSegTabs(
                    controller: _tab,
                    mineCount: _mineAll(lib).length,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_tabIndex == 0 || !def.hasPublic) _filterChips(lib),
        Expanded(
          // 禁 TabBarView 横滑:横滑手势留给 shell PageView 切底部 tab
          // (与场景/其他分类行为一致),scope 切换走分段控件点按。
          child: pinchLayer(
            child: def.hasPublic
                ? TabBarView(
                    controller: _tab,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_mineTab(lib), _publicTab(lib)],
                  )
                : _mineTab(lib),
          ),
        ),
      ],
    );
  }

  /// 当前模型筛选的显示名;null = 全部。
  String? get _modelFilterLabel {
    final f = _modelFilter;
    if (f == null) return null;
    if (f == kGenericModelFilter) return kGenericModelLabel;
    for (final g in ArtistModelGroup.values) {
      if (g.name == f) return g.filterLabel;
    }
    return null;
  }

  /// 作者的显示名:查得到昵称就显示昵称,查不到就是那串 QQ 号。
  String _authorLabel(String id) => _authorNames[id] ?? id;

  /// 漏斗里的两维有没有在筛(空列表的说法要跟着变:是"没匹配上"而不是"库是空的")。
  bool get _narrowed => _authorFilter != null || _modelFilter != null;

  /// 药丸上的字;null = 没在筛、也是默认排序。几维都改着就并排写 ——
  /// 「有没有在筛、筛的哪一档」得一眼看见,否则会出现"我的串怎么少了"。
  String? get _filterPillLabel {
    final parts = [
      if (_authorFilter != null) _authorLabel(_authorFilter!),
      ?_modelFilterLabel,
      if (_sortMode != defaultTagSort(_cat)) _sortMode.label,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 搜索框右侧的筛选入口:没筛时是个漏斗图标,筛着时变成带 × 的药丸。
  Widget _filterButton(ColorScheme scheme) {
    final label = _filterPillLabel;
    if (label == null) {
      return IconButton(
        tooltip: '筛选',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Icons.filter_alt_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        onPressed: _pickFilters,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 昵称可长可短,药丸宽度封顶在 suffixIconConstraints,超了就截断
            Flexible(
              child: InkWell(
                onTap: _pickFilters,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelMedium!.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() {
                _authorFilter = null;
                _modelFilter = null;
                _sortOverride = null;
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 5, 8, 5),
                child: Icon(Icons.close, size: 15, color: scheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFilters() async {
    // 候选作者只从**当前 scope 里真有的条目**上点:公共 tab 数公共库、我的 tab
    // 数我的那些,免得补全里列出一串在这个列表里根本搜不到的人。
    final lib = ref.read(tagLibraryProvider).value ?? const TagLibraryState();
    final pub = ref.read(publicTagsProvider(_cat)).value;
    final scope = _tabIndex == 1 && _def.hasPublic
        ? (pub ?? const <TagEntry>[])
        : mergeMineTags(
            lib.of(_cat),
            ref.read(botSessionProvider).value?.botUserId,
            pub,
          );
    final picked = await showTagFilterSheet(
      context,
      authors: collectTagAuthors(scope, _authorNames),
      current: (author: _authorFilter, model: _modelFilter, sort: _sortMode),
      // 适用模型只有画风有;角色那张表就少这一节。
      hasModels: _cat == TagCategory.artist,
      sorts: tagSortOptions(_cat),
      defaultSort: defaultTagSort(_cat),
    );
    if (!mounted || picked == null) return; // null = 点外面关掉,不改
    setState(() {
      _authorFilter = picked.author;
      _modelFilter = picked.model;
      _sortOverride = picked.sort;
    });
  }

  Widget _filterChips(TagLibraryState lib) => TagFilterChips(
    tags: lib.knownTags(_cat),
    filter: _validFilter(lib),
    onChanged: (filter) => setState(() => _filter = filter),
    onManageTags: () => showTagPoolSheet(context, ref, _cat),
    edge: _kEdge,
  );

  // ---- 我的 / 公共库 ----

  Widget _mineTab(TagLibraryState lib) {
    final list = _mineList(lib);
    if (list.isEmpty) {
      final narrowed = _search.isNotEmpty || _filter != null || _narrowed;
      return _empty(
        narrowed ? '没有匹配的${_def.label}' : '还没有${_def.label}',
        action: narrowed
            ? null
            : ('新建${_def.label}', () => widget.host._openNew(_cat)),
      );
    }
    // 按作者排序:整个 scope 改成一个作者一栏(我的这边同理 —— 自建的归自己
    // 那栏,收藏来的归原作者,「我收藏了谁的东西」一眼能看出来)
    if (_sortMode == TagSort.author) {
      final groups = _authorGroups(list);
      return _railWrap(groups, _mineScroll, _grid(groups, _mineScroll, false));
    }
    // 自建/我发布的在上,公共库收藏来的单独一组在下(对齐 web)
    final mine = [
      for (final e in list)
        if (e.origin != TagOrigin.favorited) e,
    ];
    final fav = [
      for (final e in list)
        if (e.origin == TagOrigin.favorited) e,
    ];
    // 只有一组、条数又已经写在分段上时不出区头
    final headed = (mine.isNotEmpty && fav.isNotEmpty) || !_def.hasPublic;
    final groups = <_Group>[
      if (mine.isNotEmpty)
        (
          header: headed
              ? _sectionHeader(Icons.favorite, '我的${_def.label}', mine.length)
              : null,
          items: mine,
        ),
      if (fav.isNotEmpty)
        (
          header: headed
              ? _sectionHeader(
                  Icons.star_rounded,
                  '收藏的${_def.label}',
                  fav.length,
                  muted: true,
                )
              : null,
          items: fav,
        ),
    ];
    return _railWrap(groups, _mineScroll, _grid(groups, _mineScroll, false));
  }

  Widget _publicTab(TagLibraryState lib) {
    final async = ref.watch(publicTagsProvider(_cat));
    // 骨架 → 内容之间淡入淡出,不硬切
    return AnimatedSwitcher(
      duration: Motion.medium,
      child: KeyedSubtree(
        key: ValueKey(
          async.isLoading
              ? 'sk'
              : async.hasError
              ? 'err'
              : 'data',
        ),
        child: _publicContent(async),
      ),
    );
  }

  Widget _publicContent(AsyncValue<List<TagEntry>> async) {
    return async.when(
      loading: () => pinchBuilder(
        (_) => _SkeletonGrid(aspect: _cardAspect, cols: gridColumns),
      ),
      error: (e, _) {
        // 会话过期后端回 401/403,与无会话同样按暂未开放显示,
        // 别让人困在「重试永远失败」里。
        final needBot =
            (e is StateError && e.message == 'need-bot') ||
            (e is BackendException && (e.status == 401 || e.status == 403));
        if (needBot) return _empty('公共库暂未开放');
        return _empty('公共库加载失败', action: ('重试', _reloadPublic));
      },
      data: (all) {
        final list = _publicList(all);
        if (list.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => _reloadPublic(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 320,
                  child: _empty(
                    _search.isNotEmpty || _narrowed
                        ? '没有匹配的${_def.label}'
                        : '公共库暂无内容',
                  ),
                ),
              ],
            ),
          );
        }
        final groups = _sortMode == TagSort.author
            ? _authorGroups(list)
            : <_Group>[(header: null, items: list)];
        return RefreshIndicator(
          onRefresh: () async => _reloadPublic(),
          child: _railWrap(groups, _pubScroll, _grid(groups, _pubScroll, true)),
        );
      },
    );
  }

  /// 下拉刷新 / 重试:公共库和作者目录一起重来 —— 只刷条目的话,新作者的
  /// 昵称要等下次冷启动才补得上,列表里会先冒出一串光秃秃的 QQ 号。
  void _reloadPublic() {
    ref.invalidate(publicTagsProvider(_cat));
    ref.invalidate(tagAuthorNamesProvider);
  }

  /// 按作者切组:一个作者一栏,条目多的在前;没署名的老数据兜底成「未认领」
  /// 收在最后(对齐 web 的分组画廊)。标题写成 `昵称(QQ 号)`。
  List<_Group> _authorGroups(List<TagEntry> list) {
    final byAuthor = <String, List<TagEntry>>{};
    final unclaimed = <TagEntry>[];
    for (final e in list) {
      final id = e.createdBy?.trim();
      if (id == null || id.isEmpty) {
        unclaimed.add(e);
      } else {
        (byAuthor[id] ??= []).add(e);
      }
    }
    final ids = byAuthor.keys.toList()
      ..sort((a, b) {
        final c = byAuthor[b]!.length.compareTo(byAuthor[a]!.length);
        return c != 0 ? c : _authorLabel(a).compareTo(_authorLabel(b));
      });
    return [
      for (final id in ids)
        (
          header: _sectionHeader(
            Icons.account_circle_outlined,
            authorDisplay(id, _authorNames),
            byAuthor[id]!.length,
          ),
          items: byAuthor[id]!,
        ),
      if (unclaimed.isNotEmpty)
        (
          header: _sectionHeader(
            Icons.no_accounts_outlined,
            '未认领',
            unclaimed.length,
            muted: true,
          ),
          items: unclaimed,
        ),
    ];
  }

  Widget _sectionHeader(
    IconData icon,
    String label,
    int count, {
    bool muted = false,
  }) {
    final scheme = context.scheme;
    final color = muted ? scheme.onSurfaceVariant : scheme.primary;
    return SizedBox(
      height: 32,
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            // 作者栏的标题是 `昵称(QQ 号)`,可以很长:最多占七成,截断。
            // 不用 Flexible:它和后面 Expanded 的分隔线按 1:1 分余量,
            // 标题用不完的那一半就空着,线只画到一半
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * .7),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: context.texts.labelMedium!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text, {(String, VoidCallback)? action}) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_def.icon, size: 44, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Text(
            text,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: action.$2,
              style: context.pageTonalStyle,
              child: Text(action.$1),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 网格 + 字母导航 ----

  static const _headerH = 32.0;

  /// 没区头的那组离上面一行的距离。
  static const _headlessTop = 6.0;

  /// 一组网格之前占的高度(区头 + 间距)。
  static double _groupLead(_Group g) =>
      g.header == null ? _headlessTop : 2 + _headerH + 8;

  /// 卡片 = 预览图比例:cover 下整图完整铺满、不裁切。
  double get _cardAspect => _def.previewAspect;

  Widget _grid(List<_Group> groups, ScrollController ctrl, bool isPublic) {
    final pubPreview = publicPreviewsOf(
      ref.read(publicTagsProvider(_cat)).value,
    );
    // 分组、预览表在外面算好;捏合与过渡只重建下面这一块(见 pinchBuilder)
    return pinchBuilder((_) {
      // 远端预览按**落定**列数下的格宽解码(gridColumns 在换档过渡中是起点那一档)。
      // 不给的话 RemoteImage 按实时格宽解码,过渡那几百毫秒里每一帧都是一路新解码。
      final cols = gridColumns;
      final decodeW =
          (MediaQuery.sizeOf(context).width - _kEdge * 2 - _gap * (cols - 1)) /
          cols;
      return CustomScrollView(
        // 换分类 / 分段即换一份列表,从各自的滚动账上落位
        key: ValueKey(_scrollKey(_cat, isPublic)),
        controller: ctrl,
        physics: pinchPhysics(const AlwaysScrollableScrollPhysics()),
        slivers: [
          for (final g in groups) ...[
            if (g.header case final header?)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(_kEdge, 2, _kEdge, 0),
                sliver: SliverToBoxAdapter(child: header),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                _kEdge,
                g.header == null ? _headlessTop : 8,
                _kEdge,
                16,
              ),
              sliver: SliverGrid(
                gridDelegate: zoomGridDelegate(
                  (n) => SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: n,
                    mainAxisSpacing: _gap,
                    crossAxisSpacing: _gap,
                    childAspectRatio: _cardAspect,
                  ),
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final e = g.items[i];
                  // 打码的公共条目:第一下点开原图,之后才是选择
                  final masked =
                      isPublic &&
                      e.mosaic &&
                      !_revealed.contains(_revealKey(e));
                  final preview = tagPreviewOf(e, pubPreview);
                  return TagCard(
                    key: ValueKey(e.id),
                    entry: e,
                    previewUrl: preview,
                    decodeWidth: decodeW,
                    selected: _sel.contains(e.id),
                    isPublic: isPublic,
                    mosaic: masked,
                    collected:
                        isPublic &&
                        ref
                            .read(tagLibraryProvider.notifier)
                            .isCollected(
                              _cat,
                              publicId: e.publicId,
                              name: e.name,
                            ),
                    onTap: masked
                        ? () => setState(() => _revealed.add(_revealKey(e)))
                        : () => widget.host._toggle(_cat, e),
                    onLift: (r) => _lift(e, r, preview, isPublic, masked),
                    onCollect: isPublic ? () => widget.host._collect(e) : null,
                  );
                }, childCount: g.items.length),
              ),
            ),
          ],
        ],
      );
    });
  }

  /// 画风分类包一层右缘字母导航。**只在按编号排时**有:换成时间/作者以后
  /// 列表不再是字母序,字母条跳过去就是错位。没有字母条的列表挂快速滚动把手
  /// (公共画风除外)。
  Widget _railWrap(List<_Group> groups, ScrollController ctrl, Widget child) {
    final total = groups.fold(0, (n, g) => n + g.items.length);
    if (!_def.alphabetRail || _sortMode != TagSort.number || total < 12) {
      final publicArtist =
          _cat == TagCategory.artist && identical(ctrl, _pubScroll);
      return publicArtist ? child : FastScrollHandle(child: child);
    }
    // 用 Set 去重:'#' 桶(数字开头排最前、CJK 排最后)可能不相邻,
    // 只留首次出现,跳转恒到首个。
    final seen = <String>{};
    final letters = <String>[
      for (final g in groups)
        for (final e in g.items)
          if (seen.add(letterOfName(e.name))) letterOfName(e.name),
    ];
    return Stack(
      children: [
        child,
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          child: _LetterRail(
            letters: letters,
            onSelect: (l) => _jumpToLetter(groups, ctrl, l),
          ),
        ),
      ],
    );
  }

  void _jumpToLetter(List<_Group> groups, ScrollController ctrl, String l) {
    if (!ctrl.hasClients) return;
    final cols = gridColumns;
    final w = context.size?.width ?? 400;
    final itemW = (w - _kEdge * 2 - _gap * (cols - 1)) / cols;
    final rowExtent = itemW / _cardAspect + _gap;
    // 逐组累加(组头 + 该组行高),命中组内再按行偏移
    var offset = 0.0;
    for (final g in groups) {
      final i = g.items.indexWhere((e) => letterOfName(e.name) == l);
      final rows = (g.items.length + cols - 1) ~/ cols;
      if (i >= 0) {
        offset += _groupLead(g) + (i ~/ cols) * rowExtent;
        ctrl.jumpTo(offset.clamp(0.0, ctrl.position.maxScrollExtent));
        return;
      }
      offset += _groupLead(g) + rows * rowExtent + 16;
    }
  }

  /// 长按卡片:抬起 + 菜单。我的:编辑 / 复制 / 查看提示词 / 删除;
  /// 公共:查看提示词 / 复制 / 收藏。
  Future<void> _lift(
    TagEntry e,
    Rect from,
    String? preview,
    bool isPublic,
    bool masked,
  ) async {
    final action = await showLiftMenu<String>(
      context,
      from: from,
      aspect: _cardAspect,
      preview: TagCardPreview(url: preview, name: e.name, mosaic: masked),
      actions: [
        if (!isPublic) (icon: Icons.edit_outlined, label: '编辑', value: 'edit'),
        (icon: Icons.notes, label: '查看提示词', value: 'detail'),
        (icon: Icons.copy, label: '复制提示词', value: 'copy'),
        if (isPublic)
          (icon: Icons.favorite_border, label: '收藏', value: 'collect'),
      ],
      danger: isPublic
          ? null
          : (icon: Icons.delete_outline, label: '删除', value: 'delete'),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        unawaited(
          Navigator.of(
            context,
          ).push(sharedAxisRoute(TagEditorPage(cat: _cat, edit: e))),
        );
      case 'detail':
        unawaited(showTagDetailSheet(context, e));
      case 'copy':
        await Clipboard.setData(ClipboardData(text: e.positive));
        if (mounted) hintSnack(context, '已复制提示词', icon: Icons.copy);
      case 'collect':
        await widget.host._collect(e);
      case 'delete':
        await widget.host._deleteEntries([e]);
    }
  }
}

/// 让 PageView 里的页离屏后也留着。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ---- 卡片 ----

/// 公共库加载态:骨架网格(卡片形状 + 呼吸微光),比干等一个转圈更有"内容在来"。
class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid({required this.aspect, required this.cols});

  final double aspect;
  final int cols;

  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return GridView.count(
      crossAxisCount: widget.cols,
      padding: const EdgeInsets.fromLTRB(_kEdge, 6, _kEdge, 16),
      mainAxisSpacing: _gap,
      crossAxisSpacing: _gap,
      childAspectRatio: widget.aspect,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < widget.cols * 3; i++)
          FadeTransition(
            opacity: Tween(
              begin: .35,
              end: .7,
            ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.raisedFill(scheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
      ],
    );
  }
}

/// 右缘字母导航条(画风):按住/竖向拖动跳转到该字母首个条目,
/// 交互时左侧弹出当前字母气泡。触区即胶囊本身,不越界抢网格滚动。
class _LetterRail extends StatefulWidget {
  const _LetterRail({required this.letters, required this.onSelect});

  final List<String> letters;
  final ValueChanged<String> onSelect;

  @override
  State<_LetterRail> createState() => _LetterRailState();
}

class _LetterRailState extends State<_LetterRail>
    with SingleTickerProviderStateMixin {
  /// 胶囊 = 触摸宽度;气泡半径(高 46 的一半)。
  static const _railW = 24.0;
  static const _bubbleR = 23.0;

  final _key = GlobalKey();
  int _active = -1; // 当前命中字母下标;-1=未按住

  /// 交互显隐:按住 forward、松手 reverse。驱动胶囊加深、字母放大波、
  /// 气泡淡入淡出——让整条随手指"活"起来,而非硬切。
  late final AnimationController _reveal =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 130),
        reverseDuration: const Duration(milliseconds: 170),
      )..addStatusListener((s) {
        // 收完动画再清 _active,气泡/放大得以在原位平滑退场。
        if (s == AnimationStatus.dismissed && _active != -1) {
          setState(() => _active = -1);
        }
      });

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final n = widget.letters.length;
    return SizedBox(
      width: _railW,
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          const vPad = 10.0;
          // 字母多/屏矮时等比压缩槽高,band 竖向居中;命中与气泡都按同一几何算。
          final slot = n == 0 ? 0.0 : ((h - vPad * 2) / n).clamp(0.0, 22.0);
          final bandTop = (h - slot * n) / 2;

          void update(Offset global) {
            final box = _key.currentContext?.findRenderObject() as RenderBox?;
            if (box == null || n == 0 || slot <= 0) return;
            final dy = box.globalToLocal(global).dy;
            final i = ((dy - bandTop) / slot).floor().clamp(0, n - 1);
            if (i != _active) {
              Haptics.selection();
              widget.onSelect(widget.letters[i]);
              setState(() => _active = i);
            }
            _reveal.forward();
          }

          void stop() => _reveal.reverse();

          return GestureDetector(
            key: _key,
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => update(d.globalPosition),
            onTapUp: (_) => stop(),
            onTapCancel: stop,
            onVerticalDragStart: (d) => update(d.globalPosition),
            onVerticalDragUpdate: (d) => update(d.globalPosition),
            onVerticalDragEnd: (_) => stop(),
            onVerticalDragCancel: stop,
            child: AnimatedBuilder(
              animation: _reveal,
              builder: (context, _) {
                final r = _reveal.value; // 0=静默 1=按住
                final active = _active;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 字母条胶囊:常态半透明可见(可发现),按住渐深。
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: _railW,
                          height: slot * n + vPad,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.pageControlFill.withValues(
                              alpha: .55 + .41 * r,
                            ),
                            borderRadius: BorderRadius.circular(_railW / 2),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: .5 * (1 - r),
                              ),
                              width: .5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < n; i++)
                                SizedBox(
                                  height: slot,
                                  child: Center(
                                    child: _letter(i, active, r, scheme),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 气泡:向左弹出当前字母,尾巴指向字母条;
                    // 竖向随命中槽滑动(AnimatedPositioned),按住/松手淡入淡出。
                    if (active >= 0 && active < n)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 65),
                        curve: Curves.easeOut,
                        right: _railW + 6,
                        top: bandTop + (active + 0.5) * slot - _bubbleR,
                        child: Opacity(
                          opacity: r.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale:
                                .6 +
                                .4 *
                                    Curves.easeOutBack.transform(
                                      r.clamp(0.0, 1.0),
                                    ),
                            alignment: Alignment.centerRight,
                            child: _LetterBubble(
                              widget.letters[active],
                              color: scheme.primary,
                              fg: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 单个字母:离命中点越近越大越亮(放大波),幅度乘 [r] 让它随按住淡入淡出。
  Widget _letter(int i, int active, double r, ColorScheme scheme) {
    final dist = active < 0 ? 999.0 : (i - active).abs().toDouble();
    final prox = (1 - dist / 2.6).clamp(0.0, 1.0) * r; // 命中点 ±2~3 个字母的邻域
    return Transform.scale(
      scale: 1 + .5 * prox,
      child: Text(
        widget.letters[i],
        style: TextStyle(
          fontSize: 10.5,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Color.lerp(scheme.onSurfaceVariant, scheme.primary, prox),
        ),
      ),
    );
  }
}

/// 字母气泡:圆形 + 右向小尾巴(指向字母条),软阴影浮起。
class _LetterBubble extends StatelessWidget {
  const _LetterBubble(this.letter, {required this.color, required this.fg});

  final String letter;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(color),
      child: SizedBox(
        width: 54,
        height: 46,
        // 尾巴占右 8px,文字回退到圆心。
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final center = Offset(r, r);
    final body = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    final tail = Path()
      ..moveTo(center.dx + r - 7, center.dy - 9)
      ..lineTo(size.width, center.dy)
      ..lineTo(center.dx + r - 7, center.dy + 9)
      ..close();
    final shape = Path.combine(PathOperation.union, body, tail);
    canvas.drawShadow(shape, Colors.black.withValues(alpha: .4), 4, false);
    canvas.drawPath(
      shape,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.color != color;
}

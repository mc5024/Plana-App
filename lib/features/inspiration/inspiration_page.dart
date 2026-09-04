import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/remote_image.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/scroll_memory.dart';
import '../../core/ui/selection_bar.dart';
import '../editor/editor_models.dart' show draftOf, outputOf, pickEditorText;
import '../generate/gen_modules.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart' show maxCharactersOf;
import '../generate/widgets/common.dart'
    show confirmDialog, hintSnack, sharedAxisRoute;
import '../shell/shell_state.dart';
import 'codex/codex_view.dart';
import 'artist_models.dart';
import 'public_tags.dart';
import 'tag_editor_page.dart';
import 'tag_library.dart';
import 'tag_models.dart';
import 'widgets/tag_filter_sheet.dart';
import 'widgets/tag_sheets.dart';
import '../../core/util/haptics.dart';

/// 顶部各行统一的左右边距;行尾若是 IconButton,用 [_kIconEdge]
/// (减去按钮 8px 内衬)让图标视觉边与其他行对齐。
const _kEdge = 14.0;
const _kIconEdge = 6.0;

/// 网格分组:一个区头 + 该组条目(我的/收藏的/公共)。
typedef _Group = ({Widget header, List<TagEntry> items});

/// 网格卡片间距(骨架与真实网格共用,保证切换时不跳位)。
const _gap = 10.0;

/// 灵感页:web Tag 管理器的移动端形态(底部 tab 常驻页,非弹窗)。
/// 布局随 Vibe 管理器(搜索 + 我的/公共库分段 + 网格 + 底部操作条),
/// 分类切换走左侧抽屉(角色/画风/场景/其他;自定义分类未开放,不做)。
class InspirationPage extends ConsumerStatefulWidget {
  const InspirationPage({super.key});

  @override
  ConsumerState<InspirationPage> createState() => _InspirationPageState();
}

class _InspirationPageState extends ConsumerState<InspirationPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  TagCategory _cat = TagCategory.character;

  /// 选中「法典」分类:正文切换为只读的法典浏览器 [CodexView],其余分类照旧。
  /// 法典不属于 [TagCategory](无我的/公共库、无备份/新建),故独立成一个模式位,
  /// 不污染四类标签库的分支逻辑。
  bool _codex = false;
  static const _kCodexSel = '__codex__';

  late final TabController _tab = TabController(length: 2, vsync: this);
  // 初始分类的记忆直接灌进 initialScrollOffset;换分类走 _switchCategory 落位。
  late final _mineScroll = ScrollController(
    initialScrollOffset: ScrollMemory.read(_scrollKey(_cat, false)) ?? 0,
  );
  late final _pubScroll = ScrollController(
    initialScrollOffset: ScrollMemory.read(_scrollKey(_cat, true)) ?? 0,
  );

  /// 每分类已选 id(我的/公共库两 scope 共用一套,对齐 web selectionMap)。
  final Map<TagCategory, Set<String>> _selected = {};

  String _search = '';

  /// 筛选:null=全部;[_kFavFilter]=收藏;其余为标签名。
  String? _filter;
  static const _kFavFilter = ' fav';

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

  /// 排序档,每个分类记各的。与搜索/筛选不同,**换分类不重置** —— 它是「我想
  /// 怎么看这一类」的偏好,回来还想看到上次那个排法。
  final Map<TagCategory, TagSort> _sortBy = {};

  TagSort get _sortMode => _sortBy[_cat] ?? defaultTagSort(_cat);

  /// 批量操作进行中(禁重入)。
  bool _busy = false;

  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // 只在整数位变化时 setState(筛选行随 scope 显隐)。
    _tab.animation!.addListener(() {
      final i = _tab.animation!.value.round();
      if (i != _tabIndex && mounted) setState(() => _tabIndex = i);
    });
    _mineScroll.addListener(() => _saveScroll(_mineScroll, false));
    _pubScroll.addListener(() => _saveScroll(_pubScroll, true));
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

  Set<String> get _sel => _selected[_cat] ??= {};

  void _toggle(TagEntry e) {
    // 角色分类的单次可选数 = 角色卡槽位,跟当前模型走(NAI 5 是 20);
    // 其余分类仍用注册表里的静态上限。
    final cap = _cat == TagCategory.character
        ? maxCharactersOf(ref.read(generateProvider).params.model)
        : _def.maxSelectable;
    setState(() {
      if (_sel.contains(e.id)) {
        _sel.remove(e.id);
      } else if (_sel.length < cap) {
        _sel.add(e.id);
      } else {
        hintSnack(context, '最多选 $cap 个', icon: Icons.block_outlined);
      }
    });
  }

  /// 滚动记忆的账本 key:每个分类的两个 scope 各记各的。
  String _scrollKey(TagCategory c, bool pub) =>
      'inspiration.${c.name}.${pub ? 'public' : 'mine'}';

  /// 持续记账(内容不可滚时跳过,否则会把记忆冲成 0)。
  void _saveScroll(ScrollController ctrl, bool pub) {
    if (!ctrl.hasClients || ctrl.positions.length != 1) return;
    final p = ctrl.position;
    if (!p.hasContentDimensions || p.maxScrollExtent <= 0) return;
    ScrollMemory.write(_scrollKey(_cat, pub), p.pixels);
  }

  void _jumpTo(ScrollController ctrl, double want) {
    if (!ctrl.hasClients || ctrl.positions.length != 1) return;
    final p = ctrl.position;
    if (!p.hasContentDimensions) return;
    final target = want.clamp(0.0, p.maxScrollExtent);
    if ((p.pixels - target).abs() > 1) ctrl.jumpTo(target);
  }

  void _switchCategory(TagCategory c) {
    if (c == _cat) return;
    // 目标位置必须在换 _cat **之前**读:换完之后旧偏移还挂在同一个控制器上,
    // 记账监听会先把旧值写进新分类的账,读到的就不是原位了。
    final wantMine = ScrollMemory.read(_scrollKey(c, false)) ?? 0;
    final wantPub = ScrollMemory.read(_scrollKey(c, true)) ?? 0;
    setState(() {
      _cat = c;
      _search = '';
      _filter = null;
      _modelFilter = null;
      _authorFilter = null;
      if (!tagCategoryDef(c).hasPublic) _tab.index = 0;
    });
    // 新分类的列表要等这一帧布好才有 maxScrollExtent,落位排到帧后。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpTo(_mineScroll, wantMine);
      _jumpTo(_pubScroll, wantPub);
    });
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
      ? _mergeMine(
          lib.of(_cat),
          ref.watch(botSessionProvider).value?.botUserId,
          ref.watch(publicTagsProvider(_cat)).value,
        )
      : lib.of(_cat);

  /// [_mineAll] 的纯函数体 —— 筛选弹层要在 build 之外拿同一份来源点候选作者,
  /// 那里不能 watch,只能把读来的值喂进来。
  static List<TagEntry> _mergeMine(
    List<TagEntry> local,
    String? myId,
    List<TagEntry>? pub,
  ) {
    if (myId == null || pub == null) return local;
    final haveId = {for (final e in local) e.publicId};
    final haveName = {for (final e in local) e.name};
    return [
      ...local,
      for (final p in pub)
        if (p.createdBy == myId &&
            !haveId.contains(p.publicId) &&
            !haveName.contains(p.name))
          p.copyWith(origin: TagOrigin.created),
    ];
  }

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
  }

  /// 角色 → 加入角色卡(带名追加,上限按模型截断,见 maxCharactersOf)。
  Future<void> _confirmAsCharacters(TagLibraryState lib) async {
    final entries = _resolveSelected(lib);
    if (entries.isEmpty) return;
    final cap = maxCharactersOf(ref.read(generateProvider).params.model);
    final added = ref.read(generateProvider.notifier).addNamedCharactersFrom([
      for (final e in entries)
        (name: e.name, positive: e.positive, negative: e.negative),
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
  Future<void> _confirmToPrompt(TagLibraryState lib) async {
    final entries = _resolveSelected(lib);
    if (entries.isEmpty) return;
    final gen = ref.read(generateProvider);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = context.scheme;
    final lib = ref.watch(tagLibraryProvider).value ?? const TagLibraryState();
    final def = _def;
    _authorNames = ref.watch(tagAuthorNamesProvider).value ?? const {};

    // 法典模式:只留分类胶囊的顶栏 + 只读浏览器,无搜索/分段/筛选/选择栏
    // (法典自带选择器与搜索)。
    if (_codex) {
      return Scaffold(
        body: Column(
          children: [
            _topBarCodex(scheme, lib),
            const Expanded(child: CodexView()),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _topBar(scheme, lib),
          Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 0),
            child: TextField(
              key: ValueKey('tag-search-${def.webId}'),
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: def.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                // 「作者 / 适用模型」筛选挂在搜索框里:它们和左边的标签筛选是正交
                // 维度,塞进同一条 chip 行既会让人以为是同一组单选,标签一多还会被
                // 挤到屏幕外。挂这儿两个 scope 都有,且不多占一行高度。
                // 只给有公共库的两类(角色/画风)—— 场景/其他的条目全是自己的,
                // 没有「别人」可筛。
                suffixIcon: def.hasPublic ? _filterButton(scheme) : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  maxWidth: 190,
                ),
              ),
            ),
          ),
          if (def.hasPublic)
            Padding(
              // 「我的」下面紧跟筛选行,间距由它顶出,这里不再留底距;
              // 公共态没有筛选行,分段行会直接贴上网格首个分组头(顶衬仅 2),
              // 补一档底距回到与上方各行相同的 8 节奏。
              padding: EdgeInsets.fromLTRB(
                _kEdge,
                8,
                _kEdge,
                _tabIndex == 0 ? 0 : 8,
              ),
              child: _segTabs(scheme, lib.of(_cat).length),
            ),
          if (_tabIndex == 0 || !def.hasPublic) _filterChips(lib),
          Expanded(
            // 禁 TabBarView 横滑:横滑手势留给 shell PageView 切底部 tab
            // (与场景/其他分类行为一致),scope 切换走分段控件点按。
            child: def.hasPublic
                ? TabBarView(
                    controller: _tab,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_mineTab(lib), _publicTab(lib)],
                  )
                : _mineTab(lib),
          ),
        ],
      ),
      bottomNavigationBar: _selectionBar(scheme, lib),
    );
  }

  Widget _topBar(ColorScheme scheme, TagLibraryState lib) {
    return Padding(
      // 行尾是 IconButton:右边距减去它的内衬,图标视觉边与其他行对齐
      padding: const EdgeInsets.fromLTRB(_kEdge, 6, _kIconEdge, 0),
      child: Row(
        children: [
          _categoryPill(scheme, lib),
          const Spacer(),
          // 排序只给有公共库的两类:场景/其他的条目全是自己的,没有作者可分组
          if (_def.hasPublic) _sortButton(scheme),
          IconButton(
            tooltip: '数据备份',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => showTagBackupSheet(context, ref),
          ),
          IconButton(
            tooltip: '新建',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(
              context,
            ).push(sharedAxisRoute(TagEditorPage(cat: _cat))),
          ),
        ],
      ),
    );
  }

  /// 顶栏的排序按钮。不是默认档时图标点主色 —— 「列表怎么变了个顺序」
  /// 得能一眼找到是这儿改的。
  Widget _sortButton(ColorScheme scheme) {
    final mode = _sortMode;
    final on = mode != defaultTagSort(_cat);
    return PopupMenuButton<TagSort>(
      tooltip: '排序:${mode.label}',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) => setState(() => _sortBy[_cat] = v),
      itemBuilder: (_) => [
        for (final s in tagSortOptions(_cat))
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Text(s.label),
                const Spacer(),
                if (s == mode)
                  Icon(Icons.check, size: 18, color: scheme.primary),
              ],
            ),
          ),
      ],
      icon: Icon(
        Icons.sort,
        color: on ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }

  /// 法典模式顶栏:左分类胶囊 + 右侧「选择主法典」(占用原本的空位,
  /// CodexView 不再自带头部整行)。
  Widget _topBarCodex(ColorScheme scheme, TagLibraryState lib) => Padding(
    padding: const EdgeInsets.fromLTRB(_kEdge, 6, _kEdge, 0),
    // 定高 48 与标签页 _topBar 对齐(那边由 IconButton 撑到 48,胶囊居中留 2px
    // 呼吸位)。否则本行仅胶囊高 44,整行偏矮、胶囊贴顶,比标签页明显偏上。
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          _categoryPill(scheme, lib),
          const SizedBox(width: 10),
          // 靠右、按内容自适应宽度(不撑满);标题过长时才截断
          const Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: CodexPickerButton(),
            ),
          ),
        ],
      ),
    ),
  );

  /// 分类选择(四类标签库 + 法典)。法典是特殊项:切模式,不走 [_switchCategory]。
  void _onPickCat(Object v) {
    if (v == _kCodexSel) {
      setState(() => _codex = true);
    } else if (v is TagCategory) {
      if (_codex) setState(() => _codex = false);
      _switchCategory(v);
    }
  }

  /// 分类切换:整块 filled 胶囊(图标+名称+计数+▾),点开下拉选分类。
  Widget _categoryPill(ColorScheme scheme, TagLibraryState lib) {
    return PopupMenuButton<Object>(
      tooltip: '切换分类',
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: _onPickCat,
      itemBuilder: (_) => [
        for (final d in kTagCategoryDefs)
          PopupMenuItem(
            value: d.key,
            child: _catMenuRow(
              scheme,
              d.icon,
              d.label,
              d.key == _cat && !_codex,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _kCodexSel,
          child: _catMenuRow(scheme, Icons.menu_book_outlined, '法典', _codex),
        ),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _codex
              ? [
                  Icon(Icons.menu_book, size: 19, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '法典',
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ]
              : [
                  Icon(_def.icon, size: 19, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    _def.label,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${lib.of(_cat).length}',
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
        ),
      ),
    );
  }

  /// 分类下拉的一行(图标 + 名称 + 选中勾)。
  Widget _catMenuRow(
    ColorScheme scheme,
    IconData icon,
    String label,
    bool sel,
  ) => Row(
    children: [
      Icon(
        icon,
        size: 19,
        color: sel ? scheme.primary : scheme.onSurfaceVariant,
      ),
      const SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
      ),
      const Spacer(),
      if (sel) Icon(Icons.check, size: 16, color: scheme.primary),
    ],
  );

  Widget _segTabs(ColorScheme scheme, int mineCount) {
    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // 视觉层:滑动指示器 + 渐变标签(随 tab 动画重建,无手势)。
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _tab.animation!,
                builder: (context, _) {
                  final t = _tab.animation!.value.clamp(0.0, 1.0);
                  return LayoutBuilder(
                    builder: (context, c) {
                      final segW = c.maxWidth / 2;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 3,
                            bottom: 3,
                            left: 3 + t * segW,
                            width: segW - 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _segLabel(
                                0,
                                Icons.bookmark_outline,
                                '我的 · $mineCount',
                                t,
                              ),
                              _segLabel(1, Icons.public, '公共库', t),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // 手势层:稳定不重建,整段任意位置可点。
            Positioned.fill(
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tab.animateTo(i),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segLabel(int i, IconData icon, String label, double t) {
    final scheme = context.scheme;
    final sel = i == 0 ? 1 - t : t;
    final color = Color.lerp(scheme.onSurfaceVariant, scheme.primary, sel);
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.texts.labelLarge!.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
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

  /// 药丸上的字;null = 没在筛。两维都筛着就并排写 ——「有没有在筛、筛的哪一档」
  /// 得一眼看见,否则会出现"我的串怎么少了"。
  String? get _filterPillLabel {
    final parts = [
      if (_authorFilter != null) _authorLabel(_authorFilter!),
      ?_modelFilterLabel,
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
        : _mergeMine(
            lib.of(_cat),
            ref.read(botSessionProvider).value?.botUserId,
            pub,
          );
    final picked = await showTagFilterSheet(
      context,
      authors: collectTagAuthors(scope, _authorNames),
      current: (author: _authorFilter, model: _modelFilter),
      // 适用模型只有画风有;角色那张表就少这一节。
      hasModels: _cat == TagCategory.artist,
    );
    if (!mounted || picked == null) return; // null = 点外面关掉,不改
    setState(() {
      _authorFilter = picked.author;
      _modelFilter = picked.model;
    });
  }

  /// 「全部 / 收藏 / 标签…」筛选行(我的 scope;标签=池∪在用)。
  /// 药丸 chip + 主色实底标记选中,与 Vibe 管理器同款。
  Widget _filterChips(TagLibraryState lib) {
    final scheme = context.scheme;
    final tags = lib.knownTags(_cat);
    final filter = _validFilter(lib);
    Widget chip(String label, bool sel, VoidCallback onTap, {IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            // 图标放进 label(自控间距),不用 avatar(默认间距太大)
            label: icon == null
                ? Text(label)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(label),
                    ],
                  ),
            selected: sel,
            onSelected: (_) => onTap(),
            visualDensity: VisualDensity.compact,
            shape: const StadiumBorder(),
            labelStyle: context.texts.labelMedium!.copyWith(
              fontWeight: FontWeight.w600,
              color: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            selectedColor: scheme.primary,
            backgroundColor: scheme.surfaceContainerHigh,
            side: BorderSide.none,
            showCheckmark: false,
          ),
        );
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            // 横向滚动:标签再多也不会溢出
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(_kEdge, 4, 4, 4),
              children: [
                chip(
                  '全部',
                  filter == null,
                  () => setState(() => _filter = null),
                ),
                chip(
                  '收藏',
                  filter == _kFavFilter,
                  () => setState(() => _filter = _kFavFilter),
                  icon: Icons.star_rounded,
                ),
                for (final t in tags)
                  chip(
                    t,
                    filter == t,
                    () => setState(() => _filter = _filter == t ? null : t),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '标签池管理',
            icon: Icon(
              Icons.settings_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: () => showTagPoolSheet(context, ref, _cat),
          ),
          const SizedBox(width: _kIconEdge),
        ],
      ),
    );
  }

  // ---- 我的 / 公共库 ----

  Widget _mineTab(TagLibraryState lib) {
    final list = _mineList(lib);
    if (list.isEmpty) {
      return _empty(
        _search.isNotEmpty || _filter != null || _narrowed
            ? '没有匹配的${_def.label}'
            : '还没有${_def.label},点右上角 + 新建',
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
    final groups = <_Group>[
      if (mine.isNotEmpty)
        (
          header: _sectionHeader(
            Icons.favorite,
            '我的${_def.label}',
            mine.length,
          ),
          items: mine,
        ),
      if (fav.isNotEmpty)
        (
          header: _sectionHeader(
            Icons.star_rounded,
            '收藏的${_def.label}',
            fav.length,
            muted: true,
          ),
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
      loading: () => _SkeletonGrid(aspect: _cardAspect),
      error: (e, _) {
        // 会话过期后端回 401/403,与无会话同样给「去授权」出口,
        // 别让人困在「重试永远失败」里。
        final needBot =
            (e is StateError && e.message == 'need-bot') ||
            (e is BackendException && (e.status == 401 || e.status == 403));
        if (needBot) {
          return _empty(
            '公共库需要 Bot 授权',
            action: (
              '去授权',
              () => ref.read(shellIndexProvider.notifier).select(kTabProfile),
            ),
          );
        }
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
            : <_Group>[
                (
                  header: _sectionHeader(
                    Icons.public,
                    '公共${_def.label}',
                    list.length,
                  ),
                  items: list,
                ),
              ];
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
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          // 作者栏的标题是 `昵称(QQ 号)`,可以很长:截断,别把分隔线顶出行外
          Flexible(
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
            FilledButton.tonal(onPressed: action.$2, child: Text(action.$1)),
          ],
        ],
      ),
    );
  }

  // ---- 网格 + 字母导航 ----

  static const _headerH = 32.0;

  /// 卡片 = 预览图比例:cover 下整图完整铺满、不裁切。
  double get _cardAspect => _def.previewAspect;

  Widget _grid(List<_Group> groups, ScrollController ctrl, bool isPublic) {
    // 有 publicId 的条目(收藏/我发布的)一律用当前公共库的 http 预览:
    // 随当前后端地址,不受备份剥离本机预览、也不受端口变化影响。
    final pubPreview = <String, String>{
      for (final p
          in ref.read(publicTagsProvider(_cat)).value ?? const <TagEntry>[])
        if (p.publicId != null && p.previewUrl != null)
          p.publicId!: p.previewUrl!,
    };
    return CustomScrollView(
      controller: ctrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final g in groups) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 2, _kEdge, 0),
            sliver: SliverToBoxAdapter(child: g.header),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: _gap,
                crossAxisSpacing: _gap,
                childAspectRatio: _cardAspect,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final e = g.items[i];
                final preview =
                    (e.publicId != null ? pubPreview[e.publicId] : null) ??
                    e.previewUrl;
                return _TagCard(
                  key: ValueKey(e.id),
                  entry: e,
                  previewUrl: preview,
                  selected: _sel.contains(e.id),
                  isPublic: isPublic,
                  collected:
                      isPublic &&
                      ref
                          .read(tagLibraryProvider.notifier)
                          .isCollected(
                            _cat,
                            publicId: e.publicId,
                            name: e.name,
                          ),
                  onTap: () => _toggle(e),
                  onLongPress: () => showTagDetailSheet(context, e),
                  onCollect: isPublic ? () => _collect(e) : null,
                  onMenu: isPublic ? null : (v) => _cardMenu(v, e),
                );
              }, childCount: g.items.length),
            ),
          ),
        ],
      ],
    );
  }

  /// 画风分类包一层右缘字母导航。**只在按编号排时**有:换成时间/作者以后
  /// 列表不再是字母序,字母条跳过去就是错位。
  Widget _railWrap(List<_Group> groups, ScrollController ctrl, Widget child) {
    final total = groups.fold(0, (n, g) => n + g.items.length);
    if (!_def.alphabetRail || _sortMode != TagSort.number || total < 12) {
      return child;
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
    final w = context.size?.width ?? 400;
    final itemW = (w - _kEdge * 2 - _gap) / 2;
    final rowExtent = itemW / _cardAspect + _gap;
    // 逐组累加(组头 + 该组行高),命中组内再按行偏移
    var offset = 0.0;
    for (final g in groups) {
      final i = g.items.indexWhere((e) => letterOfName(e.name) == l);
      final rows = (g.items.length + 1) ~/ 2;
      if (i >= 0) {
        offset += 2 + _headerH + 8 + (i ~/ 2) * rowExtent;
        ctrl.jumpTo(offset.clamp(0.0, ctrl.position.maxScrollExtent));
        return;
      }
      offset += 2 + _headerH + 8 + rows * rowExtent + 16;
    }
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

  Future<void> _cardMenu(String action, TagEntry e) async {
    switch (action) {
      case 'edit':
        unawaited(
          Navigator.of(
            context,
          ).push(sharedAxisRoute(TagEditorPage(cat: _cat, edit: e))),
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: e.positive));
        if (mounted) hintSnack(context, '已复制提示词', icon: Icons.copy);
      case 'delete':
        await _deleteEntries([e]);
    }
  }

  // ---- 底部操作条 ----

  /// 角色分类的动作:一体式分段胶囊 —— 左「主提示词」右「加入角色 N」,
  /// 同一主色底,中间发丝分隔,整体一颗药丸。
  Widget _splitAction(ColorScheme scheme, TagLibraryState lib, int n) {
    final bg = scheme.primary;
    final fg = scheme.onPrimary;
    Widget seg({
      required int flex,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) => Expanded(
      flex: flex,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelLarge!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      height: kSelectionActionHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kSelectionActionRadius),
        child: Row(
          children: [
            seg(
              flex: 5,
              icon: Icons.bolt_outlined,
              label: '主提示词',
              onTap: () => _confirmToPrompt(lib),
            ),
            Container(width: 1.5, color: scheme.surfaceContainer),
            seg(
              flex: 6,
              icon: Icons.person_add_alt,
              label: '加入角色',
              onTap: () => _confirmAsCharacters(lib),
            ),
          ],
        ),
      ),
    );
  }

  /// 角色模块对当前模型是否可见 —— 决定「加入角色」这个去处存不存在。
  /// anima 下 NAI 四件套整组收走(角色卡都不渲染),此时加进去的角色既不进
  /// 载荷也看不见,只会把提示词计数顶大,是个纯幽灵动作,故收起按钮。
  bool get _charModuleOn {
    final model = ref.watch(generateProvider.select((s) => s.params.model));
    final ms = ref.watch(genModulesProvider).value ?? const GenModuleSettings();
    return ms.isVisibleFor(GenModule.character, model);
  }

  Widget _selectionBar(ColorScheme scheme, TagLibraryState lib) {
    final n = _sel.length;
    final publicScope = _def.hasPublic && _tabIndex == 1;
    return SelectionBar(
      visible: n > 0,
      // shell 里的 tab 页,底部安全区由导航栏兜着
      safeArea: false,
      onClear: () => setState(() => _sel.clear()),
      actions: [
        if (publicScope)
          SelectionPill(
            icon: Icons.favorite_border,
            label: '收藏',
            onTap: _busy ? null : () => _batchCollect(lib),
          )
        else
          SelectionPill(
            icon: Icons.sell_outlined,
            label: '标签',
            onTap: _busy ? null : () => _batchTag(lib),
          ),
      ],
      destructive: publicScope
          ? null
          : SelectionPill(
              icon: Icons.delete_outline,
              label: '删除',
              color: scheme.error,
              onTap: _busy ? null : () => _batchDelete(lib),
            ),
      // 角色分类有两个去处,主动作是一体式分段按钮;角色模块不可见时
      // (anima 等)只剩「主提示词」一个去处,退回普通整条按钮
      primary: _cat == TagCategory.character && _charModuleOn
          ? _splitAction(scheme, lib, n)
          : FilledButton.icon(
              onPressed: () => _confirmToPrompt(lib),
              icon: const Icon(Icons.check, size: 18),
              label: Text('确认选择 ($n)'),
              style: selectionPrimaryStyle(),
            ),
    );
  }
}

// ---- 卡片 ----

/// 公共库加载态:骨架网格(卡片形状 + 呼吸微光),比干等一个转圈更有"内容在来"。
class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid({required this.aspect});

  final double aspect;

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
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(_kEdge, 42, _kEdge, 16),
      mainAxisSpacing: _gap,
      crossAxisSpacing: _gap,
      childAspectRatio: widget.aspect,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 6; i++)
          FadeTransition(
            opacity: Tween(
              begin: .35,
              end: .7,
            ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
      ],
    );
  }
}

/// 图片加载完淡入(缓存命中的同步图不淡),让预览逐张柔和显现而非硬蹦。
Widget _fadeInFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSync,
) {
  if (wasSync) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: Motion.medium,
    curve: Curves.easeOut,
    child: child,
  );
}

/// 网格卡:预览图(无图=名称定色相的斜纹占位)+ 底部名称条 + 来源角标;
/// 左上选择圈,右上 ⋮(我的)/ ❤ 收藏(公共)。点卡选择,长按看详情。
class _TagCard extends StatelessWidget {
  const _TagCard({
    super.key,
    required this.entry,
    this.previewUrl,
    required this.selected,
    required this.isPublic,
    this.collected = false,
    required this.onTap,
    required this.onLongPress,
    this.onCollect,
    this.onMenu,
  });

  final TagEntry entry;

  /// 实际渲染的预览(可能是按 publicId 从公共库补的 http,覆盖 entry 自身)。
  final String? previewUrl;
  final bool selected;
  final bool isPublic;
  final bool collected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onCollect;
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final modelGroups = artistModelGroups(entry.models);
    return AnimatedContainer(
      duration: Motion.fast,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.8 : 1,
        ),
      ),
      child: Material(
        color: scheme.surfaceContainer,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              switch (previewUrl) {
                null => _HueStripes(name: entry.name),
                final u when u.startsWith('http') => RemoteImage(
                  u,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: _fadeInFrame,
                  errorBuilder: (_, _, _) => _HueStripes(name: entry.name),
                ),
                final u => Image.file(
                  File(u),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: _fadeInFrame,
                  errorBuilder: (_, _, _) => _HueStripes(name: entry.name),
                ),
              },
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 14, 8, 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .62),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 适用模型角标(按分档归并:标了 V5 Full + Curated 只出一个)。
                      // 没标注的不画 —— 「通用」是默认档,给每张卡都挂一个反而是噪音。
                      if (modelGroups.isNotEmpty) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final g in modelGroups.take(2))
                              Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .22),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  g.label,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (modelGroups.length > 2)
                              Text(
                                '+${modelGroups.length - 2}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: selected ? scheme.primary : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 7,
                left: 7,
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? scheme.primary
                        : Colors.black.withValues(alpha: .3),
                    border: selected
                        ? null
                        : Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                      : null,
                ),
              ),
              // 公共卡:右上角收藏钮(40px 圆钮 + 半透明底,已收藏=实心红心);
              // 我的卡:右上角 ⋮ 菜单。
              if (isPublic)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Material(
                    color: collected
                        ? Colors.white.withValues(alpha: .92)
                        : Colors.black.withValues(alpha: .42),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onCollect,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          collected ? Icons.favorite : Icons.favorite_border,
                          size: 21,
                          color: collected ? scheme.error : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              if (!isPublic)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: .42),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: PopupMenuButton<String>(
                        onSelected: onMenu,
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.more_vert,
                          size: 20,
                          color: Colors.white,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: _MenuRow(Icons.edit_outlined, '编辑'),
                          ),
                          const PopupMenuItem(
                            value: 'copy',
                            child: _MenuRow(Icons.copy, '复制提示词'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: _MenuRow(
                              Icons.delete_outline,
                              '删除',
                              danger: true,
                            ),
                          ),
                        ],
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

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.danger = false});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? context.scheme.error : context.scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: danger ? c : null)),
      ],
    );
  }
}

/// 无预览图的占位:名称哈希定色相的深色渐变 + 斜纹 + 名称水印
/// (对齐 web HorizontalCard 的 hashHue 占位,同名恒同色)。
class _HueStripes extends StatelessWidget {
  const _HueStripes({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    return CustomPaint(
      painter: _HueStripePainter(hue),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Colors.white.withValues(alpha: .2),
            ),
          ),
        ),
      ),
    );
  }
}

class _HueStripePainter extends CustomPainter {
  const _HueStripePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final a = HSLColor.fromAHSL(1, hue, .38, .20).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 24) % 360, .42, .13).toColor();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()..color = Colors.black.withValues(alpha: .16);
    const w = 14.0;
    for (double x = -size.height; x < size.width; x += w * 2.4) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + w, 0)
        ..lineTo(x + w, size.height)
        ..close();
      canvas.drawPath(path, stripe);
    }
  }

  @override
  bool shouldRepaint(covariant _HueStripePainter old) => old.hue != hue;
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
                            color: scheme.surfaceContainerHigh.withValues(
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

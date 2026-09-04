import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/net/remote_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../editor/editor_models.dart' show draftOf, outputOf, pickEditorText;
import '../../generate/generate_state.dart';
import '../../generate/models.dart'
    show GenProvider, GenerateState, providerOfModel;
import '../../generate/widgets/common.dart'
    show confirmDialog, hintSnack, sharedAxisRoute;
import '../../import/import_panel.dart' show ImportImagePanel;
import '../../shell/shell_state.dart';
import '../tag_models.dart'
    show TagCategory, TagEntry, appendTagPositivesFolded;
import '../widgets/prompt_chips.dart';
import 'codex_card.dart';
import 'codex_char_split.dart';
import 'codex_favorites.dart';
import 'codex_models.dart';
import 'codex_providers.dart';
import '../../../core/util/haptics.dart';

/// 法典的三个弹层:词条详情、法典选择、来源致谢。

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => child,
    );

/// 把一条法典词条追加进创作页,返回角色卡的落地情况(供调用方措辞)。
///
/// 公共部分照旧作为一个**命名折叠组**进主提示词(复用灵感页同一条链路:草稿带回
/// 既有禁用/折叠,定稿由 outputOf 导出,两者同写)。
///
/// 角色段有**两种**来源,都要认:
///  ① 数据源的 `characterPrompts` 字段([CodexEntry.characters])—— 这是主流,
///     全站 8091 条,`tags` 里一个字都不带,早先只读 tags 等于把主体丢了;
///  ② 极少数把 `charN：` / `[charN±]` 直接写在 tags 里(全站 6 条),
///     由 [splitCodexCharacters] 拆(见那个模块)。
///
/// 拆角色卡**只对 NAI 做**:Anima / Krea 没有角色分离这回事,给它们拆出来的卡
/// 会被模块剥离层当场收走,白忙一场还让人以为丢了东西 —— 那两家一律整段
/// (含各角色段)折叠进主提示词。
({int added, int dropped}) codexAddToPrompt(WidgetRef ref, CodexEntry e) {
  final gen = ref.read(generateProvider);
  final isNai = providerOfModel(gen.params.model) == GenProvider.nai;

  // 非 NAI:整条(公共 + 角色段)一起进主提示词,一个字不丢
  if (!isNai) return _codexFoldInto(ref, e, e.fullText, gen);

  // 字段里带角色段 → 直接用;否则退回内联写法的拆分
  final fromField = [
    for (final c in e.characters)
      for (final slot in c.slots.isEmpty ? const [0] : c.slots)
        (index: slot, positive: c.prompt.trim(), negative: ''),
  ];
  final split = fromField.isEmpty ? splitCodexCharacters(e.tags) : null;
  final chars = fromField.isNotEmpty
      ? fromField
      : [
          for (final c in split!.characters)
            (index: c.index, positive: c.positive, negative: c.negative),
        ];
  final hasChars = chars.isNotEmpty;
  final base = fromField.isNotEmpty
      ? e.tags
      : (hasChars ? split!.base : e.tags);

  // 公共部分为空(全站 401 条 tags 就是空的)时不折叠 —— 否则插进去一个空组。
  _codexFoldInto(ref, e, base, gen);

  if (!hasChars) return (added: 0, dropped: 0);
  final added = ref.read(generateProvider.notifier).addCharactersFilled([
    for (final c in chars)
      (
        name: c.index > 0 ? '角色 ${c.index}' : '角色',
        positive: c.positive,
        negative: c.negative,
      ),
  ]);
  return (added: added, dropped: chars.length - added);
}

/// 把一段内容作为**命名折叠组**追加进主提示词(复用灵感页同一条链路:草稿带回
/// 既有禁用/折叠,定稿由 outputOf 导出,两者同写)。空段直接跳过。
({int added, int dropped}) _codexFoldInto(
  WidgetRef ref,
  CodexEntry e,
  String content,
  GenerateState gen,
) {
  if (content.trim().isEmpty) return (added: 0, dropped: 0);
  final entry = TagEntry(
    id: 'codex_${e.id}',
    category: TagCategory.other,
    name: e.title,
    positive: content,
  );
  final draft = appendTagPositivesFolded(
    pickEditorText(gen.promptRaw, gen.prompt),
    [entry],
  );
  final positive = outputOf(draft);
  ref
      .read(generateProvider.notifier)
      .setPrompts(positive: positive, positiveRaw: draftOf(draft, positive));
  return (added: 0, dropped: 0);
}

// ---- 词条详情 ----

/// 词条详情。[entries] 是当前筛选出的整批(左右滑动在里面翻上一条 / 下一条),
/// [index] 是点开的那条在其中的位置。
Future<void> showCodexDetailSheet(
  BuildContext context,
  CodexMeta codex,
  CodexMedia media, {
  required List<CodexEntry> entries,
  required int index,
}) => _sheet(
  context,
  _DetailSheet(
    codex: codex,
    entry: entries[index],
    media: media,
    entries: entries,
    index: index,
  ),
);

/// 随机抽一条:从当前筛选出的 [pool] 里随机取一条弹详情,并带「继续抽」。
Future<void> showCodexRandomSheet(
  BuildContext context,
  CodexMeta codex,
  CodexMedia media,
  List<CodexEntry> pool,
) {
  final start = pool[Random().nextInt(pool.length)];
  return _sheet(
    context,
    _DetailSheet(codex: codex, entry: start, media: media, pool: pool),
  );
}

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({
    required this.codex,
    required this.entry,
    required this.media,
    this.pool,
    this.entries = const [],
    this.index = 0,
  });

  final CodexMeta codex;
  final CodexEntry entry;
  final CodexMedia media;

  /// 非空 = 随机模式:从这批词条里「继续抽」(随机模式不支持左右翻)。
  final List<CodexEntry>? pool;

  /// 普通模式的整批词条 + 当前位置,供左右滑动翻页。
  final List<CodexEntry> entries;
  final int index;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

/// 拖动多远算「翻过去」:按屏宽的这个比例折算成 [-1,1] 的进度。
/// 卡片跟手是 1:1 的,所以这个值同时决定了甩出去的行程。
const _dragSpanRatio = .55;

/// 牌堆的标配比例 = NAI 竖图的标准出图尺寸 832×1216(见 [_DetailSheetState._deckAspect])。
const _deckRatio = 832 / 1216;

/// 一次横向拖动归谁:先看内层例图还有没有下一张,吃到头才交给牌堆。
enum _DragMode { undecided, pages, deck }

class _DetailSheetState extends ConsumerState<_DetailSheet>
    with TickerProviderStateMixin {
  late CodexEntry _entry = widget.entry;
  late int _index = widget.index;

  /// 牌堆进度:0=停稳,>0=往右拖(要上一条),<0=往左拖(要下一条)。
  /// 用 controller 而不是 setState —— 拖动每帧只重画牌堆,不重建整张弹层。
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );
  double _dragDx = 0;

  /// 多图词条的翻图进度:0=停稳,>0=往后翻一张,<0=往前。与牌堆同一套写法。
  late final AnimationController _pageDrag = AnimationController.unbounded(
    vsync: this,
  );
  int _imgPage = 0;
  _DragMode _dragMode = _DragMode.undecided;

  /// 「导入」正在下原图:按钮转圈并停用,不让同一张被点两遍。
  bool _importing = false;

  /// 下载进度(0..1;长度未知或空闲时 null)。用 notifier 而不是 setState ——
  /// 每来一个数据块就重建整张弹层(里头是牌堆和大图)太贵,只让那枚小圈重画。
  final _importAt = ValueNotifier<double?>(null);

  /// 每次按下自增:甩牌动画跑到一半又被按住时,用它作废上一轮的收尾。
  int _dragSeq = 0;

  /// 随机模式的抽牌历史:往后翻现抽一张接上,往前翻回看抽过的。
  /// 普通模式用不上(走 widget.entries)。
  late final List<CodexEntry> _drawn = widget.pool == null
      ? <CodexEntry>[]
      : [widget.entry];

  /// 当前这副牌。两种模式唯一的差别就在这:一个是定好的批次,一个是边抽边长。
  List<CodexEntry> get _list => widget.pool == null ? widget.entries : _drawn;

  @override
  void initState() {
    super.initState();
    _ensureAhead();
  }

  /// 随机模式保证后面永远有一张已经抽好的:底下露的那条边必须是**真的**
  /// 下一张,不然换人那一帧就对不上了。
  void _ensureAhead() {
    final pool = widget.pool;
    if (pool == null || pool.length < 2) return;
    if (_index < _drawn.length - 1) return;
    final rnd = Random();
    CodexEntry next;
    do {
      next = pool[rnd.nextInt(pool.length)];
    } while (next.id == _drawn[_index].id);
    _drawn.add(next);
  }

  /// 牌堆的比例:一副牌每张一样大,不能一张一个高度 —— 左右滑的时候
  /// 整张弹层跟着长高缩矮,手感是散的。
  ///
  /// 写死 [_deckRatio](NAI 竖图标配 832×1216):绝大多数例图就是这个比例,
  /// 这个高度一屏正好放得下;横图 / 方图在框里留边(同图毛玻璃垫底)。
  /// 只有**当前这张**比它还竖时才按它自己的比例撑高 —— 图不缩,正文滚起来,
  /// 翻走了框又回到标配。早先取"这批里最竖的那张"作准,混进一条长图,
  /// 整副牌全被拉成柱子(普通模式看整批,随机模式看整个抽奖池,更容易中)。
  ///
  /// 不组牌堆(单张)返回 null = 按词条自己的比例走。随机模式也是牌堆:
  /// [_ensureAhead] 一开始就备好了下一张。
  double? get _deckAspect {
    if (!_canStep) return null;
    final own = _entry.aspect; // 没尺寸的按 .75,比标配宽,落进框里
    return own < _deckRatio ? own : _deckRatio;
  }

  @override
  void dispose() {
    _drag.dispose();
    _pageDrag.dispose();
    _importAt.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _dragDx = 0;
    _dragSeq++;
    _dragMode = _DragMode.undecided;
  }

  int get _imgCount => _entry.images.isNotEmpty
      ? _entry.images.length
      : (_entry.hasImage ? 1 : 0);

  bool get _canStep => _list.length > 1;

  bool get _hasPrev => _canStep && _index > 0;
  bool get _hasNext => _canStep && _index < _list.length - 1;

  double get _span => MediaQuery.sizeOf(context).width * _dragSpanRatio;

  /// 翻到相邻词条;到头就不动(不循环,免得分不清自己在哪)。
  void _step(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _list.length) return;
    Haptics.selection();
    setState(() {
      _index = next;
      _entry = _list[next];
      _imgPage = 0; // 换词条从第一张例图看起
      _pageDrag.value = 0;
      _ensureAhead(); // 随机模式:再往后备一张
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragDx += d.delta.dx;
    // 方向一明确就定归属,整段拖动不再改主意 —— 中途换手会让画面跳。
    if (_dragMode == _DragMode.undecided) {
      if (_dragDx.abs() < 4) return;
      final wantNext = _dragDx < 0;
      final moreImages =
          _imgCount > 1 && (wantNext ? _imgPage < _imgCount - 1 : _imgPage > 0);
      _dragMode = moreImages ? _DragMode.pages : _DragMode.deck;
    }
    if (_dragMode == _DragMode.pages) {
      _pageDrag.value = (-_dragDx / _pageSpan).clamp(-1.0, 1.0);
      return;
    }
    var t = (_dragDx / _span).clamp(-1.0, 1.0);
    // 到头了给个阻尼:拖得动一点点,让人知道"这边没有了",而不是纹丝不动
    if ((t > 0 && !_hasPrev) || (t < 0 && !_hasNext)) t *= .18;
    _drag.value = t;
  }

  /// 翻图按整屏宽跟手 1:1(图本来就铺满整宽,少一点都会觉得滞后)。
  double get _pageSpan => MediaQuery.sizeOf(context).width;

  Future<void> _onDragEnd(DragEndDetails d) async {
    final seq = _dragSeq;
    if (_dragMode == _DragMode.pages) return _endPageDrag(d, seq);
    final t = _drag.value;
    final v = d.primaryVelocity ?? 0;
    final int wants = v.abs() > 300
        ? (v < 0 ? 1 : -1)
        : (t.abs() > .3 ? (t < 0 ? 1 : -1) : 0);
    final go = (wants > 0 && _hasNext) || (wants < 0 && _hasPrev) ? wants : 0;
    if (go == 0) {
      // 没过阈值:弹回原位
      await _drag.animateTo(
        0,
        duration: Motion.medium,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // 先把这张甩完(甩的过程里它同时淡出),再无缝换人
    await _drag.animateTo(
      go > 0 ? -1 : 1,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOut,
    );
    if (!mounted || seq != _dragSeq) return; // 甩到一半又被按住:让位给新的一轮
    _step(go);
    _drag.value = 0; // 顶上来那张此刻已经在正位了,归零即无缝
  }

  /// 翻图收尾:与甩牌同一套 —— 先滑完再换页码,归零那一帧正好对上。
  Future<void> _endPageDrag(DragEndDetails d, int seq) async {
    final o = _pageDrag.value;
    final v = d.primaryVelocity ?? 0;
    final int wants = v.abs() > 300
        ? (v < 0 ? 1 : -1)
        : (o.abs() > .3 ? (o > 0 ? 1 : -1) : 0);
    final go =
        (wants > 0 && _imgPage < _imgCount - 1) || (wants < 0 && _imgPage > 0)
        ? wants
        : 0;
    if (go == 0) {
      await _pageDrag.animateTo(
        0,
        duration: Motion.medium,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _pageDrag.animateTo(
      go.toDouble(),
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOut,
    );
    if (!mounted || seq != _dragSeq) return;
    setState(() => _imgPage += go);
    _pageDrag.value = 0;
  }

  TextStyle _titleStyle(BuildContext context) =>
      context.texts.titleMedium!.copyWith(fontWeight: FontWeight.w800);

  /// 表头预留高度:两行标题 + 3 间距 + 一行分类路径。按实际字号量,
  /// 系统字体放大也跟得上。
  double _headerH(BuildContext context) =>
      _lineH(context, _titleStyle(context)) * 2 +
      3 +
      _lineH(context, context.texts.labelSmall!);

  double _lineH(BuildContext context, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: '字', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final h = tp.height;
    tp.dispose();
    return h;
  }

  /// 「换一个」= 把当前这张甩掉,和左滑走同一条路 ——
  /// 按钮和手势不该是两种观感。
  Future<void> _reroll() async {
    if (!_hasNext) return;
    final seq = ++_dragSeq;
    await _drag.animateTo(
      -1,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOut,
    );
    if (!mounted || seq != _dragSeq) return;
    _step(1);
    _drag.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final e = _entry;
    final canReroll = widget.pool != null && _canStep;
    final imgCount = e.images.isNotEmpty
        ? e.images.length
        : (e.hasImage ? 1 : 0);
    final deckAspect = _deckAspect;
    // 定高卡:封顶九成屏高,正文滚动、操作条常驻。tall 词条不再顶穿屏幕、
    // 按钮也不会被内容或系统栏挤出可视区(旧版整卡随内容无限拉长)。
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 抓手由 BottomSheetTheme(showDragHandle: true)统一提供,这里不再自画
            // (自画会和主题抓手叠成两根横杆)。正文滚动区随内容滚动,封顶不外溢。
            Flexible(
              child: GestureDetector(
                // 左右滑动翻上一条 / 下一条。竖向滚动、例图横滑翻页、点击翻面
                // 各归各的:纵向归滚动区,例图那块的横向归它自己的 PageView
                // (命中更深先拿到手势),剩下的横向才落到这里。
                onHorizontalDragStart: _canStep ? _onDragStart : null,
                onHorizontalDragUpdate: _canStep ? _onDragUpdate : null,
                onHorizontalDragEnd: _canStep ? _onDragEnd : null,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  // 换词条后高度不同只来自图框的比例,由图框那处自己补间
                  // (见 TweenAnimationBuilder);表头在牌堆模式下写死了高度。
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题这块只做淡入淡出:横向位移交给下面那副牌,
                      // 两处一起动会打架。
                      // 组牌堆时按「两行标题 + 一行分类」写死高度并顶对齐:
                      // 标题一行两行、有没有分类路径都会改总高,左右滑时整张
                      // 弹层跟着长个儿 —— 牌定了高,这里不定等于白定。
                      SizedBox(
                        height: deckAspect == null ? null : _headerH(context),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: AnimatedSwitcher(
                            duration: Motion.medium,
                            // 默认是居中摞:一行换两行时,高度一涨,旧的那行
                            // 就被推到新高度的正中去了 —— 看着像"先下坠再换字"。
                            // 钉在左上角,旧的原地淡出、新的原地淡入。
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topLeft,
                              children: [...previous, ?current],
                            ),
                            // 先淡完再淡进,不让两段文字叠在一起糊成一片
                            switchOutCurve: const Interval(.5, 1),
                            switchInCurve: const Interval(.5, 1),
                            child: Column(
                              key: ValueKey(e.id),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: _titleStyle(context),
                                      ),
                                    ),
                                    if (widget.pool != null) ...[
                                      const SizedBox(width: 8),
                                      _randomBadge(scheme),
                                    ],
                                  ],
                                ),
                                if (e.path.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    e.path.join(' / '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.labelSmall!.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 牌堆模式下无论有没有图都走同一张卡(无图的正面直接是
                      // 提示词)—— 否则纯文字词条一条一个高度,左右滑又开始抖。
                      // 单张(不组牌堆)时纯文字词条仍按内容高度,不撑空 box。
                      if (imgCount > 0 || deckAspect != null)
                        // 框的比例自己做补间:换词条只改 end,框从当前比例平滑
                        // 变到新的,里头的图(contain)跟着连续缩放。早先靠外层
                        // AnimatedSize 过渡总高 —— 它只动容器、裁掉多出来的那截,
                        // 图本身第一帧就已经是新尺寸,看着是跳过去的。
                        // 首次进来 begin 为空 = 直接落在 end,不做开场补间。
                        // ⚠ 不能给它挂 ValueKey(e.id):换词条会把补间状态一起换掉。
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: deckAspect ?? e.aspect),
                          duration: Motion.medium,
                          curve: Motion.emphasized,
                          // 牌堆本身走 child:每帧只重建外面这层 AspectRatio
                          child: _CodexHeroImages(
                            key: ValueKey(e.id),
                            codex: widget.codex,
                            entry: e,
                            media: widget.media,
                            drag: _drag,
                            pageDrag: _pageDrag,
                            page: _imgPage,
                            deck: deckAspect != null,
                            prev: _hasPrev ? _list[_index - 1] : null,
                            next: _hasNext ? _list[_index + 1] : null,
                          ),
                          builder: (_, a, child) =>
                              AspectRatio(aspectRatio: a, child: child),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: PromptChips(sections: _codexPromptSections(e)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 常驻操作条:钉在底部,永远可点
            _bottomActions(scheme, e, canReroll),
          ],
        ),
      ),
    );
  }

  /// 底部常驻操作条:随机模式头上多一枚整宽的「继续抽」;顶部一道细线与滚动
  /// 区分隔。钉在 SafeArea 内,按钮永远露在系统栏之上,不被长内容挤出屏幕。
  Widget _bottomActions(ColorScheme scheme, CodexEntry e, bool canReroll) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canReroll) ...[_rerollButton(), const SizedBox(height: 10)],
          // 四件事一行摆得下,靠的是**收藏和复制只留图标**:星星和纸叠自己就
          // 说得清,那四个字省下的宽度正是带字两枚摆得开所需的 —— 「加入提示词」
          // 五个汉字加图标本来就顶格,谁多占一点它就换行,而这条操作栏一变高
          // 就把上面的内容挤走。
          Row(
            children: [
              _favButton(scheme, e),
              const SizedBox(width: 8),
              _copyButton(e),
              const SizedBox(width: 8),
              // 2:3 差不多就是「导入」与「加入提示词」各自最小宽之比;
              // 五五开等于把富余全给短的那枚,长的先换行
              Expanded(flex: 2, child: _importButton()),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _addButton(e)),
            ],
          ),
        ],
      ),
    );
  }

  /// 带字那两枚共用的尺寸:描边和实心混排,高度圆角不统一一眼就看得出参差。
  /// 内边距收到 8 —— M3 带图标的默认是左 16 右 24,那 32px 是压垮它的那根;
  /// 省下来的富余留给系统字号放大(放大到 1.2 倍才开始吃省略号)。
  static const _labeledStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 46)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    shape: WidgetStatePropertyAll(StadiumBorder()),
  );

  /// 只留图标那两枚:46×46 的**正圆**(宽=高才是圆;圆比同高的胶囊窄,
  /// 省下的宽度正好给右边带字的两枚)。
  ///
  /// ⚠ `minimumSize` 必须跟着给零:M3 给 OutlinedButton 的默认最小宽是 **64**,
  /// 而 fixedSize 要先被最小尺寸夹一道才生效 —— 只写 fixedSize 的话这两枚会
  /// 悄悄各占 64 宽,右边「导入」和「加入提示词」双双被挤成省略号(实测)。
  static const _iconOnlyStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.zero),
    fixedSize: WidgetStatePropertyAll(Size(46, 46)),
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(CircleBorder()),
  );

  /// 复制。不留字(见 [_bottomActions]);纸叠图标够常见,长按还有 tooltip 兜底。
  Widget _copyButton(CodexEntry e) => Tooltip(
    message: '复制提示词',
    child: OutlinedButton(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: e.fullText));
        if (mounted) {
          Navigator.pop(context);
          hintSnack(context, '已复制提示词', icon: Icons.copy);
        }
      },
      style: _iconOnlyStyle,
      child: const Icon(Icons.copy, size: 20),
    ),
  );

  /// 「导入」:每张例图背后还压着一张原图,里头带着出图元数据。
  ///
  /// 无图词条按**停用**摆着而不是撤掉 —— 一摞牌里翻过去少一枚按钮,
  /// 整条操作栏会跟着变形。下载期间也停用,同一张不让点两遍。
  Widget _importButton() => OutlinedButton.icon(
    onPressed: _imgCount > 0 && !_importing ? _importOriginal : null,
    style: _labeledStyle,
    icon: _importing
        ? ValueListenableBuilder<double?>(
            valueListenable: _importAt,
            builder: (_, v, _) => SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, value: v),
            ),
          )
        : const Icon(Icons.input, size: 18),
    label: const Text('导入', maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  /// 下当前这张的原图 → 关弹层 → 推导入面板(与相册 / 画布同一个面板:
  /// 参数逐项挑着导,或整张用作图生图 / 风格 / 角色参考)。
  ///
  /// 先关再推:面板是整页的,压在弹层上会留一层退不掉的夹心 —— 从面板返回时
  /// 人以为回到了图鉴,实际还在这张弹层里。
  ///
  /// 原图按字节交出去,不能拿屏幕上那张:显示走的是解码后的位图,
  /// PNG 文本块早没了,而元数据全在那里头。
  Future<void> _importOriginal() async {
    final e = _entry;
    final url = codexImageItemUrl(
      widget.codex,
      e,
      widget.media,
      _imgPage,
      original: true,
    );
    if (url == null) return;
    Haptics.selection();
    _importAt.value = null;
    setState(() => _importing = true);
    try {
      final bytes = await fetchRemoteImageBytes(
        url,
        onProgress: (got, total) {
          if (total != null && total > 0) _importAt.value = got / total;
        },
      );
      if (!mounted) return;
      final name = e.title.trim().isEmpty ? '法典原图' : e.title.trim();
      final nav = Navigator.of(context);
      nav.pop();
      unawaited(
        nav.push(
          sharedAxisRoute(
            ImportImagePanel(
              bytes: bytes,
              fileName: '$name${_extOf(url)}',
              displayName: name,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      hintSnack(context, '原图没下下来,检查下网络', icon: Icons.wifi_off_outlined);
    }
  }

  /// 原图的扩展名(png / jpg / webp 都有),给导入面板的文件名用;
  /// 认不出就当 png —— 那串只是拿来显示的,不参与解析。
  String _extOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot);
    return RegExp(r'^\.[A-Za-z0-9]{2,4}$').hasMatch(ext) ? ext : '.png';
  }

  /// 随机模式的「换一个」:整宽独占一行 —— 随机页的主循环就是它,
  /// 挤进下面那行会和主行动抢眼。
  Widget _rerollButton() => FilledButton.tonalIcon(
    onPressed: _reroll,
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 46),
      shape: const StadiumBorder(),
    ),
    icon: const Icon(Icons.casino_outlined, size: 18),
    label: const Text('换一个'),
  );

  Widget _addButton(CodexEntry e) => FilledButton.icon(
    onPressed: () {
      final r = codexAddToPrompt(ref, e);
      Navigator.pop(context);
      hintSnack(
        context,
        // 拆出了角色就说清楚 —— 不然用户只看到主提示词短了一截,
        // 不知道内容跑去了角色卡里
        r.dropped > 0
            ? '已加入提示词 · ${r.added} 个角色(另 ${r.dropped} 个超出上限)'
            : (r.added > 0 ? '已加入提示词 · ${r.added} 个角色' : '已加入提示词'),
        icon: Icons.check_circle_outline,
        actionLabel: '去创作',
        onAction: () =>
            ref.read(shellIndexProvider.notifier).select(kTabCreate),
      );
    },
    style: _labeledStyle,
    icon: const Icon(Icons.add, size: 18),
    // 兜底:系统字号调得很大时宁可省略号,也不能换行 —— 这条操作栏是钉在
    // 底部的,它一变高就把上面的内容挤走
    label: const Text('加入提示词', maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  /// 收藏开关。**图标自己就是反馈**,不弹 snack —— 翻词条时会连点很多下,
  /// 每下都弹一条反而糊住正在看的图。只有加不进去(满了)才出声。
  Widget _favButton(ColorScheme scheme, CodexEntry e) {
    final on = ref
        .watch(codexFavKeysProvider)
        .contains(codexFavKey(widget.codex.id, e.id));
    return OutlinedButton(
      onPressed: () => _toggleFav(e),
      // 只有开关色是动的,尺寸走 [_iconOnlyStyle](54 收到 44:那 10px 给了
      // 「加入提示词」)
      style: _iconOnlyStyle.merge(
        OutlinedButton.styleFrom(
          foregroundColor: on ? scheme.primary : scheme.onSurfaceVariant,
          side: BorderSide(color: on ? scheme.primary : scheme.outlineVariant),
        ),
      ),
      child: Icon(
        on ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 22,
      ),
    );
  }

  Future<void> _toggleFav(CodexEntry e) async {
    final n = ref.read(codexFavoritesProvider.notifier);
    if (n.isFull && !n.contains(widget.codex.id, e.id)) {
      hintSnack(
        context,
        '收藏已满(${CodexFavoritesNotifier.kMax} 条),先去收藏夹清一些',
        icon: Icons.info_outline,
      );
      return;
    }
    Haptics.selection();
    await n.toggle(
      widget.codex.id,
      e,
      now: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Widget _randomBadge(ColorScheme scheme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.casino_outlined,
          size: 13,
          color: scheme.onTertiaryContainer,
        ),
        const SizedBox(width: 4),
        Text(
          '随机',
          style: context.texts.labelSmall!.copyWith(
            color: scheme.onTertiaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// 详情大图 = 一副牌:当前词条压在最上面,左右相邻的各露出一条边。
/// 点一下翻面看提示词;左右拖动把最上面这张甩走,旁边那张顶上来。
/// 多图词条仍可在图上横滑翻页(它自己的 PageView 命中更深,先拿到手势)。
class _CodexHeroImages extends ConsumerStatefulWidget {
  const _CodexHeroImages({
    super.key,
    required this.codex,
    required this.entry,
    required this.media,
    required this.drag,
    required this.pageDrag,
    required this.page,
    required this.deck,
    this.prev,
    this.next,
  });

  /// 牌堆拖动进度:>0 往右(要上一条),<0 往左(要下一条)。
  final Animation<double> drag;

  /// 多图翻图进度(>0 往后一张)与当前页码。两者都由弹层统一持有 ——
  /// 内外两段手势要按同一把尺子接力,状态分家就接不上。
  final Animation<double> pageDrag;
  final int page;

  /// 组了牌堆:框是整副牌共用的比例(由弹层定并做补间),各词条比例不一,
  /// 图一律 contain 留边。单张时框就是词条自己的比例,cover 即原样铺满。
  final bool deck;

  /// 相邻词条。「下一条」常驻露一条边;「上一条」只在往回拖时才淡进来
  /// —— 牌堆是往后摞的,静止时两边都露反而看不出方向。
  final CodexEntry? prev;
  final CodexEntry? next;

  final CodexMeta codex;
  final CodexEntry entry;
  final CodexMedia media;

  @override
  ConsumerState<_CodexHeroImages> createState() => _CodexHeroImagesState();
}

/// 卡片圆角:外框不再统一裁剪,正反两面各自按这个值裁,影子也用它。
const _cardRadius = BorderRadius.all(Radius.circular(14));

/// 底下那张露出来的宽度(牌堆的「厚度」)。
const _peekDx = 24.0;

class _CodexHeroImagesState extends ConsumerState<_CodexHeroImages>
    with SingleTickerProviderStateMixin {
  /// 转角进度:0 = 例图,1 = 提示词。**不在这上面挂曲线** —— 曲线属于每次
  /// 动作(翻面 / 示范各有各的节奏),这里只当几何量用。
  late final AnimationController _turn = AnimationController(vsync: this);

  bool _showingPrompt = false;

  /// 提示词面已经排好版(在树里、照常布局,只是还没转过去)。
  /// 换词条时整个 state 是新的(卡带 `ValueKey(e.id)`),自然回到 false。
  ///
  /// **只在真点了才排**,不预热:排一次 20ms 左右(实测 56 颗芯片,换成不带
  /// 本项目任何代码的等量哑控件也要 16.6ms —— 八成是 Flutter 自己 inflate
  /// 一百多个 widget、排一百多段文字,减不掉),而多数牌根本不会被翻,
  /// 提前排等于给每张停下来看的牌白花这一笔。
  bool _backUp = false;
  bool _teasing = false; // 首次示范进行中;用户一碰就作废
  bool _teaseScheduled = false;
  bool _showHint = false; // 首次的文字提示,跟着示范一起来一起走

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  // 背面展示的是**整条**内容:tags 只是公共部分,多角色词条的主体在
  // characterPrompts 里(全站 8091 条带它,其中 401 条 tags 是空的)。
  String get _prompt => widget.entry.fullText;

  int get _imgCount => widget.entry.images.isNotEmpty
      ? widget.entry.images.length
      : (widget.entry.hasImage ? 1 : 0);

  /// 无图词条:正面直接就是提示词,没有可翻的另一面。
  bool get _canFlip => _imgCount > 0 && _prompt.isNotEmpty;

  /// 一面卡:留在树里照常布局,只切换画不画(理由见 [_topCard])。藏起来那面
  ///  · 不吃点击 —— 提示词面的滚动区看不见也会抢走竖向拖动;
  ///  · **停表** —— 芯片等译文时有一条脉动动画,不停表它在背面照转,每帧把
  ///    那片芯片重建一遍,整个弹层跟着变钝。
  static Widget _face(bool visible, Widget child) => TickerMode(
    enabled: visible,
    child: Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: child,
    ),
  );

  void _flip() {
    if (!_canFlip) return; // 没图或没提示词就没有背面,别翻出一片空
    Haptics.selection();
    _teasing = false; // 示范到一半被点:立刻让位,别再自己转回去
    _showingPrompt = !_showingPrompt;
    if (_backUp) {
      // 这张牌翻过了,版还在:直接转
      if (_showHint) setState(() => _showHint = false);
      return _turnTo();
    }
    // 第一次翻这张牌:拿这一帧排版 —— 此刻 _turn 还是 0,屏幕上什么都没动,
    // 一帧长一点看不出来。排完(帧后)才开转:动画按真实时间走,先开转再撞上
    // 这一帧,卡片会直接跳过一段角度。
    setState(() {
      _showHint = false; // 已经会了,提示收掉
      _backUp = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _turnTo();
    });
  }

  void _turnTo() => _turn.animateTo(
    _showingPrompt ? 1 : 0,
    duration: Motion.slow,
    curve: Curves.easeInOutCubic,
  );

  /// 首次示范:亮一句「点击翻转查看提示词」,同时自己歪出去一个角度再转回来。
  /// 光有动作说不清能得到什么,光有文字又不知道该怎么操作,两个一起才够。
  /// 只来这一次(落盘),之后不留任何常驻提示占版面。
  void _scheduleTease() {
    if (_teaseScheduled) return;
    _teaseScheduled = true;
    ref.read(codexFlipHintProvider.notifier).ack();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 等弹层升上来站稳:和入场动画叠在一起就看不出是它自己在转
      await Future<void>.delayed(const Duration(milliseconds: 480));
      if (!mounted || _turn.value != 0) return;
      _teasing = true;
      setState(() => _showHint = true);
      await _turn.animateTo(
        .18, // 约 32°,够看出是块能翻的板子,又不至于露出背面
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || !_teasing) return;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted || !_teasing) return;
      await _turn.animateTo(
        0,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeInOutCubic,
      );
      _teasing = false;
      // 卡片停稳后再留一会儿够读完,然后自己走
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted && _showHint) setState(() => _showHint = false);
    });
  }

  /// 首次提示条:浮在牌堆最上层,**不进翻转卡片**内部 —— 跟着卡一起做 3D
  /// 旋转会被拉斜,字都读不清。
  Widget _flipHint() => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedOpacity(
        duration: Motion.medium,
        curve: Motion.standard,
        opacity: _showHint ? 1 : 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.touch_app_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 7),
                Text(
                  '点击翻转查看提示词',
                  style: context.texts.labelLarge!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final n = _imgCount;
    // 读盘确认「没演示过」才排期(null = 还没读到,这次就不演)
    if (_canFlip && ref.watch(codexFlipHintProvider) == false) {
      _scheduleTease();
    }
    // 框(AspectRatio)由弹层那边定比例并做补间,这里只管往框里填:
    // 满宽不裁不压;太高不要紧,例图跟着正文在滚动区里滚。
    // 这里**不能**包 ClipRRect:透视会把朝向自己的那条边放大,一裁就是
    // "转到一半边角被啃掉"。圆角由每一面自己裁,卡片允许探出原位 ——
    // 翻牌本来就该是从槽里抬起来转,而不是贴在槽底转。
    return Stack(
      // none:压在下面的两张要露到框外去,才看得出是一摞
      clipBehavior: Clip.none,
      children: [
        // 顺序即层次:下一条压在底下,当前这张在中间,
        // 上一条盖在最上面 —— 它是"已经发出去的牌",拉回来自然是从前面盖回来。
        if (widget.next != null)
          Positioned.fill(child: _behindCard(widget.next!, scheme)),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: widget.drag,
            builder: (context, child) => _dragged(context, child!),
            child: _topCard(n, scheme),
          ),
        ),
        if (widget.prev != null)
          Positioned.fill(child: _frontCard(widget.prev!, scheme)),
        _flipHint(),
      ],
    );
  }

  /// 最上面那张:会翻面的卡本体(拖动位移由外面的 [_dragged] 再套一层)。
  Widget _topCard(int n, ColorScheme scheme) {
    // 两张脸各建**一次**再交给 AnimatedBuilder:它每帧只重建几何变换那几层,
    // 同一实例传下去 element 直接短路 —— 否则翻面动画里整片芯片流每帧
    // 跟着 diff 一遍,白烧 CPU。
    final front = _imageFace(n, scheme);
    final back = Transform(
      alignment: Alignment.center,
      // 背面再转 180°,否则内容是镜像的
      transform: Matrix4.identity()..rotateY(pi),
      child: _promptFace(),
    );
    return GestureDetector(
      // opaque:图没加载出来时的空白处也要能翻
      behavior: HitTestBehavior.opaque,
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, _) {
          final angle = _turn.value * pi;
          // 侧棱程度:正对为 0,转到 90° 为 1。缩放/明暗/影子都挂它上面。
          final edge = sin(angle);
          // 转起来略微后退。这一下同时压住近边的放大量,不至于盖住标题
          final scale = 1 - .14 * edge;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0016) // 透视,不然只是横向压扁的贴纸
              ..rotateY(angle)
              ..scaleByDouble(scale, scale, 1, 1),
            child: _cardSurface(
              elevation: edge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 转过一半才换脸,正好是侧棱最窄的那一帧,看不见切换。
                  //
                  // 两面都**留在树里并照常布局**,只切换画不画([_face])。
                  // 换脸那一帧最不能干活:它正是转速最快的一帧。
                  //  · 移除:多图那张 PageView 一被拆掉,翻回来就是新建的一张、
                  //    停在第一页 —— 你翻到第二张再翻牌,图会变回第一张。
                  //  · Offstage:状态是留住了,但它**跳过布局** —— 于是每次切脸
                  //    两边都要重排一遍(图那面重新解一次约束,提示词面整片芯片
                  //    重新分词排版),那几毫秒全砸在换脸那一帧上。
                  _face(_turn.value <= .5, front),
                  // 提示词面:第一次翻的时候才排版,之后一直留着(见 [_backUp])
                  if (_backUp) _face(_turn.value > .5, back),
                  // 受光:转离正对方向就变暗。少了这层,透视再准也像贴纸
                  if (edge > .01)
                    IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .34 * edge),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 当前这张。两个方向不是一回事:
  /// 往左 = 把这张甩出去(跟手 1:1 走、微微侧倾、最后一段淡出);
  /// 往右 = 这张不走,原地退成「下一张」的位姿,让上一条从前面盖回来。
  Widget _dragged(BuildContext context, Widget child) {
    final t = widget.drag.value;
    if (t == 0) return child;
    if (t > 0) {
      // 位姿和透明度都要退到「下一张」那一档:落位瞬间它就是下一张,
      // 差一点点都会在换人那一帧闪一下。
      return Transform.translate(
        offset: Offset(_peekDx * t, 0),
        child: Transform.scale(
          scale: 1 - .06 * t,
          child: Opacity(opacity: 1 - .45 * t, child: child),
        ),
      );
    }
    final fade = ((-t - .3) / .7).clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(t * MediaQuery.sizeOf(context).width * _dragSpanRatio, 0),
      child: Transform.rotate(
        angle: t * .05, // 甩出去时微微歪一下,像真被拨走
        child: Opacity(opacity: 1 - fade, child: child),
      ),
    );
  }

  /// 压在底下的「下一条」:常驻露出右边一条。往左拖时顶到正位;
  /// 往右拖时淡出 —— 换到上一条后它就不是下一条了,不能三张一起堆着。
  Widget _behindCard(CodexEntry e, ColorScheme scheme) {
    return AnimatedBuilder(
      animation: widget.drag,
      builder: (context, child) {
        final t = widget.drag.value;
        final f = t < 0 ? -t : 0.0; // 往前
        final b = t > 0 ? t : 0.0; // 往回
        final opacity = (.55 + .45 * f) * (1 - b);
        if (opacity <= .01) return const SizedBox.shrink();
        return Transform.translate(
          offset: Offset(_peekDx * (1 - f), 0),
          child: Transform.scale(
            scale: .94 + .06 * f,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
      child: _cardSurface(elevation: .35, child: _preview(e, scheme)),
    );
  }

  /// 盖在最上面的「上一条」:静止时整张在屏幕外,往回拖才从左边滑回来。
  /// 影子随着落位收掉,落稳时正好和常态的卡一样平。
  Widget _frontCard(CodexEntry e, ColorScheme scheme) {
    return AnimatedBuilder(
      animation: widget.drag,
      builder: (context, child) {
        final b = widget.drag.value;
        if (b <= 0) return const SizedBox.shrink();
        // 1.06 屏宽:起点整张在屏幕外,b→0 时不会在边上露出一条
        final away = MediaQuery.sizeOf(context).width * 1.06;
        return Transform.translate(
          offset: Offset(-away * (1 - b), 0),
          child: _cardSurface(elevation: .5 * (1 - b), child: child!),
        );
      },
      child: _preview(e, scheme),
    );
  }

  /// 卡片的"实体":圆角 + 随抬起程度变化的影子,正反面和邻居共用一套。
  Widget _cardSurface({required double elevation, required Widget child}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _cardRadius,
          boxShadow: elevation < .02
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .34 * elevation),
                    blurRadius: 28 * elevation,
                    offset: Offset(0, 10 * elevation),
                  ),
                ],
        ),
        child: ClipRRect(borderRadius: _cardRadius, child: child),
      );

  /// 组了牌堆,各词条比例不一,一律 contain —— 图鉴的例图宁可留边也不能裁。
  /// 单张时框就是原比例,cover 即原样铺满。
  BoxFit get _fit => widget.deck ? BoxFit.contain : BoxFit.cover;

  /// 邻居只画封面;没有图就退成配色块 + 标题。
  Widget _preview(CodexEntry e, ColorScheme scheme) {
    final url = codexImageUrl(widget.codex, e, widget.media);
    final fallback = ColoredBox(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Text(
            e.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
    if (url == null) return fallback;
    final img = RemoteImage(
      url,
      fit: _fit,
      gaplessPlayback: true,
      frameBuilder: codexFadeIn,
      errorBuilder: (_, _, _) => fallback,
    );
    if (_fit != BoxFit.contain) {
      return ColoredBox(color: scheme.surfaceContainerHighest, child: img);
    }
    // 邻居卡与顶卡同款毛玻璃留边,一摞牌观感才一致
    return Stack(
      fit: StackFit.expand,
      children: [
        _BlurredBackdrop(url: url, frost: .35),
        img,
      ],
    );
  }

  /// 正面:例图。这条词条压根没图时,正面直接就是提示词 —— 不留一张空卡。
  ///
  /// 多图不用 PageView:它的横滑和牌堆是同一个方向,命中更深会把整条手势吃掉
  /// (结果就是多图词条切不了下一条)。改成自己按 [pageDrag] 平移两张图,
  /// 手势归属由弹层统一裁决 —— 内层翻到头,才轮到牌堆。
  Widget _imageFace(int n, ColorScheme scheme) {
    if (n == 0) return _promptFace();
    if (n == 1) return _img(0, scheme);
    return AnimatedBuilder(
      animation: widget.pageDrag,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final o = widget.pageDrag.value;
          final w = c.maxWidth;
          final other = o > 0 ? widget.page + 1 : widget.page - 1;
          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: Offset(-o * w, 0),
                child: _img(widget.page, scheme),
              ),
              if (o != 0 && other >= 0 && other < n)
                Transform.translate(
                  offset: Offset((o > 0 ? w : -w) - o * w, 0),
                  child: _img(other, scheme),
                ),
              _pageDots(n),
            ],
          );
        },
      ),
    );
  }

  /// 页点:浮在图片底部,不占版面 —— 摆在卡片下面会让单图/多图两种词条
  /// 高度不一样,牌堆又开始一张一个高度。
  Widget _pageDots(int n) => Positioned(
    left: 0,
    right: 0,
    bottom: 10,
    child: IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .38),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++)
                AnimatedContainer(
                  duration: Motion.fast,
                  width: i == widget.page ? 14 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    // 压在任意图片上,固定白色比主题色可靠
                    color: Colors.white.withValues(
                      alpha: i == widget.page ? .95 : .45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  /// 背面(或无图词条的正面):提示词芯片面。有例图时拿**当前页**那张
  /// 垫毛玻璃底。整段复制仍走底部那枚「复制」—— 芯片不可选字,
  /// 点它就是点卡片,照样翻回去。
  Widget _promptFace() => _PromptFace(
    entry: widget.entry,
    bgUrl: _imgCount == 0
        ? null
        : codexImageItemUrl(
            widget.codex,
            widget.entry,
            widget.media,
            widget.page,
          ),
  );

  Widget _img(int i, ColorScheme scheme) {
    final url = codexImageItemUrl(widget.codex, widget.entry, widget.media, i);
    if (url == null) {
      return ColoredBox(color: scheme.surfaceContainerHighest);
    }
    final img = RemoteImage(
      url,
      fit: _fit,
      gaplessPlayback: true,
      frameBuilder: codexFadeIn,
      errorBuilder: (_, _, _) => Center(
        child: Icon(Icons.broken_image_outlined, color: scheme.outline),
      ),
    );
    // 随机模式(cover)铺满没有边,不必垫底
    if (_fit != BoxFit.contain) {
      return ColoredBox(color: scheme.surfaceContainerHighest, child: img);
    }
    // 定高后比例不一,contain 会留边 —— 边不再是死灰,用同一张图的毛玻璃
    // 垫底,留白像图自己延伸出去
    return Stack(
      fit: StackFit.expand,
      children: [
        _BlurredBackdrop(url: url, frost: .35),
        img,
      ],
    );
  }
}

/// 已烘好的模糊纹理(按图 URL):[_blurJobs] 管在途与去重,[_blurDone] 给
/// 挂载时同步取 —— 免得每次翻面都先闪一帧底色再淡入。上限之外按插入序淘汰,
/// **不 dispose**:被淘汰的可能还挂在屏幕上,96px 小图交给 GC 收尾。
final _blurJobs = <String, Future<ui.Image?>>{};
final _blurDone = <String, ui.Image>{};
const _blurCap = 96;

Future<ui.Image?> _bakedBlur(String url) {
  final hit = _blurJobs.remove(url);
  if (hit != null) return _blurJobs[url] = hit; // 重插一次 = 记「最近用过」
  while (_blurJobs.length >= _blurCap) {
    final oldest = _blurJobs.keys.first;
    _blurJobs.remove(oldest);
    _blurDone.remove(oldest);
  }
  late final Future<ui.Image?> fut;
  fut = _bakeBlur(url).then((img) {
    if (img != null) {
      _blurDone[url] = img;
    } else if (identical(_blurJobs[url], fut)) {
      _blurJobs.remove(url); // 失败不缓存,下次挂载重试
    }
    return img;
  });
  return _blurJobs[url] = fut;
}

/// 拉 96px 小图 → 高斯糊一遍 → 落成纹理。σ 按小图给:上屏还要放大十来倍,
/// 等效全尺寸 σ≈20 的观感。失败返回 null,底色顶着。
Future<ui.Image?> _bakeBlur(String url) async {
  final ui.Image src;
  try {
    src = await _resolveImage(ResizeImage(RemoteImageProvider(url), width: 96));
  } catch (_) {
    return null;
  }
  try {
    final w = src.width, h = src.height;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 4,
          sigmaY: 4,
          tileMode: ui.TileMode.clamp, // 边缘延展,不糊出一圈透明黑边
        ),
    );
    canvas.drawImage(src, Offset.zero, Paint());
    canvas.restore();
    final pic = rec.endRecording();
    final img = pic.toImageSync(w, h);
    pic.dispose();
    return img;
  } finally {
    src.dispose();
  }
}

/// 解一帧图出来(clone 出独立句柄,流内那份还给框架)。
Future<ui.Image> _resolveImage(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (e, _) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// 例图的毛玻璃垫底:同一张图 cover 铺满 + 高斯糊 + 一层主题面色罩。
/// 模糊**烘焙一次**而不是每帧现算 —— ImageFiltered 在 Impeller 下没有
/// 光栅缓存,牌堆两三张卡一起动时每帧都按屏幕面积重跑高斯,真机可感掉帧;
/// 烘成纹理后每帧只是贴图,和普通图片同价。
class _BlurredBackdrop extends StatefulWidget {
  const _BlurredBackdrop({required this.url, required this.frost});

  final String url;

  /// 罩层不透明度(surface 色):图面留边只轻罩,提示词面要衬字重罩。
  final double frost;

  @override
  State<_BlurredBackdrop> createState() => _BlurredBackdropState();
}

class _BlurredBackdropState extends State<_BlurredBackdrop> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BlurredBackdrop old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _img = null;
      _load();
    }
  }

  void _load() {
    // 缓存命中就同步上,不走「空一帧再淡入」
    final done = _blurDone[widget.url];
    if (done != null) {
      _img = done;
      return;
    }
    final url = widget.url;
    _bakedBlur(url).then((img) {
      if (mounted && img != null && url == widget.url) {
        setState(() => _img = img);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surfaceContainerHighest),
        // 首次到货淡入;挂载时就有(缓存命中)则第一帧直接是 1,不动画
        AnimatedOpacity(
          opacity: _img == null ? 0 : 1,
          duration: Motion.medium,
          child: RawImage(
            image: _img,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
          ),
        ),
        ColoredBox(color: scheme.surface.withValues(alpha: widget.frost)),
      ],
    );
  }
}

/// 提示词面:只读芯片流,例图毛玻璃垫底(无图词条素色)。
/// 装得下就禁止内滚 —— 内层滚动区会把竖向拖动全吃掉,整张弹层跟着卡住。
/// 芯片高度没法按字预算,改从真实布局读:帧后看 maxScrollExtent。
class _PromptFace extends StatefulWidget {
  const _PromptFace({required this.entry, this.bgUrl});

  final CodexEntry entry;
  final String? bgUrl;

  @override
  State<_PromptFace> createState() => _PromptFaceState();
}

class _PromptFaceState extends State<_PromptFace> {
  final _scroll = ScrollController();
  bool _fits = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final fits = _scroll.position.maxScrollExtent <= 0;
      if (fits != _fits) setState(() => _fits = fits);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    _measure();
    final content = SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      physics: _fits ? const NeverScrollableScrollPhysics() : null,
      child: PromptChips(sections: _codexPromptSections(widget.entry)),
    );
    if (widget.bgUrl == null) {
      return ColoredBox(color: scheme.surfaceContainerHigh, child: content);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _BlurredBackdrop(url: widget.bgUrl!, frost: .82),
        content,
      ],
    );
  }
}

/// 法典词条按 [PromptChips] 的口径分段:与 [CodexEntry.fullText] 一致,
/// 公共段 + 各角色段;内联 `charN：` 写法(极少)也拆开 —— 别让 char1
/// 当字面 tag 占一颗芯片。
List<PromptSection> _codexPromptSections(CodexEntry e) {
  final parts = <PromptSection>[];
  if (e.characters.isNotEmpty) {
    if (e.tags.trim().isNotEmpty) parts.add((label: null, body: e.tags));
    for (final c in e.characters) {
      if (c.prompt.trim().isNotEmpty) {
        parts.add((label: c.display, body: c.prompt));
      }
    }
  } else {
    final split = splitCodexCharacters(e.tags);
    if (split.hasCharacters) {
      if (split.base.isNotEmpty) parts.add((label: null, body: split.base));
      for (final c in split.characters) {
        parts.add((label: '角色 ${c.index}', body: c.positive));
        if (c.negative.isNotEmpty) {
          parts.add((label: '角色 ${c.index} · 负向', body: c.negative));
        }
      }
    } else if (e.tags.trim().isNotEmpty) {
      parts.add((label: null, body: e.tags));
    }
  }
  return parts;
}

// ---- 法典选择 ----

Future<String?> showCodexPickerSheet(
  BuildContext context,
  List<CodexMeta> index,
  String? current,
) => _sheet<String>(context, _PickerSheet(index: index, current: current));

class _PickerSheet extends ConsumerWidget {
  const _PickerSheet({required this.index, required this.current});

  final List<CodexMeta> index;
  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '选择法典',
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (final m in index) ...[
            _codexTile(context, ref, m, m.id == current),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _codexTile(
    BuildContext context,
    WidgetRef ref,
    CodexMeta m,
    bool sel,
  ) {
    final scheme = context.scheme;
    return Material(
      color: sel ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // R18 法典不再拦年龄确认框:标题旁的 R18 角标已经把话说清楚了,
        // 每次进都弹一遍只是让人机械点掉。
        onTap: () => Navigator.pop(context, m.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodyLarge!.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (m.type.label.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _tag(context, m.type.label, scheme.secondary),
                        ],
                        if (m.nsfw) ...[
                          const SizedBox(width: 4),
                          _tag(context, 'R18', scheme.error),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${m.author.isNotEmpty ? '${m.author} · ' : ''}'
                      '${m.entryCount} 条',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (sel) Icon(Icons.check, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: context.texts.labelSmall!.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ---- 分类树(层级筛选) ----

/// 打开分类树。[current] 为当前选中路径(空=全部),返回新选中路径
/// (空列表=全部);未选(直接关掉)返回 null,调用方不动。
// ---- 收藏夹 ----

/// 收藏夹。跨法典,不受当前法典/筛选影响 —— 收藏是「我要留着的那几条」,
/// 不是当前视图的子集。
Future<void> showCodexFavoritesSheet(BuildContext context) =>
    _sheet(context, const _FavoritesSheet());

class _FavoritesSheet extends ConsumerWidget {
  const _FavoritesSheet();

  /// 收藏里存的是词条快照,图 URL 还得靠 meta(assetBaseUrl / 路径模式)。
  /// 索引里找不到(法典下架 / 换了 id)时给个占位 meta:图可能加载不出,
  /// 但至少不会让那几条收藏凭空从列表里消失。
  CodexMeta _metaOf(List<CodexMeta> index, String id) {
    for (final m in index) {
      if (m.id == id) return m;
    }
    return CodexMeta(id: id, type: CodexType.unknown, title: id);
  }

  Future<void> _clear(BuildContext context, WidgetRef ref, int n) async {
    final ok = await confirmDialog(
      context,
      title: '清空收藏',
      message: '将移除全部 $n 条收藏,不可恢复。法典词条本身不受影响。',
      confirmLabel: '清空',
    );
    if (!ok) return;
    await ref.read(codexFavoritesProvider.notifier).clearAll();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final favs = ref.watch(codexFavoritesProvider).value ?? const [];
    final index = ref.watch(codexIndexProvider).value ?? const <CodexMeta>[];
    final media = ref.watch(codexMediaProvider).value ?? CodexMedia.fallback;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '收藏',
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${favs.length} / ${CodexFavoritesNotifier.kMax}',
                    style: mono(
                      context,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (favs.isNotEmpty)
                    TextButton(
                      onPressed: () => _clear(context, ref, favs.length),
                      child: const Text('清空'),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
            Flexible(
              child: favs.isEmpty
                  ? _empty(context)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            // 收藏夹走等比网格,不做瀑布流:这里是「翻自己存的
                            // 那几条」,整齐比错落好扫
                            childAspectRatio: 0.78,
                          ),
                      itemCount: favs.length,
                      itemBuilder: (context, i) {
                        final f = favs[i];
                        final meta = _metaOf(index, f.codexId);
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: CodexCard(
                                codex: meta,
                                entry: f.entry,
                                media: media,
                                fixedAspect: 0.78,
                                // 收藏跨法典,左右翻页会拿 A 的 meta 去解 B 的
                                // 图 —— 这里只开单条,不组批
                                onTap: () => showCodexDetailSheet(
                                  context,
                                  meta,
                                  media,
                                  entries: [f.entry],
                                  index: 0,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: _UnfavDot(
                                onTap: () => ref
                                    .read(codexFavoritesProvider.notifier)
                                    .remove(f.key),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_outline_rounded,
            size: 44,
            color: scheme.outlineVariant,
          ),
          const SizedBox(height: 10),
          Text(
            '还没有收藏',
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '点开任意词条,左下角那颗星即可收藏',
            textAlign: TextAlign.center,
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 卡角上的取消收藏:实心星 + 暗底,压在例图上也看得清。
class _UnfavDot extends StatelessWidget {
  const _UnfavDot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .42),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        child: const SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.star_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

Future<List<String>?> showCodexCategorySheet(
  BuildContext context,
  List<CodexNode> tree,
  List<String> current,
  int total,
) => _sheet<List<String>>(
  context,
  _CategorySheet(tree: tree, current: current, total: total),
);

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({
    required this.tree,
    required this.current,
    required this.total,
  });

  final List<CodexNode> tree;
  final List<String> current;
  final int total;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  /// 浏览游标(已下钻到的路径,非选中项)。打开时定位到当前选中项的父层,
  /// 好直接在同层改选。
  late List<String> _cursor = widget.current.length > 1
      ? widget.current.sublist(0, widget.current.length - 1)
      : <String>[];

  /// 层级切换方向:下钻=true(新层从右侧滑入)、返回=false(从左侧滑入)。
  bool _forward = true;

  /// 按名字在树里逐级下钻到某路径的节点(找不到返回 null)。
  CodexNode? _nodeAt(List<String> path) {
    var nodes = widget.tree;
    CodexNode? cur;
    for (final name in path) {
      cur = null;
      for (final n in nodes) {
        if (n.name == name) {
          cur = n;
          break;
        }
      }
      if (cur == null) return null;
      nodes = cur.children;
    }
    return cur;
  }

  List<CodexNode> get _level =>
      _cursor.isEmpty ? widget.tree : (_nodeAt(_cursor)?.children ?? const []);

  bool _isCurrent(List<String> path) {
    if (path.length != widget.current.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (path[i] != widget.current[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 定高弹层:各父类的二级分类数量不同,自适应高度会让弹层「一会高一会低」;
    // 定高后切分支只在内部滚动,弹层本身不再跳,层级切换用滑动+淡入表现进/退。
    final h = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(
      height: h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _breadcrumb(scheme),
          Expanded(
            // 层级切换走 Material 共享轴(横向):下钻新层从右侧滑入、旧层向左退出;
            // 返回(reverse)反向。与 app 内页面转场同一套动效语言。
            child: PageTransitionSwitcher(
              duration: Motion.medium,
              reverse: !_forward,
              transitionBuilder: (child, primary, secondary) =>
                  SharedAxisTransition(
                    animation: primary,
                    secondaryAnimation: secondary,
                    transitionType: SharedAxisTransitionType.horizontal,
                    fillColor: Colors.transparent,
                    child: child,
                  ),
              child: KeyedSubtree(
                key: ValueKey('${_cursor.length}/${_cursor.join('/')}'),
                child: _levelList(scheme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前层:整层选择(全部)+ 各子分类。定高内部滚动,不撑动弹层。
  Widget _levelList(ColorScheme scheme) {
    final atRoot = _cursor.isEmpty;
    final branchCount = atRoot
        ? widget.total
        : (_nodeAt(_cursor)?.count ?? widget.total);
    return ListView(
      // primary:false —— 过场时新旧两个 ListView 并存,别去抢同一个滚动位置
      primary: false,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      children: [
        // 选此层整体:全部 /(下钻后)全部「当前分类」。
        // 根层的「全部」= 未筛选的默认态,不高亮(否则像是用户主动选的,误导);
        // 下钻后的「全部「X」」只有确实是当前筛选路径时才高亮。
        _tile(
          scheme,
          label: atRoot ? '全部' : '全部「${_cursor.last}」',
          count: branchCount,
          selected: atRoot ? false : _isCurrent(_cursor),
          leadingAll: true,
          onTap: () => Navigator.pop(context, atRoot ? <String>[] : _cursor),
        ),
        const SizedBox(height: 8),
        for (final n in _level) ...[
          _tile(
            scheme,
            label: n.name,
            count: n.count,
            selected: _isCurrent([..._cursor, n.name]),
            // 有子级 → 点进去(下钻);叶子 → 直接选中
            drillable: n.children.isNotEmpty,
            onTap: n.children.isNotEmpty
                ? () => setState(() {
                    _forward = true;
                    _cursor = [..._cursor, n.name];
                  })
                : () => Navigator.pop(context, [..._cursor, n.name]),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 面包屑:返回 + 可点的层级路径(点任一级跳回该层)。定高 + 定宽返回位,
  /// 让根/非根切换时文字起点与整条高度都不抖。
  Widget _breadcrumb(ColorScheme scheme) {
    final atRoot = _cursor.isEmpty;
    Widget seg(String label, VoidCallback? onTap) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          label,
          maxLines: 1,
          style: context.texts.titleSmall!.copyWith(
            fontWeight: FontWeight.w700,
            color: onTap == null ? scheme.onSurface : scheme.primary,
          ),
        ),
      ),
    );
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
        child: Row(
          children: [
            // 根层不占返回位,「分类」直接靠左;下钻后才出现返回键
            if (!atRoot)
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                tooltip: '上一级',
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => setState(() {
                  _forward = false;
                  _cursor = _cursor.sublist(0, _cursor.length - 1);
                }),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    seg(
                      '分类',
                      atRoot
                          ? null
                          : () => setState(() {
                              _forward = false;
                              _cursor = <String>[];
                            }),
                    ),
                    for (var i = 0; i < _cursor.length; i++) ...[
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: scheme.outline,
                      ),
                      seg(
                        _cursor[i],
                        i == _cursor.length - 1
                            ? null
                            : () => setState(() {
                                _forward = false;
                                _cursor = _cursor.sublist(0, i + 1);
                              }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一张分类卡:填充底 + 圆角 + 大点击区(靠外部 8px 间距分隔,不再贴边)。
  Widget _tile(
    ColorScheme scheme, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    bool drillable = false,
    bool leadingAll = false,
  }) {
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final sub = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              if (leadingAll) ...[
                // 中性「全部」标识,别用对勾类图标——那会被当成「已选中」而误导
                Icon(
                  Icons.apps,
                  size: 18,
                  color: selected ? scheme.onPrimaryContainer : scheme.primary,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$count',
                style: context.texts.labelMedium!.copyWith(
                  color: sub,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (drillable) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: sub),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 来源致谢(attribution) ----

Future<void> showCodexAboutSheet(BuildContext context, CodexMeta m) =>
    _sheet(context, _AboutSheet(m));

class _AboutSheet extends StatelessWidget {
  const _AboutSheet(this.m);

  final CodexMeta m;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.displayTitle,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (m.source.isNotEmpty) _line(context, '来源', m.source),
            if (m.author.isNotEmpty) _line(context, '作者', m.author),
            if (m.version.isNotEmpty) _line(context, '版本', m.version),
            if (m.contributors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '贡献者',
                style: context.texts.labelMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final c in m.contributors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${c.name}${c.role.isNotEmpty ? ' · ${c.role}' : ''}',
                    style: context.texts.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Text(
              '内容与例图版权归各法典作者所有,本页仅作可视化索引。',
              style: context.texts.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final l in [
              ...m.links,
              (label: '法典图鉴 · 原站', url: 'https://novelai.quicktagcloud.com'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(l.url),
                    mode: LaunchMode.externalApplication,
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    l.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: RichText(
      text: TextSpan(
        style: context.texts.bodySmall,
        children: [
          TextSpan(
            text: '$k  ',
            style: TextStyle(color: context.scheme.onSurfaceVariant),
          ),
          TextSpan(text: v),
        ],
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../data/suggestions.dart' show translationOf;
import '../editor_models.dart';
import '../../../core/util/haptics.dart';

/// 词条栏 / 权重面板 —— 光标右邻是本标签正文时吸在键盘上方。
/// 头部(名字·热度·翻译·维基·复制·收藏·关闭)+ 权重(括号快捷键 · 数值加减,长按持续)
/// + 清除/关联/禁用/删除 + 关联标签(点「关联」才展开)。改动都由页面改文本落地。
class TagPanel extends StatefulWidget {
  const TagPanel({
    super.key,
    required this.tok,
    required this.count,
    required this.related,
    this.relatedLoading = false,
    this.weightStep = 0.1,
    this.compact = false,
    this.sdConvert,
    this.onSelectGroup,
    required this.onWrap,
    required this.onSetMult,
    required this.onClear,
    required this.onToggleDisabled,
    required this.onDelete,
    required this.onAddRelated,
    required this.onClose,
    this.onRename,
    this.favorited = false,
    this.onToggleFavorite,
  });

  final Tok tok;
  final int? count;
  final List<String> related;

  /// 这枚标签已在收藏里(头部星标实心)。
  final bool favorited;

  /// 收 / 取消收藏;null = 不给星标。
  final VoidCallback? onToggleFavorite;

  /// 行内改名(芯片模式专有:那边没有光标,改字只能从这里进)。
  /// null = 文本模式,点标题不进编辑态——直接点正文里那个词就行。
  final void Function(String name)? onRename;

  /// 当前词条是 SD 权重语法时的转换回调(web convertSDToNAI);null=非 SD。
  final VoidCallback? sdConvert;

  /// 词条处于跨词条权重组时的「选中整组」回调(把选区扩到整组进批量
  /// 面板调组权重);null=不在组内。
  final VoidCallback? onSelectGroup;

  /// 数值加减每步的调整量(编辑器设置:0.05 / 0.1)。
  final double weightStep;

  /// 一行精简版(编辑器设置「精简词条栏」)。见 [_TagPanelState._compactRow]。
  final bool compact;

  /// 关联标签正在异步拉取(按钮不置灰,左侧显示转圈)。
  final bool relatedLoading;

  /// 括号快捷键:套一层 {}(up=true)或 [](up=false),不动数值
  final void Function(bool up) onWrap;

  /// 数值加减:改内层 `N::tag::` 倍率
  final void Function(double mult) onSetMult;

  /// 清除权重:去括号 + 数值
  final VoidCallback onClear;
  final VoidCallback onToggleDisabled;
  final VoidCallback onDelete;
  final void Function(String tag) onAddRelated;

  /// 关闭词条栏
  final VoidCallback onClose;

  @override
  State<TagPanel> createState() => _TagPanelState();
}

/// 精简词条栏的控件尺寸。抽成常量是因为 [_TagPanelState._compactRow] 要靠
/// 它们判断放不放得下 —— 硬编码两份迟早对不上。
///
/// 尺寸按窄屏倒推:1200px / 520dpi = **369 dp**,
/// 去掉内边距只剩 353 装八个控件。按这一版的数是 334,留 19 的余量,
/// 360 那档也放得下。一行里塞八样东西,单颗就只能到这个尺寸 ——
/// 想再粗只能减功能。
///
/// ⇄ 那枚条件图标出现时(SD 语法,很少见)会超出这个预算,整排退化成横向
/// 可滚。那是有意的取舍:为了一个罕见状态把常态的按钮再削一圈不划算。
const double _kWrapW = 38; // [ ] / { }
const double _kWrapH = 38;
const double _kStepW = 36; // ⊖ / ⊕
const double _kReadW = 48; // ×N 读数(mono 12 下「×1.2」正好 48)
const double _kTailW = 34; // ⌫ / 👁 / 🗑 / ⇄

/// 控件之间**唯一**的间距。原先是 2/2/8/10/2 各不相同,想用疏密表达分组,
/// 结果只是看着乱 —— 分组交给中间那道弹性空隙就够了。
///
/// 5 而不是 6:八个控件排下来差的那 6 宽,正好是 360 那档机型「一屏摆下」
/// 和「退化成横向滚动」的分界。
const double _kGap = 5;

/// 完整版面板(词条栏 / 批量面板)的控件高度:头部圆钮、权重行的括号键与
/// 加减钮、底下那排操作键全用这一个数,面板的纵向节奏只由它和几道缝决定。
const double _kPanelBtnH = 38;

class _TagPanelState extends State<TagPanel> {
  bool _relatedOpen = false; // 关联标签是否展开
  bool _renaming = false; // 标题处于行内改名态
  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  @override
  void didUpdateWidget(TagPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切到另一枚标签时收起关联与改名(同枚改权重则保持)
    if (oldWidget.tok.name != widget.tok.name) {
      _relatedOpen = false;
      _renaming = false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startRename() {
    final name = widget.tok.name;
    _nameCtrl.value = TextEditingValue(
      text: name,
      // 全选:改名多半是整枚换掉,不是补字
      selection: TextSelection(baseOffset: 0, extentOffset: name.length),
    );
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _commitRename() {
    final v = _nameCtrl.text.trim();
    setState(() => _renaming = false);
    _nameFocus.unfocus();
    if (v.isEmpty || v == widget.tok.name) return;
    widget.onRename?.call(v);
  }

  void _cancelRename() {
    setState(() => _renaming = false);
    _nameFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final pal = context.editor;
    final tok = widget.tok;
    final on = !tok.disabled;

    // 读数/名字色以 +/− 与清除改的那份权重为准([Tok.tagMult]):自身写的,
    // 或包着它的数值组 —— 读数与操作对象一致才不跳变。括号组单独一行展示。
    final Color wc = tok.disabled
        ? scheme.onSurfaceVariant
        : tok.tagMult > 1.0001
        ? pal.weightUp
        : tok.tagMult < 0.9999
        ? pal.weightDown
        : scheme.onSurface;

    final hasRelated = widget.related.isNotEmpty;

    if (widget.compact) {
      return Material(
        color: context.editorDock,
        shape: Border(top: BorderSide(color: context.editorDockLine)),
        child: Padding(
          // 上下各 10:按钮 38 高,一行落在 58 —— 完整版约 155
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: _compactRow(context, wc),
        ),
      );
    }

    return Material(
      color: context.editorDock,
      shape: Border(top: BorderSide(color: context.editorDockLine)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              tok: tok,
              count: widget.count,
              wc: wc,
              favorited: widget.favorited,
              onToggleFavorite: widget.onToggleFavorite,
              onClose: widget.onClose,
              renaming: _renaming,
              nameCtrl: _nameCtrl,
              nameFocus: _nameFocus,
              onStartRename: widget.onRename == null ? null : _startRename,
              onCommitRename: _commitRename,
              onCancelRename: _cancelRename,
            ),
            // 跨词条权重组信息:自身读数之外单独陈述组权重与合计,
            // 「选中整组」一键进批量面板调组权重。
            if (tok.inGroup)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '处于权重组 ×${fmtMult(tok.groupMult)} · '
                        '合计 ×${fmtMult(tok.effMult)}',
                        style: context.texts.labelSmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (widget.onSelectGroup != null)
                      Material(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(9),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: widget.onSelectGroup,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            child: Text(
                              '选中整组',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (widget.sdConvert != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Material(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.sdConvert,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.autorenew,
                            size: 16,
                            color: scheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'SD 权重语法 · 点击转换为 NAI 格式',
                              style: context.texts.labelMedium!.copyWith(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: scheme.onTertiaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 权重:括号快捷键(左)· 数值加减(右,支持长按持续步进,读数居中)
            Row(
              children: [
                Text(
                  '权重',
                  style: context.texts.bodyMedium!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                _weightBtn(
                  context,
                  '[ ]',
                  pal.weightDown,
                  scheme.onError,
                  enabled: on,
                  onTap: () => widget.onWrap(false),
                ),
                const SizedBox(width: 6),
                _weightBtn(
                  context,
                  '{ }',
                  pal.weightUp,
                  scheme.onError,
                  enabled: on,
                  onTap: () => widget.onWrap(true),
                ),
                const Spacer(),
                RepeatBtn(
                  icon: Icons.remove,
                  enabled: on,
                  size: _kPanelBtnH,
                  step: () =>
                      widget.onSetMult(tok.numWeight - widget.weightStep),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '×${fmtMult(tok.tagMult)}',
                    textAlign: TextAlign.center,
                    // 读数只报数,不跟着权重变红蓝 —— 高低看名字色与正文色带
                    style: mono(
                      context,
                      size: 16,
                      color: tok.disabled
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
                RepeatBtn(
                  icon: Icons.add,
                  enabled: on,
                  size: _kPanelBtnH,
                  step: () =>
                      widget.onSetMult(tok.numWeight + widget.weightStep),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 操作:清除权重 · 关联(点开展开)· 禁用 · 删除
            Row(
              children: [
                Expanded(
                  child: _action(
                    context,
                    '清除权重',
                    enabled:
                        on &&
                        (tok.braceLevel != 0 ||
                            (tok.numWeight - 1.0).abs() >= 0.005),
                    onTap: widget.onClear,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    context,
                    '关联',
                    icon: widget.relatedLoading
                        ? null
                        : (_relatedOpen
                              ? Icons.expand_less
                              : Icons.expand_more),
                    // 加载中:左侧转圈,按钮不置灰(点击暂无动作)
                    leading: widget.relatedLoading
                        ? SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    enabled: widget.relatedLoading || hasRelated,
                    selected: _relatedOpen,
                    onTap: widget.relatedLoading
                        ? () {}
                        : () => setState(() => _relatedOpen = !_relatedOpen),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    context,
                    tok.disabled ? '启用' : '禁用',
                    icon: tok.disabled
                        ? Icons.visibility
                        : Icons.visibility_off,
                    enabled: true,
                    onTap: widget.onToggleDisabled,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    context,
                    '删除',
                    icon: Icons.delete_outline,
                    danger: true,
                    enabled: true,
                    onTap: widget.onDelete,
                  ),
                ),
              ],
            ),
            // 关联标签:点「关联」展开一行横向滚动(定高,再多也不溢出;
            // Wrap 多行版在词多时撑破 dock 区,弃用)
            AnimatedSize(
              duration: Motion.fast,
              curve: Motion.emphasized,
              alignment: Alignment.topCenter,
              child: (_relatedOpen && hasRelated)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.related.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) => TagAddChip(
                            tag: widget.related[i],
                            onTap: () => widget.onAddRelated(widget.related[i]),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  /// 一行精简版。
  ///
  ///     [⚠][⇄]   [ ] ⊖ ×1.2 ⊕ { }  ⌫        👁  🗑
  ///               └────── 权重 ──────┘        └标签┘
  ///
  /// **不显示标签名。** 这一栏吸在正文正下方,而那枚标签此刻正在正文里高亮着 ——
  /// 再抄一遍名字是复述,却要吃掉一百来宽。省下来的位置换成了三样真能用的:
  /// ×N 读数、启用/禁用,以及粗一圈的按钮。
  ///
  /// 分两组,中间用弹性空隙隔开:
  ///  · **权重组** —— 括号、数值加减、读数、清除。括号在最外、数值在里,
  ///    读数居中,左半降权右半加权,四颗键排成一条从轻到重的轴;
  ///  · **标签组** —— 启用/禁用、删除。它们改的是这枚词本身,不是它的权重。
  ///
  /// 收走的仍然是:热度、译文、维基、复制、改名、关联。译文在正文的注音层里
  /// 就有;关联要展开第二行,和「一行」直接冲突。关闭 ✕ 也没有 —— 光标挪开
  /// (文本模式)、再点一下那枚 chip 或点空白(芯片模式)都会收走这一栏。
  ///
  /// 放不下时整排改成横向可滚,一个功能都不砍(分屏 / 超窄机会走到这条)。
  Widget _compactRow(BuildContext context, Color wc) {
    final scheme = context.scheme;
    final pal = context.editor;
    final tok = widget.tok;
    final on = !tok.disabled;
    final canClear =
        on && (tok.braceLevel != 0 || (tok.numWeight - 1.0).abs() >= 0.005);
    final inGroup = tok.inGroup;
    final weighted = (tok.tagMult - 1).abs() > 0.005;

    // 固定宽的那几段。**改控件尺寸要同步改这里** —— 这几个数是「滚不滚」的
    // 依据,对不上就会在该滚的时候不滚(溢出)。
    // [ ] ⊖ ×N ⊕ { } ⌫ 六件 + 五道缝
    const weightW = _kWrapW * 2 + _kStepW * 2 + _kReadW + _kTailW + _kGap * 5;
    const tagW = _kTailW * 2 + _kGap; // 👁 🗑
    final extra = widget.sdConvert != null ? _kTailW + _kGap : 0;
    // 两组之间至少也留一道同样的缝
    final fixed = weightW + tagW + _kGap + extra;

    /// ×N 读数。**槽是定宽的**,×1 也照常显示 —— 让它在有没有权重之间伸缩,
    /// 整排键会跟着左右挪,而这一栏正是拿来连点加减的。没权重时压灰:
    /// 在场但不喧宾夺主。
    ///
    /// 读数只报数,不跟着权重变红蓝 —— 高低看正文的色带,以及旁边那两颗
    /// 本来就是彩的括号键。
    Widget readout() => SizedBox(
      width: _kReadW,
      // 在权重组里时长按报组信息:组权重与合计在这儿没地方常驻,而不说的话
      // 按 +/− 时同组的词跟着变、括号组那层读数里又没算,这一栏就在骗人。
      // 旁边那枚图层图标是「这里还有话」的记号。
      child: GestureDetector(
        onLongPress: inGroup
            ? () {
                Haptics.selection();
                hintSnack(
                  context,
                  '处于权重组 ×${fmtMult(tok.groupMult)} · '
                  '合计 ×${fmtMult(tok.effMult)}',
                  icon: Icons.layers_outlined,
                );
              }
            : null,
        // 三位数权重(×12.5)加上组标记会顶破这 50 宽 —— 缩字而不是溢出
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inGroup) ...[
                Icon(
                  Icons.layers_outlined,
                  size: 12,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
              ],
              Text(
                '×${fmtMult(tok.tagMult)}',
                // 12 不是随手挑的:这套等宽字的步进宽度**等于字号**,
                // ×1.2 四个字符正好 48,卡在 50 的槽里不用缩
                style: mono(
                  context,
                  size: 12,
                  weight: weighted ? FontWeight.w700 : FontWeight.w500,
                  color: (weighted && on)
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    List<Widget> lead() => [
      if (widget.sdConvert != null) ...[
        _denseIcon(
          context,
          Icons.autorenew,
          color: scheme.tertiary,
          tooltip: 'SD 权重语法 · 转成 NAI',
          onTap: widget.sdConvert!,
        ),
        const SizedBox(width: _kGap),
      ],
    ];

    List<Widget> weightGroup() => [
      _weightBtn(
        context,
        '[ ]',
        pal.weightDown,
        scheme.onError,
        enabled: on,
        onTap: () => widget.onWrap(false),
        width: _kWrapW,
        height: _kWrapH,
        fontSize: 12, // 3 × 12 = 36,卡在 38 的键里
      ),
      const SizedBox(width: _kGap),
      RepeatBtn(
        icon: Icons.remove,
        enabled: on,
        size: _kStepW,
        step: () => widget.onSetMult(tok.numWeight - widget.weightStep),
      ),
      const SizedBox(width: _kGap),
      readout(),
      const SizedBox(width: _kGap),
      RepeatBtn(
        icon: Icons.add,
        enabled: on,
        size: _kStepW,
        step: () => widget.onSetMult(tok.numWeight + widget.weightStep),
      ),
      const SizedBox(width: _kGap),
      _weightBtn(
        context,
        '{ }',
        pal.weightUp,
        scheme.onError,
        enabled: on,
        onTap: () => widget.onWrap(true),
        width: _kWrapW,
        height: _kWrapH,
        fontSize: 12,
      ),
      const SizedBox(width: _kGap),
      _denseIcon(
        context,
        Icons.backspace_outlined,
        tooltip: '清除权重',
        enabled: canClear,
        onTap: widget.onClear,
      ),
    ];

    List<Widget> tagGroup() => [
      _denseIcon(
        context,
        // 禁用是给这枚词套 `~ ~`,正文里它会被划掉。图标报的是**按下去会
        // 变成什么**:禁着的时候给一只睁眼(点了就启用)。
        tok.disabled ? Icons.visibility : Icons.visibility_off,
        color: tok.disabled ? scheme.primary : null,
        tooltip: tok.disabled ? '启用' : '禁用',
        onTap: widget.onToggleDisabled,
      ),
      const SizedBox(width: _kGap),
      _denseIcon(
        context,
        Icons.delete_outline,
        color: scheme.error,
        tooltip: '删除',
        onTap: widget.onDelete,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < fixed) {
          // 放不下:横向可滚,一个功能都不砍
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...lead(),
                ...weightGroup(),
                const SizedBox(width: _kGap),
                ...tagGroup(),
              ],
            ),
          );
        }
        return Row(
          children: [
            ...lead(),
            ...weightGroup(),
            // 弹性空隙:宽屏上把两组分得开,窄屏上自己收到 0
            const Spacer(),
            ...tagGroup(),
          ],
        );
      },
    );
  }
}

/// 加标签的小卡:英文 + 中文双行(web RelatedTagsRow 同形态),点按插入。
/// 关联标签与底栏收藏共用;高度由外层定。
class TagAddChip extends StatelessWidget {
  const TagAddChip({
    super.key,
    required this.tag,
    required this.onTap,
    this.onLongPress,
  });

  final String tag;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final trans = translationOf(tag);
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(11),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 13, color: scheme.primary),
                  const SizedBox(width: 3),
                  Text(
                    tag,
                    style: context.texts.bodySmall!.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (trans != null) ...[
                const SizedBox(height: 1),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    trans,
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 头部:名字 · 热度 · 翻译 · 维基 · 复制 · 收藏 · 关闭
class _Header extends StatelessWidget {
  const _Header({
    required this.tok,
    required this.count,
    required this.wc,
    required this.favorited,
    required this.onToggleFavorite,
    required this.onClose,
    required this.renaming,
    required this.nameCtrl,
    required this.nameFocus,
    required this.onStartRename,
    required this.onCommitRename,
    required this.onCancelRename,
  });

  final Tok tok;
  final int? count;
  final Color wc;
  final bool favorited;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onClose;

  /// 标题处于行内改名态:整行换成输入框 + 确认/取消。
  final bool renaming;
  final TextEditingController nameCtrl;
  final FocusNode nameFocus;

  /// null = 本模式不给改名入口(点标题没反应)。
  final VoidCallback? onStartRename;
  final VoidCallback onCommitRename;
  final VoidCallback onCancelRename;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    if (renaming) return _renameRow(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onStartRename,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        tok.name.isEmpty ? '标签' : tok.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleMedium!.copyWith(
                          color: wc,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          decoration: tok.disabled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        _formatCount(count!),
                        style: mono(
                          context,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                // 译文只给一行:长译文折成两行会把整张面板顶高一截
                if (tok.trans != null && tok.trans!.isNotEmpty)
                  Text(
                    tok.trans!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (tok.name.isNotEmpty) ...[
          _circleIcon(
            context,
            icon: Icons.travel_explore,
            onTap: () => _openWiki(context, tok.name),
          ),
          const SizedBox(width: 4),
        ],
        _circleIcon(
          context,
          icon: Icons.content_copy,
          onTap: () {
            Clipboard.setData(ClipboardData(text: tok.name));
            hintSnack(context, '已复制标签', icon: Icons.check);
          },
        ),
        if (onToggleFavorite != null && tok.name.isNotEmpty) ...[
          const SizedBox(width: 4),
          _circleIcon(
            context,
            icon: favorited ? Icons.star_rounded : Icons.star_outline_rounded,
            color: favorited ? scheme.primary : null,
            // 星形只占图标框七成,22 才和旁边 18 的图标看着一样大
            size: 22,
            onTap: () {
              Haptics.selection();
              onToggleFavorite!();
            },
          ),
        ],
        const SizedBox(width: 4),
        _circleIcon(context, icon: Icons.close, onTap: onClose),
      ],
    );
  }

  /// 改名态:标题整行换成输入框。回车 = 确认,Esc/✕ = 放弃。
  Widget _renameRow(BuildContext context) {
    final scheme = context.scheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: nameCtrl,
            focusNode: nameFocus,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onCommitRename(),
            style: context.texts.titleMedium!.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
            cursorColor: scheme.primary,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _circleIcon(context, icon: Icons.check, onTap: onCommitRename),
        const SizedBox(width: 4),
        _circleIcon(context, icon: Icons.close, onTap: onCancelRename),
      ],
    );
  }

  /// 跳系统浏览器开 Danbooru wiki(web openDanbooru 同款,空格转下划线)。
  Future<void> _openWiki(BuildContext context, String name) async {
    final tag = name.trim().replaceAll(' ', '_');
    final uri = Uri.https('danbooru.donmai.us', '/wiki_pages/$tag');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      hintSnack(context, '无法打开浏览器', icon: Icons.error_outline);
    }
  }

  static String _formatCount(int n) {
    if (n < 1000) return '';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000).round()}k';
  }
}

// ---- 面板共享控件(单词条 TagPanel 与多选 BatchPanel 共用)----

/// 括号快捷键按钮(`[ ]` / `{ }`,语义色填充)。
Widget _weightBtn(
  BuildContext context,
  String label,
  Color bg,
  Color fg, {
  required bool enabled,
  required VoidCallback onTap,
  double width = 46,
  double height = _kPanelBtnH,
  // 「[ ]」是三个等宽字符,而这套字的步进宽度**等于字号** —— 14 号就是 42,
  // 比 38 宽的按钮还宽,一直被裁着画。默认留给完整版(46 宽,放得下)。
  double fontSize = 14,
}) {
  final scheme = context.scheme;
  return Material(
    color: enabled ? bg : scheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(11),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: enabled ? fg : scheme.outlineVariant,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 操作按钮(清除权重/禁用/删除等,危险=红调)。
Widget _action(
  BuildContext context,
  String label, {
  IconData? icon,
  Widget? leading, // 覆盖 icon 的自定义前导(如加载转圈)
  bool danger = false,
  bool selected = false,
  required bool enabled,
  required VoidCallback onTap,
}) {
  final scheme = context.scheme;
  final fg = !enabled
      ? scheme.outlineVariant
      : selected
      ? context.onSelectedFill
      : danger
      ? scheme.error
      : scheme.onSurface;
  final bg = selected
      ? context.selectedFill
      : danger
      ? scheme.error.withValues(alpha: .10)
      : scheme.surfaceContainerHigh;
  return Material(
    color: bg,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: _kPanelBtnH,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 5),
            ] else if (icon != null) ...[
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: context.texts.bodyMedium!.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 圆形小图标按钮(提取 / 复制 / 收藏 / 关闭)。[color] 缺省走 onSurfaceVariant。
Widget _circleIcon(
  BuildContext context, {
  required IconData icon,
  required VoidCallback onTap,
  String? tooltip,
  Color? color,
  double size = 18,
}) {
  final scheme = context.scheme;
  final btn = Material(
    color: scheme.surfaceContainerHighest,
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: _kPanelBtnH,
        height: _kPanelBtnH,
        child: Icon(icon, size: size, color: color ?? scheme.onSurfaceVariant),
      ),
    ),
  );
  return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
}

/// 精简词条栏里的圆钮([_kTailW])。置灰时不可点,颜色跟着语义走。
Widget _denseIcon(
  BuildContext context,
  IconData icon, {
  required VoidCallback onTap,
  required String tooltip,
  Color? color,
  bool enabled = true,
}) {
  final scheme = context.scheme;
  return Tooltip(
    message: tooltip,
    child: Material(
      color: scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: _kTailW,
          height: _kTailW,
          child: Icon(
            icon,
            size: 19,
            color: enabled
                ? (color ?? scheme.onSurfaceVariant)
                : scheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}

/// 多选批量面板 —— **划词多选与多选模式共用同一张**:已选数 + 整体权重
/// + 清除权重 / 禁用 / 删除。
///
/// 面板不认识「怎么选的」:划词是选区扫出的连续区间,多选模式是点 chip 攒出
/// 的集合(可跳选),到这里都只剩已选数与几个能力位。移动不在这里 —— 那是
/// 多选模式画布上点 chip 间隙的 ⊕,就地完成。
///
/// 未选中(只可能出现在多选模式)时按钮全灰,但面板留着占位,不让画布高度
/// 在选/不选之间来回跳。
class BatchPanel extends StatelessWidget {
  const BatchPanel({
    super.key,
    required this.count,
    required this.mult,
    required this.canWeight,
    required this.canDisable,
    required this.anyEnabled,
    this.groupMult,
    this.onSelectGroup,
    this.onUnfold,
    this.foldCount = 0,
    required this.onCopy,
    this.onExtract,
    required this.onWrap,
    required this.onStepMult,
    required this.onClearWeight,
    required this.onToggleDisabled,
    required this.onDelete,
    required this.onClose,
    this.placing = false,
    this.onTogglePlacing,
  });

  /// 已选单元数(0 = 多选模式里还没点;划词多选恒 ≥2)。
  final int count;

  /// 芯片模式的**落位阶段**开着(见 ChipFlowView.placing)。
  final bool placing;

  /// 进/出落位阶段。null = 这条路不适用(划词多选没有芯片可点)或者
  /// 眼下没有能落的位置(比如全选中了,搬到哪儿都还是原样)。
  final VoidCallback? onTogglePlacing;

  /// 面板本地的统一数值权重读数(换一批选中即重置 1.0)。
  final double mult;

  /// 所选里有能加权的连续段(全是零散折叠单元时没有,见 weightRuns)。
  final bool canWeight;

  /// 所选里有散标签(折叠单元不能禁用)。
  final bool canDisable;

  /// 选中里还有启用的 → 动作为「禁用」;全禁 → 「启用」。作用于整批。
  final bool anyEnabled;

  /// 这一批处在更外层权重组里时的组倍率(与 [onSelectGroup] 同进同退)。
  final double? groupMult;

  /// 把选中扩到整个权重组(扩了才能调组权重);null=没有更外层的组。
  final VoidCallback? onSelectGroup;

  /// 恰好选中一枚折叠段时的「展开」入口。芯片模式里没有正文可点标题,
  /// 解散只能从这儿走;null = 选的不是单枚折叠。
  final VoidCallback? onUnfold;

  /// 该折叠段的成员数(与 [onUnfold] 同进同退):展开会摊出多少枚,先说清楚。
  final int foldCount;

  /// 复制所选(折叠摊平成成员,权重/禁用记号照搬)。
  final VoidCallback onCopy;

  /// 把所选提取出来新建一个分区;null = 不给(角色会话没有分区)。
  final VoidCallback? onExtract;

  final void Function(bool up) onWrap;
  final void Function(bool up) onStepMult;
  final VoidCallback onClearWeight;
  final VoidCallback onToggleDisabled;
  final VoidCallback onDelete;

  /// 划词:关面板并折叠选区;多选模式:清空选中(模式本身由底栏退出)。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final pal = context.editor;
    final has = count > 0;
    final weight = has && canWeight;
    // 没得禁用时读数无意义,标签保持「禁用」的默认相,不跳字
    final off = anyEnabled || !canDisable;

    return Material(
      color: context.editorDock,
      shape: Border(top: BorderSide(color: context.editorDockLine)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.select_all,
                  size: 18,
                  color: has ? scheme.primary : scheme.outlineVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    placing ? '点击加号移动' : (has ? '已选 $count 项' : '点词条可多选'),
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: has ? scheme.onSurface : scheme.outline,
                    ),
                  ),
                ),
                if (has) ...[
                  if (onExtract case final extract?) ...[
                    _circleIcon(
                      context,
                      icon: Icons.playlist_add,
                      onTap: extract,
                      tooltip: '提取为新分区',
                    ),
                    const SizedBox(width: 4),
                  ],
                  _circleIcon(context, icon: Icons.content_copy, onTap: onCopy),
                  const SizedBox(width: 4),
                  _circleIcon(context, icon: Icons.close, onTap: onClose),
                ],
              ],
            ),
            // 这一批还在更大的权重组里:一键把选中扩到整组,才好调组权重
            // (单词条栏同款入口)。
            if (onSelectGroup != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '处于权重组 ×${fmtMult(groupMult ?? 1)}',
                        style: context.texts.labelSmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Material(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(9),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onSelectGroup,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          child: Text(
                            '选中整组',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (onUnfold != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.unfold_more,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '折叠段 · $foldCount 个标签',
                        style: context.texts.labelSmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Material(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(9),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onUnfold,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          child: Text(
                            '展开',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // 权重:括号快捷键(左)· 统一数值加减(右,长按持续步进)
            Row(
              children: [
                Text(
                  '整体',
                  style: context.texts.bodyMedium!.copyWith(
                    color: weight ? scheme.onSurfaceVariant : scheme.outline,
                  ),
                ),
                const SizedBox(width: 12),
                _weightBtn(
                  context,
                  '[ ]',
                  pal.weightDown,
                  scheme.onError,
                  enabled: weight,
                  onTap: () => onWrap(false),
                ),
                const SizedBox(width: 6),
                _weightBtn(
                  context,
                  '{ }',
                  pal.weightUp,
                  scheme.onError,
                  enabled: weight,
                  onTap: () => onWrap(true),
                ),
                const Spacer(),
                RepeatBtn(
                  icon: Icons.remove,
                  enabled: weight,
                  size: _kPanelBtnH,
                  step: () => onStepMult(false),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '×${fmtMult(mult)}',
                    textAlign: TextAlign.center,
                    style: mono(
                      context,
                      size: 16,
                      color: weight ? scheme.onSurface : scheme.outlineVariant,
                    ),
                  ),
                ),
                RepeatBtn(
                  icon: Icons.add,
                  enabled: weight,
                  size: _kPanelBtnH,
                  step: () => onStepMult(true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _action(
                    context,
                    '移动',
                    icon: Icons.swap_horiz,
                    // 亮着 = 落位阶段开着,再点一下退出。没有有效落点时这颗
                    // 是灰的(判据见 chipValidGaps),免得点进一个空阶段。
                    selected: placing,
                    enabled: onTogglePlacing != null,
                    onTap: onTogglePlacing ?? () {},
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    context,
                    '清除权重',
                    enabled: weight,
                    onTap: onClearWeight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    context,
                    off ? '禁用' : '启用',
                    icon: off ? Icons.visibility_off : Icons.visibility,
                    enabled: has && canDisable,
                    onTap: onToggleDisabled,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(
                    context,
                    '删除',
                    icon: Icons.delete_outline,
                    danger: true,
                    enabled: has,
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 按住持续步进按钮:点=一步;按住≥350ms 后每 90ms 触发一次 [step],
/// 越按越快(每 5 步周期 −15ms,下限 40ms)。松手或超出按钮范围停止。
///
/// 导出给编辑器设置里的加减行复用 —— 那边的字号/步进是大范围连续调,
/// 没有连发就得点几十下。
class RepeatBtn extends StatefulWidget {
  const RepeatBtn({
    super.key,
    required this.icon,
    required this.enabled,
    required this.step,
    this.size = 38,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback step;

  /// 圆钮直径。精简版收到 32(图标跟着缩)。
  final double size;

  @override
  State<RepeatBtn> createState() => _RepeatBtnState();
}

class _RepeatBtnState extends State<RepeatBtn> {
  Timer? _hold;
  Timer? _tick;
  int _ticks = 0;

  void _startHold() {
    _hold?.cancel();
    _tick?.cancel();
    _hold = Timer(const Duration(milliseconds: 350), () {
      Haptics.selection();
      _scheduleNext();
    });
  }

  void _scheduleNext() {
    if (!widget.enabled) return _stop();
    // 越按越快
    final period = (90 - (_ticks ~/ 5) * 15).clamp(40, 90);
    _tick = Timer(Duration(milliseconds: period), () {
      widget.step();
      _ticks++;
      _scheduleNext();
    });
  }

  void _stop() {
    _hold?.cancel();
    _tick?.cancel();
    _hold = null;
    _tick = null;
    _ticks = 0;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Listener(
      onPointerDown: (_) {
        if (!widget.enabled) return;
        _startHold();
      },
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.step : null,
        child: Material(
          color: scheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Icon(
              widget.icon,
              size: widget.size >= 38 ? 20 : 18,
              color: widget.enabled ? scheme.onSurface : scheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

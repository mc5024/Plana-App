import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editor_theme.dart';
import '../../core/ui/ime_shift_select.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart' show PromptSection;
import '../generate/widgets/common.dart' show hintSnack;
import 'data/suggestions.dart';
import 'data/tag_completion.dart';
import 'data/tag_favorites.dart';
import 'data/tag_translation_service.dart';
import 'editor_models.dart';
import 'editor_settings.dart';
import 'editor_state.dart';
import 'widgets/annotated_field.dart';
import 'widgets/chip_flow_view.dart';
import 'widgets/completion_bar.dart';
import 'widgets/completion_panel.dart';
import 'widgets/editor_bottom_bar.dart';
import 'widgets/editor_settings_sheet.dart';
import 'widgets/editor_top_bar.dart';
import 'widgets/rich_tag_controller.dart';
import 'widgets/tag_panel.dart';
import '../../core/util/haptics.dart';
import 'chrome_scroll.dart';

/// 提示词编辑器。正文有两种形态,底栏一键切,选择记在编辑器设置里:
///
/// - **注音富文本**(默认,光标驱动定稿):可编辑文本域,权重原样内联+上色,
///   翻译绘制层画在词下。底部只一件事——光标点在词里(含多词名内部空格)
///   →词条栏;逗号/词条间空隙/行尾或打字中→补全。
/// - **芯片流**(web 移动端同款):一枚标签一颗 chip,点选/多选/⊕ 搬运,
///   打字走尾部输入框。没有光标,改名从词条栏进,折叠解散从批量面板进。
///
/// 两种形态共用同一个 [RichTagController] —— 芯片模式下正文没挂在树上,
/// 但所有改文本的操作仍旧改它,于是切回来时状态天然一致。
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({
    super.key,
    required this.positive,
    this.charId,
    this.sectionId,
  });

  final bool positive;

  /// 编辑目标:null = 创作页主提示词,否则 = 该 id 的角色提示词。
  final String? charId;

  /// 编辑目标是主提示词的某个分区(见 PromptSection);与 [charId] 互斥。
  final String? sectionId;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with SingleTickerProviderStateMixin {
  final RichTagController _controller = RichTagController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  /// 芯片模式的尾部输入框(唯一打字入口)。控制器提在页面上:补全管线要读它。
  final TextEditingController _input = TextEditingController();

  final FocusNode _inputFocus = FocusNode();

  /// 输入框的**有效**文本:去掉常驻的零宽占位符(见 [kChipInputPad])。
  /// 凡是读 _input.text 的地方都走这里 —— 占位符不是用户打的字。
  String get _inputText => chipInputBody(_input.text);

  /// 上一次的有效文本。用来分辨「空框退格」和「把打了一半的词全选删掉」——
  /// 两者都让框子变空,但后者不该顺手把标签也删了。
  String _prevInputBody = '';

  /// 把输入框清成「只剩占位符」的空态。芯片模式下清空一律走这里:
  /// 真清成空串的话,下一次空框退格就又收不到信号了。
  void _resetInput() => _setInputBody('');

  /// 正/负切换时编辑区的方向滑入(切负面从右进、切正面从左进)。
  late final AnimationController _tabAnim = AnimationController(
    vsync: this,
    duration: Motion.medium,
  )..value = 1;
  Animation<Offset> _tabSlide = const AlwaysStoppedAnimation(Offset.zero);

  Timer? _debounce;
  bool _muting = false;
  String _prevText = '';
  TextSelection _prevSel = const TextSelection.collapsed(offset: -1);
  String? _syncedText;
  String _query = '';
  SuggestResult _result = const SuggestResult();
  int _queryGen = 0; // 递增序号:作废在途异步补全(被后续输入/移光标取代)
  bool _loading = false; // 补全查询进行中(显示加载态)
  bool _translating = false; // 「翻译为英文」LLM 在途(补全条切「翻译中」态)
  bool _sheetOpen = false; // 形态 B(分类竖向列表)弹层是否打开
  double _sheetH = 0; // 形态 B 弹层高度(正文底边让到它上沿,关着为 0)
  Tok? _panelTok; // 光标所在词条(显示词条栏)
  bool _cursorDragging = false; // 正在拖水滴手柄挪光标(吸底面板暂时收起)
  (int, int)? _multiRange; // 划词多选覆盖的词条区间 [first, last](批量面板)
  double _multiMult = 1.0; // 批量面板的统一数值权重读数
  List<String> _related = const []; // 当前词的关联标签(异步拉取)
  String? _relatedFor; // _related 归属的词名(防过期回调窜词)
  bool _relatedLoading = false; // 关联标签拉取中(词条栏「关联」显示转圈)
  Set<int> _chipSel = {}; // 芯片模式已选顶层单元下标

  /// 芯片模式的**落位阶段**:芯片从选择开关变成插入靶子(见 ChipFlowView.placing)。
  /// 选和放分成两个阶段,两类误触才不会互相干扰。
  bool _chipPlacing = false;
  double _chipMult = 1.0; // 芯片模式批量面板的统一数值权重读数
  String? _charName; // 编辑角色 / 分区时的名字(顶栏标题);主提示词会话为 null

  /// 滚动正文时收起顶栏与权重面板(见 [_onContentScroll])。补全条不收:
  /// 它只在打字时出现,而打字本身就会把这里放回来。
  bool _chromeHidden = false;
  final ChromeScrollTracker _chromeScroll = ChromeScrollTracker();

  /// 底栏展开钮拉出的收藏托盘是否展开。
  bool _trayOpen = false;

  /// 正文形态。设置即真相 —— 底栏那颗切换直接改设置,不另存一份局部状态,
  /// 免得「设置里是芯片、页面还停在文本」这种两头对不上的中间态。
  bool get _chipMode => _settings.chipMode;

  EditorNotifier get _notifier => ref.read(editorProvider.notifier);
  late final TagTranslationService _transSvc;

  /// 编辑中退后台:先冲刷编辑器回写,再让工作台立即落盘——
  /// 覆盖「切走后进程被杀」,不依赖防抖计时器有没有走完。
  AppLifecycleListener? _lifecycle;

  /// 编辑器行为开关(设置弹层里改,即时生效);载入前用默认值(全开)。
  EditorSettings get _settings =>
      ref.read(editorSettingsProvider).value ?? const EditorSettings();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (!mounted) return;
        if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
          _notifier.flushWriteBack();
          ref.read(appStoresProvider).flushNow();
        }
      },
    );
    _controller.addListener(_onCtrl);
    _focus.addListener(_onFieldFocus);
    // 占位符要从一开始就在:框子真空过一次,那一次的退格就收不到信号。
    _resetInput();
    // 增强模式的后端翻译通道:回填到货即刷新注音。
    _transSvc = ref.read(tagTranslationServiceProvider);
    _transSvc.addListener(_refreshAnnotations);
    // 编辑目标进页面即钉死。角色名只读一次:名字是 app 内部写的
    // (自动编号 / 导入带入),会话中不会变,不必挂 watch。
    final id = widget.charId;
    final sectionId = id == null ? widget.sectionId : null;
    final gen0 = ref.read(generateProvider);
    final char = gen0.characters.where((c) => c.id == id).firstOrNull;
    final section = gen0.sections.where((s) => s.id == sectionId).firstOrNull;
    // 分过区时主体也写上名字,和点别的分区进来一样
    _charName = id != null
        ? char?.name
        : sectionId != null
        ? section?.name
        : gen0.sections.where((s) => s.isMain).firstOrNull?.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final gen = ref.read(generateProvider);
      // 角色 / 分区会话即使没命中(已被删)也**不**退回主提示词:那正是
      // 这个页面从前的 bug——回写会静默盖掉用户的主提示词。
      // 载入原文草稿(带回禁用/折叠);草稿过期(提示词被编辑器之外改过)
      // 时 pickEditorText 自动退回定稿。
      final (String pos, String neg) = switch ((id, sectionId)) {
        (null, null) => (
          pickEditorText(gen.promptRaw, gen.prompt),
          pickEditorText(gen.negativePromptRaw, gen.negativePrompt),
        ),
        (null, _) => (
          pickEditorText(section?.positiveRaw ?? '', section?.positive ?? ''),
          pickEditorText(section?.negativeRaw ?? '', section?.negative ?? ''),
        ),
        _ => (
          pickEditorText(char?.positiveRaw ?? '', char?.positive ?? ''),
          pickEditorText(char?.negativeRaw ?? '', char?.negative ?? ''),
        ),
      };
      _notifier.load(
        positive: pos,
        negative: neg,
        startPositive: widget.positive,
        charId: id,
        sectionId: sectionId,
      );
      // **不抢焦点**:进页面就弹输入法,半屏被键盘吃掉,而多数人进来第一件事
      // 是看词条、点标签、调权重,不是打字。想输入点一下正文即可(TextField
      // 自己会拿焦点)。
    });
  }

  /// 离开编辑器时把输入法按下去。
  ///
  /// 只 unfocus 自己不够:出栈时 Navigator 会把焦点还给上一条路由的
  /// FocusScope,那边可能还记着某个输入框(LoRA 搜索…),
  /// 于是刚离开编辑器键盘又弹一次。所以当帧压一次、下一帧再压一次 ——
  /// 后者盖住「焦点还原发生在本帧之后」的情况。
  /// 下一帧那次只碰 FocusManager:本页可能已经 dispose,再动 _focus 会抛。
  void _dismissKeyboard() {
    if (_focus.hasFocus) _focus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _debounce?.cancel();
    _transSvc.removeListener(_refreshAnnotations);
    _focus.removeListener(_onFieldFocus);
    _tabAnim.dispose();
    _controller.dispose();
    _input.dispose();
    if (_focus.hasFocus) _focus.unfocus(); // 带着焦点被销毁,键盘会赖着不走
    if (_inputFocus.hasFocus) _inputFocus.unfocus();
    _focus.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 切 tab 的方向滑入:目标是正面(左 tab)从左进,负面(右 tab)从右进。
  void _kickTabSlide(bool toPositive) {
    setState(() {
      _tabSlide = _tabAnim.drive(
        Tween(
          begin: Offset(toPositive ? -.08 : .08, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Motion.emphasized)),
      );
    });
    _tabAnim.forward(from: 0);
  }

  /// 翻译数据到货(词库灌注完成/后端回填):重绘注音层与词条栏。
  /// 走 _muting 防经 _onCtrl 触发路由把正在看的补全清掉。
  ///
  /// 只在词条栏开着**且没在打字**时才重算:文本形态下这两者本就互斥,加这个
  /// 判断是给芯片形态用的 —— 那边「选中一枚 + 在尾部输入框打字」能同时成立,
  /// 不挡的话一批译文到货就会把正在看的补全列表抹掉。
  void _refreshAnnotations() {
    if (!mounted) return;
    _muting = true;
    _controller.refresh();
    _muting = false;
    if (_panelTok != null && _query.isEmpty) _reroute();
    // 补全条与收藏托盘的译文也是显示时现查(transOf)。结果快照没变,不重建
    // 就一直空着 —— 只重绘注音层不够,那是另一棵树。
    if (!_result.isEmpty || _trayOpen) setState(() {});
  }

  /// 把注音未命中的词喂给后端翻译通道(增强模式;离线模式 no-op)。
  ///
  /// [caret] = 打字/挪光标时的光标位置:落在哪枚词上,那枚这一轮先不喂 ——
  /// 它多半还没打完,打 from_side 会先后问出 from_s、from_si、from_sid,每个
  /// 都让服务端调一次模型,注音层还会闪出「来自si」这种半截译文。打了逗号、
  /// 光标挪走、失焦([_onFieldFocus])时会再喂一轮,它就补上了。
  /// 只是这一轮不往队里加,早已入队的照样问。
  void _feedTranslation(String text, {int? caret}) {
    final toks = parseToks(text);
    final held = caret == null ? -1 : tokIndexAt(text, caret, toks);
    _transSvc.request([
      for (var i = 0; i < toks.length; i++)
        if (i != held && toks[i].trans == null) toks[i].name,
    ]);
  }

  /// 正文里正在打字的光标位置;没焦点或划了选区时 null(那不是在打字)。
  int? get _typingCaret {
    if (!_focus.hasFocus) return null;
    final s = _controller.selection;
    return s.isValid && s.isCollapsed ? s.baseOffset : null;
  }

  /// 正文失焦:打字时扣下的那枚(见 [_feedTranslation])不再算「还在打」,补喂。
  void _onFieldFocus() {
    if (mounted && !_focus.hasFocus) _feedTranslation(_controller.text);
  }

  /// 补全结果里没译文的行,交给同一条后端翻译通道(共享库 → LLM → 回写)。
  ///
  /// D 站给的行只有 `/api/tags/wiki` 那一路中文名,wiki 没写中文别名的就空着 ——
  /// web 那边正是在这一步回头去取翻译,app 先前漏了整步。到货后
  /// [_refreshAnnotations] 重建补全条,[transOf] 现查即显示。
  ///
  /// 只喂标签与角色:画师串 / OC 是本地库实体,名字不是 Danbooru 标签。
  void _feedSuggestTranslation(SuggestResult res) {
    _transSvc.request([
      for (final s in res.flat)
        if (s.trans == null &&
            (s.kind == SuggestionKind.tag ||
                s.kind == SuggestionKind.character))
          s.text,
    ]);
  }

  void _save() => _notifier.flushWriteBack();

  bool _hasCjk(String s) => s.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);

  bool _rnInside(String text, int off) {
    if (off < 0 || off >= text.length) return false; // 行尾=添加位
    final c = text[off];
    return !(c == ',' || c == '，' || c == ' ' || c == '\t' || c == '\n');
  }

  // ---- provider → controller(切 tab / 撤销 / 载入时回灌)----
  void _syncFromProvider(EditorState next) {
    if (!mounted) return;
    if (next.activeText != _syncedText) {
      _muting = true;
      _controller.value = TextEditingValue(
        text: next.activeText,
        selection: TextSelection.collapsed(offset: next.activeText.length),
      );
      _syncedText = next.activeText;
      _prevText = next.activeText;
      _prevSel = _controller.selection;
      _muting = false;
      _setChromeHidden(false); // 撤销 / 切正负换了一整份正文,收着的放回来
      _reroute();
      _feedTranslation(next.activeText); // 载入/切 tab 的既有文本也问翻译
    }
  }

  /// 文本/光标变动后重算 dock。芯片模式没有光标可依,按「选中的是哪颗 chip」
  /// 重算 —— 两条路都收敛到 [_panelTok] 与关联标签这同一处状态。
  void _reroute() => _chipMode ? _syncChipCursor() : _routeCursor();

  void _onCtrl() {
    if (_muting) return;
    final prevSel = _prevSel;
    _prevSel = _controller.selection;
    final text = _controller.text;
    // 改字或挪光标 = 手回到了正文上:滚动时收起的顶栏与面板放回来。
    // 只比落点不比整个选区 —— 输入法会发只改 affinity 的选区更新,那不是手动的。
    // 拖手柄途中不放:顶栏一撑开正文就在手指底下平移(见 [_setCursorDragging]),
    // 松手那一下再放。
    if (!_cursorDragging &&
        (text != _prevText ||
            _prevSel.baseOffset != prevSel.baseOffset ||
            _prevSel.extentOffset != prevSel.extentOffset)) {
      _setChromeHidden(false);
    }
    if (text != _prevText) {
      if (_guardFoldEdit(text)) return; // 折叠被啃 → 改判为整只删,已自行落地
      _prevText = text;
      _syncedText = text;
      _notifier.editActive(text);
      _routeTyping(); // 打字一律走补全
      _feedTranslation(text, caret: _typingCaret);
    } else {
      // 光标挪了:打字时扣下的那枚若已不在光标下,这一喂就补上。
      // 只比落点 —— 输入法只改 composing 的那种通知不算挪。
      if (_prevSel.baseOffset != prevSel.baseOffset ||
          _prevSel.extentOffset != prevSel.extentOffset) {
        _feedTranslation(text, caret: _typingCaret);
      }
      // 双击/长按选词 → 扩到整枚词条;改完选区会再进一次监听走 _routeCursor
      if (_captureTagSelection(prevSel)) return;
      if (_snapCaretOutOfFold()) return;
      _routeCursor(); // 纯移光标 → 右邻判定
    }
  }

  // ---- 折叠在正文里的交互 ----
  // 正文里折叠只是占位符 `<#名字>`(折叠体在 EditorState.foldBodies 表里,
  // 不进 TextField)。一次性:单击标题热区即解散(占位符原地换成内容)。
  // 占位符是原子整体:光标不进内部、退格落在上面整只删——啃烂占位符会留下
  // 解析不出的残渣。多字删除是主动划选,不拦(删掉占位符 = 删掉折叠,合理)。

  Map<String, String> get _foldBodies => ref.read(editorProvider).foldBodies;

  /// 单击折叠标题:一次性解散,占位符原地替换为折叠体。
  void _unfoldByName(String name) {
    for (final r in parseFoldRefs(_controller.text, _foldBodies)) {
      if (r.name != name) continue;
      _applyText(unfoldRef(_controller.text, r, _foldBodies), r.start);
      // 展开的意图是「摊开看」,不是「查首个词」:光标落在展开内容的
      // 头一个词上,路由会把它的词条面板弹出来 —— 压掉。
      if (_panelTok != null) setState(() => _panelTok = null);
      Haptics.selection();
      return;
    }
  }

  /// 光标落进占位符内部 → 吸到最近的边缘。处理了返回 true。
  ///
  /// **必须 _muting 包住 selection 写入**:改 selection 会同步 notifyListeners →
  /// 重入本 _onCtrl。不 mute 虽不至死循环(吸附后 off 已在边缘不再匹配),但会
  /// 平白多走一轮路由;mute 后手动 _routeCursor 归位 dock,干净一次到位。
  bool _snapCaretOutOfFold() {
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    final off = sel.baseOffset;
    for (final r in parseFoldRefs(_controller.text, _foldBodies)) {
      if (off <= r.start || off >= r.end) continue;
      _muting = true;
      final to = (off - r.start) < (r.end - off) ? r.start : r.end;
      _prevSel = TextSelection.collapsed(offset: to);
      _controller.selection = _prevSel;
      _muting = false;
      _routeCursor();
      return true;
    }
    return false;
  }

  /// 单字删除若落在占位符上,改判为整只删除。删除点 d 用闭区间
  /// (`>= r.start`):退格删的是 d 左边那个字,d 落在 start 时删的正是
  /// `<`,该算命中。
  bool _guardFoldEdit(String next) {
    if (next.length != _prevText.length - 1) return false;
    final d = _controller.selection.baseOffset;
    if (d < 0) return false;
    for (final r in parseFoldRefs(_prevText, _foldBodies)) {
      if (d >= r.start && d < r.end) {
        final (out, cursor) = deleteFoldRef(_prevText, r);
        _applyText(out, cursor);
        Haptics.selection();
        return true;
      }
    }
    return false;
  }

  /// 双击/长按选词的 tag 捕获(web handleDoubleClick 同款):
  /// 从折叠光标一步变出的、落在单一词条内的子选区,扩成整枚词条
  /// (含权重语法,即 [segStart, segEnd))。已有选区上继续拖手柄
  /// (prev 已展开)不干预,用户仍可自由精调;Shift + 方向键逐字扩选也不干预。
  bool _captureTagSelection(TextSelection prev) {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    if (prev.isValid && !prev.isCollapsed) return false;
    if (ImeShiftSelect.extending) return false;
    final text = _controller.text;
    final toks = parseToks(text);
    final i = tokIndexAt(text, sel.start, toks);
    if (i < 0) return false;
    final t = toks[i];
    if (sel.end > t.segEnd) return false; // 跨词条(交给多选/自由选区)
    if (sel.start == t.segStart && sel.end == t.segEnd) return false; // 已整枚
    _prevSel = TextSelection(baseOffset: t.segStart, extentOffset: t.segEnd);
    _controller.selection = _prevSel;
    return true;
  }

  /// 打字:补全当前词,隐藏词条栏/批量面板
  void _routeTyping() {
    if (_panelTok != null || _multiRange != null) {
      setState(() {
        _panelTok = null;
        _multiRange = null;
      });
    }
    _scheduleQuery();
  }

  /// 移光标:点在词里(右邻是词正文,或多词标签名内部的空格)→词条栏;
  /// 逗号/词条间空隙/行尾→清空(那是添加位)。设置里关掉则恒不出。
  /// 选区盖住 ≥2 枚词条时 dock 换成批量面板(web multiSelectPanel 移植)。
  void _routeCursor() {
    _clearSuggest();
    final text = _controller.text;
    final sel = _controller.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final toks = parseToks(text);
      var first = -1, last = -1;
      for (var i = 0; i < toks.length; i++) {
        if (toks[i].segEnd > sel.start && toks[i].segStart < sel.end) {
          if (first < 0) first = i;
          last = i;
        }
      }
      if (first >= 0 && last > first) {
        setState(() {
          _panelTok = null;
          // 新进多选才重算起步读数;同一批里连点 ± 保持读数连贯
          if (_multiRange == null) {
            _multiMult = _sharedMult(toks, {
              for (var i = first; i <= last; i++) i,
            });
          }
          _multiRange = (first, last);
        });
        return;
      }
    }
    if (_multiRange != null) setState(() => _multiRange = null);
    final off = _controller.selection.baseOffset;
    Tok? tok;
    if (_settings.enableTagPanel) {
      final toks = parseToks(text);
      final i = tokIndexAt(text, off, toks);
      if (i >= 0 &&
          // 右邻是词正文,或落在多词标签名**内部**的空格上(long| hair)——
          // 都算点在词里;词条间空隙/逗号前仍是添加位,不出面板。
          (_rnInside(text, off) ||
              (off > toks[i].nameStart && off < toks[i].nameEnd))) {
        tok = toks[i];
      }
      // 折叠占位符不是词条:词条栏对它没有任何有意义的操作
      // (权重/禁用/删除该走整块语义),点标题解散才是它的交互。
      if (tok case final Tok hit) {
        for (final r in parseFoldRefs(text, _foldBodies)) {
          if (r.start == hit.segStart && r.end == hit.segEnd) {
            tok = null;
            break;
          }
        }
      }
    }
    _setPanelTok(tok);
  }

  /// 芯片模式的「路由」:选中恰好一枚散标签时把光标(不可见,但 _tokAtCursor
  /// 那一整套操作都读它)挪到该词名上,词条栏随之出这一枚;选中折叠段或多选
  /// 则不出词条栏,交给批量面板。
  ///
  /// 光标同步是这套复用的关键:词条栏的加权/禁用/删除/SD 转换全都从光标反查
  /// 词条,同步一次就全部原样可用,不必为芯片模式再写一份。
  void _syncChipCursor() {
    _clearSuggest();
    final text = _controller.text;
    final units = topLevelUnits(text, _foldBodies);
    // 文本被改短(删除/展开)后旧下标可能越界,先滤掉再谈选中了什么
    final live = {
      for (final i in _chipSel)
        if (i >= 0 && i < units.length) i,
    };
    if (live.length != _chipSel.length) setState(() => _chipSel = live);
    Tok? tok;
    if (live.length == 1) {
      final u = units[live.first];
      final at = u.isFold ? u.start : u.tok!.nameStart;
      if (_controller.selection.baseOffset != at) {
        _muting = true;
        _prevSel = TextSelection.collapsed(offset: at);
        _controller.selection = _prevSel;
        _muting = false;
      }
      if (!u.isFold && _settings.enableTagPanel) tok = u.tok;
    }
    _setPanelTok(tok);
  }

  /// 词条栏落位 + 关联标签拉取(光标路由与芯片路由共用出口)。
  void _setPanelTok(Tok? tok) {
    if (tok?.segStart != _panelTok?.segStart ||
        tok?.braceLevel != _panelTok?.braceLevel ||
        tok?.numMult != _panelTok?.numMult ||
        // 组里的词改的是组前缀:自身那几项纹丝不动,不比这几项读数就不刷新
        tok?.numWeight != _panelTok?.numWeight ||
        tok?.groupMult != _panelTok?.groupMult ||
        tok?.inGroup != _panelTok?.inGroup ||
        tok?.disabled != _panelTok?.disabled ||
        tok?.name != _panelTok?.name ||
        tok?.trans != _panelTok?.trans) {
      setState(() => _panelTok = tok);
    }
    // 关联标签异步拉取(走后端共现,拿不到用静态表);换词即重拉,
    // 引擎内有 per-tag 缓存,重复进同一词秒回。拉取期「关联」按钮转圈不置灰。
    final name = tok?.name;
    if (name != null && name != _relatedFor) {
      setState(() {
        _related = const [];
        _relatedFor = name;
        _relatedLoading = true;
      });
      ref.read(tagCompletionProvider).relatedOf(name).then((r) {
        if (!mounted || _relatedFor != name) return;
        setState(() {
          _related = r;
          _relatedLoading = false;
        });
      });
    } else if (name == null && _relatedLoading) {
      setState(() => _relatedLoading = false);
    }
  }

  void _scheduleQuery() {
    if (!_settings.enableCompletion) {
      _clearSuggest();
      return;
    }
    _debounce?.cancel();
    final word = _queryWord();
    final trigger = _hasCjk(word) ? word.isNotEmpty : word.length >= 2;
    if (!trigger) {
      _clearSuggest();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      // 注意:不能因 IME composing 有效就 return——手机软键盘(英文预测/中文拼音)
      // 打字期几乎全程维持 composing region,那样整段输入都不会触发补全。
      // 直接用当前词查询;setState 只更新补全面板,不动 controller,不干扰输入法。
      final gen = ++_queryGen;
      // 先进加载态:补全条立即显示「查询中」,不再空白干等
      setState(() {
        _query = word;
        _loading = true;
      });
      var res = await ref.read(tagCompletionProvider).query(word);
      // 实体建议关闭:只留标签行(引擎缓存不区分设置,出口过滤)
      if (!_settings.entitySuggest) res = SuggestResult(tags: res.tags);
      // 被后续输入/移光标取代,或光标已移出该词 → 丢弃这次结果
      if (!mounted || gen != _queryGen || _queryWord() != word) return;
      setState(() {
        _loading = false;
        _result = res;
      });
      _feedSuggestTranslation(res);
    });
  }

  /// 补全查询词的来源:芯片模式是尾部输入框的原文,文本模式是光标左侧那截。
  String _queryWord() => _chipMode ? _inputText.trim() : _currentWord();

  /// 补全查询词 = 光标**左侧**的名字部分。在两 tag 间插入时后一个 tag
  /// 会与新输入并成一个 token(`tag1, bl|tag2` → `bltag2`),只取左侧
  /// (`bl`)才不会把后面的英文混进查询、搜个空。
  String _currentWord() {
    final text = _controller.text;
    final off = _controller.selection.baseOffset;
    final toks = parseToks(text);
    final i = tokIndexAt(text, off, toks);
    if (i < 0) return '';
    final t = toks[i];
    final cut = off.clamp(t.nameStart, t.nameEnd);
    return text.substring(t.nameStart, cut);
  }

  void _clearSuggest() {
    _debounce?.cancel();
    _queryGen++; // 使在途异步补全作废
    if (_query.isEmpty && _result.isEmpty && !_loading) return;
    setState(() {
      _query = '';
      _result = const SuggestResult();
      _loading = false;
    });
  }

  /// 形态 A → B:收键盘,以底部弹层(真正的上滑/下滑物理)呈现分类竖向列表。
  /// 弹层内容用当前查询快照(键盘已收,列表冻结);行主体点按=选中并关闭,
  /// `+`=连续插入不关闭,抓手/底部/下滑=关闭。关闭后唤回键盘。
  Future<void> _expand() async {
    if (_sheetOpen || _query.isEmpty || _result.isEmpty) return;
    _sheetOpen = true;
    (_chipMode ? _inputFocus : _focus).unfocus();
    final size = MediaQuery.of(context).size;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (ctx) => Theme(
        data: editorTheme(ctx),
        child: _ReportHeight(
          onHeight: (h) {
            if (mounted && _sheetOpen) setState(() => _sheetH = h);
          },
          child: CompletionPanel(
            result: _result,
            maxHeight: size.height * 0.5,
            onPick: (s) {
              Navigator.of(ctx).pop();
              _pick(s);
            },
            onInsert: _chipMode
                ? (s) =>
                      _appendTag(_insertTextOf(s, plainSlot: true), quiet: true)
                : _insertAppend,
            onCollapse: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
    _sheetOpen = false;
    if (!mounted) return;
    setState(() => _sheetH = 0);
    (_chipMode ? _inputFocus : _focus).requestFocus(); // 关闭即回键盘
  }

  /// 编辑器设置弹层:开关即时生效(经 build 的 ref.listen 反映到当前会话)。
  Future<void> _openSettings() async {
    _focus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      // 内容超过默认 9/16 屏高上限,自控高度(弹层内部滚动,封顶见 _maxHeight)
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (ctx) =>
          Theme(data: editorTheme(ctx), child: const EditorSettingsSheet()),
    );
    if (mounted && !_chipMode) _focus.requestFocus();
  }

  /// 建议的落地文本。画师串 / OC 标签组这类**一次带进来一整组**的建议
  /// 自动折叠:内容注册进折叠表,正文只落占位符 `<#名字>`;单枚标签照常平铺。
  ///
  /// 两处不折:
  /// - 角色提示词(charId != null)—— 折叠只服务主提示词;
  /// - 落点不干净([plainSlot] = false,即被 `{}` / `N::` / `~` 包着)——
  ///   占位符要独占一段才是折叠单元,塞半截词里徒增乱子。
  String _insertTextOf(Suggestion s, {required bool plainSlot}) {
    final ins = s.insertText ?? s.text;
    if (widget.charId != null || !plainSlot) return ins;
    final body = ins.trim();
    if (parseToks(body).length < 2) return ins; // 单枚不折,折了徒增记号
    final name = _notifier.registerFold(s.text, body);
    return foldRefLiteral(name);
  }

  /// `+` 连续插入:把建议追加为当前词后的新标签,弹层保持打开、结果冻结。
  /// 走独立路径(不经 [_routeCursor]),避免清掉正在浏览的补全列表。
  void _insertAppend(Suggestion s) {
    final text = _controller.text;
    final t = _tokAtCursor();
    final at = (t?.segEnd ?? _controller.selection.baseOffset).clamp(
      0,
      text.length,
    );
    // 追加到词条之后,落点天然干净
    final ins = _insertTextOf(s, plainSlot: true);
    final newText = '${text.substring(0, at)}, $ins${text.substring(at)}';
    final cursor = at + 2 + ins.length;
    _muting = true;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _prevText = newText;
    _syncedText = newText;
    _prevSel = _controller.selection;
    _muting = false;
    _notifier.editActive(newText, structural: true);
    _feedTranslation(newText); // 同 _applyText:_muting 压掉了 _onCtrl,得自己喂
    Haptics.selection();
    // _query / _result 原样保留,弹层列表不跳
  }

  /// 程序化改文本(补全/权重/删除),同步撤销与路由。[extracted] 见
  /// [EditorNotifier.editActive]。
  void _applyText(
    String text,
    int cursor, {
    bool structural = true,
    PromptSection? extracted,
  }) {
    _muting = true;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
    );
    _prevText = text;
    _syncedText = text;
    _prevSel = _controller.selection;
    _muting = false;
    _notifier.editActive(text, structural: structural, extracted: extracted);
    // 打字走 _onCtrl 会喂翻译,这条路径 _muting 压掉了 _onCtrl,必须自己喂 ——
    // 否则**所有**程序化改文本(折叠展开/补全插入/多选批量)带进来的新词
    // 都问不到后端翻译,只能退出重进页面才补上(_syncFromProvider 那次)。
    // 折叠展开尤其明显:折叠体里的词此前只在旁路表里,正文从没见过它们。
    // request() 内部按「已问过/已有译文」去重,重复调很便宜。
    _feedTranslation(text);
    _reroute();
  }

  // ---- 补全:替换光标所在词的名字(保留其权重语法)----
  /// 若 [at] 之后(跳过空格)没有分隔(逗号/换行),补上 `, ` 并把光标放
  /// 其后——选中补全即可直接打下一枚(web formatAutocompleteTagInsertion
  /// 同款追加);已有分隔则原样、光标留在词末。设置里可关。
  (String, int) _withTrailingComma(String text, int at) {
    if (!_settings.autoComma) return (text, at);
    var k = at;
    while (k < text.length && (text[k] == ' ' || text[k] == '\t')) {
      k++;
    }
    final sep =
        k < text.length &&
        (text[k] == ',' || text[k] == '，' || text[k] == '\n');
    if (sep) return (text, at);
    return (text.replaceRange(at, at, ', '), at + 2);
  }

  void _pick(Suggestion s) {
    if (s.natural) {
      _pickNatural(s);
      return;
    }
    // 芯片模式没有光标可替换:选中的建议一律落在末尾(它本来就是尾部输入框
    // 打出来的),输入框清空接着打下一枚。
    if (_chipMode) {
      _resetInput();
      _appendTag(_insertTextOf(s, plainSlot: true));
      _inputFocus.requestFocus();
      return;
    }
    final text = _controller.text;
    final off = _controller.selection.baseOffset;
    final toks = parseToks(text);
    final i = tokIndexAt(text, off, toks);
    if (i < 0) {
      // 光标在逗号/空隙上:落点干净
      final ins = _insertTextOf(s, plainSlot: true);
      final replaced = text.replaceRange(off, off, ins);
      final (withComma, cursor) = _withTrailingComma(
        replaced,
        off + ins.length,
      );
      _applyText(withComma, cursor);
      _focus.requestFocus();
      return;
    }
    final t = toks[i];
    // 光标右侧的名字残余:两 tag 间插入时后一个 tag 被并入了当前 token,
    // 拆开成「ins, 后一tag」;否则(残余为空)= 常规整词替换 + 尾部补逗号。
    final cut = off.clamp(t.nameStart, t.nameEnd);
    final rightName = text.substring(cut, t.nameEnd).trimLeft();
    if (rightName.isEmpty) {
      // 整枚替换:被替换的词条本身没有权重/禁用语法时,落点才算干净
      final ins = _insertTextOf(
        s,
        plainSlot: t.segStart == t.nameStart && t.segEnd == t.nameEnd,
      );
      final newText = text.replaceRange(t.nameStart, t.nameEnd, ins);
      final end = t.segEnd + (ins.length - (t.nameEnd - t.nameStart));
      final (withComma, cursor) = _withTrailingComma(newText, end);
      _applyText(withComma, cursor);
    } else {
      // 拆分现有 token:落点夹在半截词里,不折
      final ins = _insertTextOf(s, plainSlot: false);
      final newText = text.replaceRange(
        t.nameStart,
        t.nameEnd,
        '$ins, $rightName',
      );
      // 光标落到「ins, 」之后、后一 tag 之前,便于继续插入
      _applyText(newText, t.nameStart + ins.length + 2);
    }
    _focus.requestFocus();
  }

  /// 「翻译为英文」行:异步把当前中文词整句翻成英文短句,替换之。
  /// LLM 要等几秒:等待期补全条切「翻译中」态;定位用点击时的快照,
  /// 等待中文本被改动则丢弃结果(落下去会毁掉新输入)。
  Future<void> _pickNatural(Suggestion s) async {
    if (_translating) return; // 在途,忽略重复点击
    final text = _controller.text;
    final off = _controller.selection.baseOffset;
    setState(() => _translating = true);
    final en = await ref.read(tagCompletionProvider).translateNatural(s.text);
    if (!mounted) return;
    setState(() => _translating = false);
    final ins = en?.trim() ?? '';
    if (ins.isEmpty) {
      hintSnack(context, '翻译失败,稍后再试', icon: Icons.error_outline);
      return;
    }
    if (_chipMode) {
      _resetInput();
      _appendTag(ins);
      _inputFocus.requestFocus();
      return;
    }
    if (_controller.text != text) return;
    // 文本没变,快照偏移仍有效;光标挪走也仍替换当初点击的那个词。
    final toks = parseToks(text);
    final i = tokIndexAt(text, off, toks);
    final (String replaced, int end) = i >= 0
        ? () {
            final t = toks[i];
            final newText = text.replaceRange(t.nameStart, t.nameEnd, ins);
            // 落到整段末(名字末可能在权重括号内,在那里补逗号会插进括号)
            return (newText, t.segEnd + ins.length - (t.nameEnd - t.nameStart));
          }()
        : (text.replaceRange(off, off, ins), off + ins.length);
    final (withComma, cursor) = _withTrailingComma(replaced, end);
    _applyText(withComma, cursor);
    _focus.requestFocus();
  }

  /// 底栏那颗形态切换。写进设置(下次进来还是这一头),本页的收尾由
  /// build 里那条设置监听统一做 —— 两个入口不各清各的。
  void _toggleChipMode() {
    Haptics.selection();
    final to = !_chipMode;
    ref
        .read(editorSettingsProvider.notifier)
        .patch((s) => s.copyWith(chipMode: to));
    // 切到文本形态时把键盘唤回来:那边光标就是入口,不给焦点等于点进来发现
    // 什么也打不了。切到芯片形态则**不**抢焦点,和进页面时同一套克制。
    //
    // 必须等下一帧:此刻 AnnotatedField 还没挂上树,_focus 是个游离节点,
    // 现在 requestFocus 落不到任何输入框上。
    if (!to) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _toggleTray() {
    Haptics.selection();
    setState(() => _trayOpen = !_trayOpen);
    // 收藏卡带译文:缺的交给后端翻译通道(离线模式 no-op)
    if (_trayOpen) _transSvc.request(ref.read(tagFavoritesProvider));
  }

  /// 托盘里点了一枚收藏:芯片模式接在末尾;文本模式落在光标处 —— 光标在词里
  /// 就接在这枚词后面,在空隙里就插在原地。
  void _insertFavorite(String tag) {
    Haptics.selection();
    if (_chipMode) {
      _appendTag(tag);
      return;
    }
    final text = _controller.text;
    final sel = _controller.selection;
    final off = sel.isValid ? sel.end : text.length;
    final toks = parseToks(text);
    final i = tokIndexAt(text, off, toks);
    final (next, cursor) = insertUnitAt(
      text,
      i >= 0 ? toks[i].segEnd : off,
      tag,
    );
    _applyText(next, cursor);
  }

  /// 形态切换后的收尾:清掉另一头才有意义的状态。设置载回(冷启动时持久化的
  /// chipMode 到货)也走这里,所以这里只做清理,不碰焦点。
  void _onModeChanged(bool chip) {
    _clearSuggest();
    if (chip) {
      _focus.unfocus();
    } else {
      _inputFocus.unfocus();
    }
    setState(() {
      _chipSel = {};
      _chipMult = 1.0;
      _panelTok = null;
      _multiRange = null;
      _chromeHidden = false;
      _resetInput();
    });
  }

  /// 换一批选中:重算起步读数(批量数值是**统一设定**不是相对加减,留着上
  /// 一批的读数会指着不相干的词),并把光标同步到新的单选目标上。
  ///
  /// **落位阶段不再被改选中踢掉** —— 进了落位还能接着加减要搬的东西,不必先退
  /// 出来重选。只有两种情况自动退出:选空了(没东西可搬)、或选到没有有效落点
  /// (比如全选了,搬到哪儿都还是原样),那时留在落位阶段只会是个点不动的空壳。
  void _setChipSel(Set<int> next, {bool enterPlacing = false}) {
    final units = topLevelUnits(_controller.text, _foldBodies).length;
    setState(() {
      _chipSel = next;
      _chromeHidden = false; // 点了芯片 = 要操作了,面板得在
      _chipPlacing =
          (enterPlacing || _chipPlacing) &&
          next.isNotEmpty &&
          chipValidGaps(next, units).isNotEmpty;
      _chipMult = _sharedMult(parseToks(_controller.text), next);
    });
    _syncChipCursor();
  }

  /// 长按芯片 = 一步进落位阶段,省掉「点选中 → 再点面板上的移动」两步。
  ///
  /// 长按的那颗不在选中里就只搬它自己;已经在选中里则整批一起搬(长按谁都一样,
  /// 那时用户显然是想把攒好的这批拿起来)。已经在落位里时长按不再有额外含义 ——
  /// 那时点一下就能加减,重置成单颗反而会把攒好的批次弄没。
  void _chipLongPress(int i) {
    if (_chipPlacing) return;
    final next = _chipSel.contains(i) ? {..._chipSel} : {i};
    final units = topLevelUnits(_controller.text, _foldBodies).length;
    if (chipValidGaps(next, units).isEmpty) return; // 没有落点就别进空阶段
    Haptics.medium(); // 拾起
    _setChipSel(next, enterPlacing: true);
  }

  // ---- 芯片模式的尾部输入框 ----

  /// 打字:逗号/换行即定稿(web commitInput 同款),其余交给补全。
  ///
  /// 开头先认一件事:占位符还在不在。它没了 = 用户在**空框**上按了退格
  /// (框里有字时退格删的是字,占位符在最前面轮不到它)——那一下转成
  /// 「删掉最后一枚标签」。见 [kChipInputPad]。
  void _onInputChanged(String raw) {
    _setChromeHidden(false);
    final body = chipInputBody(raw);
    final wasEmpty = _prevInputBody.isEmpty;
    _prevInputBody = body;
    if (!raw.startsWith(kChipInputPad)) {
      _setInputBody(body);
      // 之前本来就是空的才算退格。之前有字(全选删掉、整段替换)只是普通清空。
      if (body.isEmpty && wasEmpty) {
        _chipBackspace();
        return;
      }
      // 极少见:输入法整段替换把占位符一起带走了。补回去当普通输入继续。
    }
    final m = RegExp(r'[,，\n]').firstMatch(body);
    if (m != null) {
      final head = body.substring(0, m.start).trim();
      _setInputBody(body.substring(m.end));
      if (head.isNotEmpty) {
        _appendTag(head);
        return; // _appendTag 走 _applyText,补全已在那条路上清掉
      }
    }
    _scheduleQuery();
  }

  /// 写回输入框:占位符恒在最前,光标落在正文末尾。
  void _setInputBody(String body) {
    _prevInputBody = body;
    _input.value = TextEditingValue(
      text: '$kChipInputPad$body',
      selection: TextSelection.collapsed(
        offset: kChipInputPad.length + body.length,
      ),
    );
  }

  /// 空框上按退格 = 删掉最后一枚标签(有选中就删选中的那批)。
  ///
  /// 芯片流里没有光标,标签也不是输入框里的字符,退格不会自然地落到它们身上;
  /// 不接这一下,想清掉一串标签只能一枚枚点选再点删除。
  ///
  /// 连着按就连着删,一次一枚 —— 删过头有撤销兜底([_applyText] 每次都进撤销栈)。
  void _chipBackspace() {
    if (_chipSel.isNotEmpty) {
      _chipDelete();
      return;
    }
    final units = topLevelUnits(_controller.text, _foldBodies);
    if (units.isEmpty) return;
    final (text, cursor) = deleteUnits(_controller.text, _foldBodies, {
      units.length - 1,
    });
    _applyText(text, cursor);
  }

  /// 回车/「直接添加」:整条落成标签。
  void _commitInput() {
    final raw = _inputText.trim();
    if (raw.isEmpty) {
      _clearSuggest();
      return;
    }
    _resetInput();
    _appendTag(raw);
    _inputFocus.requestFocus();
  }

  /// 末尾追加一枚标签。[quiet] = 不重算 dock(补全弹层里连续插入时用:
  /// 列表得冻在原地,不能因为插了一枚就整块塌下去)。
  void _appendTag(String tag, {bool quiet = false}) {
    final next = appendUnit(_controller.text, tag);
    if (next == _controller.text) return;
    if (quiet) {
      _muting = true;
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _prevText = next;
      _syncedText = next;
      _prevSel = _controller.selection;
      _muting = false;
      _notifier.editActive(next, structural: true);
      _feedTranslation(next); // _muting 压掉了 _onCtrl,得自己喂
      Haptics.selection();
      return;
    }
    _applyText(next, next.length);
  }

  /// 一批词条的起步读数:全员同处一个权重组(如刚点过「选中整组」)时从组
  /// 倍率起步,调整才是在原权重基础上加减;各不相同或本无组 → 从 1 起。
  /// 两处多选共用,顶层单元与词条一一对应,下标可直接用。
  double _sharedMult(List<Tok> toks, Iterable<int> sel) {
    double? gm;
    for (final i in sel) {
      if (i < 0 || i >= toks.length) continue;
      final m = toks[i].groupMult;
      if (gm == null) {
        gm = m;
      } else if ((m - gm).abs() > 0.0001) {
        return 1.0;
      }
    }
    if (gm == null || (gm - 1).abs() <= 0.0001) return 1.0;
    return (gm * 100).roundToDouble() / 100;
  }

  /// 「选中整组」的落点:覆盖这批单元、且**还能带进新单元**的最外层权重组
  /// → (组区间, 该组盖住的全部单元)。只多包住几个记号字符不算 —— 那样点了
  /// 等于没点,按钮就不该出现。
  (WeightSpan, Set<int>)? _groupSelOf(List<TopUnit> units, Set<int> sel) {
    if (sel.isEmpty) return null;
    var a = -1, b = -1;
    for (final i in sel) {
      if (a < 0 || units[i].start < a) a = units[i].start;
      if (units[i].end > b) b = units[i].end;
    }
    final spans = <WeightSpan>[];
    parseToks(_controller.text, weightSpans: spans);
    (WeightSpan, Set<int>)? best;
    for (final s in spans) {
      if (s.start > a || s.end < b) continue;
      final covered = {
        for (var i = 0; i < units.length; i++)
          if (units[i].end > s.start && units[i].start < s.end) i,
      };
      if (covered.length <= sel.length) continue;
      if (best == null || s.end - s.start > best.$1.end - best.$1.start) {
        best = (s, covered);
      }
    }
    return best;
  }

  /// 复制所选:折叠摊平成成员(占位符出了这个 app 没意义),其余原文照搬,
  /// 权重/禁用记号一并带走,逗号拼接。
  void _copyUnits(Set<int> sel) {
    final text = _controller.text;
    final units = topLevelUnits(text, _foldBodies);
    final ordered = sel.where((i) => i >= 0 && i < units.length).toList()
      ..sort();
    final parts = [
      for (final i in ordered)
        if (units[i].isFold)
          _foldBodies[units[i].fold!.name] ?? ''
        else
          text.substring(units[i].start, units[i].end),
    ];
    final out = [
      for (final p in parts)
        if (p.trim().isNotEmpty) p.trim(),
    ].join(', ');
    if (out.isEmpty) return;
    Clipboard.setData(ClipboardData(text: out));
    hintSnack(context, '已复制 ${ordered.length} 项', icon: Icons.check);
  }

  /// 提取所选为新分区:所选从这一段拿掉,原样(权重、禁用、折叠都带着)放进
  /// 新建的一格,接在分区列表最后;在负面页提取的进那一格的负面。
  /// [remove] 按各自的多选方式删掉所选并清掉选中,返回删后的正文与光标。
  ///
  /// 先删后建:删不动(选区和折叠连在同一个组里,同「删除」会原样退回)就
  /// 不建格。这一步进撤销档时记着建出的那一格,撤回正文时一并拿掉。
  /// 整组选中时组权重跟着走,只取一部分不带(见 [extractUnitsDraft])。
  void _extractUnits(Set<int> sel, (String, int) Function() remove) {
    final text = _controller.text;
    final draft = expandFolds(
      extractUnitsDraft(text, _foldBodies, sel),
      _foldBodies,
    ).trim();
    if (draft.isEmpty) return;
    final (next, cursor) = remove();
    if (next == text) {
      hintSnack(context, '所选和折叠连在一起,没法提取');
      return;
    }
    final section = ref
        .read(generateProvider.notifier)
        .addSectionFrom(
          draft,
          positive: ref.read(editorProvider).activePositive,
        );
    _applyText(next, cursor, extracted: section);
    _save(); // 当场回写:别让这几枚在原处和新分区里同时存着
    hintSnack(context, '已提取到「${section.name}」', icon: Icons.check);
  }

  void _chipExtract() => _extractUnits(_chipSel, () {
    final out = deleteUnits(_controller.text, _foldBodies, _chipSel);
    _setChipSel({});
    return out;
  });

  void _multiExtract() {
    final r = _multiRange;
    if (r == null) return;
    _extractUnits(_rangeSel(r), () {
      final out = batchDelete(_controller.text, r.$1, r.$2);
      setState(() => _multiRange = null);
      return out;
    });
  }

  /// 多选移动落地:所选顶层单元整批搬到间隙 [to]。折叠占位符作为一整块
  /// 移动;保留分隔/换行排版。搬完清空选中(这一批已经放到位了)。
  void _moveUnits(int to) {
    final next = moveUnits(_controller.text, _foldBodies, _chipSel, to);
    _setChipSel({}); // 顺带退出落位阶段
    _applyText(next, _controller.selection.baseOffset.clamp(0, next.length));
  }

  /// 批量禁用/启用的目标态:所选里**第一枚散标签**的反态,全体向它对齐
  /// (web 同款语义);全是折叠 → null,没得禁用。两处多选共用。
  bool? _disableTarget(List<TopUnit> units, Iterable<int> sel) {
    final ordered = sel.toList()..sort();
    for (final i in ordered) {
      if (i < 0 || i >= units.length) continue;
      if (units[i].tok case final t?) return !t.disabled;
    }
    return null;
  }

  // ---- 芯片模式的单元操作(chip 点选;选中保留以便接着操作)----
  // 与划词多选走同一套单元级操作,差别只在选中集可以跳选 —— 权重按连续段
  // 分段落地(batchWrapUnits 等),没选中的词不会被卷进同一层括号。

  /// 改完文本刷新面板:chip 流挂着 controller 会自己重画,dock 上的面板读的
  /// 是正文算出来的能力位(可加权/可禁用/有启用项),得跟着重建一次。
  void _applyChip(String next) {
    _applyText(next, _controller.selection.baseOffset);
    if (mounted) setState(() {});
  }

  void _chipWrap(bool up) {
    if (_chipSel.isEmpty) return;
    _applyChip(batchWrapUnits(_controller.text, _foldBodies, _chipSel, up: up));
  }

  void _chipStepMult(bool up) {
    if (_chipSel.isEmpty) return;
    final step = _settings.weightStep;
    final next =
        ((_chipMult + (up ? step : -step)) * 100).roundToDouble() / 100;
    _chipMult = next;
    _applyChip(
      batchSetMultUnits(_controller.text, _foldBodies, _chipSel, next),
    );
  }

  void _chipClearWeight() {
    if (_chipSel.isEmpty) return;
    _chipMult = 1.0;
    _applyChip(batchClearWeightUnits(_controller.text, _foldBodies, _chipSel));
  }

  void _chipToggleDisabled() {
    final units = topLevelUnits(_controller.text, _foldBodies);
    final target = _disableTarget(units, _chipSel);
    if (target == null) return; // 全是折叠,没得禁用
    _applyChip(
      setUnitsDisabled(_controller.text, _foldBodies, _chipSel, target),
    );
  }

  void _chipDelete() {
    final (text, cursor) = deleteUnits(_controller.text, _foldBodies, _chipSel);
    _setChipSel({});
    _applyText(text, cursor);
  }

  /// 芯片模式的改名:落在**当前选中**那一枚上(光标已同步过去)。
  void _chipRename(String name) {
    final t = _tokAtCursor();
    if (t == null) return;
    final next = renameTok(_controller.text, t, name);
    if (next == _controller.text) return;
    _applyChip(next);
  }

  /// 芯片模式的「选中整组」:把组盖住的单元全收进选中(文本模式那版改的是
  /// 选区,这边没有选区可改)。
  void _chipSelectGroup(Set<int> covered) => _setChipSel(covered);

  /// 芯片模式解散折叠:选中的那一枚折叠段原地摊成成员。
  void _chipUnfold() {
    final units = topLevelUnits(_controller.text, _foldBodies);
    if (_chipSel.length != 1) return;
    final i = _chipSel.first;
    if (i < 0 || i >= units.length || !units[i].isFold) return;
    _setChipSel({});
    _unfoldByName(units[i].fold!.name);
  }

  // ---- 划词多选批量操作(dock 批量面板;逐词应用,应用后保持选区)----

  /// 批量改文本落地:重新覆盖同一批词条(数量不变的操作),面板保持。
  void _applyBatchKeep(String newText) {
    final r = _multiRange;
    if (r == null) return;
    final toks = parseToks(newText);
    if (toks.isEmpty) return;
    final last = r.$2 < toks.length ? r.$2 : toks.length - 1;
    final first = r.$1 <= last ? r.$1 : last;
    _muting = true;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: toks[first].segStart,
        extentOffset: toks[last].segEnd,
      ),
    );
    _prevText = newText;
    _syncedText = newText;
    _prevSel = _controller.selection;
    _muting = false;
    _notifier.editActive(newText, structural: true);
    // 批量操作只改权重/禁用,理论上不带进新名字;仍统一喂一次,让「压了
    // _onCtrl 的路径都自己喂翻译」成为无例外的规矩,免得日后新增批量项踩坑。
    _feedTranslation(newText);
    Haptics.selection();
    setState(() => _multiRange = (first, last));
  }

  /// 选区区间 → 顶层单元下标集:单元与词条一一对应(一个逗号段一枚),
  /// 两处多选下标同一个空间,批量操作因此能共用同一套函数。
  Set<int> _rangeSel((int, int) r) => {for (var i = r.$1; i <= r.$2; i++) i};

  void _multiWrap(bool up) {
    final r = _multiRange;
    if (r == null) return;
    _applyBatchKeep(
      batchWrapUnits(_controller.text, _foldBodies, _rangeSel(r), up: up),
    );
  }

  void _multiStepMult(bool up) {
    final r = _multiRange;
    if (r == null) return;
    final step = _settings.weightStep;
    final next =
        ((_multiMult + (up ? step : -step)) * 100).roundToDouble() / 100;
    _multiMult = next;
    _applyBatchKeep(
      batchSetMultUnits(_controller.text, _foldBodies, _rangeSel(r), next),
    );
  }

  void _multiClear() {
    final r = _multiRange;
    if (r == null) return;
    _multiMult = 1.0;
    _applyBatchKeep(
      batchClearWeightUnits(_controller.text, _foldBodies, _rangeSel(r)),
    );
  }

  /// 划词批量的「选中整组」:选区扩到整个权重组,经选区监听重进面板。
  /// 先清 `_multiRange` —— 路由只在「新进多选」时重算起步读数,不清的话扩完
  /// 读数还停在上一批,而调组权重得从组倍率起步才对得上。
  void _multiSelectGroup(WeightSpan g, Set<int> _) {
    setState(() => _multiRange = null);
    _controller.selection = TextSelection(
      baseOffset: g.start,
      extentOffset: g.end,
    );
  }

  /// 批量禁用/启用:与多选模式同一条语义(第一枚散标签定目标,折叠跳过)。
  /// 从前按词条区间套 `~`,选区扫过折叠占位符时会把折叠拆散。
  void _multiToggleDisabled() {
    final r = _multiRange;
    if (r == null) return;
    final sel = _rangeSel(r);
    final units = topLevelUnits(_controller.text, _foldBodies);
    final target = _disableTarget(units, sel);
    if (target == null) return;
    _applyBatchKeep(
      setUnitsDisabled(_controller.text, _foldBodies, sel, target),
    );
  }

  void _multiDelete() {
    final r = _multiRange;
    if (r == null) return;
    final (text, cursor) = batchDelete(_controller.text, r.$1, r.$2);
    setState(() => _multiRange = null);
    _applyText(text, cursor);
  }

  /// 「选中整组」:把选区扩到包住当前词条的最外层权重组,
  /// 经选区监听自然进入批量面板(≥2 成员时)。
  void _selectGroupOf(Tok tok) {
    final spans = <WeightSpan>[];
    parseToks(_controller.text, weightSpans: spans);
    WeightSpan? best;
    for (final s in spans) {
      if (s.start > tok.segStart || s.end < tok.segEnd) continue;
      // 恰好等于自身 seg 的是词条自己的权重区间,不算组
      if (s.start == tok.segStart && s.end == tok.segEnd) continue;
      if (best == null || s.end - s.start > best.end - best.start) best = s;
    }
    if (best == null) return;
    _controller.selection = TextSelection(
      baseOffset: best.start,
      extentOffset: best.end,
    );
  }

  /// 关闭批量面板:选区折叠到末端(触发重路由,回到单词条/空 dock)。
  void _multiClose() {
    final sel = _controller.selection;
    setState(() => _multiRange = null);
    if (sel.isValid && !sel.isCollapsed) {
      _controller.selection = TextSelection.collapsed(offset: sel.end);
    }
  }

  // ---- 词条栏操作(都改文本)----
  Tok? _tokAtCursor() {
    final text = _controller.text;
    final toks = parseToks(text);
    final i = tokIndexAt(text, _controller.selection.baseOffset, toks);
    return i >= 0 ? toks[i] : null;
  }

  void _wrap(bool up) {
    final t = _tokAtCursor();
    if (t == null) return;
    _applyText(wrapBracket(_controller.text, t, up: up), t.coreStart + 1);
  }

  void _setMult(double m) {
    final t = _tokAtCursor();
    if (t == null) return;
    final (text, cursor) = setTokMult(_controller.text, t, m);
    // 拖动/连点合并入撤销栈,不逐步刷屏
    _applyText(text, cursor, structural: false);
  }

  void _clearWeight() {
    final t = _tokAtCursor();
    if (t == null) return;
    final (text, cursor) = clearWeight(_controller.text, t);
    _applyText(text, cursor);
  }

  /// 关联标签:插到当前词之后,光标留在原词条上(面板不跳)
  void _addRelated(String tag) {
    final text = _controller.text;
    final t = _tokAtCursor();
    final at = t?.segEnd ?? text.length;
    final newText = '${text.substring(0, at)}, $tag${text.substring(at)}';
    _applyText(newText, t?.segStart ?? (at + 2 + tag.length), structural: true);
  }

  void _toggleDisabled() {
    final t = _tokAtCursor();
    if (t == null) return;
    _applyText(toggleTokDisabled(_controller.text, t), t.segStart);
  }

  void _deleteCurrent() {
    final t = _tokAtCursor();
    if (t == null) return;
    final (text, cursor) = deleteTok(_controller.text, t);
    _applyText(text, cursor);
    // 删除即与这枚词条的交互终结。光标落点恰是右邻词条开头,路由会把
    // 面板顺延到下一枚 —— 按过删除的手指还悬在原地,极易误触,压掉。
    if (_panelTok != null) setState(() => _panelTok = null);
    _focus.requestFocus();
  }

  /// SD 权重语法转 NAI(web convertSDToNAI):`(tag:1.2)` → `1.2::tag::`。
  /// 光标留在词首,词条栏随即刷新出转换后的权重。
  void _convertSd() {
    final t = _tokAtCursor();
    if (t == null) return;
    final seg = _controller.text.substring(t.segStart, t.segEnd);
    final ins = sdToNaiSeg(seg);
    if (ins == seg) return;
    _applyText(
      _controller.text.replaceRange(t.segStart, t.segEnd, ins),
      t.segStart,
    );
  }

  /// 拖手柄挪光标期间把吸底面板淡掉:词条栏正好压在手指下方那一片,挡着
  /// 看不见落点;而且光标每跨过一枚词它就换一副内容,一路闪。松手再淡回来 ——
  /// 那时才知道最终停在哪枚词上。
  ///
  /// **只淡不摘**:把它从布局里摘掉会让正文可视区当场长高一截,滚动位置被
  /// 夹回同样的量,整片正文在手指底下平移 —— 而框架起拖那一刻记下的
  /// 「手指 → 文字」偏移是**固定的**,平移之后就一直错着，越往上拖越够不着,
  /// 到顶只剩原地弹。
  void _setCursorDragging(bool v) {
    if (_cursorDragging == v) return;
    setState(() {
      _cursorDragging = v;
      // 松手 = 光标落定,该看这枚词的面板了:滚动时收起的一并放回来
      if (!v) _chromeHidden = false;
    });
  }

  /// 关闭词条栏(下次移光标进词内会再出现)
  void _closePanel() {
    if (_panelTok == null) return;
    setState(() => _panelTok = null);
  }

  // ---- 滚动收起顶栏与权重面板 ----

  void _setChromeHidden(bool v) {
    if (_chromeHidden == v) return;
    setState(() => _chromeHidden = v);
  }

  /// 正文滚动 → 收起 / 放出顶栏与权重面板,判定见 [ChromeScrollTracker]。
  bool _onContentScroll(ScrollNotification n) {
    // 拖光标手柄时框架会自己贴边滚正文,这时一动顶栏,正文就在手指底下平移;
    // 松手时 [_setCursorDragging] 统一放出
    if (_cursorDragging) return false;
    final v = _chromeScroll.update(n, hidden: _chromeHidden);
    if (v != null) _setChromeHidden(v);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EditorState>(editorProvider, (prev, next) {
      if (prev != null && prev.activePositive != next.activePositive) {
        _kickTabSlide(next.activePositive);
      }
      _syncFromProvider(next);
    });
    // 设置改动即时反映到当前会话:关补全清建议、切词条栏重路由、切注音重绘。
    ref.listen<EditorSettings>(
      editorSettingsProvider.select((a) => a.value ?? const EditorSettings()),
      (prev, next) {
        final p = prev ?? const EditorSettings();
        if (p == next) return;
        if (p.enableCompletion && !next.enableCompletion) _clearSuggest();
        // 形态切换(底栏那颗,或冷启动时持久化的 chipMode 到货)的统一收尾
        if (p.chipMode != next.chipMode) _onModeChanged(next.chipMode);
        if (p.enableTagPanel != next.enableTagPanel) _reroute();
        if (p.showTranslation != next.showTranslation) {
          _controller.showTrans = next.showTranslation;
          _refreshAnnotations();
        }
        // 实体建议切换:正在显示的补全就地重查(结果有缓存,秒回)
        if (p.entitySuggest != next.entitySuggest && _query.isNotEmpty) {
          _scheduleQuery();
        }
      },
    );
    final settings =
        ref.watch(editorSettingsProvider).value ?? const EditorSettings();
    _controller.showTrans = settings.showTranslation;
    // 折叠表灌进控制器(着色/热区/药丸判占位符用);registerFold/load 改表
    // 即触发本 build 重灌 + 重绘。
    final foldBodies = ref.watch(editorProvider.select((s) => s.foldBodies));
    _controller.foldBodies = foldBodies;
    // 权重面板(词条栏 / 批量面板)一弹出,顶栏就让位;补全条不算。
    // 拖光标期间 dock 是冻住的那份,顶栏跟着不动,松手再定。
    final dock = _dock();
    final weightDock = dock is TagPanel || dock is BatchPanel;

    // 两种正文形态。切正/负时编辑区随方向轻滑 + 淡入
    // (单实例,不复制 TextField——controller/focus 不能同时挂两棵树)
    final content = NotificationListener<ScrollNotification>(
      onNotification: _onContentScroll,
      child: settings.chipMode
          ? ChipFlowView(
              controller: _controller,
              foldBodies: foldBodies,
              selection: _chipSel,
              onSelectionChanged: _setChipSel,
              onLongPressChip: _chipLongPress,
              onMove: _moveUnits,
              input: _input,
              inputFocus: _inputFocus,
              onInputChanged: _onInputChanged,
              onInputSubmitted: (_) => _commitInput(),
              placing: _chipPlacing,
              translating: _transSvc.isPending,
              showTrans: settings.showTranslation,
              fontSize: settings.chipFontSize,
            )
          : ClipRect(
              child: SlideTransition(
                position: _tabSlide,
                child: FadeTransition(
                  opacity: _tabAnim.drive(Tween(begin: .25, end: 1.0)),
                  child: AnnotatedField(
                    controller: _controller,
                    focusNode: _focus,
                    scrollController: _scroll,
                    showTrans: settings.showTranslation,
                    showWeightWash: settings.showWeightWash,
                    fontSize: settings.fontSize,
                    onCursorDrag: _setCursorDragging,
                    onFoldTap: _unfoldByName,
                    hint: '点击输入标签,可输入中文自动触发翻译与联想',
                  ),
                ),
              ),
            ),
    );

    // 滚动收起:贴顶对齐 + 裁切,往下沉进底栏后面。补全条不收。
    final dockSlot = ClipRect(
      child: AnimatedAlign(
        duration: Motion.fast,
        curve: Motion.standard,
        alignment: Alignment.topCenter,
        heightFactor: _chromeHidden && _query.isEmpty ? 0 : 1,
        // 拖光标期间只是**淡出**,位置照占:见 [_setCursorDragging]。
        child: AnimatedOpacity(
          duration: Motion.quick,
          curve: Motion.standard,
          opacity: _cursorDragging ? 0 : 1,
          child: IgnorePointer(
            ignoring: _cursorDragging,
            child:
                // dock 入场:淡入 + 轻微上滑(高度瞬时占位,不撑盒子,避免橡皮筋)
                // 离场(关面板/收补全)比入场快:走了就别在路上磨蹭。
                AnimatedSwitcher(
                  duration: Motion.fast,
                  reverseDuration: Motion.quick,
                  switchInCurve: Motion.emphasized,
                  switchOutCurve: Motion.standard,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: dock,
                ),
          ),
        ),
      ),
    );

    return Theme(
      data: editorTheme(context),
      child: Builder(
        builder: (context) => PopScope(
          // 托盘展开着时返回键先收托盘;芯片模式选中着东西时先退选(形态本身
          // 是常驻偏好,不该被返回键改掉)。收完再按一次才离开编辑器
          canPop:
              !_trayOpen &&
              !(settings.chipMode && (_chipSel.isNotEmpty || _chipPlacing)),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              _save();
              _dismissKeyboard(); // 系统返回手势也走这里,不能只挂在返回按钮上
            } else if (_trayOpen) {
              setState(() => _trayOpen = false);
            } else if (_chipPlacing) {
              // 先退落位阶段,选中留着 —— 用户多半只是想改一下选哪几枚
              setState(() => _chipPlacing = false);
            } else if (_chipSel.isNotEmpty) {
              _setChipSel({});
            }
          },
          child: Scaffold(
            // 键盘避让由 [_BodyLayout] 自己做:要和补全展开层一起取高者
            resizeToAvoidBottomInset: false,
            // 底边安全区由底栏自己垫,底栏的底色才能铺到屏幕底
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // 滚动正文时、或权重面板在时整栏收起:贴底对齐 + 裁切,
                  // 读起来是往上滑走。见 [_onContentScroll]。
                  ClipRect(
                    child: AnimatedAlign(
                      duration: Motion.fast,
                      curve: Motion.standard,
                      alignment: Alignment.bottomCenter,
                      heightFactor: _chromeHidden || weightDock ? 0 : 1,
                      child: EditorTopBar(
                        charName: _charName,
                        character: widget.charId != null,
                        sectionId: widget.charId == null
                            ? widget.sectionId
                            : null,
                        onBack: () {
                          // 先收键盘再出栈:让退场动画一开始就是完整半屏,
                          // 不是「键盘收一半、页面滑一半」两段各走各的
                          _dismissKeyboard();
                          Navigator.of(context).maybePop();
                        },
                        onSettings: _openSettings,
                      ),
                    ),
                  ),
                  Expanded(
                    // 键盘、补全展开层从底下顶上来时怎么让位,见 [_BodyLayout]
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _sheetH),
                      duration: Motion.fast,
                      curve: Motion.standard,
                      builder: (context, sheet, _) => CustomMultiChildLayout(
                        delegate: _BodyLayout(
                          keyboard: MediaQuery.viewInsetsOf(context).bottom,
                          sheet: sheet,
                        ),
                        children: [
                          LayoutId(id: _BodySlot.content, child: content),
                          LayoutId(
                            id: _BodySlot.bottom,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                dockSlot,
                                EditorBottomBar(
                                  onToggleMode: _toggleChipMode,
                                  chipMode: settings.chipMode,
                                  trayOpen: _trayOpen,
                                  onToggleTray: _toggleTray,
                                  onInsertFavorite: _insertFavorite,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 批量面板(两处多选共用):选中集 → 能力位 → 面板。越界下标(正文刚被
  /// 改短)先滤掉,面板只反映当前正文。
  Widget _batchPanel(
    Key key,
    Set<int> sel,
    double mult, {
    required void Function(WeightSpan g, Set<int> covered) onSelectGroup,
    required void Function(bool up) onWrap,
    required void Function(bool up) onStepMult,
    required VoidCallback onClearWeight,
    required VoidCallback onToggleDisabled,
    required VoidCallback onDelete,
    required VoidCallback onClose,
    required VoidCallback onExtract,
    VoidCallback? onUnfold,
  }) {
    final units = topLevelUnits(_controller.text, _foldBodies);
    final live = {
      for (final i in sel)
        if (i >= 0 && i < units.length) i,
    };
    var canDisable = false;
    var anyEnabled = false;
    for (final i in live) {
      if (units[i].tok case final t?) {
        // 折叠单元不能禁用(套 ~ 会把折叠拆散),全是折叠时这个键就该灰着
        canDisable = true;
        if (!t.disabled) anyEnabled = true;
      }
    }
    // 「展开」只在恰好选中一枚折叠段时给:多选里混着折叠,展开谁都说不清
    final fold = live.length == 1 && units[live.first].isFold
        ? units[live.first].fold!
        : null;
    final group = _groupSelOf(units, live);
    return BatchPanel(
      key: key,
      count: live.length,
      mult: mult,
      canWeight: weightRuns(units, live).isNotEmpty,
      canDisable: canDisable,
      anyEnabled: anyEnabled,
      groupMult: group?.$1.mult,
      onSelectGroup: group == null
          ? null
          : () => onSelectGroup(group.$1, group.$2),
      onUnfold: fold == null ? null : onUnfold,
      foldCount: fold == null
          ? 0
          : parseToks(_foldBodies[fold.name] ?? '').length,
      onCopy: () => _copyUnits(live),
      // 分区只属于主提示词:角色会话不给
      onExtract: widget.charId == null ? onExtract : null,
      onWrap: onWrap,
      onStepMult: onStepMult,
      onClearWeight: onClearWeight,
      onToggleDisabled: onToggleDisabled,
      onDelete: onDelete,
      onClose: onClose,
      placing: _chipPlacing,
      // 只有芯片模式有芯片可点;没有有效落点时(比如全选中了,搬到哪儿都
      // 还是原样)这条路给 null,按钮不出现,免得点进去一个空阶段。
      onTogglePlacing: _chipMode && chipValidGaps(live, units.length).isNotEmpty
          ? () => setState(() => _chipPlacing = !_chipPlacing)
          : null,
    );
  }

  /// 上一次(非拖动态)算出来的 dock。拖动期间原样端出去 —— 见 [_dock]。
  Widget _lastDock = const SizedBox.shrink(key: ValueKey('dock-empty'));

  /// 拖光标期间**冻住**:面板自己换形态(词条栏 ↔ 批量面板 ↔ 无)会改高度,
  /// 一样会把正文顶得平移。外层只把它淡掉,位置照占。
  Widget _dock() => _cursorDragging ? _lastDock : (_lastDock = _buildDock());

  Widget _buildDock() {
    // key 稳定=同一形态内更新不重播入场动画(如长按连续调权重);切形态才动画
    //
    // 芯片模式与划词多选共用同一张批量面板:前者点 chip 攒集合(可跳选),
    // 后者扫出连续区间 —— 到了面板都只是「选中了哪些顶层单元」。
    if (_chipMode) {
      // 选中恰好一枚散标签 → 走下面完整的词条栏(光标已同步到那一枚,
      // 单词条那套操作原样可用);其余情况(多选/折叠)才是批量面板。
      // 正在打字时补全优先:选中还留着,但手上这一秒的意图是输入。
      if (_query.isEmpty && _chipSel.isNotEmpty && _panelTok == null) {
        return _batchPanel(
          const ValueKey('dock-chip'),
          _chipSel,
          _chipMult,
          // 扩到整组:组盖住的单元全部收进选中(读数随之落到组倍率)
          onSelectGroup: (_, covered) => _chipSelectGroup(covered),
          onWrap: _chipWrap,
          onStepMult: _chipStepMult,
          onClearWeight: _chipClearWeight,
          onToggleDisabled: _chipToggleDisabled,
          onDelete: _chipDelete,
          onClose: () => _setChipSel({}),
          onExtract: _chipExtract,
          onUnfold: _chipUnfold,
        );
      }
    } else if (_multiRange != null) {
      final r = _multiRange!;
      if (r.$1 < parseToks(_controller.text).length) {
        return _batchPanel(
          const ValueKey('dock-multi'),
          _rangeSel(r),
          _multiMult,
          onSelectGroup: _multiSelectGroup,
          onWrap: _multiWrap,
          onStepMult: _multiStepMult,
          onClearWeight: _multiClear,
          onToggleDisabled: _multiToggleDisabled,
          onDelete: _multiDelete,
          onClose: _multiClose,
          onExtract: _multiExtract,
        );
      }
    }
    if (_query.isNotEmpty) {
      return CompletionBar(
        key: const ValueKey('dock-completion'),
        query: _query,
        result: _result,
        loading: _loading,
        translating: _translating,
        onPick: _pick,
        // 一个都没匹配上时的「直接添加」:文本模式里字已经在正文里了,
        // 收起补全即可;芯片模式还躺在输入框里,得落成一枚 chip。
        onAddRaw: _chipMode ? _commitInput : _clearSuggest,
        onExpand: _expand,
        onClose: _clearSuggest,
      );
    }
    if (_panelTok != null) {
      final tok = _panelTok!;
      return TagPanel(
        key: const ValueKey('dock-tag'),
        tok: tok,
        count: countOf(tok.name),
        related: tok.name == _relatedFor ? _related : const [],
        relatedLoading: tok.name == _relatedFor && _relatedLoading,
        weightStep: _settings.weightStep,
        compact: _settings.compactTagPanel,
        sdConvert:
            isSdWeightSeg(_controller.text.substring(tok.segStart, tok.segEnd))
            ? _convertSd
            : null,
        // 加权/禁用/关联这些都从光标反查词条,芯片模式已把光标同步到选中
        // 那一枚,原样复用;只有「扩到整组」「删除」「关闭」的落点不同 ——
        // 那边要动的是选中集,不是选区。
        onSelectGroup: !tok.inGroup
            ? null
            : _chipMode
            ? () {
                final units = topLevelUnits(_controller.text, _foldBodies);
                final g = _groupSelOf(units, _chipSel);
                if (g != null) _chipSelectGroup(g.$2);
              }
            : () => _selectGroupOf(tok),
        onWrap: _wrap,
        onSetMult: _setMult,
        onClear: _clearWeight,
        onToggleDisabled: _toggleDisabled,
        onDelete: _chipMode ? _chipDelete : _deleteCurrent,
        onAddRelated: _addRelated,
        onRename: _chipMode ? _chipRename : null,
        onClose: _chipMode ? () => _setChipSel({}) : _closePanel,
        favorited: ref
            .watch(tagFavoriteKeysProvider)
            .contains(metaKey(tok.name)),
        onToggleFavorite: () =>
            ref.read(tagFavoritesProvider.notifier).toggle(tok.name),
      );
    }
    return const SizedBox.shrink(key: ValueKey('dock-empty'));
  }
}

enum _BodySlot { content, bottom }

/// 正文 + 吸底那摞(dock、底栏)。
///
/// 键盘:整摞抬到键盘上沿,正文让出键盘 + 整摞。补全展开层是浮层,吸底那摞
/// 本来就压在它后面,不跟着抬;只有正文底边要让到它上沿。两者取高者 ——
/// 正文视口变矮时光标那行由 [KeepInViewTracker] 拉回视野。
class _BodyLayout extends MultiChildLayoutDelegate {
  _BodyLayout({required this.keyboard, required this.sheet});

  final double keyboard;
  final double sheet;

  @override
  void performLayout(Size size) {
    final w = size.width;
    final bottom = layoutChild(
      _BodySlot.bottom,
      BoxConstraints(minWidth: w, maxWidth: w, maxHeight: size.height),
    ).height;
    final floor = math.max(keyboard + bottom, sheet);
    layoutChild(
      _BodySlot.content,
      BoxConstraints.tightFor(
        width: w,
        height: math.max(0.0, size.height - floor),
      ),
    );
    positionChild(_BodySlot.content, Offset.zero);
    positionChild(_BodySlot.bottom, Offset(0, size.height - keyboard - bottom));
  }

  @override
  bool shouldRelayout(_BodyLayout old) =>
      old.keyboard != keyboard || old.sheet != sheet;
}

/// 量出子树高度报给页面。布局期不能 setState,挪到帧后。
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}

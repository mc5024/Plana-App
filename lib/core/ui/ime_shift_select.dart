/// 输入法「选择」模式下的方向键扩选。
///
/// 百度等输入法进入选择态后,每按一下方向键发的是 Shift 按下 → 方向键 → Shift 抬起,
/// 其中 Shift 按下那条的 metaState 不带 Shift 位。引擎按 metaState 同步修饰键,紧接着
/// 合成一条 Shift 抬起把它抹掉;方向键自带的 Shift 位因为来自虚拟键盘又不认。框架最后
/// 只收到单独的方向键:光标挪了,选区没扩。
///
/// 认的就是这个特征:一次真实的 Shift 按下,紧跟同一时间戳的合成抬起(实体键盘的 Shift
/// 自带 metaState,不会这样)。之后那一下方向键 / Home / End 换成对应的 Shift 组合键
/// 意图,发给当前焦点。挂在 MaterialApp.builder 上,所有输入框都管。
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ImeShiftSelect extends StatefulWidget {
  const ImeShiftSelect({super.key, required this.child});

  final Widget child;

  /// 当前这次选区变化是 Shift + 方向键扩出来的:实体键盘按着 Shift,或正由这里代发。
  static bool get extending =>
      _invoking || HardwareKeyboard.instance.isShiftPressed;

  static bool _invoking = false;

  @override
  State<ImeShiftSelect> createState() => _ImeShiftSelectState();
}

class _ImeShiftSelectState extends State<ImeShiftSelect> {
  /// 与 DefaultTextEditingShortcuts 安卓表里带 Shift 的那几条一致。
  static final _extend = <LogicalKeyboardKey, Intent>{
    LogicalKeyboardKey.arrowLeft: const ExtendSelectionByCharacterIntent(
      forward: false,
      collapseSelection: false,
    ),
    LogicalKeyboardKey.arrowRight: const ExtendSelectionByCharacterIntent(
      forward: true,
      collapseSelection: false,
    ),
    LogicalKeyboardKey.arrowUp:
        const ExtendSelectionVerticallyToAdjacentLineIntent(
          forward: false,
          collapseSelection: false,
        ),
    LogicalKeyboardKey.arrowDown:
        const ExtendSelectionVerticallyToAdjacentLineIntent(
          forward: true,
          collapseSelection: false,
        ),
    LogicalKeyboardKey.home: const ExtendSelectionToLineBreakIntent(
      forward: false,
      collapseSelection: false,
      continuesAtWrap: true,
    ),
    LogicalKeyboardKey.end: const ExtendSelectionToLineBreakIntent(
      forward: true,
      collapseSelection: false,
      continuesAtWrap: true,
    ),
  };

  /// 刚收到、还没见到合成抬起的那次 Shift 按下。
  KeyDownEvent? _press;

  /// Shift 被引擎抹掉了:接下来这一下方向键按 Shift 组合键处理,抬起即止。
  bool _held = false;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      final press = _press;
      _held =
          press != null &&
          e is KeyUpEvent &&
          e.synthesized &&
          key == press.logicalKey &&
          e.timeStamp == press.timeStamp;
      _press = e is KeyDownEvent && !e.synthesized ? e : null;
      return KeyEventResult.ignored;
    }
    _press = null;
    final intent = _held ? _extend[key] : null;
    if (intent == null || e is KeyUpEvent) {
      _held = false;
      return KeyEventResult.ignored;
    }
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return KeyEventResult.ignored;
    final action = Actions.maybeFind<Intent>(ctx, intent: intent);
    if (action == null) return KeyEventResult.ignored;
    ImeShiftSelect._invoking = true;
    try {
      final (enabled, result) = Actions.of(
        ctx,
      ).invokeActionIfEnabled(action, intent, ctx);
      return enabled
          ? action.toKeyEventResult(intent, result)
          : KeyEventResult.ignored;
    } finally {
      ImeShiftSelect._invoking = false;
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}

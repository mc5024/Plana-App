/// AI 助手页(底部第 3 个 tab)。
///
/// 一轮的样子:用户气泡 → 资料轨迹(查了什么,见 [ToolTrail])→ AI 气泡,
/// **真给了画面的**气泡底部压一条结果条(tag 数 + 增删读数 + 「展开」,见
/// [ResultStrip])。等待期 20~40 秒,靠轨迹逐条落下来撑住,不用干转圈。
///
/// **处置按钮只给最后一份提议**,和结果条包在同一个气泡里;更早的那些明细和按钮
/// 都在弹层里。
///
/// **AI 不会自己改创作页。** 它给的是一份提议;用户点「导入」才写,或者干脆不导入、
/// 直接拿它出图。底部导航「创作」上那颗角标只在真导入过之后亮。
///
/// **AI 也不会自己读创作页。** 输入框上面那颗「引用创作页」按下去,这一条才把创作页的
/// 提示词带过去;发完即清。两个方向都要用户按一下,是同一条规矩。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../../core/util/image_pick.dart';
import '../generate/generate_state.dart' show generateProvider;
import '../generate/widgets/common.dart'
    show confirmDialog, dropFocusSoon, hintSnack;
import '../shell/shell_state.dart';
import 'agent_model.dart';
import 'assistant_mode.dart';
import 'assistant_models.dart';
import 'assistant_settings.dart';
import 'assistant_state.dart';
import 'preset_rules.dart' show RulesFamily, rulesFamilyOf;
import 'widgets/history_sheet.dart';
import 'widgets/inline_images.dart';
import 'widgets/intro_dialog.dart';
import 'widgets/mode_sheet.dart';
import 'widgets/model_sheet.dart';
import 'widgets/proposal_actions.dart';
import 'widgets/reply_body.dart';
import 'widgets/result_strip.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/think_sheet.dart';
import 'widgets/tool_trail.dart';

/// 对话列表里「正在跑」那一条的 key。消息 id 是时间戳拼的,撞不上。
const _kLiveKey = '__live';

/// 开场白。`canvas` = 这句话离了创作页那串词就没意义,点它等于顺手替用户勾上
/// 「引用创作页」;创作页是空的时候这类开场白整条不出(点了也只能得到一句「你还没写」)。
const _suggests = <({String text, bool canvas})>[
  (text: '画一个白发红瞳的猫娘,站在樱花树下', canvas: false),
  (text: '帮我抽一个好看的画风', canvas: false),
  (text: '随机画一个蔚蓝档案的角色', canvas: false),
  (text: '看看我现在这串 tag 有什么问题', canvas: true),
];

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage>
    with AutomaticKeepAliveClientMixin {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  PickedImage? _pending;

  /// 这一条要不要把创作页的提示词带上。**纯一次性:每发一次回到关**,和带图一样。
  ///
  /// 没有「总是引用」那档设置,是刻意的。常驻开关是个藏起来的模式,过两轮就想
  /// 不起自己开着,然后对着结果纳闷「它怎么又照着我的旧词改」;更麻烦的是它会
  /// 和自动导入咬起来 —— 自动写进去的词下一轮又被自动读回来当基底,用户改的和
  /// AI 改的分不清谁覆盖谁。每轮现按一次,AI 看见的就是你此刻想给它看的。
  bool _withCanvas = false;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 切 tab 时保住输入框、待发的图和对话滚动位置。
  @override
  bool get wantKeepAlive => true;

  /// 回到底部。列表是**倒着**的(见 [_list]),所以底 = offset 0,一个常数 ——
  /// 不必去问 `maxScrollExtent`(懒加载列表那个值是估的,本来就够不着真底)。
  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: Motion.fast, curve: Motion.standard);
  }

  /// [canvas] 给开场白用:那几句自带「要不要引用创作页」的答案,不必先让用户
  /// 去按一下按钮。其余情况一律看用户勾没勾。
  ///
  /// 正在跑时发的排进队里;输入框空着按发送 = 接着发排着的(停下 / 出错之后)。
  Future<void> _send({String? preset, bool? canvas}) async {
    final n = ref.read(assistantProvider.notifier);
    final text = preset ?? _input.text;
    if (text.trim().isEmpty && _pending == null) {
      _toBottom();
      await n.resumeQueue();
      return;
    }
    final img = _pending;
    final withCanvas = canvas ?? _withCanvas;
    final queued = ref.read(assistantProvider).running;
    _input.clear();
    setState(() {
      _pending = null;
      _withCanvas = false; // 一次性:发完就回到关
    });
    // 排队时留着键盘,接着写下一句
    if (!queued) _inputFocus.unfocus();
    _toBottom();
    await n.submit(text, image: img?.bytes, withCanvas: withCanvas);
    _toBottom();
  }

  Future<void> _pick() async {
    final img = await pickImageFile(context);
    if (img != null && mounted) setState(() => _pending = img);
  }

  /// 「新对话」。**不弹回执** —— 这个动作本来就没有后果:上一段原样躺在
  /// 「历史会话」里,顶栏那颗按钮点开就能找回来。为它挡一条顶部提示,
  /// 等于每开一次新对话都要看一句废话。
  void _newChat() => ref.read(assistantProvider.notifier).archiveCurrent();

  /// 首次引导正开着:别在它关掉之前又弹一个。
  bool _introOpen = false;

  /// 第一次进 AI 页:先确认资料库范围和使用习惯([showAssistantIntro])。
  /// 只在 AI 页真在前台时弹 —— 页面是保活的,停在别的 tab 时也可能重建。
  void _maybeShowIntro() {
    if (_introOpen) return;
    final s = ref.watch(assistantSettingsProvider).value;
    if (s == null || s.introDone) return;
    if (ref.watch(shellIndexProvider) != kTabAssistant) return;
    _introOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await showAssistantIntro(context);
      _introOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = context.scheme;
    final st = ref.watch(assistantProvider);
    // 没有 Bot 授权也能用,但只能走免费模型或自定义接口:两样都没有就先挡住
    final usable =
        ref.watch(assistantBackendAvailableProvider) ||
        ref.watch(assistantEndpointProvider) != null;
    final supported = assistantSupportsModel(
      ref.watch(generateProvider.select((g) => g.params.model)),
    );
    _maybeShowIntro();

    return Column(
      children: [
        _topBar(scheme, st),
        Expanded(
          // 空对话 ↔ 对话列表 ↔ 两种门禁之间淡入淡出,不硬切
          child: AnimatedSwitcher(
            duration: Motion.medium,
            child: !supported
                ? const _ModelGate(key: ValueKey('model-gate'))
                : !usable
                ? const _Gate(key: ValueKey('gate'))
                : st.isEmpty && !st.running && st.queue.isEmpty
                ? KeyedSubtree(
                    key: const ValueKey('empty'),
                    child: _empty(scheme),
                  )
                : KeyedSubtree(key: const ValueKey('list'), child: _list(st)),
          ),
        ),
        if (supported && usable) _inputBar(scheme, st),
      ],
    );
  }

  /// 标题整块可点 = 换模型。
  ///
  /// 模型名摆在标题下面而不是收进设置页:同一句话换个渠道结果差得很远,用户得
  /// **随时看得见**现在是谁在答,不然「今天怎么变笨了」永远查不出来。显示的是
  /// 完整型号名(`GLM 5.3 Flash`),不是「GLM」—— 简称看不出换没换代。
  Widget _topBar(ColorScheme scheme, AssistantState st) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
    child: Row(
      children: [
        Icon(Icons.auto_awesome, size: 21, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => showModelSheet(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AI 助手',
                        style: context.texts.titleLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const _BetaBadge(),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          // 列表还没到货就先不报名字 —— 报错的名字比不报更糟。
                          ref.watch(assistantModelProvider)?.name ?? '选择模型',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelMedium!.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.expand_more,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '助手设置',
          onPressed: () => showAssistantSettings(context),
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: '历史会话',
          onPressed: () => showHistorySheet(context),
          icon: const Icon(Icons.history),
        ),
        IconButton(
          tooltip: '新对话',
          onPressed: st.isEmpty ? null : _newChat,
          icon: const Icon(Icons.edit_square),
        ),
      ],
    ),
  );

  /// 空对话:不写产品介绍,四句能点的开场铺在输入框上方,第一句就是最常用的诉求。
  Widget _empty(ColorScheme scheme) => Align(
    alignment: Alignment.bottomCenter,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              '想画什么,直接说',
              style: context.texts.titleSmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final s in _suggests)
            if (!s.canvas || canvasHasContent(ref.watch(generateProvider)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Lifted(
                  radius: BorderRadius.circular(12),
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _send(preset: s.text, canvas: s.canvas),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Text(s.text, style: context.texts.bodyMedium),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  /// 消息列表**倒序渲染**(`reverse: true`)。
  ///
  /// 这是「新内容自动贴底」唯一靠得住的做法:倒过来之后底部就是 offset 0,
  /// 新消息插在 index 0、软键盘顶上来把视口压矮、译文到货把气泡撑高 —— 全都
  /// 不改变 offset 0 的含义,视图自己就贴在最新那条上,一行滚动代码都不用写。
  ///
  /// 之前是正序 + 「变了就 animateTo(maxScrollExtent)」,两头都不灵:
  ///   · 懒加载列表的 `maxScrollExtent` 是**估**出来的,滚过去也到不了真底;
  ///   · 只在 `msgs.length` 变时滚,而工具轨迹逐条落下、结果卡译文到货都只改
  ///     高度不改条数,列表照样越长越出屏幕;
  ///   · 软键盘把视口压矮压根不经过任何一处回调。
  ///
  /// 顺带修好了「往回翻历史时被新消息拽回去」——倒序列表在用户滚上去之后,
  /// 新消息插在下面不动他的位置。
  Widget _list(AssistantState st) {
    // 只有**最后一份提议**的气泡里带处置按钮;更早的按钮在弹层里。
    // 「最后一份」不等于「最后一条消息」—— 中间夹几轮纯聊天很常见,那时候
    // 还没处置的仍是上面那份,把它的按钮收起来等于把用户正要按的东西藏了。
    // 显示成纯文本的那种(纯文本格式)不算 —— 它没有可处置的按钮,算上它反而把前面那份
    // 还能导入的按钮收起来了。
    String? liveId;
    for (var i = st.msgs.length - 1; i >= 0; i--) {
      if (st.msgs[i].draw != null && !st.msgs[i].promptAsText) {
        liveId = st.msgs[i].id;
        break;
      }
    }
    final running = st.running;
    final queue = st.queue;
    final nq = queue.length;
    final live = running ? 1 : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final fontSize =
        ref.watch(assistantSettingsProvider.select((s) => s.value?.fontSize)) ??
        AssistantSettings.fontSizeDefault;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      itemCount: nq + live + st.msgs.length,
      // 按 key 找回每条的位置。新消息插在最下面(下标 0),不给 key 的话旧元素会按下标
      // 错配到新消息上 —— 状态串门,进场动画也分不清谁是新来的。
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        if (key.value == _kLiveKey) return running ? nq : null;
        final qi = queue.indexWhere((q) => q.id == key.value);
        if (qi >= 0) return nq - 1 - qi;
        final at = st.msgs.indexWhere((m) => m.id == key.value);
        return at < 0 ? null : st.msgs.length - 1 - at + nq + live;
      },
      itemBuilder: (context, i) {
        // 倒序:i=0 是最下面那条。排着的几句在最下面,队首挨着正在跑的那一轮;
        // 发出去时那条消息沿用队里的 id,气泡原地转正
        if (i < nq) {
          final q = queue[nq - 1 - i];
          return _Enter(
            key: ValueKey(q.id),
            animate: now - q.at < 1500,
            grow: true,
            child: _MsgTile(
              msg: AssistantMsg(
                id: q.id,
                role: MsgRole.user,
                text: q.text.trim(),
                at: q.at,
                withCanvas: q.withCanvas,
              ),
              queued: true,
              queuedImage: q.image,
              fontSize: fontSize,
              onLongPress: () => _queuedMenu(q),
            ),
          );
        }
        if (running && i == nq) {
          return _Enter(
            key: const ValueKey(_kLiveKey),
            animate: true,
            grow: true,
            child: _LiveTurn(state: st, fontSize: fontSize),
          );
        }
        final at = st.msgs.length - 1 - (i - nq - live);
        final m = st.msgs[at];
        // 报错上直接给「重试」:只给最后一条、而且紧跟在提问后面的那种。
        // 发之前就被拦下的(比如没选模型接口)前面不是提问,重试只会把上一轮的话再发一遍。
        final ask = at > 0 ? st.msgs[at - 1] : null;
        final retryable =
            m.role == MsgRole.error &&
            !running &&
            at == st.msgs.length - 1 &&
            ask?.role == MsgRole.user;
        // 刚顶替掉等待气泡的那条回复:把状态行原样接过来再收走(见 _Handoff)。
        // 窗口取得短,是因为往上翻再翻回来时不该再演一遍。
        final handoff =
            m.role == MsgRole.ai &&
                !running &&
                now - m.at < 500 &&
                ask?.role == MsgRole.user
            ? ((m.at - ask!.at) ~/ 1000).clamp(0, 9999)
            : null;
        return _Enter(
          key: ValueKey(m.id),
          // 刚发出、刚回来的才播。按消息时间判:打开历史会话时那些消息都是旧的,
          // 不会一进来整屏一起动;往上翻再翻回来早过了这个窗口,也不重播。
          // 接了状态行的那条不播 —— 它本来就该稳稳停在等待气泡原来的位置。
          animate: now - m.at < 1500 && handoff == null,
          // AI 回复和报错是顶替「正在跑」那条出现的,再从 0 长高一遍会先塌后涨
          grow: m.role == MsgRole.user,
          child: _MsgTile(
            msg: m,
            prev: m.draw == null ? null : prevProposal(st.msgs, m.id),
            live: m.id == liveId,
            fontSize: fontSize,
            onLongPress: () => _menu(m),
            onRetry: retryable ? () => _retryFrom(ask!.id) : null,
            handoffSecs: handoff,
          ),
        );
      },
    );
  }

  /// 长按菜单。原生能力红利:长按是一等公民,不做「先选中再点按钮」那套。
  ///
  ///   用户的话:复制内容 / 编辑该消息 / 从这里重新生成
  ///   AI 回复:复制内容 / 重新生成(重发它回的那一句)
  Future<void> _menu(AssistantMsg m) async {
    if (m.role == MsgRole.error) return;
    Haptics.medium();
    final n = ref.read(assistantProvider.notifier);
    final isUser = m.role == MsgRole.user;
    // 跑着的时候不能截断对话:回复会接在截断后的位置上
    final idle = !ref.read(assistantProvider).running;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制内容'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (isUser && idle)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑该消息'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (idle)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(isUser ? '从这里重新生成' : '重新生成'),
                onTap: () => Navigator.pop(context, 'retry'),
              ),
          ],
        ),
      ),
    );
    // 长按之前输入框有过焦点的话,弹层一关 Flutter 会把焦点还给它、把键盘顶出来 ——
    // 用户只是来点个菜单。只有「编辑」是真要打字,那一条下面自己要焦点。
    if (action != 'edit') dropFocusSoon();
    if (action == null || !mounted) return;
    final ask = isUser ? m : n.askOf(m.id);
    switch (action) {
      case 'copy':
        await copyText(context, m.text);
      case 'edit':
        if (!await _confirmDropLater(m)) {
          dropFocusSoon(); // 不改了:同样别让焦点还回输入框
          return;
        }
        final t = n.truncateFrom(m.id);
        if (t == null) return;
        _input.text = t;
        _input.selection = TextSelection.collapsed(offset: t.length);
        // 长按的那条多半在上面,改完要发的地方在最下面
        _toBottom();
        // 放到下一帧再要焦点:菜单关掉的这一帧里,InputFocusGuard 会把「又回到输入框」
        // 的焦点放掉,当帧要的会被它一起放掉
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocus.requestFocus();
        });
      case 'retry':
        if (ask == null || !await _confirmDropLater(ask)) return;
        await _retryFrom(ask.id);
    }
  }

  /// 排着的那句长按:复制 / 拿回输入框改 / 取消发送。
  Future<void> _queuedMenu(QueuedAsk q) async {
    Haptics.medium();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制内容'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑该消息'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消发送'),
              onTap: () => Navigator.pop(context, 'cancel'),
            ),
          ],
        ),
      ),
    );
    if (action != 'edit') dropFocusSoon();
    if (action == null || !mounted) return;
    final n = ref.read(assistantProvider.notifier);
    // 菜单开着的时候可能已经轮到它发出去了
    final still = ref.read(assistantProvider).queue.any((e) => e.id == q.id);
    switch (action) {
      case 'copy':
        await copyText(context, q.text);
      case 'cancel' when still:
        n.unqueue(q.id);
      case 'edit' when still:
        n.unqueue(q.id);
        // 输入框里正写着的接在后面,不覆盖
        final draft = _input.text;
        final t = draft.trim().isEmpty ? q.text : '${q.text}\n$draft';
        _input.text = t;
        _input.selection = TextSelection.collapsed(offset: t.length);
        setState(() {
          if (_pending == null && q.image != null) {
            _pending = PickedImage('image', q.image!);
          }
          if (q.withCanvas) _withCanvas = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocus.requestFocus();
        });
    }
  }

  /// 从某一句提问重来。和 [_send] 一样先回到底部:重来的那一轮出在最下面,
  /// 而长按菜单多半是停在上面某条消息上点的。
  Future<void> _retryFrom(String askId) async {
    _toBottom();
    await ref.read(assistantProvider.notifier).retryFrom(askId);
    _toBottom();
  }

  /// 从 [ask] 这一句重来之前:后面还有别的轮就先问一句,那几轮会一起丢掉。
  /// 就是最后一轮时不问 —— 丢的只是它自己那条回复,重来本来就是要换掉它。
  Future<bool> _confirmDropLater(AssistantMsg ask) async {
    if (!ref.read(assistantProvider.notifier).hasLaterAsks(ask.id)) return true;
    if (!mounted) return false;
    return confirmDialog(
      context,
      title: '丢掉之后的对话?',
      message: '这条之后的对话都会丢掉,已经写进创作页的改动不受影响。',
      confirmLabel: '丢掉',
    );
  }

  /// 输入框上方那排快捷选项:引用创作页(只管这一条)、模式、思考等级。
  ///
  /// 单独占一行而不是塞进输入框左边那排图标里:芯片带文字,开没开一眼能读出来;
  /// 图标只能靠颜色表示状态,而这排里的东西按错了是要花钱或者改画布的。
  /// 横向可滚,以后再加选项直接往后排,不会把输入框挤窄。
  Widget _optionRow(bool hasCanvas) {
    // 能开哪几个模式跟着这个模型在用的预设走。还没取到时先不拦 —— 发的时候会再核一遍
    final family = rulesFamilyOf(
      agentImageModel(
        ref.watch(generateProvider.select((g) => g.params.model)),
      ),
    );
    final supported = ref.watch(assistantModesProvider(family)).value;
    bool usable(AssistantMode m) => supported == null || supported.contains(m);
    final picked = ref.watch(assistantProvider.select((s) => s.mode));
    // 选着的模式这份预设没写(比如 NAI5 的对话里选了漫画,又换成了 4.5):
    // 显示成「无」,发出去也什么都不加;换回来还是漫画
    final shown = usable(picked) ? picked : AssistantMode.normal;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 读画布是**一次性**的:按一次只管这一条,发完就掉(见 [_withCanvas])。
            //
            // 所以它是一枚**附件芯片**而不是开关:按上去多一件东西、带个 ✕ 能摘掉,
            // 和上面那张待发的图是同一种东西。开关那版(FilterChip 的选中态)读起来
            // 像个常驻模式,而它偏偏发一次就没了 —— 样式和行为对不上,用户只会
            // 以为自己关掉过。
            InputChip(
              selected: _withCanvas,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              // 这一排的芯片都不撑到 48 的点按区:撑的话芯片上下各多出一截透明的边,
              // 输入框上面平白空出一大条
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(
                _withCanvas ? Icons.draw : Icons.draw_outlined,
                size: 16,
                color: context.chipIcon(_withCanvas),
              ),
              deleteIconColor: context.chipIcon(_withCanvas),
              // 附上之后改叫「创作页」:带没带已经由填色和 ✕ 说清了,
              // 再留着动词反而像还没按。
              //
              // 两态都不报「23 个 tag · 2 个角色」—— 那串数字读一遍才知道说的是
              // 什么,而这枚芯片要回答的只有「这条带不带」;想确认内容切过去看。
              label: Text(_withCanvas ? '创作页' : '引用创作页'),
              onDeleted: _withCanvas
                  ? () => setState(() => _withCanvas = false)
                  : null,
              // 画布空着时**不置灰**:灰按钮按下去没反应,用户只会以为坏了。
              // 照常可点,点了说一句为什么。
              onPressed: () {
                if (_withCanvas) {
                  setState(() => _withCanvas = false);
                  return;
                }
                if (!hasCanvas) {
                  hintSnack(
                    context,
                    '创作页还没写提示词,没东西可引用',
                    icon: Icons.draw_outlined,
                  );
                  return;
                }
                setState(() => _withCanvas = true);
              },
            ),
            const SizedBox(width: 8),
            _modeChip(family, shown: shown, usable: usable),
            // 思考等级只对自定义接口有意义:后端渠道的推理档位由服务端按渠道
            // 定死,app 没有可下发的字段。摆一颗按了不生效的芯片比不摆更糟。
            if (ref.watch(assistantEndpointProvider) != null) ...[
              const SizedBox(width: 8),
              _thinkChip(),
            ],
          ],
        ),
      ),
    );
  }

  /// 模式:一个按钮,点开一张弹层选无 / 漫画模式 / 仅自然语言([showModeSheet])。
  ///
  /// 和「引用创作页」不同,它**不是一次性的**,跟着对话一直开着(见 assistant_mode.dart),
  /// 所以用开关的样式,和「思考」那颗一样把当前模式写在字面上。
  ///
  /// **一直摆着,不看在用的预设支不支持** —— 换个模型按钮就没了,反而让人找不着。
  /// 预设没写的模式照常列在弹层里,选了说一句为什么,和画布空着时的「引用创作页」
  /// 一个道理。
  Widget _modeChip(
    RulesFamily family, {
    required AssistantMode shown,
    required bool Function(AssistantMode) usable,
  }) {
    final on = shown != AssistantMode.normal;
    return FilterChip(
      // 「无」不算开着:那一档什么都不加
      selected: on,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        // 关着用 layers,别用 tune —— 顶栏「助手设置」已经是 tune 了
        on ? assistantModeIcon(shown, on: true) : Icons.layers_outlined,
        size: 16,
        color: context.chipIcon(on),
      ),
      // 开着就只写模式名;关着写「模式」,「模式 无」读着别扭
      label: Text(on ? assistantModeLabel(shown) : '模式'),
      onSelected: (_) => _pickMode(family, shown, usable),
    );
  }

  Future<void> _pickMode(
    RulesFamily family,
    AssistantMode shown,
    bool Function(AssistantMode) usable,
  ) async {
    final picked = await showModeSheet(context, current: shown);
    if (picked == null || !mounted) return;
    if (!usable(picked)) {
      // 手上那份默认规则可能是旧的:后端改了预设、重启过,app 还拿着之前取的那份。
      // 说「不支持」之前先向服务端要一份最新的,真没有才说
      final latest = await refreshAssistantModes(ref, family);
      if (!mounted) return;
      if (!latest.contains(picked)) {
        hintSnack(
          context,
          '当前规则预设不支持「${assistantModeLabel(picked)}」',
          icon: assistantModeIcon(picked),
        );
        return;
      }
    }
    // 和存着的比,不和显示的比:显示成「无」可能只是这份预设没写那个模式,
    // 用户这时选「无」是真想换回来
    if (picked == ref.read(assistantProvider).mode) return;
    Haptics.selection();
    ref.read(assistantProvider.notifier).setMode(picked);
  }

  /// 思考等级。点开是一张带滑杆的弹层([showThinkSheet])—— 六档是一条有序的轴,
  /// 循环点击要按五下才回得来,菜单又会让它看起来像六个并列选项。
  Widget _thinkChip() {
    final level =
        ref.watch(assistantSettingsProvider).value?.thinkLevel ??
        ThinkLevel.auto;
    final on = level != ThinkLevel.auto;
    return FilterChip(
      // 「自动」不算开着:那一档压根不发字段
      selected: on,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        level == ThinkLevel.off ? Icons.lightbulb_outline : Icons.lightbulb,
        size: 16,
        color: context.chipIcon(on),
      ),
      label: Text('思考 ${thinkLevelLabel(level)}'),
      onSelected: (_) => showThinkSheet(context),
    );
  }

  Widget _inputBar(ColorScheme scheme, AssistantState st) {
    final running = st.running;
    final hasDraft = _input.text.trim().isNotEmpty || _pending != null;
    final canSend = hasDraft || (!running && st.queue.isNotEmpty);
    final g = ref.watch(generateProvider);
    final hasCanvas = canvasHasContent(g);
    // 画布清空了(比如去创作页按了重置)就把勾一起撤掉,不留一个带不出东西的勾。
    if (!hasCanvas && _withCanvas) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _withCanvas) setState(() => _withCanvas = false);
      });
    }
    // 浮卡样式:白色底部区,和底栏连成一块;输入框是凹槽灰
    return Docked(
      child: ColoredBox(
        color: context.raisedFill(Colors.transparent),
        child: Padding(
          // 键盘避让交给 Scaffold(resizeToAvoidBottomInset 默认开):它已经把 body
          // 的 viewInsets.bottom 抹成 0 了,这里再加一次等于抬两倍高。
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_pending != null)
                Padding(
                  padding: const EdgeInsets.only(left: 53, bottom: 9),
                  child: _Thumb(
                    bytes: _pending!.bytes,
                    onRemove: () => setState(() => _pending = null),
                  ),
                ),
              _optionRow(hasCanvas),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '带一张图',
                    onPressed: _pick,
                    icon: Icon(
                      Icons.image_outlined,
                      color: _pending != null ? scheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '想画什么、想改哪里…',
                        filled: true,
                        fillColor: context.skin.float
                            ? scheme.surfaceContainerHigh
                            : scheme.surfaceContainerLowest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 跑着的时候:输入框空着是停止,写了东西是发送(排进队里)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: running && !hasDraft
                        ? IconButton.filledTonal(
                            tooltip: '停止',
                            onPressed: ref
                                .read(assistantProvider.notifier)
                                .stop,
                            icon: const Icon(Icons.stop, size: 20),
                          )
                        : IconButton.filled(
                            tooltip: '发送',
                            onPressed: canSend ? () => _send() : null,
                            icon: const Icon(Icons.arrow_upward, size: 20),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图片模型不支持时的门禁。
///
/// Anima / Krea 走的是服务端 Modal 那条,提示词体系与 NAI 完全不同(krea 吃的是
/// 连贯自然语言),而助手这套预设、工具、`nai_draw` 围栏全是按 NAI 写的。以前
/// 硬跑也能出东西,只是出来的提示词对那两个模型基本等于没写 —— 与其让人对着
/// 一个看不出哪儿不对的结果琢磨,不如直接挡住。
class _ModelGate extends ConsumerWidget {
  const _ModelGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: context.raisedFill(scheme.surfaceContainer),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.block_outlined,
                size: 26,
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'AI 助手暂不支持这个模型',
              style: context.texts.titleSmall!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Anima 与 Krea 的提示词体系和 NAI 是两套。\n去创作页换成 NAI 4.5 或 5 再来。',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () =>
                  ref.read(shellIndexProvider.notifier).select(kTabCreate),
              child: const Text('去换模型'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标题右边的 BETA 小标。
class _BetaBadge extends StatelessWidget {
  const _BetaBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'BETA',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
          height: 1.2,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// 没有 Bot 授权、也没选自定义接口:这时发不出去。不放一个按下去就报错的空壳输入框,
/// 给两条出路 —— 选一个自己的模型接口,或者去做 Bot 授权。
/// tab 常驻(不按登录态藏),门槛写在页里 —— tab 时有时无更迷惑。
class _Gate extends ConsumerWidget {
  const _Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: context.raisedFill(scheme.surfaceContainer),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bolt_outlined, size: 26, color: scheme.outline),
            ),
            const SizedBox(height: 15),
            Text(
              '先选一个模型接口',
              style: context.texts.titleSmall!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '没有 Bot 授权时,AI 助手只能用你自己的模型接口,\n资料只用本地库。',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => showModelSheet(context),
              child: const Text('选择模型接口'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () =>
                  ref.read(shellIndexProvider.notifier).select(kTabProfile),
              child: const Text('去 Bot 授权'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MsgTile extends ConsumerWidget {
  const _MsgTile({
    required this.msg,
    required this.onLongPress,
    required this.fontSize,
    this.prev,
    this.live = false,
    this.onRetry,
    this.handoffSecs,
    this.queued = false,
    this.queuedImage,
  });

  final AssistantMsg msg;

  /// 还排在队里、没发出去的一句:气泡压淡,底下标「排队中」。
  final bool queued;

  /// 排着那句带的图。还没存进 blob,直接拿字节画。
  final Uint8List? queuedImage;

  /// 上一份提议 —— 结果条拿它当差异基线。
  final DrawProposal? prev;
  final VoidCallback onLongPress;

  /// 报错上那颗「重试」。null = 不给(见 `_list` 里的条件)。
  final VoidCallback? onRetry;

  /// 这是不是**最后一份提议**。是就在气泡里、结果条下面带一排处置按钮。
  final bool live;

  /// 消息正文的字号(助手设置里调)。
  final double fontSize;

  /// 非空 = 这条刚顶替掉「正在跑」那张气泡,值是那一轮等了几秒。
  /// 状态行照原样再摆一下再收走,结果条跟着长出来(见 [_Handoff])。
  final int? handoffSecs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: switch (msg.role) {
        MsgRole.user => _user(context, ref, scheme),
        MsgRole.ai => _ai(context, scheme),
        MsgRole.error => _error(context, scheme),
      },
    );
  }

  Widget _user(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (queuedImage case final bytes?)
        _fade(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
          ),
        )
      else if (msg.imageHash != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: FutureBuilder(
            future: ref.read(appStoresProvider).assistant.image(msg.imageHash),
            builder: (context, snap) => snap.data == null
                ? const SizedBox.shrink()
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      snap.data!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        ),
      GestureDetector(
        onLongPress: onLongPress,
        child: _fade(
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .8,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.selectedFill,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                msg.text,
                style: context.texts.bodyMedium!.copyWith(
                  color: context.onSelectedFill,
                  fontSize: fontSize,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
      // 这一轮 AI 看没看见画布,事后光读回复分不出来 —— 留个记号,
      // 「它怎么没按我的词改」才有答案。
      if (queued || msg.withCanvas)
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (queued) ..._mark(context, Icons.schedule, '排队中'),
              if (queued && msg.withCanvas) const SizedBox(width: 10),
              if (msg.withCanvas)
                ..._mark(context, Icons.draw_outlined, '引用了创作页'),
            ],
          ),
        ),
    ],
  );

  /// 排着的那句压淡;发出去时原地淡回来。
  Widget _fade(Widget child) => AnimatedOpacity(
    opacity: queued ? .55 : 1,
    duration: Motion.medium,
    curve: Motion.standard,
    child: child,
  );

  /// 用户气泡底下那行小记号里的一项。
  List<Widget> _mark(BuildContext context, IconData icon, String label) {
    final color = context.scheme.outline;
    return [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: context.texts.labelSmall!.copyWith(color: color)),
    ];
  }

  /// AI 那一轮。给了画面的,回复和结果合成一个气泡,底部压一条 [ResultStrip] ——
  /// 每一份都长这样,不给最后一份单独摊一张卡:新一轮一来它就得收起来,同一个东西
  /// 前后两副样子,还白占两屏。
  ///
  /// 最后一份的处置按钮也包在这个气泡里,排在结果条下面;新一轮来了只是这一排收起来。
  ///
  /// 「纯文本格式」那一轮([AssistantMsg.promptAsText])不出结果条:提示词接在正文下面,
  /// 显示成纯文本,点一下复制。
  Widget _ai(BuildContext context, ColorScheme scheme) {
    final asText = msg.promptAsText;
    final strip = msg.draw != null && !asText;
    final maxW = MediaQuery.sizeOf(context).width * .84;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (msg.tools.isNotEmpty) ...[
          ToolTrail(tools: msg.tools),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Container(
              padding: EdgeInsets.fromLTRB(14, 11, 14, strip ? 9 : 11),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: _kAiBubbleRadius,
                border: context.edgeBorder,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (handoffSecs case final s?)
                    _Handoff(
                      open: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: pendingStatusRow(
                          context,
                          stage: '',
                          secs: s,
                          fontSize: fontSize,
                          style: context.texts.bodyMedium!.copyWith(
                            fontSize: fontSize,
                            height: 1.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ReplyBody(msg.text, fontSize: fontSize),
                  if (asText) ...[
                    const SizedBox(height: 10),
                    PromptTextBlocks(msg.draw!, fontSize: fontSize),
                  ],
                  if (strip) ...[
                    if (handoffSecs != null)
                      _Handoff(
                        open: true,
                        child: ResultStrip(msg: msg, prev: prev),
                      )
                    else
                      ResultStrip(msg: msg, prev: prev),
                    // 不再是最后一份时这一排收起来,不一下子抽掉。没按钮时也留着这层
                    // (零高),否则收起来没有动画可播。
                    AnimatedSize(
                      duration: Motion.medium,
                      curve: Motion.emphasized,
                      alignment: Alignment.topLeft,
                      child: live
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: ProposalActions(msg: msg, dense: true),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        InlineImages(msg: msg),
      ],
    );
  }

  /// 失败气泡。
  Widget _error(BuildContext context, ColorScheme scheme) {
    final auth = msg.errorKind == AssistErrorKind.auth;
    final fg = auth ? scheme.onSurfaceVariant : scheme.onErrorContainer;
    final retry = onRetry;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, 14, retry == null ? 12 : 4),
      decoration: BoxDecoration(
        color: auth ? scheme.surfaceContainerLow : scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: auth ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                auth ? Icons.lock_outline : Icons.error_outline,
                size: 18,
                color: auth ? scheme.outline : scheme.onErrorContainer,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  msg.text,
                  style: context.texts.bodyMedium!.copyWith(
                    color: fg,
                    fontSize: fontSize,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
          if (retry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 对话里新出现的一条:淡入并往上浮一小段。[grow] 再加上高度从 0 长出来,把上面的
/// 对话平滑地推上去。
///
/// [animate] 只在挂上的那一刻读一次,之后重建不管它 —— 不播的就是原样的子树,
/// 不留一层闲着的动画。
class _Enter extends StatefulWidget {
  const _Enter({
    super.key,
    required this.animate,
    required this.child,
    this.grow = false,
  });

  final bool animate;
  final bool grow;
  final Widget child;

  @override
  State<_Enter> createState() => _EnterState();
}

class _EnterState extends State<_Enter> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final c = AnimationController(vsync: this, duration: Motion.medium)
      ..forward();
    _c = c;
    _t = CurvedAnimation(parent: c, curve: Motion.emphasized);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    Widget child = FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - t.value) * 14),
          child: child,
        ),
        child: widget.child,
      ),
    );
    if (widget.grow) {
      // 列表是倒着的,底边贴着输入框:内容顶端对齐,长高时看着是从下面升上来。
      // 里面垫一层撑满宽度:SizeTransition 会把宽度放松,不撑的话整条按内容宽度
      // 居中摆,右对齐的用户气泡就往左偏了。
      child = SizeTransition(
        sizeFactor: t,
        alignment: Alignment.topCenter,
        child: SizedBox(width: double.infinity, child: child),
      );
    }
    return child;
  }
}

/// 正在跑的那一轮:查过的资料(与跑完之后共用 [ToolTrail] —— 同一份内容在等待期和
/// 事后长得一样,收起来才不像「刚才那些东西没了」),下面一个占着回复位置的气泡。
///
/// 占位做成和回复一样的气泡、一样的字号,带转圈、阶段文案和已经等了几秒:一轮要
/// 20~40 秒,原先一颗 11 像素的小圈缩在轨迹底下,看着像没在动。跑完回复气泡就出在
/// 这个位置上。
class _LiveTurn extends StatelessWidget {
  const _LiveTurn({required this.state, required this.fontSize});

  final AssistantState state;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // 从发出那一刻算:这一轮是跟那条提问一起开始的(见 AssistantNotifier.send)
    int? since;
    for (final m in state.msgs.reversed) {
      if (m.role == MsgRole.user) {
        since = m.at;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一条资料查出来之前没有这一块;出来时连同下面的间距一起长出来
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.standard,
            alignment: Alignment.topLeft,
            child: state.liveTools.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ToolTrail(tools: state.liveTools, running: true),
                  ),
          ),
          _PendingBubble(
            stage: state.stage,
            since: since,
            fontSize: fontSize,
            text: state.liveText,
            reasoning: state.liveReasoning,
          ),
        ],
      ),
    );
  }
}

/// AI 回复气泡的圆角:左下角收成小角,指向说话的那一方。
const _kAiBubbleRadius = BorderRadius.only(
  topLeft: Radius.circular(16),
  topRight: Radius.circular(16),
  bottomLeft: Radius.circular(4),
  bottomRight: Radius.circular(16),
);

/// 回复还没来时占着它位置的气泡:转圈 + 阶段文案 + 秒数。
///
/// 模型开始吐字之后,思考与正文接在下面实时长出来(自填接口那条才有,见
/// [AgentDelta])。最终那条 AI 气泡长得跟这里一样,所以换过去时不跳版。
class _PendingBubble extends StatefulWidget {
  const _PendingBubble({
    required this.stage,
    required this.since,
    required this.fontSize,
    this.text = '',
    this.reasoning = '',
  });

  final String stage;

  /// 这一轮开始的时刻(毫秒时间戳)。null = 找不到那条提问,不显示秒数。
  final int? since;

  final double fontSize;

  /// 正在写的正文。空 = 还没开始吐字,或这条链路不发增量。
  final String text;

  /// 正在写的思考过程。
  final String reasoning;

  @override
  State<_PendingBubble> createState() => _PendingBubbleState();
}

class _PendingBubbleState extends State<_PendingBubble> {
  late final Timer _tick;

  /// 用户手动拨过的开合。null = 没拨过,按「还没开始写正文就摊开」走。
  bool? _thinkManual;

  @override
  void initState() {
    super.initState();
    // 秒数每次按墙钟现算,不自己累加:列表滚远了这一条会被回收,重建回来还是对的
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final since = widget.since;
    final secs = since == null
        ? null
        : ((DateTime.now().millisecondsSinceEpoch - since) ~/ 1000).clamp(
            0,
            9999,
          );
    final style = context.texts.bodyMedium!.copyWith(
      fontSize: widget.fontSize,
      height: 1.6,
      color: scheme.onSurfaceVariant,
    );
    final hasThink = widget.reasoning.isNotEmpty;
    final live = widget.text.isNotEmpty || hasThink;
    // 正文一开始写就把思考收起来 —— 那会儿该看的是答案。用户自己拨过就听他的。
    final open = _thinkManual ?? widget.text.isEmpty;
    return ConstrainedBox(
      // 吐字之后按 AI 气泡同一个上限断行;还没吐字时那行状态文案自己多宽算多宽
      constraints: BoxConstraints(
        maxWidth: live
            ? MediaQuery.sizeOf(context).width * .84
            : double.infinity,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: _kAiBubbleRadius,
          border: context.edgeBorder,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态行本身就是思考那块的下拉头:有思考可看时点它开合,没有就是一行字
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasThink
                  ? () => setState(() => _thinkManual = !open)
                  : null,
              child: pendingStatusRow(
                context,
                stage: widget.stage,
                secs: secs,
                fontSize: widget.fontSize,
                style: style,
                trailing: hasThink
                    ? AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: Motion.fast,
                        curve: Motion.standard,
                        child: Icon(
                          Icons.expand_more,
                          size: widget.fontSize + 2,
                          color: scheme.outline,
                        ),
                      )
                    : null,
              ),
            ),
            if (hasThink)
              AnimatedSize(
                duration: Motion.fast,
                curve: Motion.standard,
                alignment: Alignment.topLeft,
                child: open ? _think(scheme) : const SizedBox(width: 1),
              ),
            if (widget.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              // 不套 AnimatedSize:每秒十几帧的增量,补间只会让字一直在抖
              ReplyBody(widget.text, fontSize: widget.fontSize),
            ],
          ],
        ),
      ),
    );
  }

  /// 思考过程:小一号的灰字,限高四行。
  ///
  /// 超出限高时只显示最新写出来的那几句 —— `reverse` 的滚动视图天然吸在底,
  /// 不必为了跟着最新一行去挂控制器。
  Widget _think(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: (widget.fontSize - 2) * 1.5 * 4),
      child: SingleChildScrollView(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.reasoning,
          style: context.texts.labelSmall!.copyWith(
            fontSize: widget.fontSize - 2,
            height: 1.5,
            color: scheme.outline,
          ),
        ),
      ),
    ),
  );
}

/// 「思考中 · 12 秒」这一行。等待气泡与刚换过来的回复气泡共用 —— 换场时两边
/// 长得一模一样,那一行才像是自己淡出去的,而不是整块重画。
Widget pendingStatusRow(
  BuildContext context, {
  required String stage,
  required int? secs,
  required double fontSize,
  required TextStyle style,
  Widget? trailing,
}) {
  final scheme = context.scheme;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: fontSize + 3,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: scheme.primary,
        ),
      ),
      const SizedBox(width: 10),
      // 「思考中」「查资料中」来回换时淡入淡出;左对齐叠放,长短不同的两句不会横着晃
      AnimatedSwitcher(
        duration: Motion.fast,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        child: Text(
          stage.isEmpty ? '思考中' : stage,
          key: ValueKey(stage),
          style: style,
        ),
      ),
      if (secs != null) ...[
        const SizedBox(width: 8),
        Text(
          '$secs 秒',
          style: style.copyWith(
            color: scheme.outline,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
      if (trailing != null) ...[const SizedBox(width: 4), trailing],
    ],
  );
}

/// 换场用的一层:出现时先摆成**相反**的姿态,下一帧再过渡到 [open] 那一头。
///
/// 回复气泡是顶替「正在跑」那张出现的,两张长得几乎一样 —— 状态行用它收走、
/// 结果条用它长出来,看着就是那张气泡自己变了,而不是换了一块。
class _Handoff extends StatefulWidget {
  const _Handoff({required this.open, required this.child});

  /// 最终姿态:true = 长出来,false = 收走。
  final bool open;
  final Widget child;

  @override
  State<_Handoff> createState() => _HandoffState();
}

class _HandoffState extends State<_Handoff> {
  late bool _open = !widget.open;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _open = widget.open);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedCrossFade(
    duration: Motion.medium,
    sizeCurve: Motion.emphasized,
    firstCurve: Motion.standard,
    secondCurve: Motion.standard,
    alignment: Alignment.topLeft,
    crossFadeState: _open
        ? CrossFadeState.showFirst
        : CrossFadeState.showSecond,
    firstChild: widget.child,
    secondChild: const SizedBox(width: double.infinity),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    height: 76,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
        ),
        Positioned(
          right: 0,
          top: -4,
          child: Material(
            color: context.scheme.inverseSurface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: context.scheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

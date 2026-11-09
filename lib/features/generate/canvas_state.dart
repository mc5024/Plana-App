import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../editor/editor_state.dart';
import 'canvas_models.dart';
import 'generate_state.dart';
import 'models.dart';

export 'canvas_models.dart';

final canvasWorkspaceProvider =
    NotifierProvider<CanvasWorkspaceNotifier, CanvasWorkspace>(
      CanvasWorkspaceNotifier.new,
    );

/// 画布集合。当前画布那组内容活在 generateProvider 里(编辑都走它),
/// 每次变动经 [record] 抄一份回这里;其余画布只在这里存着它们那一组。
class CanvasWorkspaceNotifier extends Notifier<CanvasWorkspace> {
  @override
  CanvasWorkspace build() {
    final store = ref.watch(appStoresProvider).workspace;
    return store.initialCanvases ??
        CanvasWorkspace.single(
          CanvasPrompts.of(store.initial ?? GenerateState.initial()),
        );
  }

  /// 落盘:整份创作状态(全局设置 + 当前画布的词)连同全部画布一起排队。
  void _save([GenerateState? current]) {
    final store = ref.read(appStoresProvider).workspace;
    store.schedule(
      current ?? ref.read(generateProvider),
      state,
      idSeq: store.idSeq,
    );
  }

  /// generateProvider 每次变动都来这里:把当前画布那组提示词抄回集合,再排队落盘。
  void record(GenerateState s, {required int idSeq}) {
    ref.read(appStoresProvider).workspace.idSeq = idSeq;
    final prompts = CanvasPrompts.of(s);
    final active = state.active;
    if (!prompts.sameAs(active.prompts)) {
      state = state.copyWith(
        canvases: [
          for (final c in state.canvases)
            if (c.id == active.id) c.copyWith(prompts: prompts) else c,
        ],
      );
    }
    _save(s);
  }

  /// 按画布 id 改它那组提示词:是当前画布就走 generateProvider(界面跟着变),
  /// 否则只改集合里存着的那份。异步流程的回写都走这里,切走了也落回原画布。
  void updatePrompts(String id, CanvasPrompts Function(CanvasPrompts) change) {
    final canvas = state.find(id);
    if (canvas == null) return;
    if (id == state.activeId) {
      final current = CanvasPrompts.of(ref.read(generateProvider));
      final next = change(current);
      if (!identical(next, current)) {
        ref.read(generateProvider.notifier).applyCanvas(next);
      }
      return;
    }
    final next = change(canvas.prompts);
    if (identical(next, canvas.prompts)) return;
    state = state.copyWith(
      canvases: [
        for (final c in state.canvases)
          if (c.id == id) c.copyWith(prompts: next) else c,
      ],
    );
    _save();
  }

  /// 按画布 id 改它的采样参数(套用画风推荐参数用)。[change] 拿到的是这张画布
  /// 那份参数,模型是它记下时那个。返回改之前那份给撤销用;没改成返回 null。
  CanvasSampling? updateSampling(
    String id,
    GenParams Function(GenParams) change,
  ) {
    CanvasSampling? before;
    updatePrompts(id, (p) {
      final s = p.sampling;
      if (s == null) return p;
      final next = CanvasSampling.of(change(s.writeInto(const GenParams())));
      if (next.sameAs(s)) return p;
      before = s;
      return p.copyWith(sampling: next);
    });
    return before;
  }

  /// 撤销一次整体写入创作页(图库导入、用作底图 / 参考图、存入重绘):全局设置
  /// 整份放回 [before],画布内容还给写入时那张画布 —— 撤销条挂着的几秒里
  /// 切了画布,也不会还错地方;那张画布已经删了就只回全局设置。
  void undoWrite(GenerateState before, String canvasId) {
    ref.read(generateProvider.notifier).restoreGlobals(before);
    updatePrompts(canvasId, (_) => CanvasPrompts.of(before));
  }

  /// 在每张画布挂着和收起来的 LoRA 上做 [change](见 [CanvasPrompts.changeLoras]),
  /// 返回有没有改到。LoRA 下载要几分钟,装好时发起的那张可能已经不是当前画布。
  bool changeLoras(List<ActiveLora>? Function(List<ActiveLora>) change) {
    var hit = false;
    for (final c in [...state.canvases]) {
      updatePrompts(c.id, (p) {
        final next = p.changeLoras(change);
        if (next == null) return p;
        hit = true;
        return next;
      });
    }
    return hit;
  }

  void _prepareSwitch() {
    // 只刷挂起的编辑;已退出的旧编辑会话不能再次盖掉外部导入内容。
    ref.read(editorProvider.notifier).flushPendingWriteBack();
  }

  void select(String id) {
    if (id == state.activeId || state.find(id) == null) return;
    _prepareSwitch();
    state = state.copyWith(activeId: id);
    ref.read(generateProvider.notifier).applyCanvas(state.active.prompts);
    _save();
  }

  /// 新建并切过去。空白画布只沿用当前的提示词预设、出图参数(含重绘放大)、
  /// Vibe 强度归一开关和风格参考强度;词、分区、角色、参考图、LoRA、底图与
  /// 重绘都清空。
  /// 复制则带上整组。
  String create({bool duplicate = false}) {
    _prepareSwitch();
    final current = CanvasPrompts.of(ref.read(generateProvider));
    final id = 'canvas${state.nextId}';
    final prompts = duplicate
        ? current
        : CanvasPrompts(
            promptPresetId: current.promptPresetId,
            sampling: current.sampling,
            normalizeVibe: current.normalizeVibe,
            kreaStyleRefWeight: current.kreaStyleRefWeight,
          );
    final name = duplicate ? _copyName(state.active.name) : _blankName();
    state = state.copyWith(
      canvases: [
        ...state.canvases,
        CanvasDraft(id: id, name: name, prompts: prompts),
      ],
      activeId: id,
      nextId: state.nextId + 1,
    );
    ref.read(generateProvider.notifier).applyCanvas(prompts);
    _save();
    return id;
  }

  /// 把 [id] 那张画布整组换成 [prompts](恢复一条历史),返回换之前那组给撤销用;
  /// 画布已经删了返回 null。
  CanvasPrompts? replace(String id, CanvasPrompts prompts) {
    final canvas = state.find(id);
    if (canvas == null) return null;
    _prepareSwitch();
    final before = id == state.activeId
        ? CanvasPrompts.of(ref.read(generateProvider))
        : canvas.prompts;
    updatePrompts(id, (_) => prompts);
    return before;
  }

  /// 用 [prompts] 新建一张画布并切过去,名字是 [from] 那张的「· 副本」。
  String createFrom(CanvasPrompts prompts, {required String from}) {
    _prepareSwitch();
    final id = 'canvas${state.nextId}';
    state = state.copyWith(
      canvases: [
        ...state.canvases,
        CanvasDraft(id: id, name: _copyName(from), prompts: prompts),
      ],
      activeId: id,
      nextId: state.nextId + 1,
    );
    ref.read(generateProvider.notifier).applyCanvas(prompts);
    _save();
    return id;
  }

  /// 新画布叫「画布 N」,N 取没被占用的最小号:新装时默认画布之后就是「画布 1」,
  /// 删掉的号下次还能用上。名字只是标签,和 id 的发号器各管各的。
  String _blankName() {
    final used = {for (final c in state.canvases) c.name};
    var n = 1;
    while (used.contains('画布 $n')) {
      n++;
    }
    return '画布 $n';
  }

  /// 副本的副本仍只挂一个「· 副本」,并守住长度上限。
  static String _copyName(String name) {
    const suffix = ' · 副本';
    final base = name.endsWith(suffix)
        ? name.substring(0, name.length - suffix.length)
        : name;
    final room = kCanvasNameMax - suffix.length;
    return '${base.length > room ? base.substring(0, room) : base}$suffix';
  }

  /// 默认画布的名字固定,改不了。
  void rename(String id, String name) {
    var trimmed = name.trim();
    if (trimmed.isEmpty || id == state.defaultId || state.find(id) == null) {
      return;
    }
    if (trimmed.length > kCanvasNameMax) {
      trimmed = trimmed.substring(0, kCanvasNameMax);
    }
    state = state.copyWith(
      canvases: [
        for (final c in state.canvases)
          if (c.id == id) c.copyWith(name: trimmed) else c,
      ],
    );
    _save();
  }

  /// 长按拖动排序,只动位置,当前画布不变。默认画布固定在最上面:它不动,
  /// 别的也排不到它前面。
  ///
  /// 索引按 `onReorderItem` 语义:[to] 已经按「移除 [from] 之后」调整过。
  void reorder(int from, int to) {
    final canvases = [...state.canvases];
    if (from == to) return;
    if (from < 1 || from >= canvases.length) return;
    if (to < 1 || to >= canvases.length) return;
    canvases.insert(to, canvases.removeAt(from));
    state = state.copyWith(canvases: canvases);
    _save();
  }

  /// 默认画布(最上面那张)删不掉,所以总有一张在。返回被移除的草稿,用于撤销。
  ({CanvasDraft canvas, int index, bool wasActive})? remove(String id) {
    if (id == state.defaultId || state.find(id) == null) return null;
    _prepareSwitch();
    final index = state.canvases.indexWhere((c) => c.id == id);
    final removed = state.canvases[index];
    final wasActive = id == state.activeId;
    final remaining = state.canvases.where((c) => c.id != id).toList();
    state = state.copyWith(
      canvases: remaining,
      activeId: wasActive
          ? remaining[index.clamp(0, remaining.length - 1)].id
          : state.activeId,
    );
    if (wasActive) {
      ref.read(generateProvider.notifier).applyCanvas(state.active.prompts);
    }
    _save();
    return (canvas: removed, index: index, wasActive: wasActive);
  }

  /// 撤销删除:放回原位(不越过默认画布);删的是当前画布就顺手切回去。
  void restore(CanvasDraft canvas, int index, {bool activate = false}) {
    if (state.find(canvas.id) != null) return;
    final canvases = [...state.canvases];
    canvases.insert(index.clamp(1, canvases.length), canvas);
    state = state.copyWith(canvases: canvases);
    if (activate) {
      select(canvas.id);
    } else {
      _save();
    }
  }
}

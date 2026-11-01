import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/gen_jobs.dart' show GenJob;
import '../../generate/widgets/common.dart' show StripeThumb;
import '../models.dart';
import 'gallery_grid_sheet.dart';
import 'result_badge_chip.dart';
import 'result_thumb.dart';
import '../../../core/util/haptics.dart';

// ---- 缩略图几何:**渲染与滚动定位共用这一组常数,谁都别再各写一份** ----
//
// 一枚条目的占位宽 = 图宽 + 内衬 2×2 + 边框 2×2。边框那 4px 极易漏算 ——
// 未选中时颜色是 transparent,肉眼看不见,但**照样占布局空间**。漏掉它
// 每张少算 4px,几十张累积上百像素,表现为自动滚动总差一截(实机反馈)。

const _thumbH = 72.0;
const _thumbPad = 2.0; // AnimatedContainer 内衬
const _thumbBorder = 2.0; // 选中环(透明时也占位)
const _thumbGap = 8.0; // ListView.separated 分隔
const _stripPadH = 12.0; // ListView 水平 padding

/// 条目在交叉轴上的完整占位高 —— 和 [_thumbSlotW] 同一套算法。
///
/// **别写死。** 原先外层 SizedBox 直接写 68,正好漏掉上面警告的那一圈边框
/// (实际占位 70),结果 ListView 给的紧约束把每张图压到 60 —— 常数说 62、
/// 屏幕上是 60,还没人发现。
const _thumbSlotH = _thumbH + (_thumbPad + _thumbBorder) * 2;

// 「›」是纯悬浮层:滚动区铺满全宽,缩略图从它底下直接穿过去,一寸不让。
const _moreSize = 44.0; // 圆钮直径
const _moreRight = 12.0; // 距右边缘

// 上滑后浮出的落点:三条横带浮在胶片条正上方(overlay 层,不占布局,不推画布),
// 自下而上是「分享」「收藏」「删除」。
const _bandH = 54.0;
const _bandSpacing = 10.0; // 两条之间的缝,松在缝里 = 取消
const _bandCount = 3;

/// 下面那条(分享)与胶片条的间距 —— 同时也是**这个手势唯一的保险**。
///
/// 原来靠长按起手:按住不动到时才拿得起来,所以落点贴着条摆(10)也不怕误触。
/// 改成直接上滑之后那道门没了,保险只能落在行程上:手指从缩略图中心算起要走
/// 约 `10(条内衬) + 38(缩略图半高) + 64 ≈ 110` 才碰到分享,是一个明确的
/// 「往上甩一下」,横滑翻图或点选时的竖向抖动够不着。
///
/// 删除排在**最远**那条(再过两条带加两道缝,约 240):松手早了落在分享或
/// 收藏上,顶多弹一下系统分享面板、或者收藏一下再撤销;反过来排的话,想分享
/// 却松早了就是一次删除。拖过分享继续往上就到收藏、删除,不用绕 ——
/// 带是通宽的,而拖起来的那张本来就只能上下走(见 [_FilmThumb] 的 axis)。
const _bandGap = 64.0;

/// 极端长宽比的兜底:太窄点不着,太宽一张就把条占满。
/// 两头都按 [_thumbH] 的倍数写(= 原来 40/116 对 62 的那两个比例)——
/// 写成绝对像素的话,一改高度这两个数就悄悄变成另一套比例了。
double _thumbImgW(double aspect) =>
    (_thumbH * aspect).clamp(_thumbH * .645, _thumbH * 1.871);

/// 条目在滚动轴上的完整占位宽(含内衬与边框)。
double _thumbSlotW(double aspect) =>
    _thumbImgW(aspect) + (_thumbPad + _thumbBorder) * 2;

/// 底部历史胶片条:横向缩略图(选中环 + 角标)+ 尾部「›」展开全部网格。
/// 头部插着**在跑的任务**,一条一张占位卡(逐帧预览 + 进度条),点卡片让画布
/// 跟随它,点历史缩略图切走看历史 —— 对齐 web 桌面端的占位卡交互。
/// 取消不在卡上:卡这么小,取消挨着「切换跟随」这个主手势太容易点错,
/// 它长在画布那条进度胶囊上(见 ProgressPill,web 也是放在状态条上)。
/// 历史图**上滑**即拿起,条上方浮出三条落点(自下而上分享、收藏、删除),拖上去
/// 松手即分享 / 收藏 / 删;拖回来或松在别处什么都不发生 —— 所以删除不再另弹确认。
/// 竖向手势与横向滚动各认各的轴(见 [_FilmThumb] 的 affinity),不用自己
/// 进竞技场调解。
/// 选中项变化(含画布横滑切图、从展开页跳选)时自动滚动,把选中项摆到视野中央;
/// 画布跟随的任务卡也算选中项。
class FilmStrip extends StatefulWidget {
  const FilmStrip({
    super.key,
    required this.results,
    required this.selectedId,
    required this.onSelect,
    required this.onShare,
    required this.onFavorite,
    required this.isFavorite,
    required this.onDelete,
    this.jobs = const [],
    this.selectedJobId,
    this.onSelectJob,
  });

  final List<ResultImage> results;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// 拖进分享区后分享这一张(按保存设置处理、拉系统面板都在调用方)。
  final ValueChanged<String> onShare;

  /// 拖进收藏区后收藏 / 取消收藏这一张。
  final ValueChanged<String> onFavorite;

  /// 这一张眼下收藏了没有:拿起时据此决定收藏那条写「收藏」还是「取消收藏」。
  final bool Function(String id) isFavorite;

  /// 拖进删除区后删这一张(移进回收站与提示由调用方处理)。
  final ValueChanged<String> onDelete;

  /// 在跑的任务,**已按新→旧排好**(调用方给 `GenPool.newestFirst`)。
  final List<GenJob> jobs;

  /// 画布正在跟随的任务;非空时历史图那边不显示选中环。
  final String? selectedJobId;
  final ValueChanged<String>? onSelectJob;

  @override
  State<FilmStrip> createState() => _FilmStripState();
}

class _FilmStripState extends State<FilmStrip>
    with SingleTickerProviderStateMixin {
  final _sc = _StripController();

  // ---- 条目进出 ----
  //
  // 视野里进来一条:宽从 0 长到整格,后面的跟着让开;视野里移除一条:留个影子从
  // 整格收到 0,后面的跟着补上。视野外的进出直接生效,位移补回滚动位置,
  // 视野里的图不动。

  /// 一次进出超过这么多条(切相册、批量删)就不做动画,直接换。
  static const _kMaxAnimated = 4;

  /// 正在长出的条目:键 → 进度 0..1。
  final _entering = <String, double>{};

  /// 正在收起的影子:键 → 影子。
  final _leaving = <String, _Leaving>{};

  /// 拖上去删掉的图:拖起时原位已经是空位,收起的影子也画空位。
  final _vacated = <String>{};

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// 上一次 build 排出来的条目(含影子)。
  List<_Entry> _display = const [];

  @override
  void initState() {
    super.initState();
    // 冷启动的选中项可能在条中段,布局完成后滚到可见
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(FilmStrip old) {
    super.didUpdateWidget(old);
    if (!_sameItems(old)) _reconcile();
    // 删除后保持用户正在看的胶片位置。即使删的是选中图，状态会自动改选相邻图，
    // 此时也不能把手动滚开的胶片条重新拉回选中项。
    final deleted = widget.results.length < old.results.length;
    if (!deleted &&
        (old.selectedId != widget.selectedId ||
            old.selectedJobId != widget.selectedJobId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  bool _sameItems(FilmStrip old) {
    if (!identical(old.results, widget.results) ||
        old.jobs.length != widget.jobs.length) {
      return false;
    }
    for (var i = 0; i < old.jobs.length; i++) {
      if (old.jobs[i].id != widget.jobs[i].id) return false;
    }
    return true;
  }

  /// 要排的条目:任务在前、历史图在后,影子插回它原来的位置。
  List<_Entry> _entries() {
    final items = [
      for (final j in widget.jobs)
        _Entry('j:${j.id}', _thumbSlotW(_aspectOf(j.width, j.height)), job: j),
      for (final r in widget.results)
        _Entry('r:${r.id}', _thumbSlotW(_resultAspect(r)), result: r),
    ];
    if (_leaving.isEmpty) return items;
    final waiting = <String?, List<_Entry>>{};
    for (final l in _leaving.values) {
      (waiting[l.before] ??= []).add(l.entry);
    }
    final out = <_Entry>[];
    final done = <String>{};
    void put(_Entry e) {
      if (!done.add(e.key)) return;
      for (final g in waiting.remove(e.key) ?? const <_Entry>[]) {
        put(g);
      }
      out.add(e);
    }

    items.forEach(put);
    // 排在末尾的,以及原本挨着的那条也已经不在的
    for (final g in [for (final gs in waiting.values) ...gs]) {
      put(g);
    }
    return out;
  }

  /// 这条眼下占整格的比例。
  double _factor(String key) {
    final l = _leaving[key];
    if (l != null) return l.from * (1 - Motion.standard.transform(l.t));
    final t = _entering[key];
    return t == null ? 1 : Motion.standard.transform(t);
  }

  /// 这条在滚动轴上占的宽:占位 + 后面那道分隔,乘上进出比例。
  /// 列表的 itemExtentBuilder 与定位计算都走这里。
  double _extentOf(_Entry e) => (e.slot + _thumbGap) * _factor(e.key);

  /// 各条的(键, 左缘, 宽)。
  List<({String key, double x, double w})> _geometry(List<_Entry> es) {
    final out = <({String key, double x, double w})>[];
    var x = _stripPadH;
    for (final e in es) {
      final w = _extentOf(e);
      out.add((key: e.key, x: x, w: w));
      x += w;
    }
    return out;
  }

  double _xOf(List<_Entry> es, String key) {
    var x = _stripPadH;
    for (final e in es) {
      if (e.key == key) break;
      x += _extentOf(e);
    }
    return x;
  }

  _StripPosition? get _laidOut {
    if (!_sc.hasClients) return null;
    final pos = _sc.position;
    return pos is _StripPosition && pos.hasContentDimensions ? pos : null;
  }

  /// 视野最左、在新排布里还在的那条。
  String? _anchor(
    List<({String key, double x, double w})> geo,
    double px,
    Set<String> present,
  ) {
    final first = geo.indexWhere((g) => g.x + g.w > px);
    if (first < 0) return null;
    for (final g in geo.skip(first)) {
      if (present.contains(g.key)) return g.key;
    }
    return null;
  }

  /// 锚点在新排布里挪了多少,滚动位置就补多少。
  double _keep(
    _StripPosition pos,
    List<({String key, double x, double w})> geo,
    String? anchor,
    List<_Entry> after,
  ) {
    if (anchor == null) return 0;
    final delta =
        _xOf(after, anchor) - geo.firstWhere((g) => g.key == anchor).x;
    if (delta.abs() > 1e-6) pos.shift(delta);
    return delta;
  }

  /// 条目有进出时:视野里的长出 / 收起,视野外的直接生效。
  void _reconcile() {
    final pos = _laidOut;
    if (pos == null) return;
    final before = _display;
    final geo = _geometry(before);
    final px = pos.pixels + pos.pendingShift;
    final vp = pos.viewportDimension;
    final keys = {
      for (final j in widget.jobs) 'j:${j.id}',
      for (final r in widget.results) 'r:${r.id}',
    };
    final added = keys.difference({for (final e in before) e.key});
    final removed = [
      for (var i = 0; i < before.length; i++)
        if (!before[i].ghost && !keys.contains(before[i].key)) i,
    ];
    bool visible(int i) =>
        geo[i].w > 0 && geo[i].x + geo[i].w > px && geo[i].x < px + vp;
    final seen = removed.where(visible).toSet();
    final animate = added.length + seen.length <= _kMaxAnimated;

    for (final i in removed) {
      final e = before[i];
      final from = _factor(e.key);
      _entering.remove(e.key);
      if (animate && seen.contains(i)) {
        _leaving[e.key] = _Leaving(
          e.asGhost(vacant: _vacated.contains(e.key)),
          from,
        );
      }
    }
    _leaving.removeWhere((k, _) => keys.contains(k)); // 影子那条又回来了
    final present = {...keys, ..._leaving.keys};
    // 影子排在旧排布里它后面第一条还在的前面
    for (var i = 0; i < before.length; i++) {
      final l = _leaving[before[i].key];
      if (l == null) continue;
      l.before = null;
      for (final e in before.skip(i + 1)) {
        if (present.contains(e.key)) {
          l.before = e.key;
          break;
        }
      }
    }

    _vacated.retainWhere(keys.contains);

    final anchor = _anchor(geo, px, present);
    final after = _entries();
    if (animate && added.isNotEmpty) {
      final ai = anchor == null
          ? after.length
          : after.indexWhere((e) => e.key == anchor);
      // 锚点前面新来的:停在最左头时看得见,长出来;否则在视野外,直接出现
      if (px <= pos.minScrollExtent + .5) {
        for (var i = 0; i < ai; i++) {
          if (added.contains(after[i].key)) _entering[after[i].key] = 0;
        }
      }
      // 锚点后面新来的:落在视野里的长出来
      if (anchor != null) {
        var x = _xOf(after, anchor);
        // 视野右缘在新排布里的位置:锚点挪了多少,视野跟着挪多少
        final right = px + x - geo.firstWhere((g) => g.key == anchor).x + vp;
        for (var i = ai; i < after.length && x < right; i++) {
          if (added.contains(after[i].key)) _entering[after[i].key] = 0;
          x += _extentOf(after[i]);
        }
      }
    }
    final delta = _keep(pos, geo, anchor, after);
    if (_entering.isNotEmpty || _leaving.isNotEmpty) _startTicker();
    final target = _animTarget;
    if (delta.abs() > .5 && target != null) {
      // 正在滚的那段目标是按旧位置算的,跟着挪
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _animateTo(target + delta),
      );
    }
  }

  void _startTicker() {
    final ticker = _ticker ??= createTicker(_tick);
    if (ticker.isActive) return;
    _lastTick = Duration.zero;
    ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _lastTick).inMicroseconds / Motion.medium.inMicroseconds;
    _lastTick = elapsed;
    final pos = _laidOut;
    final geo = _geometry(_display);
    for (final k in _entering.keys.toList()) {
      final t = _entering[k]! + dt;
      if (t >= 1) {
        _entering.remove(k);
      } else {
        _entering[k] = t;
      }
    }
    for (final l in _leaving.values) {
      l.t = math.min(1.0, l.t + dt);
    }
    _leaving.removeWhere((_, l) => l.t >= 1);
    final after = _entries();
    if (pos != null) {
      // 用户滚动过,进出中的那条跑到了视野左边:照样补,视野里的图不动
      final px = pos.pixels + pos.pendingShift;
      _keep(pos, geo, _anchor(geo, px, {for (final e in after) e.key}), after);
    }
    if (_entering.isEmpty && _leaving.isEmpty) _ticker?.stop();
    setState(() {});
  }

  /// 进行中的定位动画的目标;没有在滚就是 null。
  double? _animTarget;

  void _animateTo(double target) {
    if (!mounted || !_sc.hasClients) return;
    final p = _sc.position;
    final t = target.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((t - p.pixels).abs() < 1) return;
    _animTarget = t;
    _sc
        .animateTo(t, duration: Motion.medium, curve: Motion.emphasized)
        .whenComplete(() {
          if (_animTarget == t) _animTarget = null;
        });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _hideBands();
    _sc.dispose();
    super.dispose();
  }

  // ---- 拖拽落点:分享 / 收藏 / 删除三条带走 overlay ----
  //
  // 不能把它们塞进胶片条自己的 Stack 里:一来会把画布顶上去(拖到一半整屏
  // 跳一下),二来 Stack 越界的子节点根本收不到命中测试,而 DragTarget
  // 认的就是命中测试。
  //
  // 也不能让它待在手指起始位置底下 —— 那样原地松手就触发,「得拖过去」这层
  // 保险等于没有。所以摆在胶片条**正上方**,且隔开 [_bandGap]:
  // 完全避开横向滚动那条轴,而那段距离就是防误触的全部依仗。

  OverlayEntry? _bands;

  void _showBands(String id) {
    if (_bands != null) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final ob = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || ob == null) return;
    final top = box.localToGlobal(Offset.zero, ancestor: ob).dy;
    const h = _bandH * _bandCount + _bandSpacing * (_bandCount - 1);
    final favorite = widget.isFavorite(id);
    _bands = OverlayEntry(
      builder: (_) => Positioned(
        left: _stripPadH,
        right: _stripPadH,
        top: top - h - _bandGap,
        height: h,
        child: _DropBands(
          favorite: favorite,
          onShare: _dropShare,
          onFavorite: _dropFavorite,
          onDelete: _dropDelete,
        ),
      ),
    );
    overlay.insert(_bands!);
  }

  void _hideBands() {
    _bands?.remove();
    _bands = null;
  }

  void _dropShare(String id) {
    Haptics.medium();
    widget.onShare(id);
  }

  void _dropFavorite(String id) {
    Haptics.medium();
    widget.onFavorite(id);
  }

  void _dropDelete(String id) {
    Haptics.medium();
    _vacated.add('r:$id');
    widget.onDelete(id);
  }

  /// 把选中缩略图滚到**视野中央**。位置按渲染同款公式推算(缩略图宽 +
  /// 容器 padding 4 + 分隔 8),不去量已构建的布局 —— ListView 视野外的项
  /// 根本没建出来,量不着。
  ///
  /// 居中而非"最小滚动量刚好露出来":后者在横滑连切时会让选中项一直贴着
  /// 边缘走(看不出前后还有几张),从展开页跳选一张远处的图时也只是刚好
  /// 蹭进屏幕。首尾几张自然贴边(clamp 到滚动范围),那是应该的。
  void _reveal() {
    if (!mounted || !_sc.hasClients) return;
    final jobId = widget.selectedJobId;
    final id = widget.selectedId;
    // 画布跟随的任务卡也算选中项;任务卡都排在头部,历史图要把它们让出来
    final key = jobId != null ? 'j:$jobId' : (id == null ? null : 'r:$id');
    if (key == null) return;
    // 按进出动画走完之后的排布算:影子不占位,长出中的按整格
    var x = _stripPadH;
    for (final e in _entries()) {
      if (e.ghost) continue;
      if (e.key == key) {
        _animateTo(x + e.slot / 2 - _sc.position.viewportDimension / 2);
        return;
      }
      x += e.slot + _thumbGap;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final display = _display = _entries();
    final index = {for (var i = 0; i < display.length; i++) display[i].key: i};
    return Docked(
      child: Material(
        color: context.raisedFill(scheme.surface),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            height: _thumbSlotH,
            child: Stack(
              children: [
                Positioned.fill(
                  // 每条宽度按公式给定(不靠量):进出后位置立刻是对的,
                  // 补回滚动位置的位移和 _reveal 算的落点才对得上实际布局
                  child: ListView.builder(
                    controller: _sc,
                    scrollDirection: Axis.horizontal,
                    // 每条的宽里带着后面那道分隔,右边距相应减掉
                    padding: const EdgeInsets.only(
                      left: _stripPadH,
                      right: _stripPadH - _thumbGap,
                    ),
                    itemCount: display.length,
                    itemExtentBuilder: (i, _) =>
                        i < display.length ? _extentOf(display[i]) : null,
                    findChildIndexCallback: (key) =>
                        index[(key as ValueKey<String>).value],
                    itemBuilder: (context, i) {
                      final e = display[i];
                      final job = e.job;
                      final result = e.result;
                      final Widget thumb = job != null
                          ? _GenThumb(
                              job: job,
                              active:
                                  !e.ghost && job.id == widget.selectedJobId,
                              onTap: () => widget.onSelectJob?.call(job.id),
                            )
                          : _FilmThumb(
                              result: result!,
                              vacant: e.vacant,
                              selected:
                                  !e.ghost &&
                                  result.id == widget.selectedId &&
                                  widget.selectedJobId == null,
                              onTap: () => widget.onSelect(result.id),
                              onDragStart: () => _showBands(result.id),
                              onDragEnd: _hideBands,
                            );
                      // 进出时按比例裁宽、淡入淡出。结构不随状态变,影子与原条目
                      // 同一个键,条目内部状态(选中环过渡、拖拽)不会被重建打断
                      return ClipRect(
                        key: ValueKey(e.key),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Opacity(
                            opacity: _factor(e.key).clamp(0.0, 1.0),
                            child: IgnorePointer(
                              ignoring: e.ghost,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: _thumbGap,
                                ),
                                child: thumb,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 悬浮「›」展开全部:压在缩略图之上,靠投影拉开层次
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: _moreRight,
                  child: Center(
                    child: Material(
                      color: context.raisedFill(scheme.surfaceContainerHighest),
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: .45),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => showGalleryGrid(context),
                        child: SizedBox(
                          width: _moreSize,
                          height: _moreSize,
                          child: Icon(
                            Icons.chevron_right,
                            size: 24,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _aspectOf(int w, int h) => (w > 0 && h > 0) ? w / h : 1.0;

double _resultAspect(ResultImage r) => _aspectOf(r.width, r.height);

/// 胶片条上的一条:在跑的任务或历史图。[ghost] = 刚移除、正在收起的影子。
class _Entry {
  const _Entry(
    this.key,
    this.slot, {
    this.job,
    this.result,
    this.ghost = false,
    this.vacant = false,
  });

  final String key;

  /// 缩略图占位宽(含内衬与边框),不含分隔。
  final double slot;
  final GenJob? job;
  final ResultImage? result;
  final bool ghost;

  /// 影子画成空位(拖走删掉的那张)。
  final bool vacant;

  _Entry asGhost({required bool vacant}) =>
      _Entry(key, slot, job: job, result: result, ghost: true, vacant: vacant);
}

/// 收起中的影子:比例从 [from] 收到 0。[before] = 排在哪条前面,null 为末尾。
class _Leaving {
  _Leaving(this.entry, this.from);

  final _Entry entry;
  final double from;
  String? before;
  double t = 0;
}

/// 胶片条的滚动位置:头部进出条目时,在同一次布局里把位移补回来。
///
/// 补在 [correctForNewDimensions] 里:那时新内容已经排好、这一帧还没画。
/// 帧后再 jumpTo 会先画出一帧错位。
class _StripPosition extends ScrollPositionWithSingleContext {
  _StripPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double _shift = 0;

  /// 已登记、还没补上的位移。
  double get pendingShift => _shift;

  void shift(double delta) {
    _shift += delta;
    correctBy(0); // 让下一次布局一定走到 correctForNewDimensions
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    if (_shift == 0) {
      return super.correctForNewDimensions(oldPosition, newPosition);
    }
    final to = (pixels + _shift).clamp(
      newPosition.minScrollExtent,
      newPosition.maxScrollExtent,
    );
    _shift = 0;
    if (to == pixels) return true;
    correctPixels(to);
    return false;
  }
}

class _StripController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _StripPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

/// 在跑的任务卡:逐帧预览(未到帧显斜纹)+ 底部细进度条。
/// 点卡片让画布跟随这条;active 时亮选中环。取消在画布的进度胶囊上,不在这儿。
class _GenThumb extends StatelessWidget {
  const _GenThumb({required this.job, required this.active, this.onTap});

  final GenJob job;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    const h = _thumbH;
    final aspect = _aspectOf(job.width, job.height);
    final w = _thumbImgW(aspect);
    final preview = job.preview;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? scheme.primary : Colors.transparent,
            width: _thumbBorder,
          ),
        ),
        padding: const EdgeInsets.all(_thumbPad),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (preview != null)
                  Image.memory(
                    preview,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                else
                  StripeThumb(width: w, height: h, radius: 0),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: job.progress, // null = 准备中,不确定动画
                      backgroundColor: Colors.black.withValues(alpha: .25),
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilmThumb extends StatelessWidget {
  const _FilmThumb({
    required this.result,
    required this.selected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragEnd,
    this.vacant = false,
  });

  final ResultImage result;
  final bool selected;

  /// 只画空位:拖走删掉之后收起的那一下。
  final bool vacant;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final w = _thumbImgW(_resultAspect(result));
    if (vacant) return _vacantSlot(scheme, w);
    return Draggable<String>(
      data: result.id,
      // affinity 竖直 = 只用 VerticalDragGestureRecognizer 进竞技场:一上来就
      // 横移的归列表滚动,往上走的才算拿起。两条手势按轴分,天然不打架。
      //
      // axis 竖直 = 拖起来的那张只跟着上下走。既呼应「上滑」这个动作,
      // 也免得手一歪飘出落点的横向范围。
      affinity: Axis.vertical,
      axis: Axis.vertical,
      onDragStarted: () {
        Haptics.medium();
        onDragStart();
      },
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, _) => onDragEnd(),
      feedback: _feedback(w),
      // 占位保住原来的宽度,否则拿起一张整条会往左塌一截,
      // 拖回来时又弹回去 —— 拖到哪儿了就更看不清了
      childWhenDragging: _vacantSlot(scheme, w),
      child: GestureDetector(
        onTap: onTap,
        child: _shell(
          scheme,
          selected: selected,
          child: Stack(
            children: [
              ResultThumb(
                result: result,
                width: w,
                height: _thumbH,
                radius: 10,
              ),
              if (result.badge != ResultBadge.none)
                Positioned(
                  left: 4,
                  top: 4,
                  child: ResultBadgeChip(badge: result.badge),
                ),
              if (result.saved)
                const Positioned(right: 4, top: 4, child: SavedMark(size: 14)),
            ],
          ),
        ),
      ),
    );
  }

  /// 拿走后的空位。
  Widget _vacantSlot(ColorScheme scheme, double w) => _shell(
    scheme,
    selected: false,
    child: Container(
      width: w,
      height: _thumbH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: scheme.surfaceContainerHighest,
      ),
    ),
  );

  /// 选中环 + 内衬那层壳。**拿走后的占位也走这层** —— 两边尺寸必须同源,
  /// 否则拖起来的那一刻整条会抖一下。
  Widget _shell(
    ColorScheme scheme, {
    required bool selected,
    required Widget child,
  }) => AnimatedContainer(
    duration: Motion.fast,
    curve: Motion.standard,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: selected ? scheme.primary : Colors.transparent,
        width: _thumbBorder,
      ),
    ),
    padding: const EdgeInsets.all(_thumbPad),
    child: child,
  );

  /// 跟手的那张:略放大 + 投影,看着像从条里被拎了出来。
  /// feedback 画在 overlay 里,不在 Material 树下,所以自带一层。
  Widget _feedback(double w) => Material(
    color: Colors.transparent,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ResultThumb(
        result: result,
        width: w * 1.12,
        height: _thumbH * 1.12,
        radius: 11,
      ),
    ),
  );
}

/// 上滑后浮出的落点:上删除、中收藏、下分享(为什么这么排见 [_bandGap]),只在
/// 拖拽期间存在。悬停到哪条,哪条就亮起并把文案换成「松手 ×」—— 得先让人看见
/// 自己正停在哪儿。
class _DropBands extends StatefulWidget {
  const _DropBands({
    required this.favorite,
    required this.onShare,
    required this.onFavorite,
    required this.onDelete,
  });

  /// 拿起的这张已经收藏了:收藏那条改成「取消收藏」。
  final bool favorite;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onFavorite;
  final ValueChanged<String> onDelete;

  @override
  State<_DropBands> createState() => _DropBandsState();
}

class _DropBandsState extends State<_DropBands>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.medium)
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      // 从胶片条那头升上来,而不是凭空出现 —— 让人看出它们是被这次拿起
      // 唤出来的,不是本来就在
      child: SlideTransition(
        position: _c.drive(
          Tween(
            begin: const Offset(0, .6),
            end: Offset.zero,
          ).chain(CurveTween(curve: Motion.emphasized)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DropBand(
              icon: Icons.delete_outline,
              activeIcon: Icons.delete_forever,
              label: '拖到这里删除',
              activeLabel: '松手删除',
              destructive: true,
              onAccept: widget.onDelete,
            ),
            const SizedBox(height: _bandSpacing),
            _DropBand(
              icon: widget.favorite ? Icons.favorite : Icons.favorite_border,
              activeIcon: widget.favorite
                  ? Icons.favorite_border
                  : Icons.favorite,
              label: widget.favorite ? '拖到这里取消收藏' : '拖到这里收藏',
              activeLabel: widget.favorite ? '松手取消收藏' : '松手收藏',
              destructive: false,
              onAccept: widget.onFavorite,
            ),
            const SizedBox(height: _bandSpacing),
            _DropBand(
              icon: Icons.ios_share,
              label: '拖到这里分享',
              activeLabel: '松手分享',
              destructive: false,
              onAccept: widget.onShare,
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条落点。[destructive] 的悬停色走 error,否则走 primary。
class _DropBand extends StatelessWidget {
  const _DropBand({
    required this.icon,
    this.activeIcon,
    required this.label,
    required this.activeLabel,
    required this.destructive,
    required this.onAccept,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final String activeLabel;
  final bool destructive;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SizedBox(
      height: _bandH,
      child: DragTarget<String>(
        onAcceptWithDetails: (d) => onAccept(d.data),
        builder: (context, cand, _) {
          final on = cand.isNotEmpty;
          final bg = !on
              ? context.raisedFill(scheme.surfaceContainerHighest)
              : destructive
              ? scheme.errorContainer
              : context.solidFill(scheme.primaryContainer);
          final fg = !on
              ? scheme.onSurfaceVariant
              : destructive
              ? scheme.onErrorContainer
              : context.onSolidFill(scheme.onPrimaryContainer);
          final edge = !on
              ? Colors.transparent
              : destructive
              ? scheme.error
              : scheme.primary;
          return Material(
            color: bg,
            elevation: on ? 8 : 3,
            shadowColor: Colors.black.withValues(alpha: .45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: edge, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(on ? (activeIcon ?? icon) : icon, size: 22, color: fg),
                const SizedBox(width: 8),
                Text(
                  on ? activeLabel : label,
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

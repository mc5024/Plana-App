import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/store/app_stores.dart';
import '../../core/theme/app_theme.dart';
import '../generate/generation_controller.dart';
import '../generate/widgets/common.dart' show hintSnack;
import '../inpaint/inpaint_overlay.dart';
import 'gallery_state.dart';
import 'models.dart';
import 'save_settings.dart';
import 'share_pipeline.dart';
import 'widgets/film_strip.dart';
import 'widgets/result_canvas.dart';

/// 图库页:上方结果画布(大图 + 操作轨 + seed)、下方历史胶片条。
/// 生成链路产出的结果落在这里查看与二次操作。
/// 重绘会话期间 keep-alive:切去其他 tab 再回来,编辑面板(遮罩等)原样保留。
///
/// 画布是一条真正的 PageView(一页一张,与胶片条同序:0=最新在左,左滑看更旧),
/// 图跟手走、松手吸附 —— 以前那套「raw pointer 认快滑 + 自己放一段推移动画」的
/// 假翻页已删。shell 的 tab 横滑同时关掉了,横向手势这一层现在归画布独占。
class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

/// 图库的一次性引导。提示过就记在 `settings.json`,不再打扰。
///
/// **一次只提一条**:hintSnack 是全局单例,后一条会把前一条顶掉;而且一进
/// 图库连弹两条本身就很吵。按下面的顺序挑第一条没提过的,剩下的等下次进
/// 图库(下次冷启动)再说 —— 这两个手势都藏得深,不说没人发现,但也不急在
/// 同一秒说完。
const _kGalleryHints = <({String key, String text, IconData icon})>[
  (
    key: 'hint_save_longpress',
    text: '长按「保存」可进入下载设置',
    icon: Icons.download_outlined,
  ),
  (
    key: 'hint_strip_swipe',
    text: '底部胶片条里的图,向上滑可以分享或删除',
    icon: Icons.swipe_up_outlined,
  ),
];

class _GalleryPageState extends ConsumerState<GalleryPage>
    with AutomaticKeepAliveClientMixin {
  bool _keep = false;
  bool _hintChecked = false;

  /// 最近一次成功显示的原图字节。切到尚未读盘的老图时先继续画它,
  /// 避免空窗期露占位;新图解码完由 gaplessPlayback 无缝换掉。
  Uint8List? _lastShown;

  /// 冷启动直接停在上次选中的那一页(索引查不到就落到最新一张)。
  late final int _initialPage = () {
    final s = ref.read(galleryProvider);
    final i = s.results.indexWhere((r) => r.id == s.selectedId);
    return i < 0 ? 0 : i;
  }();
  late final PageController _pv = PageController(initialPage: _initialPage);

  /// PageView **实际**停的页码,只由 [_onPageChanged] 写。build 里拿它和选中项
  /// 索引比对:不等 = 有人从外面改了选中(点胶片条/网格跳选、新图前插、删图后
  /// 索引平移),得把页跳过去。拖动切页来的两者天生一致,不会进这条路。
  int _pageAt = 0;

  /// 已排队等 post-frame 生效的跳页目标(去重,免得每帧都排一发)。
  int? _jumpTo;

  /// 当前这次滚动是不是手拖出来的(程序 jumpToPage 不算)。
  /// 只服务顶图层的抑制:手拖期间不许盖图,见 build 里 bridge 的注释。
  bool _userDrag = false;

  @override
  void initState() {
    super.initState();
    _pageAt = _initialPage;
  }

  @override
  void dispose() {
    _pv.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => _keep;

  /// 跳页只能在帧后做(build 里动 controller 会打断本帧布局)。空窗这一两帧
  /// 由 build 里的「顶图层」盖着,看不出断层。
  void _requestPage(int i) {
    if (_jumpTo == i) return;
    _jumpTo = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final t = _jumpTo;
      _jumpTo = null;
      if (!mounted || t == null) return;
      // jumpToPage 会同步派 ScrollUpdate → onPageChanged 把 _pageAt 校正过来
      if (_pv.hasClients && (_pv.page?.round() ?? -1) != t) _pv.jumpToPage(t);
      // 兜底:目标页恰好已经是当前页(列表裁剪把页码挤过去了),或控制器还没
      // 挂上 —— 这两种都不会有 onPageChanged,得自己把 _pageAt 收平,
      // 否则 desynced 永远为真,顶图层就一直盖着撤不掉。
      if (_pageAt != t) setState(() => _pageAt = t);
    });
  }

  void _onPageChanged(int i) {
    // 程序 jumpToPage 也会走这里,且此时选中项往往已经是目标 —— select 会早退
    // 不触发重建,所以 _pageAt 必须自己 setState,否则顶图层撤不掉。
    if (_pageAt != i) setState(() => _pageAt = i);
    final results = ref.read(galleryProvider).results;
    if (i < 0 || i >= results.length) return;
    ref.read(galleryProvider.notifier).select(results[i].id);
  }

  bool _onScroll(ScrollNotification n) {
    // 拖动全程(含松手后的吸附)标志位都是真:ScrollStart 只在拖动起手时发一次,
    // 惯性吸附不会再发,所以 ScrollEnd 之前一直有效。
    if (n is ScrollStartNotification) {
      _userDrag = n.dragDetails != null;
    } else if (n is ScrollEndNotification) {
      _userDrag = false;
    }
    return false;
  }

  /// 胶片条上滑分享:单张,与网格弹层那条同一套管线(见 [prepareShareFiles])。
  Future<void> _shareOne(String id) async {
    final r = ref
        .read(galleryProvider)
        .results
        .where((e) => e.id == id)
        .firstOrNull;
    if (r == null) return;
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    final prep = await prepareShareFiles(
      [r],
      store: ref.read(appStoresProvider).gallery,
      settings: settings,
    );
    if (!mounted) return;
    if (prep.files.isEmpty) {
      hintSnack(context, '没有可分享的图片', icon: Icons.error_outline);
      return;
    }
    await SharePlus.instance.share(ShareParams(files: prep.files));
  }

  /// 图库里有图了 → 提一条还没提过的引导(见 [_kGalleryHints])。
  /// 每进程只判一次(_hintChecked),真正的"提过没"以落盘的标记为准。
  void _maybeHint(bool hasImage) {
    if (_hintChecked || !hasImage) return;
    _hintChecked = true;
    final prefs = ref.read(prefsStoreProvider);
    for (final h in _kGalleryHints) {
      if (prefs.get(h.key) != null) continue;
      prefs.write(key: h.key, value: '1');
      // build 里不能直接弹 overlay,推到帧后
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) hintSnack(context, h.text, icon: h.icon);
      });
      return; // 一次一条
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(galleryProvider);
    final gen = ref.watch(genStatusProvider);
    final inpaint = ref.watch(inpaintSessionProvider);
    final selected = state.selected;

    // 重绘会话开/关时更新 keep-alive(仅编辑期间常驻,平时随 PageView 回收)
    final keep = inpaint != null;
    if (keep != _keep) {
      _keep = keep;
      updateKeepAlive();
    }

    _maybeHint(!state.isEmpty);

    if (!gen.busy && state.isEmpty && inpaint == null) {
      return const _EmptyGallery();
    }

    // 画布跟随哪条任务由任务池说了算(GenPool.selectedId):
    // 点历史缩略图 = 解除跟随(任务继续后台跑,进度在胶片条的卡上),
    // 点任务卡 = 跟随那一条。gen 就是被跟随那条的扁平视图,没跟随时它 idle。
    final pool = ref.watch(generationProvider);
    final showGen = gen.busy;

    // 选中图字节不在内存(重启水合/RAM 减负)时按需从盘读。
    var selBytes = selected?.bytes;
    if (selBytes == null && selected != null) {
      selBytes = ref.watch(galleryImageProvider(selected.id)).value;
    }
    // 老图重启后 bytes 不在内存,要异步读原图;这段空窗以前掉回斜纹网格,
    // 就是「老图切换闪一下」的来源。**不能垫缩略图** —— 缩略图是 cover 方形
    // 裁切(256²),拉到全画布会变形又变回去,比斜纹更晃眼(实测反馈)。
    // 改为留住上一张已显示的原图,直到新图解码完成,视觉上完全无缝。
    if (selBytes != null) _lastShown = selBytes;
    final showChrome = !showGen && selected != null;

    final results = state.results;
    final selIdx = selected == null
        ? -1
        : results.indexWhere((r) => r.id == selected.id);

    // 左右邻页预取(不在内存的起读盘)+ 预解码(同引用字节命中 ImageCache)。
    // 拖到一半才起读盘的话,滑进来的是个空画框 —— 邻页必须提前备好。
    for (final k in [selIdx - 1, selIdx + 1]) {
      if (k < 0 || k >= results.length) continue;
      final nb =
          results[k].bytes ??
          ref.watch(galleryImageProvider(results[k].id)).value;
      if (nb != null) precacheImage(MemoryImage(nb), context);
    }

    // 选中项被外面改了(点胶片条/网格跳选、新图前插、删图平移)→ 排一次跳页。
    final desynced = selIdx >= 0 && selIdx != _pageAt;
    if (desynced) _requestPage(selIdx);

    // 顶图层:页码还没跟上的那一两帧、或老图字节还没读上来时,拿一张盖在
    // 分页画布上顶住 —— 优先当前选中的真身,退而求其次是上一张已显示的。
    //
    // **手拖期间一律不盖**:拖到过半就发 onPageChanged,此刻若入场页的字节碰巧
    // 还在读盘,盖上去的是上一张,等于把跟手的半页画面糊死,比露一格空画框糟得多。
    // 拖动时露空画框也几乎见不着 —— 邻页在上面预取过了。
    final bridge = !showGen && !_userDrag && (desynced || selBytes == null)
        ? (selBytes ?? _lastShown)
        : null;

    // 缩放态把翻页物理整个撤掉,横向拖动让回 InteractiveViewer 做平移。
    final zoomed = ref.watch(galleryZoomedProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 分页画布:一页一张结果,图跟手走、松手吸附。
                  // 未缩放时横向拖动归 PageView(触摸 slop 18 先于
                  // InteractiveViewer 的 pan slop 36 判定成立,竞技场稳赢);
                  // 缩放后 physics 撤成 NeverScrollable,Scrollable 干脆不装
                  // 拖动识别器,横向拖动整个让回去做平移。
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: PageView.builder(
                      controller: _pv,
                      physics: zoomed
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: results.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (_, i) => _ResultPage(result: results[i]),
                    ),
                  ),
                  // 顶图层:跳页空窗 / 老图还没读上来时顶住,不露空画框
                  if (bridge != null)
                    IgnorePointer(
                      child: GalleryImageLayer(
                        bytes: bridge,
                        width: selected?.width ?? 0,
                        height: selected?.height ?? 0,
                      ),
                    ),
                  // 生成视角:预览层盖住分页画布。预览没有邻居语义,不参与翻页;
                  // 它自带 opaque 命中行为,底下的 PageView 拿不到指针,不会误翻。
                  // 撤层那一帧,page 0 画的是同一份终帧字节(入库与预览同引用,
                  // ImageCache 直接命中),所以「生成中 → 出图」照旧不闪。
                  if (showGen)
                    // 局部重绘:发出去的只是那块裁切区,流帧本身是一小张。拿整
                    // 张原图垫底、把流帧盖回原位,画面才和入库结果(贴回后的整图)
                    // 是同一个东西 —— 否则生成中看一张小图、出图那一刻啪地换成
                    // 整图。整图生成时 pasteUnder 为空,走原来那条。
                    _ZoomableImage(
                      bytes: gen.pasteUnder ?? gen.preview ?? selBytes,
                      width: gen.pasteUnder != null
                          ? (selected?.width ?? gen.width)
                          : gen.width,
                      height: gen.pasteUnder != null
                          ? (selected?.height ?? gen.height)
                          : gen.height,
                      overlay: gen.pasteUnder == null ? null : gen.preview,
                      overlayAt: gen.pasteAt,
                    ),
                  // 结果操作层:非生成态淡入,生成时淡出
                  AnimatedOpacity(
                    duration: Motion.medium,
                    curve: Motion.standard,
                    opacity: showChrome ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showChrome,
                      child: selected != null
                          ? ResultChrome(result: selected)
                          : const SizedBox.shrink(),
                    ),
                  ),
                  // 进度胶囊:渐显+上滑进 / 渐隐+下滑出
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 22,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: Motion.medium,
                        switchInCurve: Motion.emphasized,
                        switchOutCurve: Motion.standard,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.5),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        // 切看历史图时胶囊让位(进度看占位卡),不挡图
                        child: showGen
                            ? ProgressPill(
                                key: const ValueKey('pill'),
                                status: gen,
                                // 取消**跟随的这一条**,不动循环/队列 ——
                                // 那是「停这一条」,不是「别再续了」(后者在
                                // 创作页那颗生成按钮内部的停止区)。
                                onCancel: () {
                                  final id = pool.selectedId;
                                  if (id != null) {
                                    ref
                                        .read(generationProvider.notifier)
                                        .cancelJob(id);
                                  }
                                },
                              )
                            : const SizedBox.shrink(key: ValueKey('nopill')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FilmStrip(
              results: state.results,
              selectedId: state.selectedId,
              onSelect: (id) {
                // 生成中点历史图 = 解除跟随(任务继续);平时就是普通选图
                ref.read(generationProvider.notifier).select(null);
                ref.read(galleryProvider.notifier).select(id);
              },
              onShare: _shareOne,
              onDelete: (id) =>
                  ref.read(galleryProvider.notifier).deleteResults([id]),
              jobs: pool.newestFirst,
              selectedJobId: pool.selectedId,
              onSelectJob: (id) =>
                  ref.read(generationProvider.notifier).select(id),
            ),
          ],
        ),
        // 重绘编辑面板:原地切入覆盖(出入场动画由 overlay 自己编排,
        // 收起动画结束后 session 置空、此层卸载)
        if (inpaint != null)
          InpaintOverlay(key: ObjectKey(inpaint), session: inpaint),
      ],
    );
  }
}

/// 分页画布的一页:一张结果大图。字节不在内存(重启水合/RAM 减负)时按需读盘,
/// 读到之前画空画框 —— 外层还有顶图层兜着,正常翻页看不到这一格。
class _ResultPage extends ConsumerWidget {
  const _ResultPage({required this.result});

  final ResultImage result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes =
        result.bytes ?? ref.watch(galleryImageProvider(result.id)).value;
    // 按住对比只作用在**当前这张**上:PageView 会把左右邻页也建出来,
    // 不判一下的话邻页也跟着换图(看不见,但白解码)。
    final selected = ref.watch(galleryProvider).selectedId == result.id;
    return _ZoomableImage(
      bytes: bytes,
      width: result.width,
      height: result.height,
      compare: selected ? ref.watch(compareBytesProvider) : null,
    );
  }
}

/// 可缩放大图:双指缩放/拖动 + 双击放大(以双击点为焦点)/还原。
///
/// 缩放状态经 [galleryZoomedProvider] 报给画布,由它撤掉 PageView 的翻页物理。
/// 这里**不再碰横滑** —— 翻页是 PageView 的事,未缩放时它凭更小的触摸 slop
/// 稳赢竞技场;从前那套「手指一碰就锁 + 自己认快滑」的 raw pointer 补丁是给
/// shell 级横滑擦屁股用的,shell 横滑关掉后连同快滑识别一起删了。
///
/// 每页各自持有变换控制器,滑走即销毁 —— 「换图回到 fit」不用再写重置逻辑。
class _ZoomableImage extends ConsumerStatefulWidget {
  const _ZoomableImage({
    required this.bytes,
    required this.width,
    required this.height,
    this.overlay,
    this.overlayAt,
    this.compare,
  });

  final Uint8List? bytes;
  final int width;
  final int height;

  /// 盖在底图上的一小张(局部重绘的流帧),[overlayAt] 是它在**原图坐标**里的位置。
  /// 两个都为空 = 普通生成,只画底图。
  final Uint8List? overlay;
  final ({int x, int y, int w, int h})? overlayAt;

  /// 「按住对比」要盖的重绘前原图;满幅,和底图同一个盒子。
  ///
  /// **必须画在这里面**,不能在外层 Stack 上另起一层:缩放/平移是
  /// InteractiveViewer 做的,外层那层不吃这个变换 —— 图放大之后一按对比,
  /// 屏幕上就是一张放大的和一张原大的在比。
  final Uint8List? compare;

  @override
  ConsumerState<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends ConsumerState<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );
  late final CurvedAnimation _zoomCurve = CurvedAnimation(
    parent: _ac,
    curve: Motion.emphasized,
  );
  Animation<Matrix4>? _zoomAnim;
  Offset? _doubleTapPos;

  double get _scale => _tc.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    // 缩放态如实上报(双向):捏大即锁翻页,捏回 1 即放开。
    // 1.02 的余量是给浮点残差留的,别改成 == 1。
    _tc.addListener(
      () => ref.read(galleryZoomedProvider.notifier).set(_scale > 1.02),
    );
    _ac.addListener(() {
      final a = _zoomAnim;
      if (a != null) _tc.value = a.value;
    });
  }

  @override
  void dispose() {
    // 离屏销毁时放开翻页锁;dispose 内不能同步改 provider → microtask
    final notifier = ref.read(galleryZoomedProvider.notifier);
    Future.microtask(() => notifier.set(false));
    _zoomCurve.dispose();
    _ac.dispose();
    _tc.dispose();
    super.dispose();
  }

  /// 双击:已放大 → 动画还原 fit;否则以双击点为焦点放大 2.5×。
  void _onDoubleTap() {
    final Matrix4 target;
    if (_scale > 1.3) {
      target = Matrix4.identity();
    } else {
      final f = _doubleTapPos;
      if (f == null) return;
      const k = 2.5;
      target = Matrix4.identity()
        ..translateByDouble(f.dx, f.dy, 0, 1)
        ..scaleByDouble(k, k, 1, 1)
        ..translateByDouble(-f.dx, -f.dy, 0, 1);
    }
    _zoomAnim = Matrix4Tween(begin: _tc.value, end: target).animate(_zoomCurve);
    _ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        maxScale: 10,
        child: _layer(),
      ),
    );
  }
}

/// 底图 + 可选的贴回覆盖层。覆盖层按**原图坐标**定位,所以要跟底图共用同一个
/// 等比盒子 —— 用 AspectRatio + FractionallySizedBox 换算,不必自己量像素。
extension on _ZoomableImageState {
  Widget _layer() {
    final over = widget.overlay;
    final at = widget.overlayAt;
    final cmp = widget.compare;
    // 对比图和底图共用同一套布局参数(同一个盒子、同样 contain),
    // 所以叠上去必然严丝合缝,不用自己算位置。
    final base = cmp != null
        ? GalleryImageLayer(
            bytes: cmp,
            width: widget.width,
            height: widget.height,
          )
        : GalleryImageLayer(
            bytes: widget.bytes,
            width: widget.width,
            height: widget.height,
          );
    if (over == null || at == null || widget.width <= 0 || widget.height <= 0) {
      return base;
    }
    final w = widget.width.toDouble(), h = widget.height.toDouble();
    return Stack(
      fit: StackFit.passthrough,
      children: [
        base,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (_, c) {
              // 图在盒子里是 contain 的,先算出它实际占的矩形
              final scale = (c.maxWidth / w) < (c.maxHeight / h)
                  ? c.maxWidth / w
                  : c.maxHeight / h;
              final dw = w * scale, dh = h * scale;
              final dx = (c.maxWidth - dw) / 2, dy = (c.maxHeight - dh) / 2;
              return Stack(
                children: [
                  Positioned(
                    left: dx + at.x * scale,
                    top: dy + at.y * scale,
                    width: at.w * scale,
                    height: at.h * scale,
                    child: Image.memory(
                      over,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '还没有作品',
            style: context.texts.titleMedium!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '去「创作」生成第一张',
            style: context.texts.bodySmall!.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

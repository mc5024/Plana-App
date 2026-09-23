import '../gallery/albums/album_state.dart';
import '../gallery/albums/album_ui.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/param_input.dart';
import '../generate/gen_modules.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart';
import '../generate/res_rules.dart' show kFreePixelThreshold;
import '../generate/widgets/common.dart' show hintSnack;
import '../gallery/gallery_state.dart';
import '../gallery/models.dart' show ResultBadge;
import '../shell/shell_state.dart';
import 'censor_detect.dart';
import 'censor_infer.dart';
import 'censor_ops.dart';
import 'inpaint_ops.dart';
import '../../core/util/haptics.dart';

/// 内容层功能色(画在图片上,与 app 主题无关):
/// 遮罩紫与 web 一致;裁切青取深档保证浅色底上可读。
const _maskPurple = Color(0xFFA855F7);
const _maskFill = Color(0x8CA855F7); // 遮罩填充 ~55% 紫
// 局部框用 app 主题金(scheme.primary),不硬编码 web 色值。

/// NAI img2img/inpaint 像素上限(与 img2imgResolution 一致)。
const _maxSendPixels = 1024 * 3072;

/// 局部框单边上限(框即发送尺寸)。
const _cropMaxSide = 1024;

/// 一次重绘编辑会话:进入编辑器所需的底图。
///
/// **不带参数快照**:prompt/角色/vibe/步数等一律由面板现读创作页
/// (见 [_InpaintOverlayState._liveInput])。曾经在这儿存过一份打开时的
/// 快照,但图库页在编辑期间 keep-alive,用户切去创作页改完再切回来,
/// 费用和实际发送都还停在旧值 —— 冻结的那份就是漂移的来源。
class InpaintSession {
  const InpaintSession({required this.imageBytes, this.sourceId});

  final Uint8List imageBytes;

  /// 源图的图库 id。非空时蒙版按这张图记忆:进来恢复、离开保存。
  /// 从创作页等无图库归属的入口进来时为 null,蒙版仅本次会话有效。
  final String? sourceId;
}

/// 当前重绘会话;非空时图库页原地切入编辑面板(shell 同时锁 tab 切换)。
final inpaintSessionProvider =
    NotifierProvider<InpaintSessionNotifier, InpaintSession?>(
      InpaintSessionNotifier.new,
    );

class InpaintSessionNotifier extends Notifier<InpaintSession?> {
  @override
  InpaintSession? build() => null;

  void open({required Uint8List imageBytes, String? sourceId}) {
    state = InpaintSession(imageBytes: imageBytes, sourceId: sourceId);
  }

  void close() => state = null;
}

enum _Tool { brush, eraser }

/// 顶栏三档。**共用同一张遮罩和同一套涂抹手势** —— 涂一次,既可以送去重绘,
/// 也可以就地打码,不必退出面板换个工具重涂一遍。
///
/// 重绘/扩图是「攒任务回创作页生成」,打码是**本地即时出图**(不走网络、不扣点),
/// 所以只有 CTA 那一步分岔,前面的交互完全一样。
enum _Mode { paint, expand, censor }

/// 偏位套杆:手指把手与笔刷光标的屏幕间距(手指不挡涂抹点)。
const _assistGapPx = 110.0;

enum _SliderTarget { brush, strength, block }

enum _ExpandHandle { top, bottom, left, right }

/// 重绘编辑面板:嵌在图库页 Stack 顶层原地切入(非路由页)。
/// 涂抹遮罩(8×8 网格)→ 整图/局部 infill;入场=整层渐显+顶栏/面板对滑,
/// 关闭反向收起后由 [inpaintSessionProvider] 置空卸载。
class InpaintOverlay extends ConsumerStatefulWidget {
  const InpaintOverlay({super.key, required this.session});

  final InpaintSession session;

  @override
  ConsumerState<InpaintOverlay> createState() => _InpaintOverlayState();
}

class _InpaintOverlayState extends ConsumerState<InpaintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _ac,
    curve: Motion.emphasized,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _topSlide = Tween(
    begin: const Offset(0, -1.3),
    end: Offset.zero,
  ).animate(_curve);
  late final Animation<Offset> _panelSlide = Tween(
    begin: const Offset(0, 1.1),
    end: Offset.zero,
  ).animate(_curve);

  ui.Image? _img;
  MaskGrid? _grid;
  final List<Uint8List> _undo = [];

  _Tool _tool = _Tool.brush;
  bool _assist = false; // 偏位套杆:光标偏于触点上方,手指不挡涂抹点
  Offset? _fingerAt; // 偏位模式下手指把手位置(图坐标),painter 画杆用
  bool _cropMode = false;

  /// 用户手动关掉过局部框 —— 之后不再自作主张替他打开。
  bool _cropOptOut = false;

  /// 用户拉过边 —— 之后 [_autoCrop] 只扩不缩,不再把框收回遮罩大小。
  bool _cropResized = false;

  /// 正在拖的边/角:h 管左右(-1 左、1 右),v 管上下(-1 上、1 下),0 = 该方向不动。
  /// 角就是 h、v 都不为 0。
  ({int h, int v})? _cropDrag;
  IntRect? _cropStart;
  Offset? _cropDragFrom;
  IntRect? _crop; // 发送框(w/h 恒 64 倍数,单边 ≤ _cropMaxSide)
  double _brush = 50; // 笔刷直径(图像素),对齐 web 默认
  double _strength = 0.7;
  _SliderTarget? _slider;
  bool _showOriginal = false;
  bool _firing = false;

  /// 上一次算出的 Vibe 编码费(同 BottomActionBar._lastVibeFee):查询键一变
  /// 就从 loading 重来,取值 null 时沿用旧值,免得费用在参数连改时来回跳。

  _Mode _mode = _Mode.paint;
  bool get _expandMode => _mode == _Mode.expand;
  bool get _censorMode => _mode == _Mode.censor;

  // 打码(本地即时):样式 + 块大小(格,1 格 = 8px)。块大小进模式时按图长边
  // 给默认值 —— 写死像素的话同一档在 512 和 2048 的图上强度差四倍。
  CensorStyle _censorStyle = CensorStyle.mosaic;
  int _censorBlock = 4;
  int _censorColor = kCensorColorDefault; // 纯色档的填充色

  /// 整图马赛克底片:画布按遮罩格从这上面取样 = 所见即所得。
  ///
  /// 底片的块和最终出图对齐同一套网格,所以预览与结果逐像素一致 ——
  /// 不是"意思意思画个灰块"。块大小改动后重算,拖滑杆期间防抖。
  ui.Image? _censorPreview;
  int _censorPreviewBlock = -1;
  Timer? _censorDebounce;
  bool _detecting = false; // 自动识别进行中(按钮置灰,防连点)

  // 扩图模式(对齐 web:四向 padding 恒 64 倍数,发送=白底扩后画布)
  int _padL = 0, _padT = 0, _padR = 0, _padB = 0;
  _ExpandHandle? _expandDrag;
  int _expandStartPad = 0;
  Offset? _expandDragScreen; // 拖拽起点(屏幕坐标;pad 按屏幕位移/scale 折算)
  bool _expandDragMoved = false; // 未移动即抬手 = 点按把手,+64 一个单位
  // 扩图完成后旧图在新图中的位置:「按住对比」按位对齐,新增区露底=遮挡。
  // 生成搬走之后 _prevImg 恒为 null(没人再往里塞旧图),这一对现在是死的 ——
  // 「按住对比」不再出现。留着是为了下一步把对比接到图库那份结果上,别删。
  final Offset _prevImgOffset = Offset.zero;

  // 视图变换(图坐标 → 屏幕 = *scale + offset)
  double _scale = 1;
  double _fitScale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;
  (bool, int, int, int, int)? _fitKey; // 上次 fit 的输入(扩图态+四向 pad)

  // 手势瞬态
  bool _stroking = false;
  Offset? _pendingStroke; // 单指落下、尚未确认为涂抹的起点(防双指第一拍误涂)
  int _rawPointers = 0; // 画布上的真实手指数(raw 事件层)
  bool _pinchSession = false; // 本轮触摸出现过 ≥2 指:余波单指不算涂抹
  Offset? _lastPaint; // 最近落笔点(图坐标),兼作笔刷光标
  int _lastPointers = 0;
  double? _pzScale0;
  Offset? _pzOffset0;
  Offset? _pzFocal0;
  double _pzGesture0 = 1;

  int _rev = 0; // 遮罩版本号(驱动重绘与 rects 缓存)
  List<ui.Rect>? _rectsCache;
  int _rectsRev = -1;
  ui.Path? _outlineCache;
  int _outlineRev = -1;

  /// 遮罩只画轮廓、不铺实心。重绘完成时置位,再次动笔(涂/擦/撤销/清空)复位。
  ///
  /// 55% 实心紫盖住的正是唯一变化的那块 —— 出图后不摘掉就没法看结果,
  /// 「按住对比」也只有"前"那半是干净的。桌面端靠鼠标悬停临时摘遮罩,
  /// 触屏没有悬停,索性让它在该看结果的时候自己让开。
  bool _maskAsOutline = false;

  // 会话底图。以前每次重绘完成会就地换成新结果(连环重抽),生成搬到主按钮
  // 之后不再换 —— 想接着抽就在图库对新图重新进编辑器。
  late final Uint8List _currentBytes = widget.session.imageBytes;

  // 上一张底图(重绘前):「按住对比」按住时显示它,与当前结果对照
  ui.Image? _prevImg;

  // 流式预览(仅本编辑器发起的生成;_previewDst 非空 = 生成归属本会话):
  // 预览帧只画进发送目标区,并按发送时的遮罩快照 clip(遮罩区换新、其余原图)
  ui.Image? _previewImg;
  ui.Rect? _previewDst;
  List<ui.Rect>? _previewClip;

  @override
  void initState() {
    super.initState();
    // 上次的手感。同步取值,面板一开就是对的,不会先画一帧默认值再跳。
    final p = ref.read(inpaintPrefsProvider);
    _brush = p.brush;
    _strength = p.strength;
    _assist = p.assist;
    _censorStyle = p.censorStyle == 'solid'
        ? CensorStyle.solid
        : CensorStyle.mosaic;
    _censorColor = p.censorColor;
    // 模式要等图解出来才敢定(扩图要求 64 对齐、打码要按图算块大小),
    // 见 _decode 末尾的 _restoreMode。
    _decode();
  }

  /// 关面板时把手感存一次(滑杆每一跳都写等于每帧落一次盘)。
  void _savePrefs() => ref
      .read(inpaintPrefsProvider.notifier)
      .save(
        InpaintPrefs(
          brush: _brush,
          strength: _strength,
          assist: _assist,
          mode: switch (_mode) {
            _Mode.paint => 'paint',
            _Mode.expand => 'expand',
            _Mode.censor => 'censor',
          },
          censorStyle: _censorStyle == CensorStyle.solid ? 'solid' : 'mosaic',
          censorColor: _censorColor,
        ),
      );

  /// 恢复上次停留的档。**不走 [_setMode]** —— 那条路会弹提示、重置视角,
  /// 是给「用户点了 tab」用的;这里是开面板时的静默还原。
  ///
  /// 扩图对图有 64 对齐的硬要求,对不上就老实回落涂抹档,不弹提示打扰人。
  void _restoreMode(ui.Image img) {
    final want = ref.read(inpaintPrefsProvider).mode;
    if (want == 'expand') {
      if (img.width % 64 != 0 || img.height % 64 != 0) return;
      setState(() => _mode = _Mode.expand);
      return;
    }
    if (want != 'censor') return;
    _censorBlock = defaultCensorBlock(img.width, img.height);
    setState(() => _mode = _Mode.censor);
    unawaited(_rebuildCensorPreview());
    unawaited(warmUpCensorSession());
  }

  /// 先解码、图就位后才播入场动画:渐显第一帧画布即完整,避免
  /// 「底色/加载圈 → 图突现」的闪烁。解码失败直接退出会话(防锁死)。
  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.session.imageBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _img = frame.image;
        _grid = MaskGrid(frame.image.width, frame.image.height);
      });
      _restoreMask();
      _restoreMode(frame.image);
      unawaited(_ac.forward());
    } catch (_) {
      if (mounted) ref.read(inpaintSessionProvider.notifier).close();
    }
  }

  /// 从创作页那份遮罩恢复涂抹网格 —— 「回编辑器接着改」就靠它。
  ///
  /// 认人靠 [InpaintJob.sourceId]:不是同一张图就不恢复,免得把别人的遮罩套上来。
  /// 尺寸对不上(扩过图/裁过)时 [MaskGrid.decodeInto] 自己会拒,是第二道保险。
  void _restoreMask() {
    final grid = _grid;
    final job = ref.read(generateProvider).inpaint;
    final data = job?.grid;
    if (grid == null || data == null) return;
    if (job!.sourceId != widget.session.sourceId) return;
    if (grid.decodeInto(data)) setState(() => _rev++);
  }

  @override
  void dispose() {
    _censorDebounce?.cancel();
    _curve.dispose();
    _ac.dispose();
    _img?.dispose();
    _prevImg?.dispose();
    _previewImg?.dispose();
    _censorPreview?.dispose();
    super.dispose();
  }

  /// 反向收起后卸载(会话置空)。连点关闭安全:reverse 幂等。
  Future<void> _close() async {
    _savePrefs();
    await _ac.reverse();
    if (mounted) ref.read(inpaintSessionProvider.notifier).close();
  }

  /// 画布光标:涂抹中为最近落笔点;偏位模式下按住未动时也显示悬置光标。
  Offset? get _cursorPoint => _lastPaint ?? (_assist ? _pendingStroke : null);

  List<ui.Rect> get _maskRects {
    if (_rectsRev != _rev || _rectsCache == null) {
      _rectsCache = _grid?.displayRects() ?? const [];
      _rectsRev = _rev;
    }
    return _rectsCache!;
  }

  ui.Path? get _maskOutline {
    final g = _grid;
    if (g == null) return null;
    if (_outlineRev != _rev || _outlineCache == null) {
      _outlineCache = g.outlinePath();
      _outlineRev = _rev;
    }
    return _outlineCache;
  }

  /// 用户又动遮罩了 → 回到实心(正在涂哪儿要看得清清楚楚)。
  void _maskTouched() => _maskAsOutline = false;

  // ---------- 视图 ----------

  void _fit(Size size) {
    final img = _img;
    if (img == null) return;
    final key = (_expandMode, _padL, _padT, _padR, _padB);
    if (size == _viewport && key == _fitKey) return;
    // 用户未手动缩放(仍在 fit 档)时跟随新 fit 重新居中;
    // 手动缩放过则只更新 fitScale(缩放边界基准),不打断当前视角。
    final wasAtFit = size != _viewport || (_scale - _fitScale).abs() < 1e-9;
    _viewport = size;
    _fitKey = key;
    // 扩图模式:按「图+扩展区」总尺寸适配,四周留出拖拽把手与标签空间
    final cw = (img.width + _padL + _padR).toDouble();
    final ch = (img.height + _padT + _padB).toDouble();
    final margin = _expandMode ? 56.0 : 0.0;
    final availW = math.max(64.0, size.width - margin * 2);
    final availH = math.max(64.0, size.height - margin * 2);
    _fitScale = math.min(availW / cw, availH / ch);
    if (wasAtFit) {
      _scale = _fitScale;
      // 总区域(图坐标系 [-padL, imgW+padR]×[-padT, imgH+padB])居中
      final center = Offset(
        (img.width + _padR - _padL) / 2,
        (img.height + _padB - _padT) / 2,
      );
      _offset = Offset(size.width / 2, size.height / 2) - center * _scale;
    }
  }

  Offset _toImg(Offset local) => (local - _offset) / _scale;

  // ---------- 笔画 ----------

  void _pushUndo() {
    if (_undo.length >= 20) _undo.removeAt(0);
    _undo.add(Uint8List.fromList(_grid!.cells));
  }

  void _beginStroke(Offset p) {
    _pushUndo();
    _stroking = true;
    _grid!.paintDot(p.dx, p.dy, _brush, erase: _tool == _Tool.eraser);
    setState(() {
      _lastPaint = p;
      _rev++;
      _maskTouched();
      _slider = null; // 落笔即收浮动滑杆,给画布让位
    });
  }

  void _strokeTo(Offset p) {
    final from = _lastPaint;
    if (from == null) return;
    _grid!.paintLine(from, p, _brush, erase: _tool == _Tool.eraser);
    setState(() {
      _lastPaint = p;
      _rev++;
    });
  }

  /// 工具钮点击:未选中先选中;已选中的画笔再点切换偏位套杆模式
  /// (橡皮再点不动作;偏位对画笔/橡皮涂抹都生效)。
  void _tapTool(_Tool t) {
    if (_tool != t) {
      setState(() => _tool = t);
      return;
    }
    if (t != _Tool.brush) return;
    Haptics.selection();
    setState(() => _assist = !_assist);
  }

  /// 偏位模式:笔刷光标 = 触点上方 [_assistGapPx](屏幕距离)处。
  Offset _cursorFor(Offset touch) =>
      _assist ? touch - Offset(0, _assistGapPx / _scale) : touch;

  void _endStroke() {
    if (!_stroking) return;
    _stroking = false;
    setState(() {
      _lastPaint = null;
      _autoCrop();
    });
  }

  /// 局部框全自动:框的大小位置永远等于「遮罩 + 一圈留白」,每一笔都重算。
  ///
  /// 大图省点数要走局部框,但**等落笔之后**才开 —— 原来是一进来就按分辨率
  /// 开,还没画就先框住半张图挡视线,框的位置跟你要改的地方也毫无关系。
  /// 按遮罩算,位置天然是对的,也不会出现"第二笔画到框外被静默丢掉"。
  ///
  /// 单边封顶 [_cropMaxSide]:遮罩比这还大时框只能盖住其中一段。
  void _autoCrop() {
    // 局部框是「发送范围」,只有涂抹模式有意义 —— 打码不发送,让它自动弹出来
    // 只会拿黄框和框外 40% 暗化盖住打码预览。
    if (_mode != _Mode.paint) return;
    final img = _img, grid = _grid;
    if (img == null || grid == null) return;
    final tight = tightCropRect(grid);
    if (tight == null) return; // 擦空了:框留在原处,别闪
    if (!_cropMode) {
      // 还没开:小图本来就不用开,手动关过的也不再替他打开
      if (_cropOptOut || img.width * img.height <= kFreePixelThreshold) return;
      _cropMode = true;
    }
    var want = alignSendRect(tight, img.width, img.height);
    final keep = _cropResized ? _crop : null;
    if (keep != null) {
      // 拉过边的框归用户:只扩不缩 —— 尊重他要的留白,同时让涂到框外的
      // 地方也进框(发送时按框裁遮罩,框外那部分等于没画)。
      final x = math.min(keep.x, want.x);
      final y = math.min(keep.y, want.y);
      final r = math.max(keep.x + keep.w, want.x + want.w);
      final b = math.max(keep.y + keep.h, want.y + want.h);
      want = (x: x, y: y, w: r - x, h: b - y);
    }
    // 超过上限时:先尽量多盖遮罩,再尽量留住他拉的框
    _crop = capSendRect(
      want,
      _cropMaxSide,
      focus: maskBounds(grid),
      keep: keep,
    );
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    _grid!.restore(_undo.removeLast());
    setState(() {
      _rev++;
      _maskTouched();
    });
  }

  void _clearAll() {
    if (_grid!.isEmpty) return;
    _pushUndo();
    _grid!.clear();
    setState(() {
      _rev++;
      _maskTouched();
    });
  }

  // ---------- 扩图 ----------

  bool get _hasExpand => _padL + _padT + _padR + _padB > 0;

  void _resetPad() {
    _padL = 0;
    _padT = 0;
    _padR = 0;
    _padB = 0;
  }

  /// 切模式(对齐 web:互斥局部,进出都重置扩展;本会话生成进行中不切,
  /// 防止预览状态错乱)。
  ///
  /// **遮罩不清** —— 三档共用同一张,切过去接着用就是这个功能的意义。
  void _setMode(_Mode m) {
    final img = _img;
    if (img == null || _mode == m) return;
    if (_previewDst != null) {
      hintSnack(context, '生成进行中,请稍候', icon: Icons.hourglass_top);
      return;
    }
    if (m == _Mode.expand && (img.width % 64 != 0 || img.height % 64 != 0)) {
      hintSnack(context, '图片尺寸非 64 对齐,无法扩图', icon: Icons.straighten);
      return;
    }
    if (m == _Mode.censor) {
      // 打码是本地重画像素,和「涂完看结果只描轮廓」那套无关 —— 一进来就
      // 恢复实心显示,否则遮罩是轮廓、预览又是实心,两套语义打架。
      _maskAsOutline = false;
      _censorBlock = defaultCensorBlock(img.width, img.height);
      unawaited(_rebuildCensorPreview());
      // 首次加载要解压 + 建会话 —— 进档就在后台读好,别等用户点了才开始
      unawaited(warmUpCensorSession());
    }
    setState(() {
      _mode = m;
      _resetPad();
      _slider = null;
      _viewport = Size.zero; // 强制重 fit + 居中(web 切换时重置视角同款)
      if (m != _Mode.paint) {
        _cropMode = false;
        _crop = null;
      }
    });
  }

  int _padOf(_ExpandHandle d) => switch (d) {
    _ExpandHandle.top => _padT,
    _ExpandHandle.bottom => _padB,
    _ExpandHandle.left => _padL,
    _ExpandHandle.right => _padR,
  };

  void _setPadOf(_ExpandHandle d, int v) {
    switch (d) {
      case _ExpandHandle.top:
        _padT = v;
      case _ExpandHandle.bottom:
        _padB = v;
      case _ExpandHandle.left:
        _padL = v;
      case _ExpandHandle.right:
        _padR = v;
    }
  }

  /// 扩图边把手命中(屏幕坐标):整条边外侧条带都可拖(web 拖拽条同款),
  /// 触屏给 48px 命中厚度。
  bool _hitExpand(Offset screenPt) {
    final img = _img;
    if (img == null) return false;
    Offset toScreen(double x, double y) => Offset(x, y) * _scale + _offset;
    final tl = toScreen(-_padL.toDouble(), -_padT.toDouble());
    final br = toScreen(
      (img.width + _padR).toDouble(),
      (img.height + _padB).toDouble(),
    );
    const grab = 48.0;
    final bands = <_ExpandHandle, ui.Rect>{
      _ExpandHandle.top: ui.Rect.fromLTRB(
        tl.dx,
        tl.dy - grab,
        br.dx,
        tl.dy + 8,
      ),
      _ExpandHandle.bottom: ui.Rect.fromLTRB(
        tl.dx,
        br.dy - 8,
        br.dx,
        br.dy + grab,
      ),
      _ExpandHandle.left: ui.Rect.fromLTRB(
        tl.dx - grab,
        tl.dy,
        tl.dx + 8,
        br.dy,
      ),
      _ExpandHandle.right: ui.Rect.fromLTRB(
        br.dx - 8,
        tl.dy,
        br.dx + grab,
        br.dy,
      ),
    };
    for (final e in bands.entries) {
      if (e.value.contains(screenPt)) {
        _expandDrag = e.key;
        _expandStartPad = _padOf(e.key);
        _expandDragScreen = screenPt;
        _expandDragMoved = false;
        return true;
      }
    }
    return false;
  }

  /// 拖拽调整该向 padding:屏幕位移 / scale 折回图像素,
  /// round 到 64 网格(web 同款公式),不小于 0。
  void _updateExpandDrag(Offset screenPt) {
    final dir = _expandDrag;
    final from = _expandDragScreen;
    if (dir == null || from == null) return;
    final d = screenPt - from;
    if (d.distance > 10) _expandDragMoved = true;
    final delta = switch (dir) {
      _ExpandHandle.top => -d.dy,
      _ExpandHandle.bottom => d.dy,
      _ExpandHandle.left => -d.dx,
      _ExpandHandle.right => d.dx,
    };
    final next = math.max(
      0,
      ((_expandStartPad + delta / _scale) / 64).round() * 64,
    );
    if (next != _padOf(dir)) setState(() => _setPadOf(dir, next));
  }

  // ---------- 局部框 ----------

  int _snap64(num v, {int min = 256, required int max}) {
    final capped = math.max(64, max ~/ 64 * 64);
    final lo = math.min(min, capped);
    return ((v / 64).round() * 64).clamp(lo, capped);
  }

  void _toggleCrop() {
    if (_cropMode) {
      setState(() {
        _cropMode = false;
        _crop = null;
        _cropOptOut = true; // 关过就别再自动开
        _cropResized = false;
      });
      return;
    }
    final img = _img!;
    final grid = _grid!;
    final tight = tightCropRect(grid);
    setState(() {
      _cropOptOut = false;
      _cropResized = false;
      _cropMode = true;
      // 有涂抹按遮罩算框;还没涂就先给个居中框占位,落笔后自动跟上
      _crop = tight != null
          ? capSendRect(
              alignSendRect(tight, img.width, img.height),
              _cropMaxSide,
              focus: maskBounds(grid),
            )
          : _defaultCrop(img.width, img.height);
    });
  }

  /// 居中默认框(约 55% 边长、不超过上限、64 对齐,原点也落 64 网格)。
  IntRect _defaultCrop(int imgW, int imgH) {
    final w = _snap64(imgW * 0.55, max: math.min(imgW, _cropMaxSide));
    final h = _snap64(imgH * 0.55, max: math.min(imgH, _cropMaxSide));
    return (
      x: (imgW - w) ~/ 2 ~/ 64 * 64,
      y: (imgH - h) ~/ 2 ~/ 64 * 64,
      w: w,
      h: h,
    );
  }

  /// 拉杆命中:四条边各一条窄带(屏幕 26px),横竖两条带交叠的四个角
  /// 两条边一起拉;框内其余地方一律落笔。
  /// 整框移动没有 —— 框跟着遮罩走,移开就失去意义,而且会把"框内能涂"吃掉。
  bool _hitCropHandle(Offset imgPoint) {
    final c = _crop;
    if (c == null) return false;
    final band = 26 / _scale;
    final l = c.x.toDouble(), t = c.y.toDouble();
    final r = (c.x + c.w).toDouble(), b = (c.y + c.h).toDouble();
    // 落在框外一个带宽以上就不算(框外是压暗区,那里点了也该涂)
    if (imgPoint.dx < l - band ||
        imgPoint.dx > r + band ||
        imgPoint.dy < t - band ||
        imgPoint.dy > b + band) {
      return false;
    }
    final dl = (imgPoint.dx - l).abs(), dr = (imgPoint.dx - r).abs();
    final dt = (imgPoint.dy - t).abs(), db = (imgPoint.dy - b).abs();
    // 每个方向只认近的那条边(框在屏幕上很窄时两条都可能在带内)
    final h = math.min(dl, dr) > band ? 0 : (dl <= dr ? -1 : 1);
    final v = math.min(dt, db) > band ? 0 : (dt <= db ? -1 : 1);
    if (h == 0 && v == 0) return false;
    _cropDrag = (h: h, v: v);
    _cropStart = c;
    _cropDragFrom = imgPoint;
    return true;
  }

  void _updateCropDrag(Offset imgPoint) {
    final drag = _cropDrag, start = _cropStart, from = _cropDragFrom;
    final img = _img;
    if (drag == null || start == null || from == null || img == null) return;
    // 对边固定,拖的边动;角 = 横竖各拖一条。宽高 64 步进、256 ~ 上限
    final (x, w) = _dragSpan(
      start.x,
      start.w,
      imgPoint.dx - from.dx,
      drag.h,
      img.width,
    );
    final (y, h) = _dragSpan(
      start.y,
      start.h,
      imgPoint.dy - from.dy,
      drag.v,
      img.height,
    );
    final next = (x: x, y: y, w: w, h: h);
    if (next != _crop) {
      _cropResized = true;
      setState(() => _crop = next);
    }
  }

  /// 单方向拉伸,返回 (起点, 长度)。[side] -1 拖起始边(左/上)、1 拖末端边
  /// (右/下)、0 不动;[limit] 是图在这个方向的尺寸。
  (int, int) _dragSpan(int pos, int len, double delta, int side, int limit) {
    if (side < 0) {
      final end = pos + len; // 末端固定
      final l = _snap64(len - delta, max: math.min(end, _cropMaxSide));
      return (end - l, l);
    }
    if (side > 0) {
      final l = _snap64(len + delta, max: math.min(limit - pos, _cropMaxSide));
      return (pos, l);
    }
    return (pos, len);
  }

  // ---------- 手势 ----------

  void _onScaleStart(ScaleStartDetails d) {
    _lastPointers = d.pointerCount;
    if (d.pointerCount == 1) {
      // 缩放松手余波:先抬一指时 recognizer 会以剩下那指重启手势,
      // 这不是新涂抹——整轮触摸(直到全部离手)不再落笔。
      if (_pinchSession) return;
      if (_expandMode) {
        // 扩图模式不涂抹:单指=拖边把手,未命中则平移画布
        _hitExpand(d.localFocalPoint);
        return;
      }
      final p = _toImg(d.localFocalPoint);
      if (_cropMode && _hitCropHandle(p)) return;
      // 不立即落笔:双指缩放时第一指总会先到一拍,等移动/抬手再确认涂抹
      _pendingStroke = _cursorFor(p);
      if (_assist) setState(() => _fingerAt = p); // 立即显示把手与偏位光标
    } else {
      _pendingStroke = null;
      _pzScale0 = null; // update 首帧 rebase
    }
  }

  void _rebasePZ(ScaleUpdateDetails d) {
    _pzScale0 = _scale;
    _pzOffset0 = _offset;
    _pzFocal0 = d.localFocalPoint;
    _pzGesture0 = d.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      _pendingStroke = null; // 第二指到:确认缩放,悬置起点作废
      _fingerAt = null;
      if (_stroking) _endStroke();
      _cropDrag = null;
      _expandDrag = null;
      if (_lastPointers < 2 || _pzScale0 == null) _rebasePZ(d);
      final k = d.scale / _pzGesture0;
      final ns = (_pzScale0! * k).clamp(_fitScale * 0.5, _fitScale * 10.0);
      final ratio = ns / _pzScale0!;
      setState(() {
        _offset = d.localFocalPoint - (_pzFocal0! - _pzOffset0!) * ratio;
        _scale = ns;
      });
    } else if (_expandDrag != null) {
      _updateExpandDrag(d.localFocalPoint);
    } else if (_cropDrag != null) {
      _updateCropDrag(_toImg(d.localFocalPoint));
    } else if (_expandMode) {
      // 扩图模式单指未命中把手:平移画布
      if (d.focalPointDelta != Offset.zero) {
        setState(() => _offset += d.focalPointDelta);
      }
    } else {
      final touch = _toImg(d.localFocalPoint);
      if (_assist) _fingerAt = touch; // 把手随指(strokeTo 的 setState 一并刷新)
      // 仍是单指且开始移动:确认涂抹,先补落悬置起点
      final pending = _pendingStroke;
      if (pending != null) {
        _pendingStroke = null;
        _beginStroke(pending);
      }
      if (_stroking) _strokeTo(_cursorFor(touch));
    }
    _lastPointers = d.pointerCount;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // 单指按下即抬(点涂一个点):抬手时落笔
    final pending = _pendingStroke;
    _pendingStroke = null;
    if (pending != null && _lastPointers == 1 && d.pointerCount == 0) {
      _beginStroke(pending);
    }
    _endStroke();
    if (_fingerAt != null) setState(() => _fingerAt = null);
    _cropDrag = null;
    // 点按把手(按下未拖动即抬手):该向 +64 一个单位
    final tapDir = _expandDrag;
    if (tapDir != null && !_expandDragMoved && d.pointerCount == 0) {
      Haptics.selection();
      setState(() => _setPadOf(tapDir, _padOf(tapDir) + 64));
    }
    _expandDrag = null;
    _expandDragScreen = null;
    _pzScale0 = null;
  }

  // ---------- 发起重绘 ----------

  /// 重绘发送与计价的参数源:创作页**此刻**的状态,按模块配置剥离隐藏模块
  /// (与手动生成同语义)。面板只在这之上覆盖 inpaint/img2img、发送尺寸和种子。
  ///
  /// 现读而不是用打开面板时的快照 —— 对齐 web `handleInpaintGenerate`:
  /// 那边费用和载荷都是当下的 state。冻住会让「切去创作页改步数再切回来」
  /// 变成价格不动、发出去的也还是旧步数。计价用 watch 版(见 build)。
  GenerateState get _liveInput => stripHiddenModules(
    ref.read(generateProvider),
    ref.read(genModulesProvider).value ?? const GenModuleSettings(),
  );

  /// 扩图发送:白底扩后画布 + 自动 mask(原图区黑/新增区白),
  /// paste 置空 → 结果即完整新图直接入库(尺寸=params 扩后尺寸)。
  Future<void> _fireExpand(ui.Image img, GenerateState input) async {
    final tw = img.width + _padL + _padR;
    final th = img.height + _padT + _padB;
    if (tw * th > _maxSendPixels) {
      hintSnack(
        context,
        '扩图后尺寸过大,请缩小扩展范围',
        icon: Icons.photo_size_select_large,
      );
      return;
    }
    setState(() => _firing = true);
    try {
      final image = await buildExpandImage(
        _currentBytes,
        padL: _padL,
        padT: _padT,
        padR: _padR,
        padB: _padB,
      );
      final mask = await buildExpandMask(
        imgW: img.width,
        imgH: img.height,
        padL: _padL,
        padT: _padT,
        padR: _padR,
        padB: _padB,
      );
      if (!mounted) return;
      _saveInto(
        InpaintJob(
          image: image,
          mask: mask,
          strength: _strength,
          sourceId: widget.session.sourceId,
          // 扩图后尺寸变了,这份网格回去会被 decodeInto 拒掉 —— 留着无妨,
          // 图没扩成功时(用户又退回来)还能接着用。
          grid: _grid?.encode(),
        ),
        width: tw,
        height: th,
      );
    } finally {
      if (mounted) setState(() => _firing = false);
    }
  }

  /// 存进创作页并收工 —— 这个编辑器**只负责产出遮罩**,发车交给主生成按钮
  /// (对齐官网)。流式预览也跟着回到图库画布那一份,不再自己画一套。
  ///
  /// 存完直接跳创作页:主生成按钮在那儿,留在图库等于让人自己去找。
  void _saveInto(InpaintJob job, {required int width, required int height}) {
    final before = ref.read(generateProvider).params;
    ref
        .read(generateProvider.notifier)
        .setInpaint(job, width: width, height: height);
    Haptics.medium();
    // 遮罩会改写生成分辨率(局部发裁切区、扩图发垫大后的画布),和图生图选底图
    // 一个道理 —— 变了就说一声,免得回到创作页看见分辨率莫名其妙换了。
    if (before.width != width || before.height != height) {
      hintSnack(
        context,
        '分辨率已按重绘范围调整为 $width×$height',
        icon: Icons.aspect_ratio,
      );
    }
    ref.read(shellIndexProvider.notifier).select(kTabCreate);
    _close();
  }

  // ---------- 打码 ----------

  /// 重算整图马赛克底片(画布取样用)。块大小没变就复用。
  ///
  /// 满遮罩跑一遍 [censorPng] 得到的底片,和最终出图对齐**同一套 8px 网格**,
  /// 所以按遮罩格从它上面取样画出来的预览与结果逐像素相同 —— 不是近似示意。
  Future<void> _rebuildCensorPreview() async {
    final img = _img;
    if (img == null) return;
    final block = _censorBlock;
    if (_censorPreviewBlock == block && _censorPreview != null) return;
    final full = MaskGrid(img.width, img.height);
    full.cells.fillRange(0, full.cells.length, 1);
    try {
      final png = await censorPng(
        _currentBytes,
        full.encode(),
        style: CensorStyle.mosaic,
        block: block,
      );
      if (!mounted) return;
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      // 等这一趟的功夫用户又拖了滑杆 —— 这张已经过期,直接扔
      if (!mounted || _censorBlock != block) {
        frame.image.dispose();
        return;
      }
      final old = _censorPreview;
      setState(() {
        _censorPreview = frame.image;
        _censorPreviewBlock = block;
      });
      // 旧底片延到下一帧再放:当场 dispose 有可能砍掉一张还没光栅化的
      // 帧里正引用着的图。
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } catch (_) {
      // 预览失败不拦功能:画布退回实心遮罩,打码本身照常能出图
    }
  }

  /// 自动预填:检测 → 把框刷进遮罩。
  ///
  /// **只预填,不出图。** 模型 F1 约 0.80(大概每 6 个目标漏 1 个),够不上
  /// 无人值守;人始终在回路里 —— 涂/擦/撤销全都照常,撤销一步就回到手动。
  Future<void> _autoDetect() async {
    final grid = _grid;
    final img = _img;
    if (grid == null || img == null || _detecting) return;
    setState(() => _detecting = true);
    try {
      // 直接喂**已经原生解码好**的这张位图,别再让检测层去解一遍 PNG:
      // 那是纯 Dart 解码,一张 1216×832 就要几百毫秒。
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null || !mounted) return;
      final boxes = await detectCensorBoxes(
        bd.buffer.asUint8List(),
        img.width,
        img.height,
      );
      if (!mounted) return;
      if (boxes.isEmpty) {
        hintSnack(context, '没检测到需要打码的区域', icon: Icons.search_off);
        return;
      }
      _pushUndo(); // 预填当成一次可撤销的编辑
      final n = paintBoxes(grid, boxes);
      _maskTouched();
      setState(() => _rev++);
      hintSnack(
        context,
        '检测到 ${boxes.length} 处,已预填',
        icon: Icons.auto_fix_high,
      );
      if (n == 0) return;
    } catch (e) {
      if (mounted) hintSnack(context, '自动识别失败: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// 选纯色档的填充色。预设四档灰阶,见 [kCensorColors] 的取舍说明。
  Future<void> _pickCensorColor() async {
    final scheme = context.scheme;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('打码颜色', style: ctx.texts.titleMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (c, name) in kCensorColors)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Color(c),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: c == _censorColor
                                        ? scheme.primary
                                        : scheme.outlineVariant,
                                    width: c == _censorColor ? 3 : 1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(name, style: ctx.texts.labelMedium),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    Haptics.selection();
    setState(() => _censorColor = picked);
  }

  void _toggleCensorStyle() {
    Haptics.selection();
    setState(() {
      _censorStyle = _censorStyle == CensorStyle.mosaic
          ? CensorStyle.solid
          : CensorStyle.mosaic;
      // 纯色没有块大小可调,滑杆开着就收起来
      if (_censorStyle == CensorStyle.solid && _slider == _SliderTarget.block) {
        _slider = null;
      }
    });
  }

  /// 改块大小。拖滑杆期间防抖,不每帧跑整图。
  void _setCensorBlock(int v) {
    final b = v.clamp(kCensorBlockMin, kCensorBlockMax);
    if (b == _censorBlock) return;
    setState(() => _censorBlock = b);
    _censorDebounce?.cancel();
    _censorDebounce = Timer(
      const Duration(milliseconds: 240),
      () => unawaited(_rebuildCensorPreview()),
    );
  }

  /// 就地打码 → 存入图库新的一张。
  ///
  /// **原图一个字节不动**:原图是用户资产,打码是派生品 —— 和放大那条路
  /// 一致(见 result_canvas 的 `_upscale`)。也因此不走 [_fire] 那套
  /// 「攒任务回创作页生成」:本地重画像素,不联网、不扣点、当场出结果。
  Future<void> _fireCensor() async {
    final grid = _grid;
    final img = _img;
    if (grid == null || img == null || _firing) return;
    if (grid.isEmpty) {
      hintSnack(context, '先涂抹要打码的区域', icon: Icons.brush);
      return;
    }
    final galleryTarget = ref.read(gallerySaveTargetProvider);
    setState(() => _firing = true);
    try {
      final png = await censorPng(
        _currentBytes,
        grid.encode(),
        style: _censorStyle,
        block: _censorBlock,
        color: _censorColor,
      );
      if (!mounted) return;
      // 沿用源图的 seed 与参数快照(找不到源就记 0、不带快照):打码不改变
      // "这张图当初是怎么抽出来的",和放大那条路一致。**不能记 [_liveInput]**:
      // 那是创作页此刻的参数,拿去复用或导出元数据就串成了别的图。
      var seed = 0;
      GenerateState? input;
      for (final r in ref.read(galleryProvider).results) {
        if (r.id == widget.session.sourceId) {
          seed = r.seed;
          input =
              r.input ??
              (r.hasInput
                  ? await ref.read(appStoresProvider).gallery.readInput(r.id)
                  : null);
          break;
        }
      }
      if (!mounted) return;
      await ref
          .read(galleryProvider.notifier)
          .addResultToGallery(
            target: galleryTarget,
            bytes: png,
            width: img.width,
            height: img.height,
            seed: seed,
            badge: ResultBadge.censored,
            input: input,
          );
      if (!mounted) return;
      hintSnack(context, '已打码并存入图库', icon: Icons.check_circle_outline);
      await _close();
    } catch (e) {
      if (mounted) hintSnack(context, '打码失败: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _firing = false);
    }
  }

  Future<void> _fire() async {
    final img = _img;
    final grid = _grid;
    if (img == null || grid == null || _firing) return;
    // 打码在模型门禁**之前**分岔:本地重画像素,跟用哪个模型、能不能 infill
    // 一点关系都没有 —— Anima/Krea 下也该照样能打。
    if (_censorMode) return _fireCensor();
    // 参数现读创作页,模型自然也跟着走:面板开着的时候完全可以切去换成
    // Anima / Krea(那两条通道都没有 infill)。进面板时 result_canvas 已拦过
    // 一道,这里补发车前的第二道 —— 否则会一路走到生成器里才报不支持。
    final input = _liveInput;
    if (isModalModel(input.params.model)) {
      hintSnack(
        context,
        '${isKreaModel(input.params.model) ? 'Krea 2' : 'Anima'} '
        '模型不支持重绘,请先切回 NovelAI 模型',
        icon: Icons.block,
      );
      return;
    }
    if (_expandMode) {
      if (!_hasExpand) {
        hintSnack(context, '先拖动边缘扩展画布', icon: Icons.open_in_full);
        return;
      }
      await _fireExpand(img, input);
      return;
    }
    if (grid.isEmpty) {
      hintSnack(context, '先用画笔涂抹要重绘的区域', icon: Icons.brush);
      return;
    }
    final send = _cropMode ? _crop : null;
    if (send != null && !grid.hasCellsIn(send)) {
      hintSnack(context, '黄框内没有涂抹区域', icon: Icons.crop);
      return;
    }
    final sw = send?.w ?? img.width;
    final sh = send?.h ?? img.height;
    if (sw * sh > _maxSendPixels) {
      hintSnack(
        context,
        '发送尺寸过大,请开启「局部」缩小范围',
        icon: Icons.photo_size_select_large,
      );
      return;
    }
    if (send == null && (img.width % 64 != 0 || img.height % 64 != 0)) {
      hintSnack(context, '图片尺寸非 64 对齐,请使用「局部」模式', icon: Icons.straighten);
      return;
    }

    setState(() => _firing = true);
    try {
      final Uint8List image;
      final Uint8List mask;
      InpaintPaste? paste;
      if (send != null) {
        image = await cropPng(_currentBytes, send);
        mask = await maskToPng(grid, region: send);
        paste = InpaintPaste(
          original: _currentBytes,
          sendX: send.x,
          sendY: send.y,
          tightX: send.x,
          tightY: send.y,
          tightW: send.w,
          tightH: send.h,
          outW: img.width,
          outH: img.height,
        );
      } else {
        image = _currentBytes;
        mask = await maskToPng(grid);
      }
      if (!mounted) return;
      _saveInto(
        InpaintJob(
          image: image,
          mask: mask,
          strength: _strength,
          paste: paste,
          sourceId: widget.session.sourceId,
          grid: grid.encode(),
        ),
        width: sw,
        height: sh,
      );
    } finally {
      if (mounted) setState(() => _firing = false);
    }
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final img = _img;
    final hasPrev = _prevImg != null; // 至少重绘过一次才有「前后对比」
    // 编辑中允许切 tab(图库页 keep-alive 保留本面板);仅当图库可见时
    // 返回键收面板,在其他 tab 返回键走系统默认(最小化)。
    final onGallery = ref.watch(shellIndexProvider) == kTabGallery;

    return PopScope(
      canPop: !onGallery,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: IgnorePointer(
        // 解码/入场前全透明,不拦下层图库的触摸
        ignoring: img == null,
        child: FadeTransition(
          opacity: _curve,
          child: ColoredBox(
            color: scheme.surface,
            child: Column(
              children: [
                SlideTransition(
                  position: _topSlide,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        _RoundBtn(icon: Icons.close, onTap: _close),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSegTabs()),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: ColoredBox(
                      // 与图库画布同底色,原地切换视觉连续
                      color: scheme.surfaceContainerHigh,
                      child: img == null
                          ? const Center(child: CircularProgressIndicator())
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                _fit(constraints.biggest);
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Listener(
                                      // raw 层手指计数:标记双指会话(其
                                      // 余波单指重启不算涂抹),全离手复位
                                      onPointerDown: (_) {
                                        _rawPointers++;
                                        if (_rawPointers >= 2) {
                                          _pinchSession = true;
                                        }
                                      },
                                      onPointerUp: (_) {
                                        if (_rawPointers > 0) _rawPointers--;
                                        if (_rawPointers == 0) {
                                          _pinchSession = false;
                                        }
                                      },
                                      onPointerCancel: (_) {
                                        if (_rawPointers > 0) _rawPointers--;
                                        if (_rawPointers == 0) {
                                          _pinchSession = false;
                                        }
                                      },
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onScaleStart: _onScaleStart,
                                        onScaleUpdate: _onScaleUpdate,
                                        onScaleEnd: _onScaleEnd,
                                        child: CustomPaint(
                                          painter: _CanvasPainter(
                                            // 按住对比:显示重绘前的底图
                                            // (扩图后旧图对位,新增区露画布底=遮挡)
                                            image:
                                                _showOriginal &&
                                                    _prevImg != null
                                                ? _prevImg!
                                                : img,
                                            imageOffset:
                                                _showOriginal &&
                                                    _prevImg != null
                                                ? _prevImgOffset
                                                : Offset.zero,
                                            rects: _showOriginal
                                                ? const []
                                                : _maskRects,
                                            maskOutline:
                                                _showOriginal || !_maskAsOutline
                                                ? null
                                                : _maskOutline,
                                            rev: _rev,
                                            scale: _scale,
                                            offset: _offset,
                                            crop: _showOriginal ? null : _crop,
                                            cropActive: _cropMode,
                                            // 扩图可视化(生成中/对比中隐藏)
                                            expandUi:
                                                _expandMode &&
                                                _previewDst == null &&
                                                !_showOriginal,
                                            padL: _padL,
                                            padT: _padT,
                                            padR: _padR,
                                            padB: _padB,
                                            cursor: _showOriginal
                                                ? null
                                                : _cursorPoint,
                                            finger: _showOriginal
                                                ? null
                                                : _fingerAt,
                                            brush: _brush,
                                            erasing: _tool == _Tool.eraser,
                                            // 框用主题浅金(容器色),
                                            // 外缘黑描边兜底可读性
                                            accent: scheme.primaryContainer,
                                            onAccent: scheme.onPrimaryContainer,
                                            preview: _showOriginal
                                                ? null
                                                : _previewImg,
                                            previewDst: _previewDst,
                                            previewClip: _previewClip,
                                            // 打码所见即所得(按住对比时让位)
                                            censorImg:
                                                _censorMode &&
                                                    !_showOriginal &&
                                                    _censorStyle ==
                                                        CensorStyle.mosaic
                                                ? _censorPreview
                                                : null,
                                            censorSolid:
                                                _censorMode &&
                                                !_showOriginal &&
                                                _censorStyle ==
                                                    CensorStyle.solid,
                                            censorColor: Color(_censorColor),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // 对比按钮与浮动滑杆同踞下缘,滑杆展开时让位
                                    if (hasPrev && _slider == null)
                                      Positioned(
                                        right: 14,
                                        bottom: 14,
                                        child: _CompareButton(
                                          onChanged: (v) =>
                                              setState(() => _showOriginal = v),
                                        ),
                                      ),
                                    // 浮动滑杆(笔刷/强度):悬浮画布下缘,不顶布局
                                    Positioned(
                                      left: 14,
                                      right: 14,
                                      bottom: 12,
                                      child: AnimatedSwitcher(
                                        duration: Motion.fast,
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeIn,
                                        transitionBuilder: (child, anim) =>
                                            FadeTransition(
                                              opacity: anim,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin: const Offset(0, .3),
                                                  end: Offset.zero,
                                                ).animate(anim),
                                                child: child,
                                              ),
                                            ),
                                        child: _slider == null
                                            ? const SizedBox.shrink(
                                                key: ValueKey('noslider'),
                                              )
                                            : KeyedSubtree(
                                                key: ValueKey(_slider),
                                                child: _buildSliderRow(),
                                              ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                ),
                SlideTransition(
                  position: _panelSlide,
                  child: _buildBottomPanel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegTabs() {
    final scheme = context.scheme;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      // 一块会平移的实心色块 + 触感,不做任何"这边灭那边亮"。
      // 也不用 InkWell —— 点在未选中那格上会先泛一圈水波,看着就是"闪选中态"。
      child: Stack(
        children: [
          AnimatedAlign(
            duration: Motion.medium,
            curve: Motion.emphasized,
            // 三档:-1/0/1 三个落点(两档时代那个 centerLeft/Right 的推广)
            alignment: Alignment(_mode.index - 1.0, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // secondaryContainer 太浅,压在同色系底上几乎看不出选中
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _SegTab(
                icon: Icons.brush,
                label: '涂抹',
                active: _mode == _Mode.paint,
                onTap: () => _tapSeg(_Mode.paint),
              ),
              _SegTab(
                icon: Icons.open_in_full,
                label: '扩图',
                active: _expandMode,
                onTap: () => _tapSeg(_Mode.expand),
              ),
              _SegTab(
                icon: Icons.blur_on,
                label: '打码',
                active: _censorMode,
                onTap: () => _tapSeg(_Mode.censor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _tapSeg(_Mode m) {
    if (_mode == m) return;
    Haptics.selection();
    _setMode(m);
  }

  Widget _buildBottomPanel() {
    if (_expandMode) return _buildExpandPanel();
    final scheme = context.scheme;
    final grid = _grid;
    final canUndo = _undo.isNotEmpty;
    final canClear = !(grid?.isEmpty ?? true);
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ToolBtn(
                  icon: _assist ? Icons.my_location : Icons.brush,
                  label: _assist ? '偏位' : '画笔',
                  active: _tool == _Tool.brush,
                  onTap: () => _tapTool(_Tool.brush),
                ),
                _ToolBtn(
                  icon: Icons.cleaning_services,
                  label: '橡皮',
                  active: _tool == _Tool.eraser,
                  onTap: () => _tapTool(_Tool.eraser),
                ),
                // 局部框是「发送范围」,打码不发送 —— 那一格换成样式切换。
                // (自动识别不在这排,它挂在 CTA 上,见 _buildCensorCta)
                if (_censorMode)
                  _ToolBtn(
                    icon: _censorStyle == CensorStyle.mosaic
                        ? Icons.blur_on
                        : Icons.square_rounded,
                    label: _censorStyle.label,
                    onTap: _toggleCensorStyle,
                  )
                else
                  _ToolBtn(
                    icon: Icons.crop,
                    label: '局部',
                    active: _cropMode,
                    onTap: _toggleCrop,
                  ),
                _ToolBtn(
                  icon: Icons.undo,
                  label: '撤销',
                  enabled: canUndo,
                  onTap: _undoOnce,
                ),
                _ToolBtn(
                  icon: Icons.restart_alt,
                  label: '清空',
                  enabled: canClear,
                  tint: scheme.error,
                  onTap: _clearAll,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const GallerySaveTargetRow(compact: true),
            Row(
              children: [
                _ParamChip(
                  icon: Icons.line_weight,
                  label: '笔刷',
                  value: '${_brush.round()}',
                  active: _slider == _SliderTarget.brush,
                  onTap: () => setState(
                    () => _slider = _slider == _SliderTarget.brush
                        ? null
                        : _SliderTarget.brush,
                  ),
                ),
                const SizedBox(width: 8),
                // 打码:强度换成块大小(纯色模式与块无关,整条隐掉)
                if (!_censorMode)
                  _ParamChip(
                    icon: Icons.tune,
                    label: '强度',
                    value: _strength.toStringAsFixed(2),
                    active: _slider == _SliderTarget.strength,
                    onTap: () => setState(
                      () => _slider = _slider == _SliderTarget.strength
                          ? null
                          : _SliderTarget.strength,
                    ),
                  )
                else if (_censorStyle == CensorStyle.mosaic)
                  _ParamChip(
                    icon: Icons.grid_4x4,
                    label: '块',
                    value: '${_censorBlock * 8}',
                    active: _slider == _SliderTarget.block,
                    onTap: () => setState(
                      () => _slider = _slider == _SliderTarget.block
                          ? null
                          : _SliderTarget.block,
                    ),
                  )
                else
                  // 纯色没有块大小可调,那一格改放填充色
                  _ParamChip(
                    icon: Icons.palette_outlined,
                    swatch: Color(_censorColor),
                    label: '颜色',
                    value: censorColorLabel(_censorColor),
                    active: false,
                    onTap: _pickCensorColor,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: _censorMode
                        ? _buildCensorCta()
                        : _buildCtaArea('保存遮罩', onPressed: _fire),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 扩图专属底面板:尺寸(点击弹窗直接输入)/强度/重置 + 全宽 CTA。
  Widget _buildExpandPanel() {
    final scheme = context.scheme;
    final img = _img;
    final tw = img == null ? 0 : img.width + _padL + _padR;
    final th = img == null ? 0 : img.height + _padT + _padB;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ParamChip(
                  icon: Icons.aspect_ratio,
                  label: '尺寸',
                  value: '$tw×$th',
                  active: _hasExpand,
                  onTap: _editExpandSize,
                ),
                const SizedBox(width: 8),
                _ParamChip(
                  icon: Icons.tune,
                  label: '强度',
                  value: _strength.toStringAsFixed(2),
                  active: _slider == _SliderTarget.strength,
                  onTap: () => setState(
                    () => _slider = _slider == _SliderTarget.strength
                        ? null
                        : _SliderTarget.strength,
                  ),
                ),
                const Spacer(),
                Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _hasExpand ? () => setState(_resetPad) : null,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(
                        Icons.restart_alt,
                        size: 20,
                        color: _hasExpand
                            ? scheme.error
                            : scheme.onSurfaceVariant.withValues(alpha: .35),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              width: double.infinity,
              child: _buildCtaArea('保存扩图', disabled: !_hasExpand),
            ),
          ],
        ),
      ),
    );
  }

  /// 存盘 CTA(涂抹与扩图面板共用)。
  ///
  /// 这里不再有进度条与点数:生成不在本编辑器发生了 —— 进度在图库画布上,
  /// 点数在创作页那颗主生成按钮上,两处各报一次只会互相打架。
  /// 打码档的 CTA:**一颗按钮两态**。
  ///
  /// 遮罩空 → 「自动识别」;涂了(或识别出结果)→ 「保存」。
  /// 空遮罩本来就不能保存(点了只会弹「先涂抹要打码的区域」),那一格与其
  /// 摆个按不动的保存,不如摆真正该做的下一步。识别→修补→保存是一条线,
  /// 一颗按钮跟着走完,不必在工具栏另占一格、也不必拆成两半挤在一起。
  ///
  /// 想重跑识别就清空遮罩,按钮自己会变回「自动识别」。
  Widget _buildCensorCta() {
    final empty = _grid?.isEmpty ?? true;
    return _buildCtaArea(
      empty ? '自动识别' : '保存',
      icon: empty ? Icons.auto_fix_high : Icons.check_rounded,
      onPressed: empty ? _autoDetect : _fire,
      busy: empty ? _detecting : _firing,
      busyLabel: empty ? '识别中…' : '保存中…',
    );
  }

  Widget _buildCtaArea(
    String label, {
    bool disabled = false,
    IconData icon = Icons.check_rounded,
    VoidCallback? onPressed,
    bool? busy,
    String busyLabel = '保存中…',
  }) {
    final scheme = context.scheme;
    final loading = busy ?? _firing;
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      ),
      onPressed: loading || disabled ? null : (onPressed ?? _fire),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary.withValues(alpha: .8),
                ),
              )
            else
              Icon(icon, size: 19),
            const SizedBox(width: 7),
            Text(
              loading ? busyLabel : label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  /// 扩图尺寸弹窗:输入/步进目标分辨率(controller 生命周期归弹窗
  /// StatefulWidget 管,退场动画期间仍存活,勿在 await 后立刻 dispose)。
  /// 结果 round 到 64 网格、不小于原图,增量按 64 单位对称分配到两侧
  /// (奇数单位多余的一格给右/下)。
  Future<void> _editExpandSize() async {
    final img = _img;
    if (img == null) return;
    final res = await showDialog<({int w, int h})>(
      context: context,
      builder: (_) => _ExpandSizeDialog(
        initW: img.width + _padL + _padR,
        initH: img.height + _padT + _padB,
        minW: img.width,
        minH: img.height,
      ),
    );
    if (res == null || !mounted) return;
    final tw = math.max(img.width, (res.w / 64).round() * 64);
    final th = math.max(img.height, (res.h / 64).round() * 64);
    final ux = (tw - img.width) ~/ 64;
    final uy = (th - img.height) ~/ 64;
    setState(() {
      _padL = ux ~/ 2 * 64;
      _padR = (ux - ux ~/ 2) * 64;
      _padT = uy ~/ 2 * 64;
      _padB = (uy - uy ~/ 2) * 64;
    });
  }

  Widget _buildSliderRow() {
    final scheme = context.scheme;
    final t = _slider ?? _SliderTarget.brush;
    final title = switch (t) {
      _SliderTarget.brush => '笔刷大小',
      _SliderTarget.strength => '重绘强度',
      _SliderTarget.block => '马赛克块',
    };
    // 块以像素示人(格数是实现细节),读数与滑杆都按 px 走
    final valueText = switch (t) {
      _SliderTarget.brush => '${_brush.round()}',
      _SliderTarget.strength => _strength.toStringAsFixed(2),
      _SliderTarget.block => '${_censorBlock * 8}',
    };
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          Expanded(
            child: SliderTheme(
              data: compactSliderTheme,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: switch (t) {
                  _SliderTarget.brush => Slider(
                    value: _brush,
                    min: 5, // 对齐 web 桌面端(5–200)
                    max: 200,
                    onChanged: (v) => setState(() => _brush = v),
                  ),
                  _SliderTarget.strength => Slider(
                    value: _strength,
                    min: 0.1,
                    max: 1.0,
                    // 不传 divisions:离散 Slider 会用 75ms 曲线把滑块吸到
                    // 刻度,拖起来黏手。步长(0.01)就地量化。
                    onChanged: (v) =>
                        setState(() => _strength = (v * 100).round() / 100),
                  ),
                  // 块大小档位本来就是整数格,这里的 divisions 是刻度不是吸附
                  // 补丁 —— 和强度那条的取舍不冲突。
                  _SliderTarget.block => Slider(
                    value: _censorBlock.toDouble(),
                    min: kCensorBlockMin.toDouble(),
                    max: kCensorBlockMax.toDouble(),
                    divisions: kCensorBlockMax - kCensorBlockMin,
                    onChanged: (v) => _setCensorBlock(v.round()),
                  ),
                },
              ),
            ),
          ),
          ParamValueBox(
            text: valueText,
            dense: true,
            onTap: () async {
              final v = await showParamInput(
                context,
                title: title,
                value: switch (t) {
                  _SliderTarget.brush => _brush,
                  _SliderTarget.strength => _strength,
                  _SliderTarget.block => _censorBlock * 8.0,
                },
                min: switch (t) {
                  _SliderTarget.brush => 5,
                  _SliderTarget.strength => 0.1,
                  _SliderTarget.block => kCensorBlockMin * 8.0,
                },
                max: switch (t) {
                  _SliderTarget.brush => 200,
                  _SliderTarget.strength => 1,
                  _SliderTarget.block => kCensorBlockMax * 8.0,
                },
                divisions: switch (t) {
                  _SliderTarget.brush => 195,
                  _SliderTarget.strength => 90,
                  _SliderTarget.block => kCensorBlockMax - kCensorBlockMin,
                },
              );
              if (v == null || !mounted) return;
              switch (t) {
                case _SliderTarget.brush:
                  setState(() => _brush = v);
                case _SliderTarget.strength:
                  setState(() => _strength = v);
                case _SliderTarget.block:
                  _setCensorBlock((v / 8).round());
              }
            },
          ),
        ],
      ),
    );
  }
}

// ---------- 画布 ----------

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.image,
    required this.rects,
    required this.maskOutline,
    required this.rev,
    required this.scale,
    required this.offset,
    required this.crop,
    required this.cropActive,
    required this.cursor,
    required this.finger,
    required this.brush,
    required this.erasing,
    required this.accent,
    required this.onAccent,
    this.imageOffset = Offset.zero,
    this.expandUi = false,
    this.padL = 0,
    this.padT = 0,
    this.padR = 0,
    this.padB = 0,
    this.preview,
    this.previewDst,
    this.previewClip,
    this.censorImg,
    this.censorSolid = false,
    this.censorColor = const Color(0xFF000000),
  });

  final ui.Image image;
  final List<ui.Rect> rects;

  /// 非空 = 遮罩画轮廓而非实心([rects] 此时不用)。见 `_maskAsOutline`。
  final ui.Path? maskOutline;
  final int rev;
  final double scale;
  final Offset offset;
  final IntRect? crop;
  final bool cropActive;
  final Offset? cursor; // 图坐标;非空时画笔刷光标(网格方块)
  final Offset? finger; // 偏位套杆的手指把手位置;非空时画把手+连杆
  final double brush;
  final bool erasing;
  final Color accent; // 局部框/标签主题色(scheme.primary)
  final Color onAccent; // 标签文字色(scheme.onPrimary)

  /// 底图绘制偏移:扩图完成后「按住对比」把旧图对位到 (padL, padT),
  /// 新增区露出画布底色即天然遮挡(web 用深底遮新增区,同义)。
  final Offset imageOffset;

  /// 扩图可视化(新增区棋盘/虚线框/四边把手/尺寸标签)。
  final bool expandUi;
  final int padL, padT, padR, padB;

  /// 流式预览帧:clip 到发送时的遮罩快照后画进 [previewDst]
  /// (遮罩区换新内容、其余保持原图,对齐 web 的 mask 混合预览)。
  final ui.Image? preview;
  final ui.Rect? previewDst;
  final List<ui.Rect>? previewClip;

  /// 打码模式的整图马赛克底片:遮罩格从它上面按同坐标取样,画出来的
  /// 就是出图结果本身(同一套 8px 网格)。非打码模式恒为 null。
  final ui.Image? censorImg;

  /// 打码=纯色:遮罩直接盖 [censorColor],预览即成品,不需要底片。
  final bool censorSolid;

  /// 纯色档的填充色(仅 [censorSolid] 为真时有意义)。
  final Color censorColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(
        imageOffset.dx,
        imageOffset.dy,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );

    if (expandUi) _paintExpandZones(canvas);

    // 流式预览:遮罩区显示新内容(clip 遮罩快照),其余保持原图;
    // 预览期间不再蒙紫,免得挡住效果。
    final pv = preview;
    final dst = previewDst;
    if (pv != null && dst != null) {
      canvas.save();
      final clip = previewClip;
      if (clip != null && clip.isNotEmpty) {
        final path = Path();
        for (final r in clip) {
          path.addRect(r);
        }
        canvas.clipPath(path);
      }
      canvas.drawImageRect(
        pv,
        ui.Rect.fromLTWH(0, 0, pv.width.toDouble(), pv.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else if (maskOutline != null) {
      // 出图后:只描并集外轮廓,不铺实心 —— 结果像素一点不挡
      canvas.drawPath(
        maskOutline!,
        Paint()
          ..color = _maskPurple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 / scale,
      );
    } else if (rects.isNotEmpty) {
      if (censorSolid) {
        // 纯色打码:预览就是成品
        final p = Paint()..color = censorColor;
        for (final r in rects) {
          canvas.drawRect(r, p);
        }
      } else if (censorImg != null) {
        // 马赛克打码:从整图底片同坐标取样。filterQuality=none —— 块必须是
        // 硬边方块,插值一平滑就成了模糊,那是另一回事(而且可反推)。
        final p = Paint()..filterQuality = FilterQuality.none;
        for (final r in rects) {
          canvas.drawImageRect(censorImg!, r, r, p);
        }
      } else {
        // 遮罩(紫,50%+)
        final p = Paint()..color = _maskFill;
        for (final r in rects) {
          canvas.drawRect(r, p);
        }
      }
    }

    // 局部裁切框(对齐 web:框外 40% 暗化 + 三分构图线 + 外黑内黄双描边)
    final c = crop;
    if (c != null && cropActive) {
      final rect = ui.Rect.fromLTWH(
        c.x.toDouble(),
        c.y.toDouble(),
        c.w.toDouble(),
        c.h.toDouble(),
      );
      final iw = image.width.toDouble();
      final ih = image.height.toDouble();
      final dim = Paint()..color = const Color(0x66000000);
      canvas.drawRect(ui.Rect.fromLTRB(0, 0, iw, rect.top), dim);
      canvas.drawRect(ui.Rect.fromLTRB(0, rect.bottom, iw, ih), dim);
      canvas.drawRect(
        ui.Rect.fromLTRB(0, rect.top, rect.left, rect.bottom),
        dim,
      );
      canvas.drawRect(
        ui.Rect.fromLTRB(rect.right, rect.top, iw, rect.bottom),
        dim,
      );

      // 框身:一圈虚线,不画三分线。
      final dashed = _dashPath(Path()..addRect(rect), 7 / scale, 5 / scale);
      canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black.withValues(alpha: .45)
          ..strokeWidth = 3.4 / scale,
      );
      canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent
          ..strokeWidth = 1.8 / scale,
      );

      // 拉杆:四条边中点各一根短杠(单边拉),四个角各一个 L 形角柄
      // (两条边一起拉)。
      final barLen = 22 / scale;
      final arm = 16 / scale;
      final bar = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final corners = Path();
      for (final (x, y, sx, sy) in [
        (rect.left, rect.top, 1.0, 1.0),
        (rect.right, rect.top, -1.0, 1.0),
        (rect.left, rect.bottom, 1.0, -1.0),
        (rect.right, rect.bottom, -1.0, -1.0),
      ]) {
        corners
          ..moveTo(x + sx * arm, y)
          ..lineTo(x, y)
          ..lineTo(x, y + sy * arm);
      }
      canvas.drawPath(corners, bar);
      final cx = rect.center.dx, cy = rect.center.dy;
      canvas.drawLine(
        Offset(cx - barLen / 2, rect.top),
        Offset(cx + barLen / 2, rect.top),
        bar,
      );
      canvas.drawLine(
        Offset(cx - barLen / 2, rect.bottom),
        Offset(cx + barLen / 2, rect.bottom),
        bar,
      );
      canvas.drawLine(
        Offset(rect.left, cy - barLen / 2),
        Offset(rect.left, cy + barLen / 2),
        bar,
      );
      canvas.drawLine(
        Offset(rect.right, cy - barLen / 2),
        Offset(rect.right, cy + barLen / 2),
        bar,
      );
    }

    // 笔刷光标(虚线方框,与落格网格严格一致;橡皮用深色描边)
    ui.Rect? cursorRect;
    if (cursor != null) {
      final p = Paint()
        ..color = erasing ? Colors.black54 : _maskPurple.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 / scale;
      final gridCount = math.max(1, (brush / 8).round());
      final half = gridCount ~/ 2;
      final gx = ((cursor!.dx / 8).floor() - half) * 8.0;
      final gy = ((cursor!.dy / 8).floor() - half) * 8.0;
      cursorRect = ui.Rect.fromLTWH(gx, gy, gridCount * 8.0, gridCount * 8.0);
      canvas.drawPath(
        _dashPath(Path()..addRect(cursorRect), 6 / scale, 5 / scale),
        p,
      );
    }

    // 偏位套杆:手指把手圆 + 连到光标框的杆(黑外影+白线,任意底可读)
    if (finger != null && cursor != null && cursorRect != null) {
      final handleR = 30 / scale;
      void stroke(Paint p) {
        canvas.drawCircle(finger!, handleR, p);
        final dir = cursor! - finger!;
        final len = dir.distance;
        if (len > handleR) {
          final unit = dir / len;
          canvas.drawLine(
            finger! + unit * handleR,
            cursor! - unit * (cursorRect!.width / 2),
            p,
          );
        }
      }

      stroke(
        Paint()
          ..color = Colors.black.withValues(alpha: .28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 / scale,
      );
      stroke(
        Paint()
          ..color = Colors.white.withValues(alpha: .92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 / scale,
      );
      canvas.drawCircle(
        finger!,
        handleR,
        Paint()..color = Colors.white.withValues(alpha: .10),
      );
    }

    canvas.restore();

    // 屏幕空间:裁切尺寸标签(框左上角上方)
    if (c != null && cropActive) {
      _screenLabel(
        canvas,
        '${c.w}×${c.h}',
        Offset(offset.dx + c.x * scale, offset.dy + c.y * scale - 26),
      );
    }

    if (expandUi) _paintExpandHandles(canvas);
  }

  /// 图空间的扩图可视化:新增区白底 + 主题色棋盘(将被生成填充的区域),
  /// 扩后总区虚线框(黑影垫底,层次同局部框);未拖出扩展时画图缘淡虚线提示。
  void _paintExpandZones(Canvas canvas) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final total = ui.Rect.fromLTRB(
      -padL.toDouble(),
      -padT.toDouble(),
      iw + padR,
      ih + padB,
    );
    final hasPad = padL + padT + padR + padB > 0;
    if (hasPad) {
      final zones = <ui.Rect>[
        if (padT > 0) ui.Rect.fromLTRB(total.left, total.top, total.right, 0),
        if (padB > 0)
          ui.Rect.fromLTRB(total.left, ih, total.right, total.bottom),
        if (padL > 0) ui.Rect.fromLTRB(total.left, 0, 0, ih),
        if (padR > 0) ui.Rect.fromLTRB(iw, 0, total.right, ih),
      ];
      final base = Paint()..color = Colors.white;
      final check = Paint()..color = accent.withValues(alpha: .5);
      final cell = 14 / scale; // 棋盘块按屏幕尺寸恒定(对齐 web css 背景)
      for (final z in zones) {
        canvas.drawRect(z, base);
        _checker(canvas, z, cell, check);
      }
      final dashed = _dashPath(Path()..addRect(total), 7 / scale, 5 / scale);
      canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x77000000)
          ..strokeWidth = 4.5 / scale,
      );
      canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent
          ..strokeWidth = 2.2 / scale,
      );
    } else {
      final dashed = _dashPath(Path()..addRect(total), 7 / scale, 5 / scale);
      canvas.drawPath(
        dashed,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withValues(alpha: .6)
          ..strokeWidth = 2 / scale,
      );
    }
  }

  /// 屏幕空间的扩图把手(四边中点外侧,固定屏幕尺寸)与总尺寸标签:
  /// 把手内容 = 该向 padding 数值(>0)或朝外双 chevron(=0,提示可拖)。
  void _paintExpandHandles(Canvas canvas) {
    Offset ts(double x, double y) =>
        Offset(x * scale + offset.dx, y * scale + offset.dy);
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final tl = ts(-padL.toDouble(), -padT.toDouble());
    final br = ts(iw + padR, ih + padB);
    final cx = (tl.dx + br.dx) / 2;
    final cy = (tl.dy + br.dy) / 2;
    const gap = 12.0;

    final handles = <({Offset c, bool horiz, Offset out})>[
      (c: Offset(cx, tl.dy - gap - 13), horiz: true, out: const Offset(0, -1)),
      (c: Offset(cx, br.dy + gap + 13), horiz: true, out: const Offset(0, 1)),
      (c: Offset(tl.dx - gap - 13, cy), horiz: false, out: const Offset(-1, 0)),
      (c: Offset(br.dx + gap + 13, cy), horiz: false, out: const Offset(1, 0)),
    ];
    for (final h in handles) {
      final rect = ui.Rect.fromCenter(
        center: h.c,
        width: h.horiz ? 60 : 26,
        height: h.horiz ? 26 : 60,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(13));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black.withValues(alpha: .30)
          ..strokeWidth = 3.5,
      );
      canvas.drawRRect(rr, Paint()..color = accent);
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black.withValues(alpha: .12)
          ..strokeWidth = 1,
      );
      // 恒显朝外双 chevron(数值反馈交给底部尺寸 chip)
      final perp = h.horiz ? const Offset(1, 0) : const Offset(0, 1);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..color = onAccent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      void chev(Offset tip) {
        final a = tip - h.out * 5 + perp * 5;
        final b = tip - h.out * 5 - perp * 5;
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(b.dx, b.dy),
          p,
        );
      }

      chev(h.c + h.out * 5.5);
      chev(h.c - h.out * 0.5);
    }
  }

  /// 屏幕空间胶囊标签(主题色底 + 反色字),裁切/扩图尺寸共用。
  void _screenLabel(Canvas canvas, String text, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: onAccent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(pos.dx, pos.dy - 4, tp.width + 16, 22),
      const Radius.circular(5),
    );
    canvas.drawRRect(r, Paint()..color = accent);
    tp.paint(canvas, pos + const Offset(8, -1));
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.image != image ||
      old.imageOffset != imageOffset ||
      // 实心⇄轮廓的切换不改 rev,得单独比
      (old.maskOutline == null) != (maskOutline == null) ||
      old.rev != rev ||
      old.scale != scale ||
      old.offset != offset ||
      old.crop != crop ||
      old.cropActive != cropActive ||
      old.expandUi != expandUi ||
      old.padL != padL ||
      old.padT != padT ||
      old.padR != padR ||
      old.padB != padB ||
      old.cursor != cursor ||
      old.finger != finger ||
      old.brush != brush ||
      old.erasing != erasing ||
      old.accent != accent ||
      old.preview != preview ||
      old.previewDst != previewDst ||
      old.censorImg != censorImg ||
      old.censorSolid != censorSolid ||
      old.censorColor != censorColor;
}

/// 棋盘格填充(隔格绘制),cell 为图空间尺寸。
void _checker(ui.Canvas canvas, ui.Rect r, double cell, Paint p) {
  canvas.save();
  canvas.clipRect(r);
  final x0 = (r.left / cell).floor();
  final x1 = (r.right / cell).ceil();
  final y0 = (r.top / cell).floor();
  final y1 = (r.bottom / cell).ceil();
  for (var gy = y0; gy < y1; gy++) {
    for (var gx = x0; gx < x1; gx++) {
      if ((gx + gy).isEven) {
        canvas.drawRect(ui.Rect.fromLTWH(gx * cell, gy * cell, cell, cell), p);
      }
    }
  }
  canvas.restore();
}

/// 把路径虚线化(按弧长步进抽段)。
Path _dashPath(Path src, double dash, double gap) {
  final out = Path();
  for (final metric in src.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      final len = math.min(dash, metric.length - d);
      out.addPath(metric.extractPath(d, d + len), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}

// ---------- 小部件 ----------

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, size: 21, color: scheme.onSurface),
        ),
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final fg = active ? scheme.onPrimary : scheme.onSurfaceVariant;
    // 底色由外面那枚滑动色块负责,这里只剩文字/图标。用 GestureDetector 不用
    // InkWell:水波会在色块滑过来之前先亮一下,那正是"闪选中态"。
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 撑满分段槽高度:整格可点,而非只有文本行高那一条
        child: SizedBox.expand(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 前景色跟着药丸一起过渡,不然药丸滑到一半字还是旧颜色
              TweenAnimationBuilder<Color?>(
                duration: Motion.medium,
                curve: Motion.emphasized,
                tween: ColorTween(end: fg),
                builder: (_, c, _) => Icon(icon, size: 15, color: c),
              ),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: Motion.medium,
                curve: Motion.emphasized,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  /// 非选中态的着色(清空按钮的 error 色)。
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final bg = active ? scheme.primaryContainer : Colors.transparent;
    final fg = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: .35)
        : active
        ? scheme.onPrimaryContainer
        : (tint ?? scheme.onSurfaceVariant);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 62,
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 21, color: fg),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParamChip extends StatelessWidget {
  const _ParamChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
    this.swatch,
  });

  /// 非空时用实心色块替代图标(颜色本身就是读数,画个调色板图标反而更绕)。
  final Color? swatch;

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      // 与创作页吸底栏的读数按钮(_ReadoutChip)同色。原先用浅一档的
      // surfaceContainerHigh,和画布底色几乎分不开,看着发灰。
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // 边框常在(不选中时透明):BoxDecoration 的边框会算进内边距,
          // 有无之间差 2px —— 只在选中时给,整行按钮会跟着抖。
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: .6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              if (swatch case final c?)
                Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    // 白色块压在浅底上会消失,描一圈边兜底
                    border: Border.all(
                      color: scheme.onSurfaceVariant.withValues(alpha: .45),
                    ),
                  ),
                )
              else
                Icon(icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '$label $value',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 扩图尺寸弹窗:宽/高各一行,± 步进 64 或直接输入;确定返回目标尺寸
/// (非法输入回退为打开时的值,等效未修改)。
class _ExpandSizeDialog extends StatefulWidget {
  const _ExpandSizeDialog({
    required this.initW,
    required this.initH,
    required this.minW,
    required this.minH,
  });

  final int initW, initH;
  final int minW, minH; // 原图尺寸 = 下限

  @override
  State<_ExpandSizeDialog> createState() => _ExpandSizeDialogState();
}

class _ExpandSizeDialogState extends State<_ExpandSizeDialog> {
  late final TextEditingController _w = TextEditingController(
    text: '${widget.initW}',
  );
  late final TextEditingController _h = TextEditingController(
    text: '${widget.initH}',
  );

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _step(TextEditingController ctl, int fallback, int minV, int delta) {
    final cur = int.tryParse(ctl.text.trim()) ?? fallback;
    final next = math.max(minV, ((cur + delta) / 64).round() * 64);
    ctl.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
  }

  Widget _row(String label, TextEditingController ctl, int fallback, int minV) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        IconButton.filledTonal(
          onPressed: () => _step(ctl, fallback, minV, -64),
          icon: const Icon(Icons.remove, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: ctl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          onPressed: () => _step(ctl, fallback, minV, 64),
          icon: const Icon(Icons.add, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('扩图尺寸'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row('宽', _w, widget.initW, widget.minW),
          const SizedBox(height: 10),
          _row('高', _h, widget.initH, widget.minH),
          const SizedBox(height: 12),
          Text(
            '原图 ${widget.minW}×${widget.minH},增量对称分配到两侧(64 对齐)',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            w: int.tryParse(_w.text.trim()) ?? widget.initW,
            h: int.tryParse(_h.text.trim()) ?? widget.initH,
          )),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 「按住对比」:按住期间隐藏遮罩/裁切框,只看原图。
class _CompareButton extends StatelessWidget {
  const _CompareButton({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Listener(
      onPointerDown: (_) => onChanged(true),
      onPointerUp: (_) => onChanged(false),
      onPointerCancel: (_) => onChanged(false),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, size: 16, color: scheme.onSurface),
            const SizedBox(width: 7),
            Text(
              '按住对比',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

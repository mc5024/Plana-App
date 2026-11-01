import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show DragStartBehavior, HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderAnimatedSize,
        RenderMetaData,
        SliverConstraints,
        SliverGridGeometry,
        SliverGridLayout;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/fast_scroll_handle.dart';
import '../../../core/util/document_save.dart';
import '../../generate/models.dart' show modelName;
import '../../generate/widgets/common.dart'
    show ExpandBody, hintSnack, sharedAxisRoute;
import '../../import/import_panel.dart';
import '../albums/album_models.dart';
import '../albums/album_state.dart';
import '../albums/album_ui.dart';
import '../gallery_date_filter.dart';
import '../gallery_dates.dart';
import '../gallery_groups.dart';
import '../gallery_search.dart';
import '../gallery_state.dart';
import '../models.dart';
import '../phone_gallery_save.dart';
import '../save_pipeline.dart';
import '../save_settings.dart';
import '../share_pipeline.dart';
import 'album_name_sheet.dart';
import 'gallery_date_sheet.dart';
import 'justified_grid.dart';
import 'result_badge_chip.dart';
import 'result_thumb.dart';
import 'stack_card.dart';
import 'zip_pack_sheet.dart';
import '../../../core/util/haptics.dart';

/// 「›」展开:先显示相册封面墙。首个固定相册「全部相册」收纳所有作品；点开后
/// 按时间分段浏览，仍可切成按角色 / 按画风堆叠(归属见 gallery_groups)。
/// 可按模型/时间筛选、按提示词标签搜索(数据源 gallery_search 检索索引,
/// 筛选条件全 AND 组合)。
/// 点选一张即回填画布并关闭;长按弹出该张的导入 / 保存 / 删除菜单。
/// 多选只从右上角「多选」进,段头可整段全选,底部批量保存相册 / 分享 /
/// 打包 ZIP / 批量删除 —— 批量操作只作用于当前可见集合。
/// [trash]:直接打开回收站(图库空了、只剩回收站时的入口)。
Future<void> showGalleryGrid(BuildContext context, {bool trash = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GalleryGridSheet(trash: trash),
    );

/// 「全部图库」首次打开时提一次长按 —— 网格里点一下是选中回填画布,
/// 长按才是放大预览 + 导入/保存/删除那套,不说没人会去按。
const _kGridHintKey = 'hint_grid_longpress';

/// 记住上次关闭时所在的相册页面和「全部相册」按时间列表里的位置。
/// 再次打开时直接画出对应页面和位置，避免先画顶部再跳到旧位置。
bool _resumeAllAlbum = false;
String? _resumeAlbumId;
double _allAlbumOffset = 0;
final Map<String, double> _albumOffsets = {};

const _allAlbumKey = 'all-album';

class _GalleryGridSheet extends ConsumerStatefulWidget {
  const _GalleryGridSheet({this.trash = false});

  final bool trash;

  @override
  ConsumerState<_GalleryGridSheet> createState() => _GalleryGridSheetState();
}

class _GalleryGridSheetState extends ConsumerState<_GalleryGridSheet>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _albumHome = !_resumeAllAlbum;
  String? _activeAlbumId = _resumeAlbumId;
  String? _pendingAlbumId;
  bool? _pendingAlbumHome;
  bool _selecting = false;
  final Set<String> _picked = {};

  /// 相册首页的多选勾的是整本相册(「全部相册」不在其列)。
  final Set<String> _pickedAlbums = {};
  bool _saving = false;
  bool _sharing = false;
  bool _zipping = false;
  bool _organizing = false;
  // 保存 / 分享 / 打包共用这对计数(三件事不会同时跑,canAct 互斥)
  int _saveDone = 0;
  int _saveTotal = 0;

  // ---- 检索/筛选(弹层内临时态,关弹层即重置) ----
  final _searchCtrl = TextEditingController();
  // 焦点显式管理:搜索框在 ExpandBody 里是**常驻构建**的(只是高度收成 0),
  // 用 autofocus 会在弹层一打开就抢焦点弹键盘 —— 用户还没想搜。
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  bool _searchOpen = false;
  String _query = '';
  String? _modelFilter; // null=全部;''=未知(无参数快照的老图)
  // 保存日历日期；相对日期跨日与恢复前台时重新计算。
  late GalleryDateFilter _dateFilter = ref.read(uiPrefsProvider).dateFilter;
  late final Timer _dateTick;

  // 分组维度:每进一本相册都从按时间起,只在这次浏览里换。
  GalleryGroupBy _groupBy = GalleryGroupBy.day;

  // ---- 双指捏合改列数 ----
  //
  // 走 Listener 而不是 GestureDetector(onScale*):后者会把**单指**拖动也拉进
  // 手势竞技场,和列表自己的竖向滚动抢,滚动就废了。Listener 只旁听原始指针事件、
  // 完全不参与竞技场;列表则在捏合期间换上 [_FrozenScrollPhysics] —— 不滚,
  // 但仍占着手势,免得弹层的下拉关闭捡漏。
  //
  // **手势只负责触发,不负责驱动**:指间距过阈值就换一档,过渡由 [_morph] 自己
  // 跑完。曾经做过全程跟手的版本(进度实时跟指间距走),那样手指的微抖会一分不差
  // 地变成网格几何,整片图跟着颤;死区、增益、低通三道一起上也压不干净 ——
  // 换一档本来就是个离散决定,拿连续量去驱动它是自找的麻烦。
  //
  // 过渡本身仍是 [_ZoomGridDelegate] 的几何插值:每一格从旧位置连续走到新位置,
  // 而不是整片画面缩放再交叉淡化。
  late int _cols = ref.read(uiPrefsProvider).galleryColumns;

  /// 触发一档所需的指间距倍率。取对数看两个方向基本对称(±0.22)。
  static const _kZoomIn = 1.25; // 撑开到 1.25 倍 → 少一列
  static const _kZoomOut = .8; // 收拢到 0.8 倍 → 多一列

  final _pointers = <int, Offset>{};
  double? _span0; // 基准指间距;每换一档就重取,于是可以一路捏下去
  final _bodyKey = GlobalKey();

  /// 过渡中的目标列数;null = 没在过渡。
  int? _toCols;

  /// 当前列数 → 目标列数的进度 0..1,网格几何按它插值。只由 [_morph] 驱动。
  double _t = 0;

  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );

  final ScrollController _albumCtrl = ScrollController();
  final Map<String, ScrollController> _photoCtrls = {};

  /// 眼下挂在列表上的那一个:相册首页是 [_albumCtrl],进了相册是 [_ctrl]。
  /// 捏合回正、回顶这类「对着眼前这张列表」的操作都认它。
  ScrollController get _listCtrl => _albumHome ? _albumCtrl : _ctrl;

  ScrollController get _ctrl {
    final key = _activeAlbumId ?? '';
    return _photoCtrls.putIfAbsent(key, () {
      final ctrl = ScrollController(
        initialScrollOffset: key.isEmpty
            ? _allAlbumOffset
            : (_albumOffsets[key] ?? 0),
      );
      ctrl.addListener(_remember);
      return ctrl;
    });
  }

  // 锚定:把「触发那一刻焦点落在内容里的相对位置」钉住,否则列数一变内容总高
  // 跟着变,画面会整体上下漂。
  double _anchorOff = 0, _anchorContent = 0, _focalY = 0;

  // ---- 进出堆的过场 ----
  //
  // 走 Material 的 fade-through:先把旧内容淡出,**在中间换掉**,再淡入并从 94%
  // 长回原样。两头不重叠正是这个范式的用意 —— 封面墙与堆内网格没有任何共同元素,
  // 强行交叉淡化只会糊成一团。
  //
  // 相册首页和图片列表各有自己的 ScrollController，切换时不用在绘制后 jumpTo，
  // 也不会把旧页的滚动位置短暂画在新页上。
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: _kOpenDuration,
  );

  /// 淡出 60 + 淡入 120。面板高度要变时,两段中间再插一段升降
  /// ([_kResizeDuration]),期间面板是空的。
  static const _kOpenDuration = Duration(milliseconds: 180);

  /// 淡出占整段的比例;之后是淡入。
  static const _kFadeOut = 1 / 3;

  /// 面板高度动画。
  static const _kResizeDuration = Duration(milliseconds: 120);

  /// 过场停在换内容那一刻,等面板升降到位。
  bool _held = false;

  /// 每次过场加一;停住期间又开了新过场,旧的那次到位就不再续跑。
  int _holdGen = 0;

  /// 面板那层 AnimatedSize:换内容后看它在不在升降。
  final _panelKey = GlobalKey();

  String? _pendingOpen;
  bool _openApplied = true;

  /// 封面墙的滚动位置。进堆时记下,回来时还原 —— 逛到一半点进去,回来还在原处。
  double _wallOffset = 0;

  /// 堆叠视图里**已经点开**的那一堆(键);null = 正看封面墙。
  ///
  /// 换分组维度时清掉(那一堆在新维度下不存在)。**筛选变化不清** —— 堆是从
  /// 筛选后的集合算出来的,所以在堆里搜索是在这一堆内收窄;收窄到空时这一堆
  /// 自己就没了,build 里那句 firstOrNull 取不到,自动退回封面墙。
  String? _openKey;

  /// 顶栏尾部那几颗文字按钮(多选 / 全选 / 完成)的样式。
  ///
  /// M3 的 TextButton 默认 `minimumSize: Size(64, 40)`,而「多选」两个字才二十
  /// 来像素宽 —— 撑到 64 之后,多出来的宽度平摊到两侧成了额外内边距,文字被推得
  /// 离右缘比左边标题离左缘远出十来像素,一眼就是右边没贴边。这里把最小宽度放开、
  /// 内边距写死成 12,配合容器的 8,文字落点与左边的 20 对齐。
  ///
  /// 高度仍留 40,且 tapTargetSize 保持默认(padded)—— 触摸区照样撑到 48,
  /// 只是不再把视觉往里推。
  static final _headerBtn = TextButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 12),
  );

  // ---- 多选操作栏的几何 ----
  static const _actH = 46.0;
  static const _actSubH = 38.0;
  static const _actGap = 10.0;

  /// 次行三颗按钮:M3 默认给带图标的按钮留 16/24 的内边距,三颗平分一行就只
  /// 剩下十来个像素放字。收到 10 —— 高度本来也矮一档,窄一点不违和。
  static final _subActBtn = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 10),
  );

  /// 首行三颗(保存 / 移动 / 删除)同理:M3 默认 16/24 的内边距在三等分里
  /// 放不下「保存 (12)」,收到 8,文字再 scaleDown 兜底。
  static final _mainActBtn = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
  );

  /// 次行按钮的文字:窄屏上宁可缩一号也别溢出(「自定义相册」四五个字最吃紧,
  /// 进度态的「准备 8/12」也长)。
  static Widget _fitLabel(String text) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dateTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _dateFilter.active) setState(() {});
    });
    _morph.addStatusListener(_onMorphDone);
    _morph.addListener(_onMorphTick);
    _open.addListener(_onOpenTick);
    // 刚设过保存相册:这次直接进那本,不管上次关在哪一页。
    final land = ref.read(albumsProvider.notifier).takeGridLanding();
    if (land != null) {
      _albumHome = false;
      _activeAlbumId = land.id;
    }
    if (widget.trash) {
      _albumHome = false;
      _activeAlbumId = trashId;
    }
    _ctrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(galleryProvider.notifier).purgeExpiredTrash();
    });
    // 相册数据是从备份恢复的 / 读不出来:打开时说一次(读不出来时「新建」是灰
    // 的,不说看不出为什么)。和下面的首次提示撞上时先说这个,那条留到下次。
    final albums = ref.read(appStoresProvider).albums;
    final warning = albums.warning;
    if (warning != null) {
      albums.warning = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) hintSnack(context, warning);
      });
      return;
    }
    final prefs = ref.read(prefsStoreProvider);
    if (prefs.get(_kGridHintKey) != null) return;
    prefs.write(key: _kGridHintKey, value: '1');
    // 弹层刚推进来那一帧 overlay 还没稳,推到帧后再弹
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        hintSnack(
          context,
          '点开「全部相册」后，长按图片可预览并导入 / 保存 / 删除',
          icon: Icons.touch_app_outlined,
        );
      }
    });
  }

  /// 过渡每一帧:推进插值进度并回正滚动位置。
  void _onMorphTick() {
    setState(() => _t = Motion.emphasized.transform(_morph.value));
    _reanchorAfterLayout();
  }

  void _onMorphDone(AnimationStatus st) {
    if (st != AnimationStatus.completed) return;
    _endMorph();
    _persistCols();
  }

  /// 进出堆:淡出跑到一半时把内容换掉,后半段淡入。
  /// 每帧的透明度 / 缩放由 [_openLayer] 自己跟,这里只管换内容那一下 ——
  /// 不整页 setState,否则过场每一帧都要把筛选、分组、相册归属重算一遍。
  void _onOpenTick() {
    if (_openApplied || _open.value < _kFadeOut) return;
    _openApplied = true;
    _applyOpen();
    // 先停在换内容这一刻,淡入从 0 起;面板要升降的话等它到位再淡入,
    // 新内容不和升降中的面板同时出现。
    _open.value = _kFadeOut;
    _held = true;
    final gen = _holdGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panel = _panelKey.currentContext?.findRenderObject();
      if (panel is RenderAnimatedSize && panel.isAnimating) {
        // 正常由 AnimatedSize 的 onEnd 接着淡入;它中途改成直接跳到新尺寸时
        // 不报结束,超时兜底
        Future<void>.delayed(_kResizeDuration * 1.5, () => _resumeOpen(gen));
      } else {
        _resumeOpen(gen);
      }
    });
  }

  /// 面板到位:接着淡入。[gen] 不是当前这次过场就不管。
  void _resumeOpen([int? gen]) {
    if (!mounted || !_held || (gen != null && gen != _holdGen)) return;
    _held = false;
    _open.forward();
  }

  /// 开一次过场,内容不当场换,交给 [_onOpenTick] 在过场中点换。
  void _startOpen() {
    _holdGen++;
    _held = false;
    _openApplied = false;
    _open.forward(from: 0);
  }

  /// 点开某一堆 / 回封面墙。
  void _setOpen(String? key) {
    if (key == _openKey) return;
    _pendingOpen = key;
    _startOpen();
  }

  void _setAlbumHome(bool home) {
    if (home == _albumHome) return;
    if (home) _searchFocus.unfocus();
    _pendingAlbumHome = home;
    _startOpen();
  }

  /// 正看着回收站。
  bool get _inTrash => !_albumHome && _activeAlbumId == trashId;

  void _openAlbum(String? id) {
    // 回收站、收藏只在面板里看,胶片条不跟过去
    if (id != trashId &&
        id != favoritesId &&
        ref.read(galleryBrowseAlbumProvider) != id) {
      ref.read(albumsProvider.notifier).browse(id);
    }
    _pendingAlbumId = id;
    _setAlbumHome(false);
  }

  Future<void> _createAlbum() async {
    final id = await showAlbumName(context);
    if (id != null && mounted) _openAlbum(id);
  }

  /// 长按相册卡:和长按图片同一套抬起菜单,封面浮起、菜单从下沿卷出。
  /// 「设为保存相册」与封面角上的开关是同一件事,两处都能点。
  Future<void> _albumLongPress(
    String? id,
    ResultImage? cover,
    Rect from, {
    required bool isSave,
    IconData? icon,
  }) async {
    Haptics.medium();
    final warm = cover == null
        ? null
        : await _warmFull(
            cover,
          ).timeout(const Duration(milliseconds: 300), onTimeout: () => null);
    if (!mounted) return;
    final nav = Navigator.of(context);
    final box = nav.overlay?.context.findRenderObject() as RenderBox?;
    final at = box == null ? from : box.globalToLocal(from.topLeft) & from.size;
    final picked = await nav.push(
      _ThumbMenuRoute(
        from: at,
        result: cover,
        warm: warm,
        square: true,
        emptyIcon: icon ?? Icons.photo_library_outlined,
        actions: id == trashId
            ? const [(icon: Icons.restore, label: '全部恢复', value: 'restore')]
            : [
                if (!isSave)
                  (
                    icon: Icons.move_to_inbox_outlined,
                    label: '设为保存相册',
                    value: 'save',
                  ),
                // 「全部相册」不能改名也不能删
                if (id != null)
                  (
                    icon: Icons.drive_file_rename_outline,
                    label: '重命名',
                    value: 'rename',
                  ),
              ],
        danger: id == null
            ? null
            : id == trashId
            ? (
                icon: Icons.delete_forever_outlined,
                label: '清空回收站',
                value: 'empty',
              )
            : (icon: Icons.delete_outline, label: '删除相册', value: 'delete'),
      ),
    );
    if (picked != null && mounted) await _albumMenu(id, picked);
  }

  Future<void> _albumMenu(String? id, String action) async {
    final notifier = ref.read(albumsProvider.notifier);
    final gallery = ref.read(galleryProvider.notifier);
    final trash = [for (final t in ref.read(galleryProvider).trash) t.image.id];
    try {
      if (action == 'restore') {
        final n = gallery.restoreTrash(trash);
        hintSnack(context, '已恢复 $n 张', icon: Icons.restore);
      } else if (action == 'empty') {
        if (!await _confirmPurge('清空回收站?', '清空') || !mounted) return;
        gallery.purgeTrash(trash);
        hintSnack(
          context,
          '已彻底删除 ${trash.length} 张',
          icon: Icons.delete_forever_outlined,
        );
      } else if (action == 'save') {
        _setSaveAlbum(id);
      } else if (action == 'rename' && id != null) {
        await showAlbumName(context, album: ref.read(albumsProvider).album(id));
      } else if (action == 'delete' && id != null) {
        final name = ref.read(albumsProvider).name(id);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('删除「$name」？'),
            content: const Text('只删除相册，图片仍保留在全部相册。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除相册'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) await notifier.delete(id);
      }
    } catch (e) {
      if (mounted) albumError(context, e);
    }
  }

  void _setSaveAlbum(String? id) {
    try {
      ref.read(albumsProvider.notifier).setSave(id);
      if (mounted) {
        hintSnack(context, '新图将保存到「${ref.read(albumsProvider).name(id)}」');
      }
    } catch (e) {
      if (mounted) albumError(context, e);
    }
  }

  void _applyOpen() {
    final albumHome = _pendingAlbumHome;
    if (albumHome != null) {
      _pendingAlbumHome = null;
      _remember();
      setState(() {
        _albumHome = albumHome;
        _activeAlbumId = albumHome ? null : _pendingAlbumId;
        _pendingAlbumId = null;
        _openKey = null;
        if (!albumHome) _groupBy = GalleryGroupBy.day;
      });
      return;
    }
    final key = _pendingOpen;
    // 从封面墙进堆:记下墙滚到哪了,回来时还原
    if (_openKey == null && _ctrl.hasClients) _wallOffset = _ctrl.offset;
    final want = key == null ? _wallOffset : 0.0;
    setState(() => _openKey = key);
    // 新内容的高度要等布局跑完才知道,位置只能帧后再落。这一刻画面正淡着,看不见。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      _ctrl.jumpTo(want.clamp(0.0, _ctrl.position.maxScrollExtent));
    });
  }

  /// 落定:目标列数坐实成当前列数。中途被新的一档打断时也走这里。
  void _endMorph() {
    final to = _toCols;
    if (to == null) return;
    setState(() {
      _cols = to;
      _toCols = null;
      _t = 0;
    });
  }

  // ---- 「全部相册」滚动位置与回顶 ----

  /// 记下眼下停的位置。
  ///
  /// 有搜索词或模型筛选时不记:那是筛过的列表,而这两样关弹层就清,下次打开对着的
  /// 是没筛的列表,拿筛过的位置去落只会错位 —— 停在筛之前记的那一次上。进出堆的
  /// 过场中也不记。
  void _remember() {
    if (_albumHome ||
        _groupBy != GalleryGroupBy.day ||
        _openKey != null ||
        _query.isNotEmpty ||
        _modelFilter != null ||
        _open.isAnimating ||
        _held) {
      return;
    }
    if (!_ctrl.hasClients || _ctrl.positions.length != 1) return;
    final p = _ctrl.position;
    if (!p.hasContentDimensions) return;
    if (_activeAlbumId == null) {
      _allAlbumOffset = p.pixels;
    } else {
      _albumOffsets[_activeAlbumId!] = p.pixels;
    }
  }

  /// 回顶。离得远时先跳到离顶一屏半的地方再滑:一路滑过几十屏会把沿途每一行
  /// 缩略图都建出来、读一遍盘,滑的那一两秒全是卡的。
  void _scrollToTop() {
    final c = _listCtrl;
    if (!c.hasClients || c.positions.length != 1) return;
    final p = c.position;
    final near = p.viewportDimension * 1.5;
    if (p.pixels > near) c.jumpTo(near);
    c.animateTo(0, duration: Motion.slow, curve: Motion.emphasized);
  }

  /// 顶栏的回顶按钮:滚过一屏才出现,回到一屏以内收起。只跟着滚动重建它自己。
  Widget _topButton(ColorScheme scheme, {required bool hasList}) =>
      ListenableBuilder(
        listenable: _listCtrl,
        builder: (context, _) {
          final c = _listCtrl;
          final far =
              hasList &&
              c.hasClients &&
              c.positions.length == 1 &&
              c.position.hasViewportDimension &&
              c.offset > c.position.viewportDimension;
          return AnimatedSwitcher(
            duration: Motion.fast,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SizeTransition(
                sizeFactor: a,
                axis: Axis.horizontal,
                child: child,
              ),
            ),
            child: far
                ? IconButton(
                    key: const ValueKey(true),
                    onPressed: _scrollToTop,
                    visualDensity: VisualDensity.compact,
                    tooltip: '回到顶部',
                    icon: Icon(
                      Icons.vertical_align_top,
                      size: 21,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey(false)),
          );
        },
      );

  @override
  void deactivate() {
    // 关弹层前最后记一次:开着期间出了新图、删了图,内容高变了却没滚过,
    // 滚动监听是收不到的
    _remember();
    super.deactivate();
  }

  @override
  void dispose() {
    // 回收站不记:下次打开回到相册首页
    _resumeAllAlbum = !_albumHome && !_inTrash;
    _resumeAlbumId = _albumHome || _inTrash ? null : _activeAlbumId;
    _remember();
    WidgetsBinding.instance.removeObserver(this);
    _dateTick.cancel();
    _edgeTicker?.dispose();
    _morph.dispose();
    _open.dispose();
    _albumCtrl.dispose();
    for (final ctrl in _photoCtrls.values) {
      ctrl.dispose();
    }
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
      }
    });
    // 只有明确点开搜索才弹键盘
    _searchOpen ? _searchFocus.requestFocus() : _searchFocus.unfocus();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v);
    });
  }

  // ---- 筛选谓词(模型 × 时间 × 搜索,全 AND) ----

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _dateFilter.active) {
      setState(() {});
    }
  }

  bool _passModel(ResultImage r, Map<String, GallerySearchMeta> byId) {
    final want = _modelFilter;
    if (want == null) return true;
    return (byId[r.id]?.model ?? '') == want;
  }

  bool _passQuery(
    ResultImage r,
    Map<String, GallerySearchMeta> byId,
    List<String> terms,
  ) {
    if (terms.isEmpty) return true;
    final meta = byId[r.id];
    return meta != null && searchMatch(meta.text, terms);
  }

  /// 单选弹层(模型/时间共用):选项 = (文案, 值, 计数);值用单元素 record
  /// 包一层再 pop,可空的 T(全部=null)才与「取消」区分得开。
  Future<void> _pickFilter<T>({
    required String title,
    required List<(String, T, int?)> options,
    required T current,
    required ValueChanged<T> onPick,
  }) async {
    final scheme = context.scheme;
    // 弹层关闭后焦点会回落到搜索框(它一直在树里),不先收就会顺带弹出键盘
    _searchFocus.unfocus();
    final picked = await showModalBottomSheet<(T,)>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final (label, value, count) in options)
                ListTile(
                  dense: true,
                  onTap: () => Navigator.pop(ctx, (value,)),
                  title: Text(label, style: context.texts.bodyMedium),
                  trailing: value == current
                      ? Icon(Icons.check, size: 18, color: scheme.primary)
                      : (count == null
                            ? null
                            : Text(
                                '$count',
                                style: mono(
                                  context,
                                  size: 12,
                                  color: scheme.outline,
                                ),
                              )),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked.$1);
  }

  void _pickModelFilter(
    List<ResultImage> results,
    Map<String, GallerySearchMeta> byId,
  ) {
    // 模型清单按整库统计(不按筛选后,免得选中一个后其余选项全消失)
    final counts = <String, int>{};
    for (final r in results) {
      counts.update(byId[r.id]?.model ?? '', (v) => v + 1, ifAbsent: () => 1);
    }
    final models = [
      for (final k in counts.keys)
        if (k.isNotEmpty) k,
    ]..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    _pickFilter<String?>(
      title: '按模型筛选',
      current: _modelFilter,
      options: [
        ('全部', null, null),
        for (final m in models) (modelName(m), m, counts[m]),
        if ((counts[''] ?? 0) > 0) ('未知', '', counts['']),
      ],
      onPick: (v) => setState(() => _modelFilter = v),
    );
  }

  Future<void> _pickTimeFilter() async {
    _searchFocus.unfocus();
    final filter = await showGalleryDateFilter(context, _dateFilter);
    if (filter == null || !mounted) return;
    ref
        .read(uiPrefsProvider.notifier)
        .patch((p) => p.copyWith(galleryDateFilter: filter));
    setState(() => _dateFilter = filter);
  }

  void _pickGroupBy() {
    // 不带计数:算另外两个维度的归属要把它们的 provider 都拉起来,而用户只是
    // 想换个分组。归不了的有多少,封面墙上那堆「未归类」自己会说。
    _pickFilter<GalleryGroupBy>(
      title: '分组方式',
      current: _groupBy,
      options: [for (final v in GalleryGroupBy.values) (v.label, v, null)],
      onPick: (v) {
        setState(() {
          _groupBy = v;
          _openKey = null; // 换了维度,原来点开的那一堆不存在了
        });
      },
    );
  }

  Widget _chip(
    ColorScheme scheme, {
    Key? key,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final fg = active ? context.onSelectedFill : scheme.onSurfaceVariant;
    return Material(
      key: key,
      color: active ? context.selectedFill : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 7, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.texts.bodySmall!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  /// 一段图的网格 sliver。分段列表与点开的单堆共用 —— 两边的交互(点选回填、
  /// 长按菜单、拖选的 MetaData 反查)必须逐条一致,写两遍迟早走岔。
  ///
  /// 缩略图本体还各带 5(描边 2.5 + 让位 2.5)的内缩,所以图与图之间实际留白 =
  /// 这里的 gap + 10。等高行排布,见 [JustifiedGridLayout]。
  Widget _gridSliver(List<ResultImage> items, String? selectedId) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        sliver: SliverGrid(
          gridDelegate: _zoomDelegate(
            (cols) =>
                JustifiedGridDelegate(items, cols: cols, gap: 6, inset: 10),
          ),
          delegate: SliverChildBuilderDelegate((_, i) {
            final r = items[i];
            // 拖选靠命中路径反查这个 id,见 _idAt
            return MetaData(
              metaData: r.id,
              child: _GridThumb(
                result: r,
                selected: !_selecting && !_inTrash && r.id == selectedId,
                picked: _selecting && _picked.contains(r.id),
                selecting: _selecting,
                // 回收站按删除时间分段,生成时刻不标
                showTime: !_inTrash,
                onTap: (from) {
                  if (_selecting) {
                    _toggle(r.id);
                  } else if (_inTrash) {
                    // 回收站里的图上不了画布,点一下就是抬起看看、恢复或彻底删除
                    _thumbMenu(r.id, from);
                  } else {
                    // 胶片条跟到面板停的这本:两边不一致时,点的这张可能
                    // 不在胶片条里,画布上就显示不出来。在收藏里点的:胶片条
                    // 里有这张就不动,没有就回到全部相册。
                    final browsing = ref.read(galleryBrowseAlbumProvider);
                    final scope = _activeAlbumId != favoritesId
                        ? _activeAlbumId
                        : ref.read(albumsProvider).contains(browsing, r.id)
                        ? browsing
                        : null;
                    if (browsing != scope) {
                      ref.read(albumsProvider.notifier).browse(scope);
                    }
                    ref.read(galleryProvider.notifier).select(r.id);
                    Navigator.of(context).pop();
                  }
                },
                // 捏合期间也关:两指按住不动够 500ms 就会在其中一张上弹菜单
                onLongPress: _selecting || _pinching
                    ? null
                    : (from) => _thumbMenu(r.id, from),
              ),
            );
          }, childCount: items.length),
        ),
      );

  /// 堆的封面墙:一堆一张卡。点一下进那一堆;多选态下点一下整堆全勾/全取消
  /// —— 封面墙这一层的「一个单位」就是一整堆,按单张勾在这里没有落点。
  Widget _stackSliver(ColorScheme scheme, List<GalleryGroup> groups) {
    // 封面是方的,底下还得放名字与张数两行 —— 那两行是**固定高**,不该跟着格宽缩,
    // 所以主轴高按「格宽 + 文字高」现算,而不是钉一个 childAspectRatio。
    // (钉比例的话,列数一多文字就被压没;跟着字号缩放走同理。)
    //
    // 宽度取 SliverConstraints.crossAxisExtent,不取屏宽 —— 弹层宽度未必等于屏宽
    // (主题给 bottomSheet 设了 constraints、或大屏上就会不等)。
    const pad = 12.0 * 2, gap = 6.0;
    final textH = 44 * MediaQuery.textScalerOf(context).scale(1);
    final saveAlbum = _albumHome
        ? ref.watch(gallerySaveTargetProvider).albumId
        : null;
    final albumData = ref.watch(albumsProvider);
    return SliverLayoutBuilder(
      builder: (_, cons) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        sliver: SliverGrid(
          gridDelegate: _zoomDelegate((cols) {
            final cellW =
                (cons.crossAxisExtent - pad - gap * (cols - 1)) / cols;
            return SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: gap,
              mainAxisExtent: cellW + textH,
            );
          }),
          delegate: SliverChildBuilderDelegate((_, i) {
            final g = groups[i];
            final albumId = g.key == _allAlbumKey ? null : g.key;
            final ids = _selecting && !_albumHome
                ? [for (final r in g.items) r.id]
                : const <String>[];
            final allOn =
                _selecting && !_albumHome && ids.every(_picked.contains);
            final coverIcon = _albumHome ? albumCoverIcon(albumId) : null;
            final cover = _albumHome && coverIcon == null
                ? albumCoverOf(albumData, albumId, g.items)
                : null;
            // 「全部相册」「收藏」「回收站」是固定的:不能多选,也没有改名 / 删除
            final fixed =
                _albumHome &&
                (albumId == null ||
                    albumId == favoritesId ||
                    albumId == trashId);
            return GalleryStackCard(
              group: g,
              cover: cover,
              coverIcon: coverIcon,
              // 相册多选勾的是整本;固定的两本不能选,不画勾选圈
              selecting: _selecting && !fixed,
              picked: _albumHome
                  ? _pickedAlbums.contains(albumId)
                  : _selecting && allOn,
              isSaveAlbum: _albumHome && saveAlbum == albumId,
              stacked: !_albumHome,
              // 「全部相册」只有「设为保存相册」一项,已经是保存相册时就没有菜单;
              // 「收藏」一项都没有;回收站空着时也没有
              onLongPress:
                  _albumHome &&
                      !_selecting &&
                      !_pinching &&
                      albumId != favoritesId &&
                      (albumId != trashId || g.items.isNotEmpty) &&
                      (albumId != null || saveAlbum != null)
                  ? (from) => _albumLongPress(
                      albumId,
                      cover,
                      from,
                      isSave: saveAlbum == albumId,
                      icon: coverIcon,
                    )
                  : null,
              onTap: () => setState(() {
                if (_selecting && _albumHome) {
                  if (albumId != null &&
                      !fixed &&
                      !_pickedAlbums.remove(albumId)) {
                    _pickedAlbums.add(albumId);
                  }
                } else if (_selecting) {
                  allOn ? _picked.removeAll(ids) : _picked.addAll(ids);
                } else if (_albumHome) {
                  _openAlbum(g.key == _allAlbumKey ? null : g.key);
                } else {
                  _setOpen(g.key);
                }
              }),
            );
          }, childCount: groups.length),
        ),
      ),
    );
  }

  /// 分段段头:组名 + 张数;多选态尾部整段全选/取消。
  ///
  /// 「全选」**叠**在段头上,不排进那一行:按钮再紧凑也有 32 高(默认点按区还要
  /// 撑到 40),排进去会把每个段头撑高一截 —— 一进多选,视口上方那些段头一齐
  /// 变高,整片网格就被往下推一段。叠上去之后段头在两种状态下一样高,点按区
  /// 照样竖着占满段头。
  ///
  /// [note]:张数后面再跟一句(回收站报还剩几天)。
  Widget _groupHeader(ColorScheme scheme, GalleryGroup g, {String? note}) {
    final ids = [for (final r in g.items) r.id];
    final allOn = ids.every(_picked.contains);
    return Stack(
      children: [
        Padding(
          // 跟着网格一起往里收 4:段头文字要和其下第一张图的左边缘对齐
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
          child: Row(
            children: [
              Text(
                g.label,
                style: context.texts.titleSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                note == null
                    ? '${g.items.length} 张'
                    : '${g.items.length} 张 · $note',
                style: context.texts.bodySmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_selecting)
          Positioned(
            right: 8,
            // 段头上留白 8、下留白 6:按钮顶端让出多的那 2,中线才和组名那行对齐
            top: 2,
            bottom: 0,
            child: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _saving || _zipping
                  ? null
                  : () => setState(
                      () =>
                          allOn ? _picked.removeAll(ids) : _picked.addAll(ids),
                    ),
              child: Text(allOn ? '取消' : '全选'),
            ),
          ),
      ],
    );
  }

  void _enterSelect([String? pick]) {
    setState(() {
      _selecting = true;
      if (pick != null) _picked.add(pick);
    });
  }

  void _exitSelect() {
    _dragSelectEnd();
    setState(() {
      _selecting = false;
      _picked.clear();
      _pickedAlbums.clear();
    });
  }

  void _toggle(String id) {
    setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
  }

  // ---- 滑动选择 ----
  //
  // 只认**横向**起手。竖向留给滚动 —— 多选态下照样要能翻到别的日期去,
  // 抢了竖向就等于把列表钉死。横向一旦被判定为拖选,后续 update 无论往哪个
  // 方向走都还归这个手势。
  //
  // 选的是**区间**(对齐系统相册):起手那张到手指下面那张之间、按列表顺序的每一张,
  // 跨日期段也连着;往回拖区间缩小,退出区间的回到起手前的样子。早先是「划过哪张
  // 选哪张」,可拖到列表边上要自动往下滚时,手指停着不动、图从底下滚过去,那样就
  // 只有手指所在的那一列被选上。
  //
  // 加/减看**起手那一格**的当前状态取反:从没选中的格子起手是整片选上,
  // 从已选中的起手是整片取消。
  bool? _dragAdding;
  String? _dragAnchor, _dragCurrent;

  /// 起手前的勾选集。区间每变一次都从它重算,缩回去的格子才回得去。
  Set<String> _dragBase = const {};

  /// 起手那一刻的排列顺序与下标。拖的途中来了新图也不换 —— 下标一挪区间就乱了。
  List<String> _dragOrder = const [];
  Map<String, int> _dragIndex = const {};

  /// 眼下这一屏的排列顺序:分段列表各段首尾相接 / 点开的那一堆;封面墙上没有
  /// (墙上一格是一整堆,不走拖选)。build 里刷新。
  List<String> _order = const [];

  // 贴边自动滚动:拖选时手指进了列表上下沿的感应带,就按贴得多近往那边滚,
  // 边滚边按手指下面那张续上区间。
  Offset? _dragPos; // 手指最近的屏幕坐标
  double _dragStartY = 0; // 起手时的屏幕纵坐标
  Ticker? _edgeTicker;
  Duration _edgeLast = Duration.zero;

  /// 感应带高度;列表太矮时按高度的四分之一收。
  static const _kEdgeBand = 56.0;

  /// 刚进感应带与贴到(越过)边缘时,每秒滚多少像素。
  static const _kEdgeMinSpeed = 120.0;
  static const _kEdgeMaxSpeed = 1500.0;

  /// 屏幕坐标 → 该点下面那张缩略图的 id。靠命中路径里的 [MetaData]
  /// (见网格 itemBuilder)反查,不自己按几何算 —— 网格是按日期分成多个
  /// sliver 的,中间还夹着日期头,几何换算既绕又容易在改版式后悄悄失准。
  String? _idAt(Offset globalPos) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      globalPos,
      View.of(context).viewId,
    );
    for (final e in hit.path) {
      final t = e.target;
      if (t is RenderMetaData) {
        final m = t.metaData;
        if (m is String) return m;
      }
    }
    return null;
  }

  void _dragSelectStart(DragStartDetails d) {
    // 起手坐标是按下的那一点(见 _dragSelectLayer 的 dragStartBehavior),
    // 不是越过横滑门槛之后的 —— 区间的起点得是手指落下的那张
    final id = _idAt(d.globalPosition);
    if (id == null) return;
    final index = <String, int>{
      for (var i = 0; i < _order.length; i++) _order[i]: i,
    };
    if (!index.containsKey(id)) return;
    _dragOrder = _order;
    _dragIndex = index;
    _dragAnchor = _dragCurrent = id;
    _dragAdding = !_picked.contains(id);
    _dragBase = Set.of(_picked);
    _dragPos = d.globalPosition;
    _dragStartY = d.globalPosition.dy;
    _applyDragRange();
  }

  void _dragSelectUpdate(DragUpdateDetails d) {
    if (_dragAdding == null) return;
    _dragPos = d.globalPosition;
    _trackDrag();
    final pull = _edgePull();
    if (pull == 0) {
      _edgeTicker?.stop();
    } else if (!(_edgeTicker?.isActive ?? false)) {
      _edgeLast = Duration.zero;
      (_edgeTicker ??= createTicker(_edgeTick)).start();
    }
  }

  void _dragSelectEnd() {
    _edgeTicker?.stop();
    _dragAdding = null;
    _dragAnchor = _dragCurrent = null;
    _dragBase = const {};
    _dragOrder = const [];
    _dragIndex = const {};
    _dragPos = null;
  }

  /// 手指下面换了一张就把区间终点挪过去。手指落在段头、缝里时沿用上一张。
  ///
  /// 探测点夹进网格视口:贴边滚动时手指常常已经拖出列表上下沿(压在筛选行或
  /// 底部操作栏上),照样认视口边上那一行。
  void _trackDrag() {
    final pos = _dragPos;
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (pos == null || box == null || !box.hasSize) return;
    final local = box.globalToLocal(pos);
    final id = _idAt(
      box.localToGlobal(
        Offset(
          local.dx.clamp(1.0, math.max(1.0, box.size.width - 1)),
          local.dy.clamp(1.0, math.max(1.0, box.size.height - 1)),
        ),
      ),
    );
    if (id == null || id == _dragCurrent || !_dragIndex.containsKey(id)) {
      return;
    }
    _dragCurrent = id;
    _applyDragRange();
  }

  void _applyDragRange() {
    final a = _dragIndex[_dragAnchor], c = _dragIndex[_dragCurrent];
    final adding = _dragAdding;
    if (a == null || c == null || adding == null) return;
    setState(() {
      _picked
        ..clear()
        ..addAll(_dragBase);
      for (var i = math.min(a, c); i <= math.max(a, c); i++) {
        adding ? _picked.add(_dragOrder[i]) : _picked.remove(_dragOrder[i]);
      }
    });
  }

  /// 往哪边滚、有多急:-1..1,0 = 不滚。越贴近列表上 / 下沿越接近 ±1,
  /// 拖出边缘就是满格。
  ///
  /// 起手就在感应带里的(比如从最后一行开始横扫),得先朝那条边再挪一截才算数 ——
  /// 不然刚按下去横着扫一行,列表就自己跑了。
  double _edgePull() {
    final pos = _dragPos;
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (pos == null || box == null || !box.hasSize) return 0;
    final h = box.size.height;
    final band = math.min(_kEdgeBand, h / 4);
    final y = box.globalToLocal(pos).dy;
    final startY = box.globalToLocal(Offset(pos.dx, _dragStartY)).dy;
    const arm = 16.0;
    if (y > h - band && (startY <= h - band || y - startY > arm)) {
      return ((y - (h - band)) / band).clamp(0.0, 1.0);
    }
    if (y < band && (startY >= band || startY - y > arm)) {
      return -((band - y) / band).clamp(0.0, 1.0);
    }
    return 0;
  }

  void _edgeTick(Duration elapsed) {
    final dt = (elapsed - _edgeLast).inMicroseconds / 1e6;
    _edgeLast = elapsed;
    final pull = _edgePull();
    if (pull == 0 ||
        _dragAdding == null ||
        !_selecting ||
        !_ctrl.hasClients ||
        _ctrl.positions.length != 1) {
      _edgeTicker?.stop();
      return;
    }
    // 先按这一帧的画面认手指下面那张,再滚 —— 滚过去的新布局要下一帧才有
    _trackDrag();
    final p = _ctrl.position;
    final t = pull.abs();
    // 二次方起步:刚碰到感应带时慢慢挪,越往边上压越快
    final speed = _kEdgeMinSpeed + (_kEdgeMaxSpeed - _kEdgeMinSpeed) * t * t;
    final to = (p.pixels + pull.sign * speed * dt).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (to == p.pixels) {
      // 已经滚到头:停下,手指再动时 _dragSelectUpdate 会重新判断
      if (dt > 0) _edgeTicker?.stop();
      return;
    }
    _ctrl.jumpTo(to);
  }

  double get _span {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  Offset get _mid {
    final p = _pointers.values.toList();
    return (p[0] + p[1]) / 2;
  }

  /// 双指按住中。此时列表换 [_FrozenScrollPhysics]:不滚,但仍参与手势竞技场。
  bool get _pinching => _pointers.length >= 2;

  void _persistCols() {
    if (_cols == ref.read(uiPrefsProvider).galleryColumns) return;
    ref
        .read(uiPrefsProvider.notifier)
        .patch((p) => p.copyWith(galleryColumns: _cols));
  }

  /// 记下锚点:触发那一刻焦点落在**内容**里的相对位置。
  void _takeAnchor() {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    _focalY = box == null || _pointers.length < 2
        ? 0
        : box.globalToLocal(_mid).dy;
    final c = _listCtrl;
    if (!c.hasClients || c.positions.length != 1) {
      _anchorOff = _anchorContent = 0;
      return;
    }
    final pos = c.position;
    _anchorOff = pos.pixels;
    _anchorContent = pos.maxScrollExtent + pos.viewportDimension;
  }

  /// 按锚点回正滚动位置。**必须在布局之后跑**(见下)。
  ///
  /// 列数一变内容总高就变,而 ScrollPosition 只认像素 —— 不回正的话,焦点上方
  /// 的内容长高/缩矮多少,画面就整体漂多少。这里保持**焦点在内容里的比例**不变。
  ///
  /// 内容总高取实测(`maxScrollExtent + viewportDimension`),不按列数推算:
  /// 三种视图(分段列表带段头、封面墙、单堆)的高度构成各不一样,推不准。
  ///
  /// ⚠ 放在指针事件 / 动画 tick 里算是**错的**,而且是会抖的那种错:那时拿到的
  /// 总高还是上一帧的(布局还没跟着新进度跑),按它算出的像素又会成为下一帧布局
  /// 的输入 —— 一来一回构成反馈环,整片网格每帧上下弹。放在帧后就没有环:总高与
  /// 当前进度对得上,跳完只改像素不改总高,下一次算出来就等于当前值,一帧收敛。
  void _reanchor() {
    final c = _listCtrl;
    if (_anchorContent <= 0 || !c.hasClients || c.positions.length != 1) {
      return;
    }
    final pos = c.position;
    final content = pos.maxScrollExtent + pos.viewportDimension;
    if (content <= 0) return;
    final want = ((_anchorOff + _focalY) * content / _anchorContent - _focalY)
        .clamp(0.0, pos.maxScrollExtent);
    if ((want - pos.pixels).abs() > 1.5) c.jumpTo(want);
  }

  bool _reanchorQueued = false;

  void _reanchorAfterLayout() {
    if (_reanchorQueued) return;
    _reanchorQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reanchorQueued = false;
      if (mounted) _reanchor();
    });
  }

  /// 起一次换档过渡。上一档还没跑完就先把它落定,再从新的一级起步 ——
  /// 一路捏下去时不会两段过渡叠在一起。
  void _startMorph(int to) {
    if (_morph.isAnimating) _endMorph();
    _takeAnchor();
    setState(() {
      _toCols = to;
      _t = 0;
    });
    Haptics.selection();
    _morph.forward(from: 0);
  }

  void _pinchDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length != 2) return;
    _span0 = _span;
    _dragSelectEnd(); // 拖选可能已经起手了,清掉半截状态
    setState(() {}); // 进入捏合:冻结滚动、停拖选与长按
  }

  void _pinchMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final s0 = _span0;
    if (_pointers.length != 2 || s0 == null || s0 < 1) return;

    final r = _span / s0;
    if (r < _kZoomIn && r > _kZoomOut) return; // 没到阈值,什么都不做
    // 重取基准:再捏同样的幅度就是下一档。到头时也要重取,否则会一直卡在
    // 阈值以外,手指一抖就反复触发。
    _span0 = _span;

    // 撑开 = 图变大 = 列变少
    final want = (r >= 1 ? _cols - 1 : _cols + 1).clamp(
      kGalleryMinColumns,
      kGalleryMaxColumns,
    );
    if (want == _cols) return; // 到头了
    _startMorph(want);
  }

  void _pinchUp(PointerEvent e) {
    final was = _pinching;
    _pointers.remove(e.pointer);
    if (!was) return;
    if (_pinching) {
      _span0 = _span; // 三指落回两指:重新取基准,免得拿旧间距算出一次误触发
      return;
    }
    _span0 = null;
    setState(() {}); // 退出捏合:放开滚动
    if (!_morph.isAnimating) _persistCols();
  }

  /// 进出堆的过场层。**结构常驻**:不在过场中时透明度 1(引擎按不透明直接画)、
  /// 缩放 1(不建变换层)、不拦点按。过场每一帧只重建这一层。
  ///
  /// 曾经是「不在过场就原样递出去、过场中才包一层」—— 包与不包换的是父节点类型,
  /// 过场一开始、一结束整个滚动视图都被拆掉重挂(每张缩略图重建一遍)。结束那一下
  /// 正好落在面板长高的动画中间,看着就是掉帧。
  Widget _openLayer(Widget child) => AnimatedBuilder(
    animation: _open,
    child: child,
    builder: (_, child) {
      final on = _open.isAnimating || _held;
      final v = _open.value;
      final fading = v < _kFadeOut;
      final t = fading ? 1 - v / _kFadeOut : (v - _kFadeOut) / (1 - _kFadeOut);
      return IgnorePointer(
        ignoring: on,
        child: Opacity(
          opacity: on
              ? (fading ? t : Curves.easeIn.transform(t)).clamp(0.0, 1.0)
              : 1,
          // 淡出的那一半不缩放:旧内容要走干净,再动一下只是噪音
          child: Transform.scale(
            scale: on && !fading
                ? .94 + .06 * Motion.emphasized.transform(t)
                : 1,
            child: child,
          ),
        ),
      );
    },
  );

  /// 网格几何的插值代理:没在两级之间就用当前列数的普通代理,不绕路。
  SliverGridDelegate _zoomDelegate(SliverGridDelegate Function(int cols) of) {
    final to = _toCols;
    if (to == null || _t <= 0) return of(_cols);
    return _ZoomGridDelegate(of, _cols, to, _t);
  }

  Widget _pinchLayer({required Widget child}) => Listener(
    // 几何取这一层:缩放锚点要按它的局部坐标算
    key: _bodyKey,
    onPointerDown: _pinchDown,
    onPointerMove: _pinchMove,
    onPointerUp: _pinchUp,
    onPointerCancel: _pinchUp,
    child: child,
  );

  /// 给网格套上拖选手势。非多选态传 null 处理器 —— 手势识别器不参与竞技场,
  /// 横滑照常落到下层(将来要加横滑手势也不会被这层截胡)。
  ///
  /// 捏合期间同样传 null:Listener 不进竞技场,双指横向张开在多选态下会被
  /// 拖选当成一次划选,一捏就勾中一排。
  Widget _dragSelectLayer({required Widget child}) {
    final on = _selecting && !_pinching;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: on ? _dragSelectStart : null,
      onHorizontalDragUpdate: on ? _dragSelectUpdate : null,
      onHorizontalDragEnd: on ? (_) => _dragSelectEnd() : null,
      onHorizontalDragCancel: on ? _dragSelectEnd : null,
      child: child,
    );
  }

  void _toggleAll(List<ResultImage> results) {
    setState(() {
      if (_picked.length == results.length) {
        _picked.clear();
      } else {
        _picked
          ..clear()
          ..addAll([for (final r in results) r.id]);
      }
    });
  }

  /// 相册首页多选的操作栏:保存 / 打包 ZIP / 删除一行三颗,样式同图片多选首行。
  Widget _albumActions(bool canAct) {
    final scheme = context.scheme;
    return SizedBox(
      height: _actH,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              style: _mainActBtn,
              onPressed: canAct ? _saveAlbums : null,
              icon: const Icon(Icons.download, size: 19),
              label: _fitLabel(_saving ? '保存中 $_saveDone/$_saveTotal' : '保存'),
            ),
          ),
          const SizedBox(width: _actGap),
          Expanded(
            child: FilledButton.tonalIcon(
              style: _mainActBtn,
              onPressed: canAct ? _zipAlbums : null,
              icon: _zipping
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_zip_outlined, size: 19),
              label: _fitLabel(_zipping ? '打包中' : '打包 ZIP'),
            ),
          ),
          const SizedBox(width: _actGap),
          Expanded(
            child: FilledButton.icon(
              style: _mainActBtn.merge(
                FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
              ),
              onPressed: canAct ? _deleteAlbums : null,
              icon: const Icon(Icons.delete_outline, size: 19),
              label: _fitLabel('删除'),
            ),
          ),
        ],
      ),
    );
  }

  /// 回收站多选的操作栏:恢复 / 彻底删除,样式同图片多选首行。
  Widget _trashActions(bool canAct) {
    final scheme = context.scheme;
    return SizedBox(
      height: _actH,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              style: _mainActBtn,
              onPressed: canAct ? _restorePicked : null,
              icon: const Icon(Icons.restore, size: 19),
              label: _fitLabel('恢复 (${_picked.length})'),
            ),
          ),
          const SizedBox(width: _actGap),
          Expanded(
            child: FilledButton.icon(
              style: _mainActBtn.merge(
                FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
              ),
              onPressed: canAct ? _purgePicked : null,
              icon: const Icon(Icons.delete_forever_outlined, size: 19),
              label: _fitLabel('彻底删除 (${_picked.length})'),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAllAlbums() {
    final ids = [for (final a in ref.read(albumsProvider).albums) a.id];
    setState(() {
      if (_pickedAlbums.length == ids.length) {
        _pickedAlbums.clear();
      } else {
        _pickedAlbums
          ..clear()
          ..addAll(ids);
      }
    });
  }

  /// 批量保存:按生成时间从旧到新，逐张处理并等待写入后再存下一张;逐张计数,
  /// 中途关闭弹层即中止(已存的保留)。
  /// [album] 非空 = 存进该手机相册(按需创建 `Pictures/<album>/`)。
  /// [only] 非空 = 只存这些(长按菜单的单张保存借道同一条管线,
  /// 权限申请、保存设置、失败计数一条都不用重写)。
  Future<void> _downloadPicked({String? album, Set<String>? only}) async {
    final want = only ?? _picked;
    final items = oldestFirstForSave([
      for (final r in ref.read(galleryProvider).results)
        if (want.contains(r.id)) r,
    ]);
    final done = await _saveToPhone([(album: album, items: items)]);
    if (done == null || !mounted) return;
    final where = album == null ? '相册' : '「$album」';
    hintSnack(
      context,
      done.failed == 0
          ? '已保存 ${done.saved} 张到$where'
          : '保存 ${done.saved} 张到$where,失败 ${done.failed} 张',
      icon: done.failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
    );
  }

  /// 逐张存进手机:权限、保存设置、进度与失败计数都在这一处,图片多选和
  /// 相册多选共用。[jobs] 每项一个落点(album 为 null = 默认位置),张序由
  /// 调用方排好。返回 null = 没存(没权限 / 弹层已关)。
  Future<({int saved, int failed})?> _saveToPhone(
    List<({String? album, List<ResultImage> items})> jobs,
  ) async {
    final total = jobs.fold(0, (n, j) => n + j.items.length);
    if (total == 0) return null;
    // 写自建相册**以外**的相册要额外权限位,按目标申请
    final toAlbum = jobs.any((j) => j.album != null);
    final ok =
        await Gal.hasAccess(toAlbum: toAlbum) ||
        await Gal.requestAccess(toAlbum: toAlbum);
    if (!mounted) return null;
    if (!ok) {
      hintSnack(context, '未获相册权限', icon: Icons.error_outline);
      return null;
    }
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return null;
    final store = ref.read(appStoresProvider).gallery;
    final gallery = ref.read(galleryProvider.notifier);
    setState(() {
      _saving = true;
      _saveDone = 0;
      _saveTotal = total;
    });
    var saved = 0, failed = 0;
    for (final job in jobs) {
      var savedHere = 0;
      for (final r in job.items) {
        if (!mounted) return null; // 弹层已关:中止剩余
        try {
          final bytes = r.bytes ?? await store.readImage(r.id);
          if (bytes == null) {
            failed++;
          } else {
            final out = await processForSave(bytes, settings);
            await saveProcessedImageToPhone(
              out,
              image: r,
              format: settings.format,
              album: job.album,
            );
            gallery.markSaved([r.id]);
            saved++;
            savedHere++;
          }
        } catch (_) {
          failed++;
        }
        if (mounted) setState(() => _saveDone = saved + failed);
      }
      // 存成过才记进"最近用过"(全失败的名字记下来只会碍事)
      final album = job.album;
      if (album != null && savedHere > 0) {
        await ref
            .read(saveSettingsProvider.notifier)
            .patch((s) => s.withAlbumUsed(album));
      }
    }
    if (!mounted) return null;
    setState(() => _saving = false);
    return (saved: saved, failed: failed);
  }

  /// 相册多选「保存」:每本存成手机里同名的相册(与「自定义相册」同一条
  /// 管线,`Pictures/<名字>/`),本内按生成时间从旧到新。
  Future<void> _saveAlbums() async {
    final data = ref.read(albumsProvider);
    final results = ref.read(galleryProvider).results;
    final jobs = [
      for (final a in data.albums)
        if (_pickedAlbums.contains(a.id))
          (
            album: sanitizeAlbumName(a.name),
            items: oldestFirstForSave([
              for (final r in results)
                if (data.contains(a.id, r.id)) r,
            ]),
          ),
    ];
    final albums = jobs.where((j) => j.items.isNotEmpty).length;
    if (albums == 0) {
      hintSnack(context, '所选相册里还没有图片', icon: Icons.info_outline);
      return;
    }
    final done = await _saveToPhone(jobs);
    if (done == null || !mounted) return;
    _exitSelect();
    hintSnack(
      context,
      done.failed == 0
          ? '已保存 $albums 个相册,共 ${done.saved} 张'
          : '保存 ${done.saved} 张,失败 ${done.failed} 张',
      icon: done.failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
    );
  }

  /// 保存到自定义相册:先问名字,再走同一条保存管线。
  Future<void> _downloadToAlbum() async {
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    final name = await showAlbumNameSheet(
      context,
      recent: settings.recentAlbums,
      count: _picked.length,
    );
    if (name == null || !mounted) return;
    await _downloadPicked(album: name);
  }

  /// 相册多选「打包 ZIP」:几本相册的图合成一个包,同一张在多本里只算一次。
  /// 只选了一本时包名默认用相册名。
  Future<void> _zipAlbums() async {
    final data = ref.read(albumsProvider);
    final images = {
      for (final r in ref.read(galleryProvider).results)
        if (_pickedAlbums.any((id) => data.contains(id, r.id))) r.id,
    };
    if (images.isEmpty) {
      hintSnack(context, '所选相册里还没有图片', icon: Icons.info_outline);
      return;
    }
    await _zipPicked(
      only: images,
      defaultName: _pickedAlbums.length == 1
          ? sanitizeAlbumName(data.name(_pickedAlbums.single))
          : null,
    );
  }

  /// 相册多选「删除」:只删相册本身,图片仍在全部相册(同长按里的删除)。
  Future<void> _deleteAlbums() async {
    final ids = _pickedAlbums.toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${ids.length} 个相册？'),
        content: const Text('只删除相册，图片仍保留在全部相册。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除相册'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final notifier = ref.read(albumsProvider.notifier);
    try {
      for (final id in ids) {
        await notifier.delete(id);
      }
    } catch (e) {
      if (mounted) albumError(context, e);
      return;
    }
    if (!mounted) return;
    _exitSelect();
    hintSnack(context, '已删除 ${ids.length} 个相册', icon: Icons.delete_outline);
  }

  /// 打包 ZIP:弹层里定包名、按需设密码,就地打包(进度条也在那张弹层里),
  /// 打完交给系统保存对话框让用户挑落点([saveFileAs],包再大也不整份进内存)。
  ///
  /// **不进相册** —— zip 不是图片,Gal 收不了;而且「一次拿走几十张」这件事
  /// 本来就更像存进文件管理器 / 网盘,而不是散进相机胶卷里。
  Future<void> _zipPicked({Set<String>? only, String? defaultName}) async {
    final want = only ?? _picked;
    final items = [
      for (final r in ref.read(galleryProvider).results)
        if (want.contains(r.id)) r,
    ];
    if (items.isEmpty) return;
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() => _zipping = true);
    try {
      final packed = await showZipPackSheet(
        context,
        items: items,
        store: ref.read(appStoresProvider).gallery,
        settings: settings,
        defaultName:
            defaultName ??
            'plana-${now.year}${two(now.month)}${two(now.day)}'
                '-${two(now.hour)}${two(now.minute)}',
      );
      if (packed == null || !mounted) return; // 取消:不报也不留
      final zip = packed.file;
      if (zip == null) {
        hintSnack(context, '打包失败', icon: Icons.error_outline);
        return;
      }
      // 只交路径,由原生侧边读边写(见 saveFileAs)—— 包再大也不整份进内存。
      // 存完、取消、失败,缓存里这份都没用了。
      final String? path;
      try {
        path = await saveFileAs(
          zip,
          fileName: packed.fileName,
          mime: 'application/zip',
        );
      } finally {
        try {
          await zip.delete();
        } catch (_) {}
      }
      if (path == null || !mounted) return; // 取消:不报也不留
      hintSnack(
        context,
        packed.failed == 0
            ? '已打包 ${packed.packed} 张'
            : '已打包 ${packed.packed} 张,失败 ${packed.failed} 张',
        icon: packed.failed == 0
            ? Icons.check_circle_outline
            : Icons.error_outline,
      );
    } on PlatformException catch (e) {
      // 原生侧写盘失败(盘满等):message 是原因,整串 PlatformException(...) 没法看
      if (mounted) {
        hintSnack(
          context,
          '保存失败:${e.message ?? e.code}',
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (mounted) hintSnack(context, '保存失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _zipping = false);
    }
  }

  /// 长按缩略图:压暗背景,把按住的那张从原位放大浮起,菜单紧贴在它下面。
  ///
  /// 之前是 showMenu 锚在手指坐标上 —— 图本身一点变化都没有,菜单跟哪张图
  /// 有关全靠猜。指向感只能由**图自己动**来给,锚点给不了。
  Future<void> _thumbMenu(String id, Rect from) async {
    final inTrash = _inTrash;
    final r = inTrash
        ? ref
              .read(galleryProvider)
              .trash
              .where((t) => t.image.id == id)
              .firstOrNull
              ?.image
        : _resultOf(id);
    if (r == null) return;
    Haptics.medium();
    // 先把原图读出来**并解码**,再开抬起层。只读不解码不够:Image.memory
    // 拿到字节还要一两帧才落笔,那一两帧照样露出底下垫着的缩略图 ——
    // 看着就是「先糊一下再变清」。
    final warm = await _warmFull(r).timeout(
      const Duration(milliseconds: 300),
      onTimeout: () => null, // 读得慢就先抬起来,手势不能被读盘卡住
    );
    if (!mounted) return;
    final nav = Navigator.of(context);
    // 缩略图报的是屏幕坐标,路由画在 overlay 里 —— 有嵌套导航时两者不重合
    final box = nav.overlay?.context.findRenderObject() as RenderBox?;
    final at = box == null ? from : box.globalToLocal(from.topLeft) & from.size;
    final albums = ref.read(albumsProvider);
    final isCover = albums.cover(_activeAlbumId)?.sourceImageId == id;
    final picked = await nav.push(
      inTrash
          ? _ThumbMenuRoute(
              from: at,
              result: r,
              warm: warm,
              actions: const [
                (icon: Icons.restore, label: '恢复', value: 'restore'),
              ],
              danger: (
                icon: Icons.delete_forever_outlined,
                label: '彻底删除',
                value: 'purge',
              ),
            )
          : _ThumbMenuRoute(
              from: at,
              result: r,
              warm: warm,
              actions: [
                ..._ThumbMenuRoute.imageActions,
                albums.isFavorite(id)
                    ? (icon: Icons.favorite, label: '取消收藏', value: 'favorite')
                    : (
                        icon: Icons.favorite_border,
                        label: '收藏',
                        value: 'favorite',
                      ),
                // 收藏的封面是固定图标
                if (albumCoverIcon(_activeAlbumId) == null)
                  isCover
                      ? (
                          icon: Icons.hide_image_outlined,
                          label: '取消封面',
                          value: 'uncover',
                        )
                      : (
                          icon: Icons.wallpaper_outlined,
                          label: '设为封面',
                          value: 'cover',
                        ),
              ],
            ),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'import':
        await _importOne(id);
      case 'save':
        await _downloadPicked(only: {id});
      case 'share':
        await _sharePicked(only: {id});
      case 'favorite':
        await toggleFavorite(context, id);
      case 'cover':
        await _setCover(id);
      case 'uncover':
        await _setCover(null);
      case 'delete':
        _deleteOne(id);
      case 'restore':
        ref.read(galleryProvider.notifier).restoreTrash([id]);
        hintSnack(context, '已恢复', icon: Icons.restore);
      case 'purge':
        if (!await _confirmPurge('彻底删除这张作品?', '彻底删除') || !mounted) return;
        ref.read(galleryProvider.notifier).purgeTrash([id]);
        hintSnack(context, '已彻底删除', icon: Icons.delete_forever_outlined);
    }
  }

  /// 设 / 取消当前这本(含全部相册)的封面;取消后回到用最新一张。
  Future<void> _setCover(String? imageId) async {
    final album = _activeAlbumId;
    final name = ref.read(albumsProvider).name(album);
    try {
      await ref.read(albumsProvider.notifier).setCover(album, imageId);
      if (mounted) {
        hintSnack(context, imageId == null ? '已取消「$name」的封面' : '已设为「$name」的封面');
      }
    } catch (e) {
      if (mounted) albumError(context, e);
    }
  }

  /// 读原图并预解码。解码结果进 ImageCache,抬起层再画就是同步的。
  /// 用 MemoryImage(不带 cacheWidth)是为了**和画布同一个缓存键** ——
  /// 同一张图两边共用一次解码,而不是各解一张。
  Future<Uint8List?> _warmFull(ResultImage r) async {
    try {
      final bytes =
          r.bytes ?? await ref.read(appStoresProvider).gallery.readImage(r.id);
      if (bytes == null || !mounted) return null;
      await precacheImage(MemoryImage(bytes), context);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  ResultImage? _resultOf(String id) =>
      ref.read(galleryProvider).results.where((e) => e.id == id).firstOrNull;

  /// 导入:这张送进导入面板(解析内嵌元数据 / 用作参考),与画布侧栏同一个面板。
  ///
  /// 先关网格弹层再推面板 —— 面板是整页的,压在弹层上会留一层退不掉的夹心:
  /// 从面板返回时人会以为回到了画布,实际还在弹层里。
  Future<void> _importOne(String id) async {
    final r = ref
        .read(galleryProvider)
        .results
        .where((e) => e.id == id)
        .firstOrNull;
    if (r == null) return;
    final bytes =
        r.bytes ?? await ref.read(appStoresProvider).gallery.readImage(id);
    if (!mounted) return;
    if (bytes == null) {
      hintSnack(context, '图片尚未就绪', icon: Icons.hourglass_empty);
      return;
    }
    final nav = Navigator.of(context);
    nav.pop();
    unawaited(
      nav.push(
        sharedAxisRoute(
          ImportImagePanel(
            bytes: bytes,
            fileName: 'plana_${r.seed}.png',
            displayName: 'plana_${r.seed}',
          ),
        ),
      ),
    );
  }

  /// 分享:按保存设置处理后落进缓存,交给系统分享面板(管线见
  /// [prepareShareFiles],胶片条的上滑分享也走那条)。
  /// [only] 指定就只分享这几张(长按菜单那条单张的路),否则分享多选选中的。
  Future<void> _sharePicked({Set<String>? only}) async {
    final want = only ?? _picked;
    final items = [
      for (final r in ref.read(galleryProvider).results)
        if (want.contains(r.id)) r,
    ];
    if (items.isEmpty) return;
    final settings = await ref.read(saveSettingsProvider.future);
    if (!mounted) return;
    setState(() {
      _sharing = true;
      _saveDone = 0;
      _saveTotal = items.length;
    });
    final prep = await prepareShareFiles(
      items,
      store: ref.read(appStoresProvider).gallery,
      settings: settings,
      onEach: (done) {
        if (!mounted) return false; // 弹层已关:中止剩余
        setState(() => _saveDone = done);
        return true;
      },
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (prep.files.isEmpty) {
      hintSnack(context, '没有可分享的图片', icon: Icons.error_outline);
      return;
    }
    await SharePlus.instance.share(ShareParams(files: prep.files));
    if (prep.failed > 0 && mounted) {
      hintSnack(context, '${prep.failed} 张读不出来,已跳过', icon: Icons.error_outline);
    }
  }

  /// 单张删除(长按菜单里那项)。**不再二次确认** —— 长按抬起、看清是哪张、
  /// 再点删除,本身已是三步;弹窗只是给这条路再加一次点击。
  /// 批量删除那条仍然确认:一次十几张,误触代价不在一个量级。
  void _deleteOne(String id) {
    final wasSelected = ref.read(galleryProvider).selectedId == id;
    ref.read(galleryProvider.notifier).deleteResults([id]);
    if (ref.read(galleryProvider).results.isEmpty) {
      Navigator.of(context).pop(); // 删空了,弹层没得看
    }
    _trashedSnack([id], reselect: wasSelected ? id : null);
  }

  /// 移进回收站后的提示,带撤销;[reselect] 撤销后重新选中这张。
  /// 提示条挂在根 overlay 上,弹层关了它还在:撤销不能再经弹层的 ref。
  void _trashedSnack(List<String> ids, {String? reselect}) {
    final gallery = ref.read(galleryProvider.notifier);
    hintSnack(
      context,
      ids.length == 1 ? '已移到回收站' : '已将 ${ids.length} 张移到回收站',
      icon: Icons.delete_outline,
      actionLabel: '撤销',
      onAction: () {
        if (gallery.restoreTrash(ids) > 0 && reselect != null) {
          gallery.select(reselect);
        }
      },
    );
  }

  void _restorePicked() {
    final n = ref.read(galleryProvider.notifier).restoreTrash(_picked);
    _exitSelect();
    hintSnack(context, '已恢复 $n 张', icon: Icons.restore);
  }

  Future<void> _purgePicked() async {
    final ids = _picked.toList();
    if (ids.isEmpty) return;
    if (!await _confirmPurge('彻底删除 ${ids.length} 张作品?', '彻底删除') || !mounted) {
      return;
    }
    ref.read(galleryProvider.notifier).purgeTrash(ids);
    _exitSelect();
    hintSnack(
      context,
      '已彻底删除 ${ids.length} 张',
      icon: Icons.delete_forever_outlined,
    );
  }

  /// 彻底删除前确认(单张、多选、清空回收站共用)。
  Future<bool> _confirmPurge(String title, String confirm) async {
    final scheme = context.scheme;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _deletePicked() async {
    final ids = _picked.toList();
    if (ids.isEmpty) return;
    final scheme = context.scheme;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('删除 ${ids.length} 张作品?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    ref.read(galleryProvider.notifier).deleteResults(ids);
    _exitSelect();
    if (ref.read(galleryProvider).results.isEmpty) {
      Navigator.of(context).pop(); // 删空了,弹层没得看
    }
    _trashedSnack(ids);
  }

  /// 多选「移动」:选一个相册就移过去,事后给撤销。在相册里是移出本相册、
  /// 放进目标(目标选全部相册即只移出);在全部相册里是放进目标,别的归属不动。
  Future<void> _movePicked() async {
    if (_organizing || _picked.isEmpty) return;
    setState(() => _organizing = true);
    try {
      final source = _albumHome ? null : _activeAlbumId;
      final pick = await showAlbumMovePicker(context, sourceAlbum: source);
      if (!mounted || pick == null) return;
      final change = await ref.read(albumsProvider.notifier).organize(
        Set.of(_picked),
        {?pick.id},
        sources: source == null ? null : {source},
      );
      if (!mounted) return;
      _exitSelect();
      final name = ref.read(albumsProvider).name(pick.id);
      // 提示条挂在根 overlay 上,弹层关了它还在:撤销不能再经弹层的 ref
      final albums = ref.read(albumsProvider.notifier);
      hintSnack(
        context,
        change.count == 0 ? '图片已在「$name」' : '已移动 ${change.count} 张到「$name」',
        icon: Icons.drive_file_move_outline,
        actionLabel: change.count == 0 ? null : '撤销',
        onAction: change.count == 0
            ? null
            : () => unawaited(albums.undo(change).catchError((Object _) {})),
      );
    } catch (e) {
      if (mounted) albumError(context, e);
    } finally {
      if (mounted) setState(() => _organizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(galleryProvider);
    final albumData = ref.watch(albumsProvider);
    ref.watch(gallerySaveTargetProvider);
    if (_activeAlbumId != trashId && !albumData.exists(_activeAlbumId)) {
      _activeAlbumId = null;
      _albumHome = true;
    }
    final inTrash = _inTrash;
    final results = state.results;
    final trashed = [for (final t in state.trash) t.image];
    final albumResults = inTrash
        ? trashed
        : _albumHome || _activeAlbumId == null
        ? results
        : results
              .where((r) => albumData.contains(_activeAlbumId, r.id))
              .toList();
    final search = ref.watch(gallerySearchProvider);
    final now = DateTime.now();

    // 筛选管线(先廉价的时间,再查表)
    final terms = searchTerms(_query);
    final inDate = _dateFilter.matcher(now);
    // 回收站不筛选(筛选条在那一页不显示)
    final filtered = inTrash
        ? albumResults
        : <ResultImage>[
            for (final r in albumResults)
              if (inDate(r.createdAt) &&
                  _passModel(r, search.byId) &&
                  _passQuery(r, search.byId, terms))
                r,
          ];
    final filtering =
        !inTrash &&
        (_query.isNotEmpty || _modelFilter != null || _dateFilter.active);

    // 弹层开着期间条目可能被裁剪/删除/筛掉,勾选集随之收敛 ——
    // 批量操作永远只作用于当前可见集合,不留筛选外的"隐形勾选"。
    // 查表而不是逐个在列表里找:拖选贴边滚动时每帧都在重建,几百张已选 × 几千张
    // 作品逐个比就是每帧上百万次比较。
    final visible = {for (final r in filtered) r.id};
    _picked.removeWhere((id) => !visible.contains(id));

    // 归属表只拉当前这个维度的 —— 另一个维度的 provider 不 watch 就不开算。
    // 还在算(冷启第一次点开)时先当空表:全落「未归类」,算完自然刷成正确的堆,
    // 不拿一个转圈把整页挡住。
    final tags = switch (_albumHome ? GalleryGroupBy.day : _groupBy) {
      GalleryGroupBy.character => ref.watch(galleryCharTagsProvider),
      GalleryGroupBy.style => ref.watch(galleryStyleTagsProvider),
      GalleryGroupBy.day => const AsyncValue<Map<String, List<GroupTag>>>.data(
        {},
      ),
    };
    // 只有从没算出过结果时才提示。增量重算(每出一张新图)也会 isLoading 一帧,
    // 那一下闪字纯属噪音 —— 旧结果还在,画面根本没变。
    final grouping = tags.isLoading && !tags.hasValue;
    // 回收站按删除那天分段,段头报还剩几天
    final deletedAt = {for (final t in state.trash) t.image.id: t.deletedAt};
    final groups = !_albumHome && _groupBy.stacked
        ? groupByTags(filtered, tags.value ?? const {})
        : inTrash
        ? groupByDay(filtered, now, at: (r) => deletedAt[r.id] ?? 0)
        : groupByDay(filtered, now);
    String? trashNote(GalleryGroup g) {
      final at = deletedAt[g.items.first.id];
      if (at == null) return null;
      final left = kTrashKeepDays - galleryDaysSince(at, now);
      return '${math.max(left, 1)} 天后删除';
    }

    final albums = <GalleryGroup>[
      (key: _allAlbumKey, label: '全部相册', items: results),
      (
        key: favoritesId,
        label: favoritesName,
        items: results.where((r) => albumData.isFavorite(r.id)).toList(),
      ),
      for (final album in albumData.albums)
        (
          key: album.id,
          label: album.name,
          items: results
              .where((r) => albumData.contains(album.id, r.id))
              .toList(),
        ),
      (key: trashId, label: trashName, items: trashed),
    ];

    // 点开的那一堆:筛选变了/图删了可能已经不在,不在就自动退回封面墙
    final open = _albumHome || _openKey == null
        ? null
        : groups.where((g) => g.key == _openKey).firstOrNull;
    _order = _albumHome
        ? const []
        : [
            if (open != null)
              for (final r in open.items) r.id
            else if (!_groupBy.stacked)
              for (final g in groups)
                for (final r in g.items) r.id,
          ];

    final scheme = context.scheme;
    final h = MediaQuery.of(context).size.height * 0.82;
    final canAlbumAct =
        _pickedAlbums.isNotEmpty &&
        !_saving &&
        !_sharing &&
        !_zipping &&
        !_organizing;
    final canAct =
        _picked.isNotEmpty &&
        !_saving &&
        !_sharing &&
        !_zipping &&
        !_organizing;

    return PopScope(
      // 多选态下系统返回/侧滑先退多选,不关弹层 —— 勾了十几张再手滑退出,
      // 重新勾一遍的代价比多按一次返回大得多。点开了某一堆时同理,返回先收回
      // 封面墙。两者都没有才照常放行,好让预测式返回该怎么演就怎么演。
      canPop: !_selecting && _albumHome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _exitSelect();
        } else if (open != null) {
          _setOpen(null);
        } else if (!_albumHome) {
          _setAlbumHome(true);
        }
      },
      // 高度跟着内容走,内容多了才封顶在 h:相册、图片没几张时不留一大片白。
      // 内容一变(进出相册、筛选、捏合换列)面板随之长高 / 缩矮;顶边对齐,
      // 长高时标题先就位,底下那截跟着动画展开。
      //
      // 进出相册时面板先升降到位,新内容再淡入(见 [_onOpenTick])。
      child: AnimatedSize(
        key: _panelKey,
        duration: _kResizeDuration,
        curve: Motion.emphasized,
        onEnd: _resumeOpen,
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                // 相册页最左是返回按钮:点按区 40 宽、21 的箭头居中,图形本身还有
                // 3.5 的留白 —— 左内距收到 7,箭头尖正好落在首页标题的起点(20)。
                padding: EdgeInsets.fromLTRB(
                  !_selecting && !_albumHome ? 7 : 20,
                  4,
                  8,
                  8,
                ),
                child: SizedBox(
                  height: 36,
                  child: _selecting
                      ? Row(
                          children: [
                            Text(
                              _albumHome
                                  ? '已选 ${_pickedAlbums.length} 个相册'
                                  : '已选 ${_picked.length} 张',
                              style: context.texts.titleMedium!.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            _topButton(scheme, hasList: filtered.isNotEmpty),
                            TextButton(
                              style: _headerBtn,
                              onPressed: _saving || _zipping
                                  ? null
                                  : _albumHome
                                  ? _toggleAllAlbums
                                  : () => _toggleAll(filtered),
                              child: Text(
                                (_albumHome
                                        ? _pickedAlbums.isNotEmpty &&
                                              _pickedAlbums.length ==
                                                  albumData.albums.length
                                        : _picked.length == filtered.length &&
                                              filtered.isNotEmpty)
                                    ? '全不选'
                                    : '全选',
                              ),
                            ),
                            TextButton(
                              style: _headerBtn,
                              onPressed: _saving || _zipping
                                  ? null
                                  : _exitSelect,
                              child: const Text('完成'),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            if (!_albumHome)
                              IconButton(
                                // 堆内先回分组墙，再回相册首页。
                                onPressed: () => open != null
                                    ? _setOpen(null)
                                    : _setAlbumHome(true),
                                // 尺寸写死:交给默认点按区的话,宽度会被悄悄撑到 40
                                // 且随主题变,左内距就对不齐了。
                                style: IconButton.styleFrom(
                                  fixedSize: const Size(40, 36),
                                  minimumSize: const Size(40, 36),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                tooltip: open != null ? '回到全部' : '回到相册',
                                icon: const Icon(Icons.arrow_back, size: 21),
                              ),
                            if (!_albumHome) const SizedBox(width: 4),
                            // 标题 + 张数打包进 Expanded 一起吃掉全部余量。
                            //
                            // 不能写成「Flexible(标题) … Spacer()」:两者都是 flex:1,
                            // 余量按份额对半分,而标题是 loose 的、用不满自己那份,
                            // 没用掉的又不会转给 Spacer —— 于是余量的一半滞留在行尾,
                            // 把尾部按钮往左顶。左边内容越少顶得越狠,所以「全部作品」
                            // 顶得最明显、进了堆或进了多选反而看着贴边。
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _albumHome
                                          ? '相册'
                                          : open?.label ??
                                                albumData.name(_activeAlbumId),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.texts.titleMedium!
                                          .copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    // 各堆张数之和会大于总数(一张多角色的图进多堆),
                                    // 所以封面墙上报的仍是**去重后**的总数。
                                    // 回收站不算一本相册
                                    _albumHome
                                        ? '${albums.length - 1} 个相册'
                                        : open != null
                                        ? '${open.items.length} 张'
                                        : filtering
                                        ? '${filtered.length}/${results.length} 张'
                                        : '${albumResults.length} 张',
                                    style: context.texts.bodySmall!.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_albumHome)
                              TextButton.icon(
                                style: _headerBtn,
                                onPressed:
                                    ref.watch(appStoresProvider).albums.readOnly
                                    ? null
                                    : _createAlbum,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('新建'),
                              ),
                            if (_albumHome)
                              TextButton(
                                style: _headerBtn,
                                onPressed: albumData.albums.isEmpty
                                    ? null
                                    : () => _enterSelect(),
                                child: const Text('多选'),
                              ),
                            if (!_albumHome) ...[
                              _topButton(scheme, hasList: filtered.isNotEmpty),
                              if (!inTrash)
                                IconButton(
                                  onPressed: _toggleSearch,
                                  visualDensity: VisualDensity.compact,
                                  tooltip: '搜索提示词标签',
                                  icon: Icon(
                                    Icons.search,
                                    size: 21,
                                    color: _searchOpen
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              TextButton(
                                style: _headerBtn,
                                onPressed: () => _enterSelect(),
                                child: const Text('多选'),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              // 搜索框(点放大镜展开;关闭即清词)
              ExpandBody(
                expanded: !_albumHome && !inTrash && _searchOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    style: context.texts.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索提示词标签…',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 17),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              // 分组 + 筛选 chips + 检索索引回填进度
              if (!_albumHome && !inTrash)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  // Column 默认把按内容收缩的横向滚动视图居中；占满行宽后
                  // chips 从左侧 16px 起排，长日期标签仍可横向滚动。
                  child: SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip(
                            scheme,
                            label: _groupBy.label,
                            active: _groupBy != GalleryGroupBy.day,
                            onTap: _pickGroupBy,
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            scheme,
                            label: _modelFilter == null
                                ? '模型'
                                : (_modelFilter!.isEmpty
                                      ? '未知'
                                      : modelName(_modelFilter!)),
                            active: _modelFilter != null,
                            onTap: () => _pickModelFilter(results, search.byId),
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            scheme,
                            key: const ValueKey('gallery-date-filter'),
                            label: _dateFilter.label(now),
                            active: _dateFilter.active,
                            onTap: _pickTimeFilter,
                          ),
                          if (search.building || grouping) ...[
                            const SizedBox(width: 12),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              search.building
                                  ? '索引 ${search.done}/${search.total}'
                                  : '分组中',
                              style: context.texts.bodySmall!.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              // 内容再少也留两行半封面卡的高度;空页的图标在这段里居中。
              Flexible(
                child: LayoutBuilder(
                  builder: (context, box) => ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: GalleryStackCard.wallMinHeight(
                        context,
                        box.maxWidth,
                        _cols,
                      ),
                    ),
                    child: _pinchLayer(
                      child: _dragSelectLayer(
                        child: !_albumHome && filtered.isEmpty
                            ? Center(
                                heightFactor: 1,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      filtering
                                          ? Icons.search_off
                                          : inTrash
                                          ? Icons.delete_outline
                                          : Icons.image_outlined,
                                      size: 40,
                                      color: scheme.outline,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      filtering
                                          ? '没有符合条件的作品'
                                          : inTrash
                                          ? '回收站是空的'
                                          : _activeAlbumId == null
                                          ? '图库是空的'
                                          : '这个相册还没有图片',
                                      style: context.texts.bodyMedium!.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _openLayer(
                                FastScrollHandle(
                                  // 不在多选时内容底下垫着手势条,滑轨一并让开
                                  padding: EdgeInsets.only(
                                    top: 8,
                                    bottom:
                                        8 +
                                        (_selecting
                                            ? 0
                                            : MediaQuery.paddingOf(
                                                context,
                                              ).bottom),
                                  ),
                                  child: CustomScrollView(
                                    key: PageStorageKey<String>(
                                      _albumHome
                                          ? 'gallery-albums'
                                          : 'gallery-photos-${_activeAlbumId ?? 'all'}',
                                    ),
                                    controller: _albumHome ? _albumCtrl : _ctrl,
                                    // 内容少时按内容收缩,面板才能跟着矮下去。收缩包裹
                                    // 每滚一帧都要连外层一起重排,所以只在格子少时开;
                                    // 过了这个数,最多列(5)下也早已超出封顶高,
                                    // 普通视口撑满即可。
                                    shrinkWrap:
                                        (_albumHome
                                            ? albums.length
                                            : open?.items.length ??
                                                  (_groupBy.stacked
                                                      ? groups.length
                                                      : filtered.length)) <=
                                        60,
                                    // 双指按住、以及换档过渡跑完之前都不滚 ——
                                    // 见 [_FrozenScrollPhysics]
                                    physics: _pinching || _morph.isAnimating
                                        ? const _FrozenScrollPhysics()
                                        : null,
                                    slivers: [
                                      // 相册首页 / 点开的单堆 / 堆的封面墙 / 分段列表。
                                      if (_albumHome)
                                        _stackSliver(scheme, albums)
                                      else if (open != null)
                                        _gridSliver(
                                          open.items,
                                          state.selectedId,
                                        )
                                      else if (_groupBy.stacked)
                                        _stackSliver(scheme, groups)
                                      else
                                        for (final g in groups) ...[
                                          SliverToBoxAdapter(
                                            child: _groupHeader(
                                              scheme,
                                              g,
                                              note: inTrash
                                                  ? trashNote(g)
                                                  : null,
                                            ),
                                          ),
                                          _gridSliver(
                                            g.items,
                                            state.selectedId,
                                          ),
                                        ],
                                      // 面板贴着屏幕底:不在多选时最后一行要让开手势条
                                      // (多选时操作栏自己有 SafeArea)
                                      SliverToBoxAdapter(
                                        child: SizedBox(
                                          height:
                                              10 +
                                              (_selecting
                                                  ? 0
                                                  : MediaQuery.paddingOf(
                                                      context,
                                                    ).bottom),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              // 多选操作栏:进出多选随高度动画滑入滑出
              AnimatedSize(
                duration: Motion.medium,
                curve: Motion.emphasized,
                child: !_selecting
                    ? const SizedBox(width: double.infinity)
                    : SafeArea(
                        top: false,
                        child: Padding(
                          // 上下同距,横竖间隙同取 _actGap —— 原来横 12 竖 8、
                          // 上 4 下 12,三颗挤在一小块里,不等的间隙一眼看得出别扭
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            _actGap,
                            16,
                            _actGap,
                          ),
                          child: _albumHome
                              ? _albumActions(canAlbumAct)
                              : inTrash
                              ? _trashActions(canAct)
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 高度写死在外层:三颗按钮各是 tonal/filled/outlined,
                                    // 各自的默认内边距不一样,不给紧约束就长不齐
                                    SizedBox(
                                      height: _actH,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.tonalIcon(
                                              style: _mainActBtn,
                                              onPressed: canAct
                                                  ? () => _downloadPicked()
                                                  : null,
                                              icon: const Icon(
                                                Icons.download,
                                                size: 19,
                                              ),
                                              label: _fitLabel(
                                                _saving
                                                    ? '保存中 $_saveDone/$_saveTotal'
                                                    : '保存 (${_picked.length})',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: _actGap),
                                          Expanded(
                                            child: FilledButton.tonalIcon(
                                              style: _mainActBtn,
                                              onPressed: canAct && !_organizing
                                                  ? _movePicked
                                                  : null,
                                              icon: const Icon(
                                                Icons.drive_file_move_outline,
                                                size: 19,
                                              ),
                                              label: _fitLabel('移动'),
                                            ),
                                          ),
                                          const SizedBox(width: _actGap),
                                          Expanded(
                                            child: FilledButton.icon(
                                              style: _mainActBtn.merge(
                                                FilledButton.styleFrom(
                                                  backgroundColor:
                                                      scheme.errorContainer,
                                                  foregroundColor:
                                                      scheme.onErrorContainer,
                                                ),
                                              ),
                                              onPressed: canAct
                                                  ? _deletePicked
                                                  : null,
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 19,
                                              ),
                                              label: _fitLabel(
                                                '删除 (${_picked.length})',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: _actGap),
                                    // 次行:三颗都要多一步(挑应用 / 选相册 / 挑落点),
                                    // 矮一档(_actSubH)与首行区分。
                                    //
                                    // 三颗平分一行,「自定义相册」在窄屏上会顶出去 ——
                                    // 内边距收窄 + 文字 scaleDown 兜底,缩一号也比溢出好。
                                    SizedBox(
                                      height: _actSubH,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: _subActBtn,
                                              onPressed: canAct
                                                  ? () => _sharePicked()
                                                  : null,
                                              icon: _sharing
                                                  ? const SizedBox(
                                                      width: 15,
                                                      height: 15,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.ios_share,
                                                      size: 17,
                                                    ),
                                              label: _fitLabel(
                                                _sharing
                                                    ? '准备 $_saveDone/$_saveTotal'
                                                    : '分享',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: _actGap),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: _subActBtn,
                                              onPressed: canAct
                                                  ? _downloadToAlbum
                                                  : null,
                                              icon: const Icon(
                                                Icons.photo_album_outlined,
                                                size: 17,
                                              ),
                                              label: _fitLabel('自定义相册'),
                                            ),
                                          ),
                                          const SizedBox(width: _actGap),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: _subActBtn,
                                              onPressed: canAct
                                                  ? _zipPicked
                                                  : null,
                                              icon: _zipping
                                                  ? const SizedBox(
                                                      width: 15,
                                                      height: 15,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.folder_zip_outlined,
                                                      size: 17,
                                                    ),
                                              // 进度在打包弹层里,这儿只表示「在忙」
                                              label: _fitLabel(
                                                _zipping ? '打包中' : '打包 ZIP',
                                              ),
                                            ),
                                          ),
                                        ],
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

/// 两套网格几何之间的线性插值代理。
///
/// 这是「图片真的在挪窝」的全部实现:每一格的位置与尺寸,都从 [colsA] 列下的值
/// 连续走到 [colsB] 列下的值。整张画面缩放做不到这件事 —— 那样所有格子只是被
/// 一起放大,相对关系纹丝不动,而换列数恰恰是**相对关系**在变(第 4 张从第一行
/// 末尾挪到第二行开头)。
class _ZoomGridDelegate extends SliverGridDelegate {
  const _ZoomGridDelegate(this.of, this.colsA, this.colsB, this.t);

  /// 按列数造一份普通代理。两种网格(方格缩略图 / 带两行字的封面卡)各自的
  /// 尺寸算法不同,所以由调用方传进来。
  final SliverGridDelegate Function(int cols) of;
  final int colsA, colsB;
  final double t;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _LerpGridLayout(
    of(colsA).getLayout(constraints),
    of(colsB).getLayout(constraints),
    t,
  );

  @override
  bool shouldRelayout(covariant _ZoomGridDelegate old) =>
      old.t != t || old.colsA != colsA || old.colsB != colsB;
}

class _LerpGridLayout extends SliverGridLayout {
  const _LerpGridLayout(this.a, this.b, this.t);

  final SliverGridLayout a, b;
  final double t;

  double _l(double x, double y) => x + (y - x) * t;

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final ga = a.getGeometryForChildIndex(index);
    final gb = b.getGeometryForChildIndex(index);
    return SliverGridGeometry(
      scrollOffset: _l(ga.scrollOffset, gb.scrollOffset),
      crossAxisOffset: _l(ga.crossAxisOffset, gb.crossAxisOffset),
      mainAxisExtent: _l(ga.mainAxisExtent, gb.mainAxisExtent),
      crossAxisExtent: _l(ga.crossAxisExtent, gb.crossAxisExtent),
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) => _l(
    a.computeMaxScrollOffset(childCount),
    b.computeMaxScrollOffset(childCount),
  );

  // 可见区间取两套布局的**并集**:插值后的位置一定夹在两者之间,取并集才不会
  // 把边缘上那一两格漏建(漏了就是滚动到边界时凭空出现一块空白)。
  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) => math.min(
    a.getMinChildIndexForScrollOffset(scrollOffset),
    b.getMinChildIndexForScrollOffset(scrollOffset),
  );

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) => math.max(
    a.getMaxChildIndexForScrollOffset(scrollOffset),
    b.getMaxChildIndexForScrollOffset(scrollOffset),
  );
}

/// 捏合期间给列表用的滚动物理:**照常参与手势竞技场,但不产生位移**。
///
/// 为什么不用 `NeverScrollableScrollPhysics`:它的 `shouldAcceptUserOffset`
/// 返回 false,Scrollable 会把自己的拖动识别器撤掉 —— 竞技场里少了它,弹层
/// 自己的「下拉关闭」就赢了,于是捏一下整个浮窗被拽下去。捏合时既要列表别动,
/// 又要它继续占着这个手势不放,两件事得分开:accept 照给,位移给 0。
///
/// 顺带,不给弹道模拟 —— 否则松手那一下还会甩出一段惯性。
class _FrozenScrollPhysics extends ScrollPhysics {
  const _FrozenScrollPhysics({super.parent});

  @override
  _FrozenScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _FrozenScrollPhysics(parent: buildParent(ancestor));

  /// 恒真:内容不足一屏时也要占住手势,否则短列表捏一下就把弹层拖走了。
  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) => 0;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => null;
}

class _GridThumb extends StatelessWidget {
  const _GridThumb({
    required this.result,
    required this.selected,
    required this.picked,
    required this.selecting,
    required this.onTap,
    this.onLongPress,
    this.showTime = true,
  });

  final ResultImage result;

  /// 普通模式:是否为画布当前选中项(主题色描边)。
  final bool selected;

  /// 多选模式:是否已勾选(主题色描边 + 勾选圆标)。
  final bool picked;
  final bool selecting;

  /// 点按与长按都带上**这张图当前占的屏幕矩形**(不是手指坐标)——
  /// 抬起动画要从这块地方长出来,菜单才看得出是属于哪一张的。
  final void Function(Rect from) onTap;
  final void Function(Rect from)? onLongPress;

  /// 右下角标生成时刻。
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final ring = selecting ? picked : selected;
    void withRect(void Function(Rect from) f) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      // 减掉描边 + 让位的那 5,让抬起从图的边缘起算,不是从格子边缘
      f((box.localToGlobal(Offset.zero) & box.size).deflate(5));
    }

    return GestureDetector(
      onTap: () => withRect(onTap),
      onLongPress: onLongPress == null ? null : () => withRect(onLongPress!),
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ring ? scheme.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.5),
          child: LayoutBuilder(
            builder: (_, c) => Stack(
              children: [
                ResultThumb(
                  result: result,
                  width: c.maxWidth,
                  height: c.maxHeight,
                  radius: 10,
                ),
                // 多选模式左上角换勾选圆标(角标让位)
                if (selecting)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: picked
                            ? scheme.primary
                            : Colors.black.withValues(alpha: .35),
                        border: picked
                            ? null
                            : Border.all(
                                color: Colors.white.withValues(alpha: .85),
                                width: 1.5,
                              ),
                      ),
                      child: picked
                          ? Icon(Icons.check, size: 15, color: scheme.onPrimary)
                          : null,
                    ),
                  )
                else if (result.badge != ResultBadge.none)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: ResultBadgeChip(badge: result.badge),
                  ),
                if (result.saved)
                  const Positioned(right: 5, top: 5, child: SavedMark()),
                // 右下角生成时刻(日期由段头承担,段内标时刻才是增量信息)
                if (galleryTimeBadge(result.createdAt) case final String t
                    when showTime && t.isNotEmpty)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        t,
                        style: mono(context, size: 9, weight: FontWeight.w600)
                            .copyWith(
                              color: Colors.white.withValues(alpha: .92),
                              height: 1,
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

// ---- 长按:按住抬起 + 贴着图的菜单 ----

/// 缩略图长按后的「抬起」层。
///
/// 用 PopupRoute 而不是自己搭 Overlay:遮罩、返回键、点空白关闭、进出动画
/// 全是路由自带的,手搭一遍只会漏掉其中一两样。
/// 抬起菜单的一项:图标 + 文字,点了把 value 作为路由结果交回。
typedef _LiftAction = ({IconData icon, String label, String value});

/// 菜单卷出时只裁下沿。按菜单盒子整个裁的话,圆角外那一圈阴影会被切成
/// 灰色的直角;所以左右上三边留出阴影的余量,卷到底时下沿也放开。
class _RollOutClip extends CustomClipper<Rect> {
  const _RollOutClip(this.t);

  final double t;
  static const _shadow = 24.0;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -_shadow,
    -_shadow,
    size.width + _shadow,
    size.height + _shadow * t,
  );

  @override
  bool shouldReclip(_RollOutClip old) => old.t != t;
}

class _ThumbMenuRoute extends PopupRoute<String> {
  _ThumbMenuRoute({
    required this.from,
    required this.result,
    required this.warm,
    this.actions = imageActions,
    this.danger = (icon: Icons.delete_outline, label: '删除', value: 'delete'),
    this.square = false,
    this.emptyIcon = Icons.photo_library_outlined,
  });

  /// 缩略图在 overlay 坐标系里的原始矩形 —— 放大从这里长出来,
  /// 「浮起的是这一张」全指望它。
  final Rect from;

  /// 浮起的图;null = 空相册 / 固定图标封面,浮起一块画着 [emptyIcon] 的占位。
  final ResultImage? result;
  final IconData emptyIcon;

  /// 开层前已读好并解码过的原图;null = 没赶上(读得慢/读失败),
  /// 层里自己去 watch,补上之前先用缩略图垫着。
  final Uint8List? warm;

  /// 菜单项;[danger] 单独隔一条线排在最后,null = 没有这一项。
  final List<_LiftAction> actions;
  final _LiftAction? danger;

  /// 相册卡浮起的是封面,保持方形,不按图的长宽比摊开。
  final bool square;

  static const List<_LiftAction> imageActions = [
    (icon: Icons.input, label: '导入', value: 'import'),
    (icon: Icons.download, label: '保存', value: 'save'),
    (icon: Icons.ios_share, label: '分享', value: 'share'),
  ];

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: .55);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 230);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> anim,
    Animation<double> _,
  ) => _LiftedThumb(route: this, anim: anim);
}

class _LiftedThumb extends ConsumerWidget {
  const _LiftedThumb({required this.route, required this.anim});

  final _ThumbMenuRoute route;
  final Animation<double> anim;

  static const _margin = 16.0;
  static const _gap = 12.0;
  static const _menuW = 200.0;
  static const _itemH = 46.0;
  static const _dividerH = 9.0;

  /// 抬起的图占「可用框」(去掉边距与菜单之后那块)的面积比例。
  static const _fill = .42;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final top0 = media.padding.top + _margin;
    final bot0 = size.height - media.padding.bottom - _margin;

    // 抬起后按图的**真实长宽比**摊开。
    //
    // 预算给的是**面积**,不是宽度。原先一律取屏宽六成,横图等于被砍了两刀:
    // 宽度先削到六成,高度再按长宽比除一次,最后只有同尺寸竖图的四成大 ——
    // 而它下面那截纵向空间明明空着。改成「什么比例都占可用框的 [_fill]」,
    // 竖图与原先基本同尺寸,横图翻倍,方图也不再偏小。
    //
    // 不铺满是刻意的:铺满就成了看图页,没有「一张卡浮在网格上」的意思,
    // 而这个「浮在网格上」正是指向感的来源。
    final result = route.result;
    final from = route.from;
    final menuH =
        _itemH * route.actions.length +
        (route.danger == null ? 0 : _itemH + _dividerH) +
        16;
    final aspect = route.square || result == null
        ? 1.0
        : (result.aspect.isFinite && result.aspect > 0)
        ? result.aspect
        : 1.0; // 老索引里 0 宽/0 高的条目,别把 NaN 送进布局
    final maxW = size.width - _margin * 2;
    final maxH = math.max(80.0, bot0 - top0 - menuH - _gap);
    var pw = math.sqrt(maxW * maxH * _fill * aspect);
    var ph = pw / aspect;
    if (ph > maxH) {
      ph = maxH;
      pw = ph * aspect;
    }
    if (pw > maxW) {
      pw = maxW;
      ph = pw / aspect;
    }
    // 相册封面只是用来认出是哪一本,放大一点就够。照图片的面积预算会大到
    // 盖住半屏,只能整体挪开,离手指按住的那张卡就远了。
    if (route.square) pw = ph = math.min(pw, from.width * 1.4);

    // 尽量停在原位附近:抬起来的是「刚按的那一张」,不是从屏幕中央蹦出来的
    // 另一张。装不下(菜单要顶到屏幕外)才整体上移。
    final groupH = ph + _gap + menuH;
    final left = (from.center.dx - pw / 2)
        .clamp(_margin, math.max(_margin, size.width - pw - _margin))
        .toDouble();
    final top = (from.center.dy - ph / 2)
        .clamp(top0, math.max(top0, bot0 - groupH))
        .toDouble();
    final menuLeft = left
        .clamp(_margin, math.max(_margin, size.width - _menuW - _margin))
        .toDouble();
    final to = Rect.fromLTWH(left, top, pw, ph);

    // 抬起来本就是为了看清 —— 拿缩略图放大只是把糊的放得更糊,所以用原图。
    // 常态下 warm 已经读好解好(见 _warmFull),第一帧就是清的;只有没赶上
    // 时才落到这个 watch 上,那条路再淡入。
    final full =
        route.warm ??
        (result == null
            ? null
            : ref.watch(galleryImageProvider(result.id)).value);

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = Motion.emphasized.transform(
          anim.value.clamp(0.0, 1.0).toDouble(),
        );
        final rect = Rect.lerp(from, to, t)!;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                key: const ValueKey('lift-frame'),
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 原图读盘期间先垫着已经在内存里的缩略图 ——
                    // 长按到抬起之间不该有一格空白。
                    //
                    // 原图到位后必须**让它消失**,不能一直垫着:不透明图看不出
                    // 区别(全被盖住),半透明图会从透明区把这张拉伸的缩略图透
                    // 出来,看着就是背景多了一张模糊的放大图。用淡出而不是
                    // 直接撤掉 —— 与上面那层的淡入同步,慢路径才不会闪一下空白。
                    AnimatedOpacity(
                      opacity: full == null ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: result == null
                          ? ColoredBox(
                              color: context.scheme.surfaceContainerHighest,
                              child: Icon(
                                route.emptyIcon,
                                size: 48,
                                color: context.scheme.onSurfaceVariant,
                              ),
                            )
                          : ResultThumb(
                              result: result,
                              width: rect.width,
                              height: rect.height,
                              radius: 14,
                            ),
                    ),
                    // 慢路径(warm 没赶上)才会走到这个切换:淡入而不是
                    // 直接盖上去,免得眼睁睁看着一张糊的跳成清的
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      // AnimatedSwitcher 里给的是宽松约束,不撑满的话图会按
                      // 自身比例缩在框里(方形抬起框里的竖图两边就空了)。
                      child: full == null
                          ? const SizedBox.shrink(key: ValueKey('wait'))
                          : SizedBox.expand(
                              key: const ValueKey('full'),
                              child: Image.memory(
                                full,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: menuLeft,
              top: to.bottom + _gap,
              width: _menuW,
              // 从图的下沿卷出来,不是凭空淡入 —— 强调它属于上面那张
              child: Opacity(
                opacity: t,
                child: ClipRect(
                  clipper: _RollOutClip(t),
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: math.max(t, .01),
                    child: _menu(context),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _menu(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: context.raisedFill(scheme.surfaceContainerHigh),
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          for (final a in route.actions) _item(context, a),
          // 删除排最后并单独隔一条线:菜单就在手指底下,不可撤销的那项
          // 排第一位等于放到最容易误落的地方
          if (route.danger case final danger?) ...[
            Divider(
              height: _dividerH,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: scheme.outlineVariant,
            ),
            _item(context, danger, danger: true),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    _LiftAction action, {
    bool danger = false,
  }) {
    final scheme = context.scheme;
    return InkWell(
      onTap: () => Navigator.of(context).pop(action.value),
      child: SizedBox(
        height: _itemH,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              action.icon,
              size: 20,
              color: danger ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              action.label,
              style: context.texts.bodyLarge!.copyWith(
                color: danger ? scheme.error : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

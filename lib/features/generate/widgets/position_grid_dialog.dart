import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../../gallery/gallery_state.dart';
import '../char_position.dart';
import '../generate_state.dart';
import '../models.dart';

/// 角色定位弹窗(对齐 web `CharacterPositionModal`)。
///
/// · V5(NAI 5)自由画布:按当前出图横竖比例占位,点哪放哪、也能按住直接拖;
///   主页当前图与出图比例一致时直接拿它当画布,在真实构图上摆位更直观。
/// · V4/V4.5:5×5 网格(画布表达不了网格档位语义)。
/// 二者共享:顶部角色条一处切换多个角色、先选后确认(改动落草稿,确认才写回)。
Future<void> showPositionGridDialog(BuildContext context, String charId) {
  return showDialog(
    context: context,
    builder: (context) => _PositionDialog(initialCharId: charId),
  );
}

/// 画布拖动:落点即接管。
///
/// 二维拖动和外层弹窗的竖向滚动同轴相争,默认判法是谁先够 slop —— 拖动要 36
/// 像素、滚动只要 18,手指往下拖必被滚动抢走,角色纹丝不动。画布是这个弹窗里
/// 唯一要用手拖的东西,索性按下当场判胜:画布里的每一次划动都归它。
class _CanvasDragRecognizer extends PanGestureRecognizer {
  _CanvasDragRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _PositionDialog extends ConsumerStatefulWidget {
  const _PositionDialog({required this.initialCharId});

  final String initialCharId;

  @override
  ConsumerState<_PositionDialog> createState() => _PositionDialogState();
}

class _PositionDialogState extends ConsumerState<_PositionDialog> {
  late String _selectedId = widget.initialCharId;
  // 本地草稿:先改草稿,确认才写回;切换角色时保留各自未保存的改动。
  late final Map<String, String?> _draft = {
    for (final c in ref.read(generateProvider).characters) c.id: c.position,
  };

  /// AUTO 是**整张图**的档,不是某个角色的 —— 对应官方位置区块上的
  /// AI's Choice / Custom(请求里的 `v4_prompt.use_coords`)。
  ///
  /// 每个角色始终带着自己的坐标,AUTO 只是让模型别理会它们;所以按下 AUTO
  /// 不擦任何人的位置,再切回来还是原来那些格子。摆位(点格子 / 拖画布)会
  /// 自动切成「用我摆的」—— 同官方。
  late bool _draftUseCoords = ref.read(generateProvider).params.useCoords;

  /// 挂在切换条当前选中那颗 chip 上,打开时把它滚进视野。
  final _selectedChipKey = GlobalKey();

  /// 手指正按在画布上(拖动中):点放大一圈,底下的读数改显实时坐标。
  bool _dragging = false;

  /// 按在别人那颗点上、还没分清是拖是点时的暂存(见 [_grabAt])。
  ({String id, Offset at, String pos})? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedChipKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: .5);
      }
    });
  }

  /// 摆位:写当前角色的坐标,并把整张图切成「用我摆的」。
  void _setPos(String pos) => setState(() {
    _draft[_selectedId] = pos;
    _draftUseCoords = true;
  });

  /// 开 = 全体交给模型排,关 = 收回来按各人摆的坐标发。
  ///
  /// 两个方向都不动任何人的坐标 —— 每个角色始终带着自己那份,关掉时原样生效,
  /// 不用重摆。原先这里只有「打开」一个方向(按钮按下即 AUTO),想关只能去画布上
  /// 随便摆一下,那是把开关做成了单程票。
  void _setAuto(bool auto) {
    Haptics.selection();
    setState(() => _draftUseCoords = !auto);
  }

  /// 画布局部坐标 → 自由坐标串。
  String _posAt(Offset p, double w, double h) => formatFreeformPosition(
    (p.dx / w).clamp(0.0, 1.0),
    (p.dy / h).clamp(0.0, 1.0),
  );

  /// 落点抓到的那颗点;够不着任何一颗 → null(空处按下 = 放当前角色)。
  ///
  /// 半径按手指给足(比点本身大一圈),几颗叠在一处时当前角色优先 —— 拖自己
  /// 那颗的时候选中不该被旁边的挤走。
  String? _hitDot(Offset p, List<CharacterPrompt> chars, double w, double h) {
    const r2 = 24.0 * 24.0;
    double? distTo(String id) {
      final ctr = resolveCharacterCenter(_draft[id]);
      if (ctr == null) return null;
      final d = (Offset(ctr.x * w, ctr.y * h) - p).distanceSquared;
      return d <= r2 ? d : null;
    }

    if (distTo(_selectedId) != null) return _selectedId;
    String? best;
    var bestD = double.infinity;
    for (final c in chars) {
      final d = distTo(c.id);
      if (d != null && d < bestD) {
        best = c.id;
        bestD = d;
      }
    }
    return best;
  }

  /// 按下:空处落点,按住自己那颗点则只是把它拿起来,两种都接着跟手拖。
  ///
  /// 抓自己那颗点**不挪动**(同 web):一按就跳到手指中心的话,本来想微调的人
  /// 反倒先被推走一截 —— 命中半径 24px,那一下最多偏 24px。
  ///
  /// 按在**别人**那颗点上则先按住不动:划开了才算要挪他(省得为挪一个角色先
  /// 回顶上切一次),只点一下仍按老规矩把当前角色放这儿。V5 一图能摆 32 个,
  /// 点挨得密,按下就改判的话,想在别人旁边落一个自己的点全会变成把人拖走。
  void _grabAt(Offset p, List<CharacterPrompt> chars, double w, double h) {
    final hit = _hitDot(p, chars, w, h);
    if (hit != null && hit != _selectedId) {
      _pending = (id: hit, at: p, pos: _posAt(p, w, h));
      return;
    }
    setState(() {
      _dragging = true;
      if (hit == null) _draft[_selectedId] = _posAt(p, w, h);
    });
  }

  void _dragTo(Offset p, double w, double h) {
    final pend = _pending;
    if (pend != null) {
      // 够 slop 才改判,免得点按时手指那一两像素的抖动被当成拖动
      if ((p - pend.at).distance < kTouchSlop) return;
      _pending = null;
      Haptics.selection();
    }
    setState(() {
      if (pend != null) _selectedId = pend.id;
      _dragging = true;
      _draft[_selectedId] = _posAt(p, w, h);
    });
  }

  void _endDrag() {
    final tapped = _pending?.pos; // 始终没划开 = 只是点了一下别人的点
    _pending = null;
    setState(() {
      if (tapped != null) {
        _draft[_selectedId] = tapped;
        _draftUseCoords = true; // 拖过就是「用我摆的」(同官方)
      }
      _dragging = false;
    });
  }

  void _confirm() {
    final notifier = ref.read(generateProvider.notifier);
    final current = {
      for (final c in ref.read(generateProvider).characters) c.id: c.position,
    };
    _draft.forEach((id, pos) {
      if (current.containsKey(id) && current[id] != pos) {
        notifier.updateCharacter(id, position: pos);
      }
    });
    notifier.setUseCoords(_draftUseCoords);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final gen = ref.watch(generateProvider);
    final chars = gen.characters;
    final params = gen.params;
    final isV5 = isNai5Model(params.model);
    final isAuto = !_draftUseCoords; // 整张图的档,不是当前角色的

    // 主页当前图:比例与出图设置一致时当画布底图
    final sel = ref.watch(galleryProvider).selected;
    final showBg =
        isV5 &&
        sel != null &&
        aspectRatiosMatch(sel.width, sel.height, params.width, params.height);
    final Uint8List? bgBytes = showBg
        ? (sel.bytes ?? ref.watch(galleryImageProvider(sel.id)).value)
        : null;

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 头部
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 19, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '设置角色位置',
                        style: context.texts.titleMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      color: scheme.onSurfaceVariant,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 角色切换条:一处切换所有角色,无需反复开关弹窗。
                // 单行横滑而不是 Wrap 竖排:V5 一图最多 32 个角色,竖排能占掉
                // 半屏,把真正要操作的定位画布挤到画面外;打开时把当前角色滚进
                // 视野(之后都是用户手点,点得到的本来就在视野里,不再自动滚)。
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: chars.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => Center(
                      child: KeyedSubtree(
                        key: chars[i].id == _selectedId
                            ? _selectedChipKey
                            : null,
                        child: _switcherChip(context, chars[i], i, isV5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // 定位区。AUTO 开着时这些坐标压根不发出去,所以整块压暗并挡住
                // 手势 —— 摆得动却不生效是最难受的一种:人会以为自己摆错了,
                // 反复试。要改先把下面那个开关关掉,那是唯一的入口,也看得见。
                AnimatedOpacity(
                  duration: Motion.fast,
                  opacity: isAuto ? .42 : 1,
                  child: IgnorePointer(
                    ignoring: isAuto,
                    child: isV5
                        ? _canvas(context, chars, params, bgBytes)
                        : _grid(context, chars),
                  ),
                ),
                const SizedBox(height: 14),
                // AUTO = 整张图交给模型排(官方的 AI's Choice)。管的是**所有
                // 角色**,不是当前这个 —— 官方那边它本来就是全局档,我们早先
                // 做成每角色一份,结果是「AUTO」只是个标签,坐标照发。
                //
                // 做成开关而不是按钮:它本来就是个二态的东西,按钮只按得下去
                // (按一下进 AUTO),想退出得跑去画布上随便摆一下才行 —— 那条
                // 退路在界面上根本看不出来。开关两个方向都在明面上。
                // 版式照 app 里设置行的惯例:图标 + 标题 + 右侧开关,整行可点。
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _setAuto(!isAuto),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: .9),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: isAuto ? scheme.primary : scheme.outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '全部自动 (AUTO)',
                              style: context.texts.bodyMedium!.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isAuto
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Switch(
                            value: isAuto,
                            onChanged: _setAuto,
                            // 开关默认要占 48 的点击靶,这一行会被顶得比下面
                            // 那对按钮还高。整行本来就可点,靶子不缺这一圈。
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 取消 / 确认保存
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      // 不带勾图标:对半分的窄屏半宽装不下「图标+四个字」,
                      // 文本会折成两行 —— 确认键的身份由填充色说明,图标是冗余。
                      child: FilledButton(
                        onPressed: _confirm,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                        ),
                        child: const Text(
                          '确认保存',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _switcherChip(
    BuildContext context,
    CharacterPrompt c,
    int index,
    bool isV5,
  ) {
    final scheme = context.scheme;
    final active = c.id == _selectedId;
    return Material(
      color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _selectedId = c.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: active ? scheme.primary : scheme.outlineVariant,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                c.name,
                style: context.texts.labelMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                // 网格模型下显示它实际会被吸附到的那一格,别写着 '42,67%'
                // 而请求里发的是 C4 的格心。
                positionChipLabel(_draft[c.id], grid: !isV5),
                style: context.texts.labelSmall!.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color:
                      (active
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant)
                          .withValues(alpha: .7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// V5 自由画布:按出图比例占位,可选底图,点哪放哪,画出所有角色的点。
  Widget _canvas(
    BuildContext context,
    List<CharacterPrompt> chars,
    GenParams params,
    Uint8List? bgBytes,
  ) {
    final scheme = context.scheme;
    final ratio = params.width / params.height;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        var w = constraints.maxWidth;
        var h = w / ratio;
        const maxH = 320.0;
        if (h > maxH) {
          h = maxH;
          w = h * ratio;
        }
        return Column(
          children: [
            // 上下留白:点以自身中心对齐坐标,坐标压在 0 或 1 时有一半落在画布
            // 外,没这段留白会顶到上头的角色条和下面的读数行。
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: SizedBox(
                width: w,
                height: h,
                // 按下即落点、拖着走就一路跟手、抬手落定;点一下正是零位移的
                // 那一趟拖动,所以两种手势共用同一条路径。
                child: RawGestureDetector(
                  gestures: {
                    _CanvasDragRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _CanvasDragRecognizer
                        >(() => _CanvasDragRecognizer(debugOwner: this), (r) {
                          r.onStart = (d) =>
                              _grabAt(d.localPosition, chars, w, h);
                          r.onUpdate = (d) => _dragTo(d.localPosition, w, h);
                          r.onEnd = (_) => _endDrag();
                          r.onCancel = _endDrag;
                        }),
                  },
                  // 底图与网格线单独一层做圆角裁剪,点层留在裁剪外面 ——
                  // 否则坐标贴边(x=0 / y=1 这类)的点会被切掉一半,偏偏那几个
                  // 最需要看清落在哪。Clip.none 是为了让溢出的半个点画得出来。
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(
                                  color: scheme.surfaceContainerHigh,
                                ),
                              ),
                              // 底图:主页当前图(比例一致)+ 轻压暗保证点/线可辨
                              if (bgBytes != null) ...[
                                Positioned.fill(
                                  child: Image.memory(
                                    bgBytes,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: .2),
                                  ),
                                ),
                              ],
                              // 参考网格线(仅视觉辅助,不吸附)
                              for (final f in const [.2, .4, .6, .8]) ...[
                                Positioned(
                                  left: w * f,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1,
                                    color: scheme.outline.withValues(
                                      alpha: .25,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: h * f,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 1,
                                    color: scheme.outline.withValues(
                                      alpha: .25,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // 各角色的点,当前编辑的高亮放大
                      for (var i = 0; i < chars.length; i++)
                        ..._dot(context, chars[i], i, w, h),
                    ],
                  ),
                ),
              ),
            ),
            // 拖动时手指正好压住那颗点,读数换成实时坐标补上看不见的反馈。
            Text(
              _dragging
                  ? positionChipLabel(_draft[_selectedId])
                  : '${params.width}×${params.height} · 点按或拖动放置角色',
              style: context.texts.labelSmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _dot(
    BuildContext context,
    CharacterPrompt c,
    int index,
    double w,
    double h,
  ) {
    final ctr = resolveCharacterCenter(_draft[c.id]);
    if (ctr == null) return const [];
    final scheme = context.scheme;
    final cur = c.id == _selectedId;
    final d = cur ? 30.0 : 26.0;
    return [
      Positioned(
        left: ctr.x * w - d / 2,
        top: ctr.y * h - d / 2,
        child: IgnorePointer(
          // 抓在手里时胀一圈。用缩放而不是改尺寸:尺寸一变,上面按目标直径
          // 算的锚点就和过渡中的实际直径对不上,点会在动画那 150ms 里偏心。
          child: AnimatedScale(
            scale: cur && _dragging ? 1.2 : 1,
            duration: Motion.fast,
            curve: Motion.standard,
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: cur ? scheme.primary : scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: cur
                    ? Border.all(color: Colors.white, width: 2)
                    : Border.all(color: scheme.outline.withValues(alpha: .5)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 3),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: cur ? 13 : 11,
                  fontWeight: FontWeight.w700,
                  color: cur ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// V4/V4.5 的 5×5 网格(草稿驱动:当前角色高亮,其他角色占格灰显序号)。
  Widget _grid(BuildContext context, List<CharacterPrompt> chars) {
    final scheme = context.scheme;
    final myIndex = chars.indexWhere((c) => c.id == _selectedId) + 1;
    // 一律按「落在哪一格」算,不能拿 position 字符串直接比:从 V5 带过来的
    // '0.42,0.67' 跟任何格子 id 都不相等,格子会全显示未选中,而发送层已经把它
    // 吸附进了某一格 —— 界面和请求对不上。连 '0.7000,0.3000' 这种正正压在格心
    // 上的也一样比不中。见 [gridCellForPosition]。
    final myCell = gridCellForPosition(_draft[_selectedId]);
    final occ = <String, List<int>>{};
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final cell = gridCellForPosition(_draft[c.id]);
      if (c.id != _selectedId && cell != null) (occ[cell] ??= []).add(i + 1);
    }
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 26),
            for (final col in 'ABCDE'.split(''))
              Expanded(
                child: Center(
                  child: Text(
                    col,
                    style: context.texts.labelSmall!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 1; row <= 5; row++) ...[
          Row(
            children: [
              SizedBox(
                width: 26,
                child: Center(
                  child: Text(
                    '$row',
                    style: context.texts.labelSmall!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              for (final col in 'ABCDE'.split(''))
                Expanded(
                  child: _cell(context, '$col$row', myIndex, myCell, occ),
                ),
            ],
          ),
          if (row < 5) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    String code,
    int myIndex,
    String? myCell,
    Map<String, List<int>> occ,
  ) {
    final scheme = context.scheme;
    final mine = myCell == code;
    final others = occ[code] ?? const <int>[];
    final all = [if (mine) myIndex, ...others]..sort();
    final stacked = all.length >= 2;

    late final Color bg;
    Border? border;
    Widget? content;

    if (stacked) {
      bg = scheme.tertiaryContainer;
      if (mine) border = Border.all(color: scheme.primary, width: 2);
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers, size: 13, color: scheme.onTertiaryContainer),
          const SizedBox(height: 1),
          Text(
            all.join('·'),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: scheme.onTertiaryContainer,
            ),
          ),
        ],
      );
    } else if (mine) {
      bg = scheme.primary;
      content = Text(
        '$myIndex',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimary,
        ),
      );
    } else if (others.length == 1) {
      bg = scheme.surfaceContainerHighest;
      border = Border.all(color: scheme.outline.withValues(alpha: .4));
      content = Text(
        '${others.first}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      );
    } else {
      bg = scheme.surfaceContainerHigh;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: border,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // 点自己已经在的那格 = 取消定位 → 全体转 AUTO
              onTap: () => mine ? _setAuto(true) : _setPos(code),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

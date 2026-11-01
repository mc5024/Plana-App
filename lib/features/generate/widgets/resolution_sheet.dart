import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../generate_state.dart';
import '../models.dart';
import '../res_presets.dart';
import '../res_rules.dart';
import 'common.dart';
import '../../../l10n/l10n.dart';

const _customTab = '自定义';
const _mineTab = '我的';

/// 内置档位与默认预设名按界面语言显示;自定义名原样。
String _sizeLabel(AppLocalizations l, String name) => switch (name) {
  '小图' => l.sizeNormal,
  '大图' => l.sizeLarge,
  '壁纸' => l.sizeWallpaper,
  '竖图' => l.sizePortrait,
  '横图' => l.sizeLandscape,
  '方形' => l.sizeSquare,
  '竖屏' => l.sizePortraitScreen,
  '横屏' => l.sizeLandscapeScreen,
  _ => name,
};

SizePreset _asSize(ResPreset p) =>
    SizePreset(p.name, formatAspectRatio(p.width, p.height), p.width, p.height);

// 画布满格对应的真实像素(两轴一致);矩形左上角锚定,右下角拖拽定 W/H。
final double _axisMax = kMaxDim.toDouble();

// 可视化配色(在浅色画布上可读,语义同 web:绿=免费线,红=上限线)。
const _vizFree = FixedSemantic.ok;
const _vizOver = FixedSemantic.danger;

// 可吸附的两条等像素线:免费线 / 上限线。
const _pixelLines = [kFreePixelThreshold, kMaxTotalPixels];

// 吸附圈(画布 dp):离线 8 以内吸上,拉出 12 才松开 —— 滞回,
// 免得手指停在圈边时来回跳、连着振。
const _snapInDp = 8.0;
const _snapOutDp = 12.0;

/// 分辨率 Sheet:预设三档(小图免费/大图/壁纸)+ 我的(自存预设,有才出现)
/// + 自定义档(拖拽画布)+ 统一档位状态条(MP·比例·免费/付费/超限)+ 确认生效。
/// 数值/交互对齐 web 桌面端。
Future<void> showResolutionSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => const _ResolutionSheet(),
  );
}

class _ResolutionSheet extends ConsumerStatefulWidget {
  const _ResolutionSheet();

  @override
  ConsumerState<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends ConsumerState<_ResolutionSheet> {
  late String tab;

  /// 最后停留的预设页签:自定义档下预设行仍要渲染(CrossFade 常驻两子树)。
  late String lastPresetTab;
  late SizePreset selected;
  late int customW;
  late int customH;

  @override
  void initState() {
    super.initState();
    final p = ref.read(generateProvider).params;
    tab = sizeTabs.keys.first;
    selected = sizeTabs[tab]!.first;
    customW = snapDim(p.width);
    customH = snapDim(p.height);
    final hit = _match(p.width, p.height);
    if (hit != null) {
      tab = hit.$1;
      selected = hit.$2;
    } else {
      // 当前尺寸不是任何预设(如图生图按底图设的怪尺寸)→ 落在自定义档回显。
      tab = _customTab;
    }
    lastPresetTab = _isCustom ? sizeTabs.keys.first : tab;
  }

  bool get _isCustom => tab == _customTab;
  int get _effW => _isCustom ? customW : selected.width;
  int get _effH => _isCustom ? customH : selected.height;

  bool _isSel(SizePreset p) =>
      p.width == selected.width && p.height == selected.height;

  List<SizePreset> _presetsOf(String t, List<ResPreset> mine) =>
      t == _mineTab ? [for (final p in mine) _asSize(p)] : sizeTabs[t]!;

  /// 先找内置三档,再找我的。
  (String, SizePreset)? _match(int w, int h) {
    for (final e in sizeTabs.entries) {
      for (final s in e.value) {
        if (s.width == w && s.height == h) return (e.key, s);
      }
    }
    if (ref.read(resPresetsProvider.notifier).find(w, h) case final m?) {
      return (_mineTab, _asSize(m));
    }
    return null;
  }

  void _setCustom(int w, int h) => setState(() {
    customW = w.clamp(kMinDim, kMaxDim);
    customH = h.clamp(kMinDim, kMaxDim);
  });

  /// 存下当前自定义尺寸并跳到它;已有同尺寸预设就直接跳过去。
  void _save() {
    var hit = _match(customW, customH);
    if (hit == null) {
      ref.read(resPresetsProvider.notifier).add(customW, customH);
      hit = _match(customW, customH)!;
    }
    final (t, s) = hit;
    setState(() {
      tab = t;
      lastPresetTab = t;
      selected = s;
    });
  }

  void _remove(SizePreset p) {
    ref.read(resPresetsProvider.notifier).remove(p.width, p.height);
    final mine = ref.read(resPresetsProvider);
    setState(() {
      if (mine.isEmpty) {
        // 删空后「我的」页签消失:落到自定义档,尺寸不变
        customW = p.width;
        customH = p.height;
        tab = _customTab;
        lastPresetTab = sizeTabs.keys.first;
      } else if (_isSel(p)) {
        selected = _asSize(mine.first);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final over = classifyPixels(_effW, _effH) == PixelTier.over;
    final mine = ref.watch(resPresetsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.l10n.resolution,
                style: context.texts.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const HelpDot(Help.resolution, size: 30, iconSize: 18),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              for (final t in sizeTabs.keys)
                ButtonSegment(
                  value: t,
                  label: Text(_sizeLabel(context.l10n, t)),
                ),
              if (mine.isNotEmpty)
                const ButtonSegment(value: _mineTab, label: Text(_mineTab)),
              ButtonSegment(
                value: _customTab,
                label: Text(context.l10n.sizeCustom),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (s) => setState(() {
              tab = s.first;
              if (!_isCustom) {
                lastPresetTab = tab;
                selected = _presetsOf(tab, mine).first;
              }
            }),
            showSelectedIcon: false,
            // 五段时窄屏放得下「自定义」
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // CrossFade 同步动画高度与透明度:预设行(矮)↔ 画布(高)切换不跳变
          AnimatedCrossFade(
            duration: Motion.medium,
            sizeCurve: Motion.emphasized,
            crossFadeState: _isCustom
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: _PresetGrid(
              presets: _presetsOf(lastPresetTab, mine),
              isSelected: _isSel,
              onTap: (p) => setState(() => selected = p),
              onLongPress: lastPresetTab == _mineTab ? _remove : null,
            ),
            secondChild: _CanvasEditor(
              width: customW,
              height: customH,
              onChanged: _setCustom,
            ),
          ),
          const SizedBox(height: 12),
          _StatusStrip(width: _effW, height: _effH),
          const SizedBox(height: 16),
          // 自定义档左侧让出「存为预设」,切档时宽度过渡
          LayoutBuilder(
            builder: (context, cons) => TweenAnimationBuilder<double>(
              tween: Tween(end: _isCustom ? 1.0 : 0.0),
              duration: Motion.medium,
              curve: Motion.emphasized,
              builder: (context, t, _) => Row(
                children: [
                  if (t > 0) ...[
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: t,
                        child: SizedBox(
                          width: (cons.maxWidth - 10) * .4,
                          child: Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: OutlinedButton.icon(
                              onPressed: over ? null : _save,
                              icon: const Icon(
                                Icons.bookmark_add_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                '存为预设',
                                maxLines: 1,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10 * t),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: over
                          ? null
                          : () {
                              ref
                                  .read(generateProvider.notifier)
                                  .setSize(_effW, _effH);
                              Navigator.pop(context);
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        over ? '超出像素上限' : '确认 · $_effW×$_effH',
                        maxLines: 1,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 预设卡三列排开,不满一行留空位;给了 [onLongPress] 的卡长按即删。
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({
    required this.presets,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final List<SizePreset> presets;
  final bool Function(SizePreset) isSelected;
  final ValueChanged<SizePreset> onTap;
  final ValueChanged<SizePreset>? onLongPress;

  static const _cols = 3;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var r = 0; r < presets.length; r += _cols) ...[
          if (r > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var c = 0; c < _cols; c++) ...[
                if (c > 0) const SizedBox(width: _gap),
                Expanded(
                  child: r + c < presets.length
                      ? _cell(presets[r + c])
                      : const SizedBox(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _cell(SizePreset p) => _PresetCard(
    key: ValueKey('${p.width}x${p.height}'),
    preset: p,
    selected: isSelected(p),
    onTap: () => onTap(p),
    onLongPress: onLongPress == null ? null : () => onLongPress!(p),
  );
}

/// 档位状态条:MP · 比例 + 免费/消耗点数/超出上限徽章(与 web classifyPixelStatus 同义)。
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.width, required this.height});

  final int width;
  final int height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final tier = classifyPixels(width, height);
    final (label, color) = switch (tier) {
      PixelTier.free => ('免费', scheme.tertiary),
      PixelTier.paid => ('消耗点数', scheme.primary),
      PixelTier.over => ('超出上限', scheme.error),
    };
    return Row(
      children: [
        Text(
          '${megapixels(width, height).toStringAsFixed(2)} MP',
          style: mono(
            context,
            size: 12.5,
          ).copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Text('·', style: TextStyle(color: scheme.outline)),
        const SizedBox(width: 8),
        Text(
          formatAspectRatio(width, height),
          style: mono(
            context,
            size: 12.5,
          ).copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// 自定义档:拖拽画布(左上锚定,右下角把手定 W/H)+ 读数/交换 + 缩到免费/上限。
/// 触屏在画布任意处按下/拖动即把右下角吸到手指,较桌面「抓把手」更顺;
/// 拖到免费线/上限线附近自动吸到线内侧那格。读数框点开可手输。
class _CanvasEditor extends StatefulWidget {
  const _CanvasEditor({
    required this.width,
    required this.height,
    required this.onChanged,
  });

  final int width;
  final int height;
  final void Function(int w, int h) onChanged;

  @override
  State<_CanvasEditor> createState() => _CanvasEditorState();
}

class _CanvasEditorState extends State<_CanvasEditor> {
  /// 本次拖拽吸住的线(像素预算),null = 没吸。只管手势判定,不进 build。
  int? _stuck;

  void _fromLocal(Offset local, double side) {
    final x = (local.dx / side).clamp(0.0, 1.0) * _axisMax;
    final y = (local.dy / side).clamp(0.0, 1.0) * _axisMax;
    final dpPerPx = side / _axisMax;
    int? line;
    var nearest = double.infinity;
    for (final budget in _pixelLines) {
      final d = distanceToPixelLine(x, y, budget) * dpPerPx;
      final reach = budget == _stuck ? _snapOutDp : _snapInDp;
      if (d <= reach && d < nearest) {
        line = budget;
        nearest = d;
      }
    }
    if (line != null && line != _stuck) Haptics.selection();
    _stuck = line;
    if (line != null) {
      final r = snapToPixelLine(x, y, line);
      widget.onChanged(r.w, r.h);
    } else {
      widget.onChanged(snapDim(x.round()), snapDim(y.round()));
    }
  }

  /// 读数框手输:走通用手输弹窗,步长 64、范围同画布。
  Future<void> _input({required bool isWidth}) async {
    final v = await showParamInput(
      context,
      title: isWidth ? context.l10n.width : context.l10n.height,
      value: (isWidth ? widget.width : widget.height).toDouble(),
      min: kMinDim.toDouble(),
      max: kMaxDim.toDouble(),
      divisions: (kMaxDim - kMinDim) ~/ kResSnapStep,
    );
    if (v == null || !mounted) return;
    final n = v.round();
    if (isWidth) {
      widget.onChanged(n, widget.height);
    } else {
      widget.onChanged(widget.width, n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final width = widget.width;
    final height = widget.height;
    final onChanged = widget.onChanged;
    final tier = classifyPixels(width, height);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: LayoutBuilder(
            builder: (context, cons) {
              final side = (cons.maxWidth.isFinite ? cons.maxWidth : 280.0)
                  .clamp(0.0, 300.0)
                  .toDouble();
              return SizedBox(
                width: side,
                height: side,
                child: GestureDetector(
                  // 用手势识别器抢占竞技场,避免竖向拖被底部浮层的「下拉关闭」偷走。
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _fromLocal(d.localPosition, side),
                  onPanUpdate: (d) => _fromLocal(d.localPosition, side),
                  onPanEnd: (_) => _stuck = null,
                  onPanCancel: () => _stuck = null,
                  child: CustomPaint(
                    painter: _ResCanvasPainter(
                      width: width,
                      height: height,
                      scheme: scheme,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // 读数 + 动作:交换钮夹在长宽之间(替代 ×)。动作按档位只出一个:
        // 消耗点数 → 缩到免费,超出上限 → 缩到上限。Wrap 兜底:字号调大时整组换行,
        // 不会把 chip 挤出界。
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ParamValueBox(
                  text: '$width',
                  onTap: () => _input(isWidth: true),
                ),
                const SizedBox(width: 6),
                _SwapBtn(onTap: () => onChanged(height, width)),
                const SizedBox(width: 6),
                ParamValueBox(
                  text: '$height',
                  onTap: () => _input(isWidth: false),
                ),
              ],
            ),
            // 免费档淡出但照常占位:chip 比读数行高一点,按需插拔会把整个面板
            // 顶高/缩回;常驻占位则三档布局完全一致。
            AnimatedOpacity(
              duration: Motion.fast,
              opacity: tier == PixelTier.free ? 0 : 1,
              child: IgnorePointer(
                ignoring: tier == PixelTier.free,
                child: _QuickChip(
                  tier == PixelTier.over ? '缩到上限' : '缩到免费',
                  onTap: () {
                    final r = tier == PixelTier.over
                        ? clampToMaxPixels(width, height)
                        : scaleToFree(width, height);
                    onChanged(r.w, r.h);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResCanvasPainter extends CustomPainter {
  _ResCanvasPainter({
    required this.width,
    required this.height,
    required this.scheme,
  });

  final int width;
  final int height;
  final ColorScheme scheme;

  Color _tierColor(PixelTier t) => switch (t) {
    PixelTier.free => _vizFree,
    PixelTier.paid => scheme.primary,
    PixelTier.over => _vizOver,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );

    // 底 + 圆角裁剪
    canvas.drawRRect(rrect, Paint()..color = scheme.surfaceContainerHigh);
    canvas.save();
    canvas.clipRRect(rrect);

    // 网格(每 256 真实像素一线)
    final grid = Paint()
      ..color = scheme.onSurface.withValues(alpha: .06)
      ..strokeWidth = .5;
    for (double px = 256; px < _axisMax; px += 256) {
      final c = px / _axisMax * s;
      canvas.drawLine(Offset(c, 0), Offset(c, s), grid);
      canvas.drawLine(Offset(0, c), Offset(s, c), grid);
    }

    // 等像素双曲线:免费线(绿)/上限线(红);右下角贴在哪条上,哪条描实
    _hyperbola(canvas, s, kFreePixelThreshold, _vizFree, 3, 3);
    _hyperbola(canvas, s, kMaxTotalPixels, _vizOver, 4, 3);

    // 当前尺寸矩形(左上锚定)
    final rw = (width / _axisMax).clamp(0.0, 1.0) * s;
    final rh = (height / _axisMax).clamp(0.0, 1.0) * s;
    final tier = classifyPixels(width, height);
    final col = _tierColor(tier);
    final rect = Rect.fromLTWH(0, 0, rw, rh);
    canvas.drawRect(rect, Paint()..color = col.withValues(alpha: .18));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = col,
    );

    // 右下角把手 + 抓握斜线
    final hc = Offset(rw, rh);
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: hc, width: 22, height: 22),
      const Radius.circular(5),
    );
    canvas.drawRRect(handle, Paint()..color = col);
    final grip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    for (final d in const [-4.0, 0.0, 4.0]) {
      canvas.drawLine(
        Offset(hc.dx + d, hc.dy + 4),
        Offset(hc.dx + 4, hc.dy + d),
        grip,
      );
    }

    canvas.restore();
    // 外描边
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = scheme.outlineVariant,
    );
  }

  /// w×h=pixels 的等像素线,离散成虚线路径(与 web buildHyperbolaPath 同构)。
  void _hyperbola(
    Canvas canvas,
    double s,
    int pixels,
    Color color,
    double on,
    double off,
  ) {
    final path = Path();
    var started = false;
    for (
      double xpx = kResSnapStep.toDouble();
      xpx <= _axisMax;
      xpx += kResSnapStep
    ) {
      final ypx = pixels / xpx;
      if (ypx > _axisMax) continue;
      final cx = xpx / _axisMax * s;
      final cy = ypx / _axisMax * s;
      if (!started) {
        path.moveTo(cx, cy);
        started = true;
      } else {
        path.lineTo(cx, cy);
      }
    }
    if (!started) return;
    final hit = isOnPixelLine(width, height, pixels);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hit ? 1.6 : 1
      ..color = color.withValues(alpha: hit ? .9 : .5);
    canvas.drawPath(hit ? path : _dash(path, on, off), paint);
  }

  Path _dash(Path src, double on, double off) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var dist = 0.0;
      while (dist < m.length) {
        out.addPath(m.extractPath(dist, dist + on), Offset.zero);
        dist += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_ResCanvasPainter old) =>
      old.width != width || old.height != height || old.scheme != scheme;
}

/// 长宽之间的交换钮:小巧圆钮,替代 ×,省出横向空间。
class _SwapBtn extends StatelessWidget {
  const _SwapBtn({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Tooltip(
      message: context.l10n.swapDimensions,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              Icons.swap_horiz,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.compress,
                size: 15,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.texts.bodySmall!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final SizePreset preset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final ratio = preset.width / preset.height;
    const box = 44.0;
    final w = ratio >= 1 ? box : box * ratio;
    final h = ratio >= 1 ? box / ratio : box;
    // 浮卡选中是实心主色,框和小字换成前景色
    final solid = selected && context.skin.float;
    return AnimatedContainer(
      duration: Motion.fast,
      decoration: BoxDecoration(
        color: selected ? context.selectedFill : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            child: Column(
              children: [
                SizedBox(
                  width: box,
                  height: box,
                  child: Center(
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: solid
                              ? context.onSelectedFill
                              : selected
                              ? scheme.primary
                              : scheme.outline,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _sizeLabel(context.l10n, preset.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? context.onSelectedFill : scheme.onSurface,
                  ),
                ),
                Text(
                  preset.ratio,
                  style: TextStyle(
                    fontSize: 10,
                    color: solid
                        ? context.onSelectedFill
                        : scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${preset.width}×${preset.height}',
                  style: mono(context, size: 9.5, weight: FontWeight.w500)
                      .copyWith(
                        color: solid
                            ? context.onSelectedFill.withValues(alpha: .8)
                            : scheme.outline,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/param_help.dart';
import '../../../core/ui/param_input.dart';
import '../../../core/util/haptics.dart';

// ExpandBody 已挪到 core/ui(多选底栏等非 generate 的地方也在用)。
// 这里转出去,老的 `show ExpandBody` 导入照常可用。
export '../../../core/ui/expand_body.dart';
// 参数说明:滑杆的 help 参数收 ParamHelp,顺手把 Help 表转出去,
// 调用点 `import 'common.dart'` 就能写 `help: Help.steps`。
export '../../../core/ui/param_help.dart';
// 读数框 / 手输弹窗 / quantizeToDivisions —— 药丸滑杆(重绘、步数)也在用,
// 所以本体在 core/ui,这里只转出去。
export '../../../core/ui/param_input.dart';

/// 拖动排序的浮起样式:替换 ReorderableListView 默认代理
/// (Material 白底 + 阴影),改为微放大、无底色 —— 圆角卡片/缩略图不穿帮。
Widget dragProxy(Widget child, int index, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(scale: 1 + .06 * t, child: child);
      },
    );

/// 拖动排序开始的触感反馈(长按拾起)。
void dragStartHaptic(int _) => Haptics.medium();

/// 拖动排序落定的触感反馈。
void dragEndHaptic(int _) => Haptics.selection();

/// 圆形图标按钮(卡片头部的 + / 管理器等)
class RoundIconBtn extends StatelessWidget {
  const RoundIconBtn(
    this.icon, {
    super.key,
    this.onTap,
    this.color,
    this.size = 36,
    this.iconSize = 20,
    this.tooltip,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final double iconSize;
  final String? tooltip;

  /// 底色;默认 surfaceContainerHigh。
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: background ?? context.scheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: color ?? context.scheme.primary,
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 计数徽章(角色 2/6、Vibe 2 等)
class CountBadge extends StatelessWidget {
  const CountBadge(this.text, {super.key, this.error = false});

  final String text;

  /// 超限态(如 NAI 5 存的 20 张角色切回 V4 后只剩 6 个槽位):
  /// 换错误容器色提醒 —— 超出部分不进载荷,读数得让人看出「多了」。
  final bool error;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: error
            ? context.scheme.errorContainer
            : context.scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: context.texts.labelSmall!.copyWith(
          color: error
              ? context.scheme.onErrorContainer
              : context.scheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 参数滑杆:标签 + 数值读数 + Slider,展开卡与 Sheet 通用
///
/// [divisions] 只定步长,**绝不下传给底层 Slider**:离散 Slider 每次都用 75ms
/// easeInOut 把滑块「吸」到刻度上,手指已经走了滑块还在追,就是那股阻尼感。
/// 这里改为拖动连续、就地量化——滑块永远贴着手指,数值照样落在步长上。
class ParamSlider extends StatelessWidget {
  const ParamSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.inputDivisions,
    this.valueText,
    this.caption,
    this.trailing,
    this.dense = false,
    this.help,
    this.snapTo,
  });

  final String label;
  final double value;

  /// null = 只读(滑杆走 M3 禁用态,读数框也不再可点);标签上的说明照样能点开。
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;

  /// 手输弹窗的步长,默认跟 [divisions] 走。
  /// [LiveParamSlider] 拖动要连续所以不下传 divisions,但手输仍该落在刻度上。
  final int? inputDivisions;
  final String? valueText;
  final String? caption;
  final Widget? trailing;
  final bool dense;

  /// 给上则参数说明:标签变成可点的「标签 + 问号」。
  final ParamHelp? help;

  /// 拖动吸附点:离它不到一格就落在它上面。
  final double? snapTo;

  double _snap(double v) {
    final s = snapTo;
    if (s != null &&
        divisions != null &&
        (v - s).abs() < (max - min) / divisions!) {
      return s;
    }
    return quantizeToDivisions(v, min: min, max: max, divisions: divisions);
  }

  /// 读数框弹出手输。拖动是 onChanged 一路走到 onChangeEnd,手输也照这条路
  /// 发一遍(两个回调都发):LiveParamSlider 那种「拖动本地、松手提交」的
  /// 分工才不用为手输另开一条口子。
  Future<void> _input(BuildContext context) async {
    final v = await showParamInput(
      context,
      title: label,
      value: value,
      min: min,
      max: max,
      divisions: inputDivisions ?? divisions,
    );
    if (v == null) return;
    onChanged?.call(v);
    onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = dense
        ? context.texts.labelSmall!.copyWith(
            color: context.scheme.onSurfaceVariant,
          )
        : context.texts.bodySmall!.copyWith(color: context.scheme.onSurface);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: help == null
                  ? Text(label, style: labelStyle)
                  : HelpLabel(text: label, help: help!, style: labelStyle),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
            ParamValueBox(
              text: valueText ?? value.toStringAsFixed(2),
              dense: dense,
              onTap: onChanged == null ? null : () => _input(context),
            ),
          ],
        ),
        SizedBox(
          height: dense ? 26 : 32,
          child: SliderTheme(
            data: SliderThemeData(
              padding: EdgeInsets.zero,
              trackHeight: dense ? 3 : 4,
              thumbSize: WidgetStatePropertyAll(Size.fromRadius(dense ? 7 : 9)),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged == null ? null : (v) => onChanged!(_snap(v)),
              onChangeEnd: onChangeEnd == null
                  ? null
                  : (v) => onChangeEnd!(_snap(v)),
            ),
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: context.texts.labelSmall!.copyWith(
              color: context.scheme.outline,
            ),
          ),
      ],
    );
  }
}

/// 拖动时只更新本地读数(不触发外部 provider 重建),松手才 [onCommit]。
/// 用于「拖一下就整页重建」的场景(如 vibe/角色强度),避免每帧全量重建卡顿。
class LiveParamSlider extends StatefulWidget {
  const LiveParamSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onCommit,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.caption,
    this.dense = false,
    this.help,
    this.valueTextOf,
    this.enabled = true,
  });

  final String label;
  final double value;
  final ValueChanged<double> onCommit;
  final double min;
  final double max;
  final int? divisions;
  final String? caption;
  final bool dense;
  final ParamHelp? help;

  /// false = 只读:滑杆走 M3 禁用态、读数框不可点(仍显示当前值,说明照样能点开)。
  /// 给「常驻显示但当前不该改」的参数用,别为此把整块藏起来。
  final bool enabled;

  /// 读数格式化;拿到的是**拖动中的实时值**(未量化)。null = 默认两位小数。
  /// [ParamSlider.valueText] 是死串,这里必须是函数——拖动时读数得跟着走。
  final String Function(double)? valueTextOf;

  @override
  State<LiveParamSlider> createState() => _LiveParamSliderState();
}

class _LiveParamSliderState extends State<LiveParamSlider> {
  double? _drag; // 拖动中的本地值;null = 用 widget.value

  @override
  Widget build(BuildContext context) {
    final live = _drag ?? widget.value;
    return ParamSlider(
      label: widget.label,
      value: live,
      min: widget.min,
      max: widget.max,
      valueText: widget.valueTextOf?.call(live),
      // 拖动时连读数都不量化(本地值,不外发);松手才按步长落位。
      // 手输走弹窗、没有「拖」的过程,步长照给。
      inputDivisions: widget.divisions,
      caption: widget.caption,
      dense: widget.dense,
      help: widget.help,
      onChanged: widget.enabled ? (v) => setState(() => _drag = v) : null,
      onChangeEnd: widget.enabled
          ? (v) {
              widget.onCommit(
                quantizeToDivisions(
                  v,
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                ),
              );
              setState(() => _drag = null); // 同帧父级会带新值下来,不闪
            }
          : null,
    );
  }
}

/// 斜纹占位缩略图(设计稿中的图片占位)
class StripeThumb extends StatelessWidget {
  const StripeThumb({
    super.key,
    required this.width,
    required this.height,
    this.radius = 11,
    this.onClose,
    this.label,
    this.image,
  });

  final double width;
  final double height;
  final double radius;
  final VoidCallback? onClose;
  final String? label;

  /// 有真实图则显示它(cover),否则斜纹占位。
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: image != null
                ? Image.memory(
                    image!,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    // 只给 cacheWidth(保比例):图像缓存存的是**解码后的位图**,
                    // 不限制的话一张 1536×1024 原图要占 6.3MB,而这里只画 72dp。
                    // 参考图条同屏可有 6 vibe + 6 CR,不限就是几十 MB 白烧。
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  )
                : CustomPaint(
                    size: Size(width, height),
                    painter: _StripePainter(
                      context.scheme.surfaceContainerHighest,
                      context.scheme.surfaceContainerHigh,
                    ),
                  ),
          ),
          if (onClose != null)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: context.scheme.scrim.withValues(alpha: .6),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onClose,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: context.scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          if (label != null)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: context.scheme.scrim.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  style: mono(
                    context,
                    size: 9,
                    color: context.scheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter(this.a, this.b);

  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    // 斜纹是平行四边形,右端会伸出画布 size.height 那么远,而 CustomPaint 默认
    // **不裁剪** —— 现有调用点都套着 ClipRRect 才没出事。自己兜住,免得哪天有人
    // 不加裁剪就用(图库大图占位就这么把条纹糊到隔壁页去过)。
    canvas.clipRect(Offset.zero & size);
    final paintA = Paint()..color = a;
    final paintB = Paint()..color = b;
    canvas.drawRect(Offset.zero & size, paintB);
    const w = 8.0;
    for (double x = -size.height; x < size.width; x += w * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + w, 0)
        ..lineTo(x + w, size.height)
        ..close();
      canvas.drawPath(path, paintA);
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) => old.a != a || old.b != b;
}

/// 卡片底部的说明行
class InfoNote extends StatelessWidget {
  const InfoNote(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.color,
  });

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.outline;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: context.texts.labelSmall!.copyWith(
              color: context.scheme.outline,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// 二级全屏页的路由(编辑器、令牌管理、LoRA 管理这类)。
///
/// **走主题的转场**(安卓上是左右滑动,见 `SlideBackPageTransitionsBuilder`)。原先是
/// `PageRouteBuilder` + 竖向 shared-axis 转场,自己画的动画绕过了主题,于是同一个 app
/// 里有的二级页是一种动画、有的是另一种。统一走主题,改转场只改主题一处。
/// 名字沿用旧的,省得二十来个调用点跟着改。
///
/// 不做成泛型:调用点都不接收返回值,带上 `<T>` 只会让每处推断失败退化成
/// dynamic。将来真有页面要回传结果,再单独加一个泛型版本。
Route<void> sharedAxisRoute(Widget page) =>
    MaterialPageRoute<void>(builder: (_) => page);

/// 参考图横条里的可选缩略图 —— Vibe / 角色参考 共用。
/// 不带删除角标(移除统一走详情区按钮),长按由外层拖动排序接管。
class RefThumb extends StatelessWidget {
  const RefThumb({
    super.key,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.width = 60,
    this.height = 60,
    this.image,
  });

  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final double width;
  final double height;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            AnimatedOpacity(
              duration: Motion.fast,
              opacity: enabled ? 1 : .35,
              child: StripeThumb(
                width: width,
                height: height,
                radius: 11,
                image: image,
              ),
            ),
            if (!enabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.visibility_off,
                      size: 22,
                      color: scheme.onSurface.withValues(alpha: .8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 启用/停用开关(裸电源图标)—— Vibe / 角色参考 / LoRA / 重绘放大 共用
class RefEnableToggle extends StatelessWidget {
  const RefEnableToggle({
    super.key,
    required this.enabled,
    required this.onTap,
    this.onTooltip = '停用此参考图',
    this.offTooltip = '启用',
  });

  final bool enabled;
  final VoidCallback onTap;

  /// 已启用/已停用时的长按提示(非参考图的调用方要改写)。
  final String onTooltip;
  final String offTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          Icons.power_settings_new,
          size: 24,
          color: enabled ? scheme.primary : scheme.outline,
        ),
        // 图标字体只有一档笔画,「加粗」只能靠字号 + 启用时的主色底托
        style: IconButton.styleFrom(
          backgroundColor: enabled
              ? scheme.primary.withValues(alpha: .12)
              : Colors.transparent,
        ),
        tooltip: enabled ? onTooltip : offTooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 虚线「添加」格 —— Vibe / 角色参考 共用
class AddTile extends StatelessWidget {
  const AddTile({
    super.key,
    required this.onTap,
    this.width = 60,
    this.height = 60,
  });

  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: CustomPaint(
          painter: DashedBorderPainter(scheme.outline),
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 22, color: scheme.primary),
                const SizedBox(height: 2),
                Text(
                  '添加',
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// 参考图详情头:「参考图 N」+ 文件名 + 移除药丸 —— Vibe / 角色参考 共用
class RefDetailHeader extends StatelessWidget {
  const RefDetailHeader({
    super.key,
    required this.index,
    required this.name,
    required this.onRemove,
    this.enableToggle,
    this.leadingAction,
  });

  final int index;
  final String name;
  final VoidCallback onRemove;

  /// 行首的启用/停用开关
  final Widget? enableToggle;

  /// 放在「移除」按钮左侧的额外控件(如角色参考的迁移模式切换)
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Row(
      children: [
        if (enableToggle != null) ...[enableToggle!, const SizedBox(width: 4)],
        Text(
          '参考图 $index',
          style: context.texts.bodyLarge!.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        // Expanded 占满中段,把尾部(切换 + 移除)顶到最右
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (leadingAction != null) ...[
          leadingAction!,
          const SizedBox(width: 8),
        ],
        Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 6),
                  Text(
                    '移除',
                    style: context.texts.bodyMedium!.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 虚线圆角边框
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter(this.color);

  final Color color;
  static const double radius = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(radius),
        ),
      );
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) => old.color != color;
}

/// 通用确认弹窗(破坏性操作用红色确认键)。返回 true = 确认。
/// 二次确认弹窗。[danger] 决定确认键用不用错误色 —— 默认真,因为这个函数的
/// 调用点绝大多数是删除/清空。发布、同意这类**不会毁数据**的动作传 false,
/// 否则一个红底的「我已确认,发布」看着像在警告用户别按。
/// [body] 给了就用它当正文(参数表之类排过版的内容),否则用 [message] 那段字。
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? body,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool danger = true,
}) async {
  assert(message != null || body != null);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body ?? Text(message ?? ''),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: context.scheme.error,
                  foregroundColor: context.scheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void todoSnack(BuildContext context, String what) =>
    hintSnack(context, '$what · 下一里程碑接入', icon: Icons.upcoming_outlined);

/// 弹层关掉之后**别把焦点还给刚才那个输入框**。
///
/// Flutter 的默认行为是路由 pop 之后恢复上一次的焦点,于是「输入框点过 → 打开
/// 弹层 → 关掉」会把软键盘重新顶出来,而用户只是去看了眼东西、并不打算打字。
/// 给纯查看类的弹层(选模型、看历史、看提议详情)在关闭后调一下。
///
/// 掉两次:pop 当帧一次、下一帧再一次 —— 焦点恢复发生在 pop 的收尾里,
/// 只掉当帧的话会被随后的恢复盖回去。
void dropFocusSoon() {
  FocusManager.instance.primaryFocus?.unfocus();
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => FocusManager.instance.primaryFocus?.unfocus(),
  );
}

// ---- 顶部悬浮提示(全 app 统一;替代底部 SnackBar) ----

/// 当前型号不可调的参数:照常显示实际生效值、压暗、不接手势,点一下弹 [hint]。
/// hint 为 null = 可调,原样返回。
class LockedParam extends StatelessWidget {
  const LockedParam({super.key, required this.hint, required this.child});

  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = hint;
    if (h == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => hintSnack(context, h),
      child: IgnorePointer(child: Opacity(opacity: .45, child: child)),
    );
  }
}

OverlayEntry? _activeToast;

void _removeActiveToast() {
  final e = _activeToast;
  _activeToast = null;
  if (e != null && e.mounted) e.remove();
}

/// 轻提示:顶部悬浮 toast(root overlay,pop 路由也不消失)。
/// 3 秒自动消失(带动作按钮 4 秒),点击提示本体立即关闭,新提示顶掉旧提示。
/// 可选 [actionLabel]+[onAction] 提供一个动作按钮(如「撤销」「去设置」)。
void hintSnack(
  BuildContext context,
  String text, {
  IconData icon = Icons.info_outline,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _removeActiveToast();
  late final OverlayEntry entry;
  void done() {
    if (identical(_activeToast, entry)) _activeToast = null;
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _TopToast(
      text: text,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: Duration(seconds: actionLabel != null ? 4 : 3),
      onDismissed: done,
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.text,
    required this.icon,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _close);
  }

  /// 收场动画后移除 overlay;被新提示强拆(dispose)时由调用侧兜底。
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    _c.reverse().whenCompleteOrCancel(widget.onDismissed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -0.8), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _c,
            curve: Motion.emphasized,
            reverseCurve: Motion.standard,
          ),
        ),
        child: FadeTransition(
          opacity: _c,
          child: Center(
            child: Material(
              color: scheme.inverseSurface,
              elevation: 6,
              shadowColor: scheme.shadow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _close,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    17,
                    11,
                    widget.actionLabel != null ? 8 : 17,
                    11,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: 19,
                        color: scheme.onInverseSurface,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.text,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.3,
                            color: scheme.onInverseSurface,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 6),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () {
                            widget.onAction?.call();
                            _close();
                          },
                          child: Text(
                            widget.actionLabel!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: scheme.inversePrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

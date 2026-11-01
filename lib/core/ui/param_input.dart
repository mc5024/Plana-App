import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../util/haptics.dart';

/// 把 [v] 量化到 [divisions] 等分的刻度上。算法与 Flutter 自己的 `_discretize`
/// 一致(归一化 → 取整 → 插值回去),换掉离散 Slider 后取值分毫不差。
double quantizeToDivisions(
  double v, {
  required double min,
  required double max,
  int? divisions,
}) {
  if (divisions == null || divisions <= 0 || max <= min) return v;
  final t = ((v - min) / (max - min)).clamp(0.0, 1.0);
  return min + (t * divisions).round() / divisions * (max - min);
}

/// 步长;连续滑杆(无 divisions)返回 null。
double? stepOf({required double min, required double max, int? divisions}) =>
    (divisions == null || divisions <= 0 || max <= min)
    ? null
    : (max - min) / divisions;

/// 步长 → 读数/输入该保留几位小数(0.05 → 2,1 → 0)。
/// 连续滑杆没有步长可推,退回两位 —— 与 [ParamValueBox] 的默认读数一致。
int decimalsForStep(double? step) {
  if (step == null || step <= 0) return 2;
  for (var d = 0; d <= 3; d++) {
    final scaled = step * _pow10[d];
    if ((scaled - scaled.roundToDouble()).abs() < 1e-6) return d;
  }
  return 3;
}

const _pow10 = [1.0, 10.0, 100.0, 1000.0];

/// 去掉尾随零的紧凑写法(范围/步长提示用):1.10 → 1.1,200.000 → 200。
String _plain(double v) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// 参数读数框:滑杆右侧那颗数字,点一下弹窗手输。
///
/// [onTap] 为 null(只读参数)时边框和底色一起收掉 —— 框着就该能点。
class ParamValueBox extends StatelessWidget {
  const ParamValueBox({
    super.key,
    required this.text,
    this.onTap,
    this.dense = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final enabled = onTap != null;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: dense ? 48 : 56),
      child: Material(
        color: enabled ? scheme.surfaceContainerHigh : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: enabled ? scheme.outlineVariant : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 8 : 10,
              vertical: dense ? 4 : 5,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: mono(
                context,
                size: dense ? 11 : 13,
                color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 手输参数值。确定 → 返回钳进 [min],[max] 并对齐步长的值;取消 → null。
///
/// 超范围**不静默钳住**:直接在输入框下报出范围,免得用户以为自己填的数生效了。
Future<double?> showParamInput(
  BuildContext context, {
  required String title,
  required double value,
  double min = 0,
  double max = 1,
  int? divisions,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _ParamInputDialog(
      title: title,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
    ),
  );
}

class _ParamInputDialog extends StatefulWidget {
  const _ParamInputDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;

  @override
  State<_ParamInputDialog> createState() => _ParamInputDialogState();
}

class _ParamInputDialogState extends State<_ParamInputDialog> {
  late final double? _step = stepOf(
    min: widget.min,
    max: widget.max,
    divisions: widget.divisions,
  );
  late final int _decimals = decimalsForStep(_step);
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.value
          .clamp(widget.min, widget.max)
          .toStringAsFixed(_decimals),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _range => '${_plain(widget.min)} ~ ${_plain(widget.max)}';

  /// 框里当前的数;打了一半没法解析就退回原值(加减键不该因为手滑失灵)。
  double get _current => (double.tryParse(_ctrl.text.trim()) ?? widget.value)
      .clamp(widget.min, widget.max);

  /// 加减一格。没有 divisions 的连续参数按百分之一档走。
  void _nudge(int dir) {
    final step = _step ?? (widget.max - widget.min) / 100;
    final next = quantizeToDivisions(
      (_current + dir * step).clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
    );
    Haptics.selection();
    final s = next.toStringAsFixed(_decimals);
    // 程序改文本不会走 onChanged,加减键的可用态得自己 setState 刷
    setState(() {
      _error = null;
      _ctrl.value = TextEditingValue(
        text: s,
        selection: TextSelection.collapsed(offset: s.length),
      );
    });
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null) {
      setState(() => _error = '请输入数字');
      return;
    }
    // 留一点浮点容差:边界值(如 max=0.99)按位数打出来再读回来会差个尾数
    if (v < widget.min - 1e-9 || v > widget.max + 1e-9) {
      setState(() => _error = '超出范围 $_range');
      return;
    }
    Navigator.pop(
      context,
      quantizeToDivisions(
        v.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return AlertDialog(
      // 压掉 M3 弹窗标题的 headlineSmall(24sp):这里的标题是参数名,
      // 「Info Extracted 信息提取」那种长度按 24sp 排要占掉两行
      title: Text(widget.title, style: context.texts.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepBtn(
                icon: Icons.remove,
                // 到底了就灰掉:按着没反应比按不了更像坏了
                onTap: _current > widget.min + 1e-9 ? () => _nudge(-1) : null,
              ),
              const SizedBox(width: 8),
              // 占满两键之间:弹窗窄到 280 也不会把加减键挤出去
              // (范围/步长那行已经挪到框外,这里只管放数字)
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textAlign: TextAlign.center,
                  style: mono(context, size: 18),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: _decimals > 0,
                    signed: widget.min < 0,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  // 加减键的可用态跟着输入走,每次改动都要重建
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StepBtn(
                icon: Icons.add,
                onTap: _current < widget.max - 1e-9 ? () => _nudge(1) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _error ??
                (_step == null
                    ? '范围 $_range'
                    : '范围 $_range · 步长 ${_plain(_step)}'),
            textAlign: TextAlign.center,
            style: context.texts.labelSmall!.copyWith(
              color: _error == null ? scheme.outline : scheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

/// 弹窗里的加减键。44dp 方键,圆角跟中间的输入框对齐;
/// 到边界就传 null 走灰态。长按连发,越按越快,到边界自停。
class _StepBtn extends StatefulWidget {
  const _StepBtn({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_StepBtn> createState() => _StepBtnState();
}

class _StepBtnState extends State<_StepBtn> {
  Timer? _timer;
  int _ticks = 0;

  void _start() {
    _ticks = 0;
    _repeat();
  }

  /// 每次触发读最新的 [widget.onTap]:到边界变成 null 就停。
  void _repeat() {
    final tap = widget.onTap;
    if (tap == null) return _stop();
    tap();
    _ticks++;
    _timer = Timer(
      Duration(milliseconds: math.max(40, 120 - _ticks * 8)),
      _repeat,
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final onTap = widget.onTap;
    return GestureDetector(
      onLongPressStart: onTap == null ? null : (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              widget.icon,
              size: 20,
              color: onTap == null ? scheme.outlineVariant : scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

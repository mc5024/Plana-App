/// 设置弹层的行版式。编辑器设置和助手设置共用 —— 同一个 app 里两处设置长得
/// 不一样,用户会以为自己进错了地方。
///
/// 一行是:图标 + 标题 + 一句说明 + 右侧控件(开关 / 加减 / 选中项 / 跳转),整行可点。
/// **说明是这套版式的一部分**:这些设置改的都是「以后会自动发生什么」,
/// 光看标题猜不出边界(「在对话内显示图片」到底还存不存图库),而猜错的代价
/// 是点数和画布。
library;

import 'package:flutter/material.dart';

import '../../features/editor/widgets/tag_panel.dart' show RepeatBtn;
import '../theme/app_skin.dart';
import '../theme/app_theme.dart';
import '../util/haptics.dart';

/// 分组小标题。
Widget settingSection(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
  child: Text(
    text,
    style: context.texts.labelSmall!.copyWith(
      color: context.scheme.primary,
      fontWeight: FontWeight.w700,
    ),
  ),
);

/// 单行开关:整行可点,图标随开关着色;[enabled] = false 时整行淡显不可点。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  void _flip(bool v) {
    Haptics.selection();
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: enabled ? () => _flip(!value) : null,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: enabled ? 1 : .42,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 14, 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: value ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SettingRowTexts(title: title, desc: desc),
              ),
              const SizedBox(width: 8),
              Switch(value: value, onChanged: enabled ? _flip : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单行选择:右侧显示当前选中项,整行点开一个居中的单选对话框,点一项就选中关掉。
///
/// 不用分段按钮 —— 选项文字一长(「本地库 + 公共库」)就得折行或截断,而这一页
/// 其余几行都是「左边说明 + 右侧一个控件」,分段按钮会把版式撑成另一种。
/// 也不用贴着那个值弹的菜单:位置跟着行走,在弹层里看着像是随手冒出来的。
class SettingChoiceRow<T> extends StatelessWidget {
  const SettingChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.enabled = true,
    this.optionEnabled,
    this.optionNote,
  });

  final IconData icon;
  final String title;
  final String desc;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final bool enabled;
  final ValueChanged<T> onChanged;

  /// 某一项现在能不能选。不能选的照样列出来(置灰),免得用户以为没有这一档。
  final bool Function(T)? optionEnabled;

  /// 某一项下面的一行小字,通常用来说为什么选不了。
  final String? Function(T)? optionNote;

  Future<void> _open(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: RadioGroup<T>(
          groupValue: value,
          onChanged: (v) => Navigator.of(ctx).pop(v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                RadioListTile<T>(
                  value: o,
                  enabled: optionEnabled?.call(o) ?? true,
                  title: Text(labelOf(o)),
                  subtitle: switch (optionNote?.call(o)) {
                    final note? => Text(note),
                    null => null,
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked == null || picked == value) return;
    Haptics.selection();
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: enabled ? 1 : .42,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 14, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: SettingRowTexts(title: title, desc: desc),
              ),
              const SizedBox(width: 8),
              Text(
                labelOf(value),
                style: context.texts.labelLarge!.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.unfold_more, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 加减调节行:左边图标+标题,右边一组 `− 读数 +`。
///
/// 为什么不是档位:字号、权重步进这类偏好没有天然的"三五个正确值" ——
/// 屏幕尺寸、视力、习惯的加权幅度各不相同,给了三档总有人卡在两档之间。
/// 按钮支持长按连发([RepeatBtn]),大范围也不用点几十下。
class SettingStepperRow extends StatelessWidget {
  const SettingStepperRow({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String desc;
  final double value;
  final double min;
  final double max;
  final double step;

  /// 读数怎么写(字号取整、步进去尾零)。
  final String Function(double) format;

  final bool enabled;
  final ValueChanged<double> onChanged;

  /// 按整数格数走再落回实数:直接 `value += step` 累加浮点误差,连点几十下
  /// 就会漂成 0.30000000000000004 这种,存进设置里再读出来更难看。
  void _bump(int dir) {
    final ticks = (value / step).round() + dir;
    final next = (ticks * step).clamp(min, max).toDouble();
    // 再夹一次到步长网格上,顺便把二进制小数的零头抹掉
    final snapped = double.parse(next.toStringAsFixed(4));
    if (snapped == value) return;
    Haptics.selection();
    onChanged(snapped);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: enabled ? 1 : .42,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: SettingRowTexts(title: title, desc: desc),
            ),
            const SizedBox(width: 8),
            IgnorePointer(
              ignoring: !enabled,
              child: Row(
                children: [
                  RepeatBtn(
                    icon: Icons.remove,
                    size: 32,
                    enabled: enabled && value > min,
                    step: () => _bump(-1),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      format(value),
                      textAlign: TextAlign.center,
                      style: mono(context, size: 15, weight: FontWeight.w700),
                    ),
                  ),
                  RepeatBtn(
                    icon: Icons.add,
                    size: 32,
                    enabled: enabled && value < max,
                    step: () => _bump(1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单行跳转:右侧显示当前状态,整行点进下一页。
class SettingNavRow extends StatelessWidget {
  const SettingNavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 10, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: SettingRowTexts(title: title, desc: desc),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: context.texts.labelLarge!.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 20, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 标题 + 说明那两行。开关行、加减行都用它,免得两处的行高对不齐。
class SettingRowTexts extends StatelessWidget {
  const SettingRowTexts({super.key, required this.title, required this.desc});

  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: context.texts.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 2),
      Text(
        desc,
        style: context.texts.labelSmall!.copyWith(
          color: context.scheme.outline,
        ),
      ),
    ],
  );
}

/// 设置弹层的外壳:自带抓手 + 标题栏 + 右上角关闭,正文可滚。
///
/// 抓手与标题栏留在滚动区**外面**:整片都塞进 `SingleChildScrollView` 的话,
/// 下拉手势全被滚动条吃掉,弹层自带的下拉关闭永远轮不到。右上角那颗 ✕ 是兜底。
class SettingSheet extends StatelessWidget {
  const SettingSheet({
    super.key,
    required this.title,
    required this.children,
    this.maxHeight,
  });

  final String title;
  final List<Widget> children;

  /// 封顶高度;不给就按屏高 85%。
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: context.raisedFill(scheme.surfaceContainer),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight ?? MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

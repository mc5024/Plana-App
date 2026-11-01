import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/store/ui_prefs.dart';

import '../../core/store/gen_settings.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../gallery/save_settings.dart';
import '../generate/gen_modules.dart';
import 'widgets/settings_ui.dart';

class GenSettingsPage extends ConsumerWidget {
  const GenSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(genSettingsProvider).value ?? const GenSettings();
    void patch(GenSettings Function(GenSettings) change) =>
        ref.read(genSettingsProvider.notifier).patch(change);

    return Scaffold(
      appBar: AppBar(title: const Text('生成设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          SettingsCard(
            children: [
              SwitchListTile(
                value: s.genNotify,
                onChanged: (v) => patch((x) => x.copyWith(genNotify: v)),
                title: Text(
                  '生成通知',
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
              ),
              SwitchListTile(
                value: s.streamGen,
                onChanged: (v) => patch((x) => x.copyWith(streamGen: v)),
                title: Text(
                  '流式生成',
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
              ),
              SwitchListTile(
                value: s.straightAlpha,
                onChanged: (v) => patch((x) => x.copyWith(straightAlpha: v)),
                title: Text(
                  '透明图直通 Alpha',
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
              ),
              SwitchListTile(
                value: s.retryOn429,
                onChanged: (v) => patch((x) => x.copyWith(retryOn429: v)),
                title: Text(
                  '限流后自动重试',
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
              ),
              if (s.retryOn429) ...[
                _ValueRow(
                  label: '重试间隔',
                  value: s.retryDelaySecs > 0 ? '${s.retryDelaySecs} 秒' : '立即',
                  dialogTitle: '重试间隔',
                  unit: '秒',
                  current: s.retryDelaySecs,
                  zeroLabel: '立即',
                  min: 0,
                  max: 600,
                  onChanged: (v) => patch((x) => x.copyWith(retryDelaySecs: v)),
                ),
                _ValueRow(
                  label: '重试次数',
                  value: '${s.retryCount} 次',
                  dialogTitle: '重试次数',
                  unit: '次',
                  current: s.retryCount,
                  min: 1,
                  max: 99,
                  onChanged: (v) => patch((x) => x.copyWith(retryCount: v)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const _ModulesSection(),
          const SizedBox(height: 16),
          const SettingsLabel('图库默认保存'),
          const _SaveDefaultsCard(),
        ],
      ),
    );
  }
}

/// 创作页功能模块:开关控制显隐,长按拖动调顺序(与主页卡片即时同步)。
///
/// 三个父类**共用一张卡**,顶上切换 —— 原先三组各一张标签 + 一张卡平铺,
/// 十行开关加三个标题占掉大半页,而模块本就归属唯一父类:改 Anima 的排布
/// 时看着 NAI 那四行,除了让页面变长没有任何用。
///
/// 开了几个记在标题右侧,不然收起另外两组之后,「我是不是在别处关过什么」
/// 这件事就没处看了。
class _ModulesSection extends ConsumerStatefulWidget {
  const _ModulesSection();

  @override
  ConsumerState<_ModulesSection> createState() => _ModulesSectionState();
}

class _ModulesSectionState extends ConsumerState<_ModulesSection> {
  late GenProvider _tab = GenProvider.values.firstWhere(
    (e) => e.name == ref.read(uiPrefsProvider).genSettingsTab,
    orElse: () => GenProvider.nai,
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(genModulesProvider).value ?? const GenModuleSettings();
    final order = s.orderOf(_tab);
    final on = order.where(s.isEnabled).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Text(
                '创作页模块',
                style: context.texts.labelMedium!.copyWith(
                  color: context.scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '已开 $on/${order.length}',
                style: context.texts.labelMedium!.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SegmentedButton<GenProvider>(
          showSelectedIcon: false,
          segments: [
            for (final p in GenProvider.values)
              ButtonSegment(value: p, label: Text(providerLabel(p))),
          ],
          selected: {_tab},
          onSelectionChanged: (v) {
            ref
                .read(uiPrefsProvider.notifier)
                .patch((p) => p.copyWith(genSettingsTab: v.first.name));
            setState(() => _tab = v.first);
          },
        ),
        const SizedBox(height: 8),
        _ModulesCard(_tab),
      ],
    );
  }
}

class _ModulesCard extends ConsumerWidget {
  const _ModulesCard(this.provider);

  final GenProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(genModulesProvider).value ?? const GenModuleSettings();
    final notifier = ref.read(genModulesProvider.notifier);
    final scheme = context.scheme;
    // 管理页列该组全部模块(型号能力门槛只影响主页显隐,偏好在此常驻可调)
    final order = s.orderOf(provider);

    return SettingsCard(
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) => Material(
            color: context.raisedFill(scheme.surfaceContainerHigh),
            borderRadius: BorderRadius.circular(12),
            elevation: 3,
            child: child,
          ),
          onReorderItem: (from, to) {
            notifier.patch((x) {
              final next = [...x.orderOf(provider)];
              next.insert(to, next.removeAt(from));
              return x.copyWith(order: {...x.order, provider: next});
            });
          },
          children: [
            for (var i = 0; i < order.length; i++)
              _ModuleRow(
                key: ValueKey(order[i]),
                index: i,
                module: order[i],
                enabled: s.isEnabled(order[i]),
                onChanged: (m, v) => notifier.patch(
                  (x) => x.copyWith(enabled: {...x.enabled, m: v}),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 单个模块行:抓手 + 图标 + 名称 + 开关;按住抓手即拖,整行长按也可拖。
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    super.key,
    required this.index,
    required this.module,
    required this.enabled,
    required this.onChanged,
  });

  final int index;
  final GenModule module;
  final bool enabled;
  final void Function(GenModule, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final def = genModuleDef(module);
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 30,
                height: 40,
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              def.icon,
              size: 20,
              color: enabled ? scheme.onSurfaceVariant : scheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                def.label,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled ? null : scheme.outline,
                ),
              ),
            ),
            Switch(value: enabled, onChanged: (v) => onChanged(module, v)),
          ],
        ),
      ),
    );
  }
}

/// 图库的默认保存方式(与长按保存的保存面板共用同一份设置)。
class _SaveDefaultsCard extends ConsumerWidget {
  const _SaveDefaultsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(saveSettingsProvider).value ?? const SaveSettings();
    void patch(SaveSettings Function(SaveSettings) change) =>
        ref.read(saveSettingsProvider.notifier).patch(change);

    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<SaveFormat>(
                segments: const [
                  ButtonSegment(value: SaveFormat.png, label: Text('PNG 无损')),
                  ButtonSegment(value: SaveFormat.jpg, label: Text('JPG 有损')),
                ],
                selected: {s.format},
                onSelectionChanged: (v) =>
                    patch((x) => x.copyWith(format: v.first)),
                showSelectedIcon: false,
              ),
              if (s.format == SaveFormat.png) ...[
                const SizedBox(height: 8),
                SegmentedButton<SaveMeta>(
                  segments: const [
                    ButtonSegment(
                      value: SaveMeta.original,
                      label: Text('原始元数据'),
                    ),
                    ButtonSegment(value: SaveMeta.clean, label: Text('清除')),
                    ButtonSegment(value: SaveMeta.custom, label: Text('自定义')),
                  ],
                  selected: {s.meta},
                  onSelectionChanged: (v) =>
                      patch((x) => x.copyWith(meta: v.first)),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (s.format == SaveFormat.jpg)
          _ValueRow(
            label: '压缩质量',
            value: '${(s.quality * 100).round()}',
            dialogTitle: '压缩质量(10~100)',
            unit: '',
            current: (s.quality * 100).round(),
            min: 10,
            max: 100,
            onChanged: (v) => patch((x) => x.copyWith(quality: v / 100)),
          ),
        if (s.format == SaveFormat.png && s.meta == SaveMeta.custom)
          _PromptRow(
            prompt: s.customPrompt,
            onChanged: (v) => patch((x) => x.copyWith(customPrompt: v)),
          ),
      ],
    );
  }
}

/// 自定义提示词行:点按弹多行输入。
class _PromptRow extends StatelessWidget {
  const _PromptRow({required this.prompt, required this.onChanged});

  final String prompt;
  final ValueChanged<String> onChanged;

  Future<void> _edit(BuildContext context) async {
    final ctl = TextEditingController(text: prompt);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义提示词'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(hintText: '写入图片的提示词(其余参数清除)…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) onChanged(result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final excerpt = prompt.trim().replaceAll('\n', ' ');
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Text(
              '自定义提示词',
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                excerpt.isEmpty ? '未设置' : excerpt,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.edit_outlined, size: 15, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 数值设置行:点按弹输入框;[zeroLabel] 非空时提供「0 = 该档」快捷键。
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.dialogTitle,
    required this.unit,
    required this.current,
    required this.min,
    required this.max,
    required this.onChanged,
    this.zeroLabel,
  });

  final String label;
  final String value;
  final String dialogTitle;
  final String unit;
  final int current;
  final int min;
  final int max;
  final String? zeroLabel;
  final ValueChanged<int> onChanged;

  Future<void> _edit(BuildContext context) async {
    final ctl = TextEditingController(text: current > 0 ? '$current' : '');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dialogTitle),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(suffixText: unit),
          onSubmitted: (v) =>
              Navigator.of(ctx).pop(int.tryParse(v.trim()) ?? min),
        ),
        actions: [
          if (zeroLabel != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(0),
              child: Text(zeroLabel!),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(ctl.text.trim()) ?? min),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) onChanged(result.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: mono(context, size: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 5),
            Icon(Icons.edit_outlined, size: 15, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

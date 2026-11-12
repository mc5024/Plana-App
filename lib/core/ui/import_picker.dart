import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 一条可自选的导入内容。
class ImportOption {
  const ImportOption({
    required this.key,
    required this.label,
    required this.detail,
    this.conflict = 0,
    this.enabled = true,
    this.note,
  });

  final String key;
  final String label;

  /// 右侧数据值(如「12 条」)。
  final String detail;

  /// 与本地按 id 冲突的条数(>0 时行内标红提示会被覆盖);算不出就留 0。
  final int conflict;

  /// false = 这份文件里没有该类内容,置灰不可选。
  final bool enabled;

  /// 该项独有的说明(如「重复图自动跳过」),置于标签下方小字。
  final String? note;
}

/// 「自选导入内容」确认层:逐项勾选 + 冲突预览,确认返回选中的 key 集合,
/// 取消返回 null。[mergeHint] = false 时不显示底部的「按 id 合并」说明。
///
/// 高度自控(内部滚动 + 85% 封顶):默认弹层 9/16 屏高会**静默裁掉**超出部分,
/// 条目一多或系统字号一大就看不到底下的按钮。
Future<Set<String>?> showImportPicker(
  BuildContext context, {
  required String title,
  String? notice,
  required List<ImportOption> options,
  String confirmLabel = '导入',
  bool mergeHint = true,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    builder: (ctx) => _ImportPicker(
      title: title,
      notice: notice,
      options: options,
      confirmLabel: confirmLabel,
      mergeHint: mergeHint,
    ),
  );
}

class _ImportPicker extends StatefulWidget {
  const _ImportPicker({
    required this.title,
    required this.options,
    required this.confirmLabel,
    required this.mergeHint,
    this.notice,
  });

  final String title;
  final String? notice;
  final List<ImportOption> options;
  final String confirmLabel;
  final bool mergeHint;

  @override
  State<_ImportPicker> createState() => _ImportPickerState();
}

class _ImportPickerState extends State<_ImportPicker> {
  late final Set<String> _sel = {
    for (final o in widget.options)
      if (o.enabled) o.key,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final totalConflict = [
      for (final o in widget.options)
        if (_sel.contains(o.key)) o.conflict,
    ].fold<int>(0, (a, b) => a + b);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.notice case final String n)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        n,
                        style: context.texts.bodySmall!.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                for (final o in widget.options)
                  CheckboxListTile(
                    dense: true,
                    value: _sel.contains(o.key),
                    onChanged: o.enabled
                        ? (v) => setState(
                            () => v == true
                                ? _sel.add(o.key)
                                : _sel.remove(o.key),
                          )
                        : null,
                    title: Text(
                      o.label,
                      style: context.texts.bodyMedium!.copyWith(
                        color: o.enabled ? null : scheme.outline,
                      ),
                    ),
                    subtitle: switch ((o.conflict, o.note)) {
                      (0, null) => null,
                      _ => Text(
                        [
                          if (o.conflict > 0) '其中 ${o.conflict} 条覆盖本地同 id',
                          ?o.note,
                        ].join(' · '),
                        maxLines: 2,
                        style: context.texts.bodySmall!.copyWith(
                          color: o.conflict > 0 ? scheme.error : scheme.outline,
                        ),
                      ),
                    },
                    secondary: Text(
                      o.detail,
                      style: mono(
                        context,
                        size: 12.5,
                        color: o.enabled
                            ? scheme.onSurfaceVariant
                            : scheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.mergeHint) ...[
                  Text(
                    totalConflict > 0
                        ? '按 id 合并:同 id 覆盖($totalConflict 条),其余新增;本地独有的条目保留。'
                        : '按 id 合并:本地已有的条目一个都不会丢。',
                    style: context.texts.bodySmall!.copyWith(
                      color: totalConflict > 0 ? scheme.error : scheme.outline,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _sel.isEmpty
                            ? null
                            : () => Navigator.pop(context, _sel),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: Text(widget.confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

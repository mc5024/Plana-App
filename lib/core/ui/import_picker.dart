import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// 一条可自选的导入内容。
class ImportOption {
  const ImportOption({
    required this.key,
    required this.label,
    required this.detail,
    this.size,
    this.conflict = 0,
    this.enabled = true,
    this.note,
    this.warning,
  });

  final String key;
  final String label;

  /// 右侧数据值,短(如「12 条」)。
  final String detail;

  /// 大小之类的第二个数(如「预览 1.25 GB」),放在标签下方那行的最前面。
  final String? size;

  /// 与本地按 id 冲突的条数(>0 时标签下方标红提示会被覆盖);算不出就留 0。
  final int conflict;

  /// false = 没有该类内容或不能选,置灰。
  final bool enabled;

  /// 该项独有的说明(如「重复图自动跳过」),标签下方小字。
  final String? note;

  /// 要用户留意的(如超出额度),标签下方红字。
  final String? warning;
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
  String? confirmLabel,
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
      confirmLabel: confirmLabel ?? context.l10n.importLabel,
      mergeHint: mergeHint,
    ),
  );
}

/// 一项:勾选框 | 标签 + 下方一行小字(大小、说明;冲突与警告标红)| 右侧条数。
/// 小字放不下就换行,不挤右侧的数。
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ImportOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final o = option;
    final dim = !o.enabled;
    final small = context.texts.bodySmall!.copyWith(height: 1.35);
    final facts = [?o.size, ?o.note].join(' · ');
    final warns = [
      if (o.conflict > 0) context.l10n.overwriteConflicts(o.conflict),
      ?o.warning,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: onTap == null ? null : (_) => onTap!(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dim ? scheme.outline : null,
                    ),
                  ),
                  if (facts.isNotEmpty || warns.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (facts.isNotEmpty)
                              TextSpan(
                                text: facts,
                                style: TextStyle(color: scheme.outline),
                              ),
                            if (facts.isNotEmpty && warns.isNotEmpty)
                              TextSpan(
                                text: ' · ',
                                style: TextStyle(color: scheme.outline),
                              ),
                            if (warns.isNotEmpty)
                              TextSpan(
                                text: warns,
                                style: TextStyle(color: scheme.error),
                              ),
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              o.detail,
              style: mono(
                context,
                size: 12.5,
                color: dim ? scheme.outline : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                  _OptionRow(
                    option: o,
                    selected: _sel.contains(o.key),
                    onTap: o.enabled
                        ? () => setState(
                            () => _sel.contains(o.key)
                                ? _sel.remove(o.key)
                                : _sel.add(o.key),
                          )
                        : null,
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
                        ? context.l10n.mergeWithConflicts(totalConflict)
                        : context.l10n.mergeNoLoss,
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
                        child: Text(context.l10n.cancel),
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

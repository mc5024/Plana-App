/// 拒绝关键词:不出图的回复命中其中一个就算拒绝。版式照接口页的模型栏:标签 + 输入框添加。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../generate/widgets/common.dart' show confirmDialog;
import 'assistant_settings.dart';
import 'runtime/refusal.dart' show kRefusalKeywords;

/// 一次粘贴多个时的分隔:换行、中英文逗号、顿号。
final _separators = RegExp(r'[\n,，、]');

class RefusalKeywordsPage extends ConsumerStatefulWidget {
  const RefusalKeywordsPage({super.key});

  @override
  ConsumerState<RefusalKeywordsPage> createState() =>
      _RefusalKeywordsPageState();
}

class _RefusalKeywordsPageState extends ConsumerState<RefusalKeywordsPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save(List<String> keywords) => ref
      .read(assistantSettingsProvider.notifier)
      .patch((o) => o.copyWith(refusalKeywords: keywords));

  void _add(List<String> current) {
    final next = [...current];
    for (final k in _input.text.split(_separators)) {
      final t = k.trim();
      if (t.isNotEmpty && !next.contains(t)) next.add(t);
    }
    _input.clear();
    if (next.length != current.length) _save(next);
    setState(() {});
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.restoreDefaultKeywordsQ,
      message: context.l10n.restoreDefaultKeywordsBody,
      confirmLabel: context.l10n.reset,
    );
    if (ok) _save(kRefusalKeywords);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(assistantSettingsProvider).value;
    final scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.refusalKeywords),
        actions: [
          if (s != null && !s.defaultRefusalKeywords)
            IconButton(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
              tooltip: context.l10n.reset,
            ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  controller: _input,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(s.refusalKeywords),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: context.skin.float
                        ? scheme.surfaceContainerHigh
                        : scheme.surfaceContainerHighest,
                    hintText: context.l10n.addRefusalKeyword,
                    hintStyle: TextStyle(color: scheme.outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    suffixIcon: _input.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => _add(s.refusalKeywords),
                            icon: const Icon(Icons.add, size: 20),
                            tooltip: context.l10n.add,
                            color: scheme.primary,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in s.refusalKeywords)
                      InputChip(
                        label: Text(k),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onDeleted: () => _save([
                          for (final x in s.refusalKeywords)
                            if (x != k) x,
                        ]),
                        deleteButtonTooltipMessage: context.l10n.remove,
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

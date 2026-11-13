import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart' show confirmDialog, hintSnack;
import '../public_tags.dart';
import '../tag_library.dart';
import '../tag_models.dart';
import 'prompt_chips.dart';
import '../../../l10n/l10n.dart';

/// 灵感页的弹层:条目详情、标签池管理(新建/编辑走全屏 TagEditorPage)。

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => child,
    );

Widget _sheetTitle(BuildContext context, IconData icon, String title) {
  return Row(
    children: [
      Icon(icon, size: 20, color: context.scheme.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: context.texts.titleMedium!.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

// ---- 详情 ----

Future<void> showTagDetailSheet(BuildContext context, TagEntry e) =>
    _sheet(context, _DetailSheet(e));

class _DetailSheet extends ConsumerWidget {
  const _DetailSheet(this.e);

  final TagEntry e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    // 作者:查得到昵称就显示昵称,查不到显示那串 QQ 号(目录没加载出来时同理)。
    final author = e.createdBy?.trim();
    final authorLabel = author == null || author.isEmpty
        ? null
        : (ref.watch(tagAuthorNamesProvider).value ?? const {})[author] ??
              author;
    // 定高封顶:正文(分类标签 + 正负向芯片)在内部滚,标题与「复制」常驻
    // 两端 —— 长词条不再把按钮顶出屏幕、整张弹层跟着无限拉长(法典详情同款)。
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.name,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (e.aliases.isNotEmpty)
                    Expanded(
                      child: Text(
                        e.aliases.join(' / '),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (authorLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                child: Text(
                  context.l10n.authorNamed(authorLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final t in e.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '#$t',
                                style: context.texts.labelSmall,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _block(context, context.l10n.positiveLabel, e.positive),
                    if (e.negative.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _block(context, context.l10n.negativeLabel, e.negative),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: e.positive));
                  if (context.mounted) {
                    Navigator.pop(context);
                    hintSnack(
                      context,
                      context.l10n.promptCopied,
                      icon: Icons.copy,
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(context.l10n.copyPrompt),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context, String label, String text) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelMedium!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        // 芯片流不可选字,整段复制走底部「复制提示词」
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: PromptChips.single(text),
        ),
      ],
    );
  }
}

// ---- 标签池管理 ----

Future<void> showTagPoolSheet(
  BuildContext context,
  WidgetRef ref,
  TagCategory cat,
) => _sheet(context, _PoolSheet(cat));

class _PoolSheet extends ConsumerStatefulWidget {
  const _PoolSheet(this.cat);

  final TagCategory cat;

  @override
  ConsumerState<_PoolSheet> createState() => _PoolSheetState();
}

class _PoolSheetState extends ConsumerState<_PoolSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    final ok = await ref
        .read(tagLibraryProvider.notifier)
        .addPoolTag(widget.cat, t);
    if (!mounted) return;
    if (ok) {
      _input.clear();
    } else {
      hintSnack(
        context,
        context.l10n.tagExistsShort,
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final def = tagCategoryDef(widget.cat);
    final lib = ref.watch(tagLibraryProvider).value;
    final notifier = ref.read(tagLibraryProvider.notifier);
    final tags = lib?.knownTags(widget.cat) ?? const <String>[];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: _sheetTitle(
              context,
              Icons.tune,
              context.l10n.catTagPool(def.label),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.l10n.newTagEllipsis,
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _add,
                  child: Text(context.l10n.add),
                ),
              ],
            ),
          ),
          Flexible(
            child: tags.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      context.l10n.noTags,
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                // 顺序即筛选行的顺序:按住抓手即拖,整行长按也可拖
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => Material(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 3,
                      child: child,
                    ),
                    onReorderItem: (from, to) =>
                        notifier.movePoolTag(widget.cat, from, to),
                    itemCount: tags.length,
                    itemBuilder: (context, i) {
                      final t = tags[i];
                      final n = notifier.poolTagUsage(widget.cat, t);
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(t),
                        index: i,
                        child: ListTile(
                          dense: true,
                          leading: ReorderableDragStartListener(
                            index: i,
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
                          title: Text(t),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$n',
                                style: mono(
                                  context,
                                  size: 12,
                                  color: n > 0
                                      ? scheme.primary
                                      : scheme.outline,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: scheme.error,
                                ),
                                onPressed: () async {
                                  final ok =
                                      n == 0 ||
                                      await confirmDialog(
                                        context,
                                        title: context.l10n.deleteTagQ(t),
                                        message: context.l10n
                                            .deleteTagEntriesBody(n),
                                        confirmLabel: context.l10n.delete,
                                      );
                                  if (ok) {
                                    await notifier.removePoolTag(widget.cat, t);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---- 批量贴标签:选一个标签(可现场新建) ----

Future<String?> pickTagSheet(
  BuildContext context,
  WidgetRef ref,
  TagCategory cat,
) => _sheet<String>(context, _TagPickSheet(cat));

class _TagPickSheet extends ConsumerStatefulWidget {
  const _TagPickSheet(this.cat);

  final TagCategory cat;

  @override
  ConsumerState<_TagPickSheet> createState() => _TagPickSheetState();
}

class _TagPickSheetState extends ConsumerState<_TagPickSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final tags =
        ref.watch(tagLibraryProvider).value?.knownTags(widget.cat) ??
        const <String>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: _sheetTitle(
              context,
              Icons.sell_outlined,
              context.l10n.addTag,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.l10n.newTagEllipsis,
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isNotEmpty) Navigator.pop(context, t);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () {
                    final t = _input.text.trim();
                    if (t.isNotEmpty) Navigator.pop(context, t);
                  },
                  child: Text(context.l10n.use),
                ),
              ],
            ),
          ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tags)
                    ActionChip(
                      label: Text(t),
                      shape: const StadiumBorder(),
                      onPressed: () => Navigator.pop(context, t),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

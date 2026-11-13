import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../../assistant/prompt_diff.dart' show diffPrompt;
import '../../gallery/gallery_state.dart' show galleryThumbProvider;
import '../canvas_history.dart';
import '../canvas_state.dart';
import '../models.dart' show GenParams, modelName;
import '../prompt_sections.dart' show joinSections;
import 'common.dart';
import '../../../l10n/l10n.dart';
import '../display_names.dart';

/// 一张画布的历史:最近几十次出图时的内容,点一条可以恢复或复制成新画布。
Future<void> showCanvasHistory(BuildContext context, CanvasDraft canvas) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HistorySheet(canvasId: canvas.id),
    );

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.canvasId});

  final String canvasId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvas = ref.watch(
      canvasWorkspaceProvider.select((w) => w.find(canvasId)),
    );
    final entries = ref.watch(canvasHistoryProvider(canvasId));
    final list = entries.value ?? const <CanvasHistoryEntry>[];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
        minHeight: 200,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.canvasHistoryTitle(
                    canvas == null
                        ? context.l10n.canvasSingular
                        : canvasDisplayName(context.l10n, canvas.name),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          if (entries.isLoading && list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Text(
                context.l10n.noHistoryYet,
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium!.copyWith(
                  color: context.scheme.outline,
                ),
              ),
            )
          else
            Flexible(
              child: SafeArea(
                top: false,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  itemCount: list.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EntryTile(
                      entry: list[i],
                      older: i + 1 < list.length ? list[i + 1] : null,
                      onTap: canvas == null
                          ? null
                          : () => _showActions(context, ref, canvas, list[i]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    CanvasDraft canvas,
    CanvasHistoryEntry entry,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(context.l10n.restoreThisVersion),
              onTap: () => Navigator.pop(sheet, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(context.l10n.duplicateAsNewCanvas),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final prompts = await ref
        .read(appStoresProvider)
        .workspace
        .decodeCanvas(entry.json);
    if (!context.mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Haptics.selection();
    final canvases = ref.read(canvasWorkspaceProvider.notifier);
    if (action == 'copy') {
      canvases.createFrom(prompts, from: canvas.name);
      hintSnack(
        context,
        context.l10n.duplicatedAsNewCanvas,
        icon: Icons.copy_outlined,
      );
    } else {
      final before = canvases.replace(canvas.id, prompts);
      if (before == null) return;
      canvases.select(canvas.id);
      hintSnack(
        context,
        context.l10n.restoredTo(historyTimeLabel(entry.at)),
        icon: Icons.restore,
        actionLabel: context.l10n.undo,
        onAction: () => canvases.replace(canvas.id, before),
      );
    }
    // 关掉历史和画布两层弹层,回到创作页
    final nav = Navigator.of(context)..pop();
    unawaited(nav.maybePop());
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, this.older, this.onTap});

  final CanvasHistoryEntry entry;

  /// 上一条(更早的那次);null = 这是最早的一条。
  final CanvasHistoryEntry? older;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final p = entry.preview;
    final prompt = joinSections(p.sections, p.prompt, positive: true);
    final changes = older == null ? null : historyChanges(older!, entry);
    final small = context.texts.bodySmall!.copyWith(fontSize: 13);
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(entry.resultIds.firstOrNull),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        historyTimeLabel(entry.at),
                        if (entry.resultIds.length > 1)
                          context.l10n.imagesN(entry.resultIds.length),
                      ].join(' · '),
                      style: context.texts.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prompt.isEmpty
                          ? context.l10n.noPrompt
                          : prompt.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (changes != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        changes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small.copyWith(color: scheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb(this.resultId);

  final String? resultId;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = resultId;
    final bytes = id == null ? null : ref.watch(galleryThumbProvider(id)).value;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          bytes,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    // 图已经从图库删了(或还在读)
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.image_outlined, color: context.scheme.outline),
    );
  }
}

/// 「14:02」「昨天 14:02」「10月3日 14:02」。
String historyTimeLabel(int ms, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return hm;
  final l = l10nNow;
  if (diff == 1) return l.dateYesterday(hm);
  if (t.year != n.year) {
    return l.dateYearMonthDay(t.year, '${t.month}', t.day, hm);
  }
  return l.dateMonthDay('${t.month}', t.day, hm);
}

/// [after] 相对 [before] 改了什么,一行写完:「+3 −1 · 角色 2→3 · 28→23 步」。
/// 只差在没列出的项上时写「参数有改动」。
String historyChanges(CanvasHistoryEntry before, CanvasHistoryEntry after) {
  final a = before.preview, b = after.preview;
  final out = <String>[];
  final pos = diffPrompt(
    joinSections(a.sections, a.prompt, positive: true),
    joinSections(b.sections, b.prompt, positive: true),
  );
  if (!pos.isEmpty) {
    out.add(
      [
        if (pos.added.isNotEmpty) '+${pos.added.length}',
        if (pos.removed.isNotEmpty) '−${pos.removed.length}',
      ].join(' '),
    );
  }
  final neg = diffPrompt(
    joinSections(a.sections, a.negativePrompt, positive: false),
    joinSections(b.sections, b.negativePrompt, positive: false),
  );
  final l = l10nNow;
  if (!neg.isEmpty) out.add(l.negChanged);
  if (a.characters.length != b.characters.length) {
    out.add(l.charsChange(a.characters.length, b.characters.length));
  }
  void count(String label, int x, int y) {
    if (x != y) out.add('$label $x→$y');
  }

  count('Vibe', before.countOf('vibes'), after.countOf('vibes'));
  count(
    l.preciseReference,
    before.countOf('charRefs'),
    after.countOf('charRefs'),
  );
  count(
    '风格参考',
    before.countOf('kreaStyleRefs'),
    after.countOf('kreaStyleRefs'),
  );
  count('LoRA', a.loras.length, b.loras.length);
  if (before.has('img2img') != after.has('img2img')) {
    out.add(after.has('img2img') ? l.addedBaseImage : l.removedBaseImage);
  }
  if (before.has('inpaint') != after.has('inpaint')) {
    out.add(after.has('inpaint') ? l.addedInpaint : l.removedInpaint);
  }
  final sa = a.sampling, sb = b.sampling;
  if (sa != null && sb != null) {
    if (sa.model != sb.model) out.add(modelName(sb.model));
    if (sa.width != sb.width || sa.height != sb.height) {
      out.add('${sb.width}×${sb.height}');
    }
    final stepsA = sa.writeInto(const GenParams()).activeSteps;
    final stepsB = sb.writeInto(const GenParams()).activeSteps;
    if (sa.model == sb.model && stepsA != stepsB) {
      out.add(l.stepsChange(stepsA, stepsB));
    }
  }
  return out.isEmpty ? l.paramsChanged : out.join(' · ');
}

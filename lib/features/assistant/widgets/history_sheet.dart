/// 历史会话。标题取第一句用户输入,副行取最后一句 AI 回复,右下角只放一个数字:
/// 这段对话最终攒出多少 tag —— 那是用户回头找它的真正理由。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart' show confirmDialog, dropFocusSoon;
import '../assistant_models.dart';
import '../assistant_state.dart';

Future<void> showHistorySheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _HistorySheet(),
  );
  dropFocusSoon();
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final sessions = ref.watch(assistantProvider.select((s) => s.sessions));
    final n = ref.read(assistantProvider.notifier);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '历史会话',
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (sessions.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: '清空历史会话?',
                          message: '${sessions.length} 段对话都会删掉,已经写进创作页的改动不受影响。',
                          confirmLabel: '清空',
                        );
                        if (ok) n.clearSessions();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('清空'),
                    ),
                ],
              ),
            ),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 46),
                child: Text(
                  '还没有归档的对话。\n点右上角「新对话」就会把当前这段存进来。',
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.7,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) => _Row(
                    s: sessions[i],
                    onOpen: () {
                      n.openSession(sessions[i].id);
                      Navigator.pop(context);
                    },
                    onDelete: () => n.deleteSession(sessions[i].id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.s, required this.onOpen, required this.onDelete});

  final ArchivedSession s;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 左滑删单条(原生手势);顶栏「清空」是兜底入口,不让手势成为唯一路径。
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 9),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: context.skin.float
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium!.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (s.hasError) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.error_outline,
                          size: 15,
                          color: scheme.error,
                        ),
                      ],
                    ],
                  ),
                  if (s.preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  DefaultTextStyle(
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.outline,
                    ),
                    child: Row(
                      children: [
                        Text(_when(s.at)),
                        const SizedBox(width: 10),
                        Text('${s.turns} 轮'),
                        if (s.tagCount > 0) ...[
                          const SizedBox(width: 10),
                          Text('${s.tagCount} tag'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 相对时间:今天报时分,昨天报「昨天 HH:mm」,更早报「M/d」。
String _when(int ms) {
  if (ms <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final diff = today.difference(that).inDays;
  if (diff == 0) {
    return now.difference(t).inMinutes < 3 ? '刚刚' : hm;
  }
  if (diff == 1) return '昨天 $hm';
  return '${t.month}/${t.day}';
}

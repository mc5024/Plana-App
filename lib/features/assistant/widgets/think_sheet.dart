/// 调整模型思考深度。滑杆六档:关闭 / 自动 / 低 / 中等 / 高 / 超高。
///
/// 做成滑杆而不是菜单:六档是**一条有序的轴**,菜单会让它看起来像六个并列选项;
/// 而且滑杆能一眼看出当前落在哪儿、离两头还有多远。
///
/// 副标题那句必须留着:三家的旋钮各不相同,不会思考的模型收到这些字段通常直接
/// 忽略,但也有中转会因此报错 —— 事先说清楚比事后查错便宜。
/// 当前接口没有选中的那一档时,档位名下面说一句实际按哪档发(见 [LlmProvider.thinkNote])。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/setting_row.dart';
import '../../../core/util/haptics.dart';
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../agent_model.dart' show assistantEndpointProvider;
import '../assistant_settings.dart';
import '../llm/http_provider.dart' show llmProviderFor;
import '../../../l10n/l10n.dart';

Future<void> showThinkSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => const _ThinkSheet(),
  );
  // 只是来调个档,别顺手把软键盘顶出来
  dropFocusSoon();
}

class _ThinkSheet extends ConsumerWidget {
  const _ThinkSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final level =
        ref.watch(assistantSettingsProvider).value?.thinkLevel ??
        ThinkLevel.auto;
    final levels = ThinkLevel.values;
    final i = levels.indexOf(level);
    final endpoint = ref.watch(assistantEndpointProvider);
    final note = endpoint == null
        ? null
        : llmProviderFor(endpoint).thinkNote(level);

    void set(ThinkLevel l) {
      if (l == level) return;
      Haptics.selection();
      ref
          .read(assistantSettingsProvider.notifier)
          .patch((o) => o.copyWith(thinkLevel: l));
    }

    return SettingSheet(
      title: context.l10n.adjustThinkDepth,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Text(
            context.l10n.thinkDepthNote,
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
        Icon(
          level == ThinkLevel.off ? Icons.lightbulb_outline : Icons.lightbulb,
          size: 34,
          color: level == ThinkLevel.off ? scheme.outline : scheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          thinkLevelLabel(level),
          textAlign: TextAlign.center,
          style: context.texts.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        // 占住一行高度:有没有这句话时滑杆都不上下跳
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            note ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Slider(
            value: i.toDouble(),
            max: (levels.length - 1).toDouble(),
            divisions: levels.length - 1,
            onChanged: (v) => set(levels[v.round()]),
          ),
        ),
        // 档位名单独一行,和滑杆的刻度对齐 —— Slider 自己的 label 只在拖动时冒出来,
        // 松手就没了,而这六个名字正是「我现在选的是什么」的全部依据。
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
          child: Row(
            children: [
              for (final (n, l) in levels.indexed)
                Expanded(
                  child: InkWell(
                    onTap: () => set(l),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        thinkLevelLabel(l),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall!.copyWith(
                          color: n == i ? scheme.primary : scheme.outline,
                          fontWeight: n == i
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

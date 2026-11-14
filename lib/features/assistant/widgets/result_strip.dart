/// AI 一轮给出的提示词,压在回复气泡底部的一条:「生成了 N tag」+ 相对上一轮的增删 +
/// 「展开」。**只在这一轮真给了画面时才出**(见 [DrawProposal]),纯聊天轮没有。
///
/// **每一份提议都是这一条,最后一份也一样。** 原先最后一份单独摊成一张结果卡,新一轮
/// 一来又收成摘要,同一个东西前后两副样子。处置按钮([ProposalActions])对最后一份
/// 包在同一个气泡里、排在这一条下面(见 `assistant_page` 的 `_ai`),更早的在弹层里。
///
/// 左边是 tag 数,不是导入状态:导没导入看最后一份的「导入 / 已导入」,往回翻时想知道的
/// 是那一版写了多少。数法和增删读数同一种单位(一句话算一个,见 [countTags]);
/// token 数留在弹层标题栏上。
///
/// 读数**恒为「这一轮的提议 vs 上一轮的提议」**,和创作页无关,也不随导入与否改口径。
/// 原先未导入时拿当前画布当基线(想的是「预览导入后会变成什么样」),毛病是:新对话里
/// AI 根本没见过画布,却被算出一堆「移除」;而且你在创作页随手改几个词,读数就跟着跳。
/// 第一份提议没有上一轮,基线是空的,读数就是「它写了多少」。增删怎么算见
/// `prompt_diff.dart`。
///
/// 条上**不列明细**:两三个 tag 名字凑不成完整认知,读数已经把「改了多少」说全了。
/// 明细走弹层,入口是右边那颗「展开」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/nai_tokenizer.dart';
import '../domain/conversation.dart';
import '../prompt_diff.dart';
import 'proposal_actions.dart';
import 'proposal_sheet.dart';
import 'tag_diff.dart';
import '../../../l10n/l10n.dart';

class ResultStrip extends ConsumerWidget {
  const ResultStrip({super.key, required this.msg, this.prev});

  final AssistantMsg msg;

  /// 上一轮的提议,差异的基线(由调用方用 [prevProposal] 取)。
  /// 没有上一轮就是 null,那时基线是空的。
  final DrawProposal? prev;

  /// 还没落到创作页(从没导入过,或者导入后又撤销了)。只影响弹层标题。
  bool get _live => msg.change == null || msg.change!.undone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final p = msg.draw!;
    // 这一份差异条上和弹层里共用,两处各算一遍迟早对不上。
    final diff = diffPrompt(prev?.positive ?? '', p.positive);
    final chars = <ProposalChar>[
      for (final c in p.characters)
        (
          name: c.name,
          positive: c.positive,
          // 空串 = AI 没指定,按现状继承 —— 不是「放正中」,别显示成一个格号。
          position: c.position.trim().isEmpty ? null : c.position,
        ),
    ];
    final parts = [for (final c in chars) c.positive];
    final tags = countTags(p.positive, parts);
    // token 只有弹层用得上:点开时再算,不必每条结果条每次重建都分一遍词。
    // 这里照样 watch 着,词表才会提前开始加载,点开时拿到的是准数不是估算。
    final tok = ref.watch(naiTokenizerProvider).value;
    void openSheet() => showProposalSheet(
      context,
      title: _title(diff, chars),
      diff: diff,
      positive: p.positive,
      characters: chars,
      tokens: totalPromptTokens(tok, main: p.positive, parts: parts),
      emptyNote: context.l10n.sameAsLastTurn,
      msg: msg,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: scheme.outline),
                const SizedBox(width: 6),
                Text(
                  context.l10n.generatedNTags(tags),
                  style: context.texts.labelMedium!.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 9),
                DiffCount(
                  added: diff.added.length,
                  removed: diff.removed.length,
                ),
                const Spacer(),
                _openButton(context, scheme, openSheet),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 角色列表整个换过了吗(数量或任一条的名字、正向词不同)。
  bool _charsChanged(List<ProposalChar> now) {
    final base = prev?.characters ?? const [];
    if (base.length != now.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (base[i].name != now[i].name || base[i].positive != now[i].positive) {
        return true;
      }
    }
    return false;
  }

  /// 弹层的标题。它盖住半屏、脱离了对话上下文,得有一句话说清打开的是什么。
  String _title(PromptDiff diff, List<ProposalChar> chars) {
    final charsChanged = chars.isNotEmpty && _charsChanged(chars);
    if (!_live) {
      return charsChanged
          ? l10nNow.writtenNChars(chars.length)
          : l10nNow.writtenToCreate;
    }
    if (charsChanged) return l10nNow.aiGaveNChars(chars.length);
    // 从空白开始写的那一轮:说「新增 42」不如说清楚它是一整份。
    if (diff.removed.isEmpty &&
        diff.added.isNotEmpty &&
        (prev?.positive ?? '').trim().isEmpty) {
      return l10nNow.aiWroteFull;
    }
    if (diff.isEmpty) return l10nNow.sameAsYours;
    return l10nNow.aiChanges;
  }

  /// 展开钮。做成实心小胶囊而不是图标 —— 它是这一条**唯一**的展开入口,
  /// 一枚 14px 的灰图标太容易被当成装饰。
  Widget _openButton(
    BuildContext context,
    ColorScheme scheme,
    VoidCallback onOpen,
  ) => Material(
    color: scheme.secondaryContainer,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 9, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_full,
              size: 13,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 5),
            Text(
              context.l10n.expand,
              style: context.texts.labelSmall!.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

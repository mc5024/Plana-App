/// 提议详情弹层。结果条上放不下的都在这儿:差异明细(带译文)+ 完整提示词。
///
/// **为什么是弹层,不是就地展开**:气泡底下还挂着出图和按钮,一展开就被顶出屏幕。
/// 搬进弹层之后阅读版式不受高度约束 —— tag 直接用全 app 的标准芯片([PromptChips],
/// 英文译文双行、带权重深浅)。
///
/// **句子不画成芯片**,当文字排,改过的句子只标出改掉的那几个词(见 `prompt_diff.dart`)。
///
/// **只读,而且要一直只读**。卡是一份「等你处置」的提议,处置只有导入和生成
/// 两个出口。在这儿改 tag 会造出第三份状态:它既没进画布,AI 也不知道 —— 下一轮
/// 无论是它照着自己上一版改,还是用户勾了「引用创作页」,拿到的都不是你划过的那份,
/// 划掉的东西照旧回来,而用户找不到是谁干的。要调整走两条路:导入之后去创作页改
/// (那儿的编辑器有补全、权重、译文注音),或者直接跟 AI 说一句「去掉 solo」
/// —— 后者才能让 AI 和画布保持同一个认知。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../generate/char_position.dart' show positionChipLabel;
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../../inspiration/widgets/prompt_chips.dart';
import '../domain/conversation.dart' show AssistantMsg;
import '../prompt_diff.dart';
import 'proposal_actions.dart';
import 'tag_diff.dart';
import '../../../l10n/l10n.dart';

/// 弹层里列出来的角色。结果条上不列角色(收成了标题里的一句「AI 给了 2 个
/// 角色」),所以站位也得在这儿显示 —— 不然「AI 把她挪到了 B3」就没地方看了。
typedef ProposalChar = ({String name, String positive, String? position});

Future<void> showProposalSheet(
  BuildContext context, {
  required String title,
  required PromptDiff diff,
  required String positive,
  required List<ProposalChar> characters,
  required int tokens,
  required String emptyNote,
  required AssistantMsg msg,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProposalSheet(
      title: title,
      diff: diff,
      words: markChangedWords(diff),
      positive: positive,
      characters: characters,
      tokens: tokens,
      emptyNote: emptyNote,
      msg: msg,
    ),
  );
  dropFocusSoon();
}

class _ProposalSheet extends StatelessWidget {
  const _ProposalSheet({
    required this.title,
    required this.diff,
    required this.words,
    required this.positive,
    required this.characters,
    required this.tokens,
    required this.emptyNote,
    required this.msg,
  });

  final String title;

  /// 差异,单元的区间指向 [positive](新增的)和上一轮的正向词(删掉的)。
  final PromptDiff diff;

  /// 改过的句子里具体变了的词。
  final ChangedWords words;
  final String positive;
  final List<ProposalChar> characters;
  final int tokens;
  final String emptyNote;

  /// 处置这份提议要用到的那条消息。更早的提议按钮只在这儿有一份。
  final AssistantMsg msg;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final added = diff.added, removed = diff.removed;
    return SafeArea(
      child: ConstrainedBox(
        // 高度给到 85%:行版一屏放十来条,再高就贴着状态栏了。
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(context, scheme),
            Divider(height: 1, color: scheme.outlineVariant),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (added.isEmpty && removed.isEmpty)
                    Text(
                      emptyNote,
                      style: context.texts.bodyMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (added.isNotEmpty)
                    ..._diffGroup(
                      context,
                      context.l10n.added,
                      added,
                      words.added,
                      diffAddColor,
                    ),
                  if (added.isNotEmpty && removed.isNotEmpty)
                    const SizedBox(height: 18),
                  if (removed.isNotEmpty)
                    ..._diffGroup(
                      context,
                      context.l10n.remove,
                      removed,
                      words.removed,
                      diffDelColor,
                    ),
                  const SizedBox(height: 22),
                  _label(context, scheme, context.l10n.fullPrompt),
                  const SizedBox(height: 8),
                  _fullPrompt(context, scheme),
                  for (final c in characters) ...[
                    const SizedBox(height: 18),
                    _label(
                      context,
                      scheme,
                      c.position == null
                          ? c.name
                          : '${c.name} · ${positionChipLabel(c.position)}',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      c.positive.trim().isEmpty
                          ? context.l10n.emptyParen
                          : c.positive,
                      style: context.texts.bodyMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.7,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            // 导入/撤销都会改掉上面正在显示的那份差异,所以按完就把弹层关掉 ——
            // 留在原地看着一份已经不成立的对比,只会让人怀疑是不是没生效。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ProposalActions(
                msg: msg,
                onDone: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head(BuildContext context, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 8, 10),
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
        DiffCount(added: diff.added.length, removed: diff.removed.length),
        const SizedBox(width: 10),
        Text(
          '$tokens tok',
          style: context.texts.labelSmall!.copyWith(
            color: scheme.outline,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
          style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );

  /// 一组差异:带色的组标题,tag 排成全 app 标准芯片,句子一句一段排在芯片下面。
  ///
  /// 芯片本身不染红绿 —— 弹层里高度管够,组是分开摆的,标题那一行足以说明
  /// 是哪一组;再给芯片铺一层底色反而会跟 `PromptChips` 自己的权重深浅打架。
  /// 句子里只给改掉的词铺底色([marks] 与 [units] 逐条对应),整句都是新的就不铺。
  List<Widget> _diffGroup(
    BuildContext context,
    String label,
    List<PromptUnit> units,
    List<List<(int, int)>?> marks,
    Color c,
  ) {
    final tags = [
      for (final u in units)
        if (!u.prose) u.text,
    ];
    return [
      Text(
        '$label ${units.length}',
        style: context.texts.labelMedium!.copyWith(
          color: c,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      if (tags.isNotEmpty) PromptChips.single(tags.join(', ')),
      for (final (i, u) in units.indexed)
        if (u.prose)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: c.withValues(alpha: .5), width: 2),
                ),
              ),
              child: SelectableText.rich(
                _marked(
                  u.text,
                  [
                    for (final (a, b) in marks[i] ?? const <(int, int)>[])
                      (a - u.start, b - u.start),
                  ],
                  TextStyle(
                    backgroundColor: c.withValues(alpha: .18),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: context.texts.bodyMedium!.copyWith(height: 1.6),
              ),
            ),
          ),
    ];
  }

  Widget _label(BuildContext context, ColorScheme scheme, String text) => Text(
    text,
    style: context.texts.labelMedium!.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ),
  );

  /// 完整正向词,原样排(换行、标点都不动),相对上一轮新增的带底色 —— 上面刚看完
  /// 「多了什么」,这里要能一眼认出它们落在整串的哪个位置。改过的句子只标改掉的词。
  Widget _fullPrompt(BuildContext context, ColorScheme scheme) {
    final ranges = [
      for (final (i, u) in diff.added.indexed)
        ...(words.added[i] ?? [(u.start, u.end)]),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return SelectableText.rich(
      _marked(
        positive,
        ranges,
        TextStyle(
          backgroundColor: scheme.primaryContainer,
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: context.texts.bodyMedium!.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.85,
      ),
    );
  }
}

/// [text] 里 [ranges](按起点排好、互不重叠)那几段套上 [mark],其余原样。
TextSpan _marked(String text, List<(int, int)> ranges, TextStyle mark) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final (a, b) in ranges) {
    if (a < at || b > text.length) continue;
    if (a > at) spans.add(TextSpan(text: text.substring(at, a)));
    spans.add(TextSpan(text: text.substring(a, b), style: mark));
    at = b;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: spans);
}

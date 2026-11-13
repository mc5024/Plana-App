import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/nai_tokenizer.dart';
import '../../generate/generate_state.dart';
import '../../generate/models.dart' show tokenLimitOf;
import '../../generate/prompt_presets.dart';
import '../../generate/prompt_sections.dart' show mainEnabled, sectionTexts;
import '../editor_state.dart';
import '../../../l10n/l10n.dart';

/// 编辑器顶栏(精简,单行):返回(=保存并退出)+ 进度条 + token 读数 + 设置。
/// 正/负 tab、撤销、纯文本切换都下放到底栏。滚动正文时由页面整栏收起。
class EditorTopBar extends ConsumerWidget {
  const EditorTopBar({
    super.key,
    required this.onBack,
    required this.onSettings,
    this.charName,
    this.character = false,
    this.sectionId,
  });

  final VoidCallback onBack;
  final VoidCallback onSettings;

  /// 标题:角色名 / 分区名;没分区的主提示词会话为 null,标题位留空。
  final String? charName;

  /// 角色会话:读数只计本角色正文。
  final bool character;

  /// 分区会话:读数照主提示词的口径算总数,这一格用编辑器里的实时文本。
  final String? sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final st = ref.watch(editorProvider);

    // 主提示词(含分区)会话按 web totalTokenCount 口径计:正文 + 启用分区 +
    // 启用角色串 + 激活预设(都实际参与生成),与生成页卡头读数一致;
    // 角色会话只计本角色正文。
    final tok = ref.watch(naiTokenizerProvider).value;
    final preset = character ? null : ref.watch(activePromptPresetProvider);
    final presetSide = preset == null
        ? ''
        : (st.activePositive ? preset.positive : preset.negative);
    final gen = character
        ? null
        : ref.watch(
            generateProvider.select(
              (s) => (
                prompt: s.prompt,
                negative: s.negativePrompt,
                sections: s.sections,
              ),
            ),
          );
    // 主体的正向停用了就不算(负面那侧一直算,同出图)
    final mainOn =
        gen == null || !st.activePositive || mainEnabled(gen.sections);
    final parts = gen == null
        ? const <String>[]
        : [
            // 分区会话:编辑器里是这一格,主体换成存着的那份
            if (sectionId != null && mainOn)
              st.activePositive ? gen.prompt : gen.negative,
            ...sectionTexts(
              gen.sections,
              positive: st.activePositive,
              except: sectionId,
            ),
            // 与生成页同一口径:模块不可见(anima 等)时角色整组不计
            for (final c in ref.watch(countedCharactersProvider))
              st.activePositive ? c.positive : c.negative,
          ];
    // activeOutput 而非 outputOf(activeText):正文里折叠只是占位符 `#名字`,
    // 直接算会把整段折叠体漏掉——读数得按占位符展开后的真实定稿来。
    final tokens = totalPromptTokens(
      tok,
      main: sectionId == null && !mainOn ? '' : st.activeOutput,
      parts: parts,
      preset: presetSide,
    );
    // 上限按当前模型取(NAI 5 抬到 703/1471,其余 512),与生成页卡头同源。
    final limit = tokenLimitOf(
      ref.watch(generateProvider.select((s) => s.params.model)),
    );
    final over = tokens > limit;
    final ratio = (tokens / limit).clamp(0.0, 1.0);
    final barColor = over ? scheme.error : scheme.primary;

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: ratio, end: ratio),
        duration: Motion.medium,
        curve: Motion.standard,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 4,
          backgroundColor: scheme.surfaceContainerHighest,
          color: barColor,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          // 两颗钮只压纵向:48 的点击区会在图标下面白垫 12,叠上正文自己的
          // 顶部内边距,顶栏和第一行标签之间就空出一大截
          IconButton(
            onPressed: onBack,
            visualDensity: const VisualDensity(vertical: -2),
            icon: const Icon(Icons.arrow_back),
            tooltip: context.l10n.saveAndBack,
          ),
          // 进度条不再单占一行:收进返回键与读数之间,紧挨着读数当它的表头。
          // 角色会话多一个标题,按内容取宽、封顶 45%,其余让给进度条 ——
          // Row 里 Flexible 分剩的宽度不会回流给 Expanded,只能自己量。
          Expanded(
            child: charName == null
                ? Padding(padding: const EdgeInsets.only(left: 4), child: bar)
                : LayoutBuilder(
                    builder: (context, c) => Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: c.maxWidth * .45,
                          ),
                          child: Text(
                            charName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.titleSmall!.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: bar),
                      ],
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Text(
            '$tokens',
            style: mono(
              context,
              size: 15,
              weight: FontWeight.w700,
            ).copyWith(color: over ? scheme.error : scheme.onSurface),
          ),
          Text(
            ' / $limit',
            style: mono(
              context,
              size: 12,
              weight: FontWeight.w500,
            ).copyWith(color: scheme.outline),
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: onSettings,
            visualDensity: const VisualDensity(vertical: -2),
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: context.l10n.editorSettings,
          ),
        ],
      ),
    );
  }
}

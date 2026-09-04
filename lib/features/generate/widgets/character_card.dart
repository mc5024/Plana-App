import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/nai_tokenizer.dart';
import '../../editor/editor_page.dart';
import '../char_position.dart';
import '../generate_state.dart';
import '../models.dart';
import 'common.dart';
import 'position_grid_dialog.dart';
import 'section_card.dart';

/// 角色面板(定稿版):每个角色一张内嵌圆角小卡。
/// 行 1:电源开关 · 名称(+状态说明)· 站位徽章 · 删除
/// 行 2:提示词单行预览 + token 计数
class CharacterCard extends ConsumerWidget {
  const CharacterCard({super.key, this.reorderIndex});

  final int? reorderIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(generateProvider);
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;
    final chars = state.characters;
    final cap = maxCharactersOf(state.params.model);
    final canAdd = chars.length < cap;
    // 读数按**启用**数算:上限管的是进载荷的那几个,停用的不占额度。切模型时
    // 超出的尾巴会自动停用(见 GenerateNotifier._capEnabled),之后还标红就只剩
    // 一种来路 —— 用户在小槽位模型下自己又勾回来了,那确实该红。
    final active = chars.where((c) => c.enabled).length;

    return SectionCard(
      icon: Icons.group_outlined,
      title: '角色',
      reorderIndex: reorderIndex,
      badge: CountBadge('$active / $cap', error: active > cap),
      actions: [
        if (chars.isNotEmpty)
          RoundIconBtn(
            Icons.delete_sweep_outlined,
            tooltip: '清空全部角色',
            color: scheme.onSurfaceVariant,
            onTap: () => _confirmClear(context, notifier),
          ),
        RoundIconBtn(
          Icons.add,
          tooltip: '添加角色',
          color: canAdd ? null : scheme.outline,
          onTap: canAdd ? notifier.addCharacter : null,
        ),
      ],
      // 没有角色时整卡不可展开(展开体本就是空的),但保留一个静态 chevron 占位,
      // 让空卡卡头与下方各功能卡视觉对齐;箭头不接手势、不旋转、不点开空白。
      expanded: chars.isNotEmpty && state.openPanels.contains(Panel.characters),
      onHeaderTap: chars.isEmpty
          ? null
          : () => notifier.togglePanel(Panel.characters),
      chevronPlaceholder: chars.isEmpty,
      body: chars.isEmpty
          ? null
          // 长按卡片拖动排序。删除只走行内那枚按钮 —— 横滑抹掉的是整份角色配置
          // (提示词/站位/开关),而这里没有撤销可给。
          : ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              proxyDecorator: dragProxy,
              onReorderStart: dragStartHaptic,
              onReorderEnd: dragEndHaptic,
              onReorderItem: notifier.reorderCharacters,
              children: [
                for (var i = 0; i < chars.length; i++)
                  Padding(
                    key: ValueKey('char${chars[i].id}'),
                    padding: EdgeInsets.only(top: i > 0 ? 9 : 0),
                    child: _CharacterTile(char: chars[i]),
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    GenerateNotifier notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部角色?'),
        content: const Text('将移除所有角色及其配置,此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.scheme.error,
              foregroundColor: context.scheme.onError,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) notifier.clearCharacters();
  }
}

class _CharacterTile extends ConsumerWidget {
  const _CharacterTile({required this.char});

  final CharacterPrompt char;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;
    final enabled = char.enabled;
    // 只有站位徽章的写法跟模型走(见下),select 一下别让整张卡跟着全局状态重建。
    final isV5 = ref.watch(
      generateProvider.select((s) => isNai5Model(s.params.model)),
    );
    // AUTO 是整张图的档(官方 AI's Choice = use_coords false),不是这张卡的属性:
    // 坐标一直在,只是模型不理会。同样 select 一下,别让整张卡跟着全局重建。
    final autoPos = ref.watch(
      generateProvider.select((s) => !s.params.useCoords),
    );
    final tokens = totalPromptTokens(
      ref.watch(naiTokenizerProvider).value,
      main: char.positive,
    );

    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: enabled ? 1 : .5,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(sharedAxisRoute(EditorPage(positive: true, charId: char.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // 电源开关(裸图标)
                    IconButton(
                      onPressed: () =>
                          notifier.updateCharacter(char.id, enabled: !enabled),
                      icon: Icon(
                        Icons.power_settings_new,
                        size: 24,
                        color: enabled ? scheme.primary : scheme.outline,
                      ),
                      // 与参考图那枚同款:字号 + 启用时的主色底托(见 RefEnableToggle)
                      style: IconButton.styleFrom(
                        backgroundColor: enabled
                            ? scheme.primary.withValues(alpha: .12)
                            : Colors.transparent,
                      ),
                      tooltip: enabled ? '停用(保留配置)' : '启用',
                      visualDensity: const VisualDensity(
                        horizontal: -3,
                        vertical: -3,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 名称 + 状态说明:占满中间,把尾部(徽章+删除)顶到最右
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              char.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodyLarge!.copyWith(
                                fontWeight: FontWeight.w700,
                                color: enabled
                                    ? scheme.onSurface
                                    : scheme.outline,
                              ),
                            ),
                          ),
                          if (!enabled) ...[
                            const SizedBox(width: 8),
                            // 不给 Flexible:状态标签是定长的,该让角色名去挤。
                            // 原先两个都 flex:1 平分,标签分到的一半装不下,
                            // 就从尾巴开始吃 —— 屏幕上只剩「已禁用 ·…」。
                            Text(
                              '已禁用',
                              style: context.texts.labelSmall!.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 站位徽章
                    Material(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(17),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => showPositionGridDialog(context, char.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.grid_on,
                                size: 15,
                                color: autoPos
                                    ? scheme.onSurfaceVariant
                                    : scheme.primary,
                              ),
                              const SizedBox(width: 5),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  // AUTO 是整张图的档(use_coords=false):这时
                                  // 坐标还在,只是模型不理会,徽章统一写 AUTO。
                                  // 否则网格模型(V4/V4.5)下显示它实际会被吸附到
                                  // 的那一格 —— 徽章写 '42,67%'、请求里发的却是
                                  // C4 的格心,两边对不上(见 quantizeCenterToGrid)。
                                  autoPos
                                      ? 'AUTO'
                                      : positionChipLabel(
                                          char.position,
                                          grid: !isV5,
                                        ),
                                  textAlign: TextAlign.center,
                                  style:
                                      mono(
                                        context,
                                        size: 12,
                                        weight: FontWeight.w700,
                                      ).copyWith(
                                        color: autoPos
                                            ? scheme.onSurfaceVariant
                                            : scheme.primary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        onPressed: () => notifier.removeCharacter(char.id),
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: scheme.error.withValues(alpha: .85),
                        ),
                        tooltip: '删除角色',
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          char.positive.isEmpty ? '点击编辑提示词…' : char.positive,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium!.copyWith(
                            color: char.positive.isEmpty
                                ? scheme.outline
                                : (enabled
                                      ? scheme.onSurfaceVariant
                                      : scheme.outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$tokens',
                        style: mono(
                          context,
                          size: 11,
                          weight: FontWeight.w500,
                        ).copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_settings.dart';
import '../../../core/util/nai_tokenizer.dart';
import '../../editor/editor_page.dart';
import '../../inspiration/tag_models.dart' show TagCategory, tagCategoryDef;
import '../../inspiration/widgets/char_pick_sheet.dart';
import '../../inspiration/widgets/tag_card.dart' show TagCardPreview;
import '../canvas_state.dart';
import '../char_position.dart';
import '../generate_state.dart';
import '../models.dart';
import 'common.dart';
import 'position_grid_dialog.dart';
import 'prompt_card.dart' show negativePreview;
import 'section_card.dart';
import '../../../l10n/l10n.dart';

/// 角色面板:沿用创作页的容器与公共按钮,预览比例与灵感角色库一致。
/// 点头像换角色、点名称改名;删除直接放在卡上,长按整卡仍可排序。
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
    // 窄屏只收紧公共圆形按钮尺寸,常规宽度与其它模块保持一致。
    final actionSize = MediaQuery.sizeOf(context).width < 350 ? 32.0 : 36.0;
    // 读数按**启用**数算:上限管的是进载荷的那几个,停用的不占额度。切模型时
    // 超出的尾巴会自动停用(见 GenerateNotifier._capEnabled),之后还标红就只剩
    // 一种来路 —— 用户在小槽位模型下自己又勾回来了,那确实该红。
    final active = chars.where((c) => c.enabled).length;

    return SectionCard(
      icon: Icons.group_outlined,
      title: context.l10n.characters,
      reorderIndex: reorderIndex,
      badge: CountBadge('$active / $cap', error: active > cap),
      actions: [
        if (chars.isNotEmpty)
          RoundIconBtn(
            Icons.delete_sweep_outlined,
            size: actionSize,
            tooltip: '清空全部角色',
            color: scheme.onSurfaceVariant,
            onTap: () => _confirmClear(context, notifier),
          ),
        // 与 Vibe / 角色参考卡头的「库」同一枚图标、同一个位置
        RoundIconBtn(
          Icons.grid_view,
          size: actionSize,
          tooltip: '角色库',
          color: canAdd ? scheme.onSurfaceVariant : scheme.outline,
          onTap: canAdd ? () => _addFromLibrary(context, ref) : null,
        ),
        RoundIconBtn(
          Icons.add,
          size: actionSize,
          tooltip: context.l10n.addCharacter,
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
          // 增删角色时高度平滑过渡(第一个由卡片展开动画负责)
          : AnimatedSize(
              duration: Motion.medium,
              curve: Motion.emphasized,
              alignment: Alignment.topCenter,
              // 长按卡片拖动排序。删除只走行内按钮(删了给撤销条),不做横滑删除
              // —— 横滑一下就抹掉整份角色配置(提示词/站位/开关),太容易误触。
              child: ReorderableListView(
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
                      child: _CharacterTile(char: chars[i], index: i),
                    ),
                ],
              ),
            ),
    );
  }

  /// 卡头「角色库」:多选追加,可选数 = 剩下的槽位(只剩一个就是点一下即加)。
  Future<void> _addFromLibrary(BuildContext context, WidgetRef ref) async {
    final s = ref.read(generateProvider);
    final room = maxCharactersOf(s.params.model) - s.characters.length;
    if (room <= 0) return;
    final picked = await showCharPickSheet(context, max: room);
    if (picked == null || picked.isEmpty || !context.mounted) return;
    ref.read(generateProvider.notifier).addNamedCharactersFrom([
      for (final p in picked)
        (
          name: p.entry.name,
          positive: p.entry.positive,
          negative: p.entry.negative,
          avatar: p.preview,
        ),
    ]);
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
  const _CharacterTile({required this.char, required this.index});

  final CharacterPrompt char;

  /// 行序,只用来算改名留空时回落的默认名。
  final int index;

  /// 点名字改名。留空 = 回到默认的「角色 N」,N 按当前行序算,与新增时同一口径
  /// (名字本就不是稳定句柄,认人靠 id)。
  ///
  /// 名字只在 app 内显示:载荷里没有这一项,导入也读不回来,所以改名不影响出图,
  /// 也不必跟着图走。
  Future<void> _rename(BuildContext context, GenerateNotifier notifier) async {
    final fallback = '角色 ${index + 1}';
    final ctrl = TextEditingController(text: char.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: fallback, // 留空就按默认编号显示
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null) return; // 取消
    final trimmed = name.trim();
    notifier.updateCharacter(
      char.id,
      name: trimmed.isEmpty ? fallback : trimmed,
    );
  }

  /// 点头像:从灵感角色库挑一个换进这张卡(名字、正负向、头像;站位和开关不动)。
  Future<void> _pickFromLibrary(BuildContext context, WidgetRef ref) async {
    final picked = await showCharPickSheet(context);
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final p = picked.first;
    // 读最新的:面板开着的这段时间里,这张卡可能被改过,甚至被删了
    final cur = ref
        .read(generateProvider)
        .characters
        .where((c) => c.id == char.id)
        .firstOrNull;
    if (cur == null) return;
    // 没头像又写了字 = 手写的内容,换之前问一句,别一下冲掉。带头像的本就是
    // 库里选来的,点头像就是要换人,不再多问。
    if (cur.avatar == null &&
        (cur.positive.trim().isNotEmpty || cur.negative.trim().isNotEmpty)) {
      final ok = await confirmDialog(
        context,
        title: '替换「${cur.name}」?',
        message: '提示词将换成「${p.entry.name}」的。',
        confirmLabel: '替换',
      );
      if (!ok || !context.mounted) return;
    }
    ref
        .read(generateProvider.notifier)
        .fillCharacterFrom(
          char.id,
          name: p.entry.name,
          positive: p.entry.positive,
          negative: p.entry.negative,
          avatar: p.preview,
        );
  }

  /// 删除这张卡,提示条给撤销:原样放回原来的位置。撤销条挂着的这几秒里
  /// 切了画布,也还给删的那张。
  void _remove(BuildContext context, WidgetRef ref) {
    final canvases = ref.read(canvasWorkspaceProvider.notifier);
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final chars = ref.read(generateProvider).characters;
    final at = chars.indexWhere((c) => c.id == char.id);
    if (at < 0) return;
    final removed = chars[at];
    ref.read(generateProvider.notifier).removeCharacter(removed.id);
    hintSnack(
      context,
      '已删除「${removed.name}」',
      icon: Icons.delete_outline,
      actionLabel: '撤销',
      onAction: () => canvases.updatePrompts(
        canvasId,
        (p) => p.characters.any((c) => c.id == removed.id)
            ? p
            : p.copyWith(
                characters: [...p.characters]
                  ..insert(at.clamp(0, p.characters.length), removed),
              ),
      ),
    );
  }

  void _openEditor(BuildContext context, {required bool positive}) =>
      Navigator.of(
        context,
      ).push(sharedAxisRoute(EditorPage(positive: positive, charId: char.id)));

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
    final compact = ref.watch(
      themeSettingsProvider.select((t) => t.compactCharCards),
    );
    final tokenizer = ref.watch(naiTokenizerProvider).value;
    final hasNeg = char.negative.trim().isNotEmpty;
    final positionLabel = autoPos
        ? 'AUTO'
        : positionChipLabel(char.position, grid: !isV5);
    final controlSize = MediaQuery.sizeOf(context).width < 350 ? 32.0 : 36.0;
    // 停用只弱化内容,操作按钮保持可用。
    final posColor = enabled ? scheme.primary : scheme.outline;
    final negColor = enabled ? scheme.error : scheme.outline;
    final promptStyle = context.texts.bodyMedium!;
    final countStyle = mono(
      context,
      size: 12,
      weight: FontWeight.w500,
    ).copyWith(color: scheme.outline, height: 1.25);

    final name = InkWell(
      onTap: () => _rename(context, notifier),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          char.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.bodyLarge!.copyWith(
            fontWeight: FontWeight.w700,
            color: enabled ? scheme.onSurface : scheme.outline,
          ),
        ),
      ),
    );
    // 浮卡样式下角色块是凹槽灰,块里的圆钮反用卡片白
    final btnFill = context.skin.float ? scheme.surfaceContainerLow : null;
    final toggleBtn = RoundIconBtn(
      Icons.power_settings_new,
      size: controlSize,
      background: btnFill,
      color: enabled ? scheme.primary : scheme.outline,
      onTap: () => notifier.updateCharacter(char.id, enabled: !enabled),
      tooltip: enabled ? '停用(保留配置)' : '启用',
    );
    final deleteBtn = RoundIconBtn(
      Icons.delete_outline,
      size: controlSize,
      background: btnFill,
      color: scheme.error,
      onTap: () => _remove(context, ref),
      tooltip: '删除角色',
    );
    void openPosition() => showPositionGridDialog(context, char.id);
    final positionTip = '设置角色位置：$positionLabel';
    final positive = Row(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.end,
      children: [
        // 紧凑版的位置签排在正向预览左侧
        if (compact) ...[
          _PositionChip(
            label: positionLabel,
            auto: autoPos || positionLabel == 'AUTO',
            enabled: enabled,
            onTap: openPosition,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            char.positive.isEmpty ? '点击编辑提示词…' : char.positive,
            maxLines: compact || hasNeg ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: promptStyle.copyWith(
              color: char.positive.isEmpty || !enabled
                  ? scheme.outline
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    final negative = InkWell(
      onTap: () => _openEditor(context, positive: false),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(Icons.block, size: 14, color: negColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                negativePreview(char.negative),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: promptStyle.copyWith(color: negColor),
              ),
            ),
          ],
        ),
      ),
    );
    // 提示词区:正负两行预览,右侧 token 数上正向、下负面(同分区行)
    final prompts = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              positive,
              if (hasNeg) ...[SizedBox(height: compact ? 2 : 4), negative],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${totalPromptTokens(tokenizer, main: char.positive)}',
                style: countStyle,
              ),
              Text(
                '${totalPromptTokens(tokenizer, main: char.negative)}',
                style: countStyle.copyWith(color: negColor),
              ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditor(context, positive: true),
        child: Padding(
          // 紧凑版没有头像垫在左边,文字离卡边留宽一些
          padding: compact
              ? const EdgeInsets.fromLTRB(14, 8, 8, 8)
              : const EdgeInsets.all(8),
          child: compact
              // 紧凑:名称 + 三个圆钮一行,下面位置签 + 提示词铺满整行。
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 4),
                        RoundIconBtn(
                          Icons.location_on_outlined,
                          size: controlSize,
                          background: btnFill,
                          color: posColor,
                          onTap: openPosition,
                          tooltip: positionTip,
                        ),
                        const SizedBox(width: 6),
                        toggleBtn,
                        const SizedBox(width: 6),
                        deleteBtn,
                      ],
                    ),
                    const SizedBox(height: 6),
                    prompts,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(
                      url: char.avatar,
                      name: char.name,
                      enabled: enabled,
                      onTap: () => _pickFromLibrary(context, ref),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 名称与三个等大的公共圆形按钮共用顶行。
                          Row(
                            children: [
                              Expanded(child: name),
                              const SizedBox(width: 4),
                              RoundIconBtn(
                                Icons.location_on_outlined,
                                size: controlSize,
                                background: btnFill,
                                color: posColor,
                                onTap: openPosition,
                                tooltip: positionTip,
                              ),
                              const SizedBox(width: 6),
                              toggleBtn,
                              const SizedBox(width: 6),
                              deleteBtn,
                            ],
                          ),
                          // 坐标读数与名字分开,位置按钮只占一个图标的宽度。
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: posColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  autoPos
                                      ? context.l10n.aiChoicePosition
                                      : positionLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.bodySmall!.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: posColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 名称和提示词都占满预览图右侧。
                          prompts,
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

/// 紧凑角色卡正向预览左侧的位置签:定了位是填色签,自动定位 / 停用是描边灰字。
/// 点它打开定位面板。
class _PositionChip extends StatelessWidget {
  const _PositionChip({
    required this.label,
    required this.auto,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool auto;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final filled = enabled && !auto;
    return Material(
      color: filled
          ? context.solidFill(scheme.primaryContainer)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: filled
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            auto ? context.l10n.aiChoice : label,
            maxLines: 1,
            style: context.texts.labelMedium!.copyWith(
              fontWeight: FontWeight.w600,
              color: filled
                  ? context.onSolidFill(scheme.onPrimaryContainer)
                  : enabled
                  ? scheme.onSurfaceVariant
                  : scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

/// 停用时头像去色。
const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// 竖向头像:固定使用角色库的 832:1216 比例,不随提示词高度拉伸。
/// 点它从灵感角色库挑人。
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.name,
    required this.enabled,
    required this.onTap,
  });

  final String? url;
  final String name;
  final bool enabled;
  final VoidCallback onTap;

  static const width = 72.0;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final slot = ColoredBox(
      color: context.skin.float
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.person_search_outlined,
          size: 24,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final aspect = tagCategoryDef(TagCategory.character).previewAspect;
    Widget child = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? slot
          : TagCardPreview(
              url: url,
              name: name,
              decodeWidth: width,
              placeholder: slot,
            ),
    );
    if (!enabled) {
      child = Opacity(
        opacity: .55,
        child: ColorFiltered(colorFilter: _greyscale, child: child),
      );
    }
    return Tooltip(
      message: url == null ? '从角色库选' : '换角色',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          child: AspectRatio(aspectRatio: aspect, child: child),
        ),
      ),
    );
  }
}

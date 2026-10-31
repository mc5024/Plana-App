import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/nai_tokenizer.dart';
import '../../editor/editor_models.dart'
    show outputOf, parseFolds, pickEditorText;
import '../../editor/editor_page.dart';
import '../../inspiration/codex/codex_favorites.dart' show CodexFavorite;
import '../../inspiration/codex/codex_models.dart' show CodexMeta, CodexType;
import '../../inspiration/codex/codex_providers.dart' show codexIndexProvider;
import '../../inspiration/codex/codex_sheets.dart' show codexAddToPrompt;
import '../../inspiration/tag_models.dart' show TagCategory, TagEntry;
import '../../inspiration/widgets/char_pick_sheet.dart'
    show showLibraryPickSheet;
import '../canvas_state.dart';
import '../generate_state.dart';
import '../models.dart' show PromptSection, maxCharactersOf, tokenLimitOf;
import '../prompt_presets.dart';
import '../prompt_sections.dart';
import '../style_recipes.dart';
import 'common.dart';
import 'section_save.dart';

/// 提示词卡:头部 token 进度条 + 正文 + 负面单行(带 +N 溢出与独立计数)。
/// 常驻展开。卡头按钮与角色卡同序:清空正向(可撤销)/ 灵感库 / 添加分区。
///
/// 没分区时正文是两行段落预览;分了区就一格一行,操作照角色卡:点行编辑这一格、
/// 点名字改名、⏻ 停用、删除(可撤销)。
/// 主体那一行就是原来的主提示词,停用 / 删除只管它的正向(负面那行是整张卡的)。
/// 长按一格进多选:点行是勾选,拖左边的把手调顺序(顺序即拼接顺序);卡头换成
/// 选择栏:退出、已选几格,停用 / 删除 / 存到灵感库 / 合并。
class PromptCard extends ConsumerStatefulWidget {
  const PromptCard({super.key});

  @override
  ConsumerState<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends ConsumerState<PromptCard> {
  /// 多选态(长按一格进,点卡头的退出或做完一次合并 / 删除 / 存就退)。
  bool _selecting = false;

  /// 勾了哪几格(分区 id,主体是 [kMainSectionId])。
  final _picked = <String>{};

  void _exitSelect() => setState(() {
    _selecting = false;
    _picked.clear();
  });

  /// 进多选,勾上 [id] 那一格。
  void _enterSelect(String id) => setState(() {
    _selecting = true;
    _picked
      ..clear()
      ..add(id);
  });

  void _togglePick(String id) => setState(
    () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generateProvider);
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;
    final sections = withMainRow(state.sections, state.prompt);
    // 切了画布就退出多选:勾的是那张画布的格子
    ref.listen(
      canvasWorkspaceProvider.select((w) => w.activeId),
      (_, _) => _exitSelect(),
    );
    final selecting = _selecting && sections.isNotEmpty;
    // web totalTokenCount 口径:主串 + 启用分区 + 启用角色串 + 激活预设(都实际
    // 参与生成)。角色串取 countedCharactersProvider —— 模块不可见(anima 等)
    // 时为空,不然会出现「切到 anima 计数凭空变大」的幽灵。
    final tok = ref.watch(naiTokenizerProvider).value;
    final preset = ref.watch(activePromptPresetProvider);
    final chars = ref.watch(countedCharactersProvider);
    final promptTokens = totalPromptTokens(
      tok,
      main: mainEnabled(sections) ? state.prompt : '',
      parts: [
        ...sectionTexts(sections, positive: true),
        for (final c in chars) c.positive,
      ],
      preset: preset?.positive ?? '',
    );
    final negTokens = totalPromptTokens(
      tok,
      main: state.negativePrompt,
      parts: [
        ...sectionTexts(sections, positive: false),
        for (final c in chars) c.negative,
      ],
      preset: preset?.negative ?? '',
    );
    // 上限按当前模型取(NAI 5 抬到 703/1471,其余 512),读数与编辑器顶栏同源。
    final limit = tokenLimitOf(state.params.model);
    final over = promptTokens > limit;
    final ratio = (promptTokens / limit).clamp(0.0, 1.0);
    final barColor = over ? scheme.error : scheme.primary;
    // 窄屏只收紧公共圆形按钮尺寸,与角色卡头同一口径。
    final actionSize = MediaQuery.sizeOf(context).width < 350 ? 32.0 : 36.0;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(selecting ? 9 : 15, 8, 13, 4),
            child: selecting
                ? _selectHeader(context, sections, state.prompt, actionSize)
                : Row(
                    children: [
                      Icon(
                        Icons.subject,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        '提示词',
                        style: context.texts.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        '$promptTokens',
                        style: mono(context, size: 12, weight: FontWeight.w700)
                            .copyWith(
                              color: over ? scheme.error : scheme.onSurface,
                            ),
                      ),
                      // 占满剩余宽度把按钮推到右边;四颗按钮都在时窄屏可能挤,
                      // 上限先省略,按钮不缩
                      Expanded(
                        child: Text(
                          ' / $limit',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: mono(
                            context,
                            size: 12,
                            weight: FontWeight.w500,
                          ).copyWith(color: scheme.outline),
                        ),
                      ),
                      if (state.prompt.trim().isNotEmpty ||
                          sections.isNotEmpty) ...[
                        RoundIconBtn(
                          Icons.delete_sweep_outlined,
                          size: actionSize,
                          tooltip: sections.isEmpty ? '清空正向提示词' : '清空提示词和分区',
                          color: scheme.onSurfaceVariant,
                          onTap: () => _clearPositive(context, ref),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // 与角色卡头「角色库」同一枚图标
                      RoundIconBtn(
                        Icons.grid_view,
                        size: actionSize,
                        tooltip: '灵感库',
                        color: scheme.onSurfaceVariant,
                        onTap: () => _importFromLibrary(context, ref),
                      ),
                      const SizedBox(width: 6),
                      RoundIconBtn(
                        Icons.add,
                        size: actionSize,
                        tooltip: '添加分区',
                        onTap: notifier.addSection,
                      ),
                    ],
                  ),
          ),
          // token 用量进度条
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: ratio, end: ratio),
                duration: Motion.medium,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: barColor,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 段落预览 / 分区行切换与增删分区时,高度平滑过渡
              AnimatedSize(
                duration: Motion.medium,
                curve: Motion.emphasized,
                alignment: Alignment.topCenter,
                child: sections.isEmpty
                    // 正面:段落预览
                    ? InkWell(
                        onTap: () => _openEditor(context, positive: true),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 10),
                          child: Text(
                            state.prompt.isEmpty
                                ? '点击编辑正面提示词…'
                                : state.prompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodyLarge!.copyWith(
                              height: 1.5,
                              color: state.prompt.isEmpty
                                  ? scheme.outline
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _SectionRows(
                          selecting: selecting,
                          picked: _picked,
                          onToggle: _togglePick,
                          onHold: _enterSelect,
                        ),
                      ),
              ),
              // 负面:块标 + 单行(+N)+ 独立计数
              InkWell(
                onTap: () => _openEditor(context, positive: false),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 6, 15, 12),
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 17, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          switch (negativePreview(state.negativePrompt)) {
                            '' => '点击编辑负面提示词…',
                            final s => s,
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium!.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$negTokens',
                        style: mono(
                          context,
                          size: 13,
                          weight: FontWeight.w500,
                        ).copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 多选态的卡头:左边退出 + 已选几格,右边停用 / 删除 / 存到灵感库 / 合并,
  /// 还是卡头那排圆钮。合并至少勾两格,存要勾的格里有不空的;用不了的灰着。
  Widget _selectHeader(
    BuildContext context,
    List<PromptSection> sections,
    String mainPrompt,
    double size,
  ) {
    final scheme = context.scheme;
    final notifier = ref.read(generateProvider.notifier);
    final picked = [
      for (final s in sections)
        if (_picked.contains(s.id)) s,
    ];
    final rows = picked;
    final anyOn = rows.any((s) => s.enabled);
    final canMerge = picked.length >= 2;
    final canSave = picked.any(
      (s) => sectionSaveText(s, mainPrompt).positive.isNotEmpty,
    );
    return Row(
      children: [
        RoundIconBtn(
          Icons.close,
          size: size,
          tooltip: '退出多选',
          color: scheme.onSurfaceVariant,
          onTap: _exitSelect,
        ),
        const SizedBox(width: 9),
        Text(
          '已选 ${picked.length}',
          style: context.texts.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        RoundIconBtn(
          Icons.power_settings_new,
          size: size,
          tooltip: rows.isEmpty || anyOn ? '停用' : '启用',
          color: rows.isEmpty ? scheme.outline : scheme.primary,
          onTap: rows.isEmpty
              ? null
              : () => notifier.setSectionsEnabled({
                  for (final s in rows) s.id,
                }, !anyOn),
        ),
        const SizedBox(width: 6),
        RoundIconBtn(
          Icons.delete_outline,
          size: size,
          tooltip: '删除',
          color: rows.isEmpty ? scheme.outline : scheme.error,
          onTap: rows.isEmpty ? null : () => _deletePicked(context, rows),
        ),
        const SizedBox(width: 6),
        RoundIconBtn(
          Icons.save_outlined,
          size: size,
          tooltip: '存到灵感库',
          color: canSave ? scheme.primary : scheme.outline,
          onTap: !canSave
              ? null
              : picked.length == 1
              ? () => _savePicked(context, picked.single)
              : () => _savePickedAll(context, picked),
        ),
        const SizedBox(width: 6),
        // 合并是这一栏的正事:勾够两格就填主色
        Tooltip(
          message: '合并',
          child: Material(
            color: canMerge ? scheme.primary : scheme.surfaceContainerHigh,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canMerge ? () => _mergePicked(context, picked) : null,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  Icons.call_merge,
                  size: 20,
                  color: canMerge ? scheme.onPrimary : scheme.outline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 删掉勾的几格,提示条给撤销:整列分区放回,勾了主体还把它的正向放回,
  /// 还给删除时那张画布。
  void _deletePicked(BuildContext context, List<PromptSection> rows) {
    final s = ref.read(generateProvider);
    final old = (prompt: s.prompt, raw: s.promptRaw, sections: s.sections);
    final canvases = ref.read(canvasWorkspaceProvider.notifier);
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    ref.read(generateProvider.notifier).removeSections({
      for (final s in rows) s.id,
    });
    _exitSelect();
    hintSnack(
      context,
      '已删除 ${rows.length} 个分区',
      icon: Icons.delete_outline,
      actionLabel: '撤销',
      onAction: () => canvases.updatePrompts(
        canvasId,
        (p) => p.copyWith(
          prompt: old.prompt,
          promptRaw: old.raw,
          sections: old.sections,
        ),
      ),
    );
  }

  /// 合并勾的几格(见 mergeSectionsIn),提示条给撤销:主体的词和整列分区放回。
  void _mergePicked(BuildContext context, List<PromptSection> rows) {
    final s = ref.read(generateProvider);
    final old = (
      prompt: s.prompt,
      raw: s.promptRaw,
      neg: s.negativePrompt,
      negRaw: s.negativePromptRaw,
      sections: s.sections,
    );
    final canvases = ref.read(canvasWorkspaceProvider.notifier);
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final into = ref.read(generateProvider.notifier).mergeSections({
      for (final x in rows) x.id,
    });
    if (into == null) return;
    _exitSelect();
    hintSnack(
      context,
      '已合并到「${into.name}」',
      icon: Icons.call_merge,
      actionLabel: '撤销',
      onAction: () => canvases.updatePrompts(
        canvasId,
        (p) => p.copyWith(
          prompt: old.prompt,
          promptRaw: old.raw,
          negativePrompt: old.neg,
          negativePromptRaw: old.negRaw,
          sections: old.sections,
        ),
      ),
    );
  }

  /// 勾的那一格进灵感页的新建页(见 saveSectionToLibrary),进了就退出多选。
  Future<void> _savePicked(BuildContext anchor, PromptSection section) async {
    if (await saveSectionToLibrary(anchor, ref, section) && mounted) {
      _exitSelect();
    }
  }

  /// 勾了几格:每格直接存成一条(见 saveSectionsToLibrary),存完退出多选。
  Future<void> _savePickedAll(
    BuildContext context,
    List<PromptSection> rows,
  ) async {
    final r = await saveSectionsToLibrary(ref, rows);
    if (!mounted || !context.mounted) return;
    _exitSelect();
    hintSnack(
      context,
      r.saved == 0
          ? '灵感库里都已有了'
          : r.skipped > 0
          ? '已存 ${r.saved} 条到灵感库,${r.skipped} 条已有'
          : '已存 ${r.saved} 条到灵感库',
      icon: Icons.check_circle_outline,
    );
  }

  void _openEditor(BuildContext context, {required bool positive}) {
    Navigator.of(context).push(sharedAxisRoute(EditorPage(positive: positive)));
  }

  /// 清空:主体的正向清空,分区整列清掉,主体的负面留着。撤销条挂几秒,
  /// 期间切了画布也要还给清空的那张。
  void _clearPositive(BuildContext context, WidgetRef ref) {
    final s = ref.read(generateProvider);
    final old = (prompt: s.prompt, raw: s.promptRaw, sections: s.sections);
    if (old.prompt.isEmpty && old.sections.isEmpty) return;
    final canvases = ref.read(canvasWorkspaceProvider.notifier);
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    ref.read(generateProvider.notifier).clearPositive();
    final oldIds = {for (final x in old.sections) x.id};
    hintSnack(
      context,
      old.sections.isEmpty ? '已清空正向提示词' : '已清空提示词和分区',
      icon: Icons.delete_sweep_outlined,
      actionLabel: '撤销',
      onAction: () => canvases.updatePrompts(
        canvasId,
        (p) => p.copyWith(
          prompt: old.prompt,
          promptRaw: old.raw,
          // 分区原样放回;撤销条挂着这几秒里新加的格子接在后面
          sections: old.sections.isEmpty
              ? null
              : normalizeSections([
                  ...old.sections,
                  for (final x in p.sections)
                    if (!x.isMain && !oldIds.contains(x.id)) x,
                ]),
        ),
      ),
    );
  }

  /// 卡头「灵感库」:角色、画风、场景与法典收藏都能挑。选完每条自成一格、
  /// 不折叠,格子名是分类名(角色也进分区,角色卡有自己的选择器),按勾选顺序
  /// 接在最后;法典收藏同法典页的「使用」(角色段照旧拆成角色卡),画师串词典
  /// 里收的算画风。
  Future<void> _importFromLibrary(BuildContext context, WidgetRef ref) async {
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final picks = await showLibraryPickSheet(context);
    if (picks == null || !context.mounted) return;
    // 面板是模态的,开着时切不了画布;真切了(不该发生)就不写,免得写错地方
    if (ref.read(canvasWorkspaceProvider).activeId != canvasId) return;
    final index = ref.read(codexIndexProvider).value ?? const <CodexMeta>[];
    bool artistString(CodexFavorite f) =>
        f.entry.tags.trim().isNotEmpty &&
        index.any((m) => m.id == f.codexId && m.type == CodexType.string);
    // 一条一条按勾选顺序加:新格子都接在最后,顺序就是勾的先后
    final notifier = ref.read(generateProvider.notifier);
    var dropped = 0;
    for (final p in picks) {
      final t = p.tag, f = p.codex;
      if (t != null) {
        notifier.addEntrySections([t.entry]);
      } else if (f != null && artistString(f)) {
        notifier.addEntrySections([
          TagEntry(
            id: 'codex_${f.entry.id}',
            category: TagCategory.artist,
            name: f.entry.title,
            positive: f.entry.tags,
          ),
        ]);
      } else if (f != null) {
        dropped += codexAddToPrompt(ref, f.entry, asSection: true).dropped;
      }
    }
    if (dropped > 0) {
      final cap = maxCharactersOf(ref.read(generateProvider).params.model);
      hintSnack(
        context,
        '角色已满 $cap 个,$dropped 个没加进去',
        icon: Icons.block_outlined,
      );
    }
    // 带推荐参数、且对得上当前模型的,弹窗问套不套(点了才写,不切模型)
    final artists = [
      for (final p in picks)
        if (p.tag?.entry.category == TagCategory.artist) p.tag!.entry,
    ];
    if (artists.isNotEmpty && context.mounted) {
      await offerStyleRecipe(context, ref, artists, canvasId: canvasId);
    }
  }
}

/// 分了区之后的正文:一格一行,长按一格进多选。多选态下点行是勾选,拖左边的
/// 把手排序。
class _SectionRows extends ConsumerWidget {
  const _SectionRows({
    required this.selecting,
    required this.picked,
    required this.onToggle,
    required this.onHold,
  });

  final bool selecting;
  final Set<String> picked;
  final ValueChanged<String> onToggle;

  /// 长按一格(多选态之外)。
  final ValueChanged<String> onHold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(generateProvider);
    final notifier = ref.read(generateProvider.notifier);
    final tok = ref.watch(naiTokenizerProvider).value;
    final sections = withMainRow(state.sections, state.prompt);
    var k = 0; // 非主体分区的序号,改名留空时的默认名用
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 长按留给进多选,排序只走多选态每行左边的把手
      buildDefaultDragHandles: false,
      proxyDecorator: _rowDragProxy,
      onReorderStart: dragStartHaptic,
      onReorderEnd: dragEndHaptic,
      onReorderItem: notifier.reorderSections,
      children: [
        for (final (i, s) in sections.indexed)
          _SectionRow(
            key: ValueKey('sec${s.id}'),
            index: i,
            section: s,
            fallbackName: s.isMain
                ? '主体'
                : s.artist
                ? '画风'
                : '分区 ${++k}',
            draft: s.isMain
                ? pickEditorText(state.promptRaw, state.prompt)
                : pickEditorText(s.positiveRaw, s.positive),
            tokens: totalPromptTokens(
              tok,
              main: s.isMain ? state.prompt : s.positive,
            ),
            negTokens: totalPromptTokens(
              tok,
              main: s.isMain ? state.negativePrompt : s.negative,
            ),
            selecting: selecting,
            picked: picked.contains(s.id),
            onToggle: () => onToggle(s.id),
            onHold: () => onHold(s.id),
          ),
      ],
    );
  }
}

/// 拖起来的那一行垫一层底色,不然半透明地叠在别的行上。
Widget _rowDragProxy(Widget child, int index, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + .03 * t,
          child: Material(
            color: context.scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
    );

class _SectionRow extends ConsumerWidget {
  const _SectionRow({
    super.key,
    required this.index,
    required this.section,
    required this.fallbackName,
    required this.draft,
    required this.tokens,
    required this.negTokens,
    this.selecting = false,
    this.picked = false,
    this.onToggle,
    this.onHold,
  });

  /// 多选态:点行 / 点名字都是勾选,行尾换成勾选圈,左边多出移动把手。
  final bool selecting;
  final bool picked;
  final VoidCallback? onToggle;

  /// 在列表里的位置(把手拖动用)。
  final int index;

  /// 长按这一行(多选态之外)。
  final VoidCallback? onHold;

  final PromptSection section;

  /// 改名留空时回落的名字。
  final String fallbackName;

  /// 这一格的编辑器草稿(折叠在预览里显示成名字)。
  final String draft;
  final int tokens;
  final int negTokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;
    final s = section;
    // 停用只弱化内容,操作按钮保持可用(同角色卡)
    final on = s.enabled;
    // 与角色卡的开关 / 删除同一尺寸(窄屏同样收到 32)
    final btnSize = MediaQuery.sizeOf(context).width < 350 ? 32.0 : 36.0;
    final countStyle = mono(
      context,
      size: 12,
      weight: FontWeight.w500,
    ).copyWith(color: scheme.outline, height: 1.25);
    return InkWell(
      onLongPress: selecting ? null : onHold,
      onTap: selecting
          ? onToggle
          : () => Navigator.of(context).push(
              sharedAxisRoute(
                EditorPage(positive: true, sectionId: s.isMain ? null : s.id),
              ),
            ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(selecting ? 0 : 15, 4, 13, 4),
        child: Row(
          children: [
            if (selecting)
              // 按下就能拖;把手连同左边距一起算,图标和卡头的退出钮对齐
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 0, 8, 0),
                  child: SizedBox(
                    width: 24,
                    height: btnSize,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            _NameChip(
              name: s.name,
              enabled: on,
              onTap: selecting ? onToggle! : () => _rename(context, notifier),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Preview(draft: draft, enabled: on),
            ),
            const SizedBox(width: 8),
            // 上正向、下负面
            SizedBox(
              width: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$tokens', style: countStyle),
                  Text(
                    '$negTokens',
                    style: countStyle.copyWith(color: scheme.error),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (selecting)
              // 勾选圈放在删除钮那一格,和卡头最右那颗对齐
              SizedBox(
                width: btnSize,
                height: btnSize,
                child: Center(child: _PickDot(picked: picked)),
              )
            else ...[
              RoundIconBtn(
                Icons.power_settings_new,
                size: btnSize,
                color: on ? scheme.primary : scheme.outline,
                tooltip: on ? '停用(保留配置)' : '启用',
                onTap: () => notifier.updateSection(s.id, enabled: !on),
              ),
              const SizedBox(width: 6),
              RoundIconBtn(
                Icons.delete_outline,
                size: btnSize,
                color: scheme.error,
                tooltip: '删除分区',
                onTap: () => _remove(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 点名字改名,同角色卡:留空 = 回到默认名。
  Future<void> _rename(BuildContext context, GenerateNotifier notifier) async {
    final ctrl = TextEditingController(text: section.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(isDense: true, hintText: fallbackName),
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
    notifier.updateSection(
      section.id,
      name: trimmed.isEmpty ? fallbackName : trimmed,
    );
  }

  /// 直接删,不弹确认;提示条给撤销,还回删除时那张画布的原位。删的是主体:
  /// 它的正向一并清空,撤销连正向一起放回。
  void _remove(BuildContext context, WidgetRef ref) {
    final canvases = ref.read(canvasWorkspaceProvider.notifier);
    final canvasId = ref.read(canvasWorkspaceProvider).activeId;
    final s = ref.read(generateProvider);
    final old = (prompt: s.prompt, raw: s.promptRaw);
    final r = ref.read(generateProvider.notifier).removeSection(section.id);
    if (r == null) return;
    hintSnack(
      context,
      '已删除「${r.section.name}」',
      icon: Icons.delete_outline,
      actionLabel: '撤销',
      onAction: () => canvases.updatePrompts(
        canvasId,
        (p) => p.sections.any((x) => x.id == r.section.id)
            ? p
            : p.copyWith(
                prompt: r.section.isMain ? old.prompt : null,
                promptRaw: r.section.isMain ? old.raw : null,
                sections: restoreSection(
                  p.sections,
                  r.section,
                  r.index,
                  main: r.main,
                ),
              ),
      ),
    );
  }
}

/// 多选态行尾的勾选圈。
class _PickDot extends StatelessWidget {
  const _PickDot({required this.picked});

  final bool picked;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return AnimatedContainer(
      duration: Motion.fast,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: picked ? scheme.primary : Colors.transparent,
        border: picked ? null : Border.all(color: scheme.outline, width: 1.5),
      ),
      child: picked
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : null,
    );
  }
}

/// 分区名:填色小签,停用时改成描边、灰字。点它改名。
class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.name,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: enabled ? scheme.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: enabled
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: enabled ? scheme.onPrimaryContainer : scheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行预览:折叠(画师串等)显示成它的名字,其余照定稿写法。
class _Preview extends StatelessWidget {
  const _Preview({required this.draft, required this.enabled});

  final String draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 停用:字灰掉再加一道删除线,一眼看出这一格不进载荷
    final style = context.texts.bodyMedium!.copyWith(
      color: enabled ? scheme.onSurfaceVariant : scheme.outline,
      decoration: enabled ? null : TextDecoration.lineThrough,
      decorationColor: scheme.outline,
    );
    final pieces = previewPieces(draft);
    if (pieces.isEmpty) {
      return Text(
        '点击编辑…',
        maxLines: 1,
        style: context.texts.bodyMedium!.copyWith(color: scheme.outline),
      );
    }
    final spans = <InlineSpan>[];
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      if (i > 0) {
        // 折叠签之间空一格就够,纯文本之间照写逗号
        final pill = p.fold || pieces[i - 1].fold;
        spans.add(TextSpan(text: pill ? ' ' : ', '));
      }
      spans.add(
        p.fold
            ? WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p.text,
                    style: context.texts.labelMedium!.copyWith(
                      color: style.color,
                      decoration: style.decoration,
                      decorationColor: style.decorationColor,
                    ),
                  ),
                ),
              )
            : TextSpan(text: p.text),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// 预览片段:折叠只取名字,折叠之间的文字取定稿(禁用词剔掉)。
List<({String text, bool fold})> previewPieces(String draft) {
  String clean(String s) =>
      outputOf(s).replaceAll(RegExp(r'^[,，\s]+|[,，\s]+$'), '');
  final out = <({String text, bool fold})>[];
  var at = 0;
  for (final f in parseFolds(draft)) {
    final before = clean(draft.substring(at, f.start));
    if (before.isNotEmpty) out.add((text: before, fold: false));
    if (f.name.trim().isNotEmpty) out.add((text: f.name.trim(), fold: true));
    at = f.end;
  }
  final rest = clean(draft.substring(at));
  if (rest.isNotEmpty) out.add((text: rest, fold: false));
  return out;
}

/// 负面预览:前 3 个 tag + "+N" 溢出提示;没写返回空串。提示词卡与角色卡共用。
String negativePreview(String neg) {
  final tags = neg
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (tags.isEmpty) return '';
  final shown = tags.take(3).join(', ');
  final extra = tags.length - 3;
  return extra > 0 ? '$shown +$extra' : shown;
}

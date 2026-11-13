import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../canvas_state.dart';
import '../models.dart' show CharacterPrompt, GenParams, modelName;
import '../prompt_sections.dart' show joinSections;
import '../style_recipes.dart' show recipeDetail, recipeOf;
import 'bottom_action_bar.dart';
import 'canvas_history_sheet.dart';
import 'common.dart';
import '../display_names.dart';
import '../../../l10n/l10n.dart';

/// 只显示当前画布，与模型选择共用顶栏。点名称展开全部画布。
class CanvasPicker extends ConsumerWidget {
  const CanvasPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(canvasWorkspaceProvider);
    final canvas = workspace.active;
    final scheme = context.scheme;
    return Tooltip(
      message: context.l10n.switchCanvas,
      child: Semantics(
        button: true,
        label: context.l10n.currentCanvasSemantics(
          canvasDisplayName(context.l10n, canvas.name),
          workspace.canvases.length,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const _CanvasManager(),
            ),
            // 默认画布名字固定,长按不给改名
            onLongPress: canvas.id == workspace.defaultId
                ? null
                : () => _renameCanvas(context, ref, canvas),
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      canvasDisplayName(context.l10n, canvas.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium!.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.expand_more, size: 20, color: scheme.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _prepareUiSwitch(WidgetRef ref) {
  FocusManager.instance.primaryFocus?.unfocus();
  ref.read(floatingPillProvider.notifier).close();
  Haptics.selection();
}

void _selectCanvas(WidgetRef ref, String id) {
  if (ref.read(canvasWorkspaceProvider).activeId == id) return;
  _prepareUiSwitch(ref);
  ref.read(canvasWorkspaceProvider.notifier).select(id);
}

Future<void> _renameCanvas(
  BuildContext context,
  WidgetRef ref,
  CanvasDraft canvas,
) async {
  final shown = canvasDisplayName(context.l10n, canvas.name);
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _CanvasNameDialog(name: shown),
  );
  if (result != null && result.trim() != shown && context.mounted) {
    ref.read(canvasWorkspaceProvider.notifier).rename(canvas.id, result);
  }
}

class _CanvasNameDialog extends StatefulWidget {
  const _CanvasNameDialog({required this.name});
  final String name;

  @override
  State<_CanvasNameDialog> createState() => _CanvasNameDialogState();
}

class _CanvasNameDialogState extends State<_CanvasNameDialog> {
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.renameCanvas),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: kCanvasNameMax,
      decoration: InputDecoration(labelText: context.l10n.canvasName),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      TextButton(
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
        child: Text(context.l10n.save),
      ),
    ],
  );
}

class _CanvasManager extends ConsumerStatefulWidget {
  const _CanvasManager();

  @override
  ConsumerState<_CanvasManager> createState() => _CanvasManagerState();
}

class _CanvasManagerState extends ConsumerState<_CanvasManager> {
  final _scroll = ScrollController();
  final _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 打开时把当前画布滚进视野。各行高矮不一（词有几行、有没有角色），当前那张
  /// 排得太靠后还没建出来时，先按平均行高跳到附近，下一帧再对准。
  void _revealActive({bool estimated = false}) {
    if (!mounted || !_scroll.hasClients) return;
    final target = _activeKey.currentContext;
    if (target != null) {
      // 在上方就贴顶、在下方就贴底；本来就在视野里不动
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      return;
    }
    if (estimated) return;
    final position = _scroll.position;
    final workspace = ref.read(canvasWorkspaceProvider);
    final index = workspace.canvases.indexWhere(
      (canvas) => canvas.id == workspace.activeId,
    );
    final total = position.maxScrollExtent + position.viewportDimension;
    _scroll.jumpTo(
      (total * index / workspace.canvases.length -
              position.viewportDimension / 2)
          .clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealActive(estimated: true),
    );
  }

  void _delete(CanvasDraft canvas) {
    final notifier = ref.read(canvasWorkspaceProvider.notifier);
    final removed = notifier.remove(canvas.id);
    if (removed == null) return;
    hintSnack(
      context,
      context.l10n.deletedNamed(canvasDisplayName(context.l10n, canvas.name)),
      actionLabel: context.l10n.undo,
      onAction: () => notifier.restore(
        removed.canvas,
        removed.index,
        activate: removed.wasActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(canvasWorkspaceProvider);
    final canvases = workspace.canvases;
    Widget tile(CanvasDraft canvas, {bool pinned = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CanvasTile(
        key: canvas.id == workspace.activeId ? _activeKey : null,
        canvas: canvas,
        active: canvas.id == workspace.activeId,
        onTap: () {
          _selectCanvas(ref, canvas.id);
          Navigator.pop(context);
        },
        // 默认画布名字固定、删不掉:不给改名键,删除位换成图钉
        onHistory: () => showCanvasHistory(context, canvas),
        onRename: pinned ? null : () => _renameCanvas(context, ref, canvas),
        onDelete: pinned ? null : () => _delete(canvas),
      ),
    );
    return ConstrainedBox(
      // 高度随内容，封顶七成屏。模型弹层定高是怕横滑翻类时抽动，这里没有分页，
      // 画布少时不必留一大片空白。
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题与模型弹层同款，点标题看说明（与参数说明同一套）；
          // 关弹层同样靠下滑或点外面。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: HelpLabel(
                  text: context.l10n.canvases,
                  help: Help.canvas,
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            // 长按整块拾起拖动排序，与提示词预设页、角色、Vibe 同一套。
            // 默认画布放在不参与排序的表头里:拖不动它,别的也拖不到它上面。
            child: ReorderableListView.builder(
              scrollController: _scroll,
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              buildDefaultDragHandles: false,
              proxyDecorator: dragProxy,
              onReorderStart: dragStartHaptic,
              onReorderEnd: dragEndHaptic,
              onReorderItem: (from, to) => ref
                  .read(canvasWorkspaceProvider.notifier)
                  .reorder(from + 1, to + 1),
              header: tile(canvases.first, pinned: true),
              itemCount: canvases.length - 1,
              itemBuilder: (_, index) {
                final canvas = canvases[index + 1];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(canvas.id),
                  index: index,
                  child: tile(canvas),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.newCanvas),
                      onPressed: () {
                        _prepareUiSwitch(ref);
                        ref.read(canvasWorkspaceProvider.notifier).create();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(context.l10n.duplicateCurrent),
                      onPressed: () {
                        _prepareUiSwitch(ref);
                        ref
                            .read(canvasWorkspaceProvider.notifier)
                            .create(duplicate: true);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画布一行，样子同提示词预设页的 `_PresetTile`：当前那张描主色边、圆点实心，
/// 改名、删除直接摆在右边。名字下面三行各占一行：主提示词、角色、模型与参数，
/// 图标分别同创作页提示词卡、角色卡的卡头和高级设置入口。三行总在，卡片等高。
class _CanvasTile extends StatelessWidget {
  const _CanvasTile({
    super.key,
    required this.canvas,
    required this.active,
    required this.onTap,
    required this.onHistory,
    this.onRename,
    this.onDelete,
  });

  final CanvasDraft canvas;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onHistory;

  /// 默认画布为 null：名字固定，不显示改名键。
  final VoidCallback? onRename;

  /// 默认画布为 null：删除位换成一枚不可点的图钉。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 分过区的画布按拼好的那串预览,和发出去的一致
    final prompt = joinSections(
      canvas.prompts.sections,
      canvas.prompts.prompt,
      positive: true,
    );
    final characters = canvas.prompts.characters;
    final sampling = canvas.prompts.sampling;
    final preview = _previewStyle(context);
    return Material(
      // 弹层底色就是 surfaceContainerLow，卡片提一档才看得出边界。
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active
            ? BorderSide(color: scheme.primary, width: 1.4)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          selected: active,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: active ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        canvasDisplayName(context.l10n, canvas.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: context.l10n.history,
                      visualDensity: VisualDensity.compact,
                      onPressed: onHistory,
                      icon: Icon(
                        Icons.history,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (onRename != null)
                      IconButton(
                        tooltip: context.l10n.rename,
                        visualDensity: VisualDensity.compact,
                        onPressed: onRename,
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 19,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: context.l10n.delete,
                        visualDensity: VisualDensity.compact,
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 19,
                          color: scheme.error.withValues(alpha: .85),
                        ),
                      )
                    else
                      // 和删除键同样大小的格子,行里的按钮不会因此错位
                      Tooltip(
                        message: context.l10n.defaultCanvasLocked,
                        child: SizedBox.square(
                          dimension: 40,
                          child: Icon(
                            Icons.push_pin_outlined,
                            size: 18,
                            color: scheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
                _PreviewLine(
                  icon: Icons.subject,
                  child: Text(
                    prompt.isEmpty
                        ? context.l10n.noPromptYet
                        : prompt.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: preview.copyWith(
                      color: prompt.isEmpty
                          ? scheme.outline
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                _PreviewLine(
                  icon: Icons.group_outlined,
                  child: characters.isEmpty
                      ? Text(
                          context.l10n.noCharacters,
                          style: preview.copyWith(color: scheme.outline),
                        )
                      : _CharacterSummary(characters),
                ),
                if (sampling != null) ...[
                  const SizedBox(height: 3),
                  _PreviewLine(
                    icon: Icons.tune,
                    child: Text(
                      _samplingLine(sampling),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: preview.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 预览三行的字：比 bodySmall 大一号，tag 看得清，又不抢画布名。
TextStyle _previewStyle(BuildContext context) =>
    context.texts.bodySmall!.copyWith(fontSize: 13);

/// 模型与参数那一行：「NAI 4.5 Full · 28 步 · CFG 5 · Euler Ancestral · karras」，
/// 只报当前模型那一套，写法与画风推荐参数一致。
String _samplingLine(CanvasSampling s) =>
    '${modelName(s.model)} · ${recipeDetail(recipeOf(s.writeInto(const GenParams())))}';

/// 预览行：图标落在单选圆点那一列，正文与画布名左对齐。
///
/// 图标对准正文第一行：中线压在基线上方 0.28 个字号处（小写字母视觉中线略上，
/// 提示词几乎都是小写 tag）。基线按实际字体和字号量，不写死 —— MiSans 的基线
/// 比 Roboto 低，按行盒居中会看着偏高。
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  static const _iconSize = 15.0;

  @override
  Widget build(BuildContext context) {
    final style = _previewStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    final top = baseline - scaler.scale(style.fontSize!) * .28 - _iconSize / 2;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Padding(
              padding: EdgeInsets.only(top: top > 0 ? top : 0),
              child: Icon(icon, size: _iconSize, color: context.scheme.outline),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 角色这一行：只列名字，平分一行、各自省略，多于三个只列前三个，末尾报还剩
/// 几个。停用的压暗，与角色卡一致。
class _CharacterSummary extends StatelessWidget {
  const _CharacterSummary(this.characters);

  final List<CharacterPrompt> characters;

  static const _max = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final style = _previewStyle(
      context,
    ).copyWith(color: scheme.onSurfaceVariant);
    final dim = style.copyWith(color: scheme.outline);
    final shown = characters.take(_max).toList();
    final rest = characters.length - shown.length;
    return Row(
      children: [
        for (final (i, c) in shown.indexed) ...[
          if (i > 0) Text(' · ', style: dim),
          Flexible(
            child: Text(
              characterDisplayName(context.l10n, c.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: c.enabled ? style : dim,
            ),
          ),
        ],
        if (rest > 0) Text(' +$rest', style: dim),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/fast_scroll_handle.dart';
import '../../core/ui/lift_menu.dart';
import '../../core/ui/selection_bar.dart';
import '../../core/util/image_pick.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart';
import '../generate/display_names.dart';
import '../generate/widgets/common.dart';
import '../../l10n/l10n.dart';
import 'char_library.dart';
import '../../core/util/haptics.dart';

/// 角色参考图库(仅「我的」本地库)。纯图片预览网格:
/// 点卡 = 加入/移出生成面板(选中后左上角显示勾标),长按抬起菜单 = 重命名 / 删除,
/// 底部一行多选栏 = 清除 / 删除 / 确认选择。生成页导入的参考图会自动收藏在此。
class CharLibraryPage extends ConsumerStatefulWidget {
  const CharLibraryPage({super.key});

  @override
  ConsumerState<CharLibraryPage> createState() => _CharLibraryPageState();
}

class _CharLibraryPageState extends ConsumerState<CharLibraryPage> {
  /// 进入页面时的角色参考快照(「取消」放弃本次全部增删还原它)。
  late final List<CharRefItem> _snapshot;
  // 加入角色参考会因互斥停用 Vibe,快照一并保存,「取消」时连同还原。
  late final List<VibeItem> _vibesSnapshot;
  String _search = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _snapshot = List.of(ref.read(generateProvider).charRefs);
    _vibesSnapshot = List.of(ref.read(generateProvider).vibes);
  }

  CharLibrary get _lib => ref.read(charLibraryProvider.notifier);

  // ---- 勾选语义:已加入生成面板(库条目 id 即图片内容哈希,与生成项 imageHash 对齐)----

  String? _activeItemId(CharRefEntry e) {
    for (final r in ref.read(generateProvider).charRefs) {
      if (r.imageHash == e.id) return r.id;
    }
    return null;
  }

  Future<void> _toggle(CharRefEntry e) async {
    final activeId = _activeItemId(e);
    if (activeId != null) {
      ref.read(generateProvider.notifier).removeCharRef(activeId);
      setState(() {});
      return;
    }
    final bytes = await _lib.loadImageBytes(e);
    if (!mounted) return;
    if (bytes == null) {
      hintSnack(context, context.l10n.cantReadRef, icon: Icons.error_outline);
      return;
    }
    Haptics.selection();
    final stBefore = ref.read(generateProvider);
    final hadVibes = stBefore.enabledVibes > 0;
    final inpaintBlocked =
        stBefore.inpaint != null &&
        !crSupportsInpainting(stBefore.params.model);
    ref
        .read(generateProvider.notifier)
        .addCharRef(image: bytes, name: e.name, imageHash: e.id);
    if (inpaintBlocked) {
      hintSnack(
        context,
        context.l10n.charRefIgnoredInpaint,
        icon: Icons.block,
      );
    } else if (hadVibes) {
      hintSnack(
        context,
        context.l10n.refMutexVibePaused,
        icon: Icons.swap_horiz,
      );
    }
    setState(() {});
  }

  // ---- 底部批量操作(作用于已勾选 = 已加入生成的库条目)----

  List<CharRefEntry> _checkedEntries(List<CharRefEntry> all) => [
    for (final e in all)
      if (_activeItemId(e) != null) e,
  ];

  Future<void> _deleteChecked(List<CharRefEntry> checked) async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.deleteRefImage,
      message: context.l10n.deleteRefsBody(checked.length),
      confirmLabel: context.l10n.delete,
    );
    if (!ok || !mounted) return;
    for (final e in checked) {
      final activeId = _activeItemId(e);
      if (activeId != null) {
        ref.read(generateProvider.notifier).removeCharRef(activeId);
      }
      await _lib.delete(e.id);
    }
    if (mounted) setState(() {});
  }

  void _clearActive() {
    final notifier = ref.read(generateProvider.notifier);
    for (final r in [...ref.read(generateProvider).charRefs]) {
      notifier.removeCharRef(r.id);
    }
    setState(() {});
  }

  /// 返回键的动作:还原进入页面时的快照(放弃本次全部勾选增删,含被互斥停用的
  /// Vibe),回生成页。底栏那个键是「取消选择」——只清空,不退页,两回事。
  void _cancel() {
    ref.read(generateProvider.notifier)
      ..restoreCharRefs(_snapshot)
      ..restoreVibes(_vibesSnapshot);
    Navigator.of(context).pop();
  }

  /// 确认选择:点卡时已实时加入生成面板,这里直接返回。
  void _confirm() => Navigator.of(context).pop();

  // ---- 单卡长按菜单 ----

  Future<void> _lift(CharRefEntry e, Rect from) async {
    Haptics.medium();
    final l = context.l10n;
    final action = await showLiftMenu<String>(
      context,
      from: from,
      aspect: from.height > 0 ? from.width / from.height : 1.0,
      preview: _CharThumb(thumb: _lib.thumbOf(e)),
      actions: [
        (
          icon: Icons.drive_file_rename_outline,
          label: l.rename,
          value: 'rename',
        ),
      ],
      danger: (icon: Icons.delete_outline, label: l.delete, value: 'delete'),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _rename(e);
      case 'delete':
        await _deleteOne(e);
    }
  }

  Future<void> _rename(CharRefEntry e) async {
    final l = context.l10n;
    final ctrl = TextEditingController(text: refDisplayName(l, e.name));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.rename),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(isDense: true, hintText: l.refImageName),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (name != null &&
        name.trim().isNotEmpty &&
        name.trim() != refDisplayName(l, e.name)) {
      await _lib.rename(e.id, name);
    }
  }

  Future<void> _deleteOne(CharRefEntry e) async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.deleteRefImage,
      message: context.l10n.deleteRefBody(refDisplayName(context.l10n, e.name)),
      confirmLabel: context.l10n.delete,
    );
    if (!ok) return;
    final activeId = _activeItemId(e);
    if (activeId != null) {
      ref.read(generateProvider.notifier).removeCharRef(activeId);
    }
    await _lib.delete(e.id);
    if (mounted) setState(() {});
  }

  // ---- 导入(右上角 +)----

  Future<void> _importImages() async {
    final files = await pickImageFiles(context);
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    var n = 0;
    for (final f in files) {
      try {
        await _lib.importImageBytes(f.bytes, f.baseName);
        n++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _busy = false);
    hintSnack(
      context,
      context.l10n.refsAdded(n),
      icon: Icons.check_circle_outline,
    );
  }

  // ---- 列表数据 ----

  List<CharRefEntry> _visible(List<CharRefEntry> all) {
    final q = _search.trim().toLowerCase();
    final list = [
      for (final e in all)
        if (q.isEmpty || e.name.toLowerCase().contains(q)) e,
    ];
    list.sort((a, b) => b.recency.compareTo(a.recency));
    return list;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final all = ref.watch(charLibraryProvider).value;
    final refs = ref.watch(generateProvider).charRefs;
    final checked = all == null ? const <CharRefEntry>[] : _checkedEntries(all);

    return PopScope(
      // 返回 = 放弃本次全部增删(还原进入时的快照)。「确认选择」走的是
      // Navigator.pop,不经 maybePop,不会被这里拦下。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancel();
      },
      child: _scaffold(scheme, all, refs, checked),
    );
  }

  Widget _scaffold(
    ColorScheme scheme,
    List<CharRefEntry>? all,
    List<CharRefItem> refs,
    List<CharRefEntry> checked,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.charRefLibrary),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: context.l10n.importImage,
              icon: const Icon(Icons.add),
              onPressed: _importImages,
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.l10n.searchName,
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: context.pageControlFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Expanded(
            child: all == null
                ? const Center(child: CircularProgressIndicator())
                : _grid(_visible(all)),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(scheme, checked, refs),
    );
  }

  Widget _grid(List<CharRefEntry> list) {
    final scheme = context.scheme;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.face_retouching_natural,
              size: 44,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 10),
            Text(
              _search.isEmpty
                  ? context.l10n.noCharRefs
                  : context.l10n.noMatchingRefs,
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_search.isEmpty) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.charRefLibraryHint,
                style: context.texts.labelSmall!.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return FastScrollHandle(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.0,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final e = list[i];
          return _CharCard(
            checked: _activeItemId(e) != null,
            thumb: _lib.thumbOf(e),
            onTap: () => _toggle(e),
            onLift: (rect) => _lift(e, rect),
          );
        },
      ),
    );
  }

  Widget _bottomBar(
    ColorScheme scheme,
    List<CharRefEntry> checked,
    List<CharRefItem> refs,
  ) {
    final n = refs.length;
    return SelectionBar(
      // 全部移出后底栏也要留着:此时唯一的出口是返回键,而返回=还原快照,
      // 刚做的移出会被一并撤销 —— 没有「确认」就没法把移出落地。
      visible: n > 0 || _changedFromSnapshot(refs),
      compact: true,
      onClear: n == 0 ? null : _clearActive,
      destructive: SelectionIconButton(
        icon: Icons.delete_outline,
        tooltip: context.l10n.delete,
        color: scheme.error,
        onTap: checked.isEmpty ? null : () => _deleteChecked(checked),
      ),
      primary: FilledButton.icon(
        onPressed: _confirm,
        style: selectionPrimaryStyle(),
        icon: const Icon(Icons.check, size: 18),
        label: Text(
          n > 0
              ? context.l10n.confirmSelectionN(n)
              : context.l10n.confirmSelection,
        ),
      ),
    );
  }

  /// 相对进入页面时是否有增删(顺序也算)。
  bool _changedFromSnapshot(List<CharRefItem> now) {
    if (now.length != _snapshot.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (now[i].id != _snapshot[i].id) return true;
    }
    return false;
  }
}

/// 纯图片预览卡片:点卡 = 加入/移出生成;选中后左上角显示勾标;长按抬起菜单 = 重命名 / 删除。
class _CharCard extends StatelessWidget {
  const _CharCard({
    required this.checked,
    required this.thumb,
    required this.onTap,
    required this.onLift,
  });

  final bool checked;
  final File thumb;
  final VoidCallback onTap;
  final ValueChanged<Rect> onLift;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        // 边框放前景层:选中态加粗高亮只是绘制,不占布局。
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: checked
                ? scheme.primary.withValues(alpha: .85)
                : scheme.outlineVariant.withValues(alpha: .3),
            width: checked ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: () {
              if (globalRectOf(context) case final r?) onLift(r);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CharThumb(thumb: thumb),
                if (checked)
                  ColoredBox(color: scheme.primary.withValues(alpha: .16)),
                if (checked)
                  Positioned(top: 8, left: 8, child: _checkbox(scheme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkbox(ColorScheme scheme) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(Icons.check, size: 15, color: scheme.onPrimary),
    );
  }
}

/// 缩略图渲染(网格卡与长按抬起预览共用)。
class _CharThumb extends StatelessWidget {
  const _CharThumb({required this.thumb});

  final File thumb;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Image.file(
      thumb,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Icon(Icons.broken_image_outlined, color: scheme.outline),
      ),
    );
  }
}

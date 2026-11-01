import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart' show confirmDialog, hintSnack;
import '../tag_library.dart';
import '../tag_models.dart';

/// 类别管理:页签排序(拖动)、改名(内置类别也能改)、新建 / 编辑自定义类别、
/// 删除(自定义类别与场景、其他)。
/// 版式同标签池管理那张。
Future<void> showCategoryManagerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ManagerSheet(),
    );

class _ManagerSheet extends ConsumerWidget {
  const _ManagerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final lib = ref.watch(tagLibraryProvider).value ?? const TagLibraryState();
    final notifier = ref.read(tagLibraryProvider.notifier);
    final keys = lib.visibleTabKeys;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '类别',
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              // 顺序即顶栏页签的顺序:按住抓手即拖,整行长按也可拖
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 3,
                  child: child,
                ),
                onReorderItem: notifier.moveTab,
                itemCount: keys.length,
                itemBuilder: (context, i) =>
                    ReorderableDelayedDragStartListener(
                      key: ValueKey(keys[i]),
                      index: i,
                      child: _row(context, ref, lib, keys[i], i),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: OutlinedButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建类别'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    TagLibraryState lib,
    String key,
    int index,
  ) {
    final scheme = context.scheme;
    final codex = key == kCodexTabKey;
    final cat = codex ? null : tagCategoryByWebId(key);
    final def = cat == null ? null : tagCategoryDef(cat);
    final custom = cat?.isCustom ?? false;
    final removable = custom || kRemovableBuiltins.contains(key);
    // 自定义类别进完整的编辑面板(名称 / 图标 / 形状),内置的只改名
    void edit() =>
        custom ? _edit(context, ref, def!) : _rename(context, ref, lib, key);
    return ListTile(
      dense: true,
      onTap: edit,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: SizedBox(
              width: 30,
              height: 40,
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            codex ? Icons.menu_book_outlined : def!.icon,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
      title: Text(
        codex ? codexTabLabel() : def!.label,
        style: context.texts.bodyLarge,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cat != null)
            Text(
              '${lib.of(cat).length}',
              style: mono(context, size: 12, color: scheme.outline),
            ),
          IconButton(
            tooltip: custom ? '编辑' : '改名',
            icon: Icon(
              Icons.edit_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: edit,
          ),
          // 删除钮固定在行尾;角色、画风、法典不能删,留同宽的空位让各行对齐
          if (removable)
            IconButton(
              tooltip: '删除',
              icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
              onPressed: () => _remove(context, ref, lib, def!),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final v = await showCategoryEditSheet(context);
    if (v == null) return;
    final notifier = ref.read(tagLibraryProvider.notifier);
    // 和删掉的场景 / 其他同名:把原来那一类加回来
    final lib = ref.read(tagLibraryProvider).value;
    for (final d in kTagCategoryDefs) {
      if (d.label == v.label && (lib?.isRemoved(d.webId) ?? false)) {
        await notifier.restoreBuiltin(d.webId);
        return;
      }
    }
    await notifier.addCategory(
      label: v.label,
      iconName: v.iconName,
      layout: v.layout,
    );
  }

  /// 内置类别(含法典)改名:清空或改回原名 = 恢复原名。
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    TagLibraryState lib,
    String key,
  ) async {
    final current = key == kCodexTabKey
        ? codexTabLabel()
        : tagCategoryDef(tagCategoryByWebId(key)!).label;
    final input = TextEditingController(text: current);
    final scheme = context.scheme;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('改名'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 8,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            filled: true,
            fillColor: scheme.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name == null || !context.mounted) return;
    final label = name.trim();
    if (label.isNotEmpty &&
        label != current &&
        takenCategoryLabels(lib, except: key).contains(label)) {
      hintSnack(context, '已有同名类别', icon: Icons.error_outline);
      return;
    }
    await ref.read(tagLibraryProvider.notifier).renameBuiltin(key, label);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    TagCategoryDef def,
  ) async {
    final v = await showCategoryEditSheet(context, edit: def);
    if (v == null) return;
    await ref
        .read(tagLibraryProvider.notifier)
        .updateCategory(
          TagCategoryDef.custom(
            id: def.webId,
            label: v.label,
            iconName: v.iconName,
            layout: v.layout,
          ),
        );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    TagLibraryState lib,
    TagCategoryDef def,
  ) async {
    final n = lib.of(def.key).length;
    final builtin = !def.key.isCustom;
    final entries = n == 0 ? '这个类别还没有条目。' : '类别里的 $n 个条目会一起删除,不可恢复。';
    final ok = await confirmDialog(
      context,
      title: '删除「${def.label}」?',
      message: builtin
          ? '$entries\n之后新建一个叫「${kTagCategoryDefs.firstWhere((d) => d.key == def.key).label}」的类别,可以把它加回来。'
          : entries,
      confirmLabel: '删除',
    );
    if (!ok) return;
    final notifier = ref.read(tagLibraryProvider.notifier);
    builtin
        ? await notifier.removeBuiltin(def.key)
        : await notifier.removeCategory(def.key);
  }
}

typedef CategoryForm = ({String label, String iconName, TagCardLayout layout});

/// 页签上现有的名字(除了 [except] 那一类),起名查重用。删掉的场景 / 其他
/// 不算 —— 同名新建就是把它加回来。
Set<String> takenCategoryLabels(TagLibraryState lib, {String? except}) => {
  for (final k in lib.visibleTabKeys)
    if (k != except)
      k == kCodexTabKey
          ? codexTabLabel()
          : tagCategoryDef(tagCategoryByWebId(k)!).label,
};

/// 新建 / 编辑类别:名称、图标、预览图形状。取消返回 null。
Future<CategoryForm?> showCategoryEditSheet(
  BuildContext context, {
  TagCategoryDef? edit,
}) => showModalBottomSheet<CategoryForm>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _EditSheet(edit: edit),
);

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({this.edit});

  final TagCategoryDef? edit;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final _name = TextEditingController(text: widget.edit?.label ?? '');
  late String _icon = kTagCategoryIcons.containsKey(widget.edit?.iconName)
      ? widget.edit!.iconName!
      : kTagCategoryIcons.keys.first;
  late TagCardLayout _layout = widget.edit?.layout ?? TagCardLayout.square;

  static const _iconCols = 8;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _name.text.trim();
    if (label.isEmpty) return;
    final lib = ref.read(tagLibraryProvider).value ?? const TagLibraryState();
    if (takenCategoryLabels(lib, except: widget.edit?.webId).contains(label)) {
      hintSnack(context, '已有同名类别', icon: Icons.error_outline);
      return;
    }
    Navigator.pop(context, (label: label, iconName: _icon, layout: _layout));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final empty = _name.text.trim().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.edit == null ? '新建类别' : '编辑类别',
                style: context.texts.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              // 名称:左边是选中的图标,右边输入
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.solidFill(scheme.primaryContainer),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      kTagCategoryIcons[_icon],
                      size: 24,
                      color: context.onSolidFill(scheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: widget.edit == null,
                      maxLength: 8,
                      style: context.texts.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '类别名称',
                        counterText: '',
                        filled: true,
                        fillColor: scheme.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _label('图标'),
              GridView.count(
                crossAxisCount: _iconCols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final e in kTagCategoryIcons.entries)
                    _iconCell(scheme, e.key, e.value),
                ],
              ),
              const SizedBox(height: 18),
              _label('预览图'),
              Row(
                children: [
                  for (final l in TagCardLayout.values) ...[
                    if (l != TagCardLayout.values.first)
                      const SizedBox(width: 8),
                    Expanded(child: _layoutCell(scheme, l)),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: empty ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(widget.edit == null ? '创建' : '保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: context.texts.labelLarge!.copyWith(
        color: context.scheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _iconCell(ColorScheme scheme, String key, IconData icon) {
    final sel = key == _icon;
    return Material(
      color: sel ? scheme.primary : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _icon = key),
        child: Icon(
          icon,
          size: 20,
          color: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 预览图形状:一块按比例画的小框 + 名字;无图画一道横线。
  Widget _layoutCell(ColorScheme scheme, TagCardLayout l) {
    final sel = l == _layout;
    final fg = sel
        ? context.onSolidFill(scheme.primary)
        : scheme.onSurfaceVariant;
    return Material(
      color: sel
          ? context.solidFill(scheme.primaryContainer)
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _layout = l),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              SizedBox(
                height: 34,
                child: Center(
                  child: l == TagCardLayout.none
                      ? Icon(Icons.notes, size: 22, color: fg)
                      : Container(
                          width: 34 * (l.aspect > 1 ? 1 : l.aspect),
                          height: 34 / (l.aspect > 1 ? l.aspect : 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: fg, width: 1.6),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.label,
                style: context.texts.labelMedium!.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

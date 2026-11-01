import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/image_pick.dart';
import '../../core/util/png_meta.dart';
import '../generate/widgets/common.dart' show hintSnack, sharedAxisRoute;
import '../import/image_metadata.dart';
import '../import/metadata_detail_page.dart';

class _Item {
  _Item({required this.name, required this.bytes, this.meta});

  final String name;
  final Uint8List bytes;
  final ImageMetadata? meta;
  bool selected = false;

  String get baseName => name.replaceAll(RegExp(r'\.[^.]+$'), '');
}

enum _BatchMode { clean, custom }

/// 图片元数据(工具箱页签):批量选图看生成参数,点开完整详情/角色识别/去导入,
/// 勾选后清除或覆写元数据,处理结果存回系统相册。
class MetadataToolView extends ConsumerStatefulWidget {
  const MetadataToolView({super.key});

  @override
  ConsumerState<MetadataToolView> createState() => _MetadataToolViewState();
}

class _MetadataToolViewState extends ConsumerState<MetadataToolView> {
  final List<_Item> _items = [];
  final _customPrompt = TextEditingController();
  _BatchMode _mode = _BatchMode.clean;
  bool _loading = false;
  bool _processing = false;
  (int, int)? _progress; // (当前, 总数)

  @override
  void dispose() {
    _customPrompt.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await pickImageFiles(context);
    if (files.isEmpty || !mounted) return;
    setState(() {
      _loading = true;
      _progress = (0, files.length);
    });
    for (var i = 0; i < files.length; i++) {
      try {
        final bytes = files[i].bytes;
        final meta = await extractImageMetadata(bytes);
        _items.add(_Item(name: files[i].name, bytes: bytes, meta: meta));
      } catch (_) {}
      if (!mounted) return;
      setState(() => _progress = (i + 1, files.length));
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _progress = null;
    });
  }

  int get _selectedCount => _items.where((f) => f.selected).length;

  Future<void> _saveSelected() async {
    final sel = _items.where((f) => f.selected).toList();
    if (sel.isEmpty || _processing) return;
    if (_mode == _BatchMode.custom && _customPrompt.text.trim().isEmpty) {
      hintSnack(context, '先填要覆写的提示词', icon: Icons.edit_outlined);
      return;
    }
    final ok = await Gal.hasAccess() || await Gal.requestAccess();
    if (!ok) {
      if (mounted) hintSnack(context, '未获相册权限', icon: Icons.error_outline);
      return;
    }
    setState(() {
      _processing = true;
      _progress = (0, sel.length);
    });
    var saved = 0, failed = 0;
    for (var i = 0; i < sel.length; i++) {
      try {
        final out = _mode == _BatchMode.clean
            ? await cleanImagePng(sel[i].bytes)
            : await writeCustomMetadataPng(
                sel[i].bytes,
                _customPrompt.text.trim(),
              );
        final suffix = _mode == _BatchMode.clean ? '_clean' : '_custom';
        await Gal.putImageBytes(out, name: '${sel[i].baseName}$suffix');
        saved++;
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
      setState(() => _progress = (i + 1, sel.length));
    }
    if (!mounted) return;
    setState(() {
      _processing = false;
      _progress = null;
    });
    hintSnack(
      context,
      failed == 0 ? '已保存 $saved 张到相册' : '已保存 $saved 张 · $failed 张失败',
      icon: failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final hasFiles = _items.isNotEmpty;
    final allSelected = hasFiles && _items.every((f) => f.selected);
    return Column(
      children: [
        if (hasFiles)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
            child: Row(
              children: [
                Text(
                  '${_items.length} 张',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    for (final f in _items) {
                      f.selected = !allSelected;
                    }
                  }),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
                IconButton(
                  onPressed: _loading ? null : _pick,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 21,
                  ),
                  tooltip: '添加图片',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        if (_progress case (final cur, final total)?)
          LinearProgressIndicator(
            value: total > 0 ? cur / total : null,
            minHeight: 2,
          ),
        Expanded(child: hasFiles ? _grid(scheme) : _empty(scheme)),
        if (_selectedCount > 0) _batchBar(scheme),
      ],
    );
  }

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 44,
            color: scheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            '查看生成参数 · 批量清除或覆写元数据',
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loading ? null : _pick,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined, size: 19),
            label: const Text('选择图片'),
          ),
        ],
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) => _thumb(scheme, _items[i]),
    );
  }

  Widget _thumb(ColorScheme scheme, _Item f) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        sharedAxisRoute(
          f.meta == null
              ? _NoMetaPage(item: f)
              : MetadataDetailPage(
                  meta: f.meta!,
                  bytes: f.bytes,
                  fileName: f.name,
                  standalone: true,
                ),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              f.bytes,
              fit: BoxFit.cover,
              cacheWidth: 256,
              errorBuilder: (_, _, _) => ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
            ),
          ),
          if (f.selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
            ),
          Positioned(
            top: 5,
            left: 5,
            child: InkWell(
              onTap: () => setState(() => f.selected = !f.selected),
              customBorder: const CircleBorder(),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: f.selected
                      ? scheme.primary
                      : Colors.black.withValues(alpha: .35),
                  border: f.selected
                      ? null
                      : Border.all(color: Colors.white.withValues(alpha: .8)),
                ),
                child: f.selected
                    ? Icon(Icons.check, size: 15, color: scheme.onPrimary)
                    : null,
              ),
            ),
          ),
          if (f.meta != null)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'META',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _batchBar(ColorScheme scheme) {
    return Docked(
      child: Material(
        color: context.raisedFill(scheme.surfaceContainer),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_mode == _BatchMode.custom) ...[
                  TextField(
                    controller: _customPrompt,
                    style: mono(context, size: 12, weight: FontWeight.w400),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      hintText: '要覆写进图片的提示词…',
                      hintStyle: TextStyle(color: scheme.outline, fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    SegmentedButton<_BatchMode>(
                      segments: const [
                        ButtonSegment(
                          value: _BatchMode.clean,
                          label: Text('清除'),
                        ),
                        ButtonSegment(
                          value: _BatchMode.custom,
                          label: Text('覆写'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _processing ? null : _saveSelected,
                      icon: _processing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt, size: 18),
                      label: Text('存相册 ($_selectedCount)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 无元数据的图:只给基础信息,避免详情页空转。
class _NoMetaPage extends StatelessWidget {
  const _NoMetaPage({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(title: const Text('图片信息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(item.bytes, fit: BoxFit.contain),
          ),
          const SizedBox(height: 14),
          Text(
            '${item.name} · 未识别到元数据',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

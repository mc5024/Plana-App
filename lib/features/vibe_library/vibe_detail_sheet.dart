import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../generate/generate_state.dart';
import '../generate/widgets/common.dart'
    show ParamSlider, confirmDialog, hintSnack;
import 'naiv4vibe_codec.dart' show kEncodingKeyLabel;
import 'vibe_library.dart';
import '../../l10n/l10n.dart';
import '../generate/display_names.dart';

/// 「已编码」状态色(功能绿)—— 单一来源见 [FixedSemantic]。
const _encOkColor = FixedSemantic.ok;

/// 库条目详情:大图 + 名称/默认参数编辑 + 编码状态(仅显示有无)+ 导出/删除/添加到生成。
/// pop(true) = 已添加到生成(由库页收尾:snack + 返回生成页)。
class VibeDetailSheet extends ConsumerStatefulWidget {
  const VibeDetailSheet({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<VibeDetailSheet> createState() => _VibeDetailSheetState();
}

class _VibeDetailSheetState extends ConsumerState<VibeDetailSheet> {
  double? _strength; // 本地滑条值(null = 未初始化,取 entry 默认)
  double? _ie;
  Timer? _saveTimer;
  Future<Uint8List?>? _imageFuture;
  Future<List<({String modelKey, double? ie})>>? _encFuture;

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  VibeEntry? get _entry {
    final list = ref.watch(vibeLibraryProvider).value;
    if (list == null) return null;
    for (final e in list) {
      if (e.id == widget.entryId) return e;
    }
    return null;
  }

  void _scheduleSave(VibeEntry e) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      ref
          .read(vibeLibraryProvider.notifier)
          .updateMeta(
            e.id,
            defaultStrength: _strength,
            defaultInfoExtracted: _ie,
          );
    });
  }

  Future<void> _rename(VibeEntry e) async {
    final shown = vibeDisplayName(context.l10n, e.name);
    final ctl = TextEditingController(text: shown);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.rename),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != shown) {
      await ref.read(vibeLibraryProvider.notifier).updateMeta(e.id, name: name);
    }
  }

  Future<void> _export(VibeEntry e) async {
    try {
      final text = await ref.read(vibeLibraryProvider.notifier).exportText(e);
      final safe = e.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = await FilePicker.platform.saveFile(
        fileName: '$safe.naiv4vibe',
        bytes: utf8.encode(text),
      );
      if (path != null && mounted) {
        hintSnack(
          context,
          context.l10n.exportedName('$safe.naiv4vibe'),
          icon: Icons.check_circle_outline,
        );
      }
    } catch (err) {
      if (mounted) {
        hintSnack(
          context,
          context.l10n.exportFailed('$err'),
          icon: Icons.error_outline,
        );
      }
    }
  }

  Future<void> _delete(VibeEntry e) async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.deleteVibe,
      message: context.l10n.deleteVibeBody(
        vibeDisplayName(context.l10n, e.name),
      ),
      confirmLabel: context.l10n.delete,
    );
    if (!ok || !mounted) return;
    await ref.read(vibeLibraryProvider.notifier).delete(e.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addToGenerate(VibeEntry e) async {
    final gen = ref.read(generateProvider);
    final dup = gen.vibes.any(
      (v) =>
          (e.id == v.sourceId) ||
          (v.imageHash != null && v.imageHash == e.imageHash),
    );
    if (dup) {
      hintSnack(
        context,
        context.l10n.alreadyInGenerate,
        icon: Icons.info_outline,
      );
      return;
    }
    final data = await ref
        .read(vibeLibraryProvider.notifier)
        .loadForGenerate(e);
    if (!mounted) return;
    if (data == null) {
      hintSnack(context, context.l10n.cantReadVibe, icon: Icons.error_outline);
      return;
    }
    final id = ref
        .read(generateProvider.notifier)
        .addVibe(
          image: data.image,
          name: e.name,
          imageHash: data.imageHash,
          strength: _strength ?? e.defaultStrength ?? 0.6,
          infoExtracted: data.image != null
              ? (_ie ?? e.defaultInfoExtracted ?? 1.0)
              : data.fixedInfoExtracted,
          encodedByModel: data.encodedByModel,
          sourceId: e.id,
        );
    if (id.isEmpty) {
      hintSnack(
        context,
        context.l10n.vibeNoImageOrEncoding,
        icon: Icons.error_outline,
      );
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final e = _entry;
    if (e == null) {
      // 条目被删/库未就绪:空壳(删除路径已主动 pop)
      return const SizedBox(height: 120);
    }
    _strength ??= e.defaultStrength ?? 0.6;
    _ie ??= e.defaultInfoExtracted ?? 1.0;
    _imageFuture ??= ref.read(vibeLibraryProvider.notifier).loadImageBytes(e);
    _encFuture ??= ref.read(vibeLibraryProvider.notifier).encodingList(e);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _preview(scheme),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    vibeDisplayName(context.l10n, e.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.rename,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _rename(e),
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Text(
              [
                _fmtTime(e.createdAt),
                if (e.sizeBytes > 0)
                  '${(e.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                if (!e.hasImage) context.l10n.encodingOnlyNoImage,
              ].join(' · '),
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 14),
            ParamSlider(
              label: context.l10n.defaultStrength,
              value: _strength!,
              divisions: 100,
              onChanged: (v) {
                setState(() => _strength = v);
                _scheduleSave(e);
              },
            ),
            const SizedBox(height: 4),
            if (e.hasImage)
              ParamSlider(
                label: context.l10n.defaultInfoExtracted,
                value: _ie!,
                divisions: 100,
                onChanged: (v) {
                  setState(() => _ie = v);
                  _scheduleSave(e);
                },
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  context.l10n.ieFixedNoImage,
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _encodings(e, scheme),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _addToGenerate(e),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 19),
              label: Text(context.l10n.addToGenerate),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _export(e),
                    icon: const Icon(Icons.ios_share, size: 17),
                    label: Text(context.l10n.export),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _delete(e),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: Text(context.l10n.delete),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: scheme.surfaceContainerHigh,
        constraints: const BoxConstraints(maxHeight: 240),
        width: double.infinity,
        child: FutureBuilder<Uint8List?>(
          future: _imageFuture,
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) {
              return SizedBox(
                height: 130,
                child: Center(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.data_object,
                          size: 34,
                          color: scheme.outline,
                        ),
                ),
              );
            }
            return Image.memory(bytes, fit: BoxFit.contain);
          },
        ),
      ),
    );
  }

  /// 编码状态:有无 + 已编码则逐条列出「模型 · 信息提取值」。
  /// 清单 = 文件自带 ∪ 内容寻址缓存(见 `encodingList`),所以用过之后新编出
  /// 来的也算数 —— 库列表那边走同一口径合并,两处不会再对不上。
  Widget _encodings(VibeEntry e, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: FutureBuilder(
        future: _encFuture,
        builder: (context, snap) {
          final waiting = snap.connectionState == ConnectionState.waiting;
          final list = snap.data ?? const <({String modelKey, double? ie})>[];
          final has = list.isNotEmpty;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.memory, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.encodings,
                    style: context.texts.labelLarge!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (waiting)
                    Text(
                      context.l10n.checking,
                      style: context.texts.labelMedium!.copyWith(
                        color: scheme.outline,
                      ),
                    )
                  else ...[
                    Icon(
                      has ? Icons.check_circle : Icons.remove_circle_outline,
                      size: 16,
                      color: has ? _encOkColor : scheme.outline,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      has
                          ? context.l10n.encodedN(list.length)
                          : context.l10n.notEncoded,
                      style: context.texts.labelMedium!.copyWith(
                        color: has ? _encOkColor : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              // 每条编码一行:左边模型,右边它当时的信息提取值
              for (final it in list) _encRow(it, scheme),
            ],
          );
        },
      ),
    );
  }

  Widget _encRow(({String modelKey, double? ie}) it, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          const SizedBox(width: 26),
          Text(
            kEncodingKeyLabel[it.modelKey] ?? it.modelKey,
            style: context.texts.labelMedium!.copyWith(color: scheme.onSurface),
          ),
          const Spacer(),
          Text(
            // 文件里的老编码可能没记 params,IE 就是未知
            it.ie == null ? 'IE —' : 'IE ${it.ie!.toStringAsFixed(2)}',
            style: mono(context, size: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

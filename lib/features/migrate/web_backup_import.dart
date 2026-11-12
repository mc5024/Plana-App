import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/import_picker.dart';
import '../char_library/char_library.dart';
import '../generate/prompt_presets.dart';
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../vibe_library/vibe_library.dart';
import 'web_backup.dart';

/// 一次导入的结果:逐类结果行(标签, 数值)+ 失败原因。
typedef WebBackupImportOutcome = ({
  List<(String, String)> rows,
  List<String> errors,
});

/// 弹「自选导入内容」→ 按勾选把 web 备份落进各库。用户取消返回 null。
///
/// 面板里列全五类,勾什么导什么。[notice] 用于说明来源。
///
/// [onProgress] 报「哪一类、第几条/共几条」:vibe 带图,几百条要跑上几分钟,
/// 没有动静的话用户会以为卡死了去杀进程。
Future<WebBackupImportOutcome?> runWebBackupImport(
  BuildContext context,
  WidgetRef ref,
  WebBackup b, {
  String? notice,
  void Function(String label, int done, int total)? onProgress,
}) async {
  final tagLib = ref.read(tagLibraryProvider.notifier);
  final cats = b.tagCategories();

  // 冲突预检:按 id 数出与本地重合的条数(与「导入即覆盖」同口径)。
  // 库还没水合完就当 0 —— 预览少个数字无妨,不值得为它卡住面板。
  final localVibeIds = {
    for (final e in ref.read(vibeLibraryProvider).value ?? const []) e.id,
  };
  final vibeConflict = [
    for (final v in b.vibes)
      if (v['id'] is String && localVibeIds.contains(v['id'])) v,
  ].length;
  final localPresetIds = {
    for (final p in ref.read(promptPresetsProvider).value?.presets ?? const [])
      p.id,
  };
  final presetConflict = b.presets
      .where((p) => localPresetIds.contains(p.id))
      .length;

  final picked = await showImportPicker(
    context,
    title: '选择要导入的内容',
    notice: notice,
    options: [
      ImportOption(
        key: 'vibe',
        label: 'Vibe',
        detail: '${b.vibes.length} 条',
        enabled: b.vibes.isNotEmpty,
        conflict: vibeConflict,
      ),
      ImportOption(
        key: 'cr',
        label: '角色参考',
        detail: '${b.crs.length} 张',
        enabled: b.crs.isNotEmpty,
        note: '重复图自动跳过',
      ),
      ImportOption(
        key: 'oc',
        label: '灵感库 · 角色',
        detail: '${b.ocs.length} 条',
        enabled: b.ocs.isNotEmpty,
        conflict: tagLib.previewMerge({'character': b.ocs}).overwrite,
        note: '内嵌预览图不导入',
      ),
      ImportOption(
        key: 'artist',
        label: '灵感库 · 画风',
        detail: '${b.artists.length} 条',
        enabled: b.artists.isNotEmpty,
        conflict: tagLib.previewMerge({'artist-style': b.artists}).overwrite,
      ),
      ImportOption(
        key: 'preset',
        label: '提示词预设',
        detail: '${b.presets.length} 条',
        enabled: b.presets.isNotEmpty || b.activePresetId != null,
        conflict: presetConflict,
      ),
    ],
  );
  if (picked == null || picked.isEmpty) return null;

  final rows = <(String, String)>[];
  final errors = <String>[];

  // Vibe:逐条转成 .naiv4vibe JSON 交给库导入(自带编码同时灌进缓存)
  if (picked.contains('vibe') && b.vibes.isNotEmpty) {
    try {
      final got = await ref
          .read(vibeLibraryProvider.notifier)
          .importVibeRaws(
            b.naiv4Raws(),
            onProgress: (d, t) => onProgress?.call('Vibe', d, t),
          );
      rows.add(('Vibe', '${got.length} 条'));
    } catch (e) {
      errors.add('Vibe 导入失败: $e');
    }
  }

  // 角色参考:一图一条;库内按图字节哈希去重,重复导入不会堆副本
  if (picked.contains('cr') && b.crs.isNotEmpty) {
    var n = 0;
    final lib = ref.read(charLibraryProvider.notifier);
    for (final c in b.crs) {
      try {
        await lib.importImageBytes(c.bytes, c.name);
        n++;
      } catch (e) {
        errors.add('角色参考「${c.name}」失败: $e');
      }
      onProgress?.call('角色参考', n, b.crs.length);
    }
    rows.add(('角色参考', '$n 张'));
  }

  // 画师串 / OC → 灵感库(一次 mergeBackup 合并两类,只落一次盘)
  final pickedCats = {
    for (final e in cats.entries)
      if (picked.contains(e.key == 'character' ? 'oc' : 'artist'))
        e.key: e.value,
  };
  if (pickedCats.isNotEmpty) {
    try {
      final stat = await tagLib.mergeBackup(pickedCats);
      for (final d in kTagCategoryDefs) {
        if (stat[d.key] case final s?) {
          rows.add(('灵感库 · ${d.label}', '新增 ${s.added} · 覆盖 ${s.updated}'));
        }
      }
    } catch (e) {
      errors.add('灵感库导入失败: $e');
    }
  }

  // 预设:按 id upsert,备份里用着的那一档顺带换到当前画布上
  if (picked.contains('preset') &&
      (b.presets.isNotEmpty || b.activePresetId != null)) {
    try {
      final n = await ref
          .read(promptPresetsProvider.notifier)
          .importPresets(b.presets, activeId: b.activePresetId);
      rows.add(('提示词预设', '$n 条'));
    } catch (e) {
      errors.add('预设导入失败: $e');
    }
  }

  return (rows: rows, errors: errors);
}

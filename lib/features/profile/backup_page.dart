import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/import_picker.dart';
import '../../core/util/file_read.dart';
import '../generate/widgets/common.dart' show hintSnack;
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../migrate/web_backup.dart';
import '../migrate/web_backup_import.dart';
import '../vibe_library/vibe_cloud_sync.dart';
import '../vibe_library/vibe_library.dart';
import 'widgets/settings_ui.dart';

/// 云端条数与更新时间(unix 秒)。
typedef _Cloud = ({int count, int updatedAt});

Future<T?> _orNull<T>(Future<T> f) async {
  try {
    return await f;
  } catch (_) {
    return null;
  }
}

/// 备份:灵感库 / Vibe 云端备份与恢复、从文件导入(web 全量备份或灵感库
/// 分类 JSON)、灵感库按分类导出 JSON(格式与 web tag-manager 一致)。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  /// backup | restore | import | `export:<webId>`
  String? _busy;

  /// 云端状态;null 且不在读取中 = 读取失败。
  _Cloud? _tagCloud;
  _Cloud? _vibeCloud;
  bool _tagLoading = true;
  bool _vibeLoading = true;

  /// 进行中的进度(「Vibe 42/300」「推送 Vibe 3/48」),空 = 还没开始报数。
  String _progress = '';

  /// 本次进页最近一次导入的结果。
  WebBackupImportOutcome? _result;

  @override
  void initState() {
    super.initState();
    _loadTagCloud();
    _loadVibeCloud();
  }

  Future<void> _loadTagCloud() async {
    final session = ref.read(botSessionProvider).value;
    _Cloud? c;
    if (session != null) {
      try {
        final r = await ref
            .read(backendClientProvider)
            .getTagBackup(session.sessionId);
        c = (
          count: r.counts.values.fold(0, (a, b) => a + b),
          updatedAt: r.updatedAt,
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _tagCloud = c;
        _tagLoading = false;
      });
    }
  }

  Future<void> _loadVibeCloud() async {
    final session = ref.read(botSessionProvider).value;
    _Cloud? c;
    if (session != null) {
      try {
        c = await ref
            .read(backendClientProvider)
            .getUserVibesState(session.sessionId);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _vibeCloud = c;
        _vibeLoading = false;
      });
    }
  }

  Future<void> _run(String tag, Future<void> Function(String sid) op) async {
    if (_busy != null) return;
    final session = ref.read(botSessionProvider).value;
    if (session == null) {
      hintSnack(context, '暂未开放', icon: Icons.cloud_off_outlined);
      return;
    }
    setState(() {
      _busy = tag;
      _progress = '';
    });
    try {
      await op(session.sessionId);
    } on BackendException catch (e) {
      if (mounted) hintSnack(context, e.message, icon: Icons.error_outline);
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = '';
        });
      }
    }
  }

  void _tick(String label, int done, int total) {
    if (mounted) setState(() => _progress = '$label $done/$total');
  }

  /// 内置四类(含改名)+ 自定义类别。
  List<TagCategoryDef> _defs(TagLibraryState? lib) => [
    for (final d in kTagCategoryDefs) tagCategoryDef(d.key),
    ...?lib?.customDefs,
  ];

  String _detailLine(Map<TagCategory, String> parts) => [
    for (final d in _defs(ref.read(tagLibraryProvider).value))
      if (parts[d.key] case final String s) '${d.label} $s',
  ].join(' · ');

  // ---- 云端 ----

  String _errText(Object e) => e is BackendException ? e.message : '$e';

  void _report(String verb, List<String> done, List<String> failed) {
    if (!mounted) return;
    hintSnack(
      context,
      failed.isEmpty
          ? '$verb完成:${done.join(' · ')}'
          : [...done, ...failed].join(' · '),
      icon: failed.isEmpty
          ? Icons.cloud_done_outlined
          : Icons.warning_amber_outlined,
    );
  }

  Future<void> _vibeLog(String sid, String action, int count, String detail) =>
      ref
          .read(backendClientProvider)
          .recordBackupLog(
            sessionId: sid,
            device: 'Plana App',
            action: action,
            count: count,
            detail: detail,
          );

  Future<void> _cloudBackup() => _run('backup', (sid) async {
    final lib = ref.read(tagLibraryProvider.notifier);
    final categories = lib.encodeBackup();
    final custom = lib.encodeCustom();
    final tagN =
        categories.values.fold(0, (a, l) => a + l.length) +
        (custom['items'] as Map).values.fold<int>(
          0,
          (a, l) => a + (l as List).length,
        );
    final vibeN = ref.read(vibeLibraryProvider).value?.length ?? 0;
    if (tagN == 0 && vibeN == 0) {
      hintSnack(context, '本地没有可备份的内容', icon: Icons.info_outline);
      return;
    }
    final tagCloudN = _tagCloud?.count ?? 0;
    final picked = await showImportPicker(
      context,
      title: '选择要备份的内容',
      confirmLabel: '备份',
      mergeHint: false,
      options: [
        ImportOption(
          key: 'tag',
          label: '灵感库',
          detail: '$tagN 条',
          enabled: tagN > 0,
          note: tagCloudN > 0
              ? '整体覆盖云端现有的 $tagCloudN 条 · 本机预览图不上传'
              : '本机预览图不上传',
        ),
        ImportOption(
          key: 'vibe',
          label: 'Vibe',
          detail: '$vibeN 条',
          enabled: vibeN > 0,
          note: '未改动的自动跳过',
        ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final client = ref.read(backendClientProvider);
    final done = <String>[], failed = <String>[];

    if (picked.contains('tag')) {
      setState(() => _progress = '上传灵感库…');
      try {
        await client.uploadTagBackup(
          sessionId: sid,
          categories: categories,
          custom: custom,
        );
        final state = ref.read(tagLibraryProvider).value;
        final detail = _detailLine({
          for (final d in _defs(state))
            d.key: '${state?.of(d.key).length ?? 0}',
        });
        await client.recordBackupLog(
          sessionId: sid,
          device: 'Plana App',
          action: 'backup',
          count: tagN,
          detail: 'tag-manager 备份 $detail',
        );
        done.add('灵感库 $tagN 条');
      } catch (e) {
        failed.add('灵感库失败:${_errText(e)}');
      }
    }

    if (picked.contains('vibe')) {
      try {
        final r = await ref
            .read(vibeCloudSyncProvider)
            .pushAll(onProgress: (cur, total) => _tick('推送 Vibe', cur, total));
        final detail = [
          if (r.pushed > 0) '上传 ${r.pushed}',
          if (r.skipped > 0) '跳过 ${r.skipped}',
          if (r.failed > 0) '失败 ${r.failed}',
        ].join('、');
        final text = detail.isEmpty ? '已是最新' : detail;
        await _vibeLog(sid, 'backup', r.pushed, text);
        (r.failed > 0 ? failed : done).add('Vibe $text');
      } catch (e) {
        failed.add('Vibe 失败:${_errText(e)}');
      }
    }

    await Future.wait([_loadTagCloud(), _loadVibeCloud()]);
    _report('备份', done, failed);
  });

  Future<void> _cloudRestore() => _run('restore', (sid) async {
    setState(() => _progress = '比对中…');
    final client = ref.read(backendClientProvider);
    final sync = ref.read(vibeCloudSyncProvider);
    final (tag, vibe) = await (
      _orNull(client.getTagBackup(sid)),
      _orNull(sync.previewRestore()),
    ).wait;
    if (!mounted) return;
    setState(() => _progress = '');

    var tagN = 0;
    for (final v in [
      ...?tag?.categories.values,
      ...?(tag?.custom?['items'] as Map?)?.values,
    ]) {
      if (v is List) tagN += v.length;
    }
    final tagLib = ref.read(tagLibraryProvider.notifier);
    final tagOver = tag == null
        ? 0
        : tagLib.previewMerge(tag.categories, custom: tag.custom).overwrite;
    final vibeN = vibe == null
        ? 0
        : vibe.willAdd.length + vibe.willOverwrite.length;
    if (tagN == 0 && vibeN == 0) {
      hintSnack(
        context,
        tag == null || vibe == null ? '读取云端失败' : '没有需要恢复的内容',
        icon: Icons.cloud_off_outlined,
      );
      return;
    }
    final picked = await showImportPicker(
      context,
      title: '选择要恢复的内容',
      confirmLabel: '恢复',
      options: [
        ImportOption(
          key: 'tag',
          label: '灵感库',
          detail: tag == null ? '读取失败' : (tagN > 0 ? '$tagN 条' : '暂无备份'),
          enabled: tagN > 0,
          conflict: tagOver,
        ),
        ImportOption(
          key: 'vibe',
          label: 'Vibe',
          detail: vibe == null ? '读取失败' : (vibeN > 0 ? '$vibeN 条' : '已一致'),
          enabled: vibeN > 0,
          conflict: vibe?.willOverwrite.length ?? 0,
        ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final done = <String>[], failed = <String>[];

    if (picked.contains('tag') && tag != null) {
      setState(() => _progress = '恢复灵感库…');
      try {
        final stat = await tagLib.mergeBackup(
          tag.categories,
          custom: tag.custom,
        );
        final detail = _detailLine({
          for (final e in stat.entries)
            e.key: '+${e.value.added}/✎${e.value.updated}',
        });
        await client.recordBackupLog(
          sessionId: sid,
          device: 'Plana App',
          action: 'restore',
          count: tagN,
          detail: 'tag-manager 恢复 $detail',
        );
        final added = stat.values.fold(0, (a, s) => a + s.added);
        final updated = stat.values.fold(0, (a, s) => a + s.updated);
        done.add('灵感库 新增 $added、覆盖 $updated');
      } catch (e) {
        failed.add('灵感库失败:${_errText(e)}');
      }
    }

    if (picked.contains('vibe')) {
      try {
        final r = await sync.restoreAll(
          onProgress: (cur, total) => _tick('拉取 Vibe', cur, total),
        );
        final detail = [
          if (r.added > 0) '新增 ${r.added}',
          if (r.updated > 0) '覆盖 ${r.updated}',
          if (r.skipped > 0) '跳过 ${r.skipped}',
        ].join('、');
        final text = detail.isEmpty ? '已是最新' : detail;
        await _vibeLog(sid, 'restore', r.added + r.updated, text);
        done.add('Vibe $text');
      } catch (e) {
        failed.add('Vibe 失败:${_errText(e)}');
      }
    }

    await Future.wait([_loadTagCloud(), _loadVibeCloud()]);
    _report('恢复', done, failed);
  });

  // ---- 文件导入 ----

  Future<void> _importFile() async {
    if (_busy != null) return;
    // withData: false —— 全量备份可能上百 MB,拿路径流式解析,别整份读进内存
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any, // 备份是 .json,但各家文件管理器的 mime 过滤不可靠
    );
    final file = res?.files.firstOrNull;
    if (file == null || !mounted) return;
    setState(() {
      _busy = 'import';
      _progress = '';
      _result = null;
    });
    try {
      final j = await readPickedJson(file);
      if (!mounted) return;
      final WebBackupImportOutcome? out;
      if (j is Map<String, dynamic> &&
          j['meta'] is Map &&
          (j['meta'] as Map)['identifier'] == kWebBackupIdentifier) {
        out = await _importWebBackup(WebBackup.fromDecoded(j));
      } else if (j is Map<String, dynamic> &&
          j['identifier'] == kBackupFileIdentifier) {
        final f = parseBackupFile(j);
        out = await _importTagFile(f.cat, f.items);
      } else {
        throw const FormatException('不是可识别的备份文件');
      }
      if (out == null || !mounted) return; // 自选面板里取消
      setState(() => _result = out);
      hintSnack(
        context,
        out.errors.isEmpty ? '导入完成' : '导入完成,${out.errors.length} 项失败',
        icon: out.errors.isEmpty ? Icons.check : Icons.warning_amber_outlined,
      );
    } on FormatException catch (e) {
      if (mounted) {
        hintSnack(
          context,
          e.message.isEmpty ? '不是有效的 JSON 文件' : e.message,
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (mounted) hintSnack(context, '导入失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = '';
        });
      }
    }
  }

  /// web「设置 → 数据备份」的全量备份:五类自选导入。
  Future<WebBackupImportOutcome?> _importWebBackup(WebBackup b) {
    if (b.isEmpty) throw const FormatException('这份 web 备份里没有可导入的内容');
    return runWebBackupImport(
      context,
      ref,
      b,
      onProgress: (label, done, total) {
        if (mounted) setState(() => _progress = '$label $done/$total');
      },
    );
  }

  /// 灵感库单分类 JSON(本 app / web tag-manager 导出):落进文件写明的分类。
  Future<WebBackupImportOutcome?> _importTagFile(
    TagCategory cat,
    List<Map<String, dynamic>> items,
  ) async {
    final custom = ref.read(tagLibraryProvider).value?.customDefs ?? const [];
    if (cat.isCustom && !custom.any((d) => d.key == cat)) {
      throw const FormatException('文件里的自定义分类在本机不存在');
    }
    if (items.isEmpty) throw const FormatException('文件里没有条目');
    final lib = ref.read(tagLibraryProvider.notifier);
    final d = tagCategoryDef(cat);
    final label = '灵感库 · ${d.label}';
    final payload = {d.webId: items};
    final picked = await showImportPicker(
      context,
      title: '选择要导入的内容',
      options: [
        ImportOption(
          key: d.webId,
          label: label,
          detail: '${items.length} 条',
          conflict: lib.previewMerge(payload).overwrite,
        ),
      ],
    );
    if (picked == null || picked.isEmpty) return null;
    final s = (await lib.mergeBackup(payload))[cat];
    return (
      rows: [(label, '新增 ${s?.added ?? 0} · 覆盖 ${s?.updated ?? 0}')],
      errors: const <String>[],
    );
  }

  // ---- 文件导出 ----

  Future<void> _exportFile(TagCategoryDef d) async {
    if (_busy != null) return;
    setState(() => _busy = 'export:${d.webId}');
    try {
      final items = ref.read(tagLibraryProvider.notifier).encodeCategory(d.key);
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final text = const JsonEncoder.withIndent('  ').convert(
        buildBackupFile(d.key, items, exportedAt: now.toIso8601String()),
      );
      final path = await FilePicker.platform.saveFile(
        fileName: 'tag-manager-${d.webId}-$date.json',
        bytes: utf8.encode(text),
      );
      if (path != null && mounted) {
        hintSnack(
          context,
          '已导出 ${items.length} 个${d.label}',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (mounted) hintSnack(context, '导出失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _cloudStatus(bool authed, bool loading, _Cloud? c) {
    if (!authed) return '暂未开放';
    if (loading) return '读取中…';
    if (c == null) return '读取失败';
    if (c.updatedAt <= 0) return '暂无备份';
    final t = DateTime.fromMillisecondsSinceEpoch(c.updatedAt * 1000);
    final d = DateTime.now().difference(t);
    final when = d.inMinutes < 1
        ? '刚刚'
        : d.inHours < 1
        ? '${d.inMinutes} 分钟前'
        : d.inDays < 1
        ? '${d.inHours} 小时前'
        : d.inDays < 30
        ? '${d.inDays} 天前'
        : '${t.year}-${t.month.toString().padLeft(2, '0')}-'
              '${t.day.toString().padLeft(2, '0')}';
    return '${c.count} 条 · $when';
  }

  /// 动作行在跑时的右侧值:进度或「处理中…」。
  String? _busyValue(String tag) =>
      _busy == tag ? (_progress.isEmpty ? '处理中…' : _progress) : null;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(tagLibraryProvider).value;
    final authed = ref.watch(botSessionProvider).value != null;
    final idle = _busy == null;
    return Scaffold(
      appBar: AppBar(title: const Text('备份')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          const SettingsLabel('云端备份'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.lightbulb_outline,
                title: '灵感库',
                value: _cloudStatus(authed, _tagLoading, _tagCloud),
              ),
              SettingsRow(
                icon: Icons.palette_outlined,
                title: 'Vibe',
                value: _cloudStatus(authed, _vibeLoading, _vibeCloud),
              ),
              SettingsRow(
                icon: Icons.cloud_upload_outlined,
                title: '备份到云端',
                value: _busyValue('backup'),
                onTap: idle ? _cloudBackup : null,
              ),
              SettingsRow(
                icon: Icons.cloud_download_outlined,
                title: '从云端恢复',
                value: _busyValue('restore'),
                onTap: idle ? _cloudRestore : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsLabel('导入'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.folder_open_outlined,
                title: '选择备份文件',
                value: _busyValue('import'),
                onTap: idle ? _importFile : null,
              ),
            ],
          ),
          if (_result case final r?) ...[
            const SizedBox(height: 10),
            _ResultCard(r),
          ],
          const SizedBox(height: 16),
          const SettingsLabel('导出'),
          SettingsCard(
            children: [
              for (final d in _defs(lib))
                _ExportRow(
                  def: d,
                  count: lib?.of(d.key).length ?? 0,
                  busy: _busy == 'export:${d.webId}',
                  enabled: idle,
                  onExport: () => _exportFile(d),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// 导出行:分类 + 条数 + 「导出」(存储管理「可清理」行同款)。
class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.def,
    required this.count,
    required this.busy,
    required this.enabled,
    required this.onExport,
  });

  final TagCategoryDef def;
  final int count;
  final bool busy;
  final bool enabled;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          Icon(def.icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              def.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$count 条',
            style: mono(context, size: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 32,
            width: 64,
            child: busy
                ? const Center(child: _Spinner())
                : TextButton(
                    onPressed: enabled && count > 0 ? onExport : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('导出'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 导入结果:逐类结果行 + 失败原因。
class _ResultCard extends StatelessWidget {
  const _ResultCard(this.result);

  final WebBackupImportOutcome result;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '导入结果',
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              for (final (k, v) in result.rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(k, style: context.texts.bodyMedium)),
                      Text(
                        v,
                        style: mono(
                          context,
                          size: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final e in result.errors)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    e,
                    style: context.texts.bodySmall!.copyWith(
                      color: scheme.error,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

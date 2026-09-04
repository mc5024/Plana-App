import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/bot_session_store.dart';
import '../../../core/net/backend_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/import_picker.dart';
import '../../../core/util/file_read.dart';
import '../../generate/widgets/common.dart' show confirmDialog, hintSnack;
import '../../migrate/web_backup.dart';
import '../../migrate/web_backup_import.dart';
import '../public_tags.dart';
import '../tag_library.dart';
import '../tag_models.dart';
import 'prompt_chips.dart';

/// 灵感页的三个弹层:条目详情、标签池管理、数据备份
/// (新建/编辑走全屏 TagEditorPage)。

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => child,
    );

Widget _sheetTitle(BuildContext context, IconData icon, String title) {
  return Row(
    children: [
      Icon(icon, size: 20, color: context.scheme.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: context.texts.titleMedium!.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

// ---- 详情 ----

Future<void> showTagDetailSheet(BuildContext context, TagEntry e) =>
    _sheet(context, _DetailSheet(e));

class _DetailSheet extends ConsumerWidget {
  const _DetailSheet(this.e);

  final TagEntry e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    // 作者:查得到昵称就显示昵称,查不到显示那串 QQ 号(目录没加载出来时同理)。
    final author = e.createdBy?.trim();
    final authorLabel = author == null || author.isEmpty
        ? null
        : (ref.watch(tagAuthorNamesProvider).value ?? const {})[author] ??
              author;
    // 定高封顶:正文(分类标签 + 正负向芯片)在内部滚,标题与「复制」常驻
    // 两端 —— 长词条不再把按钮顶出屏幕、整张弹层跟着无限拉长(法典详情同款)。
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.name,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (e.aliases.isNotEmpty)
                    Expanded(
                      child: Text(
                        e.aliases.join(' / '),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (authorLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                child: Text(
                  '作者 $authorLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final t in e.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '#$t',
                                style: context.texts.labelSmall,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _block(context, '正向', e.positive),
                    if (e.negative.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _block(context, '负面', e.negative),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: e.positive));
                  if (context.mounted) {
                    Navigator.pop(context);
                    hintSnack(context, '已复制提示词', icon: Icons.copy);
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制提示词'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context, String label, String text) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelMedium!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        // 芯片流不可选字,整段复制走底部「复制提示词」
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: PromptChips.single(text),
        ),
      ],
    );
  }
}

// ---- 标签池管理 ----

Future<void> showTagPoolSheet(
  BuildContext context,
  WidgetRef ref,
  TagCategory cat,
) => _sheet(context, _PoolSheet(cat));

class _PoolSheet extends ConsumerStatefulWidget {
  const _PoolSheet(this.cat);

  final TagCategory cat;

  @override
  ConsumerState<_PoolSheet> createState() => _PoolSheetState();
}

class _PoolSheetState extends ConsumerState<_PoolSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    final ok = await ref
        .read(tagLibraryProvider.notifier)
        .addPoolTag(widget.cat, t);
    if (!mounted) return;
    if (ok) {
      _input.clear();
    } else {
      hintSnack(context, '标签已存在', icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final def = tagCategoryDef(widget.cat);
    final lib = ref.watch(tagLibraryProvider).value;
    final notifier = ref.read(tagLibraryProvider.notifier);
    final tags = lib?.knownTags(widget.cat) ?? const <String>[];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: _sheetTitle(context, Icons.tune, '${def.label}标签池'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '新建标签…',
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: _add, child: const Text('添加')),
              ],
            ),
          ),
          Flexible(
            child: tags.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      '暂无标签',
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: tags.length,
                    itemBuilder: (context, i) {
                      final t = tags[i];
                      final n = notifier.poolTagUsage(widget.cat, t);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.sell_outlined, size: 18),
                        title: Text(t),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$n',
                              style: mono(
                                context,
                                size: 12,
                                color: n > 0 ? scheme.primary : scheme.outline,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: scheme.error,
                              ),
                              onPressed: () async {
                                final ok =
                                    n == 0 ||
                                    await confirmDialog(
                                      context,
                                      title: '删除标签「$t」?',
                                      message: '$n 个条目会摘掉该标签,条目本身保留。',
                                      confirmLabel: '删除',
                                    );
                                if (ok) {
                                  await notifier.removePoolTag(widget.cat, t);
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---- 批量贴标签:选一个标签(可现场新建) ----

Future<String?> pickTagSheet(
  BuildContext context,
  WidgetRef ref,
  TagCategory cat,
) => _sheet<String>(context, _TagPickSheet(cat));

class _TagPickSheet extends ConsumerStatefulWidget {
  const _TagPickSheet(this.cat);

  final TagCategory cat;

  @override
  ConsumerState<_TagPickSheet> createState() => _TagPickSheetState();
}

class _TagPickSheetState extends ConsumerState<_TagPickSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final tags =
        ref.watch(tagLibraryProvider).value?.knownTags(widget.cat) ??
        const <String>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: _sheetTitle(context, Icons.sell_outlined, '添加标签'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '新建标签…',
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isNotEmpty) Navigator.pop(context, t);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () {
                    final t = _input.text.trim();
                    if (t.isNotEmpty) Navigator.pop(context, t);
                  },
                  child: const Text('使用'),
                ),
              ],
            ),
          ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tags)
                    ActionChip(
                      label: Text(t),
                      shape: const StadiumBorder(),
                      onPressed: () => Navigator.pop(context, t),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- 数据备份 ----

Future<void> showTagBackupSheet(BuildContext context, WidgetRef ref) =>
    _sheet(context, const _BackupSheet());

class _BackupSheet extends ConsumerStatefulWidget {
  const _BackupSheet();

  @override
  ConsumerState<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<_BackupSheet> {
  String? _busy; // backup | restore
  bool _loading = true;

  /// 云端各类计数与更新时间(拉不到 = 未授权/无备份)。
  Map<String, int> _cloudCounts = const {};
  int _cloudUpdatedAt = 0;

  @override
  void initState() {
    super.initState();
    _loadCloud();
  }

  /// 打开即拉一次云端状态,好让本地/云端并排对照(对齐 web loadStats)。
  Future<void> _loadCloud() async {
    final session = ref.read(botSessionProvider).value;
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final r = await ref
          .read(backendClientProvider)
          .getTagBackup(session.sessionId);
      if (!mounted) return;
      setState(() {
        _cloudCounts = r.counts;
        _cloudUpdatedAt = r.updatedAt;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(String tag, Future<void> Function(String sid) op) async {
    if (_busy != null) return;
    final session = ref.read(botSessionProvider).value;
    if (session == null) {
      hintSnack(context, '数据备份需要 Bot 授权', icon: Icons.cloud_off_outlined);
      return;
    }
    setState(() => _busy = tag);
    try {
      await op(session.sessionId);
    } on BackendException catch (e) {
      if (mounted) hintSnack(context, e.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _detailLine(Map<TagCategory, String> parts) => [
    for (final d in kTagCategoryDefs)
      if (parts[d.key] case final String s) '${d.label} $s',
  ].join(' · ');

  Future<void> _upload() => _run('backup', (sid) async {
    final lib = ref.read(tagLibraryProvider.notifier);
    final categories = lib.encodeBackup();
    final n = categories.values.fold(0, (a, l) => a + l.length);
    final cloudTotal = _cloudCounts.values.fold(0, (a, b) => a + b);
    final ok = await confirmDialog(
      context,
      title: '上传备份?',
      message: cloudTotal > 0
          ? '本地 $n 个条目将整体覆盖云端现有的 $cloudTotal 个(本机预览图不随备份上传)。'
          : '本地 $n 个条目将上传为云端备份(本机预览图不随备份上传)。',
      confirmLabel: '上传',
    );
    if (!ok) return;
    final client = ref.read(backendClientProvider);
    await client.uploadTagBackup(sessionId: sid, categories: categories);
    final detail = _detailLine({
      for (final d in kTagCategoryDefs)
        d.key: '${categories[d.webId]?.length ?? 0}',
    });
    await client.recordBackupLog(
      sessionId: sid,
      device: 'Plana App',
      action: 'backup',
      count: n,
      detail: 'tag-manager 备份 $detail',
    );
    await _loadCloud();
    if (mounted) {
      hintSnack(context, '已上传 $n 个条目', icon: Icons.cloud_done_outlined);
    }
  });

  Future<void> _restore() => _run('restore', (sid) async {
    final client = ref.read(backendClientProvider);
    final r = await client.getTagBackup(sid);
    var n = 0;
    for (final v in r.categories.values) {
      if (v is List) n += v.length;
    }
    if (n == 0) {
      if (mounted) {
        hintSnack(context, '云端暂无备份', icon: Icons.cloud_off_outlined);
      }
      return;
    }
    if (!mounted) return;
    final lib = ref.read(tagLibraryProvider.notifier);
    // 恢复前算清「覆盖 / 新增」,别让人在不知情下被整包盖掉
    final pre = lib.previewMerge(r.categories);
    final ok = await confirmDialog(
      context,
      title: pre.overwrite > 0 ? '恢复将覆盖本地数据' : '恢复备份?',
      message:
          '将覆盖本地 ${pre.overwrite} 个,新增 ${pre.add} 个'
          '(按 id 合并,本地独有的条目保留)。',
      confirmLabel: '继续恢复',
    );
    if (!ok) return;
    final stat = await lib.mergeBackup(r.categories);
    final detail = _detailLine({
      for (final e in stat.entries)
        e.key: '+${e.value.added}/✎${e.value.updated}',
    });
    await client.recordBackupLog(
      sessionId: sid,
      device: 'Plana App',
      action: 'restore',
      count: n,
      detail: 'tag-manager 恢复 $detail',
    );
    await _loadCloud();
    if (mounted) {
      hintSnack(
        context,
        '已恢复:新增 ${pre.add} 个 · 覆盖 ${pre.overwrite} 个',
        icon: Icons.cloud_done_outlined,
      );
    }
  });

  // ---- 本地 JSON 导出 / 导入(格式与 web 一致,可双端互导) ----

  Future<void> _exportFile(TagCategoryDef d) async {
    if (_busy != null) return;
    setState(() => _busy = 'file');
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

  Future<void> _importFile(TagCategoryDef d) async {
    if (_busy != null) return;
    // withData: false —— 全量备份可能上百 MB,拿路径流式解析,别整份读进内存
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final file = res?.files.firstOrNull;
    if (file == null || !mounted) return;
    setState(() => _busy = 'file');
    try {
      final j = await readPickedJson(file);
      if (j is! Map<String, dynamic>) {
        throw const FormatException('不是有效的 JSON 备份文件');
      }
      final lib = ref.read(tagLibraryProvider.notifier);

      // web「设置 → 数据备份」的全量备份:走与专用导入页**同一套**编排 ——
      // 面板里五类全列出来,勾什么导什么,不因为入口在灵感库就砍掉别的类。
      if (j['meta'] is Map &&
          (j['meta'] as Map)['identifier'] == kWebBackupIdentifier) {
        final wb = WebBackup.fromDecoded(j);
        if (wb.isEmpty) {
          throw const FormatException('这份 web 备份里没有可导入的内容');
        }
        if (!mounted) return;
        final out = await runWebBackupImport(
          context,
          ref,
          wb,
          notice: '这是 web 端的全量备份文件,五类内容都可在此导入。',
        );
        if (out != null && mounted) {
          hintSnack(
            context,
            out.errors.isEmpty
                ? '导入完成:${out.rows.map((r) => '${r.$1} ${r.$2}').join(' · ')}'
                : '导入完成,${out.errors.length} 项失败',
            icon: out.errors.isEmpty
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
          );
        }
        return;
      }

      // 本 app / web tag-manager 导出的单分类备份:仍按当前分类校验
      final parsed = parseBackupFile(j);
      if (parsed.cat != d.key) {
        throw FormatException(
          '分类不匹配:文件是「${tagCategoryDef(parsed.cat).label}」,当前是「${d.label}」',
        );
      }
      if (parsed.items.isEmpty) {
        if (mounted) hintSnack(context, '文件里没有条目', icon: Icons.info_outline);
        return;
      }
      final payload = {d.webId: parsed.items};

      if (!mounted) return;
      final picked = await showImportPicker(
        context,
        title: '选择要导入的内容',
        options: [
          for (final def in kTagCategoryDefs)
            if (payload[def.webId] case final List items)
              ImportOption(
                key: def.webId,
                label: def.label,
                detail: '${items.length} 条',
                conflict: lib.previewMerge({def.webId: items}).overwrite,
              ),
        ],
      );
      if (picked == null || picked.isEmpty || !mounted) return;

      final sel = {
        for (final e in payload.entries)
          if (picked.contains(e.key)) e.key: e.value,
      };
      final pre = lib.previewMerge(sel);
      await lib.mergeBackup(sel);
      if (mounted) {
        hintSnack(
          context,
          '已导入:新增 ${pre.add} 个 · 覆盖 ${pre.overwrite} 个',
          icon: Icons.check_circle_outline,
        );
      }
    } on FormatException catch (e) {
      if (mounted) hintSnack(context, e.message, icon: Icons.error_outline);
    } catch (e) {
      if (mounted) hintSnack(context, '导入失败:$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _updatedText() {
    if (_cloudUpdatedAt <= 0) return '云端暂无备份';
    final t = DateTime.fromMillisecondsSinceEpoch(_cloudUpdatedAt * 1000);
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
    return '云端备份于 $when';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final lib = ref.watch(tagLibraryProvider).value;
    final localTotal = lib?.entries.length ?? 0;
    final cloudTotal = _cloudCounts.values.fold(0, (a, b) => a + b);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sheetTitle(context, Icons.cloud_outlined, '数据备份'),
                ),
                if (_loading || _busy != null)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _loading ? '正在读取云端状态…' : _updatedText(),
              style: context.texts.labelMedium!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            // 云端整包:恢复 / 备份
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy != null ? null : _restore,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: Text(
                      cloudTotal > 0 ? '恢复 ($cloudTotal)' : '恢复',
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy != null ? null : _upload,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text('备份 ($localTotal)', maxLines: 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '本地文件',
                  style: context.texts.labelLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '按分类导出 / 导入 JSON,与网页端互通',
                    style: context.texts.labelSmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 每类一张卡:本地/云端计数 + 明确的导出/导入按钮
            for (final d in kTagCategoryDefs) ...[
              _categoryCard(
                d,
                lib?.of(d.key).length ?? 0,
                _cloudCounts[d.webId],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(TagCategoryDef d, int local, int? cloud) {
    final scheme = context.scheme;
    final cloudText = cloud == null ? '云端 —' : '云端 $cloud';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(d.icon, size: 19, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.label,
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '本地 $local · $cloudText',
                  style: context.texts.labelSmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _fileBtn(
            icon: Icons.file_download_outlined,
            tooltip: '导出 $local 个',
            onTap: _busy != null || local == 0 ? null : () => _exportFile(d),
          ),
          _fileBtn(
            icon: Icons.file_upload_outlined,
            tooltip: '导入',
            onTap: _busy != null ? null : () => _importFile(d),
          ),
        ],
      ),
    );
  }

  Widget _fileBtn({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    final scheme = context.scheme;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 21,
              color: enabled ? scheme.primary : scheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

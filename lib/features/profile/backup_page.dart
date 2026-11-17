import 'dart:async' show unawaited;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/google_drive.dart';
import '../../core/store/storage_stats.dart' show fmtBytes;
import '../../core/theme/app_theme.dart';
import '../../core/ui/import_picker.dart';
import '../../core/util/document_save.dart';
import '../../core/util/file_read.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;
import '../inspiration/tag_cloud_backup.dart';
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../migrate/web_backup.dart';
import '../migrate/web_backup_import.dart';
import '../vibe_library/vibe_cloud_sync.dart';
import '../vibe_library/vibe_library.dart';
import 'cloud_backup_job.dart';
import 'drive_backup.dart';
import 'local_backup.dart';
import 'widgets/settings_ui.dart';
import '../../l10n/l10n.dart';

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
  /// 本地文件的导入 / 导出在跑:import | export。云端备份 / 恢复见 [cloudJobProvider]。
  String? _busy;

  /// 云端状态;null 且不在读取中 = 读取失败。
  _Cloud? _tagCloud;
  _Cloud? _vibeCloud;
  bool _tagLoading = true;
  bool _vibeLoading = true;

  /// 云端硬盘最新那份备份的两块;[_driveRead] = 读过且成功。
  ({DriveSection? tags, DriveSection? vibes})? _drive;
  bool _driveLoading = false;
  bool _driveRead = false;

  /// 进行中的进度(「Vibe 42/300」「推送 Vibe 3/48」),空 = 还没开始报数。
  String _progress = '';

  /// 本次进页最近一次导入的结果。
  WebBackupImportOutcome? _result;

  @override
  void initState() {
    super.initState();
    _loadTagCloud();
    _loadVibeCloud();
    _loadDrive();
    // 离开页面时跑完的那次:回来时补一句结果
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showJobResult(ref.read(cloudJobProvider));
    });
  }

  void _showJobResult(CloudJobState job) {
    final r = job.result;
    if (r == null) return;
    ref.read(cloudJobProvider.notifier).takeResult();
    hintSnack(
      context,
      r.text,
      icon: r.ok ? Icons.cloud_done_outlined : Icons.warning_amber_outlined,
    );
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

  /// 已授权时返回会话 id;未授权提示一句返回 null。
  String? _sessionOrHint() {
    final session = ref.read(botSessionProvider).value;
    if (session == null) {
      hintSnack(
        context,
        context.l10n.notAvailableYet,
        icon: Icons.cloud_off_outlined,
      );
    }
    return session?.sessionId;
  }

  bool get _idle => _busy == null && !ref.read(cloudJobProvider).busy;

  void _tick(String label, int done, int total) {
    if (mounted) setState(() => _progress = '$label $done/$total');
  }

  /// 灵感库的进度:total 为 0 的是没有计数的阶段(「上传灵感库…」)。
  void _tickTag(String label, int done, int total) {
    if (total > 0) return _tick(label, done, total);
    if (mounted) setState(() => _progress = '$label…');
  }

  // ---- 云端 ----

  /// 选好内容交给 [cloudJobProvider] 跑:离开页面、切到后台照常进行。
  Future<void> _cloudBackup() async {
    if (!_idle) return;
    final sid = _sessionOrHint();
    if (sid == null) return;
    final tagN = ref.read(tagLibraryProvider).value?.entries.length ?? 0;
    final vibeList = ref.read(vibeLibraryProvider).value ?? const [];
    if (tagN == 0 && vibeList.isEmpty) {
      hintSnack(context, '本地没有可备份的内容', icon: Icons.info_outline);
      return;
    }
    final picBytes = await ref.read(tagCloudBackupProvider).localPreviewBytes();
    if (!mounted) return;
    final vibeBytes = vibeList
        .where((e) => e.needsPush)
        .fold(0, (a, e) => a + e.sizeBytes);
    final over = picBytes > kPreviewQuotaBytes;
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
          size: picBytes > 0 ? '预览 ${fmtBytes(picBytes)}' : null,
          enabled: tagN > 0 && !over,
          note: !over && tagCloudN > 0 ? '覆盖云端现有 $tagCloudN 条' : null,
          warning: over ? '超过 ${fmtBytes(kPreviewQuotaBytes)} 上限' : null,
        ),
        ImportOption(
          key: 'vibe',
          label: 'Vibe',
          detail: '${vibeList.length} 条',
          size: vibeBytes > 0 ? '要上传 ${fmtBytes(vibeBytes)}' : '无改动',
          enabled: vibeList.isNotEmpty,
        ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    unawaited(
      ref
          .read(cloudJobProvider.notifier)
          .backup(
            sid,
            inspiration: picked.contains('tag'),
            vibes: picked.contains('vibe'),
          ),
    );
  }

  Future<void> _cloudRestore() async {
    if (!_idle) return;
    final sid = _sessionOrHint();
    if (sid == null) return;
    setState(() {
      _busy = 'restore-check';
      _progress = '比对中…';
    });
    final client = ref.read(backendClientProvider);
    final (tag, vibe) = await (
      _orNull(client.getTagBackup(sid)),
      _orNull(ref.read(vibeCloudSyncProvider).previewRestore()),
    ).wait;
    if (!mounted) return;
    setState(() {
      _busy = null;
      _progress = '';
    });

    var tagN = 0;
    for (final v in [
      ...?tag?.categories.values,
      ...?(tag?.custom?['items'] as Map?)?.values,
    ]) {
      if (v is List) tagN += v.length;
    }
    final tagOver = tag == null
        ? 0
        : ref
              .read(tagLibraryProvider.notifier)
              .previewMerge(tag.categories, custom: tag.custom)
              .overwrite;
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
    unawaited(
      ref
          .read(cloudJobProvider.notifier)
          .restore(
            sid,
            inspiration: picked.contains('tag') && tag != null
                ? (
                    categories: tag.categories,
                    custom: tag.custom,
                    pools: tag.pools,
                    codexFavorites: tag.codexFavorites,
                  )
                : null,
            inspirationCount: tagN,
            vibes: picked.contains('vibe'),
            vibeCount: vibeN,
          ),
    );
  }

  // ---- Google 云端硬盘 ----

  Future<void> _loadDrive() async {
    if (ref.read(googleDriveAuthProvider) == null) return;
    setState(() => _driveLoading = true);
    ({DriveSection? tags, DriveSection? vibes})? st;
    var ok = false;
    try {
      st = await ref.read(driveBackupProvider).status();
      ok = true;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _drive = st;
        _driveRead = ok;
        _driveLoading = false;
      });
    }
  }

  /// 没连就先连;连上(或本来就连着)返回 true。
  Future<bool> _ensureDrive() async {
    if (ref.read(googleDriveAuthProvider) != null) return true;
    setState(() => _busy = 'drive-connect');
    var ok = false;
    try {
      ok = await ref.read(googleDriveAuthProvider.notifier).connect();
      if (!ok && mounted) {
        hintSnack(context, '已取消', icon: Icons.info_outline);
      }
    } on DriveException catch (e) {
      if (mounted) hintSnack(context, e.message, icon: Icons.error_outline);
    } catch (e) {
      if (mounted) {
        hintSnack(context, 'Google 登录失败:$e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (ok && mounted) unawaited(_loadDrive());
    return ok && mounted;
  }

  Future<void> _driveAccount() async {
    if (!_idle) return;
    if (ref.read(googleDriveAuthProvider) == null) {
      await _ensureDrive();
      return;
    }
    final ok = await confirmDialog(
      context,
      title: '断开 Google 账号',
      message: '云端硬盘里的备份会保留,重新连接同一账号即可恢复。',
      confirmLabel: '断开',
    );
    if (!ok || !mounted) return;
    await ref.read(googleDriveAuthProvider.notifier).disconnect();
    if (mounted) {
      setState(() {
        _drive = null;
        _driveRead = false;
      });
    }
  }

  /// 比对阶段的进度:整体百分比。
  void _tickDrive(String label, int done, int total) {
    if (mounted) {
      setState(
        () => _progress = total > 0
            ? '比对中 ${(done * 100 / total).floor()}%'
            : '比对中…',
      );
    }
  }

  Future<void> _driveBackup() async {
    if (!_idle) return;
    final tagN = ref.read(tagLibraryProvider).value?.entries.length ?? 0;
    final vibeN = ref.read(vibeLibraryProvider).value?.length ?? 0;
    if (tagN == 0 && vibeN == 0) {
      hintSnack(context, '本地没有可备份的内容', icon: Icons.info_outline);
      return;
    }
    if (!await _ensureDrive()) return;
    setState(() {
      _busy = 'drive-backup-check';
      _progress = '比对中…';
    });
    DriveBackupPlan? plan;
    try {
      plan = await ref.read(driveBackupProvider).plan(onProgress: _tickDrive);
    } catch (e) {
      if (mounted) {
        hintSnack(
          context,
          e is DriveException ? e.message : '读取云端硬盘失败:$e',
          icon: Icons.cloud_off_outlined,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = '';
        });
      }
    }
    if (plan == null) return;
    if (!mounted) return plan.drive.close();
    final free = plan.free;
    final pic = plan.previewBytes, vb = plan.vibeBytes;
    bool fits(int n) => free == null || n <= free;
    final full = free == null ? null : '云端硬盘剩余 ${fmtBytes(free)},放不下';
    final picked = await showImportPicker(
      context,
      title: '选择要备份的内容',
      confirmLabel: '备份',
      mergeHint: false,
      options: [
        ImportOption(
          key: 'tag',
          label: '灵感库',
          detail: '${plan.tagCount} 条',
          size: pic > 0 ? '要上传预览 ${fmtBytes(pic)}' : null,
          enabled: plan.tagCount > 0 && fits(pic),
          warning: fits(pic) ? null : full,
        ),
        ImportOption(
          key: 'vibe',
          label: 'Vibe',
          detail: '${plan.vibes.length} 条',
          size: vb > 0 ? '要上传 ${fmtBytes(vb)}' : '无改动',
          enabled: plan.vibes.isNotEmpty && fits(vb),
          warning: fits(vb) ? null : full,
        ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) {
      return plan.drive.close();
    }
    final need =
        (picked.contains('tag') ? pic : 0) + (picked.contains('vibe') ? vb : 0);
    if (!fits(need)) {
      hintSnack(
        context,
        '云端硬盘剩余 ${fmtBytes(free!)},这次要传 ${fmtBytes(need)}',
        icon: Icons.cloud_off_outlined,
      );
      return plan.drive.close();
    }
    unawaited(
      ref
          .read(cloudJobProvider.notifier)
          .driveBackup(
            plan,
            inspiration: picked.contains('tag'),
            vibes: picked.contains('vibe'),
          ),
    );
  }

  Future<void> _driveRestore() async {
    if (!_idle) return;
    if (!await _ensureDrive()) return;
    setState(() {
      _busy = 'drive-restore-check';
      _progress = '读取中…';
    });
    DriveSnapshot? snap;
    var failed = false;
    try {
      snap = await ref.read(driveBackupProvider).snapshot();
    } catch (e) {
      failed = true;
      if (mounted) {
        hintSnack(context, switch (e) {
          DriveException(:final message) ||
          FormatException(:final message) => message,
          _ => '读取云端硬盘失败:$e',
        }, icon: Icons.cloud_off_outlined);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = '';
        });
      }
    }
    if (snap == null) {
      if (!failed && mounted) {
        hintSnack(context, '云端硬盘里还没有备份', icon: Icons.info_outline);
      }
      return;
    }
    if (!mounted) return snap.drive.close();
    final tagN = DriveBackup.entryCount(snap);
    final insp = snap.inspiration;
    final tagOver = insp == null
        ? 0
        : ref
              .read(tagLibraryProvider.notifier)
              .previewMerge(
                insp['categories'] is Map<String, dynamic>
                    ? insp['categories'] as Map<String, dynamic>
                    : const {},
                custom: insp['custom'] is Map<String, dynamic>
                    ? insp['custom'] as Map<String, dynamic>
                    : null,
              )
              .overwrite;
    final localIds = {
      for (final e in ref.read(vibeLibraryProvider).value ?? const []) e.id,
    };
    final vibes = snap.vibes;
    final picked = await showImportPicker(
      context,
      title: '选择要恢复的内容',
      confirmLabel: '恢复',
      options: [
        ImportOption(
          key: 'tag',
          label: '灵感库',
          detail: tagN > 0 ? '$tagN 条' : '暂无备份',
          enabled: tagN > 0,
          conflict: tagOver,
        ),
        ImportOption(
          key: 'vibe',
          label: 'Vibe',
          detail: vibes.isNotEmpty ? '${vibes.length} 条' : '暂无备份',
          enabled: vibes.isNotEmpty,
          conflict: vibes.where((v) => localIds.contains(v['id'])).length,
        ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) {
      return snap.drive.close();
    }
    unawaited(
      ref
          .read(cloudJobProvider.notifier)
          .driveRestore(
            snap,
            inspiration: picked.contains('tag'),
            vibes: picked.contains('vibe'),
          ),
    );
  }

  // ---- 文件导入 ----

  Future<void> _importFile() async {
    if (!_idle) return;
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
      final path = file.path;
      final WebBackupImportOutcome? out;
      if (path != null && await LocalBackupFile.isZip(path)) {
        if (!mounted) return;
        out = await _importLocalBackup(path);
      } else {
        final j = await readPickedJson(file);
        if (!mounted) return;
        if (j is Map<String, dynamic> &&
            j['meta'] is Map &&
            (j['meta'] as Map)['identifier'] == kWebBackupIdentifier) {
          out = await _importWebBackup(WebBackup.fromDecoded(j));
        } else if (j is Map<String, dynamic> &&
            j['identifier'] == kBackupFileIdentifier) {
          final f = parseBackupFile(j);
          out = await _importTagFile(f.cat, f.items);
        } else {
          throw FormatException(context.l10n.notBackupFile);
        }
      }
      if (out == null || !mounted) return; // 自选面板里取消
      setState(() => _result = out);
      hintSnack(
        context,
        out.errors.isEmpty
            ? context.l10n.importComplete
            : context.l10n.importCompleteFailed(out.errors.length),
        icon: out.errors.isEmpty ? Icons.check : Icons.warning_amber_outlined,
      );
    } on FormatException catch (e) {
      if (mounted) {
        hintSnack(
          context,
          e.message.isEmpty ? context.l10n.notValidJson : e.message,
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (mounted) {
        hintSnack(
          context,
          context.l10n.importFailed('$e'),
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = '';
        });
      }
    }
  }

  /// 本 App 导出的备份包:灵感库 / Vibe 自选导入,按 id 合并。
  Future<WebBackupImportOutcome?> _importLocalBackup(String path) async {
    final file = LocalBackupFile.open(path);
    try {
      final l = context.l10n;
      final tagN = file.inspirationCount, vibeN = file.vibeCount;
      if (tagN == 0 && vibeN == 0) throw FormatException(l.fileNoEntries);
      var conflict = 0;
      if (tagN > 0) {
        final j = file.inspiration();
        if (j != null) {
          conflict = ref
              .read(tagLibraryProvider.notifier)
              .previewMerge(
                j['categories'] is Map<String, dynamic>
                    ? j['categories'] as Map<String, dynamic>
                    : const {},
                custom: j['custom'] is Map<String, dynamic>
                    ? j['custom'] as Map<String, dynamic>
                    : null,
              )
              .overwrite;
        }
      }
      final picked = await showImportPicker(
        context,
        title: l.chooseImportContent,
        options: [
          ImportOption(
            key: 'tag',
            label: l.inspirationLibrary,
            detail: l.itemsN(tagN),
            enabled: tagN > 0,
            conflict: conflict,
          ),
          ImportOption(
            key: 'vibe',
            label: 'Vibe',
            detail: l.itemsN(vibeN),
            enabled: vibeN > 0,
          ),
        ],
      );
      if (picked == null || picked.isEmpty) return null;
      final backup = ref.read(localBackupProvider);
      final rows = <(String, String)>[];
      final errors = <String>[];
      if (picked.contains('tag')) {
        try {
          final r = await backup.importInspiration(file, onProgress: _tickTag);
          rows.add((
            l.inspirationLibrary,
            l.addedUpdated(
              r.stat.values.fold(0, (a, s) => a + s.added),
              r.stat.values.fold(0, (a, s) => a + s.updated),
            ),
          ));
          if (r.favoritesAdded > 0) {
            rows.add(('法典收藏', '新增 ${r.favoritesAdded}'));
          }
        } catch (e) {
          errors.add('灵感库导入失败:$e');
        }
      }
      if (picked.contains('vibe')) {
        try {
          final n = await backup.importVibes(file, onProgress: _tick);
          rows.add(('Vibe', l.itemsN(n)));
        } catch (e) {
          errors.add('Vibe 导入失败:$e');
        }
      }
      return (rows: rows, errors: errors);
    } finally {
      await file.close();
    }
  }

  /// web「设置 → 数据备份」的全量备份:五类自选导入。
  Future<WebBackupImportOutcome?> _importWebBackup(WebBackup b) {
    if (b.isEmpty) throw FormatException(context.l10n.webBackupEmpty);
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
      throw FormatException(context.l10n.customCatMissing);
    }
    if (items.isEmpty) throw FormatException(context.l10n.fileNoEntries);
    final lib = ref.read(tagLibraryProvider.notifier);
    final d = tagCategoryDef(cat);
    final l = context.l10n;
    final label = l.inspirationOf(d.label);
    final payload = {d.webId: items};
    final picked = await showImportPicker(
      context,
      title: context.l10n.chooseImportContent,
      options: [
        ImportOption(
          key: d.webId,
          label: label,
          detail: context.l10n.itemsN(items.length),
          conflict: lib.previewMerge(payload).overwrite,
        ),
      ],
    );
    if (picked == null || picked.isEmpty) return null;
    final s = (await ref
        .read(tagCloudBackupProvider)
        .withResolver(
          (resolve) => lib.mergeBackup(payload, resolvePreview: resolve),
        ))[cat];
    return (
      rows: [(label, l.addedUpdated(s?.added ?? 0, s?.updated ?? 0))],
      errors: const <String>[],
    );
  }

  // ---- 文件导出 ----

  /// 灵感库(含预览原图、标签池、法典收藏)与 Vibe 库(含编码)打成一个 zip。
  Future<void> _exportBackup() async {
    if (!_idle) return;
    final tagN = ref.read(tagLibraryProvider).value?.entries.length ?? 0;
    final vibeN = ref.read(vibeLibraryProvider).value?.length ?? 0;
    final l = context.l10n;
    if (tagN == 0 && vibeN == 0) {
      hintSnack(context, '本地没有可导出的内容', icon: Icons.info_outline);
      return;
    }
    final picked = await showImportPicker(
      context,
      title: '选择要导出的内容',
      confirmLabel: l.export,
      mergeHint: false,
      options: [
        ImportOption(
          key: 'tag',
          label: l.inspirationLibrary,
          detail: l.itemsN(tagN),
          enabled: tagN > 0,
        ),
        ImportOption(
          key: 'vibe',
          label: 'Vibe',
          detail: l.itemsN(vibeN),
          enabled: vibeN > 0,
        ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _busy = 'export';
      _progress = '';
    });
    File? zip;
    try {
      zip = await ref
          .read(localBackupProvider)
          .export(
            inspiration: picked.contains('tag'),
            vibes: picked.contains('vibe'),
            onProgress: _tick,
          );
      if (!mounted) return;
      setState(() => _progress = '');
      final now = DateTime.now();
      final date =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final path = await saveFileAs(
        zip,
        fileName: 'plana_backup_$date.zip',
        mime: 'application/zip',
      );
      if (path != null && mounted) {
        hintSnack(context, '已导出', icon: Icons.check_circle_outline);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        hintSnack(
          context,
          l.exportFailed(e.message ?? e.code),
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (mounted) {
        hintSnack(context, l.exportFailed('$e'), icon: Icons.error_outline);
      }
    } finally {
      try {
        await zip?.delete();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = '';
        });
      }
    }
  }

  String _cloudStatus(bool authed, bool loading, _Cloud? c) {
    if (!authed) return context.l10n.notAvailableYet;
    if (loading) return '读取中…';
    if (c == null) return '读取失败';
    if (c.updatedAt <= 0) return '暂无备份';
    final t = DateTime.fromMillisecondsSinceEpoch(c.updatedAt * 1000);
    return '${c.count} 条 · ${_when(t)}';
  }

  /// 云端硬盘里某一块的条数与时间。
  String _driveStatus(DriveSection? s) {
    if (_driveLoading) return '读取中…';
    if (!_driveRead) return '读取失败';
    return s == null ? '暂无备份' : '${s.count} 条 · ${_when(s.at)}';
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    return d.inMinutes < 1
        ? '刚刚'
        : d.inHours < 1
        ? '${d.inMinutes} 分钟前'
        : d.inDays < 1
        ? '${d.inHours} 小时前'
        : d.inDays < 30
        ? '${d.inDays} 天前'
        : '${t.year}-${t.month.toString().padLeft(2, '0')}-'
              '${t.day.toString().padLeft(2, '0')}';
  }

  /// 动作行在跑时的右侧值:进度或「处理中…」。
  String? _busyValue(String tag) => _busy == tag
      ? (_progress.isEmpty ? context.l10n.processing : _progress)
      : null;

  /// 云端任务那两行的右侧值。
  String? _jobValue(CloudJobState job, String kind) {
    if (_busy == '$kind-check') return _progress;
    if (job.kind != kind) return null;
    return job.progress.isEmpty ? context.l10n.processing : job.progress;
  }

  @override
  Widget build(BuildContext context) {
    final authed = ref.watch(botSessionProvider).value != null;
    final job = ref.watch(cloudJobProvider);
    final driveEmail = ref.watch(googleDriveAuthProvider);
    ref.listen(cloudJobProvider, (prev, next) {
      if (prev?.busy != true || next.busy) return;
      _showJobResult(next);
      if (prev!.kind!.startsWith('drive')) {
        _loadDrive();
      } else {
        _loadTagCloud();
        _loadVibeCloud();
      }
    });
    final idle = _busy == null && !job.busy;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.backup)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          if (authed) ...[
            SettingsLabel(context.l10n.cloudBackup),
            SettingsCard(
              children: [
                SettingsRow(
                  icon: Icons.lightbulb_outline,
                  title: context.l10n.inspirationLibrary,
                  value: _cloudStatus(authed, _tagLoading, _tagCloud),
                ),
                SettingsRow(
                  icon: Icons.palette_outlined,
                  title: 'Vibe',
                  value: _cloudStatus(authed, _vibeLoading, _vibeCloud),
                ),
                SettingsRow(
                  icon: Icons.cloud_upload_outlined,
                  title: context.l10n.backupToCloud,
                  value: _jobValue(job, 'backup'),
                  onTap: idle ? _cloudBackup : null,
                ),
                SettingsRow(
                  icon: Icons.cloud_download_outlined,
                  title: context.l10n.restoreFromCloud,
                  value: _jobValue(job, 'restore'),
                  onTap: idle ? _cloudRestore : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const SettingsLabel('Google 云端硬盘'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.account_circle_outlined,
                title: '账号',
                value: _busy == 'drive-connect'
                    ? '连接中…'
                    : (driveEmail ?? '未连接'),
                onTap: idle ? _driveAccount : null,
              ),
              if (driveEmail != null) ...[
                SettingsRow(
                  icon: Icons.lightbulb_outline,
                  title: context.l10n.inspirationLibrary,
                  value: _driveStatus(_drive?.tags),
                ),
                SettingsRow(
                  icon: Icons.palette_outlined,
                  title: 'Vibe',
                  value: _driveStatus(_drive?.vibes),
                ),
              ],
              SettingsRow(
                icon: Icons.cloud_upload_outlined,
                title: '备份到 Google 云端硬盘',
                value: _jobValue(job, 'drive-backup'),
                onTap: idle ? _driveBackup : null,
              ),
              SettingsRow(
                icon: Icons.cloud_download_outlined,
                title: '从 Google 云端硬盘恢复',
                value: _jobValue(job, 'drive-restore'),
                onTap: idle ? _driveRestore : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsLabel(context.l10n.importLabel),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.folder_open_outlined,
                title: context.l10n.selectBackupFile,
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
          SettingsLabel(context.l10n.export),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.save_alt_outlined,
                title: '导出到文件',
                value: _busyValue('export'),
                onTap: idle ? _exportBackup : null,
              ),
            ],
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
                context.l10n.importResult,
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

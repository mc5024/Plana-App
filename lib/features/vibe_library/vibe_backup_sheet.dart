import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;
import 'vibe_cloud_sync.dart';
import 'vibe_library.dart';

/// Vibe 云端备份弹层(对齐 web 桌面端 CloudManageModal)。
Future<void> showVibeBackupSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .18),
  builder: (_) => const _VibeBackupSheet(),
);

class _VibeBackupSheet extends ConsumerStatefulWidget {
  const _VibeBackupSheet();

  @override
  ConsumerState<_VibeBackupSheet> createState() => _VibeBackupSheetState();
}

class _VibeBackupSheetState extends ConsumerState<_VibeBackupSheet> {
  String? _busy; // backup | restore
  bool _loading = true;

  int _cloudCount = 0;
  int _cloudUpdatedAt = 0;
  List<BackupLogEntry> _log = const [];

  /// 进行中的逐条进度(vibe 带图,单条就要几百 KB,必须让人看见在动)。
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _loadCloud();
  }

  Future<void> _loadCloud() async {
    final session = ref.read(botSessionProvider).value;
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final client = ref.read(backendClientProvider);
      final state = await client.getUserVibesState(session.sessionId);
      final log = await client.getBackupLog(session.sessionId);
      if (!mounted) return;
      setState(() {
        _cloudCount = state.count;
        _cloudUpdatedAt = state.updatedAt;
        _log = log;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(String tag, Future<void> Function() op) async {
    if (_busy != null) return;
    if (ref.read(botSessionProvider).value == null) {
      hintSnack(context, '暂未开放', icon: Icons.cloud_off_outlined);
      return;
    }
    setState(() {
      _busy = tag;
      _progress = '';
    });
    try {
      await op();
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

  void _tick(String label, int cur, int total) {
    if (mounted) setState(() => _progress = '$label $cur/$total');
  }

  // ---- 备份 ----

  Future<void> _backup() => _run('backup', () async {
    final local = ref.read(vibeLibraryProvider).value ?? const [];
    if (local.isEmpty) {
      hintSnack(context, '本地没有 Vibe 可备份', icon: Icons.info_outline);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: '备份到云端?',
      message:
          '本地 ${local.length} 个 Vibe 将推送到云端。'
          '未改动过的会自动跳过,只改过名称/标签的不重传图片。',
      confirmLabel: '备份',
    );
    if (ok != true || !mounted) return;

    final sync = ref.read(vibeCloudSyncProvider);
    final r = await sync.pushAll(
      onProgress: (cur, total) => _tick('推送', cur, total),
    );
    final detail = [
      if (r.pushed > 0) '上传 ${r.pushed}',
      if (r.skipped > 0) '跳过 ${r.skipped}',
      if (r.failed > 0) '失败 ${r.failed}',
    ].join('、');
    await _record('backup', r.pushed, detail.isEmpty ? '已是最新' : detail);
    if (!mounted) return;
    hintSnack(
      context,
      r.failed > 0
          ? '备份完成,$detail'
          : '备份完成:${detail.isEmpty ? "已是最新" : detail}',
      icon: r.failed > 0 ? Icons.warning_amber : Icons.cloud_done_outlined,
    );
    await _loadCloud();
  });

  // ---- 恢复 ----

  Future<void> _restore() => _run('restore', () async {
    final sync = ref.read(vibeCloudSyncProvider);
    setState(() => _progress = '正在比对云端…');
    final pre = await sync.previewRestore();
    if (!mounted) return;
    if (pre.willAdd.isEmpty && pre.willOverwrite.isEmpty) {
      hintSnack(context, '本地已与云端一致', icon: Icons.check_circle_outline);
      return;
    }
    // 覆盖不可撤销,先把要覆盖的点名列出来(多了只列前 5 个)
    final over = pre.willOverwrite.length <= 5
        ? pre.willOverwrite.join('、')
        : '${pre.willOverwrite.take(5).join('、')} 等 ${pre.willOverwrite.length} 个';
    final ok = await confirmDialog(
      context,
      title: '从云端恢复?',
      message: [
        if (pre.willAdd.isNotEmpty) '新增 ${pre.willAdd.length} 个',
        if (pre.willOverwrite.isNotEmpty)
          '覆盖 ${pre.willOverwrite.length} 个:$over',
        '本地独有的 Vibe 会保留,不会被删除。',
      ].join('\n'),
      confirmLabel: '恢复',
    );
    if (ok != true || !mounted) return;

    final r = await sync.restoreAll(
      onProgress: (cur, total) => _tick('拉取', cur, total),
    );
    final detail = [
      if (r.added > 0) '新增 ${r.added}',
      if (r.updated > 0) '覆盖 ${r.updated}',
      if (r.skipped > 0) '跳过 ${r.skipped}',
    ].join('、');
    await _record(
      'restore',
      r.added + r.updated,
      detail.isEmpty ? '已是最新' : detail,
    );
    if (!mounted) return;
    hintSnack(
      context,
      '恢复完成:${detail.isEmpty ? "已是最新" : detail}',
      icon: Icons.cloud_download_outlined,
    );
    await _loadCloud();
  });

  Future<void> _record(String action, int count, String detail) async {
    final session = ref.read(botSessionProvider).value;
    if (session == null) return;
    await ref
        .read(backendClientProvider)
        .recordBackupLog(
          sessionId: session.sessionId,
          device: 'Plana App',
          action: action,
          count: count,
          detail: detail,
        );
  }

  // ---- 视图 ----

  String _fmtTime(int unixSec) {
    if (unixSec <= 0) return '从未';
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天 $hm';
    }
    return '${d.month}-${two(d.day)} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final local = ref.watch(vibeLibraryProvider).value ?? const [];
    final authed = ref.watch(botSessionProvider).value != null;
    final lastBackup = _log.where((e) => e.isBackup).firstOrNull;
    final lastRestore = _log.where((e) => !e.isBackup).firstOrNull;

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Vibe 云备份',
                style: context.texts.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (!authed)
                _hint('云备份暂未开放', Icons.cloud_off_outlined)
              else ...[
                _statRow('本地', '${local.length} 个'),
                const SizedBox(height: 6),
                _statRow(
                  '云端',
                  _loading
                      ? '读取中…'
                      : '$_cloudCount 个 · ${_fmtTime(_cloudUpdatedAt)}',
                ),
                if (lastBackup != null) ...[
                  const SizedBox(height: 6),
                  _statRow(
                    '上次备份',
                    '${_fmtTime(lastBackup.time)} · ${lastBackup.device}',
                  ),
                ],
                if (lastRestore != null) ...[
                  const SizedBox(height: 6),
                  _statRow(
                    '上次恢复',
                    '${_fmtTime(lastRestore.time)} · ${lastRestore.device}',
                  ),
                ],
              ],
              const SizedBox(height: 16),
              if (_busy != null && _progress.isNotEmpty) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _progress,
                      style: context.texts.labelMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: authed && _busy == null ? _restore : null,
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('从云端恢复', maxLines: 1),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: authed && _busy == null ? _backup : null,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('备份到云端', maxLines: 1),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
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

  Widget _statRow(String label, String value) {
    final scheme = context.scheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: context.texts.bodyMedium!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: context.texts.bodyMedium!.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _hint(String text, IconData icon) {
    final scheme = context.scheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: context.texts.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

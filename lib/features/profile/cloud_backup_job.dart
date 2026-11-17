import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/live_progress/live_progress.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/google_drive.dart';
import '../../core/store/storage_stats.dart' show fmtBytes;
import '../inspiration/tag_cloud_backup.dart';
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../vibe_library/vibe_cloud_sync.dart';
import '../vibe_library/vibe_library.dart';
import 'drive_backup.dart';

/// 云端备份 / 恢复的进行状态。
class CloudJobState {
  const CloudJobState({this.kind, this.progress = '', this.result});

  /// backup | restore | drive-backup | drive-restore;null = 空闲。
  final String? kind;

  /// 整体百分比(「42%」);空 = 还算不出来。
  final String progress;

  /// 最近一次结束的结果,备份页取走后清掉。
  final ({String text, bool ok})? result;

  bool get busy => kind != null;
}

/// 灵感库备份前从云端拉好的那份(恢复用)。
typedef CloudTagBackup = ({
  Map<String, dynamic> categories,
  Map<String, dynamic>? custom,
  Map<String, dynamic>? pools,
  List<dynamic>? codexFavorites,
});

final cloudJobProvider = NotifierProvider<CloudJob, CloudJobState>(
  CloudJob.new,
);

/// 云端备份 / 恢复跑在页面之外:离开备份页、切到后台都照常进行。跑的时候拉起前台
/// 服务保活,通知栏显示进度;在后台跑完留一条结果通知。
class CloudJob extends Notifier<CloudJobState> {
  @override
  CloudJobState build() => const CloudJobState();

  BackendClient get _client => ref.read(backendClientProvider);

  DateTime _notifiedAt = DateTime(0);

  /// 各阶段在整体进度里的分量(字节或件数,按阶段名),每个任务开始时登记;
  /// 没登记的阶段不计入整体进度。
  final _weights = <String, int>{};
  final _fracs = <String, double>{};

  /// 备份页把结果提示过了。
  void takeResult() {
    if (state.result != null) state = CloudJobState(kind: state.kind);
  }

  Future<void> backup(
    String sessionId, {
    required bool inspiration,
    required bool vibes,
  }) => _run('backup', '正在备份到云端', '备份', (done, failed) async {
    if (vibes) {
      _weights['推送 Vibe'] = [
        for (final e in ref.read(vibeLibraryProvider).value ?? <VibeEntry>[])
          if (e.needsPush) e.sizeBytes,
      ].fold(0, (a, b) => a + b);
    }
    if (inspiration) {
      try {
        var bytes = (0, 0);
        final r = await ref
            .read(tagCloudBackupProvider)
            .upload(
              sessionId,
              onBytes: (d, t) {
                bytes = (d, t);
                _weights['上传预览'] = t;
              },
              onProgress: (label, d, t) => _report(
                label,
                d,
                t,
                bytesDone: label == '上传预览' ? bytes.$1 : 0,
                bytesTotal: label == '上传预览' ? bytes.$2 : 0,
              ),
            );
        await _log(
          sessionId,
          'backup',
          r.entries,
          'tag-manager 备份 ${_countLine()}',
        );
        final pics = [
          if (r.uploaded > 0) '预览上传 ${r.uploaded}',
          if (r.failed > 0)
            r.quotaFull ? '${r.failed} 张预览超出云端额度' : '${r.failed} 张预览没传上',
        ].join('、');
        (r.failed > 0 ? failed : done).add(
          '灵感库 ${r.entries} 条${pics.isEmpty ? '' : ' · $pics'}',
        );
      } catch (e) {
        failed.add('灵感库失败:${_errText(e)}');
      }
    }
    if (vibes) {
      try {
        final r = await ref
            .read(vibeCloudSyncProvider)
            .pushAll(onProgress: (d, t) => _report('推送 Vibe', d, t));
        final text = _vibeText(r.pushed, 0, r.skipped, r.failed, '上传');
        await _log(sessionId, 'backup', r.pushed, text);
        (r.failed > 0 ? failed : done).add('Vibe $text');
      } catch (e) {
        failed.add('Vibe 失败:${_errText(e)}');
      }
    }
  });

  Future<void> restore(
    String sessionId, {
    CloudTagBackup? inspiration,
    int inspirationCount = 0,
    required bool vibes,
    int vibeCount = 0,
  }) => _run('restore', '正在从云端恢复', '恢复', (done, failed) async {
    if (inspiration != null) {
      _weights['恢复预览'] = TagLibrary.previewRefCount(
        inspiration.categories,
        custom: inspiration.custom,
      );
    }
    if (vibes) _weights['拉取 Vibe'] = vibeCount;
    if (inspiration != null) {
      _report('恢复灵感库', 0, 0);
      try {
        final r = await ref
            .read(tagCloudBackupProvider)
            .restore(inspiration, onProgress: _report);
        final detail = _detailLine({
          for (final e in r.stat.entries)
            e.key: '+${e.value.added}/✎${e.value.updated}',
        });
        await _log(
          sessionId,
          'restore',
          inspirationCount,
          'tag-manager 恢复 $detail',
        );
        final added = r.stat.values.fold(0, (a, s) => a + s.added);
        final updated = r.stat.values.fold(0, (a, s) => a + s.updated);
        done.add('灵感库 新增 $added、覆盖 $updated');
      } catch (e) {
        failed.add('灵感库失败:${_errText(e)}');
      }
    }
    if (vibes) {
      try {
        final r = await ref
            .read(vibeCloudSyncProvider)
            .restoreAll(onProgress: (d, t) => _report('拉取 Vibe', d, t));
        final text = _vibeText(
          0,
          r.added,
          r.skipped,
          0,
          '',
          updated: r.updated,
        );
        await _log(sessionId, 'restore', r.added + r.updated, text);
        done.add('Vibe $text');
      } catch (e) {
        failed.add('Vibe 失败:${_errText(e)}');
      }
    }
  });

  /// 备份到 Google 云端硬盘([plan] 是选内容前比对好的)。
  Future<void> driveBackup(
    DriveBackupPlan plan, {
    required bool inspiration,
    required bool vibes,
  }) => _run('drive-backup', '正在备份到 Google 云端硬盘', '备份', (done, failed) async {
    if (inspiration) _weights['上传预览'] = plan.previewBytes;
    if (vibes) _weights['上传 Vibe'] = plan.vibeBytes;
    final r = await ref
        .read(driveBackupProvider)
        .backup(
          plan,
          inspiration: inspiration,
          vibes: vibes,
          onProgress: (label, d, t, bd, bt) =>
              _report(label, d, t, bytesDone: bd, bytesTotal: bt),
        );
    if (inspiration) {
      final pics = [
        if (r.previews > 0) '预览上传 ${r.previews}',
        if (r.previewsFailed > 0) '${r.previewsFailed} 张预览没传上',
      ].join('、');
      (r.previewsFailed > 0 ? failed : done).add(
        '灵感库 ${r.entries} 条${pics.isEmpty ? '' : ' · $pics'}',
      );
    }
    if (vibes) {
      final skipped = plan.vibes.length - r.vibes - r.vibesFailed;
      final text = _vibeText(r.vibes, 0, skipped, r.vibesFailed, '上传');
      (r.vibesFailed > 0 ? failed : done).add('Vibe $text');
    }
  });

  /// 从 Google 云端硬盘恢复最新那份备份。
  Future<void> driveRestore(
    DriveSnapshot snap, {
    required bool inspiration,
    required bool vibes,
  }) => _run('drive-restore', '正在从 Google 云端硬盘恢复', '恢复', (done, failed) async {
    if (snap.inspiration case final j? when inspiration) {
      _weights['恢复预览'] = TagLibrary.previewRefCount(
        j['categories'] is Map<String, dynamic>
            ? j['categories'] as Map<String, dynamic>
            : const {},
        custom: j['custom'] is Map<String, dynamic>
            ? j['custom'] as Map<String, dynamic>
            : null,
      );
    }
    if (vibes) _weights['恢复 Vibe'] = snap.vibes.length;
    _report('恢复中', 0, 0);
    final r = await ref
        .read(driveBackupProvider)
        .restore(
          snap,
          inspiration: inspiration,
          vibes: vibes,
          onProgress: _report,
        );
    if (r.stat case final stat?) {
      final added = stat.values.fold(0, (a, s) => a + s.added);
      final updated = stat.values.fold(0, (a, s) => a + s.updated);
      done.add('灵感库 新增 $added、覆盖 $updated');
    }
    if (vibes) done.add('Vibe ${r.vibes} 条');
  });

  Future<void> _run(
    String kind,
    String title,
    String verb,
    Future<void> Function(List<String> done, List<String> failed) body,
  ) async {
    if (state.busy) return;
    state = CloudJobState(kind: kind);
    _weights.clear();
    _fracs.clear();
    LiveProgress.instance.beginBackup(title);
    final done = <String>[], failed = <String>[];
    try {
      await body(done, failed);
    } catch (e) {
      failed.add(_errText(e));
    }
    final ok = failed.isEmpty;
    final text = ok
        ? '$verb完成:${done.join(' · ')}'
        : [...done, ...failed].join(' · ');
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    LiveProgress.instance.endBackup(
      title: ok ? '$verb完成' : '$verb没有全部完成',
      text: text,
      success: ok,
      keep: !foreground,
    );
    state = CloudJobState(result: (text: text, ok: ok));
  }

  /// 报某阶段的进度(有字节数按字节,否则按件数),折成整体百分比:页面那行随时刷,
  /// 通知栏最多一秒一次,正文带上阶段明细。
  void _report(
    String label,
    int done,
    int total, {
    int bytesDone = 0,
    int bytesTotal = 0,
  }) {
    if (bytesTotal > 0) {
      _fracs[label] = (bytesDone / bytesTotal).clamp(0.0, 1.0);
    } else if (total > 0) {
      _fracs[label] = (done / total).clamp(0.0, 1.0);
    }
    final sum = _weights.values.fold(0, (a, b) => a + b);
    final pct = sum == 0
        ? null
        : (_weights.entries.fold(
                    0.0,
                    (a, e) => a + (_fracs[e.key] ?? 0) * e.value,
                  ) *
                  100 /
                  sum)
              .floor();
    state = CloudJobState(
      kind: state.kind,
      progress: pct == null ? '' : '$pct%',
    );
    final now = DateTime.now();
    if (now.difference(_notifiedAt) < const Duration(seconds: 1) &&
        done < total) {
      return;
    }
    _notifiedAt = now;
    LiveProgress.instance.updateBackup(
      cur: pct ?? 0,
      total: pct == null ? 0 : 100,
      text: [
        label,
        if (total > 0) '$done/$total',
        if (bytesTotal > 0) '${fmtBytes(bytesDone)} / ${fmtBytes(bytesTotal)}',
      ].join(' '),
      short: pct == null ? '' : '$pct%',
    );
  }

  Future<void> _log(String sid, String action, int count, String detail) =>
      _client.recordBackupLog(
        sessionId: sid,
        device: 'Plana App',
        action: action,
        count: count,
        detail: detail,
      );

  static String _errText(Object e) => switch (e) {
    BackendException(:final message) ||
    DriveException(:final message) ||
    FormatException(:final message) => message,
    _ => '$e',
  };

  static String _vibeText(
    int pushed,
    int added,
    int skipped,
    int failed,
    String pushedLabel, {
    int updated = 0,
  }) {
    final s = [
      if (pushed > 0) '$pushedLabel $pushed',
      if (added > 0) '新增 $added',
      if (updated > 0) '覆盖 $updated',
      if (skipped > 0) '跳过 $skipped',
      if (failed > 0) '失败 $failed',
    ].join('、');
    return s.isEmpty ? '已是最新' : s;
  }

  /// 内置四类(含改名)+ 自定义类别。
  List<TagCategoryDef> _defs() => [
    for (final d in kTagCategoryDefs) tagCategoryDef(d.key),
    ...?ref.read(tagLibraryProvider).value?.customDefs,
  ];

  String _detailLine(Map<TagCategory, String> parts) => [
    for (final d in _defs())
      if (parts[d.key] case final String s) '${d.label} $s',
  ].join(' · ');

  String _countLine() {
    final s = ref.read(tagLibraryProvider).value;
    return _detailLine({
      for (final d in _defs()) d.key: '${s?.of(d.key).length ?? 0}',
    });
  }
}

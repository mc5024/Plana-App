import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/live_progress/live_progress.dart';
import '../../core/net/backend_client.dart';
import '../../core/store/storage_stats.dart' show fmtBytes;
import '../inspiration/tag_cloud_backup.dart';
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../vibe_library/vibe_cloud_sync.dart';

/// 云端备份 / 恢复的进行状态。
class CloudJobState {
  const CloudJobState({this.kind, this.progress = '', this.result});

  /// backup | restore;null = 空闲。
  final String? kind;

  /// 「上传预览 12/40 · 120.5/450.0 MB」;空 = 还没开始报数。
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

  /// 备份页把结果提示过了。
  void takeResult() {
    if (state.result != null) state = CloudJobState(kind: state.kind);
  }

  Future<void> backup(
    String sessionId, {
    required bool inspiration,
    required bool vibes,
  }) => _run('backup', '正在备份到云端', '备份', (done, failed) async {
    if (inspiration) {
      try {
        var bytes = (0, 0);
        final r = await ref
            .read(tagCloudBackupProvider)
            .upload(
              sessionId,
              onBytes: (d, t) => bytes = (d, t),
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
  }) => _run('restore', '正在从云端恢复', '恢复', (done, failed) async {
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

  Future<void> _run(
    String kind,
    String title,
    String verb,
    Future<void> Function(List<String> done, List<String> failed) body,
  ) async {
    if (state.busy) return;
    state = CloudJobState(kind: kind);
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

  /// 报进度:页面上的那行字随时刷,通知栏最多一秒一次。
  void _report(
    String label,
    int done,
    int total, {
    int bytesDone = 0,
    int bytesTotal = 0,
  }) {
    final text = [
      label,
      if (total > 0) '$done/$total',
      if (bytesTotal > 0) '${fmtBytes(bytesDone)} / ${fmtBytes(bytesTotal)}',
    ].join(' ');
    state = CloudJobState(
      kind: state.kind,
      progress: total > 0 ? text : '$label…',
    );
    final now = DateTime.now();
    if (now.difference(_notifiedAt) < const Duration(seconds: 1) &&
        done < total) {
      return;
    }
    _notifiedAt = now;
    // 通知的进度条按字节走(有字节数时),KB 计免得超出整型
    final cur = bytesTotal > 0 ? bytesDone >> 10 : done;
    final max = bytesTotal > 0 ? bytesTotal >> 10 : total;
    LiveProgress.instance.updateBackup(
      cur: cur,
      total: max,
      text: text,
      short: max > 0 ? '${(cur * 100 / max).floor()}%' : '',
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

  static String _errText(Object e) => e is BackendException ? e.message : '$e';

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

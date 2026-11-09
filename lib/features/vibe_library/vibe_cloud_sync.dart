import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import 'vibe_library.dart';

/// 个人云端 Vibe 备份 / 恢复(对齐 web 桌面端 CloudManageModal 的语义)。
///
/// 与 Tag 备份的根本差别:Tag 是一个 JSON blob 整体覆盖,Vibe 在云端**逐文件**
/// 存放,且每条都带 base64 原图(几百 KB 起步)。所以这里必须做增量:
/// - 推送:指纹没变的整条跳过、不发请求;只有元数据变的走 PUT,不重传图。
/// - 恢复:云端**并入**本地,不删本地独有的;双 hash 相同则跳过。
class VibeCloudSync {
  VibeCloudSync(this.ref);

  final Ref ref;

  BackendClient get _client => ref.read(backendClientProvider);

  /// 未授权时抛错:整个流程必须中止,绝不能拿半截状态去动本地数据。
  String get _sessionId {
    final s = ref.read(botSessionProvider).value;
    if (s == null) throw BackendException('暂未开放');
    return s.sessionId;
  }

  VibeLibrary get _lib => ref.read(vibeLibraryProvider.notifier);

  List<VibeEntry> get _entries =>
      ref.read(vibeLibraryProvider).value ?? const [];

  // ── 备份 ────────────────────────────────────────────────────────────

  /// 把本地全部 vibe 推到云端。→ (实推, 跳过, 失败)
  Future<({int pushed, int skipped, int failed})> pushAll({
    void Function(int current, int total)? onProgress,
  }) async {
    final sid = _sessionId;
    final list = [..._entries];
    var pushed = 0, skipped = 0, failed = 0;

    for (var i = 0; i < list.length; i++) {
      onProgress?.call(i + 1, list.length);
      final e = list[i];

      // ① 图与元数据都没动过 → 整条跳过,一个请求都不发
      if (!e.needsPush) {
        skipped++;
        continue;
      }

      // ② 只有元数据变(图没变)→ PUT 改元数据,省掉整张图的重传
      if (e.canPushMetaOnly) {
        final r = await _client.updateUserVibeMeta(
          sessionId: sid,
          filename: e.cloudFilename!,
          name: e.name,
          tags: e.tags,
          defaultStrength: e.defaultStrength,
          defaultInfoExtracted: e.defaultInfoExtracted,
        );
        if (r.success) {
          await _lib.markCloudState(
            e.id,
            cloudImageHash: r.imageHash,
            cloudMetaHash: r.metaHash,
            pushedImageHash: e.imageHash,
            pushedMetaFp: e.metaFp,
          );
          pushed++;
          continue;
        }
        // PUT 失败多半是云端那个文件没了(别处删过)→ 落到整包上传重建
      }

      // ③ 整包上传。不带 filename 时后端按 id 去重覆盖,
      //    所以本地改过名/丢过 cloudFilename 也不会在云端留下重复副本。
      try {
        final raw = await _lib.rawForUpload(e);
        raw['name'] = e.name;
        raw['tags'] = e.tags;
        final r = await _client.uploadUserVibe(
          sessionId: sid,
          vibeData: raw,
          tags: e.tags,
          filename: e.cloudFilename,
        );
        if (r.success && r.filename != null) {
          await _lib.markCloudState(
            e.id,
            cloudFilename: r.filename,
            cloudImageHash: r.imageHash,
            cloudMetaHash: r.metaHash,
            pushedImageHash: e.imageHash,
            pushedMetaFp: e.metaFp,
          );
          pushed++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    // 标签池:本地为准整体覆盖(与 web putCloudTagPool 一致)
    try {
      await _client.putUserVibeTagPool(sessionId: sid, tags: _lib.knownTags);
    } catch (_) {}

    return (pushed: pushed, skipped: skipped, failed: failed);
  }

  // ── 恢复 ────────────────────────────────────────────────────────────

  /// 恢复预检:告诉用户这一下会新增哪些、覆盖哪些(覆盖不可撤销,必须先问)。
  Future<({List<String> willAdd, List<String> willOverwrite})>
  previewRestore() async {
    final cloud = await _client.listUserVibes(_sessionId);
    final localById = {for (final e in _entries) e.id: e};
    final willAdd = <String>[];
    final willOverwrite = <String>[];
    for (final c in cloud) {
      final local = localById[c.id];
      if (local == null) {
        willAdd.add(c.name.isEmpty ? c.filename : c.name);
      } else if (local.cloudImageHash != c.imageHash ||
          local.cloudMetaHash != c.metaHash) {
        // hash 对不上 = 云端那份和本地上次同步的不是同一版 → 会被覆盖
        willOverwrite.add(local.name.isEmpty ? c.filename : local.name);
      }
    }
    return (willAdd: willAdd, willOverwrite: willOverwrite);
  }

  /// 云端并入本地。→ (新增, 覆盖, 跳过)
  ///
  /// 本地独有的条目一律保留——这是「恢复」不是「镜像」,不做删除。
  Future<({int added, int updated, int skipped})> restoreAll({
    void Function(int current, int total)? onProgress,
  }) async {
    final sid = _sessionId;
    final cloud = await _client.listUserVibes(sid);
    var added = 0, updated = 0, skipped = 0;

    for (var i = 0; i < cloud.length; i++) {
      onProgress?.call(i + 1, cloud.length);
      final c = cloud[i];
      final local = {for (final e in _entries) e.id: e}[c.id];

      if (local != null &&
          local.cloudImageHash == c.imageHash &&
          local.cloudMetaHash == c.metaHash) {
        skipped++;
        continue;
      }

      try {
        final file = await _client.getUserVibeFile(sid, c.filename);
        final entries = await _lib.importVibeText(
          jsonEncode(file),
          fallbackName: c.name,
        );
        // 落库后把云端状态钉上,下次比对才跳得掉
        for (final e in entries) {
          await _lib.markCloudState(
            e.id,
            cloudFilename: c.filename,
            cloudImageHash: c.imageHash,
            cloudMetaHash: c.metaHash,
            pushedImageHash: e.imageHash,
            pushedMetaFp: e.metaFp,
          );
        }
        if (local == null) {
          added++;
        } else {
          updated++;
        }
      } catch (_) {
        // 单条拉取失败不中断整批:剩下的还能恢复,失败的下次再来
        continue;
      }
    }

    // 标签池合并(云端 ∪ 本地),两边都不丢
    try {
      final cloudPool = await _client.getUserVibeTagPool(sid);
      for (final t in cloudPool) {
        await _lib.createTag(t);
      }
    } catch (_) {}

    return (added: added, updated: updated, skipped: skipped);
  }
}

final vibeCloudSyncProvider = Provider<VibeCloudSync>(VibeCloudSync.new);

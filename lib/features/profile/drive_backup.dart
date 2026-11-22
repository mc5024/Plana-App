import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/google_drive.dart';
import '../inspiration/codex/codex_favorites.dart';
import '../inspiration/tag_cloud_backup.dart';
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../vibe_library/vibe_library.dart';
import 'local_backup.dart';

/// 进度:阶段名、件数、字节数(没有字节数的阶段传 0)。
typedef DriveProgress =
    void Function(
      String label,
      int done,
      int total,
      int bytesDone,
      int bytesTotal,
    );

/// 备份前的比对:要传哪些、多大、云端硬盘还剩多少。
class DriveBackupPlan {
  DriveBackupPlan._({
    required this.drive,
    required this.files,
    required this.shaOf,
    required this.previewsToSend,
    required this.vibes,
    required this.vibesToSend,
    required this.free,
    required this.tagCount,
  });

  final DriveClient drive;

  /// 比对时云端硬盘里已有的文件。
  final List<DriveFile> files;

  /// 本机预览路径 → sha256。
  final Map<String, String> shaOf;

  /// 云端硬盘还没有的预览:sha → (路径, 大小)。
  final Map<String, ({String path, int size})> previewsToSend;

  final List<({VibeEntry entry, String key})> vibes;

  /// 云端硬盘还没有的 Vibe 版本键。
  final Set<String> vibesToSend;

  /// 剩余空间;null = 不限。
  final int? free;

  final int tagCount;

  int get previewBytes => previewsToSend.values.fold(0, (a, p) => a + p.size);

  int get vibeBytes => [
    for (final v in vibes)
      if (vibesToSend.contains(v.key)) v.entry.sizeBytes,
  ].fold(0, (a, b) => a + b);
}

/// 最新那份备份里某一块的条数和备份时间。
typedef DriveSection = ({int count, DateTime at});

/// 云端硬盘里最新的那份备份。
class DriveSnapshot {
  DriveSnapshot._(this.drive, this.at, this.body, this.ids);

  final DriveClient drive;
  final DateTime at;
  final Map<String, dynamic> body;

  /// 文件名 → id。
  final Map<String, String> ids;

  Map<String, dynamic>? get inspiration =>
      body['inspiration'] is Map<String, dynamic>
      ? body['inspiration'] as Map<String, dynamic>
      : null;

  /// [{key, id, name, bytes}]
  List<Map<String, dynamic>> get vibes => _vibeList(body);
}

List<Map<String, dynamic>> _vibeList(Map<String, dynamic>? body) => [
  for (final v in (body?['vibes'] as List?) ?? const [])
    if (v is Map<String, dynamic> && v['key'] is String) v,
];

final driveBackupProvider = Provider<DriveBackup>(DriveBackup.new);

/// Google 云端硬盘备份,存在本 App 的隐藏数据区(平铺):
/// ```
/// p_<sha256>           预览原图,传过就不再传
/// v_<版本键>            一条 Vibe(.naiv4vibe 内容,见 VibeLibrary.backupKey)
/// backup_<毫秒>.json    清单:{identifier, version, createdAt, inspiration?, vibes?}
/// ```
/// 清单里的灵感库与本地备份包的 `inspiration.json` 同形,预览写成 sha 引用。
/// 先传缺的文件、最后写清单:中途断了,旧清单引用的文件都还在。清单留最近 [_keep] 份,
/// 哪份都不引用的文件在写完新清单后删掉。
class DriveBackup {
  /// [client] 仅供测试替换云端硬盘接口。
  DriveBackup(this.ref, {this._client});

  final Ref ref;
  final DriveClient Function(bool interactive)? _client;

  static const _keep = 3;
  static const _manifestPrefix = 'backup_';

  /// [interactive] = 第一次取令牌时允许弹授权(用户刚点过按钮)。
  DriveClient _open({bool interactive = false}) =>
      _client?.call(interactive) ??
      DriveClient(
        ref.read(googleDriveAuthProvider.notifier),
        interactive: interactive,
      );

  static int? _manifestAt(String name) =>
      name.startsWith(_manifestPrefix) && name.endsWith('.json')
      ? int.tryParse(
          name.substring(_manifestPrefix.length, name.length - '.json'.length),
        )
      : null;

  /// 清单,新的在前。
  static List<(DriveFile, int)> _manifests(List<DriveFile> files) => [
    for (final f in files)
      if (_manifestAt(f.name) case final int at) (f, at),
  ]..sort((a, b) => b.$2.compareTo(a.$2));

  static Future<Map<String, dynamic>> _readManifest(
    DriveClient drive,
    String id,
  ) async {
    final j = jsonDecode(utf8.decode(await drive.download(id)));
    if (j is! Map<String, dynamic> ||
        j['identifier'] != kLocalBackupIdentifier) {
      throw const FormatException('云端硬盘里的备份损坏');
    }
    return j;
  }

  /// 最新那份备份里灵感库、Vibe 各自的条数和备份时间;没备份过的块为 null。
  Future<({DriveSection? tags, DriveSection? vibes})> status() async {
    final drive = _open();
    try {
      final ms = _manifests(await drive.list(nameContains: _manifestPrefix));
      if (ms.isEmpty) return (tags: null, vibes: null);
      final (f, at) = ms.first;
      // 清单上没附条数的(早先的版本):下载清单现算
      final p = f.props.isNotEmpty
          ? f.props
          : _sections(await _readManifest(drive, f.id), at);
      DriveSection? section(String k) {
        final n = int.tryParse(p[k] ?? '');
        final t = int.tryParse(p['${k}At'] ?? '');
        return n == null || t == null
            ? null
            : (count: n, at: DateTime.fromMillisecondsSinceEpoch(t));
      }

      return (tags: section('tags'), vibes: section('vibes'));
    } finally {
      drive.close();
    }
  }

  /// 清单里两块各自的条数与备份时间(毫秒),附在清单文件上;[at] 是清单本身的时间。
  static Map<String, String> _sections(Map<String, dynamic> body, int at) => {
    if (body['inspiration'] != null) ...{
      'tags': '${_entryCount(body['inspiration'])}',
      'tagsAt': '${body['inspirationAt'] ?? at}',
    },
    if (body['vibes'] case final List v) ...{
      'vibes': '${v.length}',
      'vibesAt': '${body['vibesAt'] ?? at}',
    },
  };

  Future<DriveBackupPlan> plan({
    void Function(String label, int done, int total)? onProgress,
  }) async {
    final state = await ref.read(tagLibraryProvider.future);
    await ref.read(codexFavoritesProvider.future);
    final vibeList = await ref.read(vibeLibraryProvider.future);
    final drive = _open(interactive: true);
    try {
      onProgress?.call('读取云端硬盘', 0, 0);
      final files = await drive.list();
      final free = await drive.free();
      final names = {for (final f in files) f.name};

      final paths = ref
          .read(tagLibraryProvider.notifier)
          .localPreviewFiles()
          .toList();
      final hashes = await PreviewHashes.open();
      await hashes.prime(
        paths,
        onProgress: (d, t) => onProgress?.call('整理预览', d, t),
      );
      final shaOf = <String, String>{};
      final toSend = <String, ({String path, int size})>{};
      for (var i = 0; i < paths.length; i++) {
        onProgress?.call('比对', i + 1, paths.length + vibeList.length);
        try {
          final sha = await hashes.shaOf(paths[i]);
          if (sha == null) continue;
          shaOf[paths[i]] = sha;
          if (!names.contains('p_$sha') && !toSend.containsKey(sha)) {
            toSend[sha] = (path: paths[i], size: await File(paths[i]).length());
          }
        } catch (_) {} // 读不出的那张当没有
      }
      await hashes.save();

      final lib = ref.read(vibeLibraryProvider.notifier);
      final vibes = <({VibeEntry entry, String key})>[];
      for (var i = 0; i < vibeList.length; i++) {
        onProgress?.call(
          '比对',
          paths.length + i + 1,
          paths.length + vibeList.length,
        );
        try {
          vibes.add((
            entry: vibeList[i],
            key: await lib.backupKey(vibeList[i]),
          ));
        } catch (_) {} // 文件不在了:不备份
      }
      return DriveBackupPlan._(
        drive: drive,
        files: files,
        shaOf: shaOf,
        previewsToSend: toSend,
        vibes: vibes,
        vibesToSend: {
          for (final v in vibes)
            if (!names.contains('v_${v.key}')) v.key,
        },
        free: free,
        tagCount: state.entries.length,
      );
    } catch (_) {
      drive.close();
      rethrow;
    }
  }

  /// 按 [plan] 备份。没选的那块沿用上一份清单里的。
  /// → (灵感库条数, 新传预览, 没传上的预览, 新传 Vibe, 没传上的 Vibe)
  Future<
    ({
      int entries,
      int previews,
      int previewsFailed,
      int vibes,
      int vibesFailed,
    })
  >
  backup(
    DriveBackupPlan plan, {
    required bool inspiration,
    required bool vibes,
    DriveProgress? onProgress,
  }) async {
    final drive = plan.drive;
    try {
      final manifests = _manifests(plan.files);
      Map<String, dynamic>? prev;
      if (manifests.isNotEmpty) {
        try {
          prev = await _readManifest(drive, manifests.first.$1.id);
        } on FormatException {
          prev = null; // 坏了:当没有,这次也不删旧文件(见 _prune)
        }
      }

      // 预览:三张一起传;断网就整次停下,空间满了剩下的不再传
      final failedShas = <String>{};
      var sentPreviews = 0;
      if (inspiration) {
        final todo = plan.previewsToSend.entries.toList();
        final total = todo.length;
        final bytesTotal = plan.previewBytes;
        var done = 0, bytesDone = 0;
        final inFlight = <String, int>{};
        Object? stop;
        void report() => onProgress?.call(
          '上传预览',
          done,
          total,
          bytesDone + inFlight.values.fold(0, (a, b) => a + b),
          bytesTotal,
        );
        Future<void> worker() async {
          while (todo.isNotEmpty) {
            final MapEntry(key: sha, value: pic) = todo.removeLast();
            if (stop != null) {
              failedShas.add(sha);
              continue;
            }
            try {
              await drive.createFile(
                'p_$sha',
                File(pic.path),
                onSent: (n) {
                  inFlight[sha] = n;
                  report();
                },
              );
              sentPreviews++;
            } on DriveException catch (e) {
              failedShas.add(sha);
              if (e.status == null || e.status == 403) stop = e;
            } catch (_) {
              failedShas.add(sha);
            }
            inFlight.remove(sha);
            bytesDone += pic.size;
            done++;
            report();
          }
        }

        report();
        await Future.wait([for (var i = 0; i < 3; i++) worker()]);
        if (stop case final DriveException e when e.status == null) throw e;
      }

      // Vibe:传缺的;没传上的沿用上一份清单里同 id 的那版
      final vibeRows = <Map<String, dynamic>>[];
      var sentVibes = 0, failedVibes = 0;
      if (vibes) {
        final prevById = {for (final v in _vibeList(prev)) '${v['id']}': v};
        final lib = ref.read(vibeLibraryProvider.notifier);
        final todo = [
          for (final v in plan.vibes)
            if (plan.vibesToSend.contains(v.key)) v.entry.sizeBytes,
        ];
        final total = todo.length;
        final bytesTotal = todo.fold(0, (a, b) => a + b);
        var done = 0, bytesDone = 0;
        for (final (:entry, :key) in plan.vibes) {
          var row = <String, dynamic>{
            'key': key,
            'id': entry.id,
            'name': entry.name,
            'bytes': entry.sizeBytes,
          };
          if (plan.vibesToSend.contains(key)) {
            onProgress?.call('上传 Vibe', done, total, bytesDone, bytesTotal);
            try {
              final bytes = utf8.encode(
                jsonEncode(await lib.rawForUpload(entry)),
              );
              await drive.createBytes(
                'v_$key',
                bytes,
                mime: 'application/json',
                onSent: (n) => onProgress?.call(
                  '上传 Vibe',
                  done,
                  total,
                  bytesDone + (n * entry.sizeBytes ~/ bytes.length),
                  bytesTotal,
                ),
              );
              sentVibes++;
            } on DriveException catch (e) {
              if (e.status == null) rethrow;
              failedVibes++;
              row = prevById[entry.id] ?? const {};
            } catch (_) {
              failedVibes++;
              row = prevById[entry.id] ?? const {};
            }
            done++;
            bytesDone += entry.sizeBytes;
            onProgress?.call('上传 Vibe', done, total, bytesDone, bytesTotal);
          }
          if (row.isNotEmpty) vibeRows.add(row);
        }
      }

      onProgress?.call('写入清单', 0, 0, 0, 0);
      final lib = ref.read(tagLibraryProvider.notifier);
      final refs = {
        for (final e in plan.shaOf.entries)
          if (!failedShas.contains(e.value)) e.key: previewRef(e.value),
      };
      final now = DateTime.now();
      final ms = now.millisecondsSinceEpoch;
      final prevAt = manifests.isEmpty ? ms : manifests.first.$2;
      final body = <String, dynamic>{
        'identifier': kLocalBackupIdentifier,
        'version': kLocalBackupVersion,
        'createdAt': now.toIso8601String(),
        'inspirationAt': inspiration ? ms : prev?['inspirationAt'] ?? prevAt,
        'vibesAt': vibes ? ms : prev?['vibesAt'] ?? prevAt,
        'inspiration': inspiration
            ? {
                'categories': lib.encodeBackup(refs: refs),
                'custom': lib.encodeCustom(refs: refs),
                'pools': lib.encodePools(),
                'codex_favorites': ref
                    .read(codexFavoritesProvider.notifier)
                    .encodeBackup(),
              }
            : prev?['inspiration'],
        'vibes': vibes ? vibeRows : prev?['vibes'],
      };
      await drive.createBytes(
        '$_manifestPrefix$ms.json',
        utf8.encode(jsonEncode(body)),
        mime: 'application/json',
        props: _sections(body, ms),
      );

      await _prune(drive, plan.files, manifests, [body, ?prev]);
      return (
        entries: _entryCount(body['inspiration']),
        previews: sentPreviews,
        previewsFailed: failedShas.length,
        vibes: sentVibes,
        vibesFailed: failedVibes,
      );
    } finally {
      drive.close();
    }
  }

  /// 清单只留最近 [_keep] 份,哪份都不引用的文件删掉。读不到旧清单就这次不删文件。
  Future<void> _prune(
    DriveClient drive,
    List<DriveFile> files,
    List<(DriveFile, int)> manifests,
    List<Map<String, dynamic>> known,
  ) async {
    final kept = [...known];
    try {
      for (final (f, _)
          in manifests.skip(known.length - 1).take(_keep - known.length)) {
        kept.add(await _readManifest(drive, f.id));
      }
    } catch (_) {
      return;
    }
    for (final (f, _) in manifests.skip(_keep - 1)) {
      try {
        await drive.delete(f.id);
      } catch (_) {}
    }
    final used = <String>{};
    for (final body in kept) {
      _collectRefs(body['inspiration'], used);
      for (final v in _vibeList(body)) {
        used.add('v_${v['key']}');
      }
    }
    final seen = <String>{};
    for (final f in files) {
      if (!f.name.startsWith('p_') && !f.name.startsWith('v_')) continue;
      // 同名的多传了一份也删掉
      if (used.contains(f.name) && seen.add(f.name)) continue;
      try {
        await drive.delete(f.id);
      } catch (_) {}
    }
  }

  static void _collectRefs(Object? node, Set<String> out) {
    switch (node) {
      case String s:
        if (previewRefSha(s) case final String sha) out.add('p_$sha');
      case Map m:
        for (final v in m.values) {
          _collectRefs(v, out);
        }
      case List l:
        for (final v in l) {
          _collectRefs(v, out);
        }
    }
  }

  /// 灵感库块里的条数(内置分类 + 自定义分类)。
  static int _entryCount(Object? inspiration) {
    if (inspiration is! Map) return 0;
    var n = 0;
    for (final v in [
      ...?(inspiration['categories'] as Map?)?.values,
      ...?((inspiration['custom'] as Map?)?['items'] as Map?)?.values,
    ]) {
      if (v is List) n += v.length;
    }
    return n;
  }

  static int entryCount(DriveSnapshot s) => _entryCount(s.inspiration);

  /// 最新那份备份;一份都没有返回 null。
  Future<DriveSnapshot?> snapshot() async {
    final drive = _open(interactive: true);
    try {
      final files = await drive.list();
      final ms = _manifests(files);
      if (ms.isEmpty) {
        drive.close();
        return null;
      }
      final body = await _readManifest(drive, ms.first.$1.id);
      return DriveSnapshot._(
        drive,
        DateTime.fromMillisecondsSinceEpoch(ms.first.$2),
        body,
        {for (final f in files) f.name: f.id},
      );
    } catch (_) {
      drive.close();
      rethrow;
    }
  }

  /// 恢复:灵感库按 id 合并、预览本机有的直接用;Vibe 同 id 覆盖。
  /// → (灵感库每类新增 / 覆盖, Vibe 条数)
  Future<({Map<TagCategory, ({int added, int updated})>? stat, int vibes})>
  restore(
    DriveSnapshot snap, {
    required bool inspiration,
    required bool vibes,
    void Function(String label, int done, int total)? onProgress,
  }) async {
    final drive = snap.drive;
    final local = ref.read(localBackupProvider);
    try {
      Map<TagCategory, ({int added, int updated})>? stat;
      if (inspiration && snap.inspiration != null) {
        stat = (await local.mergeInspiration(
          snap.inspiration!,
          source: (sha) async => switch (snap.ids['p_$sha']) {
            final String id => await drive.download(id),
            _ => null,
          },
          label: '恢复预览',
          onProgress: onProgress,
        )).stat;
      }
      var n = 0;
      if (vibes) {
        final rows = snap.vibes;
        n = await local.importVibeBlobs(
          rows.length,
          (i) async => switch (snap.ids['v_${rows[i]['key']}']) {
            final String id => await drive.download(id),
            _ => null,
          },
          label: '恢复 Vibe',
          onProgress: onProgress,
        );
      }
      return (stat: stat, vibes: n);
    } finally {
      drive.close();
    }
  }
}

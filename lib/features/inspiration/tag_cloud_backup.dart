import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/net/backend_client.dart';
import '../../core/store/atomic_file.dart';
import '../../core/store/storage_stats.dart' show fmtBytes;
import 'codex/codex_favorites.dart';
import 'tag_library.dart';
import 'tag_models.dart';

/// 本机预览图的 sha256 缓存(`<support>/tag_preview_hashes.json`):路径 → [大小, 修改时间毫秒, sha]。
/// 预览文件落盘后不再改写,大小和修改时间都没变就不重算。
class PreviewHashes {
  PreviewHashes._(this._file, this._map);

  final File _file;
  final Map<String, (int, int, String)> _map;
  var _dirty = false;

  static Future<PreviewHashes> open() async {
    final sup = await getApplicationSupportDirectory();
    final f = File('${sup.path}/tag_preview_hashes.json');
    final map = <String, (int, int, String)>{};
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is Map) {
        for (final e in j.entries) {
          if (e.value case [final int size, final int ms, final String sha]) {
            map['${e.key}'] = (size, ms, sha);
          }
        }
      }
    } catch (_) {} // 没有或坏了:按空的重算
    return PreviewHashes._(f, map);
  }

  /// 文件内容的 sha256;文件不在返回 null。
  Future<String?> shaOf(String path) async {
    final st = await File(path).stat();
    if (st.type != FileSystemEntityType.file) return null;
    final ms = st.modified.millisecondsSinceEpoch;
    final hit = _map[path];
    if (hit != null && hit.$1 == st.size && hit.$2 == ms) return hit.$3;
    final sha = await Isolate.run(
      () => sha256.convert(File(path).readAsBytesSync()).toString(),
    );
    _map[path] = (st.size, ms, sha);
    _dirty = true;
    return sha;
  }

  /// 一批文件里没算过的,在后台 isolate 里一次算完(之后 [shaOf] 直接命中)。
  Future<void> prime(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    final miss = <String>[];
    final stats = <String, (int, int)>{};
    for (final p in paths) {
      try {
        final st = await File(p).stat();
        if (st.type != FileSystemEntityType.file) continue;
        final ms = st.modified.millisecondsSinceEpoch;
        final hit = _map[p];
        if (hit != null && hit.$1 == st.size && hit.$2 == ms) continue;
        miss.add(p);
        stats[p] = (st.size, ms);
      } catch (_) {}
    }
    const chunk = 64;
    for (var i = 0; i < miss.length; i += chunk) {
      final part = miss.sublist(i, math.min(i + chunk, miss.length));
      final shas = await _shaOfFilesInIsolate(part);
      for (var k = 0; k < part.length; k++) {
        final sha = shas[k];
        if (sha == null) continue;
        final st = stats[part[k]]!;
        _map[part[k]] = (st.$1, st.$2, sha);
        _dirty = true;
      }
      onProgress?.call(math.min(i + chunk, miss.length), miss.length);
    }
  }

  /// 记下刚落盘的文件(内容已知是 [sha])。
  Future<void> remember(String path, String sha) async {
    final st = await File(path).stat();
    _map[path] = (st.size, st.modified.millisecondsSinceEpoch, sha);
    _dirty = true;
  }

  /// 内容是 [sha] 的一个本机文件(缓存里记过、且还在);没有返回 null。
  String? pathOf(String sha) {
    for (final e in _map.entries) {
      if (e.value.$3 == sha && File(e.key).existsSync()) return e.key;
    }
    return null;
  }

  /// 落盘,顺手去掉已经不在的文件。
  Future<void> save() async {
    final gone = await _missingInIsolate(_map.keys.toList());
    if (!_dirty && gone.isEmpty) return;
    gone.forEach(_map.remove);
    try {
      await writeStringAtomic(
        _file,
        jsonEncode({
          for (final e in _map.entries)
            e.key: [e.value.$1, e.value.$2, e.value.$3],
        }),
      );
      _dirty = false;
    } catch (_) {} // 下次重算,不影响备份本身
  }
}

Future<List<String?>> _shaOfFilesInIsolate(List<String> paths) => Isolate.run(
  () => [
    for (final p in paths)
      () {
        try {
          return sha256.convert(File(p).readAsBytesSync()).toString();
        } catch (_) {
          return null;
        }
      }(),
  ],
);

Future<List<String>> _missingInIsolate(List<String> paths) => Isolate.run(
  () => [
    for (final p in paths)
      if (!File(p).existsSync()) p,
  ],
);

final tagCloudBackupProvider = Provider<TagCloudBackup>(TagCloudBackup.new);

/// 云端预览图每人额度(与后端 PREVIEW_QUOTA 一致)。
const kPreviewQuotaBytes = 2 * 1024 * 1024 * 1024;

/// 灵感库云备份:条目、自定义类别、标签池、法典收藏走 `/user-tag-backup` 整体覆盖;
/// 本机预览图按内容哈希单独存(`/user-tag-previews`),条目里写引用,只传云端没有的。
class TagCloudBackup {
  TagCloudBackup(this.ref);

  final Ref ref;

  BackendClient get _client => ref.read(backendClientProvider);

  /// 本机预览图总大小(字节,同一文件只算一次)。备份前给用户看、超额度直接拒绝用。
  Future<int> localPreviewBytes() async {
    await ref.read(tagLibraryProvider.future);
    var n = 0;
    for (final p in ref.read(tagLibraryProvider.notifier).localPreviewFiles()) {
      try {
        n += await File(p).length();
      } catch (_) {} // 文件不在了:不传,也不算
    }
    return n;
  }

  /// 上传。要新传的预览超出云端剩余额度时整次不传、抛 [BackendException]。
  /// [onBytes] 报预览上传的 (已传字节, 要传字节)。
  /// → (条目数, 预览新传几张, 几张没传上, 额度满了没)
  Future<({int entries, int uploaded, int failed, bool quotaFull})> upload(
    String sessionId, {
    void Function(String label, int done, int total)? onProgress,
    void Function(int done, int total)? onBytes,
  }) async {
    // 两个库都要读完再打包:没载入完就打包等于拿空的整体覆盖云端
    await ref.read(tagLibraryProvider.future);
    await ref.read(codexFavoritesProvider.future);
    final lib = ref.read(tagLibraryProvider.notifier);

    final files = lib.localPreviewFiles().toList();
    final hashes = await PreviewHashes.open();
    await hashes.prime(
      files,
      onProgress: (d, t) => onProgress?.call('整理预览', d, t),
    );
    final shaOf = <String, String>{};
    for (var i = 0; i < files.length; i++) {
      onProgress?.call('整理预览', i + 1, files.length);
      try {
        if (await hashes.shaOf(files[i]) case final String sha) {
          shaOf[files[i]] = sha;
        }
      } catch (_) {} // 读不出的那张当没有
    }
    await hashes.save();

    final fileOf = {for (final e in shaOf.entries) e.value: e.key};
    final failed = <String>{};
    var missing = const <String>[];
    var need = 0;
    if (fileOf.isNotEmpty) {
      try {
        final check = await _client.checkTagPreviews(
          sessionId,
          fileOf.keys.toList(),
        );
        missing = check.missing;
        for (final sha in missing) {
          try {
            need += await File(fileOf[sha]!).length();
          } catch (_) {}
        }
        if (check.quota > 0 && check.used + need > check.quota) {
          throw BackendException(
            '预览图要新传 ${fmtBytes(need)},云端已用 ${fmtBytes(check.used)},'
            '超出 ${fmtBytes(check.quota)} 额度,没有上传',
            status: 413,
          );
        }
      } on BackendException catch (e) {
        if (e.status != 404) rethrow;
        failed.addAll(fileOf.keys); // 后端还没有预览接口:条目照传,预览这次不带
      }
    }
    var uploaded = 0;
    var sent = 0;
    var quotaFull = false;
    for (var i = 0; i < missing.length; i++) {
      onBytes?.call(sent, need);
      onProgress?.call('上传预览', i + 1, missing.length);
      final sha = missing[i];
      if (quotaFull) {
        failed.add(sha);
        continue;
      }
      try {
        final bytes = await File(fileOf[sha]!).readAsBytes();
        await _client.uploadTagPreview(sessionId, sha, bytes);
        uploaded++;
        sent += bytes.length;
      } on BackendException catch (e) {
        failed.add(sha);
        if (e.status == 413) quotaFull = true;
      } catch (_) {
        failed.add(sha);
      }
    }
    if (missing.isNotEmpty) onBytes?.call(sent, need);

    onProgress?.call('上传灵感库', 0, 0);
    final refs = {
      for (final e in shaOf.entries)
        if (!failed.contains(e.value)) e.key: previewRef(e.value),
    };
    await _client.uploadTagBackup(
      sessionId: sessionId,
      categories: lib.encodeBackup(refs: refs),
      custom: lib.encodeCustom(refs: refs),
      pools: lib.encodePools(),
      codexFavorites: ref.read(codexFavoritesProvider.notifier).encodeBackup(),
    );
    return (
      entries: ref.read(tagLibraryProvider).value?.entries.length ?? 0,
      uploaded: uploaded,
      failed: failed.length,
      quotaFull: quotaFull,
    );
  }

  /// 恢复:条目按 id 合并,预览本机已有的直接用、没有的才下载;标签池、法典收藏合并。
  /// → (每类新增 / 覆盖, 法典收藏新增几条)
  Future<
    ({Map<TagCategory, ({int added, int updated})> stat, int favoritesAdded})
  >
  restore(
    ({
      Map<String, dynamic> categories,
      Map<String, dynamic>? custom,
      Map<String, dynamic>? pools,
      List<dynamic>? codexFavorites,
    })
    backup, {
    void Function(String label, int done, int total)? onProgress,
  }) async {
    await ref.read(codexFavoritesProvider.future);
    final lib = ref.read(tagLibraryProvider.notifier);
    final total = TagLibrary.previewRefCount(
      backup.categories,
      custom: backup.custom,
    );
    var done = 0;
    final stat = await withResolver(
      (resolve) => lib.mergeBackup(
        backup.categories,
        custom: backup.custom,
        pools: backup.pools,
        resolvePreview: resolve,
      ),
      onEach: () => onProgress?.call('恢复预览', ++done, total),
    );
    final favs = backup.codexFavorites;
    final added = favs == null
        ? 0
        : await ref.read(codexFavoritesProvider.notifier).mergeBackup(favs);
    return (stat: stat, favoritesAdded: added);
  }

  /// 给 [TagLibrary.mergeBackup] 用的云端预览解析:本地同条目里内容相同的那张直接沿用,
  /// [source](本地备份包、云端硬盘)里有的、本机别处有的拷一份,都没有才从 Plana 云端
  /// 下载;下载失败退成网址。
  /// [onEach] 每解析一张调一次。
  Future<T> withResolver<T>(
    Future<T> Function(PreviewResolver resolve) body, {
    void Function()? onEach,
    FutureOr<Uint8List?> Function(String sha)? source,
  }) async {
    final hashes = await PreviewHashes.open();
    Future<String> resolve(
      String sha,
      String entryId,
      int index,
      List<String> localPaths,
    ) async {
      onEach?.call();
      for (final p in localPaths) {
        if (p.startsWith('http')) continue;
        try {
          if (await hashes.shaOf(p) == sha) return p;
        } catch (_) {}
      }
      Uint8List? bytes;
      try {
        bytes = await source?.call(sha);
      } catch (_) {} // 取不到:往下找
      if (bytes == null) {
        if (hashes.pathOf(sha) case final String known) {
          try {
            bytes = await File(known).readAsBytes();
          } catch (_) {}
        }
      }
      try {
        bytes ??= await _client.fetchTagPreview(sha);
        final path = await TagLibrary.savePreviewBytes(entryId, index, bytes);
        await hashes.remember(path, sha);
        return path;
      } catch (_) {
        return _client.tagPreviewUrl(sha);
      }
    }

    try {
      return await body(resolve);
    } finally {
      await hashes.save();
    }
  }
}

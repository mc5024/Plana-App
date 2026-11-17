import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/store/cache_sweep.dart' show kShareCacheDir;
import '../inspiration/codex/codex_favorites.dart';
import '../inspiration/tag_cloud_backup.dart';
import '../inspiration/tag_library.dart';
import '../inspiration/tag_models.dart';
import '../vibe_library/vibe_library.dart';

const kLocalBackupIdentifier = 'plana-app-backup';
const kLocalBackupVersion = 1;

/// 本地备份包(zip,一律不压缩:预览是 PNG / JPG,vibe 里也大多是 base64 的图):
/// ```
/// manifest.json         {identifier, version, createdAt, inspiration?: 条数, vibes?: 条数}
/// inspiration.json      {categories, custom, pools, codex_favorites},与云备份同形
/// previews/<sha256>     预览原图
/// vibes/<序号>.naiv4vibe 每条一个文件,带全部编码
/// ```
/// 条目里的预览写成和云端一样的引用(`/api/user-tag-previews/<sha>`):包里有的
/// 从包里取,没有的(打包时就只在云端)按云端预览去取。
final localBackupProvider = Provider<LocalBackup>(LocalBackup.new);

/// 打开的备份包:目录和清单读进内存,条目内容用到时才从文件里读。
class LocalBackupFile {
  LocalBackupFile._(this._input, this._zip, this.manifest);

  final InputFileStream _input;
  final Archive _zip;
  final Map<String, dynamic> manifest;

  /// 文件头是 zip 才可能是备份包。
  static Future<bool> isZip(String path) async {
    try {
      final raf = await File(path).open();
      try {
        final head = await raf.read(4);
        return head.length == 4 &&
            head[0] == 0x50 &&
            head[1] == 0x4b &&
            head[2] == 0x03 &&
            head[3] == 0x04;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 不是本 App 的备份包抛 [FormatException],消息可直接给用户看。
  static LocalBackupFile open(String path) {
    final input = InputFileStream(path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      final m = zip.findFile('manifest.json');
      final j = m == null ? null : jsonDecode(utf8.decode(m.content));
      if (j is! Map<String, dynamic> ||
          j['identifier'] != kLocalBackupIdentifier) {
        throw const FormatException('不是 Plana 的备份文件');
      }
      if (j['version'] != kLocalBackupVersion) {
        throw FormatException('不支持的备份版本:${j['version']}');
      }
      return LocalBackupFile._(input, zip, j);
    } on FormatException {
      input.closeSync();
      rethrow;
    } catch (_) {
      input.closeSync();
      throw const FormatException('备份文件损坏或不完整');
    }
  }

  int get inspirationCount => (manifest['inspiration'] as num?)?.toInt() ?? 0;
  int get vibeCount => (manifest['vibes'] as num?)?.toInt() ?? 0;

  Map<String, dynamic>? inspiration() {
    final f = _zip.findFile('inspiration.json');
    if (f == null) return null;
    final j = jsonDecode(utf8.decode(f.content));
    return j is Map<String, dynamic> ? j : null;
  }

  Uint8List? preview(String sha) => _zip.findFile('previews/$sha')?.content;

  List<ArchiveFile> vibeFiles() => [
    for (final f in _zip.files)
      if (f.isFile && f.name.startsWith('vibes/')) f,
  ];

  Future<void> close() => _input.close();
}

class LocalBackup {
  LocalBackup(this.ref);

  final Ref ref;

  /// 打包,返回缓存目录里的 zip(交给系统保存对话框后即可丢弃)。
  Future<File> export({
    required bool inspiration,
    required bool vibes,
    void Function(String label, int done, int total)? onProgress,
  }) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/$kShareCacheDir',
    );
    await dir.create(recursive: true);
    final out = File('${dir.path}/plana_backup.zip');
    final zip = ZipFileEncoder()..create(out.path);
    final manifest = <String, dynamic>{
      'identifier': kLocalBackupIdentifier,
      'version': kLocalBackupVersion,
      'createdAt': DateTime.now().toIso8601String(),
    };
    try {
      if (inspiration) {
        manifest['inspiration'] = await _packInspiration(zip, onProgress);
      }
      if (vibes) manifest['vibes'] = await _packVibes(zip, onProgress);
      _addBytes(zip, 'manifest.json', utf8.encode(jsonEncode(manifest)));
      await zip.close();
      return out;
    } catch (_) {
      try {
        await zip.close();
      } catch (_) {}
      try {
        await out.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<int> _packInspiration(
    ZipFileEncoder zip,
    void Function(String, int, int)? onProgress,
  ) async {
    final state = await ref.read(tagLibraryProvider.future);
    await ref.read(codexFavoritesProvider.future);
    final lib = ref.read(tagLibraryProvider.notifier);
    final files = lib.localPreviewFiles().toList();
    final hashes = await PreviewHashes.open();
    final refs = <String, String>{};
    final packed = <String>{};
    for (var i = 0; i < files.length; i++) {
      onProgress?.call('打包预览', i + 1, files.length);
      final String? sha;
      try {
        sha = await hashes.shaOf(files[i]);
      } catch (_) {
        continue; // 读不出的那张当没有
      }
      if (sha == null) continue;
      refs[files[i]] = previewRef(sha);
      if (packed.add(sha)) {
        final input = InputFileStream(files[i]);
        try {
          zip.addArchiveFile(
            _stored(ArchiveFile.stream('previews/$sha', input)),
          );
        } finally {
          await input.close();
        }
      }
      await Future<void>.delayed(Duration.zero);
    }
    await hashes.save();
    _addBytes(
      zip,
      'inspiration.json',
      utf8.encode(
        jsonEncode({
          'categories': lib.encodeBackup(refs: refs),
          'custom': lib.encodeCustom(refs: refs),
          'pools': lib.encodePools(),
          'codex_favorites': ref
              .read(codexFavoritesProvider.notifier)
              .encodeBackup(),
        }),
      ),
    );
    return state.entries.length;
  }

  Future<int> _packVibes(
    ZipFileEncoder zip,
    void Function(String, int, int)? onProgress,
  ) async {
    final list = await ref.read(vibeLibraryProvider.future);
    final lib = ref.read(vibeLibraryProvider.notifier);
    for (var i = 0; i < list.length; i++) {
      onProgress?.call('打包 Vibe', i + 1, list.length);
      final raw = await lib.rawForUpload(list[i]);
      _addBytes(zip, 'vibes/$i.naiv4vibe', utf8.encode(jsonEncode(raw)));
      await Future<void>.delayed(Duration.zero);
    }
    return list.length;
  }

  static ArchiveFile _stored(ArchiveFile f) =>
      f..compression = CompressionType.none;

  static void _addBytes(ZipFileEncoder zip, String name, List<int> bytes) =>
      zip.addArchiveFile(_stored(ArchiveFile.bytes(name, bytes)));

  /// 灵感库并入本机:条目按 id 合并,预览先从包里取;标签池、法典收藏合并。
  /// → (每类新增 / 覆盖, 法典收藏新增)
  Future<
    ({Map<TagCategory, ({int added, int updated})> stat, int favoritesAdded})
  >
  importInspiration(
    LocalBackupFile file, {
    void Function(String label, int done, int total)? onProgress,
  }) {
    final j = file.inspiration();
    if (j == null) throw const FormatException('备份里没有灵感库');
    return mergeInspiration(
      j,
      source: file.preview,
      label: '导入预览',
      onProgress: onProgress,
    );
  }

  /// 把 `inspiration.json` 那份内容并入本机,预览先从 [source] 取。
  Future<
    ({Map<TagCategory, ({int added, int updated})> stat, int favoritesAdded})
  >
  mergeInspiration(
    Map<String, dynamic> j, {
    FutureOr<Uint8List?> Function(String sha)? source,
    required String label,
    void Function(String label, int done, int total)? onProgress,
  }) async {
    final categories = j['categories'] is Map<String, dynamic>
        ? j['categories'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final custom = j['custom'] is Map<String, dynamic>
        ? j['custom'] as Map<String, dynamic>
        : null;
    await ref.read(codexFavoritesProvider.future);
    final total = TagLibrary.previewRefCount(categories, custom: custom);
    var done = 0;
    final stat = await ref
        .read(tagCloudBackupProvider)
        .withResolver(
          (resolve) => ref
              .read(tagLibraryProvider.notifier)
              .mergeBackup(
                categories,
                custom: custom,
                pools: j['pools'] is Map<String, dynamic>
                    ? j['pools'] as Map<String, dynamic>
                    : null,
                resolvePreview: resolve,
              ),
          source: source,
          onEach: () => onProgress?.call(label, ++done, total),
        );
    final favs = j['codex_favorites'];
    final added = favs is List
        ? await ref.read(codexFavoritesProvider.notifier).mergeBackup(favs)
        : 0;
    return (stat: stat, favoritesAdded: added);
  }

  /// Vibe 并入本机(同 id 覆盖)。→ 条数
  Future<int> importVibes(
    LocalBackupFile file, {
    void Function(String label, int done, int total)? onProgress,
  }) {
    final files = file.vibeFiles();
    return importVibeBlobs(
      files.length,
      (i) async => files[i].content,
      label: '导入 Vibe',
      onProgress: onProgress,
    );
  }

  /// Vibe 并入本机(同 id 覆盖),[read] 取第 i 条的 .naiv4vibe 内容(null = 没有)。
  /// 分批落库,别把整包 vibe 同时摊在内存里。→ 条数
  Future<int> importVibeBlobs(
    int count,
    Future<Uint8List?> Function(int i) read, {
    required String label,
    void Function(String label, int done, int total)? onProgress,
  }) async {
    final lib = ref.read(vibeLibraryProvider.notifier);
    var n = 0;
    for (var i = 0; i < count; i += 20) {
      final raws = <Map<String, dynamic>>[];
      for (var k = i; k < count && k < i + 20; k++) {
        final bytes = await read(k);
        onProgress?.call(label, k + 1, count);
        if (bytes == null) continue;
        try {
          final j = jsonDecode(utf8.decode(bytes));
          if (j is Map<String, dynamic>) raws.add(j);
        } catch (_) {} // 坏的那条跳过
      }
      n += (await lib.importVibeRaws(raws)).length;
    }
    return n;
  }
}

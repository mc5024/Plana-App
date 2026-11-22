import '../../core/util/log.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/store/atomic_file.dart';
import '../../core/store/storage_settings.dart';
import '../../core/util/image_ops.dart';

/// 顶层函数:后台 isolate 算图片字节哈希(内容寻址键 = 条目 id)。
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// 角色参考图库条目(轻量;列表页只碰它和缩略图)。
/// 角色参考是「裸原图」——无编码、无后端、无标签,故极简:一图一条。
class CharRefEntry {
  const CharRefEntry({
    required this.id,
    required this.name,
    required this.fileName,
    this.createdAt = 0,
    this.lastUsedAt = 0,
    this.sizeBytes = 0,
  });

  /// = 原图字节 sha256 hex;既是内容寻址去重键,也是生成项的 imageHash。
  final String id;
  final String name;

  /// files/ 目录下的原图文件名。
  final String fileName;
  final int createdAt;
  final int lastUsedAt; // 0 = 未用过
  final int sizeBytes;

  /// 排序权重:用过看最近使用,没用过看入库时间 —— 最近的浮到最前。
  int get recency => lastUsedAt > 0 ? lastUsedAt : createdAt;

  CharRefEntry copyWith({String? name, int? lastUsedAt}) => CharRefEntry(
    id: id,
    name: name ?? this.name,
    fileName: fileName,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    sizeBytes: sizeBytes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'createdAt': createdAt,
    'lastUsedAt': lastUsedAt,
    'sizeBytes': sizeBytes,
  };

  static CharRefEntry? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final fileName = j['fileName'];
    if (id is! String || fileName is! String) return null;
    return CharRefEntry(
      id: id,
      name: j['name'] is String ? j['name'] as String : '',
      fileName: fileName,
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      lastUsedAt: (j['lastUsedAt'] as num?)?.toInt() ?? 0,
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 角色参考图库:`<support>/charref_library/` 下 files/ 存原图、thumbs/ 存缩略图,
/// 旁挂 index.json。生成页导入参考图时自动入库(同图去重),生成成功后回写「最近使用」。
final charLibraryProvider =
    AsyncNotifierProvider<CharLibrary, List<CharRefEntry>>(CharLibrary.new);

class CharLibrary extends AsyncNotifier<List<CharRefEntry>> {
  late Directory _root;

  Directory get _filesDir => Directory('${_root.path}/files');
  Directory get _thumbsDir => Directory('${_root.path}/thumbs');
  File get _indexFile => File('${_root.path}/index.json');

  File fileOf(CharRefEntry e) => File('${_filesDir.path}/${e.fileName}');

  /// 缩略图文件(可能不存在,UI 用 errorBuilder 兜底)。
  File thumbOf(CharRefEntry e) => File('${_thumbsDir.path}/${e.id}.png');

  @override
  Future<List<CharRefEntry>> build() async {
    // 上限设置就绪/变更时裁剪(超出删「最久未用」的)
    ref.listen(storageSettingsProvider, (_, next) {
      if (next.hasValue) enforceCap();
    });
    final sup = await getApplicationSupportDirectory();
    _root = Directory('${sup.path}/charref_library');
    await _filesDir.create(recursive: true);
    await _thumbsDir.create(recursive: true);
    try {
      if (await _indexFile.exists()) {
        final j = jsonDecode(await _indexFile.readAsString());
        if (j is Map && j['entries'] is List) {
          return [
            for (final e in j['entries'] as List)
              if (e is Map<String, dynamic>)
                if (CharRefEntry.fromJson(e) case final CharRefEntry v) v,
          ];
        }
      }
    } catch (_) {
      // 索引损坏 → 从文件重建
    }
    return _rebuildFromFiles();
  }

  // ---- 内部 ----

  List<CharRefEntry> get _entries => state.value ?? const [];

  CharRefEntry? _byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> _setEntries(List<CharRefEntry> list) {
    state = AsyncData(List.unmodifiable(list));
    final text = jsonEncode({
      'version': 1,
      'entries': [for (final e in list) e.toJson()],
    });
    // 排队一次写一份,先写临时文件再改名
    return _indexWrite = _indexWrite.then((_) async {
      try {
        await writeStringAtomic(_indexFile, text);
      } catch (e) {
        logd('[char-lib] 写索引失败: $e');
      }
    });
  }

  Future<void> _indexWrite = Future.value();

  /// 索引丢失时从 files/ 全量重建(缩略图缺失则现算)。
  Future<List<CharRefEntry>> _rebuildFromFiles() async {
    final out = <CharRefEntry>[];
    try {
      await for (final ent in _filesDir.list()) {
        if (ent is! File) continue;
        final fileName = ent.uri.pathSegments.last;
        final id = fileName.split('.').first;
        if (id.isEmpty) continue;
        try {
          final bytes = await ent.readAsBytes();
          final tf = File('${_thumbsDir.path}/$id.png');
          if (!await tf.exists()) {
            await tf.writeAsBytes(
              await coverResizePng(bytes, 256, 256, keepAlpha: true),
            );
          }
          out.add(
            CharRefEntry(
              id: id,
              name: '参考图',
              fileName: fileName,
              createdAt: (await ent.stat()).modified.millisecondsSinceEpoch,
              sizeBytes: bytes.length,
            ),
          );
        } catch (err) {
          logd('[char-lib] 重建跳过 ${ent.path}: $err');
        }
      }
      out.sort((a, b) => b.recency.compareTo(a.recency));
      await _setEntries(out);
    } catch (e) {
      logd('[char-lib] 重建失败: $e');
    }
    return out;
  }

  // ---- 导入 / 取用 ----

  /// 图片入库(生成页导入参考图时顺手调用)。同图(同内容哈希)已在库中则直接返回既有条目。
  /// [knownHash]:调用方已算好的字节哈希(避免重复计算)。
  Future<CharRefEntry> importImageBytes(
    Uint8List bytes,
    String name, {
    String? knownHash,
  }) async {
    await future;
    final id = knownHash ?? await compute<Uint8List, String>(_sha256Hex, bytes);
    final dup = _byId(id);
    if (dup != null) return dup;

    final fileName = '$id.img';
    await File('${_filesDir.path}/$fileName').writeAsBytes(bytes);
    try {
      await thumbOf(
        CharRefEntry(id: id, name: '', fileName: fileName),
      ).writeAsBytes(await coverResizePng(bytes, 256, 256, keepAlpha: true));
    } catch (_) {}

    final entry = CharRefEntry(
      id: id,
      name: name.trim().isEmpty ? '参考图' : name.trim(),
      fileName: fileName,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: bytes.length,
    );
    await _setEntries([entry, ..._entries]);
    await enforceCap();
    return entry;
  }

  /// 清空整库(存储管理页):原图/缩略图/索引一并删净。
  Future<void> clearAll() async {
    await future;
    for (final e in [..._entries]) {
      try {
        await fileOf(e).delete();
      } catch (_) {}
      try {
        await thumbOf(e).delete();
      } catch (_) {}
    }
    await _setEntries(const []);
  }

  /// 库上限裁剪:超出上限删「最久未用」的(recency 排序尾部)。
  Future<void> enforceCap() async {
    await future;
    final cap = ref.read(storageSettingsProvider).value?.charRefCap ?? 0;
    if (cap <= 0 || _entries.length <= cap) return;
    final sorted = [..._entries]
      ..sort((a, b) => b.recency.compareTo(a.recency));
    for (final e in sorted.sublist(cap)) {
      await delete(e.id);
    }
  }

  /// 读原图字节(添加到生成用)。
  Future<Uint8List?> loadImageBytes(CharRefEntry e) async {
    try {
      return await fileOf(e).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  // ---- 编辑 ----

  Future<void> rename(String id, String name) async {
    await future;
    final n = name.trim();
    if (n.isEmpty) return;
    final e = _byId(id);
    if (e == null) return;
    await _setEntries([
      for (final x in _entries) x.id == id ? x.copyWith(name: n) : x,
    ]);
  }

  Future<void> delete(String id) async {
    await future;
    final e = _byId(id);
    if (e == null) return;
    try {
      await fileOf(e).delete();
    } catch (_) {}
    try {
      await thumbOf(e).delete();
    } catch (_) {}
    await _setEntries([..._entries]..removeWhere((x) => x.id == id));
  }

  /// 生成成功后回写「最近使用」(内容哈希即条目 id)。
  Future<void> markUsed(Set<String> ids) async {
    await future;
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var hit = false;
    final list = <CharRefEntry>[];
    for (final e in _entries) {
      if (ids.contains(e.id)) {
        hit = true;
        list.add(e.copyWith(lastUsedAt: now));
      } else {
        list.add(e);
      }
    }
    if (hit) await _setEntries(list);
  }
}

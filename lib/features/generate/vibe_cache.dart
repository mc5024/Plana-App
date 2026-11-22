import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../vibe_library/naiv4vibe_codec.dart' show jsNum, kModelToEncodingKey;

/// 持久化的 Vibe 编码缓存(目录制):每条编码一个文件,
/// 文件名 `{图字节哈希}_{模型键}_{IE}.enc`,内容即编码串。
/// 内容寻址,重选同图 / 重启 / 直连↔bot 互切均命中,不重复编码扣点;
/// 也是编码的**唯一真相**——.naiv4vibe 文件里的 encodings 只在导入时灌入、
/// 导出时收集,生成链路只查这里。
///
/// 模型段统一存 encodings 键(v4-5full 等),curated 与 curated-preview 归并。
/// 旧版单 JSON(vibe_encode_cache.json,LRU 48 条)首次加载时自动迁移。
final vibeCacheProvider = FutureProvider<VibeEncodeCache>(
  (ref) => VibeEncodeCache.load(),
);

class VibeEncodeCache {
  VibeEncodeCache._(this._dir, this._names);

  final Directory _dir;
  final Set<String> _names; // 已有文件名索引;值按需读盘

  /// 写盘失败时的内存兜底(本会话仍可命中)。
  final Map<String, String> _mem = {};

  static String _normModel(String model) => kModelToEncodingKey[model] ?? model;

  /// 某条编码在缓存目录里的文件名。
  static String fileNameOf(String imageHash, String model, double ie) =>
      '${imageHash}_${_normModel(model)}_${jsNum(ie)}.enc';

  /// 缓存目录。
  String get dirPath => _dir.path;

  static Future<VibeEncodeCache> load() async {
    Directory? dir;
    final names = <String>{};
    try {
      final sup = await getApplicationSupportDirectory();
      dir = Directory('${sup.path}/vibe_encodings');
      await dir.create(recursive: true);

      // 旧版单 JSON 迁移:键 `hash|apiModel|ie`(ie 为 Dart toString 格式)。
      final legacy = File('${sup.path}/vibe_encode_cache.json');
      if (await legacy.exists()) {
        try {
          final decoded = jsonDecode(await legacy.readAsString());
          if (decoded is Map) {
            for (final e in decoded.entries) {
              final k = e.key;
              final v = e.value;
              if (k is! String || v is! String || v.isEmpty) continue;
              final parts = k.split('|');
              if (parts.length != 3) continue;
              final ie = double.tryParse(parts[2]);
              if (ie == null) continue;
              await File(
                '${dir.path}/${fileNameOf(parts[0], parts[1], ie)}',
              ).writeAsString(v);
            }
          }
          await legacy.delete();
        } catch (_) {
          // 迁移失败不致命:代价是老编码 miss 后重编一次
        }
      }

      await for (final ent in dir.list()) {
        if (ent is File && ent.path.endsWith('.enc')) {
          names.add(ent.uri.pathSegments.last);
        }
      }
    } catch (_) {
      // 目录不可用按空缓存起步(只影响命中率,不影响生成)
    }
    return VibeEncodeCache._(dir ?? Directory('vibe_encodings'), names);
  }

  Future<String?> get(String imageHash, String model, double ie) async {
    final n = fileNameOf(imageHash, model, ie);
    final mem = _mem[n];
    if (mem != null) return mem;
    if (!_names.contains(n)) return null;
    try {
      final s = await File('${_dir.path}/$n').readAsString();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// 这条编码从哪读:只在内存里的给编码串,落了盘的给文件路径;没有为 null。
  ({String? path, String? encoding})? sourceOf(
    String imageHash,
    String model,
    double ie,
  ) {
    final n = fileNameOf(imageHash, model, ie);
    final mem = _mem[n];
    if (mem != null) return (path: null, encoding: mem);
    if (!_names.contains(n)) return null;
    return (path: '${_dir.path}/$n', encoding: null);
  }

  Future<void> put(
    String imageHash,
    String model,
    double ie,
    String encoding,
  ) async {
    final n = fileNameOf(imageHash, model, ie);
    try {
      await File('${_dir.path}/$n').writeAsString(encoding);
      _names.add(n);
      _mem.remove(n);
    } catch (_) {
      _mem[n] = encoding; // 落盘失败:内存兜底,本会话可用
    }
  }

  /// 已缓存编码条数(存储管理展示用)。
  int get entryCount => {..._names, ..._mem.keys}.length;

  /// 清空全部编码(存储管理):下次生成同图需重新编码
  /// (直连线路每张扣 2 Anlas)。
  Future<void> clear() async {
    try {
      await for (final ent in _dir.list()) {
        if (ent is File && ent.path.endsWith('.enc')) {
          try {
            await ent.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    _names.clear();
    _mem.clear();
  }

  /// 图字节哈希 → 已缓存的模型键集合。库列表一次建表用:每张卡各扫一遍全表
  /// 是 O(卡数 × 缓存条数)。
  Map<String, Set<String>> modelKeysByImage() {
    final out = <String, Set<String>>{};
    for (final n in {..._names, ..._mem.keys}) {
      if (!n.endsWith('.enc')) continue;
      // 文件名 {哈希}_{模型键}_{IE}.enc:哈希是十六进制不含 _,
      // 模型键含 - 不含 _,所以首尾两个 _ 就是分界。
      final rest = n.substring(0, n.length - 4);
      final i = rest.indexOf('_');
      final j = rest.lastIndexOf('_');
      if (i <= 0 || j <= i) continue;
      (out[rest.substring(0, i)] ??= <String>{}).add(rest.substring(i + 1, j));
    }
    return out;
  }

  /// 某张图已缓存的编码清单(modelKey + IE)——编码清单展示与导出收集用。
  List<({String modelKey, double ie})> entriesForImage(String imageHash) {
    final out = <({String modelKey, double ie})>[];
    final prefix = '${imageHash}_';
    for (final n in {..._names, ..._mem.keys}) {
      if (!n.startsWith(prefix) || !n.endsWith('.enc')) continue;
      final rest = n.substring(prefix.length, n.length - 4); // modelKey_ie
      final i = rest.lastIndexOf('_');
      if (i <= 0) continue;
      final ie = double.tryParse(rest.substring(i + 1));
      if (ie == null) continue;
      out.add((modelKey: rest.substring(0, i), ie: ie));
    }
    out.sort((a, b) {
      final c = a.modelKey.compareTo(b.modelKey);
      return c != 0 ? c : a.ie.compareTo(b.ie);
    });
    return out;
  }
}

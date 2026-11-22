import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

/// 存储管理的目录扫描:各功能位置的占用与条目数。
/// 纯文件系统视角,不碰业务 provider——扫描不加载任何库。
class StorageCategory {
  const StorageCategory({required this.key, required this.bytes, this.count});

  final String key;
  final int bytes;

  /// 条目数(图库张数/blob 个数/编码条数…);不适用为 null。
  final int? count;
}

class StorageReport {
  const StorageReport({
    required this.totalBytes,
    required this.categories,
    required this.otherBytes,
  });

  /// 应用数据总占用(支持目录 + 缓存 + 文档;不含安装包本体)。
  final int totalBytes;
  final List<StorageCategory> categories;

  /// 未归类部分(debug 资产解压/系统杂项/零散配置)。
  final int otherBytes;

  StorageCategory? operator [](String key) {
    for (final c in categories) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// 上一次扫描的结果(本次运行内):再进存储页先摆它,新的扫完再换。
StorageReport? lastStorageReport;

/// 全量扫描。key 清单:gallery / blobs / vibeLib / vibeEnc / charLib /
/// imgCache / codexCache / tagPrev / models / temp。
///
/// 分类要跟着新目录一起加 —— 漏一个,那块占用就只能沉进 [StorageReport.otherBytes]
/// 里,用户看着「其他」莫名涨几十 MB 又找不到清理入口(法典缓存单部最大 ~11 MB,
/// 就这么隐身过一阵)。
///
/// 在后台 isolate 里同步遍历,每个文件只 stat 一次;总量 = 各目录之和。
Future<StorageReport> scanStorage() async {
  final sup = (await getApplicationSupportDirectory()).path;
  final tmp = (await getTemporaryDirectory()).path;
  String? docs;
  try {
    docs = (await getApplicationDocumentsDirectory()).path;
  } catch (_) {}
  final rep = await _scanInIsolate(sup, tmp, docs);
  return lastStorageReport = rep;
}

Future<StorageReport> _scanInIsolate(String sup, String tmp, String? docs) =>
    Isolate.run(() => _scanSync(sup, tmp, docs));

/// 目录 → 支持目录下的分类 key(条目数按哪个子目录、哪些后缀数)。
const _supDirs = <String, ({String key, String? countIn, List<String> ends})>{
  'gallery': (key: 'gallery', countIn: 'images', ends: ['.png', '.webp']),
  'blobs': (key: 'blobs', countIn: '', ends: []),
  'vibe_library': (key: 'vibeLib', countIn: 'files', ends: []),
  'vibe_encodings': (key: 'vibeEnc', countIn: '', ends: ['.enc']),
  'charref_library': (key: 'charLib', countIn: 'files', ends: []),
  'img_cache': (key: 'imgCache', countIn: '', ends: []),
  'codex_cache': (key: 'codexCache', countIn: '', ends: ['.json']),
  'tag_previews': (key: 'tagPrev', countIn: '', ends: ['.jpg']),
};

StorageReport _scanSync(String sup, String tmp, String? docs) {
  final bytes = <String, int>{};
  final counts = <String, int?>{};
  var supTotal = 0;
  // 超分模型:支持目录顶层的 .bin/.param。
  // 本地超分已于 2026-08-24 整条下线,这些文件现在是**纯遗留垃圾** —— 但仍然
  // 单独成组、由用户点一下才删:悄悄删掉用户机器上的文件不是我们该做的事。
  var modelBytes = 0, modelCount = 0;
  try {
    for (final e in Directory(sup).listSync(followLinks: false)) {
      final name = _baseName(e.path);
      if (e is File) {
        final n = _lengthOf(e);
        supTotal += n;
        if (name.endsWith('.bin') || name.endsWith('.param')) {
          modelBytes += n;
          modelCount++;
        }
      } else if (e is Directory) {
        final n = _treeSize(e);
        supTotal += n;
        final spec = _supDirs[name];
        if (spec != null) {
          bytes[spec.key] = n;
          counts[spec.key] = _countIn(
            spec.countIn!.isEmpty ? e.path : '${e.path}/${spec.countIn}',
            spec.ends,
          );
        }
      }
    }
  } catch (_) {}
  final tmpBytes = _treeSize(Directory(tmp));
  final categories = <StorageCategory>[
    for (final spec in _supDirs.values)
      StorageCategory(
        key: spec.key,
        bytes: bytes[spec.key] ?? 0,
        count: counts.containsKey(spec.key) ? counts[spec.key] : 0,
      ),
    StorageCategory(key: 'models', bytes: modelBytes, count: modelCount),
    StorageCategory(key: 'temp', bytes: tmpBytes, count: _countIn(tmp, [])),
  ];
  final total =
      supTotal + tmpBytes + (docs == null ? 0 : _treeSize(Directory(docs)));
  var categorized = 0;
  for (final c in categories) {
    categorized += c.bytes;
  }
  return StorageReport(
    totalBytes: total,
    categories: categories,
    otherBytes: (total - categorized).clamp(0, total),
  );
}

String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return path.substring(i + 1);
}

int _lengthOf(File f) {
  try {
    return f.lengthSync();
  } catch (_) {
    return 0;
  }
}

int _treeSize(Directory d) {
  var sum = 0;
  try {
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) sum += _lengthOf(e);
    }
  } catch (_) {}
  return sum;
}

int? _countIn(String dir, List<String> ends) {
  try {
    final d = Directory(dir);
    if (!d.existsSync()) return 0;
    var n = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (ends.isEmpty || ends.any(e.path.endsWith)) n++;
    }
    return n;
  } catch (_) {
    return null;
  }
}

/// 删除遗留的角色库缓存 `role_tag_mapping.json`(~6.5MB)。
///
/// 2026-08-25 角色·作品补全全量改走上游、角色识别下线之后,这个文件再也没人
/// 读了,但已经装过旧版的机器上它还躺在支持目录里 —— 而且不在任何一个可清理
/// 分组里,用户自己按不掉。所以随开机维护静默删掉,和选图器缓存清扫同一档:
/// 纯网络缓存、删了不少任何功能,不需要惊动用户(与 [clearUpscaleModels] 那种
/// 「让用户自己按一下」的不同 —— 那些是用户当初主动下载的模型)。
Future<void> clearRetiredRoleLexicon() async {
  try {
    final sup = await getApplicationSupportDirectory();
    final f = File('${sup.path}/role_tag_mapping.json');
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// 删除遗留的超分模型文件。本地超分下线后它们已经没有任何用处,删了不会
/// 少任何功能;仍然单独成组是为了让用户自己按一下,而不是替他做主。
///
/// 扫的是支持目录**顶层**的 `.bin`/`.param`,与 [scanStorage] 的 `models`
/// 口径一致。blob 仓在 `blobs/` 子目录里,扫不到,不会被误删。
Future<void> clearUpscaleModels() async {
  try {
    final sup = await getApplicationSupportDirectory();
    await for (final e in sup.list(followLinks: false)) {
      if (e is File && (e.path.endsWith('.bin') || e.path.endsWith('.param'))) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// 人读字节格式(1.2 GB / 34.5 MB / 890 KB / 12 B)。
String fmtBytes(int bytes) {
  if (bytes >= 1 << 30) {
    return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

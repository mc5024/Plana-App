import 'dart:io';

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

Future<int> _sizeOf(FileSystemEntity ent) async {
  try {
    if (ent is File) {
      return await ent.exists() ? await ent.length() : 0;
    }
    if (ent is Directory) {
      if (!await ent.exists()) return 0;
      var sum = 0;
      await for (final e in ent.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            sum += await e.length();
          } catch (_) {}
        }
      }
      return sum;
    }
  } catch (_) {}
  return 0;
}

Future<int?> _countIn(
  Directory d, {
  String? suffix,
  List<String>? suffixes,
}) async {
  final ends = suffixes ?? [?suffix];
  try {
    if (!await d.exists()) return 0;
    var n = 0;
    await for (final e in d.list(followLinks: false)) {
      if (ends.isEmpty || ends.any(e.path.endsWith)) n++;
    }
    return n;
  } catch (_) {
    return null;
  }
}

/// 全量扫描。key 清单:gallery / blobs / vibeLib / vibeEnc / charLib /
/// imgCache / codexCache / tagPrev / models / temp。
///
/// 分类要跟着新目录一起加 —— 漏一个,那块占用就只能沉进 [StorageReport.otherBytes]
/// 里,用户看着「其他」莫名涨几十 MB 又找不到清理入口(法典缓存单部最大 ~11 MB,
/// 就这么隐身过一阵)。
Future<StorageReport> scanStorage() async {
  final sup = await getApplicationSupportDirectory();
  final tmp = await getTemporaryDirectory();
  Directory? docs;
  try {
    docs = await getApplicationDocumentsDirectory();
  } catch (_) {}

  Directory sub(String p) => Directory('${sup.path}/$p');

  // 超分模型:支持目录顶层的 .bin/.param。
  // 本地超分已于 2026-08-24 整条下线,这些文件现在是**纯遗留垃圾** —— 但仍然
  // 单独成组、由用户点一下才删:悄悄删掉用户机器上的文件不是我们该做的事。
  var modelBytes = 0;
  var modelCount = 0;
  try {
    await for (final e in sup.list(followLinks: false)) {
      if (e is File && (e.path.endsWith('.bin') || e.path.endsWith('.param'))) {
        try {
          modelBytes += await e.length();
          modelCount++;
        } catch (_) {}
      }
    }
  } catch (_) {}

  final categories = <StorageCategory>[
    StorageCategory(
      key: 'gallery',
      bytes: await _sizeOf(sub('gallery')),
      count: await _countIn(
        Directory('${sup.path}/gallery/images'),
        suffixes: const ['.png', '.webp'],
      ),
    ),
    StorageCategory(
      key: 'blobs',
      bytes: await _sizeOf(sub('blobs')),
      count: await _countIn(sub('blobs')),
    ),
    StorageCategory(
      key: 'vibeLib',
      bytes: await _sizeOf(sub('vibe_library')),
      count: await _countIn(Directory('${sup.path}/vibe_library/files')),
    ),
    StorageCategory(
      key: 'vibeEnc',
      bytes: await _sizeOf(sub('vibe_encodings')),
      count: await _countIn(sub('vibe_encodings'), suffix: '.enc'),
    ),
    StorageCategory(
      key: 'charLib',
      bytes: await _sizeOf(sub('charref_library')),
      count: await _countIn(Directory('${sup.path}/charref_library/files')),
    ),
    StorageCategory(
      key: 'imgCache',
      bytes: await _sizeOf(sub('img_cache')),
      count: await _countIn(sub('img_cache')),
    ),
    StorageCategory(
      key: 'codexCache',
      bytes: await _sizeOf(sub('codex_cache')),
      count: await _countIn(sub('codex_cache'), suffix: '.json'),
    ),
    StorageCategory(
      key: 'tagPrev',
      bytes: await _sizeOf(sub('tag_previews')),
      count: await _countIn(sub('tag_previews'), suffix: '.jpg'),
    ),
    StorageCategory(key: 'models', bytes: modelBytes, count: modelCount),
    StorageCategory(
      key: 'temp',
      bytes: await _sizeOf(tmp),
      count: await _countIn(tmp),
    ),
  ];

  final total =
      await _sizeOf(sup) +
      await _sizeOf(tmp) +
      (docs == null ? 0 : await _sizeOf(docs));
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

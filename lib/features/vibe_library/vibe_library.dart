import '../../core/util/log.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/store/atomic_file.dart';
import '../../core/store/storage_settings.dart';
import '../../core/util/image_ops.dart';
import '../generate/vibe_cache.dart';
import 'naiv4vibe_codec.dart';

/// 顶层函数:后台 isolate 算图片字节哈希(编码缓存的内容寻址键)。
String sha256HexOfBytes(Uint8List bytes) => sha256.convert(bytes).toString();

/// 一条 vibe 完整 JSON 的出处:.naiv4vibe 文件 + 缓存里该图各条编码从哪读
/// (见 [VibeEncodeCache.sourceOf])。
typedef VibeRawSource = ({
  String file,
  List<({String modelKey, double ie, String? path, String? encoding})>
  encodings,
});

/// 按 [VibeRawSource] 读出文件本体并合并全部编码。同步 IO,在后台 isolate 里调。
Map<String, dynamic> readRawMergedSync(VibeRawSource s) {
  final raw =
      jsonDecode(File(s.file).readAsStringSync()) as Map<String, dynamic>;
  for (final e in s.encodings) {
    var enc = e.encoding;
    if (enc == null && e.path != null) {
      try {
        enc = File(e.path!).readAsStringSync();
      } catch (_) {}
    }
    if (enc == null || enc.isEmpty) continue;
    mergeEncodingIntoRaw(
      raw,
      modelKey: e.modelKey,
      infoExtracted: e.ie,
      encoding: enc,
    );
  }
  return raw;
}

Future<Map<String, dynamic>> _readRawMergedIsolate(VibeRawSource s) =>
    Isolate.run(() => readRawMergedSync(s));

/// 重建索引时扫出的一条,不带原图。[newEncodings] 是编码缓存里还没有的那些。
typedef _ScannedVibe = ({
  String fileName,
  String id,
  String name,
  String? imageHash,
  bool hasImage,
  double? defaultStrength,
  double? defaultInfoExtracted,
  List<String> supportedModels,
  List<String> tags,
  int createdAt,
  int sizeBytes,
  List<VibeEncodingItem> newEncodings,
});

/// [only] 非空时只扫这些文件名。
typedef _ScanDirs = ({
  String files,
  String thumbs,
  String encodings,
  Set<String>? only,
});

Future<List<_ScannedVibe>> _scanVibeFilesInIsolate(_ScanDirs dirs) =>
    Isolate.run(() => _scanVibeFiles(dirs));

/// 后台 isolate:逐个解析 files/ 下的 .naiv4vibe,算原图哈希,缺的缩略图补上。
List<_ScannedVibe> _scanVibeFiles(_ScanDirs dirs) {
  final out = <_ScannedVibe>[];
  for (final ent in Directory(dirs.files).listSync()) {
    if (ent is! File || !ent.path.endsWith('.naiv4vibe')) continue;
    if (dirs.only case final only?
        when !only.contains(ent.uri.pathSegments.last)) {
      continue;
    }
    try {
      final text = ent.readAsStringSync();
      final parsed = parseVibeFileText(text);
      if (parsed.isEmpty) continue;
      final p = parsed.first;
      final id = VibeLibrary.idOfParsed(p);
      final b64 = p.imageBase64;
      final bytes = b64 == null ? null : base64Decode(b64);
      final hash = bytes == null ? null : sha256HexOfBytes(bytes);
      final thumb = File('${dirs.thumbs}/${VibeLibrary._safeName(id)}.png');
      if (!thumb.existsSync()) {
        try {
          final png = bytes != null
              ? _thumbPngSync(bytes)
              : switch (p.thumbnailDataUrl) {
                  final t? => base64Decode(t.split(',').last),
                  null => null,
                };
          if (png != null) thumb.writeAsBytesSync(png);
        } catch (_) {}
      }
      out.add((
        fileName: ent.uri.pathSegments.last,
        id: id,
        name: p.name,
        imageHash: hash,
        hasImage: b64 != null,
        defaultStrength: p.defaultStrength,
        defaultInfoExtracted: p.defaultInfoExtracted,
        supportedModels: p.supportedModelKeys,
        tags: p.tags,
        createdAt: p.createdAt,
        sizeBytes: text.length,
        newEncodings: [
          if (hash != null)
            for (final it in p.encodingItems)
              if (it.infoExtracted case final ie?)
                if (!File(
                  '${dirs.encodings}/'
                  '${VibeEncodeCache.fileNameOf(hash, it.modelKey, ie)}',
                ).existsSync())
                  it,
        ],
      ));
    } catch (_) {} // 坏文件跳过
  }
  return out;
}

/// 导入落好盘的一条:文件写好、缩略图做好,主线程只组条目、灌编码。
typedef _IngestedVibe = ({
  String id,
  String fileName,
  int sizeBytes,
  String? imageHash,
  bool hasImage,
  String name,
  double? defaultStrength,
  double? defaultInfoExtracted,
  List<String> supportedModels,
  List<String> tags,
  int createdAt,
  List<VibeEncodingItem> encodings,
});

/// [srcs] 每项是解析好的 vibe JSON(Map)或 .naiv4vibe 文件字节;[base] 是
/// 第一项在整批里的序号(没 id 也没图的条目拿它拼 id)。
typedef _IngestJob = ({
  List<Object> srcs,
  int base,
  int stamp,
  String files,
  String thumbs,
});

Future<List<_IngestedVibe>> _ingestInIsolate(_IngestJob job) =>
    Isolate.run(() => _ingestVibes(job));

/// 后台 isolate:逐条落盘、算原图哈希、做缩略图。读不懂的跳过。
List<_IngestedVibe> _ingestVibes(_IngestJob job) {
  final out = <_IngestedVibe>[];
  for (var k = 0; k < job.srcs.length; k++) {
    try {
      final src = job.srcs[k];
      final j = src is Uint8List ? jsonDecode(utf8.decode(src)) : src;
      if (j is! Map<String, dynamic>) continue;
      final p = ParsedVibe(j);
      final b64 = p.imageBase64;
      final id = p.id.isNotEmpty
          ? p.id
          : (b64 != null
                ? naiVibeIdOfBase64(b64)
                : 'enc_${job.stamp}_${job.base + k}');
      final fileName = '${VibeLibrary._safeName(id)}.naiv4vibe';
      final text = jsonEncode(p.raw);
      final tmp = File('${job.files}/$fileName.tmp')
        ..writeAsStringSync(text, flush: true);
      tmp.renameSync('${job.files}/$fileName');
      final bytes = b64 == null ? null : base64Decode(b64);
      // 有原图时缩略图一律从原图现做(导入文件的 thumbnail 可能是截断伪图)
      try {
        final png = bytes != null
            ? _thumbPngSync(bytes)
            : switch (p.thumbnailDataUrl) {
                final t? => base64Decode(t.split(',').last),
                null => null,
              };
        if (png != null) {
          File(
            '${job.thumbs}/${VibeLibrary._safeName(id)}.png',
          ).writeAsBytesSync(png);
        }
      } catch (_) {}
      out.add((
        id: id,
        fileName: fileName,
        sizeBytes: text.length,
        imageHash: bytes == null ? null : sha256HexOfBytes(bytes),
        hasImage: b64 != null,
        name: p.name,
        defaultStrength: p.defaultStrength,
        defaultInfoExtracted: p.defaultInfoExtracted,
        supportedModels: p.supportedModelKeys,
        tags: p.tags,
        createdAt: p.createdAt,
        encodings: p.encodingItems,
      ));
    } catch (_) {}
  }
  return out;
}

/// 改一条 vibe 文件里的字段。[strength] / [infoExtracted] 有值时补全 importInfo,
/// 缺的项用 [model] / [fallbackStrength] / [fallbackIe]。
typedef _VibeEdit = ({
  String path,
  List<String>? tags,
  String? name,
  double? strength,
  double? infoExtracted,
  String model,
  double fallbackStrength,
  double fallbackIe,
});

Future<List<int?>> _editVibeFilesInIsolate(List<_VibeEdit> edits) =>
    Isolate.run(() => [for (final e in edits) _editVibeFile(e)]);

/// 后台 isolate:读改写一条 vibe 文件(原子替换)。返回新文本长度,失败 null。
int? _editVibeFile(_VibeEdit ed) {
  try {
    final raw =
        jsonDecode(File(ed.path).readAsStringSync()) as Map<String, dynamic>;
    if (ed.tags != null) raw['tags'] = ed.tags;
    if (ed.name != null) raw['name'] = ed.name;
    if (ed.strength != null || ed.infoExtracted != null) {
      final info = raw['importInfo'] is Map
          ? (raw['importInfo'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      info['model'] ??= ed.model;
      if (ed.strength != null) info['strength'] = ed.strength;
      if (ed.infoExtracted != null) {
        info['information_extracted'] = ed.infoExtracted;
      }
      info['strength'] ??= ed.fallbackStrength;
      info['information_extracted'] ??= ed.fallbackIe;
      raw['importInfo'] = info;
    }
    final text = jsonEncode(raw);
    final tmp = File('${ed.path}.tmp')..writeAsStringSync(text, flush: true);
    tmp.renameSync(ed.path);
    return text.length;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _vibeImageInIsolate(String path) =>
    Isolate.run(() => _vibeImageOf(path));

Uint8List? _vibeImageOf(String path) {
  final raw = jsonDecode(File(path).readAsStringSync());
  final img = raw is Map ? raw['image'] : null;
  return img is String && img.isNotEmpty ? base64Decode(img) : null;
}

Future<VibeForGenerate?> _forGenerateInIsolate(
  String path,
  String? knownHash,
  double? defaultIe,
) => Isolate.run(() => _forGenerate(path, knownHash, defaultIe));

/// 后台 isolate:有图 → 原图字节 + 哈希;纯编码 → 每模型键选一条编码
/// (优先贴近默认 IE)+ 固定 IE。
VibeForGenerate? _forGenerate(
  String path,
  String? knownHash,
  double? defaultIe,
) {
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final p = ParsedVibe(raw);
  final img = p.imageBase64;
  if (img != null) {
    final bytes = base64Decode(img);
    return (
      image: bytes,
      imageHash: knownHash ?? sha256HexOfBytes(bytes),
      encodedByModel: null,
      fixedInfoExtracted: defaultIe ?? 1.0,
    );
  }
  final prefer = defaultIe ?? p.defaultInfoExtracted ?? 1.0;
  final byModel = <String, String>{};
  double? pickedIe;
  for (final it in p.encodingItems) {
    final cur = byModel[it.modelKey];
    if (cur == null) {
      byModel[it.modelKey] = it.encoding;
      pickedIe ??= it.infoExtracted;
    } else if (it.infoExtracted != null &&
        (pickedIe == null ||
            (it.infoExtracted! - prefer).abs() < (pickedIe - prefer).abs())) {
      byModel[it.modelKey] = it.encoding;
      pickedIe = it.infoExtracted;
    }
  }
  if (byModel.isEmpty) return null;
  return (
    image: null,
    imageHash: null,
    encodedByModel: byModel,
    fixedInfoExtracted: pickedIe ?? prefer,
  );
}

/// 原图 cover 裁成 256 方图的 PNG(保留透明)。
Uint8List? _thumbPngSync(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  return img.encodePng(
    img.copyResizeCropSquare(
      src,
      size: 256,
      interpolation: img.Interpolation.average,
    ),
  );
}

/// 库索引条目(轻量,列表页只碰它和缩略图,不 parse 大 JSON)。
class VibeEntry {
  const VibeEntry({
    required this.id,
    required this.name,
    required this.fileName,
    this.imageHash,
    this.hasImage = true,
    this.defaultStrength,
    this.defaultInfoExtracted,
    this.supportedModels = const [],
    this.tags = const [],
    this.createdAt = 0,
    this.lastUsedAt = 0,
    this.sizeBytes = 0,
    this.originFilename,
    this.cloudFilename,
    this.cloudImageHash,
    this.cloudMetaHash,
    this.pushedImageHash,
    this.pushedMetaFp,
  });

  /// NAI 官方 vibe id(SHA256 of base64 文本);纯编码文件为其自带 id。
  final String id;
  final String name;

  /// files/ 目录下的文件名。
  final String fileName;

  /// 原图**字节**哈希(编码缓存键);纯编码 vibe 为 null。
  final String? imageHash;
  final bool hasImage;

  final double? defaultStrength;
  final double? defaultInfoExtracted;

  /// 文件自带 encodings 的模型键(v4-5full 等,徽标展示用;
  /// 缓存里后续新增的编码不回填这里,详情页实时合并)。
  final List<String> supportedModels;

  final List<String> tags;
  final int createdAt;
  final int lastUsedAt; // 0 = 未用过
  final int sizeBytes;

  /// 公共库来源文件名(仅从公共库收藏的条目有);app 私有关联,只存 index.json,
  /// 索引重建时会丢失(仅影响公共 tab 的「已收藏」标记,不影响功能)。
  final String? originFilename;

  // ---- 个人云端备份状态(只存 index.json;索引重建后归零 = 退化为整包重传)----

  /// 本条在云端对应的文件名(推送成功后由后端给出),改元数据时定向 PUT 用。
  final String? cloudFilename;

  /// 上次同步时后端算出的双 hash:恢复时与云端列表比对,判断该不该覆盖本地。
  final String? cloudImageHash;
  final String? cloudMetaHash;

  /// 上次**推送时**本地的图哈希与元数据指纹:与当前值比对判断本地改没改。
  /// 两者都没变 → 整条跳过不发请求;只有元数据变 → 走 PUT 不重传图。
  final String? pushedImageHash;
  final String? pushedMetaFp;

  /// 元数据指纹:名称/标签/默认参数的规范化拼接(标签排序,顺序不算改动)。
  String get metaFp {
    final t = [...tags]..sort();
    return [
      name,
      t.join(''),
      defaultStrength?.toStringAsFixed(3) ?? '',
      defaultInfoExtracted?.toStringAsFixed(3) ?? '',
    ].join('');
  }

  /// 从未推送过,或推送后本地又改了图/元数据。
  bool get needsPush =>
      cloudFilename == null ||
      pushedImageHash != imageHash ||
      pushedMetaFp != metaFp;

  /// 图没变、只有元数据变 → 可以只 PUT 元数据,省掉整张图的重传。
  bool get canPushMetaOnly =>
      cloudFilename != null && pushedImageHash == imageHash;

  VibeEntry copyWith({
    String? name,
    double? defaultStrength,
    double? defaultInfoExtracted,
    List<String>? tags,
    int? lastUsedAt,
    int? sizeBytes,
    List<String>? supportedModels,
    String? originFilename,
    String? cloudFilename,
    String? cloudImageHash,
    String? cloudMetaHash,
    String? pushedImageHash,
    String? pushedMetaFp,
  }) => VibeEntry(
    id: id,
    name: name ?? this.name,
    fileName: fileName,
    imageHash: imageHash,
    hasImage: hasImage,
    defaultStrength: defaultStrength ?? this.defaultStrength,
    defaultInfoExtracted: defaultInfoExtracted ?? this.defaultInfoExtracted,
    supportedModels: supportedModels ?? this.supportedModels,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    originFilename: originFilename ?? this.originFilename,
    cloudFilename: cloudFilename ?? this.cloudFilename,
    cloudImageHash: cloudImageHash ?? this.cloudImageHash,
    cloudMetaHash: cloudMetaHash ?? this.cloudMetaHash,
    pushedImageHash: pushedImageHash ?? this.pushedImageHash,
    pushedMetaFp: pushedMetaFp ?? this.pushedMetaFp,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    if (imageHash != null) 'imageHash': imageHash,
    'hasImage': hasImage,
    if (defaultStrength != null) 'defaultStrength': defaultStrength,
    if (defaultInfoExtracted != null)
      'defaultInfoExtracted': defaultInfoExtracted,
    'supportedModels': supportedModels,
    'tags': tags,
    'createdAt': createdAt,
    'lastUsedAt': lastUsedAt,
    'sizeBytes': sizeBytes,
    'originFilename': ?originFilename,
    'cloudFilename': ?cloudFilename,
    'cloudImageHash': ?cloudImageHash,
    'cloudMetaHash': ?cloudMetaHash,
    'pushedImageHash': ?pushedImageHash,
    'pushedMetaFp': ?pushedMetaFp,
  };

  static VibeEntry? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final fileName = j['fileName'];
    if (id is! String || fileName is! String) return null;
    return VibeEntry(
      id: id,
      name: j['name'] is String ? j['name'] as String : '',
      fileName: fileName,
      imageHash: j['imageHash'] as String?,
      hasImage: j['hasImage'] != false,
      defaultStrength: (j['defaultStrength'] as num?)?.toDouble(),
      defaultInfoExtracted: (j['defaultInfoExtracted'] as num?)?.toDouble(),
      supportedModels: j['supportedModels'] is List
          ? [
              for (final m in j['supportedModels'] as List)
                if (m is String) m,
            ]
          : const [],
      tags: j['tags'] is List
          ? [
              for (final t in j['tags'] as List)
                if (t is String) t,
            ]
          : const [],
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      lastUsedAt: (j['lastUsedAt'] as num?)?.toInt() ?? 0,
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      originFilename: j['originFilename'] as String?,
      cloudFilename: j['cloudFilename'] as String?,
      cloudImageHash: j['cloudImageHash'] as String?,
      cloudMetaHash: j['cloudMetaHash'] as String?,
      pushedImageHash: j['pushedImageHash'] as String?,
      pushedMetaFp: j['pushedMetaFp'] as String?,
    );
  }
}

/// 从库条目取出的「可生成」数据(添加到生成面板用)。
typedef VibeForGenerate = ({
  Uint8List? image,
  String? imageHash,
  Map<String, String>? encodedByModel,
  double fixedInfoExtracted,
});

/// Vibe 库:`<support>/vibe_library/` 下每条 vibe 一个标准 .naiv4vibe 文件
/// (文件即真相,与 NAI 官方/web 端互通),旁挂 index.json + thumbs/ 供列表页;
/// 索引损坏时从文件全量重建。编码不存这里——唯一真相是内容寻址缓存
/// [vibeCacheProvider],导入时灌入、导出时收集。
final vibeLibraryProvider = AsyncNotifierProvider<VibeLibrary, List<VibeEntry>>(
  VibeLibrary.new,
);

class VibeLibrary extends AsyncNotifier<List<VibeEntry>> {
  late Directory _root;

  /// 用户新建、但可能尚未挂到任何条目的「空标签」登记表(随 index.json 持久化)。
  /// 条目在用的标签仍以文件/条目为准,这里只补充「还没被用过」的那些。
  final Set<String> _registryTags = {};

  Directory get _filesDir => Directory('${_root.path}/files');
  Directory get _thumbsDir => Directory('${_root.path}/thumbs');
  File get _indexFile => File('${_root.path}/index.json');

  File fileOf(VibeEntry e) => File('${_filesDir.path}/${e.fileName}');

  /// 缩略图文件(可能不存在,UI 用 errorBuilder/占位兜底)。
  File thumbOf(VibeEntry e) =>
      File('${_thumbsDir.path}/${_safeName(e.id)}.png');

  @override
  Future<List<VibeEntry>> build() async {
    // 上限设置就绪/变更时裁剪(超出删「最久未用」的)
    ref.listen(storageSettingsProvider, (_, next) {
      if (next.hasValue) enforceCap();
    });
    final sup = await getApplicationSupportDirectory();
    _root = Directory('${sup.path}/vibe_library');
    await _filesDir.create(recursive: true);
    await _thumbsDir.create(recursive: true);
    try {
      if (await _indexFile.exists()) {
        final j = jsonDecode(await _indexFile.readAsString());
        if (j is Map && j['entries'] is List) {
          if (j['tagRegistry'] is List) {
            _registryTags
              ..clear()
              ..addAll([
                for (final t in j['tagRegistry'] as List)
                  if (t is String) t,
              ]);
          }
          unawaited(
            Future(() async {
              await future;
              await _adoptOrphans();
            }),
          );
          return [
            for (final e in j['entries'] as List)
              if (e is Map<String, dynamic>)
                if (VibeEntry.fromJson(e) case final VibeEntry v) v,
          ];
        }
      }
    } catch (_) {
      // 索引损坏 → 从文件重建
    }
    return _rebuildFromFiles();
  }

  // ---- 内部 ----

  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  List<VibeEntry> get _entries => state.value ?? const [];

  VibeEntry? _byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 按公共库来源文件名查已收藏条目(公共 tab 判断「已收藏/已加入」)。
  VibeEntry? entryByOriginFilename(String filename) {
    for (final e in _entries) {
      if (e.originFilename == filename) return e;
    }
    return null;
  }

  Future<void> _setEntries(List<VibeEntry> list) async {
    state = AsyncData(List.unmodifiable(list));
    await _writeIndex(list);
  }

  Future<void> _indexWrite = Future.value();

  /// 写索引:排队一次写一份,先写临时文件再改名。
  Future<void> _writeIndex(List<VibeEntry> list) {
    final text = jsonEncode({
      'version': 1,
      'entries': [for (final e in list) e.toJson()],
      'tagRegistry': _registryTags.toList()..sort(),
    });
    return _indexWrite = _indexWrite.then((_) async {
      try {
        await writeStringAtomic(_indexFile, text);
      } catch (e) {
        logd('[vibe-lib] 写索引失败: $e'); // 内存态仍可用,下次启动会重建
      }
    });
  }

  Future<void> _writeThumb(String id, Uint8List pngBytes) async {
    try {
      await File(
        '${_thumbsDir.path}/${_safeName(id)}.png',
      ).writeAsBytes(pngBytes);
    } catch (_) {}
  }

  /// 解析条目的最终库 id(文件自带 id 优先,无则由图推导/时间戳兜底)。
  static String idOfParsed(ParsedVibe p) => p.id.isNotEmpty
      ? p.id
      : (p.imageBase64 != null
            ? naiVibeIdOfBase64(p.imageBase64!)
            : 'enc_${DateTime.now().millisecondsSinceEpoch}');

  /// 由后台落好盘的结果组装索引条目。
  static VibeEntry _entryFromIngested(
    _IngestedVibe g, {
    String fallbackName = '',
    String? originFilename,
    VibeEntry? existing,
  }) {
    final name = g.name.isNotEmpty
        ? g.name
        : (fallbackName.isNotEmpty ? fallbackName : '未命名 Vibe');
    return VibeEntry(
      id: g.id,
      name: name,
      fileName: g.fileName,
      imageHash: g.imageHash,
      hasImage: g.hasImage,
      defaultStrength: g.defaultStrength ?? existing?.defaultStrength,
      defaultInfoExtracted:
          g.defaultInfoExtracted ?? existing?.defaultInfoExtracted,
      supportedModels: g.supportedModels,
      tags: g.tags.isNotEmpty ? g.tags : (existing?.tags ?? const []),
      createdAt:
          existing?.createdAt ??
          (g.createdAt > 0
              ? g.createdAt
              : DateTime.now().millisecondsSinceEpoch),
      lastUsedAt: existing?.lastUsedAt ?? 0,
      sizeBytes: g.sizeBytes,
      originFilename: originFilename ?? existing?.originFilename,
    );
  }

  /// 把文件自带的编码灌进内容寻址缓存(有原图哈希才有键;无 params 的条目
  /// 定位不了 IE,留在文件里不进缓存,导出时仍保留)。
  Future<void> _seedEncodings(
    List<VibeEncodingItem> items,
    String? imageHash,
  ) async {
    if (imageHash == null) return;
    final cache = await ref.read(vibeCacheProvider.future);
    for (final it in items) {
      final ie = it.infoExtracted;
      if (ie == null) continue;
      await cache.put(imageHash, it.modelKey, ie, it.encoding);
    }
  }

  /// 索引坏了 / 没了:读文件、算哈希、补缩略图都在后台 isolate 里做,
  /// 这里只把结果组装成条目、补进缓存里没有的编码。
  Future<List<VibeEntry>> _rebuildFromFiles() async {
    final out = await _scanEntries();
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeIndex(out);
    return out;
  }

  /// 扫 files/ 组条目;[only] 非空时只扫这些文件名。
  Future<List<VibeEntry>> _scanEntries({Set<String>? only}) async {
    final out = <VibeEntry>[];
    try {
      final cache = await ref.read(vibeCacheProvider.future);
      final scanned = await _scanVibeFilesInIsolate((
        files: _filesDir.path,
        thumbs: _thumbsDir.path,
        encodings: cache.dirPath,
        only: only,
      ));
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final s in scanned) {
        if (s.imageHash case final h?) {
          for (final it in s.newEncodings) {
            await cache.put(h, it.modelKey, it.infoExtracted!, it.encoding);
          }
        }
        out.add(
          VibeEntry(
            id: s.id,
            name: s.name.isNotEmpty ? s.name : '未命名 Vibe',
            fileName: s.fileName,
            imageHash: s.imageHash,
            hasImage: s.hasImage,
            defaultStrength: s.defaultStrength,
            defaultInfoExtracted: s.defaultInfoExtracted,
            supportedModels: s.supportedModels,
            tags: s.tags,
            createdAt: s.createdAt > 0 ? s.createdAt : now,
            sizeBytes: s.sizeBytes,
          ),
        );
      }
    } catch (e) {
      logd('[vibe-lib] 扫描文件失败: $e');
    }
    return out;
  }

  /// 导入到一半被杀:文件落了盘、索引没来得及写。启动后把这些文件收回来。
  Future<void> _adoptOrphans() async {
    final known = {for (final e in _entries) e.fileName};
    final orphans = <String>{};
    try {
      await for (final ent in _filesDir.list()) {
        final n = ent.uri.pathSegments.last;
        if (ent is File && n.endsWith('.naiv4vibe') && !known.contains(n)) {
          orphans.add(n);
        }
      }
    } catch (_) {}
    if (orphans.isEmpty) return;
    final got = await _scanEntries(only: orphans);
    final ids = {for (final e in _entries) e.id};
    final add = [
      for (final e in got)
        if (!ids.contains(e.id)) e,
    ];
    if (add.isNotEmpty) await _setEntries([...add, ..._entries]);
  }

  Future<void> _upsert(VibeEntry e) async {
    final list = [..._entries];
    final i = list.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      list[i] = e;
    } else {
      list.insert(0, e);
    }
    await _setEntries(list);
  }

  // ---- 导入 ----

  /// 图片入库(生成页导入顺手入库/库页导入图片共用)。
  /// 同 id(同图)已在库中时直接返回既有条目,不重复建档。
  /// [knownHash]:调用方已算好的字节哈希(生成页导入时避免重复计算)。
  Future<VibeEntry> importImageBytes(
    Uint8List bytes,
    String name, {
    String? knownHash,
  }) async {
    await future;
    final b64 = base64Encode(bytes);
    final id = naiVibeIdOfBase64(b64);
    final dup = _byId(id);
    if (dup != null) return dup;

    final hash = knownHash ?? await compute(sha256HexOfBytes, bytes);
    final thumb = await coverResizePng(bytes, 256, 256);
    final raw = newImageVibeRaw(
      imageBase64: b64,
      name: name.isEmpty ? '未命名 Vibe' : name,
      thumbnailDataUrl: 'data:image/png;base64,${base64Encode(thumb)}',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final fileName = '${_safeName(id)}.naiv4vibe';
    final text = jsonEncode(raw);
    await File('${_filesDir.path}/$fileName').writeAsString(text);
    await _writeThumb(id, thumb);

    final entry = VibeEntry(
      id: id,
      name: name.isEmpty ? '未命名 Vibe' : name,
      fileName: fileName,
      imageHash: hash,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: text.length,
    );
    await _upsert(entry);
    await enforceCap();
    return entry;
  }

  /// 导入 .naiv4vibe / .naiv4vibebundle 文本;返回落库的条目。
  /// 文件原样落盘(未知字段保留),自带编码灌入缓存(导入即免编码)。
  /// [originFilename]:公共库来源文件名(仅单条从公共库收藏时传)。
  /// 格式不对抛 [FormatException]。
  Future<List<VibeEntry>> importVibeText(
    String text, {
    String fallbackName = '',
    String? originFilename,
  }) async {
    final parsed = parseVibeFileText(text);
    return importVibeRaws(
      [for (final p in parsed) p.raw],
      fallbackName: fallbackName,
      originFilename: parsed.length == 1 ? originFilename : null,
    );
  }

  /// 同 [importVibeText],但吃已解析好的 JSON(流式读大文件用)。
  Future<List<VibeEntry>> importVibeJson(
    Object? j, {
    String fallbackName = '',
    void Function(int done, int total)? onProgress,
  }) => importVibeRaws(
    [for (final p in parseVibeJson(j)) p.raw],
    fallbackName: fallbackName,
    onProgress: onProgress,
  );

  /// 批量导入原始 vibe JSON(每个 map = 一个 .naiv4vibe 文件的内容)。
  ///
  /// 逐条落盘,索引与列表刷新**只在最后做一次**:上百条时既省掉 n 次全量索引
  /// 重写,也省掉 n 次列表重建。调用方也不必先把整批拼成一个大 JSON 串再交进来
  /// —— 那会让同一批 base64 图在内存里多存一到两份,几百条直接 OOM。
  Future<List<VibeEntry>> importVibeRaws(
    List<Map<String, dynamic>> raws, {
    String fallbackName = '',
    String? originFilename,
    void Function(int done, int total)? onProgress,
  }) => _ingest(
    raws,
    fallbackName: fallbackName,
    originFilename: originFilename,
    onProgress: onProgress,
  );

  /// 批量导入 .naiv4vibe 文件字节(备份恢复用):解析也在后台做。
  Future<List<VibeEntry>> importVibeFiles(List<Uint8List> files) =>
      _ingest(files);

  /// 每批这么多条交给一个后台 isolate。
  static const _ingestBatch = 10;

  Future<List<VibeEntry>> _ingest(
    List<Object> srcs, {
    String fallbackName = '',
    String? originFilename,
    void Function(int done, int total)? onProgress,
  }) async {
    await future;
    final kept = [..._entries]; // 库里原有的,按 id 就地覆盖
    final keptAt = {for (var i = 0; i < kept.length; i++) kept[i].id: i};
    final fresh = <VibeEntry>[]; // 本批新增的,最后整体插到最前
    final freshAt = <String, int>{};
    final out = <VibeEntry>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < srcs.length; i += _ingestBatch) {
      final got = await _ingestInIsolate((
        srcs: srcs.sublist(i, math.min(i + _ingestBatch, srcs.length)),
        base: i,
        stamp: stamp,
        files: _filesDir.path,
        thumbs: _thumbsDir.path,
      ));
      for (final g in got) {
        final entry = _entryFromIngested(
          g,
          fallbackName: fallbackName,
          originFilename: originFilename,
          existing: switch ((keptAt[g.id], freshAt[g.id])) {
            (final int i, _) => kept[i],
            (_, final int i) => fresh[i],
            _ => null,
          },
        );
        await _seedEncodings(g.encodings, entry.imageHash);
        if (keptAt[g.id] case final int i) {
          kept[i] = entry;
        } else if (freshAt[g.id] case final int i) {
          fresh[i] = entry; // 同一批里重复的 id,后一条覆盖前一条
        } else {
          freshAt[g.id] = fresh.length;
          fresh.add(entry);
        }
        out.add(entry);
      }
      onProgress?.call(math.min(i + _ingestBatch, srcs.length), srcs.length);
    }

    // 与逐条 upsert 同序:新增的排在最前,后导入的更靠前
    await _setEntries([...fresh.reversed, ...kept]);
    await enforceCap();
    return out;
  }

  // ---- 导出 ----

  /// 单条导出为 .naiv4vibe 文本:文件本体 + 缓存里该图的全部编码合并。
  Future<String> exportText(VibeEntry e) async {
    final raw = await _readRawMerged(e);
    return jsonEncode(raw);
  }

  /// 多条打包为 .naiv4vibebundle 文本。
  Future<String> exportBundleText(List<VibeEntry> entries) async {
    final raws = <Map<String, dynamic>>[];
    for (final e in entries) {
      raws.add(await _readRawMerged(e));
    }
    return buildBundleText(raws);
  }

  Future<Map<String, dynamic>> _readRawMerged(VibeEntry e) async =>
      _readRawMergedIsolate(await rawSourceOf(e));

  /// [rawForUpload] 那份内容的出处,交给后台 isolate 用 [readRawMergedSync] 读。
  Future<VibeRawSource> rawSourceOf(VibeEntry e) async {
    final encs =
        <({String modelKey, double ie, String? path, String? encoding})>[];
    final hash = e.imageHash;
    if (hash != null) {
      final cache = await ref.read(vibeCacheProvider.future);
      for (final it in cache.entriesForImage(hash)) {
        final src = cache.sourceOf(hash, it.modelKey, it.ie);
        if (src == null) continue;
        encs.add((
          modelKey: it.modelKey,
          ie: it.ie,
          path: src.path,
          encoding: src.encoding,
        ));
      }
    }
    return (file: fileOf(e).path, encodings: encs);
  }

  /// 云端备份要推的完整 vibe JSON:文件本体 + 缓存里该图的全部编码。
  /// 与导出同源,保证云端拿到的和用户手动导出的是同一份东西。
  Future<Map<String, dynamic>> rawForUpload(VibeEntry e) => _readRawMerged(e);

  /// [rawForUpload] 那份内容的版本键:文件、元数据或缓存里的编码有变就变。不读文件内容。
  Future<String> backupKey(VibeEntry e) async {
    final st = await fileOf(e).stat();
    final enc = <String>[];
    if (e.imageHash case final h?) {
      final cache = await ref.read(vibeCacheProvider.future);
      for (final it in cache.entriesForImage(h)) {
        enc.add('${it.modelKey}:${it.ie}');
      }
    }
    enc.sort();
    return sha256
        .convert(
          utf8.encode(
            [
              e.id,
              e.metaFp,
              st.size,
              st.modified.millisecondsSinceEpoch,
              ...enc,
            ].join('\n'),
          ),
        )
        .toString();
  }

  /// 回写云端同步状态(推送成功 / 从云端恢复后调用)。
  Future<void> markCloudState(
    String id, {
    String? cloudFilename,
    String? cloudImageHash,
    String? cloudMetaHash,
    String? pushedImageHash,
    String? pushedMetaFp,
  }) async {
    await future;
    final e = _byId(id);
    if (e == null) return;
    await _upsert(
      e.copyWith(
        cloudFilename: cloudFilename,
        cloudImageHash: cloudImageHash,
        cloudMetaHash: cloudMetaHash,
        pushedImageHash: pushedImageHash,
        pushedMetaFp: pushedMetaFp,
      ),
    );
  }

  // ---- 编辑 ----

  /// 改文件用的编辑项(importInfo 缺项按这条的默认值补)。
  _VibeEdit _editOf(
    VibeEntry e, {
    List<String>? tags,
    String? name,
    double? strength,
    double? infoExtracted,
  }) => (
    path: fileOf(e).path,
    tags: tags,
    name: name,
    strength: strength,
    infoExtracted: infoExtracted,
    model: e.supportedModels.isNotEmpty
        ? (kEncodingKeyToModel[e.supportedModels.first] ??
              e.supportedModels.first)
        : 'nai-diffusion-4-5-full',
    fallbackStrength: e.defaultStrength ?? 0.6,
    fallbackIe: e.defaultInfoExtracted ?? 1.0,
  );

  /// 改名 / 默认参数:同时回写文件(name / importInfo)与索引。
  Future<void> updateMeta(
    String id, {
    String? name,
    double? defaultStrength,
    double? defaultInfoExtracted,
  }) async {
    await future;
    final e = _byId(id);
    if (e == null) return;
    final size = (await _editVibeFilesInIsolate([
      _editOf(
        e,
        name: name,
        strength: defaultStrength,
        infoExtracted: defaultInfoExtracted,
      ),
    ])).single;
    if (size == null) {
      logd('[vibe-lib] 更新失败: ${e.id}');
      return;
    }
    await _upsert(
      e.copyWith(
        name: name,
        defaultStrength: defaultStrength,
        defaultInfoExtracted: defaultInfoExtracted,
        sizeBytes: size,
      ),
    );
  }

  /// 设置某条标签(整表覆盖):回写文件 tags + 索引。
  Future<void> setTags(String id, List<String> tags) async {
    await future;
    await _retag({id: tags});
  }

  /// 若干条换标签:文件在后台逐个改写,索引最后写一次。
  Future<void> _retag(Map<String, List<String>> tagsById) async {
    final edits = [
      for (final en in tagsById.entries)
        if (_byId(en.key) case final e?) _editOf(e, tags: en.value),
    ];
    if (edits.isEmpty) return;
    final sizes = await _editVibeFilesInIsolate(edits);
    if (sizes.contains(null)) logd('[vibe-lib] 部分标签没写进文件');
    await _setEntries([
      for (final e in _entries)
        if (tagsById[e.id] case final t?) e.copyWith(tags: t) else e,
    ]);
  }

  /// 批量给多条**追加**标签(已有则跳过)。
  Future<void> addTagToAll(Iterable<String> ids, String tag) async {
    await future;
    await _retag({
      for (final id in ids)
        if (_byId(id) case final e? when !e.tags.contains(tag))
          id: [...e.tags, tag],
    });
  }

  /// 全部已知标签:条目在用的 ∪ 登记表里新建的空标签,升序。
  List<String> get knownTags =>
      (<String>{..._registryTags, for (final e in _entries) ...e.tags}).toList()
        ..sort();

  /// 新建标签(可暂时不挂到任何条目):登记进标签表并持久化。
  /// 返回 false = 已存在(在用或已登记),不重复添加。
  Future<bool> createTag(String name) async {
    await future;
    final t = name.trim();
    if (t.isEmpty) return false;
    if (_registryTags.contains(t) || _entries.any((e) => e.tags.contains(t))) {
      return false;
    }
    _registryTags.add(t);
    await _setEntries([..._entries]); // 持久化 + 通知刷新
    return true;
  }

  /// 全局重命名标签(所有含 [old] 的条目改成 [neu],neu 已存在则合并去重;
  /// 仅登记、未挂条目的空标签也一并改名)。
  Future<void> renameTag(String old, String neu) async {
    await future;
    final n = neu.trim();
    if (old == n || n.isEmpty) return;
    await _retag({
      for (final e in _entries)
        if (e.tags.contains(old))
          e.id: [
            ...{for (final t in e.tags) t == old ? n : t},
          ],
    });
    if (_registryTags.remove(old)) _registryTags.add(n);
    await _setEntries([..._entries]);
  }

  /// 全局删除标签(从所有条目移除,并从登记表移除)。
  Future<void> removeTag(String tag) async {
    await future;
    await _retag({
      for (final e in _entries)
        if (e.tags.contains(tag))
          e.id: [
            for (final t in e.tags)
              if (t != tag) t,
          ],
    });
    _registryTags.remove(tag);
    await _setEntries([..._entries]);
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

  /// 清空整库(存储管理页):原图/缩略图/索引一并删净,不在索引里的残留也删。
  Future<void> clearAll() async {
    await future;
    await _setEntries(const []);
    for (final d in [_filesDir, _thumbsDir]) {
      try {
        await for (final ent in d.list()) {
          try {
            await ent.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  /// 库上限裁剪:超出上限删「最久未用」的(用过看最近使用,
  /// 没用过看入库时间);新导入的最新,永远最后被裁。
  Future<void> enforceCap() async {
    await future;
    final cap = ref.read(storageSettingsProvider).value?.vibeCap ?? 0;
    if (cap <= 0 || _entries.length <= cap) return;
    int recency(VibeEntry e) => e.lastUsedAt > 0 ? e.lastUsedAt : e.createdAt;
    final sorted = [..._entries]
      ..sort((a, b) => recency(b).compareTo(recency(a)));
    final drop = <String>{};
    // 文件逐个删,索引写一次(整包导入后可能一次裁掉上百条)
    for (final e in sorted.sublist(cap)) {
      try {
        await fileOf(e).delete();
      } catch (_) {}
      try {
        await thumbOf(e).delete();
      } catch (_) {}
      drop.add(e.id);
    }
    await _setEntries([
      for (final e in _entries)
        if (!drop.contains(e.id)) e,
    ]);
  }

  /// 生成成功后回写「最近使用」。
  Future<void> markUsed(Set<String> ids) async {
    await future;
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var hit = false;
    final list = <VibeEntry>[];
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

  // ---- 取用 ----

  /// 读原图字节(详情大图/添加到生成用);纯编码 vibe 返回 null。
  Future<Uint8List?> loadImageBytes(VibeEntry e) async {
    if (!e.hasImage) return null;
    try {
      return await _vibeImageInIsolate(fileOf(e).path);
    } catch (_) {
      return null;
    }
  }

  /// 取「可生成」数据:有图 → 原图字节 + 哈希(编码走统一编码服务);
  /// 纯编码 → 每模型键选一条编码(优先贴近默认 IE)+ 固定 IE。
  Future<VibeForGenerate?> loadForGenerate(VibeEntry e) async {
    try {
      return await _forGenerateInIsolate(
        fileOf(e).path,
        e.imageHash,
        e.defaultInfoExtracted,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<({String modelKey, double? ie})>> encodingList(
    VibeEntry e,
  ) async {
    final seen = <String>{};
    final out = <({String modelKey, double? ie})>[];
    void add(String modelKey, double? ie) {
      final k = '$modelKey|${ie == null ? '?' : jsNum(ie)}';
      if (seen.add(k)) out.add((modelKey: modelKey, ie: ie));
    }

    try {
      final raw =
          jsonDecode(await fileOf(e).readAsString()) as Map<String, dynamic>;
      for (final it in ParsedVibe(raw).encodingItems) {
        add(it.modelKey, it.infoExtracted);
      }
    } catch (_) {}
    final hash = e.imageHash;
    if (hash != null) {
      final cache = await ref.read(vibeCacheProvider.future);
      for (final it in cache.entriesForImage(hash)) {
        add(it.modelKey, it.ie);
      }
    }
    out.sort((a, b) {
      final c = a.modelKey.compareTo(b.modelKey);
      if (c != 0) return c;
      return (a.ie ?? 2).compareTo(b.ie ?? 2);
    });
    return out;
  }
}

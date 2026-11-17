import '../../core/util/log.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/store/storage_settings.dart';
import '../../core/util/image_ops.dart';
import '../generate/vibe_cache.dart';
import 'naiv4vibe_codec.dart';

/// 顶层函数:后台 isolate 算图片字节哈希(编码缓存的内容寻址键)。
String sha256HexOfBytes(Uint8List bytes) => sha256.convert(bytes).toString();

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
    try {
      await _indexFile.writeAsString(
        jsonEncode({
          'version': 1,
          'entries': [for (final e in list) e.toJson()],
          'tagRegistry': _registryTags.toList()..sort(),
        }),
      );
    } catch (e) {
      logd('[vibe-lib] 写索引失败: $e'); // 内存态仍可用,下次启动会重建
    }
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

  /// 由解析结果组装索引条目并落缩略图。
  /// 有原图时缩略图一律从原图现生成(导入文件的 thumbnail 可能是截断伪图)。
  Future<VibeEntry> _entryFromParsed(
    ParsedVibe p, {
    required String id,
    required String fileName,
    required int sizeBytes,
    String fallbackName = '',
    String? originFilename,
    VibeEntry? existing,
  }) async {
    final img = p.imageBase64;
    String? hash;
    if (img != null) {
      final bytes = base64Decode(img);
      hash = await compute(sha256HexOfBytes, bytes);
      try {
        await _writeThumb(
          id,
          await coverResizePng(bytes, 256, 256, keepAlpha: true),
        );
      } catch (_) {}
    } else {
      final t = p.thumbnailDataUrl;
      if (t != null) {
        try {
          await _writeThumb(id, base64Decode(t.split(',').last));
        } catch (_) {}
      }
    }
    final name = p.name.isNotEmpty
        ? p.name
        : (fallbackName.isNotEmpty ? fallbackName : '未命名 Vibe');
    return VibeEntry(
      id: id,
      name: name,
      fileName: fileName,
      imageHash: hash,
      hasImage: img != null,
      defaultStrength: p.defaultStrength ?? existing?.defaultStrength,
      defaultInfoExtracted:
          p.defaultInfoExtracted ?? existing?.defaultInfoExtracted,
      supportedModels: p.supportedModelKeys,
      tags: p.tags.isNotEmpty ? p.tags : (existing?.tags ?? const []),
      createdAt:
          existing?.createdAt ??
          (p.createdAt > 0
              ? p.createdAt
              : DateTime.now().millisecondsSinceEpoch),
      lastUsedAt: existing?.lastUsedAt ?? 0,
      sizeBytes: sizeBytes,
      originFilename: originFilename ?? existing?.originFilename,
    );
  }

  /// 把文件自带的编码灌进内容寻址缓存(有原图哈希才有键;无 params 的条目
  /// 定位不了 IE,留在文件里不进缓存,导出时仍保留)。
  Future<void> _seedEncodings(ParsedVibe p, String? imageHash) async {
    if (imageHash == null) return;
    final cache = await ref.read(vibeCacheProvider.future);
    for (final it in p.encodingItems) {
      final ie = it.infoExtracted;
      if (ie == null) continue;
      await cache.put(imageHash, it.modelKey, ie, it.encoding);
    }
  }

  Future<List<VibeEntry>> _rebuildFromFiles() async {
    final out = <VibeEntry>[];
    try {
      await for (final ent in _filesDir.list()) {
        if (ent is! File || !ent.path.endsWith('.naiv4vibe')) continue;
        try {
          final text = await ent.readAsString();
          final parsed = parseVibeFileText(text);
          if (parsed.isEmpty) continue;
          final p = parsed.first;
          final e = await _entryFromParsed(
            p,
            id: idOfParsed(p),
            fileName: ent.uri.pathSegments.last,
            sizeBytes: text.length,
          );
          await _seedEncodings(p, e.imageHash);
          out.add(e);
        } catch (err) {
          logd('[vibe-lib] 重建跳过 ${ent.path}: $err');
        }
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _indexFile.writeAsString(
        jsonEncode({
          'version': 1,
          'entries': [for (final e in out) e.toJson()],
          'tagRegistry': _registryTags.toList()..sort(),
        }),
      );
    } catch (e) {
      logd('[vibe-lib] 重建失败: $e');
    }
    return out;
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
  }) async {
    await future;
    final kept = [..._entries]; // 库里原有的,按 id 就地覆盖
    final keptAt = {for (var i = 0; i < kept.length; i++) kept[i].id: i};
    final fresh = <VibeEntry>[]; // 本批新增的,最后整体插到最前
    final freshAt = <String, int>{};
    final out = <VibeEntry>[];

    for (var n = 0; n < raws.length; n++) {
      final p = ParsedVibe(raws[n]);
      final id = p.id.isNotEmpty
          ? p.id
          : (p.imageBase64 != null
                ? naiVibeIdOfBase64(p.imageBase64!)
                : 'enc_${DateTime.now().millisecondsSinceEpoch}_$n');
      final fileName = '${_safeName(id)}.naiv4vibe';
      final singleText = jsonEncode(p.raw);
      await File('${_filesDir.path}/$fileName').writeAsString(singleText);
      final entry = await _entryFromParsed(
        p,
        id: id,
        fileName: fileName,
        sizeBytes: singleText.length,
        fallbackName: fallbackName,
        originFilename: originFilename,
        existing: switch ((keptAt[id], freshAt[id])) {
          (final int i, _) => kept[i],
          (_, final int i) => fresh[i],
          _ => null,
        },
      );
      await _seedEncodings(p, entry.imageHash);
      if (keptAt[id] case final int i) {
        kept[i] = entry;
      } else if (freshAt[id] case final int i) {
        fresh[i] = entry; // 同一批里重复的 id,后一条覆盖前一条
      } else {
        freshAt[id] = fresh.length;
        fresh.add(entry);
      }
      out.add(entry);
      onProgress?.call(n + 1, raws.length);
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

  Future<Map<String, dynamic>> _readRawMerged(VibeEntry e) async {
    final raw =
        jsonDecode(await fileOf(e).readAsString()) as Map<String, dynamic>;
    final hash = e.imageHash;
    if (hash != null) {
      final cache = await ref.read(vibeCacheProvider.future);
      for (final it in cache.entriesForImage(hash)) {
        final enc = await cache.get(hash, it.modelKey, it.ie);
        if (enc == null) continue;
        mergeEncodingIntoRaw(
          raw,
          modelKey: it.modelKey,
          infoExtracted: it.ie,
          encoding: enc,
        );
      }
    }
    return raw;
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
    try {
      final raw =
          jsonDecode(await fileOf(e).readAsString()) as Map<String, dynamic>;
      if (name != null) raw['name'] = name;
      if (defaultStrength != null || defaultInfoExtracted != null) {
        final info = raw['importInfo'] is Map
            ? (raw['importInfo'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        info['model'] ??= e.supportedModels.isNotEmpty
            ? (kEncodingKeyToModel[e.supportedModels.first] ??
                  e.supportedModels.first)
            : 'nai-diffusion-4-5-full';
        if (defaultStrength != null) info['strength'] = defaultStrength;
        if (defaultInfoExtracted != null) {
          info['information_extracted'] = defaultInfoExtracted;
        }
        info['strength'] ??= e.defaultStrength ?? 0.6;
        info['information_extracted'] ??= e.defaultInfoExtracted ?? 1.0;
        raw['importInfo'] = info;
      }
      final text = jsonEncode(raw);
      await fileOf(e).writeAsString(text);
      await _upsert(
        e.copyWith(
          name: name,
          defaultStrength: defaultStrength,
          defaultInfoExtracted: defaultInfoExtracted,
          sizeBytes: text.length,
        ),
      );
    } catch (err) {
      logd('[vibe-lib] 更新失败: $err');
    }
  }

  /// 设置某条标签(整表覆盖):回写文件 tags + 索引。
  Future<void> setTags(String id, List<String> tags) async {
    await future;
    final e = _byId(id);
    if (e == null) return;
    try {
      final raw =
          jsonDecode(await fileOf(e).readAsString()) as Map<String, dynamic>;
      raw['tags'] = tags;
      await fileOf(e).writeAsString(jsonEncode(raw));
    } catch (err) {
      logd('[vibe-lib] 写标签失败: $err');
    }
    await _upsert(e.copyWith(tags: tags));
  }

  /// 批量给多条**追加**标签(已有则跳过)。
  Future<void> addTagToAll(Iterable<String> ids, String tag) async {
    for (final id in ids) {
      final e = _byId(id);
      if (e == null || e.tags.contains(tag)) continue;
      await setTags(id, [...e.tags, tag]);
    }
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
    for (final e in [..._entries]) {
      if (!e.tags.contains(old)) continue;
      final next = <String>[];
      for (final t in e.tags) {
        final r = t == old ? n : t;
        if (!next.contains(r)) next.add(r);
      }
      await setTags(e.id, next);
    }
    if (_registryTags.remove(old)) _registryTags.add(n);
    await _setEntries([..._entries]);
  }

  /// 全局删除标签(从所有条目移除,并从登记表移除)。
  Future<void> removeTag(String tag) async {
    await future;
    for (final e in [..._entries]) {
      if (!e.tags.contains(tag)) continue;
      await setTags(e.id, [
        for (final t in e.tags)
          if (t != tag) t,
      ]);
    }
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
      final raw =
          jsonDecode(await fileOf(e).readAsString()) as Map<String, dynamic>;
      final img = raw['image'];
      if (img is! String || img.isEmpty) return null;
      return base64Decode(img);
    } catch (_) {
      return null;
    }
  }

  /// 取「可生成」数据:有图 → 原图字节 + 哈希(编码走统一编码服务);
  /// 纯编码 → 每模型键选一条编码(优先贴近默认 IE)+ 固定 IE。
  Future<VibeForGenerate?> loadForGenerate(VibeEntry e) async {
    try {
      final raw =
          jsonDecode(await fileOf(e).readAsString()) as Map<String, dynamic>;
      final p = ParsedVibe(raw);
      final img = p.imageBase64;
      if (img != null) {
        final bytes = base64Decode(img);
        final hash = e.imageHash ?? await compute(sha256HexOfBytes, bytes);
        return (
          image: bytes,
          imageHash: hash,
          encodedByModel: null,
          fixedInfoExtracted: e.defaultInfoExtracted ?? 1.0,
        );
      }
      final prefer = e.defaultInfoExtracted ?? p.defaultInfoExtracted ?? 1.0;
      final byModel = <String, String>{};
      double? pickedIe;
      for (final it in p.encodingItems) {
        final cur = byModel[it.modelKey];
        if (cur == null) {
          byModel[it.modelKey] = it.encoding;
          pickedIe ??= it.infoExtracted;
        } else if (it.infoExtracted != null &&
            (pickedIe == null ||
                (it.infoExtracted! - prefer).abs() <
                    (pickedIe - prefer).abs())) {
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
    } catch (_) {
      return null;
    }
  }

  /// 详情页编码清单:文件自带 + 缓存新增,按 (modelKey, IE) 去重。
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

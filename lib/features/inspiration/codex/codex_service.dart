import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/store/atomic_file.dart';
import 'codex_artist_styles.dart';
import 'codex_models.dart';
import 'codex_tag_zh.dart';
import '../../../l10n/l10n.dart';

/// 法典数据源接入:官网 CDN 取 index / media / 每部 JSON,以及原站的 tag 中文对照。
/// 每部 JSON 大(最大近 30MB),按 `id@版本` 落盘缓存(版本不变即命中不重拉),
/// 读盘与解析都放 isolate(compute),主线程不卡。索引与图床配置联网优先、拉不到读
/// 上次存的副本,离线也能打开缓存过的法典。例图不在这层缓存,走 `RemoteImage` 的
/// 磁盘缓存(`img_cache/`)。
class CodexService {
  /// [cacheDir] 仅供测试注入;缺省为 `<support>/codex_cache`。
  CodexService({http.Client? client, Directory? cacheDir})
    : _client = client ?? http.Client(),
      _cacheDir = cacheDir,
      _cacheResolved = cacheDir != null;

  final http.Client _client;
  Directory? _cacheDir;
  bool _cacheResolved;

  /// 官网(数据 JSON 的规范来源,Cloudflare CDN;非 GitHub raw)。
  static const site = 'https://novelai.quicktagcloud.com';

  /// 这么久没收到新字节就中断请求。
  static const _idle = Duration(seconds: 20);

  /// 对照表比法典正文小一个量级(core 压缩后 550KB 上下),等不了那么久:
  /// 等待期间缺译名的芯片在转圈。
  static const _tagZhTimeout = Duration(seconds: 15);

  Future<Directory?> _dir() async {
    if (_cacheResolved) return _cacheDir;
    _cacheResolved = true;
    try {
      final sup = await getApplicationSupportDirectory();
      final d = Directory('${sup.path}/codex_cache');
      await d.create(recursive: true);
      _cacheDir = d;
    } catch (_) {
      _cacheDir = null; // 缓存目录不可用:只影响命中率,不影响功能
    }
    return _cacheDir;
  }

  /// 拉一个文件的字节。[_idle] 内没收到新字节、或超过 [deadline],就中断请求
  /// (只停止等待的话,底层连接会在后台继续下完)。
  Future<Uint8List> _getBytes(String url, {Duration? deadline}) async {
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    var idle = Timer(_idle, stop);
    final hard = deadline == null ? null : Timer(deadline, stop);
    try {
      final resp = await _client.send(
        http.AbortableRequest(
          'GET',
          Uri.parse(url),
          abortTrigger: abort.future,
        ),
      );
      if (resp.statusCode != 200) {
        throw CodexException('HTTP ${resp.statusCode}');
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in resp.stream) {
        out.add(chunk);
        idle.cancel();
        idle = Timer(_idle, stop);
      }
      return out.takeBytes();
    } finally {
      idle.cancel();
      hard?.cancel();
      stop(); // 非 200 等提前退出时断开连接;已读完的响应不受影响
    }
  }

  Future<String> _get(String url, {Duration? deadline}) async =>
      utf8.decode(await _getBytes(url, deadline: deadline));

  /// 图床配置:拉 media.json,拉不到读副本,再不行退回已知常量(总能出图)。
  Future<CodexMedia> fetchMedia() async {
    try {
      return await _fetchWithCopy('media.json', (raw) {
        final j = jsonDecode(raw);
        if (j is! Map<String, dynamic>) {
          throw CodexException(l10nNow.codexBadImageHost);
        }
        return CodexMedia.fromJson(j);
      });
    } catch (_) {
      return CodexMedia.fallback;
    }
  }

  /// 法典索引(codexes.json;联网优先,拉不到读副本)。
  Future<List<CodexMeta>> fetchIndex() =>
      _fetchWithCopy('codexes.json', _parseIndex);

  /// 法典索引的副本(上次联网拿到的那份);没有或解析不了返回 null。
  Future<List<CodexMeta>?> cachedIndex() =>
      _readCopy('codexes.json', _parseIndex);

  static List<CodexMeta> _parseIndex(String raw) {
    final j = jsonDecode(raw);
    if (j is! List) throw CodexException(l10nNow.codexBadIndex);
    return [
      for (final e in j)
        if (e is Map<String, dynamic>) CodexMeta.fromJson(e),
    ].where((m) => m.id.isNotEmpty).toList();
  }

  /// 联网优先的小文件(`data/<name>`):拉到且解析通过就存一份副本到
  /// `codex_cache/meta/`,拉不到或解析不了就读副本;副本也没有才抛原错。
  ///
  /// 索引必须这样:正文缓存靠索引里的版本号对上号,索引拉不到的话盘上的正文
  /// 一部也打不开。先解析再存 —— 认证门户之类回 200 的网页不能顶掉好副本。
  Future<T> _fetchWithCopy<T>(String name, T Function(String raw) parse) async {
    try {
      final raw = await _get('$site/data/$name');
      final value = parse(raw);
      final base = await _dir();
      if (base != null) {
        try {
          await writeStringAtomic(File('${base.path}/meta/$name'), raw);
        } catch (_) {}
      }
      return value;
    } catch (_) {
      final copy = await _readCopy(name, parse);
      if (copy != null) return copy;
      rethrow;
    }
  }

  Future<T?> _readCopy<T>(String name, T Function(String raw) parse) async {
    final base = await _dir();
    if (base == null) return null;
    try {
      return parse(await File('${base.path}/meta/$name').readAsString());
    } catch (_) {
      return null;
    }
  }

  /// 一部法典的完整数据:命中缓存读盘;否则拉网 → 解析通过 → 落盘(淘汰旧版本)。
  ///
  /// 盘上那份解析不了(早先非原子写留下的半截文件之类)就删掉回源 —— 否则重试
  /// 读的还是同一个坏文件,这部法典会一直卡在「加载失败」。
  ///
  /// v5 画师词典另取画风数据([_artistStyles],按 [stamp] 缓存,缺省用本部版本号),
  /// 在同一个 isolate 里重排;取不到就按来源目录显示。
  Future<CodexData> fetchCodex(CodexMeta meta, {String? stamp}) async {
    final styles = meta.id == artistStylesCodexId
        ? _artistStyles(stamp ?? meta.version)
        : Future<File?>.value();
    final f = await _codexFile(meta);
    if (f != null && await f.exists()) {
      try {
        return await compute(codexParsePayload, <Object?>[
          f,
          meta.raw,
          await styles,
        ]);
      } catch (_) {}
      try {
        await f.delete();
      } catch (_) {}
    }

    final bytes = await _download(meta);
    final data = await compute(codexParsePayload, <Object?>[
      bytes,
      meta.raw,
      await styles,
    ]);
    if (f != null) await _storeCodex(meta, f, bytes);
    return data;
  }

  /// 画风数据文件(`meta/artist_styles@<戳>.json`):戳不变即命中不联网;没有才拉,
  /// 格式通过才落盘并淘汰旧戳。拉不到或不认时退回旧戳那份,都没有返回 null。
  Future<File?> _artistStyles(String stamp) async {
    final base = await _dir();
    if (base == null) return null;
    final dir = Directory('${base.path}/meta');
    final name = artistStylesFile.replaceFirst(RegExp(r'\.json$'), '');
    final f = File('${dir.path}/$name@${_safeName(stamp)}.json');
    if (await f.exists()) return f;
    try {
      final bytes = await _getBytes('$site/data/$artistStylesFile');
      if (!await compute(_artistStylesValid, bytes)) {
        throw CodexException(l10nNow.codexBadData);
      }
      await _evict(dir, name);
      try {
        await File('${dir.path}/$artistStylesFile').delete();
      } catch (_) {}
      await writeBytesAtomic(f, bytes);
      return f;
    } catch (_) {
      try {
        await for (final ent in dir.list()) {
          final n = ent.uri.pathSegments.last;
          if (ent is File && n.startsWith('$name@') && n.endsWith('.json')) {
            return ent;
          }
        }
      } catch (_) {}
      return null;
    }
  }

  /// 拉网:主 URL(`dataUrl` 或 `data/<id>.json`)→ 失败退兜底(本地快照)。
  Future<Uint8List> _download(CodexMeta meta) async {
    try {
      return await _getBytes(_dataUrl(meta));
    } catch (_) {
      final fb = meta.fallbackDataUrl;
      if (fb == null) rethrow;
      return _getBytes(fb.startsWith('http') ? fb : '$site/$fb');
    }
  }

  /// 落盘并淘汰同 id 的旧版本快照。
  Future<void> _storeCodex(CodexMeta meta, File f, Uint8List bytes) async {
    try {
      await _evict(f.parent, meta.id);
      await writeBytesAtomic(f, bytes);
    } catch (_) {}
  }

  /// 删掉 [dir] 里 `<name>@*` 的旧戳 / 旧版本文件(连同崩溃残留的 `.tmp`)。
  static Future<void> _evict(Directory dir, String name) async {
    try {
      await for (final ent in dir.list()) {
        if (ent is File && ent.uri.pathSegments.last.startsWith('$name@')) {
          try {
            await ent.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');

  Future<File?> _codexFile(CodexMeta meta) async {
    final dir = await _dir();
    final name = _cacheName(meta);
    return dir == null || name == null ? null : File('${dir.path}/$name');
  }

  String _dataUrl(CodexMeta meta) =>
      meta.dataUrl ?? '$site/data/${meta.id}.json';

  /// 缓存文件名 `id@版本.json`;无版本则不缓存(对不上号,每次重拉)。
  String? _cacheName(CodexMeta meta) {
    if (meta.version.isEmpty) return null;
    return '${meta.id}@${_safeName(meta.version)}.json';
  }

  /// 原站的 tag 中文对照(`data/tag_zh/<name>.json`,name = `core` 或法典 id)。
  /// 按 [stamp](见 [codexIndexStamp])落盘到 `codex_cache/tag_zh/`,戳不变即命中
  /// 不重拉;解析放 isolate。
  ///
  /// **从不抛错**:这层只是给芯片补译名,拉不到、格式不认一律返回 null,调用方
  /// 退回 app 自己的译名。抛出去的话 Riverpod 会自动重试半分钟以上,缺译名的
  /// 芯片就一直转圈。
  Future<TagZhShard?> fetchTagZh(String name, String stamp) async {
    final dir = await _tagZhDir();
    final safe = _safeName(name);
    final file = dir == null ? null : File('${dir.path}/$safe@$stamp.json');
    try {
      if (file != null && await file.exists()) {
        final hit = await compute(tagZhParsePayload, await file.readAsString());
        if (hit != null) return hit;
      }
    } catch (_) {}

    try {
      final raw = await _get(
        '$site/data/tag_zh/${Uri.encodeComponent(name)}.json',
        deadline: _tagZhTimeout,
      );
      final parsed = await compute(tagZhParsePayload, raw);
      if (parsed == null || dir == null || file == null) return parsed;
      try {
        await _evict(dir, safe);
        await writeStringAtomic(file, raw);
      } catch (_) {}
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _tagZhDir() async {
    final base = await _dir();
    if (base == null) return null;
    try {
      final d = Directory('${base.path}/tag_zh');
      await d.create(recursive: true);
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 清空落盘缓存(存储管理用),连同 `tag_zh/`、`meta/` 子目录。
  Future<void> clearCache() async {
    final dir = await _dir();
    if (dir == null) return;
    try {
      await for (final ent in dir.list()) {
        try {
          await ent.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void dispose() => _client.close();
}

/// isolate 里解析:读盘 / 解码(最重的一步)+ 建词条 + 与索引 meta 合并。
/// 顶层函数(compute 要求),入参/出参必须可跨 isolate 传送 —— [CodexData] 全是
/// 纯数据(含 record),往返无损,由 [codex_test.dart] 真跑一次 isolate 钉死。
///
/// 入参:`[正文源, 索引 meta 原文, 画风数据源?]`;源见 [_decodeJson]。
CodexData codexParsePayload(List<Object?> args) {
  final j = _decodeJson(args[0]);
  if (j is! Map<String, dynamic>) {
    throw CodexException(l10nNow.codexBadData);
  }
  final indexRaw = args[1] as Map<String, dynamic>?;
  final idx = (indexRaw != null && indexRaw.isNotEmpty)
      ? CodexMeta.fromJson(indexRaw)
      : null;
  final data = CodexData.parse(j, indexMeta: idx);
  ArtistStyles? styles;
  if (args.length > 2 && args[2] != null) {
    try {
      styles = parseArtistStyles(_decodeJson(args[2]));
    } catch (_) {}
  }
  return styles == null ? data : applyArtistStyles(data, styles);
}

/// JSON 源:盘上的 [File](在当前 isolate 里读)、下载到的字节,或 JSON 原文。
/// 字节走 UTF-8 与 JSON 合并解码,不先转出整串字符串。
Object? _decodeJson(Object? src) => switch (src) {
  File f => _utf8Json.convert(f.readAsBytesSync()),
  Uint8List b => _utf8Json.convert(b),
  String s => jsonDecode(s),
  _ => null,
};

final _utf8Json = utf8.decoder.fuse(json.decoder);

bool _artistStylesValid(Uint8List bytes) {
  try {
    return parseArtistStyles(_utf8Json.convert(bytes)) != null;
  } catch (_) {
    return false;
  }
}

class CodexException implements Exception {
  const CodexException(this.message);
  final String message;
  @override
  String toString() => message;
}

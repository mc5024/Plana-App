import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/store/atomic_file.dart';
import 'codex_artist_styles.dart';
import 'codex_models.dart';
import 'codex_tag_zh.dart';
import '../../../l10n/l10n.dart';

/// 法典数据源接入:官网 CDN 取 index / media / 每部 JSON,以及原站的 tag 中文对照。
/// 每部 JSON 大(最大 ~11MB),按 `id@版本` 落盘缓存(版本不变即命中不重拉),
/// 解析放 isolate(compute),主线程不卡。索引与图床配置联网优先、拉不到读上次
/// 存的副本,离线也能打开缓存过的法典。例图不在这层缓存,走 `RemoteImage` 的
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
  static const _timeout = Duration(seconds: 30);

  /// 对照表比法典正文小一个量级(core 压缩后 400KB 上下),等不了那么久:
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

  Future<String> _get(String url, {Duration timeout = _timeout}) async {
    final resp = await _client.get(Uri.parse(url)).timeout(timeout);
    if (resp.statusCode != 200) {
      throw CodexException('HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
  }

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

  /// 法典索引(codexes.json;拉不到读副本)。
  Future<List<CodexMeta>> fetchIndex() => _fetchWithCopy('codexes.json', (raw) {
    final j = jsonDecode(raw);
    if (j is! List) throw CodexException(l10nNow.codexBadIndex);
    return [
      for (final e in j)
        if (e is Map<String, dynamic>) CodexMeta.fromJson(e),
    ].where((m) => m.id.isNotEmpty).toList();
  });

  /// 联网优先的小文件(`data/<name>`):拉到且解析通过就存一份副本到
  /// `codex_cache/meta/`,拉不到或解析不了就读副本;副本也没有才抛原错。
  ///
  /// 索引必须这样:正文缓存靠索引里的版本号对上号,索引拉不到的话盘上的正文
  /// 一部也打不开。先解析再存 —— 认证门户之类回 200 的网页不能顶掉好副本。
  Future<T> _fetchWithCopy<T>(String name, T Function(String raw) parse) async {
    final base = await _dir();
    final copy = base == null ? null : File('${base.path}/meta/$name');
    try {
      final raw = await _get('$site/data/$name');
      final value = parse(raw);
      if (copy != null) {
        try {
          await writeStringAtomic(copy, raw);
        } catch (_) {}
      }
      return value;
    } catch (_) {
      if (copy != null) {
        try {
          return parse(await copy.readAsString());
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 一部法典的完整数据:命中缓存读盘;否则拉网 → 解析通过 → 落盘(淘汰旧版本)。
  ///
  /// 盘上那份解析不了(早先非原子写留下的半截文件之类)就删掉回源 —— 否则重试
  /// 读的还是同一个坏文件,这部法典会一直卡在「加载失败」。
  ///
  /// v5 画师词典另拉画风数据([artistStylesFile]),在同一个 isolate 里重排;
  /// 拉不到就按来源目录显示。
  Future<CodexData> fetchCodex(CodexMeta meta) async {
    final styles = meta.id == artistStylesCodexId
        ? _fetchArtistStyles()
        : Future<String?>.value();
    final f = await _codexFile(meta);
    if (f != null && await f.exists()) {
      try {
        final s = await f.readAsString();
        if (s.isNotEmpty) {
          return await compute(codexParsePayload, <Object?>[
            s,
            meta.raw,
            await styles,
          ]);
        }
      } catch (_) {}
      try {
        await f.delete();
      } catch (_) {}
    }

    final raw = await _download(meta);
    final data = await compute(codexParsePayload, <Object?>[
      raw,
      meta.raw,
      await styles,
    ]);
    if (f != null) await _storeCodex(meta, f, raw);
    return data;
  }

  /// 画风数据原文(联网优先、拉不到读副本);都没有返回 null。
  Future<String?> _fetchArtistStyles() async {
    try {
      return await _fetchWithCopy(artistStylesFile, (raw) {
        if (parseArtistStyles(jsonDecode(raw)) == null) {
          throw CodexException(l10nNow.codexBadData);
        }
        return raw;
      });
    } catch (_) {
      return null;
    }
  }

  /// 拉网:主 URL(`dataUrl` 或 `data/<id>.json`)→ 失败退兜底(本地快照)。
  Future<String> _download(CodexMeta meta) async {
    try {
      return await _get(_dataUrl(meta));
    } catch (_) {
      final fb = meta.fallbackDataUrl;
      if (fb == null) rethrow;
      return _get(fb.startsWith('http') ? fb : '$site/$fb');
    }
  }

  /// 落盘并淘汰同 id 的旧版本快照(连同崩溃残留的 `.tmp`)。
  Future<void> _storeCodex(CodexMeta meta, File f, String raw) async {
    try {
      await for (final ent in f.parent.list()) {
        if (ent is File &&
            ent.uri.pathSegments.last.startsWith('${meta.id}@')) {
          try {
            await ent.delete();
          } catch (_) {}
        }
      }
      await writeStringAtomic(f, raw);
    } catch (_) {}
  }

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
    final safe = meta.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return '${meta.id}@$safe.json';
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
    final safe = name.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
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
        timeout: _tagZhTimeout,
      );
      final parsed = await compute(tagZhParsePayload, raw);
      if (parsed == null || dir == null || file == null) return parsed;
      try {
        await for (final ent in dir.list()) {
          if (ent is File && ent.uri.pathSegments.last.startsWith('$safe@')) {
            try {
              await ent.delete(); // 淘汰同名旧戳
            } catch (_) {}
          }
        }
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

/// isolate 里解析:jsonDecode(最重的一步)+ 建词条 + 与索引 meta 合并。
/// 顶层函数(compute 要求),入参/出参必须可跨 isolate 传送 —— [CodexData] 全是
/// 纯数据(含 record),往返无损,由 [codex_test.dart] 真跑一次 isolate 钉死。
CodexData codexParsePayload(List<Object?> args) {
  final raw = args[0] as String;
  final indexRaw = args[1] as Map<String, dynamic>?;
  final j = jsonDecode(raw);
  if (j is! Map<String, dynamic>) {
    throw CodexException(l10nNow.codexBadData);
  }
  final idx = (indexRaw != null && indexRaw.isNotEmpty)
      ? CodexMeta.fromJson(indexRaw)
      : null;
  final data = CodexData.parse(j, indexMeta: idx);
  final stylesRaw = args.length > 2 ? args[2] as String? : null;
  final styles = stylesRaw == null
      ? null
      : parseArtistStyles(jsonDecode(stylesRaw));
  return styles == null ? data : applyArtistStyles(data, styles);
}

class CodexException implements Exception {
  const CodexException(this.message);
  final String message;
  @override
  String toString() => message;
}

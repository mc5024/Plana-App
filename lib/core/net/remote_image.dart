import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../store/atomic_file.dart';

/// 远端图片的磁盘缓存(`<support>/img_cache/<sha1(url)>`)。
///
/// **为什么必须自己做**:Flutter 的 `Image.network` 走 `NetworkImage` →
/// dart:io `HttpClient`,而 `HttpClient` **没有 HTTP 缓存实现** —— 响应头里的
/// `Cache-Control` / `ETag` 一概不生效。唯一的缓存是 `PaintingBinding.imageCache`
/// (内存,默认 1000 张 / 100 MiB,存的还是**解码后位图**),杀进程即空。
/// 结果就是:每次冷启动重下全部缩略图、来回滚动反复重下、离线完全不可用。
///
/// 目录由 [bind] 在 `AppStores.open()` 里挂上。用静态量而不是 provider,是因为
/// [RemoteImageProvider] 是 `ImageProvider`,拿不到 `ref`(同 `Haptics.enabled`)。
/// 没挂上时整层降级为「直连不缓存」,不影响功能。
abstract final class RemoteImageStore {
  static Directory? _dir;

  /// 磁盘缓存上限;超出时 [trim] 删最久未用的(启动后台维护里跑一次)。
  static const maxBytes = 128 << 20;

  /// 命中后回写 mtime 的最小间隔 —— 滚动列表每帧都 touch 一次太浪费,
  /// 天级粒度足够把「常看的」和「一年没碰的」区分开。
  static const _touchAfter = Duration(days: 1);

  /// 验证器旁文件的后缀。内容 = 服务端给的 ETag **原样**(含引号,
  /// If-None-Match 要逐字回传);它自己的 mtime = 上次验证的时刻。
  ///
  /// 单开一个文件而不是塞进主文件:主文件是喂给解码器的裸字节,
  /// 加个头就得所有读路径都先剥一层,还会把老缓存全作废。
  static const _validatorExt = '.v';

  /// 内容变了就给这个 URL 换一个**缓存键**(见 [RemoteImageProvider.version])。
  ///
  /// 只把磁盘那份换掉不够:内存层(`PaintingBinding.imageCache`)存的是解码后
  /// 位图,键里没有任何内容信息 —— 不换键的话屏幕上挂着的、以及重进页面拿到的
  /// 都还是旧图,只有杀进程或清缓存才会变。[revision] 变一次,所有 [RemoteImage]
  /// 跟着重建,新键自然从磁盘拿到新字节。
  static final revision = ValueNotifier<int>(0);
  static final _versions = <String, int>{};

  static int versionOf(String url) => _versions[url] ?? 0;

  /// 上次回源验证的时刻(按 URL)。
  ///
  /// ⚠ 这个和磁盘上的 ETag 旁文件是**两件事**,必须分开记:旁文件只有服务端
  /// 真给了 ETag 才有,而「验过没有」对不给 ETag 的服务端同样成立。原来把两者
  /// 合成一个判断(没旁文件 = 没验过),于是不发 ETag 的图**每次加载都回源**,
  /// 而回源必然 200 → 换缓存键 → 重建 → 再加载 → 再回源,直接转成死循环。
  ///
  /// **不落盘**:落盘要给每个 URL 多一个文件,而这个信息只值一个进程周期 ——
  /// 冷启动后每张图重验一次本来就是想要的。
  static final _checkedAt = <String, DateTime>{};

  static bool checkedRecently(String url, Duration within) {
    final at = _checkedAt[url];
    return at != null && DateTime.now().difference(at) < within;
  }

  static void markChecked(String url) => _checkedAt[url] = DateTime.now();

  static void _bumpVersion(String url) {
    _versions[url] = versionOf(url) + 1;
    revision.value++;
  }

  static void bind(Directory supportRoot) =>
      _dir = Directory('${supportRoot.path}/img_cache');

  static File? _fileOf(String url) {
    final d = _dir;
    if (d == null) return null;
    return File('${d.path}/${sha1.convert(utf8.encode(url))}');
  }

  static File? _validatorOf(String url) {
    final f = _fileOf(url);
    return f == null ? null : File('${f.path}$_validatorExt');
  }

  /// 上次验证的结果:(ETag 原文, 验证时刻)。没有旁文件(老缓存/服务端没给
  /// ETag)返回 null —— 调用方按「该验一次」处理,一次 200 回来就补上了。
  static Future<({String etag, DateTime at})?> validator(String url) async {
    final f = _validatorOf(url);
    if (f == null) return null;
    try {
      final st = await f.stat();
      if (st.type == FileSystemEntityType.notFound) return null;
      final etag = (await f.readAsString()).trim();
      if (etag.isEmpty) return null;
      return (etag: etag, at: st.modified);
    } catch (_) {
      return null;
    }
  }

  /// 304 之后刷新新鲜期:内容没变,但「刚验过」这件事要记下来。
  static Future<void> touchValidator(String url) async {
    final f = _validatorOf(url);
    if (f == null) return;
    try {
      if (await f.exists()) await f.setLastModified(DateTime.now());
    } catch (_) {}
  }

  static Future<Uint8List?> read(String url) async {
    final f = _fileOf(url);
    if (f == null) return null;
    try {
      final st = await f.stat();
      if (st.type == FileSystemEntityType.notFound) return null;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return null;
      if (DateTime.now().difference(st.modified) > _touchAfter) {
        unawaited(_touch(f));
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 原子写:文件名是 **URL** 的哈希而非内容的,半截文件没法自证损坏,
  /// 会被后续 [read] 当成有效缓存直接喂给解码器。
  ///
  /// [etag] 是服务端这次给的验证器,一并落到旁文件(见 [_validatorExt])。
  /// [replaced] = 这次是换掉了已有的内容(而不是首次下载),那就要给这个 URL
  /// 换一个缓存键,把内存里那份旧位图顶掉。
  static Future<void> write(
    String url,
    Uint8List bytes, {
    String? etag,
    bool replaced = false,
  }) async {
    final f = _fileOf(url);
    if (f == null) return;
    try {
      await writeBytesAtomic(f, bytes);
      final v = _validatorOf(url);
      if (v != null) {
        if (etag != null && etag.isNotEmpty) {
          await writeBytesAtomic(v, Uint8List.fromList(utf8.encode(etag)));
        } else if (await v.exists()) {
          // 服务端这次没给 ETag:旧验证器已经对不上内容了,留着会误判 304
          await v.delete();
        }
      }
    } catch (_) {}
    if (replaced) _bumpVersion(url);
  }

  static Future<void> _touch(File f) async {
    try {
      await f.setLastModified(DateTime.now());
    } catch (_) {}
  }

  /// 超出 [limit] 时按 mtime 从旧到新删到达标。
  static Future<void> trim({int limit = maxBytes}) async {
    final d = _dir;
    if (d == null) return;
    try {
      if (!await d.exists()) return;
      final files = <({File f, int size, DateTime at})>[];
      var total = 0;
      await for (final ent in d.list(followLinks: false)) {
        if (ent is! File) continue;
        // 验证器旁文件不单独参与淘汰:它几十字节,而且脱离主文件毫无意义
        if (ent.path.endsWith(_validatorExt)) continue;
        try {
          final st = await ent.stat();
          files.add((f: ent, size: st.size, at: st.modified));
          total += st.size;
        } catch (_) {}
      }
      if (total <= limit) return;
      files.sort((a, b) => a.at.compareTo(b.at));
      for (final e in files) {
        if (total <= limit) break;
        try {
          await e.f.delete();
          total -= e.size;
          // 主文件走了,验证器留着只会在下次下载后误判 304
          final v = File('${e.f.path}$_validatorExt');
          if (await v.exists()) await v.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 清空(存储管理用)。删掉只是下次要重下,不丢任何用户数据。
  static Future<void> clear() async {
    final d = _dir;
    try {
      if (d != null && await d.exists()) {
        await for (final ent in d.list(followLinks: false)) {
          if (ent is File) {
            try {
              await ent.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    // 内存那几份**无条件**倒掉:磁盘目录还不存在(没缓存过任何图)时,
    // 版本号和「验过」标记照样可能有本次会话攒下的条目 —— 早退会把它们漏下。
    // 内存层也要一起倒,否则刚清完的图还在屏幕上挂着,数字对不上观感。
    // imageCache.clear() 碰不到已经挂在 widget 上的那些(它们持有 live image),
    // 所以再动一下版本号,让 RemoteImage 重建、重新解析。
    PaintingBinding.instance.imageCache.clear();
    _versions.clear();
    _checkedAt.clear();
    revision.value++;
  }
}

/// 带磁盘缓存的网络图 provider。行为对齐 `NetworkImage`:同 URL 相等、
/// 走 `imageCache` 内存层、加载失败把自己从内存缓存里踢掉(否则错误态被缓存,
/// 网络恢复了也不会重试)。
@immutable
class RemoteImageProvider extends ImageProvider<RemoteImageProvider> {
  const RemoteImageProvider(this.url, {this.scale = 1.0, this.version = 0});

  final String url;
  final double scale;

  /// 内容版本(见 [RemoteImageStore.versionOf])。**只为缓存键存在**:
  /// 同一个 URL 换了内容时它 +1,于是内存里那份解码后的旧位图不再命中。
  /// 加载路径根本不看它 —— 字节永远以磁盘上那份为准。
  final int version;

  static final _client = http.Client();
  static const _timeout = Duration(seconds: 30);

  /// 后台回源验证的超时。比首次下载短:它是锦上添花,拖着不放只是占连接。
  static const _revalidateTimeout = Duration(seconds: 15);

  /// 缓存命中后多久才值得再问一次服务端。
  ///
  /// 服务端给这些图发的是 `Cache-Control: no-cache`(每次都该验),但一屏几十张
  /// 图逐张验太吵;留一分钟的窗口,进出页面不会重复问,而作者改完图最多一分钟
  /// 就能在 app 上看见。
  static const _revalidateAfter = Duration(minutes: 1);

  /// 正在回源验证的 URL。一张图会被多个 widget(或反复重建)同时解析,
  /// 不去重就是同一个 URL 并发问好几次。
  static final _validating = <String>{};

  @override
  Future<RemoteImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<RemoteImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    RemoteImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode, chunks),
      chunkEvents: chunks.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [ErrorDescription('URL: ${key.url}')],
    );
  }

  Future<ui.Codec> _load(
    RemoteImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    try {
      final hit = await RemoteImageStore.read(key.url);
      if (hit != null) {
        // 先拿缓存显示,过期的**在后台**回源验证 —— 阻塞等 304 会把「秒开」
        // 变成「每张图都先等一个来回」,而作者改图是低频事件。
        // 真拿到新内容时 write(replaced: true) 会换掉缓存键,屏幕上那张跟着换。
        unawaited(_revalidate(key.url));
        return decode(await ui.ImmutableBuffer.fromUint8List(hit));
      }
      final (:bytes, :etag) = await _download(
        key.url,
        chunks,
      ).timeout(_timeout);
      // 落盘是旁路:写失败只是下次还得重下,不该连累这一次显示
      unawaited(RemoteImageStore.write(key.url, bytes, etag: etag));
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // 与 NetworkImage 同款:微任务里踢缓存,让下次 build 能真的重试
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(chunks.close());
    }
  }

  /// 回源验证:带 `If-None-Match` 问一次。
  ///
  /// 304 → 内容没变,刷一下新鲜期就完事(响应约 200 字节)。
  /// 200 → 拿字节和缓存比,**真的不一样才换缓存键**;一样就只记一下验过。
  /// 出错(离线/超时/非预期状态码)→ 什么也不做,继续用缓存。
  ///
  /// ⚠ 每一步都得防这条回路:换缓存键 → provider 相等性变化 → Flutter 重新
  /// resolve → 再走一次 _load → 又发起验证。只要有一步**无条件**换键,就是
  /// 死循环(不发 ETag 的服务端曾经就踩在这上面,预览图肉眼可见地反复刷新)。
  static Future<void> _revalidate(String url) async {
    if (!_validating.add(url)) return;
    try {
      // 新鲜期对「验过没有」生效,而不是对「有没有 ETag」生效
      if (RemoteImageStore.checkedRecently(url, _revalidateAfter)) return;
      final v = await RemoteImageStore.validator(url);
      if (v != null && DateTime.now().difference(v.at) < _revalidateAfter) {
        return; // 上个进程刚验过(旁文件的 mtime 跨启动还在)
      }
      final req = http.Request('GET', Uri.parse(url));
      if (v != null) req.headers['If-None-Match'] = v.etag;
      final resp = await _client.send(req).timeout(_revalidateTimeout);
      // 拿到任何一个完整响应就算验过。放在分支之前:非 200 那条也得记,
      // 否则一个稳定报 403 的地址会被每次加载重试一遍。
      RemoteImageStore.markChecked(url);
      if (resp.statusCode == 304) {
        await resp.stream.drain<void>();
        await RemoteImageStore.touchValidator(url);
        return;
      }
      if (resp.statusCode != 200) {
        await resp.stream.drain<void>();
        return;
      }
      final bytes = await resp.stream.toBytes();
      if (bytes.isEmpty) return;
      // 不发 ETag、或者不认 If-None-Match 的服务端每次都回 200,内容却没变。
      // 无条件当成「换了」既白白重解码一次,也会把上面那条回路踩响。
      final same = _sameBytes(await RemoteImageStore.read(url), bytes);
      await RemoteImageStore.write(
        url,
        bytes,
        etag: resp.headers['etag'],
        replaced: !same,
      );
    } catch (_) {
      // 离线照旧看缓存 —— 验证失败绝不该让已经能显示的图变成错误态
    } finally {
      _validating.remove(url);
    }
  }

  /// 先比长度再逐字节 —— 预览图都是几十 KB,这点开销远小于一次解码。
  static bool _sameBytes(Uint8List? a, Uint8List b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [chunks] = null:不关心进度([fetchRemoteImageBytes] 那条路会用到)。
  static Future<({Uint8List bytes, String? etag})> _download(
    String url,
    StreamController<ImageChunkEvent>? chunks,
  ) async {
    final uri = Uri.parse(url);
    final resp = await _client.send(http.Request('GET', uri));
    if (resp.statusCode != 200) {
      throw NetworkImageLoadException(statusCode: resp.statusCode, uri: uri);
    }
    final total = resp.contentLength;
    final buf = BytesBuilder(copy: false);
    await for (final part in resp.stream) {
      buf.add(part);
      if (chunks != null && !chunks.isClosed) {
        chunks.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: buf.length,
            expectedTotalBytes: total,
          ),
        );
      }
    }
    final bytes = buf.takeBytes();
    if (bytes.isEmpty) throw Exception('空响应');
    return (bytes: bytes, etag: resp.headers['etag']);
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteImageProvider &&
      other.url == url &&
      other.scale == scale &&
      other.version == version;

  @override
  int get hashCode => Object.hash(url, scale, version);

  @override
  String toString() => 'RemoteImageProvider("$url")';
}

/// 取一张远端图的**原始字节**,与 [RemoteImageProvider] 共用那份磁盘缓存:
/// 命中直接返回,否则下载并落盘。
///
/// 显示走 provider 就够了,这条是给「要把字节整个交出去」的场景用的 ——
/// 比如导入原图:解码后的位图里没有 PNG 文本块,元数据只在原始字节里。
/// [onProgress] 收到的 total 可能是 null(服务端没给 Content-Length)。
Future<Uint8List> fetchRemoteImageBytes(
  String url, {
  void Function(int received, int? total)? onProgress,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final hit = await RemoteImageStore.read(url);
  if (hit != null) return hit;
  StreamController<ImageChunkEvent>? chunks;
  StreamSubscription<ImageChunkEvent>? sub;
  if (onProgress != null) {
    chunks = StreamController<ImageChunkEvent>();
    sub = chunks.stream.listen(
      (e) => onProgress(e.cumulativeBytesLoaded, e.expectedTotalBytes),
    );
  }
  try {
    final (:bytes, :etag) = await RemoteImageProvider._download(
      url,
      chunks,
    ).timeout(timeout);
    // 落盘是旁路:写失败只是下次还得重下,不该连累这一次
    unawaited(RemoteImageStore.write(url, bytes, etag: etag));
    return bytes;
  } finally {
    unawaited(sub?.cancel());
    unawaited(chunks?.close());
  }
}

/// `Image.network` 的替代:磁盘缓存 + 按布局宽限制解码尺寸。
///
/// **解码尺寸为什么要限**:`imageCache` 存的是解码后位图,一张 1216×1824 就是
/// 8.9 MB,100 MiB 的默认上限只装得下 11 张 —— 网格一滚就雪崩式互相驱逐、
/// 反复重下。默认取布局约束宽 × dpr 作为解码宽(约束无界时不限,交给调用方给
/// [decodeWidth]),缩略图按格子大小解码,同样的内存能多装一个数量级。
class RemoteImage extends StatelessWidget {
  const RemoteImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.decodeWidth,
    this.gaplessPlayback = false,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;

  /// 解码宽度上限(**逻辑像素**,内部乘 dpr);null = 取布局约束宽。
  final double? decodeWidth;

  final bool gaplessPlayback;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  Widget _image(int? cacheWidth) {
    final base = RemoteImageProvider(
      url,
      version: RemoteImageStore.versionOf(url),
    );
    return Image(
      image: cacheWidth == null
          ? base
          : ResizeImage(base, width: cacheWidth, policy: ResizeImagePolicy.fit),
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: gaplessPlayback,
      frameBuilder: frameBuilder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int? px(double logical) {
      final n = (logical * dpr).round();
      return n >= 1 ? n : null;
    }

    // 跟着版本号重建:后台验证发现内容换了会把它 +1,这里换出新的缓存键,
    // 挂在屏幕上的那张图当场刷新 —— 否则只有杀进程或清缓存才看得到新图。
    // 全局一个计数器,任何一张更新都会让所有 RemoteImage 重建;但没变的 URL
    // 版本号照旧、键不变,不会引发重解码。
    return ValueListenableBuilder<int>(
      valueListenable: RemoteImageStore.revision,
      builder: (context, _, _) {
        final explicit = decodeWidth ?? width;
        if (explicit != null && explicit.isFinite) return _image(px(explicit));
        return LayoutBuilder(
          builder: (context, c) =>
              _image(c.hasBoundedWidth ? px(c.maxWidth) : null),
        );
      },
    );
  }
}

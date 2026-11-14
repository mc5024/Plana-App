import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/net/remote_image.dart';

/// 预览图底部、名字胶囊所在那块的平均亮度 0..1。取样区底部 22% 高;
/// 胶囊居中时横向取 15%~85%,靠左([left])时取 0~65%。
///
/// 安卓交给原生侧抽样解码、在 CPU 上算(见 PreviewTone.kt),不占 Flutter 的
/// 解码队列;其余平台另解一张 24px 宽的小图来量。结果按图和取样区缓存在内存,
/// 并落盘到远端图缓存旁边,冷启动后直接命中。
abstract final class PreviewTone {
  static const _channel = MethodChannel('plana/preview_tone');

  static const _maxEntries = 5000;
  static const _saveDelay = Duration(seconds: 2);
  static const _measureTimeout = Duration(seconds: 20);

  static final _cache = <String, double>{};
  static final _pending = <String, Future<double?>>{};
  static Future<void>? _loading;
  static Timer? _saveTimer;

  static File? get _file => switch (RemoteImageStore.dir) {
    final d? => File('${d.parent.path}/preview_tone.json'),
    null => null,
  };

  static String _key(String url, bool left) => left ? '$url#left' : url;

  /// 已知的亮度;没量过 / 落盘那份还没读进来为 null。
  static double? peek(String url, {bool left = false}) {
    unawaited(_ensureLoaded());
    return _cache[_key(url, left)];
  }

  static Future<double?> of(String url, {bool left = false}) {
    final key = _key(url, left);
    return _pending[key] ??= _resolve(
      url,
      left,
      key,
    ).whenComplete(() => _pending.remove(key));
  }

  static Future<void> _ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final f = _file;
      if (f == null || !await f.exists()) return;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in map.entries) {
        if (value is num) _cache.putIfAbsent(key, () => value.toDouble());
      }
    } catch (_) {
      // 读坏了就当没有,量过的会重新写一份
    }
  }

  static Future<double?> _resolve(String url, bool left, String key) async {
    await _ensureLoaded();
    if (_cache[key] case final v?) return v;
    double? v;
    try {
      v = await _measure(url, left).timeout(_measureTimeout);
    } catch (_) {
      return null;
    }
    if (v != null) {
      _cache.remove(key);
      _cache[key] = v;
      while (_cache.length > _maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      _saveTimer?.cancel();
      _saveTimer = Timer(_saveDelay, _save);
    }
    return v;
  }

  static Future<void> _save() async {
    try {
      await _file?.writeAsString(
        jsonEncode({
          for (final MapEntry(:key, :value) in _cache.entries)
            key: (value * 1000).round() / 1000,
        }),
      );
    } catch (_) {}
  }

  /// 取样区的横向范围(占宽度的比例)。
  static (double, double) _span(bool left) => left ? (0, .65) : (.15, .85);

  static Future<double?> _measure(String url, bool left) async {
    if (!Platform.isAndroid) return _measureDecoded(url, left);
    final (x0, x1) = _span(left);
    // 远端图优先给缓存文件的路径,免得把整份字节从 Dart 拷过通道
    final path = url.startsWith('http')
        ? await RemoteImageStore.cachedPath(url)
        : url;
    return _channel.invokeMethod<double>('measure', {
      'path': path,
      'bytes': path == null ? await fetchRemoteImageBytes(url) : null,
      'x0': x0,
      'x1': x1,
    });
  }

  /// 非安卓:Flutter 解一张小图再读回像素。读回要等 GPU,比安卓那条慢。
  static Future<double?> _measureDecoded(String url, bool left) async {
    final ImageProvider base = url.startsWith('http')
        ? RemoteImageProvider(url, version: RemoteImageStore.versionOf(url))
        : FileImage(File(url));
    final stream = ResizeImage(
      base,
      width: 24,
      policy: ResizeImagePolicy.fit,
    ).resolve(ImageConfiguration.empty);
    final done = Completer<ui.Image?>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete(info.image.clone());
        info.dispose();
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final img = await done.future;
    if (img == null) return null;
    try {
      final data = await img.toByteData();
      if (data == null) return null;
      final w = img.width, h = img.height;
      final (x0, x1) = _span(left);
      var sum = 0.0;
      var n = 0;
      for (var y = (h * .78).floor(); y < h; y++) {
        for (var x = (w * x0).floor(); x < (w * x1).ceil(); x++) {
          final i = (y * w + x) * 4;
          sum +=
              .2126 * data.getUint8(i) +
              .7152 * data.getUint8(i + 1) +
              .0722 * data.getUint8(i + 2);
          n++;
        }
      }
      return n == 0 ? null : sum / n / 255;
    } finally {
      img.dispose();
    }
  }
}

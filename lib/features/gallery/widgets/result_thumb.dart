import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/theme/app_theme.dart' show Motion;
import '../../generate/widgets/common.dart' show StripeThumb;
import '../gallery_store.dart';
import '../models.dart';

/// 缩略图:内存有字节直接用;没有(重启水合/RAM 减负)按 id 懒读盘上
/// 缩略图,读到并解码出来之前垫斜纹占位。胶片条与网格共用,尺寸由外部给定。
/// 按格子大小解码,不按原图 / 缩略图文件的尺寸。
class ResultThumb extends ConsumerWidget {
  const ResultThumb({
    super.key,
    required this.result,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  final ResultImage result;
  final double width;
  final double height;
  final double radius;

  /// 解码宽度按 64px 一档取整:捏合换列时不至于每一帧都换一份解码。
  static int _bucket(double px) => math.max(64, (px / 64).ceil() * 64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = result.bytes;
    final ImageProvider base = bytes != null
        ? MemoryImage(bytes)
        : GalleryThumbImage(result.id, ref.watch(appStoresProvider).gallery);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // cover:按图的长宽比算出铺满格子所需的解码宽度
    final w = result.width, h = result.height;
    final scale = w > 0 && h > 0
        ? math.max(width / w, height / h)
        : math.max(width, height);
    final decodeW = _bucket((w > 0 ? w * scale : scale) * dpr);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: ResizeImage(base, width: decodeW),
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            StripeThumb(width: width, height: height, radius: radius),
        // 解码出第一帧前仍垫着斜纹,出来后交叉淡入;缓存里现成的直接画
        frameBuilder: (context, child, frame, sync) => sync
            ? child
            : Stack(
                children: [
                  AnimatedOpacity(
                    opacity: frame == null ? 1 : 0,
                    duration: Motion.fast,
                    child: StripeThumb(
                      width: width,
                      height: height,
                      radius: radius,
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: Motion.fast,
                    child: child,
                  ),
                ],
              ),
      ),
    );
  }
}

/// 图库缩略图(按 id 认)。同一张反复进出视野直接命中 ImageCache,
/// 不再每次重读文件、换一份字节就换一份解码。
class GalleryThumbImage extends ImageProvider<GalleryThumbImage> {
  const GalleryThumbImage(this.id, this.store);

  final String id;
  final GalleryStore store;

  @override
  Future<GalleryThumbImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    GalleryThumbImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'gallery-thumb:$id',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await store.readThumb(id);
    if (bytes == null) throw StateError('缩略图读不到: $id');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryThumbImage &&
      other.id == id &&
      identical(other.store, store);

  @override
  int get hashCode => Object.hash(id, identityHashCode(store));
}

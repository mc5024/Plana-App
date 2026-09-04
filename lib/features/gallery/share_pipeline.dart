import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../core/store/cache_sweep.dart' show kShareCacheDir;
import 'gallery_store.dart';
import 'models.dart';
import 'save_pipeline.dart';
import 'save_settings.dart';

/// 把这几张按保存设置处理好、落进分享缓存,返回可交给系统分享面板的文件。
/// 网格弹层的批量 / 单张分享与胶片条的上滑分享共用这一条路。
///
/// 刻意走 processForSave 这条**与保存同一条**的管线 —— 把元数据设成
/// 「清除」的人,不会希望分享出去的那份又把提示词带上。
///
/// 落在 cache/[kShareCacheDir]/,每次分享前先整个清掉:给出去的是 content
/// URI,接收方当场就拷走了,留着只会在缓存里越积越多(sweepPickerCache
/// 也认这个目录名,存储管理那边手动清理一并带走)。
///
/// `failed` 是读不出来 / 处理失败而跳过的张数。[onEach] 每处理完一张调一次
/// (批量进度用),返回 false 即中止剩余 —— 弹层已经关了那种。
Future<({List<XFile> files, int failed})> prepareShareFiles(
  List<ResultImage> items, {
  required GalleryStore store,
  required SaveSettings settings,
  bool Function(int done)? onEach,
}) async {
  final jpg = settings.format == SaveFormat.jpg;
  final files = <XFile>[];
  var failed = 0;
  try {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/$kShareCacheDir',
    );
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    for (final r in items) {
      try {
        final bytes = r.bytes ?? await store.readImage(r.id);
        if (bytes == null) {
          failed++;
        } else {
          final out = await processForSave(bytes, settings);
          final f = File('${dir.path}/plana_${r.seed}.${jpg ? 'jpg' : 'png'}');
          await f.writeAsBytes(out, flush: true);
          files.add(XFile(f.path, mimeType: jpg ? 'image/jpeg' : 'image/png'));
        }
      } catch (_) {
        failed++;
      }
      if (onEach != null && !onEach(files.length + failed)) break;
    }
  } catch (_) {
    failed = items.length - files.length;
  }
  return (files: files, failed: failed);
}

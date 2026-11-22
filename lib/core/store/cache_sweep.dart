import '../util/log.dart';
import 'package:path_provider/path_provider.dart';

/// 分享用的临时图落这里(gallery_grid_sheet)。每次分享前自己会清一次,
/// 这里再兜一道:分享到一半退出的残留、以及存储管理里手动清理。
const kShareCacheDir = 'plana_share';

// file_picker 建的 UUID 目录 / image_picker 落的 UUID 文件
final _uuidLike = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(\..*)?$',
);

String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return path.substring(i + 1);
}

/// 清选图器缓存垃圾:file_picker 每次选文件都往 `cache/file_picker/<时间戳>/`
/// 复制一份(LoRA、备份包动辄上百 MB)且从不回收,越积越大。只删这个目录、
/// 「UUID 命名」的顶层条目、遗留的 .onnx 模型缓存与几种前缀文件,其余不碰;
/// [minAge] 内的新鲜条目豁免(启动自动清扫默认 1 小时,防碰到本次会话
/// 正在用的临时文件;存储管理手动清理传 Duration.zero 全清)。
Future<void> sweepPickerCache({
  Duration minAge = const Duration(hours: 1),
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final cutoff = DateTime.now().subtract(minAge);
    var deleted = 0, kept = 0;
    await for (final ent in dir.list()) {
      final name = _baseName(ent.path);
      final junk =
          _uuidLike.hasMatch(name) ||
          name.endsWith('.onnx') ||
          name.startsWith('image_picker') ||
          name.startsWith('scaled_') ||
          name == 'file_picker' ||
          name == kShareCacheDir;
      if (!junk) {
        kept++;
        continue;
      }
      try {
        if ((await ent.stat()).modified.isAfter(cutoff)) {
          kept++;
          continue; // 新鲜豁免
        }
        await ent.delete(recursive: true);
        deleted++;
      } catch (e) {
        logd('[cache-sweep] 删不掉 $name: $e');
      }
    }
    logd('[cache-sweep] 清掉 $deleted 项,保留 $kept 项');
  } catch (e) {
    logd('[cache-sweep] 失败: $e');
  }
}

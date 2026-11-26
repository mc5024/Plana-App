import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' show AssetEntity;

import '../theme/theme_settings.dart';
import '../ui/gallery_picker_page.dart';
import 'harmony_compat.dart';
import 'log.dart';

/// 选中的图片:文件名 + 原始字节。
class PickedImage {
  const PickedImage(this.name, this.bytes);

  final String name;
  final Uint8List bytes;

  /// 去扩展名(入库命名/展示用)。
  String get baseName => name.replaceAll(RegExp(r'\.[^.]+$'), '');
}

/// 选单张图片,取消返回 null。
///
/// Android:默认应用内图库选择器(直读媒体库,全部相册可达;系统照片选择器
/// 只放行固定分类且不看 app 权限),右上角可改走系统选择器兜底;
/// 设置里选了系统、或在卓易通这类容器里,直接走系统选择器,见 [_inAppGallery]。
/// 桌面端:原生文件对话框。
Future<PickedImage?> pickImageFile(BuildContext context) async {
  final list = await _pick(context, multiple: false);
  return list.isEmpty ? null : list.first;
}

/// 选多张图片,取消/空选返回空列表。
Future<List<PickedImage>> pickImageFiles(BuildContext context) =>
    _pick(context, multiple: true);

/// [pickImagesOrFiles] 的结果:图库与文件浏览器二选一,同一次只有一支非空。
class PickedSources {
  const PickedSources.images(this.images) : files = const [];

  const PickedSources.files(this.files) : images = const [];

  const PickedSources.none() : images = const [], files = const [];

  /// 从应用内图库选的图,字节已读好。
  final List<PickedImage> images;

  /// 从系统文件浏览器选的文件,字节未读(见 `file_read.dart`)。
  final List<PlatformFile> files;

  bool get isEmpty => images.isEmpty && files.isEmpty;
}

/// 同 [pickImageFiles],但「从文件选」那支走系统文件浏览器且**不限类型**:
/// 图片之外的内容(如 .naiv4vibe / .naiv4vibebundle)也挑得到,由调用方按
/// 内容自行分流。**别跟着 [_pick] 改成图片类别** —— 那会把这类自定义后缀
/// 直接挡在外面(没有对应 MIME),顺带也会漏掉文件管理器认不出 MIME 的图。
///
/// 文件那支不预读字节:整包 vibe 可能上百 MB(图是 base64),`withData` 会把
/// 整批堆进内存;交调用方按 `file_read.dart` 流式读。
Future<PickedSources> pickImagesOrFiles(BuildContext context) async {
  if (await _inAppGallery(context)) {
    if (!context.mounted) return const PickedSources.none();
    final out = await _gallery(context, multiple: true);
    if (out == null) return const PickedSources.none();
    if (!out.useFileBrowser) {
      return PickedSources.images(out.images);
    }
    // 用户点了「从文件选」→ 落到下方系统文件浏览器
  }
  final res = await FilePicker.platform.pickFiles(
    type: FileType.any,
    allowMultiple: true,
  );
  return PickedSources.files(res?.files ?? const []);
}

Future<List<PickedImage>> _pick(
  BuildContext context, {
  required bool multiple,
}) async {
  if (await _inAppGallery(context)) {
    if (!context.mounted) return const [];
    final out = await _gallery(context, multiple: multiple);
    if (out == null) return const [];
    if (!out.useFileBrowser) return out.images;
    // 用户点了「从文件选」→ 落到下方系统文件浏览器
  }
  final res = await FilePicker.platform.pickFiles(
    // 挑的就是图,给系统图片类别:Android 上走 ACTION_PICK,落到系统相册/
    // 照片选择器;桌面端是原生对话框的图片过滤。
    // (只有 vibe 那支要连 .naiv4vibe 一起挑,走 FileType.any,见
    // [pickImagesOrFiles]。allowedExtensions 只配 FileType.custom,别加。)
    type: FileType.image,
    allowMultiple: multiple,
    withData: true,
    compressionQuality: 0, // 禁止重压缩:PNG 里的生成参数元数据必须原样保留
  );
  return [
    for (final f in res?.files ?? const <PlatformFile>[])
      if (f.bytes case final b? when b.isNotEmpty) PickedImage(f.name, b),
  ];
}

/// 先进应用内图库吗:仅 Android;设置里选过就按设置,没选过默认进 ——
/// 鸿蒙的安卓兼容容器(卓易通 / 出境易)里默认不进,直接落到图库右上角那个
/// 入口(系统选择器 / 文件浏览器)。容器里的媒体库桥接在鸿蒙侧,应用内图库
/// 逐张查库、查文件都要跨过去一趟,进页比普通机慢得多。
Future<bool> _inAppGallery(BuildContext context) async {
  if (!Platform.isAndroid) return false;
  final system = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(themeSettingsProvider).systemPicker;
  return !(system ?? await isHarmonyCompatContainer);
}

/// 应用内图库选择器,返回 null = 用户取消。
Future<GalleryPickOutcome?> _gallery(
  BuildContext context, {
  required bool multiple,
}) => Navigator.of(context).push<GalleryPickOutcome>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => GalleryPickerPage(multiple: multiple),
  ),
);

/// 图库资产 → 原文件字节(PNG 元数据原样保留)。
/// 优先走 [AssetEntity.originFile] 直接在 Dart 侧读文件,减少原生侧内存拷贝与
/// MethodChannel 大字节传输;拿不到文件或读失败时回落 [AssetEntity.originBytes]。
Future<PickedImage?> readAssetImage(AssetEntity a) async {
  Uint8List? bytes;
  try {
    final file = await a.originFile;
    if (file != null && await file.exists()) {
      bytes = await file.readAsBytes();
    }
  } catch (e) {
    logd('[picker] originFile 读取失败(${a.id}),回落 originBytes: $e');
  }
  if (bytes == null || bytes.isEmpty) {
    try {
      bytes = await a.originBytes;
    } catch (e) {
      logd('[picker] originBytes 读取失败(${a.id}): $e');
      return null;
    }
  }
  if (bytes == null || bytes.isEmpty) return null;
  var name = a.title ?? '';
  if (name.isEmpty) {
    try {
      name = await a.titleAsync;
    } catch (_) {}
  }
  return PickedImage(name.isEmpty ? 'image' : name, bytes);
}

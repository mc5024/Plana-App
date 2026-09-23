import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/assistant/session_store.dart';
import '../../features/gallery/gallery_store.dart';
import '../../features/gallery/albums/album_store.dart';
import '../../features/generate/workspace_store.dart';
import '../../features/stats/key_ledger.dart';
import '../net/remote_image.dart';
import 'blob_store.dart';
import 'cache_sweep.dart';
import 'prefs_store.dart';
import 'storage_stats.dart';

/// 应用级持久化门面:main() 启动时 [open](读工作台存档 + 图库索引),
/// 经 [appStoresProvider] 注入;各 Notifier 从这里水合初始状态、
/// 往这里排队落盘。任何一环载入失败都按「首启空档」降级,不 brick 启动。
class AppStores {
  AppStores._(
    this.blobs,
    this.workspace,
    this.gallery,
    this.ledger,
    this.assistant,
    this.prefs,
    this.albums,
  );

  final BlobStore blobs;
  final WorkspaceStore workspace;
  final GalleryStore gallery;
  final AlbumStore albums;
  final KeyLedgerStore ledger;

  /// AI 助手的对话存档,见 [AssistantStore]。
  final AssistantStore assistant;

  /// 非机密设置(主题/生成参数/编辑器…),见 [PrefsStore]。
  final PrefsStore prefs;

  /// 测试用空档:临时目录、不读盘;写入尽力而为。
  factory AppStores.ephemeral() {
    final root = Directory.systemTemp.createTempSync('plana_stores');
    RemoteImageStore.bind(root);
    final blobs = BlobStore(root);
    return AppStores._(
      blobs,
      WorkspaceStore(blobs, root),
      GalleryStore(blobs, root),
      KeyLedgerStore(root),
      AssistantStore(blobs, root),
      PrefsStore.emptyForTest(root),
      AlbumStore(root),
    );
  }

  /// [rootOverride]:测试指定根目录(生产走平台 support 目录)。
  static Future<AppStores> open({Directory? rootOverride}) async {
    Directory root;
    if (rootOverride != null) {
      root = rootOverride;
    } else {
      try {
        root = await getApplicationSupportDirectory();
      } catch (_) {
        root = Directory.systemTemp; // 拿不到目录的极端兜底:本次会话内存态可用
      }
    }
    // 远端图缓存目录:ImageProvider 拿不到 ref,只能挂静态量,这里是唯一
    // 知道 root 的地方(见 RemoteImageStore)。
    RemoteImageStore.bind(root);
    final blobs = BlobStore(root);
    final workspace = WorkspaceStore(blobs, root);
    final gallery = GalleryStore(blobs, root);
    final albums = AlbumStore(root);
    final ledger = KeyLedgerStore(root);
    final assistant = AssistantStore(blobs, root);
    try {
      await blobs.ensureReady();
    } catch (_) {}
    // 设置先于其余项:主题要在首帧前拿到,且它一次读全,后面各模块都走内存
    final prefs = await PrefsStore.open(root);
    await workspace.load();
    await gallery.load();
    await albums.load(liveImages: gallery.initialResults.map((r) => r.id).toSet());
    await ledger.load();
    await assistant.load();
    return AppStores._(
      blobs,
      workspace,
      gallery,
      ledger,
      assistant,
      prefs,
      albums,
    );
  }

  /// 退后台/失焦即刻把防抖窗口里的挂起状态落盘(进程被杀不丢)。
  void flushNow() {
    workspace.flush();
    gallery.flushIndex();
    ledger.flush();
    assistant.flush();
  }

  /// 启动后台维护(避开首帧,延迟几秒):清选图器缓存垃圾 + 远端图缓存裁剪
  /// + blob GC。
  void postBootMaintenance() {
    Future<void>(() async {
      await Future<void>.delayed(const Duration(seconds: 6));
      await sweepPickerCache();
      await RemoteImageStore.trim();
      await clearRetiredRoleLexicon();
      try {
        final live = <String>{
          ...await workspace.liveRefs(),
          ...await gallery.liveRefs(),
          // 漏了这行 = AI 助手里用户带的图在启动第 6 秒被 GC 掉
          ...await assistant.liveRefs(),
        };
        await blobs.gc(live);
      } catch (_) {}
    });
  }
}

final appStoresProvider = Provider<AppStores>(
  (_) => throw StateError('AppStores 未注入:main() 需 overrideWithValue'),
);

/// 非机密设置的读写出口。**新设置项一律用这个,不要再往 secure storage 塞**
/// —— 那里的 `resetOnError` 默认会在 Keystore 故障时把所有条目一起清空。
/// 见 [PrefsStore]。
final prefsStoreProvider = Provider<PrefsStore>(
  (ref) => ref.read(appStoresProvider).prefs,
);

import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/store/storage_settings.dart';
import '../generate/models.dart' show GenerateState;
import '../generate/generation_controller.dart' show genNoticeProvider;
import 'albums/album_models.dart';
import 'albums/album_state.dart';
import 'gallery_search.dart';
import 'models.dart';

final galleryProvider = NotifierProvider<GalleryNotifier, GalleryState>(
  GalleryNotifier.new,
);

/// 结果原图懒读(重启水合/RAM 减负后 bytes 不在内存时用)。
/// autoDispose:画布/操作层不看了就释放,不在内存里囤整库。
final galleryImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, id) => ref.watch(appStoresProvider).gallery.readImage(id),
    );

/// 结果缩略图懒读(胶片条/网格用,缺缩略图时店内退回原图)。
final galleryThumbProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, id) => ref.watch(appStoresProvider).gallery.readThumb(id),
    );

/// 图库大图是否已放大(scale > 1)。画布据此撤掉分页 PageView 的翻页物理,
/// 把横向拖动整个让回 InteractiveViewer 做平移 —— 否则缩放后想拖着看细节,
/// 拖动会被翻页抢走(不跟手的根源)。shell 的 tab 横滑已关,与这里无关。
final galleryZoomedProvider = NotifierProvider<GalleryZoomedNotifier, bool>(
  GalleryZoomedNotifier.new,
);

// 「生成中画布视角」那个开关(galleryViewGenProvider)在并行化时删了:
// 画布跟随哪条任务已经由 GenPool.selectedId 说了算,一个布尔值表达不了
// 「跟着第几条」,两份状态并存只会打架。

/// 入库的参数快照:**只留启用的角色卡**。
///
/// 快照记的是「这张图是怎么出来的」,而禁用的卡根本没发出去(见 nai_request 的
/// `c.enabled` 过滤)。留着它们只有坏处:检索索引会把它们的标签当成这张图的,
/// 搜得到没画的东西,按角色分组还会归进没画的角色 —— 切模型时超出槽位的卡会被
/// 自动停用(见 generate_state 的 `_capEnabled`),所以这不是偶发。
///
/// 丢掉也不损失什么,快照的用处逐个核过:重新生成 / 重绘放大是直接拿快照出图
/// (本来就只发启用的);放大 / 重绘只是把快照带给新图;长按「导入」读的是 PNG
/// 里嵌的元数据,不读快照。
///
/// 升级前的老快照盘上还带着禁用卡,检索那边按 `enabled` 再筛一道兜住。
GenerateState gallerySnapshotOf(GenerateState s) =>
    s.characters.every((c) => c.enabled)
    ? s
    : s.copyWith(
        characters: [
          for (final c in s.characters)
            if (c.enabled) c,
        ],
      );

class GalleryZoomedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) {
    if (ref.mounted && state != v) state = v;
  }
}

class GalleryState {
  const GalleryState({required this.results, required this.selectedId});

  final List<ResultImage> results;
  final String? selectedId;

  bool get isEmpty => results.isEmpty;

  /// 当前选中项;selectedId 失效时回退到最新一张。
  ResultImage? get selected {
    for (final r in results) {
      if (r.id == selectedId) return r;
    }
    return results.isEmpty ? null : results.first;
  }

  GalleryState copyWith({
    List<ResultImage>? results,
    String? selectedId,
    bool clearSelection = false,
  }) => GalleryState(
    results: results ?? this.results,
    selectedId: clearSelection ? null : selectedId ?? this.selectedId,
  );
}

class GalleryNotifier extends Notifier<GalleryState> {
  int _seq = 0;
  int _selectionRevision = 0;
  int get selectionRevision => _selectionRevision;
  final _writes = <String, Future<void>>{};

  /// 最近这么多张保留内存字节;更旧的卸掉(盘上有,再看懒读),
  /// 挂机循环几百张不再无限吃 RAM。
  static const _keepBytesFor = 30;

  @override
  GalleryState build() {
    // 启动水合:索引给顺序/尺寸/选中,像素与快照按需懒读
    final store = ref.watch(appStoresProvider).gallery;
    _seq = store.seq;
    // 上限设置就绪/变更时裁剪(冷启动水合的超长历史也在这里收口)
    ref.listen(storageSettingsProvider, (_, next) {
      if (next.hasValue) enforceCap();
    });
    return GalleryState(
      results: store.initialResults,
      selectedId: store.initialSelectedId,
    );
  }

  /// 图库上限裁剪:超出上限删最旧(列表尾部),文件一并删。
  void enforceCap() {
    final cap = ref.read(storageSettingsProvider).value?.galleryCap ?? 0;
    if (cap <= 0 || state.results.length <= cap) return;
    final keep = state.results.sublist(0, cap);
    final drop = state.results.sublist(cap);
    // 选中项被裁掉时回退到最新一张
    final sel = keep.any((r) => r.id == state.selectedId)
        ? state.selectedId
        : (keep.isEmpty ? null : keep.first.id);
    state = GalleryState(results: keep, selectedId: sel);
    final dropIds = [for (final r in drop) r.id];
    ref.read(appStoresProvider).gallery.deleteResultFiles(dropIds);
    ref.read(gallerySearchProvider.notifier).removeAll(dropIds);
    _removeMemberships(dropIds);
    _persistIndex();
  }

  void _persistIndex() {
    ref
        .read(appStoresProvider)
        .gallery
        .scheduleIndex(
          results: state.results,
          selectedId: state.selectedId,
          seq: _seq,
        );
  }

  void select(String? id) {
    _selectionRevision++;
    ref.read(galleryResultPreviewProvider.notifier).clear();
    if (id == state.selectedId) return;
    state = state.copyWith(selectedId: id, clearSelection: id == null);
    _persistIndex();
  }

  /// 生成链路产出真实结果:前插并选中,同时落盘(原图/缩略图/参数快照)。
  ResultImage addResult({
    required Uint8List bytes,
    required int width,
    required int height,
    required int seed,
    ResultBadge badge = ResultBadge.none,
    GenerateState? input,

    /// 重绘产物的源图 id(供「按住对比」取原图);非重绘为 null。
    String? inpaintFrom,

    /// 这张在批次里的位置(-1 = 不是批次产物)。与 seed 一起决定这张图
    /// 将来还能不能复现,见 [ResultImage.batchIndex]。
    int batchIndex = -1,

    /// 是否顺带选中新图。并行出图时只有「画布正跟着的那条」才该抢选中 ——
    /// 后台某一条出完就把用户正看的图换掉,是并行最容易踩的坑。
    bool select = true,
  }) {
    final snap = input == null ? null : gallerySnapshotOf(input);
    final r = ResultImage(
      id: 'gen${_seq++}',
      width: width,
      height: height,
      seed: seed,
      badge: badge,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      batchIndex: batchIndex,
      inpaintFrom: inpaintFrom,
      bytes: bytes,
      input: snap,
    );
    // 检索索引同帧写入(input 在内存,零 IO)
    if (snap != null) {
      ref.read(gallerySearchProvider.notifier).put(r.id, snap);
    }
    var list = [r, ...state.results];
    if (list.length > _keepBytesFor) {
      list = [
        for (var i = 0; i < list.length; i++)
          i < _keepBytesFor ? list[i] : list[i].stripped(),
      ];
    }
    state = state.copyWith(
      results: list,
      selectedId: select ? r.id : state.selectedId,
    );
    // 蒙版不再按图存盘:它跟着创作页的重绘状态走(见 InpaintJob.grid),
    // 所以这里也没有「产物继承源图蒙版」这回事了。
    final write = ref.read(appStoresProvider).gallery.persistResult(r);
    _writes[r.id] = write;
    // addResult 仍供旧调用方同步使用；错误由异步入库接口报告。
    unawaited(
      write.then(
        (_) => _writes.remove(r.id),
        onError: (Object _, StackTrace _) {},
      ),
    );
    _persistIndex();
    enforceCap();
    return r;
  }

  /// 所有生成/处理产物经此提交：先保存原图，再提交归属，最后按视角选中。
  Future<ResultImage> addResultToGallery({
    required Uint8List bytes,
    required int width,
    required int height,
    required int seed,
    required GallerySaveTarget target,
    ResultBadge badge = ResultBadge.none,
    GenerateState? input,
    String? inpaintFrom,
    int batchIndex = -1,
    bool select = true,
    bool Function()? canSelect,
    bool notify = true,
  }) async {
    final revision = _selectionRevision;
    final r = addResult(
      bytes: bytes,
      width: width,
      height: height,
      seed: seed,
      badge: badge,
      input: input,
      inpaintFrom: inpaintFrom,
      batchIndex: batchIndex,
      select: false,
    );
    final store = ref.read(appStoresProvider).gallery;
    try {
      await _writes[r.id];
      await store.flushIndex();
    } catch (_) {
      unawaited(_writes.remove(r.id)?.catchError((Object _) {}));
      rethrow;
    }
    if (!ref.mounted || !state.results.any((e) => e.id == r.id)) return r;
    var actual = target;
    if (target.albumId != null) {
      try {
        await ref
            .read(albumsProvider.notifier)
            .organize({r.id}, {target.albumId!});
      } catch (_) {
        actual = const GallerySaveTarget.all();
        ref.read(genNoticeProvider.notifier).show('图片已保存在全部作品，目标图库不可用或归类失败');
      }
    }
    if (!ref.mounted || !state.results.any((e) => e.id == r.id)) return r;
    final inScope = ref
        .read(albumsProvider)
        .contains(ref.read(galleryBrowseAlbumProvider), r.id);
    if (select &&
        revision == _selectionRevision &&
        (canSelect?.call() ?? true)) {
      if (inScope) {
        this.select(r.id);
      } else {
        ref.read(galleryResultPreviewProvider.notifier).show(r.id, actual);
      }
    } else if (notify && !inScope) {
      ref.read(gallerySavedNoticeProvider.notifier).show(r.id, actual);
    }
    return r;
  }

  void _removeMemberships(List<String> ids) {
    unawaited(
      ref.read(albumsProvider.notifier).removeImages(ids.toSet()).catchError((
        Object _,
      ) {
        if (ref.mounted) {
          ref.read(genNoticeProvider.notifier).show('图片已删除，图库归属清理失败');
        }
      }),
    );
    final preview = ref.read(galleryResultPreviewProvider);
    if (preview != null && ids.contains(preview.imageId)) {
      ref.read(galleryResultPreviewProvider.notifier).clear();
    }
  }

  /// 删除单张或多张图片:状态移除 + 盘上文件一并删。
  /// 删除当前图片时，沿当前图库顺序选下一张；没有下一张则选上一张。
  void deleteResults(List<String> ids) {
    if (ids.isEmpty) return;
    final drop = ids.toSet();
    final keep = [
      for (final r in state.results)
        if (!drop.contains(r.id)) r,
    ];
    if (keep.length == state.results.length) return;
    // 不读取依赖本 provider 的 galleryViewProvider，避免循环依赖。
    final scope = ref.read(galleryBrowseAlbumProvider);
    final albums = ref.read(albumsProvider);
    final visible = state.results
        .where((r) => albums.contains(scope, r.id))
        .toList();
    final current = visible.any((r) => r.id == state.selectedId)
        ? state.selectedId
        : visible.firstOrNull?.id;
    var sel = state.selectedId;
    if (drop.contains(current) || drop.contains(sel)) {
      // 使用删除前的浏览集合，避免跨到其他图库或因索引平移跳回第一张。
      final at = visible.indexWhere((r) => r.id == current);
      sel = null;
      for (var i = at; i >= 0 && i < visible.length; i++) {
        if (!drop.contains(visible[i].id)) {
          sel = visible[i].id;
          break;
        }
      }
      if (sel == null) {
        for (var i = at - 1; i >= 0; i--) {
          if (!drop.contains(visible[i].id)) {
            sel = visible[i].id;
            break;
          }
        }
      }
      // 删除产生的新选择也优先于仍在异步入库的结果。
      _selectionRevision++;
    }
    state = GalleryState(results: keep, selectedId: sel);
    ref.read(appStoresProvider).gallery.deleteResultFiles(ids);
    ref.read(gallerySearchProvider.notifier).removeAll(ids);
    _removeMemberships(ids);
    _persistIndex();
  }

  /// 清空图库(存储管理):内存态与盘上文件一并清,发号器保留不复用。
  Future<void> clearAll() async {
    final store = ref.read(appStoresProvider).gallery;
    final albums = ref.read(albumsProvider.notifier);
    _selectionRevision++;
    state = const GalleryState(results: [], selectedId: null);
    final clearFiles = store.clearAllFiles(seq: _seq);
    ref.read(gallerySearchProvider.notifier).clear();
    await albums.clearAll();
    await clearFiles;
  }
}

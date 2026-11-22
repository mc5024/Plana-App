import '../../core/util/log.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/store/atomic_file.dart';
import '../../core/store/blob_store.dart';
import '../../core/util/image_ops.dart';
import '../../core/util/webp_to_png.dart' show isWebp;
import '../generate/models.dart' show GenerateState, imageSizeOf;
import '../generate/state_codec.dart';
import 'models.dart';

/// 一张图的检索元数据(见 gallery_search):[text] 已按 normalizeSearchText 归一;
/// 后三项是图库按角色 / 画风归类认的来源 —— [ids] 灵感库条目 id(分区与角色卡
/// 记下的),[cards] 启用的角色卡名,[folds] 草稿里的折叠组名。
typedef GallerySearchMeta = ({
  String model,
  String text,
  List<String> ids,
  List<String> cards,
  List<String> folds,
});

/// 图库持久化(`<support>/gallery/`):每张结果 `images/<id>.png` 原图(生成设置选了保持
/// WebP 的是 `<id>.webp`)+
/// `thumbs/<id>.jpg` 缩略图(带透明的是 .png)+ `inputs/<id>.json` 参数快照(参考图外置
/// blob 仓),旁挂 index.json(顺序/选中/发号器/回收站)。启动只读索引,像素
/// 按需懒读——重启不丢图,也不把整库塞回内存。
class GalleryStore {
  GalleryStore(this._blobs, Directory supportRoot)
    : _root = Directory('${supportRoot.path}/gallery');

  final BlobStore _blobs;
  final Directory _root;

  Directory get _imagesDir => Directory('${_root.path}/images');
  Directory get _thumbsDir => Directory('${_root.path}/thumbs');
  Directory get _inputsDir => Directory('${_root.path}/inputs');
  File get _indexFile => File('${_root.path}/index.json');

  File _imageFile(String id) => File('${_imagesDir.path}/$id.png');
  File _imageWebp(String id) => File('${_imagesDir.path}/$id.webp');

  /// 盘上那张原图(PNG 优先);都没有给 null。
  Future<File?> _existingImage(String id) async {
    for (final f in [_imageFile(id), _imageWebp(id)]) {
      if (await f.exists()) return f;
    }
    return null;
  }

  File _thumbPng(String id) => File('${_thumbsDir.path}/$id.png');
  File _thumbJpg(String id) => File('${_thumbsDir.path}/$id.jpg');
  File _inputFile(String id) => File('${_inputsDir.path}/$id.json');

  /// 重绘产物要继承的源图 id:发起重绘时置,落新图时**消费一次**后清空。
  /// 「只继承一次」的语义就落在这里 —— 此后两张图的蒙版各自独立编辑保存。

  /// 启动读出的图库(字节/快照皆空壳,懒读);首启为空。
  List<ResultImage> initialResults = const [];

  /// 启动读出的回收站,新删的在前。
  List<TrashedImage> initialTrash = const [];
  String? initialSelectedId;
  int seq = 0;

  static final _seqRe = RegExp(r'^gen(\d+)$');

  Future<void> load() async {
    try {
      await _imagesDir.create(recursive: true);
      await _thumbsDir.create(recursive: true);
      await _inputsDir.create(recursive: true);
      if (!await _indexFile.exists()) {
        await _rebuildFromDisk(); // 索引缺失但图还在(如首次升级/被误删)
        return;
      }
      final path = _indexFile.path;
      final d = await _parseIndexInIsolate(path);
      if (d == null) {
        await _rebuildFromDisk();
        return;
      }
      seq = d.seq;
      initialSelectedId = d.selectedId;
      for (var i = 0; i < d.items.length; i++) {
        _itemFrag[d.items[i]] = d.itemJson[i];
      }
      initialTrash = List.unmodifiable(d.trash);
      initialResults = List.unmodifiable(await _backfillCreatedAt(d.items));
      if (await _selFile.exists()) {
        final s = (await _selFile.readAsString()).trim();
        initialSelectedId = s.isEmpty ? null : s;
      }
      _flushedItems = initialResults;
      _flushedTrash = initialTrash;
      _flushedSeq = seq;
      _flushedSel = initialSelectedId;
    } catch (e) {
      logd('[gallery-store] 索引载入失败,改从目录重建: $e');
      await _rebuildFromDisk();
    }
  }

  /// 索引里的一条;坏条目返回 null。
  static ResultImage? _parseItem(Object? e) {
    if (e is! Map || e['id'] is! String) return null;
    final id = e['id'] as String;
    ResultBadge badge = ResultBadge.none;
    for (final b in ResultBadge.values) {
      if (b.name == e['badge']) badge = b;
    }
    return ResultImage(
      id: id,
      width: (e['w'] as num?)?.toInt() ?? 0,
      height: (e['h'] as num?)?.toInt() ?? 0,
      seed: (e['seed'] as num?)?.toInt() ?? 0,
      badge: badge,
      createdAt: (e['t'] as num?)?.toInt() ?? 0,
      // 老索引没这键 → -1(不是批次产物)
      batchIndex: (e['bi'] as num?)?.toInt() ?? -1,
      inpaintFrom: e['from'] as String?,
      saved: e['sv'] == true,
      hasInput: e['hasInput'] == true,
    );
  }

  static Map<String, Object?> _itemJson(ResultImage r) => {
    'id': r.id,
    'w': r.width,
    'h': r.height,
    'seed': r.seed,
    'badge': r.badge.name,
    't': r.createdAt,
    // 批次内位置。只有批次产物才写,单张不占位
    if (r.batchIndex >= 0) 'bi': r.batchIndex,
    if (r.inpaintFrom != null) 'from': r.inpaintFrom,
    if (r.saved) 'sv': true,
    'hasInput': r.hasInput,
  };

  /// 条目 / 回收站条目各自编码好的 JSON 片段。条目对象不可变,改动都会换新对象,
  /// 所以按对象记;重写索引时只编码新对象,其余直接拼。
  static final _itemFrag = Expando<String>();
  static final _trashFrag = Expando<String>();

  static String _indexText(
    int seq,
    String? selected,
    List<ResultImage> items,
    List<TrashedImage> trash,
  ) {
    final b = StringBuffer('{"v":1,"seq":$seq');
    if (selected != null) b.write(',"selectedId":${jsonEncode(selected)}');
    b.write(',"items":[');
    for (var i = 0; i < items.length; i++) {
      if (i > 0) b.write(',');
      final r = items[i];
      b.write(_itemFrag[r] ??= jsonEncode(_itemJson(r)));
    }
    b.write(']');
    if (trash.isNotEmpty) {
      b.write(',"trash":[');
      for (var i = 0; i < trash.length; i++) {
        if (i > 0) b.write(',');
        final t = trash[i];
        b.write(
          _trashFrag[t] ??= jsonEncode({
            ..._itemJson(t.image),
            'dt': t.deletedAt,
          }),
        );
      }
      b.write(']');
    }
    b.write('}');
    return b.toString();
  }

  /// 生成时刻缺失(升级前的老索引)→ 原图文件 mtime 一次性回填并落索引,
  /// 之后不再 stat。mtime 在备份恢复场景可能失真,但它是老图唯一可用来源。
  Future<List<ResultImage>> _backfillCreatedAt(List<ResultImage> items) async {
    var changed = false;
    final out = <ResultImage>[];
    for (final r in items) {
      if (r.createdAt > 0) {
        out.add(r);
        continue;
      }
      var t = 0;
      try {
        final f = await _existingImage(r.id);
        if (f != null) {
          t = (await f.stat()).modified.millisecondsSinceEpoch;
        }
      } catch (_) {}
      if (t > 0) changed = true;
      out.add(t > 0 ? r.withCreatedAt(t) : r);
    }
    if (changed) {
      // 防抖窗口内被杀也无妨:回填幂等,下次启动重来
      scheduleIndex(
        results: out,
        trash: initialTrash,
        selectedId: initialSelectedId,
        seq: seq,
      );
    }
    return out;
  }

  /// 索引损坏 / 缺失时的兜底:扫 `images/` 重建条目并续上发号器。
  ///
  /// **为什么必须有**:原先失败路径直接把库当成空的,而 `seq` 的赋值在 try 内
  /// 没跑到、停在初始值 `0` —— 下一张生成写 `images/gen0.png`,**覆盖盘上仍在
  /// 的老图**,事后修好索引也回不来。`vibe_library` / `char_library` 早就有
  /// 目录重建兜底,唯独图库没有,而图库存的恰恰是最不可再生的东西。见 S1C-01。
  ///
  /// **代价**:seed 与角标(`4x` / `重绘`)只存在索引里,重建取不回来,按
  /// `0` / `none` 处理;原图与参数快照都还在,重新生成、参数导入照常可用。
  Future<void> _rebuildFromDisk() async {
    final out = <ResultImage>[];
    var maxSeq = 0;
    try {
      final files = <File>[];
      await for (final ent in _imagesDir.list()) {
        if (ent is File &&
            (ent.path.endsWith('.png') || ent.path.endsWith('.webp'))) {
          files.add(ent);
        }
      }
      int numOf(File f) {
        final m = _seqRe.firstMatch(_idOf(f));
        return m == null ? -1 : int.parse(m.group(1)!);
      }

      files.sort((a, b) => numOf(a).compareTo(numOf(b))); // 还原生成先后
      for (final f in files) {
        final id = _idOf(f);
        final (w, h) = await _imageSize(f);
        var t = 0;
        try {
          t = (await f.stat()).modified.millisecondsSinceEpoch;
        } catch (_) {}
        out.add(
          ResultImage(
            id: id,
            width: w,
            height: h,
            seed: 0,
            badge: ResultBadge.none,
            createdAt: t > 0 ? t : 0,
            hasInput: await _inputFile(id).exists(),
          ),
        );
        final n = numOf(f);
        if (n + 1 > maxSeq) maxSeq = n + 1;
      }
    } catch (e) {
      logd('[gallery-store] 目录重建失败: $e');
    }
    initialResults = List.unmodifiable(out);
    initialTrash = const []; // 回收站只记在索引里,重建时连同其余图一起回到列表
    initialSelectedId = out.isEmpty ? null : out.last.id;
    // 关键一行:发号器只进不退,否则新图会覆盖盘上老图
    if (maxSeq > seq) seq = maxSeq;
    if (out.isNotEmpty) {
      logd('[gallery-store] 已从目录重建 ${out.length} 条,发号器续到 $seq');
    }
  }

  static String _idOf(File f) {
    final n = f.uri.pathSegments.last;
    return n.substring(0, n.lastIndexOf('.')); // 去 .png / .webp
  }

  /// 只读文件头拿宽高(PNG 的 IHDR / WebP 的 VP8X 等),不解码整图。
  static Future<(int, int)> _imageSize(File? f) async {
    if (f == null) return (0, 0);
    try {
      final head = <int>[];
      await for (final chunk in f.openRead(0, 30)) {
        head.addAll(chunk);
        if (head.length >= 30) break;
      }
      return imageSizeOf(Uint8List.fromList(head)) ?? (0, 0);
    } catch (_) {
      return (0, 0);
    }
  }

  // ---- 写入(串行队列,互不重叠) ----

  Future<void> _chain = Future.value();

  /// 写入队列与后台删除都排空(存储管理在清空后等它,再做 GC/重扫)。
  Future<void> get idle =>
      Future.wait([_chain, _searchChain, _deleting]).then((_) {});

  Future<void> _enqueue(Future<void> Function() job) {
    final work = _chain.then((_) => job());
    _chain = work.catchError((Object e) {
      logd('[gallery-store] 写入失败: $e');
    });
    return work;
  }

  /// 新结果落盘:原图 + 缩略图 + 参数快照(有则)。
  /// 调用时机是 addResult 同帧,bytes/input 一定在内存里。
  Future<void> persistResult(ResultImage r) {
    final bytes = r.bytes;
    if (bytes == null) return Future.value();
    final input = r.input;
    return _enqueue(() async {
      // 全部走原子写:半截 PNG 会变成永远打不开的坏图,半截快照 JSON 会让
      // 「重新生成」读不出参数(见 atomic_file.dart)
      await writeBytesAtomic(
        isWebp(bytes) ? _imageWebp(r.id) : _imageFile(r.id),
        bytes,
      );
      try {
        await _writeThumb(r.id, await makeThumb(bytes));
      } catch (_) {} // 缩略图失败不阻断,读取端退回原图
      if (input != null) {
        final enc = await encodeGenerateState(input, _blobs);
        await writeStringAtomic(
          _inputFile(r.id),
          jsonEncode({'v': 1, 'refs': enc.refs.toList(), 'state': enc.json}),
        );
      }
    });
  }

  // 索引防抖:新增/点选共用,窗口内合并成一次全量重写
  Timer? _idxTimer;
  List<ResultImage>? _idxItems;
  List<TrashedImage> _idxTrash = const [];
  String? _idxSelected;
  int _idxSeq = 0;
  Future<void> _indexWrite = Future.value();

  void scheduleIndex({
    required List<ResultImage> results,
    List<TrashedImage> trash = const [],
    required String? selectedId,
    required int seq,
  }) {
    _idxItems = results;
    _idxTrash = trash;
    _idxSelected = selectedId;
    _idxSeq = seq;
    _idxTimer?.cancel();
    _idxTimer = Timer(const Duration(milliseconds: 400), flushIndex);
  }

  // 盘上索引 / 选中记录对应的状态:条目没变只换了选中,就只写选中记录
  List<ResultImage>? _flushedItems;
  List<TrashedImage>? _flushedTrash;
  int? _flushedSeq;
  String? _flushedSel;

  File get _selFile => File('${_root.path}/selected.txt');

  /// 立即写索引(前后台切换时由 AppStores.flushNow 调用)。
  Future<void> flushIndex() {
    final items = _idxItems;
    if (items == null) return _indexWrite;
    _idxItems = null;
    _idxTimer?.cancel();
    final trash = _idxTrash;
    final selected = _idxSelected;
    final seq = _idxSeq;
    final itemsChanged =
        !identical(items, _flushedItems) ||
        !identical(trash, _flushedTrash) ||
        seq != _flushedSeq;
    final selChanged = selected != _flushedSel;
    if (!itemsChanged && !selChanged) return _indexWrite;
    final text = itemsChanged ? _indexText(seq, selected, items, trash) : null;
    _flushedItems = items;
    _flushedTrash = trash;
    _flushedSeq = seq;
    _flushedSel = selected;
    return _indexWrite = _enqueue(() async {
      // 索引是最不能半截的一个文件:坏了会让整库看起来是空的(见 S1C-01)
      if (text != null) await writeStringAtomic(_indexFile, text);
      if (selChanged) await writeStringAtomic(_selFile, selected ?? '');
    });
  }

  // 批量删文件走后台 isolate,不占写入队列:新图落盘不必等它删完
  Future<void> _deleting = Future.value();

  void _deleteInBackground(List<String> paths, {bool trees = false}) {
    if (paths.isEmpty) return;
    final after = Future.wait([_chain, _deleting]);
    _deleting = after
        .then((_) => _deletePathsInIsolate(paths, trees))
        .catchError((Object e) {
          logd('[gallery-store] 删除失败: $e');
        });
  }

  /// 删除若干条结果的文件(上限裁剪 / 彻底删除用):原图/缩略图/快照一并删。
  /// 索引由调用方随后 scheduleIndex 重写。
  void deleteResultFiles(List<String> ids) {
    _deleteInBackground([
      for (final id in ids)
        for (final f in [
          _imageFile(id),
          _imageWebp(id),
          _thumbJpg(id),
          _thumbPng(id),
          _inputFile(id),
        ])
          f.path,
    ]);
  }

  /// 清空图库文件(存储管理「清空图库」):写空索引但**保留发号器**(id 永不
  /// 复用),三个目录整个挪走、换上空目录,旧目录在后台删。作废挂起的索引写,
  /// 串行队列保证在途的 persistResult 先完成。返回的 Future 等到旧文件删完。
  Future<void> clearAllFiles({required int seq}) {
    _idxItems = null;
    _idxTimer?.cancel();
    final moved = <String>[];
    _indexWrite = _enqueue(() async {
      await writeStringAtomic(
        _indexFile,
        jsonEncode({'v': 1, 'seq': seq, 'items': const <Object>[]}),
      );
      try {
        if (await _selFile.exists()) await _selFile.delete();
      } catch (_) {}
      _flushedItems = null;
      _flushedSel = null;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (final d in [_imagesDir, _thumbsDir, _inputsDir]) {
        final to =
            '${_root.path}/$_clearedPrefix${stamp}_${d.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}';
        try {
          await d.rename(to);
          moved.add(to);
        } catch (_) {
          try {
            await for (final ent in d.list()) {
              try {
                await ent.delete(recursive: true);
              } catch (_) {}
            }
          } catch (_) {}
        }
        await d.create(recursive: true);
      }
    });
    return _indexWrite.then((_) {
      _deleteInBackground(moved, trees: true);
      return _deleting;
    });
  }

  static const _clearedPrefix = '.cleared_';

  /// 删掉清空图库时没删完的旧目录(删到一半被杀的残留)。
  Future<void> sweepCleared() async {
    final doomed = <String>[];
    try {
      await for (final ent in _root.list()) {
        if (ent is Directory &&
            ent.uri.pathSegments
                .lastWhere((s) => s.isNotEmpty)
                .startsWith(_clearedPrefix)) {
          doomed.add(ent.path);
        }
      }
    } catch (_) {}
    _deleteInBackground(doomed, trees: true);
    await _deleting;
  }

  // ---- 懒读 ----

  Future<Uint8List?> readImage(String id) async {
    try {
      final f = await _existingImage(id);
      if (f == null) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 缩略图;缺失(旧数据/生成失败)退回原图。旧版小缩略图从原图重做。
  Future<Uint8List?> readThumb(String id) async {
    try {
      final jpg = _thumbJpg(id);
      if (await jpg.exists()) return await jpg.readAsBytes();
      final png = _thumbPng(id);
      if (await png.exists()) {
        final bytes = await png.readAsBytes();
        if (!await _isOutdated(id, bytes)) return bytes;
        return await _refitThumb(id) ?? bytes;
      }
    } catch (_) {}
    return readImage(id);
  }

  /// 旧版缩略图:短边 256(方形居中裁或等比),原图比它大就该重做。
  Future<bool> _isOutdated(String id, Uint8List png) async {
    if (png.length < 24) return false;
    final bd = ByteData.sublistView(png);
    final tw = bd.getUint32(16), th = bd.getUint32(20);
    if (math.min(tw, th) >= kThumbShortSide) return false;
    final (w, h) = await _imageSize(await _existingImage(id));
    if (w <= 0 || h <= 0) return false;
    return math.min(w, h) > math.min(tw, th) || (tw == th && w != h);
  }

  /// 不透明的存 .jpg,带透明的存 .png;另一种格式的旧文件一并删掉。
  Future<void> _writeThumb(String id, ({Uint8List bytes, bool jpeg}) t) async {
    final keep = t.jpeg ? _thumbJpg(id) : _thumbPng(id);
    final drop = t.jpeg ? _thumbPng(id) : _thumbJpg(id);
    await writeBytesAtomic(keep, t.bytes);
    try {
      if (await drop.exists()) await drop.delete();
    } catch (_) {}
  }

  /// 重做分三路排队:老图库一屏几十张同时解原图,内存会一下子顶上去。
  final _refitLanes = List<Future<void>>.filled(3, Future.value());
  Future<void> _refitWrites = Future.value();
  var _refitNext = 0;

  Future<Uint8List?> _refitThumb(String id) {
    final lane = _refitNext++ % _refitLanes.length;
    final work = _refitLanes[lane].then((_) async {
      final src = await readImage(id);
      if (src == null) return null;
      final thumb = await makeThumb(src);
      // 单独排队,不挡新图落盘;排队期间图被删了就不写,免得留下孤儿缩略图
      _refitWrites = _refitWrites.then((_) async {
        try {
          if (await _existingImage(id) != null) await _writeThumb(id, thumb);
        } catch (_) {}
      });
      return thumb.bytes;
    });
    _refitLanes[lane] = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }

  // ---- 检索索引(search.json;可重建,容错语义与 index.json 不同) ----

  File get _searchFile => File('${_root.path}/search.json');

  /// 检索索引的版本。取材口径一变就得抬 —— 旧版里的文本是按旧口径抽的,留着就是
  /// 带着错答案不走;读到版本不对直接当空表,回填会按新口径把整库重扫一遍。
  ///
  ///   1 → 2:禁用的角色卡不再进索引(旧版把它们也收了,搜得到图里没画的东西,
  ///          按角色分组也跟着归错)。
  ///   2 → 3:多存来源(灵感库条目 id、角色卡名、折叠组名);换行算分隔。
  static const _searchVersion = 3;

  /// 增量日志:每行一条新增(`p`)或一批删除(`d`),读时在 search.json 之上重放;
  /// 攒多了在后台并回 search.json。文件名带版本,换版本后旧日志自然作废。
  File get _searchLog => File('${_root.path}/search.v$_searchVersion.log');

  Future<void> _searchChain = Future.value();
  int _searchLogLines = 0;
  int _searchBaseCount = 0;

  Future<void> _enqueueSearch(Future<void> Function() job) {
    final work = _searchChain.then((_) => job());
    _searchChain = work.catchError((Object e) {
      logd('[gallery-store] 检索索引写入失败: $e');
    });
    return work;
  }

  /// 检索索引读入(后台 isolate);空/坏/**版本不对** → 空表(回填会重扫快照补齐)。
  Future<Map<String, GallerySearchMeta>> readSearchIndex() async {
    final base = _searchFile.path;
    final log = _searchLog.path;
    await _searchChain;
    try {
      final r = await _readSearchInIsolate(base, log);
      _searchBaseCount = r.baseCount;
      _searchLogLines = r.logLines;
      return r.items;
    } catch (_) {
      return const {};
    }
  }

  /// 追加若干条(新图 / 回填一批)。
  void appendSearch(Map<String, GallerySearchMeta> puts) {
    if (puts.isEmpty) return;
    final b = StringBuffer();
    for (final e in puts.entries) {
      b
        ..write(jsonEncode({'p': e.key, ..._searchItemJson(e.value)}))
        ..write('\n');
    }
    _appendSearchLines(b.toString(), puts.length);
  }

  /// 追加一批删除。
  void appendSearchRemovals(List<String> ids) {
    if (ids.isEmpty) return;
    _appendSearchLines('${jsonEncode({'d': ids})}\n', 1);
  }

  void _appendSearchLines(String text, int n) {
    _searchLogLines += n;
    final log = _searchLog;
    _enqueueSearch(() => log.writeAsString(text, mode: FileMode.append));
    if (_searchLogLines >= math.max(2000, _searchBaseCount)) {
      unawaited(compactSearch());
    }
  }

  /// 把日志并回 search.json(后台 isolate)。
  Future<void> compactSearch() {
    _searchLogLines = 0;
    final base = _searchFile.path;
    final log = _searchLog.path;
    return _enqueueSearch(() async {
      _searchBaseCount = await _compactSearchInIsolate(base, log);
    });
  }

  /// 清空检索索引。
  Future<void> clearSearch() {
    _searchLogLines = 0;
    _searchBaseCount = 0;
    final log = _searchLog;
    return _enqueueSearch(() async {
      await writeStringAtomic(
        _searchFile,
        jsonEncode({'v': _searchVersion, 'items': const <String, Object>{}}),
      );
      if (await log.exists()) await log.delete();
    });
  }

  /// 某张图参数快照的文件路径(检索索引回填在后台 isolate 里自己读)。
  String inputPathOf(String id) => _inputFile(id).path;

  /// 有参数快照的全部 id(检索索引回填清单)。
  Future<List<String>> listInputIds() async {
    final out = <String>[];
    try {
      await for (final ent in _inputsDir.list()) {
        if (ent is File && ent.path.endsWith('.json')) {
          final n = ent.uri.pathSegments.last;
          out.add(n.substring(0, n.length - 5));
        }
      }
    } catch (_) {}
    return out;
  }

  /// 参数快照(重新生成/重绘/导入用),blob 缺失字段按可用降级。
  /// [presetFallback]:快照里没记提示词预设的老图用哪一档(见 [decodeGenerateState])。
  Future<GenerateState?> readInput(String id, {String? presetFallback}) async {
    try {
      final f = _inputFile(id);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['state'] is! Map<String, dynamic>) return null;
      return await decodeGenerateState(
        j['state'] as Map<String, dynamic>,
        _blobs,
        presetFallback: presetFallback,
      );
    } catch (e) {
      logd('[gallery-store] 快照读取失败 $id: $e');
      return null;
    }
  }

  /// 全部参数快照引用的 blob 哈希(启动 GC 的引用清单)。
  /// 逐个解析快照在后台 isolate 里做,图多时不占主线程。
  Future<Set<String>> liveRefs() => _refsOfSnapshotsInIsolate(_inputsDir.path);
}

Map<String, Object> _searchItemJson(GallerySearchMeta m) => {
  'm': m.model,
  't': m.text,
  if (m.ids.isNotEmpty) 'i': m.ids,
  if (m.cards.isNotEmpty) 'c': m.cards,
  if (m.folds.isNotEmpty) 'f': m.folds,
};

GallerySearchMeta? _searchMetaOf(Object? v) {
  if (v is! Map || v['t'] is! String) return null;
  List<String> strs(Object? x) => x is List
      ? [
          for (final y in x)
            if (y is String) y,
        ]
      : const [];
  return (
    model: (v['m'] as String?) ?? '',
    text: v['t'] as String,
    ids: strs(v['i']),
    cards: strs(v['c']),
    folds: strs(v['f']),
  );
}

Future<_IndexData?> _parseIndexInIsolate(String path) =>
    Isolate.run(() => _parseIndexFile(path));

Future<({Map<String, GallerySearchMeta> items, int baseCount, int logLines})>
_readSearchInIsolate(String base, String log) =>
    Isolate.run(() => _readSearch(base, log));

Future<int> _compactSearchInIsolate(String base, String log) =>
    Isolate.run(() => _compactSearch(base, log));

Future<void> _deletePathsInIsolate(List<String> paths, bool trees) =>
    Isolate.run(() => _deletePaths(paths, trees: trees));

/// 后台 isolate:search.json(版本对得上才用)+ 日志重放。坏行跳过。
({Map<String, GallerySearchMeta> items, int baseCount, int logLines})
_readSearch(String basePath, String logPath) {
  final out = <String, GallerySearchMeta>{};
  try {
    final base = File(basePath);
    if (base.existsSync()) {
      final j = jsonDecode(base.readAsStringSync());
      if (j is Map &&
          j['v'] == GalleryStore._searchVersion &&
          j['items'] is Map) {
        for (final e in (j['items'] as Map).entries) {
          if (e.key is! String) continue;
          if (_searchMetaOf(e.value) case final m?) out[e.key as String] = m;
        }
      }
    }
  } catch (_) {}
  final baseCount = out.length;
  var lines = 0;
  try {
    final log = File(logPath);
    if (log.existsSync()) {
      for (final line in log.readAsLinesSync()) {
        if (line.isEmpty) continue;
        lines++;
        try {
          final j = jsonDecode(line);
          if (j is! Map) continue;
          if (j['p'] is String) {
            if (_searchMetaOf(j) case final m?) out[j['p'] as String] = m;
          } else if (j['d'] is List) {
            for (final id in j['d'] as List) {
              out.remove(id);
            }
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return (items: out, baseCount: baseCount, logLines: lines);
}

/// 后台 isolate:日志并回 search.json,删日志。返回并完的条数。
int _compactSearch(String basePath, String logPath) {
  final items = _readSearch(basePath, logPath).items;
  final tmp = File('$basePath.tmp');
  tmp.writeAsStringSync(
    jsonEncode({
      'v': GalleryStore._searchVersion,
      'items': {for (final e in items.entries) e.key: _searchItemJson(e.value)},
    }),
    flush: true,
  );
  tmp.renameSync(basePath);
  try {
    File(logPath).deleteSync();
  } catch (_) {}
  return items.length;
}

/// 解析好的主索引;[itemJson] 是每条编码好的片段,与 [items] 一一对应。
typedef _IndexData = ({
  int seq,
  String? selectedId,
  List<ResultImage> items,
  List<String> itemJson,
  List<TrashedImage> trash,
});

/// 后台 isolate:读 index.json。不是对象返回 null。
_IndexData? _parseIndexFile(String path) {
  final j = jsonDecode(File(path).readAsStringSync());
  if (j is! Map) return null;
  var seq = (j['seq'] as num?)?.toInt() ?? 0;
  // 索引防抖窗口内被杀时 seq 可能落后于条目 id,取最大防撞车
  void bump(String id) {
    final m = GalleryStore._seqRe.firstMatch(id);
    if (m == null) return;
    final n = int.parse(m.group(1)!) + 1;
    if (n > seq) seq = n;
  }

  final trash = <TrashedImage>[];
  if (j['trash'] is List) {
    for (final e in j['trash'] as List) {
      if (GalleryStore._parseItem(e) case final r?) {
        bump(r.id);
        trash.add(TrashedImage(r, ((e as Map)['dt'] as num?)?.toInt() ?? 0));
      }
    }
  }
  final items = <ResultImage>[];
  final itemJson = <String>[];
  if (j['items'] is List) {
    for (final e in j['items'] as List) {
      if (GalleryStore._parseItem(e) case final r?) {
        bump(r.id);
        items.add(r);
        itemJson.add(jsonEncode(GalleryStore._itemJson(r)));
      }
    }
  }
  return (
    seq: seq,
    selectedId: j['selectedId'] as String?,
    items: items,
    itemJson: itemJson,
    trash: trash,
  );
}

Future<Set<String>> _refsOfSnapshotsInIsolate(String dir) =>
    Isolate.run(() => _refsOfSnapshots(dir));

/// 后台 isolate:[dir] 下全部快照引用的 blob 哈希。快照按 `{v, refs, state}`
/// 的顺序写,只读到 `"state"` 之前就够;找不到再整份解析。
Set<String> _refsOfSnapshots(String dir) {
  final out = <String>{};
  void add(Object? j) {
    if (j is Map && j['refs'] is List) {
      for (final r in j['refs'] as List) {
        if (r is String) out.add(r);
      }
    }
  }

  try {
    for (final ent in Directory(dir).listSync()) {
      if (ent is! File || !ent.path.endsWith('.json')) continue;
      try {
        final raf = ent.openSync();
        final String head;
        try {
          head = utf8.decode(raf.readSync(8192), allowMalformed: true);
        } finally {
          raf.closeSync();
        }
        final cut = head.indexOf(',"state":');
        add(
          jsonDecode(
            cut > 0 ? '${head.substring(0, cut)}}' : ent.readAsStringSync(),
          ),
        );
      } catch (_) {}
    }
  } catch (_) {}
  return out;
}

/// 后台 isolate:逐个删文件;[trees] 时按目录整棵删。不存在的跳过。
void _deletePaths(List<String> paths, {bool trees = false}) {
  for (final p in paths) {
    try {
      if (trees) {
        Directory(p).deleteSync(recursive: true);
      } else {
        File(p).deleteSync();
      }
    } catch (_) {}
  }
}

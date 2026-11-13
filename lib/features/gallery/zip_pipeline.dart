import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/store/cache_sweep.dart' show kShareCacheDir;
import 'gallery_store.dart';
import 'models.dart';
import 'save_pipeline.dart';
import 'save_settings.dart';
import '../../l10n/l10n.dart';

/// 把这几张按保存设置处理好、**打成一个 zip** 落进缓存,返回那个包。
/// 网格弹层多选里的「打包 ZIP」走这一条。
///
/// 与逐张保存共用 [processForSave] —— 包里那份该和存进相册的那份逐字节一致
/// (把元数据设成「清除」的人,不会希望打包出去的又把提示词带上)。
///
/// **一律 store 不压缩**:PNG/JPG 本身就是压过的,再 deflate 一遍省不到几个
/// 百分点,却要啃掉几十 MB —— 换那点体积不值。
///
/// [password] 非空则整包加密(WinZip AES-256,每个条目各自加盐)。
///
/// 落在 cache/[kShareCacheDir]/:与分享缓存同一个目录,下次分享、以及启动清扫
/// 顺手带走(包交给系统保存对话框时已经被拷走了,留着只是垃圾)。
///
/// `failed` 是读不出来 / 处理失败而跳过的张数。[onEach] 每处理完一张调一次
/// (进度用),返回 false 即中止 —— 中止不留半成品,`file` 回 null。
Future<({File? file, int packed, int failed})> packImagesZip(
  List<ResultImage> items, {
  required GalleryStore store,
  required SaveSettings settings,
  required String fileName,
  String? password,
  bool Function(int done)? onEach,
}) async {
  final ext = settings.format == SaveFormat.jpg ? 'jpg' : 'png';
  var packed = 0, failed = 0;
  _EntryPool? pool;
  RandomAccessFile? raf;
  File? out;
  try {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/$kShareCacheDir',
    );
    await dir.create(recursive: true);
    // 上一次打的包先清掉:交出去的那份系统已经拷走,这里留着只占地方
    for (final e in dir.listSync()) {
      if (e is File && e.path.endsWith('.zip')) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
    out = File('${dir.path}/$fileName');
    pool = await _EntryPool.start(password, _poolSize(items.length));
    raf = await out.open(mode: FileMode.write);

    final used = <String>{};
    final cds = <Uint8List>[]; // 每条的中央目录记录,最后一次性写在包尾
    var offset = 0; // 已写进包里的字节数 = 下一条 local 记录的起点
    var aborted = false;
    var done = 0;

    void tick() {
      done++;
      if (onEach != null && !onEach(done)) aborted = true;
    }

    for (var i = 0; i < items.length && !aborted; i += pool.size) {
      // 一波 = 池子里有几个 worker 就备几张料。读盘和元数据处理留在主 isolate
      // (后者要 dart:ui 解码,搬不走),加密才是要摊开的那部分。
      final jobs = <(String, Uint8List, int)>[];
      for (final r in items.skip(i).take(pool.size)) {
        Uint8List? data;
        try {
          final bytes = r.bytes ?? await store.readImage(r.id);
          if (bytes != null) data = await processForSave(bytes, settings);
        } catch (_) {}
        if (data == null) {
          // 读不出来 / 处理失败:只赔上这一张
          failed++;
          tick();
        } else {
          jobs.add((
            zipEntryName(r.seed, ext, used),
            data,
            // 包里的时间用出图那一刻,不是打包这一刻 —— 解出来按时间排还是
            // 原来的顺序。0(老索引没回填上)退回当下,zip 的 DOS 时间戳表示
            // 不了 1980 年以前。
            (r.createdAt > 0
                    ? r.createdAt
                    : DateTime.now().millisecondsSinceEpoch) ~/
                1000,
          ));
        }
      }
      if (jobs.isEmpty) continue;

      // 并行编码。谁先回来谁先推进度条,免得进度按「一波」跳着走
      final encoded = await Future.wait([
        for (var j = 0; j < jobs.length; j++)
          pool.workers[j].encode(jobs[j]).whenComplete(tick),
      ]);

      // 落盘按原序:zip 里条目的先后就是这里写下去的先后
      for (final e in encoded) {
        await raf.writeFrom(e.local);
        // 单条包里这条的 local 记录在 0,搬进大包得改写成真实偏移
        e.cd.buffer.asByteData().setUint32(
          e.cd.offsetInBytes + _kCdLocalOffsetField,
          offset,
          Endian.little,
        );
        cds.add(e.cd);
        offset += e.local.length;
        packed++;
      }
    }

    if (aborted || packed == 0) {
      await raf.close();
      raf = null;
      await out.delete();
      return (file: null, packed: packed, failed: failed);
    }

    // 包尾:中央目录 + EOCD
    final cdStart = offset;
    var cdSize = 0;
    for (final cd in cds) {
      await raf.writeFrom(cd);
      cdSize += cd.length;
    }
    await raf.writeFrom(_endOfCentralDirectory(cds.length, cdSize, cdStart));
    await raf.close();
    raf = null;
    return (file: out, packed: packed, failed: failed);
  } catch (_) {
    // 半路炸了(盘满、权限)——收尾别再抛,半成品包也别留着骗人
    try {
      await raf?.close();
    } catch (_) {}
    try {
      if (await out?.exists() ?? false) await out!.delete();
    } catch (_) {}
    return (file: null, packed: 0, failed: items.length);
  } finally {
    pool?.dispose();
  }
}

/// 包内文件名:与保存/分享同款 `plana_<seed>.<ext>`,重名的补 `_2`、`_3`。
///
/// 同一个 seed 出现两次是常事(一批多张共用一个 seed、重绘产物跟着源图走),
/// zip 允许重名条目但解出来会互相覆盖 —— 名字必须在包内唯一。
/// [used] 记的是包里已占掉的名字,取一个就记一个。
String zipEntryName(int seed, String ext, Set<String> used) {
  final base = 'plana_$seed';
  var name = '$base.$ext';
  var n = 1;
  while (!used.add(name)) {
    name = '${base}_${++n}.$ext';
  }
  return name;
}

/// 包名清洗(不含扩展名,`.zip` 由调用方补)。
/// 空串 = 这名字不能用,调用方据此禁掉「打包」。
String sanitizeZipName(String raw) {
  final s = raw
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      // 自己把 .zip 打进去的人不少,别让他拿到 xxx.zip.zip
      .replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
  // 首尾的点:开头是类 Unix 的隐藏文件,结尾在 Windows 上根本存不下
  return s.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
}

// ---- 包的拼装 ----
//
// 每张图由 worker 单独编成一个**只装一条的完整 zip**,主 isolate 再把这些包
// 拆开拼成一个:前半截(local 记录)按原序接着写,后半截(中央目录记录)改掉
// 里头的偏移攒着,最后连同 EOCD 一起写在包尾。
//
// 这么绕是为了并行:加密是纯 Dart 的 AES,一张 1.5MB 要啃掉一两百毫秒,
// 串着打几十张就是几十秒的干等。而条目之间本来互不相干 —— 各自加盐、各自算
// MAC,唯一的串行点只有「谁排在谁前面」,那部分只是拷字节,不值一提。
//
// 自己写的字节只有 EOCD 那 22 个,以及每条中央目录记录里被改写的 4 个字节 ——
// 条目本身(含 AES 头、MAC)全是 archive 生成的,没有第二套实现。

/// 中央目录记录里「这条的 local 记录在哪」的字段位置(定长头内偏移)。
const _kCdLocalOffsetField = 42;

/// 池子大小。留一个核给界面,再多也不给 —— 几张图的批量根本摊不开,
/// 而每个 worker 手里都握着一张图的两份拷贝。
int _poolSize(int items) {
  final cores = (Platform.numberOfProcessors - 1).clamp(1, 4);
  return items < cores ? items.clamp(1, cores) : cores;
}

/// 包尾的 End Of Central Directory。单盘、无注释,固定 22 字节。
Uint8List _endOfCentralDirectory(int count, int cdSize, int cdStart) {
  // 65535 条 / 4GB 以上要 zip64,而这是相册批量导出 —— 真撞上了宁可报错,
  // 也不能吐一个解不开的包出去
  if (count > 0xffff || cdSize > 0xffffffff || cdStart > 0xffffffff) {
    throw StateError(l10nNow.zipTooLarge);
  }
  final b = Uint8List(22);
  final d = b.buffer.asByteData();
  d.setUint32(0, 0x06054b50, Endian.little); // 签名
  d.setUint16(4, 0, Endian.little); // 本盘号
  d.setUint16(6, 0, Endian.little); // 中央目录所在盘号
  d.setUint16(8, count, Endian.little); // 本盘条目数
  d.setUint16(10, count, Endian.little); // 总条目数
  d.setUint32(12, cdSize, Endian.little);
  d.setUint32(16, cdStart, Endian.little);
  d.setUint16(20, 0, Endian.little); // 注释长度
  return b;
}

/// 一条编好的条目:`local` 是连头带数据的 local 记录,`cd` 是它的中央目录记录。
typedef _Entry = ({Uint8List local, Uint8List cd});

/// 常驻 worker 池。isolate 起一次用到底 —— 每张图现起一个的话,光起 isolate
/// 的开销就能盖过不加密时的整个编码时间。
class _EntryPool {
  _EntryPool._(this.workers);

  final List<_EntryWorker> workers;
  int get size => workers.length;

  static Future<_EntryPool> start(String? password, int n) async {
    final ws = <_EntryWorker>[];
    try {
      for (var i = 0; i < n; i++) {
        ws.add(await _EntryWorker.start(password));
      }
    } catch (_) {
      for (final w in ws) {
        w.dispose();
      }
      rethrow;
    }
    return _EntryPool._(ws);
  }

  void dispose() {
    for (final w in workers) {
      w.dispose();
    }
  }
}

/// 单个 worker:发一张回一条。
///
/// 协议:主 → worker 发 `[名字, 字节, 秒级时间]`,worker 回 `[local, cd]`
/// 或 `['err', 说明]`。worker 意外退出时端口上会收到 onExit 的 null,
/// 于是等回复不会挂死。
class _EntryWorker {
  _EntryWorker._(this._tx, this._rx, this._reply);

  final SendPort _tx;
  final ReceivePort _rx;
  final StreamIterator<dynamic> _reply;
  bool _closed = false;

  static Future<_EntryWorker> start(String? password) async {
    final rx = ReceivePort();
    final reply = StreamIterator<dynamic>(rx);
    try {
      await Isolate.spawn(
        _entryWorkerMain,
        [rx.sendPort, password],
        onExit: rx.sendPort,
        onError: rx.sendPort,
      );
    } catch (_) {
      rx.close();
      rethrow;
    }
    // 第一条必是 worker 自己的收件端口;不是就说明它没起来
    if (!await reply.moveNext() || reply.current is! SendPort) {
      rx.close();
      throw StateError('打包 worker 起不来');
    }
    return _EntryWorker._(reply.current as SendPort, rx, reply);
  }

  /// 编一条。抛 = 这包废了,调用方该整包作废。
  Future<_Entry> encode((String, Uint8List, int) job) async {
    if (_closed) throw StateError('打包 worker 已关');
    final (name, data, mtime) = job;
    _tx.send([name, data, mtime]);
    if (!await _reply.moveNext()) {
      dispose();
      throw StateError(l10nNow.zipInterrupted);
    }
    final r = _reply.current;
    // 回的不是两段字节:要么 worker 报错(['err', 说明]),要么它自己挂了
    // (onExit 的 null / onError 的 [错误, 栈])
    if (r is! List || r.length != 2 || r[0] is! Uint8List) {
      dispose();
      throw StateError(
        r is List && r.length == 2 ? '${r[1]}' : l10nNow.zipInterrupted,
      );
    }
    return (local: r[0] as Uint8List, cd: r[1] as Uint8List);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    // 关自己这头的端口 worker 是不知道的:它 await 的是**它自己**的收件端口。
    // 得明说一声收工,否则每打一包就留下几个空转的 isolate。
    _tx.send(null);
    _rx.close();
  }
}

/// worker 侧:把一张图编成一个只装一条的 zip,再拆成 local / cd 两段回去。
Future<void> _entryWorkerMain(List<Object?> arg) async {
  final tx = arg[0] as SendPort;
  final password = arg[1] as String?;
  final rx = ReceivePort();
  tx.send(rx.sendPort);

  await for (final msg in rx) {
    if (msg == null) break; // 主侧 dispose 了
    try {
      final cmd = msg as List<Object?>;
      final out = OutputMemoryStream();
      ZipEncoder(password: password)
        ..startEncode(out)
        ..add(
          ArchiveFile.typedData(cmd[0] as String, cmd[1] as Uint8List)
            ..compression = CompressionType.none
            ..lastModTime = cmd[2] as int,
        )
        ..endEncode();
      final zip = out.getBytes();
      // 尾部 22 字节就是 EOCD(没写注释),从里头取中央目录的起点和长度,
      // 据此把这个小包切成 local 段和 cd 段
      final d = ByteData.sublistView(zip);
      final eocd = zip.length - 22;
      if (eocd < 0 || d.getUint32(eocd, Endian.little) != 0x06054b50) {
        throw StateError('zip 尾部不认识');
      }
      final cdSize = d.getUint32(eocd + 12, Endian.little);
      final cdStart = d.getUint32(eocd + 16, Endian.little);
      // sublist 而不是 view:要过端口,带着整个大 buffer 走没意义
      tx.send([
        zip.sublist(0, cdStart),
        zip.sublist(cdStart, cdStart + cdSize),
      ]);
    } catch (e) {
      tx.send(['err', '$e']);
    }
  }
  rx.close();
}

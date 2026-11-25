import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

import 'atomic_file.dart';

/// 顶层函数:isolate 里算 sha256(大图不卡 UI)。
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// 内容寻址二进制仓(`<support>/blobs/<sha256>.bin`):工作台与图库
/// 参数快照里的参考图统一存这里,同图天然去重(循环出图共享参考时
/// 只落一份)。删除交给启动期 [gc](扫引用清单,新鲜文件豁免),
/// 写入方不管生命周期。
class BlobStore {
  BlobStore(Directory supportRoot)
    : _dir = Directory('${supportRoot.path}/blobs');

  final Directory _dir;

  /// 正在写入的哈希 → 写入任务,合并同一哈希的并发写入,避免写同一 .tmp 冲突。
  final _inflight = <String, Future<void>>{};

  /// bytes 对象 → 已算过的哈希备忘(同一对象在防抖保存里反复出现,
  /// 不重复算 sha256)。
  static final Expando<String> _hashMemo = Expando<String>();

  Future<void> ensureReady() => _dir.create(recursive: true);

  File _fileOf(String hash) => File('${_dir.path}/$hash.bin');

  /// 算哈希;[known] 为调用方已有的内容哈希(vibe/CR 自带),直接采信。
  Future<String> hashOf(Uint8List bytes, {String? known}) async {
    if (known != null && known.isNotEmpty) return _hashMemo[bytes] = known;
    final memo = _hashMemo[bytes];
    if (memo != null) return memo;
    final h = bytes.length > 256 * 1024
        ? await compute(_sha256Hex, bytes)
        : _sha256Hex(bytes);
    return _hashMemo[bytes] = h;
  }

  /// 存入(已存在跳过写),返回哈希。
  ///
  /// 原子写不是可选项:这里是**内容寻址**存储,半截文件的内容与文件名里的
  /// 哈希对不上,却会被后续 [get] 当成有效缓存命中 —— 比文件缺失更糟。
  Future<String> put(Uint8List bytes, {String? known}) async {
    final h = await hashOf(bytes, known: known);
    final pending = _inflight[h];
    if (pending != null) {
      await pending;
      return h;
    }
    Future<void> write() async {
      final f = _fileOf(h);
      if (!await f.exists()) await writeBytesAtomic(f, bytes);
    }

    final work = write();
    _inflight[h] = work;
    try {
      await work;
    } finally {
      if (identical(_inflight[h], work)) unawaited(_inflight.remove(h));
    }
    return h;
  }

  Future<Uint8List?> get(String hash) async {
    try {
      final f = _fileOf(hash);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      _hashMemo[bytes] = hash;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 清孤儿:不在引用集 [live] 且落盘超过 [minAge] 的 blob 删除。
  /// 新鲜豁免挡住「GC 扫描期间刚写入、引用清单还没更新」的并发窗口;
  /// 启动自动 GC 用默认 1 天,存储管理手动清理传短窗口。
  Future<void> gc(
    Set<String> live, {
    Duration minAge = const Duration(days: 1),
  }) async {
    try {
      if (!await _dir.exists()) return;
      final cutoff = DateTime.now().subtract(minAge);
      await for (final ent in _dir.list()) {
        if (ent is! File || !ent.path.endsWith('.bin')) continue;
        final name = ent.uri.pathSegments.last;
        final hash = name.substring(0, name.length - 4);
        if (live.contains(hash)) continue;
        try {
          if ((await ent.stat()).modified.isAfter(cutoff)) continue;
          await ent.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

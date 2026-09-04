import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback, compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'suggestions.dart';

/// 顶层函数(compute 要求):在后台 isolate 解析整份 TSV。
/// 行格式 `tag<TAB>post_count<TAB>中文<TAB>alias1,alias2`。
List<_Entry> _parseTsv(String raw) {
  final list = <_Entry>[];
  for (final line in const LineSplitter().convert(raw)) {
    if (line.isEmpty) continue;
    final f = line.split('\t');
    if (f.length < 2) continue;
    final count = int.tryParse(f[1]) ?? 0;
    if (count < 50) continue; // 滤冷门,减内存(与 web <50 剔除一致)
    final zh = LocalTagDb.firstZh(
      (f.length > 2 && f[2].isNotEmpty) ? f[2] : null,
      tag: f[0],
    );
    final aliases = (f.length > 3 && f[3].isNotEmpty)
        ? [
            for (final s in f[3].split(','))
              if (s.isNotEmpty && !s.startsWith('/')) s, // 去掉 /lh 之类快捷别名
          ]
        : const <String>[];
    list.add(_Entry(f[0], count, zh, aliases));
  }
  return list;
}

/// 离线 Danbooru 标签库(`assets/danbooru.tsv`,**含中文翻译**,已按热度降序)。
/// 用户在设置里显式选了「离线词库」时的英文补全走这里——**完全离线**,不碰网络,
/// 天然绕开 Cloudflare。(2026-08-25 前它还是「未授权模式」的兜底,门禁解除后不再是。)
/// 行格式(tab 分隔):`tag<TAB>post_count<TAB>中文<TAB>alias1,alias2`;
/// tag 用下划线,app 内展示/插入转空格;中文来自社区词库(ChinaGPT 10w + byzod 精选合并)。
class LocalTagDb {
  List<_Entry>? _entries;
  Future<void>? _loading;
  Future<void>? _warming;

  Future<void> _ensureLoaded() {
    if (_entries != null) return Future.value();
    return _loading ??= _load();
  }

  /// 把全库中文/热度灌进 suggestions 反查缓存(注音层/词条栏 sync 查询用)。
  /// 不灌的话翻译只在补全命中时零星回填——手打/带入的既有 prompt 都显示不出。
  /// 分片让帧;进编辑器时触发,幂等。
  ///
  /// [onChunk]:灌到前几片时各调一次,让调用方**提前刷一次**,不必干等整轮。
  /// 整轮不便宜 —— 桌面实测读 asset + isolate 解析 195ms、灌注 427ms,手机上
  /// 一两秒;而词库按热度降序,拿真实提示词量过:前 8000 条(灌注进度 8%)就已经
  /// 覆盖其中约七成的词。所以头三片各刷一次、剩下的到货再补,首屏观感差很多。
  ///
  /// 刷太勤会让注音层反复重排,所以只在 [_warmNotifyAt] 那几个点刷,不是每片都刷。
  ///
  /// 多个调用者(编辑器 + 同屏若干 `PromptChips`)各自的 [onChunk] **都会收到** ——
  /// 灌注本身仍只跑一轮。记忆化写成 `_warming ??=` 的话只有头一个调用者的回调能生效,
  /// 后来的只能干等整轮,所以回调单独存一份。已经灌完时不再登记(直接 await 那个
  /// 完成的 future 即可)。
  Future<void> warmTagMeta({VoidCallback? onChunk}) {
    if (onChunk != null && !_warmDone) _warmListeners.add(onChunk);
    return _warming ??= _warmTagMeta();
  }

  final _warmListeners = <VoidCallback>[];
  bool _warmDone = false;

  /// 一片最多占主线程多久 —— **也就是这轮灌注最多能让哪一帧晚多久**。
  ///
  /// 分片一直都有,但早先是按**条数**切(8000 条一片)。条数和耗时不是一回事:
  /// 同样 8000 条,在这台机器上十几毫秒,一帧就整个没了 —— 于是"开机灌注"变成
  /// 十来帧连着丢,撞上切页面就是一口气卡那么一下。改按**时间**切,片长在哪台
  /// 机器上都是这个数,一帧最多被推迟 2ms,挤得进 16ms 的预算。
  ///
  /// 让帧用零延时 Timer 就够:同一时刻只挂着**一个**待跑的片,vsync 一到就排在
  /// 它后面,最多等这一片跑完。(必须是 `Future.delayed`,不能 `await null` ——
  /// 后者只让微任务,事件循环根本不喘气,vsync 进不来。)
  static const _warmSliceUs = 2000;

  /// 在这几个进度点回调 [warmTagMeta] 的 `onChunk`。都落在正名那一遍里
  /// (别名遍从 9 万多开始),因为热度降序的收益全在前面。
  static const _warmNotifyAt = {8000, 16000, 32000};

  void _notifyWarm() {
    for (final f in _warmListeners) {
      f();
    }
  }

  Future<void> _warmTagMeta() async {
    await _ensureLoaded();
    final entries = _entries;
    if (entries == null) return;
    var i = 0;
    // 这一片已经占了主线程多久;到点就让一帧,让完清零。
    //
    // 写成同步判定、由调用处 await,而不是包一个 `Future<void> yieldIfDue()`:
    // 那样每一条都要 await 一次,即便立刻返回也得建一个 Future、走一轮微任务
    // —— 十一万条,光这一下就够把省下来的钱花回去。
    final slice = Stopwatch()..start();
    var since = 0; // 距上次看表又过了多少条:看表也要钱,64 条问一次够细了
    bool sliceDue() {
      if (++since < 64) return false;
      since = 0;
      if (slice.elapsedMicroseconds < _warmSliceUs) return false;
      slice.reset();
      return true;
    }

    final taken = <String>{};
    for (final e in entries) {
      final name = e.tag.replaceAll('_', ' ');
      taken.add(metaKey(name));
      if (e.zh != null || e.count > 0) {
        cacheTagMeta(name, trans: e.zh, count: e.count);
      }
      // 进度回调按**条数**走(热度降序,前几片的收益最大),让帧按**时间**走,
      // 两者不再互相绑定 —— 早先合在一条 if 里,分片一改这几个点就再也对不上。
      if (_warmNotifyAt.contains(++i)) _notifyWarm();
      if (sliceDue()) await Future<void>.delayed(Duration.zero);
    }
    // 第二遍:别名(第 4 列)。Danbooru 的别名就是同一个标签的另一种写法 ——
    // 旧名、拼写变体、俗称(`hires`/`high res`→highres、`1girls`→1girl、
    // `longhair`→long hair、`oppai`/`tits`→breasts),译名和热度都该跟着正名走。
    // 这些写法在真实提示词里极常见,不认的话整词注音空白,还会被白送去后端问。
    // 全库能这么捡回 20,966 条,且头部全是百万热度的词。
    //
    // 正名优先:与正式标签同名的别名跳过(`taken` 里已有)。别名之间撞车时先到
    // 先得 —— 词库按热度降序,所以赢的是更热门那个标签,这正是想要的。
    for (final e in entries) {
      if (e.zh == null && e.count <= 0) continue;
      for (final a in e.aliases) {
        if (!taken.add(metaKey(a))) continue;
        cacheTagMeta(a, trans: e.zh, count: e.count);
      }
      if (sliceDue()) await Future<void>.delayed(Duration.zero);
    }
    _warmDone = true;
    _warmListeners.clear(); // 灌完就不再需要,别攥着已 dispose 的 State 的闭包
  }

  /// 社区词库常一格多译,注音只取第一段。实现在 [firstTransSegment] ——
  /// 网络回填那一路(`cacheTagMeta`)用的是同一个,两边分头维护过一次名单,
  /// 结果 `|` 只补了一处。非私有:后台解析的顶层函数 [_parseTsv] 要用。
  static String? firstZh(String? zh, {String? tag}) =>
      firstTransSegment(zh, tag: tag);

  Future<void> _load() async {
    // rootBundle 是平台通道,只能在主 isolate 读;解析(9 万行、几十万次字符串
    // 分配)扔进后台 isolate。原先整段在主 isolate 同步跑完、一帧都不让,
    // 而触发时机正是用户在编辑器里打字 —— 最在意流畅的场景。见 S3-02。
    final raw = await rootBundle.loadString('assets/danbooru.tsv');
    _entries = await compute(_parseTsv, raw);
  }

  /// 前缀匹配:标签名命中优先、别名命中次之(各自因源已按热度降序)。取前 [limit] 条。
  Future<List<Suggestion>> search(String query, {int limit = 15}) async {
    await _ensureLoaded();
    final entries = _entries;
    if (entries == null) return const [];
    final q = query.trim().toLowerCase().replaceAll(' ', '_');
    if (q.length < 2) return const [];

    final primary = <_Entry>[]; // 标签名前缀命中
    final secondary = <_Entry>[]; // 仅别名前缀命中
    final seen = <String>{};
    for (final e in entries) {
      if (e.tag.startsWith(q)) {
        if (seen.add(e.tag)) primary.add(e);
        if (primary.length >= limit) break; // 已按热度,够了就停
      } else if (secondary.length < limit &&
          e.aliases.any((a) => a.startsWith(q))) {
        if (seen.add(e.tag)) secondary.add(e);
      }
    }
    final out = <Suggestion>[];
    for (final e in [...primary, ...secondary].take(limit)) {
      final text = e.tag.replaceAll('_', ' ');
      cacheTagMeta(text, trans: e.zh, count: e.count); // 回填注音/热度
      out.add(
        Suggestion(
          text: text,
          kind: SuggestionKind.tag,
          trans: e.zh,
          count: e.count,
        ),
      );
    }
    return out;
  }
}

class _Entry {
  _Entry(this.tag, this.count, this.zh, this.aliases);
  final String tag;
  final int count;
  final String? zh; // 中文翻译(可空)
  final List<String> aliases;
}

/// 全局单例(懒加载一次,常驻内存)。
final localTagDbProvider = Provider<LocalTagDb>((ref) => LocalTagDb());

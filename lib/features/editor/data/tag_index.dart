import 'dart:convert';
import 'dart:typed_data';

import '../../../core/util/prompt_tokens.dart';
import 'suggestions.dart';

/// 离线词库索引:构建期由 [kTagTsv] 编出来的一张二进制表([kTagIndexAsset]),
/// 运行时拿到字节就能查 —— 不解析、不灌注,也不在 Dart 堆里建对象。
///
/// 早先是开机读 TSV → 后台 isolate 解析 9 万行 → 主线程把 11 万条灌进反查缓存。
/// 灌注那一遍在手机上占主线程一两秒;解析虽在后台 isolate,可它与主 isolate
/// 共用一个堆,狂分配触发的 GC 会把主线程一起停住 —— 开机那一小段掉帧就是这么来的。
///
/// 纯 Dart(不 import Flutter),`tool/build_tag_index.dart` 直接 `dart run`。
/// 改了 TSV 或建库口径要重跑它,`test/tag_index_test.dart` 会校验进包的文件是否同步。
///
/// 格式(小端,偏移都从文件头算起):
/// ```
/// 头部   magic 'PTIX' | 版本 | 条目段 | 条目数 | 键段 | 哈希表 | 槽数 | 文件总长
/// 条目段 按热度降序:u16+标签 | u16+首段译名 | u32 热度 | u8 类目 | u16+别名(逗号连,
///        含 `/lh` 这类快捷别名)
/// 键段   u16+键 | u32 注音条目 | u16 译名字节数 | u32 帖子数条目 | u32 角色条目
/// 哈希表 u32 × 槽数(2 的幂),存键记录偏移,0 为空;FNV-1a + 线性探测
/// ```
/// 三种口径共用一张表:同一个串可能既是注音键又是清洗键,记录里哪个口径的条目
/// 偏移为 0,就是这个口径下没有它。
const kTagIndexAsset = 'assets/danbooru.tagidx';

/// 索引的源数据(不进包)。行格式(tab 分隔):
/// `tag<TAB>post_count<TAB>中文<TAB>alias1,alias2<TAB>category`,已按热度降序。
const kTagTsv = 'assets/danbooru.tsv';

const _magic = 0x58495450; // 'PTIX'
const _version = 2;
const _headerSize = 32;

/// 清洗结果与「下划线换空格」对不上的标签:带括号、方括号、花括号或冒号的。
final _reOddTag = RegExp(r'[()\[\]{}:]');

/// 补全拆词的分隔符,同后端 `autocomplete.py` 的 `_SPLIT`。
final _reSplit = RegExp(r"[_\s\-():\[\]/.,'!?&;~*+=]+");

/// [_reSplit] 的逐字节版(分隔符全是 ASCII,UTF-8 多字节字符里不会撞上)。
final _splitBytes = () {
  final t = Uint8List(128);
  for (final c in "_-():[]/.,'!?&;~*+=".codeUnits) {
    t[c] = 1;
  }
  for (final c in [
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x1C,
    0x1D,
    0x1E,
    0x1F,
    0x20,
  ]) {
    t[c] = 1;
  }
  return t;
}();

bool _isSplit(int b) => b < 128 && _splitBytes[b] == 1;

/// pg_trgm 的三元组:按字母数字切词,每个词前补两个空格、后补一个,
/// 取每三个连续字符。三个字节压成一个 int,排序去重。
List<int> _trigrams(Uint8List b, int at, int len) {
  bool alnum(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39);
  final out = <int>[];
  var i = at;
  final end = at + len;
  while (i < end) {
    if (!alnum(b[i])) {
      i++;
      continue;
    }
    var a = 0x20, c = 0x20;
    for (; i < end && alnum(b[i]); i++) {
      out.add((a << 16) | (c << 8) | b[i]);
      a = c;
      c = b[i];
    }
    out.add((a << 16) | (c << 8) | 0x20);
  }
  out.sort();
  var n = 0;
  for (var k = 0; k < out.length; k++) {
    if (k == 0 || out[k] != out[k - 1]) out[n++] = out[k];
  }
  return out..length = n;
}

/// pg_trgm 的 similarity:共有三元组数 / 合起来的三元组数。两边都已排序去重。
double _similarity(List<int> x, List<int> y) {
  var i = 0, j = 0, common = 0;
  while (i < x.length && j < y.length) {
    if (x[i] == y[j]) {
      common++;
      i++;
      j++;
    } else if (x[i] < y[j]) {
      i++;
    } else {
      j++;
    }
  }
  final union = x.length + y.length - common;
  return union == 0 ? 0 : common / union;
}

/// 一枚命中的角色标签。[tag] 是词库正名(下划线形式),[zh] 可空。
typedef CharacterTag = ({String tag, String? zh, int count});

/// 一条补全结果。[tag] 是词库正名(下划线形式),[category] 是 Danbooru 类目。
typedef TagHit = ({String tag, String? zh, int count, int category});

/// 词库一行。热度 <50 的冷门行建库时就滤掉了。
/// [shortcuts] 是 `/lh` 这类快捷别名,只参与补全,不进反查表。
typedef TagRow = ({
  String tag,
  int count,
  String? zh,
  List<String> aliases,
  List<String> shortcuts,
  int category,
  bool isChar,
});

/// 建库口径:TSV → 三张「键 → 条目」表。[encode] 只是把它原样落盘,
/// 测试也拿它当读取端的对照。
///
/// 三张表同一条规矩:**正名优先,撞车先到先得** —— 词库按热度降序,
/// 赢的是更热门的那行。
class TagIndexSpec {
  TagIndexSpec.fromTsv(String raw) : rows = _parse(raw) {
    // 注音 / 热度。键跟反查那头同走 [metaKey]:下划线归空格、大小写与连续空白归一。
    for (var i = 0; i < rows.length; i++) {
      metaRow.putIfAbsent(metaKey(rows[i].tag.replaceAll('_', ' ')), () => i);
    }
    // 别名是同一个标签的另一种写法 —— 旧名、拼写变体、俗称(`hires`/`high res`
    // →highres、`1girls`→1girl、`oppai`/`tits`→breasts),译名和热度跟着正名走。
    // 这些写法在真实提示词里极常见,全库能这么捡回两万多条。
    for (var i = 0; i < rows.length; i++) {
      for (final a in rows[i].aliases) {
        metaRow.putIfAbsent(metaKey(a), () => i);
      }
    }

    // 帖子数与角色:查询那头的词是 [cleanPromptToken] 清洗过的(`ganyu_(genshin_impact)`
    // 与 `ganyu (genshin impact)` 都归到 `ganyu genshin impact`),键也照此清洗。
    // 多数行的清洗结果就是下划线换空格,只有带括号 / 冒号的才真要跑一遍正则。
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final k = _reOddTag.hasMatch(r.tag)
          ? cleanPromptToken(r.tag)
          : r.tag.replaceAll('_', ' ');
      if (k.isNotEmpty) postRow.putIfAbsent(k, () => i);
      if (r.isChar) charRow.putIfAbsent(cleanPromptToken(r.tag), () => i);
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      for (final a in r.aliases) {
        final k = a.contains('(') || a.contains(':')
            ? cleanPromptToken(a)
            : a.replaceAll('_', ' ');
        if (k.isNotEmpty) postRow.putIfAbsent(k, () => i);
        // 别名遍:`reimu_hakurei` 也该认出博丽灵梦
        if (r.isChar) charRow.putIfAbsent(cleanPromptToken(a), () => i);
      }
    }
  }

  final List<TagRow> rows;

  /// [metaKey] 口径 → 条目下标。注音层 / 词条栏的同步反查。
  final metaRow = <String, int>{};

  /// [cleanPromptToken] 口径 → 条目下标。图库归类掂量词的分量用的帖子数。
  final postRow = <String, int>{};

  /// [cleanPromptToken] 口径 → 角色条目下标。图库按角色归类。
  final charRow = <String, int>{};

  /// 注音键 [key] 该显示的译名。
  ///
  /// 同一个条目的译名按键再切一次:斜杠算不算分隔符要看**键**带不带斜杠
  /// (见 [firstTransSegment]),别名与正名不一定一样。结果总是条目首段译名的前缀,
  /// 所以索引里只记字节数。
  String? transOf(String key) {
    final i = metaRow[key];
    if (i == null) return null;
    final t = firstTransSegment(rows[i].zh, tag: key);
    return t == key ? null : t; // 同 [cacheTagMeta]:原样透传 = 没翻译
  }

  static List<TagRow> _parse(String raw) {
    final rows = <TagRow>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.isEmpty) continue;
      final f = line.split('\t');
      if (f.length < 2) continue;
      final count = int.tryParse(f[1]) ?? 0;
      if (count < 50) continue; // 滤冷门(与 web <50 剔除一致)
      // 名字与别名去空白、转小写,同后端补全(tag_search/autocomplete.py)
      final all = f.length > 3
          ? [
              for (final s in f[3].split(','))
                if (s.trim().isNotEmpty) s.trim().toLowerCase(),
            ]
          : const <String>[];
      // 第 5 列 category 是 Danbooru 类目(0 一般 / 1 画师 / 3 作品 / 4 角色 /
      // 5 meta);少数保留的旧行留空 = 未定类,按 0 算
      final category = f.length > 4 ? int.tryParse(f[4]) ?? 0 : 0;
      rows.add((
        tag: f[0].trim().toLowerCase(),
        count: count,
        zh: firstTransSegment(
          (f.length > 2 && f[2].isNotEmpty) ? f[2] : null,
          tag: f[0],
        ),
        aliases: [
          for (final s in all)
            if (!s.startsWith('/')) s,
        ],
        shortcuts: [
          for (final s in all)
            if (s.startsWith('/')) s,
        ],
        category: category,
        isChar: category == 4,
      ));
    }
    return rows;
  }

  Uint8List encode() {
    final w = _Writer()..zeros(_headerSize);
    final entriesOff = w.length;
    final rowAt = List<int>.filled(rows.length, 0);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      rowAt[i] = w.length;
      w
        ..str16(r.tag)
        ..str16(r.zh ?? '')
        ..u32(r.count)
        ..u8(r.category)
        ..str16([...r.aliases, ...r.shortcuts].join(','));
    }

    final keysOff = w.length;
    final keys = {...metaRow.keys, ...postRow.keys, ...charRow.keys};
    final recAt = <int>[];
    final hashes = <int>[];
    for (final k in keys) {
      final kb = utf8.encode(k);
      recAt.add(w.length);
      hashes.add(_fnv1a(kb));
      final meta = metaRow[k];
      final trans = transOf(k);
      if (trans != null && !rows[meta!].zh!.startsWith(trans)) {
        throw StateError('译名不是首段译名的前缀:$k');
      }
      final post = postRow[k];
      final char = charRow[k];
      w
        ..u16(kb.length)
        ..bytes(kb)
        ..u32(meta == null ? 0 : rowAt[meta])
        ..u16(trans == null ? 0 : utf8.encode(trans).length)
        ..u32(post == null ? 0 : rowAt[post])
        ..u32(char == null ? 0 : rowAt[char]);
    }

    // 负载不超过 3/4,线性探测平均一两次就中
    var slots = 1;
    while (slots * 3 < keys.length * 4) {
      slots <<= 1;
    }
    final table = Uint32List(slots);
    for (var i = 0; i < recAt.length; i++) {
      var s = hashes[i] & (slots - 1);
      while (table[s] != 0) {
        s = (s + 1) & (slots - 1);
      }
      table[s] = recAt[i];
    }
    final tableOff = w.length;
    for (final v in table) {
      w.u32(v);
    }

    w
      ..setU32(0, _magic)
      ..setU32(4, _version)
      ..setU32(8, entriesOff)
      ..setU32(12, rows.length)
      ..setU32(16, keysOff)
      ..setU32(20, tableOff)
      ..setU32(24, slots)
      ..setU32(28, w.length);
    return w.take();
  }
}

/// 词库一行的只读视图,见 [TagIndex.rows]。
class TagRowView {
  TagRowView._(this._ix, this._row);

  final TagIndex _ix;
  final int _row;

  int get count => _ix._rowCount(_row);

  /// Danbooru 类目:0 一般 / 1 画师 / 3 作品 / 4 角色 / 5 meta。
  int get category => _ix._rowCategory(_row);

  /// 标签正名(下划线形式)。
  String get tag => _ix._str(_row + 2, _ix._u16(_row));

  /// 首段译名;没有是空串。
  String get zh {
    final zhAt = _row + 2 + _ix._u16(_row);
    final len = _ix._u16(zhAt);
    return len == 0 ? '' : _ix._str(zhAt + 2, len);
  }
}

/// 读取端。查询全是同步的,只读字节;注音层 / 词条栏经 [offlineTagMeta] 用它。
class TagIndex implements OfflineTagMeta {
  TagIndex(ByteData data)
    : _d = data,
      _b = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes) {
    if (data.lengthInBytes < _headerSize ||
        _u32(0) != _magic ||
        _u32(4) != _version ||
        _u32(28) != data.lengthInBytes) {
      throw const FormatException('离线词库索引格式对不上,重跑 tool/build_tag_index.dart');
    }
    _entriesOff = _u32(8);
    _entryCount = _u32(12);
    _tableOff = _u32(20);
    _mask = _u32(24) - 1;
  }

  final ByteData _d;
  final Uint8List _b;
  late final int _entriesOff;
  late final int _entryCount;
  late final int _tableOff;
  late final int _mask;

  @override
  String? transOf(String key) {
    final p = _find(key);
    if (p < 0) return null;
    final row = _u32(p);
    final len = _u16(p + 4);
    if (row == 0 || len == 0) return null;
    return _str(row + 2 + _u16(row) + 2, len);
  }

  @override
  int? countOf(String key) {
    final p = _find(key);
    if (p < 0) return null;
    final row = _u32(p);
    return row == 0 ? null : _rowCount(row);
  }

  /// 清洗过的词([cleanPromptToken] 口径)→ 词库帖子数;没收的回 0。
  int postCountOf(String token) {
    final p = _find(token);
    if (p < 0) return 0;
    final row = _u32(p + 6);
    return row == 0 ? 0 : _rowCount(row);
  }

  /// 分词集合 → 命中的角色标签,按热度降序。
  List<CharacterTag> charactersIn(Iterable<String> tokens) {
    final hit = <int>{};
    for (final t in tokens) {
      final p = _find(t);
      if (p < 0) continue;
      final row = _u32(p + 10);
      if (row != 0) hit.add(row);
    }
    if (hit.isEmpty) return const [];
    final out = [for (final row in hit) _character(row)];
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// 分词集合里词库标成画师(类目 1)的那些词。
  Set<String> artistsIn(Iterable<String> tokens) => {
    for (final t in tokens)
      if (_postRowOf(t) case final row? when _rowCategory(row) == 1) t,
  };

  int? _postRowOf(String token) {
    final p = _find(token);
    if (p < 0) return null;
    final row = _u32(p + 6);
    return row == 0 ? null : row;
  }

  /// 按热度降序逐条给出词库的行。字段用到才解码,扫全库时只解码要比的那一列。
  Iterable<TagRowView> get rows sync* {
    var p = _entriesOff;
    for (var i = 0; i < _entryCount; i++) {
      final row = p;
      final zhAt = row + 2 + _u16(row);
      final aliasAt = zhAt + 2 + _u16(zhAt) + 5;
      p = aliasAt + 2 + _u16(aliasAt);
      yield TagRowView._(this, row);
    }
  }

  /// 英文补全,匹配口径同后端 `tag_search/autocomplete.py`(仿 Danbooru tag_query)。
  /// 标签名和别名都参与,按命中强度分档,档高的排前、同档按热度:
  ///   4 与标签名或别名完全相同           `seifuku` → school uniform
  ///   3 输入整串出现在标签名开头或词边界   `kimono` → white kimono
  ///   2 同上,命中在别名上
  ///   1 多词输入各词散落命中标签名,不论顺序 `white ser` → white album (series)
  ///   0 同上,命中在别名上
  /// 单词输入不收 1、0 两档(`:d` 拆出的 `d` 会捞来 dress 一类)。
  /// `test/tag_index_test.dart` 拿后端导出的结果逐条对拍。
  List<TagHit> search(String query, {int limit = 15}) {
    final q = query
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp('_+'), '_');
    if (q.length < 2) return const [];
    final qb = utf8.encode(q);
    final words = [
      for (final w in q.split(_reSplit))
        if (w.isNotEmpty) utf8.encode(w),
    ];
    final scattered = words.length >= 2;
    // 条目按热度降序,同档先扫到的热度就高:每档攒够 limit 条即可
    final tiers = List.generate(5, (_) => <int>[]);
    var p = _entriesOff;
    for (var i = 0; i < _entryCount; i++) {
      final row = p;
      final tagLen = _u16(row);
      final zhAt = row + 2 + tagLen;
      final aliasAt = zhAt + 2 + _u16(zhAt) + 5;
      final aliasLen = _u16(aliasAt);
      p = aliasAt + 2 + aliasLen;
      var best = _tier(row + 2, tagLen, qb, words, alias: false);
      final end = aliasAt + 2 + aliasLen;
      for (var s = aliasAt + 2; s < end && best < 4;) {
        var e = s;
        while (e < end && _b[e] != 0x2C) {
          e++;
        }
        final t = _tier(s, e - s, qb, words, alias: true);
        if (t > best) best = t;
        s = e + 1;
      }
      if (best < 0 || (best <= 1 && !scattered)) continue;
      if (tiers[best].length < limit) tiers[best].add(row);
      if (tiers[4].length >= limit) break;
    }
    return [
      for (final row in tiers.reversed.expand((t) => t).take(limit)) _hit(row),
    ];
  }

  /// [at] 起 [len] 字节这个名字(标签名或别名)的命中档,没命中回 -1。档位见 [search]。
  int _tier(
    int at,
    int len,
    Uint8List q,
    List<Uint8List> words, {
    required bool alias,
  }) {
    final prefix = _startsWith(at, len, q);
    if (!prefix) {
      if (words.isEmpty) return -1;
      for (final w in words) {
        if (!_hasWordStartingWith(at, len, w)) return -1;
      }
    }
    if (prefix && len == q.length) return 4;
    for (var i = 0; i + q.length <= len; i++) {
      if ((i == 0 || _isSplit(_b[at + i - 1])) &&
          _startsWith(at + i, len - i, q)) {
        return alias ? 2 : 3;
      }
    }
    return alias ? 0 : 1;
  }

  /// 名字里有没有哪个词以 [w] 开头。词 = 开头或分隔符之后的那一段。
  bool _hasWordStartingWith(int at, int len, Uint8List w) {
    for (var i = 0; i + w.length <= len; i++) {
      if ((i == 0 || _isSplit(_b[at + i - 1])) &&
          _startsWith(at + i, len - i, w)) {
        return true;
      }
    }
    return false;
  }

  /// 拼写纠错,口径同 Danbooru 补全的 autocorrect(`Tag.autocorrect_matches`):
  /// 只比标签名,编辑距离 < max(输入长度 ÷ 4, 3) 且三元组相似度 ≥ 0.3
  /// (pg_trgm 的 `%`),按编辑距离、热度降序、名字排。
  /// 输入要是 ASCII、不以 `/` 开头、至少 3 个字母数字。
  List<TagHit> correct(String query, {int limit = 15}) {
    final q = query.trim().toLowerCase().replaceAll(' ', '_');
    if (q.startsWith('/') || q.codeUnits.any((c) => c > 0x7F)) return const [];
    if (q.replaceAll(RegExp('[^a-z0-9]'), '').length < 3) return const [];
    final qb = Uint8List.fromList(q.codeUnits);
    final maxDist = q.length ~/ 4 > 3 ? q.length ~/ 4 : 3;
    final qTri = _trigrams(qb, 0, qb.length);
    final prev = Int32List(qb.length + 1), cur = Int32List(qb.length + 1);
    final found = <(int, int)>[]; // (编辑距离, 条目)
    var p = _entriesOff;
    for (var i = 0; i < _entryCount; i++) {
      final row = p;
      final tagLen = _u16(row);
      final zhAt = row + 2 + tagLen;
      final aliasAt = zhAt + 2 + _u16(zhAt) + 5;
      p = aliasAt + 2 + _u16(aliasAt);
      // 编辑距离不小于长度差:先按长度筛掉绝大多数
      if ((tagLen - qb.length).abs() >= maxDist) continue;
      final d = _levenshtein(row + 2, tagLen, qb, maxDist, prev, cur);
      if (d >= maxDist) continue;
      if (_similarity(qTri, _trigrams(_b, row + 2, tagLen)) < 0.3) continue;
      found.add((d, row));
    }
    final hits = [for (final (d, row) in found) (d, _hit(row))];
    hits.sort((a, b) {
      if (a.$1 != b.$1) return a.$1 - b.$1;
      if (a.$2.count != b.$2.count) return b.$2.count - a.$2.count;
      return a.$2.tag.compareTo(b.$2.tag);
    });
    return [for (final h in hits.take(limit)) h.$2];
  }

  /// [at] 起 [len] 字节与 [q] 的编辑距离;到 [cap] 就不再算,回 [cap]。
  int _levenshtein(
    int at,
    int len,
    Uint8List q,
    int cap,
    Int32List prev,
    Int32List cur,
  ) {
    for (var j = 0; j <= q.length; j++) {
      prev[j] = j;
    }
    for (var i = 1; i <= len; i++) {
      cur[0] = i;
      var rowMin = i;
      final c = _b[at + i - 1];
      for (var j = 1; j <= q.length; j++) {
        var v = prev[j - 1] + (c == q[j - 1] ? 0 : 1);
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin >= cap) return cap;
      for (var j = 0; j <= q.length; j++) {
        prev[j] = cur[j];
      }
    }
    return prev[q.length] < cap ? prev[q.length] : cap;
  }

  TagHit _hit(int row) {
    final c = _character(row);
    final zhAt = row + 2 + _u16(row);
    return (
      tag: c.tag,
      zh: c.zh,
      count: c.count,
      category: _b[zhAt + 2 + _u16(zhAt) + 4],
    );
  }

  /// 键记录里键之后那几个字段的起点;没有这个键回 -1。
  int _find(String key) {
    final kb = utf8.encode(key);
    var s = _fnv1a(kb) & _mask;
    while (true) {
      final rec = _u32(_tableOff + s * 4);
      if (rec == 0) return -1;
      if (_u16(rec) == kb.length && _startsWith(rec + 2, kb.length, kb)) {
        return rec + 2 + kb.length;
      }
      s = (s + 1) & _mask;
    }
  }

  int _rowCount(int row) {
    final zhAt = row + 2 + _u16(row);
    return _u32(zhAt + 2 + _u16(zhAt));
  }

  int _rowCategory(int row) {
    final zhAt = row + 2 + _u16(row);
    return _b[zhAt + 2 + _u16(zhAt) + 4];
  }

  CharacterTag _character(int row) {
    final tagLen = _u16(row);
    final zhAt = row + 2 + tagLen;
    final zhLen = _u16(zhAt);
    return (
      tag: _str(row + 2, tagLen),
      zh: zhLen == 0 ? null : _str(zhAt + 2, zhLen),
      count: _u32(zhAt + 2 + zhLen),
    );
  }

  bool _startsWith(int at, int len, Uint8List q) {
    if (len < q.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (_b[at + i] != q[i]) return false;
    }
    return true;
  }

  String _str(int at, int len) =>
      utf8.decode(Uint8List.sublistView(_b, at, at + len));
  int _u16(int at) => _d.getUint16(at, Endian.little);
  int _u32(int at) => _d.getUint32(at, Endian.little);
}

int _fnv1a(Uint8List b) {
  var h = 0x811c9dc5;
  for (final x in b) {
    h = ((h ^ x) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

class _Writer {
  var _buf = Uint8List(1 << 22);
  var length = 0;

  void _grow(int n) {
    if (length + n <= _buf.length) return;
    var cap = _buf.length * 2;
    while (cap < length + n) {
      cap *= 2;
    }
    _buf = Uint8List(cap)..setRange(0, length, _buf);
  }

  void zeros(int n) {
    _grow(n);
    length += n;
  }

  void bytes(List<int> b) {
    _grow(b.length);
    _buf.setRange(length, length + b.length, b);
    length += b.length;
  }

  void u8(int v) {
    if (v > 0xFF) throw StateError('字段超长:$v');
    _grow(1);
    _buf[length++] = v;
  }

  void u16(int v) {
    if (v > 0xFFFF) throw StateError('字段超长:$v 字节');
    _grow(2);
    ByteData.sublistView(_buf).setUint16(length, v, Endian.little);
    length += 2;
  }

  void u32(int v) {
    _grow(4);
    ByteData.sublistView(_buf).setUint32(length, v, Endian.little);
    length += 4;
  }

  void str16(String s) {
    final b = utf8.encode(s);
    u16(b.length);
    bytes(b);
  }

  void setU32(int at, int v) =>
      ByteData.sublistView(_buf).setUint32(at, v, Endian.little);

  Uint8List take() => _buf.sublist(0, length);
}

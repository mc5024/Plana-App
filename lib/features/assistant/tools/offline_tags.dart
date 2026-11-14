/// 离线词库(进包的 Danbooru 标签表:每行有中文名、热度、类目)上的查询,
/// 给查角色、查 tag 的离线来源和 [角色候选] 预取用。
///
/// 扫全库在主线程上做,每扫几千行让出一次,界面不卡。[角色候选] 要的角色行和缩写否决用的
/// 一般 tag 中文名,第一次用到时扫一遍缓存住。
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor/data/local_tag_db.dart';
import '../../editor/data/tag_index.dart';
import 'my_library.dart';
import 'tool_context.dart';

/// 每扫这么多行让出一次。
const _chunk = 4000;

/// [角色候选] 的热度门槛:绝对下限,以及低于榜首 1/N 的算陪跑。
const kRoleAbsFloor = 500;
const kRoleHeatRatio = 20;

/// 中文名最短几个字才参与匹配,缩写前缀最短几个字。单字必然误命中(「画一张芙兰」里的「兰」)。
const _minAlias = 2;
const _minPrefix = 2;

/// 画图请求里高频出现的通用中文名词。角色的中文名(或它的缩写)恰好是这些词时一律当误命中。
const _stopwords = {
  // 人物泛称
  '少女', '少年', '女孩', '女孩子', '男孩', '男孩子', '孩子', '小孩', '女生', '男生',
  // 亚人泛称:要的是 cat girl 这类通用 tag,不是某部作品里的具体角色
  '猫娘', '狐娘', '兔娘', '狼娘', '龙娘', '兽娘', '魅魔', '精灵', '兽耳娘', '女仆娘',
  '女人', '男人', '女性', '男性', '小姐', '先生', '姐姐', '妹妹', '哥哥', '弟弟',
  '老师', '学生', '护士', '女仆', '天使', '恶魔', '公主', '王子', '女王', '国王',
  '美少女', '萝莉', '御姐', '大叔', '婆婆', '妈妈', '爸爸', '朋友', '情侣', '双子',
  // 场景 / 地点
  '海边', '海滩', '沙滩', '雪山', '森林', '草原', '教室', '学校', '咖啡厅', '咖啡店',
  '餐厅', '房间', '卧室', '浴室', '厨房', '街道', '城市', '乡村', '山脉', '湖泊',
  '花园', '公园', '天台', '屋顶', '车站', '商店', '图书馆', '神社', '寺庙', '医院',
  // 时间 / 天气 / 氛围
  '天气', '早晨', '中午', '傍晚', '黄昏', '夜晚', '深夜', '白天', '春天', '夏天',
  '秋天', '冬天', '下雨', '下雪', '晴天', '阴天', '彩虹', '夕阳', '日出', '日落',
  '星空', '月亮', '太阳', '云朵', '微风',
  // 动作 / 状态
  '微笑', '哭泣', '睡觉', '跑步', '跳舞', '唱歌', '看书', '吃饭', '喝茶', '聊天',
  '站立', '坐着', '躺着', '回忆', '梦境', '日常',
  // 物件 / 服装
  '裙子', '长裙', '短裙', '衬衫', '外套', '帽子', '眼镜', '耳环', '项链', '鲜花',
  '樱花', '气球', '雨伞', '书包', '手机', '蛋糕', '咖啡', '牛奶',
  // 动物
  '猫', '狗', '兔子', '小鸟', '蝴蝶', '龙', '狐狸', '熊猫',
};

final _punctOrSpace = RegExp(r'[\p{P}\s]', unicode: true);

/// 词库名字的比对口径:小写、去掉标点和空白。词库里没有需要 NFKC 的写法,省掉它扫得快。
String _key(String s) => s.toLowerCase().replaceAll(_punctOrSpace, '');

bool _isCjk(int r) => r >= 0x4E00 && r <= 0x9FFF;
bool _hasCjk(String s) => s.runes.any(_isCjk);

typedef _RoleRow = ({String tag, String zh, List<int> key, int count});

/// 按热度降序扫一遍,每 [_chunk] 行让出一次。
Stream<TagRowView> _scan(TagIndex ix) async* {
  var n = 0;
  for (final r in ix.rows) {
    if (++n % _chunk == 0) await Future<void>.delayed(Duration.zero);
    yield r;
  }
}

class OfflineTags implements TagLookup {
  OfflineTags(this._index);

  final Future<TagIndex?> _index;

  Future<({List<_RoleRow> roles, Set<String> common})?>? _cache;

  /// 角色行(热度够 [kRoleAbsFloor]、有中文名)和一般 tag 的中文名(只用来否决缩写前缀)。
  Future<({List<_RoleRow> roles, Set<String> common})?> _roleCache() =>
      _cache ??= () async {
        final ix = await _index;
        if (ix == null) return null;
        final roles = <_RoleRow>[];
        final common = <String>{};
        await for (final r in _scan(ix)) {
          final cat = r.category;
          if (cat == 4) {
            if (r.count < kRoleAbsFloor) continue;
            final zh = r.zh;
            final key = _key(zh).runes.toList();
            if (key.length < _minAlias) continue;
            roles.add((tag: r.tag, zh: zh, key: key, count: r.count));
          } else if (cat == 0) {
            final zh = r.zh;
            if (zh.isEmpty) continue;
            final key = _key(zh);
            final len = key.runes.length;
            if (len >= _minPrefix && len <= 6) common.add(key);
          }
        }
        return (roles: roles, common: common);
      }();

  @override
  Future<List<TagRecord>> roleCandidates(String text, {int limit = 5}) async {
    final cache = await _roleCache();
    final msg = normalizeName(text);
    if (cache == null || msg.isEmpty) return const [];
    final hits = <_RoleRow>[];
    for (final r in cache.roles) {
      // 完整命中和各级缩写都以前两个字开头,这两个字不在句子里就整条跳过
      if (!msg.contains(String.fromCharCodes(r.key.take(_minPrefix)))) {
        continue;
      }
      final full = String.fromCharCodes(r.key);
      if (msg.contains(full)) {
        if (!_stopwords.contains(full)) hits.add(r);
        continue;
      }
      // 缩写(芙兰朵露 → 芙兰)只认全汉字前缀,且前缀本身不能是通用词
      for (var cut = r.key.length - 1; cut >= _minPrefix; cut--) {
        final head = r.key.take(cut);
        final prefix = String.fromCharCodes(head);
        if (!msg.contains(prefix) ||
            !head.every(_isCjk) ||
            cache.common.contains(prefix) ||
            _stopwords.contains(prefix)) {
          continue;
        }
        hits.add(r);
        break;
      }
    }
    if (hits.isEmpty) return const [];
    hits.sort((a, b) {
      if (a.count != b.count) return b.count.compareTo(a.count);
      if (a.tag.length != b.tag.length) {
        return a.tag.length.compareTo(b.tag.length);
      }
      return a.tag.compareTo(b.tag);
    });
    // 全被门槛拦下就一条都不给:真要查角色,模型手上还有 search_character
    final floor = max(
      kRoleAbsFloor.toDouble(),
      hits.first.count / kRoleHeatRatio,
    );
    return [
      for (final h in hits)
        if (h.count >= floor)
          (tag: h.tag, zh: h.zh, count: h.count, category: 4),
    ].take(limit).toList();
  }

  @override
  Future<List<TagRecord>> characters({
    String query = '',
    String origin = '',
    int limit = 10,
  }) async {
    final ix = await _index;
    final q = normalizeName(query);
    final o = normalizeName(origin);
    if (ix == null || (q.isEmpty && o.isEmpty)) return const [];
    final works = o.isEmpty ? const <String>[] : await _works(ix, o);
    bool inWork(String tag) => works.any((w) => tag.endsWith('_($w)'));

    if (q.isEmpty) {
      // 只给出处:列这个作品下的角色,只认 tag 带「_(作品)」的,按热度
      if (works.isEmpty) return const [];
      final out = <TagRecord>[];
      await for (final r in _scan(ix)) {
        if (r.category != 4) continue;
        final tag = r.tag;
        if (!inWork(tag)) continue;
        out.add((tag: tag, zh: r.zh, count: r.count, category: 4));
        if (out.length >= limit) break;
      }
      return out;
    }

    final scored = <(int, TagRecord)>[];
    if (_hasCjk(q)) {
      // 中文:比中文名。开头就对上的算强命中,出处对上的再往前提
      await for (final r in _scan(ix)) {
        if (r.category != 4) continue;
        final zh = r.zh;
        if (zh.isEmpty) continue;
        final key = _key(zh);
        if (!key.contains(q)) continue;
        final tag = r.tag;
        scored.add((
          (key.startsWith(q) ? 2 : 1) + (inWork(tag) ? 2 : 0),
          (tag: tag, zh: zh, count: r.count, category: 4),
        ));
        if (scored.length >= 200) break;
      }
    } else {
      // 英文:比标签名和别名,口径同编辑页补全
      for (final h in ix.search(query, limit: 60)) {
        if (h.category != 4) continue;
        scored.add((
          inWork(h.tag) ? 1 : 0,
          (tag: h.tag, zh: h.zh ?? '', count: h.count, category: 4),
        ));
      }
    }
    return _byTier(scored, limit);
  }

  @override
  Future<List<TagRecord>> tags(
    String query, {
    int? category,
    int limit = 10,
  }) async {
    final ix = await _index;
    final q = normalizeName(query);
    if (ix == null || q.isEmpty) return const [];
    bool wanted(int c) => c != 1 && (category == null || c == category);
    if (!_hasCjk(q)) {
      return [
        for (final h in ix.search(query, limit: 60))
          if (wanted(h.category))
            (tag: h.tag, zh: h.zh ?? '', count: h.count, category: h.category),
      ].take(limit).toList();
    }
    final scored = <(int, TagRecord)>[];
    await for (final r in _scan(ix)) {
      final c = r.category;
      if (!wanted(c)) continue;
      final zh = r.zh;
      if (zh.isEmpty) continue;
      final key = _key(zh);
      if (!key.contains(q)) continue;
      scored.add((
        key == q ? 3 : (key.startsWith(q) ? 2 : 1),
        (tag: r.tag, zh: zh, count: r.count, category: c),
      ));
      if (scored.length >= 200) break;
    }
    return _byTier(scored, limit);
  }

  /// 出处 → 作品 tag(按中文名或英文名认),热度最高的三个。
  Future<List<String>> _works(TagIndex ix, String origin) async {
    final out = <String>[];
    await for (final r in _scan(ix)) {
      if (r.category != 3) continue;
      final tag = r.tag;
      if (_key(r.zh).contains(origin) || _key(tag).contains(origin)) {
        out.add(tag);
        if (out.length >= 3) break;
      }
    }
    return out;
  }

  /// 按档位从高到低,同档保持扫到的先后(即热度序)。
  static List<TagRecord> _byTier(List<(int, TagRecord)> scored, int limit) {
    final indexed = [for (var i = 0; i < scored.length; i++) (i, scored[i])];
    indexed.sort((a, b) {
      final c = b.$2.$1.compareTo(a.$2.$1);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed.take(limit)) e.$2.$2];
  }
}

/// 全局一份:缓存要跨轮留着。
final offlineTagsProvider = Provider<OfflineTags>(
  (ref) => OfflineTags(ref.watch(localTagDbProvider).index),
);

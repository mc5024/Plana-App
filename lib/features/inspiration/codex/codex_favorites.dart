import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/store/atomic_file.dart';
import '../../../core/util/log.dart';
import 'codex_models.dart';

/// 法典收藏夹(`<support>/codex_favorites.json`)。
///
/// 存的是词条**快照**,不是「法典 id + 词条 id」这样的引用 —— 一部法典动辄上万
/// 条,打开要拉数据 + 解析好几秒(法典正文那个「正在载入 N 条词条…」就是它)。
/// 收藏夹是随手翻两眼的地方,不该为了看三条收藏把三部法典全拉起来。
/// 代价是法典更新后快照会旧;词条内容本来极少改,真要跟新的重新收藏一次即可。
///
/// 单独一个文件,不进 settings.json:那份是每次改设置都整体重写的,
/// 几百条收藏塞进去等于每次调个开关都重写几百 KB。
class CodexFavorite {
  const CodexFavorite({
    required this.codexId,
    required this.entry,
    required this.savedAt,
  });

  /// 所属法典 id:图 URL 要靠它回索引里取 meta(assetBaseUrl / 路径模式)。
  final String codexId;
  final CodexEntry entry;

  /// 收藏时间(毫秒);列表按它倒序,新收的在前。
  final int savedAt;

  String get key => codexFavKey(codexId, entry.id);

  Map<String, dynamic> toJson() => {
    'codexId': codexId,
    'savedAt': savedAt,
    'entry': entry.toJson(),
  };

  static CodexFavorite? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['codexId'];
    final e = j['entry'];
    if (id is! String || id.isEmpty || e is! Map<String, dynamic>) return null;
    final entry = CodexEntry.fromJson(e);
    if (entry.id.isEmpty) return null;
    return CodexFavorite(
      codexId: id,
      entry: entry,
      savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 收藏的唯一键。词条 id 只在自己那部法典里唯一,必须带上法典 id。
String codexFavKey(String codexId, String entryId) => '$codexId/$entryId';

final codexFavoritesProvider =
    AsyncNotifierProvider<CodexFavoritesNotifier, List<CodexFavorite>>(
      CodexFavoritesNotifier.new,
    );

class CodexFavoritesNotifier extends AsyncNotifier<List<CodexFavorite>> {
  /// 上限。快照带着 tags(动辄几百字符),不设限就是一个能长到几 MB 的本地文件,
  /// 而且收藏夹本身也失去意义了。满了如实告诉用户,不静默丢最旧的那条 ——
  /// 悄悄扔掉用户收过的东西比拒绝收藏更难受。
  static const kMax = 500;

  Future<File> _file() async {
    final sup = await getApplicationSupportDirectory();
    return File('${sup.path}/codex_favorites.json');
  }

  @override
  Future<List<CodexFavorite>> build() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final j = jsonDecode(await f.readAsString());
      if (j is! List) return const [];
      final out = [for (final it in j) ?CodexFavorite.fromJson(it)];
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (e) {
      logd('[codex] 收藏夹载入失败(按空处理): $e');
      return const [];
    }
  }

  /// 先改状态(界面立刻响应),再尽力落盘(失败不打断浏览)。
  Future<void> _save(List<CodexFavorite> next) async {
    state = AsyncData(next);
    try {
      await writeStringAtomic(
        await _file(),
        jsonEncode([for (final f in next) f.toJson()]),
      );
    } catch (e) {
      logd('[codex] 收藏夹保存失败: $e');
    }
  }

  List<CodexFavorite> get _list => state.value ?? const [];

  bool contains(String codexId, String entryId) {
    final k = codexFavKey(codexId, entryId);
    return _list.any((f) => f.key == k);
  }

  /// 收 / 取消收藏。返回操作后是否处于已收藏;上限已满则原样返回 false,
  /// 由调用方提示(见 [kMax])。
  Future<bool> toggle(String codexId, CodexEntry e, {required int now}) async {
    final k = codexFavKey(codexId, e.id);
    final cur = _list;
    if (cur.any((f) => f.key == k)) {
      await _save([
        for (final f in cur)
          if (f.key != k) f,
      ]);
      return false;
    }
    if (cur.length >= kMax) return false;
    await _save([
      CodexFavorite(codexId: codexId, entry: e, savedAt: now),
      ...cur,
    ]);
    return true;
  }

  /// 上限已满(toggle 返回 false 时用来区分「取消了」和「加不进去」)。
  bool get isFull => _list.length >= kMax;

  Future<void> remove(String key) async {
    await _save([
      for (final f in _list)
        if (f.key != key) f,
    ]);
  }

  Future<void> clearAll() => _save(const []);

  /// 云备份的 `codex_favorites`。
  List<Map<String, dynamic>> encodeBackup() => [
    for (final f in _list) f.toJson(),
  ];

  /// 恢复:按收藏键合并,同一条留收藏时间新的那份;超出 [kMax] 时留最新的。返回新增条数。
  Future<int> mergeBackup(List<dynamic> raw) async {
    final byKey = {for (final f in _list) f.key: f};
    var added = 0;
    for (final it in raw) {
      final f = CodexFavorite.fromJson(it);
      if (f == null) continue;
      final cur = byKey[f.key];
      if (cur == null) added++;
      if (cur == null || f.savedAt > cur.savedAt) byKey[f.key] = f;
    }
    final next = byKey.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    await _save(next.take(kMax).toList());
    return added;
  }
}

/// 收藏键集合。详情弹层每换一条词条都要问「这条收了没」,
/// 单独派生一份免得每处各遍历一遍列表。
final codexFavKeysProvider = Provider<Set<String>>(
  (ref) => {
    for (final f
        in ref.watch(codexFavoritesProvider).value ?? const <CodexFavorite>[])
      f.key,
  },
);

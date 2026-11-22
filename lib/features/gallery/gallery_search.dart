/// 图库检索索引:id → (模型, 归一化提示词文本, 来源)。模型筛选、tag 搜索与
/// 按角色 / 画风归类的数据源 —— 参数快照散在 `inputs/*.json`,逐张现读太重,
/// 这里维护一份轻量可查的内存镜像,旁挂 `search.json` 持久化。
///
/// 该索引**可重建**:文件坏了/缺了,回填会重扫快照补齐 —— 容错语义与
/// index.json(最不能坏)完全不同,所以坚决不并进 index.json。
/// 抽取只碰快照里的明文字段,不走 decodeGenerateState(那要解参考图 blob)。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../editor/editor_models.dart' show outputOf, parseFolds;
import '../generate/models.dart' show GenerateState;
import 'gallery_store.dart';

export 'gallery_store.dart' show GallerySearchMeta;

final _reWeightMark = RegExp(r'-?\d+(?:\.\d+)?::');
final _reBrackets = RegExp(r'[\[\]{}]');
final _reNewline = RegExp(r'[\s,]*\n[\s,]*');
final _reSpaces = RegExp(r'\s+');

/// 搜索归一化(索引与查询词必须同一口径):小写、剥权重记号与括号、
/// 下划线归空格、全角逗号归半角、换行归逗号、压空白。保留 `:`(artist:wlop 要搜得到)。
String normalizeSearchText(String s) => s
    .toLowerCase()
    .replaceAll(_reWeightMark, '')
    .replaceAll('::', '')
    .replaceAll(_reBrackets, '')
    .replaceAll('_', ' ')
    .replaceAll('，', ',')
    .replaceAll(_reNewline, ', ')
    .replaceAll(_reSpaces, ' ')
    .trim();

/// 查询串 → 词表(逗号/空白切分,AND 语义)。
List<String> searchTerms(String query) => [
  for (final t in normalizeSearchText(query).split(RegExp(r'[,\s]+')))
    if (t.isNotEmpty) t,
];

bool searchMatch(String normalizedText, List<String> terms) =>
    terms.every(normalizedText.contains);

/// 检索文本的取材口径:正向 + **启用的**角色正向。
///
/// 禁用的角色卡不进:它没发出去,图里没有它。早先是收的(理由是「承载过构图
/// 意图,搜得到比搜不到有用」),结果搜得到图里没画的东西,按角色分组也跟着
/// 归错 —— 这份文本同时是分组的输入。负向同样不进:人人都有 lowres/bad hands,
/// 搜什么都命中,纯噪音。
String _joinedText(String prompt, Iterable<String> charPositives) =>
    normalizeSearchText(
      [prompt, ...charPositives].where((t) => t.trim().isNotEmpty).join(', '),
    );

/// 草稿里进了载荷的折叠组名。草稿过期(对不上定稿)的不算,折叠体全被禁用的也不算。
List<String> _foldNames(Iterable<(String raw, String text)> drafts) => {
  for (final (raw, text) in drafts)
    if (raw.isNotEmpty && outputOf(raw) == text)
      for (final f in parseFolds(raw))
        if (f.name.trim().isNotEmpty &&
            outputOf(raw.substring(f.bodyStart, f.bodyEnd)).isNotEmpty)
          f.name.trim(),
}.toList();

/// 内存里的输入快照 → 元数据(addResult 同帧,input 一定在)。
GallerySearchMeta metaOfInput(GenerateState s) {
  final chars = [
    for (final c in s.characters)
      if (c.enabled) c,
  ];
  return (
    model: s.params.model,
    text: _joinedText(s.prompt, [for (final c in chars) c.positive]),
    ids: {
      ...s.usedEntries,
      for (final c in chars)
        if (c.source != null) c.source!,
    }.toList(),
    cards: [
      for (final c in chars)
        if (c.name.trim().isNotEmpty) c.name.trim(),
    ],
    folds: _foldNames([
      (s.promptRaw, s.prompt),
      for (final c in chars) (c.positiveRaw, c.positive),
    ]),
  );
}

/// 快照原始 JSON(`inputs/<id>.json` 的 `{v, refs, state}`)→ 元数据。
/// 字段名钉在 state_codec 的编码形状上;认不出返回 null。
GallerySearchMeta? metaOfSnapshotJson(Map<String, dynamic> j) {
  final st = j['state'];
  if (st is! Map) return null;
  final params = st['params'];
  String str(Object? v) => v is String ? v : '';
  final chars = [
    if (st['characters'] is List)
      for (final c in st['characters'] as List)
        // 缺 enabled 键按启用算:state_codec 解码时默认就是 true
        if (c is Map && c['enabled'] != false) c,
  ];
  return (
    model: params is Map && params['model'] is String
        ? params['model'] as String
        : '',
    text: _joinedText(str(st['prompt']), [
      for (final c in chars) str(c['positive']),
    ]),
    ids: {
      if (st['usedEntries'] is List)
        for (final x in st['usedEntries'] as List)
          if (x is String) x,
      for (final c in chars)
        if (c['source'] is String) c['source'] as String,
    }.toList(),
    cards: [
      for (final c in chars)
        if (str(c['name']).trim().isNotEmpty) str(c['name']).trim(),
    ],
    folds: _foldNames([
      (str(st['promptRaw']), str(st['prompt'])),
      for (final c in chars) (str(c['positiveRaw']), str(c['positive'])),
    ]),
  );
}

class GallerySearchState {
  const GallerySearchState({
    this.byId = const {},
    this.building = false,
    this.done = 0,
    this.total = 0,
  });

  final Map<String, GallerySearchMeta> byId;

  /// 老图回填进行中(展开页筛选栏显示进度;结果随回填逐步变全)。
  final bool building;
  final int done;
  final int total;

  GallerySearchState copyWith({
    Map<String, GallerySearchMeta>? byId,
    bool? building,
    int? done,
    int? total,
  }) => GallerySearchState(
    byId: byId ?? this.byId,
    building: building ?? this.building,
    done: done ?? this.done,
    total: total ?? this.total,
  );
}

final gallerySearchProvider =
    NotifierProvider<GallerySearchNotifier, GallerySearchState>(
      GallerySearchNotifier.new,
    );

class GallerySearchNotifier extends Notifier<GallerySearchState> {
  GalleryStore get _store => ref.read(appStoresProvider).gallery;

  @override
  GallerySearchState build() {
    Future.microtask(_init); // build 里不做 IO
    return const GallerySearchState();
  }

  Future<void> _init() async {
    final loaded = await _store.readSearchIndex();
    // 已 put 的新图优先(_init 前生成的),盘上旧值不回退它
    state = state.copyWith(byId: {...loaded, ...state.byId});
    await _backfill();
  }

  /// 每批回填的快照数。
  static const _batch = 200;

  /// 老图回填:盘上有快照但索引缺的,分批在后台 isolate 里读快照、抽取;每批
  /// 做完就落盘,中途被杀下次接着补。顺带清掉快照已不在的陈条(崩溃残留)。
  Future<void> _backfill() async {
    final ids = await _store.listInputIds();
    final live = ids.toSet();
    final missing = [
      for (final id in ids)
        if (!state.byId.containsKey(id)) id,
    ];
    final stale = [
      for (final id in state.byId.keys)
        if (!live.contains(id)) id,
    ];
    if (missing.isEmpty && stale.isEmpty) return;

    if (missing.isNotEmpty) {
      state = state.copyWith(building: true, done: 0, total: missing.length);
    }
    for (var i = 0; i < missing.length; i += _batch) {
      final add = await _metasInIsolate([
        for (final id in missing.skip(i).take(_batch))
          (id: id, path: _store.inputPathOf(id)),
      ]);
      state = state.copyWith(
        byId: {...state.byId, ...add},
        done: math.min(i + _batch, missing.length),
      );
      _store.appendSearch(add);
    }
    final next = {...state.byId}..removeWhere((id, _) => !live.contains(id));
    state = GallerySearchState(byId: next);
    _store.appendSearchRemovals(stale);
  }

  /// 新结果入索引(addResult 同帧调,input 在内存,零 IO)。
  void put(String id, GenerateState input) {
    final m = metaOfInput(input);
    state = state.copyWith(byId: {...state.byId, id: m});
    _store.appendSearch({id: m});
  }

  /// 删除/裁剪联动。
  void removeAll(Iterable<String> ids) {
    final drop = [
      for (final id in ids.toSet())
        if (state.byId.containsKey(id)) id,
    ];
    if (drop.isEmpty) return;
    final gone = drop.toSet();
    state = state.copyWith(
      byId: {...state.byId}..removeWhere((id, _) => gone.contains(id)),
    );
    _store.appendSearchRemovals(drop);
  }

  void clear() {
    if (state.byId.isEmpty) return;
    state = state.copyWith(byId: const {});
    _store.clearSearch();
  }
}

Future<Map<String, GallerySearchMeta>> _metasInIsolate(
  List<({String id, String path})> files,
) => Isolate.run(() => _metasOfSnapshots(files));

/// 后台 isolate:逐个读快照抽元数据。读不出 / 认不出的不进结果。
Map<String, GallerySearchMeta> _metasOfSnapshots(
  List<({String id, String path})> files,
) {
  final out = <String, GallerySearchMeta>{};
  for (final f in files) {
    try {
      final j = jsonDecode(File(f.path).readAsStringSync());
      if (j is! Map<String, dynamic>) continue;
      if (metaOfSnapshotJson(j) case final m?) out[f.id] = m;
    } catch (_) {}
  }
  return out;
}

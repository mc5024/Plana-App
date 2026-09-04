import 'package:flutter/material.dart' show IconData, Icons;

import '../../core/util/prompt_tokens.dart';
import '../editor/editor_models.dart' show foldWrap, outputOf;

/// 灵感页(Tag 管理器)数据模型,对齐 web tag-manager 的注册表与条目结构。
/// 分类 id 沿用 web(character/artist-style/scene/other),云备份四类键
/// 与 web 完全互通;自定义分类 web 端未开放,app 不实现。
enum TagCategory { character, artist, scene, other }

class TagCategoryDef {
  const TagCategoryDef(
    this.key,
    this.webId,
    this.label,
    this.icon, {
    required this.searchHint,
    required this.maxSelectable,
    required this.previewAspect,
    this.hasPublic = false,
    this.alphabetRail = false,
  });

  final TagCategory key;

  /// web 端 subtypeId,同时是云备份 categories 的键。
  final String webId;
  final String label;
  final IconData icon;
  final String searchHint;

  /// 单次可选上限(角色 6 = 角色卡槽位;画风 99;场景/其他 20,对齐 web)。
  /// 角色分类在灵感页会被按模型覆盖(NAI 5 槽位 20,见 maxCharactersOf),
  /// 这里的 6 只是 const 表放不下模型参数的兜底。
  final int maxSelectable;

  /// 是否有服务端公共库(仅角色/画风)。
  final bool hasPublic;

  /// 预览图宽高比:角色竖图 832/1216、画风横图 1216/832、场景其他方图。
  /// 卡片按此比例排版,BoxFit.cover 下预览图恰好完整铺满不裁切。
  final double previewAspect;

  /// 右缘字母导航(仅画风,条目名以 A1..Z99 编号为主)。
  final bool alphabetRail;
}

const kTagCategoryDefs = <TagCategoryDef>[
  TagCategoryDef(
    TagCategory.character,
    'character',
    '角色',
    Icons.person_outline,
    searchHint: '搜索角色 / 别名…',
    maxSelectable: 6,
    previewAspect: 832 / 1216,
    hasPublic: true,
  ),
  TagCategoryDef(
    TagCategory.artist,
    'artist-style',
    '画风',
    Icons.palette_outlined,
    searchHint: '搜索名称 / 提示词 / 标签…',
    maxSelectable: 99,
    previewAspect: 1216 / 832,
    hasPublic: true,
    alphabetRail: true,
  ),
  TagCategoryDef(
    TagCategory.scene,
    'scene',
    '场景',
    Icons.landscape_outlined,
    searchHint: '搜索场景…',
    maxSelectable: 20,
    previewAspect: 1,
  ),
  TagCategoryDef(
    TagCategory.other,
    'other',
    '其他',
    Icons.sell_outlined,
    searchHint: '搜索名称 / 提示词…',
    maxSelectable: 20,
    previewAspect: 1,
  ),
];

TagCategoryDef tagCategoryDef(TagCategory c) =>
    kTagCategoryDefs.firstWhere((d) => d.key == c);

/// 灵感页网格的排序档。
///   [number] 按名字自然序(A1<A2<A10)—— 只有画风有,它的名字本来就是编号;
///   [time]   最新在前;
///   [author] 按作者切组,组内仍按该分类的自然序。
enum TagSort { number, time, author }

extension TagSortX on TagSort {
  String get label => switch (this) {
    TagSort.number => '编号',
    TagSort.time => '最新',
    TagSort.author => '作者',
  };
}

/// 该分类的默认档 = 它原本的排法(画风按编号,其余最新在前)。
TagSort defaultTagSort(TagCategory c) =>
    c == TagCategory.artist ? TagSort.number : TagSort.time;

/// 排序菜单给哪几档:编号只对画风有意义,角色那栏就少一项。
List<TagSort> tagSortOptions(TagCategory c) => c == TagCategory.artist
    ? const [TagSort.number, TagSort.time, TagSort.author]
    : const [TagSort.time, TagSort.author];

TagCategory? tagCategoryByWebId(String webId) {
  for (final d in kTagCategoryDefs) {
    if (d.webId == webId) return d.key;
  }
  return null;
}

/// 条目来源(决定卡片角标与可编辑范围,对齐 web origin 三态):
/// local=本机创建;favorited=从公共库收藏的副本;created=自己发布的
/// 公共条目的本地副本(app 暂不做发布,解析备份时保留该态)。
enum TagOrigin { local, favorited, created }

/// 统一条目模型(web TagFile / ArtistData / OCData / CustomTagData 的归一)。
/// [extra] 透传 web 备份里 app 不认识的字段(恢复时收下、上传时原样带回),
/// 避免 app 恢复→再上传的整体覆盖冲掉 web 端数据;体积大的 base64 预览
/// 除外(解码时即丢弃,上传确认时向用户说明)。
class TagEntry {
  const TagEntry({
    required this.id,
    required this.category,
    required this.name,
    this.positive = '',
    this.negative = '',
    this.aliases = const [],
    this.tags = const [],
    this.models = const [],
    this.origin = TagOrigin.local,
    this.publicId,
    this.previews = const [],
    this.createdAt = 0,
    this.createdBy,
    this.extra = const {},
  });

  /// 封面(首张预览)。
  String? get previewUrl => previews.isEmpty ? null : previews.first;

  final String id;
  final TagCategory category;
  final String name;
  final String positive;
  final String negative;

  /// 别名(仅角色用于搜索)。
  final List<String> aliases;

  /// 用户私有二级标签(筛选用,纯本地,不上公共库)。
  final List<String> tags;

  /// 适用模型 id 列表(仅画风;见 artist_models.dart)。空 = 通用,老数据即此档。
  /// **不参与出图**,只用于筛选与角标。id 与 web 互通,会随公共库和云备份走。
  final List<String> models;
  final TagOrigin origin;

  /// 对应公共库条目 id(favorited/created 时有,收藏去重依据)。
  final String? publicId;

  /// 预览图列表(http URL 或本机文件路径;画师串最多 4 张,首张为封面;
  /// 空则渲染条纹占位)。
  final List<String> previews;
  final int createdAt; // ms
  final String? createdBy;
  final Map<String, dynamic> extra;

  /// [publicId] 传 [clearPublicId] 哨兵可清空(取消发布/脱钩副本用)。
  static const clearPublicId = Object();

  TagEntry copyWith({
    String? name,
    String? positive,
    String? negative,
    List<String>? aliases,
    List<String>? tags,
    List<String>? models,
    TagOrigin? origin,
    Object? publicId,
    List<String>? previews,
    String? createdBy,
  }) => TagEntry(
    id: id,
    category: category,
    name: name ?? this.name,
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    aliases: aliases ?? this.aliases,
    tags: tags ?? this.tags,
    origin: origin ?? this.origin,
    publicId: identical(publicId, clearPublicId)
        ? null
        : (publicId as String? ?? this.publicId),
    previews: previews ?? this.previews,
    createdAt: createdAt,
    createdBy: createdBy ?? this.createdBy,
    extra: extra,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': tagCategoryDef(category).webId,
    'name': name,
    'positive': positive,
    'negative': negative,
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (tags.isNotEmpty) 'tags': tags,
    if (models.isNotEmpty) 'models': models,
    'origin': origin.name,
    if (publicId != null) 'publicId': publicId,
    if (previews.isNotEmpty) 'previews': previews,
    'createdAt': createdAt,
    if (createdBy != null) 'createdBy': createdBy,
    if (extra.isNotEmpty) 'extra': extra,
  };

  static TagEntry? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final cat = j['category'] is String
        ? tagCategoryByWebId(j['category'] as String)
        : null;
    if (id is! String || cat == null) return null;
    return TagEntry(
      id: id,
      category: cat,
      name: j['name'] is String ? j['name'] as String : '',
      positive: j['positive'] is String ? j['positive'] as String : '',
      negative: j['negative'] is String ? j['negative'] as String : '',
      aliases: _strList(j['aliases']),
      tags: _strList(j['tags']),
      models: _strList(j['models']),
      origin: TagOrigin.values.asNameMap()[j['origin']] ?? TagOrigin.local,
      publicId: j['publicId'] as String?,
      // 旧版单字段 previewUrl 迁入列表
      previews: j['previews'] is List
          ? _strList(j['previews'])
          : [if (j['previewUrl'] is String) j['previewUrl'] as String],
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      createdBy: j['createdBy'] as String?,
      extra: j['extra'] is Map<String, dynamic>
          ? j['extra'] as Map<String, dynamic>
          : const {},
    );
  }
}

/// 本地备份文件(与 web tag-manager 导出格式逐字一致,双端可互导)。
const kBackupFileIdentifier = 'tag-manager-backup';
const kBackupFileVersion = 1;

Map<String, dynamic> buildBackupFile(
  TagCategory cat,
  List<Map<String, dynamic>> items, {
  required String exportedAt,
}) => {
  'identifier': kBackupFileIdentifier,
  'version': kBackupFileVersion,
  'category': tagCategoryDef(cat).webId,
  'exportedAt': exportedAt,
  'count': items.length,
  'items': items,
};

/// 解析备份文件。返回 (分类, 条目);格式不符抛 [FormatException](文案可直出)。
({TagCategory cat, List<Map<String, dynamic>> items}) parseBackupFile(
  Map<String, dynamic> j,
) {
  if (j['identifier'] != kBackupFileIdentifier) {
    throw const FormatException('不是 Tag 管理器的备份文件');
  }
  final cat = j['category'] is String
      ? tagCategoryByWebId(j['category'] as String)
      : null;
  if (cat == null) throw const FormatException('备份文件的分类无法识别');
  return (
    cat: cat,
    items: [
      for (final e in (j['items'] is List ? j['items'] as List : const []))
        if (e is Map<String, dynamic>) e,
    ],
  );
}

/// 备份/发布只带可跨端使用的 http(s) 预览,本机文件路径不外发。
List<String> portablePreviews(List<String> previews) => [
  for (final p in previews)
    if (p.startsWith('http')) p,
];

List<String> _strList(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is String) e,
      ]
    : const [];

/// 追加正向到**编辑器原文草稿**:每个条目各自包成一个命名折叠(名字取条目名,
/// 单枚标签不折),加入后在编辑器里就是一个可收起的整体。
///
/// 去重按**定稿**判定:草稿里有折叠/禁用记号,直接分词会把记号当成标签,
/// 既漏判也可能误判。
String appendTagPositivesFolded(String draft, Iterable<TagEntry> entries) {
  var out = draft.trim();
  final have = tokenizeSet(outputOf(out));
  for (final e in entries) {
    final p = e.positive.trim();
    if (p.isEmpty) continue;
    final toks = tokenizeSet(p);
    if (toks.isNotEmpty && have.containsAll(toks)) continue;
    have.addAll(toks);
    final piece = foldWrap(e.name, p);
    out = out.isEmpty ? piece : '$out, $piece';
  }
  return out;
}

/// 追加负面:逗号拆词、与现有去重后逐词追加(对齐 web appendArtistNegatives)。
String appendTagNegatives(String negative, Iterable<TagEntry> entries) {
  var out = negative.trim();
  final have = tokenizeSet(out);
  for (final e in entries) {
    for (final piece in e.negative.split(RegExp(r'[，,]'))) {
      final raw = piece.trim();
      final t = cleanPromptToken(raw);
      if (raw.isEmpty || t.isEmpty || have.contains(t)) continue;
      have.add(t);
      out = out.isEmpty ? raw : '$out, $raw';
    }
  }
  return out;
}

/// 编号自然序(A1 < A2 < A10,画风列表用):文本段不分大小写比较,
/// 数字段按数值比较。
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+|\D+)');
  final xa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final xb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xa.length && i < xb.length; i++) {
    final na = int.tryParse(xa[i]);
    final nb = int.tryParse(xb[i]);
    final c = na != null && nb != null
        ? na.compareTo(nb)
        : xa[i].compareTo(xb[i]);
    if (c != 0) return c;
  }
  return xa.length.compareTo(xb.length);
}

/// 画师串「获取编号」:A1..A99 → B1..,取首个空位(gap-filling,
/// 对齐 web suggestNextArtistCode;占用集 = 本地∪公共全部名称)。
String? suggestArtistCode(Set<String> occupied) {
  final upper = {for (final n in occupied) n.trim().toUpperCase()};
  for (var l = 'A'.codeUnitAt(0); l <= 'Z'.codeUnitAt(0); l++) {
    for (var n = 1; n <= 99; n++) {
      final code = '${String.fromCharCode(l)}$n';
      if (!upper.contains(code)) return code;
    }
  }
  return null;
}

/// 字母导航分桶:首个 ASCII 字母大写,其余归 '#'。
String letterOfName(String name) {
  if (name.isEmpty) return '#';
  final c = name.codeUnitAt(0);
  if ((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)) {
    return String.fromCharCode(c & ~0x20);
  }
  return '#';
}

/// 云备份条目编码:按 web 各分类的本地存储 shape 生成(画师串用 `prompt`,
/// 角色/场景/其他用 `positive`),extra 打底、本字段覆盖,web 恢复可直读。
Map<String, dynamic> encodeBackupEntry(TagEntry e) {
  final base = Map<String, dynamic>.from(e.extra);
  base['id'] = e.id;
  base['name'] = e.name;
  base['negative'] = e.negative;
  base['createdAt'] = e.createdAt;
  base['isLocal'] = true;
  base['origin'] = e.origin.name;
  if (e.publicId != null) base['publicId'] = e.publicId;
  if (e.tags.isNotEmpty) base['tags'] = e.tags;
  switch (e.category) {
    case TagCategory.artist:
      base['prompt'] = e.positive;
      base['previews'] ??= portablePreviews(e.previews);
    case TagCategory.character:
      base['positive'] = e.positive;
      base['aliases'] = e.aliases;
      base['preview'] ??= portablePreviews(e.previews).firstOrNull ?? '';
    case TagCategory.scene || TagCategory.other:
      base['positive'] = e.positive;
      base['subtypeId'] = tagCategoryDef(e.category).webId;
  }
  return base;
}

/// 云备份条目解码(容错:web 三种 shape 双读;base64 预览体积过大不落地)。
TagEntry? decodeBackupEntry(TagCategory cat, Map<String, dynamic> j) {
  final id = j['id'];
  if (id is! String || id.isEmpty) return null;
  final name = j['name'];
  final positive = j['positive'] ?? j['prompt'] ?? j['tag_group'];

  final previews = <String>[];
  void addPreview(Object? v) {
    if (v is String && v.isNotEmpty && !v.startsWith('data:')) {
      previews.add(v);
    }
  }

  addPreview(j['preview']);
  if (j['previews'] is List) {
    for (final p in j['previews'] as List) {
      addPreview(p);
    }
  }

  // extra 透传除 app 已建模字段外的一切;previews/preview 的 base64 丢弃。
  final extra = <String, dynamic>{
    for (final en in j.entries)
      if (!const {
        'id',
        'name',
        'positive',
        'prompt',
        'tag_group',
        'negative',
        'negative_prompt',
        'aliases',
        'tags',
        'origin',
        'publicId',
        'createdAt',
        'isLocal',
        'subtypeId',
        'preview',
        'previews',
      }.contains(en.key))
        en.key: en.value,
  };

  return TagEntry(
    id: id,
    category: cat,
    name: name is String ? name : '',
    positive: positive is String ? positive : '',
    negative: (j['negative'] ?? j['negative_prompt']) is String
        ? (j['negative'] ?? j['negative_prompt']) as String
        : '',
    aliases: _strList(j['aliases']),
    tags: _strList(j['tags']),
    origin: TagOrigin.values.asNameMap()[j['origin']] ?? TagOrigin.local,
    // 历史数据里 publicId/added_by 存在裸数字,宽松转字符串,别让恢复崩掉
    publicId: switch (j['publicId']) {
      final String s => s,
      final num n => '$n',
      _ => null,
    },
    previews: previews,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    createdBy: switch (j['user'] ?? j['addedBy']) {
      final String s => s,
      final num n => '$n',
      _ => null,
    },
    extra: extra,
  );
}

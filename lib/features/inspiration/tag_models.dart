import 'package:flutter/material.dart' show IconData, Icons;

import '../../core/util/prompt_tokens.dart';
import '../editor/editor_models.dart' show foldWrap, outputOf;

/// 灵感页(Tag 管理器)数据模型,对齐 web tag-manager 的注册表与条目结构。
/// 内置四类的 id 沿用 web(character/artist-style/scene/other),云备份四类键
/// 与 web 完全互通;用户自建的类别 id 以 `c_` 开头,云备份里单走 `custom`。
final class TagCategory {
  const TagCategory._(this.name);

  /// 内置四类是原来的枚举名;自定义类别就是它的 id(`c_…`,同 webId)。
  final String name;

  static const character = TagCategory._('character');
  static const artist = TagCategory._('artist');
  static const scene = TagCategory._('scene');
  static const other = TagCategory._('other');

  static const builtins = [character, artist, scene, other];

  static const customPrefix = 'c_';

  /// 自定义类别。
  factory TagCategory.custom(String id) => TagCategory._(id);

  bool get isCustom => name.startsWith(customPrefix);

  @override
  bool operator ==(Object other) => other is TagCategory && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'TagCategory($name)';
}

/// 预览图形状(自定义类别可选;内置四类各自固定)。
enum TagCardLayout { portrait, landscape, square, none }

extension TagCardLayoutX on TagCardLayout {
  String get label => switch (this) {
    TagCardLayout.portrait => '竖图',
    TagCardLayout.landscape => '横图',
    TagCardLayout.square => '方图',
    TagCardLayout.none => '无图',
  };

  double get aspect => switch (this) {
    TagCardLayout.portrait => 832 / 1216,
    TagCardLayout.landscape => 1216 / 832,
    _ => 1,
  };
}

/// 自定义类别可选的图标。键名同 web 注册表的 lucide 图标名(`Shirt` 是 app 加的)。
const kTagCategoryIcons = <String, IconData>{
  'Shirt': Icons.checkroom_outlined,
  'Sparkles': Icons.auto_awesome_outlined,
  'Sun': Icons.wb_sunny_outlined,
  'Moon': Icons.dark_mode_outlined,
  'Heart': Icons.favorite_border,
  'Star': Icons.star_outline,
  'Camera': Icons.photo_camera_outlined,
  'Flame': Icons.local_fire_department_outlined,
  'Leaf': Icons.eco_outlined,
  'Flower': Icons.local_florist_outlined,
  'Crown': Icons.workspace_premium_outlined,
  'Gem': Icons.diamond_outlined,
  'Hand': Icons.back_hand_outlined,
  'Eye': Icons.visibility_outlined,
  'Smile': Icons.sentiment_satisfied_outlined,
  'PersonStanding': Icons.accessibility_new,
  'Music': Icons.music_note_outlined,
  'Brush': Icons.brush_outlined,
  'Wand': Icons.auto_fix_high_outlined,
  'Zap': Icons.bolt_outlined,
  'Cloud': Icons.cloud_outlined,
  'Snowflake': Icons.ac_unit,
  'Droplet': Icons.water_drop_outlined,
  'Tag': Icons.sell_outlined,
};

class TagCategoryDef {
  const TagCategoryDef(
    this.key,
    this.webId,
    this.label,
    this.icon, {
    required this.searchHint,
    required this.maxSelectable,
    required this.previewAspect,
    this.hasPreview = true,
    this.hasPublic = false,
    this.alphabetRail = false,
    this.iconName,
    this.layout,
  });

  /// 自定义类别。
  factory TagCategoryDef.custom({
    required String id,
    required String label,
    required String iconName,
    required TagCardLayout layout,
  }) => TagCategoryDef(
    TagCategory.custom(id),
    id,
    label,
    kTagCategoryIcons[iconName] ?? Icons.sell_outlined,
    searchHint: '搜索名称 / 提示词…',
    maxSelectable: 20,
    previewAspect: layout.aspect,
    hasPreview: layout != TagCardLayout.none,
    iconName: iconName,
    layout: layout,
  );

  final TagCategory key;

  /// web 端 subtypeId,同时是云备份 categories 的键(自定义类别 = 它的 id)。
  final String webId;
  final String label;
  final IconData icon;
  final String searchHint;

  /// 单次可选上限(角色 6 = 角色卡槽位;画风 99;场景/其他/自定义 20,对齐 web)。
  /// 角色分类在灵感页会被按模型覆盖(NAI 5 槽位 20,见 maxCharactersOf),
  /// 这里的 6 只是 const 表放不下模型参数的兜底。
  final int maxSelectable;

  /// 是否有服务端公共库(仅角色/画风)。
  final bool hasPublic;

  /// 预览图宽高比:角色竖图 832/1216、画风横图 1216/832、场景其他方图。
  /// 卡片按此比例排版,BoxFit.cover 下预览图恰好完整铺满不裁切。
  final double previewAspect;

  /// 条目有没有预览图(其他、无图的自定义类别没有)。
  final bool hasPreview;

  /// 右缘字母导航(仅画风,条目名以 A1..Z99 编号为主)。
  final bool alphabetRail;

  /// 自定义类别才有:图标键名、预览图形状。
  final String? iconName;
  final TagCardLayout? layout;

  /// 换个名字(内置类别改名用),其余不变。
  TagCategoryDef withLabel(String label) => TagCategoryDef(
    key,
    webId,
    label,
    icon,
    searchHint: searchHint,
    maxSelectable: maxSelectable,
    previewAspect: previewAspect,
    hasPreview: hasPreview,
    hasPublic: hasPublic,
    alphabetRail: alphabetRail,
    iconName: iconName,
    layout: layout,
  );

  Map<String, dynamic> toJson() => {
    'id': webId,
    'label': label,
    'iconName': iconName,
    'cardLayout': layout?.name,
  };

  /// 自定义类别定义;不合规返回 null。
  static TagCategoryDef? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final label = j['label'];
    if (id is! String ||
        !id.startsWith(TagCategory.customPrefix) ||
        label is! String) {
      return null;
    }
    return TagCategoryDef.custom(
      id: id,
      label: label,
      iconName: j['iconName'] is String ? j['iconName'] as String : 'Tag',
      layout:
          TagCardLayout.values.asNameMap()[j['cardLayout']] ??
          TagCardLayout.square,
    );
  }
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
    hasPreview: false,
  ),
];

/// 当前的自定义类别(由 [TagLibrary] 在载入 / 改动时同步)。放在这里而不是
/// 只放 provider 里,是为了让 [tagCategoryDef] 这类同步查表在哪都能用。
var _customDefs = <String, TagCategoryDef>{};

/// 内置类别(含法典,键 `codex`)改过的名字。
var _labels = <String, String>{};

void syncCustomTagCategories(
  Iterable<TagCategoryDef> defs, {
  Map<String, String> labels = const {},
}) {
  _customDefs = {for (final d in defs) d.webId: d};
  _labels = labels;
}

/// 法典页签的名字(可改名)。
String codexTabLabel() => _labels['codex'] ?? '法典';

TagCategoryDef tagCategoryDef(TagCategory c) {
  for (final d in kTagCategoryDefs) {
    if (d.key == c) {
      final l = _labels[d.webId];
      return l == null ? d : d.withLabel(l);
    }
  }
  return _customDefs[c.name] ??
      TagCategoryDef.custom(
        id: c.name,
        label: '未命名',
        iconName: 'Tag',
        layout: TagCardLayout.square,
      );
}

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

/// 按 webId 认分类:内置四类按表,`c_` 开头的是自定义类别。
TagCategory? tagCategoryByWebId(String webId) {
  for (final d in kTagCategoryDefs) {
    if (d.webId == webId) return d.key;
  }
  if (webId.startsWith(TagCategory.customPrefix)) {
    return TagCategory.custom(webId);
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
    this.recipe,
    this.extra = const {},
    this.mosaic = false,
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

  /// 推荐参数(仅画风;见 [StyleRecipe])。null = 没记。
  final StyleRecipe? recipe;
  final Map<String, dynamic> extra;

  /// 公共库预览要先打码(服务端给);只在公共库列表里有,不落盘、不进备份。
  final bool mosaic;

  /// [publicId] 传 [clearPublicId] 哨兵可清空(取消发布/脱钩副本用)。
  static const clearPublicId = Object();

  /// [recipe] 传 [clearRecipe] 哨兵可清空。
  static const clearRecipe = Object();

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
    Object? recipe,
    bool? mosaic,
  }) => TagEntry(
    id: id,
    category: category,
    name: name ?? this.name,
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    aliases: aliases ?? this.aliases,
    tags: tags ?? this.tags,
    models: models ?? this.models,
    origin: origin ?? this.origin,
    publicId: identical(publicId, clearPublicId)
        ? null
        : (publicId as String? ?? this.publicId),
    previews: previews ?? this.previews,
    createdAt: createdAt,
    createdBy: createdBy ?? this.createdBy,
    recipe: identical(recipe, clearRecipe)
        ? null
        : (recipe as StyleRecipe? ?? this.recipe),
    extra: extra,
    mosaic: mosaic ?? this.mosaic,
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
    if (recipe != null) 'recipe': recipe!.toJson(),
    if (extra.isNotEmpty) 'extra': extra,
  };

  static TagEntry? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final cat = j['category'] is String
        ? tagCategoryByWebId(j['category'] as String)
        : null;
    if (id is! String || cat == null) return null;
    final rawExtra = j['extra'] is Map<String, dynamic>
        ? j['extra'] as Map<String, dynamic>
        : const <String, dynamic>{};
    // 早先从云端恢复时 web 标的适用模型落进了 extra(解码没认这个键):
    // 搬回字段,extra 里不再留,免得编码备份时又被旧值带出去
    var models = _strList(j['models']);
    if (models.isEmpty) models = _strList(rawExtra['models']);
    final extra = rawExtra.containsKey('models')
        ? ({...rawExtra}..remove('models'))
        : rawExtra;
    return TagEntry(
      id: id,
      category: cat,
      name: j['name'] is String ? j['name'] as String : '',
      positive: j['positive'] is String ? j['positive'] as String : '',
      negative: j['negative'] is String ? j['negative'] as String : '',
      aliases: _strList(j['aliases']),
      tags: _strList(j['tags']),
      models: models,
      origin: TagOrigin.values.asNameMap()[j['origin']] ?? TagOrigin.local,
      publicId: j['publicId'] as String?,
      // 旧版单字段 previewUrl 迁入列表
      previews: j['previews'] is List
          ? _strList(j['previews'])
          : [if (j['previewUrl'] is String) j['previewUrl'] as String],
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      createdBy: j['createdBy'] as String?,
      recipe: StyleRecipe.fromJson(j['recipe']),
      extra: extra,
    );
  }
}

/// 画风的推荐参数:记下时的模型 + 那一档的采样参数(步数、CFG、采样器、调度,
/// NAI 另有 CFG Rescale 与 Variety+)。
///
/// 画风本身仍是那串提示词;这份只是附带的出图条件 —— 导入时模型对得上才提示,
/// 用户点了才写进当前画布,不切模型。随条目进云备份,发布时也带进公共库。
class StyleRecipe {
  const StyleRecipe({
    required this.model,
    required this.steps,
    required this.cfg,
    required this.sampler,
    required this.scheduler,
    this.cfgRescale = 0,
    this.varietyPlus = false,
  });

  /// 记下时的模型,用与 web 互通的模型 id(见 artist_models.dart);
  /// 目录里没有的模型存展示名。
  final String model;
  final int steps;
  final double cfg;
  final String sampler;

  /// NAI 是噪声调度,Anima / Krea 是调度器。
  final String scheduler;

  /// 仅 NAI 有。
  final double cfgRescale;
  final bool varietyPlus;

  Map<String, dynamic> toJson() => {
    'model': model,
    'steps': steps,
    'cfg': cfg,
    'sampler': sampler,
    'scheduler': scheduler,
    'cfgRescale': cfgRescale,
    'varietyPlus': varietyPlus,
  };

  /// 缺关键字段就当没有 —— 半套参数套出去比不套更难查。
  static StyleRecipe? fromJson(Object? j) {
    if (j is! Map) return null;
    final model = j['model'];
    final steps = j['steps'];
    final cfg = j['cfg'];
    final sampler = j['sampler'];
    final scheduler = j['scheduler'];
    if (model is! String ||
        model.isEmpty ||
        steps is! num ||
        cfg is! num ||
        sampler is! String ||
        scheduler is! String) {
      return null;
    }
    return StyleRecipe(
      model: model,
      steps: steps.toInt(),
      cfg: cfg.toDouble(),
      sampler: sampler,
      scheduler: scheduler,
      cfgRescale: switch (j['cfgRescale']) {
        final num v => v.toDouble(),
        _ => 0,
      },
      varietyPlus: j['varietyPlus'] == true,
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
/// 给了 [present] 就按它判重,不给按 [negative] 自己。
String appendTagNegatives(
  String negative,
  Iterable<TagEntry> entries, {
  String? present,
}) {
  var out = negative.trim();
  final have = tokenizeSet(present ?? out);
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
      // 适用模型、推荐参数以字段为准:有就写,清空了就不带这个键(通用 / 没记)
      if (e.models.isNotEmpty) {
        base['models'] = e.models;
      } else {
        base.remove('models');
      }
      if (e.recipe case final r?) {
        base['recipe'] = r.toJson();
      } else {
        base.remove('recipe');
      }
    case TagCategory.character:
      base['positive'] = e.positive;
      base['aliases'] = e.aliases;
      base['preview'] ??= portablePreviews(e.previews).firstOrNull ?? '';
    case TagCategory.scene || TagCategory.other:
      base['positive'] = e.positive;
      base['subtypeId'] = tagCategoryDef(e.category).webId;
    default:
      base['positive'] = e.positive;
      base['subtypeId'] = e.category.name;
      base['previews'] ??= portablePreviews(e.previews);
  }
  return base;
}

/// 云备份条目解码(容错:web 三种 shape 双读;base64 预览不在这里落地,
/// 见 [TagLibrary.mergeBackup])。
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
        'models',
        'recipe',
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
    models: _strList(j['models']),
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
    recipe: StyleRecipe.fromJson(j['recipe']),
    extra: extra,
  );
}

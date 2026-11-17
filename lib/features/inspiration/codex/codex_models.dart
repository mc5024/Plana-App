/// 法典(社区整理的成品提示词图鉴)数据模型 —— 消费 quicktagcloud.com 的
/// 公开数据源(index=codexes.json,每部一个 `<id>.json`,图在 R2 CDN)。
///
/// 这是**只读**接入:app 不改、不发布法典内容,只按原站的口径解析与拼 URL。
/// 图片 URL 构造严格照搬原站 `site/assets/app/media.js` 的 mediaPath/assetUrl:
/// 两种取图模式(默认 = 图床/images/法典id/文件名;relative = 每部自带 assetBaseUrl),
/// 拼错就会整片裂图,故用 [codex_test.dart] 把两模式与编码/版本号钉死。
library;

import '../../../l10n/l10n.dart';

/// 图床配置(取自原站 data/media.json)。字段缺失时退回已知常量,
/// 保证即使 media.json 拉不到也能出图。
class CodexMedia {
  const CodexMedia({
    required this.baseUrl,
    required this.imagePrefix,
    required this.originalPrefix,
  });

  /// R2 图床根,如 `https://assets.quicktagcloud.com`。
  final String baseUrl;
  final String imagePrefix; // 'images'
  final String originalPrefix; // 'originals'

  /// media.json 拉不到时的兜底(与原站现值一致)。
  static const fallback = CodexMedia(
    baseUrl: 'https://assets.quicktagcloud.com',
    imagePrefix: 'images',
    originalPrefix: 'originals',
  );

  factory CodexMedia.fromJson(Map<String, dynamic> j) => CodexMedia(
    baseUrl: j['baseUrl'] is String ? j['baseUrl'] as String : fallback.baseUrl,
    imagePrefix: j['imagePrefix'] is String
        ? j['imagePrefix'] as String
        : fallback.imagePrefix,
    originalPrefix: j['originalPrefix'] is String
        ? j['originalPrefix'] as String
        : fallback.originalPrefix,
  );
}

/// 法典类型:codex=成品词条图鉴;string=画师串/画风串词典;composition=构图 /
/// 服装 / 场景(原站 2026-08-31 从画风串里拆出来的);pack=合集包。
/// app 侧几类渲染一致(都是「标题 + 提示词 + 例图」),仅作角标区分。
enum CodexType {
  codex,
  string,
  composition,
  pack,
  unknown;

  static CodexType parse(Object? v) => switch (v) {
    'codex' => CodexType.codex,
    'string' => CodexType.string,
    'composition' => CodexType.composition,
    'pack' => CodexType.pack,
    _ => CodexType.unknown,
  };

  String get label => switch (this) {
    CodexType.codex => l10nNow.sectionCodex,
    CodexType.string => l10nNow.codexTypeDict,
    CodexType.composition => l10nNow.codexTypeComposition,
    CodexType.pack => l10nNow.codexTypePack,
    CodexType.unknown => '',
  };
}

/// 贡献者(作者/配图提供等),attribution 展示用。
typedef CodexContributor = ({String name, String role});

/// 外链(数据来源、教程等)。
typedef CodexLink = ({String label, String url});

/// 法典元信息(codexes.json 的一条)。
class CodexMeta {
  const CodexMeta({
    required this.id,
    required this.type,
    required this.title,
    this.version = '',
    this.author = '',
    this.source = '',
    this.entryCount = 0,
    this.imagedCount = 0,
    this.nsfw = false,
    this.selectorTitle,
    this.newFilterLabel,
    this.aliases = const [],
    this.dataUrl,
    this.fallbackDataUrl,
    this.fallbackVersion,
    this.assetBaseUrl,
    this.assetPathMode,
    this.contributors = const [],
    this.links = const [],
    this.raw = const {},
  });

  /// 索引里的原始 JSON(传进 isolate 做合并用;const 构造默认空)。
  final Map<String, dynamic> raw;

  final String id;
  final CodexType type;
  final String title;
  final String version;
  final String author;
  final String source;
  final int entryCount;
  final int imagedCount;

  /// 成人内容:app 侧默认隐藏,过年龄门后才列出。
  final bool nsfw;

  /// 选择器里的短标题(没有则用 [title])。
  final String? selectorTitle;

  /// 「本次更新」筛选的标签文案(如「本次7.15更新」)。
  final String? newFilterLabel;
  final List<String> aliases;

  /// 数据 JSON 的绝对地址(仅外部数据源的法典有;默认走 `data/<id>.json`)。
  final String? dataUrl;

  /// [dataUrl] 拉不到时的兜底(站内相对路径,如 data/mengshen_r18.json)。
  final String? fallbackDataUrl;
  final String? fallbackVersion;

  /// 每部自带图床根(relative 模式必有)。
  final String? assetBaseUrl;

  /// 'relative' = 图路径已是相对完整路径,直接挂 [assetBaseUrl];
  /// 其余(null)= 默认模式,图床/images/法典id/文件名。
  final String? assetPathMode;

  final List<CodexContributor> contributors;
  final List<CodexLink> links;

  String get displayTitle =>
      selectorTitle?.isNotEmpty == true ? selectorTitle! : title;

  bool get isRelativeAssets => assetPathMode == 'relative';

  factory CodexMeta.fromJson(Map<String, dynamic> j) {
    List<String> strs(Object? v) => v is List
        ? [
            for (final e in v)
              if (e is String) e,
          ]
        : const [];
    return CodexMeta(
      id: j['id'] is String ? j['id'] as String : '',
      type: CodexType.parse(j['type']),
      title: j['title'] is String ? j['title'] as String : '',
      version: j['version'] is String ? j['version'] as String : '',
      author: j['author'] is String ? j['author'] as String : '',
      source: j['source'] is String ? j['source'] as String : '',
      entryCount: (j['entryCount'] as num?)?.toInt() ?? 0,
      imagedCount: (j['imagedCount'] as num?)?.toInt() ?? 0,
      nsfw: j['nsfw'] == true,
      selectorTitle: j['selectorTitle'] is String
          ? j['selectorTitle'] as String
          : null,
      newFilterLabel: j['newFilterLabel'] is String
          ? j['newFilterLabel'] as String
          : null,
      aliases: strs(j['aliases']),
      dataUrl: j['dataUrl'] is String ? j['dataUrl'] as String : null,
      fallbackDataUrl: j['fallbackDataUrl'] is String
          ? j['fallbackDataUrl'] as String
          : null,
      fallbackVersion: j['fallbackVersion'] is String
          ? j['fallbackVersion'] as String
          : null,
      assetBaseUrl: j['assetBaseUrl'] is String
          ? j['assetBaseUrl'] as String
          : null,
      assetPathMode: j['assetPathMode'] is String
          ? j['assetPathMode'] as String
          : null,
      contributors: j['contributors'] is List
          ? [
              for (final c in j['contributors'] as List)
                if (c is Map<String, dynamic>)
                  (
                    name: c['name'] is String ? c['name'] as String : '',
                    role: c['role'] is String ? c['role'] as String : '',
                  ),
            ]
          : const [],
      links: j['links'] is List
          ? [
              for (final c in j['links'] as List)
                if (c is Map<String, dynamic> && c['url'] is String)
                  (
                    label: c['label'] is String
                        ? c['label'] as String
                        : c['url'] as String,
                    url: c['url'] as String,
                  ),
            ]
          : const [],
      raw: j,
    );
  }
}

/// 词条的一张图(codex 多图词条用)。
class CodexImage {
  const CodexImage(this.path, this.original);
  final String path;
  final String? original;
}

/// 词条自带的一个角色段(数据源里的 `characterPrompts[]`)。
///
/// [label] 是原样的人读标签:`char1` / `char2` …,另有极少数 `char`(不带号)
/// 与 `char2-4`(一段管好几个角色)。全站计数:char1 8102、char2 4311、char3 653、
/// char4 103、char5 17、char6 4、char 2、char2-4 1 —— 所以按 1..6 处理够用,
/// 但解析必须容得下另两种,不能因为一个认不出的 label 就把这段丢了。
class CodexCharacter {
  const CodexCharacter(this.label, this.prompt);

  final String label;
  final String prompt;

  /// 展示名:`char1` → 角色 1;`char2-4` → 角色 2-4;`char` → 角色。
  String get display {
    final m = RegExp(
      r'^char\s*(\d+(?:\s*-\s*\d+)?)$',
      caseSensitive: false,
    ).firstMatch(label.trim());
    return m == null
        ? label
        : l10nNow.charRangeLabel(m.group(1)!.replaceAll(' ', ''));
  }

  /// 这段管哪几个角色位(1 起)。`char2-4` → [2,3,4];`char` → [1];认不出 → 空。
  List<int> get slots {
    final m = RegExp(
      r'^char\s*(\d+)?(?:\s*-\s*(\d+))?$',
      caseSensitive: false,
    ).firstMatch(label.trim());
    if (m == null) return const [];
    final a = int.tryParse(m.group(1) ?? '') ?? 1; // `char` 不带号 = 第一个
    final b = int.tryParse(m.group(2) ?? '') ?? a;
    if (b < a || b - a > 8) return [a]; // 区间反了或离谱:只认起点
    return [for (var i = a; i <= b; i++) i];
  }
}

/// 法典词条:标题 + 成品提示词(NovelAI 权重语法)+ 例图 + 分类路径。
class CodexEntry {
  const CodexEntry({
    required this.id,
    required this.title,
    required this.tags,
    this.path = const [],
    this.image,
    this.original,
    this.imageWidth,
    this.imageHeight,
    this.assetRev,
    this.assetCodexId,
    this.isNew = false,
    this.images = const [],
    this.characters = const [],
  });

  final String id;
  final String title;

  /// 成品正向提示词(原样,含 `1.3::x::` / `{}` 等权重语法)。
  final String tags;

  /// 分类路径(对应法典的 tree),末级即所属子类。
  final List<String> path;

  final String? image;
  final String? original;
  final int? imageWidth;
  final int? imageHeight;

  /// 资源版本号:进图 URL 的 `?v=`,原图更新即换。
  final String? assetRev;

  /// 跨法典引用时图归属的法典 id(极少;默认用所属法典 id)。
  final String? assetCodexId;
  final bool isNew;
  final List<CodexImage> images;

  /// 词条自带的角色段。**数据源里这是与 [tags] 平级的独立字段**,不在 tags 里 ——
  /// 全站 8091 条带它,其中 401 条 tags 本身是空的(内容全在这儿)。
  /// 早先只读 tags,那些词条翻开就是一句话甚至一片空白。
  final List<CodexCharacter> characters;

  /// 给人看的完整内容:公共部分 + 各角色段,缺哪段就不占行。
  /// 展示与复制都走它 —— 只给 tags 会漏掉大半条目的主体。
  String get fullText => [
    if (tags.trim().isNotEmpty) tags.trim(),
    for (final c in characters)
      if (c.prompt.trim().isNotEmpty) '${c.display}\n${c.prompt.trim()}',
  ].join('\n\n');

  bool get hasImage =>
      images.isNotEmpty || (image != null && image!.isNotEmpty);

  /// 封面宽高比(无尺寸时给个竖图默认,避免瀑布流塌成 0 高)。
  double get aspect {
    final w = imageWidth, h = imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return 0.75;
    return w / h;
  }

  factory CodexEntry.fromJson(Map<String, dynamic> j) {
    final images = <CodexImage>[];
    if (j['images'] is List) {
      for (final im in j['images'] as List) {
        if (im is Map<String, dynamic> && im['path'] is String) {
          images.add(
            CodexImage(
              im['path'] as String,
              im['original'] is String ? im['original'] as String : null,
            ),
          );
        }
      }
    }
    return CodexEntry(
      id: j['id'] is String ? j['id'] as String : '',
      title: j['title'] is String ? j['title'] as String : '',
      tags: j['tags'] is String ? j['tags'] as String : '',
      path: j['path'] is List
          ? [
              for (final p in j['path'] as List)
                if (p is String) p,
            ]
          : const [],
      image: j['image'] is String ? j['image'] as String : null,
      original: j['original'] is String ? j['original'] as String : null,
      imageWidth: (j['imageWidth'] as num?)?.toInt(),
      imageHeight: (j['imageHeight'] as num?)?.toInt(),
      assetRev: j['assetRev'] is String ? j['assetRev'] as String : null,
      assetCodexId: j['assetCodexId'] is String
          ? j['assetCodexId'] as String
          : null,
      isNew: j['isNew'] == true,
      images: images,
      characters: [
        if (j['characterPrompts'] is List)
          for (final c in j['characterPrompts'] as List)
            if (c is Map &&
                c['prompt'] is String &&
                (c['prompt'] as String).trim().isNotEmpty)
              CodexCharacter(
                c['label'] is String ? c['label'] as String : '',
                c['prompt'] as String,
              ),
      ],
    );
  }

  CodexEntry copyWith({String? title, List<String>? path}) => CodexEntry(
    id: id,
    title: title ?? this.title,
    tags: tags,
    path: path ?? this.path,
    image: image,
    original: original,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    assetRev: assetRev,
    assetCodexId: assetCodexId,
    isNew: isNew,
    images: images,
    characters: characters,
  );

  /// 回写(收藏夹存词条快照用)。只落非空字段:收藏文件里几百条,
  /// 每条多带一串 null 白占体积。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'tags': tags,
    if (path.isNotEmpty) 'path': path,
    if (image != null) 'image': image,
    if (original != null) 'original': original,
    if (imageWidth != null) 'imageWidth': imageWidth,
    if (imageHeight != null) 'imageHeight': imageHeight,
    if (assetRev != null) 'assetRev': assetRev,
    if (assetCodexId != null) 'assetCodexId': assetCodexId,
    if (isNew) 'isNew': true,
    if (images.isNotEmpty)
      'images': [
        for (final im in images)
          {'path': im.path, if (im.original != null) 'original': im.original},
      ],
    // 收藏夹存的是快照:漏了这个,收藏过的多角色词条打开会缺主体
    if (characters.isNotEmpty)
      'characterPrompts': [
        for (final c in characters) {'label': c.label, 'prompt': c.prompt},
      ],
  };
}

/// 整部法典(元信息 + 词条 + 分类树)。
class CodexData {
  const CodexData({
    required this.meta,
    required this.entries,
    this.tree = const [],
    this.specimens = const {},
  });

  final CodexMeta meta;
  final List<CodexEntry> entries;

  /// 分类树(顶层节点;app 侧 v1 只用顶层做筛选 chip)。
  final List<CodexNode> tree;

  /// 按画风重排后的单画师词条:词条 id → 所属画师下标与例图优先级(小者优先)。
  /// 只有挂上画风数据的 v5 画师词典非空,见 `codex_artist_styles.dart`。
  final Map<String, ({int artist, int rank})> specimens;

  /// 每位画师只留一张卡(取 [list] 里优先级最高的例图,占该画师首次出现的位置);
  /// 其余词条原样保留。
  List<CodexEntry> onePerArtist(List<CodexEntry> list) {
    if (specimens.isEmpty) return list;
    final best = <int, CodexEntry>{};
    for (final e in list) {
      final s = specimens[e.id];
      if (s == null) continue;
      final cur = best[s.artist];
      if (cur == null || s.rank < specimens[cur.id]!.rank) best[s.artist] = e;
    }
    final seen = <int>{};
    final out = <CodexEntry>[];
    for (final e in list) {
      final s = specimens[e.id];
      if (s == null) {
        out.add(e);
      } else if (seen.add(s.artist)) {
        out.add(best[s.artist]!);
      }
    }
    return out;
  }

  /// 分类树:有 tree 用 tree;没有则从词条 path 首级合成扁平树(带计数),
  /// 让每部法典都能走同一套层级筛选。
  List<CodexNode> get effectiveTree {
    if (tree.isNotEmpty) return tree;
    final counts = <String, int>{};
    for (final e in entries) {
      final top = e.path.isNotEmpty ? e.path.first : '';
      if (top.isNotEmpty) counts[top] = (counts[top] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries) CodexNode(e.key, e.value, const []),
    ];
  }

  /// 顶层分类名(去重、保序),筛选 chip 用。
  List<String> get topCategories {
    final seen = <String>{};
    final out = <String>[];
    for (final n in tree) {
      if (n.name.isNotEmpty && seen.add(n.name)) out.add(n.name);
    }
    // tree 缺失时从词条 path 首级兜底
    if (out.isEmpty) {
      for (final e in entries) {
        final top = e.path.isNotEmpty ? e.path.first : '';
        if (top.isNotEmpty && seen.add(top)) out.add(top);
      }
    }
    return out;
  }

  /// 解析一份法典 JSON(顶层是 dict:meta 平铺 + entries/tree)。
  /// [indexMeta] 为索引里的元信息;JSON 内如带同名字段以 JSON 为准、
  /// 但外部数据源(dataUrl)的 JSON 可能缺 nsfw/assetBaseUrl,故索引兜底。
  factory CodexData.parse(Map<String, dynamic> j, {CodexMeta? indexMeta}) {
    final selfMeta = CodexMeta.fromJson(j);
    final meta = indexMeta == null
        ? selfMeta
        : _mergeMeta(indexMeta, j, selfMeta);
    return CodexData(
      meta: meta,
      entries: j['entries'] is List
          ? [
              for (final e in j['entries'] as List)
                if (e is Map<String, dynamic>) CodexEntry.fromJson(e),
            ]
          : const [],
      tree: CodexNode.parseList(j['tree']),
    );
  }

  /// 以索引 meta 为底,JSON 里出现的字段覆盖(外部源缺的字段保索引值:
  /// 尤其 nsfw / assetBaseUrl / assetPathMode 决定门控与出图,不能被覆没)。
  static CodexMeta _mergeMeta(
    CodexMeta idx,
    Map<String, dynamic> j,
    CodexMeta self,
  ) => CodexMeta(
    id: idx.id,
    type: self.type != CodexType.unknown ? self.type : idx.type,
    title: self.title.isNotEmpty ? self.title : idx.title,
    version: self.version.isNotEmpty ? self.version : idx.version,
    author: self.author.isNotEmpty ? self.author : idx.author,
    source: self.source.isNotEmpty ? self.source : idx.source,
    entryCount: self.entryCount != 0 ? self.entryCount : idx.entryCount,
    imagedCount: self.imagedCount != 0 ? self.imagedCount : idx.imagedCount,
    nsfw: idx.nsfw || j['nsfw'] == true,
    selectorTitle: idx.selectorTitle ?? self.selectorTitle,
    newFilterLabel: idx.newFilterLabel ?? self.newFilterLabel,
    aliases: idx.aliases.isNotEmpty ? idx.aliases : self.aliases,
    dataUrl: idx.dataUrl ?? self.dataUrl,
    fallbackDataUrl: idx.fallbackDataUrl ?? self.fallbackDataUrl,
    fallbackVersion: idx.fallbackVersion ?? self.fallbackVersion,
    assetBaseUrl: idx.assetBaseUrl ?? self.assetBaseUrl,
    assetPathMode: idx.assetPathMode ?? self.assetPathMode,
    contributors: idx.contributors.isNotEmpty
        ? idx.contributors
        : self.contributors,
    links: idx.links.isNotEmpty ? idx.links : self.links,
  );
}

/// 分类树节点。
class CodexNode {
  const CodexNode(this.name, this.count, this.children);
  final String name;
  final int count;
  final List<CodexNode> children;

  static List<CodexNode> parseList(Object? v) => v is List
      ? [
          for (final n in v)
            if (n is Map<String, dynamic>)
              CodexNode(
                n['name'] is String ? n['name'] as String : '',
                (n['count'] as num?)?.toInt() ?? 0,
                parseList(n['children']),
              ),
        ]
      : const [];
}

/// 词条路径是否落在某分类路径下:选中路径是词条 path 的前缀即命中
/// (空 [catPath] = 全部;选父级 = 含其所有子级)。
bool codexPathUnder(List<String> entryPath, List<String> catPath) {
  if (catPath.isEmpty) return true;
  if (entryPath.length < catPath.length) return false;
  for (var i = 0; i < catPath.length; i++) {
    if (entryPath[i] != catPath[i]) return false;
  }
  return true;
}

// ---- 图片 URL 构造(照搬原站 media.js;两模式) ----

bool _isAbsolute(String u) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(u) ||
    u.startsWith('data:');

/// JS encodeURIComponent 语义:Dart 的 Uri.encodeComponent 与其一致
/// (都不编码 A-Za-z0-9-_.!~*'())。默认模式里再把 %2F 还原成 /。
String _encPart(String s) => Uri.encodeComponent(s).replaceAll('%2F', '/');

String _encodeAssetPath(String p) =>
    p.split('/').map(Uri.encodeComponent).join('/');

String _withRev(String url, CodexEntry e) {
  final rev = e.assetRev;
  if (rev == null || rev.isEmpty) return url;
  return '$url${url.contains('?') ? '&' : '?'}v=${Uri.encodeComponent(rev)}';
}

/// 相对图床根:去尾部斜杠。
String? _mediaPath(
  CodexMeta codex,
  CodexEntry e,
  CodexMedia media, {
  required bool original,
}) {
  final file = original ? e.original : e.image;
  if (file == null || file.isEmpty) return null;
  if (_isAbsolute(file)) return file;
  if (codex.isRelativeAssets) return _encodeAssetPath(file);
  final prefix = original ? media.originalPrefix : media.imagePrefix;
  final assetCodexId = e.assetCodexId ?? codex.id;
  return [prefix, assetCodexId, file].map(_encPart).join('/');
}

/// 词条封面(或原图)的完整 URL;无图返回 null。
String? codexImageUrl(
  CodexMeta codex,
  CodexEntry e,
  CodexMedia media, {
  bool original = false,
}) {
  final path = _mediaPath(codex, e, media, original: original);
  if (path == null || path.isEmpty) return null;
  if (_isAbsolute(path)) return _withRev(path, e);
  if (codex.isRelativeAssets) {
    final base = codex.assetBaseUrl;
    return _withRev(base != null && base.isNotEmpty ? '$base/$path' : path, e);
  }
  final base = media.baseUrl.replaceAll(RegExp(r'/+$'), '');
  return _withRev(base.isNotEmpty ? '$base/$path' : path, e);
}

/// 多图词条里第 [i] 张的 URL(详情弹窗翻图用)。越界或无图返回 null。
String? codexImageItemUrl(
  CodexMeta codex,
  CodexEntry e,
  CodexMedia media,
  int i, {
  bool original = false,
}) {
  final items = e.images.isNotEmpty
      ? e.images
      : (e.image != null
            ? [CodexImage(e.image!, e.original)]
            : const <CodexImage>[]);
  if (i < 0 || i >= items.length) return null;
  final it = items[i];
  final file = original ? (it.original ?? it.path) : it.path;
  // 复用封面构造:把该图当作单图词条塞进去
  return codexImageUrl(
    codex,
    CodexEntry(
      id: e.id,
      title: e.title,
      tags: e.tags,
      image: file,
      original: it.original ?? it.path,
      assetRev: e.assetRev,
      assetCodexId: e.assetCodexId,
    ),
    media,
    original: original,
  );
}

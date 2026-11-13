/// 画风条目的「适用模型」目录 —— 只用于灵感页里的分类 / 筛选 / 角标展示,
/// **不参与出图**:预览图生成、提示词注入这些链路一律不读它。
///
/// 两层粒度,各管各的:
///   标注(编辑页多选)  按具体模型 —— 用户自己知道这串是在哪个档位上调出来的
///   筛选 / 角标        按分档([ArtistModelGroup]) —— 找东西不需要那么细
/// 分档是模型自带的属性,不是另一份名单,所以上新模型只改 [kArtistModels] 一行。
///
/// ⚠ [ArtistModelDef.id] 必须与 web `tag-manager/artistModels.ts` **逐字一致** ——
/// 这个字段会随画师串上公共库、也会进云备份,两端对不上就等于互相看不懂。
/// 展示名用 app 自己的叫法(与出图侧下拉一致),那个不参与互通。
library;

import '../../l10n/l10n.dart';

enum ArtistModelGroup { naiV5, naiV4, anima, krea }

extension ArtistModelGroupX on ArtistModelGroup {
  /// 角标上的短名。
  String get label => switch (this) {
    ArtistModelGroup.naiV5 => 'NAI 5',
    ArtistModelGroup.naiV4 => 'NAI 4',
    ArtistModelGroup.anima => 'Anima',
    ArtistModelGroup.krea => 'Krea',
  };

  /// 筛选行里的名字,可以写得长一点。
  String get filterLabel => switch (this) {
    ArtistModelGroup.naiV5 => 'NAI 5',
    ArtistModelGroup.naiV4 => 'NAI 4 / 4.5',
    ArtistModelGroup.anima => 'Anima',
    ArtistModelGroup.krea => 'Krea 2',
  };
}

class ArtistModelDef {
  const ArtistModelDef(this.id, this.name, this.short, this.group);

  /// 与 web 互通的稳定 id。
  final String id;

  /// 完整展示名(与出图侧下拉一致)。
  final String name;

  /// 编辑页多选里的短名。
  final String short;
  final ArtistModelGroup group;
}

/// 上新模型时这里补一行,否则新模型在灵感页标不了。
const kArtistModels = <ArtistModelDef>[
  ArtistModelDef('v5-full', 'NAI 5.0 Full', 'V5 Full', ArtistModelGroup.naiV5),
  ArtistModelDef(
    'v5-curated',
    'NAI 5.0 Curated',
    'V5 Curated',
    ArtistModelGroup.naiV5,
  ),
  ArtistModelDef(
    'v4.5-full',
    'NAI 4.5 Full',
    'V4.5 Full',
    ArtistModelGroup.naiV4,
  ),
  ArtistModelDef(
    'v4.5-curated',
    'NAI 4.5 Curated',
    'V4.5 Curated',
    ArtistModelGroup.naiV4,
  ),
  ArtistModelDef('v4-full', 'NAI 4.0 Full', 'V4 Full', ArtistModelGroup.naiV4),
  ArtistModelDef(
    'v4-curated-preview',
    'NAI 4.0 Curated',
    'V4 Curated',
    ArtistModelGroup.naiV4,
  ),
  ArtistModelDef('anima-turbo', 'Anima Turbo', 'Turbo', ArtistModelGroup.anima),
  ArtistModelDef(
    'anima-aesthetic',
    'Anima Aesthetic',
    'Aesthetic',
    ArtistModelGroup.anima,
  ),
  ArtistModelDef('anima-base', 'Anima Base', 'Base', ArtistModelGroup.anima),
  ArtistModelDef(
    'anima-beta',
    'Anima 2.9B Beta',
    '2.9B Beta',
    ArtistModelGroup.anima,
  ),
  ArtistModelDef('krea-turbo', 'Krea 2 Turbo', 'Turbo', ArtistModelGroup.krea),
  ArtistModelDef('krea-raw', 'Krea 2 Raw', 'Raw', ArtistModelGroup.krea),
];

/// 一条画风没标注任何模型时的说法。老数据(没有 models 字段)天然落在这一档。
String get kGenericModelLabel => l10nNow.genericModel;

/// 筛选里「只看通用串」的哨兵,与真实分档 id 不会重名。
const kGenericModelFilter = '__generic__';

final _byId = {for (final m in kArtistModels) m.id: m};

ArtistModelDef? findArtistModel(String id) => _byId[id];

/// 取展示名。目录里没有的 id(模型下线 / 数据来自更新的客户端)**原样回显** ——
/// 别把用户标过的东西吞掉。
String artistModelName(String id) => _byId[id]?.name ?? id;

String artistModelShort(String id) => _byId[id]?.short ?? id;

bool isGenericModels(List<String>? models) => models == null || models.isEmpty;

/// 按 [kArtistModels] 的顺序归一化:丢空串 + 去重 + 未知 id 排末尾保序。
List<String> normalizeArtistModels(List<String>? models) {
  if (models == null || models.isEmpty) return const [];
  final seen = <String>{};
  final known = <String>[];
  final unknown = <String>[];
  for (final raw in models) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    (_byId.containsKey(id) ? known : unknown).add(id);
  }
  known.sort(
    (a, b) => kArtistModels
        .indexWhere((m) => m.id == a)
        .compareTo(kArtistModels.indexWhere((m) => m.id == b)),
  );
  return [...known, ...unknown];
}

/// 归并到分档,给角标用:标了 V5 Full + V5 Curated 只出一个「NAI 5」。
List<ArtistModelGroup> artistModelGroups(List<String>? models) => [
  for (final g in ArtistModelGroup.values)
    if ((models ?? const []).any((id) => _byId[id]?.group == g)) g,
];

/// 筛选判定。三类互斥,**通用是独立的一类**(标了别的档的串不该混进「通用」):
///   null                  → 全部
///   [kGenericModelFilter] → 只看没标注的通用串
///   分档 name             → 只看标了这一档的
bool matchesArtistModelFilter(List<String>? models, String? filter) {
  if (filter == null) return true;
  if (filter == kGenericModelFilter) return isGenericModels(models);
  return (models ?? const []).any((id) => _byId[id]?.group.name == filter);
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_stores.dart';
import '../../features/gallery/gallery_date_filter.dart';

/// 零散界面偏好的统一出处:那些「选了一次就该一直是那样」、但又不值得各开一份
/// 存储的小状态(页签、时间范围、排序、筛选)。
///
/// 为什么合成一份而不是各存各的:它们的共同点是**每一项都只有一两个字节**,
/// 各开一个 key 就是六次读盘、六个 Notifier、六处同样的样板;凑一起之后加一项
/// 只要动这个类。真正成体系的设置(生成/编辑器/存图/存储)仍各自独立,别往这儿塞。
///
/// **同步取值**(见 [UiPrefsNotifier.build]):PrefsStore 的内存表在
/// `AppStores.open` 时就装满了,所以这里没有「首帧还没读出来」那一档 ——
/// 拿 AsyncNotifier 的 `.value` 在首读期取值会把「还没读出来」当成「没存过」,
/// 界面就会先闪一帧默认值,那是放大面板记忆坏掉的原因,别再来一次。
class UiPrefs {
  const UiPrefs({
    this.statsRange = 'week',
    this.toolsTab = 0,
    this.genSettingsTab = 'nai',
    this.completionByHeat = true,
    this.galleryDaysFilter = 0,
    this.galleryDateFilter,
    this.galleryBrowseAlbum = '',
    this.gallerySaveAlbum = '',
    this.galleryGroupBy = 'day',
    this.galleryColumns = 3,
    this.inspirationColumns = const {},
  });

  /// 统计页的时间范围(`today` / `week` / `month`)。**统计页与平台页共用一个**
  /// —— 两页问的是同一件事:我习惯看多长时间。
  final String statsRange;

  /// 工具页页签下标。
  final int toolsTab;

  /// 生成设置页的通道页签(`GenProvider` 的名字)。
  final String genSettingsTab;

  /// 补全面板排序:true=热度 / false=字母。
  final bool completionByHeat;

  /// 图库网格的时间筛选(0=全部 / 1=今天 / 7=近 7 天 / 30=近 30 天)。
  final int galleryDaysFilter;
  final GalleryDateFilter? galleryDateFilter;
  GalleryDateFilter get dateFilter =>
      galleryDateFilter ?? GalleryDateFilter.legacy(galleryDaysFilter);

  /// 空字符串代表全部作品，两个选择互相独立。
  final String galleryBrowseAlbum;
  final String gallerySaveAlbum;

  /// 图库网格的分组维度(`GalleryGroupBy` 的 name:`day` / `character` / `style`)。
  /// 存字符串而不是下标 —— 将来插一个维度不会把老用户的选择挪到别的档去。
  final String galleryGroupBy;

  /// 图库网格的列数(双指捏合调,2~5)。与分组维度共用一个值 ——
  /// 系统相册也只有一个缩放档,分开记两份只会让人捏完切个分组又变回去。
  final int galleryColumns;

  /// 灵感页网格的列数(双指捏合调),**每个分类记各的**,键是 `TagCategory` 的
  /// name,法典是 `codex`;缺键 = 那一类没捏过,用页面的默认列数。
  ///
  /// 与图库只记一份相反:四类卡片形状不一样(角色竖、画风横、其余方),同一个
  /// 列数在各类下的疏密差得很远。各类的上下界跟卡片形状走,由灵感页夹。
  final Map<String, int> inspirationColumns;

  UiPrefs copyWith({
    String? statsRange,
    int? toolsTab,
    String? genSettingsTab,
    bool? completionByHeat,
    int? galleryDaysFilter,
    GalleryDateFilter? galleryDateFilter,
    String? galleryBrowseAlbum,
    String? gallerySaveAlbum,
    String? galleryGroupBy,
    int? galleryColumns,
    Map<String, int>? inspirationColumns,
  }) => UiPrefs(
    statsRange: statsRange ?? this.statsRange,
    toolsTab: toolsTab ?? this.toolsTab,
    genSettingsTab: genSettingsTab ?? this.genSettingsTab,
    completionByHeat: completionByHeat ?? this.completionByHeat,
    galleryDaysFilter: galleryDaysFilter ?? this.galleryDaysFilter,
    galleryDateFilter:
        galleryDateFilter ??
        (galleryDaysFilter != null
            ? GalleryDateFilter.legacy(galleryDaysFilter)
            : this.galleryDateFilter),
    galleryBrowseAlbum: galleryBrowseAlbum ?? this.galleryBrowseAlbum,
    gallerySaveAlbum: gallerySaveAlbum ?? this.gallerySaveAlbum,
    galleryGroupBy: galleryGroupBy ?? this.galleryGroupBy,
    galleryColumns: galleryColumns ?? this.galleryColumns,
    inspirationColumns: inspirationColumns ?? this.inspirationColumns,
  );

  Map<String, dynamic> toJson() => {
    'statsRange': statsRange,
    'toolsTab': toolsTab,
    'genSettingsTab': genSettingsTab,
    'completionByHeat': completionByHeat,
    'galleryDaysFilter': galleryDaysFilter,
    'galleryDateFilter': dateFilter.toJson(),
    'galleryBrowseAlbum': galleryBrowseAlbum,
    'gallerySaveAlbum': gallerySaveAlbum,
    'galleryGroupBy': galleryGroupBy,
    'galleryColumns': galleryColumns,
    'inspirationColumns': inspirationColumns,
  };

  /// 每一项各自兜底:某一项是垃圾值不该连累其余项(整份丢掉的话,用户会看到
  /// 「所有偏好一起被重置」,比单项回默认难查得多)。
  factory UiPrefs.fromJson(Map<String, dynamic> j) => UiPrefs(
    statsRange: const {'today', 'week', 'month'}.contains(j['statsRange'])
        ? j['statsRange'] as String
        : 'week',
    // `as num?` 会在存档里是字符串时**抛异常** —— 而 fromJson 整体被 try 包着,
    // 抛了就是「所有偏好一起被重置」,恰恰是上面那句注释要避免的。用 is 判型。
    toolsTab: j['toolsTab'] is num
        ? (j['toolsTab'] as num).toInt().clamp(0, 9)
        : 0,
    genSettingsTab: j['genSettingsTab'] is String
        ? j['genSettingsTab'] as String
        : 'nai',
    completionByHeat: j['completionByHeat'] is bool
        ? j['completionByHeat'] as bool
        : true,
    galleryDaysFilter: const {0, 1, 7, 30}.contains(j['galleryDaysFilter'])
        ? j['galleryDaysFilter'] as int
        : 0,
    galleryDateFilter: GalleryDateFilter.fromJson(
      j['galleryDateFilter'],
      legacyDays: j['galleryDaysFilter'] is int
          ? j['galleryDaysFilter'] as int
          : 0,
    ),
    galleryBrowseAlbum: j['galleryBrowseAlbum'] is String
        ? j['galleryBrowseAlbum'] as String
        : '',
    gallerySaveAlbum: j['gallerySaveAlbum'] is String
        ? j['gallerySaveAlbum'] as String
        : '',
    galleryGroupBy: j['galleryGroupBy'] is String
        ? j['galleryGroupBy'] as String
        : 'day',
    galleryColumns: j['galleryColumns'] is num
        ? (j['galleryColumns'] as num).toInt().clamp(
            kGalleryMinColumns,
            kGalleryMaxColumns,
          )
        : 3,
    // 逐键判型:某一类存坏了只丢那一类
    inspirationColumns: {
      if (j['inspirationColumns'] case final Map m)
        for (final e in m.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toInt(),
    },
  );
}

/// 图库网格的列数上下界。1 列在 82% 高的弹层里没意义,6 列名字全是省略号。
const kGalleryMinColumns = 2;
const kGalleryMaxColumns = 5;

const _key = 'ui_prefs';

final uiPrefsProvider = NotifierProvider<UiPrefsNotifier, UiPrefs>(
  UiPrefsNotifier.new,
);

class UiPrefsNotifier extends Notifier<UiPrefs> {
  @override
  UiPrefs build() {
    try {
      final raw = ref.read(prefsStoreProvider).get(_key);
      if (raw == null || raw.isEmpty) return const UiPrefs();
      return UiPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UiPrefs(); // 损坏 / 无 AppStores(测试)按默认
    }
  }

  /// 改一项并落盘。这些都是**点一下变一次**的离散选择(页签、档位、排序),
  /// 不是滑杆,所以每次都写没有性能问题。
  void patch(UiPrefs Function(UiPrefs) change) {
    final next = change(state);
    state = next;
    try {
      ref
          .read(prefsStoreProvider)
          .write(key: _key, value: jsonEncode(next.toJson()));
    } catch (_) {} // 写失败只影响下次恢复
  }
}

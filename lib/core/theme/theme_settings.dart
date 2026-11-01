import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../store/app_stores.dart';
import '../store/prefs_store.dart';
import 'app_theme.dart';

/// 主题色档位。
class ThemeSeed {
  const ThemeSeed(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;
}

// 按色环排列(新增档位只管加,持久化按 key 不受顺序影响)。
const themeSeeds = <ThemeSeed>[
  ThemeSeed('gold', '金', Color(0xFFD4A72C)),
  ThemeSeed('rose', '粉', Color(0xFFD81B60)),
  ThemeSeed('violet', '紫', Color(0xFF6750A4)),
  ThemeSeed('sky', '浅蓝', Color(0xFF4FA3E3)),
  ThemeSeed('teal', '青', Color(0xFF00897B)),
];

/// 下架的档位就近归到留下的那档。
const _retiredSeeds = {
  'orange': 'gold',
  'brown': 'gold',
  'red': 'rose',
  'plum': 'violet',
  'indigo': 'sky',
  'grey': 'sky',
  'green': 'teal',
};

/// 默认主题色(未选过时的档位)。
const kDefaultSeedKey = 'sky';

/// 浮卡主题:固定配色 + 组件外观,不走种子取色。和种子档位共用
/// [ThemeSettings.seedKey]:蓝色是 `float`,其余 `float:<档位>`。
const kFloatThemeKey = 'float';

String floatThemeKey(FloatAccent a) =>
    a == kFloatBlue ? kFloatThemeKey : '$kFloatThemeKey:${a.key}';

FloatAccent? _floatAccentOf(String key) {
  for (final a in floatAccents) {
    if (floatThemeKey(a) == key) return a;
  }
  return null;
}

/// 认得的档位原样留,下架的就近归档,其余回退默认。
String _seedKeyOf(Object? v) {
  if (v is! String) return kDefaultSeedKey;
  if (_floatAccentOf(v) != null || themeSeeds.any((s) => s.key == v)) return v;
  return _retiredSeeds[v] ?? kDefaultSeedKey;
}

/// 外观与触感设置(持久化):深浅模式 + 主题色 + 振动总开关 + 版式偏好。
class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemeMode.light,
    this.seedKey = kDefaultSeedKey,
    this.haptics = true,
    this.showAssistant = true,
    this.compactCharCards = false,
    this.systemPicker,
    this.language = '',
  });

  final ThemeMode mode;
  final String seedKey;

  /// 关掉后 app 内所有振动静默(实际拦在 [Haptics])。
  final bool haptics;

  /// 底栏显不显示「AI」那一格。关掉只是**藏起入口**,助手本身照旧 ——
  /// 已经导入过的改动、归档的会话都不受影响,开回来还在。
  ///
  /// 放在主题设置里是因为它和深浅模式一样要在 ProviderScope 建立之前就读到
  /// (底栏首帧就得知道画几格),而这份是全 app 唯一一个同步加载的偏好。
  final bool showAssistant;

  /// 创作页角色卡去掉头像预览,只留名称、位置与提示词。
  final bool compactCharCards;

  /// 选图走系统选择器(true)还是应用内图库(false);null = 没选过,按机型
  /// 默认(见 `image_pick.dart` 的 `_inAppGallery`)。仅 Android 生效。
  final bool? systemPicker;

  /// 界面语言:`zh` / `en` / `ja`;空串 = 跟随系统。
  final String language;

  Locale? get locale => language.isEmpty ? null : Locale(language);

  ThemeSeed get seed => themeSeeds.firstWhere(
    (s) => s.key == seedKey,
    orElse: () => themeSeeds.firstWhere((s) => s.key == kDefaultSeedKey),
  );

  /// 选的浮卡档位;种子档位为 null。
  FloatAccent? get floatAccent => _floatAccentOf(seedKey);

  /// 选的是浮卡主题,不是种子档位。
  bool get float => floatAccent != null;

  ThemeSettings copyWith({
    ThemeMode? mode,
    String? seedKey,
    bool? haptics,
    bool? showAssistant,
    bool? compactCharCards,
    bool? systemPicker,
    String? language,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    seedKey: seedKey ?? this.seedKey,
    haptics: haptics ?? this.haptics,
    showAssistant: showAssistant ?? this.showAssistant,
    compactCharCards: compactCharCards ?? this.compactCharCards,
    systemPicker: systemPicker ?? this.systemPicker,
    language: language ?? this.language,
  );

  /// 脏数据(旧版本/早先那档深蓝等)回退默认。
  factory ThemeSettings.fromJson(Map<String, dynamic> j) => ThemeSettings(
    mode: ThemeMode.values.asNameMap()[j['mode']] ?? ThemeMode.light,
    seedKey: _seedKeyOf(j['seed']),
    haptics: j['haptics'] != false,
    showAssistant: j['showAssistant'] != false,
    compactCharCards: j['compactCharCards'] == true,
    systemPicker: switch (j['systemPicker']) {
      final bool v => v,
      _ => null,
    },
    language: switch (j['language']) {
      final String v when kSupportedLocales.any((l) => l.languageCode == v) =>
        v,
      _ => '',
    },
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'seed': seedKey,
    'haptics': haptics,
    'showAssistant': showAssistant,
    'compactCharCards': compactCharCards,
    'systemPicker': ?systemPicker,
    if (language.isNotEmpty) 'language': language,
  };

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.mode == mode &&
      other.seedKey == seedKey &&
      other.haptics == haptics &&
      other.showAssistant == showAssistant &&
      other.compactCharCards == compactCharCards &&
      other.systemPicker == systemPicker &&
      other.language == language;

  @override
  int get hashCode => Object.hash(
    mode,
    seedKey,
    haptics,
    showAssistant,
    compactCharCards,
    systemPicker,
    language,
  );
}

const _key = 'theme_settings';

/// 启动时预读的初始值(main 注入,首帧即为用户配色,不闪变)。
final themeInitProvider = Provider<ThemeSettings>((_) => const ThemeSettings());

/// 首帧前的预读。`main()` 在 ProviderScope 之前调用,拿不到 ref,所以直接
/// 收 [PrefsStore] —— 它此时已随 `AppStores.open()` 一次性读进内存,
/// 这里**不再产生任何 I/O**(此前是第二次读 secure storage,要解 Keystore)。
ThemeSettings loadThemeSettings(PrefsStore prefs) {
  try {
    final raw = prefs.get(_key);
    if (raw == null || raw.isEmpty) return const ThemeSettings();
    return ThemeSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const ThemeSettings();
  }
}

final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
      ThemeSettingsNotifier.new,
    );

class ThemeSettingsNotifier extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() => ref.watch(themeInitProvider);

  /// 先改状态(全局即时换肤),再尽力持久化。
  void patch(ThemeSettings Function(ThemeSettings) change) {
    state = change(state);
    _persist(state);
  }

  Future<void> _persist(ThemeSettings s) async {
    try {
      await ref
          .read(prefsStoreProvider)
          .write(key: _key, value: jsonEncode(s.toJson()));
    } catch (_) {}
  }
}

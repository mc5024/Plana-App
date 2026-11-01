import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/core/theme/theme_settings.dart';

void main() {
  test('外观设置 json 回环', () {
    const s = ThemeSettings(mode: ThemeMode.dark, seedKey: 'teal');
    expect(ThemeSettings.fromJson(s.toJson()), s);
  });

  test('脏数据回退默认(未知模式/未知色/类型错)', () {
    expect(
      ThemeSettings.fromJson({'mode': 'neon', 'seed': 'plaid'}),
      const ThemeSettings(),
    );
    expect(
      ThemeSettings.fromJson({'mode': 3, 'seed': 7}),
      const ThemeSettings(),
    );
    expect(ThemeSettings.fromJson({}), const ThemeSettings());
  });

  test('seed 找不到档位时回退默认档(不是列表第一个)', () {
    // 第一个是「金」,回退到那儿等于用户随便点一下就换了个不相干的色。
    expect(const ThemeSettings(seedKey: 'nope').seed.key, kDefaultSeedKey);
  });

  test('浮卡主题存取回环', () {
    const s = ThemeSettings(seedKey: kFloatThemeKey);
    expect(s.float, isTrue);
    expect(ThemeSettings.fromJson(s.toJson()).seedKey, kFloatThemeKey);
    expect(const ThemeSettings(seedKey: 'teal').float, isFalse);
  });

  test('浮卡各档存取回环;旧的 float 键读成蓝色', () {
    for (final a in floatAccents) {
      final s = ThemeSettings(seedKey: floatThemeKey(a));
      expect(s.float, isTrue);
      expect(s.floatAccent, a);
      expect(ThemeSettings.fromJson(s.toJson()).floatAccent, a);
    }
    expect(ThemeSettings.fromJson({'seed': 'float'}).floatAccent, kFloatBlue);
    expect(
      ThemeSettings.fromJson({'seed': 'float:neon'}).seedKey,
      kDefaultSeedKey,
    );
  });

  test('浮卡各档主色按亮暗取', () {
    for (final a in floatAccents) {
      expect(AppTheme.float(Brightness.light, a).colorScheme.primary, a.light);
      expect(AppTheme.float(Brightness.dark, a).colorScheme.primary, a.dark);
      expect(
        AppTheme.float(Brightness.dark, a).colorScheme.onPrimary,
        a.onDark,
      );
    }
  });

  test('浮卡深色底:蓝色是原夜空,其余各带色调', () {
    final night = AppTheme.float(Brightness.dark).colorScheme.surface;
    expect(night, const Color(0xFF0B1220));
    final others = {
      for (final a in floatAccents)
        if (a != kFloatBlue)
          AppTheme.float(Brightness.dark, a).colorScheme.surface,
    };
    expect(others, hasLength(floatAccents.length - 1));
    expect(others, isNot(contains(night)));
  });

  test('浮卡蓝色的第三色(点数胶囊的粉)与旧版浅蓝档一致', () {
    for (final b in Brightness.values) {
      final old = (b == Brightness.light ? AppTheme.light() : AppTheme.dark())
          .colorScheme;
      final now = AppTheme.float(b).colorScheme;
      expect(now.tertiaryContainer, old.tertiaryContainer);
      expect(now.onTertiaryContainer, old.onTertiaryContainer);
      expect(now.tertiary, old.tertiary);
    }
  });

  test('下架的种子档就近归档', () {
    expect(ThemeSettings.fromJson({'seed': 'orange'}).seedKey, 'gold');
    expect(ThemeSettings.fromJson({'seed': 'green'}).seedKey, 'teal');
    expect(ThemeSettings.fromJson({'seed': 'indigo'}).seedKey, 'sky');
  });

  test('下架的档位(旧版深蓝)按脏数据回退', () {
    expect(themeSeeds.any((s) => s.key == 'blue'), isFalse);
    expect(
      ThemeSettings.fromJson({'mode': 'dark', 'seed': 'blue'}).seedKey,
      kDefaultSeedKey,
    );
  });

  test('振动开关:默认开,缺键的老存档也按开', () {
    expect(const ThemeSettings().haptics, isTrue);
    expect(ThemeSettings.fromJson({'mode': 'dark'}).haptics, isTrue);
    const off = ThemeSettings(haptics: false);
    expect(ThemeSettings.fromJson(off.toJson()).haptics, isFalse);
  });

  test('紧凑角色卡:默认关,缺键的老存档也按关', () {
    expect(const ThemeSettings().compactCharCards, isFalse);
    expect(ThemeSettings.fromJson({'mode': 'dark'}).compactCharCards, isFalse);
    const on = ThemeSettings(compactCharCards: true);
    expect(ThemeSettings.fromJson(on.toJson()).compactCharCards, isTrue);
  });

  test('选图器:没选过为 null,选过的两档都能回环', () {
    expect(const ThemeSettings().systemPicker, isNull);
    expect(ThemeSettings.fromJson({'mode': 'dark'}).systemPicker, isNull);
    expect(
      ThemeSettings.fromJson({'systemPicker': 'yes'}).systemPicker,
      isNull,
    );
    for (final v in [true, false]) {
      final s = ThemeSettings(systemPicker: v);
      expect(ThemeSettings.fromJson(s.toJson()).systemPicker, v);
    }
  });

  test('界面语言:默认跟随系统,认得的三种能回环,其余按跟随系统', () {
    expect(const ThemeSettings().locale, isNull);
    expect(ThemeSettings.fromJson({'mode': 'dark'}).language, '');
    expect(ThemeSettings.fromJson({'language': 'ko'}).language, '');
    expect(ThemeSettings.fromJson({'language': 1}).language, '');
    for (final v in ['zh', 'en', 'ja']) {
      final s = ThemeSettings(language: v);
      expect(ThemeSettings.fromJson(s.toJson()).locale, Locale(v));
    }
  });
}

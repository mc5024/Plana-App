import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/theme_settings.dart';
import 'package:plana_app/features/shell/float_theme_intro.dart';

void main() {
  Future<ProviderContainer> pumpHost(
    WidgetTester tester,
    AppStores stores,
    ThemeSettings init,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStoresProvider.overrideWithValue(stores),
          themeInitProvider.overrideWithValue(init),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showFloatThemeIntro(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('go')));
  }

  testWidgets('点「试试」默认换上蓝色,反向深浅色停一下再切回,只弹一次', (tester) async {
    final stores = AppStores.ephemeral();
    final c = await pumpHost(
      tester,
      stores,
      const ThemeSettings(seedKey: 'rose'),
    );
    expect(needsFloatThemeIntro(stores.prefs), isTrue);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('试试新主题？'), findsOneWidget);
    expect(needsFloatThemeIntro(stores.prefs), isFalse);

    await tester.tap(find.text('试试'));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).seedKey, kFloatThemeKey);
    expect(c.read(themeSettingsProvider).mode, ThemeMode.dark);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).mode, ThemeMode.light);

    // 「换回」回到原来的种子档位
    await tester.tap(find.text('换回'));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).seedKey, 'rose');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('点「以后再说」不换主题', (tester) async {
    final stores = AppStores.ephemeral();
    final c = await pumpHost(tester, stores, const ThemeSettings());
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).seedKey, kDefaultSeedKey);
    expect(needsFloatThemeIntro(stores.prefs), isFalse);
  });

  testWidgets('已在用浮卡:不弹,只记下', (tester) async {
    final stores = AppStores.ephemeral();
    await pumpHost(
      tester,
      stores,
      const ThemeSettings(seedKey: kFloatThemeKey),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('试试新主题？'), findsNothing);
    expect(needsFloatThemeIntro(stores.prefs), isFalse);
  });
}

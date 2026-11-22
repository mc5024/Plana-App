import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/auth/auth_mode.dart';
import 'package:plana_app/core/net/anlas_provider.dart';
import 'package:plana_app/core/net/nai_client.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/gen_settings.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/gallery/widgets/result_badge_chip.dart';
import 'package:plana_app/features/generate/widgets/common.dart';
import 'package:plana_app/features/inspiration/tag_editor_page.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/tools/tools_page.dart';
import 'package:plana_app/l10n/l10n.dart';
import 'package:plana_app/main.dart';

/// 英文界面的版式回归。测试默认字体每个字母都是一整格宽,英文会被量得比真机
/// 宽得多;这里换成 Flutter SDK 自带的 Roboto(拿不到就跳过)。

class _TokenMode extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => AuthMode.token;
}

class _PrimedSettings extends GenSettingsNotifier {
  @override
  Future<GenSettings> build() async => const GenSettings(notifyPrimed: true);
}

class _NoMode extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => null;
}

class _FreshSettings extends GenSettingsNotifier {
  @override
  Future<GenSettings> build() async => const GenSettings();
}

class _NoAnlas extends AnlasNotifier {
  @override
  Future<NaiSubscription?> build() async => null;
}

/// SDK 缓存里的 Roboto 目录:flutter_tester 在 `<sdk>/bin/cache/artifacts/engine/<平台>/` 下。
Directory? _robotoDir() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) '$root/bin/cache/artifacts/material_fonts',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  ];
  for (final c in candidates) {
    final d = Directory(c);
    if (File('${d.path}/roboto-regular.ttf').existsSync()) return d;
  }
  return null;
}

Future<bool> _loadRoboto() async {
  // PLANA_TEST_FONT_DIR:放 misans-400/500/600/700.ttf,按主测试机的字体量(英文比 Roboto 宽约一成)
  final misans = Platform.environment['PLANA_TEST_FONT_DIR'];
  if (misans != null) {
    Future<ByteData> font(int w) async =>
        ByteData.sublistView(await File('$misans/misans-$w.ttf').readAsBytes());
    for (final family in ['Roboto', 'monospace']) {
      final loader = FontLoader(family)
        ..addFont(font(400))
        ..addFont(font(500))
        ..addFont(font(600))
        ..addFont(font(700));
      await loader.load();
    }
    return true;
  }
  final dir = _robotoDir();
  if (dir == null) return false;
  Future<ByteData> font(String name) async =>
      ByteData.sublistView(await File('${dir.path}/$name').readAsBytes());
  // 等宽读数在真机上是系统 monospace,宽度和 Roboto 的数字相近
  for (final family in ['Roboto', 'monospace']) {
    final loader = FontLoader(family)
      ..addFont(font('roboto-regular.ttf'))
      ..addFont(font('roboto-medium.ttf'))
      ..addFont(font('roboto-bold.ttf'));
    await loader.load();
  }
  return true;
}

Future<void> _pumpEnglish(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStoresProvider.overrideWithValue(AppStores.ephemeral()),
        authModeProvider.overrideWith(_TokenMode.new),
        genSettingsProvider.overrideWith(_PrimedSettings.new),
        anlasProvider.overrideWith(_NoAnlas.new),
      ],
      child: const PlanaApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  var fonts = false;
  setUpAll(() async => fonts = await _loadRoboto());

  testWidgets('360 宽的创作页不溢出', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    await _pumpEnglish(tester, const Size(360, 800));

    expect(find.text('Generate'), findsWidgets);
    // 确认量的是 Roboto:测试字体下 10px 的「Size」是 40 宽
    expect(tester.getSize(find.text('Size')).width, lessThan(30));

    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('360 宽的底栏各页不溢出', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    await _pumpEnglish(tester, const Size(360, 800));

    for (final tab in ['Gallery', 'Ideas', 'Profile']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }

    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('360 宽的分辨率面板不溢出', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    await _pumpEnglish(tester, const Size(360, 800));

    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect(find.text('Wallpaper'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('360 宽的引导页逐页不溢出', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStoresProvider.overrideWithValue(AppStores.ephemeral()),
          authModeProvider.overrideWith(_NoMode.new),
          genSettingsProvider.overrideWith(_FreshSettings.new),
        ],
        child: const PlanaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Plana'), findsOneWidget);

    Future<void> tap(String text) async {
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tap('Next');
    expect(find.text('Appearance'), findsOneWidget);
    await tap('Next');
    expect(find.text('How to Generate'), findsOneWidget);
    await tap('Skip for Now');
    expect(find.text('Progress Notifications'), findsOneWidget);
    await tap('Not Now');
    expect(find.text('All Done'), findsOneWidget);
  });

  testWidgets('参考图标题行放不下时「移除」只留图标', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    Future<void> pump({required double leading}) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            // 创作页卡片内宽
            child: SizedBox(
              width: 333,
              child: RefDetailHeader(
                index: 1,
                name: 'reference.png',
                onRemove: () {},
                enableToggle: const SizedBox(width: 38),
                leadingAction: SizedBox(width: leading),
                leadingActionWidth: leading,
              ),
            ),
          ),
        ),
      ),
    );

    await pump(leading: 0);
    expect(find.text('Remove'), findsOneWidget);
    // 一颗较宽的切换钮
    await pump(leading: 175);
    expect(find.text('Remove'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('胶片条角标放不下时只留图标', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    Future<void> pump(Locale locale, double maxWidth) => tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: kSupportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) {
          syncL10nNow(context);
          return child!;
        },
        home: Scaffold(
          body: Center(
            child: ResultBadgeChip(
              badge: ResultBadge.inpaint,
              maxWidth: maxWidth,
            ),
          ),
        ),
      ),
    );

    // 竖图缩略图约 49 宽,左右各让 4
    await pump(const Locale('en'), 41);
    expect(find.text('Inpaint'), findsNothing);
    expect(find.byIcon(Icons.brush), findsOneWidget);
    await pump(const Locale('en'), 64);
    expect(find.text('Inpaint'), findsOneWidget);
    await pump(const Locale('zh'), 41);
    expect(find.text('重绘'), findsOneWidget);
  });

  testWidgets('360 宽的工具箱页签不折行', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoresProvider.overrideWithValue(AppStores.ephemeral())],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) {
            syncL10nNow(context);
            return child!;
          },
          home: const ToolsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final line = tester.getSize(find.text('Toolbox')).height;
    for (final tab in ['Convert Weights', 'Image Metadata', 'Compare']) {
      expect(tester.getSize(find.text(tab)).height, lessThan(line));
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('360 宽的灵感新建页不溢出', (tester) async {
    if (!fonts) return markTestSkipped('找不到 SDK 自带的 Roboto');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoresProvider.overrideWithValue(AppStores.ephemeral())],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) {
            syncL10nNow(context);
            return child!;
          },
          home: const TagEditorPage(cat: TagCategory.artist),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Recommended Settings'));
    await tester.pumpAndSettle();

    // 按钮里的文字被截断不报溢出,逐个比排版宽度和完整宽度
    final clipped = [
      for (final e in find.byType(RichText).evaluate())
        if (e.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicWidth(double.infinity) > p.size.width + .5)
          p.text.toPlainText(),
    ];
    expect(clipped, isEmpty);

    await tester.pump(const Duration(seconds: 1));
  });
}

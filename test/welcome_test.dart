import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/auth/auth_mode.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/gen_settings.dart';
import 'package:plana_app/main.dart';

/// 首启:没选接入方式 + 没过通知那步 → 欢迎流程,四页可翻。
class _NoMode extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => null;
}

class _FreshSettings extends GenSettingsNotifier {
  @override
  Future<GenSettings> build() async => const GenSettings();
}

/// 已选直连但通知那步没过(本次升级的老用户):仍要走欢迎流程。
class _TokenMode extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => AuthMode.token;
}

void main() {
  // 文案按中文断言:系统语言固定成中文
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = [
      const Locale('zh'),
    ];
  });
  tearDown(
    () => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearLocalesTestValue(),
  );

  Widget app({required AuthModeNotifier Function() mode}) => ProviderScope(
    overrides: [
      appStoresProvider.overrideWithValue(AppStores.ephemeral()),
      authModeProvider.overrideWith(mode),
      genSettingsProvider.overrideWith(_FreshSettings.new),
    ],
    child: const PlanaApp(),
  );

  testWidgets('首启走欢迎流程,五页依次可达', (tester) async {
    await tester.pumpWidget(app(mode: _NoMode.new));
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用 Plana'), findsOneWidget);

    Future<void> next() async {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }

    await next();
    expect(find.text('外观配色'), findsOneWidget);
    await next();
    expect(find.text('生成接入方式'), findsOneWidget);

    // 没配好接入方式不放行(选直连但没存令牌也算没配),只能走「暂时跳过」
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('暂时跳过'));
    await tester.pumpAndSettle();
    expect(find.text('生成进度通知'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开启通知'), findsOneWidget);
    expect(find.text('暂不开启'), findsOneWidget);

    // 通知选完进完成页,末页只有一个出口
    await tester.tap(find.text('暂不开启'));
    await tester.pumpAndSettle();
    expect(find.text('全部完成'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始使用'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);
  });

  testWidgets('通知那步没过的老用户也会被引到欢迎流程', (tester) async {
    await tester.pumpWidget(app(mode: _TokenMode.new));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 Plana'), findsOneWidget);
  });
}

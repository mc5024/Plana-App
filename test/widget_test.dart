import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/auth/auth_mode.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/gen_settings.dart';
import 'package:plana_app/features/generate/widgets/bottom_action_bar.dart';
import 'package:plana_app/main.dart';

/// 测试环境无 Keystore,固定「已选直连」跳过引导页,直接冒烟创作页。
class _TokenMode extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => AuthMode.token;
}

/// 同理跳过首启的通知说明页(notifyPrimed 已过)。
class _PrimedSettings extends GenSettingsNotifier {
  @override
  Future<GenSettings> build() async => const GenSettings(notifyPrimed: true);
}

void main() {
  testWidgets('创作页冒烟:核心区块可见', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStoresProvider.overrideWithValue(AppStores.ephemeral()),
          authModeProvider.overrideWith(_TokenMode.new),
          genSettingsProvider.overrideWith(_PrimedSettings.new),
        ],
        child: const PlanaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);
    expect(find.text('生成'), findsWidgets);
    expect(find.text('创作'), findsOneWidget);

    // 放行工作台持久化的 800ms 防抖 Timer,避免拆树时报 pending timer
    await tester.pump(const Duration(milliseconds: 900));
  });

  // ---- 费用胶囊(CostPill)的几何不变量 ----
  //
  // 这三条全是布局层面的事,analyze 一条都查不出来,而这颗胶囊历史上连着栽过
  // 三次:撑满整条按钮、贴着字缩掉一截、免费比两位数窄零点几像素(表现为切档
  // 时左边「生成」两个字往左挪一格)。所以直接 pump 它,一条一条钉死。
  Future<Size> pumpPill(WidgetTester tester, int cost) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // 有界且宽松的约束 —— 复刻它在生成按钮里的处境:撑满型的 bug
          // (Align 取 constraints.biggest)只有在有上界时才现形。
          body: Center(
            child: SizedBox(
              width: 300,
              child: Row(children: [CostPill(cost: cost)]),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(CostPill));
  }

  testWidgets('费用胶囊:免费与两位数点数完全等宽等高', (WidgetTester tester) async {
    final free = await pumpPill(tester, 0);
    final two = await pumpPill(tester, 35);
    // 等宽靠的是那个隐形替身(恒按「图标 + 间隔 + 两位数字」占位),不是估出来
    // 的常数 —— 数字宽度是字体的事,估的那版在真机上就差了零点几像素。
    expect(free.width, equals(two.width));
    expect(free.height, equals(two.height));
    // 一位数同样躲在替身后面,不该让胶囊变窄。
    expect((await pumpPill(tester, 7)).width, equals(two.width));
  });

  testWidgets('费用胶囊:三位数撑开,且不会撑满可用宽度', (WidgetTester tester) async {
    final two = await pumpPill(tester, 35);
    final three = await pumpPill(tester, 350);
    // 三位数是少数情况,允许变宽(外面由 AnimatedSize 滑过去),但只多一位的量。
    expect(three.width, greaterThan(two.width));
    // 上界守的是那次真正的回归:给 Container 加 alignment 会包出一层 Align,
    // 它在有界约束下直接取 constraints.biggest,胶囊会一路铺到 300。
    expect(three.width, lessThan(80));
  });

  testWidgets('生成按钮的费用胶囊只占内容宽,不会撑满整颗按钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStoresProvider.overrideWithValue(AppStores.ephemeral()),
          authModeProvider.overrideWith(_TokenMode.new),
          genSettingsProvider.overrideWith(_PrimedSettings.new),
        ],
        child: const PlanaApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 吸底栏里只有费用胶囊裹了 AnimatedSize(三位数以上撑开时的过渡),拿它定位。
    final pill = find.descendant(
      of: find.byType(BottomActionBar),
      matching: find.byType(AnimatedSize),
    );
    expect(pill, findsOneWidget);

    // 上面几条是单独 pump 胶囊量的,这里再在**真实按钮里**兜一道:约束、
    // 可用宽度都跟线上一致,撑满型的 bug 只有在这种处境下才会现形。
    final size = tester.getSize(pill);
    expect(size.width, lessThan(80));
    expect(size.height, equals(20));

    await tester.pump(const Duration(milliseconds: 900));
  });
}

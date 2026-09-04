import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_info.dart';
import 'core/auth/auth_mode.dart';
import 'core/store/app_stores.dart';
import 'core/store/gen_settings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_settings.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/shell/app_shell.dart';
import 'core/util/haptics.dart';
import 'features/editor/data/local_tag_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动装载持久化状态(工作台存档 + 图库索引 + 设置;失败按首启空档降级)。
  // 外观预读(首帧不闪色)现在直接取内存态 —— 设置已随 AppStores 一次读全,
  // 不再需要第二笔 I/O,也不必再解一次 Keystore。
  final stores = await AppStores.open();
  final themeInit = loadThemeSettings(stores.prefs);
  // 自己 new 再注进去,是为了**开机就能开灌**(见下面 warmTagMeta):
  // 走 provider 的话第一个读它的人才创建,那就还是"谁先用到谁背这一下"。
  final tagDb = LocalTagDb();
  runApp(
    ProviderScope(
      overrides: [
        appStoresProvider.overrideWithValue(stores),
        themeInitProvider.overrideWithValue(themeInit),
        localTagDbProvider.overrideWithValue(tagDb),
      ],
      child: const PlanaApp(),
    ),
  );
  // 注册即挂到 binding 观察者列表(强引用,不会被 GC):
  // 退后台/失焦即刻把防抖窗口里的工作台/图库索引落盘,进程被杀不丢。
  AppLifecycleListener(
    onStateChange: (s) {
      if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
        stores.flushNow();
      }
    },
  );
  stores.postBootMaintenance(); // 选图器缓存清扫 + blob GC(延迟后台跑)
  // 离线词库开机就灌:编辑器补全、法典/灵感页芯片的注音都要它,基本每次开
  // app 都会碰到,与其等第一个用到的人背这一下,不如开机顺手灌完。
  //
  // 早先是"谁先用到谁触发",而那几个触发点全带动画:第一次进编辑器、第一次
  // 翻法典的牌 —— 翻牌那一下实测多花 130 多毫秒(读 4.9MB asset 与解析虽在别
  // 的 isolate,最后灌 9 万条反查缓存那一遍是主线程的),正好砸在卡片转起来的
  // 时候。原来的触发点都留着不动:[LocalTagDb.warmTagMeta] 幂等,灌过即返回。
  //
  // 等首帧过去再动手 —— 主线程那一遍不跟开屏抢。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 600),
        tagDb.warmTagMeta,
      ),
    );
  });
}

class PlanaApp extends ConsumerWidget {
  const PlanaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(themeSettingsProvider);
    // 触感开关同步到全局出口:调用点在手势/绘制层,拿不到 ref,只能这样递。
    Haptics.enabled = ts.haptics;
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(ts.seed.color),
      darkTheme: AppTheme.dark(ts.seed.color),
      themeMode: ts.mode,
      home: const _AuthGate(),
    );
  }
}

/// 启动 gate:欢迎流程没走完(没过通知那步)或没选接入方式 → 欢迎页;
/// 否则主界面。首帧 loading 时垫占位,避免闪主界面。
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(authModeProvider);
    final gs = ref.watch(genSettingsProvider);
    if (mode.isLoading || gs.isLoading) return const _SplashHold();
    // 读失败一律按首启处理:宁可多走一次欢迎,也不让人卡在空界面
    final primed = gs.value?.notifyPrimed ?? false;
    if (!primed || mode.value == null) return const WelcomePage();
    return const AppShell();
  }
}

class _SplashHold extends StatelessWidget {
  const _SplashHold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Icon(
          Icons.auto_awesome,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

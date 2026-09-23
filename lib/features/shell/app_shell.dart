import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/auth/nai_credential_login.dart';
import '../../core/auth/token_store.dart';
import '../../core/net/backend_config.dart';
import '../../core/store/app_stores.dart';
import '../../core/store/prefs_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_settings.dart';
import '../assistant/assistant_page.dart';
import '../assistant/assistant_state.dart';
import '../gallery/gallery_page.dart';
import '../gallery/gallery_state.dart';
import '../gallery/albums/album_models.dart';
import '../gallery/albums/album_state.dart';
import '../generate/generate_page.dart';
import '../generate/generation_controller.dart';
import '../generate/widgets/common.dart' show hintSnack;
import '../inspiration/inspiration_page.dart';
import '../inpaint/inpaint_overlay.dart' show inpaintSessionProvider;
import '../profile/profile_page.dart';
import '../update/update_service.dart';
import '../update/update_sheet.dart' show showUpdateSheet;
import 'shell_state.dart';

/// 全局骨架:5 tab 底部导航(AI 那格可藏)+ PageView 切页。
///
/// **横滑翻 tab 已关掉**(physics 恒为 NeverScrollable),切页只认底部导航点按与
/// 程序跳转(生成完跳图库、缺 token 跳我的)。PageView 留着只为那段横向推移动画。
/// 关掉的理由:页内本来就需要横向手势(图库大图翻页、缩放平移),tab 级横滑与它们
/// 长期抢竞技场 —— 以前靠「碰一下图就锁 shell」的补丁压着,页内一有正经翻页需求
/// 就压不住了。整个横向手势层交给页面自己,shell 不再参与。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final PageController _pc = PageController(
    initialPage: ref.read(shellIndexProvider),
  );

  static const _pages = [
    GeneratePage(),
    GalleryPage(),
    AssistantPage(),
    InspirationPage(),
    ProfilePage(),
  ];

  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // 预热鉴权/后端配置(懒加载 AsyncNotifier 的 storage 首读在此触发,
    // 否则冷启动后立刻点「生成」会在 loading 态被误判成未授权/没 token)。
    ref.read(tokenProvider);
    ref.read(botSessionProvider);
    ref.read(backendBaseProvider);
    // 账号密码登录的 JWT 临期静默换新(非该来源的令牌自动跳过)。
    ref.read(naiTokenAutoRefreshProvider);
    _scheduleAutoCheck();
  }

  /// 冷启动静默查一次更新(24h 节流)。
  ///
  /// 延后 3 秒:启动那几帧要留给首页和鉴权预热,更新弹层不是急事。计时器**必须
  /// 存下来并在 dispose 取消** —— 裸 `Future.delayed` 在页面提前销毁后照样会醒,
  /// 属于真实泄漏(widget 冒烟测试会直接报 pending timer)。
  void _scheduleAutoCheck() {
    final prefs = ref.read(prefsStoreProvider);
    if (!shouldAutoCheck(prefs)) return;
    _updateTimer = Timer(
      const Duration(seconds: 3),
      () => _autoCheckUpdate(prefs),
    );
  }

  /// **只在真有新版时弹**,查不到/网络不通一律无声吞掉 —— 用户没主动要求检查,
  /// 不该为此看到任何失败提示。
  Future<void> _autoCheckUpdate(PrefsStore prefs) async {
    if (!mounted) return;
    try {
      final installed = await installedInfo();
      if (!installed.isKnown) return; // 非 Android / 通道缺失
      final release = await fetchLatestRelease(installed.versionName);
      await markUpdateChecked(prefs);
      if (release == null || !mounted) return;
      await showUpdateSheet(
        context,
        UpdateCheck(installed: installed, release: release),
      );
    } catch (_) {
      // 静默:后台检查失败不打扰
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  /// 切到创作页的一刻:把「AI 页导入过、还没来看」的角标熄掉。
  ///
  /// **不再在这儿弹回执**:导入本身就是用户在结果卡上点的,当场已经弹过一次
  /// 「已写入创作页」,路过再弹一条是重复。撤销的入口长期留在那张卡上。
  void _onEnterCreate() => ref.read(assistantProvider.notifier).markSeen();

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellIndexProvider);
    // 底栏可以藏掉「AI」那一格(外观设置里)。**页面列表不跟着变**:
    // PageView 五页照旧,跨页跳转用的还是 kTab* 那几个逻辑下标,
    // 只在画底栏和读回点击时做一次映射 —— 把下标也跟着挪的话,
    // 「生成完跳图库」「缺 token 跳我的」这些调用点全得判一遍开关。
    final showAi = ref.watch(
      themeSettingsProvider.select((t) => t.showAssistant),
    );
    final tabs = [
      kTabCreate,
      kTabGallery,
      if (showAi) kTabAssistant,
      kTabInspiration,
      kTabProfile,
    ];
    // 正停在 AI 页时被关掉(例如从别处恢复的状态):退回创作页,
    // 否则 selectedIndex 会拿到 -1。
    if (!showAi && index == kTabAssistant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(shellIndexProvider.notifier).select(kTabCreate);
      });
    }

    // 索引变化(导航点按 / 生成后跳图库)→ 滑到对应页。
    ref.listen<int>(shellIndexProvider, (prev, next) {
      if (!_pc.hasClients) return;
      // 比精确页码,不比 round 过的:切页动画途中改点别的格,若途经页 round 出来
      // 恰好是新目标,会被当成「已经到了」,页面却继续滑向原目标、底栏对不上。
      // 停稳时 page 就是整数(PagePosition 会把浮点误差吸附掉)。
      final current = _pc.page ?? _pc.initialPage.toDouble();
      if (current != next.toDouble()) {
        // 切页先收焦点。PageView 是保活的,离开时焦点还留在原页的输入框上
        // (灵感页搜索框最容易中招),之后**在任何一页**切页都会把软键盘重新
        // 顶出来一下。放在动画开始前,不是切完再收 —— 否则过渡里照样闪一下。
        FocusManager.instance.primaryFocus?.unfocus();
        _pc.animateToPage(
          next,
          duration: Motion.medium,
          curve: Motion.emphasized,
        );
      }
    });

    // 生成错误全局提示(常驻:切 tab 也不漏)
    ref.listen<GenStatus>(genStatusProvider, (prev, next) {
      final err = next.error;
      if (err == null) return;
      if (next.noToken) {
        hintSnack(
          context,
          '请先在「我的」页设置 NovelAI API Token',
          icon: Icons.key_off_outlined,
          actionLabel: '去设置',
          onAction: () =>
              ref.read(shellIndexProvider.notifier).select(kTabProfile),
        );
      } else {
        hintSnack(context, err, icon: Icons.error_outline);
      }
      ref.read(generationProvider.notifier).clearError();
    });

    // 生成侧非致命提醒(LoRA 超上限被丢弃等):图照常出,但得说一声,
    // 否则用户对着一个根本没生效的 LoRA 查半天。
    ref.listen<String?>(genNoticeProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      hintSnack(context, next, icon: Icons.info_outline);
      ref.read(genNoticeProvider.notifier).clear();
    });

    ref.listen<GalleryResultPreview?>(gallerySavedNoticeProvider, (_, next) {
      if (next == null) return;
      final name = ref.read(albumsProvider).name(next.target.albumId);
      hintSnack(
        context,
        '新图片已保存到「$name」',
        icon: Icons.photo_library_outlined,
        actionLabel: '查看',
        onAction: () {
          if (!mounted) return;
          if (ref.read(inpaintSessionProvider) != null) {
            hintSnack(context, '结束编辑后可查看新图片');
            return;
          }
          if (!ref
              .read(galleryProvider)
              .results
              .any((r) => r.id == next.imageId)) {
            hintSnack(context, '这张图片已被删除');
            return;
          }
          final target = ref.read(albumsProvider).exists(next.target.albumId)
              ? next.target
              : const GallerySaveTarget.all();
          ref.read(generationProvider.notifier).select(null);
          ref
              .read(galleryResultPreviewProvider.notifier)
              .show(next.imageId, target);
          ref.read(shellIndexProvider.notifier).select(kTabGallery);
        },
      );
      ref.read(gallerySavedNoticeProvider.notifier).clear();
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageView(
          controller: _pc,
          // 只让程序 animateToPage 驱动;用户横滑一律不吃
          physics: const NeverScrollableScrollPhysics(),
          // **不接 onPageChanged**:页面只会跟着索引走,而 animateToPage 途经的
          // 每一页都会上报一次。写回索引的话,创作 → 灵感会在半路把索引拨成 AI 页
          // —— 没做过引导的弹出引导;底栏藏了 AI 的,被上面那段拽回创作页。
          children: _pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs.indexOf(index).clamp(0, tabs.length - 1),
        // 重绘编辑中也允许点按切页(图库页 keep-alive,回来面板还在);
        // 仅横滑仍锁(防抢涂抹手势)。
        onDestinationSelected: (i) {
          final tab = tabs[i];
          ref.read(shellIndexProvider.notifier).select(tab);
          if (tab == kTabCreate) _onEnterCreate();
        },
        destinations: [
          NavigationDestination(
            // 用户在 AI 页点过「导入」、但还没切过来看时点亮。
            // 独立 tab 没有「改动就在眼皮底下」的同屏感,这颗点是全部的补偿 ——
            // 它只负责说「那边有东西变了」,改了什么去看提示词卡。
            icon: Badge(
              isLabelVisible: ref.watch(
                assistantProvider.select((s) => s.changedUnseen),
              ),
              smallSize: 8,
              child: const Icon(Icons.draw_outlined),
            ),
            selectedIcon: const Icon(Icons.draw),
            label: '创作',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: '图库',
          ),
          if (showAi)
            const NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI',
            ),
          const NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: '灵感',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

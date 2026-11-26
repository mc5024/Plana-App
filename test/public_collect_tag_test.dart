// 公共库多选「添加到我的标签」:数据层收藏+打标去重、以及灵感页公共库多选底栏流程。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/auth/bot_session_store.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/gen_settings.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/inspiration/inspiration_page.dart';
import 'package:plana_app/features/inspiration/public_tags.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/inspiration/widgets/tag_sheets.dart';
import 'package:plana_app/l10n/l10n.dart';

class _Library extends TagLibrary {
  _Library([this._initial = const TagLibraryState()]);

  final TagLibraryState _initial;

  @override
  Future<TagLibraryState> build() async => _initial;
}

class _Session extends BotSessionNotifier {
  @override
  Future<BotSession?> build() async =>
      const BotSession(sessionId: 'sid', botUserId: 'me');
}

class _GenSettings extends GenSettingsNotifier {
  @override
  Future<GenSettings> build() async => const GenSettings(notifyPrimed: true);
}

const _pubA = TagEntry(
  id: 'pub_alice',
  category: TagCategory.character,
  name: '爱丽丝',
  positive: '1girl, blue hair',
  publicId: 'alice',
  createdBy: 'other1',
  createdAt: 1000,
);

const _pubB = TagEntry(
  id: 'pub_bob',
  category: TagCategory.character,
  name: '白子',
  positive: '1girl, wolf ears',
  publicId: 'bob',
  createdBy: 'other2',
  createdAt: 2000,
);

const _pubMine = TagEntry(
  id: 'pub_mine',
  category: TagCategory.character,
  name: '我发的角色',
  positive: '1girl, black hair',
  publicId: 'mine',
  createdBy: 'me',
  createdAt: 3000,
);

void main() {
  group('TagLibrary.collectWithTag', () {
    test('批量收藏多个公共条目到指定标签:不重 ID、写入标签池、已收藏条目只补标签', () async {
      final existingFav = TagEntry(
        id: 'fav_existing',
        category: TagCategory.character,
        name: '白子',
        positive: '1girl, wolf ears',
        tags: const ['常用'],
        origin: TagOrigin.favorited,
        publicId: 'bob',
        createdBy: 'other2',
        createdAt: 10,
      );
      final container = ProviderContainer(
        overrides: [
          tagLibraryProvider.overrideWith(
            () => _Library(
              TagLibraryState(
                entries: [existingFav],
                pools: {
                  TagCategory.character: const ['常用'],
                },
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(tagLibraryProvider.future);

      final r = await container
          .read(tagLibraryProvider.notifier)
          .collectWithTag(
            TagCategory.character,
            const [_pubA, _pubB, _pubMine],
            '蔚蓝档案',
            myUserId: 'me',
          );

      expect(r.collected, 2);
      expect(r.tagged, 3);

      final state = container.read(tagLibraryProvider).requireValue;
      expect(state.entries, hasLength(3));
      // 3 条 ID 全部唯一
      expect(state.entries.map((e) => e.id).toSet(), hasLength(3));
      // 新标签已进池
      expect(state.poolOf(TagCategory.character), ['常用', '蔚蓝档案']);

      final alice = state.entries.firstWhere((e) => e.publicId == 'alice');
      expect(alice.origin, TagOrigin.favorited);
      expect(alice.tags, ['蔚蓝档案']);

      final bob = state.entries.firstWhere((e) => e.publicId == 'bob');
      expect(bob.id, 'fav_existing');
      expect(bob.tags, ['常用', '蔚蓝档案']);

      final mine = state.entries.firstWhere((e) => e.publicId == 'mine');
      expect(mine.origin, TagOrigin.created);
      expect(mine.tags, ['蔚蓝档案']);
      expect(mine.createdAt, 3000);
    });

    test('已带有该标签的条目幂等不重复追加', () async {
      final existing = TagEntry(
        id: 'fav_1',
        category: TagCategory.character,
        name: '爱丽丝',
        tags: const ['BA'],
        origin: TagOrigin.favorited,
        publicId: 'alice',
      );
      final container = ProviderContainer(
        overrides: [
          tagLibraryProvider.overrideWith(
            () => _Library(TagLibraryState(entries: [existing])),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(tagLibraryProvider.future);

      final r = await container
          .read(tagLibraryProvider.notifier)
          .collectWithTag(TagCategory.character, const [_pubA], 'BA');

      expect(r.collected, 0);
      expect(r.tagged, 0);
      final state = container.read(tagLibraryProvider).requireValue;
      expect(state.entries.single.tags, ['BA']);
    });
  });

  testWidgets('角色公共库多选底栏点标签一键收藏到「我的」指定标签', (tester) async {
    tester.view.physicalSize = const Size(369, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        appStoresProvider.overrideWithValue(AppStores.ephemeral()),
        tagLibraryProvider.overrideWith(
          () => _Library(
            TagLibraryState(
              pools: {
                TagCategory.character: const ['蔚蓝档案'],
              },
            ),
          ),
        ),
        botSessionProvider.overrideWith(_Session.new),
        genSettingsProvider.overrideWith(_GenSettings.new),
        publicTagsProvider(
          TagCategory.character,
        ).overrideWith((_) async => const [_pubA, _pubB]),
        publicTagsProvider(
          TagCategory.artist,
        ).overrideWith((_) async => const []),
        tagAuthorNamesProvider.overrideWith((_) async => const {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const InspirationPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 切到角色公共库
    await tester.tap(find.text('公共'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // 勾选两个公共角色
    await tester.tap(find.byKey(const ValueKey('pub_alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pub_bob')));
    await tester.pumpAndSettle();

    // 多选底栏同时有收藏钮和标签钮
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('标签'), findsOneWidget);

    // 点标签钮 → 选已有标签「蔚蓝档案」
    await tester.tap(find.byTooltip('标签'));
    await tester.pumpAndSettle();
    expect(find.text('添加到我的标签'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '蔚蓝档案'));
    await tester.pumpAndSettle();

    // 已收藏进「我的」并都带上该标签,且多选已清空
    final entries = container.read(tagLibraryProvider).requireValue.entries;
    expect(entries, hasLength(2));
    expect(entries.every((e) => e.tags.contains('蔚蓝档案')), isTrue);
    expect(find.text('已添加 2 项到「蔚蓝档案」'), findsOneWidget);

    // 再选一个已收藏的角色,现场新建标签「阿拜多斯」补打上去
    await tester.tap(find.byKey(const ValueKey('pub_bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '阿拜多斯');
    await tester.tap(find.text('使用'));
    await tester.pumpAndSettle();

    final bob = container
        .read(tagLibraryProvider)
        .requireValue
        .entries
        .firstWhere((e) => e.publicId == 'bob');
    expect(bob.tags, ['蔚蓝档案', '阿拜多斯']..sort());

    // 切回「我的」→ 点 #蔚蓝档案 筛选胶囊,两个角色都在里面
    await tester.tap(find.text('我的'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('#蔚蓝档案'));
    await tester.pumpAndSettle();
    expect(find.text('爱丽丝'), findsWidgets);
    expect(find.text('白子'), findsWidgets);

    // 点 #阿拜多斯 筛选胶囊,只剩白子
    await tester.tap(find.text('#阿拜多斯'));
    await tester.pumpAndSettle();
    expect(find.text('白子'), findsWidgets);
    expect(find.text('爱丽丝'), findsNothing);
  });

  group('confirmDeleteTagEntries 文案与排版', () {
    Future<void> openDialog(WidgetTester tester, List<TagEntry> entries) async {
      tester.view.physicalSize = const Size(369, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => confirmDeleteTagEntries(context, entries),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    const longLocal = TagEntry(
      id: 'c1',
      category: TagCategory.character,
      name: '这是一个特别长的角色名字测试不会把标题挤成两行',
    );
    const local2 = TagEntry(
      id: 'c2',
      category: TagCategory.character,
      name: '小焰',
    );
    const fav1 = TagEntry(
      id: 'f1',
      category: TagCategory.character,
      name: '天童爱丽丝（女仆装版本）',
      origin: TagOrigin.favorited,
      publicId: 'alice',
    );
    const fav2 = TagEntry(
      id: 'f2',
      category: TagCategory.character,
      name: '白子',
      origin: TagOrigin.favorited,
      publicId: 'bob',
    );
    const pub1 = TagEntry(
      id: 'p1',
      category: TagCategory.character,
      name: '我发布的超长名字角色条目',
      origin: TagOrigin.created,
      publicId: 'mine',
    );

    testWidgets('单删收藏与批量全收藏标题简短单行、名称在正文、不出现无法恢复', (tester) async {
      await openDialog(tester, const [fav1]);
      expect(find.text('删除收藏'), findsOneWidget);
      expect(find.text('将从「我的」移除「天童爱丽丝（女仆装版本）」，公共库中仍会保留。'), findsOneWidget);
      expect(find.textContaining('无法恢复'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await openDialog(tester, const [fav1, fav2]);
      expect(find.text('删除 2 项'), findsOneWidget);
      expect(find.text('仅从「我的」移除，公共库中仍会保留。'), findsOneWidget);
      expect(find.textContaining('无法恢复'), findsNothing);
    });

    testWidgets('长名称单删与批量全本地标题不折行', (tester) async {
      await openDialog(tester, const [longLocal]);
      expect(find.text('删除条目'), findsOneWidget);
      expect(
        find.text('将删除「这是一个特别长的角色名字测试不会把标题挤成两行」，无法恢复。'),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await openDialog(tester, const [pub1]);
      expect(find.text('删除条目'), findsOneWidget);
      expect(find.text('将同时删除「我发布的超长名字角色条目」的公共库条目与本地副本，无法恢复。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await openDialog(tester, const [longLocal, local2]);
      expect(find.text('删除 2 项'), findsOneWidget);
      expect(find.text('删除后无法恢复。'), findsOneWidget);
    });

    testWidgets('混合来源按分组结构展示各自后果且不溢出', (tester) async {
      await openDialog(tester, const [pub1, longLocal, local2, fav1]);
      expect(find.text('删除 4 项'), findsOneWidget);
      expect(find.text('已发布 · 1 项'), findsOneWidget);
      expect(find.text('同时从公共库与本地删除，无法恢复'), findsOneWidget);
      expect(find.text('本地 · 2 项'), findsOneWidget);
      expect(find.text('删除后无法恢复'), findsOneWidget);
      expect(find.text('收藏 · 1 项'), findsOneWidget);
      expect(find.text('仅从「我的」移除，公共库中仍会保留'), findsOneWidget);
    });
  });
}

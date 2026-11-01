// 提示词卡头「灵感库」面板:四类标签库(只列我的)+ 法典收藏,分类胶囊切换。
//
// 容易坏的几处:切分类把别的分类勾好的丢了;法典那页把整部法典而不是收藏
// 列出来;底栏只带走当前分类;「最近使用」记到了错的分类上。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/auth/bot_session_store.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/editor/data/tag_translation_service.dart';
import 'package:plana_app/features/inspiration/codex/codex_card.dart';
import 'package:plana_app/features/inspiration/codex/codex_favorites.dart';
import 'package:plana_app/features/inspiration/codex/codex_models.dart';
import 'package:plana_app/features/inspiration/codex/codex_providers.dart';
import 'package:plana_app/features/inspiration/public_tags.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/inspiration/widgets/char_pick_sheet.dart';
import 'package:plana_app/features/inspiration/widgets/tag_card.dart';

const _a12 = TagEntry(
  id: 'a12',
  category: TagCategory.artist,
  name: 'A12',
  positive: 'artist:wlop',
);
const _b3 = TagEntry(
  id: 'b3',
  category: TagCategory.artist,
  name: 'B3',
  positive: 'artist:ask',
);
const _rain = TagEntry(
  id: 'rain',
  category: TagCategory.scene,
  name: '雨夜',
  positive: 'night, rain',
);
const _miku = TagEntry(
  id: 'miku',
  category: TagCategory.character,
  name: '初音',
  positive: 'hatsune miku',
);
final _fav = CodexFavorite(
  codexId: 'c1',
  entry: const CodexEntry(id: 'e1', title: '雨中回眸', tags: '1girl, rain'),
  savedAt: 1,
);

class _Library extends TagLibrary {
  final used = <TagCategory, List<String>>{};

  @override
  Future<TagLibraryState> build() async =>
      const TagLibraryState(entries: [_a12, _b3, _rain, _miku]);

  @override
  Future<void> markUsed(TagCategory category, List<String> ids) async =>
      used[category] = ids;
}

class _Session extends BotSessionNotifier {
  @override
  Future<BotSession?> build() async =>
      const BotSession(sessionId: 'test', botUserId: 'me');
}

class _Favorites extends CodexFavoritesNotifier {
  @override
  Future<List<CodexFavorite>> build() async => [_fav];
}

Future<({ProviderContainer c, LibraryPicks? Function() result})> _open(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(369 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      tagLibraryProvider.overrideWith(_Library.new),
      botSessionProvider.overrideWith(_Session.new),
      for (final cat in TagCategory.builtins)
        publicTagsProvider(cat).overrideWith((_) async => const []),
      tagAuthorNamesProvider.overrideWith((_) async => const {}),
      codexFavoritesProvider.overrideWith(_Favorites.new),
      codexIndexProvider.overrideWith((_) async => const []),
      codexMediaProvider.overrideWith((_) async => CodexMedia.fallback),
      tagTranslationServiceProvider.overrideWith((ref) {
        final service = TagTranslationService(enabled: false, baseUrl: '');
        ref.onDispose(service.dispose);
        return service;
      }),
    ],
  );
  addTearDown(c.dispose);
  LibraryPicks? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async =>
                    result = await showLibraryPickSheet(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return (c: c, result: () => result);
}

/// 顶上页签里的 [label](勾过的类名字后面跟着个数)。
Finder _tab(String label) => find.byWidgetPredicate(
  (w) => w is Text && (w.data == label || (w.data ?? '').startsWith('$label ')),
);

/// 点顶上页签里的 [label]。
Future<void> _switchTo(WidgetTester tester, String label) async {
  await tester.tap(_tab(label));
  await tester.pumpAndSettle();
}

Finder _tagCard(String id) =>
    find.byWidgetPredicate((w) => w is TagCard && w.entry.id == id);

void main() {
  testWidgets('跨分类勾选都留着,法典只列收藏;底栏一次带走,最近使用按分类记', (tester) async {
    final h = await _open(tester);
    await _switchTo(tester, '画风');
    expect(_tagCard('a12'), findsOneWidget);
    expect(_tagCard('rain'), findsNothing);
    await tester.tap(_tagCard('a12'));
    await tester.pump();

    await _switchTo(tester, '场景');
    expect(_tagCard('rain'), findsOneWidget);
    await tester.tap(_tagCard('rain'));
    await tester.pump();

    await _switchTo(tester, '法典');
    expect(find.byType(CodexCard), findsOneWidget);
    await tester.tap(find.text('雨中回眸'));
    await tester.pump();

    expect(find.text('加入 (3)'), findsOneWidget);
    await tester.tap(find.text('加入 (3)'));
    await tester.pumpAndSettle();

    // 按勾的先后:标签库条目和法典收藏排在同一个顺序里
    final r = h.result()!;
    expect(
      [for (final p in r) p.tag?.entry.id ?? p.codex!.key],
      ['a12', 'rain', _fav.key],
    );
    final lib = h.c.read(tagLibraryProvider.notifier) as _Library;
    expect(lib.used, {
      TagCategory.artist: ['a12'],
      TagCategory.scene: ['rain'],
    });
  });

  testWidgets('页签不标已勾几个;取消选择一次清掉全部', (tester) async {
    await _open(tester);
    await _switchTo(tester, '画风');
    await tester.tap(_tagCard('a12'));
    await tester.tap(_tagCard('b3'));
    await tester.pump();
    await _switchTo(tester, '角色');
    await tester.tap(_tagCard('miku'));
    await tester.pump();
    expect(find.text('加入 (3)'), findsOneWidget);

    // 各类都在一排页签上;「其他」不放进来
    for (final label in ['画风', '角色', '场景', '法典']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('其他'), findsNothing);
    expect(find.text('画风 2'), findsNothing);
    await _switchTo(tester, '画风');

    await tester.tap(find.text('取消选择'));
    await tester.pumpAndSettle();
    // 底栏收起;回到画风页,刚才勾的也都放掉了
    expect(find.text('加入 (3)'), findsNothing);
    expect(tester.widget<TagCard>(_tagCard('a12')).selected, isFalse);
    expect(tester.widget<TagCard>(_tagCard('b3')).selected, isFalse);
  });

  testWidgets('左右滑整页切到相邻分类', (tester) async {
    await _open(tester);
    await _switchTo(tester, '画风');
    expect(_tagCard('a12'), findsOneWidget);
    await tester.fling(_tagCard('a12'), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(_tagCard('rain'), findsOneWidget);
    expect(_tagCard('a12'), findsNothing);
  });

  testWidgets('再打开时落在上次停的那一页', (tester) async {
    await _open(tester);
    await _switchTo(tester, '场景');
    expect(_tagCard('rain'), findsOneWidget);
    // 点空白关掉面板,再开
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(_tagCard('rain'), findsOneWidget);
  });
}

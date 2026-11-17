// 提示词卡分区行(369dp 宽):一格一行,操作照角色卡。
//
// 容易坏的几处:窄屏一行塞不下(名字签 + 预览 + 计数 + 两颗按钮)直接溢出;
// 删除没给撤销,或撤销没放回原位;主体那行冒出删除钮;点名字没先拿到手势,
// 被外层「点行进编辑器」抢走。
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/editor/editor_page.dart';
import 'package:plana_app/features/generate/generate_state.dart';
import 'package:plana_app/features/generate/prompt_presets.dart';
import 'package:plana_app/features/generate/widgets/common.dart'
    show RoundIconBtn;
import 'package:plana_app/features/generate/widgets/prompt_card.dart';
import 'package:plana_app/features/inspiration/public_tags.dart';
import 'package:plana_app/features/inspiration/tag_editor_page.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

class _Presets extends PromptPresetsNotifier {
  @override
  Future<PromptPresetsState> build() async =>
      const PromptPresetsState(presets: kDefaultPromptPresets);
}

class _Library extends TagLibrary {
  _Library(this.seed);

  final List<TagEntry> seed;

  @override
  Future<TagLibraryState> build() async => TagLibraryState(entries: seed);
}

const _a12 = TagEntry(
  id: 't1',
  category: TagCategory.artist,
  name: 'A12',
  positive: 'artist:wlop, artist:ask, year 2024',
);

/// 加进来之后库里那条改过词的 [_a12]。
const _a12Edited = TagEntry(
  id: 't1',
  category: TagCategory.artist,
  name: 'A12',
  positive: 'artist:wlop',
);

/// [id] 那一行里的 [icon] 按钮。
Finder _inRow(String id, IconData icon) => find.descendant(
  of: find.byKey(ValueKey('sec$id')),
  matching: find.byIcon(icon),
);

Future<GenerateNotifier> _pumpCard(
  WidgetTester tester, {
  List<TagEntry> library = const [],
}) async {
  tester.view.physicalSize = const Size(369 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      appStoresProvider.overrideWithValue(AppStores.ephemeral()),
      promptPresetsProvider.overrideWith(_Presets.new),
      tagLibraryProvider.overrideWith(() => _Library(library)),
      publicTagsProvider(
        TagCategory.artist,
      ).overrideWith((_) async => const []),
      publicTagsProvider(
        TagCategory.character,
      ).overrideWith((_) async => const []),
    ],
  );
  addTearDown(c.dispose);
  final gen = c.read(generateProvider.notifier);
  gen.setPromptPreset('none'); // 读数里不掺质量词
  gen.setPrompts(
    positive:
        '1girl, solo, silver hair, long hair, blue eyes, white dress, '
        'looking at viewer, smile',
    negative: 'lowres, bad anatomy',
  );
  gen.addEntrySections([_a12]);
  gen.addSection();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SingleChildScrollView(child: PromptCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return gen;
}

/// 工作区落盘是 800ms 防抖、提示条 4 秒,收尾前都走完。
Future<void> _settleTimers(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 5));

void main() {
  testWidgets('窄屏一格一行不溢出;画风条目自成一格,主体也有开关和删除', (tester) async {
    await _pumpCard(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('A12'), findsOneWidget);
    expect(find.text('主体'), findsOneWidget);
    expect(find.text('分区 1'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
    expect(find.byIcon(Icons.power_settings_new), findsNWidgets(3));
    await _settleTimers(tester);
  });

  testWidgets('名字签最多显示 6 个字', (tester) async {
    final gen = await _pumpCard(tester);
    gen.updateSection(gen.state.sections[1].id, name: '银发蓝眼白裙少女');
    await tester.pumpAndSettle();
    expect(find.text('银发蓝眼白裙'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _settleTimers(tester);
  });

  testWidgets('删除给撤销,撤销放回原位', (tester) async {
    final gen = await _pumpCard(tester);
    await tester.tap(_inRow(gen.state.sections[1].id, Icons.delete_outline));
    await tester.pumpAndSettle();
    expect([for (final s in gen.state.sections) s.name], ['主体', '分区 1']);
    expect(find.text('已删除「A12」'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect([for (final s in gen.state.sections) s.name], ['主体', 'A12', '分区 1']);
    await _settleTimers(tester);
  });

  testWidgets('停用后还能再点开;点名字先拿到手势弹改名', (tester) async {
    final gen = await _pumpCard(tester);
    final art = gen.state.sections[1].id;
    await tester.tap(_inRow(art, Icons.power_settings_new));
    await tester.pumpAndSettle();
    expect(gen.state.sections[1].enabled, isFalse);
    // 停用的那行预览带删除线
    TextDecoration? deco() => tester
        .widget<Text>(find.textContaining('artist:wlop'))
        .style
        ?.decoration;
    expect(deco(), TextDecoration.lineThrough);
    await tester.tap(_inRow(art, Icons.power_settings_new));
    await tester.pumpAndSettle();
    expect(gen.state.sections[1].enabled, isTrue);
    expect(deco(), isNot(TextDecoration.lineThrough));

    await tester.tap(find.text('分区 1'));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.byType(EditorPage), findsNothing);
    await tester.enterText(find.byType(TextField), ' 场景 ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(gen.state.sections.last.name, '场景');
    await _settleTimers(tester);
  });

  testWidgets('删到只剩主体,卡片回到两行预览', (tester) async {
    final gen = await _pumpCard(tester);
    final art = gen.state.sections[1].id, extra = gen.state.sections[2].id;
    await tester.tap(_inRow(art, Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_inRow(extra, Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(gen.state.sections, isEmpty);
    expect(find.text('主体'), findsNothing);
    expect(find.textContaining('1girl, solo'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('清空连分区一起清掉,撤销整组放回;清完没东西可清就不显示清空', (tester) async {
    final gen = await _pumpCard(tester);
    await tester.tap(find.byTooltip('清空提示词和分区'));
    await tester.pumpAndSettle();
    expect(gen.state.sections, isEmpty);
    expect(gen.state.prompt, isEmpty);
    expect(gen.state.negativePrompt, 'lowres, bad anatomy'); // 负面留着
    expect(find.text('已清空提示词和分区'), findsOneWidget);
    // 主提示词空了、也没分区:清空按钮收起来(提示条上那枚同款图标不算)
    final clearBtn = find.descendant(
      of: find.byType(PromptCard),
      matching: find.byIcon(Icons.delete_sweep_outlined),
    );
    expect(clearBtn, findsNothing);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect([for (final s in gen.state.sections) s.name], ['主体', 'A12', '分区 1']);
    expect(gen.state.prompt, startsWith('1girl, solo'));
    expect(clearBtn, findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('卡头同角色卡只有清空 / 灵感库 / +,贴右边;清空收起来也不往左缩', (tester) async {
    final gen = await _pumpCard(tester);
    double gap(String tip) =>
        tester.getRect(find.byType(PromptCard)).right -
        tester.getRect(find.byTooltip(tip)).right;
    expect(find.byTooltip('多选'), findsNothing); // 多选靠长按一格进
    expect(gap('添加分区'), closeTo(13, .01));
    await tester.tap(find.byTooltip('清空提示词和分区'));
    await tester.pumpAndSettle();
    expect(gen.state.sections, isEmpty);
    expect(gap('添加分区'), closeTo(13, .01));
    await _settleTimers(tester);
  });

  /// 长按 [from] 拿起来,分几步拖到 [to] 松手(排序列表要一步步过、让位
  /// 动画走完才会连着换位)。
  Future<void> drag(WidgetTester tester, Finder from, Offset to) async {
    final start = tester.getCenter(from);
    final g = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset.lerp(start, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
  }

  Rect rowOf(WidgetTester tester, String id) =>
      tester.getRect(find.byKey(ValueKey('sec$id')));

  /// 长按 [row](进多选)。
  Future<void> hold(WidgetTester tester, Finder row) async {
    await tester.longPress(row);
    await tester.pumpAndSettle();
  }

  testWidgets('长按只进多选,不拖动排序:按住拖过去顺序不变', (tester) async {
    final gen = await _pumpCard(tester);
    final before = [for (final s in gen.state.sections) s.id];
    expect(find.byIcon(Icons.drag_indicator), findsNothing); // 平时没有把手
    await drag(
      tester,
      find.text('分区 1'),
      rowOf(tester, 'main').topCenter + const Offset(0, 3),
    );
    expect([for (final s in gen.state.sections) s.id], before);
    expect(find.text('已选 1'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('长按一格进多选、勾上这一格;左边出把手,拖把手排序还在多选里', (tester) async {
    final gen = await _pumpCard(tester);
    final art = gen.state.sections[1];
    final extra = gen.state.sections[2];
    await hold(tester, find.text('A12'));
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.text('重命名'), findsNothing);
    expect(_inRow(art.id, Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
    // 把手和卡头的退出钮对齐
    expect(
      tester.getCenter(_inRow('main', Icons.drag_indicator)).dx,
      closeTo(tester.getCenter(find.byTooltip('退出多选')).dx, .01),
    );

    // 按下把手就能拖,不用长按
    final start = tester.getCenter(_inRow(extra.id, Icons.drag_indicator));
    final top = rowOf(tester, 'main').top + 3;
    final g = await tester.startGesture(start);
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset(start.dx, start.dy + (top - start.dy) * i / steps));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(
      [for (final s in gen.state.sections) s.id],
      [extra.id, 'main', art.id],
    );
    expect(find.text('已选 1'), findsOneWidget); // 还在多选里,勾的没变
    expect(_inRow(art.id, Icons.check), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('多选:勾两行合并,留最上面那行;撤销放回;做完退出多选', (tester) async {
    final gen = await _pumpCard(tester);
    final art = gen.state.sections[1];
    final extra = gen.state.sections[2];
    await hold(tester, find.text('A12'));
    // 多选态:卡头不放按钮,行尾换成勾选圈
    expect(find.byTooltip('灵感库'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget); // 只剩卡头那颗
    // 点名字也是勾选,不弹改名
    await tester.tap(find.text('分区 1'));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsNothing);
    expect(find.text('已选 2'), findsOneWidget);
    // 勾选圈和卡头最右那颗(合并)对齐
    expect(
      tester.getCenter(_inRow(art.id, Icons.check)).dx,
      closeTo(tester.getCenter(find.byTooltip('合并')).dx, .01),
    );

    await tester.tap(find.byTooltip('合并'));
    await tester.pumpAndSettle();
    expect([for (final s in gen.state.sections) s.id], ['main', art.id]);
    expect(find.text('已合并到「A12」'), findsOneWidget);
    expect(find.byTooltip('灵感库'), findsOneWidget); // 退回平时的卡头

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(
      [for (final s in gen.state.sections) s.id],
      ['main', art.id, extra.id],
    );
    await _settleTimers(tester);
  });

  testWidgets('多选:批量停用 / 删除连主体一起;删了主体,撤销连正向放回', (tester) async {
    final gen = await _pumpCard(tester);
    await hold(tester, find.text('主体'));
    await tester.tap(find.text('A12'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('停用'));
    await tester.pumpAndSettle();
    expect(gen.state.sections[0].enabled, isFalse);
    expect(gen.state.sections[1].enabled, isFalse);
    expect(find.byTooltip('启用'), findsOneWidget); // 勾着的都停了,这颗换成启用

    final prompt = gen.state.prompt;
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect([for (final s in gen.state.sections) s.name], ['分区 1']);
    expect(gen.state.prompt, isEmpty);
    expect(gen.state.negativePrompt, 'lowres, bad anatomy');
    expect(find.text('已删除 2 个分区'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect([for (final s in gen.state.sections) s.name], ['主体', 'A12', '分区 1']);
    expect(gen.state.prompt, prompt);
    await _settleTimers(tester);
  });

  testWidgets('多选:点卡头的退出,平时的卡头按钮回来', (tester) async {
    await _pumpCard(tester);
    await hold(tester, find.text('A12'));
    expect(find.text('已选 1'), findsOneWidget);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('灵感库'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.text('已选 1'), findsNothing);
    await _settleTimers(tester);
  });

  /// 长按 [names] 第一行进多选、再勾上其余几行,点「存到灵感库」。
  Future<void> openSave(WidgetTester tester, List<String> names) async {
    await hold(tester, find.text(names.first));
    for (final n in names.skip(1)) {
      await tester.tap(find.text(n));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('存到灵感库'));
    await tester.pumpAndSettle();
  }

  List<TagEntry> libOf(WidgetTester tester, TagCategory c) =>
      ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      ).read(tagLibraryProvider).value!.of(c);

  TagDraft? draftOf(WidgetTester tester) =>
      tester.widget<TagEditorPage>(find.byType(TagEditorPage)).draft;

  testWidgets('存到灵感库:画风格直接进新建画风页,词和空编号填好;存完回来多选已退出', (tester) async {
    await _pumpCard(
      tester,
      library: const [
        TagEntry(
          id: 'x',
          category: TagCategory.artist,
          name: 'A1',
          positive: 'artist:foo',
        ),
        _a12Edited,
      ],
    );
    await openSave(tester, ['A12']);
    expect(find.text('新建画风'), findsOneWidget);
    expect(draftOf(tester)?.name, 'A2'); // 来源条目名不算自己起的;编号避开库里的 A1
    expect(draftOf(tester)?.positive, 'artist:wlop, artist:ask, year 2024');
    await tester.tap(find.text('保存到本地'));
    await tester.pumpAndSettle();
    final e = libOf(tester, TagCategory.artist).last;
    expect(e.name, 'A2');
    expect(e.positive, 'artist:wlop, artist:ask, year 2024');
    expect(find.byType(TagEditorPage), findsNothing);
    expect(find.text('已选 1'), findsNothing); // 多选已退出
    await _settleTimers(tester);
  });

  testWidgets('存到灵感库:主体猜不出分类,落第一类;点标题换类别,词带过去', (tester) async {
    await _pumpCard(tester);
    await openSave(tester, ['主体']);
    expect(find.text('新建角色'), findsOneWidget);
    final d = draftOf(tester)!;
    expect(d.name, isEmpty); // 名字自己起
    expect(d.positive, startsWith('1girl, solo'));
    expect(d.negative, isEmpty); // 卡上负面那行不带
    // 标题可点:换到场景,词跟过去
    await tester.tap(find.text('新建角色'));
    await tester.pumpAndSettle();
    expect(find.text('其他'), findsNothing); // 同灵感库面板,不给「其他」
    await tester.tap(find.text('场景'));
    await tester.pumpAndSettle();
    expect(find.text('新建场景'), findsOneWidget);
    expect(draftOf(tester)!.positive, startsWith('1girl, solo'));
    await _settleTimers(tester);
  });

  testWidgets('存到灵感库:空格子不行;同分类里已有一样的词就提示那一条', (tester) async {
    await _pumpCard(tester, library: const [_a12]);
    await hold(tester, find.text('分区 1'));
    final btn = find.widgetWithIcon(RoundIconBtn, Icons.save_outlined);
    VoidCallback? onTap() => tester.widget<RoundIconBtn>(btn).onTap;
    expect(onTap(), isNull); // 只勾了空的
    await tester.tap(find.text('A12'));
    await tester.tap(find.text('分区 1'));
    await tester.pumpAndSettle();
    expect(onTap(), isNotNull);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.byType(TagEditorPage), findsNothing);
    expect(libOf(tester, TagCategory.artist), [_a12]);
    expect(find.text('灵感库里已有「A12」'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('存到灵感库:勾几格直接各存一条,不进新建页;已有的跳过', (tester) async {
    await _pumpCard(tester, library: const [_a12Edited]);
    await openSave(tester, ['A12', '主体', '分区 1']);
    expect(find.byType(TagEditorPage), findsNothing);
    final art = libOf(tester, TagCategory.artist);
    expect(art.last.name, 'A1'); // 画风格用新编号
    expect(art.last.positive, 'artist:wlop, artist:ask, year 2024');
    final chars = libOf(tester, TagCategory.character);
    expect(chars.single.name, '1girl'); // 主体猜不出:落第一类,名字取第一个词
    expect(find.text('已存 2 条到灵感库'), findsOneWidget);
    expect(find.text('已选 3'), findsNothing); // 多选已退出
    await _settleTimers(tester);

    // 再存一次:都已有
    await openSave(tester, ['A12', '主体']);
    expect(libOf(tester, TagCategory.artist), hasLength(2));
    expect(find.text('灵感库里都已有了'), findsOneWidget);
    await _settleTimers(tester);
  });
}

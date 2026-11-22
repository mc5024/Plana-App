// 胶片条条目进出时的滚动与动画:滚开时视野不动;画布跟随新任务时一次滑到头;
// 停在最左头或删的是视野里那张时,后面的图逐帧让开 / 补位,不跳。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/gallery/widgets/film_strip.dart';
import 'package:plana_app/features/gallery/widgets/result_thumb.dart';
import 'package:plana_app/features/generate/gen_jobs.dart';

/// 方图在胶片条上的一格:图宽 72 + 内衬与边框 8 + 分隔 8。
const _slot = 88.0;

const _job = GenJob(
  id: 'j1',
  kind: GenJobKind.normal,
  stage: GenJobStage.running,
  width: 64,
  height: 64,
  seq: 1,
  // 给定进度:不确定进度条会一直转,pumpAndSettle 等不到头
  step: 1,
  total: 10,
);

void main() {
  final bytes = File('assets/app_icon.png').readAsBytesSync();
  final all = [
    for (var i = 0; i < 16; i++)
      ResultImage(id: 'gen$i', width: 64, height: 64, seed: i, bytes: bytes),
  ];

  Widget strip({
    List<ResultImage>? results,
    List<GenJob> jobs = const [],
    String? selectedJobId,
  }) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: FilmStrip(
            results: results ?? all,
            selectedId: 'gen0',
            onSelect: (_) {},
            onShare: (_) {},
            onFavorite: (_) {},
            isFavorite: (_) => false,
            onDelete: (_) {},
            jobs: jobs,
            selectedJobId: selectedJobId,
          ),
        ),
      ),
    ),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ScrollController controllerOf(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!;

  double xOf(WidgetTester tester, String id) => tester
      .getTopLeft(
        find.byWidgetPredicate((w) => w is ResultThumb && w.result.id == id),
      )
      .dx;

  /// 逐帧看 [id] 的横坐标:单向移动、每帧挪得不多(没有跳),最后走到 [to]。
  Future<void> expectGlide(
    WidgetTester tester,
    String id, {
    required double from,
    required double to,
  }) async {
    expect(xOf(tester, id), closeTo(from, 1)); // 变化那一帧还在原地
    var last = from;
    for (var i = 0; i < 40 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final x = xOf(tester, id);
      expect((x - last).abs(), lessThan(_slot / 4), reason: '第 $i 帧跳了');
      expect((x - from).sign * (to - from).sign, greaterThanOrEqualTo(0));
      last = x;
    }
    await tester.pumpAndSettle();
    expect(xOf(tester, id), closeTo(to, 1));
  }

  Future<ScrollController> scrolledAway(WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(strip());
    await tester.pumpAndSettle();
    final scroll = controllerOf(tester);
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    return scroll;
  }

  testWidgets('画布没跟的新任务:视野里的图原地不动', (tester) async {
    final scroll = await scrolledAway(tester);
    await tester.pumpWidget(strip(jobs: const [_job]));
    expect(scroll.offset, closeTo(500 + _slot, 1));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(500 + _slot, 1));
  });

  testWidgets('画布跟随新任务:第一帧不跳,然后一路滑到头', (tester) async {
    final scroll = await scrolledAway(tester);
    await tester.pumpWidget(strip(jobs: const [_job], selectedJobId: 'j1'));
    expect(scroll.offset, closeTo(500 + _slot, 1));
    var last = scroll.offset;
    for (var i = 0; i < 40 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, lessThanOrEqualTo(last + .01));
      last = scroll.offset;
    }
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });

  testWidgets('停在最左头来了新任务:任务卡长出来,后面的图被推开', (tester) async {
    phone(tester);
    await tester.pumpWidget(strip());
    await tester.pumpAndSettle();
    final x0 = xOf(tester, 'gen0');
    await tester.pumpWidget(strip(jobs: const [_job]));
    await expectGlide(tester, 'gen0', from: x0, to: x0 + _slot);
    expect(controllerOf(tester).offset, 0);
  });

  testWidgets('停在最左头时任务卡消失:后面的图滑过去补位', (tester) async {
    phone(tester);
    await tester.pumpWidget(strip(jobs: const [_job]));
    await tester.pumpAndSettle();
    final x0 = xOf(tester, 'gen0');
    await tester.pumpWidget(strip());
    await expectGlide(tester, 'gen0', from: x0, to: x0 - _slot);
    expect(controllerOf(tester).offset, 0);
  });

  testWidgets('拖上去删掉:原位只剩空位收起,图不再冒出来', (tester) async {
    phone(tester);
    var results = all;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FilmStrip(
                  results: results,
                  selectedId: 'gen0',
                  onSelect: (_) {},
                  onShare: (_) {},
                  onFavorite: (_) {},
                  isFavorite: (_) => false,
                  onDelete: (id) => setState(
                    () => results = [
                      for (final r in results)
                        if (r.id != id) r,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final thumb = find.byWidgetPredicate(
      (w) => w is ResultThumb && w.result.id == 'gen1',
    );
    final x2 = xOf(tester, 'gen2');

    // 往上拖过分享那条,停在删除那条上松手
    final start = tester.getCenter(thumb);
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 400)); // 落点滑入
    final band = tester.getCenter(find.text('拖到这里删除'));
    await g.moveTo(Offset(start.dx, band.dy));
    await tester.pump();
    expect(find.text('松手删除'), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(results.any((r) => r.id == 'gen1'), isFalse);
    expect(thumb, findsNothing);
    await expectGlide(tester, 'gen2', from: x2, to: x2 - _slot);

    await tester.pump(const Duration(seconds: 4)); // 等「已删除」提示收走
    await tester.pumpAndSettle();
  });

  testWidgets('拖到收藏那条松手收藏;已收藏的写「取消收藏」', (tester) async {
    phone(tester);
    final favorites = <String>{'gen2'};
    final toggled = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FilmStrip(
                results: all,
                selectedId: 'gen0',
                onSelect: (_) {},
                onShare: (_) {},
                onFavorite: toggled.add,
                isFavorite: favorites.contains,
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> dragTo(String id, String band, String active) async {
      final start = tester.getCenter(
        find.byWidgetPredicate((w) => w is ResultThumb && w.result.id == id),
      );
      final g = await tester.startGesture(start);
      await g.moveBy(const Offset(0, -30));
      // 落点滑入:动画从下一帧才起跑,滑到位之前命中区和画面对不上
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final y = tester.getCenter(find.text(band)).dy;
      await g.moveTo(Offset(start.dx, y));
      await tester.pump();
      expect(find.text(active), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
    }

    await dragTo('gen1', '拖到这里收藏', '松手收藏');
    await dragTo('gen2', '拖到这里取消收藏', '松手取消收藏');
    expect(toggled, ['gen1', 'gen2']);
    // 三条自下而上:分享、收藏、删除
    final g = await tester.startGesture(
      tester.getCenter(
        find.byWidgetPredicate(
          (w) => w is ResultThumb && w.result.id == 'gen1',
        ),
      ),
    );
    await g.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 400));
    final share = tester.getCenter(find.text('拖到这里分享')).dy;
    final fav = tester.getCenter(find.text('拖到这里收藏')).dy;
    final del = tester.getCenter(find.text('拖到这里删除')).dy;
    expect(share, greaterThan(fav));
    expect(fav, greaterThan(del));
    await g.moveBy(const Offset(0, 30));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('删掉视野里的一张:右边的滑过去补位', (tester) async {
    phone(tester);
    await tester.pumpWidget(strip());
    await tester.pumpAndSettle();
    final x2 = xOf(tester, 'gen2');
    await tester.pumpWidget(
      strip(
        results: [
          for (final r in all)
            if (r.id != 'gen1') r,
        ],
      ),
    );
    await expectGlide(tester, 'gen2', from: x2, to: x2 - _slot);
    expect(controllerOf(tester).offset, 0);
  });
}

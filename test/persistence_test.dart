import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/store/storage_settings.dart';
import 'package:plana_app/features/editor/editor_models.dart';
import 'package:plana_app/features/editor/editor_state.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/generate/generate_state.dart';

/// 1×1 透明 PNG(最小合法字节,充当结果图/参考图)。
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<void> _until(
  Future<bool> Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await cond()) {
    if (DateTime.now().isAfter(end)) fail('等待落盘超时');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('工作台+图库:改状态→落盘→重启水合回环', () async {
    final root = Directory.systemTemp.createTempSync('plana_persist');
    addTearDown(() async {
      // Windows 句柄释放有延迟,重试删;删不掉留给系统清临时目录
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    // ---- 会话 1:改状态并落盘 ----
    final stores1 = await AppStores.open(rootOverride: root);
    final c1 = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores1)],
    );
    addTearDown(c1.dispose);

    final gen = c1.read(generateProvider.notifier);
    gen.setPrompts(positive: '1girl, {smile, blue eyes}', negative: 'lowres');
    gen.addCharacter();
    gen.updateCharacter(
      c1.read(generateProvider).characters.first.id,
      positive: 'red hair',
    );
    gen.addVibe(image: _png, name: '测试vibe', strength: 0.55);
    gen.setSize(1024, 1024);

    final gal = c1.read(galleryProvider.notifier);
    final added = gal.addResult(
      bytes: _png,
      width: 832,
      height: 1216,
      seed: 42,
      input: c1.read(generateProvider),
    );
    expect(added.hasInput, isTrue);

    stores1.flushNow(); // 模拟退后台立即落盘
    final stateFile = File('${root.path}/workspace/state.json');
    final indexFile = File('${root.path}/gallery/index.json');
    final imageFile = File('${root.path}/gallery/images/${added.id}.png');
    await _until(
      () async =>
          await stateFile.exists() &&
          await indexFile.exists() &&
          await imageFile.exists(),
    );

    // ---- 会话 2:重新装载,断言全部回来 ----
    final stores2 = await AppStores.open(rootOverride: root);
    final ws = stores2.workspace.initial;
    expect(ws, isNotNull);
    expect(ws!.prompt, '1girl, {smile, blue eyes}');
    expect(ws.negativePrompt, 'lowres');
    expect(ws.characters, hasLength(1));
    expect(ws.characters.first.positive, 'red hair');
    expect(ws.vibes, hasLength(1));
    expect(ws.vibes.first.name, '测试vibe');
    expect(ws.vibes.first.strength, 0.55);
    expect(ws.vibes.first.image, isNotNull); // 图片经 blob 仓回来
    expect(ws.params.width, 1024);
    // id 发号器续点:恢复后新 id 不与已恢复条目撞车
    expect(stores2.workspace.idSeq, greaterThan(100));

    final items = stores2.gallery.initialResults;
    expect(items, hasLength(1));
    expect(items.first.id, added.id);
    expect(items.first.seed, 42);
    expect(items.first.width, 832);
    expect(items.first.hasInput, isTrue);
    expect(items.first.bytes, isNull); // 懒读:索引不带像素
    expect(stores2.gallery.initialSelectedId, added.id);

    final bytes = await stores2.gallery.readImage(added.id);
    expect(bytes, isNotNull);
    expect(bytes, equals(_png));

    final input = await stores2.gallery.readInput(added.id);
    expect(input, isNotNull);
    expect(input!.prompt, '1girl, {smile, blue eyes}');
    expect(input.vibes, hasLength(1));
    expect(input.vibes.first.image, isNotNull);

    // 图库发号器续点:恢复后新增不与旧 id 撞车
    final c2 = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores2)],
    );
    addTearDown(c2.dispose);
    final again = c2
        .read(galleryProvider.notifier)
        .addResult(bytes: _png, width: 64, height: 64, seed: 7);
    expect(again.id, isNot(added.id));
    expect(c2.read(galleryProvider).results, hasLength(2));

    // 排空第二次落盘链再进 teardown,避免删目录撞上进行中的写句柄
    stores2.flushNow();
    final againFile = File('${root.path}/gallery/images/${again.id}.png');
    await _until(() => againFile.exists());
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  test('编辑器实时回写:编辑防抖后自动进创作页,undo/flush 即时生效', () async {
    final root = Directory.systemTemp.createTempSync('plana_writeback');
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    final stores = await AppStores.open(rootOverride: root);
    final c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(c.dispose);

    c.read(generateProvider.notifier).setPrompts(positive: 'old');
    final ed = c.read(editorProvider.notifier);
    ed.load(positive: 'old', negative: '', startPositive: true);

    ed.editActive('old, 1girl, ~scrapped~');
    expect(c.read(generateProvider).prompt, 'old'); // 防抖未到,尚未回写
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // 防抖到点自动回写,且定稿剔除禁用词
    expect(c.read(generateProvider).prompt, 'old, 1girl');

    ed.undo();
    ed.flushWriteBack(); // 离开编辑器/退后台路径:立即生效
    expect(c.read(generateProvider).prompt, 'old');
    stores.flushNow();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('禁用词跨会话存活:原文草稿随定稿落盘,外部改写即失效', () async {
    final root = Directory.systemTemp.createTempSync('plana_draft');
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    final stores1 = await AppStores.open(rootOverride: root);
    final c1 = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores1)],
    );
    final gen1 = c1.read(generateProvider.notifier);
    gen1.setPrompts(positive: 'a, b');
    final ed = c1.read(editorProvider.notifier);
    ed.load(positive: 'a, b', negative: '', startPositive: true);
    ed.editActive('a, ~b~');
    ed.flushWriteBack();

    final s1 = c1.read(generateProvider);
    expect(s1.prompt, 'a'); // 定稿剔除禁用词,发给 NAI 的干净
    expect(s1.promptRaw, 'a, ~b~'); // 草稿保住记号
    expect(pickEditorText(s1.promptRaw, s1.prompt), 'a, ~b~');

    stores1.flushNow();
    final stateFile = File('${root.path}/workspace/state.json');
    await _until(() async => stateFile.exists());
    c1.dispose();

    // 重启:草稿从存档回来,重进编辑器仍看得到禁用词
    final stores2 = await AppStores.open(rootOverride: root);
    final ws = stores2.workspace.initial;
    expect(ws, isNotNull);
    expect(ws!.prompt, 'a');
    expect(pickEditorText(ws.promptRaw, ws.prompt), 'a, ~b~');

    // 编辑器之外改写提示词(导入/灵感追加/清空)→ 草稿即刻作废,
    // 不会用陈年草稿顶掉用户的新内容
    final c2 = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores2)],
    );
    addTearDown(c2.dispose);
    c2.read(generateProvider.notifier).setPrompts(positive: 'a, c');
    final s2 = c2.read(generateProvider);
    expect(s2.promptRaw, '');
    expect(pickEditorText(s2.promptRaw, s2.prompt), 'a, c');
  });

  test('编辑器角色路由:角色会话只写该角色,不碰主提示词', () async {
    final root = Directory.systemTemp.createTempSync('plana_charroute');
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    final stores = await AppStores.open(rootOverride: root);
    final c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(c.dispose);

    final gen = c.read(generateProvider.notifier);
    gen.setPrompts(positive: 'main prompt', negative: 'main neg');
    gen.addCharacter();
    final id = c.read(generateProvider).characters.first.id;

    // 角色会话:文本进角色,主提示词必须纹丝不动(修复前这里会被静默覆盖)
    final ed = c.read(editorProvider.notifier);
    ed.load(positive: '', negative: '', startPositive: true, charId: id);
    ed.editActive('1girl, ~scrapped~');
    ed.flushWriteBack();
    final s1 = c.read(generateProvider);
    expect(s1.characters.first.positive, '1girl'); // 定稿剔除禁用词
    expect(s1.prompt, 'main prompt');
    expect(s1.negativePrompt, 'main neg');

    // 同一 notifier 换回主提示词会话:目标要跟着切回,且不牵连角色
    ed.load(positive: 'main prompt', negative: 'main neg', startPositive: true);
    ed.editActive('main prompt, extra');
    ed.flushWriteBack();
    final s2 = c.read(generateProvider);
    expect(s2.prompt, 'main prompt, extra');
    expect(s2.characters.first.positive, '1girl');

    stores.flushNow();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('清空图库:文件删净、发号器不复用、重载为空', () async {
    final root = Directory.systemTemp.createTempSync('plana_clear');
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    final stores = await AppStores.open(rootOverride: root);
    final c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(c.dispose);

    final gal = c.read(galleryProvider.notifier);
    final a = gal.addResult(bytes: _png, width: 8, height: 8, seed: 1);
    await stores.gallery.idle;
    final aFile = File('${root.path}/gallery/images/${a.id}.png');
    expect(aFile.existsSync(), isTrue);

    await gal.clearAll();
    await stores.gallery.idle;
    expect(aFile.existsSync(), isFalse);
    expect(c.read(galleryProvider).results, isEmpty);

    final b = gal.addResult(bytes: _png, width: 8, height: 8, seed: 2);
    expect(b.id, isNot(a.id)); // 发号器保留,id 不复用

    stores.flushNow();
    await stores.gallery.idle;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stores2 = await AppStores.open(rootOverride: root);
    expect([for (final r in stores2.gallery.initialResults) r.id], [b.id]);
  });

  test('批量删除:状态移除、文件同删、选中移到相邻图片', () async {
    final root = Directory.systemTemp.createTempSync('plana_delete');
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    final stores = await AppStores.open(rootOverride: root);
    final c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(c.dispose);

    final gal = c.read(galleryProvider.notifier);
    final ids = [
      for (var i = 0; i < 4; i++)
        gal.addResult(bytes: _png, width: 8, height: 8, seed: i).id,
    ];
    // 当前选中最新一张 ids[3];删掉它 + 最旧的 ids[0]
    gal.deleteResults([ids[3], ids[0]]);
    final s = c.read(galleryProvider);
    expect([for (final r in s.results) r.id], [ids[2], ids[1]]);
    expect(s.selectedId, ids[2]); // 选中第一张被删 → 下一张
    await stores.gallery.idle;
    expect(
      File('${root.path}/gallery/images/${ids[3]}.png').existsSync(),
      isFalse,
    );
    expect(
      File('${root.path}/gallery/images/${ids[2]}.png').existsSync(),
      isTrue,
    );

    // 删未选中的,选中不动;删不存在的 id 为空操作
    gal.deleteResults([ids[1]]);
    expect(c.read(galleryProvider).selectedId, ids[2]);
    gal.deleteResults(['gen999']);
    expect(c.read(galleryProvider).results, hasLength(1));

    // 全删光:选中归 null,重载为空
    gal.deleteResults([ids[2]]);
    expect(c.read(galleryProvider).results, isEmpty);
    expect(c.read(galleryProvider).selectedId, isNull);
    stores.flushNow();
    await stores.gallery.idle;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stores2 = await AppStores.open(rootOverride: root);
    expect(stores2.gallery.initialResults, isEmpty);
  });

  test('图库上限:超出裁最旧,文件同删', () async {
    final root = Directory.systemTemp.createTempSync('plana_cap');
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    final stores = await AppStores.open(rootOverride: root);
    final c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(c.dispose);

    await c.read(storageSettingsProvider.future); // 平台通道缺失 → 默认值
    await c
        .read(storageSettingsProvider.notifier)
        .patch((s) => s.copyWith(galleryCap: 3));

    final gal = c.read(galleryProvider.notifier);
    final ids = [
      for (var i = 0; i < 5; i++)
        gal.addResult(bytes: _png, width: 8, height: 8, seed: i).id,
    ];
    expect(c.read(galleryProvider).results, hasLength(3));
    expect(
      [for (final r in c.read(galleryProvider).results) r.id],
      [ids[4], ids[3], ids[2]], // 最新 3 张保留
    );
    await stores.gallery.idle;
    expect(
      File('${root.path}/gallery/images/${ids[0]}.png').existsSync(),
      isFalse, // 最旧的文件已删
    );
    expect(
      File('${root.path}/gallery/images/${ids[4]}.png').existsSync(),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  test('存档损坏按首启降级,不 brick 启动', () async {
    final root = Directory.systemTemp.createTempSync('plana_corrupt');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/workspace/state.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{oops');
    File('${root.path}/gallery/index.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('[]');

    final stores = await AppStores.open(rootOverride: root);
    expect(stores.workspace.initial, isNull);
    expect(stores.gallery.initialResults, isEmpty);
  });
}

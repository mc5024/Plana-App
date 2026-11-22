import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/gallery/gallery_search.dart';

Directory _tempRoot() {
  final root = Directory.systemTemp.createTempSync('plana_gallery_search');
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
  return root;
}

void _writeSnapshot(Directory root, String id, String prompt, String ref) {
  File('${root.path}/gallery/inputs/$id.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'v': 1,
        'refs': [ref],
        'state': {
          'prompt': prompt,
          'params': {'model': 'nai-diffusion-4-5-full'},
        },
      }),
    );
}

/// 轮询到 [done] 成立,最多约 5 秒。
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('检索索引回填:分批读快照补齐,并落盘', () async {
    final root = _tempRoot();
    for (var i = 0; i < 250; i++) {
      _writeSnapshot(root, 'gen$i', 'Blue_Sky, tag$i', 'blob$i');
    }
    final stores = await AppStores.open(rootOverride: root);
    final c = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(c.dispose);
    c.listen(gallerySearchProvider, (_, _) {});

    await _until(() {
      final s = c.read(gallerySearchProvider);
      return !s.building && s.byId.length == 250;
    });
    final s = c.read(gallerySearchProvider);
    expect(s.building, isFalse);
    expect(s.byId, hasLength(250));
    expect(s.byId['gen7']!.text, 'blue sky, tag7');
    expect(s.byId['gen7']!.model, 'nai-diffusion-4-5-full');

    var disk = <String, GallerySearchMeta>{};
    for (var i = 0; i < 50 && disk.length != 250; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      disk = await stores.gallery.readSearchIndex();
    }
    expect(disk, hasLength(250));
    expect(disk['gen249']!.text, 'blue sky, tag249');
  });

  test('快照引用的 blob 全部收齐', () async {
    final root = _tempRoot();
    for (var i = 0; i < 3; i++) {
      _writeSnapshot(root, 'gen$i', 'p$i', 'blob$i');
    }
    final stores = await AppStores.open(rootOverride: root);
    expect(await stores.gallery.liveRefs(), {'blob0', 'blob1', 'blob2'});
  });

  test('检索索引:日志重放、删除、并回 search.json 后内容不变', () async {
    final root = _tempRoot();
    final stores = await AppStores.open(rootOverride: root);
    final g = stores.gallery;
    GallerySearchMeta meta(String t) => (
      model: 'm',
      text: t,
      ids: const [],
      cards: const ['c'],
      folds: const [],
    );

    g.appendSearch({'gen1': meta('a'), 'gen2': meta('b')});
    g.appendSearchRemovals(['gen1']);
    g.appendSearch({'gen3': meta('c')});
    await g.idle;
    var m = await g.readSearchIndex();
    expect(m.keys, unorderedEquals(['gen2', 'gen3']));
    expect(m['gen2']!.cards, ['c']);

    await g.compactSearch();
    expect(File('${root.path}/gallery/search.v3.log').existsSync(), isFalse);
    m = await g.readSearchIndex();
    expect(m.keys, unorderedEquals(['gen2', 'gen3']));

    // 日志末行写到一半被杀:跳过坏行,其余照读
    File(
      '${root.path}/gallery/search.v3.log',
    ).writeAsStringSync('{"p":"gen4","m":"m","t":"d"}\n{"p":"gen5","m"');
    m = await g.readSearchIndex();
    expect(m.keys, unorderedEquals(['gen2', 'gen3', 'gen4']));

    await g.clearSearch();
    expect(await g.readSearchIndex(), isEmpty);
  });
}

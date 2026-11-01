import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

class _Library extends TagLibrary {
  _Library(this.initial);

  final List<TagEntry> initial;

  @override
  Future<TagLibraryState> build() async => TagLibraryState(entries: initial);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plana_tag_preview');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ProviderContainer> containerWith(List<TagEntry> entries) async {
    final c = ProviderContainer(
      overrides: [tagLibraryProvider.overrideWith(() => _Library(entries))],
    );
    addTearDown(c.dispose);
    await c.read(tagLibraryProvider.future);
    return c;
  }

  test('备份没带本机图:同条目的本机预览保留,http 预览按备份增删', () async {
    final local = File('${root.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    final c = await containerWith([
      TagEntry(
        id: 'a1',
        category: TagCategory.artist,
        name: '水彩',
        positive: 'artist:foo',
        previews: [local.path, 'http://p/1.jpg', 'http://p/old.jpg'],
      ),
    ]);

    await c.read(tagLibraryProvider.notifier).mergeBackup({
      'artist-style': [
        {
          'id': 'a1',
          'name': '水彩',
          'prompt': 'artist:foo',
          'previews': ['http://p/1.jpg', 'http://p/2.jpg'],
        },
      ],
    });

    final e = c.read(tagLibraryProvider).requireValue.entries.single;
    expect(e.previews, [local.path, 'http://p/1.jpg', 'http://p/2.jpg']);
    expect(local.existsSync(), isTrue);
  });

  test('备份带 base64 预览:落成本机文件,替换掉的旧本机图清理', () async {
    final old = File('${root.path}/old.jpg')..writeAsBytesSync([9]);
    final c = await containerWith([
      TagEntry(
        id: 'oc1',
        category: TagCategory.character,
        name: '角色',
        positive: '1girl',
        previews: [old.path],
      ),
    ]);
    final png = [137, 80, 78, 71, 1, 2, 3];

    await c.read(tagLibraryProvider.notifier).mergeBackup({
      'character': [
        {
          'id': 'oc1',
          'name': '角色',
          'positive': '1girl',
          'preview': 'data:image/png;base64,${base64Encode(png)}',
        },
        {
          'id': 'oc2',
          'name': '新角色',
          'positive': '1boy',
          'preview': 'data:image/png;base64,${base64Encode(png)}',
        },
      ],
    });

    final entries = c.read(tagLibraryProvider).requireValue.entries;
    for (final id in ['oc1', 'oc2']) {
      final e = entries.firstWhere((e) => e.id == id);
      expect(e.previews, hasLength(1));
      expect(e.previews.single, startsWith('${root.path}/tag_previews/'));
      expect(File(e.previews.single).readAsBytesSync(), png);
    }
    expect(old.existsSync(), isFalse);
  });
}

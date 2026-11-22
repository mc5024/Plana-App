import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/features/vibe_library/naiv4vibe_codec.dart'
    show vibeEncodingHashKey;
import 'package:plana_app/features/vibe_library/vibe_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plana_vibe_library');
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

  /// files/ 下放一条带原图和一条编码的 vibe,返回原图字节。
  List<int> writeVibeFile() {
    final png = img.encodePng(img.Image(width: 8, height: 4));
    Directory('${root.path}/vibe_library/files').createSync(recursive: true);
    File('${root.path}/vibe_library/files/v1.naiv4vibe').writeAsStringSync(
      jsonEncode({
        'identifier': 'novelai-vibe-transfer',
        'id': 'v1',
        'name': '晴空',
        'createdAt': 1000,
        'image': base64Encode(png),
        'encodings': {
          'v4-5full': {
            vibeEncodingHashKey(1): {
              'encoding': 'ENC',
              'params': {'information_extracted': 1},
            },
          },
        },
      }),
    );
    return png;
  }

  test('索引写坏:从文件重建条目、缩略图和编码缓存,索引写回完整', () async {
    final png = writeVibeFile();
    File(
      '${root.path}/vibe_library/index.json',
    ).writeAsStringSync('{"version":1,"entr');

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final list = await c.read(vibeLibraryProvider.future);

    final e = list.single;
    expect(e.id, 'v1');
    expect(e.name, '晴空');
    expect(e.createdAt, 1000);
    expect(e.imageHash, sha256.convert(png).toString());
    expect(e.supportedModels, ['v4-5full']);
    expect(
      File('${root.path}/vibe_library/thumbs/v1.png').existsSync(),
      isTrue,
    );
    expect(
      File(
        '${root.path}/vibe_encodings/${e.imageHash}_v4-5full_1.enc',
      ).readAsStringSync(),
      'ENC',
    );
    final idx = jsonDecode(
      File('${root.path}/vibe_library/index.json').readAsStringSync(),
    );
    expect((idx['entries'] as List).single['id'], 'v1');
  });

  test('连着几次写索引:排队落盘,最后一份完整且是最新的', () async {
    writeVibeFile();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(vibeLibraryProvider.future);
    final lib = c.read(vibeLibraryProvider.notifier);

    await Future.wait([
      lib.markUsed({'v1'}),
      lib.markUsed({'v1'}),
      lib.markUsed({'v1'}),
    ]);

    final idx = jsonDecode(
      File('${root.path}/vibe_library/index.json').readAsStringSync(),
    );
    final saved = (idx['entries'] as List).single as Map<String, dynamic>;
    expect(
      saved['lastUsedAt'],
      c.read(vibeLibraryProvider).requireValue.single.lastUsedAt,
    );
  });

  test('文件字节导入:后台落盘、出缩略图、灌编码;批量改标签写进文件', () async {
    final pngs = {
      'a': img.encodePng(img.Image(width: 8, height: 4)),
      'b': img.encodePng(img.Image(width: 4, height: 8)),
    };
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(vibeLibraryProvider.future);
    final lib = c.read(vibeLibraryProvider.notifier);

    List<int> vibe(String id, List<String> tags) => utf8.encode(
      jsonEncode({
        'identifier': 'novelai-vibe-transfer',
        'id': id,
        'name': id,
        'createdAt': 1000,
        'image': base64Encode(pngs[id]!),
        'tags': tags,
        'encodings': {
          'v4-5full': {
            vibeEncodingHashKey(1): {
              'encoding': 'ENC_$id',
              'params': {'information_extracted': 1},
            },
          },
        },
      }),
    );

    final got = await lib.importVibeFiles([
      Uint8List.fromList(vibe('a', ['x'])),
      Uint8List.fromList(utf8.encode('{坏的')),
      Uint8List.fromList(vibe('b', ['x', 'y'])),
    ]);
    expect([for (final e in got) e.id], ['a', 'b']);
    final a = got.first;
    expect(a.imageHash, sha256.convert(pngs['a']!).toString());
    expect(File('${root.path}/vibe_library/thumbs/a.png').existsSync(), isTrue);
    expect(
      File(
        '${root.path}/vibe_encodings/${a.imageHash}_v4-5full_1.enc',
      ).readAsStringSync(),
      'ENC_a',
    );

    await lib.renameTag('x', 'y');
    final b = jsonDecode(
      File('${root.path}/vibe_library/files/b.naiv4vibe').readAsStringSync(),
    );
    expect(b['tags'], ['y']);
    expect(
      c
          .read(vibeLibraryProvider)
          .requireValue
          .firstWhere((e) => e.id == 'a')
          .tags,
      ['y'],
    );
  });

  test('导入到一半被杀:没进索引的文件下次启动收回来', () async {
    writeVibeFile();
    File(
      '${root.path}/vibe_library/index.json',
    ).writeAsStringSync('{"version":1,"entries":[]}');

    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(vibeLibraryProvider.future);
    for (var i = 0; i < 100; i++) {
      if (c.read(vibeLibraryProvider).requireValue.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(c.read(vibeLibraryProvider).requireValue.single.id, 'v1');
  });
}

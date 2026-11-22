import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/profile/local_backup.dart';
import 'package:plana_app/features/vibe_library/naiv4vibe_codec.dart'
    show vibeEncodingHashKey;

class _Library extends TagLibrary {
  _Library(this.initial);

  final TagLibraryState initial;

  @override
  Future<TagLibraryState> build() async => initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plana_local_backup');
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

  Future<ProviderContainer> containerWith(TagLibraryState s) async {
    final c = ProviderContainer(
      overrides: [tagLibraryProvider.overrideWith(() => _Library(s))],
    );
    addTearDown(c.dispose);
    await c.read(tagLibraryProvider.future);
    return c;
  }

  test('灵感库导出成包、导进空库:预览原图从包里取回,标签池带上', () async {
    final png = [137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4];
    final pic = File('${root.path}/pic.jpg')..writeAsBytesSync(png);
    final src = await containerWith(
      TagLibraryState(
        entries: [
          TagEntry(
            id: 'a1',
            category: TagCategory.artist,
            name: '水彩',
            positive: 'artist:foo',
            previews: [pic.path, 'http://p/1.jpg'],
          ),
        ],
        pools: {
          TagCategory.artist: ['厚涂'],
        },
      ),
    );
    final zip = await src
        .read(localBackupProvider)
        .export(inspiration: true, vibes: false);
    final sha = sha256.convert(png).toString();

    final file = LocalBackupFile.open(zip.path);
    addTearDown(file.close);
    expect(file.inspirationCount, 1);
    expect(file.vibeCount, 0);
    expect(file.preview(sha), png);

    pic.deleteSync(); // 本机原图没了,只能从包里取
    final dst = await containerWith(const TagLibraryState());
    final r = await dst.read(localBackupProvider).importInspiration(file);
    expect(r.stat[TagCategory.artist]?.added, 1);
    final s = dst.read(tagLibraryProvider).requireValue;
    final e = s.entries.single;
    expect(e.previews.length, 2);
    expect(File(e.previews.first).readAsBytesSync(), png);
    expect(e.previews.last, 'http://p/1.jpg');
    expect(s.poolOf(TagCategory.artist), ['厚涂']);
  });

  test('Vibe 导出成包:文件本体合并缓存里的编码', () async {
    final files = Directory('${root.path}/vibe_library/files')
      ..createSync(recursive: true);
    File('${files.path}/v1.naiv4vibe').writeAsStringSync(
      jsonEncode({
        'identifier': 'novelai-vibe-transfer',
        'id': 'v1',
        'name': '晴空',
      }),
    );
    File('${root.path}/vibe_library/index.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'entries': [
          {
            'id': 'v1',
            'name': '晴空',
            'fileName': 'v1.naiv4vibe',
            'imageHash': 'abc',
          },
        ],
      }),
    );
    Directory('${root.path}/vibe_encodings').createSync();
    File(
      '${root.path}/vibe_encodings/abc_v4-5full_1.enc',
    ).writeAsStringSync('ENC');

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final zip = await c
        .read(localBackupProvider)
        .export(inspiration: false, vibes: true);

    final file = LocalBackupFile.open(zip.path);
    addTearDown(file.close);
    expect(file.vibeCount, 1);
    final raw =
        jsonDecode(utf8.decode(file.vibeFiles().single.content))
            as Map<String, dynamic>;
    expect(raw['name'], '晴空');
    expect(
      raw['encodings']['v4-5full'][vibeEncodingHashKey(1)]['encoding'],
      'ENC',
    );
  });

  test('不是本 App 的包:给出能看懂的错误', () async {
    final p = '${root.path}/other.zip';
    final enc = ZipFileEncoder()..create(p);
    enc.addArchiveFile(
      ArchiveFile.string('manifest.json', '{"identifier":"x"}'),
    );
    await enc.close();
    expect(await LocalBackupFile.isZip(p), isTrue);
    expect(
      () => LocalBackupFile.open(p),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('不是 Plana'),
        ),
      ),
    );

    final notZip = File('${root.path}/a.json')..writeAsStringSync('{}');
    expect(await LocalBackupFile.isZip(notZip.path), isFalse);
  });
}

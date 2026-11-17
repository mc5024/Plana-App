import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/net/google_drive.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/profile/drive_backup.dart';

class _Library extends TagLibrary {
  _Library(this.initial);

  final List<TagEntry> initial;

  @override
  Future<TagLibraryState> build() async => TagLibraryState(entries: initial);
}

/// 内存里的云端硬盘隐藏数据区。
class _FakeDrive implements DriveClient {
  final files =
      <String, ({String name, Uint8List bytes, Map<String, String> props})>{};
  final created = <String>[];
  var _next = 0;

  @override
  void close() {}

  @override
  Future<List<DriveFile>> list({String? nameContains}) async => [
    for (final e in files.entries)
      if (nameContains == null || e.value.name.contains(nameContains))
        (
          id: e.key,
          name: e.value.name,
          size: e.value.bytes.length,
          props: e.value.props,
        ),
  ];

  @override
  Future<int?> free() async => null;

  @override
  Future<String> createBytes(
    String name,
    Uint8List bytes, {
    String mime = 'application/octet-stream',
    Map<String, String>? props,
    void Function(int sent)? onSent,
  }) async {
    // 清单名带毫秒,同一毫秒里连着备份会撞名
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final id = 'f${_next++}';
    files[id] = (name: name, bytes: bytes, props: props ?? const {});
    created.add(name);
    onSent?.call(bytes.length);
    return id;
  }

  @override
  Future<String> createFile(
    String name,
    File file, {
    String mime = 'application/octet-stream',
    void Function(int sent)? onSent,
  }) async => createBytes(name, await file.readAsBytes(), onSent: onSent);

  @override
  Future<Uint8List> download(String id) async => files[id]!.bytes;

  @override
  Future<void> delete(String id) async => files.remove(id);

  List<String> names(String prefix) => [
    for (final f in files.values)
      if (f.name.startsWith(prefix)) f.name,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plana_drive');
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

  ProviderContainer containerWith(List<TagEntry> entries, _FakeDrive drive) {
    final c = ProviderContainer(
      overrides: [
        tagLibraryProvider.overrideWith(() => _Library(entries)),
        driveBackupProvider.overrideWith(
          (ref) => DriveBackup(ref, client: (_) => drive),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('只传云端硬盘没有的预览;清单留 3 份;没人引用的预览删掉', () async {
    final drive = _FakeDrive();
    final a = File('${root.path}/a.png')..writeAsBytesSync([1, 2, 3]);
    final b = File('${root.path}/b.png')..writeAsBytesSync([4, 5]);
    final entry = TagEntry(
      id: 'a1',
      category: TagCategory.artist,
      name: '水彩',
      positive: 'artist:foo',
      previews: [a.path],
    );
    final c = containerWith([entry], drive);
    await c.read(tagLibraryProvider.future);
    final backup = c.read(driveBackupProvider);

    Future<void> run() async =>
        backup.backup(await backup.plan(), inspiration: true, vibes: false);

    await run();
    expect(drive.names('p_'), hasLength(1));
    expect(drive.names('backup_'), hasLength(1));

    drive.created.clear();
    await run();
    expect(drive.created.single, startsWith('backup_')); // 预览没再传

    // 换成另一张图:新图传上,旧图还被前几份清单引用,先留着
    await c
        .read(tagLibraryProvider.notifier)
        .upsert(entry.copyWith(previews: [b.path]));
    await run();
    expect(drive.names('p_'), hasLength(2));
    expect(drive.names('backup_'), hasLength(3));

    // 再备份两次:引用旧图的清单都被挤掉,旧图删掉
    await run();
    await run();
    expect(drive.names('backup_'), hasLength(3));
    expect(drive.names('p_'), hasLength(1));
  });

  test('恢复:条目并入本机,预览从云端硬盘取回落成本机文件', () async {
    final drive = _FakeDrive();
    final pic = File('${root.path}/a.png')..writeAsBytesSync([7, 8, 9]);
    final src = containerWith([
      TagEntry(
        id: 'a1',
        category: TagCategory.artist,
        name: '水彩',
        positive: 'artist:foo',
        previews: [pic.path],
      ),
    ], drive);
    await src.read(tagLibraryProvider.future);
    final up = src.read(driveBackupProvider);
    await up.backup(await up.plan(), inspiration: true, vibes: false);
    pic.deleteSync();

    final dst = containerWith(const [], drive);
    await dst.read(tagLibraryProvider.future);
    final down = dst.read(driveBackupProvider);
    final snap = (await down.snapshot())!;
    expect(DriveBackup.entryCount(snap), 1);
    final r = await down.restore(snap, inspiration: true, vibes: false);
    expect(r.stat![TagCategory.artist]!.added, 1);

    final e = dst.read(tagLibraryProvider).requireValue.entries.single;
    expect(e.previews.single, startsWith('${root.path}/tag_previews/'));
    expect(File(e.previews.single).readAsBytesSync(), [7, 8, 9]);
  });

  test('只备份 Vibe 时灵感库沿用上一份清单,两块各记各的备份时间', () async {
    final drive = _FakeDrive();
    final c = containerWith([
      TagEntry(id: 'a1', category: TagCategory.artist, name: '水彩'),
    ], drive);
    await c.read(tagLibraryProvider.future);
    final backup = c.read(driveBackupProvider);
    expect(await backup.status(), (tags: null, vibes: null));

    await backup.backup(await backup.plan(), inspiration: true, vibes: false);
    final first = await backup.status();
    expect(first.tags?.count, 1);
    expect(first.vibes, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await backup.backup(await backup.plan(), inspiration: false, vibes: true);
    final second = await backup.status();
    expect(second.tags, first.tags); // 灵感库还是第一次那份
    expect(second.vibes?.count, 0);
    expect(second.vibes!.at.isAfter(first.tags!.at), isTrue);

    final snap = (await backup.snapshot())!;
    expect(DriveBackup.entryCount(snap), 1);
    expect(snap.vibes, isEmpty);
    expect(jsonDecode(jsonEncode(snap.body))['vibes'], isEmpty);
  });
}

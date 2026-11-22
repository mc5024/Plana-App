import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/net/remote_image.dart';

Uint8List _bytes(int n, {int fill = 7}) =>
    Uint8List.fromList(List.filled(n, fill));

void main() {
  // clear() 会碰 PaintingBinding(要倒掉内存图缓存),没这行整组直接抛
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory dir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plana_imgcache');
    dir = Directory('${root.path}/img_cache');
    RemoteImageStore.bind(root);
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<File> files() => dir.listSync().whereType<File>().toList();

  /// 按内容首字节找回落盘文件(文件名是 URL 哈希,测试里拿不到)。
  File fileWithFill(int fill) => files().firstWhere(
    (f) => f.readAsBytesSync().firstOrNull == fill,
    orElse: () => throw StateError('没找到 fill=$fill 的缓存文件'),
  );

  test('写入后按 URL 读回;不同 URL 互不串味', () async {
    await RemoteImageStore.write('https://x/a.png', _bytes(16, fill: 1));
    await RemoteImageStore.write('https://x/b.png', _bytes(16, fill: 2));
    expect((await RemoteImageStore.read('https://x/a.png'))!.first, 1);
    expect((await RemoteImageStore.read('https://x/b.png'))!.first, 2);
    expect(await RemoteImageStore.read('https://x/never.png'), isNull);
  });

  test('URL 哈希成文件名:带查询串/非 ASCII 也不炸文件系统', () async {
    const url = 'https://x/图 片.png?w=200&sig=a/b+c';
    await RemoteImageStore.write(url, _bytes(8));
    expect(await RemoteImageStore.read(url), hasLength(8));
    // 落盘名只有十六进制:原 URL 里的 / ? & 空格一个都没漏进路径
    final names = files().map((f) => f.uri.pathSegments.last).toList();
    expect(names, hasLength(1));
    expect(names.single, matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  test('原子写:不留 .tmp 残渣', () async {
    await RemoteImageStore.write('https://x/a', _bytes(32));
    expect(files().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('trim 按 mtime 从旧到新删到达标', () async {
    for (var i = 0; i < 5; i++) {
      await RemoteImageStore.write('https://x/$i', _bytes(1000, fill: i));
    }
    for (var i = 0; i < 5; i++) {
      fileWithFill(i).setLastModifiedSync(DateTime(2026, 1, 1 + i)); // 越小越旧
    }

    await RemoteImageStore.trim(limit: 2500);

    // 5000 字节要压到 ≤2500:删掉最旧的三个,留最新的两个
    final left = files();
    expect(left, hasLength(2));
    expect({for (final f in left) f.readAsBytesSync().first}, {3, 4});
  });

  test('trim 不超上限时一个都不删', () async {
    await RemoteImageStore.write('https://x/a', _bytes(100));
    await RemoteImageStore.trim(limit: 1 << 20);
    expect(files(), hasLength(1));
  });

  // 服务端给预览图发的是 ETag + `Cache-Control: no-cache`(作者换图 → mtime 变
  // → etag 变)。缓存这层不记验证器的话,同一个 URL 换了内容就永远拉不到新的,
  // 只能手动清缓存 —— 这组用例钉住「记住验证器 / 换了内容就换缓存键」。
  group('ETag 验证器', () {
    const url = 'https://x/preview';

    test('带 etag 写入 → 读得回来,且时刻是刚刚', () async {
      await RemoteImageStore.write(url, _bytes(8), etag: '"abc"');
      final v = await RemoteImageStore.validator(url);
      expect(v!.etag, '"abc"'); // 引号原样留着:If-None-Match 要逐字回传
      expect(DateTime.now().difference(v.at).inSeconds, lessThan(5));
    });

    test('没有 etag 就没有验证器(老缓存/服务端没发)', () async {
      await RemoteImageStore.write(url, _bytes(8));
      expect(await RemoteImageStore.validator(url), isNull);
    });

    test('后来一次响应没带 etag → 旧验证器要删掉,不能留着误判 304', () async {
      await RemoteImageStore.write(url, _bytes(8), etag: '"v1"');
      await RemoteImageStore.write(url, _bytes(8, fill: 9));
      expect(await RemoteImageStore.validator(url), isNull);
    });

    test('replaced 才换缓存键:首次下载不换,内容真变了才换', () async {
      final before = RemoteImageStore.versionOf(url);
      await RemoteImageStore.write(url, _bytes(8), etag: '"v1"');
      expect(RemoteImageStore.versionOf(url), before);
      await RemoteImageStore.write(
        url,
        _bytes(8, fill: 9),
        etag: '"v2"',
        replaced: true,
      );
      expect(RemoteImageStore.versionOf(url), before + 1);
    });

    test('immutable 记进旁文件;没给 etag 也有验证器', () async {
      await RemoteImageStore.write(
        url,
        _bytes(8),
        etag: '"i"',
        immutable: true,
      );
      final v = await RemoteImageStore.validator(url);
      expect(v!.immutable, isTrue);
      expect(v.etag, '"i"');

      await RemoteImageStore.write(
        'https://x/noetag',
        _bytes(8),
        immutable: true,
      );
      final w = await RemoteImageStore.validator('https://x/noetag');
      expect(w!.immutable, isTrue);
      expect(w.etag, isEmpty);
    });

    test('304 带 immutable:老验证器补记,etag 保留', () async {
      await RemoteImageStore.write(url, _bytes(8), etag: '"old"');
      expect((await RemoteImageStore.validator(url))!.immutable, isFalse);
      await RemoteImageStore.touchValidator(url, immutable: true);
      final v = await RemoteImageStore.validator(url);
      expect(v!.immutable, isTrue);
      expect(v.etag, '"old"');
    });

    test('trim 删主文件时验证器跟着走,不留孤儿', () async {
      await RemoteImageStore.write('https://x/old', _bytes(3000), etag: '"o"');
      // mtime 拉开,保证 old 先被淘汰
      fileWithFill(7).setLastModifiedSync(DateTime(2020));
      await RemoteImageStore.write('https://x/new', _bytes(100), etag: '"n"');
      await RemoteImageStore.trim(limit: 500);
      expect(await RemoteImageStore.read('https://x/old'), isNull);
      expect(await RemoteImageStore.validator('https://x/old'), isNull);
      // 留下的那份验证器不受影响
      expect((await RemoteImageStore.validator('https://x/new'))!.etag, '"n"');
    });
  });

  // LoRA 预览反复刷新那个 bug 的核心:「验过没有」得和「有没有 ETag」分开记。
  //
  // 服务端不给 ETag 时磁盘上根本没有旁文件,validator() 恒为 null。原来拿它
  // 当「没验过」,于是每次加载都回源 → 必然 200 → 无条件换缓存键 → provider
  // 相等性变化 → 重建 → 再加载 → 再回源,肉眼看就是图在不停刷新。
  group('回源新鲜期:与 ETag 无关', () {
    const url = 'https://x.test/no-etag.png';

    test('标记过就算刚验过,没标记过就该验', () {
      expect(
        RemoteImageStore.checkedRecently(url, const Duration(minutes: 1)),
        isFalse,
      );
      RemoteImageStore.markChecked(url);
      expect(
        RemoteImageStore.checkedRecently(url, const Duration(minutes: 1)),
        isTrue,
      );
    });

    test('窗口过了就重新该验', () {
      RemoteImageStore.markChecked(url);
      expect(RemoteImageStore.checkedRecently(url, Duration.zero), isFalse);
    });

    test('这个标记不依赖旁文件 —— 没写过 etag 也照样成立', () async {
      await RemoteImageStore.write(url, _bytes(8), etag: null);
      expect(await RemoteImageStore.validator(url), isNull); // 确实没有旁文件
      RemoteImageStore.markChecked(url);
      expect(
        RemoteImageStore.checkedRecently(url, const Duration(minutes: 1)),
        isTrue,
      );
    });

    test('各 URL 互不影响', () {
      RemoteImageStore.markChecked(url);
      expect(
        RemoteImageStore.checkedRecently(
          'https://x.test/other.png',
          const Duration(minutes: 1),
        ),
        isFalse,
      );
    });

    test('清空缓存后重新算', () async {
      RemoteImageStore.markChecked(url);
      await RemoteImageStore.clear();
      expect(
        RemoteImageStore.checkedRecently(url, const Duration(minutes: 1)),
        isFalse,
      );
    });
  });

  test('目录不可用时整层降级为空,读写清理都不抛', () async {
    // 绑到一个不可建的路径(父目录是文件),模拟拿不到 support 目录的极端情况
    final blocker = File('${root.path}/blocker')..writeAsStringSync('x');
    RemoteImageStore.bind(Directory(blocker.path));
    expect(await RemoteImageStore.read('https://x/a'), isNull);
    await RemoteImageStore.write('https://x/a', _bytes(8)); // 吞掉写失败
    await RemoteImageStore.trim();
  });
}

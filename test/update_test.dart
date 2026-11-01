import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plana_app/core/store/prefs_store.dart';
import 'package:plana_app/features/update/release_notes.dart';
import 'package:plana_app/features/update/update_service.dart';

/// 更新判定的纯逻辑。错了不会崩,只会"永远不提示"或"反复提示已装的版本" ——
/// 两种都是用户不会报、你也看不见的静默故障,所以钉在这里。
void main() {
  group('compareSemver', () {
    void newer(String a, String b) {
      expect(compareSemver(a, b), greaterThan(0), reason: '$a 应比 $b 新');
      expect(compareSemver(b, a), lessThan(0), reason: '$b 应比 $a 旧');
    }

    test('主次修订逐段按数字比', () {
      newer('1.0.1', '1.0.0');
      newer('1.1.0', '1.0.9');
      newer('2.0.0', '1.99.99');
    });

    test('**预发布段按数字比,不按字典序** —— beta.10 必须比 beta.9 新', () {
      // 字符串比会判反,这正是不能偷懒用 String.compareTo 的原因
      newer('1.0.0-beta.10', '1.0.0-beta.9');
      newer('1.0.0-beta.2', '1.0.0-beta.1');
    });

    test('带预发布标识的版本小于同号正式版', () {
      newer('1.0.0', '1.0.0-beta.1');
      newer('1.0.0', '1.0.0-rc.1');
    });

    test('预发布标识:数字段 < 字母段;前缀相同则段数少的更小', () {
      newer('1.0.0-beta', '1.0.0-1');
      newer('1.0.0-beta.1', '1.0.0-beta');
      newer('1.0.0-rc.1', '1.0.0-beta.1');
    });

    test('剥前导 v,忽略 +build 元数据', () {
      expect(compareSemver('v1.0.0', '1.0.0'), 0);
      expect(compareSemver('1.0.0+3', '1.0.0+9'), 0);
      newer('v1.0.1+1', '1.0.0+99');
    });

    test('缺段按 0 补(1.0 == 1.0.0)', () {
      expect(compareSemver('1.0', '1.0.0'), 0);
      newer('1.1', '1.0.5');
    });

    test('相等就是相等 —— 不能把自己判成有新版', () {
      expect(compareSemver('1.0.0-beta.1', 'v1.0.0-beta.1'), 0);
    });
  });

  group('isPrerelease', () {
    test('识别预发布', () {
      expect(isPrerelease('1.0.0-beta.1'), isTrue);
      expect(isPrerelease('v1.0.0'), isFalse);
      expect(isPrerelease('1.0.0+3'), isFalse);
    });
  });

  group('pickNewer', () {
    Map<String, dynamic> rel(
      String tag, {
      bool pre = false,
      bool draft = false,
    }) => {
      'tag_name': tag,
      'html_url': 'https://github.com/x/y/releases/tag/$tag',
      'name': '',
      'body': '',
      'prerelease': pre,
      'draft': draft,
    };

    test('挑出更新的那个', () {
      final r = pickNewer('1.0.0-beta.1', [rel('v1.0.0-beta.2', pre: true)]);
      expect(r?.tag, 'v1.0.0-beta.2');
    });

    test('同版本或更旧 → 无更新', () {
      expect(
        pickNewer('1.0.0-beta.2', [rel('v1.0.0-beta.2', pre: true)]),
        isNull,
      );
      expect(pickNewer('1.0.0', [rel('v0.9.0')]), isNull);
    });

    test('草稿不算数', () {
      expect(pickNewer('1.0.0', [rel('v2.0.0', draft: true)]), isNull);
    });

    test('正式版用户不会被推预发布', () {
      expect(pickNewer('1.0.0', [rel('v1.1.0-beta.1', pre: true)]), isNull);
      // 但正式版仍然推
      expect(pickNewer('1.0.0', [rel('v1.1.0')])?.tag, 'v1.1.0');
    });

    test('beta 用户照收 beta', () {
      final r = pickNewer('1.0.0-beta.1', [rel('v1.0.0-beta.2', pre: true)]);
      expect(r?.tag, 'v1.0.0-beta.2');
    });

    test('列表里混着旧版也能挑对(GitHub 按时间倒序,不保证版本序)', () {
      final r = pickNewer('1.0.0-beta.1', [
        rel('v0.9.0'),
        rel('v1.0.0-beta.3', pre: true),
      ]);
      expect(r?.tag, 'v1.0.0-beta.3');
    });

    test('脏数据条目跳过,不整体炸掉', () {
      final r = pickNewer('1.0.0', [
        {'no_tag': true},
        rel('v1.2.0'),
      ]);
      expect(r?.tag, 'v1.2.0');
    });

    test('展示名:release 标题为空时回落到 tag', () {
      final r = pickNewer('1.0.0', [rel('v1.2.0')]);
      expect(r?.display, 'v1.2.0');
    });
  });

  group('fetchLatestRelease', () {
    Future<GithubRelease?> fetch(
      int status, {
      String body = '[]',
      Map<String, String> headers = const {},
    }) => http.runWithClient(
      () => fetchLatestRelease('1.0.0', repo: 'x/y'),
      () => MockClient(
        (_) async => http.Response(body, status, headers: headers),
      ),
    );

    Matcher failsWith(String text) => throwsA(
      isA<UpdateException>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('200 且无更新 → null', () async {
      expect(await fetch(200), isNull);
    });

    test('限流 → 报错,不当成已是最新', () async {
      await expectLater(
        fetch(403, headers: {'x-ratelimit-remaining': '0'}),
        failsWith('上限'),
      );
      await expectLater(fetch(429), failsWith('上限'));
    });

    test('其他非 200(含 403 / 404)→ 报错', () async {
      await expectLater(fetch(403), failsWith('HTTP 403'));
      await expectLater(fetch(404), failsWith('HTTP 404'));
    });

    test('200 但不是 JSON → 报错', () async {
      await expectLater(fetch(200, body: '<html></html>'), failsWith('失败'));
    });
  });

  group('shouldAutoCheck', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('plana_update'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('从没查过 → 查', () {
      expect(shouldAutoCheck(PrefsStore.emptyForTest(tmp)), isTrue);
    });

    test('刚查过 → 不查;超过间隔 → 查', () async {
      final prefs = PrefsStore.emptyForTest(tmp);
      await markUpdateChecked(prefs);
      expect(shouldAutoCheck(prefs), isFalse);
      expect(shouldAutoCheck(prefs, interval: Duration.zero), isTrue);
    });

    test('存的值是脏数据 → 当作没查过,不要因此永远不检查', () async {
      final prefs = PrefsStore.emptyForTest(tmp);
      await prefs.write(key: 'update_last_check', value: 'oops');
      expect(shouldAutoCheck(prefs), isTrue);
    });
  });

  test('更新说明按块切:标题 / 粗体小标题 / 列表 / 正文', () {
    // 照 v1.1.0 的写法,GitHub 存的是 \r\n
    const raw =
        '## 新增\r\n\r\n**AI 助手(BETA)**\r\n\r\n- 底栏新增「AI」页\r\n'
        '- 支持 `1.2::a::` 写法\r\n  续一行\r\n\r\n---\r\n'
        '本次更新**旧版本**无法使用\r\n1. 第一步';
    final b = parseReleaseNotes(raw);
    expect(b.map((e) => e.kind).toList(), [
      NoteKind.heading,
      NoteKind.sub,
      NoteKind.item,
      NoteKind.item,
      NoteKind.para,
      NoteKind.item,
    ]);
    expect(b[0].text, '新增');
    expect(b[1].text, 'AI 助手(BETA)');
    expect(b[3].text, '支持 `1.2::a::` 写法\n续一行');
    expect(b[4].text, '本次更新**旧版本**无法使用'); // 行内粗体留给渲染
    expect(b[5].marker, '1.');
  });
}

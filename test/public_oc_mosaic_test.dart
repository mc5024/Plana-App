// 公共 OC 的预览打码:列表接口的 mosaic 字段,以及打码卡片的闭眼标。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plana_app/core/net/backend_client.dart';
import 'package:plana_app/features/inspiration/public_tags.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/inspiration/widgets/tag_card.dart';

void main() {
  test('mosaic 只认 true,缺省或其他值都不码', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'ocs': [
            {'en_name': 'a', 'tag_group': 'x', 'mosaic': true},
            {'en_name': 'b', 'tag_group': 'x'},
            {'en_name': 'c', 'tag_group': 'x', 'mosaic': 1},
            {'en_name': 'd', 'tag_group': 'x', 'mosaic': false},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final ocs = await http.runWithClient(
      () => BackendClient('http://backend.test').listPublicOcs('sid'),
      () => client,
    );
    expect(ocs.map((o) => o.mosaic), [true, false, false, false]);
  });

  test('我发布的打码条目并进「我的」时不带打码', () {
    const pub = [
      TagEntry(
        id: 'pub_a',
        category: TagCategory.character,
        name: 'A',
        publicId: 'a',
        createdBy: 'me',
        mosaic: true,
      ),
      TagEntry(
        id: 'pub_b',
        category: TagCategory.character,
        name: 'B',
        publicId: 'b',
        createdBy: 'other',
        mosaic: true,
      ),
    ];
    final mine = mergeMineTags(const [], 'me', pub);
    expect(mine.map((e) => e.name), ['A']);
    expect(mine.single.mosaic, isFalse);
    expect(pub.first.mosaic, isTrue, reason: '公共库那份照旧打码');
  });

  testWidgets('打码卡片正中有闭眼标,不码的没有', (tester) async {
    const e = TagEntry(
      id: 'pub_a',
      category: TagCategory.character,
      name: 'A',
      mosaic: true,
    );
    Widget card({required bool mosaic}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            height: 240,
            child: TagCard(
              entry: e,
              selected: false,
              mosaic: mosaic,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(mosaic: true));
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.pumpWidget(card(mosaic: false));
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });
}

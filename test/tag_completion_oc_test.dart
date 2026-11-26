// 补全里的画风与 OC 只检索本机灵感库,不再拉取后端公共库。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plana_app/features/editor/data/artist_oc_library.dart';
import 'package:plana_app/features/editor/data/local_tag_db.dart';
import 'package:plana_app/features/editor/data/tag_completion.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

const _base = 'http://backend.test';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

TagEntry _oc(
  String id,
  String name,
  String positive, {
  List<String> aliases = const [],
}) => TagEntry(
  id: id,
  category: TagCategory.character,
  name: name,
  positive: positive,
  aliases: aliases,
  origin: TagOrigin.local,
);

TagEntry _artist(
  String id,
  String name,
  String positive, {
  List<String> aliases = const [],
}) => TagEntry(
  id: id,
  category: TagCategory.artist,
  name: name,
  positive: positive,
  aliases: aliases,
  origin: TagOrigin.local,
);

final _localOcs = [
  _oc('character_1', '雪莉', 'local copy', aliases: ['sherry']),
  _oc('character_2', '初雪', 'first snow'),
  _oc('character_3', '冬雪', 'my winter'),
  _oc('character_4', '晴天', 'sunny'),
];

final _localArtists = [
  _artist('artist_1', '水彩画风', 'watercolor style', aliases: ['shuicai']),
  _artist('artist_2', '厚涂风', 'impasto style'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // 离线词库从 asset 读

  test('画风与 OC 仅查本机灵感库,不请求公共库接口', () async {
    final requestedPaths = <String>[];
    final client = MockClient((req) async {
      requestedPaths.add(req.url.path);
      if (req.url.path == '/api/tags/search') {
        return _json({'results': []});
      }
      return http.Response('{}', 404);
    });
    final tc = TagCompletion(
      baseUrl: _base,
      localDb: LocalTagDb(),
      artistOcLib: const ArtistOcLibrary(),
      localArtists: Future.value(_localArtists),
      localOcs: Future.value(_localOcs),
      client: client,
    );

    final ocRes = await tc.query('雪');
    expect(ocRes.ocs.map((s) => s.text), ['雪莉', '初雪', '冬雪']);
    expect(ocRes.ocs.map((s) => s.local), everyElement(isTrue));
    expect(ocRes.ocs.first.insertText, 'local copy');

    final styleRes = await tc.query('画风');
    expect(styleRes.artists.map((s) => s.text), ['水彩画风']);
    expect(styleRes.artists.single.insertText, 'watercolor style');
    expect(styleRes.artists.single.local, isTrue);

    final aliasRes = await tc.query('sherry');
    expect(aliasRes.ocs.map((s) => s.text), ['雪莉']);

    expect(requestedPaths, isNot(contains('/api/oc/list')));
    expect(requestedPaths, isNot(contains('/api/artists/list')));
    expect(requestedPaths, isNot(contains('/api/public/authors')));
  });

  test('后端连不上:本机画风与 OC 中英文都照样补', () async {
    final down = MockClient(
      (req) async => throw const SocketException('network down'),
    );
    final tc = TagCompletion(
      baseUrl: _base,
      localDb: LocalTagDb(),
      artistOcLib: const ArtistOcLibrary(),
      localArtists: Future.value(_localArtists),
      localOcs: Future.value([
        ..._localOcs,
        _oc('character_5', 'Kimono Girl', 'kimono girl tags'),
      ]),
      client: down,
    );

    final zh = await tc.query('雪');
    expect(zh.ocs.map((s) => s.text), ['雪莉', '初雪', '冬雪']);
    final style = await tc.query('shuicai');
    expect(style.artists.map((s) => s.text), ['水彩画风']);
    final en = await tc.query('kimono');
    expect(en.ocs.map((s) => s.text), ['Kimono Girl']);
    expect(en.tags.map((s) => s.text), contains('kimono'));
  });
}

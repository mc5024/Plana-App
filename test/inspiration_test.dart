import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';
import 'package:plana_app/features/inspiration/widgets/tag_filter_sheet.dart';

TagEntry _e(
  TagCategory c, {
  String id = 'x',
  String name = 'n',
  String positive = '',
  String negative = '',
  List<String> tags = const [],
  String? createdBy,
  Map<String, dynamic> extra = const {},
}) => TagEntry(
  id: id,
  category: c,
  name: name,
  positive: positive,
  negative: negative,
  tags: tags,
  createdAt: 1,
  createdBy: createdBy,
  extra: extra,
);

void main() {
  test('分类注册表:web id 与能力对齐', () {
    expect(tagCategoryDef(TagCategory.artist).webId, 'artist-style');
    expect(tagCategoryByWebId('artist-style'), TagCategory.artist);
    expect(tagCategoryDef(TagCategory.character).maxSelectable, 6);
    expect(tagCategoryDef(TagCategory.scene).hasPublic, isFalse);
    expect(tagCategoryDef(TagCategory.scene).maxSelectable, 20);
  });

  test('备份编码:画师串用 prompt,角色用 positive,场景带 subtypeId', () {
    final a = encodeBackupEntry(
      _e(TagCategory.artist, positive: 'wlop, {{thick}}'),
    );
    expect(a['prompt'], 'wlop, {{thick}}');
    expect(a['previews'], isEmpty);
    expect(a.containsKey('positive'), isFalse);

    // 收藏来的画师串带 URL 预览:备份往返不能丢
    // 备份只带可跨端的 http 预览,本机文件路径不外发
    final fav = encodeBackupEntry(
      TagEntry(
        id: 'f1',
        category: TagCategory.artist,
        name: 'B3',
        positive: 'x',
        previews: const ['http://h/p.jpg', '/data/local/tag_previews/a.jpg'],
        createdAt: 1,
      ),
    );
    expect(fav['previews'], ['http://h/p.jpg']);

    final c = encodeBackupEntry(_e(TagCategory.character, positive: '1girl'));
    expect(c['positive'], '1girl');

    final s = encodeBackupEntry(_e(TagCategory.scene, positive: 'rain'));
    expect(s['subtypeId'], 'scene');
  });

  test('备份解码:web 三种 shape 双读,base64 预览丢弃,未知字段透传', () {
    // web ArtistData(prompt + base64 previews + usageCount)
    final a = decodeBackupEntry(TagCategory.artist, {
      'id': 'a1',
      'name': 'A1',
      'prompt': 'artist:x',
      'previews': ['data:image/png;base64,AAAA'],
      'usageCount': 7,
      'isLocal': true,
    })!;
    expect(a.positive, 'artist:x');
    expect(a.previewUrl, isNull);
    expect(a.extra['usageCount'], 7);
    // 再编码时未知字段带回
    expect(encodeBackupEntry(a)['usageCount'], 7);

    // web OCData(positive + user)
    final o = decodeBackupEntry(TagCategory.character, {
      'id': 'o1',
      'name': '星野遥',
      'positive': '1girl, blue hair',
      'user': 'u9',
      'aliases': ['遥'],
    })!;
    expect(o.positive, '1girl, blue hair');
    expect(o.createdBy, 'u9');
    expect(o.aliases, ['遥']);

    // 公共 OC 原始 shape(tag_group / negative_prompt)也可读
    final p = decodeBackupEntry(TagCategory.character, {
      'id': 'o2',
      'name': 'x',
      'tag_group': '1boy',
      'negative_prompt': 'lowres',
    })!;
    expect(p.positive, '1boy');
    expect(p.negative, 'lowres');

    // 历史数据 publicId/added_by 有裸数字:宽松转字符串不崩
    final t = decodeBackupEntry(TagCategory.artist, {
      'id': 'a2',
      'name': 'A2',
      'prompt': 'y',
      'publicId': 123,
      'addedBy': 456,
    })!;
    expect(t.publicId, '123');
    expect(t.createdBy, '456');
  });

  test('条目 JSON 往返', () {
    final e = TagEntry(
      id: 'scene_a_b',
      category: TagCategory.scene,
      name: '雨夜街道',
      positive: 'rain, night, street',
      tags: const ['构图'],
      origin: TagOrigin.favorited,
      publicId: 'p1',
      previews: const ['http://h/x.jpg', 'http://h/y.jpg'],
      createdAt: 123,
      extra: const {'k': 'v'},
    );
    final back = TagEntry.fromJson(e.toJson())!;
    expect(back.category, TagCategory.scene);
    expect(back.name, e.name);
    expect(back.origin, TagOrigin.favorited);
    expect(back.publicId, 'p1');
    expect(back.previews, ['http://h/x.jpg', 'http://h/y.jpg']);
    expect(back.previewUrl, 'http://h/x.jpg');
    // 旧版单字段 previewUrl 迁入列表
    final legacy = TagEntry.fromJson({
      'id': 'l1',
      'category': 'scene',
      'name': 'x',
      'previewUrl': 'http://h/old.jpg',
    })!;
    expect(legacy.previews, ['http://h/old.jpg']);
  });

  test('备份互通:web ArtistData/OCData 往返后关键字段不丢', () {
    // 模拟 web 端上传的一条画风:prompt + tags + origin + publicId
    final decoded = decodeBackupEntry(TagCategory.artist, {
      'id': 'fav_1',
      'name': 'B3',
      'prompt': 'artist:y',
      'negative': 'lowres',
      'tags': ['厚涂'],
      'origin': 'favorited',
      'publicId': 'pub-9',
      'previews': ['http://h/p.jpg'],
      'usageCount': 3,
    })!;
    expect(decoded.origin, TagOrigin.favorited);
    expect(decoded.publicId, 'pub-9');
    expect(decoded.tags, ['厚涂']);
    final re = encodeBackupEntry(decoded);
    expect(re['prompt'], 'artist:y');
    expect(re['negative'], 'lowres');
    expect(re['origin'], 'favorited');
    expect(re['publicId'], 'pub-9');
    expect(re['tags'], ['厚涂']);
    expect(re['previews'], ['http://h/p.jpg']);
    expect(re['usageCount'], 3); // 未建模字段经 extra 透传
  });

  test('导出文件格式与 web 一致,解析校验分类与标识', () {
    final file = buildBackupFile(TagCategory.scene, [
      {'id': 's1', 'name': '雨夜'},
    ], exportedAt: '2026-07-19T10:00:00.000');
    expect(file['identifier'], 'tag-manager-backup');
    expect(file['version'], 1);
    expect(file['category'], 'scene');
    expect(file['count'], 1);

    final parsed = parseBackupFile(file);
    expect(parsed.cat, TagCategory.scene);
    expect(parsed.items.single['id'], 's1');

    // 非本备份文件 / 未知分类都要拒绝
    expect(() => parseBackupFile({'identifier': 'x'}), throwsFormatException);
    expect(
      () => parseBackupFile({
        'identifier': 'tag-manager-backup',
        'category': 'lora',
      }),
      throwsFormatException,
    );
  });

  test('画师编号建议:gap-filling', () {
    expect(suggestArtistCode({'A1', 'A2', 'B1'}), 'A3');
    expect(suggestArtistCode({for (var i = 1; i <= 99; i++) 'A$i'}), 'B1');
    expect(suggestArtistCode({}), 'A1');
  });

  test('自然序与字母分桶', () {
    final names = ['A10', 'B1', 'A2', 'A1']..sort(naturalCompare);
    expect(names, ['A1', 'A2', 'A10', 'B1']);
    expect(letterOfName('A17 厚涂'), 'A');
    expect(letterOfName('wlop'), 'W');
    expect(letterOfName('赛璐璐'), '#');
  });

  test('正向追加:整条命中跳过,否则整串追加并自动成组折叠', () {
    final a = _e(
      TagCategory.artist,
      name: 'wlop厚涂',
      positive: '{{wlop}}, thick paint',
    );
    // 空提示词直接放入,多枚标签包成以条目名命名的折叠
    expect(
      appendTagPositivesFolded('', [a]),
      '<#wlop厚涂: {{wlop}}, thick paint#>',
    );
    // token 已全命中(权重/下划线归一后)→ 跳过
    expect(
      appendTagPositivesFolded('wlop, thick_paint, 1girl', [a]),
      'wlop, thick_paint, 1girl',
    );
    // 部分命中 → 整串追加
    expect(
      appendTagPositivesFolded('wlop', [a]),
      'wlop, <#wlop厚涂: {{wlop}}, thick paint#>',
    );
    // 同批内两条目重复也去重
    expect(
      appendTagPositivesFolded('', [
        a,
        _e(TagCategory.artist, positive: 'wlop'),
      ]),
      '<#wlop厚涂: {{wlop}}, thick paint#>',
    );
    // 单枚标签不折(折一枚只是徒增记号)
    expect(
      appendTagPositivesFolded('', [
        _e(TagCategory.artist, name: 'x', positive: 'wlop'),
      ]),
      'wlop',
    );
    // 去重按**定稿**判:草稿里已有的折叠成员照样算命中
    expect(
      appendTagPositivesFolded('<#wlop厚涂: {{wlop}}, thick paint>', [a]),
      '<#wlop厚涂: {{wlop}}, thick paint>',
    );
  });

  test('负面追加:逐词去重,保留原词写法', () {
    final e1 = _e(TagCategory.artist, negative: 'lowres, bad hands');
    final e2 = _e(TagCategory.artist, negative: 'bad hands, watermark');
    expect(
      appendTagNegatives('lowres', [e1, e2]),
      'lowres, bad hands, watermark',
    );
    expect(appendTagNegatives('', [e1]), 'lowres, bad hands');
  });

  test('候选作者:只数署名的条目,昵称查不到就回显 QQ 号', () {
    final authors = collectTagAuthors(
      [
        _e(TagCategory.artist, id: '1', createdBy: '10001'),
        _e(TagCategory.artist, id: '2', createdBy: '10001'),
        _e(TagCategory.artist, id: '3', createdBy: ' 10001 '), // 首尾空白同一人
        _e(TagCategory.artist, id: '4', createdBy: '20002'),
        _e(TagCategory.artist, id: '5'), // 无主:不进候选
        _e(TagCategory.artist, id: '6', createdBy: '  '),
      ],
      const {'10001': '小明'},
    );
    expect(authors.map((a) => a.id), ['10001', '20002']); // 条目多的在前
    expect(authors.first.count, 3);
    expect(authors.first.label, '小明');
    expect(authors.last.label, '20002'); // 目录里没有 → 回显号码
  });

  test('作者补全:昵称和 QQ 号都能命中', () {
    const a = TagAuthor(id: '123456', nickname: '小明');
    expect(a.matches('小'), isTrue);
    expect(a.matches('3456'), isTrue);
    expect(a.matches('阿花'), isFalse);
    // 没昵称的按号码找
    expect(const TagAuthor(id: '654321').matches('6543'), isTrue);
  });

  test('作者署名:昵称(QQ 号),没昵称就只剩号码', () {
    expect(authorDisplay('12345', const {'12345': '小明'}), '小明(12345)');
    expect(authorDisplay('12345', const {}), '12345');
    expect(authorDisplay('12345', const {'12345': ''}), '12345');
  });

  test('排序档:画风多一档编号,默认各回各的原排法', () {
    expect(defaultTagSort(TagCategory.artist), TagSort.number);
    expect(defaultTagSort(TagCategory.character), TagSort.time);
    expect(tagSortOptions(TagCategory.artist), contains(TagSort.number));
    expect(tagSortOptions(TagCategory.character), [
      TagSort.time,
      TagSort.author,
    ]);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

void main() {
  final cloth = TagCategoryDef.custom(
    id: 'c_1',
    label: '服装',
    iconName: 'Shirt',
    layout: TagCardLayout.portrait,
  );

  test('自定义类别按 id 认,和内置的不相等', () {
    expect(tagCategoryByWebId('c_1'), TagCategory.custom('c_1'));
    expect(tagCategoryByWebId('artist-style'), TagCategory.artist);
    expect(tagCategoryByWebId('unknown'), isNull);
    expect(TagCategory.custom('c_1').isCustom, isTrue);
    expect(TagCategory.scene.isCustom, isFalse);
  });

  test('类别定义来回转一遍不变', () {
    final back = TagCategoryDef.fromJson(cloth.toJson())!;
    expect(back.webId, 'c_1');
    expect(back.label, '服装');
    expect(back.layout, TagCardLayout.portrait);
    expect(back.hasPreview, isTrue);
    expect(TagCategoryDef.fromJson({'id': 'scene', 'label': 'x'}), isNull);
  });

  test('页签:按存下的顺序排,没列到的按默认顺序接在后面', () {
    final lib = TagLibraryState(
      customDefs: [cloth],
      order: const ['codex', 'artist-style'],
    );
    expect(lib.tabKeys, [
      'codex',
      'artist-style',
      'character',
      'scene',
      'c_1',
      'other',
    ]);
  });

  test('自定义类别条目进备份时带上 subtypeId 与可外发的预览', () {
    final e = TagEntry(
      id: 'x',
      category: TagCategory.custom('c_1'),
      name: '泳装',
      positive: 'swimsuit',
      previews: const ['https://a/b.png', '/local/c.png'],
    );
    final j = encodeBackupEntry(e);
    expect(j['subtypeId'], 'c_1');
    expect(j['positive'], 'swimsuit');
    expect(j['previews'], ['https://a/b.png']);
    final back = decodeBackupEntry(TagCategory.custom('c_1'), j)!;
    expect(back.category, TagCategory.custom('c_1'));
    expect(back.positive, 'swimsuit');
  });

  test('删掉的场景不出页签;内置改名进 defs、查表时生效', () {
    final lib = TagLibraryState(
      hidden: const {'scene', 'codex'},
      labels: const {'other': '杂项', 'codex': '图鉴'},
    );
    // 只有场景 / 其他算删除,法典不受影响
    expect(lib.visibleTabKeys, isNot(contains('scene')));
    expect(lib.visibleTabKeys, contains('codex'));
    final defs = lib.layoutJson()['defs'] as List;
    expect(defs, contains(equals({'id': 'other', 'label': '杂项'})));
    syncCustomTagCategories(const [], labels: lib.labels);
    addTearDown(() => syncCustomTagCategories(const []));
    expect(tagCategoryDef(TagCategory.other).label, '杂项');
    expect(codexTabLabel(), '图鉴');
  });
}

// 查角色、查 tag 的离线来源与 [角色候选] 预取:在一份小词库上跑。
//
// [角色候选] 这几道闸门(单字不认、通用词否决、热度门槛、缩写只认全汉字前缀)少一道
// 就会把一堆不相干的角色端给模型。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/assistant/tools/offline_tags.dart';
import 'package:plana_app/features/editor/data/tag_index.dart';

/// 行格式:tag、热度、中文、别名、类目;按热度降序。
const _tsv = '''
1girl\t5000000\t一个女孩\t\t0
white_hair\t900000\t白发\t\t0
blue_archive\t200000\t蔚蓝档案\t\t3
hatsune_miku\t131808\t初音未来\tmiku\t4
flandre_scarlet\t58619\t芙兰朵露·斯卡雷特\t\t4
wlop\t40000\t\t\t1
shiroko_(blue_archive)\t11429\t砂狼白子\t\t4
nekomusume\t1605\t猫娘\t\t4
fran_(ff12)\t546\t芙兰\t\t4
grogu\t300\t格罗古\t\t4
''';

OfflineTags _tags() {
  final bytes = TagIndexSpec.fromTsv(_tsv).encode();
  return OfflineTags(Future.value(TagIndex(ByteData.sublistView(bytes))));
}

void main() {
  group('角色候选', () {
    test('缩写认得出(芙兰 → 芙兰朵露·斯卡雷特),热度门槛把同名冷门角色拦掉', () async {
      final hits = await _tags().roleCandidates('画一张芙兰');
      expect([for (final h in hits) h.tag], ['flandre_scarlet']);
    });

    test('角色中文名恰好是通用词的一律不认', () async {
      expect(await _tags().roleCandidates('给我一张猫娘立绘'), isEmpty);
    });

    test('完整名字命中,按热度排', () async {
      final hits = await _tags().roleCandidates('画初音未来和芙兰朵露');
      expect([for (final h in hits) h.tag], ['hatsune_miku', 'flandre_scarlet']);
    });

    test('一个字都对不上就空着', () async {
      expect(await _tags().roleCandidates('画一片海'), isEmpty);
    });
  });

  group('查角色', () {
    test('中文名开头对上的在前,同档按热度', () async {
      final hits = await _tags().characters(query: '芙兰');
      expect([for (final h in hits) h.tag], ['flandre_scarlet', 'fran_(ff12)']);
    });

    test('给了出处,这个作品下的角色往前提', () async {
      final hits = await _tags().characters(query: '白子', origin: '蔚蓝档案');
      expect(hits.first.tag, 'shiroko_(blue_archive)');
    });

    test('只给出处:按 tag 末尾的作品名列', () async {
      final hits = await _tags().characters(origin: 'blue archive');
      expect([for (final h in hits) h.tag], ['shiroko_(blue_archive)']);
    });

    test('英文按标签名和别名查', () async {
      final hits = await _tags().characters(query: 'miku');
      expect(hits.first.tag, 'hatsune_miku');
    });
  });

  group('查 tag', () {
    test('中文名完全相同的排最前,可以按类目过滤,不出画师', () async {
      final tags = _tags();
      expect((await tags.tags('白发')).first.tag, 'white_hair');
      expect(await tags.tags('白发', category: 4), isEmpty);
      expect(await tags.tags('wlop'), isEmpty);
    });
  });
}

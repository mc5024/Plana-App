// 图库展开页的时间分组/时刻徽标 + 检索索引的归一化/抽取 + 入库快照的取舍。
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/editor/editor_models.dart' show outputOf;
import 'package:plana_app/features/gallery/gallery_dates.dart';
import 'package:plana_app/features/gallery/gallery_search.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/generate/models.dart';

void main() {
  group('时间分组', () {
    final now = DateTime(2026, 7, 30, 12, 0);

    int ms(DateTime d) => d.millisecondsSinceEpoch;

    test('日键与段头文案', () {
      final today = ms(DateTime(2026, 7, 30, 9, 30));
      final yesterday = ms(DateTime(2026, 7, 29, 23, 59));
      final thisYear = ms(DateTime(2026, 1, 2));
      final lastYear = ms(DateTime(2025, 12, 31));

      expect(galleryDayLabel(galleryDayKey(today), now), '今天');
      expect(galleryDayLabel(galleryDayKey(yesterday), now), '昨天');
      expect(galleryDayLabel(galleryDayKey(thisYear), now), '1月2日');
      expect(galleryDayLabel(galleryDayKey(lastYear), now), '2025年12月31日');
    });

    test('跨月的昨天(月初)', () {
      final n = DateTime(2026, 8, 1, 8, 0);
      final y = ms(DateTime(2026, 7, 31, 20, 0));
      expect(galleryDayLabel(galleryDayKey(y), n), '昨天');
    });

    test('无时间戳归「更早」,不画时刻', () {
      expect(galleryDayKey(0), 0);
      expect(galleryDayLabel(0, now), '更早');
      expect(galleryTimeBadge(0), '');
    });

    test('时刻徽标补零', () {
      expect(galleryTimeBadge(ms(DateTime(2026, 7, 30, 9, 5))), '09:05');
      expect(galleryTimeBadge(ms(DateTime(2026, 7, 30, 23, 59))), '23:59');
    });
  });

  group('搜索归一化', () {
    test('大小写/下划线/权重记号/括号/全角逗号', () {
      expect(
        normalizeSearchText('1.2::Long_Hair::, {Blue  Eyes}, [x]，Tail'),
        'long hair, blue eyes, x,tail',
      );
    });

    test('保留冒号(artist:wlop 要搜得到)', () {
      expect(normalizeSearchText('Artist:WLOP'), 'artist:wlop');
    });

    test('换行归逗号(只换行不写逗号的提示词也切得开)', () {
      expect(
        normalizeSearchText('1girl\nlong hair,\n\nsmile'),
        '1girl, long hair, smile',
      );
    });

    test('查询词切分 AND 匹配', () {
      final text = normalizeSearchText('1girl, long_hair, blue eyes');
      expect(searchMatch(text, searchTerms('long hair')), isTrue);
      expect(searchMatch(text, searchTerms('LONG_HAIR, 1girl')), isTrue);
      expect(searchMatch(text, searchTerms('long hair, red')), isFalse);
      expect(searchMatch(text, searchTerms('')), isTrue); // 空查询全过
    });
  });

  group('快照轻量抽取', () {
    test('标准形状:模型 + 正向 + 角色正向(不带负向)', () {
      final m = metaOfSnapshotJson({
        'v': 1,
        'refs': const [],
        'state': {
          'prompt': '1girl, {Blue_Sky}',
          'negativePrompt': 'lowres',
          'characters': [
            {'positive': 'red eyes', 'negative': 'bad hands'},
            {'positive': ''},
          ],
          'params': {'model': 'NAI 4.5 Full', 'width': 832},
        },
      });
      expect(m, isNotNull);
      expect(m!.model, 'NAI 4.5 Full');
      expect(m.text, '1girl, blue sky, red eyes');
      expect(m.text.contains('lowres'), isFalse);
      expect(m.text.contains('bad hands'), isFalse);
    });

    test('params 缺失 → 模型空串(归「未知」桶)', () {
      final m = metaOfSnapshotJson({
        'state': {'prompt': 'solo', 'characters': const []},
      });
      expect(m!.model, '');
      expect(m.text, 'solo');
    });

    test('state 不是 map → null', () {
      expect(metaOfSnapshotJson({'state': 'oops'}), isNull);
      expect(metaOfSnapshotJson(const {}), isNull);
    });

    // 禁用的角色卡没发出去,图里没有它 —— 进了索引就会搜到没画的东西、
    // 按角色分组归错。升级前的老快照盘上还带着它们,抽取这一道必须兜住。
    test('老快照里禁用的角色卡不进索引;缺 enabled 键按启用算', () {
      final m = metaOfSnapshotJson({
        'state': {
          'prompt': '1girl',
          'characters': [
            {'positive': 'red eyes', 'enabled': true},
            {'positive': 'cat ears', 'enabled': false},
            {'positive': 'halo'}, // 老存档没这个键
          ],
        },
      });
      expect(m!.text, '1girl, red eyes, halo');
    });

    test('内存快照同样只收启用的', () {
      final s = GenerateState.initial().copyWith(
        prompt: '1girl',
        characters: const [
          CharacterPrompt(id: 'a', name: '小夜', positive: 'red eyes'),
          CharacterPrompt(
            id: 'b',
            name: '角色 2',
            positive: 'cat ears',
            enabled: false,
          ),
        ],
      );
      expect(metaOfInput(s).text, '1girl, red eyes');
    });

    test('来源:条目 id(分区 + 角色卡)、启用的角色卡名、进了载荷的折叠组名', () {
      const raw = '1girl, <#小夜: blue hair, red eyes#>, <#黑兔: ~pink hair~#>';
      final m = metaOfSnapshotJson({
        'state': {
          'prompt': outputOf(raw),
          'promptRaw': raw,
          'usedEntries': ['e1'],
          'characters': [
            {'name': '初音', 'positive': 'miku', 'source': 'e2'},
            {'name': '角色 2', 'positive': 'cat ears', 'enabled': false},
            {
              'name': '角色 3',
              'positive': 'halo',
              'positiveRaw': '<#旧条目: wings, halo#>',
            },
          ],
        },
      });
      expect(m!.ids, ['e1', 'e2']);
      expect(m.cards, ['初音', '角色 3'], reason: '停用的卡不算');
      expect(m.folds, ['小夜'], reason: '整组禁用的折叠没进载荷;草稿对不上定稿的过期了');

      final s = GenerateState.initial().copyWith(
        prompt: outputOf(raw),
        promptRaw: raw,
        usedEntries: const ['e1'],
        characters: const [
          CharacterPrompt(id: 'a', name: '初音', positive: 'miku', source: 'e2'),
        ],
      );
      final n = metaOfInput(s);
      expect(n.ids, ['e1', 'e2']);
      expect(n.cards, ['初音']);
      expect(n.folds, ['小夜']);
    });
  });

  group('入库快照', () {
    const on = CharacterPrompt(id: 'a', name: '小夜', positive: 'red eyes');
    const off = CharacterPrompt(
      id: 'b',
      name: '角色 7',
      positive: 'cat ears',
      enabled: false,
    );

    test('禁用的角色卡不入快照,启用的原样保留', () {
      final s = GenerateState.initial().copyWith(characters: const [on, off]);
      final snap = gallerySnapshotOf(s);
      expect(snap.characters.map((c) => c.id), ['a']);
      expect(snap.characters.single.name, '小夜');
      expect(snap.prompt, s.prompt, reason: '只动角色卡,别的一概不碰');
    });

    test('全都启用时不复制,原对象直接用', () {
      final s = GenerateState.initial().copyWith(characters: const [on]);
      expect(identical(gallerySnapshotOf(s), s), isTrue);
    });
  });
}

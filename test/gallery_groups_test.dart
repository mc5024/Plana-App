// 图库分组:按时间 / 按归属(角色、画风)分堆的纯函数 + 角色 / 画风两张命中表。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/util/prompt_tokens.dart';
import 'package:plana_app/features/gallery/gallery_groups.dart';
import 'package:plana_app/features/gallery/gallery_search.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/inspiration/public_tags.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

ResultImage img(String id, DateTime at) => ResultImage(
  id: id,
  width: 832,
  height: 1216,
  seed: 1,
  createdAt: at.millisecondsSinceEpoch,
);

GroupTag tag(String k, [String? label]) => (key: k, label: label ?? k);

void main() {
  group('按天分堆', () {
    test('键的首现序即堆序,段头文案照旧', () {
      final now = DateTime(2026, 9, 6, 12);
      final g = groupByDay([
        img('a', DateTime(2026, 9, 6, 10)),
        img('b', DateTime(2026, 9, 6, 9)),
        img('c', DateTime(2026, 9, 5, 23)),
      ], now);
      expect(g.map((e) => e.label), ['今天', '昨天']);
      expect(g.first.items.map((e) => e.id), ['a', 'b']);
    });

    test('无时间戳归「更早」', () {
      final g = groupByDay([
        img('a', DateTime(2026, 9, 6)),
        const ResultImage(id: 'z', width: 1, height: 1, seed: 0),
      ], DateTime(2026, 9, 6, 12));
      expect(g.last.label, '更早');
      expect(g.last.items.single.id, 'z');
    });
  });

  group('按归属分堆', () {
    // 时间:a 最新 → c 最旧
    final a = img('a', DateTime(2026, 9, 6, 12));
    final b = img('b', DateTime(2026, 9, 6, 11));
    final c = img('c', DateTime(2026, 9, 6, 10));

    test('一张多角色的图,每一堆里都看得到', () {
      final g = groupByTags(
        [a, b],
        {
          'a': [tag('ganyu_(genshin_impact)', '甘雨'), tag('keqing', '刻晴')],
          'b': [tag('keqing', '刻晴')],
        },
      );
      expect(g.map((e) => e.label), ['甘雨', '刻晴']);
      expect(g[0].items.map((e) => e.id), ['a']);
      // 双人图在刻晴那堆里也在,只归一边的话另一边的合集就是缺的
      expect(g[1].items.map((e) => e.id), ['a', 'b']);
    });

    test('堆序按堆内最新一张降序,未归类恒垫底', () {
      final g = groupByTags(
        [a, b, c],
        {
          // c 最旧却排在前面传入 —— 堆序看的是时间不是传入序
          'c': [tag('x')],
          'b': [tag('y')],
        },
      );
      expect(g.map((e) => e.key), ['y', 'x', kGalleryUngroupedKey]);
      expect(g.last.label, '未归类');
      expect(g.last.items.map((e) => e.id), ['a']);
    });

    test('堆内保持传入顺序(调用方已按新→旧)', () {
      final g = groupByTags(
        [a, b, c],
        {
          'a': [tag('x')],
          'b': [tag('x')],
          'c': [tag('x')],
        },
      );
      expect(g.single.items.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('归属表为空 / 全空列表 → 只有未归类,或什么都没有', () {
      expect(groupByTags([a, b], const {}).single.key, kGalleryUngroupedKey);
      expect(groupByTags(const [], const {}), isEmpty);
      // 有键但值是空表,等同于没归属
      expect(
        groupByTags([a], {'a': const []}).single.key,
        kGalleryUngroupedKey,
      );
    });

    test('显示名以先到的为准,键相同即同一堆', () {
      final g = groupByTags(
        [a, b],
        {
          'a': [tag('hakurei_reimu', '博丽灵梦')],
          'b': [tag('hakurei_reimu', '灵梦')],
        },
      );
      expect(g.single.label, '博丽灵梦');
      expect(g.single.items.length, 2);
    });
  });

  TagEntry entry(TagCategory c, String name, String positive) =>
      TagEntry(id: 'e_$name', category: c, name: name, positive: positive);

  /// 词库帖子数的替身:只点名几个大众词,其余一律当词库没收(0 帖)。
  int postCount(String t) =>
      const {
        '1girl': 6000000,
        'solo': 5000000,
        'smile': 2000000,
        'long hair': 1300000,
        'thighhighs': 900000,
        'red eyes': 800000,
        'blue hair': 700000,
        'white dress': 200000,
        'realistic': 23000,
      }[t] ??
      0;

  List<String> keys(List<GroupTag> hits) => [for (final h in hits) h.key];

  group('画风:画师整组都在', () {
    StyleMatcher style(List<TagEntry> es) =>
        StyleMatcher(es, postCount: postCount);
    List<String> hit(
      StyleMatcher m,
      String prompt, {
      Set<String> artists = const {},
      Set<String> ids = const {},
      Set<String> names = const {},
    }) => keys(
      m.match(tokenizeSet(prompt), artists: artists, ids: ids, names: names),
    );

    test('画师全在图里才算命中,少一个不算', () {
      final m = style([
        entry(TagCategory.artist, '冷淡水彩', 'artist:wlop, artist:ciloranko'),
      ]);
      expect(hit(m, '1girl, artist:wlop, artist:ciloranko, solo'), ['冷淡水彩']);
      // 只用了其中一个 —— 那不是这个画风,不能归进去
      expect(hit(m, '1girl, artist:wlop'), isEmpty);
    });

    test('共用画师的两个条目不互相串味', () {
      final m = style([
        entry(TagCategory.artist, 'A', 'artist:wlop, artist:ciloranko'),
        entry(TagCategory.artist, 'B', 'artist:wlop, artist:rella'),
      ]);
      expect(hit(m, 'artist:wlop, artist:rella, 1girl'), ['B']);
    });

    test('顺序无关(画风串怎么排都是那几个画师)', () {
      final m = style([
        entry(TagCategory.artist, '阿米娅风', 'ke-ta, mika_pikazo'),
      ]);
      expect(hit(m, 'mika pikazo, 1girl, ke-ta'), ['阿米娅风']);
    });

    test('下划线/权重/括号写法同归一', () {
      final m = style([
        entry(TagCategory.artist, '阿米娅风', 'ke-ta, mika_pikazo'),
        entry(TagCategory.artist, '带账号', 'lobelia_(saclia), ezu (e104mjd)'),
      ]);
      for (final form in [
        'ke-ta, mika_pikazo',
        '{ke-ta}, 1.3::mika pikazo::',
        'KE-TA, Mika_Pikazo, 1girl',
      ]) {
        expect(hit(m, form), ['阿米娅风'], reason: form);
      }
      // 画师名后面带账号的,括号前有没有空格、有没有下划线三种写法都有
      for (final form in [
        'lobelia(saclia), ezu_(e104mjd)',
        'lobelia (saclia), ezu(e104mjd), 1girl',
      ]) {
        expect(hit(m, form), ['带账号'], reason: form);
      }
    });

    test('artist: 前缀带不带、大小写、冒号后有没有空格,都是同一个画师', () {
      final m = style([
        entry(TagCategory.artist, '带前缀', 'artist:wlop, artist:ciloranko'),
        entry(TagCategory.artist, '不带前缀', 'rella, yoneyama_mai'),
      ]);
      expect(hit(m, 'wlop, ciloranko'), ['带前缀']);
      expect(hit(m, 'Artist: rella, artist:yoneyama mai'), ['不带前缀']);
    });

    test('质量词、年份、通用词不参与判定,出图时顺手改掉也照样归类', () {
      final m = style([
        entry(
          TagCategory.artist,
          '写实',
          'artist:wlop, artist:ciloranko, masterpiece, very aesthetic, '
              'year 2024, realistic',
        ),
      ]);
      expect(
        hit(m, 'wlop, ciloranko, best quality, year 2025, 1girl'),
        ['写实'],
        reason: '年份改了、质量词换了、realistic 删了,画师还是那两个',
      );
      expect(
        hit(
          m,
          'artist:wlop, masterpiece, very aesthetic, year 2024, realistic',
        ),
        isEmpty,
        reason: '少了一个画师就不是这个画风,质量词凑齐了也不算',
      );
    });

    test('画师被别的条目整个包含时,让位给更具体的那个', () {
      final m = style([
        entry(TagCategory.artist, '双人', 'wlop, ciloranko'),
        entry(TagCategory.artist, '三人', 'wlop, ciloranko, rella'),
      ]);
      expect(hit(m, 'wlop, ciloranko, rella'), ['三人']);
      expect(hit(m, 'wlop, ciloranko, 1girl'), ['双人']);
    });

    test('一个画师都没有的条目(纯质量词串)只认来源,不做文本匹配', () {
      final m = style([
        entry(
          TagCategory.artist,
          '纯质感',
          'masterpiece, very aesthetic, realistic',
        ),
      ]);
      expect(hit(m, 'masterpiece, very aesthetic, realistic, 1girl'), isEmpty);
      expect(hit(m, 'masterpiece, 1girl', names: {'纯质感'}), ['纯质感']);
    });

    test('条目的画师不到图里画师的六成不算:那是另一个组合', () {
      final m = style([entry(TagCategory.artist, '单人', 'wlop')]);
      expect(hit(m, 'wlop, 1girl'), ['单人']);
      expect(
        hit(m, 'wlop, ciloranko, rella', artists: {'ciloranko', 'rella'}),
        isEmpty,
      );
      final three = style([
        entry(TagCategory.artist, '三人', 'wlop, ciloranko, rella'),
      ]);
      expect(
        hit(three, 'wlop, ciloranko, rella, ask', artists: {'ask'}),
        ['三人'],
        reason: '多一个画师照样算(四分之三)',
      );
    });

    test('别的条目里出现过的画师也算进图里的画师', () {
      final m = style([
        entry(TagCategory.artist, 'A', 'wlop'),
        entry(TagCategory.artist, 'B', 'ciloranko, rella'),
      ]);
      expect(hit(m, 'wlop, ciloranko, 1girl'), isEmpty);
    });

    test('记下来源的直接算:条目 id 或折叠组名,画师删了也认', () {
      final m = style([
        entry(TagCategory.artist, 'A', 'wlop, ciloranko, rella'),
      ]);
      expect(hit(m, 'wlop, 1girl', ids: {'e_A'}), ['A']);
      expect(hit(m, 'wlop, 1girl', names: {'A'}), ['A']);
      expect(hit(m, 'wlop, 1girl'), isEmpty);
    });

    test('被记下来源的条目整个包含的小条目让位', () {
      final m = style([
        entry(TagCategory.artist, '双人', 'wlop, ciloranko'),
        entry(TagCategory.artist, '三人', 'wlop, ciloranko, rella'),
      ]);
      expect(hit(m, 'wlop, ciloranko, 1girl', ids: {'e_三人'}), ['三人']);
    });

    test('artist: 前缀写的画师认得出来(词库没收的冷门画师靠它)', () {
      expect(
        taggedArtists(
          normalizeSearchText('1girl, Artist:Foo_Bar, artist: baz'),
        ),
        {'foo bar', 'baz'},
      );
    });

    test('没标签 / 没名字的条目一律剔掉,不当成「人人都用了」', () {
      // 空标签集若留着,判定恒真 —— 全库每张图都会归进这个条目
      final m = style([
        entry(TagCategory.artist, '空标签', '  '),
        entry(TagCategory.artist, '  ', 'a, b'),
      ]);
      expect(hit(m, '随便什么, 别的'), isEmpty);
      expect(hit(m, 'a, b'), isEmpty, reason: '没名字的条目也不该归组');
      expect(m.isEmpty, isTrue, reason: '剔干净后整表为空,provider 据此早退');
      expect(style(const []).isEmpty, isTrue);
    });

    test('同名条目(本地 + 收藏的公共副本)只出一条', () {
      final m = style([
        entry(TagCategory.artist, '同一个', 'a, b'),
        entry(TagCategory.artist, '同一个', 'a, b'),
      ]);
      expect(hit(m, 'a, b, c'), ['同一个']);
    });

    test('同名但内容不同时,先撞上的没过不挡住后一个', () {
      final m = style([
        entry(TagCategory.artist, '撞名', 'a, zzz'), // 不会命中
        entry(TagCategory.artist, '撞名', 'a, b'), // 该命中
      ]);
      expect(hit(m, 'a, b'), ['撞名']);
    });

    // 用户提示词里的画师名常常**不带 `artist:` 前缀**(`kazutake hazano,
    // lobelia(saclia), ezu (e104mjd), …`),所以「哪些是画师」不能靠前缀认 ——
    // 靠的是剔掉 NAI 质量词和词库里的大众词,剩下的就当画师。
    test('画师名不带前缀照样认', () {
      final m = style([
        entry(
          TagCategory.artist,
          'A1',
          'kazutake hazano, lobelia(saclia), ezu (e104mjd), hyatsu, '
              'very aesthetic, masterpiece, artist collaboration, year 2024',
        ),
      ]);
      expect(
        hit(
          m,
          'plana (blue archive), kazutake hazano, lobelia(saclia), '
          'ezu (e104mjd), hyatsu, very aesthetic, masterpiece, '
          'artist collaboration, year 2024',
        ),
        ['A1'],
      );
    });

    test('artist collaboration 这类控制标签不足以命中', () {
      final m = style([
        entry(
          TagCategory.artist,
          'A1',
          'kazutake hazano, artist collaboration',
        ),
      ]);
      expect(hit(m, '1girl, artist collaboration, masterpiece'), isEmpty);
    });
  });

  group('OC:加权覆盖率', () {
    // 10 枚:5 枚大众词(3 枚外观 + 2 枚服装,帖子数上几十万)+ 5 枚这个 OC 独有的
    // (词库没收,分量顶格)。独有的里 black ribbon choker 算服装配饰。
    const saya =
        'blue_hair, long_hair, red_eyes, crescent hair ornament, '
        'star-shaped pupils, white dress, thighhighs, black ribbon choker, '
        'halo, feathered wings';
    OcMatcher oc(List<TagEntry> es) => OcMatcher(es, postCount: postCount);
    List<String> hit(
      OcMatcher m,
      String prompt, {
      Set<String> ids = const {},
      Set<String> names = const {},
    }) => keys(m.match(tokenizeSet(prompt), ids: ids, names: names));
    final m = oc([entry(TagCategory.character, '小夜', saya)]);

    test('原样插进去,前后再加别的标签也认', () {
      expect(hit(m, '1girl, solo, $saya, smile, outdoors'), ['小夜']);
    });

    test('顺序打乱也认 —— 检索文本是主提示词在前、角色槽在后拼的,顺序当不了证据', () {
      final reversed = saya.split(', ').reversed.join(', ');
      expect(hit(m, '1girl, $reversed'), ['小夜']);
    });

    test('换一整套衣服也认:独有的外观特征还在', () {
      expect(
        hit(
          m,
          '1girl, blue hair, long hair, red eyes, crescent hair ornament, '
          'star-shaped pupils, halo, feathered wings, '
          'school uniform, pleated skirt, loafers',
        ),
        ['小夜'],
        reason: '10 枚里换掉 3 枚服装,按枚数只剩七成;但分量大头是独有特征,都还在',
      );
    });

    test('只剩大众词的另一个角色不认,凑够枚数也不行', () {
      expect(
        hit(
          m,
          '1girl, blue hair, long hair, red eyes, white dress, thighhighs, '
          'smile, holding umbrella',
        ),
        isEmpty,
      );
    });

    test('独有特征只剩两个就不认', () {
      expect(
        hit(
          m,
          '1girl, blue hair, long hair, red eyes, white dress, thighhighs, '
          'halo, black ribbon choker',
        ),
        isEmpty,
      );
    });

    test('至少对上 kOcMinKeep 枚:小条目要求全中,五枚的条目蹭上三枚也不算', () {
      final small = oc([
        entry(TagCategory.character, '三枚', 'cat ears, fang, heterochromia'),
        entry(
          TagCategory.character,
          '五枚',
          'fox ears, fox tail, kitsune mask, bell choker, shrine maiden',
        ),
      ]);
      expect(hit(small, 'cat ears, fang, 1girl'), isEmpty);
      expect(hit(small, 'cat ears, fang, heterochromia, 1girl'), ['三枚']);
      expect(
        hit(small, 'fox ears, fox tail, kitsune mask, 1girl'),
        isEmpty,
        reason: '分量占六成过了门槛,但只对上三枚',
      );
    });

    test('同一个角色的两个版本,只归覆盖最全的那个', () {
      final both = oc([
        entry(TagCategory.character, '小夜', saya),
        entry(
          TagCategory.character,
          '小夜·泳装',
          'blue_hair, long_hair, red_eyes, crescent hair ornament, '
              'star-shaped pupils, halo, feathered wings, '
              'white bikini, sarong, sandals',
        ),
      ]);
      expect(
        hit(
          both,
          '1girl, blue hair, long hair, red eyes, crescent hair ornament, '
          'star-shaped pupils, halo, feathered wings, white bikini, sarong, '
          'sandals, beach',
        ),
        ['小夜·泳装'],
        reason: '外观够得上「小夜」的门槛,但泳装版覆盖得更全',
      );
      expect(hit(both, '1girl, $saya'), ['小夜']);
    });

    test('两个不同的 OC 同框,两个都认', () {
      final two = oc([
        entry(TagCategory.character, '小夜', saya),
        entry(
          TagCategory.character,
          '黑兔',
          'pink hair, twin drills, heterochromia, gothic lolita, bat wings',
        ),
      ]);
      expect(
        hit(
          two,
          '2girls, $saya, pink hair, twin drills, heterochromia, '
          'gothic lolita, bat wings',
        ),
        ['小夜', '黑兔'],
      );
    });

    test('同名条目(本地 + 收藏的公共副本)只出一条', () {
      final dup = oc([
        entry(TagCategory.character, '小夜', saya),
        entry(
          TagCategory.character,
          '小夜',
          saya.replaceFirst('halo', 'cat ears'),
        ),
      ]);
      expect(hit(dup, '1girl, $saya'), ['小夜']);
    });

    test('没标签 / 没名字的条目一律剔掉', () {
      final empty = oc([
        entry(TagCategory.character, '空标签', '  '),
        entry(TagCategory.character, '  ', 'a, b, c, d'),
      ]);
      expect(empty.isEmpty, isTrue);
      expect(hit(empty, 'a, b, c, d'), isEmpty);
    });

    test('记下来源的直接算:换得面目全非也认', () {
      expect(hit(m, '1girl, school uniform', ids: {'e_小夜'}), ['小夜']);
      expect(hit(m, '1girl, school uniform', names: {'小夜'}), ['小夜']);
      expect(hit(m, '1girl, school uniform'), isEmpty);
    });

    test('折叠组名是清洗过的条目名,也对得上', () {
      final m = oc([entry(TagCategory.character, '小夜:泳装', saya)]);
      expect(hit(m, '1girl', names: {'小夜 泳装'}), ['小夜:泳装']);
    });

    test('同一个角色的几个版本:记下来源的那个优先于覆盖更全的', () {
      final both = oc([
        entry(TagCategory.character, '小夜', saya),
        entry(
          TagCategory.character,
          '小夜·泳装',
          'blue_hair, long_hair, red_eyes, crescent hair ornament, '
              'star-shaped pupils, halo, feathered wings, '
              'white bikini, sarong, sandals',
        ),
      ]);
      expect(
        hit(
          both,
          '1girl, blue hair, long hair, red eyes, crescent hair ornament, '
          'star-shaped pupils, halo, feathered wings, white bikini, sarong, '
          'sandals',
          names: {'小夜'},
        ),
        ['小夜'],
      );
    });

    test('记下来源的和文本命中的另一个 OC 同框,两个都留', () {
      final two = oc([
        entry(TagCategory.character, '小夜', saya),
        entry(
          TagCategory.character,
          '黑兔',
          'pink hair, twin drills, heterochromia, gothic lolita, bat wings',
        ),
      ]);
      expect(hit(two, '2girls, $saya', names: {'黑兔'}), ['小夜', '黑兔']);
    });

    test('词的分量:词库没收的顶格,越大众越轻', () {
      expect(ocTokenWeight(0), 1);
      expect(ocTokenWeight(1000), greaterThan(ocTokenWeight(100000)));
      expect(ocTokenWeight(1300000), lessThan(.04));
    });
  });

  // provider 层:一个 OC 条目都没有时,词库里的角色照样得归类。早先这里拿命中表
  // 回的常量空表直接往里加词库角色,一加就抛,整轮归属作废,全落「未归类」。
  test('没有 OC 条目时,词库角色照样归类', () async {
    TestWidgetsFlutterBinding.ensureInitialized(); // 词库从 asset 读
    final c = ProviderContainer(
      overrides: [
        gallerySearchProvider.overrideWith(
          () => _Search({
            'a': (
              model: 'nai-diffusion-4-5-full',
              text: normalizeSearchText('1girl, hakurei_reimu, smile'),
              ids: const [],
              cards: const [],
              folds: const [],
            ),
          }),
        ),
        tagLibraryProvider.overrideWith(() => _Library(const [])),
        myPublicTagsProvider.overrideWith(_Mine.new),
      ],
    );
    addTearDown(c.dispose);
    await c.read(tagLibraryProvider.future);
    await c.read(myPublicTagsProvider.future);
    final tags = await c.read(galleryCharTagsProvider.future);
    expect(keys(tags['a'] ?? const []), ['hakurei_reimu']);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'provider 认索引里的来源:角色卡名、条目 id、折叠组名',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized(); // 词库从 asset 读
      GallerySearchMeta meta({
        List<String> ids = const [],
        List<String> cards = const [],
        List<String> folds = const [],
      }) => (
        model: '',
        text: normalizeSearchText('1girl, smile'),
        ids: ids,
        cards: cards,
        folds: folds,
      );
      final c = ProviderContainer(
        overrides: [
          gallerySearchProvider.overrideWith(
            () => _Search({
              'card': meta(cards: ['小夜']),
              'id': meta(ids: ['e_小夜', 'e_水彩']),
              'fold': meta(folds: ['水彩']),
              'none': meta(),
            }),
          ),
          tagLibraryProvider.overrideWith(
            () => _Library(const [
              TagEntry(
                id: 'e_小夜',
                category: TagCategory.character,
                name: '小夜',
                positive:
                    'blue hair, halo, feathered wings, star-shaped pupils',
              ),
              TagEntry(
                id: 'e_水彩',
                category: TagCategory.artist,
                name: '水彩',
                positive: 'wlop, ciloranko',
              ),
            ]),
          ),
          myPublicTagsProvider.overrideWith(_Mine.new),
        ],
      );
      addTearDown(c.dispose);
      await c.read(tagLibraryProvider.future);
      await c.read(myPublicTagsProvider.future);
      final chars = await c.read(galleryCharTagsProvider.future);
      final styles = await c.read(galleryStyleTagsProvider.future);
      expect(keys(chars['card'] ?? const []), ['小夜']);
      expect(keys(chars['id'] ?? const []), ['小夜']);
      expect(chars['fold'], isNull, reason: '「水彩」是画风条目');
      expect(keys(styles['id'] ?? const []), ['水彩']);
      expect(keys(styles['fold'] ?? const []), ['水彩']);
      expect(styles['card'], isNull, reason: '角色卡名只认角色条目');
      expect(chars['none'], isNull);
      expect(styles['none'], isNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('GalleryGroupBy 的存档名稳定(UiPrefs 存的是 name)', () {
    expect(GalleryGroupBy.day.name, 'day');
    expect(GalleryGroupBy.character.name, 'character');
    expect(GalleryGroupBy.style.name, 'style');
    expect(GalleryGroupBy.day.label, '按时间');
    expect(GalleryGroupBy.character.label, '按角色');
    expect(GalleryGroupBy.style.label, '按画风');
    // 时间走分段列表,归属类的走堆叠封面墙
    expect(GalleryGroupBy.day.stacked, isFalse);
    expect(GalleryGroupBy.character.stacked, isTrue);
    expect(GalleryGroupBy.style.stacked, isTrue);
  });
}

class _Search extends GallerySearchNotifier {
  _Search(this.byId);
  final Map<String, GallerySearchMeta> byId;

  @override
  GallerySearchState build() => GallerySearchState(byId: byId);
}

class _Library extends TagLibrary {
  _Library(this.entries);
  final List<TagEntry> entries;

  @override
  Future<TagLibraryState> build() async => TagLibraryState(entries: entries);
}

class _Mine extends MyPublicTags {
  @override
  Future<Map<TagCategory, List<TagEntry>>> build() async => const {};
}

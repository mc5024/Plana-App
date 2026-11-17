import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/inspiration/codex/codex_artist_styles.dart';
import 'package:plana_app/features/inspiration/codex/codex_models.dart';

const _p = 'artist_nai5_personal_';

CodexEntry _e(String id, String title, List<String> path) =>
    CodexEntry(id: '$_p$id', title: title, tags: 'artist:$title', path: path);

CodexData _codex() => CodexData(
  meta: const CodexMeta(
    id: artistStylesCodexId,
    type: CodexType.string,
    title: 'v5',
  ),
  entries: [
    _e('may_1', 'alice', ['单画师词典', 'MayRain', 'set']),
    _e('hz_1', 'alice 2024', ['单画师词典', '花枝鱼', 'set']),
    _e('may_2', 'bob', ['单画师词典', 'MayRain', 'set']),
    _e('may_3', 'carol', ['单画师词典', 'MayRain', 'set']),
    _e('may_4', 'nobody', ['单画师词典', 'MayRain', 'set']),
    _e('mix_1', 'mix', ['画风组词典', 'pack']),
  ],
  tree: const [
    CodexNode('单画师词典', 5, [
      CodexNode('MayRain', 4, [CodexNode('set', 4, [])]),
      CodexNode('花枝鱼', 1, [CodexNode('set', 1, [])]),
    ]),
    CodexNode('画风组词典', 1, [CodexNode('pack', 1, [])]),
  ],
);

Map<String, dynamic> _styles() => {
  'schema': 3,
  'codexId': artistStylesCodexId,
  'idPrefix': _p,
  'parents': [
    {
      'name': '高光二次元',
      'groups': [0, 1],
    },
    {
      'name': '简约',
      'groups': [2],
    },
  ],
  'groups': [
    {'name': '逆光半厚涂', 'parent': 0},
    {'name': '光晕半厚涂', 'parent': 0},
    {'name': '极简平涂', 'parent': 1},
  ],
  'artists': [
    // alice:MayRain 是代表条,花枝鱼那条在 x 里;规范标题取 may_1
    {
      'e': 'may_1',
      'x': ['hz_1'],
      'c': 'may_1',
      'p': 50,
      'g': 0,
    },
    {'e': 'may_2', 'p': 300, 'g': 0},
    {'e': 'may_3', 'g': 2},
  ],
};

void main() {
  test('目录换成画风大类 › 小类,计数按画师,空小类不建,认不出的进未归类', () {
    final d = applyArtistStyles(_codex(), parseArtistStyles(_styles())!);
    final single = d.tree.first;
    expect(single.name, '单画师词典');
    expect(single.count, 4); // 3 位画师 + 1 条未归类
    expect([for (final n in single.children) n.name], [
      '高光二次元',
      '简约',
      '未归类',
    ]);
    expect(single.children.first.count, 2);
    expect([for (final n in single.children.first.children) n.name], [
      '逆光半厚涂',
    ]);
    expect(d.tree[1].name, '画风组词典');
  });

  test('一位画师一张卡:取花枝鱼例图、用规范标题;组内 post 降序', () {
    final d = applyArtistStyles(_codex(), parseArtistStyles(_styles())!);
    final list = d.onePerArtist(d.entries);
    expect([for (final e in list) e.id], [
      '${_p}may_2', // post 300
      '${_p}hz_1', // alice post 50,花枝鱼优先于 MayRain
      '${_p}may_3',
      '${_p}may_4',
      '${_p}mix_1',
    ]);
    expect(list[1].title, 'alice');
    expect(list[1].path, ['单画师词典', '高光二次元', '逆光半厚涂']);
    expect(list[3].path, ['单画师词典', '未归类']);
  });

  test('筛掉优先例图后退到另一来源', () {
    final d = applyArtistStyles(_codex(), parseArtistStyles(_styles())!);
    final list = d.onePerArtist([
      for (final e in d.entries)
        if (e.id != '${_p}hz_1') e,
    ]);
    expect(list.where((e) => e.title == 'alice').single.id, '${_p}may_1');
  });

  test('画风数据里的词条在法典里找不到:原样返回', () {
    final raw = _styles();
    (raw['artists'] as List).add({'e': 'gone', 'g': 0});
    final src = _codex();
    expect(identical(applyArtistStyles(src, parseArtistStyles(raw)!), src), true);
  });

  test('格式不认返回 null', () {
    expect(parseArtistStyles({..._styles(), 'schema': 2}), isNull);
    expect(parseArtistStyles({..._styles(), 'codexId': 'x'}), isNull);
  });
}

// 角色卡头像:从灵感角色库选来时带上的预览图。
//
// 容易坏的几处:存档往返丢了头像(重启后卡上只剩占位);点头像换人时旧的
// 编辑器草稿没清(那份草稿对的是上一个人的提示词);新条目没有预览图时
// 头像没清 —— 新名字挂着上一个人的脸。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/assistant/domain/conversation.dart';
import 'package:plana_app/features/generate/generate_state.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/state_codec.dart';
import 'package:plana_app/features/inspiration/public_tags.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

GenerateNotifier _notifier() {
  final c = ProviderContainer(
    overrides: [appStoresProvider.overrideWithValue(AppStores.ephemeral())],
  );
  addTearDown(c.dispose);
  return c.read(generateProvider.notifier);
}

void main() {
  test('工作台序列化往返保留头像,没头像的仍是 null', () async {
    final blobs = AppStores.ephemeral().blobs;
    final s = GenerateState.initial().copyWith(
      characters: const [
        CharacterPrompt(
          id: 'a',
          name: '初音',
          positive: 'hatsune_miku',
          avatar: 'https://example.com/miku.png',
        ),
        CharacterPrompt(id: 'b', name: '角色 2'),
      ],
    );
    final back = await decodeGenerateState(
      (await encodeGenerateState(s, blobs)).json,
      blobs,
    );
    expect(
      [for (final c in back.characters) c.avatar],
      ['https://example.com/miku.png', null],
    );
  });

  test('AI 写回的撤销快照往返保留头像', () {
    const snap = PromptSnapshot(
      characters: [
        CharacterPrompt(id: 'a', name: '初音', avatar: '/data/previews/a.png'),
      ],
    );
    final back = PromptSnapshot.fromJson(snap.toJson());
    expect(back.characters.single.avatar, '/data/previews/a.png');
  });

  test('从库里追加:带上头像和条目 id,名字取条目名', () {
    final gen = _notifier();
    final n = gen.addNamedCharactersFrom([
      (
        name: '初音',
        positive: 'hatsune_miku',
        negative: '',
        avatar: 'u1',
        source: 'e1',
      ),
      (
        name: '',
        positive: 'kagamine_rin',
        negative: '',
        avatar: null,
        source: null,
      ),
    ]);
    expect(n, 2);
    final chars = gen.state.characters;
    expect([for (final c in chars) c.name], ['初音', '角色 2']);
    expect([for (final c in chars) c.avatar], ['u1', null]);
    expect([for (final c in chars) c.source], ['e1', null]);
  });

  test('点头像换人:内容整份换掉、草稿清空,站位与开关不动', () {
    final gen = _notifier();
    gen.addCharacter();
    final id = gen.state.characters.single.id;
    gen.updateCharacter(
      id,
      positive: 'old',
      positiveRaw: '~old~',
      negativeRaw: 'x',
      enabled: false,
      position: 'B2',
    );

    gen.fillCharacterFrom(
      id,
      name: '初音',
      positive: 'hatsune_miku',
      negative: 'bad hands',
      avatar: 'u1',
      source: 'e1',
    );
    final c = gen.state.characters.single;
    expect(c.source, 'e1');
    expect(c.name, '初音');
    expect(c.positive, 'hatsune_miku');
    expect(c.negative, 'bad hands');
    expect(c.positiveRaw, isEmpty);
    expect(c.negativeRaw, isEmpty);
    expect(c.avatar, 'u1');
    expect(c.enabled, isFalse);
    expect(c.position, 'B2');
  });

  test('换成没有预览图的条目:头像清掉;条目没名字就留原名', () {
    final gen = _notifier();
    gen.addNamedCharactersFrom([
      (name: '初音', positive: 'a', negative: '', avatar: 'u1', source: 'e1'),
    ]);
    final id = gen.state.characters.single.id;

    gen.fillCharacterFrom(id, name: '', positive: 'b', negative: '');
    final c = gen.state.characters.single;
    expect(c.avatar, isNull);
    expect(c.source, isNull, reason: '来源跟着条目换');
    expect(c.name, '初音');
    expect(c.positive, 'b');
  });

  test('预览优先用公共库的 http,公共库里没有才用条目自带的', () {
    const fav = TagEntry(
      id: 'l1',
      category: TagCategory.character,
      name: '初音',
      publicId: 'miku',
      previews: ['/local/miku.png'],
    );
    const local = TagEntry(
      id: 'l2',
      category: TagCategory.character,
      name: '手写',
      previews: ['/local/own.png'],
    );
    const pub = TagEntry(
      id: 'pub_miku',
      category: TagCategory.character,
      name: '初音',
      publicId: 'miku',
      previews: ['https://example.com/miku.png'],
    );
    final map = publicPreviewsOf(const [pub]);
    expect(tagPreviewOf(fav, map), 'https://example.com/miku.png');
    expect(tagPreviewOf(local, map), '/local/own.png');
    expect(tagPreviewOf(fav, publicPreviewsOf(null)), '/local/miku.png');
  });
}

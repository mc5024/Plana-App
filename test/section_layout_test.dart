// 主提示词分区随图保存:写进 PNG 的 iTXt 块读得回来、官方 Comment 不受影响,
// 拼出来对得上才还原,两种导入方式落地正确。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/prompt_sections.dart';
import 'package:plana_app/features/generate/section_layout.dart';
import 'package:plana_app/features/import/image_metadata.dart';

Uint8List _png(String comment) {
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final t = ascii.encode(type);
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(t)
      ..add(data)
      ..add(
        (ByteData(
          4,
        )..setUint32(0, getCrc32([...t, ...data]))).buffer.asUint8List(),
      );
  }

  chunk(
    'IHDR',
    (ByteData(13)
          ..setUint32(0, 1)
          ..setUint32(4, 1)
          ..setUint8(8, 8))
        .buffer
        .asUint8List(),
  );
  chunk('IDAT', const [0x78, 1, 1, 0, 0, 0xFF, 0xFF, 0, 0, 0, 1]);
  chunk('tEXt', [...latin1.encode('Comment'), 0, ...utf8.encode(comment)]);
  chunk('IEND', const []);
  return out.toBytes();
}

var _ids = 0;
String _id() => 'n${_ids++}';

GenerateState _state() => GenerateState.initial().copyWith(
  prompt: '1girl, smile',
  negativePrompt: 'lowres',
  sections: const [
    PromptSection(
      id: 'a',
      name: '画风',
      positive: 'artist:wlop, smile',
      negative: 'lowres, blurry',
      artist: true,
    ),
    PromptSection.main(),
    PromptSection(id: 'b', name: '场景', positive: 'night'),
    PromptSection(id: 'c', name: '停用', positive: 'nsfw', enabled: false),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('快照只记进了载荷的格子,写进 PNG 读得回来', () async {
    final snap = composeSections(_state());
    expect(snap.prompt, 'artist:wlop, smile, 1girl, night');
    expect([for (final r in snap.composedSections) r.name], ['画风', '主体', '场景']);
    final comment = jsonEncode({
      'prompt': snap.prompt,
      'uc': snap.negativePrompt,
    });
    final png = withSectionLayout(_png(comment), snap.composedSections);
    // 再写一次只留一块
    final again = withSectionLayout(png, snap.composedSections);
    expect(again.length, png.length);

    final m = await extractImageMetadata(again);
    expect(m!.prompt, snap.prompt);
    final rows = decodeSectionLayout(m.sectionLayout)!;
    expect(rows.map((r) => r.name), ['画风', '主体', '场景']);
    expect(rows.first.artist, isTrue);
    expect(sectionLayoutMatches(rows, m.prompt, positive: true), isTrue);
    expect(
      sectionLayoutMatches(rows, m.negativePrompt, positive: false),
      isTrue,
    );
    expect(sectionLayoutMatches(rows, '1girl, night', positive: true), isFalse);
  });

  test('完全覆盖:换成勾的几格;新建分区:接在最后、已有的词不重复', () {
    final rows = decodeSectionLayout(
      encodeSectionLayout(composeSections(_state()).composedSections),
    )!;
    final base = GenerateState.initial().copyWith(
      prompt: 'old',
      negativePrompt: 'bad',
    );

    final over = importSectionsInto(
      base,
      rows,
      mainNegative: 'lowres',
      append: false,
      newId: _id,
    );
    expect(over.prompt, '1girl, smile');
    expect(over.negativePrompt, 'lowres');
    expect([for (final s in over.sections) s.name], ['画风', '主体', '场景']);
    expect(
      joinSections(over.sections, over.prompt, positive: true),
      'artist:wlop, smile, 1girl, night',
    );

    final noMain = importSectionsInto(
      base,
      [rows[0], rows[2]],
      append: false,
      newId: _id,
    );
    expect(noMain.prompt, isEmpty);
    expect(noMain.negativePrompt, 'bad');
    expect([for (final s in noMain.sections) s.name], ['画风', '场景']);

    final add = importSectionsInto(
      base.copyWith(prompt: 'cat'),
      rows,
      mainNegative: 'lowres, bad hands',
      append: true,
      newId: _id,
    );
    expect(add.prompt, 'cat');
    expect([for (final s in add.sections) s.name], ['主体', '画风', '分区 1', '场景']);
    expect(add.sections[1].artist, isTrue);
    // smile 已在画风格里、lowres 已在画风格负面里
    expect(add.sections[2].positive, '1girl');
    expect(add.sections[2].negative, 'bad hands');
  });
}

// WebP → PNG 还原:样张由 Pillow 造(仿 NAI:无损、RGBA、alpha 有 254、EXIF UserComment 里 6 个文字块,
// Description 含中文),期望像素是 Pillow 解出来的原始 RGBA —— 和后端 / web 对得上才算数。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/core/util/webp_to_png.dart';

final _bs = String.fromCharCode(92); // 反斜杠
final _text = {
  'Title': 'NovelAI generated image',
  'Description': '1girl, 狼耳, silver hair',
  'Software': 'NovelAI',
  'Source': 'NovelAI Diffusion V5 0ADF9AB7',
  'Generation time': '2.5',
  // Python json.dumps 默认把中文转义成 \uXXXX(NAI 的 Comment 也是),这一块是纯 ASCII → tEXt
  'Comment': '{"prompt": "1girl, ${_bs}u72fc${_bs}u8033, silver hair", "seed": 42, "steps": 28}',
};

/// 拆 PNG 的文字块:(类型, 关键字, 文本)
List<(String, String, String)> _texts(Uint8List png) {
  final v = ByteData.sublistView(png);
  final out = <(String, String, String)>[];
  for (var p = 8; p < png.length;) {
    final n = v.getUint32(p);
    final type = String.fromCharCodes(png, p + 4, p + 8);
    final d = Uint8List.sublistView(png, p + 8, p + 8 + n);
    if (type == 'tEXt' || type == 'iTXt') {
      final z = d.indexOf(0);
      final key = latin1.decode(d.sublist(0, z));
      out.add((
        type,
        key,
        type == 'tEXt' ? latin1.decode(d.sublist(z + 1)) : utf8.decode(d.sublist(z + 5)),
      ));
    }
    p += 12 + n;
  }
  return out;
}

void main() {
  final webp = File('test/fixtures/nai_sample.webp').readAsBytesSync();
  final rgba = File('test/fixtures/nai_sample.rgba').readAsBytesSync();

  test('认得出 WebP、alpha 和 EXIF 里的文字块', () {
    expect(isWebp(webp), isTrue);
    expect(isWebp(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0, 0, 0, 0])), isFalse);
    expect(webpHasAlpha(webp), isTrue);
    expect(readWebpText(webp), _text);
  });

  test('还原出的 PNG 像素和 alpha 与 Pillow 逐字节一致,文字块按官方顺序、中文写 iTXt', () {
    final png = webpToPng(webp);
    final back = img.PngDecoder().decode(png)!;
    expect((back.width, back.height, back.numChannels), (40, 28, 4));
    expect(back.getBytes(order: img.ChannelOrder.rgba), rgba);
    expect(_texts(png), [
      ('tEXt', 'Title', _text['Title']),
      ('iTXt', 'Description', _text['Description']),
      ('tEXt', 'Software', _text['Software']),
      ('tEXt', 'Source', _text['Source']),
      ('tEXt', 'Generation time', _text['Generation time']),
      ('tEXt', 'Comment', _text['Comment']),
    ]);
  });

  test('不是 WebP 原样返回', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2]);
    expect(identical(webpToPng(png), png), isTrue);
  });

  test('没有 alpha 时写成 RGB', () {
    final px = Uint8List.fromList([1, 2, 3, 255, 4, 5, 6, 255, 7, 8, 9, 255, 10, 11, 12, 255]);
    final back = img.PngDecoder().decode(encodePngWithText(px, 2, 2, false, {}))!;
    expect(back.numChannels, 3);
    expect(back.getBytes(order: img.ChannelOrder.rgb), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  });
}

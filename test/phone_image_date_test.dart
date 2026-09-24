import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/features/gallery/phone_image_date.dart';
import 'package:plana_app/features/gallery/save_pipeline.dart';
import 'package:plana_app/features/gallery/save_settings.dart';
import 'package:plana_app/features/import/image_metadata.dart';

List<({String type, Uint8List raw, Uint8List data})> chunks(Uint8List bytes) {
  final out = <({String type, Uint8List raw, Uint8List data})>[];
  final view = ByteData.sublistView(bytes);
  for (var i = 8; i + 12 <= bytes.length;) {
    final size = view.getUint32(i);
    final end = i + size + 12;
    expect(
      view.getUint32(end - 4),
      getCrc32(Uint8List.sublistView(bytes, i + 4, end - 4)),
    );
    out.add((
      type: String.fromCharCodes(bytes.sublist(i + 4, i + 8)),
      raw: Uint8List.sublistView(bytes, i, end),
      data: Uint8List.sublistView(bytes, i + 8, end - 4),
    ));
    i = end;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 9, 21, 13, 1, 5, 321);
  final source = img.Image(width: 8, height: 8, numChannels: 4)
    ..textData = {'Comment': '{"prompt":"keep me"}'};
  img.fill(source, color: img.ColorRgba8(123, 54, 67, 129));
  final png = img.encodePng(source);

  void expectDate(img.ExifData exif) {
    expect(exif.exifIfd[0x9003]!.toString(), '2026:09:21 13:01:05');
    expect(exif.exifIfd[0x9291]!.toString(), '321');
    final offset = at.timeZoneOffset.inMinutes;
    String pad(int value) => value.toString().padLeft(2, '0');
    expect(
      exif.exifIfd[0x9011]!.toString(),
      '${offset < 0 ? '-' : '+'}${pad(offset.abs() ~/ 60)}:${pad(offset.abs() % 60)}',
    );
  }

  test('PNG 仅增加有效 eXIf，像素压缩块及文本逐字节保持，含时区毫秒', () {
    final dated = withPhoneCaptureDate(
      png,
      at.millisecondsSinceEpoch,
      SaveFormat.png,
    );
    final parts = chunks(dated);
    expect(
      parts.where((c) => c.type != 'eXIf').map((c) => c.raw).toList(),
      chunks(png).map((c) => c.raw).toList(),
    );
    final exif = img.ExifData.fromInputBuffer(
      img.InputBuffer(parts.singleWhere((c) => c.type == 'eXIf').data),
    );
    expectDate(exif);
    expect(img.decodePng(dated)!.getBytes(), source.getBytes());
    expect(
      img.decodePng(dated)!.textData!['Comment'],
      source.textData!['Comment'],
    );
  });

  test('再次写日期替换已有 eXIf，保留已有 EXIF 其他字段', () {
    final dated = withPhoneCaptureDate(
      png,
      at.millisecondsSinceEpoch,
      SaveFormat.png,
    );
    final parts = chunks(dated);
    final exifBefore = img.ExifData.fromInputBuffer(
      img.InputBuffer(parts.singleWhere((c) => c.type == 'eXIf').data),
    );
    exifBefore.imageIfd[0x010e] = 'keep description';
    final exifOut = img.OutputBuffer();
    exifBefore.write(exifOut);
    final payload = exifOut.getBytes();
    final replacement = Uint8List(payload.length + 12);
    final replacementView = ByteData.sublistView(replacement);
    replacementView.setUint32(0, payload.length);
    replacement.setRange(4, 8, 'eXIf'.codeUnits);
    replacement.setRange(8, replacement.length - 4, payload);
    replacementView.setUint32(
      replacement.length - 4,
      getCrc32(Uint8List.sublistView(replacement, 4, replacement.length - 4)),
    );
    final withDescription =
        (BytesBuilder()
              ..add(dated.sublist(0, 8))
              ..add(
                parts
                    .expand((c) => c.type == 'eXIf' ? replacement : c.raw)
                    .toList(),
              ))
            .takeBytes();
    final twice = withPhoneCaptureDate(
      withDescription,
      at.millisecondsSinceEpoch,
      SaveFormat.png,
    );
    final exifs = chunks(twice).where((c) => c.type == 'eXIf');
    expect(exifs, hasLength(1));
    final exif = img.ExifData.fromInputBuffer(
      img.InputBuffer(exifs.single.data),
    );
    expectDate(exif);
    expect(exif.imageIfd[0x010e]!.toString(), 'keep description');
  });

  test('JPG 只补充日期，解码后的像素保持完全一致', () {
    final jpg = img.encodeJpg(source);
    final dated = withPhoneCaptureDate(
      jpg,
      at.millisecondsSinceEpoch,
      SaveFormat.jpg,
    );
    expectDate(img.decodeJpgExif(dated)!);
    expect(img.decodeJpg(dated)!.getBytes(), img.decodeJpg(jpg)!.getBytes());
  });

  test('清除生成信息后仅增加日期，不恢复原提示词', () async {
    final clean = await processForSave(
      png,
      const SaveSettings(meta: SaveMeta.clean),
    );
    final dated = withPhoneCaptureDate(
      clean,
      at.millisecondsSinceEpoch,
      SaveFormat.png,
    );
    expect(img.decodePng(dated)!.textData?['Comment'], isNull);
    expect(img.decodePng(dated)!.getBytes(), img.decodePng(clean)!.getBytes());
    expectDate(
      img.ExifData.fromInputBuffer(
        img.InputBuffer(
          chunks(dated).singleWhere((c) => c.type == 'eXIf').data,
        ),
      ),
    );
  });

  test('自定义提示词后补充生成日期，再导入仍完整读取自定义元数据', () async {
    const prompt = '1girl, pink hair, 喵喵自定义\nsmile, soft lighting';
    final original = img.Image(width: 160, height: 160, numChannels: 4)
      ..textData = {'Comment': '{"prompt":"old prompt"}'};
    img.fill(original, color: img.ColorRgba8(123, 54, 67, 255));
    final custom = await processForSave(
      img.encodePng(original),
      const SaveSettings(meta: SaveMeta.custom, customPrompt: prompt),
    );
    final before = await extractImageMetadata(custom);
    expect(before?.prompt, prompt);

    final dated = withPhoneCaptureDate(
      custom,
      at.millisecondsSinceEpoch,
      SaveFormat.png,
    );
    final after = await extractImageMetadata(dated);
    expect(after?.prompt, prompt);
    expect(after?.raw, before!.raw);
    expect(
      chunks(dated).where((c) => c.type != 'eXIf').map((c) => c.raw).toList(),
      chunks(custom).map((c) => c.raw).toList(),
    );
    expectDate(
      img.ExifData.fromInputBuffer(
        img.InputBuffer(
          chunks(dated).singleWhere((c) => c.type == 'eXIf').data,
        ),
      ),
    );

    // 再选清除也不能残留隐写提示词；补日期不应让导入器误认出生成信息。
    final clean = await processForSave(
      dated,
      const SaveSettings(meta: SaveMeta.clean),
    );
    final cleanDated = withPhoneCaptureDate(
      clean,
      at.millisecondsSinceEpoch,
      SaveFormat.png,
    );
    expect(await extractImageMetadata(cleanDated), isNull);
  });

  test('未知日期原样返回；损坏 PNG 明确失败，不输出半成品', () {
    expect(withPhoneCaptureDate(png, 0, SaveFormat.png), same(png));
    expect(
      () => withPhoneCaptureDate(
        png.sublist(0, png.length - 2),
        at.millisecondsSinceEpoch,
        SaveFormat.png,
      ),
      throwsFormatException,
    );
  });
}

import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:image/image.dart' as img;

import 'save_settings.dart';

/// 系统扫描相册会从文件重新读取拍摄时间，单写 MediaStore.DATE_TAKEN
/// 会被覆盖。给导出的副本补充 EXIF 时间、时区与毫秒，不重编码像素。
/// 本函数在原始/清除/自定义生成信息的处理之后调用，不恢复已清除的信息。
Uint8List withPhoneCaptureDate(
  Uint8List bytes,
  int createdAt,
  SaveFormat format,
) {
  if (createdAt <= 0) return bytes;
  if (format == SaveFormat.jpg) {
    final exif = img.decodeJpgExif(bytes) ?? img.ExifData();
    _setDate(exif, createdAt);
    return img.injectJpgExif(bytes, exif) ??
        (throw const FormatException('无法写入 JPG 生成日期'));
  }

  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 8 ||
      Iterable<int>.generate(8).any((i) => bytes[i] != signature[i])) {
    throw const FormatException('无法写入 PNG 生成日期');
  }
  final data = ByteData.sublistView(bytes);
  final chunks = <({String type, Uint8List raw})>[];
  var exif = img.ExifData();
  var offset = 8;
  var ended = false;
  while (offset + 12 <= bytes.length) {
    final size = data.getUint32(offset);
    final end = offset + size + 12;
    if (end > bytes.length) throw const FormatException('PNG 数据不完整');
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'eXIf') {
      final payload = Uint8List.sublistView(bytes, offset + 8, end - 4);
      final header = payload.length >= 8
          ? ByteData.sublistView(payload).getUint32(0)
          : 0;
      if (header != 0x49492a00 && header != 0x4d4d002a) {
        throw const FormatException('PNG EXIF 数据不完整');
      }
      // image 4.8.0 的 read() 成功后仍返回 false；验证 TIFF 头后按其构造器读取。
      exif = img.ExifData.fromInputBuffer(img.InputBuffer(payload));
    }
    chunks.add((type: type, raw: Uint8List.sublistView(bytes, offset, end)));
    offset = end;
    if (type == 'IEND') {
      ended = true;
      break;
    }
  }
  if (!ended || !chunks.any((c) => c.type == 'IDAT')) {
    throw const FormatException('PNG 数据不完整');
  }
  _setDate(exif, createdAt);
  final encoded = img.OutputBuffer();
  exif.write(encoded);
  final payload = encoded.getBytes();
  final chunk = Uint8List(payload.length + 12);
  final chunkData = ByteData.sublistView(chunk);
  chunkData.setUint32(0, payload.length);
  chunk.setRange(4, 8, 'eXIf'.codeUnits);
  chunk.setRange(8, chunk.length - 4, payload);
  chunkData.setUint32(
    chunk.length - 4,
    getCrc32(Uint8List.sublistView(chunk, 4, chunk.length - 4)),
  );
  final out = BytesBuilder(copy: false)..add(signature);
  var inserted = false;
  for (final part in chunks) {
    if (!inserted && part.type == 'IDAT') {
      out.add(chunk);
      inserted = true;
    }
    if (part.type != 'eXIf') out.add(part.raw);
  }
  if (offset < bytes.length) out.add(Uint8List.sublistView(bytes, offset));
  return out.takeBytes();
}

void _setDate(img.ExifData exif, int createdAt) {
  final at = DateTime.fromMillisecondsSinceEpoch(createdAt);
  String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
  final date =
      '${pad(at.year, 4)}:${pad(at.month)}:${pad(at.day)} '
      '${pad(at.hour)}:${pad(at.minute)}:${pad(at.second)}';
  final minutes = at.timeZoneOffset.inMinutes;
  final zone =
      '${minutes < 0 ? '-' : '+'}${pad(minutes.abs() ~/ 60)}:${pad(minutes.abs() % 60)}';
  final millis = pad(at.millisecond, 3);
  exif.imageIfd[0x0132] = img.IfdValueAscii(date);
  for (final tag in [0x9003, 0x9004]) {
    exif.exifIfd[tag] = img.IfdValueAscii(date);
  }
  for (final tag in [0x9010, 0x9011, 0x9012]) {
    exif.exifIfd[tag] = img.IfdValueAscii(zone);
  }
  for (final tag in [0x9290, 0x9291, 0x9292]) {
    exif.exifIfd[tag] = img.IfdValueAscii(millis);
  }
}

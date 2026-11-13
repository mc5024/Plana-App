/// 省内存地读「用户选中的文件」。
///
/// 备份 / vibe 整包动辄几十上百 MB(图是 base64),
/// `jsonDecode(utf8.decode(await f.readAsBytes()))` 会让同一份数据同时以
/// 「字节 + 文本 + 对象树」三种形态存在,手机上直接 OOM。
/// 选文件时用 `withData: false` 拿路径,再走这里的流式读法,内存里只留对象树。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import '../../l10n/l10n.dart';

/// 流式读 JSON:边读边解析,不把整份文本先存成一个大 String。
/// 内容不是合法 UTF-8 / JSON 时抛 [FormatException](消息可直接给用户看)。
Future<Object?> readJsonStream(Stream<List<int>> src) async {
  try {
    return await src.transform(utf8.decoder).transform(json.decoder).first;
  } on FormatException {
    throw FormatException(l10nNow.notValidJson);
  }
}

/// 读选中文件里的 JSON。有本地路径(移动端/桌面端都有)走流式;
/// 只有内存字节时(web)退回一次性解析。
Future<Object?> readPickedJson(PlatformFile f) async {
  final path = f.path;
  if (path != null) return readJsonStream(File(path).openRead());
  final bytes = f.bytes;
  if (bytes == null) throw FormatException(l10nNow.fileReadFailed);
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw FormatException(l10nNow.notValidJson);
  }
}

/// 首字节是否为 [byte](嗅探文件类型用)。有路径时只读这 1 个字节。
Future<bool> pickedStartsWith(PlatformFile f, int byte) async {
  final path = f.path;
  if (path == null) {
    return f.bytes?.isNotEmpty == true && f.bytes!.first == byte;
  }
  await for (final chunk in File(path).openRead(0, 1)) {
    if (chunk.isNotEmpty) return chunk.first == byte;
  }
  return false;
}

/// 读选中文件的全部字节(图片等必须整份拿到的内容)。
Future<Uint8List> readPickedBytes(PlatformFile f) {
  final path = f.path;
  if (path != null) return File(path).readAsBytes();
  final bytes = f.bytes;
  if (bytes == null || bytes.isEmpty) throw FormatException(l10nNow.fileEmpty);
  return Future.value(bytes);
}

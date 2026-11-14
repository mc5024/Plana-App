import 'dart:convert';
import 'dart:typed_data';

import '../../../core/util/image_ops.dart' show styleRefResizeJpg;
import 'llm_provider.dart';

/// 按文件头认图片类型,认不出按 PNG。标签和字节对不上时有的接口整条拒收。
String imageMimeOf(Uint8List b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
  if (at(0, 'GIF87a'.codeUnits) || at(0, 'GIF89a'.codeUnits)) {
    return 'image/gif';
  }
  return 'image/png';
}

/// 附图超过这个字节数就先缩再发:Claude 单张图 base64 超过 5MB 整条请求被拒。
const kLlmImageMaxBytes = 3500000;

/// 附图 → 发给模型的那份。超过 [kLlmImageMaxBytes] 的按长边 2048 转 JPEG;
/// 转不动(解不开的格式)就原样发,让接口自己判。
Future<LlmImage> prepareLlmImage(Uint8List bytes) async {
  if (bytes.length > kLlmImageMaxBytes) {
    try {
      final jpg = await styleRefResizeJpg(bytes, maxDim: 2048, quality: 90);
      return (mime: 'image/jpeg', data: base64Encode(jpg));
    } catch (_) {}
  }
  return (mime: imageMimeOf(bytes), data: base64Encode(bytes));
}

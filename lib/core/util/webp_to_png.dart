/// NAI 的无损 WebP 成图 → PNG(和后端 `_nai_webp_to_png`、web `utils/webpToPng.ts` 同一个结果)。
///
/// bot 渠道提交时声明 `result_format: webp`,后端就把 NAI 给的 WebP 原样发过来;
/// 这里还原成 PNG,下游(图库、保存、读参数…)照旧拿 PNG。
///
/// 还原是无损的:
/// - 像素和 alpha 逐字节一致 —— alpha 最低位藏着 NAI 的隐写参数。所以不能走 `dart:ui`
///   (`rawRgba` 是预乘的,透明度不是 255 的像素颜色会变),解码用 `package:image` 的
///   `WebPDecoder`(直通 alpha);
/// - PNG 的 6 个文字块原样装在 WebP 的 EXIF UserComment 里(一段 JSON),照官方 PNG 的
///   顺序写回;拉丁字母以外的字写 iTXt(同 Pillow)。`package:image` 的 PNG 编码只会
///   写 latin1 的 tEXt,遇到中文会抛错,所以 PNG 自己编。
library;

import 'dart:convert';
import 'dart:io' show ZLibEncoder, ZLibOption;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:image/image.dart' as img;

/// NAI 那 6 个 PNG 文字块的顺序(照官方 PNG 排)
const _textOrder = [
  'Title',
  'Description',
  'Software',
  'Source',
  'Generation time',
  'Comment',
];

bool isWebp(Uint8List b) =>
    b.length >= 12 &&
    b[0] == 0x52 &&
    b[1] == 0x49 &&
    b[2] == 0x46 &&
    b[3] == 0x46 &&
    b[8] == 0x57 &&
    b[9] == 0x45 &&
    b[10] == 0x42 &&
    b[11] == 0x50;

/// 逐个 RIFF 块:(四字符码, 内容起点, 长度)
Iterable<(String, int, int)> _riffChunks(Uint8List b) sync* {
  final v = ByteData.sublistView(b);
  var pos = 12;
  while (pos + 8 <= b.length) {
    final id = String.fromCharCodes(b, pos, pos + 4);
    final n = v.getUint32(pos + 4, Endian.little);
    final avail = b.length - pos - 8;
    yield (id, pos + 8, n < avail ? n : avail);
    pos += 8 + n + (n & 1);
  }
}

/// 带不带 alpha(决定还原成 RGBA 还是 RGB,和 Pillow 解出来的模式一致)
bool webpHasAlpha(Uint8List b) {
  for (final (id, start, n) in _riffChunks(b)) {
    if (id == 'VP8X' && n >= 1) return b[start] & 0x10 != 0;
    if (id == 'VP8L' && n >= 5) return (b[start + 4] >> 4) & 1 == 1;
    if (id == 'VP8 ') return false;
  }
  return false;
}

/// 只读文件头拿宽高(VP8X 画布 / VP8L / VP8 关键帧),不解码整图;不是 WebP 给 null。
(int, int)? webpSizeOf(Uint8List b) {
  if (!isWebp(b) || b.length < 30) return null;
  final v = ByteData.sublistView(b);
  final id = String.fromCharCodes(b, 12, 16);
  int u24(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
  final (w, h) = switch (id) {
    'VP8X' => (u24(24) + 1, u24(27) + 1),
    'VP8L' => (
      (v.getUint32(21, Endian.little) & 0x3fff) + 1,
      ((v.getUint32(21, Endian.little) >> 14) & 0x3fff) + 1,
    ),
    'VP8 ' => (
      v.getUint16(26, Endian.little) & 0x3fff,
      v.getUint16(28, Endian.little) & 0x3fff,
    ),
    _ => (0, 0),
  };
  return w > 0 && h > 0 ? (w, h) : null;
}

/// 本 app 自己的文字块(RIFF 块 `PLTX`,内容 `关键字\0UTF-8 文本`):WebP 没有 PNG 那种
/// 文字块,主提示词分区(`plana:sections`)这类我们自己写的东西放这里。解码器按规范
/// 跳过不认识的块;还原成 PNG 时随 [readWebpText] 一起写回文字块。
const _appTextChunk = 'PLTX';

/// 加一个 [_appTextChunk](同关键字的旧块先去掉)。只对扩展格式(VP8X)动手,
/// 简单格式按规范只能有一个图像块,原样返回。
Uint8List withWebpText(Uint8List webp, String key, String text) {
  if (!isWebp(webp) || webp.length < 16 || String.fromCharCodes(webp, 12, 16) != 'VP8X') {
    return webp;
  }
  final kb = latin1.encode(key);
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(webp, 0, 12));
  for (final (id, start, n) in _riffChunks(webp)) {
    final body = Uint8List.sublistView(webp, start, start + n);
    if (id == _appTextChunk) {
      final z = body.indexOf(0);
      if (z >= 0 && latin1.decode(body.sublist(0, z)) == key) continue;
    }
    out
      ..add(Uint8List.sublistView(webp, start - 8, start + n))
      ..add(n.isOdd ? const [0] : const []);
  }
  final payload = [...kb, 0, ...utf8.encode(text)];
  out
    ..add(ascii.encode(_appTextChunk))
    ..add((ByteData(4)..setUint32(0, payload.length, Endian.little)).buffer.asUint8List())
    ..add(payload)
    ..add(payload.length.isOdd ? const [0] : const []);
  final res = out.takeBytes();
  ByteData.sublistView(res).setUint32(4, res.length - 8, Endian.little);
  return res;
}

/// EXIF UserComment 里的 JSON(NAI 的 6 个文字块),外加本 app 的 [_appTextChunk];
/// 没有或解不出返回空表
Map<String, String> readWebpText(Uint8List b) {
  final out = <String, String>{};
  for (final (id, start, n) in _riffChunks(b)) {
    if (id != _appTextChunk) continue;
    final body = Uint8List.sublistView(b, start, start + n);
    final z = body.indexOf(0);
    if (z <= 0) continue;
    try {
      out[latin1.decode(body.sublist(0, z))] = utf8.decode(body.sublist(z + 1));
    } catch (_) {}
  }
  return {..._readExifText(b), ...out};
}

Map<String, String> _readExifText(Uint8List b) {
  for (final (id, start, n) in _riffChunks(b)) {
    if (id != 'EXIF') continue;
    var t = start, len = n;
    if (len >= 6 && b[t] == 0x45 && b[t + 1] == 0x78 && b[t + 2] == 0x69 && b[t + 3] == 0x66) {
      t += 6; // 有的写法前面带 "Exif\0\0"
      len -= 6;
    }
    try {
      final v = ByteData.sublistView(b, t, t + len);
      final e = v.getUint16(0) == 0x4949 ? Endian.little : Endian.big;
      int u16(int o) => v.getUint16(o, e);
      int u32(int o) => v.getUint32(o, e);
      int find(int ifd, int tag) {
        final cnt = u16(ifd);
        for (var i = 0; i < cnt; i++) {
          final p = ifd + 2 + i * 12;
          if (u16(p) == tag) return p;
        }
        return -1;
      }

      final ptr = find(u32(4), 0x8769); // IFD0 → Exif IFD
      if (ptr < 0) return {};
      final uc = find(u32(ptr + 8), 0x9286); // UserComment
      if (uc < 0) return {};
      final count = u32(uc + 4);
      final off = count > 4 ? u32(uc + 8) : uc + 8;
      // 头 8 字节是字符集标记(NAI 写 ASCII)
      final raw = Uint8List.sublistView(b, t + off + 8, t + off + count);
      final obj = jsonDecode(utf8.decode(raw));
      if (obj is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in obj.entries)
          '$key': value is String ? value : jsonEncode(value),
      };
    } catch (_) {
      return {};
    }
  }
  return {};
}

Uint8List _chunk(String type, List<int> data) {
  final typ = ascii.encode(type);
  final out = BytesBuilder(copy: false)
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(typ)
    ..add(data)
    ..add((ByteData(4)..setUint32(0, getCrc32(data, getCrc32(typ)))).buffer.asUint8List());
  return out.takeBytes();
}

Uint8List _textChunk(String key, String value) {
  final kb = latin1.encode(key);
  if (value.codeUnits.every((c) => c <= 0xff)) {
    return _chunk('tEXt', [...kb, 0, ...latin1.encode(value)]);
  }
  // iTXt:关键字\0 不压缩(0) 方法(0) 语言标签\0 译名\0 UTF-8 文本(同 Pillow add_itxt)
  return _chunk('iTXt', [...kb, 0, 0, 0, 0, 0, ...utf8.encode(value)]);
}

int _abs8(int v) => v < 128 ? v : 256 - v;

/// 每行挑「有符号绝对值和最小」的滤波(同 libpng 的启发式),行首写滤波类型。
/// 五种滤波在一趟紧循环里各写各的行缓冲:比逐字节按类型分支快四倍(1216×832 上 147 → 37 ms)。
Uint8List _filterRows(Uint8List px, int w, int h, int bpp) {
  final stride = w * bpp;
  final out = Uint8List(h * (stride + 1));
  final zero = Uint8List(stride);
  final b0 = Uint8List(stride), b1 = Uint8List(stride), b2 = Uint8List(stride);
  final b3 = Uint8List(stride), b4 = Uint8List(stride);
  final bufs = [b0, b1, b2, b3, b4];
  for (var y = 0; y < h; y++) {
    final cur = Uint8List.sublistView(px, y * stride, (y + 1) * stride);
    final prev = y > 0 ? Uint8List.sublistView(px, (y - 1) * stride, y * stride) : zero;
    var s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0;
    // 行首 bpp 个字节没有左邻:Sub 照抄、Average 只看上方、Paeth 退化成 Up
    for (var i = 0; i < bpp; i++) {
      final x = cur[i], up = prev[i];
      final v2 = (x - up) & 0xff, v3 = (x - (up >> 1)) & 0xff;
      b0[i] = x;
      b1[i] = x;
      b2[i] = v2;
      b3[i] = v3;
      b4[i] = v2;
      s0 += _abs8(x);
      s1 += _abs8(x);
      s2 += _abs8(v2);
      s3 += _abs8(v3);
      s4 += _abs8(v2);
    }
    for (var i = bpp; i < stride; i++) {
      final x = cur[i], a = cur[i - bpp], up = prev[i], ul = prev[i - bpp];
      final q = a + up - ul;
      final pa = (q - a).abs(), pb = (q - up).abs(), pc = (q - ul).abs();
      final pr = pa <= pb && pa <= pc ? a : (pb <= pc ? up : ul);
      final v1 = (x - a) & 0xff, v2 = (x - up) & 0xff;
      final v3 = (x - ((a + up) >> 1)) & 0xff, v4 = (x - pr) & 0xff;
      b0[i] = x;
      b1[i] = v1;
      b2[i] = v2;
      b3[i] = v3;
      b4[i] = v4;
      s0 += _abs8(x);
      s1 += _abs8(v1);
      s2 += _abs8(v2);
      s3 += _abs8(v3);
      s4 += _abs8(v4);
    }
    var best = 0, bs = s0;
    if (s1 < bs) (best, bs) = (1, s1);
    if (s2 < bs) (best, bs) = (2, s2);
    if (s3 < bs) (best, bs) = (3, s3);
    if (s4 < bs) (best, bs) = (4, s4);
    final o = y * (stride + 1);
    out[o] = best;
    out.setRange(o + 1, o + 1 + stride, bufs[best]);
  }
  return out;
}

/// RGBA 像素 → PNG。[hasAlpha] 为 false 时丢掉 alpha 写成 RGB。文字块写在 IDAT 前面(同 Pillow)
Uint8List encodePngWithText(
  Uint8List rgba,
  int w,
  int h,
  bool hasAlpha,
  Map<String, String> text,
) {
  final bpp = hasAlpha ? 4 : 3;
  var px = rgba;
  if (!hasAlpha) {
    px = Uint8List(w * h * 3);
    for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      px[j] = rgba[i];
      px[j + 1] = rgba[i + 1];
      px[j + 2] = rgba[i + 2];
    }
  }
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, hasAlpha ? 6 : 2);
  // RLE 策略:只找连续重复,比默认快一倍多、体积只大 2%(后端同款)
  final idat = ZLibEncoder(level: 6, strategy: ZLibOption.strategyRle)
      .convert(_filterRows(px, w, h, bpp));
  int rank(String k) {
    final i = _textOrder.indexOf(k);
    return i < 0 ? _textOrder.length : i;
  }

  final keys = text.keys.toList()
    ..sort((a, b) {
      final d = rank(a) - rank(b);
      return d != 0 ? d : a.compareTo(b);
    });
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()));
  for (final k in keys) {
    out.add(_textChunk(k, text[k]!));
  }
  out
    ..add(_chunk('IDAT', idat))
    ..add(_chunk('IEND', const []));
  return out.takeBytes();
}

/// 整套还原:解码 → 读文字块 → 编 PNG。不是 WebP 原样返回。放后台 isolate 跑(compute)。
Uint8List webpToPng(Uint8List webp) {
  if (!isWebp(webp)) return webp;
  final image = img.WebPDecoder().decode(webp);
  if (image == null) throw const FormatException('WebP 解码失败');
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);
  return encodePngWithText(
    rgba,
    image.width,
    image.height,
    webpHasAlpha(webp),
    readWebpText(webp),
  );
}

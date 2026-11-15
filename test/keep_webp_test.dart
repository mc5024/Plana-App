// 生成设置「保持图片格式」选 WebP:设置读写、直连请求的 image_format、WebP 上的自定义文字块
// (分区随图存)、导入读参数、图库按 .webp 存取 / 重建、保存时无损还原成 PNG。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:plana_app/core/store/blob_store.dart';
import 'package:plana_app/core/store/gen_settings.dart';
import 'package:plana_app/core/util/webp_to_png.dart';
import 'package:plana_app/features/gallery/gallery_store.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/gallery/save_pipeline.dart';
import 'package:plana_app/features/gallery/save_settings.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/nai_request.dart';
import 'package:plana_app/features/import/image_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final webp = File('test/fixtures/nai_sample.webp').readAsBytesSync();
  final rgba = File('test/fixtures/nai_sample.rgba').readAsBytesSync();

  test('设置:默认存 PNG,json 回环,老存档没这个字段按 PNG', () {
    expect(const GenSettings().keepWebp, isFalse);
    const s = GenSettings(keepWebp: true);
    expect(GenSettings.fromJson(s.toJson()), s);
    expect(GenSettings.fromJson({'retryCount': 5}).keepWebp, isFalse);
  });

  test('直连:image_format 按设置填,缺省 png', () {
    Map<String, dynamic> params(String? fmt) {
      final built = fmt == null
          ? buildNaiPayload(GenerateState.initial(), presetId: 'none')
          : buildNaiPayload(GenerateState.initial(), presetId: 'none', imageFormat: fmt);
      return built.body['parameters'] as Map<String, dynamic>;
    }

    expect(params(null)['image_format'], 'png');
    expect(params('webp')['image_format'], 'webp');
  });

  test('WebP 宽高只读文件头', () {
    expect(webpSizeOf(webp), (40, 28));
    expect(imageSizeOf(webp), (40, 28));
    expect(webpSizeOf(Uint8List(40)), isNull);
  });

  test('自定义文字块:写得进读得回,同关键字覆盖,解码不受影响,还原 PNG 时变成文字块', () {
    final a = withWebpText(webp, 'plana:sections', '{"v":1,"rows":["画风"]}');
    final b = withWebpText(a, 'plana:sections', '{"v":1,"rows":["场景"]}');
    expect(ByteData.sublistView(b).getUint32(4, Endian.little), b.length - 8);
    final text = readWebpText(b);
    expect(text['plana:sections'], '{"v":1,"rows":["场景"]}');
    expect(text['Title'], 'NovelAI generated image');
    final back = img.WebPDecoder().decode(b)!;
    expect(back.getBytes(order: img.ChannelOrder.rgba), rgba);
    final png = webpToPng(b);
    expect(img.PngDecoder().decode(png)!.getBytes(order: img.ChannelOrder.rgba), rgba);
    expect(String.fromCharCodes(png).contains('plana:sections'), isTrue);
  });

  test('导入:WebP 里的 NAI 参数和分区都读得出来', () async {
    final m = await extractImageMetadata(
      withWebpText(webp, 'plana:sections', '{"v":1,"rows":[]}'),
    );
    expect(m, isNotNull);
    expect(m!.isNovelAI, isTrue);
    expect(m.prompt, contains('silver hair'));
    expect(m.sectionLayout, '{"v":1,"rows":[]}');
  });

  test('图库:WebP 存成 .webp,读得回;索引丢了从目录重建也认它', () async {
    final root = Directory.systemTemp.createTempSync('plana_webp');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = GalleryStore(BlobStore(root), root);
    await store.load();
    await store.persistResult(
      ResultImage(id: 'gen0', width: 40, height: 28, seed: 1, bytes: webp),
    );
    expect(File('${root.path}/gallery/images/gen0.webp').existsSync(), isTrue);
    expect(File('${root.path}/gallery/images/gen0.png').existsSync(), isFalse);
    expect(await store.readImage('gen0'), webp);

    final again = GalleryStore(BlobStore(root), root);
    await again.load();
    final r = again.initialResults.single;
    expect((r.id, r.width, r.height), ('gen0', 40, 28));
    expect(again.seq, 1);
  });

  test('保存 PNG + 原始:WebP 无损还原成 PNG', () async {
    final out = await processForSave(webp, const SaveSettings());
    expect(out.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    expect(img.PngDecoder().decode(out)!.getBytes(order: img.ChannelOrder.rgba), rgba);
  });
}

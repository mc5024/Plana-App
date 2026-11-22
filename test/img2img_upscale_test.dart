import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/generate/cost.dart';
import 'package:plana_app/features/generate/gen_modules.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/state_codec.dart';

GenerateState _state(String model, EnhanceScale scale) => GenerateState(
  prompt: '1girl',
  negativePrompt: '',
  characters: const [],
  vibes: const [],
  charRefs: const [],
  anlas: 0,
  openPanels: const {},
  params: GenParams(model: model, width: 832, height: 1216),
  img2img: Img2ImgConfig(
    image: Uint8List.fromList(const [1, 2, 3]),
    strength: 0.5,
    upscale: Img2ImgUpscale(scale: scale, srcW: 832, srcH: 1216),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mods = GenModuleSettings();

  test('数值档:发送尺寸按倍率算,不带 upscaled_enhance', () {
    final out = stripHiddenModules(
      _state('NAI 5.0 Full', EnhanceScale.x15),
      mods,
    );
    expect((out.params.width, out.params.height), (1248, 1824));
    expect(out.img2img!.upscaledEnhance, isFalse);
  });

  test('Max 档:发原图尺寸并带 upscaled_enhance,点数按放大后算', () {
    final s = _state('NAI 5.0 Full', EnhanceScale.max);
    final out = stripHiddenModules(s, mods);
    expect((out.params.width, out.params.height), (832, 1216));
    expect(out.img2img!.upscaledEnhance, isTrue);
    final plain = out.copyWith(
      img2img: Img2ImgConfig(image: s.img2img!.image, strength: 0.5),
    );
    expect(
      estimateCost(out, isOpus: true),
      greaterThan(estimateCost(plain, isOpus: true)),
    );
  });

  test('非 V5 给不了 Max:落到可用的数值档', () {
    final out = stripHiddenModules(
      _state('NAI 4.5 Full', EnhanceScale.max),
      mods,
    );
    expect(out.img2img!.upscaledEnhance, isFalse);
    expect((out.params.width, out.params.height), (1248, 1824));
  });

  test('主分辨率不动:画布里存的仍是原值', () {
    final s = _state('NAI 5.0 Full', EnhanceScale.x15);
    expect((s.params.width, s.params.height), (832, 1216));
  });

  test('存档往返保留放大设置', () async {
    final blobs = AppStores.ephemeral().blobs;
    final enc = await encodeGenerateState(
      _state('NAI 5.0 Full', EnhanceScale.x15),
      blobs,
    );
    final up = (await decodeGenerateState(enc.json, blobs)).img2img!.upscale!;
    expect(up.scale, EnhanceScale.x15);
    expect((up.srcW, up.srcH), (832, 1216));
  });
}

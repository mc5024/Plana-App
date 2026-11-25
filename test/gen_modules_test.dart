import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/generate/gen_modules.dart';
import 'package:plana_app/features/generate/models.dart';

GenerateState _stateWithAll({String model = 'NAI 4.5 Full'}) =>
    GenerateState.initial().copyWith(
      characters: const [
        CharacterPrompt(id: 'c1', name: '角色1', positive: '1girl'),
      ],
      vibes: const [VibeItem(id: 'v1')],
      charRefs: const [CharRefItem(id: 'r1')],
      img2img: const Img2ImgConfig(),
      params: const GenParams().copyWith(model: model),
    );

void main() {
  const naiDefault = [
    GenModule.character,
    GenModule.vibe,
    GenModule.charRef,
    GenModule.img2img,
  ];

  group('GenModuleSettings', () {
    test('默认全启用,nai 组顺序为注册表顺序', () {
      const s = GenModuleSettings();
      expect(s.orderOf(GenProvider.nai), naiDefault);
      for (final m in GenModule.values) {
        expect(s.isEnabled(m), isTrue);
      }
      expect(s.visibleFor('NAI 4.5 Full'), naiDefault);
    });

    test('型号能力门槛:4.0 与 V5 Medium 隐藏角色参考,V5 Full/Curated 放开', () {
      const s = GenModuleSettings();
      expect(s.visibleFor('NAI 4.0 Full'), isNot(contains(GenModule.charRef)));
      expect(s.visibleFor('NAI 4.0 Curated'), hasLength(3));
      expect(s.visibleFor('NAI 5.0 Full'), contains(GenModule.charRef));
      expect(s.visibleFor('NAI 5.0 Curated'), contains(GenModule.charRef));
      expect(
        s.visibleFor('NAI 5.0 Full Medium'),
        isNot(contains(GenModule.charRef)),
      );
      expect(s.orderOf(GenProvider.nai), contains(GenModule.charRef));
    });

    test('fromJson 容错:过滤未知项、去重、补齐缺失、读启用位', () {
      final s = GenModuleSettings.fromJson({
        'enabled': {'vibe': false, 'ghost': true, 'img2img': 1},
        'order': {
          'nai': ['img2img', 'ghost', 'img2img', 'vibe'],
        },
      });
      expect(s.orderOf(GenProvider.nai), [
        GenModule.img2img,
        GenModule.vibe,
        GenModule.character,
        GenModule.charRef,
      ]);
      expect(s.isEnabled(GenModule.vibe), isFalse);
      expect(s.isEnabled(GenModule.img2img), isTrue); // 非 bool 丢弃 → 默认启用
      expect(s.visibleFor('NAI 4.5 Full'), isNot(contains(GenModule.vibe)));
    });

    test('旧版扁平 order 数组归入 nai 组', () {
      final s = GenModuleSettings.fromJson({
        'order': ['vibe', 'character'],
      });
      expect(s.orderOf(GenProvider.nai), [
        GenModule.vibe,
        GenModule.character,
        GenModule.charRef,
        GenModule.img2img,
      ]);
    });

    test('toJson/fromJson 往返一致', () {
      final a = GenModuleSettings(
        enabled: const {GenModule.charRef: false},
        order: const {
          GenProvider.nai: [
            GenModule.vibe,
            GenModule.img2img,
            GenModule.character,
            GenModule.charRef,
          ],
        },
      );
      final b = GenModuleSettings.fromJson(
        Map<String, dynamic>.from(a.toJson()),
      );
      expect(b.orderOf(GenProvider.nai), a.orderOf(GenProvider.nai));
      for (final m in GenModule.values) {
        expect(b.isEnabled(m), a.isEnabled(m));
      }
    });
  });

  group('stripHiddenModules', () {
    test('全启用且型号全支持时原样返回(同一对象,零拷贝)', () {
      final s = _stateWithAll();
      expect(
        identical(stripHiddenModules(s, const GenModuleSettings()), s),
        isTrue,
      );
    });

    test('隐藏的模块数据被剥离,其余保留', () {
      final s = _stateWithAll();
      final out = stripHiddenModules(
        s,
        const GenModuleSettings(
          enabled: {GenModule.vibe: false, GenModule.img2img: false},
        ),
      );
      expect(out.vibes, isEmpty);
      expect(out.img2img, isNull);
      expect(out.characters, hasLength(1));
      expect(out.charRefs, hasLength(1));
    });

    test('型号不支持的模块同样剥离:4.0 与 V5 Medium 下角色参考不发', () {
      final s40 = _stateWithAll(model: 'NAI 4.0 Full');
      final out40 = stripHiddenModules(s40, const GenModuleSettings());
      expect(out40.charRefs, isEmpty);
      expect(out40.vibes, hasLength(1));
      expect(out40.characters, hasLength(1));
      expect(out40.img2img, isNotNull);

      final sMed = _stateWithAll(model: 'NAI 5.0 Full Medium');
      final outMed = stripHiddenModules(sMed, const GenModuleSettings());
      expect(outMed.charRefs, isEmpty);
      expect(outMed.vibes, isEmpty);
    });

    test('V5 重绘态剥离 charRefs(保留原状态),V4.5 重绘与 V5 非重绘照常保留', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final job = InpaintJob(image: bytes, mask: bytes, strength: 0.7);
      const ms = GenModuleSettings();

      final v5Inpaint = _stateWithAll(model: 'NAI 5.0 Full').copyWith(
        inpaint: job,
      );
      final outV5 = stripHiddenModules(v5Inpaint, ms);
      expect(outV5.charRefs, isEmpty);
      expect(v5Inpaint.charRefs, hasLength(1)); // 画布原状态不动

      final v5CuratedInpaint = _stateWithAll(model: 'NAI 5.0 Curated').copyWith(
        inpaint: job,
      );
      expect(stripHiddenModules(v5CuratedInpaint, ms).charRefs, isEmpty);

      final v5Plain = _stateWithAll(model: 'NAI 5.0 Full');
      expect(stripHiddenModules(v5Plain, ms).charRefs, hasLength(1));

      final v45Inpaint = _stateWithAll(model: 'NAI 4.5 Full').copyWith(
        inpaint: job,
      );
      expect(stripHiddenModules(v45Inpaint, ms).charRefs, hasLength(1));
    });

    test('retargetModel 按能力保留/剥离角色参考', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final src = _stateWithAll(model: 'NAI 4.5 Full');
      expect(retargetModel(src, 'NAI 5.0 Full').charRefs, hasLength(1));
      expect(retargetModel(src, 'NAI 5.0 Curated').charRefs, hasLength(1));
      expect(retargetModel(src, 'NAI 5.0 Full Medium').charRefs, isEmpty);
      expect(retargetModel(src, 'NAI 4.0 Full').charRefs, isEmpty);

      final inpaintSrc = src.copyWith(
        inpaint: InpaintJob(image: bytes, mask: bytes, strength: 1),
      );
      expect(retargetModel(inpaintSrc, 'NAI 5.0 Full').charRefs, isEmpty);
      expect(retargetModel(inpaintSrc, 'NAI 4.5 Curated').charRefs, hasLength(1));
    });

    GenerateState chars(List<bool> enabled) => GenerateState.initial().copyWith(
      characters: [
        for (final (i, on) in enabled.indexed)
          CharacterPrompt(
            id: 'c$i',
            name: '角色$i',
            positive: 'p$i',
            enabled: on,
          ),
      ],
      params: const GenParams().copyWith(model: 'NAI 4.5 Full'),
    );

    test('角色上限只数启用的:7 张停掉前 6 张,第 7 张照发', () {
      final s = chars([...List.filled(6, false), true]);
      const ms = GenModuleSettings();
      expect(identical(stripHiddenModules(s, ms), s), isTrue);
      expect(countedCharacters(s, ms).map((c) => c.id), ['c6']);
    });

    test('启用数超出上限:排在后面的启用卡不进载荷,停用的留着', () {
      final s = chars([true, false, ...List.filled(7, true)]);
      const ms = GenModuleSettings();
      final sent = ['c0', 'c2', 'c3', 'c4', 'c5', 'c6'];
      expect(stripHiddenModules(s, ms).characters.map((c) => c.id), [
        'c0',
        'c1',
        ...sent.skip(1),
      ]);
      expect(countedCharacters(s, ms).map((c) => c.id), sent);
    });
  });

  test('精确参考能力矩阵:4.5 与 V5 Full/Curated 支持,Medium/4.0 不支持', () {
    for (final m in ['NAI 4.5 Full', 'NAI 4.5 Curated']) {
      expect(crSupportsModel(m), isTrue, reason: m);
      expect(crSupportsInpainting(m), isTrue, reason: m);
      expect(crSupportsOutfit(m), isFalse, reason: m);
      expect(crSupportsFidelity(m), isTrue, reason: m);
      expect(crStrengthMax(m), 1.0, reason: m);
      expect(crUsesBucketResize(m), isFalse, reason: m);
    }
    for (final m in ['NAI 5.0 Full', 'NAI 5.0 Curated']) {
      expect(crSupportsModel(m), isTrue, reason: m);
      expect(crSupportsInpainting(m), isFalse, reason: m);
      expect(crSupportsOutfit(m), isTrue, reason: m);
      expect(crSupportsFidelity(m), isFalse, reason: m);
      expect(crStrengthMax(m), 5.0, reason: m);
      expect(crUsesBucketResize(m), isTrue, reason: m);
    }
    for (final m in [
      'NAI 5.0 Full Medium',
      'NAI 4.0 Full',
      'NAI 4.0 Curated',
      'Anima Turbo',
    ]) {
      expect(crSupportsModel(m), isFalse, reason: m);
      expect(crSupportsInpainting(m), isFalse, reason: m);
      expect(crSupportsOutfit(m), isFalse, reason: m);
      expect(crSupportsFidelity(m), isFalse, reason: m);
      expect(crUsesBucketResize(m), isFalse, reason: m);
    }
  });
}

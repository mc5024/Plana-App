// V5 上线后与 web 对齐的三条硬契约(2026-08-24 同步)。
//
// 三条都是**静默错**:发错了不崩、不报错,只是元数据写进去是错的、或者字段被
// 服务端悄悄丢掉。人工点一遍 UI 一个都看不出来 —— 只能靠测试钉住。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/generate/bot_request.dart';
import 'package:plana_app/features/generate/char_position.dart';
import 'package:plana_app/features/generate/cost.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/nai_request.dart';
import 'package:plana_app/features/generate/prompt_presets.dart';
import 'package:plana_app/features/import/image_metadata.dart';

/// 一份非 karras + Variety+ 都开着的状态。非 karras 是 V5 不支持的:
/// 用户切到 V5 之前留下的值就长这样,收口没做好就会被带出去。
GenerateState _state(String model) => GenerateState.initial().copyWith(
  prompt: '1girl',
  params: const GenParams().copyWith(
    model: model,
    seed: '1',
    noiseSchedule: 'exponential',
    varietyPlus: true,
  ),
);

Map<String, dynamic> _direct(String model, {String presetId = 'heavy'}) =>
    buildNaiPayload(_state(model), presetId: presetId).body['parameters']
        as Map<String, dynamic>;

Map<String, dynamic> _bot(String model, {String presetId = 'heavy'}) =>
    buildBotParams(_state(model), seed: 1, presetId: presetId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ucPreset 的数值是**档位数组的下标**,直连与 bot 两条线共用同一张官方表。
  // 曾经按线拆成两张(bot 线是一套自造的反向取值 heavy→4 / none→0),web 把
  // bot 线也换成官方表时 app 只跟了一半 —— 于是「重度」被写进图片元数据时
  // 成了「无」。拆表就是这个 bug 的成因,所以这一组同时钉住「值对」和「两条线一致」。
  group('ucPresetValue:两条线共用官方下标表', () {
    const v5 = 'nai-diffusion-5-full';

    test('V5 档位数组 [heavy, light, furryFocus, humanFocus, none] 的下标', () {
      expect(ucPresetValue('heavy', v5), 0);
      expect(ucPresetValue('light', v5), 1);
      expect(ucPresetValue('furryFocus', v5), 2);
      expect(ucPresetValue('humanFocus', v5), 3);
      expect(ucPresetValue('none', v5), 4);
    });

    // 下标是**该模型**负面档数组里的位置,而各模型数组长度不同 —— 曾经写死
    // none=4,对下面这几档全是错的(只污染元数据、不影响出图)。
    test('none 的下标随模型变:短数组不能按 V5 的 4 发', () {
      expect(ucPresetValue('none', 'nai-diffusion-5-curated'), 4);
      expect(ucPresetValue('none', 'nai-diffusion-4-5-full'), 4);
      expect(ucPresetValue('none', 'nai-diffusion-4-5-curated'), 3);
      expect(ucPresetValue('none', 'nai-diffusion-4-full'), 2);
      expect(ucPresetValue('none', 'nai-diffusion-4-curated-preview'), 2);
      expect(ucPresetValue('none', 'nai-diffusion-3'), 3);
    });

    test('heavy / light 在所有模型里都是 0 / 1', () {
      for (final m in [
        'nai-diffusion-5-full',
        'nai-diffusion-4-5-curated',
        'nai-diffusion-4-full',
        'nai-diffusion-3',
      ]) {
        expect(ucPresetValue('heavy', m), 0, reason: m);
        expect(ucPresetValue('light', m), 1, reason: m);
      }
    });

    test('该模型没有的档落回它自己的 none', () {
      // 4.5Curated 没有 furryFocus,V4 连 humanFocus 都没有
      expect(ucPresetValue('furryFocus', 'nai-diffusion-4-5-curated'), 3);
      expect(ucPresetValue('humanFocus', 'nai-diffusion-4-full'), 2);
    });

    test('重绘换模型时下标跟着换:V5 Curated 重绘回退 4.5 Curated', () {
      // inpaintModelId('nai-diffusion-5-curated') = 'nai-diffusion-4-5-curated-inpainting'
      expect(
        ucPresetValue('none', inpaintModelId('nai-diffusion-5-curated')),
        3,
      );
    });

    test('v5 档跟随它所用的官方负面档', () {
      expect(ucPresetValue('v5-standard', v5), ucPresetValue('heavy', v5));
      expect(ucPresetValue('v5-light', v5), ucPresetValue('light', v5));
    });

    test('自定义预设落 none —— 负面词是用户自己写的,不该宣称套了官方档', () {
      expect(ucPresetValue('preset-1755999999', v5), 4);
      expect(ucPresetValue('', v5), 4);
      expect(ucPresetValue('preset-1755999999', 'nai-diffusion-4-full'), 2);
    });

    test('同一档在直连与 bot 发出的是同一个数', () {
      for (final id in ['heavy', 'light', 'none', 'preset-1755999999']) {
        expect(
          _direct('NAI 4.5 Full', presetId: id)['ucPreset'],
          _bot('NAI 4.5 Full', presetId: id)['ucPreset'],
          reason: id,
        );
      }
    });
  });

  // 官方能力表里 V5 的 noiseSchedule 是 false:请求清洗会把 noise_schedule
  // 硬写回 karras。带过去不会报错,只是白发 —— 但用户切模型前留下的值会一直
  // 显示成选着,所以两条线都收口。Variety+ 则与 4.5 同样照发。
  group('V5 的 noise_schedule 恒 karras,Variety+ 照发', () {
    test('直连:noise_schedule 恒 karras', () {
      expect(_direct('NAI 5.0 Full')['noise_schedule'], 'karras');
      expect(_direct('NAI 5.0 Curated')['noise_schedule'], 'karras');
    });

    test('直连:Variety+ 开着发 skip_cfg_above_sigma = 58', () {
      expect(_direct('NAI 5.0 Full')['skip_cfg_above_sigma'], 58);
      expect(_direct('NAI 5.0 Curated')['skip_cfg_above_sigma'], 58);
    });

    test('bot:同一口径', () {
      expect(_bot('NAI 5.0 Full')['noiseSchedule'], 'karras');
      expect(_bot('NAI 5.0 Full')['varietyPlus'], isTrue);
    });

    test('4.5 不受影响:用户选什么发什么', () {
      expect(_direct('NAI 4.5 Full')['noise_schedule'], 'exponential');
      expect(_direct('NAI 4.5 Full')['skip_cfg_above_sigma'], 58);
      expect(_bot('NAI 4.5 Full')['noiseSchedule'], 'exponential');
      expect(_bot('NAI 4.5 Full')['varietyPlus'], isTrue);
    });
  });

  // 透明背景:straight_alpha 跟官方一样「只要模型支持就无条件发」(它只是 alpha
  // 的编码约定),tag_hint 才是记录「这张到底透不透明」的那个,由提示词触发。
  group('透明背景字段', () {
    GenerateState withPrompt(String model, String prompt) =>
        GenerateState.initial().copyWith(
          prompt: prompt,
          params: const GenParams().copyWith(model: model, seed: '1'),
        );

    Map<String, dynamic> direct(GenerateState s, {bool straight = true}) =>
        buildNaiPayload(
              s,
              presetId: 'none',
              straightAlpha: straight,
            ).body['parameters']
            as Map<String, dynamic>;

    test('V5:straight_alpha 恒发,tag_hint 跟提示词走', () {
      final on = direct(
        withPrompt('NAI 5.0 Full', '1girl, transparent background'),
      );
      expect(on['straight_alpha'], isTrue);
      expect(on['tag_hint_transparent_background'], isTrue);

      final off = direct(withPrompt('NAI 5.0 Full', '1girl'));
      expect(off['straight_alpha'], isTrue);
      expect(off['tag_hint_transparent_background'], isFalse);
    });

    test('设置里改成预乘 → straight_alpha false', () {
      final p = direct(withPrompt('NAI 5.0 Full', '1girl'), straight: false);
      expect(p['straight_alpha'], isFalse);
    });

    test('非 V5 一个字段都不发', () {
      final p = direct(
        withPrompt('NAI 4.5 Full', '1girl, transparent background'),
      );
      expect(p.containsKey('straight_alpha'), isFalse);
      expect(p.containsKey('tag_hint_transparent_background'), isFalse);
    });

    // 看的是**最终要发的** model:V5 Curated 的重绘会回退到 4.5 Curated
    // Inpainting,那个模型没有 transparency 能力,不该跟着发。
    test('V5 Curated 重绘回退到 4.5 → 不发', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final s = withPrompt('NAI 5.0 Curated', 'transparent background')
          .copyWith(
            inpaint: InpaintJob(image: bytes, mask: bytes, strength: 0.7),
          );
      final p = direct(s);
      expect(p.containsKey('straight_alpha'), isFalse);
      // V5 Full 的重绘模型已上线,那条照发
      final full = withPrompt('NAI 5.0 Full', 'transparent background')
          .copyWith(
            inpaint: InpaintJob(image: bytes, mask: bytes, strength: 0.7),
          );
      expect(direct(full)['straight_alpha'], isTrue);
    });

    test('bot 线同口径(camelCase)', () {
      final p = buildBotParams(
        withPrompt('NAI 5.0 Full', '1girl, transparent background'),
        seed: 1,
        presetId: 'none',
      );
      expect(p['straightAlpha'], isTrue);
      expect(p['tagHintTransparentBackground'], isTrue);
      final legacy = buildBotParams(
        withPrompt('NAI 4.5 Full', 'transparent background'),
        seed: 1,
        presetId: 'none',
      );
      expect(legacy.containsKey('straightAlpha'), isFalse);
    });
  });

  // 官方前端不分模型都发 tag_hint_qt / tag_hint_uc_preset;三方中转对非 V5 会拒。
  group('档位提示字段', () {
    Map<String, dynamic> direct(GenerateState s, {bool thirdParty = false}) =>
        buildNaiPayload(
              s,
              presetId: 'light',
              thirdParty: thirdParty,
            ).body['parameters']
            as Map<String, dynamic>;

    test('官方地址:4.5 也照发', () {
      final p = direct(_state('NAI 4.5 Full'));
      expect(p['tag_hint_qt'], 1);
      expect(p['tag_hint_uc_preset'], 3);
    });

    test('三方地址:非 V5 不发,V5 照发', () {
      final legacy = direct(_state('NAI 4.5 Full'), thirdParty: true);
      expect(legacy.containsKey('tag_hint_qt'), isFalse);
      expect(legacy.containsKey('tag_hint_uc_preset'), isFalse);
      final v5 = direct(_state('NAI 5.0 Full'), thirdParty: true);
      expect(v5.containsKey('tag_hint_qt'), isTrue);
      expect(v5.containsKey('tag_hint_uc_preset'), isTrue);
    });

    test('三方地址:V5 Curated 重绘回退到 4.5 → 不发', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final s = _state('NAI 5.0 Curated').copyWith(
        inpaint: InpaintJob(image: bytes, mask: bytes, strength: 0.7),
      );
      expect(direct(s, thirdParty: true).containsKey('tag_hint_qt'), isFalse);
    });
  });

  group('重绘强度', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    Map<String, dynamic> infill(String model, double strength) =>
        buildNaiPayload(
              _state(model).copyWith(
                inpaint: InpaintJob(
                  image: bytes,
                  mask: bytes,
                  strength: strength,
                ),
              ),
              presetId: 'none',
            ).body['parameters']
            as Map<String, dynamic>;

    test('不是 1:两个字段同值,带 img2img 块', () {
      final p = infill('NAI 4.5 Full', .5);
      expect(p['inpaintImg2ImgStrength'], .5);
      expect(p['strength'], .5);
      expect(p['img2img'], {'strength': .5, 'color_correct': true});
    });

    test('等于 1:不带 img2img 块', () {
      final p = infill('NAI 4.5 Full', 1);
      expect(p['inpaintImg2ImgStrength'], 1);
      expect(p['strength'], 1);
      expect(p.containsKey('img2img'), isFalse);
    });

    test('V5 Full Medium 不能调:恒发 1', () {
      expect(inpaintStrengthSupported('NAI 5.0 Full Medium'), isFalse);
      final p = infill('NAI 5.0 Full Medium', .5);
      expect(p['inpaintImg2ImgStrength'], 1);
      expect(p['strength'], 1);
      expect(p.containsKey('img2img'), isFalse);
    });

    test('V5 Curated 回退 4.5 重绘模型,强度照发', () {
      final p = infill('NAI 5.0 Curated', .5);
      expect(p['inpaintImg2ImgStrength'], .5);
      expect(p['img2img'], {'strength': .5, 'color_correct': true});
    });

    test('图生图不受影响', () {
      final p =
          buildNaiPayload(
                _state('NAI 4.5 Full'),
                presetId: 'none',
                img2img: (
                  image: 'x',
                  strength: .7,
                  noise: 0,
                  upscaledEnhance: false,
                ),
              ).body['parameters']
              as Map<String, dynamic>;
      expect(p['strength'], .7);
      expect(p['inpaintImg2ImgStrength'], 1);
      expect(p.containsKey('img2img'), isFalse);
    });
  });

  // V5 的 Source 串里**不写 Full / Curated**,只有权重 hash。按字面找 curated
  // 永远不成立 —— 那样写会把每一张 V5 图都认成 Full(本仓 2026-08-24 前就是)。
  group('naiSourceIsV5Full:V5 认 hash 不认字面', () {
    test('白名单里的两个 hash 是 Full', () {
      expect(naiSourceIsV5Full('NovelAI Diffusion V5 657484A5'), isTrue);
      expect(naiSourceIsV5Full('NovelAI Diffusion V5 0ADF9AB7'), isTrue);
    });

    test('其余 V5 一律 Curated(官方那边就是 default 分支)', () {
      expect(naiSourceIsV5Full('NovelAI Diffusion V5 12345678'), isFalse);
      expect(naiSourceIsV5Full('NovelAI Diffusion V5'), isFalse);
    });

    test('大小写不敏感', () {
      expect(naiSourceIsV5Full('novelai diffusion v5 657484a5'), isTrue);
    });

    test('归一化之后的串也吃得下(那时 hash 已经没了,只能看字面)', () {
      expect(naiSourceIsV5Full('NovelAI V5 Full'), isTrue);
      expect(naiSourceIsV5Full('NovelAI V5 Curated'), isFalse);
    });

    test('Medium 档的两个 hash 认成 Full Medium', () {
      for (final src in [
        'NovelAI Diffusion V5 93F4BD30',
        'NovelAI Diffusion V5 70AB5786',
        'NovelAI V5 Full Medium',
      ]) {
        expect(naiSourceIsV5Medium(src), isTrue, reason: src);
        expect(naiSourceIsV5Full(src), isTrue, reason: src);
      }
      expect(naiSourceIsV5Medium('NovelAI Diffusion V5 657484A5'), isFalse);
    });
  });

  group('V5 Full Medium', () {
    test('文生图 / 重绘', () {
      final id = naiModelId('NAI 5.0 Full Medium');
      expect(id, 'nai-diffusion-5-full-medium');
      expect(inpaintModelId(id), 'nai-diffusion-5-full-medium-inpainting');
    });

    test('按 V5 处理', () {
      expect(isNai5Model('NAI 5.0 Full Medium'), isTrue);
      expect(tokenLimitOf('NAI 5.0 Full Medium'), 1471);
      expect(ucPresetValue('none', 'nai-diffusion-5-full-medium'), 4);
    });

    GenerateState medium({int w = 832, int h = 1216}) {
      final s = _state('NAI 5.0 Full Medium');
      return s.copyWith(
        negativePrompt: 'lowres',
        params: s.params.copyWith(
          width: w,
          height: h,
          steps: 40,
          sampler: 'DPM++ 2M',
          cfgRescale: .3,
        ),
      );
    }

    test('步数 / 采样器固定,不发 CFG Rescale,负面照发', () {
      final d =
          buildNaiPayload(medium(), presetId: 'heavy').body['parameters']
              as Map<String, dynamic>;
      expect(d['steps'], 14);
      expect(d['sampler'], 'k_euler_ancestral');
      expect(d.containsKey('cfg_rescale'), isFalse);

      final b = buildBotParams(medium(), seed: 1, presetId: 'heavy');
      expect(b['steps'], 14);
      expect(b['sampler'], 'k_euler_ancestral');
      expect(b.containsKey('cfgRescale'), isFalse);
      expect(b['negativePrompt'], 'lowres');
    });

    test('价格:按 14 步,步数项再乘 1/1.06521739', () {
      expect(estimateCost(medium(), isOpus: false), 17);
      expect(estimateCost(medium(w: 1024, h: 1024), isOpus: false), 18);
      expect(estimateCost(medium(w: 1024, h: 1536), isOpus: false), 26);
      expect(estimateCost(medium(w: 1536, h: 2048), isOpus: false), 51);
      expect(estimateCost(medium(w: 1024, h: 1536), isOpus: true), 26);
      expect(estimateCost(medium(), isOpus: true), 0);
    });
  });

  // 角色坐标:只有 V5 吃自由坐标,其余模型官方在**发送前**把坐标吸附到 5×5 格心
  // (能力位 freeformCharacterPosition),存着的值一个字节不改。发错了照样出图,
  // 只是构图和官方对不上 —— 又一条静默错。
  group('角色坐标:非 V5 发送前吸附到格心', () {
    GenerateState withChar(String model, String? pos) => _state(model).copyWith(
      characters: [
        CharacterPrompt(
          id: 'c1',
          name: '角色1',
          positive: '1girl',
          position: pos,
        ),
      ],
    );

    List<dynamic> capCenters(Map<String, dynamic> body) =>
        (((body['parameters'] as Map)['v4_prompt'] as Map)['caption']
                as Map)['char_captions']
            as List;

    test('floor 分桶,不是四舍五入 —— 0.2 / 0.4 这些边界差一格', () {
      // u = [.1,.3,.5,.7,.9];  h = v => u[clamp(floor(5*v), 0, 4)]
      expect(quantizeCenterToGrid(0.19, 0.19), (x: 0.1, y: 0.1));
      expect(quantizeCenterToGrid(0.2, 0.4), (x: 0.3, y: 0.5));
      expect(quantizeCenterToGrid(0.42, 0.67), (x: 0.5, y: 0.7));
      expect(quantizeCenterToGrid(0.0, 1.0), (x: 0.1, y: 0.9));
    });

    test('V4.5 直连:自由坐标吸附进 char_captions,characterPrompts 仍是原值', () {
      final body = buildNaiPayload(
        withChar('NAI 4.5 Full', '0.4200,0.6700'),
        presetId: 'heavy',
      ).body;
      expect(capCenters(body).first['centers'], [
        {'x': 0.5, 'y': 0.7},
      ]);
      // 导入回放数据不跟着改,否则切回 V5 精确坐标就丢了
      final cps = (body['parameters'] as Map)['characterPrompts'] as List;
      expect(cps.first['center'], {'x': 0.42, 'y': 0.67});
    });

    test('V5 直连:自由坐标原样发', () {
      final body = buildNaiPayload(
        withChar('NAI 5.0 Full', '0.4200,0.6700'),
        presetId: 'heavy',
      ).body;
      expect(capCenters(body).first['centers'], [
        {'x': 0.42, 'y': 0.67},
      ]);
    });

    // 判据得是**最终**模型:V5 Curated 的重绘回落到 4.5 Curated Inpainting,
    // 底模看着是 V5,那条路却只吃格心。
    test('V5 Curated 重绘回落到 4.5:照样吸附', () {
      final s = withChar('NAI 5.0 Curated', '0.4200,0.6700').copyWith(
        inpaint: InpaintJob(
          image: Uint8List.fromList(const [1]),
          mask: Uint8List.fromList(const [2]),
          strength: 0.7,
        ),
      );
      final body = buildNaiPayload(s, presetId: 'heavy').body;
      expect(body['model'], 'nai-diffusion-4-5-curated-inpainting');
      expect(capCenters(body).first['centers'], [
        {'x': 0.5, 'y': 0.7},
      ]);
    });

    // 网格 UI 的高亮要靠它:自由坐标串跟任何格子 id 都不相等,直接比字符串会让
    // 25 个格子全显示未选中,而请求里发的是其中某一格。
    test('gridCellForPosition:自由坐标也能算出落在哪一格', () {
      expect(gridCellForPosition('0.4200,0.6700'), 'C4');
      expect(gridCellForPosition('0.7000,0.3000'), 'D2');
      expect(gridCellForPosition('D2'), 'D2');
      expect(gridCellForPosition(null), isNull);
    });

    // 导入走的是同一套:元数据里的 center → position。V5 图的自由坐标必须原样
    // 留住,吸附了就等于把用户摆的位置改掉(web importOptions 同规则)。
    test('导入:V5 自由坐标不吸附,正落格心的才收成格子 id', () {
      expect(positionOfCenter(0.42, 0.67), '0.4200,0.6700');
      expect(positionOfCenter(0.5, 0.7), 'C4');
      expect(positionOfCenter(null, null), isNull);
      // 收成格子 id 也不丢位置:两种写法解析回来是同一个点
      expect(resolveCharacterCenter('C4'), (x: 0.5, y: 0.7));
    });

    // ── 对齐官方的角色定位模型(2026-09-04)──────────────────────────
    //
    // 官方没有「每角色 AUTO」:每个角色**建出来就有具体坐标**,而「要不要按坐标
    // 出图」是位置区块上的全局二选一(AI's Choice / Custom = `use_coords`),
    // 默认 false。我们早先恒发 true、用 position==null 表示 AUTO,那是自造的模型。
    group('新角色的出生位置照官方的候选序挑', () {
      String posAt(List<String?> taken) =>
          nextSpawnPosition(taken, freeform: false);

      test('第一个落正中,之后由内向外铺开', () {
        // 官方 lc 表:中间横排由内向外 → 其余按到画面中心的距离铺开。
        //
        // ⚠ C4 排在 C2 **前面**看着别扭,但那是照抄官方比较器的必然结果:
        //   `0.7 - 0.5 = 0.19999999999999996`,比 `0.5 - 0.3 = 0.2` 小一丁点,
        //   于是下半边先于上半边。官方那句 hypot 相减吃的是同一个浮点误差,
        //   照着"整齐"的直觉改反而会和官方错开。
        const want = ['C3', 'B3', 'D3', 'A3', 'E3', 'C4', 'C2', 'D4'];
        final got = <String?>[];
        for (var i = 0; i < want.length; i++) {
          got.add(posAt(got));
        }
        expect(got, want);
      });

      test('不挑已经被占的格子', () {
        expect(posAt(['C3']), 'B3');
        expect(posAt(['C3', 'B3']), 'D3');
        // 中间空着就先补中间,不管已有的是谁
        expect(posAt(['B3', 'D3']), 'C3');
      });

      test('V5 的自由坐标按距离判占用(< 0.1),不是按格子', () {
        // 0.52,0.5 离正中只有 0.02,正中算被占了
        expect(nextSpawnPosition(['0.5200,0.5000'], freeform: true), 'B3');
        // 离得够远就不算
        expect(nextSpawnPosition(['0.9000,0.9000'], freeform: true), 'C3');
      });
    });

    group('use_coords 是全局开关,默认关', () {
      test('默认 false —— 与官方一致(早先我们恒发 true)', () {
        expect(const GenParams().useCoords, isFalse);
      });

      test('发送时照实发,且坐标只认角色自己的(不再按下标代入)', () {
        final chars = [
          const CharacterPrompt(
            id: 'a',
            name: 'a',
            positive: 'x',
            position: 'A1',
          ),
          const CharacterPrompt(
            id: 'b',
            name: 'b',
            positive: 'y',
            position: 'E5',
          ),
        ];
        for (final on in [false, true]) {
          final body = buildNaiPayload(
            GenerateState.initial().copyWith(
              prompt: '1girl',
              characters: chars,
              params: const GenParams().copyWith(
                model: 'NAI 4.5 Full',
                useCoords: on,
              ),
            ),
            presetId: 'none',
          ).body;
          final v4 = (body['parameters'] as Map)['v4_prompt'] as Map;
          expect(v4['use_coords'], on);
          final caps = (v4['caption'] as Map)['char_captions'] as List;
          expect((caps[0] as Map)['centers'], [
            {'x': 0.1, 'y': 0.1},
          ]);
          expect((caps[1] as Map)['centers'], [
            {'x': 0.9, 'y': 0.9},
          ]);
        }
      });
    });

    test('positionChipLabel:grid 模式显示会被吸附到的那一格', () {
      expect(positionChipLabel('0.4200,0.6700'), '42,67%');
      expect(positionChipLabel('0.4200,0.6700', grid: true), 'C4');
      expect(positionChipLabel(null, grid: true), 'AUTO');
    });
  });

  // NAI 要求 v4_prompt / v4_negative_prompt 两份 char_captions 等长,不等直接 400
  // 「V4 positive and negative character prompts must have the same length.」。
  // 早先负向只收写了负向的角色 —— 只要有一个角色没写负向就出不了图。
  test('角色负向与正向等长:没写负向的发空串', () {
    final body = buildNaiPayload(
      _state('NAI 4.5 Full').copyWith(
        characters: const [
          CharacterPrompt(id: 'a', name: 'a', positive: 'x', position: 'B3'),
          CharacterPrompt(
            id: 'b',
            name: 'b',
            positive: 'y',
            negative: 'bad hands',
            position: 'D3',
          ),
        ],
      ),
      presetId: 'heavy',
    ).body;
    List<dynamic> caps(String key) =>
        (((body['parameters'] as Map)[key] as Map)['caption']
                as Map)['char_captions']
            as List;
    final neg = caps('v4_negative_prompt');
    expect(neg.length, caps('v4_prompt').length);
    expect(neg[0], {
      'char_caption': '',
      'centers': [
        {'x': 0.3, 'y': 0.5},
      ],
    });
    expect((neg[1] as Map)['char_caption'], 'bad hands');
  });

  test('显示名:去掉 .0,名字其余照旧;非 NAI 原样', () {
    expect(modelName('NAI 5.0 Full Medium'), 'NAI 5 Full Medium');
    expect(modelName('NAI 4.5 Curated'), 'NAI 4.5 Curated');
    expect(modelName('NAI 4.0 Full'), 'NAI 4 Full');
    expect(modelName('Krea 2 Raw'), 'Krea 2 Raw');
  });

  test('顶栏短名:去掉 .0,只把 Medium 缩成 M;非 NAI 原样', () {
    expect(shortModelName('NAI 5.0 Full'), 'NAI 5 Full');
    expect(shortModelName('NAI 5.0 Full Medium'), 'NAI 5 Full M');
    expect(shortModelName('NAI 5.0 Curated'), 'NAI 5 Curated');
    expect(shortModelName('NAI 4.5 Full'), 'NAI 4.5 Full');
    expect(shortModelName('NAI 4.0 Curated'), 'NAI 4 Curated');
    expect(shortModelName('Anima Turbo'), 'Anima Turbo');
    expect(shortModelName('Krea 2 Raw'), 'Krea 2 Raw');
    expect(shortModelName(''), '');
  });
}

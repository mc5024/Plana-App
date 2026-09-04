// V5 上线后与 web 对齐的三条硬契约(2026-08-24 同步)。
//
// 三条都是**静默错**:发错了不崩、不报错,只是元数据写进去是错的、或者字段被
// 服务端悄悄丢掉。人工点一遍 UI 一个都看不出来 —— 只能靠测试钉住。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/generate/bot_request.dart';
import 'package:plana_app/features/generate/char_position.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/nai_request.dart';
import 'package:plana_app/features/generate/prompt_presets.dart';
import 'package:plana_app/features/import/image_metadata.dart';

/// 发送层对第 [i] 个 AUTO 角色代入的中心点(与 nai_request 的 _center 同表)。
Map<String, double> _centerForAuto(int i) =>
    kAutoCenters[i % kAutoCenters.length];

/// 一份**故意把两个 V5 不支持的开关都打开**的状态:非 karras + Variety+。
/// 用户切到 V5 之前留下的值就长这样,收口没做好它们就会被带出去。
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

  // 官方能力表里 V5 的 noiseSchedule / cfgDelay 都是 false:请求清洗会把
  // noise_schedule 硬写回 karras、把 skip_cfg_above_sigma 删掉。带过去不会报错,
  // 只是白发 —— 但用户切模型前留下的开关会一直显示成"开着",所以两条线都收口。
  group('V5 不发它没有的两项能力', () {
    test('直连:noise_schedule 恒 karras', () {
      expect(_direct('NAI 5.0 Full')['noise_schedule'], 'karras');
      expect(_direct('NAI 5.0 Curated')['noise_schedule'], 'karras');
    });

    test('直连:Variety+ 开着也不发 skip_cfg_above_sigma', () {
      expect(_direct('NAI 5.0 Full')['skip_cfg_above_sigma'], isNull);
    });

    test('bot:同一口径(后端还会再兜一道,但别指望它)', () {
      expect(_bot('NAI 5.0 Full')['noiseSchedule'], 'karras');
      expect(_bot('NAI 5.0 Full')['varietyPlus'], isFalse);
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

    // 自家出的图导回来,不该凭空多出一批用户从没摆过的站位。
    //
    // AUTO **发出去就没了**:请求和元数据里记的都是 _center 代入的具体坐标
    // (第一个 0.3,0.5 —— 正压在 B3 格心上)。不认这张自动排布表的话,导入
    // 回来第一个角色写着 B3、第二个 D3,用户从没点过那两格。
    group('导入:自动排布的坐标还原成 AUTO', () {
      ({double x, double y}) at(int i) =>
          (x: kAutoCenters[i]['x']!, y: kAutoCenters[i]['y']!);

      test('整批落在自动序列上 → 全体 AUTO', () {
        expect(isAutoCenterLayout([at(0)]), isTrue);
        expect(isAutoCenterLayout([at(0), at(1)]), isTrue);
        expect(isAutoCenterLayout([at(0), at(1), at(2), at(3)]), isTrue);
        // 超过表长按 % 轮换,与发送侧同一套
        expect(
          isAutoCenterLayout([for (var i = 0; i < 8; i++) at(i % 6)]),
          isTrue,
        );
      });

      test('顺序不对 / 有一位偏了 → 保留站位,不误判', () {
        expect(isAutoCenterLayout([at(1), at(0)]), isFalse, reason: '换了序就是摆过的');
        expect(isAutoCenterLayout([at(0), (x: 0.1, y: 0.1)]), isFalse);
        expect(isAutoCenterLayout([(x: 0.5, y: 0.5)]), isFalse, reason: 'C3 不在表里');
      });

      test('缺坐标 / 空列表 → 不算自动排布', () {
        expect(isAutoCenterLayout([null]), isFalse);
        expect(isAutoCenterLayout([at(0), null]), isFalse);
        expect(isAutoCenterLayout([]), isFalse);
      });

      test('JSON 浮点有误差也认', () {
        expect(isAutoCenterLayout([(x: 0.30000000000000004, y: 0.5)]), isTrue);
      });

      // 这条是「改了也不会变差」的依据:落在自动序列上的坐标,按 AUTO 重发时
      // _center 原样代回同一组数 —— 请求逐字节相同,只是徽章老实写 AUTO。
      test('还原成 AUTO 之后重发,坐标与原来逐位相同', () {
        for (var i = 0; i < kAutoCenters.length; i++) {
          final a = at(i);
          expect(positionOfCenter(a.x, a.y), isNotNull, reason: '本来会被读成格子 id');
          expect(_centerForAuto(i), {'x': a.x, 'y': a.y});
        }
      });
    });

    test('positionChipLabel:grid 模式显示会被吸附到的那一格', () {
      expect(positionChipLabel('0.4200,0.6700'), '42,67%');
      expect(positionChipLabel('0.4200,0.6700', grid: true), 'C4');
      expect(positionChipLabel(null, grid: true), 'AUTO');
    });
  });
}

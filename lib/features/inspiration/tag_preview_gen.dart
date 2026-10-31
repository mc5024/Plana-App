import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/backend_config.dart';
import '../../core/net/bot_stream.dart';
import '../../core/net/nai_client.dart';
import '../../core/net/nai_gate.dart';
import '../../core/store/gen_settings.dart';
import '../generate/bot_request.dart';
import '../generate/models.dart';
import '../generate/nai_request.dart';
import 'tag_models.dart';

/// 编辑器预览图生成:参数与提示词模板逐字对齐 web(useOCManager
/// generatePreviewBase64 / useArtistManager buildPreviewPrompts)。
/// GenParams 默认值即 web 预览参数(4.5 Full · 28 步 · CFG5 · Euler A ·
/// karras),仅覆盖宽高与正负向;按接入方式走直连流式或 bot 任务。

const _kCommonPositive =
    'best quality, amazing quality, very aesthetic, absurdres, very aesthetic, '
    'masterpiece, no text';

/// 角色预览的固定画风前缀(web fixedPrompt)。
const _kOcStylePrefix =
    '2::1girl, solo::, 0.6::artist:shano hiyori::, 1.2::artist:min (120716) ::, '
    '0.6::artist:momoco ::, 0.6::artist:Akakura::, 1::artist:miv4t ::,'
    '::artist:aramedraw,artist:kouyafu,0.5::artist:fujiyama,'
    '::artist:motimoti067,0.8::artist:ham_melon_(iloha_24),'
    '::0.7::artist:onineko::,artist:ouchi_kaeru,0.95::artist:syagamu,'
    '::artist:konya_karasue,artist:luozhou pile,0.6::artist:hagimorijia,:: '
    '0.6::artist:yumenouchi_chiharu,1.02::artist:huang_gua,:: '
    '-2::artist collaboration,noise,film grain::, year 2024, year 2025, '
    '-0.45::flat color::, 1.3::white background,full body,stand::';

const _kOcNegative =
    '2::little dolls, extra characters,extra fingers,logo,watermark,signature,'
    'artist collaboration,deformed,what::,lowres, artistic error, film grain, '
    'scan artifacts, worst quality, bad quality, jpeg artifacts, '
    'very displeasing, chromatic aberration, dithering, halftone, screentone, '
    'multiple views, logo, too many watermarks, negative space, blank page, '
    '0.5::monochrome, blue tint, cyan tint, desaturated, cold color::';

const _kArtistNegative =
    '2::little dolls, extra characters,extra fingers,logo,watermark,signature,'
    'artist collaboration,deformed,what::, lowres, artistic error, film grain, '
    'scan artifacts, worst quality, bad quality, jpeg artifacts, '
    'very displeasing, chromatic aberration, dithering, halftone, screentone, '
    'multiple views, logo, too many watermarks, negative space, blank page, 1';

/// 画师串四张预览的随机语法模板(氛围/场景服饰/色彩情绪/构图盲测)。
List<String> artistPreviewPrompts(String artistString) => [
  '$artistString, -2::artist collaboration::, '
      '1.3::The atmosphere of ||winter|autumn|summer|spring||::, '
      '||day|night|star night|golden hour|sunset||, lively atmosphere, '
      '||cowboy shot|upper body||, 1girl, solo, $_kCommonPositive',
  '$artistString, -2::artist collaboration::, '
      '||outdoors, nature|indoors, room|city street|fantasy ruins||, '
      '||casual wear|school uniform|fantasy clothing|elegant dress||, '
      '||standing|sitting|dynamic pose||, full body, 1girl, solo, '
      '$_kCommonPositive',
  '$artistString, -2::artist collaboration::, '
      '||vibrant colors|pastel colors|dark moody colors|monochrome||, '
      '||smile|expressionless|crying|angry||, '
      '||looking at viewer|looking away||, close-up, portrait, 1girl, solo, '
      '$_kCommonPositive',
  '$artistString, -2::artist collaboration::, '
      '||scenery, no humans, wide angle|2girls, interacting, cowboy shot|'
      '1boy, solo, upper body|1girl, solo, extreme dynamic angle||, '
      '||highly detailed background|simple background||, $_kCommonPositive',
];

/// 生成一张预览。[slot] 对画师串选模板(0-3);角色恒用固定前缀 + 条目正向。
/// 失败抛异常(message 可直接展示)。
Future<Uint8List> generateTagPreview(
  WidgetRef ref, {
  required TagCategory cat,
  required String positive,
  required int slot,
  void Function(int step, int total)? onStep,
}) async {
  final p = positive.trim();
  final (int w, int h, String prompt, String negative) = switch (cat) {
    TagCategory.character => (832, 1216, '$_kOcStylePrefix, $p', _kOcNegative),
    TagCategory.artist => (
      1216,
      832,
      artistPreviewPrompts(p)[slot % 4],
      _kArtistNegative,
    ),
    _ => throw StateError('该分类不支持生成预览'),
  };

  final s = GenerateState.initial().copyWith(
    prompt: prompt,
    negativePrompt: negative,
    params: const GenParams().copyWith(width: w, height: h),
  );

  if (ref.read(authModeProvider).value == AuthMode.bot) {
    final session = ref.read(botSessionProvider).value;
    if (session == null) throw BackendException('需要 Bot 授权');
    final base = await ref.read(backendBaseProvider.future);
    if (base.isEmpty) throw BackendException('未配置后端地址');
    final client = ref.read(backendClientProvider);
    final params = buildBotParams(
      s,
      seed: Random().nextInt(1 << 31),
      presetId: 'none',
    );
    final sub = await client.botGenerate(
      sessionId: session.sessionId,
      params: params,
    );
    if (!sub.success || sub.taskId == null) {
      throw BackendException(sub.message.isEmpty ? '任务提交失败' : sub.message);
    }
    // 预览恒是单张:上面那份 params 是现搭的(`const GenParams()`),
    // batchCount 就是默认的 1,不会继承创作页里选的张数。
    final out = await streamBotTask(
      baseUrl: base,
      sessionId: session.sessionId,
      taskId: sub.taskId!,
      client: client,
      onProgress: (step, total, _, _) => onStep?.call(step, total),
    );
    return out.first;
  }

  // 同超分:预览也吃直连那条账号限额,得和生成抢同一个闸门,否则生成中开预览
  // 两边一起 429。整段流都在槽里 —— 拿到首帧就放槽的话后半程仍在占着连接。
  // paid:预览就是一张正经的图,该扣的点一分不少,所以没勾「参与点数生成」的 Key
  // 不参与。用哪把由闸门定。
  // 关了流式就跟创作页一样走一次性端点(自定义接口可能只有那一个),
  // 那时没有逐步进度,onStep 一次都不响 —— 调用方本就按不确定进度渲染。
  final streaming = ref.read(genSettingsProvider).value?.streamGen ?? true;
  final last = await ref.read(naiGateProvider).run(paid: true, (
    token,
    base,
  ) async {
    if (token == null || token.isEmpty) {
      throw NaiException('请先在「我的」页设置 NovelAI API Token');
    }
    // 打哪台机器跟着闸门给的那把 Key 走。
    final client = ref.read(naiClientProvider(base));
    final built = buildNaiPayload(
      s,
      presetId: 'none',
      thirdParty: base.isNotEmpty,
      vibes: const [],
      img2img: null,
      charRefs: const [],
    );
    if (!streaming) {
      return client.generateImage(token: token, body: built.body);
    }
    Uint8List? got;
    await for (final f in client.generateImageStream(
      token: token,
      body: built.body,
    )) {
      got = f.bytes;
      onStep?.call(f.isFinal ? s.params.steps : (f.step ?? 0), s.params.steps);
      if (f.isFinal) break;
    }
    return got;
  });
  if (last == null) throw NaiException('未收到图片数据');
  return last;
}

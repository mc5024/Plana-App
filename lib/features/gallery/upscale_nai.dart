import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/nai_client.dart';
import '../../core/net/nai_gate.dart';
import '../../core/store/app_stores.dart';
import 'upscale_model.dart';

/// NAI 官方超分。按当前授权模式分发:
///  - bot:走后端 `/api/upscale`(Bearer 会话)。
///  - 直连:app 直打 NAI(Bearer 用户 token),解 zip。
///
/// 只有 V5 扩散超分这一条线(image 子域,固定 ×2、输入尺寸无白名单、按源图
/// 1–4 点)。传统 4× 超分(api 子域、只收三种固定尺寸)官方已下线,2026-08-31
/// 从本 app 摘掉。
///
/// 输入原图 PNG + 尺寸;返回 (超分 PNG, 结果宽高)。
/// 远程一次性调用无逐步进度 —— 只经 [onStage] 报阶段。
Future<({Uint8List png, int width, int height})> upscaleNai(
  WidgetRef ref,
  Uint8List srcPng, {
  required int width,
  required int height,
  void Function(String stage)? onStage,
}) async {
  onStage?.call('编码图片…');
  final b64 = base64Encode(srcPng);
  final mode = ref.read(authModeProvider).value;

  Uint8List out;
  if (mode == AuthMode.bot) {
    final session = await ref.read(botSessionProvider.future);
    if (session == null) throw Exception('暂未开放');
    onStage?.call('提交后端…');
    final r = await ref
        .read(backendClientProvider)
        .upscale(
          sessionId: session.sessionId,
          imageBase64: b64,
          width: width,
          height: height,
          scale: 2,
          mode: 'nai5',
          model: kNaiV5UpscaleModel,
          declaredBlurSigma: 0,
        );
    if (!r.success || r.imageBase64 == null || r.imageBase64!.isEmpty) {
      throw Exception(r.message.isNotEmpty ? r.message : 'NAI 超分失败');
    }
    onStage?.call('接收结果…');
    out = base64Decode(r.imageBase64!);
  } else {
    onStage?.call('上传 NAI…');
    // 占一个直连槽再打:超分和生成花的是同一个账号、撞的是同一个限流桶。
    // 不占的话「生成中顺手点一次超分」必 429(NAI 同 Key 不许并发)。
    //
    // paid:超分一定扣点(按源图像素 1–4 点),所以没勾「参与点数生成」的 Key
    // 不参与 —— 白嫖号的点数不该被超分悄悄花掉。用哪把由闸门定。
    // 打哪台机器跟着闸门给的那把 Key 走(第三方的 key 只在它自己那台上有效)。
    out = await ref.read(naiGateProvider).run(paid: true, (token, base) {
      if (token == null || token.isEmpty) {
        throw Exception('没有可用于付费操作的 NAI Token');
      }
      return ref
          .read(naiClientProvider(base))
          .upscaleV5(token: token, imageBase64: b64);
    });
    onStage?.call('接收结果…');
    // 本机记账(bot 模式由服务端记):按**源图**像素查表 1–4 点。
    try {
      final pts = naiV5UpscalePrice(width, height) ?? 4;
      ref.read(appStoresProvider).ledger.recordOp('upscale', pts);
    } catch (_) {}
  }

  final size = naiV5UpscaleTargetSize(width, height);
  return (png: out, width: size.w, height: size.h);
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/auth/token_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/net/nai_client.dart';
import '../../core/store/app_stores.dart';
import 'models.dart';
import 'nai_request.dart' show naiModelId;
import 'vibe_cache.dart';

/// 统一 Vibe 编码服务:内容寻址缓存优先,miss 时按当前授权模式
/// (直连 NAI / bot 后端)现场编码(扣 2 Anlas)并回填缓存。
/// 生成链路与库页「预编码」共用同一入口,避免多处实现漂移。
final vibeEncoderProvider = Provider<VibeEncoder>(VibeEncoder.new);

/// 尚未缓存的 Vibe 编码费(Anlas),生成按钮/循环面板的费用要带上它。
///
/// **为什么必须单列**:`estimateCost` 里的 `vibeExtra` 是 NAI 的「第 5 张起每张
/// +2」多图附加费,与编码费是两笔钱。编码费按「图 × 模型 × IE」组合首次收 2 点、
/// 之后走缓存。不算的话,新加一张 Vibe 时按钮写着「免费」,一生成实扣 2 点
/// —— 用户实测反馈。
///
/// 入参是 [vibeEncodeFeeKey] 生成的紧凑键(family 需要可比较的参数)。
final vibeEncodeFeeProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  key,
) async {
  if (key.isEmpty) return 0;
  final parts = key.split('\n');
  final model = parts.first;
  final encoder = ref.read(vibeEncoderProvider);
  var miss = 0;
  for (final row in parts.skip(1)) {
    final i = row.lastIndexOf(':');
    if (i <= 0) continue;
    final ie = double.tryParse(row.substring(i + 1));
    if (ie == null) continue;
    final hit = await encoder.cached(
      imageHash: row.substring(0, i),
      model: model,
      infoExtracted: ie,
    );
    if (hit == null) miss++;
  }
  return miss * 2;
});

/// 构造 [vibeEncodeFeeProvider] 的查询键;无需计费时返回空串(provider 直接给 0)。
///
/// **bot 模式同样计费**:顶栏显示的是后端共享账户余额,编码一样会让它掉;
/// `estimateCost` 在 bot 下也照常报生成费用(只是按 Opus 算),编码费没有理由
/// 单独隐身。(初版按「不扣用户自己的点」把 bot 排除了 —— 判断错了,实测发现
/// bot 模式下按钮恒显示「免费」。)
///
/// 两种确实不收费的情形,与 `_prepareVibes` 的实际行为严格对齐:
/// - **无原图的纯编码 Vibe**:用文件自带的 `encodedByModel`,不发编码请求
/// - 缺内容哈希(理论上不该发生):查不了缓存,不臆测收费
String vibeEncodeFeeKey(GenerateState s) {
  final rows = <String>[];
  for (final v in s.vibes) {
    if (!v.enabled || v.image == null) continue;
    final h = v.imageHash;
    if (h == null || h.isEmpty) continue;
    rows.add('$h:${v.infoExtracted}');
  }
  if (rows.isEmpty) return '';
  // 模型必须转成 API id:缓存文件名用的是 encodings 键(v4-5full 等),
  // 传展示名(「NAI 4.5 Full」)会永远查不中,按钮就会一直多报 2 点。
  return '${naiModelId(s.params.model)}\n${rows.join('\n')}';
}

class VibeEncoder {
  VibeEncoder(this._ref);

  final Ref _ref;

  /// 只查缓存,不发起编码。
  Future<String?> cached({
    required String imageHash,
    required String model,
    required double infoExtracted,
  }) async {
    final cache = await _ref.read(vibeCacheProvider.future);
    return cache.get(imageHash, model, infoExtracted);
  }

  /// 缓存优先编码。未授权抛 [StateError](调用方兜 UI 提示)。
  Future<String> encode({
    required Uint8List image,
    required String imageHash,
    required String model,
    required double infoExtracted,
  }) async {
    final cache = await _ref.read(vibeCacheProvider.future);
    final hit = await cache.get(imageHash, model, infoExtracted);
    if (hit != null) return hit;

    final String enc;
    if (_ref.read(authModeProvider).value == AuthMode.bot) {
      final session = await _ref.read(botSessionProvider.future);
      if (session == null) throw StateError('暂未开放');
      enc = await _ref
          .read(backendClientProvider)
          .encodeVibe(
            sessionId: session.sessionId,
            imageBase64: base64Encode(image),
            informationExtracted: infoExtracted,
            model: model,
          );
    } else {
      // 主账号那把 —— 连它的接口地址一起,第三方的 key 得打自己那台机器。
      final key = await _ref.read(primaryNaiKeyProvider.future);
      if (key == null || key.token.isEmpty) throw StateError('未设置令牌,无法编码');
      enc = await _ref
          .read(naiClientProvider(key.endpoint))
          .encodeVibe(
            token: key.token,
            imageBase64: base64Encode(image),
            infoExtracted: infoExtracted,
            model: model,
          );
      // 本机记账:直连现场编码扣 2 Anlas(缓存命中免费,不落账)
      try {
        _ref.read(appStoresProvider).ledger.recordOp('vibe', 2);
      } catch (_) {}
    }
    await cache.put(imageHash, model, infoExtracted, enc);
    return enc;
  }
}

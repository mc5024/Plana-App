import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'gen_abort.dart';
import 'nai_chat_compat.dart';
import 'nai_endpoint.dart';
import 'nai_proxy.dart';

/// 流式生成的一帧:step 非空=中间预览,isFinal=终图。
typedef NaiFrame = ({int? step, bool isFinal, Uint8List bytes});

/// NAI 5 的 Opus 充电式额度(官方叫 Opus Generations allowance)。
///
/// **只有 Opus 且订阅有效时接口才下发这一块**,其余情况为 null —— 非 Opus、
/// 以及 V5 之前的所有图像/文本模型都不受这层额度约束,照旧只看 Anlas。
///
/// - [percent]          剩余百分比 0~100
/// - [isNegative]       已耗尽(逻辑上跌破 0)。为真时按 0 显示,且 V5 免费尺寸图
///                      不再免费、转扣 Anlas,回充过 0 自动恢复
/// - [secondsToNextPct] 距下一次 +1% 回充还剩多少秒(回充纯时间驱动,与是否在
///                      花 Anlas 无关,充满 100% 封顶,没有「周/月」周期)
/// - [accounts]         这块额度合了几个号。直连线恒 1;bot 线是服务端主池里
///                      Opus 号的个数,那时 [percent] 是**平均水位** —— 界面上
///                      的读数和折算张数都要乘回号数(每个号满值都是 ≈1730 张),
///                      换算一律走 [NaiUsageX],别直接读这个字段去画
typedef NaiUsage = ({
  double percent,
  bool isNegative,
  int secondsToNextPct,
  int accounts,
});

/// `/user/subscription` 响应里的 `usage` 块 → [NaiUsage];整块缺省时返回 null。
///
/// 这三个字段名是从官方前端扒的,官方没有文档承诺过 —— 所以**只认 percent**:
/// 它读不到就整块作废,让界面干干净净回落到「只显示 Anlas」。反过来若拿个
/// 默认 0 顶上,用户看到的就是一块「额度已耗尽」的假警报,比不显示糟得多。
///
/// bot 线走的是同一个解析器:服务端 `/api/anlas` 把主池各号并成一块后,
/// 沿用了 NAI 这套字段名,只多带一个 `accounts`(号数)。直连响应没这个字段,
/// 缺省算 1 —— 一套字段名一处实现,两条线不会各自漂。
NaiUsage? parseNaiUsage(Object? raw) {
  if (raw is! Map) return null;
  final pct = (raw['percent'] as num?)?.toDouble();
  if (pct == null) return null;
  return (
    percent: pct,
    isNegative: raw['isNegative'] == true,
    secondsToNextPct: (raw['timeUntilNextPercent'] as num?)?.toInt() ?? 0,
    accounts: max(1, (raw['accounts'] as num?)?.toInt() ?? 1),
  );
}

/// 订阅信息:剩余点数 + 是否 Opus(决定免费额度)+ NAI 5 额度电池。
///
/// [anlas] 是两笔钱的合计,给计费估算用;界面要摊开显示时看后面两项:
/// [fixedAnlas] 是订阅每月赠送的固定额(月底重置),[purchasedAnlas] 是自己买断
/// 的已购额(不过期)。合计相同但构成不同 —— 只报一个数看不出还剩多少是自己的。
///
/// [tier] 为生效档位:订阅有效(active/宽限)时取原 tier(1 Tablet /
/// 2 Scroll / 3 Opus),失效按 0(未订阅)。
/// [usage] 见 [NaiUsage];非 Opus / 订阅失效时为 null。bot 授权线由服务端把
/// 主池各 Opus 号合并成一块水位下发,那时 `accounts` > 1。
typedef NaiSubscription = ({
  int anlas,
  int fixedAnlas,
  int purchasedAnlas,
  bool isOpus,
  int tier,
  NaiUsage? usage,
});

/// 档位显示名。
String naiTierName(int tier) => switch (tier) {
  3 => 'Opus',
  2 => 'Scroll',
  1 => 'Tablet',
  _ => '未订阅',
};

/// [NaiUsage] 的派生显示值。常数取自官方前端:满值 100% ≈ 1730 张免费尺寸
/// V5 图,故每 1% 合 17.3 张;回充按天算就是 86400 秒 ÷ 每 1% 所需秒数。
///
/// 全是纯函数,不碰 UI —— 电池条、约图数、回充速率三处读的是同一份算法,
/// 免得各自在 widget 里手抄一遍再抄歪。
extension NaiUsageX on NaiUsage {
  /// 每 1% 额度约合多少张免费尺寸 V5 图。
  static const imagesPerPct = 17.3;

  /// 池子满值:每个号 100%,所以 N 个号是 100N。直连线恒 100。
  ///
  /// 百分比一律按**相加**显示(5 个号平均 74.8% → 374%,而不是平均后的 74.8%):
  /// 平均水位那个数看着像单号的电量,跟旁边「约 6470 张」这个池子总量对不上,
  /// 两个数摆在一起反而要人心算号数才对得上账。相加之后两者同尺度。
  ///
  /// 代价是满值不再是 100 —— 所以凡是拿百分比跟 100 比的地方都要换成它。
  double get fullPct => 100.0 * accounts;

  /// 电池读数(**池子合计**):耗尽按 0,其余夹到 0~[fullPct](接口给过 100.4
  /// 这种越界值)。会超过 100,那是有意的,见 [fullPct]。
  double get batteryPct =>
      isNegative ? 0 : (percent * accounts).clamp(0.0, fullPct).toDouble();

  /// 约合还能出多少张免费尺寸 V5 图。[batteryPct] 已是池子合计,不再乘号数。
  int get imagesRemaining => (imagesPerPct * batteryPct).round();

  /// 回充速率(百分点/天,**池子合计**:每个号都在各自回充,所以乘号数),
  /// 保留一位小数;拿不到回充节奏时为 0。
  /// 电池条上那截「24 小时后」的预测、以及 [daysToFull] 都按它算。
  double get refillPctPerDay => secondsToNextPct <= 0
      ? 0
      : (86400 / secondsToNextPct * accounts * 10).round() / 10;

  /// 回充速率(百分点/小时,同样是池子合计)。**不预先取整** —— 单号实际速率在
  /// 0.6%/时 这个量级,照日速率那样先四舍五入到一位小数会把它压成 0.0,
  /// 连带张数也变 0。取整交给显示层按大小挑位数。
  double get refillPctPerHour =>
      secondsToNextPct <= 0 ? 0 : 3600 / secondsToNextPct * accounts;

  /// 回充速率折成张数/小时。速率已含号数,这里不再乘。
  int get imagesPerHour => (imagesPerPct * refillPctPerHour).round();

  /// 从**当前**充到满还要几天;不回充时为 null(界面显示「—」,不写 ∞)。
  ///
  /// 官方 bundle 里那个数是 `100 / 回充速率` —— 那是从 0 充满一整轮要多久,
  /// 跟标签写的「还要多久充满」并不是一回事。这里按标签的字面意思算剩余缺口,
  /// 让读数和文案对得上;满电时自然是 0 天。
  double? get daysToFull {
    final rate = refillPctPerDay;
    if (rate <= 0) return null;
    return (fullPct - batteryPct) / rate;
  }

  /// 低电量或已耗尽:该提醒用户「再生成就要扣 Anlas 了」。阈值取自官方前端。
  ///
  /// 这里**故意读 percent 原值**(单号口径)而不是相加后的读数:门槛问的是
  /// 「一个号还剩多少」,跟着号数放大的话,5 个号各剩 4% 也会被算作健康。
  bool get isLowOrEmpty => isNegative || percent < 5;
}

/// NovelAI 直连客户端(v1:App 用用户自己的 Bearer token 直接打 NAI)。
/// 复刻后端 `novelai_web_ui/server/app.py` 的原生请求。
///
/// 按**基址**分实例(family 参数即基址,空串 = 官方 [kNaiOfficialBase])。
///
/// 不是单例:基址跟着每把令牌走(见 `NaiKey.endpoint`),官方号和第三方中转的
/// key 可以同时存着,各打各的机器 —— 没有「当前接口地址」这种全局状态可依赖,
/// 调用方拿的是哪把 Key 就传哪个地址。换地址等于换 family 键,`watch` 它的
/// 账户查询会自己重来一遍。
///
/// 唯一的全局量是代理开关([naiProxyProvider]),只作用于官方那份:开关一拨,
/// 官方客户端重建,账户查询同样自己重来;第三方的不看它,也就不随它重建。
final naiClientProvider = Provider.family<NaiClient, String>(
  (ref, base) =>
      NaiClient(base: base, proxy: base.isEmpty && ref.watch(naiProxyProvider)),
);

class NaiException implements Exception {
  NaiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => 'NaiException($status): $message';
}

/// 服务端明确不认这把令牌(401):账号删了、令牌重置了、JWT 过期了,或者压根
/// 贴错了。官方对这几种回的是同一句(image 子域都回 `Unauthorized`,api 子域都回
/// `User not found.`),分不出是哪种 —— 所以界面只说「令牌失效」,不替它猜原因。
///
/// 要跟「查询失败」分开摆:那边是网络/服务器的事,点按重试有意义;这边重查多少
/// 遍都一样,只能换令牌。
bool naiTokenRejected(Object? e) => e is NaiException && e.status == 401;

/// V5 扩散超分用的模型:官方前端写死这个。
/// 实测只有 nai-diffusion-5-full / -curated 支持 standalone upscaling。
const kNaiV5UpscaleModel = 'nai-diffusion-5-curated';

class NaiClient {
  /// [base] 为空 = 官方 [kNaiOfficialBase],此时开了 [proxy] 改经 [kNaiProxyBase];
  /// 非空则整条直连线改打它,[proxy] 不起作用。
  NaiClient({String base = '', bool proxy = false})
    : _host = naiBaseOf(base, proxy: proxy),
      _chat = naiEndpointIsChat(base);

  /// `/ai/*` 与 `/user/subscription` 的基址(已带协议、无尾斜杠);
  /// OpenAI 兼容接口则是整条 chat 地址。
  final String _host;

  /// OpenAI 兼容接口(见 `nai_chat_compat.dart`):这种格式只有出图一个端点,
  /// 点数查询、Vibe 编码、超分都没有对应的地址可打。
  final bool _chat;

  /// 有没有逐步预览。OpenAI 兼容接口只回终图。
  bool get streams => !_chat;

  /// 仅供测试观察。
  String get host => _host;

  /// 报错文案里的主机名(自定义地址时不能再张口就说「novelai.net 被拦了」)。
  String get _hostName => Uri.tryParse(_host)?.host ?? _host;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  /// origin / referer 恒写官方站:这两个头是**给 NAI 看的**,自建反代把请求原样
  /// 转上去时改了反而对不上。自定义地址只换主机,不改请求的样子。
  Map<String, String> _genHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'accept': '*/*',
    'origin': 'https://novelai.net',
    'referer': 'https://novelai.net/',
    'user-agent': _ua,
  };

  /// 流式端点头:NAI 前端每请求都带 x-correlation-id(6 hex)+ x-initiated-at。
  Map<String, String> _streamHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'accept': '*/*',
    'accept-language': 'en-US,en;q=0.9',
    'origin': 'https://novelai.net',
    'referer': 'https://novelai.net/',
    'user-agent': _ua,
    'x-correlation-id': _corrId(),
    'x-initiated-at': _isoNow(),
  };

  String _corrId() {
    final r = Random();
    return List<int>.generate(
      3,
      (_) => r.nextInt(256),
    ).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  String _isoNow() {
    final d = DateTime.now().toUtc();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p2(d.month)}-${p2(d.day)}'
        'T${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}.000Z';
  }

  /// 流式文生图:POST /ai/generate-image-stream。
  /// 响应为「4 字节大端长度 + msgpack 消息」帧序列,消息 {step_ix, image, code}:
  /// step_ix 非空=中间预览、为空=终图;code!=200=错误。单帧解析失败跳过(与后端一致)。
  Stream<NaiFrame> generateImageStream({
    required String token,
    required Map<String, dynamic> body,
    GenAbort? abort,
  }) async* {
    if (_chat) {
      final bytes = await _chatGenerate(token, body, abort);
      yield (step: null, isFinal: true, bytes: bytes);
      return;
    }
    final uri = Uri.parse('$_host/ai/generate-image-stream');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    // 取消:强制关连接,进行中的请求/流随即断开抛错(对齐 web abort fetch)。
    abort?.whenAbort(() {
      try {
        client.close(force: true);
      } catch (_) {}
    });

    var received = 0; // 诊断:累计字节
    var parseFails = 0; // 诊断:解析失败帧数
    String? firstParseErr;
    var yielded = 0;

    try {
      final payload = utf8.encode(jsonEncode(body));
      final req = await client.postUrl(uri);
      _streamHeaders(token).forEach(req.headers.set);
      req.contentLength = payload.length;
      req.add(payload);

      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        final text = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10), onTimeout: () => '');
        throw NaiException(
          _errorTextRaw(text, resp.statusCode),
          status: resp.statusCode,
        );
      }

      final buf = <int>[];
      // 帧间隔超 90s 视为断流(出图步间通常 1~3s)
      await for (final chunk in resp.timeout(const Duration(seconds: 90))) {
        received += chunk.length;
        buf.addAll(chunk);
        var off = 0;
        while (buf.length - off >= 4) {
          final len =
              (buf[off] << 24) |
              (buf[off + 1] << 16) |
              (buf[off + 2] << 8) |
              buf[off + 3];
          if (len < 0 || len > (64 << 20)) {
            throw NaiException('流数据格式异常(帧长 $len)');
          }
          if (buf.length - off < 4 + len) break;
          final msgBytes = Uint8List.fromList(
            buf.sublist(off + 4, off + 4 + len),
          );
          off += 4 + len;

          dynamic msg;
          try {
            msg = msgpack.deserialize(msgBytes);
          } catch (e) {
            parseFails++;
            firstParseErr ??= '$e';
            continue; // 与后端一致:坏帧跳过,不断流
          }
          if (msg is! Map) continue;

          final code = msg['code'];
          if (code != null && code != 200) {
            final m = msg['message'];
            throw NaiException(
              m is String ? m : '生成失败(code $code)',
              status: code is int ? code : null,
            );
          }

          final img = msg['image'];
          if (img is List<int>) {
            final stepIx = msg['step_ix'];
            yielded++;
            yield (
              step: stepIx is int ? stepIx + 1 : null,
              isFinal: stepIx == null,
              bytes: img is Uint8List ? img : Uint8List.fromList(img),
            );
          }
        }
        if (off > 0) buf.removeRange(0, off);
      }

      if (yielded == 0) {
        final diag = StringBuffer('未收到图片帧(收到 $received 字节');
        if (parseFails > 0) diag.write(',$parseFails 帧解析失败:$firstParseErr');
        diag.write(')');
        throw NaiException(diag.toString());
      }
    } on NaiException {
      rethrow;
    } on TimeoutException {
      throw NaiException('生成超时,请重试');
    } on SocketException catch (e) {
      throw NaiException('无法连接 $_hostName:${e.message}');
    } on HandshakeException {
      throw NaiException('TLS 握手失败,当前网络可能拦截了 $_hostName');
    } catch (e) {
      throw NaiException('流式生成失败:$e');
    } finally {
      client.close(force: true);
    }
  }

  /// 一次性生成:POST /ai/generate-image → zip,解出首张 PNG 字节。
  ///
  /// 两种情况走这条:用户在生成设置里关了流式,或流式端点回 404/405。
  /// 没有逐步预览 —— 整张图画完才回来。
  ///
  /// [abort] 一触发就关掉客户端,进行中的请求随即断开(同流式那条)。取消之后
  /// 这里抛的是「网络错误」,调用方先看 `abort.aborted` 再判错误。
  Future<Uint8List> generateImage({
    required String token,
    required Map<String, dynamic> body,
    GenAbort? abort,
  }) async {
    if (_chat) return _chatGenerate(token, body, abort);
    final uri = Uri.parse('$_host/ai/generate-image');
    final client = http.Client();
    abort?.whenAbort(() {
      try {
        client.close();
      } catch (_) {}
    });
    final http.Response resp;
    try {
      resp = await client
          .post(uri, headers: _genHeaders(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw NaiException('网络错误:$e');
    } finally {
      client.close();
    }

    if (resp.statusCode != 200) {
      throw NaiException(_errorText(resp), status: resp.statusCode);
    }

    return _pngFromMaybeZip(resp.bodyBytes);
  }

  /// OpenAI 兼容接口出图:官方请求体转成 chat 请求,从回复里取图。
  /// 取消同 [generateImage]。
  Future<Uint8List> _chatGenerate(
    String token,
    Map<String, dynamic> body,
    GenAbort? abort,
  ) async {
    final payload = jsonEncode(naiChatBody(body));
    final client = http.Client();
    abort?.whenAbort(() {
      try {
        client.close();
      } catch (_) {}
    });
    final http.Response resp;
    try {
      resp = await client
          .post(
            Uri.parse(_host),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw NaiException('网络错误:$e');
    } finally {
      client.close();
    }
    final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      throw NaiException(
        _errorTextRaw(text, resp.statusCode),
        status: resp.statusCode,
      );
    }
    return naiChatImage(text);
  }

  /// 从响应字节取 PNG:直接是 PNG(魔数 89 50 4E 47)就用,否则当 zip 解出第一个 png。
  Uint8List _pngFromMaybeZip(Uint8List bytes) {
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return bytes;
    }
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      for (final f in zip.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.png')) {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
    } catch (e) {
      throw NaiException('解压结果失败:$e');
    }
    throw NaiException('结果中未找到图片');
  }

  /// NAI 官方超分:POST https://api.novelai.net/ai/upscale → zip,解出 PNG。
  /// ⚠️ 端点在 api. 子域(非 image.);仅支持 832×1216/1216×832/1024²,scale 固定 4,
  /// 直接扣用户账户 Anlas。
  Future<Uint8List> upscale({
    required String token,
    required String imageBase64,
    required int width,
    required int height,
    int scale = 4,
  }) async {
    final uri = Uri.parse('https://api.novelai.net/ai/upscale');
    final http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {..._genHeaders(token), 'accept': 'application/zip'},
            body: jsonEncode({
              'image': imageBase64,
              'width': width,
              'height': height,
              'scale': scale,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw NaiException('网络错误:$e');
    }
    if (resp.statusCode != 200) {
      throw NaiException(_errorText(resp), status: resp.statusCode);
    }
    return _pngFromMaybeZip(resp.bodyBytes);
  }

  /// V5 扩散超分:POST image.novelai.net/ai/upscale。
  ///
  /// ⚠ 和上面那个 [upscale] 是**两个并存的服务**,不是新旧版本关系
  /// (2026-08-24 实测两个端点都活着,各认各的 schema):
  ///  - `api` 子域  `{image,width,height,scale∈{2,4}}` 传统超分,输入尺寸有白名单
  ///  - `image` 子域 `{image,model,declared_blur_sigma}` 扩散超分,固定 ×2、无白名单
  ///
  /// [model] 实测只有 nai-diffusion-5-full / -curated 支持 standalone upscaling,
  /// 其余模型服务端直接报 "doesn't support standalone upscaling"。
  /// [declaredBlurSigma] = 源图有多糊(官方默认 0),服务端据此调整去模糊力度。
  Future<Uint8List> upscaleV5({
    required String token,
    required String imageBase64,
    String model = kNaiV5UpscaleModel,
    double declaredBlurSigma = 0,
  }) async {
    if (_chat) throw NaiException('这个接口没有超分');
    final uri = Uri.parse('$_host/ai/upscale');
    final http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {..._genHeaders(token), 'accept': 'application/zip'},
            body: jsonEncode({
              'image': imageBase64,
              'model': model,
              'declared_blur_sigma': declaredBlurSigma,
            }),
          )
          .timeout(const Duration(seconds: 300));
    } catch (e) {
      throw NaiException('网络错误:$e');
    }
    if (resp.statusCode != 200) {
      throw NaiException(_errorText(resp), status: resp.statusCode);
    }
    return _pngFromMaybeZip(resp.bodyBytes);
  }

  /// 订阅信息:GET /user/subscription。
  /// anlas = 固定额 + 已购额;isOpus = tier==3 且 active/宽限期(与 web `novelai.ts` 一致)。
  /// 同一份响应里还带 NAI 5 的额度电池(`usage`),见 [parseNaiUsage]。
  Future<NaiSubscription> subscription(String token) async {
    if (_chat) throw NaiException('这个接口不提供账户状态');
    final uri = Uri.parse('$_host/user/subscription');
    final http.Response resp;
    try {
      resp = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw NaiException('网络错误:$e');
    }
    if (resp.statusCode != 200) {
      throw NaiException(_errorText(resp), status: resp.statusCode);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final steps = (data['trainingStepsLeft'] as Map?) ?? const {};
    final fixed = (steps['fixedTrainingStepsLeft'] as num?)?.toInt() ?? 0;
    final purchased = (steps['purchasedTrainingSteps'] as num?)?.toInt() ?? 0;
    final alive = data['active'] == true || data['isGracePeriod'] == true;
    final tier = alive ? ((data['tier'] as num?)?.toInt() ?? 0) : 0;
    return (
      anlas: fixed + purchased,
      fixedAnlas: fixed,
      purchasedAnlas: purchased,
      isOpus: tier == 3,
      tier: tier,
      usage: parseNaiUsage(data['usage']),
    );
  }

  /// Vibe 编码:POST /ai/encode-vibe(每次固定耗 2 Anlas)。
  /// 请求体 `{image: 原始 base64(无 data: 前缀), information_extracted, model}`;
  /// 直连响应是二进制向量 → base64 化(与 web token 模式 `btoa(binary)` 一致)。
  Future<String> encodeVibe({
    required String token,
    required String imageBase64,
    required double infoExtracted,
    required String model,
  }) async {
    if (_chat) throw NaiException('这个接口没有 Vibe 编码');
    final uri = Uri.parse('$_host/ai/encode-vibe');
    final http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              'accept': '*/*',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'origin': 'https://novelai.net',
              'referer': 'https://novelai.net/',
            },
            body: jsonEncode({
              'image': imageBase64,
              'information_extracted': infoExtracted,
              'model': model,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw NaiException('编码参考图失败:$e');
    }
    if (resp.statusCode != 200) {
      throw NaiException(_errorText(resp), status: resp.statusCode);
    }
    return base64Encode(resp.bodyBytes);
  }

  String _errorText(http.Response r) => _errorTextRaw(r.body, r.statusCode);

  String _errorTextRaw(String body, int code) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] is String) return j['message'] as String;
      // OpenAI 风格:{"error": {"message": …}}
      final e = j is Map ? j['error'] : null;
      if (e is Map && e['message'] is String) return e['message'] as String;
    } catch (_) {}
    return switch (code) {
      401 => 'Token 无效或已过期',
      402 => '订阅 / 点数不足',
      429 => '并发过多或触发限流,请稍后重试',
      _ => '请求失败(HTTP $code)',
    };
  }
}

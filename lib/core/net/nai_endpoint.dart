/// 直连线的接口基址。
///
/// 地址**跟着每把令牌走**(见 `NaiKey.endpoint`),不是全局一份的设置 ——
/// 官方号和第三方中转的 key 常要同时存着,全局一份时加一个中转站就会把官方
/// 那几把一起带跑偏,而用户根本不知道是哪把在打哪儿。这里只剩基址本身的
/// 常量与判定。
library;

/// NAI 官方直连基址。`/ai/*` 与 `/user/*` 现在同在 image 子域
/// (2026-07-04 起,旧 api.novelai.net 回 400 "Please refresh NovelAI.net")。
const kNaiOfficialBase = 'https://image.novelai.net';

/// 官方基址的代理替身:Plana 的 Cloudflare Worker,网页端 API 模式走的同一台。
/// 开关见 `naiProxyProvider`。
///
/// Worker 按路径前缀分流,`/image/*` 去掉前缀原样转给 image.novelai.net ——
/// 所以它能整个顶替 [kNaiOfficialBase],`/ai/*`、`/user/*` 的拼法一个字不用改。
///
/// **`/image` 不能省**:不带前缀时 Worker 转的是 api 子域(只有
/// `/user/subscription` 被单独指去了 image),`/user/login` 就打错了地方。
/// 2026-09-16 用空体 POST 对拍过:带前缀回 image 那套校验文案,不带回 api 那套。
const kNaiProxyBase = 'https://novelai.sora214.top/image';

/// 旧的**全局**接口地址设置键。只剩迁移用:首次读取令牌列表时盖到还没有地址
/// 的 Key 上,盖完清掉(见 `NaiKeysNotifier._adoptLegacyEndpoint`)。
const kLegacyNaiEndpointKey = 'nai_endpoint_base';

/// 实际生效的基址:自定义地址优先;为空(官方)时开了 [proxy] 就换代理。
///
/// [proxy] 只管官方那几把:第三方的 key 只在它自己那台机器上有效,Worker 却只会
/// 转给官方,绕过去等于换了一台不认这把 key 的机器。
String naiBaseOf(String custom, {bool proxy = false}) =>
    custom.isNotEmpty ? custom : (proxy ? kNaiProxyBase : kNaiOfficialBase);

/// 基址归一:trim + 去尾斜杠;填成官方地址本身归一到空串 —— 不然界面上会多出
/// 一条「第三方」而它跟官方一模一样。
String normalizeNaiBase(String url) {
  var u = url.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u == kNaiOfficialBase ? '' : u;
}

/// 能不能当基址用:必须是带 http(s) 协议、有主机名、且不带查询串的 URL。
///
/// 只挡明显填错的(漏协议、把整条 `…/ai/generate-image` 贴进来带了参数)。
/// 对面通不通、是不是真的 NAI 兼容接口,这里验不出来,交给下一次请求报错 ——
/// 这里替用户探一次的话,自建反代多半没开 GET,探测失败反而拦住能用的地址。
bool naiBaseLooksValid(String url) {
  final u = Uri.tryParse(url);
  return u != null &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty &&
      !u.hasQuery;
}

/// 界面上认地址用的主机名;空串(官方)也回空串。整条 URL 摆进列表行里
/// 只会把名字挤没,主机名才是「这把打哪儿」的答案。
String naiBaseHost(String base) =>
    base.isEmpty ? '' : (Uri.tryParse(base)?.host ?? base);

/// 第三方接口的请求格式,添加时选。
enum NaiApiFormat {
  /// NovelAI 官方格式:`/ai/generate-image(-stream)`。
  nai('NovelAI 格式', 'NovelAI 接口格式：/ai/generate-image'),

  /// OpenAI 兼容:`/v1/chat/completions`,见 `nai_chat_compat.dart`。
  openai('OpenAI 格式', 'OpenAI 接口格式：/v1/chat/completions');

  const NaiApiFormat(this.label, this.hint);

  final String label;
  final String hint;
}

const _chatPath = '/chat/completions';

/// OpenAI 兼容的接口存整条 `…/chat/completions` 地址,格式按路径认。
bool naiEndpointIsChat(String endpoint) => endpoint.endsWith(_chatPath);

/// 添加时填的地址 + 选的格式 → 存下的地址(已归一)。OpenAI 格式补全到
/// `…/v1/chat/completions`:填根域名、带 `/v1`、整条贴进来都行。
String naiEndpointFor(String url, NaiApiFormat format) {
  final base = normalizeNaiBase(url);
  if (format == NaiApiFormat.nai || base.isEmpty || naiEndpointIsChat(base)) {
    return base;
  }
  return base.endsWith('/v1') ? '$base$_chatPath' : '$base/v1$_chatPath';
}

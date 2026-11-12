import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/net/backend_config.dart';
import '../../../core/net/backend_http.dart';
import '../../../core/store/app_stores.dart';
import 'suggestions.dart';
import 'trans_cache_store.dart';

/// 注音层的后端翻译通道。
///
/// **一次请求搞定**:`POST /api/tags/translate`,服务端内部依次走共享映射库 →
/// 进程内 LLM 缓存 → 上游 LLM。2026-08-28 之前 app 要自己打两次(先
/// `/api/tags/translations/lookup` 查库,未命中的再打 `/api/translate/en2zh`),
/// 而后者是个收任意 `messages` 的**通用 chat 代理** —— 提示词握在客户端手里,
/// 等于对外开了个免费 LLM。现在提示词收进服务端,这个端点只收 tag 数组、只回
/// 译名映射。旧的两个没下线(已发布的 APK 会一直打它们),但已收紧成模板路由。
///
/// 归一化也一并交给服务端了:剥 NAI 权重(`{{x}}`/`1.5::x::`/`x:1.2`)、大小写、
/// 连续空白。所以响应的键**就是我们传进去的原文**,不用再做一层映射。
///
/// LLM 译文**不回写**公共映射库(服务端 2026-08-25 起也不再收 `ai` 源):那张库
/// 攒到 24.2 万条时有 19.7 万条是 AI 回写的,抽样核实 94.6% 的 key 连
/// danbooru.tsv 都不认识 —— 全是被当成 tag 提交的整段提示词碎片。译文照常显示、
/// 照常进本地反查缓存,并存进本机([TransCacheStore]),下次开机不用再问。
///
/// 命中回填 [cacheTagMeta](transCacheRev 随之自增)后 notifyListeners,编辑器
/// 刷新注音层/词条栏。enabled=false 时全程 no-op。
class TagTranslationService extends ChangeNotifier {
  TagTranslationService({
    required this.enabled,
    required this.baseUrl,
    this.saved,
    http.Client? client,
  }) : _client = client ?? backendHttpClient();

  final bool enabled;
  final String baseUrl;

  /// 翻出来的译名存一份到本机;null = 不存(测试)。
  final TransCacheStore? saved;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  /// 一次请求里的 tag 数。服务端上限是 200,但它对未命中的部分**按 20 分块、
  /// 串行**打 LLM —— 发 60 个就是三次串行调用,轻松吃掉这边 20 秒的超时。
  /// 保持 20 = 服务端最多一次 LLM,延迟可控。
  static const _batchMax = 20;

  final _pending = <String>{}; // 待查(小写、空格形式)
  final _asked = <String>{}; // 已有定论(含 LLM 也答不出的),本进程不再问
  Timer? _timer;
  bool _busy = false;
  DateTime? _cooldownUntil; // 撞限流(429)后的退避窗口

  /// 上一次问后端没问成(连不上 / 出错 / 限流)。这期间不画加载态,后台照常重试,
  /// 问成一次就恢复。
  bool _failing = false;

  /// 单个名字的长度上限。
  ///
  /// 原来是 60 —— 那是按 Danbooru tag 的尺度定的,而 Krea 2 的提示词**整条都是
  /// 自然语言句子**,一句轻松过百,于是整条都不翻译,恰恰是最需要翻译的那种。
  /// 200 够装一个长句;再长多半是整段粘进来的,翻出来也只是一行省略号
  /// (注音层单行绘制,见 annotated_field 的 _FuriganaPainter)。
  /// 服务端 en2zh 的体积上限是整批 32000 字符,20×200 远在其下。
  static const _nameMax = 200;

  /// 值得问后端的名字:含英文字母(纯中文/数字/符号跳过)、非画师前缀、长度合理。
  static bool _worthAsking(String name) {
    if (name.isEmpty || name.length > _nameMax) return false;
    if (name.contains('artist:')) return false;
    return name.codeUnits.any(
      (c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A),
    );
  }

  /// 这个名字还在等译文:排队中或正在问。
  /// 芯片流据此画加载态 —— 后端没问成时恒 false([_failing]),后台重试着,
  /// 挂着加载动画等于骗人;`_asked` 里的也算有定论(含 LLM 答不出的),
  /// 不能一直转下去。
  bool isPending(String name) {
    if (!enabled || baseUrl.isEmpty || _failing) return false;
    final k = metaKey(name); // 与反查缓存同一套键,见 [metaKey]
    if (!_worthAsking(k) || _asked.contains(k)) return false;
    return translationOf(k) == null;
  }

  /// 编辑器解析后把注音未命中的名字塞进来;防抖攒批后查询。
  void request(Iterable<String> names) {
    if (!enabled || baseUrl.isEmpty) return;
    var added = false;
    for (final n in names) {
      final k = metaKey(n); // 同上:下划线/连续空白归一,否则同一个词会问两遍
      if (!_worthAsking(k) || _asked.contains(k)) continue;
      if (translationOf(k) != null) continue; // 本地缓存/词库已有
      added |= _pending.add(k);
    }
    if (added && !_busy) _arm(const Duration(milliseconds: 700));
  }

  void _arm(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _flush);
  }

  Future<void> _flush() async {
    if (_busy || _pending.isEmpty) return;
    _busy = true;
    final askedBefore = _asked.length;
    try {
      final batch = _pending.take(_batchMax).toList();
      _pending.removeAll(batch);
      // 入队时查过一次本地缓存还不够:防抖这 700ms 里补全那一路可能刚好回填了
      // 同一批词。不在这里再滤一道,它们就会白跑一趟 lookup,未命中还要接着落到
      // LLM 那步。
      batch.removeWhere((t) => translationOf(t) != null);
      if (batch.isEmpty) return;
      final cool = _cooldownUntil;
      if (cool != null && DateTime.now().isBefore(cool)) {
        _pending.addAll(batch);
        _arm(cool.difference(DateTime.now()) + const Duration(seconds: 1));
        return;
      }

      final res = await _translate(batch);
      if (res == null) {
        // 网络失败 / 非 200:整批放回稍后再试。撞限流时 [_translate] 已经把
        // [_cooldownUntil] 设好,上面那道会拦住下一次。加载态收掉。
        _pending.addAll(batch);
        _arm(const Duration(seconds: 30));
        if (!_failing) {
          _failing = true;
          notifyListeners();
        }
        return;
      }
      final recovered = _failing;
      _failing = false;

      var gotAny = false;
      res.hits.forEach((name, zh) {
        cacheTagMeta(name, trans: zh); // 只进本地反查缓存,不回写公共库
        saved?.put(name, zh);
        _asked.add(name);
        gotAny = true;
      });
      // 服务端明说「查过、确实没有」的(含被它的 LLM 闸门挡掉的画师名、纯中文、
      // 提示词碎片)。这些也算有定论 —— 不记进 `_asked`,芯片流的加载态会一直转。
      _asked.addAll(res.missing);

      // 有定论就通知,**不只看翻出了什么**:一个都没翻出来时 `_asked` 照样长了,
      // 芯片流的加载态得据此收掉 —— 只在 gotAny 时通知的话,那些「问过但没答案」
      // 的 chip 会一直转到下一次无关重绘。
      if (gotAny || recovered || _asked.length != askedBefore) {
        notifyListeners();
      }
    } finally {
      _busy = false;
      if (_pending.isNotEmpty && (_timer == null || !_timer!.isActive)) {
        _arm(const Duration(milliseconds: 400));
      }
    }
  }

  /// 一次请求要到译名。失败(网络 / 非 200)返回 null;撞 429 时顺手把
  /// [_cooldownUntil] 设成 90 秒后,由 [_flush] 那道闸拦住后续请求。
  ///
  /// 响应的键就是传进去的原文——归一化在服务端(见类文档),这边不用再映射一层。
  Future<({Map<String, String> hits, List<String> missing})?> _translate(
    List<String> tags,
  ) async {
    try {
      final r = await _client
          .post(
            Uri.parse('$baseUrl/api/tags/translate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tags': tags}),
          )
          .timeout(_timeout);
      if (r.statusCode == 429) {
        _cooldownUntil = DateTime.now().add(const Duration(seconds: 90));
        return null;
      }
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return null;
      final tr = j['translations'];
      final ms = j['missing'];
      return (
        hits: <String, String>{
          if (tr is Map)
            for (final e in tr.entries)
              if (e.value is String && (e.value as String).isNotEmpty)
                '${e.key}': e.value as String,
        },
        missing: <String>[
          if (ms is List)
            for (final x in ms)
              if (x is String) x,
        ],
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}

/// 按后端基址构造;基址变化即重建(与 tagCompletionProvider 同款)。
/// 不需要 bot 会话 —— 端点是公开的,回写那一步已取消(见类文档)。
final tagTranslationServiceProvider = Provider<TagTranslationService>((ref) {
  final base = ref.watch(backendBaseProvider).value ?? '';
  final s = TagTranslationService(
    enabled: true,
    baseUrl: base,
    saved: ref.watch(appStoresProvider).transCache,
  );
  ref.onDispose(s.dispose);
  return s;
});

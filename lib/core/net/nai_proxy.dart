import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/app_stores.dart';
import '../../l10n/l10n.dart';

/// 官方接口走不走代理(`kNaiProxyBase`)。本机设置,默认关。
///
/// 全局一份,不像接口地址那样跟着每把 Key 走:它回答的是「这台手机够不够得着
/// NovelAI」,跟用哪个号无关。第三方的 key 不受它影响,见 `naiBaseOf`。
///
/// 管的是整条官方直连线:生成、超分、Vibe 编码、查点数、邮箱登录与续期。
///
/// **同步取值**:PrefsStore 启动时已整份读进内存。做成异步的话冷启动首读那一拍
/// 是 null,开着代理也会先直连打一趟查点数 —— 连不上的人正好撞上。
final naiProxyProvider = NotifierProvider<NaiProxyNotifier, bool>(
  NaiProxyNotifier.new,
);

/// 开关底下那行小字。账号页与引导页共用,两处说法不会各写各的。
String get kNaiProxyHint => l10nNow.naiProxyHint;

const _key = 'nai_proxy';

class NaiProxyNotifier extends Notifier<bool> {
  @override
  bool build() {
    try {
      return ref.read(prefsStoreProvider).get(_key) == '1';
    } catch (_) {
      return false; // 无 AppStores(测试)
    }
  }

  void set(bool on) {
    if (on == state) return;
    state = on;
    try {
      // 关 = 删键:默认就是关,设置文件里不留一条 '0'。
      ref.read(prefsStoreProvider).write(key: _key, value: on ? '1' : null);
    } catch (_) {} // 写失败只影响下次启动
  }
}

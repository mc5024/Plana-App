/// 对话模式:无、漫画模式、仅自然语言。输入框上方那个「模式」按钮,点开选。
/// 「纯文本格式」不是模式,是助手设置里的开关(见 `AssistantSettings.noDraw`),和哪个模式都能叠。
///
/// 模式的说明写在预设里,是带 `when: "mode:<名>"` 的段(默认规则 Nyako 里的
/// mode_comic、natural_construction / mode_natural);app 负责把选了哪个发出去:
///   · 走服务端:请求带上模式名,服务端并进本轮的条件段筛选
///   · 走自定义接口:在 app 里按同一条规则挑段([renderRules])
/// 在用的预设没写那一段,这个模式就开不了 —— 开了也只是什么都没发出去。
///
/// 模式**跟着对话走**:记在每条用户消息上([AssistantMsg.mode]),开新对话回到「无」,
/// 打开一段历史就回到它最后用的那个。漫画是一段对话从头做到尾的事,换个对话再画
/// 单张,不该还挂着漫画。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_config.dart';
import 'preset_rules.dart';
import '../../l10n/l10n.dart';

/// 顺序就是弹层里的顺序。`normal` 就是「无」:什么都不加。
enum AssistantMode { normal, comic, natural }

String assistantModeLabel(AssistantMode m) => switch (m) {
  AssistantMode.normal => l10nNow.modeNone,
  AssistantMode.comic => l10nNow.modeComic,
  AssistantMode.natural => l10nNow.modeNatural,
};

/// 预设里对应那一段的 when。「无」没有段。
String? assistantModeWhen(AssistantMode m) => switch (m) {
  AssistantMode.comic => '${kModeWhenPrefix}comic',
  AssistantMode.natural => '${kModeWhenPrefix}natural',
  AssistantMode.normal => null,
};

/// 这一轮要发出去、拿来挑段的模式名。
///
/// 漫画连 `comic` 一起带:漫画的字段规则(comic_composition)挂在 `comic` 上,平时由
/// 服务端按关键词自动判;手动选了漫画,就不必等「四格」「分镜」这些词出现。
List<String> assistantModeKeys(AssistantMode m) => switch (m) {
  AssistantMode.comic => const ['comic', '${kModeWhenPrefix}comic'],
  AssistantMode.natural => const ['${kModeWhenPrefix}natural'],
  AssistantMode.normal => const [],
};

/// 这个模式是不是非得预设里写了对应的段才成立。
bool modeNeedsPresetSection(AssistantMode m) =>
    m == AssistantMode.comic || m == AssistantMode.natural;

/// 这份规则能选哪几个模式。
Set<AssistantMode> supportedModes(List<PresetRule> rules) {
  final whens = {for (final r in rules) r.when};
  return {
    for (final m in AssistantMode.values)
      if (!modeNeedsPresetSection(m) || whens.contains(assistantModeWhen(m))) m,
  };
}

/// 这个模型现在在用的预设能选哪几个模式。界面和发消息都认这一份,两边不会各说各的。
///
/// 还没取到时界面先不拦。默认规则取不到服务端那份会回落包里内置的,不至于一直没有。
///
/// ⚠ 默认规则取回来之后**一直用那一份**([defaultRulesProvider] 不会自己过期)。
/// 后端改了预设、重启之后,这里还是旧的 —— 所以要说「不支持」之前,先用
/// [refreshAssistantModes] 拿最新的核一遍。
final assistantModesProvider =
    FutureProvider.family<Set<AssistantMode>, RulesFamily>((ref, f) async {
      final lib = await ref.watch(rulesLibraryProvider.future);
      final rules =
          lib.customRulesFor(f) ??
          (await ref.watch(defaultRulesProvider(f).future)).rules;
      return supportedModes(rules);
    });

/// 重新向服务端要一份默认规则,再算一遍能选哪几个模式;[assistantModesProvider] 跟着更新。
///
/// 在用的是导入的预设就不必取:那份存在本机,没有新旧之分。取不到最新的(网络抖了)
/// 就还是手上那份。
Future<Set<AssistantMode>> refreshAssistantModes(
  WidgetRef ref,
  RulesFamily f,
) async {
  final custom = (await ref.read(
    rulesLibraryProvider.future,
  )).customRulesFor(f);
  if (custom != null) return supportedModes(custom);
  final base = ref.read(backendBaseProvider).value ?? '';
  final sid = (await ref.read(botSessionProvider.future))?.sessionId ?? '';
  final latest = await fetchDefaultRules(
    f,
    backendBase: base,
    sessionId: sid,
    fresh: true,
  );
  // 取回来的已经进了 fetchDefaultRules 的缓存,重建时读到的就是这份
  ref.invalidate(defaultRulesProvider(f));
  return supportedModes(latest.rules);
}

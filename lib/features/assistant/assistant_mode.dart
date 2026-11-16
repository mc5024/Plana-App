/// 对话模式:无、漫画模式、仅自然语言。输入框上方那个「模式」按钮,点开选。
/// 「纯文本格式」不是模式,是助手设置里的开关(见 `AssistantSettings.noDraw`),和哪个模式都能叠。
///
/// 模式的说明写在预设里,是带 `when: "mode:<名>"` 的段(默认规则 Nyako 里的
/// mode_comic、natural_construction / mode_natural)。只有用户在这里选了才发对应的段,
/// 不按聊天内容自动判。在用的预设没写那一段,这个模式就开不了。
///
/// 模式**跟着对话走**:记在每条用户消息上([AssistantMsg.mode]),开新对话回到「无」,
/// 打开一段历史就回到它最后用的那个。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import 'presets/default_rules.dart';
import 'presets/preset_rule.dart';
import 'presets/rules_library.dart';

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

/// 这一轮拿来挑段的模式名。
///
/// 漫画连 `comic` 一起带:漫画的字段规则(comic_composition)挂在 `comic` 上。
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
  final whens = {
    for (final r in rules)
      if (r.enabled) r.when,
  };
  return {
    for (final m in AssistantMode.values)
      if (!modeNeedsPresetSection(m) || whens.contains(assistantModeWhen(m))) m,
  };
}

/// 这个模型现在在用的预设能选哪几个模式。界面和发消息都认这一份。
final assistantModesProvider =
    FutureProvider.family<Set<AssistantMode>, RulesFamily>((ref, f) async {
      final lib = await ref.watch(rulesLibraryProvider.future);
      final rules =
          lib.customRulesFor(f) ??
          (await ref.watch(defaultRulesProvider(f).future)).rules;
      return supportedModes(rules);
    });

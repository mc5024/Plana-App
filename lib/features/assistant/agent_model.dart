/// AI 助手用哪个 LLM 渠道。
///
/// 候选来自后端 `GET /api/agent/models`(即 `server/config.py` 的 `MODEL_CHOICES`),
/// **不在 app 里写死** —— 那张表上线下线很频繁(半年里 kimi、mimo、minimax 三个
/// 来了又走),写死就得跟着发版,而且发完老版本还在选一个已经不存在的渠道。
///
/// 选中的只存 key,发请求时原样带上。key 过期(渠道被下架)也不用特判:后端
/// `_normalize_model_key` 认不出就回落全局默认,最坏结果是「换了个模型答」,
/// 不会报错。
///
/// **没有 Bot 授权时只列后端 `free_choices` 那张表**(免费模型),再加自定义接口
/// (见 [assistantBotAuthorizedProvider])。后端一条都没有就只剩自定义接口。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/store/app_stores.dart';
import '../../core/store/prefs_store.dart';
import 'custom_endpoint.dart';
import 'image_gen/image_models.dart' show assistantImageModelProvider;
import 'llm/http_provider.dart' show llmProviderFor;
import 'llm/llm_provider.dart' show LlmCapabilities;
import 'llm/plana_channel_provider.dart' show kChannelCapabilities;

/// label 里括号那段(线路/渠道说明)。中英文括号都收。
final _paren = RegExp(r'[（(].*?[)）]');

class AgentModelChoice {
  const AgentModelChoice({
    required this.key,
    required this.name,
    this.recommended = false,
    this.free = false,
  });

  /// 发给后端的 `model`(MODEL_CHOICES 的 key)。
  final String key;

  /// 完整型号名,如 `GLM 5.3 Flash`。界面上一律显示这个,不显示 key,
  /// 也不显示 `short_label` —— 「GLM」「豆包」这种简称看不出是哪一代。
  final String name;

  /// 后端标了推荐:列表里挂角标并排在前面。纯展示,别的照常能选。
  final bool recommended;

  /// 后端标了免费:没有 Bot 授权也能用。
  final bool free;
}

class AgentModelList {
  const AgentModelList({
    this.choices = const [],
    this.active = '',
    this.freeChoices,
  });

  /// 已按「推荐在前」排好,同档保持后端给的顺序。
  final List<AgentModelChoice> choices;

  /// 后端当前的全局默认。用户没自己选过时就显示它。
  final String active;

  /// 后端 `free_choices`,排法同 [choices]。同一个 key 免费和授权可能是两个型号
  /// (gemini 授权走 4 Argon、免费走 3.8 Flash),也可能只在这张表里(haiku55),
  /// 所以没授权时名字和候选都得从这里取。老后端没这个字段时为 null。
  final List<AgentModelChoice>? freeChoices;

  AgentModelChoice? byKey(String key) {
    for (final c in choices) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// 没有 Bot 授权时能选的。老后端没给 `free_choices` 就退回 [choices] 里标了 free 的。
  List<AgentModelChoice> get free =>
      freeChoices ??
      [
        for (final c in choices)
          if (c.free) c,
      ];

  /// 该用哪一条:选过的 [pinned] 能用就是它,否则后端默认。
  ///
  /// 没授权时只在免费的里挑,默认那条不免费就取第一条免费的(推荐在前);
  /// 一条免费的都没有就是 null。
  AgentModelChoice? pick(String pinned, {required bool authorized}) {
    final pool = authorized ? choices : free;
    for (final k in [pinned, active]) {
      for (final c in pool) {
        if (c.key == k) return c;
      }
    }
    return authorized ? null : pool.firstOrNull;
  }
}

/// 一条 choice 的完整型号名。
///
/// 与 bot 端 `core/nai_agent._agent_model_display_name` 同一套规则:优先 `name`,
/// 没有就把 `label` 的括号说明去掉,再没有就退回 key。**规则要跟着那边走** ——
/// 同一个渠道在 bot 里叫一个名、在 app 里叫另一个名,用户会以为是两个模型。
String modelDisplayName(String key, Map<String, dynamic> choice) {
  final name = choice['name']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  final label = choice['label']?.toString() ?? '';
  final cleaned = label.replaceAll(_paren, '').trim();
  return cleaned.isNotEmpty ? cleaned : key;
}

/// `GET /api/agent/models` 的响应 → 选项列表。
///
/// 后端那张表是给 bot 和 web 一起用的,字段比 app 需要的多(别名、registry key、
/// 预设变体),这里只挑四样。缺字段一律 fail-soft:少一条选项好过整页打不开。
AgentModelList parseAgentModels(Map<String, dynamic> j) {
  final raw = j['choices'];
  if (raw is! Map) return const AgentModelList();
  final freeRaw = j['free_choices'];
  return AgentModelList(
    choices: _parseChoices(raw),
    active: j['active']?.toString() ?? '',
    freeChoices: freeRaw is Map ? _parseChoices(freeRaw, free: true) : null,
  );
}

/// 一张 choice 表 → 选项列表。[free] 为 true 时整张表都算免费(`free_choices` 不带标记)。
List<AgentModelChoice> _parseChoices(Map raw, {bool free = false}) {
  final out = <AgentModelChoice>[];
  raw.forEach((k, v) {
    final key = k.toString();
    if (key.isEmpty || v is! Map) return;
    final choice = v.cast<String, dynamic>();
    out.add(
      AgentModelChoice(
        key: key,
        name: modelDisplayName(key, choice),
        recommended: choice['recommended'] == true,
        free: free || choice['free'] == true,
      ),
    );
  });
  // 稳定排序:推荐的提到前面,同档保持后端顺序(那个顺序本身有含义 ——
  // 第一条通常就是 ACTIVE_MODEL)。
  final recommended = [
    for (final c in out)
      if (c.recommended) c,
  ];
  final rest = [
    for (final c in out)
      if (!c.recommended) c,
  ];
  return [...recommended, ...rest];
}

/// 可选渠道。后端基址变了自动重取(provider 依赖 client)。
final agentModelsProvider = FutureProvider<AgentModelList>((ref) async {
  final j = await ref.watch(backendClientProvider).agentModels();
  return parseAgentModels(j);
});

/// 选中自定义接口时,存的是这个前缀加接口 id,再加 `/模型`。没带模型的(旧存档)按
/// 那个接口的第一个模型算。接口 id 里没有 `/`,模型名里可能有(`openai/gpt-4o`)。
///
/// 与后端渠道共用一个偏好键:两者是**互斥的一次选择**,分两个键存就会出现
/// 「都选着」这种表达不出来的状态,界面还得再判一次谁优先。
const kCustomKeyPrefix = 'custom:';

String customModelKey(String endpointId, [String model = '']) =>
    '$kCustomKeyPrefix$endpointId${model.isEmpty ? '' : '/$model'}';

/// 选中图像模型时存这个前缀加图像模型的 key(见 `image_gen/image_models.dart`)。
/// 同一个偏好键:选了图像模型就不走对话模型,发的话直接交给它出图。
const kImageKeyPrefix = 'image:';

/// 选中的是不是图像模型;是就给出图像模型的 key。
String? imageChoiceKeyOf(String key) => key.startsWith(kImageKeyPrefix)
    ? key.substring(kImageKeyPrefix.length)
    : null;

/// 选中的是不是自定义接口;是就给出接口 id。
String? customEndpointIdOf(String key) {
  if (!key.startsWith(kCustomKeyPrefix)) return null;
  final rest = key.substring(kCustomKeyPrefix.length);
  final i = rest.indexOf('/');
  return i < 0 ? rest : rest.substring(0, i);
}

/// 自定义接口这一条选的模型;没带模型或不是自定义接口为 null。
String? customModelOf(String key) {
  if (!key.startsWith(kCustomKeyPrefix)) return null;
  final rest = key.substring(kCustomKeyPrefix.length);
  final i = rest.indexOf('/');
  return i < 0 ? null : rest.substring(i + 1);
}

/// [key] 落在 [e] 上就给出用哪个模型发的那份,模型不在了的按第一个算;不是它为 null。
CustomEndpoint? resolveCustomChoice(CustomEndpoint e, String key) {
  if (customEndpointIdOf(key) != e.id) return null;
  final m = customModelOf(key);
  return m != null && e.allModels.contains(m) ? e.forModel(m) : e;
}

const _key = 'assistant_model';

/// 用户**自己选过**的渠道 key;空串 = 没选过,跟着后端默认走。
///
/// 不把后端默认写进偏好:那样后端换了默认,没主动选过的用户会被钉在旧渠道上,
/// 而且他从来不知道自己「选过」。
final assistantModelPrefProvider =
    AsyncNotifierProvider<AssistantModelPrefNotifier, String>(
      AssistantModelPrefNotifier.new,
    );

class AssistantModelPrefNotifier extends AsyncNotifier<String> {
  PrefsStore get _storage => ref.read(prefsStoreProvider);

  @override
  Future<String> build() async {
    try {
      return await _storage.read(key: _key) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> set(String key) async {
    state = AsyncData(key);
    try {
      await _storage.write(key: _key, value: key);
    } catch (_) {
      // 存不下只影响下次冷启动,这一程照常按新选择走
    }
  }
}

/// 这一轮实际要发的 `model`。没选过就发空串,让后端用它的全局默认。
/// 选的是自定义接口时后端渠道用不上,发空串即可(那条根本不打后端出词)。
///
/// 没有 Bot 授权时发界面上显示的那条免费模型,不发空串:后端的全局默认未必免费。
final assistantModelKeyProvider = Provider<String>((ref) {
  final k = ref.watch(assistantModelPrefProvider).value ?? '';
  bool backend(String key) =>
      customEndpointIdOf(key) == null && imageChoiceKeyOf(key) == null;
  if (ref.watch(assistantBotAuthorizedProvider)) return backend(k) ? k : '';
  final shown = ref.watch(assistantModelProvider);
  return shown == null || !backend(shown.key) ? '' : shown.key;
});

/// 有没有 Bot 授权。没有也能用助手,但只能用免费模型和自定义接口,资料只给本地库;
/// 预设照常从后端取。
final assistantBotAuthorizedProvider = Provider<bool>(
  (ref) => ref.watch(botSessionProvider).value != null,
);

/// 能不能走 Plana 后端:有 Bot 授权,或者后端下放了免费模型。
/// 列表还没到货时没授权的按不能算。
final assistantBackendAvailableProvider = Provider<bool>((ref) {
  if (ref.watch(assistantBotAuthorizedProvider)) return true;
  return ref.watch(agentModelsProvider).value?.free.isNotEmpty ?? false;
});

/// 界面上该显示哪一条。选过就是选的那条;没选过显示后端默认那条;
/// 列表还没到货(或拿不到)就是 null,界面按「未知」显示。
/// 没有 Bot 授权时只认免费的(见 [AgentModelList.pick]),选着的那条不免费也不改存档,
/// 授权回来就还是它。
final assistantModelProvider = Provider<AgentModelChoice?>((ref) {
  final pinned = ref.watch(assistantModelPrefProvider).value ?? '';
  // 图像模型用不了(授权没了、接口删了)时回落到对话模型那边照常显示
  if (ref.watch(assistantImageModelProvider) case final m?) {
    return AgentModelChoice(key: pinned, name: m.name);
  }
  // 自定义接口不在后端那张表里,名字从本机的接口列表取
  if (customEndpointIdOf(pinned) != null) {
    for (final e in ref.watch(customEndpointsProvider).value ?? const []) {
      if (resolveCustomChoice(e, pinned) case final r?) {
        return AgentModelChoice(
          key: customModelKey(r.id, r.model),
          name: r.model.isEmpty ? r.displayName : r.model,
        );
      }
    }
  }
  return ref
      .watch(agentModelsProvider)
      .value
      ?.pick(pinned, authorized: ref.watch(assistantBotAuthorizedProvider));
});

/// 这一轮该走哪条路:非 null = 直连这个自定义接口,null = 走 Plana 后端。
final assistantEndpointProvider = Provider<CustomEndpoint?>((ref) {
  final key = ref.watch(assistantModelPrefProvider).value ?? '';
  if (customEndpointIdOf(key) == null) return null;
  for (final e in ref.watch(customEndpointsProvider).value ?? const []) {
    // 填不全的不算数:发出去必然失败,不如当没选,回落后端那条
    if (resolveCustomChoice(e, key) case final r? when r.usable) return r;
  }
  return null;
});

/// 当前选的模型支持什么。界面据此置灰思考等级、逐字显示。
final assistantCapabilitiesProvider = Provider<LlmCapabilities>((ref) {
  final e = ref.watch(assistantEndpointProvider);
  return e == null ? kChannelCapabilities : llmProviderFor(e).capabilities;
});

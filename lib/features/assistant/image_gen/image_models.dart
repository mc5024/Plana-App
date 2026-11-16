/// 「生成图片」能用的出图模型:后端渠道(免费额度,要 Bot 授权)在前,各接口里填的
/// 出图模型在后。后端那张表由服务端下发,不在 App 里写死。
///
/// 不在设置里选:每个模型带几个触发词,用户原话里提到哪个就用哪个([matchImageModel])。
/// 一轮用的哪个记在 AI 消息上,存 key:后端渠道 `plana:<渠道>`,接口沿用对话模型那套
/// `custom:<接口 id>/<模型>`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/bot_session_store.dart';
import '../../../core/net/backend_client.dart';
import '../agent_model.dart' show customModelKey;
import '../custom_endpoint.dart';

const kPlanaImagePrefix = 'plana:';

class ImageModelChoice {
  const ImageModelChoice({
    required this.key,
    required this.name,
    required this.model,
    required this.triggers,
    this.endpoint,
    this.available = true,
  });

  final String key;
  final String name;

  /// 后端渠道 key / 接口里的模型 id。
  final String model;

  /// 用户原话里出现(不分大小写)就用这个模型。
  final List<String> triggers;

  /// 走哪个接口;null = 后端渠道。
  final CustomEndpoint? endpoint;

  /// 后端渠道没有 Bot 授权时为 false。
  final bool available;
}

typedef PlanaImageChannel = ({String key, String name, List<String> triggers});

/// `GET /api/agent/image/channels` 的响应。
typedef PlanaImageChannels = ({
  List<PlanaImageChannel> channels,
  bool authorized,
});

PlanaImageChannels parsePlanaImageChannels(Map<String, dynamic> j) => (
  channels: [
    for (final c in (j['channels'] as List? ?? const []))
      if (c is Map && '${c['key'] ?? ''}'.isNotEmpty)
        (
          key: '${c['key']}',
          name: '${c['name'] ?? c['key']}',
          triggers: [
            for (final t in (c['triggers'] as List? ?? [c['name'] ?? c['key']]))
              if ('$t'.trim().isNotEmpty) '$t'.trim(),
          ],
        ),
  ],
  authorized: j['authorized'] == true,
);

/// 后端渠道。拿不到(没配后端、老后端没这个接口)就是空表。
final planaImageChannelsProvider = FutureProvider<PlanaImageChannels>((
  ref,
) async {
  final sid = (await ref.watch(botSessionProvider.future))?.sessionId ?? '';
  try {
    return parsePlanaImageChannels(
      await ref.watch(backendClientProvider).agentImageChannels(sid),
    );
  } catch (_) {
    return (channels: const <PlanaImageChannel>[], authorized: false);
  }
});

List<ImageModelChoice> imageModelChoices(
  PlanaImageChannels? plana,
  List<CustomEndpoint> endpoints,
) => [
  for (final c in plana?.channels ?? const <PlanaImageChannel>[])
    ImageModelChoice(
      key: '$kPlanaImagePrefix${c.key}',
      name: c.name,
      model: c.key,
      triggers: c.triggers,
      available: plana!.authorized,
    ),
  for (final e in endpoints)
    if (e.canDraw)
      for (final m in e.imageModels)
        ImageModelChoice(
          key: customModelKey(e.id, m),
          name: m,
          model: m,
          triggers: e.triggersOf(m),
          endpoint: e,
        ),
];

/// [text] 里点到的出图模型:能用的里触发词出现得最早的那个,同一处的取更长的触发词。
/// 一个都没点到为 null。
({ImageModelChoice choice, String trigger})? matchImageModel(
  List<ImageModelChoice> all,
  String text,
) {
  final lower = text.toLowerCase();
  ({ImageModelChoice choice, String trigger})? best;
  var bestAt = -1;
  for (final c in all) {
    if (!c.available) continue;
    for (final t in c.triggers) {
      final word = t.trim();
      if (word.isEmpty) continue;
      final at = lower.indexOf(word.toLowerCase());
      if (at < 0) continue;
      if (best == null ||
          at < bestAt ||
          (at == bestAt && word.length > best.trigger.length)) {
        best = (choice: c, trigger: word);
        bestAt = at;
      }
    }
  }
  return best;
}

/// [key] 对应的那个,不在了或用不了为 null。
ImageModelChoice? imageModelOf(List<ImageModelChoice> all, String? key) {
  for (final c in all) {
    if (c.key == key && c.available) return c;
  }
  return null;
}

final imageModelChoicesProvider = Provider<List<ImageModelChoice>>(
  (ref) => imageModelChoices(
    ref.watch(planaImageChannelsProvider).value,
    ref.watch(customEndpointsProvider).value ?? const [],
  ),
);

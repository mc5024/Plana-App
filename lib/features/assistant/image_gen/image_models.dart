/// 「生成图片」能选的出图模型:后端渠道(免费额度,要 Bot 授权)在前,各接口里填的
/// 出图模型在后。后端那张表由服务端下发,不在 App 里写死。
///
/// 选中的存 key:后端渠道 `plana:<渠道>`,接口沿用对话模型那套 `custom:<接口 id>/<模型>`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/bot_session_store.dart';
import '../../../core/net/backend_client.dart';
import '../agent_model.dart'
    show customEndpointIdOf, customModelKey, customModelOf;
import '../custom_endpoint.dart';
import '../tools/tool_settings.dart';

const kPlanaImagePrefix = 'plana:';

class ImageModelChoice {
  const ImageModelChoice({
    required this.key,
    required this.name,
    required this.model,
    this.endpoint,
    this.remaining,
    this.available = true,
  });

  final String key;
  final String name;

  /// 后端渠道 key / 接口里的模型 id。
  final String model;

  /// 走哪个接口;null = 后端渠道。
  final CustomEndpoint? endpoint;

  /// 后端渠道所在额度池的剩余次数;不知道为 null。
  final int? remaining;

  /// 后端渠道没有 Bot 授权时为 false。
  final bool available;
}

/// `GET /api/agent/image/channels` 的响应。
typedef PlanaImageChannels = ({
  List<({String key, String name, int? remaining})> channels,
  bool authorized,
});

PlanaImageChannels parsePlanaImageChannels(Map<String, dynamic> j) => (
  channels: [
    for (final c in (j['channels'] as List? ?? const []))
      if (c is Map && '${c['key'] ?? ''}'.isNotEmpty)
        (
          key: '${c['key']}',
          name: '${c['name'] ?? c['key']}',
          remaining: (c['remaining'] as num?)?.toInt(),
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
    return (
      channels: const <({String key, String name, int? remaining})>[],
      authorized: false,
    );
  }
});

List<ImageModelChoice> imageModelChoices(
  PlanaImageChannels? plana,
  List<CustomEndpoint> endpoints,
) => [
  for (final c in plana?.channels ?? const [])
    ImageModelChoice(
      key: '$kPlanaImagePrefix${c.key}',
      name: c.name,
      model: c.key,
      remaining: c.remaining,
      available: plana!.authorized,
    ),
  for (final e in endpoints)
    if (e.canDraw)
      for (final m in e.imageModels)
        ImageModelChoice(
          key: customModelKey(e.id, m),
          name: m,
          model: m,
          endpoint: e,
        ),
];

/// 选着的那个:[pinned] 在表里且能用就是它,否则第一个能用的;都不能用为 null。
ImageModelChoice? pickImageModel(List<ImageModelChoice> all, String pinned) {
  for (final c in all) {
    if (c.key == pinned && c.available) return c;
  }
  // 接口还在、模型被删了:同一个接口里剩下的第一个
  final id = customEndpointIdOf(pinned);
  if (id != null && customModelOf(pinned) != null) {
    for (final c in all) {
      if (c.endpoint?.id == id) return c;
    }
  }
  for (final c in all) {
    if (c.available) return c;
  }
  return null;
}

final imageModelChoicesProvider = Provider<List<ImageModelChoice>>(
  (ref) => imageModelChoices(
    ref.watch(planaImageChannelsProvider).value,
    ref.watch(customEndpointsProvider).value ?? const [],
  ),
);

/// 生成图片现在用哪个;null = 没有能用的。
final activeImageModelProvider = Provider<ImageModelChoice?>(
  (ref) => pickImageModel(
    ref.watch(imageModelChoicesProvider),
    ref.watch(toolSettingsProvider).value?.imageModel ?? '',
  ),
);

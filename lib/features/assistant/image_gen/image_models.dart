/// 图像模型:选模型弹层里「图像模型」那组。后端渠道(免费额度,要 Bot 授权)在前,各接口里填的
/// 出图模型在后;后端那张表由服务端下发,不在 App 里写死。
///
/// 选中时存在助手模型那个偏好里,值是 `image:` 加这里的 key(见 [kImageKeyPrefix]):
/// 后端渠道 `plana:<渠道>`,接口沿用对话模型那套 `custom:<接口 id>/<模型>`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/bot_session_store.dart';
import '../../../core/net/backend_client.dart';
import '../agent_model.dart';
import '../custom_endpoint.dart';
import '../domain/image_gen.dart';

const kPlanaImagePrefix = 'plana:';

class ImageModelChoice {
  const ImageModelChoice({
    required this.key,
    required this.name,
    required this.model,
    this.endpoint,
    this.available = true,
    this.sizes = const [],
    this.aspects = const [],
    this.health = ModelHealth.unknown,
  });

  final String key;
  final String name;

  /// 后端渠道 key / 接口里的模型 id。
  final String model;

  /// 走哪个接口;null = 后端渠道。
  final CustomEndpoint? endpoint;

  /// 后端渠道没有 Bot 授权时为 false。
  final bool available;

  /// 能选的分辨率档 / 比例;不在里面的按「自动」发。
  final List<String> sizes;
  final List<String> aspects;

  /// 后端渠道的近况;接口里的模型没有,恒为 unknown。
  final ModelHealth health;
}

typedef PlanaImageChannel = ({
  String key,
  String name,
  List<String> sizes,
  List<String> aspects,
  ModelHealth health,
});

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
          // 老后端不报能出哪几档:分辨率按「自动」,比例全给
          sizes: [
            for (final s in (c['sizes'] as List? ?? const []))
              if (kImageSizes.contains('$s')) '$s',
          ],
          aspects: switch (c['aspects']) {
            final List l => [
              for (final a in l)
                if (isImageAspect('$a')) '$a',
            ],
            _ => kImageAspects,
          },
          health:
              ModelHealth.values.asNameMap()[c['health']] ??
              ModelHealth.unknown,
        ),
  ],
  authorized: j['authorized'] == true,
);

/// 后端渠道。拿不到(没配后端、老后端没这个接口)就是空表;重取失败时沿用上一份,不自动重试。
final planaImageChannelsProvider = FutureProvider<PlanaImageChannels>((
  ref,
) async {
  final sid = (await ref.watch(botSessionProvider.future))?.sessionId ?? '';
  return parsePlanaImageChannels(
    await ref.watch(backendClientProvider).agentImageChannels(sid),
  );
}, retry: (_, _) => null);

List<ImageModelChoice> imageModelChoices(
  PlanaImageChannels? plana,
  List<CustomEndpoint> endpoints,
) => [
  for (final c in plana?.channels ?? const <PlanaImageChannel>[])
    ImageModelChoice(
      key: '$kPlanaImagePrefix${c.key}',
      name: c.name,
      model: c.key,
      available: plana!.authorized,
      sizes: c.sizes,
      aspects: c.aspects,
      health: c.health,
    ),
  for (final e in endpoints)
    if (e.canDraw)
      for (final m in e.imageModels)
        ImageModelChoice(
          key: customModelKey(e.id, m),
          name: m,
          model: m,
          endpoint: e,
          // OpenAI 的 Images 接口只有方 / 竖 / 横三档尺寸;Gemini 分辨率、比例都能给
          sizes: e.format == AgentApiFormat.google ? kImageSizes : const [],
          aspects: e.format == AgentApiFormat.google
              ? kImageAspects
              : const ['1:1', '2:3', '3:2'],
        ),
];

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

/// 选着的图像模型;选的不是图像模型、或者它现在用不了为 null。
final assistantImageModelProvider = Provider<ImageModelChoice?>((ref) {
  final key = imageChoiceKeyOf(
    ref.watch(assistantModelPrefProvider).value ?? '',
  );
  return key == null
      ? null
      : imageModelOf(ref.watch(imageModelChoicesProvider), key);
});

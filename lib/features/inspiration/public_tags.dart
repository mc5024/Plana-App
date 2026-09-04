import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import 'artist_models.dart';
import 'tag_models.dart';

/// 公共库列表(角色=OC、画风=画师串),映射为统一 [TagEntry] 供页面渲染。
/// 依赖 bot 会话:未授权抛 [StateError]('need-bot'),UI 据此显示授权提示
/// (范式同 publicVibesProvider)。场景/其他无公共库。
final publicTagsProvider = FutureProvider.family<List<TagEntry>, TagCategory>((
  ref,
  cat,
) async {
  final session = await ref.watch(botSessionProvider.future);
  if (session == null) throw StateError('need-bot');
  final client = ref.read(backendClientProvider);

  switch (cat) {
    case TagCategory.character:
      final ocs = await client.listPublicOcs(session.sessionId);
      return [
        for (final o in ocs)
          TagEntry(
            id: 'pub_${o.enName}',
            category: TagCategory.character,
            name: o.displayName,
            positive: o.tagGroup,
            negative: o.negativePrompt,
            aliases: o.aliases,
            publicId: o.enName,
            previews: [if (o.previewUrl != null) o.previewUrl!],
            createdAt: o.createdAt * 1000,
            // 归属以服务端 owner_id 为准,存量数据回退 created_by(对齐 web)
            createdBy: o.ownerId ?? o.createdBy,
          ),
      ];
    case TagCategory.artist:
      final artists = await client.listPublicArtists(session.sessionId);
      return [
        for (final a in artists)
          TagEntry(
            id: 'pub_${a.id}',
            category: TagCategory.artist,
            name: a.name,
            positive: a.artistString,
            negative: a.negative,
            models: normalizeArtistModels(a.models),
            publicId: a.id,
            previews: [if (a.previewUrl != null) a.previewUrl!],
            createdAt: a.createdTime * 1000,
            createdBy: a.ownerId ?? a.addedBy,
          ),
      ];
    case TagCategory.scene || TagCategory.other:
      return const [];
  }
});

/// 公共库作者目录:归属 id(QQ 号)→ 昵称。灵感页拿它把条目上的 owner_id
/// 显示成人名,也是作者筛选那个输入补全的候选名单来源。
///
/// **取不到就当没有**:未授权、老后端(没这个端点)、网络抖动一律回空表 ——
/// 昵称只是显示增强,缺了照样能按 QQ 号搜和筛,不值得把整页拖进错误态。
final tagAuthorNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final session = await ref.watch(botSessionProvider.future);
  if (session == null) return const {};
  try {
    final authors = await ref
        .read(backendClientProvider)
        .listPublicAuthors(session.sessionId);
    return {
      for (final a in authors)
        if (a.nickname != null && a.nickname!.isNotEmpty) a.id: a.nickname!,
    };
  } catch (_) {
    return const {};
  }
});

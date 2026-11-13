import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'codex_models.dart';
import 'codex_service.dart';
import 'codex_tag_zh.dart';
import '../../../l10n/l10n.dart';

/// 法典接入的 Riverpod 门面:索引/图床/每部数据都是拉一次缓存,
/// 选中法典在会话内记忆,首次说明/翻面示范各自落一个标记。

final codexServiceProvider = Provider<CodexService>((ref) {
  final svc = CodexService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// 图床配置(media.json;失败退常量)。
final codexMediaProvider = FutureProvider<CodexMedia>(
  (ref) => ref.read(codexServiceProvider).fetchMedia(),
);

/// 法典索引(codexes.json)。
final codexIndexProvider = FutureProvider<List<CodexMeta>>(
  (ref) => ref.read(codexServiceProvider).fetchIndex(),
);

/// 一部法典的完整数据(按 id)。依赖索引拿到该部 meta,再拉数据。
final codexDataProvider = FutureProvider.family<CodexData, String>((
  ref,
  id,
) async {
  final index = await ref.watch(codexIndexProvider.future);
  final meta = index.firstWhere(
    (m) => m.id == id,
    orElse: () => throw CodexException(l10nNow.codexNotFound(id)),
  );
  return ref.read(codexServiceProvider).fetchCodex(meta);
});

/// 对照表的缓存戳(见 [codexIndexStamp])。索引出错(含 Riverpod 自动重试中)
/// 直接给 null:对照表这层跳过,芯片退回 app 自己的译名,不陪着索引转圈。
Future<String?> _tagZhStamp(Ref ref) async {
  if (ref.watch(codexIndexProvider).hasError) return null;
  try {
    return codexIndexStamp(await ref.watch(codexIndexProvider.future));
  } catch (_) {
    return null;
  }
}

/// 原站的全站公共对照表(`tag_zh/core.json`)。拉不到 → null。
final codexTagZhCoreProvider = FutureProvider<TagZhShard?>((ref) async {
  final stamp = await _tagZhStamp(ref);
  if (stamp == null) return null;
  return ref.read(codexServiceProvider).fetchTagZh('core', stamp);
});

/// 一部法典查译名用的表(core + 该书分片);null = 对照表不可用。
/// 收藏夹打开单条也走这里:只拉两张译名表,不必把整部法典拉起来。
final codexTagZhProvider = FutureProvider.family<CodexTagZh?, String>((
  ref,
  id,
) async {
  final core = await ref.watch(codexTagZhCoreProvider.future);
  if (core == null) return null;
  if (!core.shards.contains(id)) return CodexTagZh(core);
  final stamp = await _tagZhStamp(ref);
  final shard = stamp == null
      ? null
      : await ref.read(codexServiceProvider).fetchTagZh(id, stamp);
  return CodexTagZh(core, shard);
});

/// 当前选中的法典 id(会话内记忆;为空时 UI 默认取索引首个非 R18)。
final selectedCodexProvider = NotifierProvider<SelectedCodexNotifier, String?>(
  SelectedCodexNotifier.new,
);

class SelectedCodexNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String id) => state = id;
}

/// 首次进入法典功能的说明弹窗:确认一次落盘,之后不再弹。
/// null=尚未读盘(先不弹),false=没读过(可弹),true=已确认(不弹)。
final codexIntroProvider = NotifierProvider<CodexIntro, bool?>(CodexIntro.new);

class CodexIntro extends Notifier<bool?> {
  static const _marker = 'codex_intro_ack';

  @override
  bool? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    try {
      final sup = await getApplicationSupportDirectory();
      state = await File('${sup.path}/$_marker').exists();
    } catch (_) {
      state = false;
    }
  }

  /// 用户点「我知道了」:置位并落盘。
  Future<void> ack() async {
    state = true;
    try {
      final sup = await getApplicationSupportDirectory();
      await File('${sup.path}/$_marker').writeAsString('1');
    } catch (_) {}
  }
}

/// 例图可翻面看提示词 —— 第一次看到例图时自己转一下作示范,只演示这一次。
/// null=尚未读盘(先不演),false=没演过(可演),true=演过了。
final codexFlipHintProvider = NotifierProvider<CodexFlipHint, bool?>(
  CodexFlipHint.new,
);

class CodexFlipHint extends Notifier<bool?> {
  static const _marker = 'codex_flip_hint_ack';

  @override
  bool? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    try {
      final sup = await getApplicationSupportDirectory();
      state = await File('${sup.path}/$_marker').exists();
    } catch (_) {
      state = false;
    }
  }

  /// 演示过一次:置位并落盘。
  Future<void> ack() async {
    state = true;
    try {
      final sup = await getApplicationSupportDirectory();
      await File('${sup.path}/$_marker').writeAsString('1');
    } catch (_) {}
  }
}

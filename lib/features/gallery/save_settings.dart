import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';

/// 保存到相册的元数据处理方式(对齐 web SaveModal)。
enum SaveMeta { original, clean, custom }

enum SaveFormat { png, jpg }

/// 图库的默认保存设置(持久化):点「保存」直接按此存相册,
/// 长按进保存设置面板可单次调整或改默认。
class SaveSettings {
  const SaveSettings({
    this.meta = SaveMeta.original,
    this.format = SaveFormat.png,
    this.quality = 0.92,
    this.customPrompt = '',
    this.recentAlbums = const [],
  });

  final SaveMeta meta;
  final SaveFormat format;

  /// JPG 压缩质量 0.1~1.0。
  final double quality;

  /// meta = custom 时写入的提示词。
  final String customPrompt;

  /// 用过的自定义相册名(最近在前,上限 [maxRecentAlbums])。
  /// 只记名字不记路径 —— 手机相册固定写 `Pictures/<名字>/`。
  final List<String> recentAlbums;

  static const maxRecentAlbums = 8;

  SaveSettings copyWith({
    SaveMeta? meta,
    SaveFormat? format,
    double? quality,
    String? customPrompt,
    List<String>? recentAlbums,
  }) => SaveSettings(
    meta: meta ?? this.meta,
    format: format ?? this.format,
    quality: quality ?? this.quality,
    customPrompt: customPrompt ?? this.customPrompt,
    recentAlbums: recentAlbums ?? this.recentAlbums,
  );

  /// 记一次使用:提到最前、去重、截断。
  SaveSettings withAlbumUsed(String name) => copyWith(
    recentAlbums: [
      name,
      for (final a in recentAlbums)
        if (a != name) a,
    ].take(maxRecentAlbums).toList(),
  );

  factory SaveSettings.fromJson(Map<String, dynamic> j) {
    final q = (j['quality'] as num?)?.toDouble() ?? 0.92;
    return SaveSettings(
      meta: SaveMeta.values.asNameMap()[j['meta']] ?? SaveMeta.original,
      format: SaveFormat.values.asNameMap()[j['format']] ?? SaveFormat.png,
      quality: q.clamp(0.1, 1.0),
      customPrompt: j['customPrompt'] is String
          ? j['customPrompt'] as String
          : '',
      recentAlbums: [
        if (j['recentAlbums'] is List)
          for (final a in j['recentAlbums'] as List)
            if (a is String && a.isNotEmpty) a,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'meta': meta.name,
    'format': format.name,
    'quality': quality,
    'customPrompt': customPrompt,
    if (recentAlbums.isNotEmpty) 'recentAlbums': recentAlbums,
  };

  @override
  bool operator ==(Object other) =>
      other is SaveSettings &&
      other.meta == meta &&
      other.format == format &&
      other.quality == quality &&
      other.customPrompt == customPrompt &&
      _sameList(other.recentAlbums, recentAlbums);

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    meta,
    format,
    quality,
    customPrompt,
    Object.hashAll(recentAlbums),
  );
}

/// 相册名清洗:剔除文件系统/MediaStore 不接受的字符,压空白,限长。
/// 空 = 非法(调用方据此禁用确定按钮)。
String sanitizeAlbumName(String raw) => raw
    .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _key = 'save_settings';

final saveSettingsProvider =
    AsyncNotifierProvider<SaveSettingsNotifier, SaveSettings>(
      SaveSettingsNotifier.new,
    );

class SaveSettingsNotifier extends AsyncNotifier<SaveSettings> {
  @override
  Future<SaveSettings> build() async {
    try {
      final raw = await ref.read(prefsStoreProvider).read(key: _key);
      if (raw == null || raw.isEmpty) return const SaveSettings();
      return SaveSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SaveSettings();
    }
  }

  /// 先改状态(立即生效),再尽力持久化。
  Future<void> patch(SaveSettings Function(SaveSettings) change) async {
    final next = change(state.value ?? const SaveSettings());
    state = AsyncData(next);
    try {
      await ref
          .read(prefsStoreProvider)
          .write(key: _key, value: jsonEncode(next.toJson()));
    } catch (_) {}
  }
}

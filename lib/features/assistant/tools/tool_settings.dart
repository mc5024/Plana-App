/// 工具页的开关:哪些工具关着,哪些附带选项开着。工具默认全开,选项默认关。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/app_stores.dart';
import '../../../core/store/prefs_store.dart';

const _key = 'assistant_tools';

/// 旧版助手设置的键:「资料库范围」「OC 占位符」原先存在那里。
const _legacyKey = 'assistant_settings';

/// 使用角色库的「OC 使用占位符」选项。
const kOcPlaceholdersOption = 'search_oc/placeholders';

class ToolSettings {
  const ToolSettings({
    this.disabledTools = const {},
    this.enabledOptions = const {},
  });

  /// 关掉的工具名。记关着的,以后新加的工具默认开着。
  final Set<String> disabledTools;

  /// 开着的附带选项,`工具名/选项 id`。
  final Set<String> enabledOptions;

  bool toolOn(String tool) => !disabledTools.contains(tool);

  bool optionOn(String tool, String option) =>
      enabledOptions.contains('$tool/$option');

  /// 使用角色库:OC 只给模型占位符,出图前展开。
  bool get ocPlaceholders => enabledOptions.contains(kOcPlaceholdersOption);

  ToolSettings copyWith({
    Set<String>? disabledTools,
    Set<String>? enabledOptions,
  }) => ToolSettings(
    disabledTools: disabledTools ?? this.disabledTools,
    enabledOptions: enabledOptions ?? this.enabledOptions,
  );

  Map<String, dynamic> toJson() => {
    'disabledTools': disabledTools.toList()..sort(),
    'enabledOptions': enabledOptions.toList()..sort(),
  };

  factory ToolSettings.fromJson(Map<String, dynamic> j) => ToolSettings(
    disabledTools: _set(j['disabledTools']),
    enabledOptions: _set(j['enabledOptions']),
  );

  /// 旧版助手设置 → 工具设置:资料库范围选「不使用」的,关掉使用画风库、使用角色库;
  /// OC 占位符原样带过来。
  factory ToolSettings.fromLegacy(Map<String, dynamic> j) {
    final none = j['libraryScope'] == 'none';
    return ToolSettings(
      disabledTools: none ? const {'search_artist', 'search_oc'} : const {},
      enabledOptions: j['ocPlaceholders'] == true
          ? const {kOcPlaceholdersOption}
          : const {},
    );
  }

  static Set<String> _set(Object? v) => {
    if (v is List)
      for (final e in v)
        if ('$e'.isNotEmpty) '$e',
  };
}

/// 还没有工具设置时,把旧版助手设置里的「资料库范围」「OC 占位符」迁过来。
///
/// 助手设置读盘时先调它:之后助手设置一改就整份重写,旧字段就没了。
Future<void> migrateLegacyToolSettings(PrefsStore prefs) async {
  try {
    final has = await prefs.read(key: _key);
    if (has != null && has.isNotEmpty) return;
    final legacy = await prefs.read(key: _legacyKey);
    if (legacy == null || legacy.isEmpty) return;
    final j = jsonDecode(legacy);
    if (j is! Map<String, dynamic>) return;
    if (!j.containsKey('libraryScope') && !j.containsKey('ocPlaceholders')) {
      return;
    }
    await prefs.write(
      key: _key,
      value: jsonEncode(ToolSettings.fromLegacy(j).toJson()),
    );
  } catch (_) {
    // 迁不过去就按默认(全开)
  }
}

final toolSettingsProvider =
    AsyncNotifierProvider<ToolSettingsNotifier, ToolSettings>(
      ToolSettingsNotifier.new,
    );

class ToolSettingsNotifier extends AsyncNotifier<ToolSettings> {
  @override
  Future<ToolSettings> build() async {
    final prefs = ref.read(prefsStoreProvider);
    try {
      await migrateLegacyToolSettings(prefs);
      final raw = await prefs.read(key: _key);
      if (raw == null || raw.isEmpty) return const ToolSettings();
      return ToolSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ToolSettings();
    }
  }

  Future<void> _patch(ToolSettings Function(ToolSettings) change) async {
    final next = change(state.value ?? const ToolSettings());
    state = AsyncData(next);
    try {
      await ref
          .read(prefsStoreProvider)
          .write(key: _key, value: jsonEncode(next.toJson()));
    } catch (_) {
      // 存不下只影响下次冷启动,这一程照常按新设置走
    }
  }

  static Set<String> _toggled(Set<String> s, String key, bool add) =>
      add ? {...s, key} : ({...s}..remove(key));

  Future<void> setTool(String tool, bool on) => _patch(
    (s) => s.copyWith(disabledTools: _toggled(s.disabledTools, tool, !on)),
  );

  Future<void> setOption(String tool, String option, bool on) => _patch(
    (s) => s.copyWith(
      enabledOptions: _toggled(s.enabledOptions, '$tool/$option', on),
    ),
  );
}

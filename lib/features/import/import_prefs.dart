import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../../core/store/prefs_store.dart';

/// 导入面板上一次用的**偏好**（持久化）。
///
/// 只记「跟这张图无关」的那些选择。面板里另一半开关是**元数据驱动**的，必须每次
/// 现算，记了反而出错：
///   · `_usePrompt` / `_useNegative` —— 这张图有没有那段文本
///   · `_usePreset`                  —— 是不是 NAI 图
///   · `_convertPrompt`              —— 源是不是 a1111 语法、目标是不是 NAI
///   · 角色 / Vibe / LoRA 的勾选下标 —— 逐图不同，下标本身就没有跨图含义
///
/// 参数项（模型/分辨率/Steps/CFG…）按**标题**存，不按字段名：三类模型
/// （NAI / anima / krea）各有一套字段，标题是它们之间唯一稳定的键。默认缺省
/// 即「勾上」，所以首次使用与改动前的行为完全一致。
class ImportPrefs {
  const ImportPrefs({
    this.presetImport = true,
    this.presetExpanded = false,
    this.charImport = true,
    this.vibeImport = true,
    this.loraImport = true,
    this.promptAppend = false,
    this.charAppend = false,
    this.vibeAppend = false,
    this.loraAppend = false,
    this.useSeed = false,
    this.settings = const {},
    this.sectionExpanded = true,
    this.charExpanded = true,
    this.vibeExpanded = true,
    this.settingsExpanded = true,
    this.loraExpanded = true,
  });

  /// 提示词预设:true=「导入」(顺带切档位),false=「剥离」(只删文本)。
  final bool presetImport;

  /// 预设卡详情的展开态。默认收起 —— 那段会被剥掉的文本重度档有二十来个词,
  /// 常驻着会把下面的角色/Vibe/参数顶出屏幕。
  final bool presetExpanded;

  /// 角色 / Vibe / LoRA **这一整类要不要导**。
  ///
  /// 逐行的勾选下标不记(那是逐图的,跨图没有含义),但「整区全不勾」是个明确的
  /// 偏好——用户点区头的全选框清空,意思是「这类东西我不导」,下次开面板不该
  /// 又给他勾满。所以只记这一位:true=按老规矩预勾,false=整区留空。
  final bool charImport;
  final bool vibeImport;
  final bool loraImport;

  /// 主提示词:false=完全覆盖,true=新建分区。
  final bool promptAppend;

  /// 角色 / Vibe / LoRA:false=完全覆盖,true=额外添加。
  final bool charAppend;
  final bool vibeAppend;
  final bool loraAppend;

  /// 种子。默认 false —— 大多数人导入是想复现风格而不是复现同一张图。
  final bool useSeed;

  /// 参数项标题 → 勾选。**缺席即勾上**(见类文档),所以这里只需要存用户
  /// 手动取消过的那些,不必把整表写满。
  final Map<String, bool> settings;

  /// 四个可折叠区的展开态。
  final bool sectionExpanded;
  final bool charExpanded;
  final bool vibeExpanded;
  final bool settingsExpanded;
  final bool loraExpanded;

  ImportPrefs copyWith({
    bool? presetImport,
    bool? presetExpanded,
    bool? charImport,
    bool? vibeImport,
    bool? loraImport,
    bool? promptAppend,
    bool? charAppend,
    bool? vibeAppend,
    bool? loraAppend,
    bool? useSeed,
    Map<String, bool>? settings,
    bool? sectionExpanded,
    bool? charExpanded,
    bool? vibeExpanded,
    bool? settingsExpanded,
    bool? loraExpanded,
  }) => ImportPrefs(
    presetImport: presetImport ?? this.presetImport,
    presetExpanded: presetExpanded ?? this.presetExpanded,
    charImport: charImport ?? this.charImport,
    vibeImport: vibeImport ?? this.vibeImport,
    loraImport: loraImport ?? this.loraImport,
    promptAppend: promptAppend ?? this.promptAppend,
    charAppend: charAppend ?? this.charAppend,
    vibeAppend: vibeAppend ?? this.vibeAppend,
    loraAppend: loraAppend ?? this.loraAppend,
    useSeed: useSeed ?? this.useSeed,
    settings: settings ?? this.settings,
    sectionExpanded: sectionExpanded ?? this.sectionExpanded,
    charExpanded: charExpanded ?? this.charExpanded,
    vibeExpanded: vibeExpanded ?? this.vibeExpanded,
    settingsExpanded: settingsExpanded ?? this.settingsExpanded,
    loraExpanded: loraExpanded ?? this.loraExpanded,
  );

  Map<String, dynamic> toJson() => {
    'presetImport': presetImport,
    'presetExpanded': presetExpanded,
    'charImport': charImport,
    'vibeImport': vibeImport,
    'loraImport': loraImport,
    'promptAppend': promptAppend,
    'charAppend': charAppend,
    'vibeAppend': vibeAppend,
    'loraAppend': loraAppend,
    'useSeed': useSeed,
    'settings': settings,
    'sectionExpanded': sectionExpanded,
    'charExpanded': charExpanded,
    'vibeExpanded': vibeExpanded,
    'settingsExpanded': settingsExpanded,
    'loraExpanded': loraExpanded,
  };

  /// 逐项容错:任何一项类型不对就退回默认,不因为一个坏字段丢掉整份偏好。
  factory ImportPrefs.fromJson(Map<String, dynamic> j) {
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    final raw = j['settings'];
    return ImportPrefs(
      presetImport: b('presetImport', true),
      presetExpanded: b('presetExpanded', false),
      charImport: b('charImport', true),
      vibeImport: b('vibeImport', true),
      loraImport: b('loraImport', true),
      promptAppend: b('promptAppend', false),
      charAppend: b('charAppend', false),
      vibeAppend: b('vibeAppend', false),
      loraAppend: b('loraAppend', false),
      useSeed: b('useSeed', false),
      settings: raw is Map
          ? {
              for (final e in raw.entries)
                if (e.value is bool) '${e.key}': e.value as bool,
            }
          : const {},
      sectionExpanded: b('sectionExpanded', true),
      charExpanded: b('charExpanded', true),
      vibeExpanded: b('vibeExpanded', true),
      settingsExpanded: b('settingsExpanded', true),
      loraExpanded: b('loraExpanded', true),
    );
  }
}

/// 不登记进 [PrefsStore.migrateKeys]:那张表是给「曾经存在 secure storage 里、
/// 需要搬出来」的键用的,这个键是新加的,从没在那边待过,登记了也只是一次
/// 必然返回 null 的读。
const _key = 'import_prefs';

class ImportPrefsNotifier extends AsyncNotifier<ImportPrefs> {
  PrefsStore get _storage => ref.read(prefsStoreProvider);

  @override
  Future<ImportPrefs> build() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const ImportPrefs();
      return ImportPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ImportPrefs();
    }
  }

  /// 落盘一份新的偏好。**在真正执行导入时调**,不是每次拨开关就写 ——
  /// 「上一次导入的设置」指的是用户最终确认的那一套,中途试着拨两下又改回去的
  /// 不该算数。写失败不打断导入。
  Future<void> save(ImportPrefs next) async {
    state = AsyncData(next);
    try {
      await _storage.write(key: _key, value: jsonEncode(next.toJson()));
    } catch (_) {}
  }
}

final importPrefsProvider =
    AsyncNotifierProvider<ImportPrefsNotifier, ImportPrefs>(
      ImportPrefsNotifier.new,
    );

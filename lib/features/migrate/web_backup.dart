/// web(novelai_web_ui)「数据备份」文件的解析与格式适配。
///
/// 契约来自 web `src/services/backupService.ts`(桌面/移动端共用同一份):
/// ```
/// { meta: { identifier: 'novelai-web-ui-backup', version: 1, createdAt, ... },
///   localStorage: { 'novelai_prompt_presets': '<JSON 串>', 'novelai_active_preset': '<id>', … },
///   indexedDB:    { vibes: [...], oc_files: [...], artist_files: [...], cr_files: [...] } }
/// ```
/// 注意 localStorage 的值是**字符串**(预设那项是 JSON 串,要二次解析)。
///
/// 四类 IndexedDB 数据在 app 侧都有落点:
/// - `vibes`        → Vibe 库(转成 .naiv4vibebundle 走现成的 importVibeText)
/// - `cr_files`     → 角色参考图库(preview 是 data URL,解出字节落库)
/// - `oc_files`     → 灵感库「角色」分类
/// - `artist_files` → 灵感库「画风」分类
///
/// 后两类交给灵感库现成的 [TagLibrary.mergeBackup] —— 它按 webId 分类收原始
/// map,内部用 [decodeBackupEntry] 解码,而那个解码器本就是照 web 的三种 shape
/// 写的(画师串读 `prompt`、角色读 `positive`,别名/预览/未知字段都照顾到了)。
/// 这里只做「web 备份的键名 → 灵感库的 webId」这一层搬运,不重写解码。
///
/// 注意 editor 下那个 `artist_oc_library.dart` 是**另一回事** —— 那是增强模式
/// 下直读后端 `/api/artists/list` 的只读缓存,不是本地库,别拿它当落点。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../generate/prompt_presets.dart';
import '../vibe_library/naiv4vibe_codec.dart';
import '../../l10n/l10n.dart';

const kWebBackupIdentifier = 'novelai-web-ui-backup';
const kWebBackupVersion = 1;

/// 一张角色参考图(已从 data URL 解出字节)。
typedef WebBackupImage = ({String name, Uint8List bytes});

class WebBackup {
  const WebBackup({
    required this.createdAt,
    required this.vibes,
    required this.crs,
    required this.artists,
    required this.ocs,
    required this.presets,
    this.activePresetId,
  });

  /// meta.createdAt(ISO 串;原样展示,不解析成本地时区免得又生歧义)。
  final String createdAt;

  /// 原始 VibeData 列表(转换推迟到 [vibeBundleText],预览阶段不做重活)。
  final List<Map<String, dynamic>> vibes;

  /// 角色参考:preview 能解出字节的才收(解不出的等于没有图,留着也没用)。
  final List<WebBackupImage> crs;

  /// 画师串 / OC 的**原始** map(解码交给灵感库的 mergeBackup,见 [tagCategories])。
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> ocs;

  /// 自定义预设(内置三档 heavy/light/none 已剔除 —— app 侧恒用内置文本)。
  final List<PromptPreset> presets;

  /// 激活预设 id(web 存的是裸字符串)。
  final String? activePresetId;

  bool get isEmpty =>
      vibes.isEmpty &&
      crs.isEmpty &&
      artists.isEmpty &&
      ocs.isEmpty &&
      presets.isEmpty &&
      activePresetId == null;

  /// 喂给灵感库 [TagLibrary.mergeBackup] 的形状:webId → 原始条目表。
  /// 键名是灵感库分类的 webId(与 web tag-manager 同一套),不是备份文件里的键。
  /// 场景/其他两类 web 备份里没有,自然缺席。
  Map<String, dynamic> tagCategories() => {
    if (ocs.isNotEmpty) 'character': ocs,
    if (artists.isNotEmpty) 'artist-style': artists,
  };

  /// 解析备份文件文本。格式不对抛 [FormatException],消息可直接给用户看。
  static WebBackup parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw FormatException(l10nNow.notValidJson);
    }
    return fromDecoded(j);
  }

  /// 已解析好的 JSON → 备份对象。备份文件可能上百 MB(vibe 的图是 base64),
  /// 手上已经有对象树时走这里,别再拿原文本重解析一遍 —— 那等于把整份数据
  /// 在内存里又存了一份。流式读文件见 `core/util/file_read.dart`。
  static WebBackup fromDecoded(Object? j) {
    if (j is! Map<String, dynamic>) {
      throw FormatException(l10nNow.notValidBackup);
    }

    final meta = j['meta'];
    if (meta is! Map || meta['identifier'] != kWebBackupIdentifier) {
      throw FormatException(l10nNow.backupIdMismatch);
    }
    final ver = meta['version'];
    if (ver != kWebBackupVersion) {
      throw FormatException(
        l10nNow.backupVersionUnsupported('$ver', '$kWebBackupVersion'),
      );
    }
    final idb = j['indexedDB'];
    final ls = j['localStorage'];
    if (idb is! Map || ls is! Map) {
      throw FormatException(l10nNow.backupIncomplete);
    }

    List<Map<String, dynamic>> mapsOf(Object? v) => [
      for (final e in (v is List ? v : const []))
        if (e is Map<String, dynamic>) e,
    ];

    final crs = <WebBackupImage>[];
    for (final c in mapsOf(idb['cr_files'])) {
      final bytes = decodeDataUrl(c['preview']);
      if (bytes == null) continue; // 没图的角色参考条目没有意义
      final name = c['name'];
      crs.add((
        name: name is String && name.isNotEmpty ? name : '参考图',
        bytes: bytes,
      ));
    }

    final (presets, activeId) = _presetsOf(ls);

    return WebBackup(
      createdAt: meta['createdAt'] is String ? meta['createdAt'] as String : '',
      vibes: mapsOf(idb['vibes']),
      crs: crs,
      artists: mapsOf(idb['artist_files']),
      ocs: mapsOf(idb['oc_files']),
      presets: presets,
      activePresetId: activeId,
    );
  }

  /// 预设:`novelai_prompt_presets` 是 JSON **串**;字段与 app [PromptPreset]
  /// 同名同义(web PromptPresetData),直接映射。内置三档剔除 —— app 侧
  /// 恒用内置文本(与 web 的「默认项每次加载都被覆盖」同语义)。
  static (List<PromptPreset>, String?) _presetsOf(Map ls) {
    final out = <PromptPreset>[];
    final raw = ls['novelai_prompt_presets'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is! Map<String, dynamic>) continue;
            if (e['isDefault'] == true) continue;
            if (e['id'] is! String) continue;
            if (kDefaultPromptPresets.any((d) => d.id == e['id'])) continue;
            out.add(PromptPreset.fromJson(e));
          }
        }
      } catch (_) {} // 预设坏了不该让整个备份导不进来
    }
    final active = ls['novelai_active_preset'];
    return (out, active is String && active.isNotEmpty ? active : null);
  }

  /// Vibe → `.naiv4vibe` 文件 JSON 列表,交给 Vibe 库的 importVibeRaws 落库。
  ///
  /// 只搬字段、与源 map 共享同一批 base64 字符串,几乎不占额外内存。
  /// 不再拼成一个 `.naiv4vibebundle` 大字符串 —— 拼包 + 重新解析会让同一批
  /// 数据在内存里堆到三份,几百条带图的 vibe 足以把 app 撑爆。
  List<Map<String, dynamic>> naiv4Raws() => [
    for (final v in vibes) vibeDataToNaiv4(v),
  ];
}

/// web `VibeData`(IndexedDB) → `.naiv4vibe` 文件 JSON(web `Naiv4VibeFile`)。
///
/// 两处形状差异,别直接搬:
/// - 缩略图:VibeData 叫 `preview`,文件里叫 `thumbnail`;
/// - 默认参数:VibeData 拍平成 `defaultStrength`/`defaultInfoExtracted`,
///   文件里收在 `importInfo` 下 —— app 的 [ParsedVibe] 只认后者,不还原就丢默认值。
///
/// `encodings` 两边同构(modelKey → hashKey → {encoding, params}),原样透传;
/// 云同步那几个字段(cloudSync/imageHash/localMetaFp…)是 web 私有账本,不带过来。
Map<String, dynamic> vibeDataToNaiv4(Map<String, dynamic> v) {
  final image = v['image'];
  final imageBase64 = image is String ? image : '';
  final id = v['id'] is String && (v['id'] as String).isNotEmpty
      ? v['id'] as String
      : (imageBase64.isNotEmpty ? naiVibeIdOfBase64(imageBase64) : '');
  final strength = (v['defaultStrength'] as num?)?.toDouble();
  final ie = (v['defaultInfoExtracted'] as num?)?.toDouble();

  return {
    'identifier': 'novelai-vibe-transfer',
    'version': 1,
    'type': 'image',
    'image': imageBase64,
    'id': id,
    'encodings': v['encodings'] is Map ? v['encodings'] : <String, dynamic>{},
    'name': v['name'] is String ? v['name'] : '',
    'thumbnail': v['preview'] is String ? v['preview'] : '',
    'createdAt': (v['createdAt'] as num?)?.toInt() ?? 0,
    if (strength != null || ie != null)
      'importInfo': {
        'model': '',
        'information_extracted': ?ie,
        'strength': ?strength,
      },
    if (v['tags'] is List)
      'tags': [
        for (final t in v['tags'] as List)
          if (t is String) t,
      ],
  };
}

/// `data:<mime>;base64,XXXX` → 字节;不是 data URL / 解不开返回 null。
Uint8List? decodeDataUrl(Object? v) {
  if (v is! String || !v.startsWith('data:')) return null;
  final comma = v.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(v.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

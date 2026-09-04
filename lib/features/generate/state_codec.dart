import 'dart:typed_data';

import '../../core/store/blob_store.dart';
import 'char_position.dart';
import 'models.dart';
import 'nai_request.dart' show kLegacyAutoCenters;

/// GenerateState ⇄ JSON。图片字节不进 JSON——写入 [BlobStore] 后只存
/// 内容哈希引用;[EncodedState.refs] 汇总本快照引用的全部 blob,
/// 落盘方把它写进信封顶层,启动期 GC 只扫信封不解析业务字段。
class EncodedState {
  const EncodedState(this.json, this.refs);

  final Map<String, dynamic> json;
  final Set<String> refs;
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

Future<EncodedState> encodeGenerateState(
  GenerateState s,
  BlobStore blobs,
) async {
  final refs = <String>{};

  Future<String?> putImg(Uint8List? bytes, {String? known}) async {
    if (bytes == null) return null;
    final h = await blobs.put(bytes, known: known);
    refs.add(h);
    return h;
  }

  final vibes = <Map<String, dynamic>>[];
  for (final v in s.vibes) {
    vibes.add({
      'id': v.id,
      'name': v.name,
      'enabled': v.enabled,
      'strength': v.strength,
      'infoExtracted': v.infoExtracted,
      'image': await putImg(v.image, known: v.imageHash),
      if (v.encodedByModel != null) 'encodedByModel': v.encodedByModel,
      if (v.sourceId != null) 'sourceId': v.sourceId,
    });
  }

  final charRefs = <Map<String, dynamic>>[];
  for (final r in s.charRefs) {
    charRefs.add({
      'id': r.id,
      'name': r.name,
      'enabled': r.enabled,
      'mode': r.mode.name,
      'strength': r.strength,
      'infoExtracted': r.infoExtracted,
      'image': await putImg(r.image, known: r.imageHash),
    });
  }

  final kreaStyleRefs = <Map<String, dynamic>>[];
  for (final r in s.kreaStyleRefs) {
    final hash = await putImg(r.image, known: r.imageHash);
    if (hash == null) continue; // 无图的条目无法参与生成
    kreaStyleRefs.add({
      'id': r.id,
      'name': r.name,
      'enabled': r.enabled,
      'image': hash,
    });
  }

  final i2i = s.img2img;
  final inpaint = s.inpaint;
  final paste = inpaint?.paste;
  final p = s.params;

  final json = <String, dynamic>{
    'prompt': s.prompt,
    'negativePrompt': s.negativePrompt,
    // 编辑器原文草稿:与定稿无差别时为空,空就不写(绝大多数存档不带这两键)
    if (s.promptRaw.isNotEmpty) 'promptRaw': s.promptRaw,
    if (s.negativePromptRaw.isNotEmpty)
      'negativePromptRaw': s.negativePromptRaw,
    'characters': [
      for (final c in s.characters)
        {
          'id': c.id,
          'name': c.name,
          'positive': c.positive,
          'negative': c.negative,
          if (c.positiveRaw.isNotEmpty) 'positiveRaw': c.positiveRaw,
          if (c.negativeRaw.isNotEmpty) 'negativeRaw': c.negativeRaw,
          'enabled': c.enabled,
          if (c.position != null) 'position': c.position,
          'activeTab': c.activeTab.name,
        },
    ],
    'vibes': vibes,
    'charRefs': charRefs,
    // LoRA 无图片字节(previewUrl 是远端直链),整条直接进 JSON
    // 下载中的占位条不入存档:安装队列在内存里,重启就没了,存回来只会是一条
    // 永远停在「排队中」、还悄悄不参与生成的僵尸条目。
    if (s.loras.any((l) => l.pending == null))
      'loras': [
        for (final l in s.loras)
          if (l.pending == null)
            {
              'name': l.name,
              'displayName': l.displayName,
              'weight': l.weight,
              'enabled': l.enabled,
              if (l.clipWeight != null) 'clipWeight': l.clipWeight,
              if (l.hasTe != null) 'hasTe': l.hasTe,
              'triggerWords': l.triggerWords,
              if (l.previewUrl.isNotEmpty) 'previewUrl': l.previewUrl,
              'type': l.type,
            },
      ],
    if (kreaStyleRefs.isNotEmpty) 'kreaStyleRefs': kreaStyleRefs,
    // 强度无条件写(不跟着图走):同一份 codec 也在存创作页工作区,只在有图时
    // 存的话,把参考图清空再重启,调好的强度就没了。
    'kreaStyleRefWeight': s.kreaStyleRefWeight,
    if (i2i != null)
      'img2img': {
        'strength': i2i.strength,
        'noise': i2i.noise,
        'image': await putImg(i2i.image),
      },
    'params': {
      'model': p.model,
      'width': p.width,
      'height': p.height,
      'steps': p.steps,
      'cfg': p.cfg,
      'varietyPlus': p.varietyPlus,
      'sampler': p.sampler,
      'noiseSchedule': p.noiseSchedule,
      'seed': p.seed,
      'cfgRescale': p.cfgRescale,
      'normalizeVibe': p.normalizeVibe,
      'loop': p.loop.name,
      'animaSteps': p.animaSteps,
      'animaCfg': p.animaCfg,
      'animaSampler': p.animaSampler,
      'animaScheduler': p.animaScheduler,
      'kreaSteps': p.kreaSteps,
      'kreaCfg': p.kreaCfg,
      'kreaSampler': p.kreaSampler,
      'kreaScheduler': p.kreaScheduler,
      // 各 Modal 档位调过的采样参数(切档来回不丢,见 GenParams.modalMem)。
      // 没进过任何一档就整键不写,老存档/纯 NAI 用户的档案一个字节都不变。
      if (p.modalMem.isNotEmpty)
        'modalMem': {
          for (final e in p.modalMem.entries)
            e.key: {
              'steps': e.value.steps,
              'cfg': e.value.cfg,
              'sampler': e.value.sampler,
              'scheduler': e.value.scheduler,
            },
        },
      'batchCount': p.batchCount,
      'useCoords': p.useCoords,
      // 整块常驻(不只在 enabled 时写):同一份 codec 也在存创作页工作区,
      // 只存开着的那份,用户关掉开关重启后调好的倍率/强度就没了。
      'hires': {
        'enabled': p.hires.enabled,
        'scale': p.hires.scale,
        'denoise': p.hires.denoise,
        'steps': p.hires.steps,
        'useModel': p.hires.useModel,
        'model': p.hires.model.name,
      },
    },
    'anlas': s.anlas,
    'openPanels': [for (final pn in s.openPanels) pn.name],
    if (inpaint != null)
      'inpaint': {
        'image': await putImg(inpaint.image),
        'mask': await putImg(inpaint.mask),
        'strength': inpaint.strength,
        if (inpaint.sourceId != null) 'sourceId': inpaint.sourceId,
        if (inpaint.grid != null) 'grid': await putImg(inpaint.grid!),
        if (paste != null)
          'paste': {
            'original': await putImg(paste.original),
            'sendX': paste.sendX,
            'sendY': paste.sendY,
            'tightX': paste.tightX,
            'tightY': paste.tightY,
            'tightW': paste.tightW,
            'tightH': paste.tightH,
            'outW': paste.outW,
            'outH': paste.outH,
          },
      },
  };
  return EncodedState(json, refs);
}

/// 反序列化。blob 缺失(被清/损坏)时按条目降级:vibe 留编码丢图、
/// CR 整条跳过、img2img/重绘任务置空——恢复出的状态始终可用。
/// 存量存档迁移:把老的「每角色 AUTO」翻译成官方那套「全局 use_coords + 具体坐标」。
///
/// 2026-09-04 之前:`use_coords` 恒发 `true`,`position == null` 表示 AUTO,发送时
/// 按**参与出图的角色**的下标从 [kLegacyAutoCenters] 代一个坐标进去。现在改成
/// 官方模型(全局开关默认 false,角色建出来就带坐标),老存档若不迁移,那些
/// `null` 会被当成"没坐标"回落到正中 —— 同一份提示词出的图就变了。
///
/// 所以迁移**照原样复现**:补回当年会代进去的那个坐标,并把开关钉成 `true`。
/// 判据是「存档里没有 useCoords 这个键」= 老版本写的;新版存档一律带这个键,
/// 不会被误迁。
///
/// ⚠ 下标必须按当年的口径算 —— 只数 `enabled && positive 非空` 的那些
/// (见 buildNaiPayload 的 chars 过滤),否则一个禁用的首位角色会让后面全错一格。
/// 不参与出图的那些补个不冲突的空位即可,它们本来也发不出去。
({List<CharacterPrompt> characters, bool useCoords})?
_migrateLegacyPositions(
  List<CharacterPrompt> characters, {
  required bool hadUseCoordsKey,
}) {
  if (hadUseCoordsKey) return null; // 新存档,不动
  if (!characters.any((c) => c.position == null)) return null; // 没有 AUTO 可迁

  final out = <CharacterPrompt>[];
  var sendIndex = 0;
  for (final c in characters) {
    if (c.position != null) {
      out.add(c);
      continue;
    }
    final sends = c.enabled && c.positive.trim().isNotEmpty;
    if (sends) {
      final a = kLegacyAutoCenters[sendIndex % kLegacyAutoCenters.length];
      sendIndex++;
      out.add(c.copyWith(position: positionOfCenter(a['x'], a['y'])));
    } else {
      // 不参与出图:给个不与他人冲突的空位,免得 UI 上一堆角色叠在同一格
      out.add(
        c.copyWith(
          position: nextSpawnPosition(
            out.map((e) => e.position),
            freeform: false,
          ),
        ),
      );
    }
  }
  return (characters: out, useCoords: true);
}

Future<GenerateState> decodeGenerateState(
  Map<String, dynamic> j,
  BlobStore blobs,
) async {
  Future<Uint8List?> img(Object? hash) async =>
      hash is String && hash.isNotEmpty ? blobs.get(hash) : null;

  final characters = <CharacterPrompt>[];
  if (j['characters'] is List) {
    for (final e in j['characters'] as List) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String) continue;
      characters.add(
        CharacterPrompt(
          id: id,
          name: e['name'] is String ? e['name'] as String : '角色',
          positive: e['positive'] is String ? e['positive'] as String : '',
          negative: e['negative'] is String ? e['negative'] as String : '',
          positiveRaw: e['positiveRaw'] is String
              ? e['positiveRaw'] as String
              : '',
          negativeRaw: e['negativeRaw'] is String
              ? e['negativeRaw'] as String
              : '',
          enabled: e['enabled'] != false,
          position: e['position'] as String?,
          activeTab:
              _enumByName(CharTab.values, e['activeTab']) ?? CharTab.positive,
        ),
      );
    }
  }

  final vibes = <VibeItem>[];
  if (j['vibes'] is List) {
    for (final e in j['vibes'] as List) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String) continue;
      final hash = e['image'] as String?;
      final bytes = await img(hash);
      final enc = e['encodedByModel'] is Map
          ? (e['encodedByModel'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )
          : null;
      if (bytes == null && (enc == null || enc.isEmpty)) continue; // 不可生成
      vibes.add(
        VibeItem(
          id: id,
          name: e['name'] is String ? e['name'] as String : '',
          enabled: e['enabled'] != false,
          strength: (e['strength'] as num?)?.toDouble() ?? 0.6,
          infoExtracted: (e['infoExtracted'] as num?)?.toDouble() ?? 1.0,
          image: bytes,
          imageHash: bytes != null ? hash : null,
          encodedByModel: enc,
          sourceId: e['sourceId'] as String?,
        ),
      );
    }
  }

  final charRefs = <CharRefItem>[];
  if (j['charRefs'] is List) {
    for (final e in j['charRefs'] as List) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String) continue;
      final hash = e['image'] as String?;
      final bytes = await img(hash);
      if (bytes == null) continue; // 无图的 CR 无法参与生成
      charRefs.add(
        CharRefItem(
          id: id,
          name: e['name'] is String ? e['name'] as String : '',
          enabled: e['enabled'] != false,
          mode: _enumByName(CharRefMode.values, e['mode']) ?? CharRefMode.both,
          strength: (e['strength'] as num?)?.toDouble() ?? 1.0,
          infoExtracted: (e['infoExtracted'] as num?)?.toDouble() ?? 1.0,
          image: bytes,
          imageHash: hash,
        ),
      );
    }
  }

  final kreaStyleRefs = <KreaStyleRefItem>[];
  if (j['kreaStyleRefs'] is List) {
    for (final e in j['kreaStyleRefs'] as List) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String) continue;
      final hash = e['image'] as String?;
      final bytes = await img(hash);
      if (bytes == null) continue; // 无图的风格参考无法参与生成
      kreaStyleRefs.add(
        KreaStyleRefItem(
          id: id,
          name: e['name'] is String ? e['name'] as String : '',
          enabled: e['enabled'] != false,
          image: bytes,
          imageHash: hash,
        ),
      );
    }
  }

  final loras = <ActiveLora>[];
  if (j['loras'] is List) {
    for (final e in j['loras'] as List) {
      if (e is! Map) continue;
      final name = e['name'];
      if (name is! String || name.isEmpty) continue;
      loras.add(
        ActiveLora(
          name: name,
          displayName: e['displayName'] is String
              ? e['displayName'] as String
              : name,
          weight: (e['weight'] as num?)?.toDouble() ?? 0.8,
          enabled: e['enabled'] != false,
          clipWeight: (e['clipWeight'] as num?)
              ?.toDouble(), // 缺省 null=跟随 weight
          hasTe: e['hasTe'] is bool ? e['hasTe'] as bool : null,
          triggerWords: e['triggerWords'] is List
              ? [
                  for (final t in e['triggerWords'] as List)
                    if (t is String && t.isNotEmpty) t,
                ]
              : const [],
          previewUrl: e['previewUrl'] is String
              ? e['previewUrl'] as String
              : '',
          type: e['type'] is String ? e['type'] as String : 'concept',
        ),
      );
    }
  }

  Img2ImgConfig? img2img;
  if (j['img2img'] is Map) {
    final e = j['img2img'] as Map;
    final bytes = await img(e['image']);
    if (bytes != null) {
      img2img = Img2ImgConfig(
        strength: (e['strength'] as num?)?.toDouble() ?? 0.7,
        noise: (e['noise'] as num?)?.toDouble() ?? 0.0,
        image: bytes,
      );
    }
  }

  var params = const GenParams();
  if (j['params'] is Map) {
    final e = j['params'] as Map;
    var hires = params.hires;
    if (e['hires'] is Map) {
      final he = e['hires'] as Map;
      hires = HiresConfig(
        enabled: he['enabled'] == true,
        scale: (he['scale'] as num?)?.toDouble() ?? hires.scale,
        denoise: (he['denoise'] as num?)?.toDouble() ?? hires.denoise,
        steps: (he['steps'] as num?)?.toInt() ?? hires.steps,
        // 老存档没这键 → 默认「先超分后重绘」(与新建时一致)
        useModel: he['useModel'] != false,
        model: _enumByName(HiresUpscaler.values, he['model']) ?? hires.model,
      );
    }
    // 档位记忆:四个字段缺一条就整条丢掉(回落该档官方配方)—— 半套参数还原
    // 出去是 sampler 传空串给服务端,那比忘掉这一档难查得多。
    final modalMem = <String, ModalSampling>{};
    if (e['modalMem'] is Map) {
      for (final me in (e['modalMem'] as Map).entries) {
        final k = me.key;
        final v = me.value;
        if (k is! String || v is! Map) continue;
        final steps = (v['steps'] as num?)?.toInt();
        final cfg = (v['cfg'] as num?)?.toDouble();
        final sampler = v['sampler'];
        final scheduler = v['scheduler'];
        if (steps == null ||
            cfg == null ||
            sampler is! String ||
            scheduler is! String) {
          continue;
        }
        modalMem[k] = (
          steps: steps,
          cfg: cfg,
          sampler: sampler,
          scheduler: scheduler,
        );
      }
    }
    params = GenParams(
      model: e['model'] is String ? e['model'] as String : params.model,
      width: (e['width'] as num?)?.toInt() ?? params.width,
      height: (e['height'] as num?)?.toInt() ?? params.height,
      steps: (e['steps'] as num?)?.toInt() ?? params.steps,
      cfg: (e['cfg'] as num?)?.toDouble() ?? params.cfg,
      varietyPlus: e['varietyPlus'] == true,
      sampler: e['sampler'] is String ? e['sampler'] as String : params.sampler,
      noiseSchedule: e['noiseSchedule'] is String
          ? e['noiseSchedule'] as String
          : params.noiseSchedule,
      seed: e['seed'] is String ? e['seed'] as String : '',
      cfgRescale: (e['cfgRescale'] as num?)?.toDouble() ?? 0.0,
      // 老存档没这个键 → 默认开(与此前恒开的行为一致)
      normalizeVibe: e['normalizeVibe'] != false,
      loop: _enumByName(LoopCount.values, e['loop']) ?? LoopCount.x8,
      animaSteps: (e['animaSteps'] as num?)?.toInt() ?? params.animaSteps,
      animaCfg: (e['animaCfg'] as num?)?.toDouble() ?? params.animaCfg,
      animaSampler: e['animaSampler'] is String
          ? e['animaSampler'] as String
          : params.animaSampler,
      animaScheduler: e['animaScheduler'] is String
          ? e['animaScheduler'] as String
          : params.animaScheduler,
      kreaSteps: (e['kreaSteps'] as num?)?.toInt() ?? params.kreaSteps,
      kreaCfg: (e['kreaCfg'] as num?)?.toDouble() ?? params.kreaCfg,
      // 2026-08-10 开放采样器之前存下的记录没有这两键,回落到默认的官方配方
      kreaSampler: e['kreaSampler'] is String
          ? e['kreaSampler'] as String
          : params.kreaSampler,
      kreaScheduler: e['kreaScheduler'] is String
          ? e['kreaScheduler'] as String
          : params.kreaScheduler,
      // 老记录没这键 → 1 张(与此前恒为单张的行为一致)。夹一遍范围:
      // 服务端上限降下来的话,存档里那个 4 不该把新的限制绕过去。
      batchCount: ((e['batchCount'] as num?)?.toInt() ?? params.batchCount)
          .clamp(1, kBatchMax),
      hires: hires,
      modalMem: modalMem,
      // 老存档没这个键 → 下面 _migrateLegacyPositions 决定给 true 还是 false
      useCoords: e['useCoords'] as bool? ?? params.useCoords,
    );
  }

  final hadUseCoordsKey =
      j['params'] is Map && (j['params'] as Map).containsKey('useCoords');

  InpaintJob? inpaint;
  if (j['inpaint'] is Map) {
    final e = j['inpaint'] as Map;
    final image = await img(e['image']);
    final mask = await img(e['mask']);
    if (image != null && mask != null) {
      InpaintPaste? paste;
      if (e['paste'] is Map) {
        final pe = e['paste'] as Map;
        final original = await img(pe['original']);
        if (original != null) {
          paste = InpaintPaste(
            original: original,
            sendX: (pe['sendX'] as num?)?.toInt() ?? 0,
            sendY: (pe['sendY'] as num?)?.toInt() ?? 0,
            tightX: (pe['tightX'] as num?)?.toInt() ?? 0,
            tightY: (pe['tightY'] as num?)?.toInt() ?? 0,
            tightW: (pe['tightW'] as num?)?.toInt() ?? 0,
            tightH: (pe['tightH'] as num?)?.toInt() ?? 0,
            outW: (pe['outW'] as num?)?.toInt() ?? 0,
            outH: (pe['outH'] as num?)?.toInt() ?? 0,
          );
        }
      }
      inpaint = InpaintJob(
        image: image,
        mask: mask,
        strength: (e['strength'] as num?)?.toDouble() ?? 0.7,
        paste: paste,
        sourceId: e['sourceId'] as String?,
        grid: await img(e['grid']),
      );
    }
  }

  final openPanels = <Panel>{};
  if (j['openPanels'] is List) {
    for (final n in j['openPanels'] as List) {
      final p = _enumByName(Panel.values, n);
      if (p != null) openPanels.add(p);
    }
  }

  final migrated = _migrateLegacyPositions(
    characters,
    hadUseCoordsKey: hadUseCoordsKey,
  );
  if (migrated != null) {
    characters
      ..clear()
      ..addAll(migrated.characters);
    params = params.copyWith(useCoords: migrated.useCoords);
  }

  return GenerateState(
    prompt: j['prompt'] is String ? j['prompt'] as String : '',
    negativePrompt: j['negativePrompt'] is String
        ? j['negativePrompt'] as String
        : '',
    promptRaw: j['promptRaw'] is String ? j['promptRaw'] as String : '',
    negativePromptRaw: j['negativePromptRaw'] is String
        ? j['negativePromptRaw'] as String
        : '',
    characters: characters,
    vibes: vibes,
    charRefs: charRefs,
    img2img: img2img,
    params: params,
    anlas: (j['anlas'] as num?)?.toInt() ?? 0,
    openPanels: openPanels,
    loras: loras,
    kreaStyleRefs: kreaStyleRefs,
    kreaStyleRefWeight: (j['kreaStyleRefWeight'] as num?)?.toDouble() ?? 1.0,
    inpaint: inpaint,
  );
}

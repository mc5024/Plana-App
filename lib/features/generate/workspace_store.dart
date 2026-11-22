import '../../core/util/log.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/store/atomic_file.dart';
import '../../core/store/blob_store.dart';
import 'models.dart';
import 'canvas_models.dart';
import 'state_codec.dart';

/// 创作工作台持久化(`<support>/workspace/state.json`):提示词、角色、
/// Vibe/角色参考(图片走 blob 仓)、图生图、参数、面板开合——重启原样回来。
/// 写入防抖 800ms 吸收滑条/输入抖动;前后台切换由 AppStores.flushNow 即刻落盘。
///
/// 格式(v3):`state` 仍是整份创作状态(全局设置 + 当前画布的内容),旧版本只认它,
/// 装回旧包至少保住当前那套;各画布的内容另挂在 `canvases` 里,图片同样走 blob 仓,
/// 顶层 `refs` 是所有画布引用的并集。
/// 读得懂两种老格式:v1 只有 `state`(迁成「默认画布」);v2 是每张画布各存一整份
/// 状态、没有顶层 `state`(全局设置取当时那张当前画布的)。
class WorkspaceStore {
  WorkspaceStore(this._blobs, Directory supportRoot)
    : _file = File('${supportRoot.path}/workspace/state.json'),
      _presetsFile = File('${supportRoot.path}/prompt_presets.json');

  final BlobStore _blobs;
  final File _file;

  /// 预设库文件,只为读 1.1.1 用的那一档(见 [_legacyPresetId])。
  final File _presetsFile;

  /// 启动读出的整份创作状态;null = 首启/无存档。
  GenerateState? initial;

  /// 启动读出的画布集合;null = 首启/无存档(由调用方按 [initial] 建一张)。
  CanvasWorkspace? initialCanvases;

  /// GenerateNotifier 的 id 发号器续点(防重启后 id 撞车)。
  int idSeq = 100;

  static final _idNumRe = RegExp(r'^id(\d+)$');
  static final _canvasNumRe = RegExp(r'^canvas(\d+)$');

  /// 1.1.1 的提示词预设是全局一份,记在预设库文件的 `activeId` 里;那时的存档
  /// 没记用哪一档。升级上来按它补进画布,补完存一次,之后只认画布自己记的。
  Future<String?> _legacyPresetId() async {
    try {
      if (!await _presetsFile.exists()) return null;
      final j = jsonDecode(await _presetsFile.readAsString());
      return j is Map && j['activeId'] is String
          ? j['activeId'] as String
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString());
      if (j is! Map<String, dynamic>) return;
      idSeq = (j['idSeq'] as num?)?.toInt() ?? 100;
      final legacyPreset = await _legacyPresetId();
      // 有没有哪份没记预设、按 1.1.1 那一档补上的:补了就得存回去
      var presetFilled = false;
      bool lacksPreset(Object? m) => m is Map && m['promptPresetId'] is! String;
      if (lacksPreset(j['state'])) presetFilled = true;
      // 同一张图在几张画布里各读一次也只留一份字节
      final images = <String, Future<Uint8List?>>{};
      // 各画布引用的图一起开读,别一张张排着等
      if (j['refs'] is List) {
        for (final r in j['refs'] as List) {
          if (r is String && r.isNotEmpty) {
            images.putIfAbsent(r, () => _blobs.get(r));
          }
        }
      }
      var full = j['state'] is Map<String, dynamic>
          ? await decodeGenerateState(
              j['state'] as Map<String, dynamic>,
              _blobs,
              presetFallback: legacyPreset,
              images: images,
            )
          : null;
      final savedActive = j['activeCanvasId'] is String
          ? j['activeCanvasId'] as String
          : null;

      final canvases = <CanvasDraft>[];
      var nextId = (j['nextCanvasId'] as num?)?.toInt() ?? 2;
      // v2 没有顶层 state:全局设置取当前画布那一整份(找不到就取第一张)
      GenerateState? v2Active;
      GenerateState? v2First;
      if (j['canvases'] is List) {
        for (final raw in j['canvases'] as List) {
          if (raw is! Map<String, dynamic> ||
              raw['id'] is! String ||
              (raw['id'] as String).isEmpty ||
              canvases.any((c) => c.id == raw['id'])) {
            continue;
          }
          final id = raw['id'] as String;
          try {
            final CanvasPrompts prompts;
            if (raw['prompts'] is Map<String, dynamic>) {
              if (lacksPreset(raw['prompts'])) presetFilled = true;
              prompts = await _decodePrompts(
                raw['prompts'] as Map<String, dynamic>,
                globals: full,
                presetFallback: legacyPreset,
                images: images,
              );
            } else if (raw['state'] is Map<String, dynamic>) {
              if (lacksPreset(raw['state'])) presetFilled = true;
              final s = await decodeGenerateState(
                raw['state'] as Map<String, dynamic>,
                _blobs,
                presetFallback: legacyPreset,
                images: images,
              );
              v2First ??= s;
              if (id == savedActive) v2Active = s;
              prompts = CanvasPrompts.of(s);
            } else {
              continue;
            }
            final name = raw['name'] is String
                ? (raw['name'] as String).trim()
                : '';
            canvases.add(
              CanvasDraft(
                id: id,
                name: name.isEmpty ? '画布 ${canvases.length + 1}' : name,
                prompts: prompts,
              ),
            );
            final m = _canvasNumRe.firstMatch(id);
            if (m != null) {
              final n = int.parse(m.group(1)!) + 1;
              if (nextId < n) nextId = n;
            }
          } catch (e) {
            logd('[workspace] 跳过损坏画布: $e');
          }
        }
      }
      full ??= v2Active ?? v2First;

      if (canvases.isEmpty) {
        if (full == null) return;
        initial = full;
        initialCanvases = CanvasWorkspace.single(CanvasPrompts.of(full));
      } else {
        // 最上面那张是默认画布,名字固定(老存档里排第一的那张就此改叫默认画布)
        if (canvases.first.name != kDefaultCanvasName) {
          canvases[0] = canvases[0].copyWith(name: kDefaultCanvasName);
        }
        final activeId = canvases.any((c) => c.id == savedActive)
            ? savedActive!
            : canvases.first.id;
        final active = canvases.firstWhere((c) => c.id == activeId);
        if (full != null && activeId == savedActive) {
          // 当前画布以整份状态里的词为准(同一次写盘,正常两边一致)
          canvases[canvases.indexOf(active)] = active.copyWith(
            prompts: CanvasPrompts.of(full),
          );
        } else {
          // 记着的当前画布坏了 / 没有整份状态:全局设置照用,词换成落到的那张
          full = active.prompts.applyTo(full ?? GenerateState.initial());
        }
        // 出图参数是后来才跟画布走的:老存档里的画布一律接着用当时那份全局的
        final legacy = CanvasSampling.of(full.params);
        for (var i = 0; i < canvases.length; i++) {
          if (canvases[i].prompts.sampling == null) {
            canvases[i] = canvases[i].copyWith(
              prompts: canvases[i].prompts.withSampling(legacy),
            );
          }
        }
        initial = full;
        initialCanvases = CanvasWorkspace(
          canvases: canvases,
          activeId: activeId,
          nextId: nextId < 2 ? 2 : nextId,
        );
      }

      // 防抖窗口内被杀时 idSeq 可能落后于状态里的实际 id,取两者最大;
      // 所有画布都要算上,不能只看当前那张。
      for (final id in [
        for (final canvas in initialCanvases!.canvases) ...[
          for (final c in canvas.prompts.characters) c.id,
          for (final s in canvas.prompts.sections) s.id,
          for (final v in canvas.prompts.vibes) v.id,
          for (final r in canvas.prompts.charRefs) r.id,
          for (final r in canvas.prompts.kreaStyleRefs) r.id,
        ],
      ]) {
        final m = _idNumRe.firstMatch(id);
        if (m != null) {
          final n = int.parse(m.group(1)!) + 1;
          if (n > idSeq) idSeq = n;
        }
      }
      // 补过预设就存一次:预设库文件往后不再记那一档,不存下次就读不到了
      if (presetFilled && legacyPreset != null) {
        schedule(full, initialCanvases!, idSeq: idSeq);
      }
    } catch (e) {
      logd('[workspace] 载入失败(按首启处理): $e');
      initial = null;
      initialCanvases = null;
    }
  }

  GenerateState? _pending;
  CanvasWorkspace? _pendingCanvases;
  int _pendingSeq = 100;
  Timer? _timer;
  Future<void> _chain = Future.value();

  /// 状态一变就来这里排队;真正写盘在防抖窗口后。
  void schedule(
    GenerateState s,
    CanvasWorkspace canvases, {
    required int idSeq,
  }) {
    _pending = s;
    _pendingCanvases = canvases;
    _pendingSeq = idSeq;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), flush);
  }

  /// 立即把挂起的状态落盘(串行链,不与上一次写重叠)。
  void flush() {
    final s = _pending;
    final w = _pendingCanvases;
    if (s == null || w == null) return;
    _pending = null;
    _pendingCanvases = null;
    _timer?.cancel();
    final seq = _pendingSeq;
    _chain = _chain.then((_) async {
      try {
        final enc = await encodeGenerateState(s, _blobs);
        final refs = {...enc.refs};
        final canvases = <Map<String, dynamic>>[];
        for (final c in w.canvases) {
          final p = await _encodePrompts(c.prompts);
          refs.addAll(p.refs);
          canvases.add({'id': c.id, 'name': c.name, 'prompts': p.json});
        }
        // 原子写:落盘时机就是退后台,不能留半截 JSON(见 atomic_file.dart)
        await writeStringAtomic(
          _file,
          jsonEncode({
            'v': 3,
            'idSeq': seq,
            'refs': refs.toList(),
            'state': enc.json,
            'activeCanvasId': w.activeId,
            'nextCanvasId': w.nextId,
            'canvases': canvases,
          }),
        );
      } catch (e) {
        logd('[workspace] 保存失败: $e');
      }
    });
  }

  Future<void> get idle => _chain;

  /// 一张画布只存跟画布走的那几项。编解码借整份状态那一套(含老存档的站位
  /// 迁移,图片走 blob 仓),免得两种格式各走各的。
  static const _promptKeys = [
    'prompt',
    'negativePrompt',
    'promptRaw',
    'negativePromptRaw',
    'sections',
    'characters',
    'promptPresetId',
    'vibes',
    'charRefs',
    'kreaStyleRefs',
    'kreaStyleRefWeight',
    'loras',
    'loraMem',
    'img2img',
    'inpaint',
  ];

  /// 模型、尺寸、种子、采样参数和重绘放大借整份状态 params 里的同名键
  /// (含分档记忆)。
  static const _samplingKeys = [
    'model',
    'width',
    'height',
    'seed',
    'steps',
    'cfg',
    'varietyPlus',
    'sampler',
    'noiseSchedule',
    'cfgRescale',
    'animaSteps',
    'animaCfg',
    'animaSampler',
    'animaScheduler',
    'kreaSteps',
    'kreaCfg',
    'kreaSampler',
    'kreaScheduler',
    'modalMem',
    'hires',
  ];

  Future<EncodedState> _encodePrompts(CanvasPrompts p) async {
    final enc = await encodeGenerateState(
      p.applyTo(GenerateState.initial()),
      _blobs,
    );
    final params = enc.json['params'] as Map<String, dynamic>;
    return EncodedState({
      for (final k in _promptKeys)
        if (enc.json.containsKey(k)) k: enc.json[k],
      'useCoords': p.useCoords,
      'normalizeVibe': p.normalizeVibe,
      if (p.sampling != null)
        'sampling': {
          for (final k in _samplingKeys)
            if (params.containsKey(k)) k: params[k],
        },
    }, enc.refs);
  }

  /// 一张画布的内容编成存档里 `canvases[].prompts` 那一段(画布历史也存这个)。
  Future<EncodedState> encodeCanvas(CanvasPrompts p) => _encodePrompts(p);

  /// [encodeCanvas] 的反向。[withImages] 为 false 时不读图:参考图、底图与重绘
  /// 都是空的,只拿来看词和参数。
  Future<CanvasPrompts> decodeCanvas(
    Map<String, dynamic> j, {
    bool withImages = true,
  }) => _decodePrompts(
    withImages ? j : ({...j}..removeWhere((k, _) => _imageKeys.contains(k))),
  );

  static const _imageKeys = {
    'vibes',
    'charRefs',
    'kreaStyleRefs',
    'img2img',
    'inpaint',
  };

  /// [globals] 是同一份存档顶层的整份状态。比画布晚收进来的几项,那之前存下的
  /// 画布没有对应的键,一律接着用当时全局那份:尺寸和种子、重绘放大,以及参考图、
  /// LoRA、底图与重绘(这几项看 `vibes` 键;LoRA 换到这张画布的模型那个底模)。
  Future<CanvasPrompts> _decodePrompts(
    Map<String, dynamic> j, {
    GenerateState? globals,
    String? presetFallback,
    Map<String, Future<Uint8List?>>? images,
  }) async {
    final sampling = j['sampling'];
    final g = globals?.params;
    var s = await decodeGenerateState(
      {
        for (final k in _promptKeys)
          if (j.containsKey(k)) k: j[k],
        'params': {
          if (g != null) ...{
            'width': g.width,
            'height': g.height,
            'seed': g.seed,
          },
          if (sampling is Map<String, dynamic>) ...sampling,
          // 带上这个键,解码就不会把它当老存档去迁移站位
          'useCoords': j['useCoords'] == true,
          if (j['normalizeVibe'] is bool) 'normalizeVibe': j['normalizeVibe'],
        },
      },
      _blobs,
      presetFallback: presetFallback,
      images: images,
    );
    if (globals != null) {
      if (sampling is Map<String, dynamic> && sampling['hires'] is! Map) {
        s = s.copyWith(params: s.params.copyWith(hires: globals.params.hires));
      }
      if (!j.containsKey('vibes')) {
        // 没记模型的画布收尾时补成全局那个,LoRA 原样接着用
        final from = sampling is Map<String, dynamic>
            ? globals.withLoraBaseOf(s.params.model)
            : globals;
        s = s.copyWith(
          vibes: from.vibes,
          charRefs: from.charRefs,
          kreaStyleRefs: from.kreaStyleRefs,
          kreaStyleRefWeight: from.kreaStyleRefWeight,
          loras: from.loras,
          loraMem: from.loraMem,
          img2img: from.img2img,
          inpaint: from.inpaint,
          params: s.params.copyWith(
            normalizeVibe: globals.params.normalizeVibe,
          ),
        );
      }
    }
    final prompts = CanvasPrompts.of(s);
    // 没这块的是老存档:先空着,载入收尾时补成当时的全局参数
    return sampling is Map<String, dynamic>
        ? prompts
        : prompts.withSampling(null);
  }

  /// 盘上存档引用的 blob 哈希(启动 GC 的引用清单)。
  Future<Set<String>> liveRefs() async {
    try {
      if (!await _file.exists()) return {};
      final j = jsonDecode(await _file.readAsString());
      if (j is Map && j['refs'] is List) {
        return {
          for (final r in j['refs'] as List)
            if (r is String) r,
        };
      }
    } catch (_) {}
    return {};
  }
}

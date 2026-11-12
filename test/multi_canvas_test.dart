import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/auth/auth_mode.dart';
import 'package:plana_app/core/net/anlas_provider.dart';
import 'package:plana_app/core/net/nai_client.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/editor/editor_state.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/features/generate/canvas_history.dart';
import 'package:plana_app/features/generate/canvas_state.dart';
import 'package:plana_app/features/generate/gen_jobs.dart';
import 'package:plana_app/features/generate/gen_queue.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/features/generate/gen_modules.dart';
import 'package:plana_app/features/generate/generate_state.dart';
import 'package:plana_app/features/generate/generation_controller.dart';
import 'package:plana_app/features/generate/gpu_rental.dart';
import 'package:plana_app/features/generate/loop_controller.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/prompt_presets.dart';
import 'package:plana_app/features/generate/state_codec.dart';
import 'package:plana_app/features/generate/style_recipes.dart';
import 'package:plana_app/features/inspiration/tag_editor_page.dart';
import 'package:plana_app/features/inspiration/tag_library.dart';
import 'package:plana_app/features/inspiration/tag_models.dart'
    show StyleRecipe, TagCategory, TagEntry;
import 'package:plana_app/features/generate/widgets/canvas_history_sheet.dart';
import 'package:plana_app/features/generate/widgets/top_bar.dart';

class _TokenMode extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => AuthMode.token;
}

class _Balance extends AnlasNotifier {
  static int anlas = 1234;

  @override
  Future<NaiSubscription?> build() async => (
    anlas: anlas,
    fixedAnlas: anlas,
    purchasedAnlas: 0,
    isOpus: true,
    tier: 3,
    usage: (percent: 70.0, isNegative: false, secondsToNextPct: 0, accounts: 1),
  );

  @override
  Future<void> refresh() async {}
}

class _Rental extends GpuRentalNotifier {
  @override
  RentalState build() => const RentalState();

  void showRunning() => state = const RentalState(
    status: RentalStatus.ready,
    elapsedS: 90,
    price: .12,
  );
}

class _EmptyLibrary extends TagLibrary {
  @override
  Future<TagLibraryState> build() async => const TagLibraryState();
}

class _Presets extends PromptPresetsNotifier {
  @override
  Future<PromptPresetsState> build() async =>
      const PromptPresetsState(presets: kDefaultPromptPresets);
}

class _ControlledGeneration extends GenerationNotifier {
  final snapshots = <GenerateState?>[];
  final origins = <CanvasOrigin?>[];
  final replies = <Completer<GenOutcome>>[];
  @override
  GenPool build() => const GenPool();
  @override
  Future<int> concurrency() async => 1;
  @override
  Future<GenOutcome> generate({
    GallerySaveTarget? galleryTarget,
    GenerateState? using,
    bool stay = false,
    void Function(String)? onJob,
    CanvasOrigin? origin,
  }) {
    snapshots.add(using);
    origins.add(origin);
    final reply = Completer<GenOutcome>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStores stores;
  late ProviderContainer c;
  late CanvasWorkspaceNotifier canvases;
  late GenerateNotifier gen;
  late _ControlledGeneration generation;
  var widgetCase = false;

  void bind(AppStores next) {
    stores = next;
    generation = _ControlledGeneration();
    c = ProviderContainer(
      overrides: [
        appStoresProvider.overrideWithValue(stores),
        promptPresetsProvider.overrideWith(_Presets.new),
        generationProvider.overrideWith(() => generation),
        authModeProvider.overrideWith(_TokenMode.new),
        anlasProvider.overrideWith(_Balance.new),
        gpuRentalProvider.overrideWith(_Rental.new),
      ],
    );
    gen = c.read(generateProvider.notifier);
    canvases = c.read(canvasWorkspaceProvider.notifier);
  }

  setUp(() async {
    widgetCase = false;
    bind(AppStores.ephemeral());
    await c.read(promptPresetsProvider.future);
  });
  tearDown(() async {
    stores.flushNow();
    if (!widgetCase) await stores.workspace.idle;
    c.dispose();
  });

  test('切换换掉整组内容：词、出图参数和参考图', () {
    gen.setPrompts(
      positive: 'rain',
      negative: 'lowres',
      positiveRaw: 'rain, ~text~',
    );
    gen.addCharacter();
    gen.updateCharacter(
      c.read(generateProvider).characters.first.id,
      positive: 'blue hair',
    );
    gen.setUseCoords(true);
    gen.setSize(1024, 1024);
    gen.addVibe(image: Uint8List.fromList([1, 2, 3]), name: 'rain palette');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create(duplicate: true);
    expect(c.read(generateProvider).promptRaw, 'rain, ~text~');
    expect(c.read(generateProvider).characters.first.positive, 'blue hair');
    expect(c.read(generateProvider).params.useCoords, isTrue);
    gen.setPrompts(positive: 'sunset');
    gen.updateCharacter(
      c.read(generateProvider).characters.first.id,
      positive: 'red hair',
    );
    gen.setSize(832, 1216);
    canvases.select(a);
    expect(c.read(generateProvider).prompt, 'rain');
    expect(c.read(generateProvider).negativePrompt, 'lowres');
    expect(c.read(generateProvider).characters.first.positive, 'blue hair');
    // 尺寸和参考图都跟画布走,A 还是自己的
    expect(c.read(generateProvider).params.width, 1024);
    expect(c.read(generateProvider).vibes.single.name, 'rain palette');
    canvases.select(b);
    expect(c.read(generateProvider).prompt, 'sunset');
    expect(c.read(generateProvider).characters.first.positive, 'red hair');
    expect(c.read(generateProvider).vibes.single.name, 'rain palette');
    gen.removeVibe(c.read(generateProvider).vibes.single.id);
    gen.addCharRef(image: Uint8List.fromList([4, 5, 6]), name: 'b face');
    canvases.select(a);
    expect(c.read(generateProvider).vibes.single.name, 'rain palette');
    expect(c.read(generateProvider).charRefs, isEmpty);
    canvases.select(b);
    expect(c.read(generateProvider).vibes, isEmpty);
    expect(c.read(generateProvider).charRefs.single.name, 'b face');
    gen.setImg2ImgImage(
      image: Uint8List.fromList([7, 8, 9]),
      width: 832,
      height: 1216,
    );
    canvases.create();
    expect(c.read(generateProvider).prompt, isEmpty);
    expect(c.read(generateProvider).negativePrompt, isEmpty);
    expect(c.read(generateProvider).characters, isEmpty);
    expect(c.read(generateProvider).params.useCoords, isFalse);
    expect(c.read(generateProvider).vibes, isEmpty);
    expect(c.read(generateProvider).charRefs, isEmpty);
    expect(c.read(generateProvider).img2img, isNull);
    expect(c.read(generateProvider).params.width, 832);
    canvases.select(a);
    expect(c.read(generateProvider).params.useCoords, isTrue);
    expect(c.read(generateProvider).img2img, isNull);
    canvases.select(b);
    expect(c.read(generateProvider).img2img!.image, [7, 8, 9]);
  });

  test('新建空白画布沿用重绘放大、强度归一和风格参考强度,清空 LoRA;切画布各还各的', () {
    gen.setModel('Anima Turbo');
    gen.applyLoraSelection([const ActiveLora(name: 'x', displayName: 'X')]);
    gen.updateHires(enabled: true, scale: 1.8);
    gen.applyParams(
      c.read(generateProvider).params.copyWith(normalizeVibe: false),
    );
    gen.setKreaStyleRefWeight(0.4);
    final a = c.read(canvasWorkspaceProvider).activeId;
    canvases.create();
    final s = c.read(generateProvider);
    expect(s.loras, isEmpty);
    expect(s.params.hires.enabled, isTrue);
    expect(s.params.hires.scale, 1.8);
    expect(s.params.normalizeVibe, isFalse);
    expect(s.kreaStyleRefWeight, 0.4);
    gen.updateHires(enabled: false);
    canvases.select(a);
    expect(c.read(generateProvider).params.hires.enabled, isTrue);
    expect(c.read(generateProvider).loras.single.name, 'x');
  });

  test('复制的名字只挂一个「· 副本」，并守住长度上限', () {
    canvases.create(duplicate: true);
    expect(c.read(canvasWorkspaceProvider).active.name, '默认画布 · 副本');
    canvases.create(duplicate: true);
    expect(c.read(canvasWorkspaceProvider).active.name, '默认画布 · 副本');
    canvases.rename(c.read(canvasWorkspaceProvider).activeId, 'x' * 40);
    expect(
      c.read(canvasWorkspaceProvider).active.name,
      hasLength(kCanvasNameMax),
    );
    canvases.create(duplicate: true);
    final copied = c.read(canvasWorkspaceProvider).active.name;
    expect(copied.length, lessThanOrEqualTo(kCanvasNameMax));
    expect(copied, endsWith(' · 副本'));
  });

  test('按画布 id 改词：当前画布走创作状态，别的画布只改它那份', () {
    gen.setPrompts(positive: 'rain');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    gen.setPrompts(positive: 'forest');
    canvases.updatePrompts(a, (p) => p.copyWith(prompt: 'rain, moon'));
    expect(c.read(generateProvider).prompt, 'forest');
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.prompt,
      'rain, moon',
    );
    canvases.updatePrompts(b, (p) => p.copyWith(prompt: 'forest, lake'));
    expect(c.read(generateProvider).prompt, 'forest, lake');
    canvases.select(a);
    expect(c.read(generateProvider).prompt, 'rain, moon');
  });

  test('撤销导入：全局设置整份放回，词还给导入时那张画布', () {
    gen.setPrompts(positive: 'rain');
    gen.setSize(832, 1216);
    final a = c.read(canvasWorkspaceProvider).activeId;
    // 没切画布:撤销后整份回到导入前
    var before = c.read(generateProvider);
    gen.setPrompts(positive: 'imported');
    gen.setSize(640, 640);
    gen.addVibe(image: Uint8List.fromList([1, 2, 3]), name: 'imported vibe');
    canvases.undoWrite(before, a);
    expect(c.read(generateProvider).prompt, 'rain');
    expect(c.read(generateProvider).params.width, 832);
    expect(c.read(generateProvider).vibes, isEmpty);
    // 撤销条挂着时切去了别的画布:全局设置回滚,当前画布的词和参数不动,A 的还回 A
    before = c.read(generateProvider);
    gen.setPrompts(positive: 'imported');
    gen.setSize(640, 640);
    canvases.create();
    gen.setPrompts(positive: 'forest');
    canvases.undoWrite(before, a);
    expect(c.read(generateProvider).prompt, 'forest');
    expect(c.read(generateProvider).params.width, 640);
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.sampling!.width,
      832,
    );
    expect(c.read(canvasWorkspaceProvider).find(a)!.prompts.prompt, 'rain');
  });

  test('出图参数跟画布走：模型、尺寸、种子、采样；新建沿用当前那份', () {
    GenParams params() => c.read(generateProvider).params;
    gen.applyParams(
      params().copyWith(steps: 20, cfg: 4, sampler: 'k_dpmpp_2m', seed: '7'),
    );
    gen.setSize(1024, 1024);
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    expect(params().steps, 20, reason: '新画布沿用当前的出图参数');
    expect(params().width, 1024);
    expect(params().seed, '7');
    gen.setModel('NAI 4.0 Full');
    gen.applyParams(params().copyWith(steps: 40, cfg: 7, seed: '123'));
    gen.setSize(640, 640);
    canvases.select(a);
    expect(params().model, 'NAI 4.5 Full');
    expect(params().steps, 20);
    expect(params().cfg, 4);
    expect(params().sampler, 'k_dpmpp_2m');
    expect(params().seed, '7');
    expect(params().width, 1024);
    canvases.select(b);
    expect(params().model, 'NAI 4.0 Full');
    expect(params().steps, 40);
    expect(params().cfg, 7);
    expect(params().seed, '123');
    expect(params().width, 640);
  });

  test('模型跟画布走：切画布连模型和采样参数一起换', () {
    GenParams params() => c.read(generateProvider).params;
    gen.setModel('Anima Turbo');
    gen.applyParams(params().copyWith(animaSteps: 10));
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    expect(params().model, 'Anima Turbo', reason: '新画布沿用当前模型');
    gen.setModel('Anima Aesthetic');
    expect(params().animaSteps, animaTierDefaults('aesthetic').steps);
    gen.applyParams(params().copyWith(animaSteps: 30));
    canvases.select(a);
    expect(params().model, 'Anima Turbo');
    expect(params().animaSteps, 10);
    canvases.select(b);
    expect(params().model, 'Anima Aesthetic');
    expect(params().animaSteps, 30);
  });

  test('LoRA 跟画布走,同一张画布进出 Krea 按底模各记一份', () {
    const x = ActiveLora(name: 'x', displayName: 'X');
    const y = ActiveLora(name: 'y', displayName: 'Y');
    const z = ActiveLora(name: 'z', displayName: 'Z');
    gen.setModel('Anima Turbo');
    gen.applyLoraSelection([x]);
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    expect(c.read(generateProvider).loras, isEmpty, reason: '空白画布不挂');
    gen.applyLoraSelection([z]);
    gen.setModel('Krea 2 Turbo');
    expect(c.read(generateProvider).loras, isEmpty, reason: 'Krea 不挂 Anima 的');
    gen.applyLoraSelection([y]);
    canvases.select(a);
    expect(c.read(generateProvider).loras.map((l) => l.name), ['x']);
    canvases.select(b);
    expect(c.read(generateProvider).loras.map((l) => l.name), ['y']);
    // 手动切模型进出 Krea 也一样,不清空
    gen.setModel('Anima Base');
    expect(c.read(generateProvider).loras.map((l) => l.name), ['z']);
    gen.setModel('Krea 2 Raw');
    expect(c.read(generateProvider).loras.map((l) => l.name), ['y']);
  });

  // 存入重绘不动主分辨率;发送时宽高是重绘那块的,不然底图、遮罩和声明的尺寸
  // 对不上。重绘跟画布走,新画布没有。
  test('挂着重绘时按重绘那块的尺寸发,主分辨率不动', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 64, height: 128)),
    );
    (int, int) sent() {
      final p = stripHiddenModules(
        c.read(generateProvider),
        const GenModuleSettings(),
      ).params;
      return (p.width, p.height);
    }

    gen.setSize(1024, 1024);
    gen.setInpaint(InpaintJob(image: png, mask: png, strength: 0.7));
    expect(sent(), (64, 128));
    final main = c.read(generateProvider).params;
    expect((main.width, main.height), (1024, 1024));
    gen.setSize(832, 1216);
    expect(sent(), (64, 128));
    final a = c.read(canvasWorkspaceProvider).activeId;
    canvases.create();
    expect(c.read(generateProvider).inpaint, isNull);
    expect(sent(), (832, 1216));
    canvases.select(a);
    expect(c.read(generateProvider).inpaint, isNotNull);
    gen.clearInpaint();
    expect(sent(), (832, 1216));
  });

  test('改重绘强度:涂抹网格与图库 id 不丢', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 64, height: 64)),
    );
    final grid = Uint8List.fromList([1, 2, 3]);
    gen.setInpaint(
      InpaintJob(
        image: png,
        mask: png,
        strength: 1,
        sourceId: 'g1',
        grid: grid,
      ),
    );
    gen.updateInpaintStrength(0.5);
    final job = c.read(generateProvider).inpaint!;
    expect(job.strength, 0.5);
    expect(job.sourceId, 'g1');
    expect(job.grid, grid);
  });

  test('下载途中切走了底模：占位条在收起来的那份里转正', () {
    gen.setModel('Anima Turbo');
    gen.applyLoraSelection([
      const ActiveLora(
        name: 'pending-1',
        displayName: 'P',
        pending: LoraPending(versionId: 1),
      ),
    ]);
    gen.setModel('Krea 2 Turbo');
    final promoted = gen.promotePendingLora(
      'pending-1',
      const ActiveLora(name: 'real', displayName: 'Real'),
    );
    expect(promoted, isTrue);
    expect(c.read(generateProvider).loras, isEmpty);
    gen.setModel('Anima Turbo');
    expect(c.read(generateProvider).loras.single.name, 'real');
  });

  test('下载途中切走了画布：每张画布里的占位条都转正,当前画布不动', () {
    const pending = ActiveLora(
      name: 'pending-2',
      displayName: 'P',
      weight: .6,
      pending: LoraPending(versionId: 2),
    );
    gen.setModel('Anima Turbo');
    gen.applyLoraSelection([pending]);
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create(duplicate: true);
    gen.setModel('Krea 2 Turbo'); // 复制出来的这张把占位条收进了 loraMem
    canvases.create();
    gen.setModel('Anima Turbo');
    gen.applyLoraSelection([const ActiveLora(name: 'x', displayName: 'X')]);
    final promoted = gen.promotePendingLora(
      'pending-2',
      const ActiveLora(name: 'real', displayName: 'Real'),
    );
    expect(promoted, isTrue);
    expect(c.read(generateProvider).loras.single.name, 'x');
    CanvasPrompts at(String id) =>
        c.read(canvasWorkspaceProvider).find(id)!.prompts;
    expect(at(a).loras.single.name, 'real');
    expect(at(a).loras.single.weight, .6);
    expect(at(b).loraMem['anima']!.single.name, 'real');
    expect(
      gen.promotePendingLora(
        'pending-2',
        const ActiveLora(name: 'real', displayName: 'Real'),
      ),
      isFalse,
    );
  });

  test('收起来的 LoRA 随存档保存', () async {
    gen.setModel('Anima Turbo');
    gen.applyLoraSelection([const ActiveLora(name: 'x', displayName: 'X')]);
    gen.setModel('Krea 2 Turbo');
    final enc = await encodeGenerateState(
      c.read(generateProvider),
      stores.blobs,
    );
    final back = await decodeGenerateState(
      jsonDecode(jsonEncode(enc.json)) as Map<String, dynamic>,
      stores.blobs,
    );
    expect(back.loras, isEmpty);
    expect(back.loraMem['anima']!.single.name, 'x');
  });

  test('撤销导入也把采样参数还给原画布，不动别的画布', () {
    GenParams params() => c.read(generateProvider).params;
    gen.applyParams(params().copyWith(steps: 23));
    final a = c.read(canvasWorkspaceProvider).activeId;
    final before = c.read(generateProvider);
    gen.applyParams(params().copyWith(steps: 50));
    canvases.create();
    gen.applyParams(params().copyWith(steps: 12));
    canvases.undoWrite(before, a);
    expect(params().steps, 12);
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.sampling!.steps,
      23,
    );
  });

  test('套用画风推荐参数：只改发起导入的那张画布，可撤销', () {
    GenParams params() => c.read(generateProvider).params;
    gen.applyParams(params().copyWith(steps: 23, cfg: 5));
    final a = c.read(canvasWorkspaceProvider).activeId;
    canvases.create();
    gen.applyParams(params().copyWith(steps: 12));
    const r = StyleRecipe(
      model: 'v4.5-full',
      steps: 40,
      cfg: 7,
      sampler: 'Euler',
      scheduler: 'karras',
    );
    // 提示条挂着时已经切到别的画布:照样写回发起的那张,当前这张不动
    final before = canvases.updateSampling(a, (p) => withRecipe(p, r))!;
    expect(params().steps, 12);
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.sampling!.steps,
      40,
    );
    canvases.updatePrompts(a, (p) => p.copyWith(sampling: before));
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.sampling!.steps,
      23,
    );
    // 套到当前画布:界面跟着变
    canvases.select(a);
    final before2 = canvases.updateSampling(a, (p) => withRecipe(p, r))!;
    expect(params().steps, 40);
    expect(params().cfg, 7);
    expect(before2.steps, 23);
  });

  test('预设选择随画布恢复；删除预设后安全回落', () async {
    final presets = c.read(promptPresetsProvider.notifier);
    await presets.setActive('light');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    await presets.setActive('none');
    expect(c.read(activePromptPresetIdProvider), 'none');
    canvases.select(a);
    expect(c.read(activePromptPresetIdProvider), 'light');
    canvases.select(b);
    expect(c.read(activePromptPresetIdProvider), 'none');
    gen.setPromptPreset('deleted-custom');
    expect(c.read(activePromptPresetIdProvider), 'none');
  });

  // 每张画布各存一份,没有「跟着全局走」:图库导入换了档,撤销得还回原来那档,
  // 别的画布也不跟着变。
  test('导入时换了预设:撤销连预设一起还原,别的画布不受影响', () async {
    final presets = c.read(promptPresetsProvider.notifier);
    final a = c.read(canvasWorkspaceProvider).activeId;
    expect(c.read(activePromptPresetIdProvider), kDefaultPromptPresetId);
    final b = canvases.create();
    await presets.setActive('none');
    canvases.select(a);
    final before = c.read(generateProvider); // 同图库导入:写入前先记下
    await presets.setActive('light');
    expect(c.read(activePromptPresetIdProvider), 'light');
    canvases.undoWrite(before, a);
    expect(c.read(activePromptPresetIdProvider), kDefaultPromptPresetId);
    canvases.select(b);
    expect(c.read(activePromptPresetIdProvider), 'none');
  });

  test('1.1.1 升级上来:存档没记预设,补成当时选的那一档并存回', () async {
    final root = Directory.systemTemp.createTempSync('plana_canvas_preset');
    final legacyStores = await AppStores.open(rootOverride: root);
    final encoded = await encodeGenerateState(
      GenerateState.initial().copyWith(prompt: 'legacy'),
      legacyStores.blobs,
    );
    final file = File('${root.path}/workspace/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'v': 1,
        'idSeq': 100,
        'state': {...encoded.json}..remove('promptPresetId'),
        'refs': encoded.refs.toList(),
      }),
    );
    // 1.1.1 的预设是全局一份,记在预设库文件里
    File(
      '${root.path}/prompt_presets.json',
    ).writeAsStringSync(jsonEncode({'activeId': 'light', 'custom': []}));

    final loaded = await AppStores.open(rootOverride: root);
    expect(loaded.workspace.initial!.promptPresetId, 'light');
    expect(
      loaded.workspace.initialCanvases!.active.prompts.promptPresetId,
      'light',
    );
    loaded.flushNow();
    await loaded.workspace.idle;
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect((saved['state'] as Map)['promptPresetId'], 'light');
    final canvas = (saved['canvases'] as List).single as Map;
    expect((canvas['prompts'] as Map)['promptPresetId'], 'light');
  });

  test('编辑防抖与撤销按画布分账；旧会话回写不覆盖当前画布', () async {
    gen.setPrompts(positive: 'rain');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final editor = c.read(editorProvider.notifier);
    editor.load(positive: 'rain', negative: '', startPositive: true);
    editor.editActive('rain, neon');
    final b = canvases.create();
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.prompt,
      'rain, neon',
    );
    // 模拟旧编辑会话的迟到回写。
    editor.editActive('rain, moon');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(c.read(generateProvider).prompt, isEmpty);
    expect(
      c.read(canvasWorkspaceProvider).find(a)!.prompts.prompt,
      'rain, moon',
    );
    editor.load(positive: '', negative: '', startPositive: true);
    expect(c.read(editorProvider).canUndo, isFalse);
    editor.editActive('forest');
    editor.undo();
    editor.flushWriteBack();
    expect(c.read(generateProvider).prompt, isEmpty);
    expect(c.read(canvasWorkspaceProvider).activeId, b);
    canvases.select(a);
    editor.load(positive: 'rain, moon', negative: '', startPositive: true);
    expect(c.read(editorProvider).canUndo, isTrue);
  });

  test('删除当前画布切到邻居；撤销放回原位并切回去；默认画布不可删除', () {
    gen.setPrompts(positive: 'original');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    canvases.rename(b, '  海边夕阳  ');
    gen.setPrompts(positive: 'sunset');
    final removed = canvases.remove(b)!;
    expect(removed.wasActive, isTrue);
    expect(c.read(generateProvider).prompt, 'original');
    expect(c.read(canvasWorkspaceProvider).activeId, a);
    expect(canvases.remove(a), isNull);
    canvases.restore(
      removed.canvas,
      removed.index,
      activate: removed.wasActive,
    );
    expect(c.read(canvasWorkspaceProvider).activeId, b);
    expect(c.read(generateProvider).prompt, 'sunset');
    expect(c.read(canvasWorkspaceProvider).active.name, '海边夕阳');
    expect(c.read(canvasWorkspaceProvider).canvases.map((d) => d.id), [a, b]);
  });

  test('重启恢复全部画布的词、当前选择、预设、参考图，以及全局设置', () async {
    c.dispose();
    final root = Directory.systemTemp.createTempSync('plana_canvas_restore');
    bind(await AppStores.open(rootOverride: root));
    await c.read(promptPresetsProvider.future);
    gen.setPrompts(positive: 'rain');
    gen.applyParams(c.read(generateProvider).params.copyWith(steps: 20));
    gen.addVibe(image: Uint8List.fromList([1, 2, 3]), name: 'A image');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    gen.setPrompts(positive: 'sunset');
    gen.applyParams(c.read(generateProvider).params.copyWith(steps: 40));
    gen.addVibe(image: Uint8List.fromList([4, 5, 6]), name: 'B image');
    gen.setSize(1024, 1024);
    await c.read(promptPresetsProvider.notifier).setActive('none');
    canvases.rename(b, '夕阳');
    stores.flushNow();
    await stores.workspace.idle;
    expect(await stores.workspace.liveRefs(), hasLength(2));
    final reloaded = await AppStores.open(rootOverride: root);
    final workspace = reloaded.workspace.initialCanvases!;
    expect(workspace.canvases, hasLength(2));
    expect(workspace.activeId, b);
    expect(workspace.active.name, '夕阳');
    expect(workspace.active.prompts.promptPresetId, 'none');
    expect(workspace.find(a)!.prompts.prompt, 'rain');
    expect(workspace.find(a)!.prompts.sampling!.steps, 20);
    final atA = workspace.find(a)!.prompts.vibes.single;
    expect(atA.name, 'A image');
    expect(atA.image, Uint8List.fromList([1, 2, 3]));
    final initial = reloaded.workspace.initial!;
    expect(initial.prompt, 'sunset');
    expect(initial.params.steps, 40);
    expect(initial.params.width, 1024);
    expect(initial.vibes.map((v) => v.name), ['B image']);
    expect(initial.vibes.single.image, Uint8List.fromList([4, 5, 6]));
  });

  test('几张画布用同一张图,载入后共用一份字节', () async {
    c.dispose();
    final root = Directory.systemTemp.createTempSync('plana_canvas_share');
    bind(await AppStores.open(rootOverride: root));
    await c.read(promptPresetsProvider.future);
    gen.addVibe(image: Uint8List.fromList([1, 2, 3]), name: 'shared');
    canvases.create(duplicate: true);
    canvases.create(duplicate: true);
    stores.flushNow();
    await stores.workspace.idle;
    expect(await stores.workspace.liveRefs(), hasLength(1));
    final w = (await AppStores.open(rootOverride: root)).workspace;
    final images = [
      for (final d in w.initialCanvases!.canvases) d.prompts.vibes.single.image,
    ];
    expect(images, hasLength(3));
    expect(identical(images[0], images[1]), isTrue);
    expect(identical(images[1], images[2]), isTrue);
    expect(identical(w.initial!.vibes.single.image, images[2]), isTrue);
  });

  test('拖动排序只动顺序：当前画布不变，重启后顺序还在', () async {
    c.dispose();
    final root = Directory.systemTemp.createTempSync('plana_canvas_order');
    bind(await AppStores.open(rootOverride: root));
    await c.read(promptPresetsProvider.future);
    List<String> order() => [
      for (final d in c.read(canvasWorkspaceProvider).canvases) d.id,
    ];
    final a = c.read(canvasWorkspaceProvider).activeId;
    final b = canvases.create();
    final d = canvases.create();
    final e = canvases.create();
    gen.setPrompts(positive: 'fourth');
    canvases.reorder(3, 1);
    expect(order(), [a, e, b, d]);
    expect(c.read(canvasWorkspaceProvider).activeId, e);
    expect(c.read(generateProvider).prompt, 'fourth');
    canvases.reorder(1, 3);
    expect(order(), [a, b, d, e]);
    canvases.reorder(2, 1);
    expect(order(), [a, d, b, e]);
    // 默认画布固定在最上面:它拖不动,别的也排不到它前面
    canvases.reorder(0, 2);
    canvases.reorder(2, 0);
    expect(order(), [a, d, b, e]);
    stores.flushNow();
    await stores.workspace.idle;
    final reloaded = await AppStores.open(rootOverride: root);
    expect(reloaded.workspace.initialCanvases!.canvases.map((x) => x.id), [
      a,
      d,
      b,
      e,
    ]);
  });

  test('默认画布删不掉、改不了名；别的画布都能删，撤销放回也排在默认画布后面', () {
    final a = c.read(canvasWorkspaceProvider).activeId;
    expect(c.read(canvasWorkspaceProvider).active.name, '默认画布');
    canvases.rename(a, '我的画布');
    expect(c.read(canvasWorkspaceProvider).active.name, '默认画布');
    final b = canvases.create();
    expect(c.read(canvasWorkspaceProvider).active.name, '画布 1');
    expect(canvases.remove(a), isNull);
    final removed = canvases.remove(b)!;
    expect(c.read(canvasWorkspaceProvider).canvases.map((d) => d.id), [a]);
    // 撤销时哪怕记着的位置是 0,也不会插到默认画布前面
    canvases.restore(removed.canvas, 0);
    expect(c.read(canvasWorkspaceProvider).canvases.map((d) => d.id), [a, b]);
    // 删掉的号下次还能用上
    canvases.remove(b);
    canvases.create();
    expect(c.read(canvasWorkspaceProvider).active.name, '画布 1');
  });

  test('存档顶层仍写整份状态：旧版本只认它也能拿回当前画布', () async {
    c.dispose();
    final root = Directory.systemTemp.createTempSync('plana_canvas_compat');
    bind(await AppStores.open(rootOverride: root));
    await c.read(promptPresetsProvider.future);
    gen.setPrompts(positive: 'rain');
    canvases.create();
    gen.setPrompts(positive: 'sunset');
    gen.setSize(1024, 1024);
    stores.flushNow();
    await stores.workspace.idle;
    final j =
        jsonDecode(File('${root.path}/workspace/state.json').readAsStringSync())
            as Map<String, dynamic>;
    final old = await decodeGenerateState(
      j['state'] as Map<String, dynamic>,
      stores.blobs,
    );
    expect(old.prompt, 'sunset');
    expect(old.params.width, 1024);
  });

  test('老存档里的画布没记采样参数：一律接着用当时的全局参数', () async {
    final root = Directory.systemTemp.createTempSync('plana_canvas_sampling');
    final blobs = (await AppStores.open(rootOverride: root)).blobs;
    final full = await encodeGenerateState(
      GenerateState.initial().copyWith(
        prompt: 'a-prompt',
        params: const GenParams().copyWith(steps: 33, cfg: 6),
      ),
      blobs,
    );
    final file = File('${root.path}/workspace/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'v': 3,
        'idSeq': 100,
        'refs': <String>[],
        'state': full.json,
        'activeCanvasId': 'canvas1',
        'nextCanvasId': 3,
        'canvases': [
          {
            'id': 'canvas1',
            'name': '人物',
            'prompts': {'prompt': 'a-prompt', 'useCoords': false},
          },
          {
            'id': 'canvas2',
            'name': '风景',
            'prompts': {'prompt': 'b-prompt', 'useCoords': false},
          },
        ],
      }),
    );
    final loaded = await AppStores.open(rootOverride: root);
    final w = loaded.workspace.initialCanvases!;
    for (final id in ['canvas1', 'canvas2']) {
      expect(w.find(id)!.prompts.sampling!.steps, 33);
      expect(w.find(id)!.prompts.sampling!.cfg, 6);
    }
    expect(w.find('canvas2')!.prompts.prompt, 'b-prompt');
    // 排第一的那张改叫默认画布,内容不动
    expect(w.canvases.first.name, '默认画布');
    expect(w.canvases.first.prompts.prompt, 'a-prompt');
  });

  test('上一版存档的画布记了模型和采样、没记尺寸种子：接着用当时全局那份', () async {
    final root = Directory.systemTemp.createTempSync('plana_canvas_size');
    final blobs = (await AppStores.open(rootOverride: root)).blobs;
    final full = await encodeGenerateState(
      GenerateState.initial().copyWith(
        params: const GenParams().copyWith(
          width: 1024,
          height: 1024,
          seed: '42',
        ),
      ),
      blobs,
    );
    final file = File('${root.path}/workspace/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'v': 3,
        'idSeq': 100,
        'refs': <String>[],
        'state': full.json,
        'activeCanvasId': 'canvas1',
        'nextCanvasId': 3,
        'canvases': [
          {
            'id': 'canvas1',
            'name': '默认画布',
            'prompts': {
              'prompt': 'a',
              'useCoords': false,
              'sampling': {'model': 'NAI 4.5 Full', 'steps': 28},
            },
          },
          {
            'id': 'canvas2',
            'name': '画布 1',
            'prompts': {
              'prompt': 'b',
              'useCoords': false,
              'sampling': {'model': 'NAI 4.0 Full', 'steps': 33},
            },
          },
        ],
      }),
    );
    final loaded = await AppStores.open(rootOverride: root);
    final s = loaded.workspace.initialCanvases!.find('canvas2')!.prompts;
    expect(s.sampling!.model, 'NAI 4.0 Full');
    expect(s.sampling!.steps, 33);
    expect(s.sampling!.width, 1024);
    expect(s.sampling!.seed, '42');
  });

  test('参考图收进画布之前的存档：每张画布都补成当时全局那份,LoRA 按各自底模', () async {
    final root = Directory.systemTemp.createTempSync('plana_canvas_refs');
    final blobs = (await AppStores.open(rootOverride: root)).blobs;
    final full = await encodeGenerateState(
      GenerateState.initial().copyWith(
        vibes: [
          VibeItem(id: 'id120', name: 'v', image: Uint8List.fromList([1, 2])),
        ],
        charRefs: [
          CharRefItem(id: 'id121', name: 'r', image: Uint8List.fromList([3])),
        ],
        img2img: Img2ImgConfig(image: Uint8List.fromList([4])),
        loras: const [ActiveLora(name: 'x', displayName: 'X')],
        loraMem: const {
          'krea': [ActiveLora(name: 'k', displayName: 'K')],
        },
        kreaStyleRefWeight: .3,
        params: const GenParams().copyWith(
          model: 'Anima Turbo',
          normalizeVibe: false,
          hires: const HiresConfig(enabled: true, scale: 1.7),
        ),
      ),
      blobs,
    );
    final file = File('${root.path}/workspace/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'v': 3,
        'idSeq': 100,
        'refs': full.refs.toList(),
        'state': full.json,
        'activeCanvasId': 'canvas1',
        'nextCanvasId': 3,
        'canvases': [
          {
            'id': 'canvas1',
            'name': '默认画布',
            'prompts': {
              'prompt': 'a',
              'useCoords': false,
              'sampling': {'model': 'Anima Turbo'},
            },
          },
          {
            'id': 'canvas2',
            'name': '画布 1',
            'prompts': {
              'prompt': 'b',
              'useCoords': false,
              'sampling': {'model': 'Krea 2 Turbo'},
            },
          },
        ],
      }),
    );
    final loaded = await AppStores.open(rootOverride: root);
    final w = loaded.workspace.initialCanvases!;
    final a = w.find('canvas1')!.prompts;
    final b = w.find('canvas2')!.prompts;
    for (final p in [a, b]) {
      expect(p.vibes.single.image, [1, 2]);
      expect(p.charRefs.single.name, 'r');
      expect(p.img2img!.image, [4]);
      expect(p.kreaStyleRefWeight, .3);
      expect(p.normalizeVibe, isFalse);
      expect(p.sampling!.hires.scale, 1.7);
    }
    expect(identical(a.vibes.single.image, b.vibes.single.image), isTrue);
    expect(a.loras.single.name, 'x');
    expect(b.loras.single.name, 'k');
    expect(b.loraMem['anima']!.single.name, 'x');
    expect(loaded.workspace.idSeq, 122);
  });

  test('v1 单工作台无损迁移，恢复角色 id 发号器', () async {
    final root = Directory.systemTemp.createTempSync('plana_canvas_migrate');
    final legacyStores = await AppStores.open(rootOverride: root);
    final old = GenerateState.initial().copyWith(
      prompt: 'legacy',
      characters: [
        const CharacterPrompt(
          id: 'id999',
          name: 'old character',
          positive: 'silver hair',
        ),
      ],
    );
    final encoded = await encodeGenerateState(old, legacyStores.blobs);
    final file = File('${root.path}/workspace/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'v': 1,
        'idSeq': 100,
        'state': encoded.json,
        'refs': encoded.refs.toList(),
      }),
    );
    final loaded = await AppStores.open(rootOverride: root);
    expect(loaded.workspace.initialCanvases!.active.name, '默认画布');
    expect(
      loaded.workspace.initialCanvases!.active.prompts.characters.single.id,
      'id999',
    );
    expect(loaded.workspace.initial!.prompt, 'legacy');
    expect(loaded.workspace.idSeq, 1000);
  });

  test('v2 过渡存档：各画布留下词和角色，全局设置取当时的当前画布', () async {
    final root = Directory.systemTemp.createTempSync('plana_canvas_v2');
    final blobs = (await AppStores.open(rootOverride: root)).blobs;
    final a = await encodeGenerateState(
      GenerateState.initial().copyWith(
        prompt: 'a-prompt',
        characters: [
          const CharacterPrompt(
            id: 'id150',
            name: 'A girl',
            positive: 'silver hair',
          ),
        ],
        params: const GenParams().copyWith(width: 1024, height: 1024),
      ),
      blobs,
    );
    final b = await encodeGenerateState(
      GenerateState.initial().copyWith(
        prompt: 'b-prompt',
        params: const GenParams().copyWith(width: 832, height: 1216),
      ),
      blobs,
    );
    final file = File('${root.path}/workspace/state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'v': 2,
        'idSeq': 100,
        'refs': <String>[],
        'activeCanvasId': 'canvas2',
        'nextCanvasId': 3,
        'canvases': [
          {'id': 'canvas1', 'name': '人物', 'state': a.json},
          {'id': 'canvas2', 'name': '风景', 'state': b.json},
        ],
      }),
    );
    final loaded = await AppStores.open(rootOverride: root);
    final w = loaded.workspace.initialCanvases!;
    // 排第一的那张载入时改叫默认画布(内容不动)
    expect(w.canvases.map((d) => d.name), ['默认画布', '风景']);
    expect(w.activeId, 'canvas2');
    expect(w.nextId, 3);
    expect(w.find('canvas1')!.prompts.prompt, 'a-prompt');
    expect(
      w.find('canvas1')!.prompts.characters.single.positive,
      'silver hair',
    );
    expect(loaded.workspace.initial!.prompt, 'b-prompt');
    expect(loaded.workspace.initial!.params.width, 832);
    expect(loaded.workspace.idSeq, 151);
  });

  Future<void> dispatched(int count) async {
    for (var i = 0; i < 100 && generation.replies.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(generation.replies.length, count);
  }

  test('队列消费入队时的快照，切换后不读取新画布的词或预设', () async {
    gen.setPrompts(positive: 'rain');
    await c.read(promptPresetsProvider.notifier).setActive('light');
    final queue = c.read(genQueueProvider.notifier);
    queue.enqueue();
    canvases.create();
    gen.setPrompts(positive: 'forest');
    await c.read(promptPresetsProvider.notifier).setActive('none');
    final running = queue.maybeStart();
    await dispatched(1);
    expect(generation.snapshots.single!.prompt, 'rain');
    expect(generation.snapshots.single!.promptPresetId, 'light');
    generation.replies.single.complete(GenOutcome.ok);
    await running;
  });

  test('循环续张读来源画布的词和出图参数；来源画布删了就用它最后那组', () async {
    // 从一张普通画布发起(默认画布删不掉,测不到「来源被删」)
    final a = canvases.create();
    gen.setPrompts(positive: 'rain');
    gen.applyParams(c.read(generateProvider).params.copyWith(steps: 20));
    gen.setSize(1024, 1024);
    gen.addVibe(image: Uint8List.fromList([1, 2, 3]), name: 'rain vibe');
    gen.setLoop(LoopCount.x4);
    final running = c.read(loopStatusProvider.notifier).start();
    await dispatched(1);
    expect(generation.snapshots[0]!.prompt, 'rain');
    canvases.create();
    gen.setPrompts(positive: 'forest');
    gen.addVibe(image: Uint8List.fromList([4, 5, 6]), name: 'forest vibe');
    gen.applyParams(c.read(generateProvider).params.copyWith(steps: 40));
    gen.setSize(640, 640);
    generation.replies[0].complete(GenOutcome.ok);
    await dispatched(2);
    expect(generation.snapshots[1]!.prompt, 'rain');
    expect(generation.snapshots[1]!.vibes.single.name, 'rain vibe');
    expect(generation.snapshots[1]!.params.steps, 20);
    expect(generation.snapshots[1]!.params.width, 1024);
    canvases.updatePrompts(a, (p) => p.copyWith(prompt: 'rain, moon'));
    generation.replies[1].complete(GenOutcome.ok);
    await dispatched(3);
    expect(generation.snapshots[2]!.prompt, 'rain, moon');
    expect(canvases.remove(a), isNotNull);
    generation.replies[2].complete(GenOutcome.ok);
    await dispatched(4);
    expect(generation.snapshots[3]!.prompt, 'rain, moon');
    generation.replies[3].complete(GenOutcome.ok);
    await running;
    expect(c.read(generateProvider).prompt, 'forest');
  });

  test('画布历史:同样内容连着出图只算一条,图追加在前;每张画布最多 50 条', () async {
    final history = stores.history;
    final a = c.read(canvasWorkspaceProvider).activeId;
    gen.setPrompts(positive: 'rain');
    await history.record(a, CanvasPrompts.of(c.read(generateProvider)), ['g1']);
    await history.record(a, CanvasPrompts.of(c.read(generateProvider)), [
      'g2',
      'g3',
    ]);
    var list = await history.load(a);
    expect(list, hasLength(1));
    expect(list.single.resultIds, ['g2', 'g3', 'g1']);
    for (var i = 4; i <= 6; i++) {
      await history.record(a, CanvasPrompts.of(c.read(generateProvider)), [
        'g$i',
      ]);
    }
    list = await history.load(a);
    expect(list.single.resultIds, hasLength(CanvasHistoryStore.maxResults));
    expect(list.single.resultIds.first, 'g6');
    gen.setPrompts(positive: 'rain, moon');
    await history.record(a, CanvasPrompts.of(c.read(generateProvider)), ['x']);
    list = await history.load(a);
    expect(list.map((e) => e.preview.prompt), ['rain, moon', 'rain']);
    for (var i = 0; i < 60; i++) {
      gen.setPrompts(positive: 'tag$i');
      await history.record(a, CanvasPrompts.of(c.read(generateProvider)), [
        'n$i',
      ]);
    }
    list = await history.load(a);
    expect(list, hasLength(CanvasHistoryStore.cap));
    expect(list.first.preview.prompt, 'tag59');
    // 别的画布各记各的
    final b = canvases.create();
    expect(await history.load(b), isEmpty);
  });

  test('画布历史随重启保留,引用的图计入 GC;删掉的画布启动时清掉', () async {
    c.dispose();
    final root = Directory.systemTemp.createTempSync('plana_canvas_history');
    bind(await AppStores.open(rootOverride: root));
    await c.read(promptPresetsProvider.future);
    final a = c.read(canvasWorkspaceProvider).activeId;
    gen.setPrompts(positive: 'rain');
    gen.addVibe(image: Uint8List.fromList([9, 9, 9]), name: 'v');
    await stores.history.record(a, CanvasPrompts.of(c.read(generateProvider)), [
      'g1',
    ]);
    final b = canvases.create();
    await stores.history.record(b, CanvasPrompts.of(c.read(generateProvider)), [
      'g2',
    ]);
    gen.removeVibe(c.read(generateProvider).vibes.firstOrNull?.id ?? '');
    canvases.select(a);
    gen.removeVibe(c.read(generateProvider).vibes.single.id);
    stores.flushNow();
    await stores.workspace.idle;
    expect(await stores.workspace.liveRefs(), isEmpty);
    expect(await stores.history.liveRefs(), hasLength(1));
    canvases.remove(b);
    stores.flushNow();
    await stores.workspace.idle;
    final reloaded = await AppStores.open(rootOverride: root);
    final entry = (await reloaded.history.load(a)).single;
    expect(entry.preview.prompt, 'rain');
    expect(entry.countOf('vibes'), 1);
    final back = await reloaded.workspace.decodeCanvas(entry.json);
    expect(back.vibes.single.image, [9, 9, 9]);
    await reloaded.history.removeOrphans({
      for (final d in reloaded.workspace.initialCanvases!.canvases) d.id,
    }, DateTime.now().add(const Duration(seconds: 1)));
    expect(await reloaded.history.load(a), hasLength(1));
    expect(
      File('${root.path}/workspace/history/$b.json').existsSync(),
      isFalse,
    );
  });

  test('恢复历史整组换回、可撤销;复制成新画布不动原画布', () async {
    final a = c.read(canvasWorkspaceProvider).activeId;
    gen.setPrompts(positive: 'rain');
    gen.addVibe(image: Uint8List.fromList([1]), name: 'v');
    final old = CanvasPrompts.of(c.read(generateProvider));
    gen.setPrompts(positive: 'forest');
    gen.removeVibe(c.read(generateProvider).vibes.single.id);
    final before = canvases.replace(a, old)!;
    expect(c.read(generateProvider).prompt, 'rain');
    expect(c.read(generateProvider).vibes.single.name, 'v');
    canvases.replace(a, before);
    expect(c.read(generateProvider).prompt, 'forest');
    expect(c.read(generateProvider).vibes, isEmpty);
    final copy = canvases.createFrom(old, from: '默认画布');
    expect(c.read(canvasWorkspaceProvider).activeId, copy);
    expect(c.read(canvasWorkspaceProvider).active.name, '默认画布 · 副本');
    expect(c.read(generateProvider).prompt, 'rain');
    expect(c.read(canvasWorkspaceProvider).find(a)!.prompts.prompt, 'forest');
  });

  test('出图带上发起的画布:队列记入队时那张,循环记来源画布', () async {
    gen.setPrompts(positive: 'rain');
    final a = c.read(canvasWorkspaceProvider).activeId;
    final queue = c.read(genQueueProvider.notifier);
    queue.enqueue();
    canvases.create();
    gen.setPrompts(positive: 'forest');
    final running = queue.maybeStart();
    await dispatched(1);
    expect(generation.origins.single!.canvasId, a);
    expect(generation.origins.single!.content.prompt, 'rain');
    generation.replies.single.complete(GenOutcome.ok);
    await running;
  });

  test('历史一行的改动摘要和时间', () {
    CanvasHistoryEntry entry(CanvasPrompts p, {int vibes = 0}) =>
        CanvasHistoryEntry(
          id: 'h',
          at: 0,
          json: {'vibes': List.filled(vibes, {})},
          preview: p,
          resultIds: const [],
          refs: const [],
        );
    final base = CanvasPrompts.of(
      GenerateState.initial().copyWith(prompt: 'a, b, c'),
    );
    final next = CanvasPrompts.of(
      GenerateState.initial().copyWith(
        prompt: 'a, b, d, e',
        params: const GenParams().copyWith(steps: 23),
      ),
    );
    expect(
      historyChanges(entry(base), entry(next, vibes: 1)),
      '+2 −1 · Vibe 0→1 · 28→23 步',
    );
    expect(historyChanges(entry(base), entry(base)), '参数有改动');
    final now = DateTime(2026, 10, 24, 15);
    int at(DateTime t) => t.millisecondsSinceEpoch;
    expect(
      historyTimeLabel(at(DateTime(2026, 10, 24, 9, 5)), now: now),
      '09:05',
    );
    expect(
      historyTimeLabel(at(DateTime(2026, 10, 23, 21, 30)), now: now),
      '昨天 21:30',
    );
    expect(
      historyTimeLabel(at(DateTime(2026, 10, 3, 8, 0)), now: now),
      '10月3日 08:00',
    );
  });

  Future<void> pumpHeader(
    WidgetTester tester, {
    double textScale = 1,
    double width = 320,
  }) async {
    widgetCase = true;
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(
            body: Column(
              children: [
                GenerateTopBar(),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('320px 融合顶栏可以展开、新建、切换、改名和删除撤销', (tester) async {
    await pumpHeader(tester);
    expect(tester.getSize(find.byType(GenerateTopBar)).height, lessThan(80));
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建画布'));
    await tester.pumpAndSettle();
    expect(c.read(canvasWorkspaceProvider).canvases, hasLength(2));
    expect(find.text('画布 1'), findsOneWidget);
    expect(find.text('默认画布'), findsNothing);
    // 普通画布:长按顶栏的名字改名
    await tester.longPress(find.text('画布 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '雨夜街景');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('雨夜街景'), findsOneWidget);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认画布'));
    await tester.pumpAndSettle();
    expect(c.read(canvasWorkspaceProvider).activeId, 'canvas1');
    // 默认画布名字固定:长按不弹改名
    await tester.longPress(find.text('默认画布'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    expect(find.text('画布'), findsOneWidget);
    // 画布少时弹层随内容高，不撑到七成屏
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(740 * .6));
    // 改名、删除直接摆在行上;默认画布那行两样都没有,只有图钉
    expect(find.byTooltip('重命名'), findsOneWidget);
    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '海边');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(c.read(canvasWorkspaceProvider).find('canvas2')!.name, '海边');
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(c.read(canvasWorkspaceProvider).canvases, hasLength(1));
    // 只剩默认画布：没有删除键也没有改名键，删除位是图钉
    expect(find.byTooltip('删除'), findsNothing);
    expect(find.byTooltip('重命名'), findsNothing);
    expect(find.byTooltip('默认画布，固定在最上面，不能删除或改名'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(c.read(canvasWorkspaceProvider).canvases, hasLength(2));
    expect(find.byTooltip('删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('卡片三行各一行：主提示词、角色名字（多于三个报剩余数）、模型与参数', (tester) async {
    gen.setPrompts(positive: 'rain, neon lights');
    for (var i = 0; i < 5; i++) {
      gen.addCharacter();
    }
    final chars = c.read(generateProvider).characters;
    gen.updateCharacter(chars[0].id, positive: 'silver hair');
    gen.updateCharacter(chars[1].id, name: '雨夜少女');
    canvases.create(duplicate: true);
    gen.replaceCharacters(const []);
    gen.applyParams(c.read(generateProvider).params.copyWith(steps: 23));
    await pumpHeader(tester);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    expect(find.text('rain, neon lights'), findsNWidgets(2));
    // 角色只列名字,不带提示词
    expect(find.text('角色 1'), findsOneWidget);
    expect(find.text('雨夜少女'), findsOneWidget);
    expect(find.text('silver hair'), findsNothing);
    expect(find.text(' +2'), findsOneWidget);
    // 没角色的那张也占着这一行,卡片等高
    expect(find.text('无角色'), findsOneWidget);
    expect(find.textContaining('NAI 4.5 Full · 28 步 · CFG'), findsOneWidget);
    expect(find.textContaining('NAI 4.5 Full · 23 步 · CFG'), findsOneWidget);
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Text),
      ),
    )) {
      expect(t.maxLines, anyOf(isNull, 1));
    }
    // 图标中线压在正文基线上方 0.28 个字号处(预览字号 13)
    final prompt = find.text('rain, neon lights').first;
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: tester.widget<Text>(prompt).style),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline =
        tester.getTopLeft(prompt).dy +
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.dispose();
    final icon = tester.getCenter(find.byIcon(Icons.subject).first).dy;
    expect(baseline - icon, moreOrLessEquals(13 * .28, epsilon: .1));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('画风带推荐参数：弹窗问套不套，点「套用」才写进当前画布，可撤销', (tester) async {
    widgetCase = true;
    const entry = TagEntry(
      id: 'a',
      category: TagCategory.artist,
      name: '水彩',
      positive: 'watercolor',
      recipe: StyleRecipe(
        model: 'v4.5-full',
        steps: 40,
        cfg: 7,
        sampler: 'Euler',
        scheduler: 'karras',
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => offerStyleRecipe(context, ref, [
                  entry,
                ], canvasId: c.read(canvasWorkspaceProvider).activeId),
                child: const Text('导入'),
              ),
            ),
          ),
        ),
      ),
    );
    final steps = c.read(generateProvider).params.steps;
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('套用「水彩」的推荐参数?'), findsOneWidget);
    // 排成参数表:一格一项,上面项名、下面值
    for (final (label, value) in [
      ('模型', 'NAI 4.5 Full'),
      ('步数', '40'),
      ('CFG', '7'),
      ('采样器', 'Euler'),
      ('噪声调度', 'karras'),
      ('CFG Rescale', '0'),
      ('Variety+', '关'),
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(find.text(value), findsOneWidget);
    }
    await tester.tap(find.text('不用'));
    await tester.pumpAndSettle();
    expect(c.read(generateProvider).params.steps, steps);
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    expect(c.read(generateProvider).params.steps, 40);
    expect(c.read(generateProvider).params.cfg, 7);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(c.read(generateProvider).params.steps, steps);
    // 提示条自己的计时走完,别留着 Timer
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('画风编辑页推荐参数：没导入只给按钮、不摆参数；导入后点开才列全表，可清除', (tester) async {
    widgetCase = true;
    tester.view.physicalSize = const Size(369, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scoped = ProviderContainer(
      parent: c,
      overrides: [tagLibraryProvider.overrideWith(_EmptyLibrary.new)],
    );
    addTearDown(scoped.dispose);
    gen.applyParams(
      c.read(generateProvider).params.copyWith(steps: 37, cfg: 6.5),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scoped,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TagEditorPage(cat: TagCategory.artist),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('推荐参数'));
    await tester.pumpAndSettle();

    // 空着:只有按钮,创作页的参数一项都不摆出来
    final import = find.widgetWithText(OutlinedButton, '导入创作页');
    expect(import, findsOneWidget);
    for (final t in ['模型', '步数', '37', '6.5', '清除']) {
      expect(find.text(t), findsNothing);
    }
    expect(tester.getSize(import).height, greaterThanOrEqualTo(40));

    await tester.tap(import);
    await tester.pumpAndSettle();
    expect(import, findsNothing);
    await tester.tap(find.text('推荐参数'));
    await tester.pumpAndSettle();
    for (final t in ['模型', 'NAI 4.5 Full', '步数', '37', 'CFG', '6.5']) {
      expect(find.text(t), findsOneWidget);
    }
    final clear = find.widgetWithText(OutlinedButton, '清除');
    expect(tester.getSize(clear).height, greaterThanOrEqualTo(40));

    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.text('步数'), findsNothing);
    expect(import, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布行点「历史」列出出图记录;没出过图写一句空状态', (tester) async {
    final a = c.read(canvasWorkspaceProvider).activeId;
    gen.setPrompts(positive: 'rain, moon');
    await tester.runAsync(
      () => stores.history.record(
        a,
        CanvasPrompts.of(c.read(generateProvider)),
        ['g1', 'g2'],
      ),
    );
    final b = canvases.create();
    // 读盘在假时钟里不会自己走完,先读进缓存
    await tester.runAsync(() => stores.history.load(a));
    await tester.runAsync(() => stores.history.load(b));
    await pumpHeader(tester);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史').first);
    await tester.pumpAndSettle();
    expect(find.text('默认画布 · 历史'), findsOneWidget);
    expect(find.textContaining('2 张'), findsOneWidget);
    // 底下画布卡片一处,历史这一条一处
    expect(find.text('rain, moon'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('默认画布 · 历史'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史').last);
    await tester.pumpAndSettle();
    expect(find.text('这张画布还没有出过图'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('面板标题带说明：点开讲清画布记录什么、哪些共用', (tester) async {
    await pumpHeader(tester);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('画布'));
    await tester.pumpAndSettle();
    expect(find.textContaining('各存一套提示词和出图参数'), findsOneWidget);
    expect(find.textContaining('所有画布共用'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('长按整块拖动排序，当前画布不变；默认画布拖不动，也拖不到它上面', (tester) async {
    canvases.create();
    canvases.create();
    canvases.create();
    await pumpHeader(tester);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    Finder row(String name) => find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.text(name),
    );
    final step =
        tester.getCenter(row('画布 2')).dy - tester.getCenter(row('画布 1')).dy;
    Future<void> drag(String name, double rows) async {
      final gesture = await tester.startGesture(tester.getCenter(row(name)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(Offset(0, step * rows / 6));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    List<String> order() => [
      for (final d in c.read(canvasWorkspaceProvider).canvases) d.id,
    ];
    await drag('画布 1', 1.8);
    expect(order(), ['canvas1', 'canvas3', 'canvas4', 'canvas2']);
    expect(c.read(canvasWorkspaceProvider).activeId, 'canvas4');
    await drag('默认画布', 1.8);
    expect(order(), ['canvas1', 'canvas3', 'canvas4', 'canvas2']);
    await drag('画布 2', -1.8);
    expect(order(), ['canvas1', 'canvas3', 'canvas4', 'canvas2']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('画布增多不加宽顶栏；当前名称随新建和选择立即更新', (tester) async {
    for (var i = 0; i < 7; i++) {
      canvases.create();
    }
    await pumpHeader(tester);
    final width = tester.getSize(find.byType(GenerateTopBar)).width;
    expect(find.text('画布 7'), findsOneWidget);
    canvases.create();
    await tester.pumpAndSettle();
    expect(find.text('画布 8'), findsOneWidget);
    expect(find.text('画布 7'), findsNothing);
    expect(tester.getSize(find.byType(GenerateTopBar)).width, width);
    await tester.tap(find.byTooltip('切换画布'));
    await tester.pumpAndSettle();
    Finder row(String name) => find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.text(name),
    );
    // 打开时当前画布已在视野里，排在前面的滚出去了
    expect(row('画布 8').hitTestable(), findsOneWidget);
    expect(row('画布 1').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      row('画布 1'),
      -200,
      scrollable: find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      ),
    );
    // scrollUntilVisible 收尾的 ensureVisible 不排版，点之前补一帧
    await tester.pump();
    await tester.tap(row('画布 1'));
    await tester.pumpAndSettle();
    expect(find.text('画布 1'), findsOneWidget);
    expect(find.text('画布 8'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('模型入口独立可点；模型跟画布走，切回来恢复那张的型号；V5 显示点数与额度', (tester) async {
    await pumpHeader(tester);
    final a = c.read(canvasWorkspaceProvider).activeId;
    expect(find.text('NAI 4.5 Full'), findsOneWidget);
    await tester.tap(find.byTooltip('切换模型：NAI 4.5 Full'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NAI 5 Curated'));
    await tester.pumpAndSettle();
    expect(c.read(generateProvider).params.model, 'NAI 5.0 Curated');
    expect(find.text('NAI 5 Curated'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    // 320 宽放不下百分比:额度画成进度条
    expect(find.text('70%'), findsNothing);
    canvases.create();
    gen.setModel('NAI 4.0 Full');
    await tester.pumpAndSettle();
    expect(find.text('NAI 4 Full'), findsOneWidget);
    canvases.select(a);
    await tester.pumpAndSettle();
    expect(find.text('NAI 5 Curated'), findsOneWidget);
    await tester.tap(find.byTooltip('点数与额度'));
    await tester.pumpAndSettle();
    expect(find.text('点数与额度'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('宽屏放得下:点数 │ 百分比,没有进度条', (tester) async {
    _Balance.anlas = 12345;
    addTearDown(() => _Balance.anlas = 1234);
    gen.setModel('NAI 5.0 Curated');
    await pumpHeader(tester, width: 800);
    expect(find.text('12,345'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            '${w.foregroundPainter.runtimeType}' == '_MeterPainter',
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('窄屏放不下:百分比换成点数底下的进度条', (tester) async {
    _Balance.anlas = 12345;
    addTearDown(() => _Balance.anlas = 1234);
    gen.setModel('NAI 5.0 Curated');
    await pumpHeader(tester);
    expect(find.text('12,345'), findsOneWidget);
    // 额度画成点数底下的进度条,百分比只给读屏
    expect(find.text('70%'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('12,345，70%')), findsOneWidget);
    // 条画在读数框外,得落在这枚入口的可见范围里(被撑满行高就画出界、被裁掉)
    final status = find.byTooltip('点数与额度');
    final meter = find.descendant(
      of: status,
      matching: find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            '${w.foregroundPainter.runtimeType}' == '_MeterPainter',
      ),
    );
    expect(meter, findsOneWidget);
    expect(
      tester.getRect(meter).bottom + 6,
      lessThanOrEqualTo(tester.getRect(status).bottom),
    );
    // 入口不裁切内容:条贴着左右边和下半截,按圆角一裁两头就成了斜边
    expect(
      find.descendant(
        of: status,
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.clipBehavior != Clip.none,
        ),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('顶栏三段各占固定的格:画布名长短不推着模型和读数挪', (tester) async {
    // 从一个字的画布名起步:默认画布那四个字在窄屏下本来就占满了格
    final id = canvases.create();
    canvases.rename(id, '雨');
    gen.setModel('NAI 4.5 Full');
    await pumpHeader(tester);
    final model = find.byTooltip('切换模型：NAI 4.5 Full');
    final status = find.byTooltip('点数与额度');
    final modelX = tester.getCenter(model).dx;
    final statusRect = tester.getRect(status);
    canvases.rename(id, '雨夜街景与霓虹灯下的城市角色探索');
    await tester.pumpAndSettle();
    expect(find.text('雨夜街景与霓虹灯下的城市角色探索'), findsOneWidget);
    expect(tester.getCenter(model).dx, modelX);
    expect(tester.getRect(status), statusRect);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('320px 长画布名称、大字体和算力状态不溢出；NAI 下仍显示计费实例', (tester) async {
    // 默认画布名字固定,长名字放在一张普通画布上试
    canvases.rename(canvases.create(), '雨夜街景与霓虹灯下的城市角色探索');
    gen.setModel('Anima Aesthetic');
    await pumpHeader(tester, textScale: 1.4);
    expect(find.text('Anima Aesthetic'), findsOneWidget);
    // 没开机时顶栏只报一句：共享「免费共享」，独享「未启动」
    expect(find.text('免费共享'), findsOneWidget);
    unawaited(
      c
          .read(rentalPrefsProvider.notifier)
          .patch((p) => p.copyWith(channel: ModalChannel.rented)),
    );
    await tester.pump();
    expect(find.text('未启动'), findsOneWidget);
    expect(find.text('免费共享'), findsNothing);
    expect(tester.takeException(), isNull);
    (c.read(gpuRentalProvider.notifier) as _Rental).showRunning();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('¥0.12'), findsOneWidget);
    gen.setModel('NAI 4.5 Full');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('算力与费用'), findsOneWidget);
    expect(find.text('¥0.12'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 关闭组件的每秒计时订阅，避免测试结束留下 Timer。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

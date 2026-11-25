// AI 助手里两处最容易写错的逻辑。
//
// 一是 tag 差集:整套「看得出改了什么」的设计全靠它,算错了回执就是假的。
// 二是站位继承:AI 只在用户明说方位时才给坐标,其余留空 —— 空的当成「放正中」
// 会让「让她笑一下」这种无关改动把用户摆好的构图重排掉。
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plana_app/features/assistant/domain/agent_event.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/assistant/agent_model.dart';
import 'package:plana_app/features/assistant/agent_trace.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:plana_app/features/assistant/domain/agent_result.dart';
import 'package:plana_app/features/assistant/assistant_mode.dart';
import 'package:plana_app/features/assistant/domain/conversation.dart';
import 'package:plana_app/features/assistant/assistant_settings.dart';
import 'package:plana_app/features/assistant/custom_endpoint.dart';
import 'package:plana_app/features/assistant/llm/gemini_provider.dart';
import 'package:plana_app/features/assistant/llm/http_provider.dart';
import 'package:plana_app/features/assistant/llm/llm_image.dart';
import 'package:plana_app/features/assistant/llm/llm_provider.dart';
import 'package:plana_app/features/assistant/llm/plana_channel_provider.dart';
import 'package:plana_app/features/assistant/runtime/agent_runtime.dart';
import 'package:plana_app/features/assistant/domain/turn_request.dart';
import 'package:plana_app/features/assistant/presets/preset_rule.dart';
import 'package:plana_app/features/assistant/protocol/fenced_protocol.dart';
import 'package:plana_app/features/assistant/protocol/reply_parser.dart';
import 'package:plana_app/features/assistant/protocol/tool_protocol.dart';
import 'package:plana_app/features/assistant/runtime/ledger.dart';
import 'package:plana_app/features/assistant/runtime/placeholders.dart';
import 'package:plana_app/features/assistant/runtime/prompt_assets.dart';
import 'package:plana_app/features/assistant/runtime/refusal.dart';
import 'package:plana_app/features/assistant/tools/artist_tool.dart';
import 'package:plana_app/features/assistant/tools/character_tool.dart';
import 'package:plana_app/features/assistant/tools/my_library.dart';
import 'package:plana_app/features/assistant/tools/oc_tool.dart';
import 'package:plana_app/features/assistant/tools/tool_context.dart';
import 'package:plana_app/features/assistant/tools/tool_registry.dart';
import 'package:plana_app/features/assistant/tools/tool_settings.dart';
import 'package:plana_app/features/assistant/prompt_diff.dart';
import 'package:plana_app/features/assistant/application/assistant_controller.dart';
import 'package:plana_app/features/assistant/application/proposal_service.dart';
import 'package:plana_app/features/assistant/application/session_repository.dart';
import 'package:plana_app/features/assistant/domain/image_model.dart';
import 'package:plana_app/features/assistant/widgets/reply_body.dart';
import 'package:plana_app/features/generate/generate_state.dart';
import 'package:plana_app/features/inspiration/codex/codex_char_split.dart';
import 'package:plana_app/features/generate/models.dart';
import 'package:plana_app/features/generate/prompt_sections.dart';
import 'package:plana_app/features/inspiration/tag_models.dart';

Directory _tempRoot() {
  final root = Directory.systemTemp.createTempSync('plana_assistant');
  addTearDown(() async {
    for (var i = 0; i < 10; i++) {
      try {
        root.deleteSync(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });
  return root;
}

HttpLlmProvider _llm(AgentApiFormat f, [String model = 'm']) => llmProviderFor(
  CustomEndpoint(
    id: 'x',
    name: '',
    format: f,
    baseUrl: '',
    apiKey: 'k',
    model: model,
  ),
);

PromptTexts _texts() =>
    PromptTexts.parse(File('assets/prompts/texts.yaml').readAsStringSync());

List<ToolCall> _calls(String reply) =>
    const FencedToolProtocol().parse(reply).calls;

class _FakeOffline implements TagLookup {
  _FakeOffline({this.roles = const [], this.chars = const []});

  final List<TagRecord> roles;
  final List<TagRecord> chars;

  @override
  Future<List<TagRecord>> roleCandidates(String text, {int limit = 5}) async =>
      roles;

  @override
  Future<List<TagRecord>> characters({
    String query = '',
    String origin = '',
    int limit = 10,
  }) async => chars;

  @override
  Future<List<TagRecord>> tags(
    String query, {
    int? category,
    int limit = 10,
  }) async => const [];
}

class _FakeOnline implements OnlineTags {
  _FakeOnline({this.hits = const [], this.kept});

  final List<SemanticHit> hits;
  final asked = <String>[];

  /// 角色候选筛选的结果;null = 判不了。
  final List<String>? kept;
  final filtered = <List<String>>[];

  @override
  Future<List<SemanticHit>> characters(String query, {int limit = 10}) async {
    asked.add(query);
    return hits;
  }

  @override
  Future<String?> wiki(String tag) async => null;

  @override
  Future<List<String>?> filterRoles(String userText, List<String> tags) async {
    filtered.add(tags);
    return kept;
  }
}

/// 第一次查询一直等到第二次查询开始:两个调用串着跑就会卡死。
class _GatedOnline implements OnlineTags {
  final _second = Completer<void>();
  final asked = <String>[];

  @override
  Future<List<SemanticHit>> characters(String query, {int limit = 10}) async {
    asked.add(query);
    if (asked.length == 1) {
      await _second.future;
    } else if (!_second.isCompleted) {
      _second.complete();
    }
    return const [];
  }

  @override
  Future<String?> wiki(String tag) async => null;

  @override
  Future<List<String>?> filterRoles(String userText, List<String> tags) async =>
      null;
}

Future<GenerateNotifier> _notifier() async {
  final stores = await AppStores.open(rootOverride: _tempRoot());
  final c = ProviderContainer(
    overrides: [appStoresProvider.overrideWithValue(stores)],
  );
  addTearDown(c.dispose);
  return c.read(generateProvider.notifier);
}

AssistantChange _change(String before, String after) => AssistantChange(
  before: PromptSnapshot(positive: before),
  after: PromptSnapshot(positive: after),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tag 差集', () {
    test('加了什么、删了什么,按 after 的顺序报', () {
      final c = _change(
        'masterpiece, 1girl, cherry blossoms, standing',
        'masterpiece, ciloranko, 1girl, cherry_blossom_tree, falling_petals, standing',
      );
      expect(c.added, ['ciloranko', 'cherry_blossom_tree', 'falling_petals']);
      expect(c.removed, ['cherry blossoms']);
    });

    test('空格与下划线是两个不同的 tag,不能归一成「没变」', () {
      // NAI 眼里 `cat girl` 和 `cat_girl` 是两条不同的 tag,把它们算成同一个
      // 会让一次真实的改写在回执上显示成「什么都没做」。
      final c = _change('cat girl', 'cat_girl');
      expect(c.added, ['cat_girl']);
      expect(c.removed, ['cat girl']);
    });

    test('顺序变了但内容没变 = 没有增删', () {
      final c = _change('a, b, c', 'c, a, b');
      expect(c.added, isEmpty);
      expect(c.removed, isEmpty);
    });

    test('重排角色时回执以角色为准 —— 那是比改几个 tag 大得多的动作', () {
      final c = AssistantChange(
        before: const PromptSnapshot(positive: 'a'),
        after: PromptSnapshot(
          positive: 'a, b',
          characters: [
            for (var i = 0; i < 3; i++)
              CharacterPrompt(id: '$i', name: '角色$i', positive: 'p$i'),
          ],
        ),
      );
      expect(c.charsChanged, isTrue);
      expect(c.charCount, 3);
    });
  });

  group('撤销的冲突判定', () {
    test('一字不差才算同步;正向词改一个字就不同步', () {
      const a = PromptSnapshot(positive: '1girl, solo', negative: 'lowres');
      expect(
        a.sameAs(
          const PromptSnapshot(positive: '1girl, solo', negative: 'lowres'),
        ),
        isTrue,
      );
      expect(
        a.sameAs(
          const PromptSnapshot(
            positive: '1girl, solo, cat',
            negative: 'lowres',
          ),
        ),
        isFalse,
      );
    });

    test('站位开关也算在内 —— AI 替用户开过它,撤销要连它一起还原', () {
      const a = PromptSnapshot(positive: 'x', useCoords: true);
      expect(a.sameAs(const PromptSnapshot(positive: 'x')), isFalse);
    });

    test('角色的站位变了就算不同步', () {
      final a = PromptSnapshot(
        positive: 'x',
        characters: [const CharacterPrompt(id: '1', name: 'A', position: 'B2')],
      );
      final b = PromptSnapshot(
        positive: 'x',
        characters: [const CharacterPrompt(id: '1', name: 'A', position: 'D3')],
      );
      expect(a.sameAs(b), isFalse);
    });
  });

  group('applyAgentCharacters 只认 AI 这一份', () {
    test('不从画布继承站位 —— 画布和 AI 两边彻底分开', () async {
      // 原先 AI 没给站位的角色会按位继承画布上同位旧角色的坐标。那是一次没人按过
      // 的「读画布」:用户没点引用,AI 也没见过这些坐标,结果却带着它们。
      final n = await _notifier();
      n.applyAgentCharacters([
        (
          name: '芙兰',
          positive: 'flandre',
          negative: '',
          position: '0.2000,0.5000',
        ),
        (
          name: '蕾米',
          positive: 'remilia',
          negative: '',
          position: '0.8000,0.5000',
        ),
      ]);

      // 第二轮 AI 一个坐标都没给。
      final placed = n.applyAgentCharacters([
        (name: '芙兰', positive: 'flandre, smile', negative: '', position: ''),
        (name: '蕾米', positive: 'remilia, smile', negative: '', position: ''),
      ]);
      expect(placed, isFalse, reason: 'AI 没摆位,不该报告摆过');
      expect(
        n.state.characters.map((c) => c.position).toList(),
        isNot(['0.2000,0.5000', '0.8000,0.5000']),
        reason: '上一份的坐标不该被悄悄继承过来',
      );
    });

    test('AI 一个角色都没给 = 清空,不是「保持原样」', () async {
      final n = await _notifier();
      n.applyAgentCharacters([
        (name: 'A', positive: 'a', negative: '', position: ''),
      ]);
      n.applyAgentCharacters(const []);
      expect(n.state.characters, isEmpty);
    });

    test('AI 摆了位就返回 true(调用方据此打开 use_coords)', () async {
      final n = await _notifier();
      final placed = n.applyAgentCharacters([
        (name: 'A', positive: 'a', negative: '', position: '0.3000,0.7000'),
      ]);
      expect(placed, isTrue);
      expect(n.state.characters.single.position, '0.3000,0.7000');
    });

    test('是替换不是追加 —— 聊三轮不会攒出十二个角色', () async {
      final n = await _notifier();
      for (var i = 0; i < 3; i++) {
        n.applyAgentCharacters([
          (name: 'A', positive: 'a', negative: '', position: ''),
          (name: 'B', positive: 'b', negative: '', position: ''),
        ]);
      }
      expect(n.state.characters.length, 2);
    });

    test('新角色比旧的多时,多出来的挑空格而不是撞在一起', () async {
      final n = await _notifier();
      n.applyAgentCharacters([
        (name: 'A', positive: 'a', negative: '', position: ''),
        (name: 'B', positive: 'b', negative: '', position: ''),
        (name: 'C', positive: 'c', negative: '', position: ''),
      ]);
      final pos = n.state.characters.map((c) => c.position).toList();
      expect(pos.whereType<String>().toSet().length, 3, reason: '三个角色不该落同一格');
    });
  });

  group('图片生成模型的档位映射', () {
    // 后端只看三件事:是不是 anima、是不是 krea、是不是以 nai_v5 开头,
    // 其余一律回落 4.5(agent_router/router.py:resolve_preset_and_backend)。
    // 映射错了不会报错,只会静默拿到错代次的预设 —— krea 尤其致命:
    // 它吃的是连贯自然语言,喂 4.5 的 tag 串预设基本等于没写提示词。
    test('三个父类各自映射到后端认得的档位', () {
      expect(agentImageModel('Anima XL 3.0'), 'anima');
      expect(agentImageModel('Krea 2'), 'krea');
      expect(agentImageModel('NAI 5.0 Full'), startsWith('nai_v5'));
      expect(agentImageModel('NAI 5.0 Curated'), startsWith('nai_v5'));
    });

    test('4.x 与认不出的一律回落 4.5,且不能误撞 nai_v5 前缀', () {
      for (final m in ['NAI 4.5 Full', 'NAI 4.5 Curated', 'NAI 4.0 Full', '']) {
        final got = agentImageModel(m);
        expect(got.startsWith('nai_v5'), isFalse, reason: '$m 被误判成 V5');
        expect(got, 'nai_v45_full');
      }
    });
  });

  group('历史回带', () {
    // AI 轮要带着当初那个 nai_draw 围栏一起回去。只回正文的话模型看不见自己
    // 上一轮写了什么,下一句「把头发改成金色」得从头推一遍 —— 连角色、画风
    // 都要重新查一次工具,用户看到的就是「怎么又查了一遍」。
    const draw = DrawProposal(
      positive: '1girl, plana_(blue_archive), halo',
      negative: 'bad hands',
    );

    test('有提议的那轮:正文 + 围栏', () {
      const m = AssistantMsg(
        id: 'x',
        role: MsgRole.ai,
        text: '改好了喵~',
        at: 1,
        draw: draw,
      );
      final out = replayText(m);
      expect(out, startsWith('改好了喵~'));
      expect(out, contains('```nai_draw'));
      // 围栏里必须是**完整提示词**,不是增量 —— 最新那条就等于当前这幅画的全部
      expect(out, contains('plana_(blue_archive)'));
      expect(out, contains('bad hands'));
      expect(out.trimRight(), endsWith('```'));
    });

    test('围栏里是合法 JSON,字段名与模型写的一致', () {
      const m = AssistantMsg(
        id: 'x',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        draw: draw,
      );
      final body = replayText(m).split('```nai_draw\n')[1].split('\n```')[0];
      final j = jsonDecode(body) as Map<String, dynamic>;
      expect(j['positive'], draw.positive);
      expect(j['negative'], draw.negative);
      expect(j.containsKey('characters'), isTrue);
    });

    AssistantMsg ai(String id, {bool drawn = true}) => AssistantMsg(
      id: id,
      role: MsgRole.ai,
      text: 'ok',
      at: 1,
      draw: drawn ? draw : null,
    );
    AssistantMsg user(String id) =>
        AssistantMsg(id: id, role: MsgRole.user, text: '改一下', at: 1);

    test('只留最近两个有产出的 AI 轮', () {
      final msgs = [
        user('u1'),
        ai('a1'),
        user('u2'),
        ai('a2'),
        user('u3'),
        ai('a3'),
      ];
      expect(historyFenceIds(msgs, 2), {'a2', 'a3'});
    });

    test('纯聊天轮不占名额 —— 它本来就没围栏可留', () {
      final msgs = [
        user('u1'),
        ai('a1'),
        user('u2'),
        ai('a2', drawn: false),
        user('u3'),
        ai('a3', drawn: false),
      ];
      // 往前一直数到真有产出的那条,不能被两条闲聊挡住
      expect(historyFenceIds(msgs, 2), {'a1'});
    });

    test('不足两个就有几个算几个', () {
      expect(historyFenceIds([user('u1'), ai('a1')], 2), {'a1'});
      expect(historyFenceIds([user('u1')], 2), isEmpty);
      expect(historyFenceIds(const [], 2), isEmpty);
    });

    test('keep 为 0 就一个都不留', () {
      expect(historyFenceIds([user('u1'), ai('a1')], 0), isEmpty);
    });

    test('纯聊天轮原样返回,不凭空造一个空围栏', () {
      const m = AssistantMsg(
        id: 'x',
        role: MsgRole.ai,
        text: '这串 tag 挺好的喵',
        at: 1,
      );
      expect(replayText(m), '这串 tag 挺好的喵');
    });

    test('角色连 position 一起带回去', () {
      const m = AssistantMsg(
        id: 'x',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        draw: DrawProposal(
          positive: '2girls',
          characters: [
            AgentCharacter(
              name: '普拉娜',
              positive: 'smile',
              position: '0.5000,0.4000',
            ),
          ],
        ),
      );
      // 不带的话下一轮模型重写 characters 会丢站位,用户摆好的构图被重排
      expect(replayText(m), contains('0.5000,0.4000'));
    });
  });

  group('直接生成的快照:沿用参数和 Vibe,其余只认 AI', () {
    // 原先是「拿画布当底、AI 给了的字段盖上去」。AI 没写角色分区时,出图会带上
    // 画布里原有的角色 —— 用户没点引用,AI 也没见过它们,图里却有。
    final canvas = GenerateState.initial().copyWith(
      prompt: 'miku, rin',
      negativePrompt: 'my curated negatives',
      promptRaw: 'miku, rin',
      characters: const [
        CharacterPrompt(id: 'c1', name: '初音', positive: 'hatsune_miku'),
        CharacterPrompt(id: 'c2', name: '镜音铃', positive: 'kagamine_rin'),
      ],
      params: const GenParams(
        model: 'nai-diffusion-4-5-full',
        width: 1216,
        height: 832,
        steps: 28,
        useCoords: true,
      ),
    );

    GenerateState send(DrawProposal r) {
      var i = 0;
      return proposalSendState(
        canvas,
        r,
        SectionImport.main,
        newId: () => 'p${i++}',
      );
    }

    test('AI 没写角色分区,出图就没有分区', () {
      final s = send(const DrawProposal(positive: '1girl, cat ears'));
      expect(s.characters, isEmpty, reason: '画布上的初音和镜音铃不能混进来');
    });

    test('AI 没写负向,负向就是空', () {
      final s = send(const DrawProposal(positive: '1girl'));
      expect(s.negativePrompt, '');
    });

    test('正向词只认 AI 的,编辑器草稿也不带', () {
      final s = send(const DrawProposal(positive: '1girl'));
      expect(s.prompt, '1girl');
      expect(s.promptRaw, '', reason: '草稿是画布那份的,留着会和定稿对不上');
    });

    test('四个图像模块只留 Vibe', () {
      // 角色参考、图生图、重绘是冲着某张具体的图、某个具体的角色配的,
      // 套到 AI 写的新画面上只会拧在一起;Vibe 管的是画风,套谁都成立。
      final withModules = canvas.copyWith(
        vibes: const [VibeItem(id: 'v1', name: 'style')],
        charRefs: const [CharRefItem(id: 'r1')],
        img2img: const Img2ImgConfig(strength: 0.5),
      );
      var i = 0;
      final s = proposalSendState(
        withModules,
        const DrawProposal(positive: '1girl'),
        SectionImport.main,
        newId: () => 'p${i++}',
      );
      expect(s.vibes.single.id, 'v1');
      expect(s.charRefs, isEmpty);
      expect(s.img2img, isNull);
      expect(s.inpaint, isNull);
    });

    test('尺寸、步数这些参数沿用创作页', () {
      final s = send(const DrawProposal(positive: '1girl'));
      expect(s.params.model, 'nai-diffusion-4-5-full');
      expect(s.params.width, 1216);
      expect(s.params.height, 832);
      expect(s.params.steps, 28);
    });

    test('坐标开关跟着 AI 这份走,不留画布上的旧值', () {
      // 画布开着坐标、AI 没摆位:沿用的话发出去的是几个默认空格,
      // 被模型当成用户指定的站位。
      expect(
        send(const DrawProposal(positive: '1girl')).params.useCoords,
        isFalse,
      );
      final placed = send(
        const DrawProposal(
          positive: '1girl',
          characters: [
            AgentCharacter(name: 'A', positive: 'a', position: '0.3000,0.5000'),
          ],
        ),
      );
      expect(placed.params.useCoords, isTrue);
      expect(placed.characters.single.position, '0.3000,0.5000');
    });

    test('AI 给了角色分区就原样用', () {
      final s = send(
        const DrawProposal(
          positive: '2girls',
          characters: [
            AgentCharacter(name: '芙兰', positive: 'flandre_scarlet'),
            AgentCharacter(name: '蕾米', positive: 'remilia_scarlet'),
          ],
        ),
      );
      expect(s.characters.map((c) => c.positive), [
        'flandre_scarlet',
        'remilia_scarlet',
      ]);
    });
  });

  group('主提示词分区:读整串,导入按设置写', () {
    final canvas = GenerateState.initial().copyWith(
      prompt: '1girl, smile',
      negativePrompt: 'lowres',
      sections: const [
        PromptSection.main(),
        PromptSection(
          id: 's1',
          name: '画风',
          positive: 'artist:foo, 1.2::artist:bar::, masterpiece',
          negative: 'blurry',
          artist: true,
        ),
        PromptSection(id: 's2', name: '场景', positive: 'night', enabled: false),
      ],
    );
    // AI 读到的就是这一串,原样带回再改两处
    const ai =
        '1girl, smile, cat ears, artist:foo, 1.2::artist:bar::, masterpiece';

    GenerateState into(SectionImport mode, {GenerateState? from}) {
      var i = 0;
      return importPromptsInto(
        from ?? canvas,
        ai,
        'lowres, blurry, bad hands',
        mode,
        newId: () => 'n${i++}',
      );
    }

    test('引用时发主体和启用分区拼好的整串', () {
      expect(
        canvasPositive(canvas),
        '1girl, smile, artist:foo, 1.2::artist:bar::, masterpiece',
      );
      expect(canvasNegative(canvas), 'lowres, blurry');
    });

    test('只有分区有词时也能引用', () {
      final s = canvas.copyWith(prompt: '', negativePrompt: '');
      expect(canvasHasContent(s), isTrue);
    });

    test('替换主体:分区留着,分区已有的词不再进主体', () {
      final s = into(SectionImport.main);
      expect(s.prompt, '1girl, smile, cat ears');
      expect(s.negativePrompt, 'lowres, bad hands');
      expect(s.sections.map((x) => x.id), ['main', 's1', 's2']);
      expect(
        composeSections(s).prompt,
        '1girl, smile, cat ears, artist:foo, 1.2::artist:bar::, masterpiece',
        reason: '带权重的画师词不能叠成两份',
      );
    });

    test('替换主体:主体停用着就打开,AI 的词不会被丢掉', () {
      final off = canvas.copyWith(
        sections: [
          for (final x in canvas.sections)
            x.isMain ? x.copyWith(enabled: false) : x,
        ],
      );
      final s = into(SectionImport.main, from: off);
      expect(s.sections.first.enabled, isTrue);
      expect(composeSections(s).prompt, startsWith('1girl, smile, cat ears'));
    });

    test('新建分区:原有的不动,新的一格只放没有的词', () {
      final s = into(SectionImport.newSection);
      expect(s.prompt, '1girl, smile');
      expect(s.sections.length, 4);
      final added = s.sections.last;
      expect(added.name, 'AI');
      expect(added.positive, 'cat ears');
      expect(added.negative, 'bad hands');
    });

    test('新建分区:没分区时连主体一起建出来', () {
      final s = into(
        SectionImport.newSection,
        from: canvas.copyWith(sections: const []),
      );
      expect(s.sections.map((x) => x.isMain), [true, false]);
      expect(s.sections.last.positive, contains('artist:foo'));
    });

    test('清空分区:整列清掉,整份进主体', () {
      final s = into(SectionImport.clear);
      expect(s.sections, isEmpty);
      expect(s.prompt, ai);
      expect(s.negativePrompt, 'lowres, blurry, bad hands');
    });

    test('组里的词不单独拿掉', () {
      final s = canvas.copyWith(
        sections: const [
          PromptSection.main(),
          PromptSection(id: 's1', name: '画风', positive: 'a, b'),
        ],
      );
      expect(
        dropSectionWords(
          '{a, c}, 1.1::b, d::, b',
          s.sections,
          s.prompt,
          positive: true,
        ),
        '{a, c}, 1.1::b, d::',
      );
    });

    test('直接生成和导入后再生成是同一串', () {
      const r = DrawProposal(positive: ai, negative: 'lowres, bad hands');
      for (final mode in SectionImport.values) {
        var i = 0;
        final direct = proposalSendState(
          canvas,
          r,
          mode,
          newId: () => 'n${i++}',
        );
        var j = 0;
        final imported = importPromptsInto(
          canvas,
          r.positive,
          r.negative,
          mode,
          newId: () => 'n${j++}',
        );
        expect(
          composeSections(direct).prompt,
          composeSections(imported).prompt,
          reason: mode.name,
        );
      }
    });

    test('快照带分区;老记录没有分区键时撤销不碰分区', () {
      final snap = PromptSnapshot(positive: 'a', sections: canvas.sections);
      final back = PromptSnapshot.fromJson(
        jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>,
      );
      expect(back.sections!.map((x) => x.id), ['main', 's1', 's2']);
      expect(back.sameAs(snap), isTrue);
      expect(PromptSnapshot.fromJson(const {'positive': 'a'}).sections, isNull);
    });
  });

  group('库内画师串的负面跟着进提议', () {
    const a1 = TagEntry(
      id: 'a1',
      category: TagCategory.artist,
      name: 'A1',
      positive: 'artist:foo, 1.2::artist:bar::',
      negative: 'lowres, bad hands, sketch',
    );
    const a2 = TagEntry(
      id: 'a2',
      category: TagCategory.artist,
      name: 'A2',
      positive: 'artist:baz',
      negative: 'monochrome',
    );

    test('用到的画师串补负面,已有的词不重复', () {
      const r = DrawProposal(
        positive: 'artist:foo, 1.2::artist:bar::, 1girl',
        negative: 'lowres, blurry',
      );
      expect(
        withArtistNegatives(r, const [a1, a2]),
        'lowres, blurry, bad hands, sketch',
      );
    });

    test('写在角色正向里的也算', () {
      const r = DrawProposal(
        positive: '1girl',
        characters: [AgentCharacter(name: 'x', positive: 'artist:baz, smile')],
      );
      expect(withArtistNegatives(r, const [a1, a2]), 'monochrome');
    });

    test('没用到、只用了一半都不补', () {
      const r = DrawProposal(positive: 'artist:foo, 1girl', negative: 'n');
      expect(withArtistNegatives(r, const [a1]), 'n');
    });
  });

  group('回复里的代码', () {
    // 预设的写 tag 模式会把 tag 包进代码块,气泡原先是纯文本,
    // 用户看到的是字面的反引号,复制也复制不干净。
    test('围栏里的是代码块,语言标注不算内容', () {
      const raw =
          '查到了,就是这条喵~\n\n```text\nsakayori_iroha_(tsukuyomi)\n```\n\n别弄混了喵';
      expect(splitCodeFences(raw), [
        (text: '查到了,就是这条喵~', block: false),
        (text: 'sakayori_iroha_(tsukuyomi)', block: true),
        (text: '别弄混了喵', block: false),
      ]);
    });

    test('没有围栏就是一整段文字', () {
      expect(splitCodeFences('好的喵'), [(text: '好的喵', block: false)]);
    });

    test('没收尾的围栏:剩下的当代码,那串 tag 至少还能完整复制', () {
      expect(splitCodeFences('给你:\n```\n1girl, solo'), [
        (text: '给你:', block: false),
        (text: '1girl, solo', block: true),
      ]);
    });

    test('代码保留缩进和多行,只去掉首尾空行', () {
      expect(splitCodeFences('```\n\nchar1: a\n  char2: b\n\n```'), [
        (text: 'char1: a\n  char2: b', block: true),
      ]);
    });

    test('Windows 换行也认', () {
      expect(splitCodeFences('看:\r\n```text\r\nabc\r\n```\r\n'), [
        (text: '看:', block: false),
        (text: 'abc', block: true),
      ]);
    });

    test('行内反引号拆出来', () {
      expect(splitInlineCode('挂的是 `_(tsukuyomi)` 而不是作品名'), [
        (text: '挂的是 ', code: false),
        (text: '_(tsukuyomi)', code: true),
        (text: ' 而不是作品名', code: false),
      ]);
    });

    test('一行里写的三个反引号也当行内,不拆成一堆符号', () {
      expect(splitInlineCode('就是 ```miku``` 喵'), [
        (text: '就是 ', code: false),
        (text: 'miku', code: true),
        (text: ' 喵', code: false),
      ]);
    });

    test('落单的反引号原样留着', () {
      expect(splitInlineCode('这个 ` 是手滑'), [(text: '这个 ` 是手滑', code: false)]);
    });
  });

  group('提示词差异', () {
    // NAI5 的提示词是 tag 和句子混写的,句子里本来就有逗号。一律按逗号切的话,
    // 一句话碎成好几截:改一个词报出一串增删,弹层里还把半句话画成芯片。
    List<String> units(String s) => [for (final u in promptUnits(s)) u.text];

    test('纯 tag 串照旧按逗号切', () {
      expect(units('1girl, solo, long hair, 1.2::silver hair::'), [
        '1girl',
        'solo',
        'long hair',
        '1.2::silver hair::',
      ]);
    });

    test('一整句是一个单元,句子里的逗号不切', () {
      expect(
        units(
          'A girl sits on the windowsill, her knees drawn up. '
          'Rain streaks the glass, and grey light outlines her profile.',
        ),
        [
          'A girl sits on the windowsill, her knees drawn up.',
          'Rain streaks the glass, and grey light outlines her profile.',
        ],
      );
    });

    test('句子前头挂着的画师串、tag 还是一枚一枚的', () {
      expect(
        units(
          'artist:foo, 1girl, A girl sits by the window, rain on the glass.',
        ),
        [
          'artist:foo',
          '1girl',
          'A girl sits by the window, rain on the glass.',
        ],
      );
    });

    test('句号只是分隔的不算句子,tag 上的句号去掉', () {
      expect(
        units(
          '2girls, manga, monochrome. Read right to left, then top to bottom.',
        ),
        [
          '2girls',
          'manga',
          'monochrome',
          'Read right to left, then top to bottom.',
        ],
      );
    });

    test('一个句号都没有的混排,短句照旧是逗号分隔的成分', () {
      expect(
        units(
          '1girl, she sits on the windowsill, looking out at the rain, very aesthetic',
        ),
        [
          '1girl',
          'she sits on the windowsill',
          'looking out at the rain',
          'very aesthetic',
        ],
      );
    });

    test('小写开头的句子只合句末连着的长截,不把前面的 tag 吞进去', () {
      expect(
        units(
          '1girl, very aesthetic, soft light filters through the curtains, '
          'casting long shadows.',
        ),
        [
          '1girl',
          'very aesthetic',
          'soft light filters through the curtains, casting long shadows.',
        ],
      );
    });

    test('数里的点、夹在 tag 中间的问号叹号不是句末', () {
      expect(units('1.2::smile::, !?, ?, 1girl'), [
        '1.2::smile::',
        '!?',
        '?',
        '1girl',
      ]);
      expect(units('1girl, ?'), ['1girl', '?']);
    });

    test('单元的区间指回原文', () {
      const s = '1girl,  A girl sits by the window.\nRain streaks the glass.';
      for (final u in promptUnits(s)) {
        expect(s.substring(u.start, u.end), u.text);
      }
    });

    test('句子里改一个词是 +1 −1,不是一串', () {
      final d = diffPrompt(
        'A girl with long silver hair sits by the window, looking outside. '
            'Rain streaks the glass.',
        'A girl with long golden hair sits by the window, looking outside. '
            'Rain streaks the glass.',
      );
      expect(d.added.map((u) => u.text), [
        'A girl with long golden hair sits by the window, looking outside.',
      ]);
      expect(d.removed.map((u) => u.text), [
        'A girl with long silver hair sits by the window, looking outside.',
      ]);
    });

    test('只动了句首大小写、空白、句末标点,不算改', () {
      expect(
        diffPrompt(
          '1girl. She smiles at the viewer.',
          '1girl, she  smiles at the viewer',
        ).isEmpty,
        isTrue,
      );
    });

    test('改过的句子只标出改掉的词', () {
      const before = 'A girl with long silver hair sits by the window.';
      const after = 'A girl with long golden hair sits by the window.';
      final w = markChangedWords(diffPrompt(before, after));
      String cut(String s, List<(int, int)>? r) =>
          [for (final (a, b) in r!) s.substring(a, b)].join(' ');
      expect(cut(after, w.added.single), 'golden');
      expect(cut(before, w.removed.single), 'silver');
    });

    test('tag 数:一句话算一个,角色分区一并算上', () {
      expect(
        countTags(
          '1girl, solo. A girl sits by the window, rain on the glass.',
          ['silver hair, blue eyes', ''],
        ),
        5,
      );
    });

    test('历史列表的 tag 数和结果条同一个数法', () {
      AssistantMsg ai(
        String id, {
        DrawProposal? draw,
        AssistantChange? change,
      }) => AssistantMsg(
        id: id,
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        draw: draw,
        change: change,
      );
      const draw = DrawProposal(
        positive: '2girls. Two girls share an umbrella, walking in the rain.',
        characters: [AgentCharacter(name: 'A', positive: 'red hair, smile')],
      );
      expect(
        ArchivedSession(id: 1, at: 1, msgs: [ai('a', draw: draw)]).tagCount,
        4,
      );
      // 导入过的按写进创作页的那份数,关掉的角色不算
      final change = AssistantChange(
        before: const PromptSnapshot(),
        after: PromptSnapshot(
          positive: 'a, b',
          characters: [
            CharacterPrompt(id: '1', name: 'A', positive: 'c'),
            CharacterPrompt(id: '2', name: 'B', positive: 'd', enabled: false),
          ],
        ),
      );
      expect(
        ArchivedSession(
          id: 1,
          at: 1,
          msgs: [ai('a', draw: draw, change: change)],
        ).tagCount,
        3,
      );
    });

    test('对不上的句子不配对,整句都算新写的', () {
      final w = markChangedWords(
        diffPrompt(
          'A girl sits by the window.',
          'Neon signs flicker over a wet street at night.',
        ),
      );
      expect(w.added.single, isNull);
      expect(w.removed.single, isNull);
    });
  });

  group('差异基线', () {
    // 结果条上那对读数说的是「AI 这轮相对上轮改了什么」,和创作页无关。
    // 原先未导入时拿当前画布当基线,新对话里会凭空算出一堆「移除」——
    // 那些词 AI 根本没见过。
    const d1 = DrawProposal(positive: 'a, b');
    const d2 = DrawProposal(positive: 'a, c');

    AssistantMsg ai(String id, {DrawProposal? draw}) =>
        AssistantMsg(id: id, role: MsgRole.ai, text: 'ok', at: 1, draw: draw);

    test('取上一份提议,不是上一条消息', () {
      final msgs = [
        ai('a1', draw: d1),
        const AssistantMsg(id: 'u1', role: MsgRole.user, text: '再聊聊', at: 1),
        ai('a2'), // 纯聊天轮,没出图
        const AssistantMsg(id: 'u2', role: MsgRole.user, text: '改一下', at: 1),
        ai('a3', draw: d2),
      ];
      expect(prevProposal(msgs, 'a3'), same(d1));
    });

    test('第一份提议没有上一轮', () {
      expect(prevProposal([ai('a1', draw: d1)], 'a1'), isNull);
    });

    test('认不出的 id 当没有', () {
      expect(prevProposal([ai('a1', draw: d1)], 'nope'), isNull);
    });

    test('只往前找,不会捞到后面那份', () {
      final msgs = [ai('a1', draw: d1), ai('a2', draw: d2)];
      expect(prevProposal(msgs, 'a1'), isNull);
      expect(prevProposal(msgs, 'a2'), same(d1));
    });
  });

  group('沿用资源账本', () {
    // 预匹配是逐条消息做的:用户这轮没再提「A1」,[画师串] 块就不出现,画风的出处
    // 断在那儿 —— 下一句「换个姿势」模型就不知道该保留哪串了。账本由服务端算、
    // 按「还在不在这幅画里」筛,客户端负责存和回传(这条链路没有服务端会话)。
    const ledger = {
      'artist': {'A1': 'wlop, as109'},
      'oc': {'OC_小星': 'star hair ornament'},
    };

    test('挂在最新那条 AI 消息上', () {
      final msgs = [
        const AssistantMsg(id: 'u1', role: MsgRole.user, text: '画', at: 1),
        const AssistantMsg(
          id: 'a1',
          role: MsgRole.ai,
          text: 'ok',
          at: 1,
          resources: ledger,
        ),
        const AssistantMsg(id: 'u2', role: MsgRole.user, text: '再改', at: 1),
      ];
      // 末尾那条是用户消息,得往前找到 AI 那条
      expect(latestResources(msgs)['artist'], {'A1': 'wlop, as109'});
    });

    test('一轮都没跑过就是空的', () {
      expect(latestResources(const []), isEmpty);
      expect(
        latestResources(const [
          AssistantMsg(id: 'u1', role: MsgRole.user, text: '画', at: 1),
        ]),
        isEmpty,
      );
    });

    test('取的是最新那条,不是最早那条', () {
      final msgs = [
        const AssistantMsg(
          id: 'a1',
          role: MsgRole.ai,
          text: 'ok',
          at: 1,
          resources: ledger,
        ),
        const AssistantMsg(id: 'a2', role: MsgRole.ai, text: 'ok', at: 2),
      ];
      // 后一轮把画风换掉了(服务端筛完是空的),就该跟着空
      expect(latestResources(msgs), isEmpty);
    });

    test('存得下也读得回来', () {
      const m = AssistantMsg(
        id: 'a1',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        resources: ledger,
      );
      final back = AssistantMsg.fromJson(m.toJson());
      expect(back.resources['artist'], {'A1': 'wlop, as109'});
      expect(back.resources['oc'], {'OC_小星': 'star hair ornament'});
    });

    test('形状不对当空,别让整段会话打不开', () {
      expect(decodeResources(null), isEmpty);
      expect(decodeResources('nope'), isEmpty);
      expect(decodeResources(const {'artist': 'nope'}), isEmpty);
      // 空槽不留,免得回传一堆空对象
      expect(decodeResources(const {'artist': {}}), isEmpty);
    });

    test('老存档没这个字段,读成空', () {
      expect(
        AssistantMsg.fromJson(const {
          'id': 'a1',
          'role': 'ai',
          'text': 'ok',
          'at': 1,
        }).resources,
        isEmpty,
      );
    });
  });

  group('对话模式', () {
    test('记在用户消息上,存得下也读得回来;老存档没这个字段读成正常', () {
      const m = AssistantMsg(
        id: 'u1',
        role: MsgRole.user,
        text: '画个四格',
        at: 1,
        mode: AssistantMode.comic,
      );
      expect(AssistantMsg.fromJson(m.toJson()).mode, AssistantMode.comic);
      // 正常模式不写字段,老存档读回来一个样
      const plain = AssistantMsg(
        id: 'u2',
        role: MsgRole.user,
        text: 'x',
        at: 1,
      );
      expect(plain.toJson().containsKey('mode'), isFalse);
      expect(
        AssistantMsg.fromJson(const {
          'id': 'u3',
          'role': 'user',
          'text': 'x',
          'at': 1,
          'mode': 'nope',
        }).mode,
        AssistantMode.normal,
      );
    });

    test('一段对话的模式取最后一条用户消息的:中途换过就以换完的为准', () {
      expect(conversationMode(const []), AssistantMode.normal);
      final msgs = [
        const AssistantMsg(
          id: 'u1',
          role: MsgRole.user,
          text: 'a',
          at: 1,
          mode: AssistantMode.comic,
        ),
        const AssistantMsg(id: 'a1', role: MsgRole.ai, text: 'ok', at: 2),
        const AssistantMsg(
          id: 'u2',
          role: MsgRole.user,
          text: 'b',
          at: 3,
          mode: AssistantMode.natural,
        ),
        const AssistantMsg(id: 'e1', role: MsgRole.error, text: '断了', at: 4),
      ];
      expect(conversationMode(msgs), AssistantMode.natural);
    });

    test('纯文本格式记在回复上,和模式互不相干;存得下,早先当成模式存的也认', () {
      const m = AssistantMsg(
        id: 'a1',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        mode: AssistantMode.comic,
        noDraw: true,
      );
      final back = AssistantMsg.fromJson(m.toJson());
      expect((back.mode, back.noDraw), (AssistantMode.comic, true));
      const off = AssistantMsg(id: 'a2', role: MsgRole.ai, text: 'x', at: 1);
      expect(off.toJson().containsKey('noDraw'), isFalse);
      final migrated = SessionRepository.migrate({
        'v': 1,
        'current': [
          {'id': 'u3', 'role': 'user', 'text': 'x', 'at': 1, 'mode': 'noDraw'},
        ],
        'sessions': [
          {
            'id': 7,
            'at': 1,
            'msgs': [
              {
                'id': 'e1',
                'role': 'error',
                'text': 'boom',
                'at': 1,
                'errorKind': 'network',
              },
            ],
          },
        ],
      });
      expect(migrated['v'], SessionRepository.schemaVersion);
      final legacy = AssistantMsg.fromJson(
        (migrated['current'] as List).single as Map<String, dynamic>,
      );
      expect((legacy.mode, legacy.noDraw), (AssistantMode.normal, true));
      final err =
          ((migrated['sessions'] as List).single as Map)['msgs'] as List;
      expect((err.single as Map).containsKey('errorKind'), isFalse);
      // 已是当前版本的原样返回
      final current = {'v': SessionRepository.schemaVersion, 'current': []};
      expect(identical(SessionRepository.migrate(current), current), isTrue);
    });

    test('开新对话回到正常', () async {
      final stores = AppStores.ephemeral();
      final c = ProviderContainer(
        overrides: [appStoresProvider.overrideWithValue(stores)],
      );
      addTearDown(() async {
        c.dispose();
        stores.flushNow();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      final n = c.read(assistantProvider.notifier);
      expect(c.read(assistantProvider).mode, AssistantMode.normal);
      n.setMode(AssistantMode.comic);
      expect(c.read(assistantProvider).mode, AssistantMode.comic);
      n.archiveCurrent();
      expect(c.read(assistantProvider).mode, AssistantMode.normal);
    });

    const draw = DrawProposal(
      positive: '2girls, park',
      negative: 'lowres',
      characters: [
        AgentCharacter(name: '芙兰', positive: 'flandre scarlet, smile'),
        AgentCharacter(
          name: '蕾米',
          positive: 'remilia scarlet',
          negative: 'hat',
        ),
      ],
    );

    test('纯文本格式那一轮的提议显示成纯文本;看的是那一轮开没开,不是现在的开关', () {
      const noDraw = AssistantMsg(
        id: 'a1',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        draw: draw,
        noDraw: true,
      );
      expect(noDraw.promptAsText, isTrue);
      // 存盘读回来还是纯文本那种
      expect(AssistantMsg.fromJson(noDraw.toJson()).promptAsText, isTrue);
      // 正常模式的照常出卡;没有提议的纯聊天轮无所谓显示成什么
      const normal = AssistantMsg(
        id: 'a2',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        draw: draw,
      );
      expect(normal.promptAsText, isFalse);
      const chat = AssistantMsg(
        id: 'a3',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        noDraw: true,
      );
      expect(chat.promptAsText, isFalse);
    });

    test('纯文本写法:全局正向在前,角色一行一个 charN:,角色负向跟在后面,全局负向单列', () {
      final t = promptTextOf(draw);
      expect(
        t.positive,
        '2girls, park\n'
        'char1: flandre scarlet, smile\n'
        'char2: remilia scarlet\n'
        '[char2-] hat',
      );
      expect(t.negative, 'lowres');
      // 和法典 / web 的 charN 解析器是同一套写法:复制出去再贴回来,角色拆得开
      final back = splitCodexCharacters(t.positive);
      expect(back.base, '2girls, park');
      expect(
        [for (final c in back.characters) c.positive],
        ['flandre scarlet, smile', 'remilia scarlet'],
      );
      expect(back.characters[1].negative, 'hat');
      // 单角色场景没有 characters,就只有正向那一行
      expect(
        promptTextOf(const DrawProposal(positive: '1girl')).positive,
        '1girl',
      );
    });
  });

  group('工具:预取资料块', () {
    const a1 = '[[artist:as109]],{{artist:wlop}},1.3::artist:hiten::';
    const d11 =
        '<artist>\n2.4::harukui::,1.4::urotsuki_(ku9625)::\n</artist>\n\n'
        '<style>\nthick paint, painterly,\ncel rendering,\n</style>,';
    final artists = libArtistsOf([
      {'id': 'A1', 'name': 'A1', 'prompt': a1},
      {'id': 'D11', 'name': 'D11', 'prompt': d11},
      {'id': '厚涂 风', 'name': '厚涂 风', 'prompt': 'thick paint'},
      {'id': 'E5', 'name': 'E5', 'prompt': '   '},
    ]);
    final ocs = libOcsOf([
      {
        'en_name': 'OC_DeepSeek',
        'zh_name': 'DeepSeek',
        'zh_aliases': <String>[],
        'tag_group': 'blue hair',
      },
      {
        'en_name': 'local-1',
        'zh_name': '小小纺',
        'zh_aliases': ['阿纺'],
        'tag_group': 'silver hair, twin braids',
      },
    ]);
    final texts = _texts();

    ToolContext ctx(
      String text, {
      Map<String, Map<String, String>> remembered = const {},
      ToolSettings settings = const ToolSettings(),
      TagLookup? offline,
      OnlineTags? online,
    }) => ToolContext(
      userText: text,
      settings: settings,
      texts: texts,
      artists: artists,
      ocs: ocs,
      remembered: remembered,
      offline: offline,
      online: online,
    );

    test('编号不分大小写、名字去掉空白标点再比,没内容的条目不认', () {
      expect(matchArtists('a1 和厚涂风,还有 e5', artists), [
        ('A1', a1),
        ('厚涂 风', 'thick paint'),
      ]);
      // 名字规范化后只有 1 个字的不按名字认:在任何一句话里都能撞上
      final single = libArtistsOf([
        {'id': '风', 'name': '风', 'prompt': 'artist:wind'},
      ]);
      expect(matchArtists('画一张风景', single), isEmpty);
    });

    test('编号只认整段:A12 不带出 A1,三位编号也认', () {
      final coded = libArtistsOf([
        {'id': 'A1', 'name': 'A1', 'prompt': 'artist:a'},
        {'id': 'A10', 'name': 'A10', 'prompt': 'artist:b'},
        {'id': 'A12', 'name': 'A12', 'prompt': 'artist:c'},
        {'id': 'A105', 'name': 'A105', 'prompt': 'artist:d'},
      ]);
      expect(matchArtists('用 A12 画', coded), [('A12', 'artist:c')]);
      expect(matchArtists('a105 那个', coded), [('A105', 'artist:d')]);
    });

    test('OC 认中文名、别名和去掉 OC_ 的键名,命中的名字越长越靠前', () {
      expect(matchOcs('阿纺、小小纺和 deep seek', ocs), [
        ('DeepSeek', 'blue hair'),
        ('小小纺、阿纺', 'silver hair, twin braids'),
      ]);
    });

    test('[画师串] 只给占位符,多行内容一行都不漏;[OC 角色] 给完整 tag 组', () async {
      final c = ctx('用 D11 画小小纺');
      final artist = await const SearchArtistTool().prefetch(c);
      expect(
        artist!.text,
        '[画师串]\n${texts.get('artist_block_note')}\nD11 → __ARTIST_D11__',
      );
      expect(artist.resources, {
        'artist': {'D11': d11},
      });
      expect(c.artistPlan.tokens, {'__ARTIST_D11__': d11});
      final oc = await const SearchOcTool().prefetch(c);
      expect(oc!.text, '[OC 角色]\n小小纺 → silver hair, twin braids');
    });

    test('开着 OC 占位符:只给占位符,这轮没点到就补账本里记着的', () async {
      const on = ToolSettings(enabledOptions: {kOcPlaceholdersOption});
      final first = await const SearchOcTool().prefetch(
        ctx('画小小纺', settings: on),
      );
      expect(first!.text, contains('小小纺 → __OC_小小纺__'));
      expect(first.text, isNot(contains('twin braids')));
      final later = ctx(
        '换个姿势',
        settings: on,
        remembered: const {
          'oc': {'深海': 'blue eyes, shell crown'},
        },
      );
      final block = await const SearchOcTool().prefetch(later);
      expect(block!.text, contains('深海 → __OC_深海__'));
      expect(block.text, isNot(contains('shell crown')));
      expect(later.ocPlan.tokens['__OC_深海__'], 'blue eyes, shell crown');
      final draw = expandOcDraw({
        'positive': '__OC_深海__, sea',
        'characters': [
          {'name': '小小纺', 'positive': '__OC_小小纺__, smiling'},
        ],
      }, later.ocPlan)!;
      expect(draw['positive'], 'blue eyes, shell crown, sea');
      expect(
        (draw['characters'] as List).single['positive'],
        'silver hair, twin braids, smiling',
      );
    });

    test('这轮没点到的画师串用账本补上,OC 不补;补上的不算本轮命中', () async {
      final c = ctx(
        '换个姿势',
        remembered: {
          'artist': {'A1': a1},
          'oc': {'小小纺': 'silver hair, twin braids'},
        },
      );
      final artist = await const SearchArtistTool().prefetch(c);
      expect(artist!.text, contains('A1 → __ARTIST_A1__'));
      expect(artist.resources['artist'], isEmpty);
      expect(
        await const SearchOcTool().prefetch(c),
        isNull,
        reason: 'OC 只活在点到它的那一轮',
      );
    });

    test('[角色候选] 来自离线词库,出处取 tag 末尾的括号;离线来源关着就不预取', () async {
      final offline = _FakeOffline(
        roles: const [
          (
            tag: 'shiroko_(blue_archive)',
            zh: '砂狼白子',
            count: 11429,
            category: 4,
          ),
        ],
      );
      final b = await const SearchCharacterTool().prefetch(
        ctx('画白子', offline: offline),
      );
      expect(
        b!.text,
        '[角色候选]\nshiroko_(blue_archive) → 中文: 砂狼白子 / 出处: blue archive',
      );
      expect(
        await const SearchCharacterTool().prefetch(ctx('画白子')),
        isNull,
        reason: '离线词库读不出来就不给块',
      );
    });

    test('[角色候选] 有后端时交后端筛,判不了就全留', () async {
      final offline = _FakeOffline(
        roles: const [
          (tag: 'flandre_scarlet', zh: '芙兰朵露', count: 58619, category: 4),
          (tag: 'fran_(ff12)', zh: '芙兰', count: 546, category: 4),
        ],
      );
      final kept = _FakeOnline(kept: ['flandre_scarlet']);
      final b = await const SearchCharacterTool().prefetch(
        ctx('画芙兰', offline: offline, online: kept),
      );
      expect(kept.filtered, [
        ['flandre_scarlet', 'fran_(ff12)'],
      ]);
      expect(b!.text, contains('flandre_scarlet'));
      expect(b.text, isNot(contains('fran_(ff12)')));

      final none = await const SearchCharacterTool().prefetch(
        ctx(
          '画芙兰',
          offline: offline,
          online: _FakeOnline(kept: const []),
        ),
      );
      expect(none, isNull, reason: '全被筛掉就不给块');

      final unsure = await const SearchCharacterTool().prefetch(
        ctx('画芙兰', offline: offline, online: _FakeOnline()),
      );
      expect(unsure!.text, contains('fran_(ff12)'));

      final local = await const SearchCharacterTool().prefetch(
        ctx('画芙兰', offline: offline),
      );
      expect(local!.text, contains('fran_(ff12)'), reason: '没有后端就不筛');
    });

    test('旧账本里只记下第一行的多行画师串,按本地库补全', () {
      final healed = healRememberedArtists({
        'artist': {'D11': '<artist>', 'A1': 'artist:old'},
      }, artists);
      expect(healed['artist'], {'D11': d11, 'A1': 'artist:old'});
    });
  });

  group('本地资料:占位符还原与账本', () {
    const a1 = '[[artist:as109]],{{artist:wlop}},1.3::artist:hiten::';
    final artists = libArtistsOf([
      {'id': 'A1', 'name': 'A1', 'prompt': a1},
      {'id': '厚涂 风', 'name': '厚涂 风', 'prompt': 'artist:rella'},
    ]);
    const tokens = {'__ARTIST_A1__': a1};

    test('画布和历史里逐字相同的画师串折成占位符,改过的不动', () {
      expect(
        collapseArtistStrings('positive: $a1, 1girl', tokens),
        'positive: __ARTIST_A1__, 1girl',
      );
      const edited = 'positive: [[artist:as109]], 1girl';
      expect(collapseArtistStrings(edited, tokens), edited);
    });

    test('认得的逐字换回(权重包着也行、写歪了也认),认不出的连逗号和空壳一起删', () {
      final plan = ArtistPlan()..add('A1', a1);
      final resolve = artistResolver(plan, artists);
      expect(
        expandArtistText('1.2::__ARTIST_A1__::, 1girl', resolve).text,
        '1.2::$a1::, 1girl',
      );
      final r = expandArtistText(
        '__artist_a1__, __ARTIST_A1__, {__ARTIST_Z9__}, 0.8::__ARTIST_C3__::, 1girl',
        resolve,
      );
      expect(r.text, '$a1, 1girl');
      expect(r.used, ['A1']);
      expect(r.notes, hasLength(2));
    });

    test('模型自己又抄了一遍完整串的,只删占位符', () {
      final resolve = artistResolver(ArtistPlan()..add('A1', a1), artists);
      expect(
        expandArtistText('__ARTIST_A1__, $a1, 1girl', resolve).text,
        '$a1, 1girl',
      );
    });

    test('映射里没有的去本地库查,查到的记进映射', () {
      final plan = ArtistPlan();
      final resolve = artistResolver(plan, artists);
      expect(
        expandArtistText('__ARTIST_厚涂_风__, 1girl', resolve).text,
        'artist:rella, 1girl',
      );
      expect(plan.tokens, {'__ARTIST_厚涂_风__': 'artist:rella'});
      expect(
        namesInReply('用了 __ARTIST_厚涂_风__ 和 __ARTIST_Q1__', resolve),
        '用了 厚涂 风 和 Q1',
      );
    });

    test('查画风返回 placeholder,查到的画师串作为资源报上来', () async {
      final out = await const SearchArtistTool().call(
        ToolContext(
          userText: '',
          settings: const ToolSettings(),
          texts: _texts(),
          artists: artists,
        ),
        {
          'artist_ids': ['a1'],
        },
      );
      expect((out.data as List).single['placeholder'], '__ARTIST_A1__');
      expect(out.resources, {
        'artist': {'A1': a1},
      });
    });

    test('还在不在用:整串原样在,或者规范化后命中两枚以上的 tag', () {
      expect(
        resourceStillInUse('1.2::mika_pikazo::, ask_\\(askzy\\)', {
          'positive': 'mika pikazo, 1.4::ask (askzy)::',
        }),
        isTrue,
      );
      expect(
        resourceStillInUse('silver hair, twin braids, purple eyes', {
          'positive': 'a girl with silver hair and purple eyes',
        }),
        isTrue,
      );
      expect(
        resourceStillInUse('银发, 双马尾', {
          'positive': '1girl',
          'characters': [
            {'positive': '银发少女'},
          ],
        }),
        isFalse,
      );
    });

    test('收尾记账:本轮 ∪ 记着的,出了图才按画面筛;OC 一律不进账', () {
      const remembered = {
        'artist': {'A1': a1, 'Q9': 'artist:gone'},
        'oc': {'小小纺': 'silver hair, twin braids'}, // 旧版记下的
      };
      const thisTurn = {
        'oc': {'小小纺': 'silver hair, twin braids'},
      };
      expect(mergeLedger(remembered, thisTurn, null), {
        'artist': {'A1': a1, 'Q9': 'artist:gone'},
      });
      expect(
        mergeLedger(remembered, thisTurn, {
          'positive': '$a1, 1girl',
          'characters': [
            {'positive': 'silver hair, twin braids, smile'},
          ],
        }),
        {
          'artist': {'A1': a1},
        },
      );
    });

    test('查我的库:按编号 / 关键词找画师串,OC 按名字找', () {
      expect(searchArtists(artists, {'keyword': 'RELLA'}).single.id, '厚涂 风');
      expect(searchArtists(artists, {'keyword': '  '}), isEmpty);
      final ocs = searchOcs(
        libOcsOf([
          {
            'en_name': 'OC_DeepSeek',
            'zh_name': 'DeepSeek',
            'zh_aliases': ['深度求索'],
            'tag_group': 'blue hair',
          },
        ]),
        'deep seek',
      );
      expect(ocs.single.tagGroup, 'blue hair');
      expect(ocs.single.aliases, ['深度求索']);
    });
  });

  group('自定义接口:一轮在本机跑', () {
    const d11 =
        '<artist>\n1.2::harukui::,\n</artist>\n\n<style>\nthick paint,\n</style>,';
    const a1 = '[[artist:as109]],{{artist:wlop}}';
    const endpoint = CustomEndpoint(
      id: 'e',
      name: 'e',
      format: AgentApiFormat.openai,
      baseUrl: 'https://llm.test',
      apiKey: 'k',
      model: 'm',
    );
    final library = (
      artists: [
        {'id': 'D11', 'name': 'D11', 'prompt': d11},
        {'id': 'B7', 'name': 'B7', 'prompt': 'artist:rella'},
      ],
      ocs: [
        {
          'en_name': 'local-1',
          'zh_name': '小小纺',
          'zh_aliases': <String>[],
          'tag_group': 'silver hair, twin braids',
        },
        {
          'en_name': 'local-2',
          'zh_name': '深海',
          'zh_aliases': <String>[],
          'tag_group': 'blue eyes, shell crown',
        },
      ],
    );

    http.Response modelSays(String text) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': text},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    http.Response channelSays(String text) => http.Response(
      ': open\n\nevent: final\ndata: ${jsonEncode({'text': text, 'reasoning': ''})}\n\n',
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );

    http.Response channelError(Map<String, Object?> data) => http.Response(
      ': open\n\nevent: error\ndata: ${jsonEncode(data)}\n\n',
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );

    /// [backend] 为 true 时走后端的模型通道,否则直连 [endpoint]。
    Future<List<AgentEvent>> run(
      MockClient mock, {
      String userRequest = '用 D11 画小小纺',
      List<Uint8List> images = const [],
      ToolSettings tools = const ToolSettings(),
      TagLookup? offline,
      OnlineTags? online,
      bool stream = true,
      bool backend = false,
      int retries = AssistantSettings.retriesDefault,
      bool retryStripImage = false,
      int rerolls = AssistantSettings.rerollsDefault,
      List<String> refusalKeywords = kRefusalKeywords,
      AgentTrace? trace,
    }) => http.runWithClient(
      () =>
          agentRuntimeFor(
                endpoint: backend ? null : endpoint,
                backendBase: 'https://plana.test',
                sessionId: 'sid',
                backendModel: 'glm',
                imageModel: 'nai_v45_full',
                offline: offline,
                online: online,
              )
              .run(
                AgentTurnRequest(
                  userText: userRequest,
                  images: images,
                  imageModel: 'nai_v45_full',
                  customRules: const [
                    PresetRule(name: 'role', content: '你是画师'),
                  ],
                  canvas: const CanvasSnapshot(
                    positive: '$a1, 1girl',
                    negative: '',
                    characters: [],
                  ),
                  history: const [
                    {'role': 'user', 'content': '上一轮'},
                    {'role': 'assistant', 'content': 'positive: $a1'},
                  ],
                  tools: tools,
                  artists: library.artists,
                  ocs: library.ocs,
                  resources: const {
                    'artist': {'A1': a1},
                  },
                  stream: stream,
                  retries: retries,
                  retryStripImage: retryStripImage,
                  rerolls: rerolls,
                  refusalKeywords: refusalKeywords,
                ),
                trace: trace,
              )
              .toList(),
      () => mock,
    );

    test('只请求模型接口;预取、查库、还原、记账都在本机', () async {
      final others = <http.Request>[];
      final model = <String>[];
      final mock = MockClient((req) async {
        if (req.url.host != 'llm.test') {
          others.add(req);
          return http.Response('{}', 404);
        }
        model.add(req.body);
        return modelSays(
          model.length == 1
              ? '```tool_call\n{"name": "search_artist", "arguments": {"artist_ids": ["B7"]}}\n```'
              : '用 __ARTIST_D11__ 和 __ARTIST_B7__ 画好了\n```nai_draw\n'
                    '{"positive": "1.2::__ARTIST_D11__::, __ARTIST_B7__, 1girl, silver hair, twin braids", '
                    '"negative": "", "characters": []}\n```',
        );
      });

      final events = await run(
        mock,
        offline: _FakeOffline(
          roles: const [
            (tag: 'flandre_scarlet', zh: '芙兰朵露', count: 58619, category: 4),
          ],
        ),
      );

      expect(others, isEmpty, reason: '自定义接口那条不打 Plana 后端');
      expect(model.first, contains('D11 → __ARTIST_D11__'));
      expect(model.first, contains('小小纺 → silver hair, twin braids'));
      expect(model.first, contains('[角色候选]'));
      expect(model.first, contains('[可用工具]'));
      expect(model.first, isNot(contains('harukui')));
      expect(model.first, isNot(contains('as109')), reason: '画布、历史里的串折成占位符');
      expect(model.last, contains('__ARTIST_B7__'), reason: '工具结果回灌');

      final done = events.whereType<AgentDone>().single.result;
      expect(
        done.positive,
        '1.2::$d11::, artist:rella, 1girl, silver hair, twin braids',
      );
      expect(done.replyText, '用 D11 和 B7 画好了');
      expect(done.resources, {
        'artist': {'D11': d11, 'B7': 'artist:rella'},
      }, reason: '工具查到、用进画面的画师串也进账本;没再用的 A1 筛掉');
    });

    test('查角色:语义搜词在前、离线词库补后,重复的去掉', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(
          model.length == 1
              ? '```tool_call\n{"name": "search_character", "arguments": {"query": "芙兰", "origin": "东方"}}\n```'
              : '好',
        );
      });
      final online = _FakeOnline(
        hits: const [
          (
            tag: 'flandre_scarlet',
            zh: '芙兰朵露·斯卡雷特、东方Project',
            count: 58619,
            wiki: '红魔馆的二小姐',
          ),
        ],
      );
      final offline = _FakeOffline(
        chars: const [
          (tag: 'flandre_scarlet', zh: '芙兰朵露', count: 58619, category: 4),
          (tag: 'fran_(ff12)', zh: '芙兰', count: 546, category: 4),
        ],
      );
      await run(mock, userRequest: '画芙兰', online: online, offline: offline);
      expect(online.asked, ['东方 芙兰']);
      final result = model.last;
      expect(result.indexOf('红魔馆的二小姐'), greaterThan(-1));
      expect(
        result.indexOf('fran_(ff12)'),
        greaterThan(result.indexOf('红魔馆的二小姐')),
      );
      expect('flandre_scarlet'.allMatches(result), hasLength(1));
    });

    test('OC 占位符:预取、查 OC 的结果都只给占位符,出图前展开', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(
          model.length == 1
              ? '```tool_call\n{"name": "search_oc", "arguments": {"query": "深海"}}\n```'
              : '```nai_draw\n{"positive": "__OC_深海__, sea", "characters": [{"name": "小小纺", "positive": "__OC_小小纺__, smiling"}]}\n```',
        );
      });
      final events = await run(
        mock,
        userRequest: '画小小纺',
        tools: const ToolSettings(enabledOptions: {kOcPlaceholdersOption}),
      );
      expect(model.first, contains('小小纺 → __OC_小小纺__'));
      expect(model.first, contains('[OC 占位符模式]'));
      expect(model.last, contains('"tags\\":\\"__OC_深海__'));
      for (final request in model) {
        expect(request, isNot(contains('twin braids')));
        expect(request, isNot(contains('shell crown')));
      }
      final done = events.whereType<AgentDone>().single.result;
      expect(done.positive, 'blue eyes, shell crown, sea');
      expect(
        done.characters.single.positive,
        'silver hair, twin braids, smiling',
      );
      expect(done.resources['oc'], {
        '小小纺': 'silver hair, twin braids',
        '深海': 'blue eyes, shell crown',
      });
    });

    test('关掉逐字显示:一帧 AgentDelta 都不推', () async {
      final mock = MockClient((req) async => modelSays('好'));
      final events = await run(mock, stream: false);
      expect(events.whereType<AgentDelta>(), isEmpty);
      expect(events.whereType<AgentDone>().single.result.replyText, '好');
    });

    test('工具全关:不预取,系统提示里没有工具;账本里的画师串照样折', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays('好');
      });
      await run(
        mock,
        tools: ToolSettings(
          disabledTools: {for (final t in kAgentTools) t.name},
        ),
      );
      expect(model.single, isNot(contains('[可用工具]')));
      expect(model.single, isNot(contains('<tool_usage>')));
      expect(model.single, isNot(contains('[画师串]')));
      expect(model.single, isNot(contains('as109')));
    });

    test('调了没开的工具:回灌「没有这个工具」,这一轮照常收尾', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(
          model.length == 1
              ? '```tool_call\n{"name": "lookup_tag", "arguments": {"query": "halo"}}\n```'
              : '查不了,直接说喵',
        );
      });
      final events = await run(
        mock,
        tools: const ToolSettings(disabledTools: {'lookup_tag'}),
      );
      expect(model.last, contains('没有这个工具'));
      expect(events.whereType<AgentDone>().single.result.replyText, '查不了,直接说喵');
    });

    test('写坏的 tool_call:回灌原文和原因,同一条里别的调用照常执行', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(
          model.length == 1
              ? '```tool_call\n{坏了\n```\n'
                    '```tool_call\n{"name": "lookup_tag", "arguments": {"query": "halo"}}\n```'
              : '好',
        );
      });
      final events = await run(mock);
      expect(model, hasLength(2));
      expect(model.last, contains('[tool_result 共 2 条]'));
      expect(model.last, contains('写坏了'));
      expect(model.last, contains('{坏了'));
      expect(events.whereType<AgentToolCall>().single.name, 'lookup_tag');
    });

    test('同工具同参数:只真跑一次,再调给上次结果和提醒', () async {
      final model = <String>[];
      final online = _FakeOnline();
      const call =
          '```tool_call\n{"name": "search_character", "arguments": {"query": "芙兰"}}\n```';
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(model.length <= 2 ? call : '好');
      });
      await run(mock, online: online);
      expect(online.asked, ['芙兰']);
      expect(model[1], isNot(contains('完全相同')));
      expect(model[2], contains('完全相同'));
    });

    test('同一跳的几个调用并行跑,结果按调用顺序回', () async {
      final online = _GatedOnline();
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return modelSays(
          n == 1
              ? '```tool_call\n{"name": "search_character", "arguments": {"query": "芙兰"}}\n```\n'
                    '```tool_call\n{"name": "search_character", "arguments": {"query": "蕾米"}}\n```'
              : '好',
        );
      });
      final events = await run(
        mock,
        online: online,
      ).timeout(const Duration(seconds: 5));
      expect(online.asked, ['芙兰', '蕾米']);
      expect(
        [
          for (final e in events)
            if (e is AgentToolCall)
              'call:${e.args['query']}'
            else if (e is AgentToolResult)
              'result',
        ],
        ['call:芙兰', 'call:蕾米', 'result', 'result'],
      );
    });

    test('工具轮数用完还在调:不执行,回灌让它直接收尾', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(
          model.length <= 4
              ? '```tool_call\n{"name": "lookup_tag", "arguments": {"query": "q${model.length}"}}\n```'
              : '好',
        );
      });
      final events = await run(mock);
      expect(model, hasLength(5));
      expect(model[4], contains('工具调用次数已经用完'));
      expect(events.whereType<AgentToolCall>(), hasLength(3));
      expect(events.whereType<AgentDone>().single.result.replyText, '好');
    });

    test('出图块没写完:回灌让模型重写', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(
          model.length == 1
              ? '画好了\n```nai_draw\n{"positive": "1gi'
              : '画好了\n```nai_draw\n{"positive": "1girl"}\n```',
        );
      });
      final events = await run(mock);
      expect(model, hasLength(2));
      expect(model.last, contains('没写完'));
      final done = events.whereType<AgentDone>().single.result;
      expect(done.positive, '1girl');
      expect(done.replyText, '画好了');
    });

    test('回灌两次还写不对:换下一次尝试,资料块照带,都不行就报错带原文', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays('画好了\n```nai_draw\n{"positive": ""}\n```');
      });
      await expectLater(
        run(mock),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'message',
            contains('{"positive": ""}'),
          ),
        ),
      );
      expect(model, hasLength(12), reason: '四次尝试,各回灌两次');
      expect(model[0], contains('D11 → __ARTIST_D11__'));
      expect(model[3], model[0], reason: '没附图,原样再发');
      expect(model[9], model[0]);
    });

    test('失败重试按设置的次数,关掉就不重试', () async {
      for (final (retries, want) in [(0, 1), (1, 2), (4, 5)]) {
        var n = 0;
        final mock = MockClient((req) async {
          n++;
          return modelSays('');
        });
        await expectLater(
          run(mock, retries: retries),
          throwsA(isA<AgentFailure>()),
        );
        expect(n, want, reason: 'retries=$retries');
      }
    });

    test('失败重试默认保留附图,开剥图开关后仅最后一次重试剥图', () async {
      final png = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final b64 = base64Encode(png);
      List<Object?> retryNoImages(AgentTrace t) => [
        for (final e in t.events)
          if (e['event'] == 'retry') (e['data'] as Map)['no_image'],
      ];

      // 默认关闭:每次重试都保留附图
      final keepBodies = <String>[];
      final keepTrace = AgentTrace(
        startedAt: 0,
        route: AgentTrace.routeCustom,
        userText: '画这个',
      );
      await expectLater(
        run(
          MockClient((req) async {
            keepBodies.add(req.body);
            return modelSays('');
          }),
          images: [png],
          retries: 3,
          trace: keepTrace,
        ),
        throwsA(isA<AgentFailure>()),
      );
      expect(keepBodies, hasLength(4));
      for (final b in keepBodies) {
        expect(b, contains(b64));
        expect(b, isNot(contains('已剥去图片')));
      }
      expect(retryNoImages(keepTrace), [false, false, false]);

      // 开启后:前两次重试保留附图,最后一次重试才剥图
      final stripBodies = <String>[];
      final stripTrace = AgentTrace(
        startedAt: 0,
        route: AgentTrace.routeCustom,
        userText: '画这个',
      );
      final events = await run(
        MockClient((req) async {
          stripBodies.add(req.body);
          return modelSays(stripBodies.length < 4 ? '' : '好');
        }),
        images: [png],
        retries: 3,
        retryStripImage: true,
        trace: stripTrace,
      );
      expect(events.whereType<AgentDone>().single.result.replyText, '好');
      expect(stripBodies, hasLength(4));
      for (var i = 0; i < 3; i++) {
        expect(stripBodies[i], contains(b64), reason: 'attempt $i 应保留附图');
        expect(stripBodies[i], isNot(contains('已剥去图片')));
      }
      expect(stripBodies[3], isNot(contains(b64)), reason: '最后一次重试应剥图');
      expect(stripBodies[3], contains('已剥去图片'));
      expect(retryNoImages(stripTrace), [false, false, true]);

      // 重试次数为 1 时,这唯一一次重试就是最后一次
      final oneBodies = <String>[];
      final oneTrace = AgentTrace(
        startedAt: 0,
        route: AgentTrace.routeCustom,
        userText: '画这个',
      );
      await expectLater(
        run(
          MockClient((req) async {
            oneBodies.add(req.body);
            return modelSays('');
          }),
          images: [png],
          retries: 1,
          retryStripImage: true,
          trace: oneTrace,
        ),
        throwsA(isA<AgentFailure>()),
      );
      expect(oneBodies, hasLength(2));
      expect(oneBodies[0], contains(b64));
      expect(oneBodies[1], isNot(contains(b64)));
      expect(oneBodies[1], contains('已剥去图片'));
      expect(retryNoImages(oneTrace), [true]);
    });

    test('空回、只有思考没有正文:换下一次尝试', () async {
      for (final empty in ['', '<Think>想了想</Think>']) {
        final model = <String>[];
        final mock = MockClient((req) async {
          model.add(req.body);
          return modelSays(model.length == 1 ? empty : '好');
        });
        final events = await run(mock);
        expect(model, hasLength(2));
        expect(events.whereType<AgentDone>().single.result.replyText, '好');
      }
    });

    test('密钥不对:不重试', () async {
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return http.Response('{"error": "bad key"}', 401);
      });
      await expectLater(run(mock), throwsA(isA<AgentFailure>()));
      expect(n, 1);
    });

    test('回复像拒绝:原上下文原地重掷,什么都不回灌', () async {
      final model = <String>[];
      final mock = MockClient((req) async {
        model.add(req.body);
        return modelSays(model.length <= 2 ? '这个我画不了' : '好');
      });
      final events = await run(mock);
      expect(model, hasLength(3));
      expect(model[1], model[0]);
      expect(model[2], model[0]);
      expect(events.whereType<AgentDone>().single.result.replyText, '好');
    });

    test('重掷用完还像拒绝:报错收场,不再降级', () async {
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return modelSays('这个我画不了');
      });
      await expectLater(
        run(mock),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'message',
            contains('画不了'),
          ),
        ),
      );
      expect(n, 4);
    });

    test('拒绝重试按设置的次数,关掉就不判拒绝、回复照常交出', () async {
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return modelSays('这个我画不了');
      });
      await expectLater(run(mock, rerolls: 4), throwsA(isA<AgentFailure>()));
      expect(n, 5);

      n = 0;
      final events = await run(mock, rerolls: 0);
      expect(n, 1);
      expect(events.whereType<AgentDone>().single.result.replyText, '这个我画不了');
    });

    test('拒绝关键词按设置的词表判', () async {
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return modelSays(n == 1 ? '换个话题吧' : '这个我画不了');
      });
      final events = await run(mock, refusalKeywords: const ['换个话题']);
      expect(n, 2);
      expect(events.whereType<AgentDone>().single.result.replyText, '这个我画不了');
    });

    test('后端模型:经模型通道跑同一个循环,一跳一个请求,历史与本轮分开发', () async {
      final bodies = <Map<String, dynamic>>[];
      final others = <String>[];
      final auth = <String?>{};
      final mock = MockClient((req) async {
        if (req.url.toString() != 'https://plana.test/api/agent/channel') {
          others.add('${req.url}');
          return http.Response('{}', 404);
        }
        auth.add(req.headers['Authorization']);
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return channelSays(
          bodies.length == 1
              ? '```tool_call\n{"name": "search_artist", "arguments": {"artist_ids": ["B7"]}}\n```'
              : '画好了\n```nai_draw\n{"positive": "__ARTIST_B7__, 1girl"}\n```',
        );
      });
      final events = await run(mock, backend: true);

      expect(others, isEmpty);
      expect(auth, {'Bearer sid'});
      expect(bodies, hasLength(2));
      expect(bodies.first['model'], 'glm');
      expect(bodies.first['image_model'], 'nai_v45_full');
      expect(bodies.first['system'], contains('[可用工具]'));
      expect(
        [for (final m in bodies.first['history'] as List) m['role']],
        ['user', 'assistant'],
      );
      expect(
        [for (final m in bodies.last['messages'] as List) m['role']],
        ['user', 'assistant', 'user'],
        reason: '本轮的工具往返跟在用户那条后面',
      );
      expect(bodies.last['turn_id'], bodies.first['turn_id']);
      final done = events.whereType<AgentDone>().single.result;
      expect(done.positive, 'artist:rella, 1girl');
      expect(done.replyText, '画好了');
      expect(
        agentRuntimeFor(
          endpoint: null,
          backendBase: 'https://plana.test',
          sessionId: '',
          backendModel: '',
          imageModel: 'nai_v45_full',
        ).route,
        AgentTrace.routeBackend,
      );
    });

    test('后端判为拒绝且重掷用尽、后端自己拒掉的请求:都不再降级重试', () async {
      var n = 0;
      final refused = MockClient((req) async {
        n++;
        return channelError({'message': '重掷 2 次后仍判为拒绝生成', 'code': 'refused'});
      });
      await expectLater(
        run(refused, backend: true),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'message',
            '重掷 2 次后仍判为拒绝生成',
          ),
        ),
      );
      expect(n, 1);

      n = 0;
      final limited = MockClient((req) async {
        n++;
        return http.Response(
          '{"detail": "生成太频繁了"}',
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await expectLater(
        run(limited, backend: true),
        throwsA(isA<AgentFailure>()),
      );
      expect(n, 1);
    });

    test('后端模型上游一时出错:照常降级重试', () async {
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return n == 1
            ? channelError({
                'message': 'status_code: 503, model error: busy',
                'code': 'upstream',
                'status': 503,
              })
            : channelSays('好');
      });
      final events = await run(mock, backend: true);
      expect(n, 2);
      expect(events.whereType<AgentDone>().single.result.replyText, '好');
    });

    test('出图轮不判拒绝', () async {
      var n = 0;
      final mock = MockClient((req) async {
        n++;
        return modelSays(
          '不能画太露骨的,换成这样\n```nai_draw\n{"positive": "1girl"}\n```',
        );
      });
      final events = await run(mock);
      expect(n, 1);
      expect(events.whereType<AgentDone>().single.result.positive, '1girl');
    });
  });

  group('后端模型通道', () {
    PlanaChannelProvider provider() => PlanaChannelProvider(
      baseUrl: 'https://plana.test',
      sessionId: '',
      model: 'glm',
      imageModel: 'nai_v5_full',
      turnId: 't1',
    );
    const sse = {'content-type': 'text/event-stream; charset=utf-8'};

    Future<List<LlmText>> chat(http.Response r) => provider()
        .chat(
          const LlmRequest(
            system: 's',
            messages: [(role: 'user', content: 'x', images: [])],
          ),
          client: MockClient((req) async => r),
        )
        .toList();

    test('请求体:messages 在 turnStart 处切成历史与本轮,图跟着本轮那条', () {
      final body = provider().requestBody(
        const LlmRequest(
          system: 'sys',
          messages: [
            (role: 'user', content: '上一轮', images: []),
            (role: 'assistant', content: '嗯', images: []),
            (
              role: 'user',
              content: '照这几张画',
              images: [
                (mime: 'image/png', data: 'AAAA'),
                (mime: 'image/jpeg', data: 'BBBB'),
              ],
            ),
            (role: 'assistant', content: '查一下', images: []),
          ],
          turnStart: 2,
        ),
      );
      expect(body['history'], [
        {'role': 'user', 'content': '上一轮'},
        {'role': 'assistant', 'content': '嗯'},
      ]);
      expect(body['messages'], [
        // 老后端只认 image:放第一张;新后端认 images
        {
          'role': 'user',
          'content': '照这几张画',
          'image': {'mime': 'image/png', 'data': 'AAAA'},
          'images': [
            {'mime': 'image/png', 'data': 'AAAA'},
            {'mime': 'image/jpeg', 'data': 'BBBB'},
          ],
        },
        {'role': 'assistant', 'content': '查一下'},
      ]);
      expect(body['system'], 'sys');
      expect(body['turn_id'], 't1');
      expect(body['image_model'], 'nai_v5_full');
    });

    test('心跳行不认,final 一帧给全文与原生思考', () async {
      final frames = await chat(
        http.Response(
          ': open\n\n: ping\n\nevent: final\ndata: {"text": "好的", "reasoning": "想"}\n\n',
          200,
          headers: sse,
        ),
      );
      expect(frames, [(text: '好的', reasoning: '想')]);
    });

    test('error 事件原样报;重掷过的拒绝、等满的超时不再降级重试,上游错可以', () async {
      Future<AgentFailure> failure(Map<String, Object?> data) async {
        try {
          await chat(
            http.Response(
              'event: error\ndata: ${jsonEncode(data)}\n\n',
              200,
              headers: sse,
            ),
          );
        } on AgentFailure catch (e) {
          return e;
        }
        fail('应该抛 AgentFailure');
      }

      final refused = await failure({'message': '判为拒绝', 'code': 'refused'});
      expect((refused.message, refused.retryable), ('判为拒绝', false));
      final timeout = await failure({'message': '没有回复', 'code': 'timeout'});
      expect(timeout.retryable, isFalse);
      final upstream = await failure({
        'message': 'status_code: 429, model error: quota',
        'code': 'upstream',
        'status': 429,
      });
      expect(upstream.message, 'status_code: 429, model error: quota');
      expect((upstream.status, upstream.retryable), (429, true));
    });

    test('后端自己拒的 HTTP 错不重试,网关错可以;没等到结果就断了要报', () async {
      for (final (status, retry) in [(413, false), (429, false), (502, true)]) {
        await expectLater(
          chat(http.Response('{"detail": "x"}', status)),
          throwsA(
            isA<AgentFailure>()
                .having((e) => e.status, 'status', status)
                .having((e) => e.retryable, 'retryable', retry),
          ),
        );
      }
      await expectLater(
        chat(http.Response(': open\n\n', 200, headers: sse)),
        throwsA(isA<AgentFailure>()),
      );
    });
  });

  group('直连回复解析', () {
    // 模型写坏围栏的花样很多,而写坏的表现是「这轮没出图」——和「模型决定不出图」
    // 长得一模一样,不钉住根本分不出来。
    final texts = _texts();
    ParsedReply parse(String raw) => parseReply(raw, texts);
    Matcher retry(String part) => throwsA(
      isA<OutputFailure>().having(
        (e) => e.instruction,
        'instruction',
        contains(part),
      ),
    );
    String fence(Map<String, Object?> draw) =>
        '```nai_draw\n${jsonEncode(draw)}\n```';

    test('正文 + nai_draw 围栏', () {
      final r = parse(
        '好耶,画一张芙兰喵~\n'
        '```nai_draw\n'
        '{"positive": "1girl, flandre_scarlet", "negative": "bad hands"}\n'
        '```',
      );
      expect(r.reply, '好耶,画一张芙兰喵~');
      expect(r.draw!['positive'], '1girl, flandre_scarlet');
      expect(r.repairs, isEmpty);
    });

    test('思考类标签连内容剥掉,只写了半边的也剥', () {
      final r = parse(
        '<Think>先查一下</Think>\n<thinking_process>想想</thinking_process>'
        '<Reference_Example>例子</Reference_Example>好的喵~</think>',
      );
      expect(r.reply, '好的喵~');
    });

    test('写了两版围栏时以最后一版为准', () {
      final r = parse(
        '```nai_draw\n{"positive": "a"}\n```\n'
        '改一下\n'
        '```nai_draw\n{"positive": "b"}\n```',
      );
      expect(r.draw!['positive'], 'b');
      expect(r.reply, '改一下');
      expect(r.repairs, hasLength(1));
    });

    test('围栏里不是合法 JSON:要模型重写,不能当这轮没出图', () {
      expect(() => parse('在想喵\n```nai_draw\n{坏了\n```'), retry('不是合法 JSON'));
      expect(() => parse('```nai_draw\n[1]\n```'), retry('顶层不是 JSON 对象'));
    });

    test('纯聊天轮没有围栏', () {
      final r = parse('这串 tag 挺好的喵');
      expect(r.draw, isNull);
      expect(r.reply, '这串 tag 挺好的喵');
    });

    test('残留的 tool_call 围栏不进正文', () {
      final r = parse(
        '好的\n```tool_call\n{"name": "lookup_tag", "arguments": {}}\n```',
      );
      expect(r.reply, '好的');
      expect(r.draw, isNull);
    });

    test('围栏名写错:按字段认出出图块', () {
      final r = parse('画好了\n```json\n{"positive": "1girl"}\n```');
      expect(r.draw!['positive'], '1girl');
      expect(r.reply, '画好了');
      expect(r.repairs, hasLength(1));
    });

    test('普通代码块里不是出图对象的照留', () {
      const raw = '给你:\n```json\n{"tag": "1girl"}\n```';
      expect(parse(raw).draw, isNull);
      expect(parse(raw).reply, raw);
    });

    test('漏了收尾的 ```:JSON 完整就收下', () {
      final r = parse('画好了\n```nai_draw\n{"positive": "1girl"}\n');
      expect(r.draw!['positive'], '1girl');
      expect(r.reply, '画好了');
    });

    test('开标记后面的 JSON 被截断:要模型重写', () {
      expect(
        () => parse('画好了\n```nai_draw\n{"positive": "1gi'),
        retry('多半是被截断了'),
      );
      expect(
        () => parse('画好了\n```nai_draw\n{"tag": "1girl"}'),
        retry('不是出图用的 JSON 对象'),
      );
    });

    test('忘了写围栏:正文里裸着的出图对象也认,加权语法的花括号不当真', () {
      final r = parse(
        '加了 {masterpiece} 权重\n{"positive": "{masterpiece}, 1girl"}',
      );
      expect(r.draw!['positive'], '{masterpiece}, 1girl');
      expect(r.reply, '加了 {masterpiece} 权重');
      expect(parse('{"positive": "1girl"}').draw!['positive'], '1girl');
    });

    test('写坏的出图对象里,单个角色分区不会被当成整块', () {
      final r = parse(
        '{"positive": "a", "characters": [{"name": "x", "positive": "b"}],}',
      );
      expect(r.draw, isNull);
    });

    test('出图块:数组拼成串、单个角色对象套成数组、多余字段剔掉', () {
      final r = parse(
        fence({
          'positive': ['1girl', 'smile'],
          'negative': ['bad'],
          'characters': {'name': '芙兰', 'positive': 'flandre_scarlet', 'x': 1},
        }),
      );
      expect(r.draw!['positive'], '1girl, smile');
      expect(r.draw!['negative'], 'bad');
      expect(r.draw!['characters'], [
        {'name': '芙兰', 'positive': 'flandre_scarlet', 'negative': ''},
      ]);
      expect(r.repairs, hasLength(4));
    });

    test('出图块:positive 缺了、空了、角色分区没有 tag,都要模型重写', () {
      expect(() => parse(fence({'negative': ''})), retry('没有 positive 字段'));
      expect(() => parse(fence({'positive': 1})), retry('positive 是 number'));
      expect(() => parse(fence({'positive': ' '})), retry('positive 是空的'));
      expect(
        () => parse(fence({'positive': 'a', 'characters': '芙兰'})),
        retry('写成了字符串 "芙兰"'),
      );
      expect(
        () => parse(
          fence({
            'positive': 'a',
            'characters': ['芙兰'],
          }),
        ),
        retry('有 1 项不是对象'),
      );
      expect(
        () => parse(
          fence({
            'positive': 'a',
            'characters': [
              {'name': '芙兰'},
            ],
          }),
        ),
        retry('第 1 个角色（name: "芙兰"）没有 positive'),
      );
    });

    test('出图块:characters 写成数字或空串,按单角色处理;negative 类型不对就置空', () {
      final r = parse(fence({'positive': 'a', 'characters': 1, 'negative': 2}));
      expect(r.draw!['characters'], isEmpty);
      expect(r.draw!['negative'], '');
    });

    test('出图块:站位的几种写歪法就地救回,认不出的去掉交给自动排布', () {
      final given = <Object?>[
        '0.25, 0.75',
        '25,75',
        {'x': 0.25, 'y': 0.75},
        [0.5, 0.5],
        'c4',
        '左下',
        '',
        1.5,
      ];
      final r = parse(
        fence({
          'positive': 'a',
          'characters': [
            for (final p in given)
              {'name': 'x', 'positive': 'y', 'position': p},
          ],
        }),
      );
      expect(
        [for (final c in r.draw!['characters'] as List) (c as Map)['position']],
        [
          '0.2500,0.7500',
          '0.2500,0.7500',
          '0.2500,0.7500',
          '0.5000,0.5000',
          'C4',
          null,
          null,
          null,
        ],
      );
    });
  });

  group('直连工具调用解析', () {
    test('一条回复里多个 tool_call 都要认出来', () {
      final calls = _calls(
        '我查一下喵\n'
        '```tool_call\n'
        '{"name": "search_character", "arguments": {"query": "芙兰"}}\n'
        '```\n'
        '```tool_call\n'
        '{"name": "search_artist", "arguments": {"keyword": "wlop"}}\n'
        '```',
      );
      expect(
        [for (final c in calls) c.name],
        ['search_character', 'search_artist'],
      );
      expect(calls.first.args['query'], '芙兰');
    });

    test('坏掉的那一块单独记下原文,别的照常执行', () {
      final p = const FencedToolProtocol().parse(
        '```tool_call\n{坏了\n```\n'
        '```tool_call\n'
        '{"name": "lookup_tag", "arguments": {"query": "halo"}}\n'
        '```',
      );
      expect(p.calls.single.name, 'lookup_tag');
      expect(p.broken.single.body, '{坏了');
    });

    test('没有 name、arguments 不是对象的不算调用,记下哪里不对', () {
      final p = const FencedToolProtocol().parse(
        '```tool_call\n{"arguments": {}}\n```\n'
        '```tool_call\n{"name": "lookup_tag", "arguments": "halo"}\n```\n'
        '```tool_call\n{"name": "lookup_tag"}\n```',
      );
      expect([for (final b in p.broken) b.error], ['缺 name', 'arguments 不是对象']);
      expect(p.calls.single.args, isEmpty, reason: '没写 arguments 当空参数');
    });

    test('没写围栏就是没调工具', () {
      expect(_calls('直接给你写好了喵'), isEmpty);
    });
  });

  group('直连响应取正文', () {
    // 三家的取文字段各不相同,认错的表现是「模型回了一段空的」,
    // 和真的空回长得一样。
    test('OpenAI:choices[0].message.content', () {
      expect(
        _llm(AgentApiFormat.openai).parseResponse(const {
          'choices': [
            {
              'message': {'content': '喵'},
            },
          ],
        }),
        '喵',
      );
    });

    test('Google:candidates[0].content.parts[].text,要拼起来', () {
      expect(
        _llm(AgentApiFormat.google).parseResponse(const {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '喵'},
                  {'text': '呜'},
                ],
              },
            },
          ],
        }),
        '喵呜',
      );
    });

    test('Anthropic:content[] 里只取 type=text 那几段', () {
      expect(
        _llm(AgentApiFormat.anthropic).parseResponse(const {
          'content': [
            {'type': 'thinking', 'thinking': '不该拿这段'},
            {'type': 'text', 'text': '喵'},
          ],
        }),
        '喵',
      );
    });

    test('形状不对返回空串,不崩', () {
      for (final f in AgentApiFormat.values) {
        expect(_llm(f).parseResponse(null), '');
        expect(_llm(f).parseResponse(const {}), '');
      }
    });
  });

  group('直连请求体:附图', () {
    // 三家的图片字段各不相同,写错的表现是「模型说没看到图」,
    // 和它自己看走眼分不出来。
    const img = (mime: 'image/jpeg', data: 'QUJD');
    const img2 = (mime: 'image/png', data: 'REVG');
    List<LlmMessage> msgs({
      List<LlmImage> images = const [],
      String text = '画个芙兰',
    }) => [
      (role: 'user', content: '上一轮', images: const []),
      (role: 'assistant', content: '好的', images: const []),
      (role: 'user', content: text, images: images),
    ];
    Map<String, dynamic> body(AgentApiFormat f, List<LlmMessage> m) => _llm(
      f,
    ).requestBody(LlmRequest(system: 'sys', messages: m), stream: false);

    test('OpenAI:content 换成分段,图在前,data URL', () {
      final m =
          body(AgentApiFormat.openai, msgs(images: [img, img2]))['messages']
              as List;
      expect(m[1], {'role': 'user', 'content': '上一轮'}, reason: '没图的仍是字符串');
      expect(m.last, {
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,QUJD'},
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,REVG'},
          },
          {'type': 'text', 'text': '画个芙兰'},
        ],
      });
    });

    test('Gemini:inlineData 在前,text 在后', () {
      final c =
          body(AgentApiFormat.google, msgs(images: [img, img2]))['contents']
              as List;
      expect(c.last['parts'], [
        {
          'inlineData': {'mimeType': 'image/jpeg', 'data': 'QUJD'},
        },
        {
          'inlineData': {'mimeType': 'image/png', 'data': 'REVG'},
        },
        {'text': '画个芙兰'},
      ]);
    });

    test('Claude:base64 的 image 块在前', () {
      final m =
          body(AgentApiFormat.anthropic, msgs(images: [img, img2]))['messages']
              as List;
      expect(m.last['content'], [
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/jpeg',
            'data': 'QUJD',
          },
        },
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'REVG',
          },
        },
        {'type': 'text', 'text': '画个芙兰'},
      ]);
    });

    test('只发图不打字:不塞空的文字段(Claude 会拒空 text 块)', () {
      for (final f in AgentApiFormat.values) {
        final raw = jsonEncode(body(f, msgs(images: [img], text: '')));
        expect(raw, isNot(contains('"text":""')), reason: f.name);
        expect(raw, contains('QUJD'), reason: f.name);
      }
    });

    test('不带图:和原来一样', () {
      expect((body(AgentApiFormat.openai, msgs())['messages'] as List).last, {
        'role': 'user',
        'content': '画个芙兰',
      });
      expect(
        (body(AgentApiFormat.google, msgs())['contents'] as List).last['parts'],
        [
          {'text': '画个芙兰'},
        ],
      );
      expect(
        (body(AgentApiFormat.anthropic, msgs())['messages'] as List).last,
        {'role': 'user', 'content': '画个芙兰'},
      );
    });

    test('图片类型按文件头认,认不出按 PNG', () {
      Uint8List head(List<int> b) =>
          Uint8List.fromList([...b, ...List.filled(16, 0)]);
      expect(imageMimeOf(head([0x89, 0x50, 0x4E, 0x47])), 'image/png');
      expect(imageMimeOf(head([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
      expect(
        imageMimeOf(
          head([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]),
        ),
        'image/webp',
      );
      expect(imageMimeOf(head('GIF89a'.codeUnits)), 'image/gif');
      expect(imageMimeOf(Uint8List(0)), 'image/png');
    });

    test('没超大小的图原样发,不转码', () async {
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);
      final r = await prepareLlmImage(jpg);
      expect(r.mime, 'image/jpeg');
      expect(base64Decode(r.data), jpg);
    });
  });

  group('助手设置', () {
    test('默认:自动的一律关着,逐字显示开着', () {
      const d = AssistantSettings();
      expect(d.autoGenerate, isFalse);
      expect(d.inlineImage, isFalse);
      expect(d.autoImport, isFalse);
      // 逐字显示不属于「放权」那一类:它不替用户决定任何事,默认开着
      expect(d.stream, isTrue);
    });

    test('逐字显示:存得下,老存档缺这个字段按开算', () {
      expect(
        AssistantSettings.fromJson(
          const AssistantSettings(stream: false).toJson(),
        ).stream,
        isFalse,
      );
      expect(AssistantSettings.fromJson(const {}).stream, isTrue);
    });

    test('存得下也读得回来', () {
      const s = AssistantSettings(
        autoGenerate: true,
        thinkLevel: ThinkLevel.high,
      );
      final back = AssistantSettings.fromJson(s.toJson());
      expect(back.autoGenerate, isTrue);
      expect(back.thinkLevel, ThinkLevel.high);
    });
  });

  group('工具设置', () {
    test('默认工具全开,选项全关', () {
      const s = ToolSettings();
      for (final t in kAgentTools) {
        expect(s.toolOn(t.name), isTrue);
        for (final o in t.options) {
          expect(s.optionOn(t.name, o.id), isFalse);
        }
      }
      expect(
        [for (final t in enabledTools(s)) t.name],
        ['search_artist', 'search_oc', 'search_character', 'lookup_tag'],
      );
    });

    test('关掉的工具不算', () {
      const s = ToolSettings(disabledTools: {'search_oc'});
      expect(
        [for (final t in enabledTools(s)) t.name],
        ['search_artist', 'search_character', 'lookup_tag'],
      );
    });

    test('存得下也读得回来;旧存档里的来源开关不认', () {
      const s = ToolSettings(
        disabledTools: {'search_oc'},
        enabledOptions: {kOcPlaceholdersOption},
      );
      final back = ToolSettings.fromJson(s.toJson());
      expect(back.toolOn('search_oc'), isFalse);
      expect(back.ocPlaceholders, isTrue);
      expect(ToolSettings.fromJson(const {}).ocPlaceholders, isFalse);
      final old = ToolSettings.fromJson(const {
        'disabledSources': ['lookup_tag/offline', 'lookup_tag/wiki'],
      });
      expect(enabledTools(old), hasLength(kAgentTools.length));
    });

    test('旧版设置迁过来:资料库「不使用」关掉使用画风库、使用角色库,OC 占位符照带', () {
      final none = ToolSettings.fromLegacy(const {
        'libraryScope': 'none',
        'ocPlaceholders': true,
      });
      expect(none.toolOn('search_artist'), isFalse);
      expect(none.toolOn('search_oc'), isFalse);
      expect(none.toolOn('search_character'), isTrue);
      expect(none.ocPlaceholders, isTrue);
      final all = ToolSettings.fromLegacy(const {'libraryScope': 'all'});
      expect(enabledTools(all), hasLength(kAgentTools.length));
      expect(all.ocPlaceholders, isFalse);
    });

    test('工具清单:只列开着的工具,带参数和各自的说明;没有工具就是空的', () async {
      final list = await const FencedToolProtocol().toolList(
        enabledTools(const ToolSettings(disabledTools: {'lookup_tag'})),
      );
      expect(list, contains('- search_artist'));
      expect(list, contains('artist_ids: array'));
      expect(list, contains('- search_oc'));
      expect(list, contains('预取块 [画师串]'));
      expect(list, isNot(contains('lookup_tag')));
      expect(await const FencedToolProtocol().toolList(const []), isEmpty);
    });
  });

  group('思考等级', () {
    // 三家的旋钮完全不是一回事:OpenAI 给档位字符串,另外两家要 token 预算。
    // 发错字段的表现是「请求被拒」或者「悄悄没生效」,两种都难查。
    test('滑杆顺序:关 → 自动 → 由低到高', () {
      expect(ThinkLevel.values, [
        ThinkLevel.off,
        ThinkLevel.auto,
        ThinkLevel.low,
        ThinkLevel.medium,
        ThinkLevel.high,
        ThinkLevel.ultra,
      ]);
    });

    test('自动档不发档位;Gemini 3 及以后只要思考摘要', () {
      for (final f in AgentApiFormat.values) {
        expect(
          _llm(f, 'gemini-2.5-flash').thinkFields(ThinkLevel.auto),
          isEmpty,
        );
      }
      expect(
        _llm(
          AgentApiFormat.google,
          'gemini-4-carbon',
        ).thinkFields(ThinkLevel.auto),
        {
          'generationConfig': {
            'thinkingConfig': {'includeThoughts': true},
          },
        },
      );
    });

    test('OpenAI:reasoning_effort 档位字符串,两头各自封顶', () {
      expect(_llm(AgentApiFormat.openai).thinkFields(ThinkLevel.low), {
        'reasoning_effort': 'low',
      });
      // 它没有「关」,minimal 是最低;也没有「超高」,high 是最高
      expect(_llm(AgentApiFormat.openai).thinkFields(ThinkLevel.off), {
        'reasoning_effort': 'minimal',
      });
      expect(
        _llm(AgentApiFormat.openai).thinkFields(ThinkLevel.ultra),
        _llm(AgentApiFormat.openai).thinkFields(ThinkLevel.high),
      );
    });

    test('Gemini 2.x:thinkingBudget,关掉是 0 而不是不发', () {
      Map cfg(ThinkLevel l) {
        final f = _llm(
          AgentApiFormat.google,
          'gemini-2.5-flash',
        ).thinkFields(l);
        return (f['generationConfig'] as Map)['thinkingConfig'] as Map;
      }

      int budget(ThinkLevel l) => cfg(l)['thinkingBudget'] as int;

      expect(budget(ThinkLevel.off), 0);
      expect(cfg(ThinkLevel.off).containsKey('thinkingLevel'), isFalse);
      expect(cfg(ThinkLevel.off).containsKey('includeThoughts'), isFalse);
      expect(cfg(ThinkLevel.high)['includeThoughts'], isTrue);
      // 越往上给得越多,而且真的要递增 —— 两档撞在一起等于白给一档
      expect(budget(ThinkLevel.low), lessThan(budget(ThinkLevel.medium)));
      expect(budget(ThinkLevel.medium), lessThan(budget(ThinkLevel.high)));
      expect(budget(ThinkLevel.high), lessThan(budget(ThinkLevel.ultra)));
    });

    test('Gemini 3 / 4:thinkingLevel,不发预算,没有的档就近落', () {
      String? level(String model, ThinkLevel l) {
        final f = _llm(AgentApiFormat.google, model).thinkFields(l);
        final cfg = (f['generationConfig'] as Map)['thinkingConfig'] as Map;
        // 两种一起发会被拒
        expect(cfg.containsKey('thinkingBudget'), isFalse);
        expect(cfg['includeThoughts'], isTrue);
        return cfg['thinkingLevel'] as String?;
      }

      for (final m in [
        'gemini-4-argon',
        'models/gemini-4-carbon',
        'gemini-3.7-flash',
        'gemini-flash-latest',
      ]) {
        expect(level(m, ThinkLevel.low), 'LOW', reason: m);
        expect(level(m, ThinkLevel.medium), 'MEDIUM', reason: m);
        expect(level(m, ThinkLevel.high), 'HIGH', reason: m);
        // 没有「关」也不用 MINIMAL,落到 LOW;没有 XHIGH,落到 HIGH
        expect(level(m, ThinkLevel.off), 'LOW', reason: m);
        expect(level(m, ThinkLevel.ultra), 'HIGH', reason: m);
      }
      expect(level('gemini-4-hydrogen', ThinkLevel.ultra), 'XHIGH');
    });

    test('认代:2.x 及更早给预算,3 及以后给档位,认不出的按预算', () {
      expect(geminiThinkingOf('gemini-2.5-pro'), GeminiThinking.budget);
      expect(geminiThinkingOf('gemini-2.0-flash'), GeminiThinking.budget);
      expect(geminiThinkingOf('models/gemini-1.5-pro'), GeminiThinking.budget);
      expect(geminiThinkingOf('gemini-3.1-pro-preview'), GeminiThinking.level);
      expect(geminiThinkingOf('gemini-4-argon'), GeminiThinking.level);
      expect(geminiThinkingOf('Gemini-4-Carbon'), GeminiThinking.level);
      expect(geminiThinkingOf('deepseek-chat'), GeminiThinking.budget);
    });

    test('档位被换掉时才有提示', () {
      CustomEndpoint ep(AgentApiFormat f, String model) => CustomEndpoint(
        id: 'x',
        name: '',
        format: f,
        baseUrl: '',
        apiKey: 'k',
        model: model,
      );
      final carbon = ep(AgentApiFormat.google, 'gemini-4-carbon');
      expect(llmProviderFor(carbon).thinkNote(ThinkLevel.off), isNotNull);
      expect(llmProviderFor(carbon).thinkNote(ThinkLevel.ultra), isNotNull);
      expect(llmProviderFor(carbon).thinkNote(ThinkLevel.high), isNull);
      expect(llmProviderFor(carbon).thinkNote(ThinkLevel.auto), isNull);
      final hydrogen = ep(AgentApiFormat.google, 'gemini-4-hydrogen');
      expect(llmProviderFor(hydrogen).thinkNote(ThinkLevel.ultra), isNull);
      final old = ep(AgentApiFormat.google, 'gemini-2.5-flash');
      expect(llmProviderFor(old).thinkNote(ThinkLevel.off), isNull);
      final gpt = ep(AgentApiFormat.openai, 'gpt-5');
      expect(llmProviderFor(gpt).thinkNote(ThinkLevel.ultra), isNotNull);
      final claude = ep(AgentApiFormat.anthropic, 'claude');
      expect(llmProviderFor(claude).thinkNote(ThinkLevel.off), isNull);
    });

    test('Gemini 的思考摘要不算正文', () {
      expect(
        _llm(AgentApiFormat.google).parseResponse(const {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '先想想', 'thought': true},
                  {'text': '好的'},
                ],
              },
            },
          ],
        }),
        '好的',
      );
    });

    test('Claude:关 = 不带 thinking 字段;开着预算不低于 1024 且递增', () {
      expect(
        _llm(AgentApiFormat.anthropic).thinkFields(ThinkLevel.off),
        isEmpty,
      );
      var prev = 0;
      for (final l in [
        ThinkLevel.low,
        ThinkLevel.medium,
        ThinkLevel.high,
        ThinkLevel.ultra,
      ]) {
        final t =
            _llm(AgentApiFormat.anthropic).thinkFields(l)['thinking'] as Map;
        expect(t['type'], 'enabled');
        final b = t['budget_tokens'] as int;
        // Anthropic 自己规定的下限
        expect(b, greaterThanOrEqualTo(1024));
        expect(b, greaterThan(prev));
        prev = b;
      }
    });

    test('存得下也读得回来,老存档自动档', () {
      const s = AssistantSettings(thinkLevel: ThinkLevel.ultra);
      expect(
        AssistantSettings.fromJson(s.toJson()).thinkLevel,
        ThinkLevel.ultra,
      );
      expect(AssistantSettings.fromJson(const {}).thinkLevel, ThinkLevel.auto);
      // 认不出的值回落自动,不能瞎选一档替用户花钱
      expect(
        AssistantSettings.fromJson(const {'thinkLevel': 'wat'}).thinkLevel,
        ThinkLevel.auto,
      );
    });
  });

  group('自定义接口', () {
    test('多个模型:存得下读得回,老存档的单个模型读成一个', () {
      const e = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'k',
        model: 'deepseek-chat',
        models: ['deepseek-chat', 'deepseek-reasoner'],
      );
      final back = CustomEndpoint.fromJson(e.toJson())!;
      expect(back.models, ['deepseek-chat', 'deepseek-reasoner']);
      expect(back.model, 'deepseek-chat');
      final old = CustomEndpoint.fromJson({'id': 'y', 'model': 'gpt-4o'})!;
      expect(old.allModels, ['gpt-4o']);
      expect(old.model, 'gpt-4o');
      expect(CustomEndpoint.fromJson({'id': 'z'})!.usable, isFalse);
    });

    test('选择键:带模型的认模型,旧键和不在了的模型按第一个', () {
      const e = CustomEndpoint(
        id: 'ep1_0',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'k',
        model: 'a',
        models: ['a', 'openai/gpt-4o'],
      );
      final k = customModelKey('ep1_0', 'openai/gpt-4o');
      expect(customEndpointIdOf(k), 'ep1_0');
      expect(customModelOf(k), 'openai/gpt-4o');
      expect(resolveCustomChoice(e, k)!.model, 'openai/gpt-4o');
      expect(resolveCustomChoice(e, customModelKey('ep1_0'))!.model, 'a');
      expect(
        resolveCustomChoice(e, customModelKey('ep1_0', 'gone'))!.model,
        'a',
      );
      expect(resolveCustomChoice(e, customModelKey('ep2_0', 'a')), isNull);
      expect(customEndpointIdOf('glm-4'), isNull);
    });

    test('认服务:格式 + 地址对上才算,地址留空按官方', () {
      expect(
        endpointPresetOf(
          AgentApiFormat.openai,
          'https://api.deepseek.com/v1/',
        )?.label,
        'DeepSeek',
      );
      for (final f in AgentApiFormat.values) {
        final p = endpointPresetOf(f, '');
        expect(p?.official, isTrue);
        expect(p?.format, f);
      }
      // 每个格式恰好一个官方
      for (final f in AgentApiFormat.values) {
        expect(
          kEndpointPresets.where((p) => p.format == f && p.official).length,
          1,
        );
      }
      // 地址对上、格式不对,不是那一家
      expect(
        endpointPresetOf(AgentApiFormat.google, 'https://api.openai.com/v1'),
        isNull,
      );
      expect(
        endpointPresetOf(AgentApiFormat.openai, 'https://relay.example.com/v1'),
        isNull,
      );
    });

    test('地址连对话路径一起贴进来时切掉路径', () {
      expect(
        normalizeEndpointBase(
          ' https://r.example.com/v1/chat/completions/ ',
          AgentApiFormat.openai,
        ),
        'https://r.example.com/v1',
      );
      expect(
        normalizeEndpointBase(
          'https://r.example.com/v1/messages',
          AgentApiFormat.anthropic,
        ),
        'https://r.example.com/v1',
      );
      expect(
        normalizeEndpointBase(
          'https://r.example.com/v1beta/models/gemini-4-carbon:streamGenerateContent?alt=sse',
          AgentApiFormat.google,
        ),
        'https://r.example.com/v1beta',
      );
      // 只切和格式对应的那段
      expect(
        normalizeEndpointBase(
          'https://r.example.com/v1/messages',
          AgentApiFormat.openai,
        ),
        'https://r.example.com/v1/messages',
      );
    });

    // 三家的模型列表字段各不相同,而**认错字段的表现是「列表空着」**,
    // 和网络失败长得一模一样 —— 不钉住的话根本分不出是哪一头的问题。
    test('OpenAI:data[].id', () {
      expect(
        _llm(AgentApiFormat.openai).parseModels(const {
          'data': [
            {'id': 'gpt-4o'},
            {'id': 'o3-mini'},
          ],
        }),
        ['gpt-4o', 'o3-mini'],
      );
    });

    test('Google:models[].name,要把 models/ 前缀剥掉', () {
      expect(
        _llm(AgentApiFormat.google).parseModels(const {
          'models': [
            {'name': 'models/gemini-3.7-flash'},
            {'name': 'models/gemini-3.1-flash-lite'},
          ],
        }),
        ['gemini-3.1-flash-lite', 'gemini-3.7-flash'],
      );
    });

    test('Anthropic:也是 data[].id', () {
      expect(
        _llm(AgentApiFormat.anthropic).parseModels(const {
          'data': [
            {'id': 'claude-sonnet-4-6'},
          ],
        }),
        ['claude-sonnet-4-6'],
      );
    });

    test('形状不对就空表,不崩', () {
      expect(_llm(AgentApiFormat.openai).parseModels(null), isEmpty);
      expect(_llm(AgentApiFormat.openai).parseModels(const {}), isEmpty);
      expect(
        _llm(AgentApiFormat.openai).parseModels(const {'data': 'nope'}),
        isEmpty,
      );
      expect(
        _llm(AgentApiFormat.openai).parseModels(const {
          'data': ['x', 3],
        }),
        isEmpty,
      );
    });

    test('去重', () {
      expect(
        _llm(AgentApiFormat.openai).parseModels(const {
          'data': [
            {'id': 'a'},
            {'id': 'a'},
          ],
        }),
        ['a'],
      );
    });

    test('基址留空用各家默认,末尾斜杠一律削掉', () {
      const e = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: '',
        apiKey: 'k',
        model: 'gpt-4o',
      );
      expect(e.effectiveBase, 'https://api.openai.com/v1');
      expect(
        e.copyWith(baseUrl: 'http://localhost:8080/v1//').effectiveBase,
        'http://localhost:8080/v1',
      );
      // 名字留空就显示认出的服务名,认不出显示主机名
      expect(e.displayName, 'OpenAI');
      expect(
        e.copyWith(baseUrl: 'https://relay.example.com/v1').displayName,
        'relay.example.com',
      );
      expect(e.copyWith(name: '我的中转').displayName, '我的中转');
    });

    test('接口路径:留空用各家默认,Gemini 那条要把模型名替进去', () {
      const base = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: '',
        apiKey: 'k',
        model: 'gpt-4o',
      );
      expect(base.effectivePath, '/chat/completions');
      expect(
        base.chatUri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );

      final g = base.copyWith(
        format: AgentApiFormat.google,
        model: 'gemini-3.7-flash',
      );
      expect(g.effectivePath, '/models/gemini-3.7-flash:generateContent');

      final a = base.copyWith(format: AgentApiFormat.anthropic);
      expect(a.effectivePath, '/messages');
    });

    test('自己填的路径:开头没斜杠也补上,{model} 照样替换', () {
      const e = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: 'http://localhost:8080',
        apiKey: 'k',
        model: 'qwen',
        apiPath: 'v1/chat/{model}',
      );
      expect(e.effectivePath, '/v1/chat/qwen');
      expect(e.chatUri.toString(), 'http://localhost:8080/v1/chat/qwen');
    });

    test('路径存得下也读得回来,空的不落盘', () {
      const e = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: '',
        apiKey: 'k',
        model: 'm',
      );
      expect(e.toJson().containsKey('apiPath'), isFalse);
      expect(
        CustomEndpoint.fromJson(e.copyWith(apiPath: '/x').toJson())!.apiPath,
        '/x',
      );
    });

    test('请求头:按行解析,坏行报行号,存得下也读得回来', () {
      final ok = parseHeaderLines(
        'HTTP-Referer: https://plana.test\n\n  X-Title : Plana \nx-title: P2',
      );
      expect(ok.bad, isNull);
      expect(ok.headers, {
        'HTTP-Referer': 'https://plana.test',
        'x-title': 'P2',
      });
      expect(parseHeaderLines('A: 1\nno colon').bad, 2);
      expect(parseHeaderLines('Bad Name: 1').bad, 1);
      expect(parseHeaderLines('X-Title: 中文').bad, 1);
      expect(
        parseHeaderLines(formatHeaderLines(ok.headers)).headers,
        ok.headers,
      );

      const e = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: '',
        apiKey: 'k',
        model: 'm',
      );
      expect(e.toJson().containsKey('headers'), isFalse);
      final withH = e.copyWith(headers: {'X-A': '1'});
      expect(CustomEndpoint.fromJson(withH.toJson())!.headers, {'X-A': '1'});
    });

    test('请求头盖在默认头上,同名不分大小写', () {
      const e = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: '',
        apiKey: 'k',
        model: 'm',
        headers: {'authorization': 'Token t', 'X-A': '1'},
      );
      expect(e.withHeaders({'Authorization': 'Bearer k', 'Accept': 'x'}), {
        'Accept': 'x',
        'authorization': 'Token t',
        'X-A': '1',
      });
      expect(e.copyWith(headers: const {}).withHeaders({'A': '1'}), {'A': '1'});
    });

    test('缺 key 或缺模型都算没填全', () {
      const base = CustomEndpoint(
        id: 'x',
        name: '',
        format: AgentApiFormat.openai,
        baseUrl: '',
        apiKey: 'k',
        model: 'm',
      );
      expect(base.usable, isTrue);
      expect(base.copyWith(apiKey: ' ').usable, isFalse);
      expect(base.copyWith(model: '').usable, isFalse);
    });

    test('存得下也读得回来,坏条目跳过', () {
      const e = CustomEndpoint(
        id: 'x',
        name: 'n',
        format: AgentApiFormat.google,
        baseUrl: 'https://h/v1',
        apiKey: 'k',
        model: 'm',
      );
      final back = CustomEndpoint.fromJson(e.toJson())!;
      expect(back.format, AgentApiFormat.google);
      expect(back.baseUrl, 'https://h/v1');
      expect(back.model, 'm');
      // 没有 id 的一律丢掉:它是替换和删除的唯一依据
      expect(CustomEndpoint.fromJson(const {'name': 'x'}), isNull);
      expect(CustomEndpoint.fromJson('nope'), isNull);
      // 认不出的格式回落 OpenAI 兼容,那是最常见的一种
      expect(
        CustomEndpoint.fromJson(const {'id': 'y', 'format': 'wat'})!.format,
        AgentApiFormat.openai,
      );
    });
  });

  group('模型门禁', () {
    // Anima / Krea 的提示词体系与 NAI 是两套,助手的预设、工具、nai_draw 围栏
    // 全是按 NAI 写的。硬跑出得来东西,但对那两个模型基本等于没写。
    test('NAI 两条线放行', () {
      expect(assistantSupportsModel('NAI 4.5 Full'), isTrue);
      expect(assistantSupportsModel('NAI 5 Full'), isTrue);
      expect(assistantSupportsModel(''), isTrue);
    });

    test('Anima / Krea 挡住', () {
      expect(assistantSupportsModel('Anima'), isFalse);
      expect(assistantSupportsModel('Krea 2'), isFalse);
    });
  });

  group('助手设置', () {
    // 三项都是「把手动改成自动」,所以**默认必须全关** —— 谁都不该在没开过
    // 开关的情况下发现 AI 自己动了画布、自己花了点数。
    test('默认全关', () {
      const s = AssistantSettings();
      expect(s.autoGenerate, isFalse);
      expect(s.inlineImage, isFalse);
      expect(s.autoImport, isFalse);
      expect(s.noDraw, isFalse);
      expect(s.introDone, isFalse, reason: '首次引导没走过就得弹');
    });

    test('存得下也读得回来', () {
      const s = AssistantSettings(
        autoGenerate: true,
        inlineImage: true,
        autoImport: true,
        noDraw: true,
        introVersion: kAssistantIntroVersion,
      );
      final back = AssistantSettings.fromJson(s.toJson());
      expect(back.autoGenerate, isTrue);
      expect(back.inlineImage, isTrue);
      expect(back.autoImport, isTrue);
      expect(back.noDraw, isTrue);
      expect(back.introDone, isTrue);
      // 引导改过版,走过旧版的也得再看一次
      expect(
        const AssistantSettings(
          introVersion: kAssistantIntroVersion - 1,
        ).introDone,
        isFalse,
      );
    });

    test('老存档缺字段一律当关 —— 不能因为读不到就替用户开了', () {
      final s = AssistantSettings.fromJson(const {});
      expect(s.autoGenerate, isFalse);
      expect(s.inlineImage, isFalse);
      expect(s.autoImport, isFalse);
      expect(s.noDraw, isFalse);
      // 值不是 bool 也不能当真
      expect(
        AssistantSettings.fromJson(const {'autoGenerate': 'yes'}).autoGenerate,
        isFalse,
      );
    });

    test('老存档的 alwaysCanvas 只继承「自动导入」那一半', () {
      // 这一项原来叫「总是读写创作页」,读画布那一半已经撤了(两个方向常开会
      // 互相咬:自动写进去的词下一轮又被自动读回来当基底)。老存档里开着的,
      // 保留写那一半。
      expect(
        AssistantSettings.fromJson(const {'alwaysCanvas': true}).autoImport,
        isTrue,
      );
      expect(
        AssistantSettings.fromJson(const {'alwaysCanvas': false}).autoImport,
        isFalse,
      );
      // 新名字优先,但两个键都不认就还是关
      expect(
        AssistantSettings.fromJson(const {'autoImport': true}).autoImport,
        isTrue,
      );
    });

    test('copyWith 只动指定的那一项', () {
      const s = AssistantSettings(autoImport: true);
      final n = s.copyWith(autoGenerate: true);
      expect(n.autoGenerate, isTrue);
      expect(n.autoImport, isTrue, reason: '没提到的项不该被顺手关掉');
      expect(n.inlineImage, isFalse);
    });

    test('消息字号:默认比正文大一号,存得下读得回来,越界夹回范围', () {
      expect(const AssistantSettings().fontSize, 15);
      expect(AssistantSettings.fromJson(const {}).fontSize, 15);
      expect(
        AssistantSettings.fromJson(
          const AssistantSettings(fontSize: 18).toJson(),
        ).fontSize,
        18,
      );
      expect(
        AssistantSettings.fromJson(const {'fontSize': 99}).fontSize,
        AssistantSettings.fontSizeMax,
      );
      expect(
        AssistantSettings.fromJson(const {'fontSize': 'big'}).fontSize,
        AssistantSettings.fontSizeDefault,
      );
    });

    test('上下文轮数:默认 20 与服务端一致,存得下读得回来,零头落到十轮一档,越界夹回范围', () {
      expect(const AssistantSettings().historyTurns, 20);
      expect(AssistantSettings.fromJson(const {}).historyTurns, 20);
      expect(
        AssistantSettings.fromJson(
          const AssistantSettings(historyTurns: 130).toJson(),
        ).historyTurns,
        130,
      );
      expect(
        AssistantSettings.fromJson(const {'historyTurns': 35}).historyTurns,
        40,
      );
      expect(
        AssistantSettings.fromJson(const {'historyTurns': 3}).historyTurns,
        AssistantSettings.historyTurnsMin,
      );
      expect(
        AssistantSettings.fromJson(const {'historyTurns': 999}).historyTurns,
        AssistantSettings.historyTurnsMax,
      );
      expect(
        AssistantSettings.fromJson(const {'historyTurns': 0}).historyTurns,
        AssistantSettings.historyTurnsMin,
      );
      expect(
        AssistantSettings.fromJson(const {
          'historyTurns': double.infinity,
        }).historyTurns,
        AssistantSettings.historyTurnsDefault,
      );
    });

    test('失败重试 / 拒绝重试:默认 3,0 存得下,越界夹回;末次重试剥图默认关', () {
      final d = AssistantSettings.fromJson(const {});
      expect((d.retries, d.rerolls, d.retryStripImage), (3, 3, false));
      final back = AssistantSettings.fromJson(
        const AssistantSettings(
          retries: 0,
          retryStripImage: true,
          rerolls: 5,
        ).toJson(),
      );
      expect((back.retries, back.rerolls, back.retryStripImage), (0, 5, true));
      final wild = AssistantSettings.fromJson(const {
        'retries': -1,
        'rerolls': 99,
        'retryStripImage': 'yes',
      });
      expect(
        (wild.retries, wild.rerolls, wild.retryStripImage),
        (0, AssistantSettings.retriesMax, false),
      );
    });

    test('拒绝关键词:默认不落盘,改过的存得下读得回来,空词丢掉', () {
      expect(
        const AssistantSettings().toJson().containsKey('refusalKeywords'),
        isFalse,
      );
      expect(
        AssistantSettings.fromJson(const {}).refusalKeywords,
        kRefusalKeywords,
      );
      final back = AssistantSettings.fromJson(
        const AssistantSettings(refusalKeywords: ['不画', '红线']).toJson(),
      );
      expect(back.refusalKeywords, ['不画', '红线']);
      expect(back.defaultRefusalKeywords, isFalse);
      expect(
        AssistantSettings.fromJson(const {
          'refusalKeywords': [' 不画 ', '', 3],
        }).refusalKeywords,
        ['不画'],
      );
      expect(
        AssistantSettings.fromJson(const {
          'refusalKeywords': <String>[],
        }).refusalKeywords,
        isEmpty,
      );
    });
  });

  group('上下文轮数', () {
    Map<String, String> u(String t) => {'role': 'user', 'content': t};
    Map<String, String> a(String t) => {'role': 'assistant', 'content': t};

    test('只留最近几轮,边界落在提问上', () {
      final h = [u('1'), a('答1'), u('2'), a('答2'), u('3'), a('答3')];
      expect(recentTurns(h, 2), [u('2'), a('答2'), u('3'), a('答3')]);
      expect(recentTurns(h, 1).first, u('3'));
    });

    test('不足几轮就全留', () {
      final h = [u('1'), a('答1')];
      expect(recentTurns(h, 20), h);
      expect(recentTurns(const [], 20), isEmpty);
    });
  });

  group('对话记录导出', () {
    AgentTrace sample() {
      final t =
          AgentTrace(
              startedAt: DateTime(
                2026,
                9,
                15,
                20,
                58,
                3,
              ).millisecondsSinceEpoch,
              route: AgentTrace.routeCustom,
              userText: '画个芙兰',
              settings: <String, Object?>{
                'mode': 'normal',
                'history_turns': 20,
              },
            )
            ..system = '系统提示全文'
            ..prequery = {
              'block': '[画师串]\nA1 → artist:wlop',
              'modes': ['comic'],
            }
            ..messages = [
              {'role': 'user', 'content': '画个芙兰'},
            ]
            ..endedAt = DateTime(
              2026,
              9,
              15,
              20,
              58,
              21,
            ).millisecondsSinceEpoch;
      t.hops.add({
        't': 800,
        'ms': 5200,
        'reply': '先查一下',
        'tool_calls': [
          {
            'name': 'search_character',
            'arguments': {'query': '芙兰'},
          },
        ],
        'tool_results': '[search_character] []',
      });
      t.event('final', {
        'reply': '好了',
        'draw': {'positive': 'flandre_scarlet'},
      });
      return t;
    }

    test('记录存得下也读得回来', () {
      final t = sample();
      final back = AgentTrace.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(back.toJson()), jsonEncode(t.toJson()));
    });

    test('读坏的字段当没有,不整份作废', () {
      final t = AgentTrace.fromJson(const {
        'route': 'custom',
        'hops': 'oops',
        'events': [
          1,
          {'event': 'x'},
        ],
        'settings': 3,
      });
      expect(t.route, AgentTrace.routeCustom);
      expect(t.hops, isEmpty);
      expect(t.events.single['event'], 'x');
      expect(t.settings, isEmpty);
    });

    test('导出里有每一轮的系统提示、每一跳、失败原因,和下一轮会带的上下文', () {
      final failed =
          AgentTrace(
              startedAt: 1,
              route: AgentTrace.routeBackend,
              userText: '再来',
              settings: <String, Object?>{},
            )
            ..request = {'user_request': '再来'}
            ..endedAt = 2
            ..error = '连接后端超时';
      final text = renderTraceExport(
        traces: [sample(), failed],
        settings: const {'historyTurns': 20},
        nextHistory: const [
          {'role': 'user', 'content': '画个芙兰'},
          {'role': 'assistant', 'content': '好了'},
        ],
        resources: const {
          'artist': {'A1': 'artist:wlop'},
        },
        messages: const [],
        now: 0,
        appVersion: '9.9.9',
      );
      for (final s in [
        '第 1 轮',
        '自定义接口',
        '系统提示全文',
        '第 1 跳',
        'search_character',
        '第 2 轮',
        '后端渠道',
        '失败:连接后端超时',
        '下一轮会带上的上下文',
        'artist:wlop',
      ]) {
        expect(text, contains(s));
      }
    });

    test('调试记录落盘,重开 app 还在', () async {
      final root = _tempRoot();
      final stores = await AppStores.open(rootOverride: root);
      await stores.assistant.saveTraces([sample()]);
      final again = await AppStores.open(rootOverride: root);
      expect(again.assistant.initialTraces.single.userText, '画个芙兰');
      expect(again.assistant.initialTraces.single.hops.single['ms'], 5200);
    });
  });

  group('对话里挂的出图', () {
    test('图库 id 能落盘也能读回来', () {
      const m = AssistantMsg(
        id: 'x',
        role: MsgRole.ai,
        text: '改好了喵~',
        at: 1,
        imageIds: ['gen3', 'gen4'],
      );
      expect(AssistantMsg.fromJson(m.toJson()).imageIds, ['gen3', 'gen4']);
    });

    test('老存档没有这个字段,读成空表', () {
      expect(
        AssistantMsg.fromJson(const {
          'id': 'y',
          'role': 'ai',
          'text': '旧消息',
          'at': 1,
        }).imageIds,
        isEmpty,
      );
    });

    test('copyWith 补图时别把工具轨迹和改动弄丢', () {
      const m = AssistantMsg(
        id: 'x',
        role: MsgRole.ai,
        text: 'ok',
        at: 1,
        tools: [ToolTrace(name: 'lookup_tag', subject: 'halo')],
      );
      final n = m.copyWith(imageIds: ['gen1']);
      expect(n.imageIds, ['gen1']);
      expect(n.tools.single.subject, 'halo');
    });
  });

  group('查资料轨迹', () {
    // 这一栏的价值全在「查的是什么」上:服务端回的 summary 只有计数,
    // 说不出查的是谁。挑错字段的后果是整栏退回「查了 3 处资料」那种废话。
    test('四个工具的参数名各不相同,都要能挑出查询词', () {
      // search_character
      expect(
        toolSubject(const {'query': '普拉娜', 'origin': '蔚蓝档案', 'limit': 8}),
        '普拉娜',
      );
      // lookup_tag
      expect(toolSubject(const {'query': 'halo', 'category': ''}), 'halo');
      // search_artist:按关键词
      expect(toolSubject(const {'artist_ids': [], 'keyword': 'wlop'}), 'wlop');
      // search_artist:按 id
      expect(
        toolSubject(const {
          'artist_ids': ['A1', 'B2'],
          'keyword': '',
        }),
        'A1 B2',
      );
      // random_artist 只有个数,那也是信息
      expect(toolSubject(const {'count': 3}), '随机 3 个');
    });

    test('query 空就退到 origin —— 「画个蔚蓝档案的角色」那种问法', () {
      expect(toolSubject(const {'query': '  ', 'origin': '蔚蓝档案'}), '蔚蓝档案');
    });

    test('什么都挑不出来就空着,不编一个词出来', () {
      expect(toolSubject(const {}), '');
      expect(toolSubject(const {'limit': 8, 'count': 0}), '');
    });

    test('折叠那行只报处数', () {
      expect(
        toolHeadline(const [
          ToolTrace(name: 'search_character', subject: '普拉娜'),
          ToolTrace(name: 'lookup_tag', subject: 'halo'),
          ToolTrace(name: 'lookup_tag', subject: 'smile'),
        ]),
        '查了 3 处资料',
      );
    });

    test('降级那条不算「查资料」,不能把处数灌水', () {
      expect(
        toolHeadline(const [
          ToolTrace(name: 'lookup_tag'),
          ToolTrace(name: kDegradedTool, summary: '已降级到安全模式'),
        ]),
        '查了 1 处资料',
      );
    });

    test('一处都没查、只有降级时报降级,不能报「查了 0 处」', () {
      expect(toolLabel(kDegradedTool), '安全模式');
      expect(
        toolHeadline(const [
          ToolTrace(name: kDegradedTool, summary: '已降级到安全模式'),
        ]),
        '安全模式',
      );
    });

    test('查询词能落盘也能读回来', () {
      const t = ToolTrace(
        name: 'search_character',
        subject: '普拉娜',
        summary: 'OC 0 个 + 通用 3/12 个 = 3 个',
      );
      final back = ToolTrace.fromJson(t.toJson());
      expect(back.subject, '普拉娜');
      expect(back.summary, t.summary);
      // 旧存档没有这个字段,读成空串而不是崩
      expect(ToolTrace.fromJson(const {'name': 'lookup_tag'}).subject, '');
    });

    test('补 summary 时别把查询词弄丢 —— tool_result 只回计数', () {
      const t = ToolTrace(name: 'lookup_tag', subject: 'halo');
      expect(t.copyWith(summary: '匹配 5 条').subject, 'halo');
    });
  });

  group('可选模型列表', () {
    // 这张表是后端下发的,app 只挑三样字段。挑错了不会崩,只会在顶栏显示一个
    // 看不出是哪一代的名字(「GLM」而不是「GLM 5.3 Flash」),所以拿真实形状钉住。
    Map<String, dynamic> live() => {
      'active': 'deepseek',
      'choices': {
        'deepseek': {
          // 后端写的是全角括号,去括号那条规则必须按真实形状钉
          'label': 'DeepSeek v4 flash（commandcode）',
          'short_label': 'DeepSeek',
          'model': 'deepseek-v4-flash@commandcode',
          'recommended': true,
          'aliases': ['ds'],
        },
        'gemini': {
          'label': 'Gemini(3.7 Flash Vertex)',
          'short_label': 'Gemini',
          'name': 'Gemini 3.7 Flash',
          'model': 'gemini-3.7-flash@vertex',
        },
        'chatgpt': {
          'label': 'ChatGPT(gpt-5.6-luna)',
          'name': 'GPT-5.6 Luna',
          'model': 'gpt-5.6-luna',
        },
        'glm': {
          'label': 'GLM 5.3 Flash(commandcode)',
          'name': 'GLM 5.3 Flash',
          'recommended': true,
          'model': 'glm-5.3-flash@commandcode',
        },
      },
    };

    test('显示名:有 name 用 name,没有就把 label 的括号说明去掉', () {
      final l = parseAgentModels(live());
      expect(l.byKey('gemini')!.name, 'Gemini 3.7 Flash');
      // deepseek 没配 name,得靠去括号得到完整型号,不能显示成整条 label
      expect(l.byKey('deepseek')!.name, 'DeepSeek v4 flash');
    });

    test('label 也没有就退回 key,不显示空白', () {
      final l = parseAgentModels({
        'choices': {
          'mystery': {'model': 'x'},
        },
      });
      expect(l.byKey('mystery')!.name, 'mystery');
    });

    test('推荐的排前面,同档保持后端顺序', () {
      final l = parseAgentModels(live());
      expect(
        [for (final c in l.choices) c.key],
        ['deepseek', 'glm', 'gemini', 'chatgpt'],
      );
      expect(l.byKey('glm')!.recommended, isTrue);
      expect(l.byKey('gemini')!.recommended, isFalse);
    });

    test('后端还没加 recommended 也照常出表 —— 只是没角标', () {
      final j = live();
      for (final v in (j['choices'] as Map).values) {
        (v as Map).remove('recommended');
      }
      final l = parseAgentModels(j);
      expect(l.choices.length, 4);
      expect(l.choices.every((c) => !c.recommended), isTrue);
      expect([for (final c in l.choices) c.key].first, 'deepseek');
    });

    test('形状不对不能整页打不开:少一条好过全没有', () {
      expect(parseAgentModels(const {}).choices, isEmpty);
      expect(parseAgentModels(const {'choices': 'nope'}).choices, isEmpty);
      final mixed = parseAgentModels(const {
        'choices': {
          'ok': {'name': 'OK'},
          'bad': 'not a map',
        },
      });
      expect([for (final c in mixed.choices) c.key], ['ok']);
    });

    test('active 读得出来 —— 没自己选过时顶栏显示的就是它', () {
      expect(parseAgentModels(live()).active, 'deepseek');
    });

    test('渠道近况:认得的照读,没有或认不出都是 unknown', () {
      final l = parseAgentModels(const {
        'choices': {
          'a': {'name': 'A', 'health': 'down'},
          'b': {'name': 'B', 'health': 'flaky'},
          'c': {'name': 'C'},
        },
        'free_choices': {
          'a': {'name': 'A', 'health': 'ok'},
        },
      });
      expect(l.byKey('a')!.health, ModelHealth.down);
      expect(l.byKey('b')!.health, ModelHealth.unknown);
      expect(l.byKey('c')!.health, ModelHealth.unknown);
      expect(l.free.single.health, ModelHealth.ok);
    });

    // 给 [free] 里那几条标上 free。live() 里有的条目推断成 Map<String, String>,
    // 塞不进 bool,所以整份重建
    Map<String, dynamic> withFree(Set<String> free) {
      final j = live();
      j['choices'] = {
        for (final e in (j['choices'] as Map).entries)
          e.key: {...e.value as Map, if (free.contains(e.key)) 'free': true},
      };
      return j;
    }

    Future<ProviderContainer> container({
      required bool authorized,
      required String pinned,
      Set<String> free = const {},
    }) async {
      final j = withFree(free);
      final c = ProviderContainer(
        overrides: [
          assistantBotAuthorizedProvider.overrideWithValue(authorized),
          agentModelsProvider.overrideWith((ref) async => parseAgentModels(j)),
          assistantModelPrefProvider.overrideWith(() => _PinnedPref(pinned)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(agentModelsProvider.future);
      await c.read(assistantModelPrefProvider.future);
      return c;
    }

    test('free 读得出来,没写就是不免费', () {
      final l = parseAgentModels(withFree({'glm'}));
      expect(l.byKey('glm')!.free, isTrue);
      expect(l.byKey('deepseek')!.free, isFalse);
      expect([for (final c in l.free) c.key], ['glm']);
    });

    test('后端一条免费的都没标:没授权时后端渠道不算,顶栏就是没选', () async {
      Future<AgentModelChoice?> shown({
        required bool authorized,
        required String pinned,
      }) async => (await container(
        authorized: authorized,
        pinned: pinned,
      )).read(assistantModelProvider);

      expect((await shown(authorized: true, pinned: 'glm'))?.key, 'glm');
      expect((await shown(authorized: true, pinned: ''))?.key, 'deepseek');
      expect(await shown(authorized: false, pinned: 'glm'), isNull);
      // 没选过时也不能拿后端默认那条顶上
      expect(await shown(authorized: false, pinned: ''), isNull);
      final c = await container(authorized: false, pinned: '');
      expect(c.read(assistantBackendAvailableProvider), isFalse);
      expect(c.read(assistantModelKeyProvider), '');
    });

    test('没授权只在免费的里挑,发的 key 跟显示的那条走', () async {
      Future<(String?, String)> pick(String pinned, Set<String> free) async {
        final c = await container(
          authorized: false,
          pinned: pinned,
          free: free,
        );
        expect(c.read(assistantBackendAvailableProvider), isTrue);
        return (
          c.read(assistantModelProvider)?.key,
          c.read(assistantModelKeyProvider),
        );
      }

      // 选过的免费:就是它
      expect(await pick('gemini', {'gemini', 'glm'}), ('gemini', 'gemini'));
      // 选过的不免费:后端默认免费就用默认
      expect(await pick('chatgpt', {'deepseek', 'glm'}), (
        'deepseek',
        'deepseek',
      ));
      // 默认也不免费:取第一条免费的(推荐在前),而且不能发空串让后端用默认
      expect(await pick('', {'gemini', 'glm'}), ('glm', 'glm'));
    });

    test('有授权时免费标记不影响选择', () async {
      final c = await container(
        authorized: true,
        pinned: 'chatgpt',
        free: {'glm'},
      );
      expect(c.read(assistantModelProvider)?.key, 'chatgpt');
      expect(c.read(assistantModelKeyProvider), 'chatgpt');
      final d = await container(authorized: true, pinned: '', free: {'glm'});
      expect(d.read(assistantModelProvider)?.key, 'deepseek');
      // 没选过照旧发空串,让后端用全局默认
      expect(d.read(assistantModelKeyProvider), '');
    });

    test('有 free_choices 时没授权按它列:同 key 换名、只在免费表的也列', () {
      final j = withFree({'gemini'});
      j['free_choices'] = {
        'glm': {'name': 'GLM 5.3 Flash', 'recommended': true},
        'gemini': {'name': 'Gemini 3.8 Flash'},
        'haiku55': {'label': 'Claude Haiku 5.5(官方)'},
      };
      final l = parseAgentModels(j);
      expect([for (final c in l.free) c.key], ['glm', 'gemini', 'haiku55']);
      expect(l.free.every((c) => c.free), isTrue);
      expect(l.pick('gemini', authorized: false)!.name, 'Gemini 3.8 Flash');
      expect(l.pick('haiku55', authorized: false)!.name, 'Claude Haiku 5.5');
      // 授权那边照旧用 choices 的名字,也没有 haiku55
      expect(l.pick('gemini', authorized: true)!.name, 'Gemini 3.7 Flash');
      expect(l.byKey('haiku55'), isNull);
    });
  });

  test('replaceCharacters 原样恢复,连 id 一起', () async {
    final n = await _notifier();
    final snap = [
      const CharacterPrompt(id: 'keep-me', name: '旧角色', positive: 'old'),
    ];
    n.applyAgentCharacters([
      (name: '新', positive: 'new', negative: '', position: ''),
    ]);
    n.replaceCharacters(snap);
    expect(n.state.characters.single.id, 'keep-me');
    expect(n.state.characters.single.positive, 'old');
  });
}

class _PinnedPref extends AssistantModelPrefNotifier {
  _PinnedPref(this.key);

  final String key;

  @override
  Future<String> build() async => key;
}

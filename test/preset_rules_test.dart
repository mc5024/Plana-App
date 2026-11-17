// AI 助手的规则预设:规则文件的读写、预设库的选用规则、条件段筛选、内置兜底那份。
//
// 规则文件的写法与服务端预设 yaml 一致,两边的段要能直接互相复制 ——
// 所以这里最要紧的是「导出去再导回来一个字不变」,以及「整份服务端预设能直接导」。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/assistant/assistant_mode.dart';
import 'package:plana_app/features/assistant/presets/default_rules.dart';
import 'package:plana_app/features/assistant/presets/preset_rule.dart';
import 'package:plana_app/features/assistant/presets/rules_file.dart';
import 'package:plana_app/features/assistant/presets/rules_library.dart';
import 'package:plana_app/features/assistant/runtime/prompt_assets.dart';
import 'package:plana_app/features/assistant/runtime/prompt_composer.dart';
import 'package:plana_app/l10n/l10n.dart';

Directory _tempRoot() {
  final root = Directory.systemTemp.createTempSync('plana_rules');
  addTearDown(() async {
    for (var i = 0; i < 10; i++) {
      try {
        root.deleteSync(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('规则文件', () {
    test('导出去再导回来:名字、作者、模型、每段内容一个字不变', () {
      const rules = [
        PresetRule(
          name: 'role',
          content: '<role>\n# 角色定义\n\n你是 Nyako:喵\n</role>',
        ),
        // 第一行以空格开头:不写缩进指示符的话,YAML 会把这几个空格当缩进吃掉
        PresetRule(name: 'indent', content: '  缩进开头\n    更深一层\n回到行首'),
        PresetRule(
          name: 'comic_composition',
          content: 'key: value # 看着像 YAML 的内容\n- 也不能被读成列表',
          when: 'comic',
        ),
      ];
      final back = decodeRulesFile(
        encodeRulesFile(
          name: '漫画特化: "第二版" # 测试',
          author: '某某',
          models: {RulesFamily.nai45, RulesFamily.nai5},
          rules: rules,
        ),
      );
      expect(back.name, '漫画特化: "第二版" # 测试');
      expect(back.author, '某某');
      expect(back.models, {RulesFamily.nai45, RulesFamily.nai5});
      expect(
        [for (final r in back.rules) r.name],
        [for (final r in rules) r.name],
      );
      expect(
        [for (final r in back.rules) r.content],
        [for (final r in rules) r.content],
      );
      expect(
        [for (final r in back.rules) r.when],
        [for (final r in rules) r.when],
      );
    });

    test('上一版导出的文件(只有一个 model)照样认', () {
      const v1 = '''
format: plana-rules
version: 1
model: nai5
sections:
  - name: "role"
    content: |
      规则
''';
      final f = decodeRulesFile(v1, fileName: 'plana-rules-nai5.yaml');
      expect(f.models, {RulesFamily.nai5});
      expect(f.name, 'plana-rules-nai5', reason: '文件里没写名字就用文件名');
      expect(f.author, '');
    });

    const serverPreset = '''
sections:
  - name: ctx_lead
    content: |
      外壳开头
  - name: role
    role: user
    group: rules
    content: |
      <role>规则一</role>
  - name: fixed_tag_placeholder
    when: tag_sentinel
    content: |
      占位符规则,服务端机制配套的,在外壳里
  - name: comic_composition
    role: user
    group: rules
    when: comic
    content: |
      漫画规则
  - name: ctx_think_format
    content: |
      思考格式
''';

    test('整份服务端预设直接导:只取规则主体,外壳不要', () {
      final f = decodeRulesFile(serverPreset, fileName: 'prompts_nai5.yaml');
      expect(f.rules.map((r) => r.name), ['role', 'comic_composition']);
      expect(f.rules.last.when, 'comic');
    });

    test('服务端预设按文件名认出模型,认不出就留空让用户选', () {
      expect(
        decodeRulesFile(serverPreset, fileName: 'prompts_nai5.yaml').models,
        {RulesFamily.nai5},
      );
      expect(
        decodeRulesFile(
          serverPreset,
          fileName: 'prompts_nai45_gemini.yaml',
        ).models,
        {RulesFamily.nai45},
      );
      expect(
        decodeRulesFile(serverPreset, fileName: '我改的.yaml').models,
        isEmpty,
      );
    });

    test('不是规则文件就说清楚,不静默导个空的进去', () {
      for (final bad in ['随便一段话', 'sections: []', 'sections: [\n']) {
        expect(() => decodeRulesFile(bad), throwsFormatException);
      }
    });

    test('YAML 写坏了,报错带上第几行(全文编辑里好找)', () {
      expect(
        () => decodeRulesFile('sections:\n  - name: role\n    content: a: b\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('第 3 行'),
          ),
        ),
      );
    });

    test('超过服务端上限的在导入时就拦下', () {
      final text = encodeRulesFile(
        name: 'x',
        author: '',
        models: {RulesFamily.nai5},
        rules: [PresetRule(name: 'role', content: 'x' * (kRulesMaxChars + 1))],
      );
      expect(() => decodeRulesFile(text), throwsFormatException);
    });
  });

  group('酒馆预设', () {
    test('按全局顺序取段,占位和空条目跳过,开关照带,注释宏删掉、别的宏留着', () {
      final text = jsonEncode({
        'temperature': 1,
        'prompts': [
          {
            'identifier': 'main',
            'name': 'Main Prompt',
            'role': 'system',
            'content': '主提示 {{char}}',
          },
          {'identifier': 'chatHistory', 'name': 'Chat History', 'marker': true},
          {'identifier': 'nsfw', 'name': 'Auxiliary Prompt', 'content': '辅助'},
          {
            'identifier': 'jailbreak',
            'name': 'Post-History Instructions',
            'content': '',
          },
          {'identifier': 'abc', 'name': '自定义', 'content': '{{// 注释}}正文'},
        ],
        'prompt_order': [
          {
            'character_id': 100000,
            'order': [
              {'identifier': 'main', 'enabled': true},
            ],
          },
          {
            'character_id': 100001,
            'order': [
              {'identifier': 'abc', 'enabled': true},
              {'identifier': 'main', 'enabled': true},
              {'identifier': 'chatHistory', 'enabled': true},
              {'identifier': 'nsfw', 'enabled': false},
              {'identifier': 'jailbreak', 'enabled': true},
            ],
          },
        ],
      });
      final f = decodeRulesFile(text, fileName: '破限预设.json');
      expect(f.name, '破限预设');
      expect(f.models, isEmpty, reason: '酒馆预设不分 NAI 模型,导入时让用户选');
      expect(
        [for (final r in f.rules) r.name],
        ['自定义', 'Main Prompt', 'Auxiliary Prompt'],
      );
      expect([for (final r in f.rules) r.enabled], [true, true, false]);
      expect(f.rules[0].content, '正文');
      expect(f.rules[1].content, '主提示 {{char}}');
    });

    test('没有 prompt_order 就按 prompts 原顺序;一条能用的都没有报错', () {
      final f = decodeRulesFile(
        jsonEncode({
          'prompts': [
            {'identifier': 'b', 'name': 'B', 'content': 'b'},
            {'identifier': 'a', 'content': 'a'},
          ],
        }),
      );
      expect([for (final r in f.rules) r.name], ['B', 'a']);
      expect(
        () => decodeRulesFile(
          jsonEncode({
            'prompts': [
              {'identifier': 'chatHistory', 'marker': true},
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  test('副本名:原名加后缀,重名往后加数字', () {
    final first = 'Nyako v5 ${l10nNow.copySuffix}';
    expect(const RulesLibrary().copyNameOf('Nyako v5'), first);
    final lib = RulesLibrary(
      presets: [
        RulesPreset(
          id: 'r1',
          name: first,
          author: '',
          models: {RulesFamily.nai5},
          rules: const [],
        ),
      ],
    );
    expect(lib.copyNameOf('Nyako v5'), '$first 2');
  });

  test('一段都没有的预设也读得回来(新建的从空的开始)', () {
    final lib = RulesLibrary(
      presets: [
        RulesPreset(
          id: 'r1',
          name: '空',
          author: '',
          models: {RulesFamily.nai5},
          rules: const [],
        ),
      ],
    );
    final back = RulesLibrary.fromJson(jsonDecode(jsonEncode(lib.toJson())));
    expect(back.presets.single.rules, isEmpty);
  });

  group('预设库', () {
    const comic = RulesPreset(
      id: 'p1',
      name: '漫画特化',
      author: '某某',
      models: {RulesFamily.nai5},
      rules: [PresetRule(name: 'role', content: 'R')],
    );

    test('什么都没选:两个模型都用默认规则,什么都不发', () {
      const lib = RulesLibrary(presets: [comic]);
      for (final f in RulesFamily.values) {
        expect(lib.activeFor(f).isDefault, isTrue);
        expect(lib.customRulesFor(f), isNull);
      }
    });

    test('选了就用选的那份', () {
      const lib = RulesLibrary(
        presets: [comic],
        active: {RulesFamily.nai5: 'p1'},
      );
      expect(lib.activeFor(RulesFamily.nai5).name, '漫画特化');
      expect(lib.customRulesFor(RulesFamily.nai5)!.single.content, 'R');
      expect(lib.activeFor(RulesFamily.nai45).isDefault, isTrue);
    });

    test('选的那份不支持这个模型:回落默认,不能把 5 的规则发给 4.5', () {
      const lib = RulesLibrary(
        presets: [comic],
        active: {RulesFamily.nai45: 'p1'},
      );
      expect(lib.activeFor(RulesFamily.nai45).isDefault, isTrue);
    });

    test('选的那份被删了:回落默认', () {
      const lib = RulesLibrary(active: {RulesFamily.nai5: 'p1'});
      expect(lib.activeFor(RulesFamily.nai5).isDefault, isTrue);
    });

    test('默认规则排第一,存得下也读得回来', () {
      const lib = RulesLibrary(
        presets: [comic],
        active: {RulesFamily.nai5: 'p1'},
      );
      // 默认规则按模型分两份排在最前,各自只支持自己那个模型
      expect([for (final p in lib.all.take(2)) p.isDefault], [true, true]);
      expect(
        [for (final p in lib.all.take(2)) p.models],
        [
          {RulesFamily.nai45},
          {RulesFamily.nai5},
        ],
      );
      final back = RulesLibrary.fromJson(jsonDecode(jsonEncode(lib.toJson())));
      expect(back.presets.single.name, '漫画特化');
      expect(back.presets.single.author, '某某');
      expect(back.presets.single.models, {RulesFamily.nai5});
      expect(back.activeFor(RulesFamily.nai5).id, 'p1');
    });

    test('上一版每个模型一份无名规则:迁成预设,并且照旧在用', () async {
      final stores = await AppStores.open(rootOverride: _tempRoot());
      await stores.prefs.write(
        key: 'assistant_rules',
        value: jsonEncode({
          'nai5': [
            {'name': 'role', 'content': '我导入过的规则'},
          ],
        }),
      );
      final c = ProviderContainer(
        overrides: [appStoresProvider.overrideWithValue(stores)],
      );
      addTearDown(c.dispose);

      final lib = await c.read(rulesLibraryProvider.future);
      expect(lib.presets.single.models, {RulesFamily.nai5});
      expect(
        lib.customRulesFor(RulesFamily.nai5)!.single.content,
        '我导入过的规则',
        reason: '升级之后不该悄悄换回默认规则',
      );
      expect(lib.activeFor(RulesFamily.nai45).isDefault, isTrue);
      expect(await stores.prefs.read(key: 'assistant_rules'), isNull);
    });

    test('点默认规则那张 = 回到默认,不存一个指向默认的选择', () async {
      final stores = await AppStores.open(rootOverride: _tempRoot());
      final c = ProviderContainer(
        overrides: [appStoresProvider.overrideWithValue(stores)],
      );
      addTearDown(c.dispose);
      await c.read(rulesLibraryProvider.future);
      final n = c.read(rulesLibraryProvider.notifier);
      final id = await n.add(
        name: '漫画特化',
        author: '',
        models: {RulesFamily.nai5},
        rules: const [PresetRule(name: 'role', content: 'R')],
      );
      await n.use(RulesFamily.nai5, id);
      await n.use(RulesFamily.nai5, defaultPresetOf(RulesFamily.nai5).id);
      final lib = c.read(rulesLibraryProvider).value!;
      expect(lib.activeFor(RulesFamily.nai5).isDefault, isTrue);
      expect(lib.active, isEmpty);
    });

    test('删掉正在用的预设,那个模型回到默认', () async {
      final stores = await AppStores.open(rootOverride: _tempRoot());
      final c = ProviderContainer(
        overrides: [appStoresProvider.overrideWithValue(stores)],
      );
      addTearDown(c.dispose);
      await c.read(rulesLibraryProvider.future);
      final n = c.read(rulesLibraryProvider.notifier);
      final id = await n.add(
        name: '漫画特化',
        author: '',
        models: {RulesFamily.nai5},
        rules: const [PresetRule(name: 'role', content: 'R')],
      );
      await n.use(RulesFamily.nai5, id);
      expect(
        c.read(rulesLibraryProvider).value!.activeFor(RulesFamily.nai5).id,
        id,
      );
      await n.remove(id);
      final lib = c.read(rulesLibraryProvider).value!;
      expect(lib.activeFor(RulesFamily.nai5).isDefault, isTrue);
      expect(lib.active, isEmpty);
    });

    test('全文编辑存回原处:还是那一份、照旧在用;不再支持的模型回到默认', () async {
      final stores = await AppStores.open(rootOverride: _tempRoot());
      final c = ProviderContainer(
        overrides: [appStoresProvider.overrideWithValue(stores)],
      );
      addTearDown(c.dispose);
      await c.read(rulesLibraryProvider.future);
      final n = c.read(rulesLibraryProvider.notifier);
      final id = await n.add(
        name: '漫画特化',
        author: '',
        models: {RulesFamily.nai45, RulesFamily.nai5},
        rules: const [PresetRule(name: 'role', content: 'R')],
      );
      await n.use(RulesFamily.nai45, id);
      await n.use(RulesFamily.nai5, id);
      await n.replace(
        id,
        name: '漫画特化 2',
        author: '某某',
        models: {RulesFamily.nai5},
        rules: const [PresetRule(name: 'role', content: 'R2')],
      );
      final lib = c.read(rulesLibraryProvider).value!;
      expect(lib.presets.single.id, id);
      expect(lib.presets.single.name, '漫画特化 2');
      expect(lib.customRulesFor(RulesFamily.nai5)!.single.content, 'R2');
      expect(lib.activeFor(RulesFamily.nai45).isDefault, isTrue);
      expect(lib.active, {RulesFamily.nai5: id});
    });
  });

  group('工具层', () {
    // 怎么调工具、系统塞进来的数据块怎么读,是 app 自己的工具层,发出去之前挂到在用的
    // 预设上。原先这段长在预设里,用户自己写的预设不照抄就调不了工具。
    const layer = '<tool_usage>工具说明</tool_usage>';

    test('挂在 role 后面 —— 默认规则原本就是这个顺序', () {
      final out = withToolLayer(const [
        PresetRule(name: 'role', content: 'R'),
        PresetRule(name: 'prompt_construction', content: 'P'),
      ], layer);
      expect(out.map((r) => r.name), [
        'role',
        kToolLayerName,
        'prompt_construction',
      ]);
    });

    test('没有 role 的预设接在最后,别把工具说明顶到人设前面', () {
      final out = withToolLayer(const [
        PresetRule(name: 'style', content: 'S'),
      ], layer);
      expect(out.map((r) => r.name), ['style', kToolLayerName]);
    });

    test('预设里原有的工具说明丢掉,只留 app 这份', () {
      final out = withToolLayer(const [
        PresetRule(name: 'role', content: 'R'),
        PresetRule(name: kToolLayerName, content: '老版本导入时带进来的'),
      ], layer);
      expect(out.where((r) => r.name == kToolLayerName).single.content, layer);
    });

    test('导入时工具层不要:服务端标了 layer: tools 的、老文件里同名的', () {
      const text = '''
sections:
  - name: role
    group: rules
    content: |
      R
  - name: tool_usage
    group: rules
    layer: tools
    content: |
      服务端那份工具说明
''';
      expect(decodeRulesFile(text).rules.map((r) => r.name), ['role']);
      const old = '''
sections:
  - name: role
    content: |
      R
  - name: tool_usage
    content: |
      老导出文件里的工具说明
''';
      expect(decodeRulesFile(old).rules.map((r) => r.name), ['role']);
    });

    test('存下来的老预设里带着工具说明:读的时候丢掉', () {
      final p = RulesPreset.fromJson({
        'id': 'r1',
        'name': '老预设',
        'models': ['nai5'],
        'rules': [
          {'name': 'role', 'content': 'R'},
          {'name': 'tool_usage', 'content': 'T'},
        ],
      })!;
      expect(p.rules.map((r) => r.name), ['role']);
    });

    test('导入时给工具层留余量:整份发出去还得在服务端上限里', () {
      final text = encodeRulesFile(
        name: 'x',
        author: '',
        models: {RulesFamily.nai5},
        rules: [
          PresetRule(name: 'role', content: 'x' * (kRulesMaxChars - 1000)),
        ],
      );
      expect(() => decodeRulesFile(text), throwsFormatException);
    });

    test('app 自带的工具约定与出图格式都在,也不再提 bot', () async {
      final tools = await toolLayerText();
      expect(tools, startsWith('<tool_usage>'));
      expect(tools, contains('tool_call'));
      expect(tools, isNot(contains('Bot 端')));
      expect(await outputFormatText(), contains('nai_draw'));
    });

    test('默认规则里已经没有工具说明,不会和工具层发两份', () async {
      for (final f in RulesFamily.values) {
        final rules = await bundledRules(f);
        expect(rules.map((r) => r.name), isNot(contains(kToolLayerName)));
      }
    });

    test('系统提示:规则(工具约定挂在 role 后面)、出图格式、工具清单、附加说明依次排开', () {
      final system = composeSystemPrompt(
        rules: const [
          PresetRule(name: 'role', content: 'R'),
          PresetRule(name: 'comic_composition', content: 'C', when: 'comic'),
        ],
        modes: const [],
        toolLayer: '<tool_usage>',
        outputFormat: '[输出格式]',
        toolList: '[可用工具]',
        notes: const ['', '[OC 占位符模式]'],
      );
      expect(system, 'R\n\n<tool_usage>\n\n[输出格式]\n\n[可用工具]\n\n[OC 占位符模式]');
    });

    test('系统提示也按用户选的模式挑段', () {
      final system = composeSystemPrompt(
        rules: const [
          PresetRule(name: 'role', content: 'R'),
          PresetRule(name: 'mode_natural', content: 'NL', when: 'mode:natural'),
        ],
        modes: assistantModeKeys(AssistantMode.natural),
      );
      expect(system, 'R\n\nNL');
    });
  });

  group('条件段筛选', () {
    const rules = [
      PresetRule(name: 'role', content: 'R'),
      PresetRule(name: 'comic_composition', content: 'C', when: 'comic'),
      PresetRule(name: 'output_specification', content: 'O'),
    ];

    test('没选漫画:漫画规则不发 —— 不按聊天内容自动判', () {
      expect(renderRules(rules, const []), 'R\n\nO');
    });

    test('选的模式带着 comic:发', () {
      expect(renderRules(rules, const ['comic']), 'R\n\nC\n\nO');
    });

    const withModes = [
      PresetRule(name: 'role', content: 'R'),
      PresetRule(name: 'comic_composition', content: 'C', when: 'comic'),
      PresetRule(name: 'mode_comic', content: 'MC', when: 'mode:comic'),
      PresetRule(name: 'mode_natural', content: 'NL', when: 'mode:natural'),
    ];

    test('模式段只认选中的那个键:光有 comic 不带 mode:comic 那段', () {
      expect(renderRules(withModes, const ['comic']), 'R\n\nC');
    });

    test('选了漫画:漫画规则和模式段都在,不用等「四格」这类词判到', () {
      expect(
        renderRules(withModes, assistantModeKeys(AssistantMode.comic)),
        'R\n\nC\n\nMC',
      );
    });

    test('模式选「无」什么都不发给模型', () {
      expect(assistantModeKeys(AssistantMode.normal), isEmpty);
      expect(
        renderRules(withModes, assistantModeKeys(AssistantMode.normal)),
        'R',
      );
    });

    test('选了仅自然语言:只多它那段,漫画规则不跟着来', () {
      expect(
        renderRules(withModes, assistantModeKeys(AssistantMode.natural)),
        'R\n\nNL',
      );
    });

    test('! 开头的没选才发:选了仅自然语言,构建规则换成自然语言那份', () {
      const swap = [
        PresetRule(name: 'role', content: 'R'),
        PresetRule(
          name: 'prompt_construction',
          content: 'MIX',
          when: '!mode:natural',
        ),
        PresetRule(
          name: 'natural_construction',
          content: 'NAT',
          when: 'mode:natural',
        ),
      ];
      expect(renderRules(swap, const []), 'R\n\nMIX');
      expect(
        renderRules(swap, assistantModeKeys(AssistantMode.comic)),
        'R\n\nMIX',
      );
      expect(
        renderRules(swap, assistantModeKeys(AssistantMode.natural)),
        'R\n\nNAT',
      );
    });

    test('漫画、仅自然语言要预设里写了那一段才能选,「无」哪份预设都能选', () {
      expect(supportedModes(withModes), AssistantMode.values.toSet());
      expect(supportedModes(rules), {AssistantMode.normal});
    });

    test('停用的段不发、不算模式、不占上限,导出导回来还是停用', () {
      final off = [
        for (final r in withModes)
          r.name == 'mode_comic' || r.name == 'role'
              ? r.copyWith(enabled: false)
              : r,
      ];
      expect(renderRules(off, assistantModeKeys(AssistantMode.comic)), 'C');
      expect(supportedModes(off), {
        AssistantMode.normal,
        AssistantMode.natural,
      });

      final big = [
        const PresetRule(name: 'a', content: 'x'),
        PresetRule(name: 'b', content: 'y' * kRulesMaxChars, enabled: false),
      ];
      expect(rulesLimitError(big), isNull);
      expect(
        rulesLimitError([big[0], big[1].copyWith(enabled: true)]),
        isNotNull,
      );

      final back = decodeRulesFile(
        encodeRulesFile(
          name: 'n',
          author: '',
          models: {RulesFamily.nai5},
          rules: off,
        ),
      );
      expect(
        [for (final r in back.rules) r.enabled],
        [for (final r in off) r.enabled],
      );
      expect(PresetRule.fromJson(off.first.toJson())!.enabled, isFalse);
      expect(withModes.first.toJson().containsKey('enabled'), isFalse);
    });

    test('条件段小标签:常驻没有,comic 与 mode:comic 同名,! 开头是不发', () {
      expect(whenTag(''), isNull);
      expect(whenTag('comic'), whenTag('mode:comic'));
      expect(whenTag('!mode:natural'), isNot(whenTag('mode:natural')));
      expect(whenTag('!mode:natural'), contains(whenTag('mode:natural')!));
      expect(whenTag('mode:custom'), contains('mode:custom'));
      expect(ruleSectionLabel('role'), isNot('role'));
      expect(ruleSectionLabel('我的段'), '我的段');
    });
  });

  test('默认规则:NAI5 全部模式都能选,4.5 没有漫画规则所以不给选漫画', () async {
    expect(
      supportedModes(await bundledRules(RulesFamily.nai5)),
      AssistantMode.values.toSet(),
    );
    expect(supportedModes(await bundledRules(RulesFamily.nai45)), {
      AssistantMode.normal,
      AssistantMode.natural,
    });
  });

  test('默认 NAI5 规则:平时发混合写法,选了仅自然语言整段换成纯自然语言写法', () async {
    final rules = await bundledRules(RulesFamily.nai5);
    final plain = renderRules(rules, const []);
    final natural = renderRules(
      rules,
      assistantModeKeys(AssistantMode.natural),
    );
    expect(plain, contains('tag + 短句 + 自然语言混排'));
    expect(plain, isNot(contains('提示词构建：纯自然语言')));
    expect(natural, contains('提示词构建：纯自然语言'));
    expect(natural, isNot(contains('tag + 短句 + 自然语言混排')));
    // 两份同名标签只发一份,别处「按 <prompt_construction> 写」两边都对得上
    for (final text in [plain, natural]) {
      expect('<prompt_construction>\n'.allMatches(text), hasLength(1));
    }
  });

  test('默认规则的名称、作者、版本读预设里写的,缺了才用占位', () async {
    final nai5 = await bundledDefaultRules(RulesFamily.nai5);
    expect((nai5.name, nai5.author, nai5.version), ('Nyako', '夏夜浮梦', 'v5'));
    final nai45 = await bundledDefaultRules(RulesFamily.nai45);
    expect(nai45.version, 'v4.5');

    final bare = DefaultRules.fromJson({
      'rules': [
        {'name': 'role', 'content': 'R'},
      ],
    }, RulesFamily.nai45)!;
    expect(
      (bare.name, bare.author, bare.version),
      (kDefaultRulesName, kDefaultRulesAuthor, 'v4.5'),
    );
    expect(DefaultRules.fromJson({'rules': []}, RulesFamily.nai5), isNull);
  });

  test('图片模型分档与服务端一致', () {
    expect(rulesFamilyOf('nai_v5_full'), RulesFamily.nai5);
    expect(rulesFamilyOf('nai_v45_full'), RulesFamily.nai45);
    expect(rulesFamilyOf(''), RulesFamily.nai45);
  });

  test('内置兜底的 NAI5 规则段是全的,而且导出导入一个字不变', () async {
    // 原先那份是照着 4.5 的段落清单裁的,5 多出来的五段全丢了,
    // 剩下的文字里还在「见漫画规则」—— 指向一段根本不存在的规则。
    final rules = await bundledRules(RulesFamily.nai5);
    final names = rules.map((r) => r.name).toList();
    expect(names.first, 'role');
    // output_specification 之后只跟用户手动选的模式段
    expect(names.sublist(names.indexOf('output_specification') + 1), [
      'mode_comic',
      'mode_natural',
    ]);
    for (final n in [
      'model_traits',
      'natural_construction',
      'comic_composition',
      'custom_tags',
      'text_rendering',
      'alpha_transparency',
    ]) {
      expect(names, contains(n));
    }
    expect(names, isNot(contains('fixed_tag_placeholder')));
    // 真实规则里满是「key: |」、「# ====」这类长得像 YAML 的内容,拿它做一遍往返:
    // 用户导出当底稿、改完导回来,没改的段必须逐字一样
    final back = decodeRulesFile(
      encodeRulesFile(
        name: '默认规则',
        author: 'Plana',
        models: {RulesFamily.nai5},
        rules: rules,
      ),
    );
    expect(
      [for (final r in back.rules) r.content],
      [for (final r in rules) r.content],
    );
    expect(
      [for (final r in back.rules) r.when],
      [for (final r in rules) r.when],
    );
    expect(
      await rootBundle.loadString('assets/prompts/nai45.json'),
      isNotEmpty,
    );
  });
}

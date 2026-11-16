/// 规则预设的段落页:内置段按用途归成几张卡(见 [ruleCardsOf]),认不出的段名各自一张。
/// 点卡改内容和触发条件(一组几段就上下排开一起改),点自己加的段名改名;
/// ⏻ 停用、🗑 删除、长按拖动排序都按整张卡来,顶栏加一段或全文编辑。
///
/// 默认规则的原件在包里,改不了:第一次保存时另存为一份新预设,这个模型原先用默认规则的
/// 就改用新存的这份,之后在这页接着改的都是那份。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../../l10n/l10n.dart';
import '../generate/widgets/common.dart'
    show RoundIconBtn, confirmDialog, hintSnack;
import 'presets/default_rules.dart';
import 'presets/preset_rule.dart';
import 'presets/rules_file.dart';
import 'presets/rules_library.dart';

class RulesSectionsPage extends ConsumerStatefulWidget {
  /// [family] 给了就是那个模型的默认规则,否则是 [presetId] 那份导入的预设。
  const RulesSectionsPage({super.key, this.family, this.presetId})
    : assert((family == null) != (presetId == null));

  final RulesFamily? family;
  final String? presetId;

  @override
  ConsumerState<RulesSectionsPage> createState() => _RulesSectionsPageState();
}

class _RulesSectionsPageState extends ConsumerState<RulesSectionsPage> {
  /// 在改的那份预设;默认规则还没另存时是 null。
  late String? _id = widget.presetId;

  /// 默认规则正在另存,这期间的操作不接,免得存出两份。
  var _copying = false;

  RulesPreset? _preset(RulesLibrary? lib) =>
      lib?.presets.where((p) => p.id == _id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(rulesLibraryProvider).value;
    final String title;
    final List<PresetRule>? rules;
    if (_id != null) {
      final p = _preset(lib);
      title = p?.name ?? '';
      rules = p?.rules;
    } else {
      final d = ref.watch(defaultRulesProvider(widget.family!)).value;
      title = d == null ? '' : '${d.name} ${d.version}'.trim();
      rules = d?.rules;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: context.l10n.fullTextEdit,
            onPressed: rules == null ? null : () => _editFullText(rules!),
            icon: const Icon(Icons.notes),
          ),
          IconButton(
            tooltip: context.l10n.addRuleSection,
            onPressed: rules == null ? null : () => _add(rules!),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: rules == null
          ? const Center(child: CircularProgressIndicator())
          : _list(rules),
    );
  }

  Widget _list(List<PresetRule> rules) {
    final cards = ruleCardsOf(rules);
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: cards.length,
      proxyDecorator: (child, _, _) => Material(
        color: Colors.transparent,
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      // 整张卡一起挪:组里的段挪完挨在一起
      onReorderItem: (from, to) {
        final next = [...cards];
        next.insert(to, next.removeAt(from));
        _commit([
          for (final c in next)
            for (final i in c.indices) rules[i],
        ]);
      },
      itemBuilder: (context, k) {
        final c = cards[k];
        final members = [for (final i in c.indices) rules[i]];
        return Padding(
          key: ObjectKey(members.first),
          padding: const EdgeInsets.only(bottom: 10),
          child: _RuleCardView(
            title: c.group == null
                ? members.single.name
                : ruleGroupLabel(c.group!),
            rules: members,
            onEdit: () => _edit(rules, c),
            onRename: c.group == null
                ? () => _rename(rules, c.indices.single)
                : null,
            onToggle: () => _toggle(rules, c),
            // 预设至少留一段:一段不剩的预设读回来会被当成坏数据丢掉
            onDelete: rules.length > c.indices.length
                ? () => _delete(rules, c)
                : null,
          ),
        );
      },
    );
  }

  /// 存回去。默认规则第一次存是另存为一份新预设。
  Future<void> _commit(
    List<PresetRule> rules, {
    String? name,
    String? author,
    Set<RulesFamily>? models,
  }) async {
    if (_copying) return;
    final err = rulesEditLimitError(rules);
    if (err != null) {
      hintSnack(context, err, icon: Icons.error_outline);
      return;
    }
    final n = ref.read(rulesLibraryProvider.notifier);
    final id = _id;
    if (id != null) {
      final p = _preset(ref.read(rulesLibraryProvider).value);
      if (p == null) return;
      await n.replace(
        id,
        name: name ?? p.name,
        author: author ?? p.author,
        models: models ?? p.models,
        rules: rules,
      );
      return;
    }
    final f = widget.family!;
    _copying = true;
    try {
      final d = await bundledDefaultRules(f);
      final copyName = name ?? '${d.name} ${d.version}'.trim();
      final copyModels = models ?? {f};
      final wasDefault =
          ref.read(rulesLibraryProvider).value?.activeFor(f).isDefault ?? true;
      final newId = await n.add(
        name: copyName,
        author: author ?? d.author,
        models: copyModels,
        rules: rules,
      );
      if (wasDefault && copyModels.contains(f)) await n.use(f, newId);
      if (!mounted) return;
      setState(() => _id = newId);
      hintSnack(
        context,
        context.l10n.savedAsNamed(copyName),
        icon: Icons.check_circle_outline,
      );
    } finally {
      _copying = false;
    }
  }

  /// 一段的卡进单段页;一组几段的进组页,几段上下排开一起改。
  Future<void> _edit(List<PresetRule> rules, RuleCard c) async {
    final List<PresetRule>? edited;
    if (c.indices.length == 1) {
      final r = await Navigator.push<PresetRule>(
        context,
        MaterialPageRoute(
          builder: (_) => _SectionEditorPage(rule: rules[c.indices.single]),
        ),
      );
      edited = r == null ? null : [r];
    } else {
      edited = await Navigator.push<List<PresetRule>>(
        context,
        MaterialPageRoute(
          builder: (_) => _GroupEditorPage(
            title: ruleGroupLabel(c.group!),
            rules: [for (final i in c.indices) rules[i]],
          ),
        ),
      );
    }
    if (edited == null) return;
    final next = [...rules];
    for (final (j, i) in c.indices.indexed) {
      next[i] = edited[j];
    }
    await _commit(next);
  }

  /// 有一段开着就整张关掉,全关着就整张打开。
  Future<void> _toggle(List<PresetRule> rules, RuleCard c) {
    final anyOn = c.indices.any((i) => rules[i].enabled);
    final next = [...rules];
    for (final i in c.indices) {
      next[i] = rules[i].copyWith(enabled: !anyOn);
    }
    return _commit(next);
  }

  Future<void> _add(List<PresetRule> rules) async {
    final name = await _askName('');
    if (name == null || !mounted) return;
    final r = await Navigator.push<PresetRule>(
      context,
      MaterialPageRoute(
        builder: (_) => _SectionEditorPage(
          rule: PresetRule(name: name, content: ''),
        ),
      ),
    );
    if (r != null) await _commit([...rules, r]);
  }

  /// 点名字改名(只有认不出的段,内置段归在组里不单独改名)。
  Future<void> _rename(List<PresetRule> rules, int i) async {
    final shown = rules[i].name;
    final name = await _askName(shown);
    if (name == null || name == shown) return;
    await _commit([...rules]..[i] = rules[i].copyWith(name: name));
  }

  /// 问段名,取消或留空返回 null。
  Future<String?> _askName(String initial) async {
    final ctrl = TextEditingController(text: initial);
    final l = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial.isEmpty ? l.addRuleSection : l.rename),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: l.ruleSectionName,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(l.confirm),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final v = name?.trim() ?? '';
    if (v.isEmpty) return null;
    // 和工具层同名的段读回来会被当成旧货丢掉
    if (v == kToolLayerName) {
      if (mounted) {
        hintSnack(
          context,
          l.ruleSectionNameReserved,
          icon: Icons.error_outline,
        );
      }
      return null;
    }
    return v;
  }

  Future<void> _delete(List<PresetRule> rules, RuleCard c) async {
    final label = c.group == null
        ? rules[c.indices.single].name
        : ruleGroupLabel(c.group!);
    final ok = await confirmDialog(
      context,
      title: c.indices.length > 1
          ? context.l10n.deleteRuleGroupQ
          : context.l10n.deleteRuleSectionQ,
      message: context.l10n.deleteRuleSectionBody(label),
      confirmLabel: context.l10n.delete,
    );
    if (!ok) return;
    final drop = c.indices.toSet();
    await _commit([
      for (final (i, r) in rules.indexed)
        if (!drop.contains(i)) r,
    ]);
  }

  /// 全文编辑:摊开的就是导出的那份文本,电脑上改好的能整段贴进来。
  Future<void> _editFullText(List<PresetRule> rules) async {
    final p = _preset(ref.read(rulesLibraryProvider).value);
    final RulesFamily? f = widget.family;
    final DefaultRules? d = p == null && f != null
        ? await bundledDefaultRules(f)
        : null;
    if (!mounted) return;
    final name = p?.name ?? '${d?.name ?? ''} ${d?.version ?? ''}'.trim();
    final file = await Navigator.push<RulesFile>(
      context,
      MaterialPageRoute(
        builder: (_) => _RulesEditorPage(
          title: name,
          text: encodeRulesFile(
            name: name,
            author: p?.author ?? d?.author ?? '',
            models: p?.models ?? {?f},
            rules: rules,
          ),
        ),
      ),
    );
    if (file == null) return;
    await _commit(
      file.rules,
      name: file.name,
      author: file.author,
      models: file.models,
    );
  }
}

class _RuleCardView extends StatelessWidget {
  const _RuleCardView({
    required this.title,
    required this.rules,
    required this.onEdit,
    required this.onToggle,
    this.onRename,
    this.onDelete,
  });

  final String title;

  /// 卡里的段。
  final List<PresetRule> rules;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  /// 内置段的组卡不改名,传 null。
  final VoidCallback? onRename;

  /// 删了就一段不剩时删不了,传 null。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final on = rules.any((r) => r.enabled);
    final whens = {for (final r in rules) whenLabel(r.when)};
    final meta = [
      if (whens.length == 1) whens.single,
      if (rules.length > 1) context.l10n.sectionsN(rules.length),
      context.l10n.charsN(rules.fold(0, (n, r) => n + r.content.length)),
    ].join(' · ');
    // 与角色卡的开关 / 删除同一尺寸(窄屏同样收到 32)
    final btnSize = MediaQuery.sizeOf(context).width < 350 ? 32.0 : 36.0;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                // 停用只弱化内容,操作按钮保持可用(同角色卡)
                Expanded(
                  child: AnimatedOpacity(
                    duration: Motion.fast,
                    opacity: on ? 1 : .45,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: onRename,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodyLarge!.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          style: context.texts.labelSmall!.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                RoundIconBtn(
                  Icons.power_settings_new,
                  size: btnSize,
                  color: on ? scheme.primary : scheme.outline,
                  tooltip: on
                      ? context.l10n.disableKeepConfig
                      : context.l10n.enable,
                  onTap: () {
                    Haptics.selection();
                    onToggle();
                  },
                ),
                const SizedBox(width: 6),
                RoundIconBtn(
                  Icons.delete_outline,
                  size: btnSize,
                  color: onDelete == null ? scheme.outline : scheme.error,
                  tooltip: context.l10n.delete,
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 去掉开头的空行和末尾空白,不动第一行的缩进。
String _tidy(String s) =>
    s.replaceFirst(RegExp(r'^(?:[ \t]*\r?\n)+'), '').trimRight();

/// 选触发条件,没改返回 null。
Future<String?> _pickWhen(BuildContext context, String current) async {
  // `comic` 和 `mode:comic` 是一回事,对话框里落在同一项上
  final shown = current == 'comic' ? '${kModeWhenPrefix}comic' : current;
  final options = [...kWhenChoices, if (!kWhenChoices.contains(shown)) shown];
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.triggerCondition),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: RadioGroup<String>(
        groupValue: shown,
        onChanged: (v) => Navigator.of(ctx).pop(v),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              RadioListTile<String>(value: o, title: Text(whenLabel(o))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    ),
  );
  if (picked == null || picked == shown) return null;
  Haptics.selection();
  return picked;
}

/// 触发条件按钮:当前条件 + 上下箭头,点开选。
class _WhenButton extends StatelessWidget {
  const _WhenButton({required this.when, required this.onTap});

  final String when;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return TextButton(
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            whenLabel(when),
            style: context.texts.labelLarge!.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.unfold_more, size: 18, color: scheme.outline),
        ],
      ),
    );
  }
}

Future<void> _confirmLeave(BuildContext context) async {
  final ok = await confirmDialog(
    context,
    title: context.l10n.discardChangesQ,
    message: context.l10n.unsavedLost2,
    confirmLabel: context.l10n.discardAction,
  );
  if (ok && context.mounted) Navigator.pop(context);
}

/// 一段的编辑页:内容直接铺在页面上,顶栏右边改触发条件、保存。
/// 没保存就返回要确认一下。
class _SectionEditorPage extends StatefulWidget {
  const _SectionEditorPage({required this.rule});

  final PresetRule rule;

  @override
  State<_SectionEditorPage> createState() => _SectionEditorPageState();
}

class _SectionEditorPageState extends State<_SectionEditorPage> {
  late final _ctl = TextEditingController(text: widget.rule.content);
  late var _when = widget.rule.when;
  var _dirty = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final content = _tidy(_ctl.text);
    if (content.trim().isEmpty) {
      hintSnack(
        context,
        context.l10n.ruleSectionEmpty,
        icon: Icons.error_outline,
      );
      return;
    }
    Navigator.pop(context, widget.rule.copyWith(content: content, when: _when));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(ruleSectionLabel(widget.rule.name)),
          actions: [
            _WhenButton(
              when: _when,
              onTap: () async {
                final v = await _pickWhen(context, _when);
                if (v != null) {
                  setState(() {
                    _when = v;
                    _dirty = true;
                  });
                }
              },
            ),
            IconButton(
              tooltip: context.l10n.save,
              onPressed: _save,
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: TextField(
            controller: _ctl,
            expands: true,
            maxLines: null,
            autofocus: widget.rule.content.isEmpty,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            // YAML 靠缩进和原样的键名,输入法的自动更正只会帮倒忙
            autocorrect: false,
            enableSuggestions: false,
            style: mono(context, size: 13, weight: FontWeight.w400),
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一组几段的编辑页:一段一张卡上下排开,卡头是段名、触发条件和 ⏻,
/// 下面就是这段的内容。顶栏保存一起存。
class _GroupEditorPage extends StatefulWidget {
  const _GroupEditorPage({required this.title, required this.rules});

  final String title;
  final List<PresetRule> rules;

  @override
  State<_GroupEditorPage> createState() => _GroupEditorPageState();
}

class _GroupEditorPageState extends State<_GroupEditorPage> {
  late final _ctls = [
    for (final r in widget.rules) TextEditingController(text: r.content),
  ];
  late final _whens = [for (final r in widget.rules) r.when];
  late final _enabled = [for (final r in widget.rules) r.enabled];
  var _dirty = false;

  @override
  void dispose() {
    for (final c in _ctls) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final out = <PresetRule>[];
    for (final (i, r) in widget.rules.indexed) {
      final content = _tidy(_ctls[i].text);
      if (content.trim().isEmpty) {
        hintSnack(
          context,
          context.l10n.ruleSectionEmpty,
          icon: Icons.error_outline,
        );
        return;
      }
      out.add(
        r.copyWith(content: content, when: _whens[i], enabled: _enabled[i]),
      );
    }
    Navigator.pop(context, out);
  }

  void _touch(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: context.l10n.save,
              onPressed: _save,
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            4,
            14,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            for (var i = 0; i < widget.rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _block(context, i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context, int i) {
    final scheme = context.scheme;
    final on = _enabled[i];
    final btnSize = MediaQuery.sizeOf(context).width < 350 ? 32.0 : 36.0;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ruleSectionLabel(widget.rules[i].name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on ? null : scheme.outline,
                      ),
                    ),
                  ),
                  _WhenButton(
                    when: _whens[i],
                    onTap: () async {
                      final v = await _pickWhen(context, _whens[i]);
                      if (v != null) _touch(() => _whens[i] = v);
                    },
                  ),
                  RoundIconBtn(
                    Icons.power_settings_new,
                    size: btnSize,
                    color: on ? scheme.primary : scheme.outline,
                    tooltip: on
                        ? context.l10n.disableKeepConfig
                        : context.l10n.enable,
                    onTap: () {
                      Haptics.selection();
                      _touch(() => _enabled[i] = !on);
                    },
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: Motion.fast,
              opacity: on ? 1 : .45,
              child: TextField(
                controller: _ctls[i],
                maxLines: null,
                minLines: 3,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                style: mono(context, size: 13, weight: FontWeight.w400),
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全文编辑:摊开的是导出的那份文本。保存时按导入同一套规矩读回来,读不通就
/// 原地报错、不关页面;没保存就返回要确认一下,几万字的规则丢了找不回来。
class _RulesEditorPage extends StatefulWidget {
  const _RulesEditorPage({required this.title, required this.text});

  final String title;
  final String text;

  @override
  State<_RulesEditorPage> createState() => _RulesEditorPageState();
}

class _RulesEditorPageState extends State<_RulesEditorPage> {
  late final _ctl = TextEditingController(text: widget.text);
  var _dirty = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final RulesFile file;
    try {
      file = decodeRulesFile(_ctl.text);
    } on FormatException catch (e) {
      hintSnack(context, e.message, icon: Icons.error_outline);
      return;
    }
    // 导入时这两样能在弹层里补,这里没有弹层,文本里就得写全
    final missing = file.name.isEmpty
        ? context.l10n.missingPresetName
        : file.models.isEmpty
        ? context.l10n.missingModels
        : null;
    if (missing != null) {
      hintSnack(context, missing, icon: Icons.error_outline);
      return;
    }
    Navigator.pop(context, file);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: context.l10n.save,
              onPressed: _save,
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        // 文本直接铺在页面上,不再套一层底色框:整页就是编辑区
        body: SafeArea(
          top: false,
          child: TextField(
            controller: _ctl,
            expands: true,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            autocorrect: false,
            enableSuggestions: false,
            style: mono(context, size: 13, weight: FontWeight.w400),
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            ),
          ),
        ),
      ),
    );
  }
}

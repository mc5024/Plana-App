/// 预设页:上面是这份预设的名称、作者、支持的模型和启用的模型,下面是段落。
///
/// 段落一段一张卡:点卡进编辑页改内容,点名字改名,⏻ 停用、🗑 删除、长按拖动排序。
///
/// 默认规则的原件在包里,改不了:名称、作者、支持的模型只读,段落第一次保存时另存为
/// 「原名 (副本)」,这个模型原先用默认规则的就改用这份副本,之后在这页接着改的都是它。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../../l10n/l10n.dart';
import '../generate/widgets/common.dart'
    show RoundIconBtn, confirmDialog, hintSnack;
import '../profile/widgets/settings_ui.dart';
import 'presets/default_rules.dart';
import 'presets/preset_rule.dart';
import 'presets/rules_file.dart';
import 'presets/rules_library.dart';

class RulesPresetDetailPage extends ConsumerStatefulWidget {
  /// [family] 给了就是那个模型的默认规则,否则是 [presetId] 那份预设。
  const RulesPresetDetailPage({super.key, this.family, this.presetId})
    : assert((family == null) != (presetId == null));

  final RulesFamily? family;
  final String? presetId;

  @override
  ConsumerState<RulesPresetDetailPage> createState() =>
      _RulesPresetDetailPageState();
}

class _RulesPresetDetailPageState extends ConsumerState<RulesPresetDetailPage> {
  /// 在改的那份预设;默认规则还没另存时是 null。
  late String? _id = widget.presetId;

  /// 默认规则正在另存,这期间的操作不接,免得存出两份。
  var _copying = false;

  RulesPreset? _preset(RulesLibrary? lib) =>
      lib?.presets.where((p) => p.id == _id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(rulesLibraryProvider).value;
    final p = _id == null ? null : _preset(lib);
    final d = _id == null
        ? ref.watch(defaultRulesProvider(widget.family!)).value
        : null;
    final rules = p?.rules ?? d?.rules;
    final title = p?.name ?? d?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: context.l10n.fullTextEdit,
            onPressed: rules == null ? null : () => _editFullText(rules),
            icon: const Icon(Icons.notes),
          ),
        ],
      ),
      body: lib == null || rules == null
          ? const Center(child: CircularProgressIndicator())
          : _body(lib, p, d, rules),
    );
  }

  Widget _body(
    RulesLibrary lib,
    RulesPreset? p,
    DefaultRules? d,
    List<PresetRule> rules,
  ) {
    final l = context.l10n;
    final models = p?.models ?? {widget.family!};
    final selfId = p?.id ?? defaultPresetOf(widget.family!).id;
    final enabled = [
      for (final m in RulesFamily.values)
        if (models.contains(m) && lib.activeFor(m).id == selfId)
          rulesFamilyLabel(m),
    ];
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              icon: Icons.drive_file_rename_outline,
              title: l.presetName,
              value: p?.name ?? d?.displayName ?? '',
              onTap: p == null ? null : () => _editName(p),
            ),
            SettingsRow(
              icon: Icons.person_outline,
              title: l.author,
              value: p?.author ?? d?.author ?? '',
              onTap: p == null ? null : () => _editAuthor(p),
            ),
            SettingsRow(
              icon: Icons.memory_outlined,
              title: l.supportedModels,
              value: [
                for (final m in RulesFamily.values)
                  if (models.contains(m)) rulesFamilyLabel(m),
              ].join(l.listSep),
              onTap: p == null ? null : () => _editModels(p),
            ),
            SettingsRow(
              icon: Icons.check_circle_outline,
              title: l.enabledModels,
              value: enabled.isEmpty ? l.notEnabled : enabled.join(l.listSep),
              onTap: () => _editEnabled(lib, models, selfId),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsLabel(l.ruleSectionsLabel),
        // 首尾各一颗:顶上这颗加在最前;一段都没有时只留底下那颗
        if (rules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _addButton(() => _add(rules, atStart: true)),
          ),
      ],
    );
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      header: header,
      footer: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: _addButton(() => _add(rules)),
      ),
      itemCount: rules.length,
      proxyDecorator: (child, _, _) => Material(
        color: Colors.transparent,
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      onReorderItem: (from, to) {
        final next = [...rules];
        next.insert(to, next.removeAt(from));
        _commit(next);
      },
      itemBuilder: (context, i) => Padding(
        key: ObjectKey(rules[i]),
        padding: const EdgeInsets.only(bottom: 10),
        child: _RuleCardView(
          rule: rules[i],
          onEdit: () => _edit(rules, i),
          onRename: () => _rename(rules, i),
          onToggle: () => _commit(
            [...rules]..[i] = rules[i].copyWith(enabled: !rules[i].enabled),
          ),
          onDelete: () => _delete(rules, i),
        ),
      ),
    );
  }

  Future<void> _replace(
    RulesPreset p, {
    String? name,
    String? author,
    Set<RulesFamily>? models,
  }) => ref
      .read(rulesLibraryProvider.notifier)
      .replace(
        p.id,
        name: name ?? p.name,
        author: author ?? p.author,
        models: models ?? p.models,
        rules: p.rules,
      );

  Future<void> _editName(RulesPreset p) async {
    final v = await _askText(context.l10n.presetName, p.name);
    if (v == null || v.isEmpty || v == p.name) return;
    await _replace(p, name: v);
  }

  Future<void> _editAuthor(RulesPreset p) async {
    final v = await _askText(context.l10n.author, p.author);
    if (v == null || v == p.author) return;
    await _replace(p, author: v);
  }

  /// 支持的模型:多选,至少留一个。去掉的模型原先在用这份的,回到默认规则。
  Future<void> _editModels(RulesPreset p) async {
    final picked = await _pickModels(
      title: context.l10n.supportedModels,
      options: RulesFamily.values,
      initial: p.models,
      allowEmpty: false,
    );
    if (picked == null || _sameSet(picked, p.models)) return;
    await _replace(p, models: picked);
  }

  /// 启用的模型:在支持的模型里多选,勾上的改用这份,取消的回到默认规则。
  /// 默认规则正在用时勾不掉(退无可退),要换去别的预设里勾。
  Future<void> _editEnabled(
    RulesLibrary lib,
    Set<RulesFamily> models,
    String selfId,
  ) async {
    final on = {
      for (final m in models)
        if (lib.activeFor(m).id == selfId) m,
    };
    final isDefault = selfId.startsWith('default');
    final picked = await _pickModels(
      title: context.l10n.enabledModels,
      options: [
        for (final m in RulesFamily.values)
          if (models.contains(m)) m,
      ],
      initial: on,
      locked: isDefault ? on : const {},
    );
    if (picked == null || _sameSet(picked, on)) return;
    final n = ref.read(rulesLibraryProvider.notifier);
    for (final m in models) {
      if (picked.contains(m) && !on.contains(m)) {
        await n.use(m, selfId);
      } else if (!picked.contains(m) && on.contains(m)) {
        await n.use(m, defaultPresetOf(m).id);
      }
    }
  }

  static bool _sameSet(Set<RulesFamily> a, Set<RulesFamily> b) =>
      a.length == b.length && a.containsAll(b);

  /// 模型多选弹窗,取消返回 null。[locked] 里的勾着且改不了。
  Future<Set<RulesFamily>?> _pickModels({
    required String title,
    required List<RulesFamily> options,
    required Set<RulesFamily> initial,
    bool allowEmpty = true,
    Set<RulesFamily> locked = const {},
  }) => showDialog<Set<RulesFamily>>(
    context: context,
    builder: (context) {
      var sel = {...initial};
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in options)
                CheckboxListTile(
                  value: sel.contains(m),
                  title: Text(rulesFamilyLabel(m)),
                  onChanged: locked.contains(m)
                      ? null
                      : (v) => setState(
                          () => sel = v == true
                              ? {...sel, m}
                              : ({...sel}..remove(m)),
                        ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: sel.isEmpty && !allowEmpty
                  ? null
                  : () => Navigator.pop(context, sel),
              child: Text(context.l10n.confirm),
            ),
          ],
        ),
      );
    },
  );

  /// 存段落。默认规则第一次存是另存为一份新预设。
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
      // 副本叫「Nyako v5 (副本)」;全文编辑里改了名字的用改过的
      final copyName = name == null || name == d.displayName
          ? (ref.read(rulesLibraryProvider).value ?? const RulesLibrary())
                .copyNameOf(d.displayName)
          : name;
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

  Future<void> _edit(List<PresetRule> rules, int i) async {
    final edited = await Navigator.push<PresetRule>(
      context,
      MaterialPageRoute(builder: (_) => _SectionEditorPage(rule: rules[i])),
    );
    if (edited == null) return;
    await _commit([...rules]..[i] = edited);
  }

  Widget _addButton(VoidCallback onPressed) => FilledButton.tonalIcon(
    onPressed: onPressed,
    icon: const Icon(Icons.add, size: 18),
    label: Text(context.l10n.addRuleSection),
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
  );

  /// 新加一段:先起名再写内容;[atStart] = 加在最前,否则接在最后。
  Future<void> _add(List<PresetRule> rules, {bool atStart = false}) async {
    final name = await _askSectionName('');
    if (name == null || !mounted) return;
    final edited = await Navigator.push<PresetRule>(
      context,
      MaterialPageRoute(
        builder: (_) => _SectionEditorPage(
          rule: PresetRule(name: name, content: ''),
        ),
      ),
    );
    if (edited == null) return;
    await _commit(atStart ? [edited, ...rules] : [...rules, edited]);
  }

  /// 点名字改名。框里是显示名,没改就不动(内置段名不会被换成中文)。
  Future<void> _rename(List<PresetRule> rules, int i) async {
    final shown = ruleSectionLabel(rules[i].name);
    final name = await _askSectionName(shown);
    if (name == null || name == shown) return;
    await _commit([...rules]..[i] = rules[i].copyWith(name: name));
  }

  /// 问一行字,取消返回 null,其余去掉首尾空白返回。
  Future<String?> _askText(
    String title,
    String initial, {
    String? label,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(isDense: true, labelText: label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return v?.trim();
  }

  /// 问段名,取消或留空返回 null。
  Future<String?> _askSectionName(String initial) async {
    final l = context.l10n;
    final v = await _askText(
      initial.isEmpty ? l.addRuleSection : l.rename,
      initial,
      label: l.ruleSectionName,
    );
    if (v == null || v.isEmpty) return null;
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

  Future<void> _delete(List<PresetRule> rules, int i) async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.deleteRuleSectionQ,
      message: context.l10n.deleteRuleSectionBody(
        ruleSectionLabel(rules[i].name),
      ),
      confirmLabel: context.l10n.delete,
    );
    if (!ok) return;
    await _commit([...rules]..removeAt(i));
  }

  /// 全文编辑:摊开的就是导出的那份文本,电脑上改好的能整段贴进来。
  Future<void> _editFullText(List<PresetRule> rules) async {
    final p = _preset(ref.read(rulesLibraryProvider).value);
    final RulesFamily? f = widget.family;
    final DefaultRules? d = p == null && f != null
        ? await bundledDefaultRules(f)
        : null;
    if (!mounted) return;
    final name = p?.name ?? d?.displayName ?? '';
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
    required this.rule,
    required this.onEdit,
    required this.onRename,
    required this.onToggle,
    required this.onDelete,
  });

  final PresetRule rule;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final on = rule.enabled;
    final meta = [
      ?whenTag(rule.when),
      context.l10n.charsN(rule.content.length),
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
                            ruleSectionLabel(rule.name),
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
                  color: scheme.error,
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

/// 条件段卡头的小标签(如「漫画模式」),样式同预设卡标题后的标签。
class _CondTag extends StatelessWidget {
  const _CondTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: context.texts.labelSmall!.copyWith(
          color: scheme.onSurfaceVariant,
        ),
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

/// 段落编辑页:一张卡,卡头是段名、条件段的小标签和 ⏻,下面就是这段的内容。
/// 顶栏保存,没保存就返回要确认一下。
class _SectionEditorPage extends StatefulWidget {
  const _SectionEditorPage({required this.rule});

  final PresetRule rule;

  @override
  State<_SectionEditorPage> createState() => _SectionEditorPageState();
}

class _SectionEditorPageState extends State<_SectionEditorPage> {
  late final _ctl = TextEditingController(text: widget.rule.content);
  late var _enabled = widget.rule.enabled;
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
    Navigator.pop(
      context,
      widget.rule.copyWith(content: content, enabled: _enabled),
    );
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
          title: Text(ruleSectionLabel(widget.rule.name)),
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
          children: [_block(context)],
        ),
      ),
    );
  }

  Widget _block(BuildContext context) {
    final scheme = context.scheme;
    final rule = widget.rule;
    final on = _enabled;
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
                  Flexible(
                    child: Text(
                      ruleSectionLabel(rule.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on ? null : scheme.outline,
                      ),
                    ),
                  ),
                  // 触发条件只显示,要改去全文编辑
                  if (whenTag(rule.when) case final tag?) _CondTag(tag),
                  const Spacer(),
                  RoundIconBtn(
                    Icons.power_settings_new,
                    size: btnSize,
                    color: on ? scheme.primary : scheme.outline,
                    tooltip: on
                        ? context.l10n.disableKeepConfig
                        : context.l10n.enable,
                    onTap: () {
                      Haptics.selection();
                      _touch(() => _enabled = !on);
                    },
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: Motion.fast,
              opacity: on ? 1 : .45,
              child: TextField(
                controller: _ctl,
                autofocus: rule.content.isEmpty,
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

/// 规则预设页:每个模型在用哪一份、导入、导出、编辑、删除。
///
/// 一张卡一份预设。默认规则按模型分两张(v4.5 版、v5 版),名称、作者、版本读服务端
/// 预设顶层的 meta。**点卡片就用这份**,正在用的卡右上角挂一个「使用中」角标。
/// 每个模型恰好有一张卡在用,默认规则兜底。
///
/// 编辑是全文编辑:摊开的就是导出的那份文本,不做逐段的表单 —— 规则文件的写法与
/// 服务端预设一致,整份摊开最直接,电脑上改好的也能整段贴进来。默认规则的原件在
/// 服务端,改完另存为一份新预设。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_config.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;
import 'preset_rules.dart';

class RulesPresetPage extends ConsumerWidget {
  const RulesPresetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(rulesLibraryProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则预设'),
        actions: [
          IconButton(
            tooltip: '导入',
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      body: lib == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              children: [
                for (final p in lib.all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _card(context, ref, lib, p),
                  ),
              ],
            ),
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    RulesLibrary lib,
    RulesPreset p,
  ) {
    final inUse = {
      for (final f in RulesFamily.values)
        if (lib.activeFor(f).id == p.id) f,
    };
    void onUse(RulesFamily f) {
      Haptics.selection();
      ref.read(rulesLibraryProvider.notifier).use(f, p.id);
    }

    if (p.isDefault) {
      // 默认规则只支持一个模型;名称、作者、版本读服务端预设,没取到时用占位值
      final f = p.models.single;
      final info = ref.watch(defaultRulesProvider(f)).value;
      return _PresetCard(
        title: info?.name ?? p.name,
        subtitle: [
          info?.author ?? p.author,
          '${info?.version ?? defaultRulesVersionOf(f)} 版',
        ].where((s) => s.isNotEmpty).join(' · '),
        isDefault: true,
        models: p.models,
        inUse: inUse,
        onUse: onUse,
        onEdit: () => _editDefault(context, ref, f),
        onExport: () => _exportDefault(context, ref, f),
      );
    }
    return _PresetCard(
      title: p.name,
      subtitle: [
        if (p.author.isNotEmpty) p.author,
        '${p.rules.length} 段',
      ].join(' · '),
      isDefault: false,
      models: p.models,
      inUse: inUse,
      onUse: onUse,
      onEdit: () => _edit(context, ref, p),
      onExport: () => _save(
        context,
        name: p.name,
        author: p.author,
        models: p.models,
        rules: p.rules,
        fileName: 'plana-rules-${_safe(p.name)}.yaml',
      ),
      onDelete: () => _delete(context, ref, p),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final picked = res?.files.firstOrNull;
    final bytes = picked?.bytes;
    if (picked == null || bytes == null || !context.mounted) return;

    final RulesFile file;
    try {
      file = decodeRulesFile(utf8.decode(bytes), fileName: picked.name);
    } on FormatException catch (e) {
      hintSnack(context, e.message, icon: Icons.error_outline);
      return;
    } catch (_) {
      hintSnack(context, '读不了这个文件,请确认是 UTF-8 文本', icon: Icons.error_outline);
      return;
    }

    // 名字、作者、模型让用户过一眼:服务端预设文件里压根没写这几样,
    // 文件里写了的也可能想改个自己认得出的名字
    final meta = await showModalBottomSheet<_ImportMeta>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ImportSheet(file: file),
    );
    if (meta == null || !context.mounted) return;
    await ref
        .read(rulesLibraryProvider.notifier)
        .add(
          name: meta.name,
          author: meta.author,
          models: meta.models,
          rules: file.rules,
        );
    if (context.mounted) {
      hintSnack(context, '已导入「${meta.name}」', icon: Icons.check_circle_outline);
    }
  }

  Future<DefaultRules> _fetchDefault(
    WidgetRef ref,
    RulesFamily f, {
    bool fresh = false,
  }) async => fetchDefaultRules(
    f,
    backendBase: ref.read(backendBaseProvider).value ?? '',
    sessionId: (await ref.read(botSessionProvider.future))?.sessionId ?? '',
    fresh: fresh,
  );

  /// 默认规则导出的是服务端**最新**那份,名字带上版本(「Nyako v5」)——
  /// 两个版本同名,导进来之后分不出哪张是哪张。
  Future<void> _exportDefault(
    BuildContext context,
    WidgetRef ref,
    RulesFamily f,
  ) async {
    try {
      final d = await _fetchDefault(ref, f, fresh: true);
      if (!context.mounted) return;
      await _save(
        context,
        name: '${d.name} ${d.version}'.trim(),
        author: d.author,
        models: {f},
        rules: d.rules,
        fileName: 'plana-rules-${_safe('${d.name}-${d.version}')}.yaml',
      );
    } catch (e) {
      if (context.mounted) {
        hintSnack(context, '导出失败:$e', icon: Icons.error_outline);
      }
    }
  }

  Future<RulesFile?> _openEditor(
    BuildContext context, {
    required String title,
    required String text,
  }) => Navigator.push<RulesFile>(
    context,
    MaterialPageRoute(
      builder: (_) => _RulesEditorPage(title: title, text: text),
    ),
  );

  /// 全文编辑导入的预设,存回原处。
  Future<void> _edit(BuildContext context, WidgetRef ref, RulesPreset p) async {
    final file = await _openEditor(
      context,
      title: p.name,
      text: encodeRulesFile(
        name: p.name,
        author: p.author,
        models: p.models,
        rules: p.rules,
      ),
    );
    if (file == null) return;
    await ref
        .read(rulesLibraryProvider.notifier)
        .replace(
          p.id,
          name: file.name,
          author: file.author,
          models: file.models,
          rules: file.rules,
        );
    if (context.mounted) {
      hintSnack(context, '已保存「${file.name}」', icon: Icons.check_circle_outline);
    }
  }

  /// 默认规则的原件跟着服务端走,改不了:改完另存为一份新预设。这个模型原先用的是
  /// 默认规则的,改用新存的这份 —— 点「编辑」是想改自己在用的规则,存完还挂在原件上
  /// 等于白改。
  Future<void> _editDefault(
    BuildContext context,
    WidgetRef ref,
    RulesFamily f,
  ) async {
    final DefaultRules d;
    try {
      // 卡片进页面时刚取过,走缓存就行,不让人干等一趟网络
      d = await _fetchDefault(ref, f);
    } catch (e) {
      if (context.mounted) {
        hintSnack(context, '读取默认规则失败:$e', icon: Icons.error_outline);
      }
      return;
    }
    if (!context.mounted) return;
    final name = '${d.name} ${d.version}'.trim();
    final file = await _openEditor(
      context,
      title: name,
      text: encodeRulesFile(
        name: name,
        author: d.author,
        models: {f},
        rules: d.rules,
      ),
    );
    if (file == null) return;
    final wasDefault =
        ref.read(rulesLibraryProvider).value?.activeFor(f).isDefault ?? false;
    final n = ref.read(rulesLibraryProvider.notifier);
    final id = await n.add(
      name: file.name,
      author: file.author,
      models: file.models,
      rules: file.rules,
    );
    if (wasDefault && file.models.contains(f)) await n.use(f, id);
    if (context.mounted) {
      hintSnack(
        context,
        '已另存为「${file.name}」',
        icon: Icons.check_circle_outline,
      );
    }
  }

  Future<void> _save(
    BuildContext context, {
    required String name,
    required String author,
    required Set<RulesFamily> models,
    required List<PresetRule> rules,
    required String fileName,
  }) async {
    try {
      final path = await FilePicker.platform.saveFile(
        fileName: fileName,
        bytes: utf8.encode(
          encodeRulesFile(
            name: name,
            author: author,
            models: models,
            rules: rules,
          ),
        ),
      );
      if (path != null && context.mounted) {
        hintSnack(context, '已导出「$name」', icon: Icons.check_circle_outline);
      }
    } catch (e) {
      if (context.mounted) {
        hintSnack(context, '导出失败:$e', icon: Icons.error_outline);
      }
    }
  }

  /// 文件名里别带路径分隔符和系统不认的字符。
  String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RulesPreset p,
  ) async {
    final ok = await confirmDialog(
      context,
      title: '删除预设?',
      message: '「${p.name}」将被删除,正在使用它的模型改用默认规则。',
      confirmLabel: '删除',
    );
    if (!ok) return;
    await ref.read(rulesLibraryProvider.notifier).remove(p.id);
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.title,
    required this.subtitle,
    required this.isDefault,
    required this.models,
    required this.inUse,
    required this.onUse,
    required this.onEdit,
    required this.onExport,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final bool isDefault;

  /// 这份支持的模型。
  final Set<RulesFamily> models;

  /// 正在用这份的模型。
  final Set<RulesFamily> inUse;
  final ValueChanged<RulesFamily> onUse;
  final VoidCallback onEdit;
  final VoidCallback onExport;

  /// 默认规则删不了,传 null。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final allInUse = models.every(inUse.contains);
    // 支持两个模型、只在其中一个上用着的,角标说清是哪一个;其余只说「使用中」
    final badge = inUse.isEmpty
        ? null
        : allInUse
        ? '使用中'
        : '${inUse.map(rulesFamilyLabel).join('、')} 使用中';
    final notInUse = [
      for (final f in RulesFamily.values)
        if (models.contains(f) && !inUse.contains(f)) f,
    ];
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: inUse.isNotEmpty
              ? BorderSide(color: scheme.primary, width: 1.4)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // 点卡片 = 支持的模型都改用这份。两个模型想分开用的,点完再点另一个模型
          // 要用的那张卡(比如它的默认规则),那个模型就换回去了
          onTap: notInUse.isEmpty
              ? null
              : () {
                  for (final f in notInUse) {
                    onUse(f);
                  }
                },
          child: Stack(
            children: [
              Padding(
                // 上下对称,标题那两行在卡片里垂直居中。角标是叠在上面的
                // (Positioned),不占高度;上边距留够了,它压不到标题和右边的按钮
                padding: const EdgeInsets.fromLTRB(16, 16, 6, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.bodyLarge!.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (isDefault) const _Tag('默认'),
                              for (final f in RulesFamily.values)
                                if (models.contains(f))
                                  _Tag(rulesFamilyLabel(f)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: context.texts.labelSmall!.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 与提示词预设页同一排按钮:编辑、导出直接摆出来,不收进菜单
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '编辑',
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      tooltip: '导出',
                      visualDensity: VisualDensity.compact,
                      onPressed: onExport,
                      icon: Icon(
                        Icons.ios_share,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: '删除',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 19,
                          color: scheme.error.withValues(alpha: .85),
                        ),
                      ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 1, 11, 2),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                    child: Text(
                      badge,
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.onPrimary,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题后面那几枚小标签:默认、支持的模型。
class _Tag extends StatelessWidget {
  const _Tag(this.text);

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

typedef _ImportMeta = ({String name, String author, Set<RulesFamily> models});

/// 导入前过一眼:名字、作者、支持的模型。文件里写了就预先填上。
class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.file});

  final RulesFile file;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  late final _name = TextEditingController(text: widget.file.name);
  late final _author = TextEditingController(text: widget.file.author);
  late final Set<RulesFamily> _models = {...widget.file.models};

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    super.dispose();
  }

  bool get _ok => _name.text.trim().isNotEmpty && _models.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final conditional = widget.file.rules.any((r) => r.when.isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '导入规则预设',
            style: context.texts.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              '共 ${widget.file.rules.length} 段',
              if (conditional) '含条件段',
            ].join(' · '),
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '预设名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _author,
            decoration: const InputDecoration(
              labelText: '作者',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '支持的模型',
            style: context.texts.labelLarge!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final f in RulesFamily.values)
                FilterChip(
                  label: Text(rulesFamilyLabel(f)),
                  selected: _models.contains(f),
                  onSelected: (v) =>
                      setState(() => v ? _models.add(f) : _models.remove(f)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _ok
                ? () => Navigator.pop(context, (
                    name: _name.text.trim(),
                    author: _author.text.trim(),
                    models: {..._models},
                  ))
                : null,
            child: const Text('导入'),
          ),
        ],
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
        ? '缺少预设名称(name)'
        : file.models.isEmpty
        ? '缺少支持的模型(models 写 nai45、nai5)'
        : null;
    if (missing != null) {
      hintSnack(context, missing, icon: Icons.error_outline);
      return;
    }
    Navigator.pop(context, file);
  }

  Future<void> _confirmLeave() async {
    final ok = await confirmDialog(
      context,
      title: '放弃修改?',
      message: '还没保存的改动会丢掉。',
      confirmLabel: '放弃',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: '保存',
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

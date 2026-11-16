/// 规则预设页:一张卡一份预设。
///
/// 默认规则按模型分两张(v4.5 版、v5 版),名称、作者、版本读内置那份的 meta。
/// 点卡进预设页([RulesPresetDetailPage]);卡上直接摆副本、导出、删除。
/// 卡底下是它支持的模型,点哪个就是那个模型改用这份;每个模型恰好有一份在用,默认规则兜底。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;
import 'presets/default_rules.dart';
import 'presets/preset_rule.dart';
import 'presets/rules_file.dart';
import 'presets/rules_library.dart';
import 'rules_preset_detail_page.dart';
import '../../l10n/l10n.dart';

class RulesPresetPage extends ConsumerWidget {
  const RulesPresetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(rulesLibraryProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.rulePresets),
        actions: [
          IconButton(
            tooltip: context.l10n.importLabel,
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      body: lib == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
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
    // 点没在用的模型 = 那个模型改用这份;点在用的 = 退回默认规则(默认规则本身退无可退)
    void onUse(RulesFamily f) {
      final n = ref.read(rulesLibraryProvider.notifier);
      if (!inUse.contains(f)) {
        Haptics.selection();
        n.use(f, p.id);
      } else if (!p.isDefault) {
        Haptics.selection();
        n.use(f, defaultPresetOf(f).id);
      }
    }

    void open() => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => p.isDefault
            ? RulesPresetDetailPage(family: p.models.single)
            : RulesPresetDetailPage(presetId: p.id),
      ),
    );

    if (p.isDefault) {
      // 默认规则只支持一个模型;名称、作者、版本读内置那份,没读到时用占位值
      final f = p.models.single;
      final info = ref.watch(defaultRulesProvider(f)).value;
      return _PresetCard(
        title: info?.name ?? p.name,
        subtitle: [
          info?.author ?? p.author,
          l10nNow.versionN(info?.version ?? defaultRulesVersionOf(f)),
        ].where((s) => s.isNotEmpty).join(' · '),
        isDefault: true,
        models: p.models,
        inUse: inUse,
        onUse: onUse,
        onOpen: open,
        onCopy: () => _duplicate(context, ref, p),
        onExport: () => _exportDefault(context, ref, f),
      );
    }
    return _PresetCard(
      title: p.name,
      subtitle: [
        if (p.author.isNotEmpty) p.author,
        l10nNow.sectionsN(p.rules.length),
      ].join(' · '),
      isDefault: false,
      models: p.models,
      inUse: inUse,
      onUse: onUse,
      onOpen: open,
      onCopy: () => _duplicate(context, ref, p),
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

  /// 副本:段落、作者、支持的模型照抄,名字后面加「(副本)」,不自动启用。
  /// 默认规则的副本名字带版本(「Nyako v5 (副本)」)。
  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    RulesPreset p,
  ) async {
    final String base;
    final String author;
    final Set<RulesFamily> models;
    final List<PresetRule> rules;
    if (p.isDefault) {
      final f = p.models.single;
      final d = await bundledDefaultRules(f);
      base = '${d.name} ${d.version}'.trim();
      author = d.author;
      models = {f};
      rules = d.rules;
    } else {
      base = p.name;
      author = p.author;
      models = p.models;
      rules = p.rules;
    }
    final taken = {
      for (final x in ref.read(rulesLibraryProvider).value?.presets ?? [])
        x.name,
    };
    final first = '$base ${l10nNow.copySuffix}';
    var name = first;
    for (var n = 2; taken.contains(name); n++) {
      name = '$first $n';
    }
    await ref
        .read(rulesLibraryProvider.notifier)
        .add(name: name, author: author, models: models, rules: rules);
    if (context.mounted) {
      hintSnack(
        context,
        context.l10n.savedAsNamed(name),
        icon: Icons.check_circle_outline,
      );
    }
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
      hintSnack(context, context.l10n.notUtf8, icon: Icons.error_outline);
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
      hintSnack(
        context,
        context.l10n.importedNamed(meta.name),
        icon: Icons.check_circle_outline,
      );
    }
  }

  /// 默认规则导出时名字带上版本(「Nyako v5」)——
  /// 两个版本同名,导进来之后分不出哪张是哪张。
  Future<void> _exportDefault(
    BuildContext context,
    WidgetRef ref,
    RulesFamily f,
  ) async {
    try {
      final d = await bundledDefaultRules(f);
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
        hintSnack(
          context,
          context.l10n.exportFailed('$e'),
          icon: Icons.error_outline,
        );
      }
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
        hintSnack(
          context,
          context.l10n.exportedNamed(name),
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (context.mounted) {
        hintSnack(
          context,
          context.l10n.exportFailed('$e'),
          icon: Icons.error_outline,
        );
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
      title: context.l10n.deletePresetQ,
      message: context.l10n.deleteRulePresetBody(p.name),
      confirmLabel: context.l10n.delete,
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
    required this.onOpen,
    required this.onCopy,
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

  /// 点了卡底下的某个模型。
  final ValueChanged<RulesFamily> onUse;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onExport;

  /// 默认规则删不了,传 null。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    Widget btn(IconData icon, String tip, VoidCallback onTap, Color color) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 19, color: color),
        );
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                              if (isDefault)
                                _Tag(context.l10n.presetGroupDefault),
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
                    // 副本、导出、删除直接摆出来,不收进菜单
                    const SizedBox(width: 4),
                    btn(
                      Icons.copy_all_outlined,
                      context.l10n.duplicatePreset,
                      onCopy,
                      scheme.onSurfaceVariant,
                    ),
                    btn(
                      Icons.ios_share,
                      context.l10n.export,
                      onExport,
                      scheme.onSurfaceVariant,
                    ),
                    if (onDelete != null)
                      btn(
                        Icons.delete_outline,
                        context.l10n.delete,
                        onDelete!,
                        scheme.error.withValues(alpha: .85),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final f in RulesFamily.values)
                      if (models.contains(f))
                        _ModelChip(
                          label: rulesFamilyLabel(f),
                          on: inUse.contains(f),
                          onTap: () => onUse(f),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡底下的一个模型:在用时实底 + 勾 +「在用」,没在用是描边,点了改用这份。
class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final fg = on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: on ? scheme.primaryContainer : Colors.transparent,
      shape: StadiumBorder(
        side: on ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(on ? 8 : 12, 5, 12, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[
                Icon(Icons.check, size: 15, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                on ? context.l10n.inUseOn(label) : label,
                style: context.texts.labelMedium!.copyWith(
                  color: fg,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
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
            context.l10n.importRulePreset,
            style: context.texts.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              context.l10n.totalSectionsN(widget.file.rules.length),
              if (conditional) context.l10n.hasConditional,
            ].join(' · '),
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.l10n.presetName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _author,
            decoration: InputDecoration(
              labelText: context.l10n.author,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.supportedModels,
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
            child: Text(context.l10n.importLabel),
          ),
        ],
      ),
    );
  }
}

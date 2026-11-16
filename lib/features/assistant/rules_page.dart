/// 规则预设页:最上面「在用」写着每个模型用的是哪一份(点开换),下面是全部预设。
///
/// 一张卡一份预设。默认规则按模型分两张(v4.5 版、v5 版),名称、作者、版本读内置
/// 那份的 meta。点卡进预设页([RulesPresetDetailPage]);卡上直接摆副本、导出、删除。
/// 每个模型恰好有一份在用,默认规则兜底。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/setting_row.dart' show SettingSheet;
import '../../core/util/haptics.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;
import '../profile/widgets/settings_ui.dart';
import 'presets/default_rules.dart';
import 'presets/preset_rule.dart';
import 'presets/rules_file.dart';
import 'presets/rules_library.dart';
import 'rules_preset_detail_page.dart';
import '../../l10n/l10n.dart';

/// 预设的显示名:默认规则带上版本(「Nyako v5」),两份默认规则同名。
String presetDisplayName(WidgetRef ref, RulesPreset p) {
  if (!p.isDefault) return p.name;
  final f = p.models.single;
  final info = ref.watch(defaultRulesProvider(f)).value;
  return '${info?.name ?? p.name} ${info?.version ?? defaultRulesVersionOf(f)}'
      .trim();
}

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
                SettingsLabel(context.l10n.rulesInUse),
                SettingsCard(
                  children: [
                    for (final f in RulesFamily.values)
                      SettingsRow(
                        icon: Icons.rule_outlined,
                        title: rulesFamilyLabel(f),
                        value: presetDisplayName(ref, lib.activeFor(f)),
                        onTap: () => _pickInUse(context, f),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsLabel(context.l10n.rulesAllPresets),
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

  Future<void> _pickInUse(BuildContext context, RulesFamily f) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (_) => _InUseSheet(family: f),
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

/// 选某个模型用哪份规则:列出支持它的预设,在用的那份打勾,点一份就换过去。
class _InUseSheet extends ConsumerWidget {
  const _InUseSheet({required this.family});

  final RulesFamily family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(rulesLibraryProvider).value ?? const RulesLibrary();
    final current = lib.activeFor(family).id;
    final scheme = context.scheme;
    return SettingSheet(
      title: rulesFamilyLabel(family),
      maxHeight: MediaQuery.sizeOf(context).height * .82,
      children: [
        for (final p in lib.all)
          if (p.models.contains(family))
            InkWell(
              onTap: () {
                Haptics.selection();
                ref.read(rulesLibraryProvider.notifier).use(family, p.id);
                Navigator.of(context).maybePop();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        presetDisplayName(ref, p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: p.id == current ? scheme.primary : null,
                        ),
                      ),
                    ),
                    if (p.id == current)
                      Icon(Icons.check, size: 20, color: scheme.primary),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.title,
    required this.subtitle,
    required this.isDefault,
    required this.models,
    required this.inUse,
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
  final VoidCallback onOpen;
  final VoidCallback onCopy;
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
        ? l10nNow.inUse
        : l10nNow.inUseBy(inUse.map(rulesFamilyLabel).join(l10nNow.listSep));
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: inUse.isNotEmpty
              ? BorderSide(color: scheme.primary, width: 1.4)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
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
                              if (isDefault)
                                _Tag(context.l10n.presetGroupDefault),
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

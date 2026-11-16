/// 我的接口:已添加的一张卡一个,最后一张是「添加接口」。点卡就地展开表单,同一时间只展开
/// 一张;长按收着的卡拖动排序(选择模型里按这个顺序列),删除在卡头。
///
/// 表单各栏都摆出来,一行一项、标签在左。点现成的服务替用户填好格式和地址,填完照样能改;
/// 地址认得出是哪家就亮哪家,认不出亮「自定义」。一个接口下可以存多个模型,选择模型里各占
/// 一行。名称、接口路径、请求头收在「高级设置」里,默认折起。
///
/// 「模型列表」免得手抄模型 id(抄错的表现是 404,中转上还常被包成别的错);拉不到也不拦着,
/// 有些自建服务没有列表接口。「测试」用第一个模型发一条最短的对话,地址、Key、模型、格式
/// 哪样不对都在保存前暴露。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../generate/widgets/common.dart'
    show
        confirmDialog,
        dragEndHaptic,
        dragProxy,
        dragStartHaptic,
        hintSnack,
        sharedAxisRoute;
import 'agent_model.dart'
    show
        assistantModelPrefProvider,
        assistantModelProvider,
        customEndpointIdOf,
        customModelKey;
import 'custom_endpoint.dart';
import 'llm/http_provider.dart' show llmProviderFor;
import '../../l10n/l10n.dart';

/// [editId] 为空 = 展开「添加接口」那张;否则展开那一条。
Future<void> openEndpointsPage(BuildContext context, {String? editId}) =>
    Navigator.of(context).push(sharedAxisRoute(EndpointsPage(editId: editId)));

/// 「添加接口」那张卡的记号。
const _kAdd = '';

class EndpointsPage extends ConsumerStatefulWidget {
  const EndpointsPage({super.key, this.editId});

  final String? editId;

  @override
  ConsumerState<EndpointsPage> createState() => _EndpointsPageState();
}

class _EndpointsPageState extends ConsumerState<EndpointsPage> {
  /// 展开的那张:接口 id、[_kAdd],或 null(都收着)。
  late String? _open = widget.editId ?? _kAdd;

  /// 展开的表单里有没保存的改动。
  bool _dirty = false;

  Future<bool> _discard() => confirmDialog(
    context,
    title: context.l10n.discardChangesQ,
    message: context.l10n.unsavedLost,
    confirmLabel: context.l10n.discardAction,
  );

  Future<void> _toggle(String id) async {
    if (_dirty && !await _discard()) return;
    if (!mounted) return;
    Haptics.selection();
    setState(() {
      _open = _open == id ? null : id;
      _dirty = false;
    });
  }

  void _saved(CustomEndpoint e) {
    Haptics.selection();
    setState(() {
      _open = null;
      _dirty = false;
    });
    hintSnack(
      context,
      context.l10n.savedNamed(e.displayName),
      icon: Icons.check_circle_outline,
    );
  }

  Future<void> _delete(CustomEndpoint e) async {
    final ok = await confirmDialog(
      context,
      title: context.l10n.deleteEndpointQ,
      message: context.l10n.deleteEndpointBody,
      confirmLabel: context.l10n.delete,
    );
    if (!ok || !mounted) return;
    await ref.read(customEndpointsProvider.notifier).remove(e.id);
    if (!mounted) return;
    Haptics.medium();
    if (_open == e.id) {
      setState(() {
        _open = null;
        _dirty = false;
      });
    }
  }

  Widget _form(CustomEndpoint? source) => _EndpointForm(
    key: ValueKey(source?.id ?? _kAdd),
    source: source,
    onDirty: (d) => setState(() => _dirty = d),
    onSaved: _saved,
  );

  @override
  Widget build(BuildContext context) {
    final list =
        ref.watch(customEndpointsProvider).value ?? const <CustomEndpoint>[];
    final current = customEndpointIdOf(
      ref.watch(assistantModelProvider)?.key ?? '',
    );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _discard() || !context.mounted) return;
        setState(() => _dirty = false);
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.myEndpoints)),
        body: ReorderableListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          buildDefaultDragHandles: false,
          proxyDecorator: dragProxy,
          onReorderStart: dragStartHaptic,
          onReorderEnd: dragEndHaptic,
          onReorderItem: (from, to) =>
              ref.read(customEndpointsProvider.notifier).reorder(from, to),
          footer: _EndpointCard(
            title: context.l10n.addEndpoint,
            adding: true,
            open: _open == _kAdd,
            onToggle: () => _toggle(_kAdd),
            form: () => _form(null),
          ),
          children: [
            for (var i = 0; i < list.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(list[i].id),
                index: i,
                // 展开着的卡里有输入框,长按要留给选字
                enabled: _open != list[i].id,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EndpointCard(
                    title: list[i].displayName,
                    subtitle: _subtitle(list[i]),
                    dim: !list[i].usable && !list[i].canDraw,
                    inUse: current == list[i].id,
                    open: _open == list[i].id,
                    onToggle: () => _toggle(list[i].id),
                    onDelete: () => _delete(list[i]),
                    form: () => _form(list[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 卡上副行:起过名的补上服务名,认不出的地址补上格式,最后列模型(出图模型跟在后面)。
String _subtitle(CustomEndpoint e) {
  if (!e.usable && !e.canDraw) return l10nNow.notComplete;
  return [
    if (e.name.trim().isNotEmpty) e.providerLabel,
    if (endpointPresetOf(e.format, e.baseUrl) == null)
      l10nNow.formatOf(agentApiFormatLabel(e.format)),
    [...e.allModels, ...e.imageModels].join(l10nNow.listSep),
  ].join(' · ');
}

/// 一张卡:卡头(标题、副行、删除、展开箭头)+ 展开后的表单。展开时滚到顶上,表单尽量
/// 整个露出来。选择模型里正在用的那张描边、右上角挂「使用中」,与规则预设页同一套。
class _EndpointCard extends StatefulWidget {
  const _EndpointCard({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.form,
    this.subtitle,
    this.adding = false,
    this.dim = false,
    this.inUse = false,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final bool open;
  final bool adding;
  final bool dim;
  final bool inUse;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  /// 展开时才建。
  final Widget Function() form;

  @override
  State<_EndpointCard> createState() => _EndpointCardState();
}

class _EndpointCardState extends State<_EndpointCard> {
  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void didUpdateWidget(_EndpointCard old) {
    super.didUpdateWidget(old);
    // 等展开动画走完再滚,列表还没长高时滚不到位
    if (widget.open && !old.open) Future.delayed(Motion.medium, _reveal);
  }

  void _reveal() {
    if (!mounted || !widget.open) return;
    Scrollable.ensureVisible(
      context,
      duration: Motion.medium,
      curve: Motion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: w.inUse
              ? BorderSide(color: scheme.primary, width: 1.4)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: w.onToggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 6, 13),
                    child: Row(
                      children: [
                        if (w.adding) ...[
                          Icon(Icons.add, size: 20, color: scheme.primary),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodyLarge!.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: w.adding
                                      ? scheme.primary
                                      : w.dim
                                      ? scheme.outline
                                      : null,
                                ),
                              ),
                              if (w.subtitle case final s?) ...[
                                const SizedBox(height: 3),
                                Text(
                                  s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.labelSmall!.copyWith(
                                    color: scheme.outline,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (w.onDelete != null)
                          IconButton(
                            tooltip: context.l10n.delete,
                            visualDensity: VisualDensity.compact,
                            onPressed: w.onDelete,
                            icon: Icon(
                              Icons.delete_outline,
                              size: 19,
                              color: scheme.error.withValues(alpha: .85),
                            ),
                          ),
                        AnimatedRotation(
                          turns: w.open ? .5 : 0,
                          duration: Motion.fast,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.expand_more,
                              size: 20,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.standard,
                  alignment: Alignment.topCenter,
                  child: w.open
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: scheme.outlineVariant.withValues(
                                alpha: .35,
                              ),
                            ),
                            w.form(),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
            if (w.inUse)
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
                    context.l10n.inUse,
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
    );
  }
}

/// 一张卡展开后的表单。[source] 为空 = 新建,保存后直接选上它的第一个模型。
class _EndpointForm extends ConsumerStatefulWidget {
  const _EndpointForm({
    super.key,
    this.source,
    required this.onDirty,
    required this.onSaved,
  });

  final CustomEndpoint? source;

  /// 有没有没保存的改动,变了才报。
  final ValueChanged<bool> onDirty;
  final ValueChanged<CustomEndpoint> onSaved;

  @override
  ConsumerState<_EndpointForm> createState() => _EndpointFormState();
}

class _EndpointFormState extends ConsumerState<_EndpointForm> {
  CustomEndpoint? get _src => widget.source;

  /// 新建那条的 id。测试和保存用同一个。
  late final String _newId = ref.read(customEndpointsProvider.notifier).newId();

  late AgentApiFormat _format = _src?.format ?? AgentApiFormat.openai;

  late final _name = TextEditingController(text: _src?.name ?? '');
  late final _base = TextEditingController(text: _src?.effectiveBase ?? '');
  final _baseFocus = FocusNode();
  late final _key = TextEditingController(text: _src?.apiKey ?? '');
  late final _path = TextEditingController(text: _src?.apiPath ?? '');
  late final _headers = TextEditingController(
    text: formatHeaderLines(_src?.headers ?? const {}),
  );

  late List<String> _models = [...?_src?.allModels];

  /// 「添加模型」那格。没点添加就保存的,也算一个。
  final _modelInput = TextEditingController();

  /// 出图模型,和对话模型分开。
  late List<String> _imageModels = [...?_src?.imageModels];
  final _imageInput = TextEditingController();

  /// 点过「自定义」、地址还空着时也亮着它。
  bool _customPicked = false;

  bool _advanced = false;
  bool _obscureKey = true;

  /// 正在拉列表的那一格:对话模型 false、出图模型 true;没在拉为 null。
  bool? _loadingModels;
  bool _testing = false;

  /// 测试 / 校验的结果,显示在按钮上面。改了任何一格就清掉,免得留着过期的「连接正常」。
  ({bool ok, String text})? _result;

  /// 地址认得出的那一家;没填或认不出为 null。
  EndpointPreset? get _preset => _base.text.trim().isEmpty
      ? null
      : endpointPresetOf(_format, normalizeEndpointBase(_base.text, _format));

  bool get _custom =>
      _preset == null && (_customPicked || _base.text.trim().isNotEmpty);

  List<String> get _allModels => _withPending(_models, _modelInput);

  /// Claude 格式不出图,恒为空。
  List<String> get _allImageModels => _format == AgentApiFormat.anthropic
      ? const []
      : _withPending(_imageModels, _imageInput);

  static List<String> _withPending(List<String> list, TextEditingController c) {
    final pending = c.text.trim();
    return [
      ...list,
      if (pending.isNotEmpty && !list.contains(pending)) pending,
    ];
  }

  List<TextEditingController> get _fields => [
    _name,
    _base,
    _key,
    _path,
    _headers,
    _modelInput,
    _imageInput,
  ];

  /// 打开时的样子,和它比出有没有改动。
  String _initial = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _snap = _texts();
    _initial = _fingerprint();
    for (final c in _fields) {
      c.addListener(_onEdit);
    }
  }

  String _snap = '';

  String _texts() => [for (final c in _fields) c.text].join('\u0000');

  String _fingerprint() => jsonEncode(_draft().toJson());

  void _changed() {
    final d = _fingerprint() != _initial;
    if (d == _dirty) return;
    _dirty = d;
    widget.onDirty(d);
  }

  /// 文字变了就重建:实际请求地址、各格的后缀按钮、高级设置的摘要跟着刷新。
  /// 只挪光标、换焦点不算。
  void _onEdit() {
    final now = _texts();
    if (now == _snap) return;
    _snap = now;
    setState(() => _result = null);
    _changed();
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c
        ..removeListener(_onEdit)
        ..dispose();
    }
    _baseFocus.dispose();
    super.dispose();
  }

  CustomEndpoint _draft() {
    final models = _allModels;
    return CustomEndpoint(
      id: _src?.id ?? _newId,
      name: _name.text.trim(),
      format: _format,
      baseUrl: normalizeEndpointBase(_base.text, _format),
      apiKey: _key.text.trim(),
      model: models.firstOrNull ?? '',
      models: models,
      imageModels: _allImageModels,
      apiPath: _path.text.trim(),
      headers: parseHeaderLines(_headers.text).headers,
    );
  }

  /// 缺了什么就返回那句话,填齐了返回 null。请求头不合格时顺手展开高级设置。
  String? _missing({bool needModel = true}) {
    final b = _base.text.trim();
    if (b.isEmpty) return context.l10n.pickServiceOrUrl;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(b)) {
      return context.l10n.urlMustHttp;
    }
    if (_key.text.trim().isEmpty) return context.l10n.noApiKeyYet;
    // 只填出图模型的也行:这个接口只拿来生成图片
    if (needModel && _allModels.isEmpty && _allImageModels.isEmpty) {
      return context.l10n.noModelYet;
    }
    final bad = parseHeaderLines(_headers.text).bad;
    if (bad != null) {
      _advanced = true;
      return context.l10n.headerLineBad(bad);
    }
    return null;
  }

  void _fail(String text) => setState(() => _result = (ok: false, text: text));

  /// 填好这家的格式和地址。
  void _pickPreset(EndpointPreset p) {
    if (p == _preset) return;
    Haptics.selection();
    setState(() {
      _format = p.format;
      _customPicked = false;
      _result = null;
    });
    _base.text = p.base;
    _changed();
  }

  /// 清掉认得出的地址,光标进地址栏自己填。
  void _pickCustom() {
    Haptics.selection();
    setState(() {
      _customPicked = true;
      _result = null;
    });
    if (_preset != null) _base.clear();
    _baseFocus.requestFocus();
  }

  /// 换格式。地址是原格式的官方地址时跟着换成新格式的官方地址。
  void _pickFormat(AgentApiFormat f) {
    Haptics.selection();
    final official = _preset?.official ?? false;
    setState(() {
      _format = f;
      _result = null;
    });
    if (official) _base.text = agentApiDefaultBase(f);
    _changed();
  }

  /// [image] = 出图模型那一格,否则对话模型。
  List<String> _listOf(bool image) => image ? _imageModels : _models;

  void _setList(bool image, List<String> v) =>
      image ? _imageModels = v : _models = v;

  TextEditingController _inputOf(bool image) =>
      image ? _imageInput : _modelInput;

  void _addModel({bool image = false}) {
    final input = _inputOf(image);
    final m = input.text.trim();
    if (m.isEmpty) return;
    Haptics.selection();
    setState(() {
      final list = _listOf(image);
      if (!list.contains(m)) _setList(image, [...list, m]);
    });
    input.clear();
    _changed();
  }

  void _removeModel(String m, {bool image = false}) {
    Haptics.selection();
    setState(() {
      _setList(image, [..._listOf(image)]..remove(m));
      _result = null;
    });
    _changed();
  }

  Future<void> _paste(TextEditingController c) async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (t == null || t.isEmpty) return;
    c.text = t;
    c.selection = TextSelection.collapsed(offset: c.text.length);
  }

  Future<void> _openKeyPage(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (ok) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      setState(() => _result = (ok: true, text: context.l10n.linkCopied(url)));
    }
  }

  /// 拉模型列表多选。列表里勾掉的移出去,手填的(列表里没有的)留着。
  Future<void> _pickModels({bool image = false}) async {
    final miss = _missing(needModel: false);
    if (miss != null) return _fail(miss);
    setState(() {
      _loadingModels = image;
      _result = null;
    });
    List<String> listed;
    try {
      listed = await llmProviderFor(_draft()).listModels();
    } catch (e) {
      if (mounted) _fail('$e');
      return;
    } finally {
      if (mounted) setState(() => _loadingModels = null);
    }
    if (!mounted) return;
    final current = _listOf(image);
    final picked = await _showModelPicker(context, listed, current.toSet());
    if (picked == null || !mounted) return;
    setState(() {
      _setList(image, [
        for (final m in current)
          if (picked.contains(m) || !listed.contains(m)) m,
        for (final m in listed)
          if (picked.contains(m) && !current.contains(m)) m,
      ]);
    });
    _changed();
  }

  Future<void> _test() async {
    final miss = _missing();
    if (miss != null) return _fail(miss);
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _result = null;
    });
    final draft = _draft();
    try {
      // 只填了出图模型的不发对话,拉一次模型列表看通不通
      final Duration took;
      if (draft.allModels.isEmpty) {
        final watch = Stopwatch()..start();
        await llmProviderFor(draft).listModels();
        took = watch.elapsed;
      } else {
        took = await llmProviderFor(draft).ping();
      }
      if (!mounted) return;
      Haptics.selection();
      final secs = (took.inMilliseconds / 1000).toStringAsFixed(1);
      setState(
        () => _result = (
          ok: true,
          text: draft.allModels.length > 1
              ? context.l10n.modelConnOk(draft.model, secs)
              : context.l10n.connOk(secs),
        ),
      );
    } catch (e) {
      if (mounted) _fail('$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final miss = _missing();
    if (miss != null) return _fail(miss);
    FocusScope.of(context).unfocus();
    final draft = _draft();
    await ref.read(customEndpointsProvider.notifier).put(draft);
    if (_src == null && draft.model.isNotEmpty) {
      await ref
          .read(assistantModelPrefProvider.notifier)
          .set(customModelKey(draft.id, draft.model));
    }
    if (mounted) widget.onSaved(draft);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final keyEmpty = _key.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in kEndpointPresets)
                _serviceChip(p.label, _preset == p, () => _pickPreset(p)),
              _serviceChip(context.l10n.sizeCustom, _custom, _pickCustom),
            ],
          ),
          const SizedBox(height: 6),
          _row(
            context.l10n.formatField,
            top: 12,
            SegmentedButton<AgentApiFormat>(
              segments: [
                for (final f in AgentApiFormat.values)
                  ButtonSegment(value: f, label: Text(agentApiFormatLabel(f))),
              ],
              selected: {_format},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => _pickFormat(v.first),
            ),
          ),
          _row(
            context.l10n.urlField,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  _base,
                  focus: _baseFocus,
                  hint: switch (_format) {
                    AgentApiFormat.google => 'https://example.com/v1beta',
                    _ => 'https://example.com/v1',
                  },
                  keyboard: TextInputType.url,
                  suffix: _pasteBtn(_base),
                ),
                // 自定义地址下面写出实际请求的地址:贴了整条对话地址、少了 /v1 这类错
                // 一眼看得出
                if (_custom && _base.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                    child: Text(
                      '${_draft().chatUri}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                        context,
                        size: 11,
                        weight: FontWeight.w500,
                      ).copyWith(color: scheme.outline),
                    ),
                  ),
              ],
            ),
          ),
          _row(
            'Key',
            _field(
              _key,
              obscure: _obscureKey,
              keyboard: TextInputType.visiblePassword,
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pasteBtn(_key),
                  if (keyEmpty && _preset != null)
                    IconButton(
                      onPressed: () => _openKeyPage(_preset!.keyUrl),
                      icon: const Icon(Icons.open_in_new, size: 20),
                      tooltip: context.l10n.getKey,
                      color: scheme.primary,
                    )
                  else
                    IconButton(
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                        size: 20,
                      ),
                      tooltip: _obscureKey
                          ? context.l10n.show
                          : context.l10n.hide,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          _modelsRow(context.l10n.modelField),
          if (_format != AgentApiFormat.anthropic)
            _modelsRow(context.l10n.imageModelField, image: true),
          _advancedHeader(),
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: _advanced
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row(
                        context.l10n.name,
                        _field(
                          _name,
                          hint: _draft().providerLabel,
                          monoText: false,
                        ),
                      ),
                      // 中转改路径是常事;Gemini 那条还得把模型名写进路径,所以给了
                      // {model} 占位
                      _row(
                        context.l10n.pathField,
                        _field(
                          _path,
                          hint: agentApiDefaultPath(_format),
                          keyboard: TextInputType.url,
                        ),
                      ),
                      _row(
                        context.l10n.headersField,
                        _field(
                          _headers,
                          hint: context.l10n.headersHint,
                          multiline: true,
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (_result case final r?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    r.ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 16,
                    color: r.ok ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.text,
                      style: context.texts.labelMedium!.copyWith(
                        color: r.ok ? scheme.primary : scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Spacer(),
                OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.test),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: Text(context.l10n.save)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceChip(String label, bool on, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: on,
    showCheckmark: false,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    onSelected: (_) => onTap(),
  );

  /// 模型那一格:已添加的一排可删的芯片 + 手填 / 从列表选。[image] = 出图模型。
  Widget _modelsRow(String label, {bool image = false}) {
    final scheme = context.scheme;
    final list = _listOf(image);
    final input = _inputOf(image);
    return _row(
      label,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in list)
                    InputChip(
                      label: Text(m, style: mono(context, size: 12)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () => _removeModel(m, image: image),
                      deleteButtonTooltipMessage: context.l10n.remove,
                    ),
                ],
              ),
            ),
          _field(
            input,
            hint: list.isEmpty
                ? context.l10n.modelIdHint
                : context.l10n.addAnotherModel,
            action: TextInputAction.done,
            onSubmitted: (_) => _addModel(image: image),
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (input.text.trim().isNotEmpty)
                  IconButton(
                    onPressed: () => _addModel(image: image),
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: context.l10n.add,
                    color: scheme.primary,
                  ),
                _loadingModels == image
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _loadingModels == null
                            ? () => _pickModels(image: image)
                            : null,
                        icon: const Icon(Icons.format_list_bulleted, size: 20),
                        tooltip: context.l10n.modelList,
                        color: scheme.onSurfaceVariant,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一行:左边短标签,右边控件。标签对齐控件第一行的中线,[top] 按控件高度给。
  Widget _row(String label, Widget child, {double top = 15}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(top: top),
            // 英文标签放不下时缩字号
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: context.texts.labelMedium!.copyWith(
                  color: context.scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );

  /// 「高级设置」那一行,右边列出填过的几项。
  Widget _advancedHeader() {
    final scheme = context.scheme;
    final headers = parseHeaderLines(_headers.text).headers.length;
    final summary = [
      if (_name.text.trim().isNotEmpty) context.l10n.name,
      if (_path.text.trim().isNotEmpty) context.l10n.pathField,
      if (headers > 0) context.l10n.headersN(headers),
    ].join(' · ');
    return InkWell(
      onTap: () => setState(() => _advanced = !_advanced),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.tune, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.advancedSettings,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!_advanced && summary.isNotEmpty)
              Text(
                summary,
                style: context.texts.labelMedium!.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _advanced ? .5 : 0,
              duration: Motion.fast,
              child: Icon(Icons.expand_more, size: 20, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pasteBtn(TextEditingController c) => IconButton(
    onPressed: () => _paste(c),
    icon: const Icon(Icons.content_paste, size: 20),
    tooltip: context.l10n.paste,
    color: context.scheme.onSurfaceVariant,
  );

  Widget _field(
    TextEditingController c, {
    FocusNode? focus,
    String? hint,
    bool obscure = false,
    bool multiline = false,
    bool monoText = true,
    TextInputType? keyboard,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
    Widget? suffix,
  }) {
    final scheme = context.scheme;
    return TextField(
      controller: c,
      focusNode: focus,
      obscureText: obscure,
      keyboardType: multiline ? TextInputType.multiline : keyboard,
      textInputAction: action,
      onSubmitted: onSubmitted,
      minLines: 1,
      maxLines: multiline ? 5 : 1,
      autocorrect: false,
      enableSuggestions: false,
      style: monoText ? mono(context, size: 13) : null,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: context.skin.float
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerHighest,
        hintText: hint,
        hintStyle: TextStyle(color: scheme.outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        suffixIcon: suffix,
      ),
    );
  }
}

/// 模型列表多选。条数可能上百,给个搜索框。[selected] 是已经加上的,返回勾完的全部;
/// 关掉返回 null。
Future<Set<String>?> _showModelPicker(
  BuildContext context,
  List<String> models,
  Set<String> selected,
) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ModelPicker(models: models, selected: selected),
);

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.selected});

  final List<String> models;
  final Set<String> selected;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _q = '';
  late final Set<String> _on = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final q = _q.trim().toLowerCase();
    final list = [
      for (final m in widget.models)
        if (q.isEmpty || m.toLowerCase().contains(q)) m,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.l10n.searchNModels(widget.models.length),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final on = _on.contains(m);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      controlAffinity: ListTileControlAffinity.trailing,
                      title: Text(
                        m,
                        style: TextStyle(
                          fontWeight: on ? FontWeight.w700 : null,
                          color: on ? scheme.primary : null,
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _on.add(m);
                        } else {
                          _on.remove(m);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _on),
                    child: Text(context.l10n.doneSelectedN(_on.length)),
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

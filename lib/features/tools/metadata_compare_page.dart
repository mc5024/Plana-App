import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editor_theme.dart';
import '../../core/util/image_pick.dart';
import '../assistant/widgets/attach_pick.dart';
import '../import/image_metadata.dart';
import '../../l10n/l10n.dart';
import 'metadata_diff.dart';

class _Side {
  const _Side(this.bytes, this.meta);

  final Uint8List bytes;
  final ImageMetadata? meta;
}

/// 图片比对(工具箱页签):A / B 两张图的生成参数逐项比,提示词按标签标出增删、
/// 权重与位置变化。
class MetadataCompareView extends ConsumerStatefulWidget {
  const MetadataCompareView({super.key});

  @override
  ConsumerState<MetadataCompareView> createState() =>
      _MetadataCompareViewState();
}

class _MetadataCompareViewState extends ConsumerState<MetadataCompareView> {
  final _sides = <_Side?>[null, null];
  bool _loading = false;
  bool _showSame = false;

  /// 点哪格先填哪格;一次挑了两张,第二张填另一格。
  Future<void> _pick(int slot) async {
    final source = await showAttachSourceDialog(
      context,
      title: context.l10n.selectImage,
    );
    if (source == null || !mounted) return;
    final picked = source == AttachSource.gallery
        ? await pickGalleryImages(context, ref, max: 2)
        : await pickImageFiles(context);
    if (picked.isEmpty || !mounted) return;
    setState(() => _loading = true);
    final sides = <_Side>[];
    for (final p in picked.take(2)) {
      ImageMetadata? meta;
      try {
        meta = await extractImageMetadata(p.bytes);
      } catch (_) {}
      sides.add(_Side(p.bytes, meta));
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sides[slot] = sides.first;
      if (sides.length > 1) _sides[1 - slot] = sides[1];
    });
  }

  Color _colorOf(TagChange c) => switch (c) {
    TagChange.onlyA => context.scheme.error,
    TagChange.onlyB => context.editor.oc,
    TagChange.weight => context.editor.weightUp,
    TagChange.moved => context.editor.weightDown,
    TagChange.same => context.scheme.onSurface,
  };

  @override
  Widget build(BuildContext context) {
    final a = _sides[0]?.meta, b = _sides[1]?.meta;
    final both = a != null && b != null;
    final params = both ? diffParams(a, b, context.l10n) : const <ParamRow>[];
    final pos = both ? diffTags(a.prompt, b.prompt) : const <TagDiff>[];
    final neg = both
        ? diffTags(a.negativePrompt, b.negativePrompt)
        : const <TagDiff>[];
    final chars = both ? diffCharacters(a, b) : const <CharDiff>[];
    final kinds = {
      for (final d in [
        pos,
        neg,
        for (final c in chars) ...[c.prompt, c.uc],
      ])
        for (final t in d) t.change,
    }..remove(TagChange.same);

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            children: [
              _slots(),
              for (final (i, s) in _sides.indexed)
                if (s != null && s.meta == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      context.l10n.noMetadataFor(i == 0 ? 'A' : 'B'),
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall!.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              if (both) ...[
                if (kinds.isNotEmpty) _legend(kinds),
                const SizedBox(height: 18),
                _paramsSection(params),
                if (pos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _promptSection(context.l10n.positivePrompt, pos),
                ],
                if (neg.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _promptSection(context.l10n.negativePrompt, neg),
                ],
                if (chars.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(context.l10n.characterPrompts),
                  const SizedBox(height: 8),
                  for (final c in chars) ...[
                    _charCard(c),
                    if (c != chars.last) const SizedBox(height: 8),
                  ],
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- A / B 两格 ----------------

  Widget _slots() {
    final full = _sides.every((s) => s != null);
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            Expanded(child: _slot(0)),
            const SizedBox(width: 8),
            Expanded(child: _slot(1)),
          ],
        ),
        if (full)
          Material(
            color: context.scheme.surface,
            shape: const CircleBorder(),
            elevation: 1,
            child: IconButton(
              onPressed: () => setState(() {
                final t = _sides[0];
                _sides[0] = _sides[1];
                _sides[1] = t;
              }),
              icon: const Icon(Icons.swap_horiz, size: 18),
              tooltip: context.l10n.swapAB,
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  Widget _slot(int i) {
    final scheme = context.scheme;
    final side = _sides[i];
    final edge = context.skin.edge;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: context.raisedFill(scheme.surfaceContainerHigh),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: edge == null ? BorderSide.none : BorderSide(color: edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _loading ? null : () => _pick(i),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (side == null)
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 28,
                  color: scheme.outline,
                )
              else
                Image.memory(
                  side.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 512,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.broken_image_outlined, color: scheme.outline),
                ),
              Positioned(top: 6, left: 6, child: _badge(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(int i) {
    final color = i == 0 ? context.scheme.error : context.editor.oc;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        i == 0 ? 'A' : 'B',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _legend(Set<TagChange> kinds) {
    final labels = {
      TagChange.onlyA: context.l10n.onlyInA,
      TagChange.onlyB: context.l10n.onlyInB,
      TagChange.weight: context.l10n.weightChanged,
      TagChange.moved: context.l10n.orderChanged,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final MapEntry(:key, :value) in labels.entries)
            if (kinds.contains(key))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorOf(key),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  // ---------------- 分区 ----------------

  Widget _sectionLabel(String text, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }

  Widget _status(String text) => Text(
    text,
    style: TextStyle(fontSize: 12.5, color: context.scheme.outline),
  );

  BoxDecoration get _card => BoxDecoration(
    color: context.raisedFill(context.scheme.surfaceContainerHigh),
    border: context.edgeBorder,
    borderRadius: BorderRadius.circular(11),
  );

  Widget _paramsSection(List<ParamRow> rows) {
    final scheme = context.scheme;
    final diff = rows.where((r) => r.differs).toList();
    final same = rows.where((r) => !r.differs).toList();
    Widget divider() => Divider(
      height: 1,
      thickness: 1,
      color: scheme.outlineVariant.withValues(alpha: .4),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          context.l10n.genParams,
          trailing: _status(
            diff.isEmpty
                ? context.l10n.identical
                : context.l10n.differentN(diff.length),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: _card,
          child: Column(
            children: [
              if (diff.isNotEmpty)
                _paramRow(null, _badge(0), _badge(1), vertical: 8),
              for (final r in diff) ...[
                divider(),
                _paramRow(
                  r,
                  _value(r.a, scheme.error),
                  _value(r.b, context.editor.oc),
                ),
              ],
              if (same.isNotEmpty) ...[
                if (diff.isNotEmpty) divider(),
                InkWell(
                  onTap: () => setState(() => _showSame = !_showSame),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                    child: Row(
                      children: [
                        Text(
                          context.l10n.identicalN(same.length),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showSame ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: scheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showSame)
                  for (final r in same) ...[
                    divider(),
                    _paramRow(
                      r,
                      _value(
                        r.a,
                        scheme.onSurfaceVariant,
                        weight: FontWeight.w400,
                      ),
                      null,
                    ),
                  ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 一行参数:键名 | A | B;[b] 为 null 时 [a] 占满两栏(相同项)。
  Widget _paramRow(ParamRow? r, Widget a, Widget? b, {double vertical = 10}) {
    final scheme = context.scheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: vertical),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: r == null
                ? null
                : Text(
                    // 原始键名多是 snake_case,下划线 / 点后允许折行
                    r.rawKey
                        ? r.label.replaceAllMapped(
                            RegExp(r'[_.]'),
                            (m) => '${m[0]}​',
                          )
                        : r.label,
                    style: r.rawKey
                        ? mono(
                            context,
                            size: 12,
                            weight: FontWeight.w400,
                            color: scheme.onSurfaceVariant,
                          )
                        : TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                  ),
          ),
          const SizedBox(width: 8),
          if (b == null)
            Expanded(child: a)
          else ...[
            Expanded(
              child: Align(alignment: Alignment.topLeft, child: a),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(alignment: Alignment.topLeft, child: b),
            ),
          ],
        ],
      ),
    );
  }

  Widget _value(
    String? v,
    Color color, {
    FontWeight weight = FontWeight.w500,
  }) => Text(
    v ?? '—',
    style: mono(
      context,
      size: 13.5,
      weight: weight,
      color: v == null ? context.scheme.outline : color,
    ),
  );

  Widget _promptSection(String label, List<TagDiff> d) {
    final changed = tagsDiffer(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          label,
          trailing: changed ? null : _status(context.l10n.identical),
        ),
        if (changed) ...[
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: _card,
            child: _tagText(d),
          ),
        ],
      ],
    );
  }

  Widget _tagText(List<TagDiff> d) {
    final scheme = context.scheme;
    final spans = <InlineSpan>[];
    for (final (i, t) in d.indexed) {
      if (i > 0) {
        spans.add(
          TextSpan(
            text: ', ',
            style: TextStyle(color: scheme.outline),
          ),
        );
      }
      final c = _colorOf(t.change);
      spans.add(
        TextSpan(
          text: t.text,
          style: t.change == TagChange.same
              ? null
              : TextStyle(
                  color: c,
                  backgroundColor: c.withValues(alpha: .13),
                  decoration: t.change == TagChange.onlyA
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: c,
                  decorationThickness: 2,
                ),
        ),
      );
      if (t.change == TagChange.weight) {
        spans.add(
          TextSpan(
            text: ' ${fmtWeight(t.weightA!)}→${fmtWeight(t.weightB!)}',
            style: mono(context, size: 12, color: c),
          ),
        );
      }
    }
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: 14, height: 1.6, color: scheme.onSurface),
    );
  }

  Widget _charCard(CharDiff c) {
    final scheme = context.scheme;
    final posChanged = c.posA != c.posB;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10n.characterN(c.index + 1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              if (posChanged)
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: c.posA ?? '—',
                          style: TextStyle(color: scheme.error),
                        ),
                        const TextSpan(text: ' → '),
                        TextSpan(
                          text: c.posB ?? '—',
                          style: TextStyle(color: context.editor.oc),
                        ),
                      ],
                    ),
                    style: mono(
                      context,
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: scheme.outline,
                    ),
                  ),
                )
              else if (c.posA != null)
                Text(
                  c.posA!,
                  style: mono(
                    context,
                    size: 12.5,
                    weight: FontWeight.w400,
                    color: scheme.outline,
                  ),
                ),
              const Spacer(),
              if (!c.differs) _status(context.l10n.identical),
            ],
          ),
          if (tagsDiffer(c.prompt)) ...[
            const SizedBox(height: 5),
            _tagText(c.prompt),
          ],
          if (tagsDiffer(c.uc)) ...[
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3.5, right: 6),
                  child: Text(
                    'UC',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.error.withValues(alpha: .85),
                    ),
                  ),
                ),
                Expanded(child: _tagText(c.uc)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

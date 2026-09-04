import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show hintSnack, sharedAxisRoute;
import 'image_metadata.dart';
import 'import_panel.dart';

/// 3b 完整元数据页:顶卡「完整元数据」入口的落地页,对齐桌面 MetadataDetailPanel。
/// 图片 + 大小/尺寸/格式/来源、正/负向(可复制)、角色提示词、生成参数网格、
/// LoRA、Vibe、原始 JSON(可复制)。
class MetadataDetailPage extends StatelessWidget {
  const MetadataDetailPage({
    super.key,
    required this.meta,
    required this.bytes,
    required this.fileName,
    this.standalone = false,
  });

  final ImageMetadata meta;
  final Uint8List bytes;
  final String fileName;

  /// true = 从工具页独立打开:无「关闭导入」动作,底部给「去导入面板」。
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('完整元数据'),
        actions: [
          if (!standalone)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭导入',
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.pop();
              },
            ),
        ],
      ),
      bottomNavigationBar: standalone && meta.isNovelAI
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    sharedAxisRoute(
                      ImportImagePanel(
                        bytes: bytes,
                        fileName: fileName,
                        displayName: fileName.replaceAll(
                          RegExp(r'\.[^.]+$'),
                          '',
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('去导入面板(导入参数 / 用作参考)'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          _header(context, scheme),
          const SizedBox(height: 18),
          if (meta.prompt.isNotEmpty)
            _textBlock(context, scheme, '正向提示词', meta.prompt),
          if (meta.negativePrompt.isNotEmpty) ...[
            const SizedBox(height: 16),
            _textBlock(
              context,
              scheme,
              '负向提示词',
              meta.negativePrompt,
              danger: true,
            ),
          ],
          if (meta.characters.isNotEmpty) ...[
            const SizedBox(height: 16),
            _charBlock(context, scheme),
          ],
          if (_paramItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _paramsBlock(context, scheme),
          ],
          if (meta.loras.isNotEmpty) ...[
            const SizedBox(height: 16),
            _loraBlock(context, scheme),
          ],
          if (meta.vibes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _vibeBlock(context, scheme),
          ],
          if (meta.raw != null) ...[
            const SizedBox(height: 16),
            _rawBlock(context, scheme),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: 88, height: 88, fit: BoxFit.cover),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              _kv(context, scheme, '大小', _fmtSize(bytes.length)),
              _kv(
                context,
                scheme,
                '尺寸',
                '${meta.width}×${meta.height}',
                mono: true,
              ),
              _kv(context, scheme, '格式', _sourceLabel(meta.sourceType)),
              _kv(context, scheme, '来源', meta.source),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(
    BuildContext context,
    ColorScheme scheme,
    String k,
    String v, {
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              k,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? monoStyle(context, 11)
                  : TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    ColorScheme scheme,
    String text, {
    String? copyText,
  }) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (copyText != null)
          InkWell(
            onTap: () => _copy(context, copyText),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.content_copy,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '复制',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _textBlock(
    BuildContext context,
    ColorScheme scheme,
    String label,
    String text, {
    bool danger = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, scheme, label, copyText: text),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(11),
          ),
          // 可选中:整段复制走右上角按钮,这里是给"只要其中几个 tag"的场景
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: danger ? scheme.error : scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _charBlock(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, scheme, '角色提示词'),
        const SizedBox(height: 8),
        for (var i = 0; i < meta.characters.length; i++) ...[
          _charCard(context, scheme, i),
          if (i != meta.characters.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _charCard(BuildContext context, ColorScheme scheme, int i) {
    final c = meta.characters[i];
    final coord = (c.centerX != null && c.centerY != null)
        ? ' (${c.centerX!.toStringAsFixed(2)}, ${c.centerY!.toStringAsFixed(2)})'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '角色 ${i + 1}$coord',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            c.prompt.isEmpty ? '(空)' : c.prompt,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: scheme.onSurface,
            ),
          ),
          if ((c.uc ?? '').isNotEmpty) ...[
            const SizedBox(height: 5),
            SelectableText(
              'UC: ${c.uc}',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: scheme.error.withValues(alpha: .85),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<(String, String)> get _paramItems {
    final m = meta;
    return [
      if (m.seed.isNotEmpty) ('Seed', m.seed),
      if (m.steps != null) ('Steps', m.steps!),
      if (m.scale != null) ('CFG Scale', m.scale!),
      if (m.sampler != null) ('Sampler', m.sampler!),
      if (m.noiseSchedule != null) ('Noise Schedule', m.noiseSchedule!),
      if (m.cfgRescale != null) ('CFG Rescale', m.cfgRescale!),
      // 透明背景(V5)。只报,不参与导入 —— 触发它的 tag 本来就在提示词里。
      if (m.transparentBackground != null)
        ('透明背景', m.transparentBackground! ? '是' : '否'),
      if (m.straightAlpha != null)
        ('Alpha', m.straightAlpha! ? '直通 Straight' : '预乘 Premultiplied'),
    ];
  }

  Widget _paramsBlock(BuildContext context, ColorScheme scheme) {
    final items = _paramItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, scheme, '生成参数'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            const gap = 7.0;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (k, v) in items)
                  SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            k.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.outline,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(context, 11.5),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _loraBlock(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, scheme, 'LoRA'),
        const SizedBox(height: 8),
        for (final l in meta.loras)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(l.weight.toString(), style: monoStyle(context, 11.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _vibeBlock(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, scheme, 'Vibe Transfer (${meta.vibes.length})'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            const gap = 7.0;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < meta.vibes.length; i++)
                  SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vibe ${i + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.outline,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '强度: ${meta.vibes[i].strength.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            '提取: ${(meta.vibes[i].informationExtracted ?? 1.0).toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _rawBlock(BuildContext context, ColorScheme scheme) {
    final text = _prettyRaw();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, scheme, '原始数据', copyText: text),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(11),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: monoStyle(context, 10, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  String _prettyRaw() {
    try {
      return const JsonEncoder.withIndent('  ').convert(meta.raw);
    } catch (_) {
      return meta.raw.toString();
    }
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    hintSnack(context, '已复制', icon: Icons.check);
  }

  String _sourceLabel(ImageSourceType t) => switch (t) {
    ImageSourceType.novelai => 'novelai',
    ImageSourceType.stableDiffusion => 'stable-diffusion',
    ImageSourceType.comfyui => 'comfyui',
    ImageSourceType.unknown => 'unknown',
  };

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

/// 等宽小字(复用 app_theme 的 mono 语义,但这里是无 context 依赖的薄封装)。
TextStyle monoStyle(BuildContext context, double size, {Color? color}) =>
    mono(context, size: size, color: color);

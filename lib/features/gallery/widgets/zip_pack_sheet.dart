import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../../core/theme/app_theme.dart';
import '../gallery_store.dart';
import '../models.dart';
import '../save_settings.dart';
import '../zip_pipeline.dart';
import '../../../l10n/l10n.dart';

/// 打好的包 + 用户定的文件名。`file` 为 null = 打包失败(提示由调用方给)。
typedef ZipPacked = ({File? file, String fileName, int packed, int failed});

/// 打包 ZIP:先定包名、按需加密,确认后**就地打包** —— 进度条留在这张弹层里,
/// 打完把包交回调用方去挑落点。取消或划走返回 null。
///
/// 打包不丢回外面做:按下「打包」之后用户还盯着的就是这张弹层,进度跑到底部
/// 按钮上去等于让弹层先消失、再让人找进度在哪。
Future<ZipPacked?> showZipPackSheet(
  BuildContext context, {
  required List<ResultImage> items,
  required GalleryStore store,
  required SaveSettings settings,
  required String defaultName,
}) => showModalBottomSheet<ZipPacked>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ZipPackSheet(
    items: items,
    store: store,
    settings: settings,
    defaultName: defaultName,
  ),
);

class _ZipPackSheet extends StatefulWidget {
  const _ZipPackSheet({
    required this.items,
    required this.store,
    required this.settings,
    required this.defaultName,
  });

  final List<ResultImage> items;
  final GalleryStore store;
  final SaveSettings settings;
  final String defaultName;

  @override
  State<_ZipPackSheet> createState() => _ZipPackSheetState();
}

class _ZipPackSheetState extends State<_ZipPackSheet> {
  late final _name = TextEditingController(text: widget.defaultName);
  final _pwd = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _canceled = false;
  int _done = 0;

  @override
  void dispose() {
    _name.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _pack() async {
    final base = sanitizeZipName(_name.text);
    if (base.isEmpty || _busy) return;
    final fileName = '$base.zip';
    final pwd = _pwd.text;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _canceled = false;
      _done = 0;
    });
    final r = await packImagesZip(
      widget.items,
      store: widget.store,
      settings: widget.settings,
      fileName: fileName,
      password: pwd.isEmpty ? null : pwd,
      onEach: (done) {
        if (!mounted || _canceled) return false; // 划走/按了取消:中止剩余
        setState(() => _done = done);
        return true;
      },
    );
    if (!mounted) return;
    // 掐在最后一张按的取消,包可能已经成了 —— 那也不能留,用户要的是别打
    if (_canceled) {
      try {
        await r.file?.delete();
      } catch (_) {}
      if (mounted) Navigator.pop(context);
      return;
    }
    Navigator.pop(context, (
      file: r.file,
      fileName: fileName,
      packed: r.packed,
      failed: r.failed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final total = widget.items.length;
    final valid = sanitizeZipName(_name.text).isNotEmpty;
    final field = InputDecoration(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    return SafeArea(
      child: Padding(
        // 键盘顶起时输入框不被遮
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text(
                      context.l10n.packZip,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      context.l10n.imagesN(total),
                      style: context.texts.bodyMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 60,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: field.copyWith(
                    labelText: context.l10n.zipName,
                    suffixText: '.zip',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: TextField(
                  controller: _pwd,
                  enabled: !_busy,
                  obscureText: _obscure,
                  maxLength: 64,
                  // 密码只收 ASCII:archive 派生密钥吃的是码元低 8 位,中文进去
                  // 别家解压工具算出来的密钥对不上,包就等于废了
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]')),
                  ],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _pack(),
                  decoration: field.copyWith(
                    labelText: context.l10n.zipPassword,
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            _canceled
                                ? context.l10n.stopping
                                : context.l10n.zipping,
                            style: context.texts.bodySmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$_done/$total',
                            style: context.texts.bodySmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? null : _done / total,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _canceled
                            ? null
                            : () {
                                if (_busy) {
                                  setState(() => _canceled = true);
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: Text(context.l10n.cancel),
                      ),
                    ),
                    if (!_busy) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: valid ? _pack : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: Text(context.l10n.pack),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

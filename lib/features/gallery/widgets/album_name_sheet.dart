import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../save_settings.dart';

/// 选/建自定义相册名。确定返回清洗后的名字,取消返回 null。
///
/// 只让用户输名字、不列系统已有相册 —— 固定写 `Pictures/<名字>/`,
/// 而系统相册里大量条目住在别处(相机在 DCIM/Camera 等)。若列出来任选,
/// 选了写不进去的那些会另建同名新相册,出现两个同名相册,极其迷惑。
Future<String?> showAlbumNameSheet(
  BuildContext context, {
  required List<String> recent,
  required int count,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .85,
  ),
  builder: (_) => _AlbumNameSheet(recent: recent, count: count),
);

class _AlbumNameSheet extends StatefulWidget {
  const _AlbumNameSheet({required this.recent, required this.count});

  final List<String> recent;
  final int count;

  @override
  State<_AlbumNameSheet> createState() => _AlbumNameSheetState();
}

class _AlbumNameSheetState extends State<_AlbumNameSheet> {
  late final _ctrl = TextEditingController(
    text: widget.recent.isEmpty ? '' : widget.recent.first,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = sanitizeAlbumName(_ctrl.text);
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final valid = sanitizeAlbumName(_ctrl.text).isNotEmpty;
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  '保存到手机相册',
                  style: context.texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  '${widget.count} 张将存入系统相册的「${sanitizeAlbumName(_ctrl.text).isEmpty ? "…" : sanitizeAlbumName(_ctrl.text)}」;'
                  '相册不存在会自动创建。',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  maxLength: 40,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '相册名称',
                    hintText: '如 Plana 精选',
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (widget.recent.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in widget.recent)
                        ActionChip(
                          label: Text(a),
                          onPressed: () => setState(() {
                            _ctrl.text = a;
                            _ctrl.selection = TextSelection.collapsed(
                              offset: a.length,
                            );
                          }),
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
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: valid ? _submit : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const Text('保存'),
                      ),
                    ),
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

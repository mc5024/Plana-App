import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/file_read.dart';
import '../generate/widgets/common.dart' show hintSnack;
import 'web_backup.dart';
import 'web_backup_import.dart';

/// 导入 web(novelai_web_ui)「数据备份」文件:选文件 → 预览清单 → 导入。
/// 落库走各库现成的导入口(Vibe 走 .naiv4vibebundle、角色参考走图片字节),
/// 不新开写路径,免得两套落库逻辑日后走岔。
class WebBackupPage extends ConsumerStatefulWidget {
  const WebBackupPage({super.key});

  @override
  ConsumerState<WebBackupPage> createState() => _WebBackupPageState();
}

class _WebBackupPageState extends ConsumerState<WebBackupPage> {
  WebBackup? _backup;
  String? _fileName;
  bool _busy = false;
  String? _error;

  /// 导入完成后的结果行(逐类计数 + 跳过说明),null = 还没导过。
  List<(String, String)>? _result;

  /// 进行中的逐条进度(「Vibe 42/300」),空 = 还没开始报数。
  String _progress = '';

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _result = null;
    });
    // withData: false —— 备份可能上百 MB,拿路径流式解析,别整份读进内存
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any, // 备份是 .json,但各家文件管理器的 mime 过滤不可靠
    );
    final file = res?.files.firstOrNull;
    if (file == null || !mounted) return;
    // 大文件解析要一会儿:先撤掉上一份的清单,免得下面的按钮跟着报「正在导入」
    setState(() {
      _busy = true;
      _backup = null;
      _fileName = null;
    });
    try {
      final b = WebBackup.fromDecoded(await readPickedJson(file));
      if (!mounted) return;
      setState(() {
        _backup = b;
        _fileName = file.name;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message.isEmpty ? '不是有效的 JSON 文件' : e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '文件读取失败(不是 UTF-8 文本?)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final b = _backup;
    if (b == null || _busy) return;
    // 自选面板 + 落库全在 runWebBackupImport 里(与灵感库手动导入共用同一套)
    setState(() => _busy = true);
    final out = await runWebBackupImport(
      context,
      ref,
      b,
      onProgress: (label, done, total) {
        if (mounted) setState(() => _progress = '$label $done/$total');
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = '';
      if (out == null) return; // 用户在自选面板取消
      _result = out.rows;
      _error = out.errors.isEmpty ? null : out.errors.join('\n');
    });
    if (out == null) return;
    hintSnack(
      context,
      out.errors.isEmpty ? '导入完成' : '导入完成,${out.errors.length} 项失败',
      icon: out.errors.isEmpty ? Icons.check : Icons.warning_amber_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final b = _backup;
    return Scaffold(
      appBar: AppBar(title: const Text('导入 web 备份')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            '在 web 端「设置 → 数据备份 → 导出数据」得到的 '
            'novelai_backup_*.json,可在此导入。',
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open_outlined, size: 19),
            label: Text(
              b != null
                  ? '重新选择'
                  : (_busy ? '正在读取…' : '选择备份文件'), // 上百 MB 的备份解析要几秒
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ).merge(context.pageTonalStyle),
          ),
          if (_error case final String e) ...[
            const SizedBox(height: 14),
            _Banner(text: e, error: true),
          ],
          if (b != null) ...[
            const SizedBox(height: 18),
            _Card(
              title: _fileName ?? '备份文件',
              subtitle: b.createdAt.isEmpty ? null : '备份于 ${b.createdAt}',
              rows: [
                ('Vibe', '${b.vibes.length} 条'),
                ('角色参考', '${b.crs.length} 张'),
                ('灵感库 · 角色', '${b.ocs.length} 条'),
                ('灵感库 · 画风', '${b.artists.length} 条'),
                ('提示词预设', '${b.presets.length} 条'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '同 id 的条目会被覆盖,其余保留。灵感库条目里 base64 内嵌的预览图'
              '不带过来(体积过大),其余字段原样保留。web 端的界面/AI 设置不导入'
              '(两端设置项不是一套)。',
              style: context.texts.bodySmall!.copyWith(
                color: scheme.outline,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: (_busy || b.isEmpty) ? null : _import,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 19),
              label: Text(
                !_busy
                    ? '选择内容并导入'
                    : (_progress.isEmpty ? '正在导入…' : '正在导入 $_progress'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (b.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '这份备份里没有 app 能接收的数据。',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ),
          ],
          if (_result case final List<(String, String)> rows) ...[
            const SizedBox(height: 18),
            _Card(title: '导入结果', rows: rows),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: error
            ? scheme.errorContainer.withValues(alpha: .5)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: error ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall!.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 清单卡:单行条目 + 右侧数据值。
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.rows, this.subtitle});

  final String title;
  final String? subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyLarge!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle case final String s) ...[
                const SizedBox(height: 2),
                Text(
                  s,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(k, style: context.texts.bodyMedium)),
                      Text(
                        v,
                        style: mono(
                          context,
                          size: 12.5,
                          color: scheme.onSurfaceVariant,
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

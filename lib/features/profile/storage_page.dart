import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/remote_image.dart';
import '../../core/store/app_stores.dart';
import '../../core/store/cache_sweep.dart';
import '../../core/store/storage_settings.dart';
import '../../core/store/storage_stats.dart';
import '../../core/theme/app_theme.dart';
import '../char_library/char_library.dart';
import '../gallery/gallery_state.dart';
import '../generate/vibe_cache.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;
import '../inspiration/codex/codex_providers.dart';
import '../inspiration/tag_library.dart';
import '../vibe_library/vibe_library.dart';
import 'widgets/settings_ui.dart';

/// 存储管理:占用一览、自动清理上限、一键清理。
class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _CatSpec {
  const _CatSpec(this.keys, this.icon, this.label, this.action);

  /// 一行可以盖住多个扫描分类:占用取和,清理时逐个执行。
  /// 首个 key 兼作行 id(忙碌态与释放量都按它记)。
  final List<String> keys;
  final IconData icon;
  final String label;
  final String action;

  String get id => keys.first;
}

/// 免费重建的那几样:导入临时文件、在线图缓存、法典缓存、孤儿参考图快照。
/// 合成一行 —— 没人需要知道它们在磁盘上分了四个目录。
const _kCacheKeys = ['temp', 'imgCache', 'codexCache', 'blobs'];

/// 「可清理」只此一组。合并看的是**重建代价**,不是目录结构:
/// - 头一行全是删了自动重建、不花钱也不花流量的,合成一条即可;
/// - 往下每一条的代价都不一样(重编码扣 Anlas / 重下 10.9 MB 模型 /
///   预览要重新做 / 作品和素材库直接不可恢复)。代价不同就得让人分开选,
///   不能为了少几行把它们捆成一键。
const _cleanable = <_CatSpec>[
  _CatSpec(_kCacheKeys, Icons.cached, '缓存文件', '清理'),
  _CatSpec(['vibeEnc'], Icons.bolt_outlined, 'Vibe 编码缓存', '清空'),
  _CatSpec(['models'], Icons.hd_outlined, '超分模型(遗留)', '删除'),
  _CatSpec(['tagPrev'], Icons.lightbulb_outline, '灵感预览图', '清空'),
  _CatSpec(['gallery'], Icons.photo_library_outlined, '图库作品', '清空'),
  _CatSpec(['vibeLib'], Icons.palette_outlined, 'Vibe 库', '清空'),
  _CatSpec(['charLib'], Icons.person_outline, '角色参考库', '清空'),
];

class _StoragePageState extends ConsumerState<StoragePage> {
  StorageReport? _report;
  String? _busy; // 正在清理的分类 key
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _scanning = true);
    final rep = await scanStorage();
    if (!mounted) return;
    setState(() {
      _report = rep;
      _scanning = false;
    });
  }

  /// 各分类占用之和(合并行按它取数)。
  int _bytesOf(StorageReport? rep, List<String> keys) {
    var sum = 0;
    for (final k in keys) {
      sum += rep?[k]?.bytes ?? 0;
    }
    return sum;
  }

  /// 清理动作前后各扫一次,提示释放量。
  Future<void> _run(List<String> keys, Future<void> Function() job) async {
    if (_busy != null) return;
    final before = _bytesOf(_report, keys);
    setState(() => _busy = keys.first);
    try {
      await job();
      // 等 store 的串行删除链走完再重扫,数字才准
      await ref.read(appStoresProvider).gallery.idle;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final rep = await scanStorage();
      if (!mounted) return;
      final freed = before - _bytesOf(rep, keys);
      setState(() {
        _report = rep;
        _busy = null;
      });
      hintSnack(
        context,
        freed > 0 ? '已释放 ${fmtBytes(freed)}' : '没有可清理的内容',
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      hintSnack(context, '清理失败: $e', icon: Icons.error_outline);
    }
  }

  /// 改上限后立即触发各仓库裁剪,再刷新数字。
  Future<void> _applyCaps(
    StorageSettings Function(StorageSettings) change,
  ) async {
    await ref.read(storageSettingsProvider.notifier).patch(change);
    ref.read(galleryProvider.notifier).enforceCap();
    await ref.read(vibeLibraryProvider.notifier).enforceCap();
    await ref.read(charLibraryProvider.notifier).enforceCap();
    await ref.read(appStoresProvider).gallery.idle;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) await _refresh();
  }

  /// 孤儿参考图回收:活引用之外的 blob 才删,给个新鲜窗口防并发写。
  Future<void> _gcBlobs() async {
    final stores = ref.read(appStoresProvider);
    stores.flushNow();
    await stores.gallery.idle;
    final live = <String>{
      ...await stores.workspace.liveRefs(),
      ...await stores.gallery.liveRefs(),
    };
    await stores.blobs.gc(live, minAge: const Duration(minutes: 5));
  }

  Future<void> _onAction(String key) async {
    final stores = ref.read(appStoresProvider);
    switch (key) {
      // 合并行「缓存文件」:四样一起清。全是免费重建的,不必确认。
      case 'temp':
        await _run(_kCacheKeys, () async {
          await sweepPickerCache(minAge: Duration.zero);
          await RemoteImageStore.clear();
          await ref.read(codexServiceProvider).clearCache();
          await _gcBlobs();
        });
      case 'tagPrev':
        final n = _report?['tagPrev']?.count;
        final ok = await confirmDialog(
          context,
          title: '清空灵感预览图',
          message:
              '将删除本机生成的${n == null ? '' : ' $n 张'}条目预览图,'
              '并从条目上摘除引用;条目本身与提示词不受影响,预览需重新生成。',
          confirmLabel: '清空',
        );
        if (!ok) return;
        await _run([
          key,
        ], () => ref.read(tagLibraryProvider.notifier).clearLocalPreviews());
      case 'gallery':
        final n = _report?['gallery']?.count;
        final ok = await confirmDialog(
          context,
          title: '清空全部图库数据',
          message:
              '将删除全部${n == null ? '' : ' $n 张'}作品与参数快照，以及自建图库和封面，不可恢复。'
              '已保存到系统相册的图片不受影响。',
          confirmLabel: '清空',
        );
        if (!ok) return;
        // 快照没了,顺手清孤儿参考图;释放量把这部分也算进去
        await _run(const ['gallery', 'blobs'], () async {
          await ref.read(galleryProvider.notifier).clearAll();
          await stores.gallery.idle;
          await stores.albums.idle;
          await _gcBlobs();
        });
      case 'vibeEnc':
        final ok = await confirmDialog(
          context,
          title: '清空编码缓存',
          message:
              '清空后,下次用这些图生成时需重新编码;直连线路每张图约扣 2 Anlas。'
              '不影响 Vibe 库文件本身。',
          confirmLabel: '清空',
        );
        if (!ok) return;
        await _run([key], () async {
          final cache = await ref.read(vibeCacheProvider.future);
          await cache.clear();
        });
      case 'vibeLib':
        final n = _report?['vibeLib']?.count;
        final ok = await confirmDialog(
          context,
          title: '清空 Vibe 库',
          message:
              '将删除库内全部${n == null ? '' : ' $n 个'}文件'
              '(原图 / 缩略图 / 已存编码),不可恢复。',
          confirmLabel: '清空',
        );
        if (!ok) return;
        await _run([
          key,
        ], () => ref.read(vibeLibraryProvider.notifier).clearAll());
      case 'charLib':
        final n = _report?['charLib']?.count;
        final ok = await confirmDialog(
          context,
          title: '清空角色参考库',
          message:
              '将删除库内全部${n == null ? '' : ' $n 个'}文件,不可恢复。'
              '图库作品里的参数快照不受影响。',
          confirmLabel: '清空',
        );
        if (!ok) return;
        await _run([
          key,
        ], () => ref.read(charLibraryProvider.notifier).clearAll());
      case 'models':
        final ok = await confirmDialog(
          context,
          title: '删除超分模型',
          message:
              '本地超分功能已下线,这 ${fmtBytes(_report?['models']?.bytes ?? 0)} '
              '模型文件已经用不上了,删掉不会少任何功能。',
          confirmLabel: '删除',
        );
        if (!ok) return;
        await _run([key], clearUpscaleModels);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rep = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
        actions: [
          IconButton(
            onPressed: _scanning ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
          ),
        ],
      ),
      body: rep == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                children: [
                  _TotalCard(report: rep, scanning: _scanning),
                  const SizedBox(height: 16),
                  const SettingsLabel('自动清理上限'),
                  _CapsCard(onPatch: _applyCaps),
                  const SizedBox(height: 16),
                  const SettingsLabel('可清理'),
                  SettingsCard(
                    children: [
                      for (final spec in _cleanable)
                        _CleanRow(
                          spec: spec,
                          bytes: _bytesOf(rep, spec.keys),
                          busy: _busy == spec.id,
                          enabled: _busy == null,
                          onAction: () => _onAction(spec.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.report, required this.scanning});

  final StorageReport report;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '总占用',
                      style: context.texts.bodySmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fmtBytes(report.totalBytes),
                      style: context.texts.headlineSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '其他 ${fmtBytes(report.otherBytes)}',
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (scanning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapsCard extends ConsumerWidget {
  const _CapsCard({required this.onPatch});

  final Future<void> Function(StorageSettings Function(StorageSettings))
  onPatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s =
        ref.watch(storageSettingsProvider).value ?? const StorageSettings();
    return SettingsCard(
      children: [
        _CapRow(
          label: '图库作品',
          unit: '张',
          value: s.galleryCap,
          onChanged: (v) => onPatch((x) => x.copyWith(galleryCap: v)),
        ),
        _CapRow(
          label: 'Vibe 库',
          unit: '条',
          value: s.vibeCap,
          onChanged: (v) => onPatch((x) => x.copyWith(vibeCap: v)),
        ),
        _CapRow(
          label: '角色参考库',
          unit: '张',
          value: s.charRefCap,
          onChanged: (v) => onPatch((x) => x.copyWith(charRefCap: v)),
        ),
      ],
    );
  }
}

/// 上限行:点按弹输入框,自定义数字或设为无上限。
class _CapRow extends StatelessWidget {
  const _CapRow({
    required this.label,
    required this.unit,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String unit;
  final int value;
  final ValueChanged<int> onChanged;

  Future<void> _edit(BuildContext context) async {
    final ctl = TextEditingController(text: value > 0 ? '$value' : '');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label上限'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(suffixText: unit),
          onSubmitted: (v) =>
              Navigator.of(ctx).pop(int.tryParse(v.trim()) ?? 0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: const Text('无上限'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(ctl.text.trim()) ?? 0),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) onChanged(result.clamp(0, 999999));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: context.texts.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value > 0 ? '$value $unit' : '无上限',
              style: value > 0
                  ? mono(context, size: 13, color: scheme.onSurfaceVariant)
                  : context.texts.bodySmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.edit_outlined, size: 15, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _CleanRow extends StatelessWidget {
  const _CleanRow({
    required this.spec,
    required this.bytes,
    required this.busy,
    required this.enabled,
    required this.onAction,
  });

  final _CatSpec spec;
  final int bytes;
  final bool busy;
  final bool enabled;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final canAct = enabled && bytes > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          Icon(spec.icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              spec.label,
              style: context.texts.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            fmtBytes(bytes),
            style: mono(context, size: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 32,
            width: 64,
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: canAct ? onAction : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(spec.action),
                  ),
          ),
        ],
      ),
    );
  }
}

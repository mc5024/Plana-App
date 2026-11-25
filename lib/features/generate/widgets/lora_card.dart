import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/bot_session_store.dart';
import '../../../core/net/backend_client.dart';
import '../../../core/net/remote_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../lora/lora_install_queue.dart';
import '../../lora/lora_manager_page.dart';
import '../../lora/lora_stack_ui.dart';
import '../../lora/lora_upload_task.dart';
import '../generate_state.dart';
import '../lora_triggers.dart';
import '../models.dart';
import 'common.dart';
import 'section_card.dart';

/// LoRA 卡(anima / krea 共用同一块 UI,样式对齐 web 桌面端 lora 模块):
/// 已挂列表(启用开关 · 缩略图 · 名称/类型徽标/触发词计数 · 权重),
/// 选中项展开权重滑杆与触发词行 —— 点触发词直接写进/移出正向提示词。
///
/// 两边挂载语义完全一致,差别只在库(见 `loraBaseProvider`)和发出去时进
/// `anima_extra` 还是 `krea_extra` —— 所以卡片本身不用分两份。
class LoraCard extends ConsumerStatefulWidget {
  const LoraCard({super.key, this.reorderIndex});

  final int? reorderIndex;

  @override
  ConsumerState<LoraCard> createState() => _LoraCardState();
}

class _LoraCardState extends ConsumerState<LoraCard> {
  String? _selectedName;
  void Function()? _dropInstallHandler;
  void Function()? _dropUploadHandler;

  /// 正在收尾的任务(按 versionId):装好的回调和下面的补接、换模型时新旧两张
  /// 卡片,都可能撞上同一条。
  static final _handling = <int>{};

  @override
  void initState() {
    super.initState();
    // 后台安装队列:导入页只负责入队,装好在这里自动挂上并提示。
    _dropInstallHandler = ref
        .read(loraInstallQueueProvider.notifier)
        .onInstalled(_onLoraInstalled);
    // 后台上传结束、管理器没开着(开着的话它先接走):在这里提示一声
    _dropUploadHandler = ref
        .read(loraUploadTaskProvider.notifier)
        .onFinished(_onUploadFinished);
    // 装好的那一刻卡片不在(切去了没有 LoRA 模块的模型 / 画布),那条没人接,
    // 占位条会一直停在「下载中」:卡片回来时把队列里没收尾的补上。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final job in ref.read(loraInstallQueueProvider)) {
        if (!job.pending) unawaited(_onLoraInstalled(job));
      }
    });
  }

  @override
  void dispose() {
    _dropInstallHandler?.call();
    _dropUploadHandler?.call();
    super.dispose();
  }

  bool _onUploadFinished(LoraUploadOutcome o) {
    if (!mounted) return false;
    if (!o.ok) {
      hintSnack(context, 'LoRA「${o.name}」${o.message}', icon: Icons.cloud_off);
    } else {
      hintSnack(
        context,
        o.dedup ? 'LoRA「${o.name}」库里已有,已为你收藏' : 'LoRA「${o.name}」已上传好,可在管理器里挂载',
        icon: Icons.check,
      );
    }
    return true;
  }

  /// 转正 / 标红是状态上的事,卡片中途被拆也照做(用到的先取到手);只有提示
  /// 条要看卡片还在不在。
  Future<void> _onLoraInstalled(LoraInstallJob job) async {
    if (!_handling.add(job.versionId)) return;
    final queue = ref.read(loraInstallQueueProvider.notifier);
    final notifier = ref.read(generateProvider.notifier);
    final backend = ref.read(backendClientProvider);
    final session = ref.read(botSessionProvider.future);
    final placeholder = pendingLoraKey(job.versionId);
    if (job.status != LoraInstallStatus.done || job.lrId == null) {
      // 失败:占位条留在原地标红,别让它默默消失 —— 用户导入时是勾了的,
      // 悄悄不见了他会以为已经生效。停用它,同时保住「移除」入口。
      notifier.markLoraFailed(placeholder, job.message ?? '下载失败');
      if (mounted) {
        hintSnack(context, 'LoRA「${job.name}」下载失败:${job.message ?? '未知原因'}');
      }
      queue.clearFinished();
      _handling.remove(job.versionId);
      return;
    }
    try {
      final sid = (await session)?.sessionId;
      if (sid == null || sid.isEmpty) return;
      // 按任务自己的底模去查:队列跨页面存活,装好时用户可能已经切走模型,
      // 拿当前底模查会查不到这条(它落在另一个库里)。
      final lib = await backend.listLoras(sid, base: job.base);
      final item = lib.where((l) => l.name == job.lrId).firstOrNull;
      if (item != null) {
        final promoted = notifier.promotePendingLora(
          placeholder,
          ActiveLora(
            name: item.name,
            displayName: item.displayName,
            weight: job.weight ?? item.recommendedWeight,
            clipWeight: job.clipWeight,
            hasTe: item.hasTe,
            triggerWords: item.triggerWords,
            previewUrl: item.previewUrl,
            type: item.type,
          ),
        );
        if (mounted) {
          hintSnack(
            context,
            // 没转正 = 占位条已经不在了(用户中途移除 / 换了工作区),
            // 只报下载完成,别暗示它已经挂上
            promoted
                ? 'LoRA「${item.displayName}」已下载,现在可以用了'
                : 'LoRA「${item.displayName}」已下载,可在管理器里挂载',
          );
        }
      }
    } catch (_) {
      if (mounted) hintSnack(context, 'LoRA「${job.name}」已下载,请手动挂载');
    } finally {
      queue.clearFinished();
      _handling.remove(job.versionId);
    }
  }

  Future<void> _openManager() async {
    await Navigator.of(context).push(sharedAxisRoute(const LoraManagerPage()));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generateProvider);
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;

    final loras = state.loras;
    final expanded = state.openPanels.contains(Panel.lora) && loras.isNotEmpty;

    ActiveLora? selected;
    for (final l in loras) {
      if (l.name == _selectedName) {
        selected = l;
        break;
      }
    }
    selected ??= loras.isNotEmpty ? loras.first : null;

    // 后台下载(导入页入队的),让人在生成页也看得到进度
    final queue = ref.watch(loraInstallQueueProvider);
    final installing = queue.where((j) => j.pending).length;
    final cur = queue
        .where((j) => j.status == LoraInstallStatus.installing)
        .firstOrNull;
    final upload = ref.watch(loraUploadTaskProvider);
    final dlTitle = cur != null
        ? 'LoRA · ${cur.name} ${cur.progressText}'
        : upload != null
        ? 'LoRA · 上传 ${upload.name} ${upload.progressText}'
        : (installing > 0 ? 'LoRA · 下载排队 $installing' : 'LoRA');

    return SectionCard(
      icon: Icons.auto_awesome_outlined,
      title: dlTitle,
      reorderIndex: widget.reorderIndex,
      badge: loras.isEmpty ? null : CountBadge('${loras.length}'),
      actions: [
        if (loras.any((l) => l.pending == null))
          RoundIconBtn(
            Icons.layers_outlined,
            tooltip: '保存为 LoRA 堆',
            color: scheme.onSurfaceVariant,
            onTap: () => showSaveLoraStackDialog(context, ref),
          ),
        RoundIconBtn(
          Icons.grid_view,
          tooltip: 'LoRA 管理器',
          color: loras.isEmpty ? scheme.primary : scheme.onSurfaceVariant,
          onTap: _openManager,
        ),
      ],
      expanded: expanded,
      onHeaderTap: loras.isEmpty
          ? _openManager
          : () => notifier.togglePanel(Panel.lora),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 有条目还没下载完 → 明说本次生成不带它,别让人以为已经生效
          if (loras.any((l) => l.pending != null && l.pending!.failed == null))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoNote(
                '${loras.where((l) => l.pending != null && l.pending!.failed == null).length}'
                ' 个 LoRA 正在下载,暂时不参与生成,装好会自动接上',
                icon: Icons.downloading_outlined,
                color: scheme.primary,
              ),
            ),
          for (final l in loras) ...[
            _LoraRow(
              lora: l,
              selected: l.name == selected?.name,
              onTap: () => setState(() => _selectedName = l.name),
            ),
            const SizedBox(height: 6),
          ],
          if (selected != null) ...[
            const SizedBox(height: 8),
            _LoraDetail(
              lora: selected,
              onRemove: () {
                notifier.removeLora(selected!.name);
                final rest = ref.read(generateProvider).loras;
                setState(
                  () => _selectedName = rest.isEmpty ? null : rest.first.name,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 类型徽标(角色/画风/概念),配色对齐 web:pink/purple/cyan。
class LoraTypeBadge extends StatelessWidget {
  const LoraTypeBadge(this.type, {super.key});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'character' => const Color(0xFFEC4899),
      'style' => const Color(0xFFA855F7),
      _ => const Color(0xFF06B6D4),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        loraTypeLabel(type),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// LoRA 缩略图(远端预览直链;取不到时用闪光图标占位)。
class LoraThumb extends StatelessWidget {
  const LoraThumb(this.url, {super.key, this.size = 40});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHigh,
      child: Icon(
        Icons.auto_awesome,
        size: size * .5,
        color: scheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: url.isEmpty
          ? fallback
          : RemoteImage(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _LoraRow extends ConsumerWidget {
  const _LoraRow({
    required this.lora,
    required this.selected,
    required this.onTap,
  });

  final ActiveLora lora;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final prompt = ref.watch(generateProvider.select((s) => s.prompt));
    final added = lora.triggerWords
        .where((t) => promptHasTrigger(prompt, t))
        .length;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .08)
          : scheme.surfaceContainerHigh.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Opacity(
                opacity: lora.enabled ? 1 : .4,
                child: LoraThumb(lora.previewUrl),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: lora.enabled ? 1 : .55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lora.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: lora.enabled
                              ? null
                              : TextDecoration.lineThrough,
                          decorationThickness: 2,
                          color: lora.enabled
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          // 下载态顶掉类型徽标:这条现在的关键信息是「还不能用」
                          if (lora.pending != null)
                            _PendingBadge(pending: lora.pending!)
                          else
                            LoraTypeBadge(lora.type),
                          if (lora.triggerWords.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.key,
                              size: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$added/${lora.triggerWords.length}',
                              style: context.texts.labelSmall!.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'w${lora.weight.toStringAsFixed(2)}',
                style: mono(
                  context,
                  size: 12,
                  color: lora.enabled && lora.pending == null
                      ? scheme.primary
                      : scheme.outline,
                ),
              ),
              if (!lora.enabled && lora.pending == null) ...[
                const SizedBox(width: 6),
                Icon(Icons.visibility_off, size: 15, color: scheme.outline),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 占位条上的状态徽标:实时进度从安装队列按 versionId 取(别在条目里再存一份
/// 进度,两份状态迟早对不上)。失败时标红停在原地,等用户移除或重新导入。
class _PendingBadge extends ConsumerWidget {
  const _PendingBadge({required this.pending});

  final LoraPending pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final failed = pending.failed;
    final job = ref
        .watch(loraInstallQueueProvider)
        .where((j) => j.versionId == pending.versionId)
        .firstOrNull;
    final text = failed != null
        ? '下载失败'
        : job == null || job.status == LoraInstallStatus.queued
        ? '排队中'
        : '下载中 ${job.progressText}';
    final fg = failed != null ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// 选中项详情:启用/移除 + 权重滑杆 + 触发词行(点击写进/移出正向词)。
class _LoraDetail extends ConsumerWidget {
  const _LoraDetail({required this.lora, required this.onRemove});

  final ActiveLora lora;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(generateProvider.notifier);
    final scheme = context.scheme;
    final prompt = ref.watch(generateProvider.select((s) => s.prompt));
    // 还没下载完:控件全锁(改了也没处生效),只留「移除」
    final locked = lora.pending != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // 下载中/失败的不给切启停 —— 它本来就还不能用
            if (locked)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  lora.pending!.failed != null
                      ? Icons.error_outline
                      : Icons.downloading_outlined,
                  size: 20,
                  color: lora.pending!.failed != null
                      ? scheme.error
                      : scheme.primary,
                ),
              )
            else
              RefEnableToggle(
                enabled: lora.enabled,
                onTap: () =>
                    notifier.updateLora(lora.name, enabled: !lora.enabled),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                lora.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: scheme.error),
                      const SizedBox(width: 6),
                      Text(
                        '移除',
                        style: context.texts.bodyMedium!.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LiveParamSlider(
          label: 'Weight 权重',
          help: Help.loraWeight,
          value: lora.weight,
          max: kLoraWeightMax,
          divisions: 40, // step 0.05(对齐 web LoraNumberInput)
          enabled: !locked,
          caption: locked ? '下载完成后可调(元数据里的值已记下)' : null,
          onCommit: (v) => notifier.updateLora(lora.name, weight: v),
        ),
        // CLIP 强度:默认跟随权重(开关关着=不发 clip_weight)。开了才独立,
        // 所见即所发——不留「界面没显示但请求里有」的隐藏参数。
        // 该 LoRA 没训文本编码器时整块换成一行说明:调了也不会有任何变化,
        // 摆个能拨的开关反而误导。
        if (lora.hasTe == false)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: scheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '该 LoRA 未训练文本编码器,CLIP 强度对它无效',
                    style: context.texts.bodySmall!.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              // 说明挂在下面那条滑杆的标签上,这里不再重复一个问号
              Expanded(
                child: Text(
                  'CLIP 跟随权重',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              // 开=跟随(默认,与历史行为一致);关掉才独立调下面那条滑杆。
              // 语义与 web 的「CLIP 跟随权重」勾选框一致——正着说,别让默认态是「关」。
              Switch(
                value: lora.clipWeight == null,
                onChanged: locked
                    ? null
                    : (follow) => notifier.updateLora(
                        lora.name,
                        clipWeight: follow ? null : lora.weight,
                        clearClipWeight: follow,
                      ),
              ),
            ],
          ),
        // 滑杆常驻(对齐 web 的常显 CLIP 列):跟随开着时只读、显权重值,
        // 关掉跟随就地变可拖——不藏起来,省得用户找不到这个参数在哪。
        if (lora.hasTe != false)
          LiveParamSlider(
            label: 'CLIP 强度',
            help: Help.loraClip,
            value: lora.clipWeight ?? lora.weight,
            max: kLoraWeightMax,
            divisions: 40,
            enabled: lora.clipWeight != null && !locked,
            onCommit: (v) => notifier.updateLora(lora.name, clipWeight: v),
          ),
        if (lora.triggerWords.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '触发词 · 点击写入/移出正向提示词',
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 6),
          for (final tw in lora.triggerWords) ...[
            _TriggerRow(
              trigger: tw,
              added: promptHasTrigger(prompt, tw),
              onTap: () {
                final cur = ref.read(generateProvider).prompt;
                notifier.setPrompts(
                  positive: promptHasTrigger(cur, tw)
                      ? removeTriggerFromPrompt(cur, tw)
                      : appendTriggerToPrompt(cur, tw),
                );
              },
            ),
            const SizedBox(height: 5),
          ],
        ],
      ],
    );
  }
}

class _TriggerRow extends StatelessWidget {
  const _TriggerRow({
    required this.trigger,
    required this.added,
    required this.onTap,
  });

  final String trigger;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: added
          ? scheme.primary.withValues(alpha: .13)
          : scheme.surfaceContainerHigh.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: added
                  ? scheme.primary.withValues(alpha: .5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                added ? Icons.check : Icons.add,
                size: 14,
                color: added ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  trigger,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall!.copyWith(
                    color: added ? scheme.primary : scheme.onSurfaceVariant,
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

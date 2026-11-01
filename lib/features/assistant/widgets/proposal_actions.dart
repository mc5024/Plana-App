/// 处置一份提议的那一排按钮:导入 / 生成 / 撤销。
///
/// 两处用:最后一份提议的气泡里、结果条下面(见 `assistant_page` 的 `_ai`),每一份的
/// 详情弹层底部也有 —— 两处必须是同一排按钮,复制一份迟早漂。
///
/// **一行放得下就是一行**。原来是 Wrap,三颗按钮在窄屏上折成两行、把卡拉得更长;
/// 而这三件事本来就不是并列的:
///   · 「看完整」是查看不是动作,在结果条上单独一颗「展开」
///   · 「直接生成」的「直接」是相对「导入后再生成」说的,而两条路现在并排
///     摆着,不必用词再解释一遍 —— 就叫「生成」
///   · 「撤销」推到右缘,与左边那组动作分开
///
/// 气泡里只有屏宽的八成多,窄屏上导入过之后三颗可能挤不下:这时「撤销」换到下一行
/// ([OverflowBar]),不溢出、也不去压缩按钮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/anlas_provider.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../generate/cost.dart';
import '../../generate/vibe_encoder.dart';
import '../../generate/widgets/bottom_action_bar.dart' show CostPill;
import '../../generate/widgets/common.dart'
    show confirmDialog, dropFocusSoon, hintSnack;
import '../assistant_models.dart';
import '../assistant_state.dart';

class ProposalActions extends ConsumerWidget {
  const ProposalActions({
    super.key,
    required this.msg,
    this.onDone,
    this.dense = false,
  });

  final AssistantMsg msg;

  /// 按完之后要做的事。弹层里传「关掉自己」—— 导入/撤销都会改掉弹层正在显示的
  /// 那份差异,留在原地看着一份已经不成立的对比只会让人怀疑是不是没生效。
  final VoidCallback? onDone;

  /// 包在气泡里的那一排:按钮矮一点、边距收一点,「撤销」不带图标。
  final bool dense;

  /// 还没落到创作页(从没导入过,或者导入后又撤销了)。
  bool get _live => msg.change == null || msg.change!.undone;

  void _import(BuildContext context, WidgetRef ref) {
    if (!ref.read(assistantProvider.notifier).applyProposal(msg.id)) return;
    hintSnack(context, '已写入创作页', icon: Icons.check);
    onDone?.call();
  }

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    final n = ref.read(assistantProvider.notifier);
    if (n.undo(msg.id)) {
      onDone?.call();
      return;
    }
    // 不一致 = 用户在导入之后自己又改过。直接恢复会把他那些改动一起吃掉,
    // 所以这里必须拦一下 —— 整套流程里唯一需要确认的地方。
    final ok = await confirmDialog(
      context,
      title: '撤销这次导入?',
      message: '你在导入之后又动过提示词。撤销会一并丢掉你那些改动,回到导入之前的样子。',
      confirmLabel: '仍要撤销',
    );
    // 对话框一关焦点会还给输入框、把键盘顶出来,而用户点的是卡上的按钮
    dropFocusSoon();
    if (!ok || !context.mounted) return;
    n.undo(msg.id, force: true);
    hintSnack(context, '已撤销', icon: Icons.undo);
    onDone?.call();
  }

  void _generate(WidgetRef ref) {
    // 走 notifier 那条唯一入口:要不要切去图库、出完的图挂不挂回对话,
    // 都由那边按设置定 —— 这里再判一遍迟早和自动生成那条漂开。
    ref.read(assistantProvider.notifier).generateFrom(msg.id);
    onDone?.call();
  }

  /// 这一版要花多少点。与吸底栏那颗按钮同一套算法(含 Vibe 编码费单列),
  /// 免得同一份状态在两处报出两个数。助手不产重绘,所以不走 inpaint 那条公式。
  int _cost(WidgetRef ref) {
    final sent = ref.read(assistantProvider.notifier).previewSendState(msg.id);
    if (sent == null) return 0;
    final isOpus = ref.watch(anlasProvider).asData?.value?.isOpus ?? false;
    final v5Charged = ref.watch(v5ChargedProvider);
    final fee = ref.watch(vibeEncodeFeeProvider(vibeEncodeFeeKey(sent))).value;
    return estimateCost(sent, isOpus: isOpus, v5Charged: v5Charged) +
        (fee ?? 0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final float = context.skin.float;
    final height = dense ? 36.0 : 40.0;
    final undoStyle = TextButton.styleFrom(
      minimumSize: Size(0, height),
      padding: dense ? const EdgeInsets.symmetric(horizontal: 10) : null,
      foregroundColor: scheme.onSurfaceVariant,
    );
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      spacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 导入过就停在「已导入」,不收起来:按钮一消失,分不清是导进去了还是没点上。
            // 开着自动导入时,提议一出来就已经导进去了,这里一直是「已导入」。
            FilledButton.tonalIcon(
              onPressed: _live ? () => _import(context, ref) : null,
              icon: Icon(_live ? Icons.download : Icons.check, size: 17),
              label: Text(_live ? '导入' : '已导入'),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, height),
                padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14),
                backgroundColor: float ? scheme.surfaceContainerLow : null,
                foregroundColor: float ? scheme.onSurface : null,
                side: switch (context.skin.edge) {
                  final edge? when float => BorderSide(color: edge),
                  _ => null,
                },
              ),
            ),
            const SizedBox(width: 8),
            // 不导入也能出这一版,和导入后再生成是同一张(见 proposalSendState)。
            FilledButton(
              onPressed: () => _generate(ref),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, height),
                padding: EdgeInsets.fromLTRB(dense ? 10 : 12, 0, 8, 0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, size: 17),
                  const SizedBox(width: 4),
                  const Text('生成'),
                  const SizedBox(width: 7),
                  // 与吸底栏同一颗胶囊:点了要不要花钱、花多少,按之前就该知道。
                  CostPill(cost: _cost(ref)),
                ],
              ),
            ),
          ],
        ),
        if (!_live)
          dense
              ? TextButton(
                  onPressed: () => _undo(context, ref),
                  style: undoStyle,
                  child: const Text('撤销'),
                )
              : TextButton.icon(
                  onPressed: () => _undo(context, ref),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('撤销'),
                  style: undoStyle,
                ),
      ],
    );
  }
}

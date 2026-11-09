import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_mode.dart';
import '../../../core/auth/bot_session_store.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../canvas_state.dart';
import '../generate_state.dart';
import '../gpu_rental.dart';
import '../models.dart' as m;
import 'anlas_panel.dart';
import 'canvas_picker.dart';
import 'common.dart' show hintSnack;
import 'rental_panel.dart';
import 'top_bar_status.dart' show topBarTextWidth;
import '../../../l10n/l10n.dart';

/// 单行顶栏：画布、模型和资源均裸显示。
class GenerateTopBar extends ConsumerWidget {
  const GenerateTopBar({super.key});

  Future<void> _pickModel(BuildContext context, WidgetRef ref) async {
    final current = ref.read(generateProvider).params.model;
    final picked = await showModalBottomSheet<String>(
      context: context,
      // 定高七成屏(与高级设置那张 .86 同一路数)。不按内容高:各类条目数不同,
      // 贴内容会让弹层随分类横滑抽动;而默认的 9/16 封顶在矮屏/大字号机型上
      // 又会从底部静默裁掉选项(实机反馈:部分机型最后一个模型被挡)。
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .7,
        // anima / krea 都走服务端 Modal 后端,仅 Bot 授权模式提供
        // (对齐 web isAnimaAvailable / isKreaAvailable:token 直连模式没有服务端会话)。
        //
        // watch 而不是 read:NAI 页右上角能就地切生成方式,切完这两页要当场
        // 进出。分组数变了就换 key 整块重建 —— TabController 的 length 定死在
        // 构造时,重建 State 比手工换控制器干净(新的照样停在当前型号那一类)。
        child: Consumer(
          builder: (context, ref, _) {
            final modalOk = ref.watch(authModeProvider).value == AuthMode.bot;
            return _ModelSheet(
              key: ValueKey(modalOk),
              current: current,
              groups: [
                m.GenProvider.nai,
                if (modalOk) ...[m.GenProvider.anima, m.GenProvider.krea],
              ],
              // NAI 5 已上线,直连线与 bot 线都可用:直连 buildNaiPayload 已支持
              // V5 载荷(v4_prompt + params_version 4),bot 线由后端构造 —— 两档常列。
              nai5: true,
            );
          },
        ),
      ),
    );
    if (picked != null) ref.read(generateProvider.notifier).setModel(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(generateProvider.select((s) => s.params.model));
    final canvasName = ref.watch(
      canvasWorkspaceProvider.select((w) => w.active.name),
    );
    final rentalActive = ref.watch(gpuRentalProvider).active;
    final scheme = context.scheme;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final extra = (textScale - 1).clamp(0.0, double.infinity);
    final rowHeight = 44.0 + extra * 20;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: LayoutBuilder(
        // 三段各占固定的格:画布靠左、模型在中间那格居中、读数靠右(读数自己
        // 定宽)。名字长短变了只在各自格里截断,不推着别的段挪位
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(height: rowHeight, child: const CanvasPicker()),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 5,
              child: Center(
                child: Tooltip(
                  message: '切换模型：$model',
                  child: Semantics(
                    button: true,
                    label: '切换模型，当前 $model',
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _pickModel(context, ref),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: SizedBox(
                            height: rowHeight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    m.shortModelName(model),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.bodyMedium!.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.expand_more,
                                  size: 20,
                                  color: scheme.outline,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .38),
              child: SizedBox(
                height: rowHeight,
                // 持续订阅实例状态，NAI 下也显示仍在计费的算力。
                child: m.isModalModel(model) || rentalActive
                    ? const RentalSourceChip(compact: true)
                    : AnlasChip(
                        budget: _readoutBudget(
                          context,
                          constraints.maxWidth,
                          canvasName,
                          model,
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

/// 读数最多能占多宽,画布名和模型名才都不被截(两格按 4 : 5 分读数以外的
/// 宽度):画布格是图标 + 名字 + 箭头,模型格是名字 + 箭头。
double _readoutBudget(
  BuildContext context,
  double width,
  String canvasName,
  String model,
) {
  final style = context.texts.bodyMedium!.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  final canvasNeed = 47 + topBarTextWidth(context, canvasName, style);
  final modelNeed =
      25 + topBarTextWidth(context, m.shortModelName(model), style);
  return width - 8 - max(canvasNeed * 9 / 4, modelNeed * 9 / 5);
}

/// 模型选择弹层(定高七成屏):下划线 Tab + 可左右滑的分页,每页是该大类的型号列表。
///
/// 三类平铺成一张长表要滚两屏,选型时还得先认清自己看的是哪一段;分页之后
/// 每页只有 2-4 项,一眼到底,还能直接横滑翻类。
///
/// 只列**当前可用**的大类:Anima / Krea 走服务端 Modal 后端,token 直连模式
/// 没有服务端会话,列出来也点不动 —— 摆一排点不动的 tab 比不摆更让人费解。
/// 于是只剩一类时连 Tab 条一起收走(孤零零一个 tab 是纯噪声)。
class _ModelSheet extends StatefulWidget {
  const _ModelSheet({
    super.key,
    required this.current,
    required this.groups,
    this.nai5 = false,
  });

  final String current;
  final List<m.GenProvider> groups;

  /// NAI 组是否追加 NAI 5 两档(已上线,直连 + Bot 双线恒 true;留参数
  /// 是为下一个未上线模型的预载再用同一开关)。
  final bool nai5;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet>
    with SingleTickerProviderStateMixin {
  /// 进来就停在当前型号所属的那一类;那类当前不可用(如停在 Anima 却切回了
  /// token 模式)就落到第一类 —— 停在一个选不了的分组上没有意义。
  late final TabController _tab = TabController(
    length: widget.groups.length,
    // 进来就停在当前型号所属的那一类;那类当前不可用(如停在 Anima 却切回了
    // token 模式)就落到第一类 —— 停在一个选不了的分组上没有意义。
    initialIndex: widget.groups
        .indexOf(m.providerOfModel(widget.current))
        .clamp(0, widget.groups.length - 1),
    vsync: this,
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: SizedBox(
              // 定高:胶囊随分页进出,行高不能跟着变,否则切 tab 整个列表上下抽
              height: 34,
              child: Row(
                children: [
                  Text(
                    context.l10n.model,
                    style: context.texts.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  // 右上角这一格两枚胶囊轮值,跟着 tab 动画淡入淡出 ——
                  // 横滑到一半时它们也在半路上,不是「啪」地切换:
                  //  - Anima / Krea 页 → 算力来源(那两条线才有实例可言);
                  //  - NAI 页 → 生成方式速切(直连 Token / Bot 账户)。
                  AnimatedBuilder(
                    animation: _tab.animation!,
                    builder: (context, _) {
                      final i = _tab.animation!.value.round().clamp(
                        0,
                        widget.groups.length - 1,
                      );
                      final nai = widget.groups[i] == m.GenProvider.nai;
                      return Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          _slot(show: !nai, child: const RentalSourceChip()),
                          _slot(show: nai, child: const _AuthModeChip()),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 下划线 Tab + 可左右滑的分页:不做成一排按钮,列表本身也跟着滑。
          if (widget.groups.length > 1)
            TabBar(
              controller: _tab,
              tabs: [
                for (final g in widget.groups)
                  Tab(height: 42, text: m.providerLabel(g)),
              ],
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: scheme.outlineVariant.withValues(alpha: .5),
            ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [for (final g in widget.groups) _modelList(g)],
            ),
          ),
        ],
      ),
    );
  }

  /// 轮值格里的一枚:淡出的那枚不吃点击。两枚都留在树里,格宽按较宽的那枚
  /// 定死,换页时标题行不会跟着变宽变窄。
  Widget _slot({required bool show, required Widget child}) => AnimatedOpacity(
    opacity: show ? 1 : 0,
    duration: Motion.fast,
    child: IgnorePointer(ignoring: !show, child: child),
  );

  Widget _modelList(m.GenProvider g) => ListView(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    children: [
      for (final model in m.modelsOf(g, nai5: widget.nai5)) _modelTile(model),
    ],
  );

  Widget _modelTile(String model) {
    final desc = m.modelDescriptions[model];
    return ListTile(
      onTap: () => Navigator.pop(context, model),
      title: Text(m.modelName(model), style: context.texts.bodyMedium),
      // 副标题恒单行:文案本身已按一行裁,但系统字号调大/窄屏仍会折行 ——
      // 折了这张表就一页两套行高,ellipsis 兜住。
      subtitle: desc == null
          ? null
          : Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall!.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
      trailing: model == widget.current
          ? Icon(Icons.check, size: 18, color: context.scheme.primary)
          : null,
      dense: true,
    );
  }
}

/// 生成方式速切(只在模型弹层的 NAI 页露面):直连 Token ↔ Bot 账户,点开选。
///
/// NAI 两条线都能出图,来回换是常事(直连那边额度见底、或想省 Anlas 走 Bot),
/// 原先只有「我的 → 账号与接入」一处切得动,挑模型挑到一半得整个退出去。
///
/// 下拉而不是点一下对切(与并排的 [RentalSourceChip]、统计页的数据源下拉同一
/// 套):两个去处摊开摆着,不用先按一下才知道另一边是什么。没授权 Bot 时那行
/// 压暗但照样点得动 —— 点它提示暂未开放,禁用了反倒只剩一条说不出所以然的
/// 灰杠。而「选了 Bot 却没授权」那种坏状态,回 Token 这行永远亮着。
class _AuthModeChip extends ConsumerWidget {
  const _AuthModeChip();

  /// 与并排轮值的 [RentalSourceChip] 同高。
  static const _height = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final mode = ref.watch(authModeProvider).value ?? AuthMode.token;
    final bot = mode == AuthMode.bot;
    // 会话还在读盘时按「没有」办:只影响能不能换去 Bot,读完自己会重建
    final canSwitch = bot || ref.watch(botSessionProvider).value != null;
    final fg = scheme.onSurfaceVariant;

    PopupMenuItem<AuthMode> item(AuthMode v, IconData icon, String label) {
      final dim = v == AuthMode.bot && !canSwitch;
      return PopupMenuItem(
        value: v,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: dim ? scheme.outline : null),
          title: Text(
            label,
            style: dim ? TextStyle(color: scheme.outline) : null,
          ),
          trailing: v == mode
              ? Icon(Icons.check, size: 18, color: scheme.primary)
              : null,
        ),
      );
    }

    // Material 在外、菜单按钮在内:水波纹才会被裁成胶囊,而不是方角糊出来。
    return Material(
      color: context.pageControlFill,
      borderRadius: BorderRadius.circular(_height / 2),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<AuthMode>(
        tooltip: '生成方式',
        position: PopupMenuPosition.under,
        onSelected: (v) {
          if (v == mode) return;
          if (v == AuthMode.bot && !canSwitch) {
            hintSnack(context, '暂未开放', icon: Icons.smart_toy_outlined);
            return;
          }
          Haptics.selection();
          ref.read(authModeProvider.notifier).set(v);
        },
        itemBuilder: (_) => [
          item(AuthMode.token, Icons.vpn_key, '直连 Token'),
          item(AuthMode.bot, Icons.smart_toy_outlined, 'Bot 账户'),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
          child: SizedBox(
            height: _height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  bot ? Icons.smart_toy_outlined : Icons.vpn_key,
                  size: 15,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Text(
                  bot ? 'Bot 账户' : '直连 Token',
                  style: context.texts.labelMedium!.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.expand_more, size: 17, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart';
import '../../../core/util/haptics.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../data/tag_favorites.dart';
import '../editor_state.dart';
import 'tag_panel.dart' show TagAddChip;

/// 底栏控件的统一高度:正/负滑块、展开钮、右侧操作胶囊共用一个数。
/// 高度钉死,系统字号放大时各控件不会各长各的。
const double _kBarH = 36;

/// 编辑器底栏:正/负 tab(左)+ 展开钮(中)+ 显示形态切换、撤销(右)。
/// 左右两条胶囊等宽、同底色、同字号,展开钮落在正中;展开钮在栏上方拉出
/// 收藏托盘。
class EditorBottomBar extends ConsumerWidget {
  const EditorBottomBar({
    super.key,
    required this.onToggleMode,
    required this.chipMode,
    required this.trayOpen,
    required this.onToggleTray,
    required this.onInsertFavorite,
  });

  /// 正文形态切换:注音富文本 ⇄ 芯片流。选择记在编辑器设置里。
  final VoidCallback onToggleMode;
  final bool chipMode;

  /// 收藏托盘是否展开。状态放在页面上:返回键要先收托盘。
  final bool trayOpen;
  final VoidCallback onToggleTray;

  /// 托盘里点了一枚收藏:插进正文。
  final void Function(String tag) onInsertFavorite;

  /// 长按收藏 = 移出收藏,提示里可撤销。
  void _removeFavorite(BuildContext context, WidgetRef ref, String tag) {
    Haptics.medium();
    final favs = ref.read(tagFavoritesProvider.notifier);
    final at = favs.remove(tag);
    if (at < 0) return;
    hintSnack(
      context,
      '已取消收藏「$tag」',
      icon: Icons.star_outline_rounded,
      actionLabel: '撤销',
      onAction: () => favs.restore(tag, at),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final st = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final favs = ref.watch(tagFavoritesProvider);

    // 浮卡样式:托盘和底栏同为卡片白,顶边描发丝边
    return Docked(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 托盘:贴顶对齐 + 裁切,展开时从底栏后面升上来
          ClipRect(
            child: AnimatedAlign(
              duration: Motion.fast,
              curve: Motion.standard,
              alignment: Alignment.topCenter,
              heightFactor: trayOpen ? 1 : 0,
              child: Material(
                color: context.editorDock,
                shape: Border(top: BorderSide(color: context.editorDockLine)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  // 卡片高度同词条栏的关联标签;空着也占这一行,收第一枚时不跳
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: favs.isEmpty
                        ? Center(
                            child: Text(
                              '暂无收藏',
                              style: context.texts.labelMedium!.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: favs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) => TagAddChip(
                              tag: favs[i],
                              onTap: () => onInsertFavorite(favs[i]),
                              onLongPress: () =>
                                  _removeFavorite(context, ref, favs[i]),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: context.raisedFill(scheme.surface),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _PosNegToggle(
                        positive: st.activePositive,
                        onChanged: notifier.setActivePositive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TrayButton(open: trayOpen, onTap: onToggleTray),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(_kBarH / 2),
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox(
                          height: _kBarH,
                          child: Row(
                            children: [
                              // 文案/图标报的是**切过去**的那一头(和 web 那颗
                              // Grid/AlignLeft 同款语义),所以不做选中高亮 ——
                              // 高亮加文案会互相打架。
                              Expanded(
                                child: _GroupAction(
                                  icon: chipMode
                                      ? Icons.notes_rounded
                                      : Icons.grid_view_rounded,
                                  label: chipMode ? '文本' : '芯片',
                                  enabled: true,
                                  onTap: onToggleMode,
                                ),
                              ),
                              SizedBox(
                                width: 1,
                                height: 16,
                                child: ColoredBox(color: scheme.outlineVariant),
                              ),
                              Expanded(
                                child: _GroupAction(
                                  icon: Icons.undo,
                                  label: '撤销',
                                  enabled: st.canUndo,
                                  onTap: notifier.undo,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 展开钮:圆形,展开时 + 转成 ×。
class _TrayButton extends StatelessWidget {
  const _TrayButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Tooltip(
      message: open ? '收起' : '展开',
      child: Material(
        color: open ? context.selectedFill : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: _kBarH,
            child: AnimatedRotation(
              turns: open ? 1 / 8 : 0,
              duration: Motion.fast,
              curve: Motion.standard,
              child: Icon(
                Icons.add_rounded,
                size: 22,
                color: open ? context.onSelectedFill : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧胶囊里的一颗操作钮:图标 + 文案,禁用置灰(形态切换 / 撤销共用)。
/// 图标与字号同左侧滑块的分段;放不下时整体缩小。
class _GroupAction extends StatelessWidget {
  const _GroupAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final fg = enabled ? scheme.onSurface : scheme.outlineVariant;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: _kBarH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 正面 / 负面 切换 —— 滑块分段:激活段填充语义色(正面金 / 负面红)并滑动过渡。
/// 宽度由底栏分配,两段各占一半。
class _PosNegToggle extends StatelessWidget {
  const _PosNegToggle({required this.positive, required this.onChanged});

  final bool positive;
  final ValueChanged<bool> onChanged;

  static const double _h = _kBarH;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final thumbColor = positive ? scheme.primary : scheme.error;
    final onThumb = positive ? scheme.onPrimary : scheme.onError;

    return Container(
      height: _h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_h / 2),
      ),
      child: Stack(
        children: [
          // 滑块:填充当前语义色,左右滑动
          AnimatedAlign(
            duration: Motion.medium,
            curve: Motion.emphasized,
            alignment: positive ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: .5,
              child: AnimatedContainer(
                duration: Motion.medium,
                curve: Motion.standard,
                height: _h - 6,
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: BorderRadius.circular((_h - 6) / 2),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _seg(
                  '正面',
                  Icons.check,
                  active: positive,
                  onThumb: onThumb,
                  onTap: () => onChanged(true),
                ),
              ),
              Expanded(
                child: _seg(
                  '负面',
                  Icons.block,
                  active: !positive,
                  onThumb: onThumb,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg(
    String label,
    IconData icon, {
    required bool active,
    required Color onThumb,
    required VoidCallback onTap,
  }) {
    return _SegLabel(
      label: label,
      icon: icon,
      active: active,
      onThumb: onThumb,
      height: _h - 6,
      onTap: onTap,
    );
  }
}

class _SegLabel extends StatelessWidget {
  const _SegLabel({
    required this.label,
    required this.icon,
    required this.active,
    required this.onThumb,
    required this.height,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color onThumb;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final fg = active ? onThumb : scheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

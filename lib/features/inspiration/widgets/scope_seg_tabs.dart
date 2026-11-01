import 'package:flutter/material.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';

/// 「我的 / 公共库」分段:滑动指示器 + 渐变标签(随 [controller] 的动画走),
/// 整段任意位置可点。[compact] 是搜索框旁的窄版:不带图标、不写条数。
class ScopeSegTabs extends StatelessWidget {
  const ScopeSegTabs({
    super.key,
    required this.controller,
    required this.mineCount,
    this.publicCount,
    this.compact = false,
  });

  final TabController controller;
  final int mineCount;

  /// 公共库条数;null = 还没拉到,不显示。
  final int? publicCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 40 : 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.pageControlFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // 视觉层:滑动指示器 + 渐变标签(随 tab 动画重建,无手势)。
            Positioned.fill(
              child: AnimatedBuilder(
                animation: controller.animation!,
                builder: (context, _) {
                  final t = controller.animation!.value.clamp(0.0, 1.0);
                  return LayoutBuilder(
                    builder: (context, c) {
                      final segW = c.maxWidth / 2;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 3,
                            bottom: 3,
                            left: 3 + t * segW,
                            width: segW - 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: context.segThumb,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _label(
                                context,
                                0,
                                Icons.bookmark_outline,
                                compact ? '我的' : '我的 · $mineCount',
                                t,
                              ),
                              _label(context, 1, Icons.public, switch ((
                                compact,
                                publicCount,
                              )) {
                                (true, final int n) => '公共 $n',
                                (true, null) => '公共',
                                (false, final int n) => '公共库 · $n',
                                (false, null) => '公共库',
                              }, t),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // 手势层:稳定不重建,整段任意位置可点。
            Positioned.fill(
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => controller.animateTo(i),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(
    BuildContext context,
    int i,
    IconData icon,
    String label,
    double t,
  ) {
    final scheme = context.scheme;
    final sel = i == 0 ? 1 - t : t;
    final color = Color.lerp(
      scheme.onSurfaceVariant,
      context.segLabel(scheme.primary),
      sel,
    );
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!compact) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: context.texts.labelLarge!.copyWith(
              fontSize: compact ? 14 : null,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

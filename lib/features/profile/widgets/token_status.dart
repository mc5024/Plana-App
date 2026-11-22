import 'package:flutter/material.dart';

import '../../../core/auth/token_probe.dart';
import '../../../core/net/nai_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../stats/stats_providers.dart' show fmtInt;
import '../../../l10n/l10n.dart';

/// 令牌在线校验的状态行(引导页与「账号与接入」共用)。
/// 四态同高:档位+点数+额度 / 查询中 / 失败(令牌被拒或可重试) / 空占位——出现或消失都不改版高。
/// 读数与令牌列表那行(`NaiKeyStatusLine`)同一口径。
Widget tokenStatusLine(
  BuildContext context,
  TokenProbe probe, {
  required VoidCallback onRetry,
}) {
  final scheme = context.scheme;
  if (probe.loading) {
    return Text(
      context.l10n.queryingAccount,
      style: context.texts.labelSmall!.copyWith(color: scheme.outline),
    );
  }
  final s = probe.sub;
  if (s != null) {
    final usage = s.usage;
    return Text(
      [
        naiTierName(s.tier),
        'Anlas ${fmtInt(s.anlas)}',
        // 非 Opus / 读不到时不提,不顶个假的 0%
        if (usage != null) context.l10n.quotaPct(usage.totalPct.round()),
      ].join(' · '),
      // 引导页那格右边还挤着「保存」按钮,折行就破了四态同高
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.texts.bodySmall!.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
  if (probe.failed) {
    return InkWell(
      onTap: onRetry,
      borderRadius: BorderRadius.circular(6),
      child: Text(
        probe.rejected
            ? context.l10n.tokenInvalid
            : context.l10n.accountQueryFailedRetry,
        style: context.texts.labelSmall!.copyWith(color: scheme.error),
      ),
    );
  }
  return Text('', style: context.texts.labelSmall);
}

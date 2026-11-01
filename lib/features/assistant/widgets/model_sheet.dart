/// 选 AI 助手用哪个模型:Plana 后端的渠道,或者自己填的接口。
/// 没有 Bot 授权时后端那组只列免费模型。
///
/// 两组共用**同一种行**:左边一个图标、中间完整型号名、右边留给「编辑」。
/// 不写 `short_label`(「GLM」「豆包」这种简称看不出是哪一代),也不写线路说明
/// (commandcode / vertex / 火山方舟)—— 选哪条线不是用户的决定。
///
/// 「推荐」是后端标的([AgentModelChoice.recommended]),不在 app 里写死 ——
/// 哪个渠道当下稳、当下便宜只有后端知道,写死就得跟着发版。
///
/// **选中态放在左边**(图标换成对勾 + 整行染色),右边空出来给「编辑」。两样都挤在
/// 右边的话,想选中却点到编辑是迟早的事 —— 而这个弹层九成时候是来选的,
/// 不是来改配置的。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/setting_row.dart';
import '../../generate/widgets/common.dart' show dropFocusSoon;
import '../agent_model.dart';
import '../custom_endpoint.dart';
import 'endpoint_sheet.dart';

Future<void> showModelSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // 抓手、圆角、关闭都由 SettingSheet 自己画(与编辑器/助手设置同一套)
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (_) => const _ModelSheet(),
  );
  // 只是来看一眼模型,别顺手把软键盘顶出来
  dropFocusSoon();
}

class _ModelSheet extends ConsumerWidget {
  const _ModelSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(agentModelsProvider);
    final currentKey = ref.watch(assistantModelProvider)?.key ?? '';
    final endpoints = ref.watch(customEndpointsProvider).value ?? const [];
    // 没有 Bot 授权时只列免费的;后端一条免费的都没有就整组不列
    final authorized = ref.watch(assistantBotAuthorizedProvider);
    List<AgentModelChoice> shown(AgentModelList l) =>
        authorized ? l.choices : l.free;
    final hidden = !authorized && async.hasValue && shown(async.value!).isEmpty;

    return SettingSheet(
      title: '选择模型',
      children: [
        if (!hidden) ...[
          settingSection(context, authorized ? 'Plana 后端' : '免费模型'),
          switch (async) {
            AsyncData(:final value) when shown(value).isNotEmpty => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in shown(value))
                  _row(
                    context,
                    icon: Icons.cloud_outlined,
                    title: c.name,
                    badge: c.recommended ? '推荐' : null,
                    selected: c.key == currentKey,
                    onTap: () => _pick(context, ref, c.key),
                  ),
              ],
            ),
            AsyncError(:final error) => _note(
              context,
              '拿不到渠道列表:$error',
              onRetry: () => ref.invalidate(agentModelsProvider),
            ),
            AsyncData() => _note(
              context,
              '后端没配可选渠道。',
              onRetry: () => ref.invalidate(agentModelsProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
        settingSection(context, '我的接口'),
        for (final e in endpoints)
          _row(
            context,
            icon: Icons.bolt_outlined,
            title: e.displayName,
            // 副行写格式和模型,不写地址 —— 地址又长又不是你要确认的东西
            subtitle: e.usable
                ? '${agentApiFormatLabel(e.format)} · ${e.model}'
                : '还没填全,点一下去补',
            dim: !e.usable,
            selected: e.usable && customModelKey(e.id) == currentKey,
            onTap: () => e.usable
                ? _pick(context, ref, customModelKey(e.id))
                : showEndpointSheet(context, source: e),
            onEdit: () => showEndpointSheet(context, source: e),
          ),
        _row(
          context,
          icon: Icons.add,
          title: '添加接口',
          accent: true,
          onTap: () => showEndpointSheet(context),
        ),
      ],
    );
  }

  void _pick(BuildContext context, WidgetRef ref, String key) {
    ref.read(assistantModelPrefProvider.notifier).set(key);
    Navigator.pop(context);
  }

  /// 一行。选中时左边图标换成对勾并整行染色 —— 一列小对勾要挨个找,
  /// 染色那行扫一眼就看见。
  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    String? badge,
    bool selected = false,
    bool dim = false,
    bool accent = false,
    VoidCallback? onEdit,
  }) {
    final scheme = context.scheme;
    final solid = selected && context.skin.float;
    final fg = solid
        ? scheme.onPrimary
        : selected || accent
        ? scheme.primary
        : (dim ? scheme.outline : null);
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: context.skin.float
          ? scheme.primary
          : scheme.primaryContainer.withValues(alpha: .35),
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      leading: Icon(
        selected ? Icons.check_circle : icon,
        size: 21,
        color: selected ? fg : (dim ? scheme.outline : fg),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodyLarge!.copyWith(
                fontWeight: selected || accent
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: solid
                    ? scheme.onPrimary.withValues(alpha: .2)
                    : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                badge,
                style: context.texts.labelSmall!.copyWith(
                  color: solid ? scheme.onPrimary : scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall!.copyWith(
                color: solid
                    ? scheme.onPrimary.withValues(alpha: .8)
                    : scheme.outline,
              ),
            ),
      trailing: onEdit == null
          ? null
          : IconButton(
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: solid ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onPressed: onEdit,
            ),
    );
  }

  Widget _note(
    BuildContext context,
    String text, {
    required VoidCallback onRetry,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: context.texts.bodySmall!.copyWith(
              color: context.scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

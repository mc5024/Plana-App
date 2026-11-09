/// 第一次打开 AI 助手时的引导:确认 AI 能查哪些资料,顺手把几项使用习惯定下来。
///
/// 两页:资料库范围 → 使用习惯。一页塞不下,挤在一起时整个弹窗顶满屏幕。
///
/// 资料库范围决定你收藏的画师串和角色会不会发出去,不该在用户不知道的时候就生效,
/// 所以要点过「开始使用」才算走完;走完之前每次进 AI 页都会弹。
/// 这里定的几项之后都能在「助手设置」里改,两边用的是同一份设置和同样的文字。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/setting_row.dart';
import '../agent_model.dart' show assistantBotAuthorizedProvider;
import '../assistant_settings.dart';

Future<void> showAssistantIntro(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _IntroDialog(),
);

class _IntroDialog extends ConsumerStatefulWidget {
  const _IntroDialog();

  @override
  ConsumerState<_IntroDialog> createState() => _IntroDialogState();
}

class _IntroDialogState extends ConsumerState<_IntroDialog> {
  /// 先在这份草稿上改,点「开始使用」才一起存 —— 中途退出不留半截设置。
  late AssistantSettings _draft =
      ref.read(assistantSettingsProvider).value ?? const AssistantSettings();

  /// 0 = 资料库范围,1 = 使用习惯。
  int _page = 0;

  void _edit(AssistantSettings Function(AssistantSettings) change) =>
      setState(() => _draft = change(_draft));

  Future<void> _done(bool authorized) async {
    final scope = effectiveLibraryScope(
      _draft.libraryScope,
      botAuthorized: authorized,
    );
    await ref
        .read(assistantSettingsProvider.notifier)
        .patch(
          (o) => o.copyWith(
            libraryScope: scope,
            autoGenerate: _draft.autoGenerate,
            inlineImage: _draft.inlineImage,
            autoImport: _draft.autoImport,
            introVersion: kAssistantIntroVersion,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _scopePage(bool authorized) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingSection(context, '资料库范围'),
      RadioGroup<LibraryScope>(
        groupValue: effectiveLibraryScope(
          _draft.libraryScope,
          botAuthorized: authorized,
        ),
        onChanged: (v) {
          if (v != null) _edit((o) => o.copyWith(libraryScope: v));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in LibraryScope.values)
              RadioListTile<LibraryScope>(
                value: o,
                enabled: libraryScopeAllowed(o, botAuthorized: authorized),
                title: Text(libraryScopeLabel(o)),
                subtitle: Text(
                  libraryScopeAllowed(o, botAuthorized: authorized)
                      ? libraryScopeDesc(o)
                      : '暂未开放',
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _habitPage() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingSection(context, '使用习惯'),
      SettingRow(
        icon: Icons.bolt_outlined,
        title: '生成提示词后自动出图',
        desc: '提示词生成完成后立即开始出图',
        value: _draft.autoGenerate,
        onChanged: (v) => _edit((o) => o.copyWith(autoGenerate: v)),
      ),
      SettingRow(
        icon: Icons.image_outlined,
        title: '在对话内显示图片',
        desc: '生成的图片显示在对话内,同时保存至图库',
        value: _draft.inlineImage,
        onChanged: (v) => _edit((o) => o.copyWith(inlineImage: v)),
      ),
      SettingRow(
        icon: Icons.draw_outlined,
        title: '自动写入创作页',
        desc: '生成的提示词自动写回创作页,无需手动导入',
        value: _draft.autoImport,
        onChanged: (v) => _edit((o) => o.copyWith(autoImport: v)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final authorized = ref.watch(assistantBotAuthorizedProvider);
    return PopScope(
      canPop: false,
      // 第二页按返回回到第一页;第一页按返回不关 —— 点过「开始使用」才算走完
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page == 1) setState(() => _page = 0);
      },
      child: AlertDialog(
        // 边距比默认的 40 小,弹窗宽一点,开关那几行的标题少折一次行
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Row(
          children: [
            const Expanded(child: Text('开始使用 AI 助手')),
            Text(
              '${_page + 1} / 2',
              style: context.texts.labelMedium!.copyWith(
                color: context.scheme.outline,
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.only(top: 8),
        content: SingleChildScrollView(
          // 两页叠着放、都参与排版:高度按高的那页算,翻页时弹窗不跟着伸缩。
          // 翻页是横向的淡入淡出加一小段位移,前面的页往左退、后面的页从右边进。
          child: ClipRect(
            child: Stack(
              children: [
                for (final (i, page) in [
                  _scopePage(authorized),
                  _habitPage(),
                ].indexed)
                  _IntroPage(shift: i - _page, child: page),
              ],
            ),
          ),
        ),
        actions: [
          if (_page == 0)
            FilledButton(
              onPressed: () => setState(() => _page = 1),
              child: const Text('下一步'),
            )
          else ...[
            TextButton(
              onPressed: () => setState(() => _page = 0),
              child: const Text('上一步'),
            ),
            FilledButton(
              onPressed: () => _done(authorized),
              child: const Text('开始使用'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 引导里的一页。[shift] = 相对当前页的位置:0 是当前页,负数在左边,正数在右边。
///
/// 不在当前的那页照样排版(弹窗高度要按两页里高的算),只是透明、点不到、
/// 读屏也跳过。
class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.shift, required this.child});

  final int shift;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final active = shift == 0;
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: ExcludeFocus(
          excluding: !active,
          child: AnimatedOpacity(
            duration: Motion.medium,
            curve: Motion.standard,
            opacity: active ? 1 : 0,
            child: AnimatedSlide(
              duration: Motion.medium,
              curve: Motion.emphasized,
              offset: Offset(shift * .15, 0),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

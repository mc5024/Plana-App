import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/nai_keys.dart';
import '../../core/net/nai_client.dart';
import '../../core/net/nai_key_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../generate/widgets/common.dart' show confirmDialog;
import '../stats/stats_providers.dart' show fmtInt;
import 'widgets/token_add_sheet.dart';

/// 令牌管理(账号页二级)。一把一块:单选钮 + 名字 + 账户读数 + 两个勾选项。
///
/// **一个主账号 + 若干副账号**:主账号强制参与出图并花点数(那些「一次只能对
/// 一个账号」的操作也认它),副账号各自决定要不要参与并发生成、要不要花点数。
/// 换主账号 = 点别人那整块。改名和删除各一颗小图标,不套菜单。
class TokenManagePage extends ConsumerStatefulWidget {
  const TokenManagePage({super.key});

  @override
  ConsumerState<TokenManagePage> createState() => _TokenManagePageState();
}

class _TokenManagePageState extends ConsumerState<TokenManagePage> {
  Future<void> _add() async {
    if (await showTokenAddSheet(context) && mounted) Haptics.selection();
  }

  /// 拨副账号的某个选项(主账号没有开关,拨不到这里)。
  Future<void> _toggle(NaiKey k, String flag, bool on) async {
    await ref
        .read(naiKeysStoreProvider.notifier)
        .setFlags(
          k.id,
          forGenerate: flag == 'gen' ? on : null,
          usePoints: flag == 'pts' ? on : null,
        );
    if (mounted) Haptics.selection();
  }

  Future<void> _makePrimary(String id) async {
    await ref.read(naiKeysStoreProvider.notifier).makePrimary(id);
    if (mounted) Haptics.selection();
  }

  Future<void> _rename(NaiKey k) async {
    final ctrl = TextEditingController(text: k.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: naiKeyTail(k.token), // 留空就按尾号显示
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 清空即回到尾号显示,所以空串也照写(不像别处那样要求非空)
    if (name != null) {
      await ref.read(naiKeysStoreProvider.notifier).rename(k.id, name);
    }
  }

  Future<void> _delete(NaiKey k) async {
    final ok = await confirmDialog(
      context,
      title: '删除令牌',
      message: '将从本机删除「${naiKeyTitle(k)}」,直连能同时出的张数也会少一路。',
      confirmLabel: '删除',
    );
    if (!ok) return;
    await ref.read(naiKeysStoreProvider.notifier).remove(k.id);
    if (mounted) Haptics.medium();
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(naiKeysStoreProvider).value ?? const <NaiKey>[];
    final full = keys.length >= kMaxNaiKeys;

    return Scaffold(
      appBar: AppBar(
        title: const Text('令牌管理'),
        actions: [
          IconButton(
            onPressed: full ? null : _add,
            icon: const Icon(Icons.add),
            tooltip: full ? '最多 $kMaxNaiKeys 把' : '添加令牌',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: keys.isEmpty
          ? _Empty(onAdd: _add)
          // 整列共一组:选中谁谁就是主账号。放在 ListView 外面而不是每行自己
          // 管 groupValue —— 那样每行都要知道别人是谁。
          : RadioGroup<String>(
              groupValue: naiPrimaryKey(keys)?.id,
              onChanged: (id) {
                if (id != null) _makePrimary(id);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                children: [
                  for (var i = 0; i < keys.length; i++) ...[
                    _KeyTile(
                      k: keys[i],
                      primary: keys[i].primary,
                      onToggle: (f, on) => _toggle(keys[i], f, on),
                      onPrimary: () => _makePrimary(keys[i].id),
                      onRename: () => _rename(keys[i]),
                      onDelete: () => _delete(keys[i]),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
    );
  }
}

/// 末行定高:主账号那行只有一句说明,副账号那行是两个勾选项,不钉死的话
/// 换主账号时整块会一涨一缩。
const _kOptionRowHeight = 34.0;

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.vpn_key_outlined,
              size: 40,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有令牌',
              style: context.texts.bodyLarge!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '存多把可以同时出多张 —— NAI 按账号限流,一把只能跑一条',
              textAlign: TextAlign.center,
              style: context.texts.labelSmall!.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加令牌'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一把令牌一块:
///   ◉ 名字 [主账号] ………… ✎ 🗑
///   尾号 · 档位 · Anlas · 额度
///   ☑ 并发生成   ☑ 允许花点数
///
/// 整块可点 = 设为主账号。主账号那块**没有开关**,只有一句「生成与点数都用它」
/// —— 它是一定会被用到的那个,给它「不参与生成」的开关就自相矛盾了。
/// 副账号才有两个勾选项:要不要参与并发生成、要不要花自己的点数。
class _KeyTile extends ConsumerWidget {
  const _KeyTile({
    required this.k,
    required this.primary,
    required this.onToggle,
    required this.onPrimary,
    required this.onRename,
    required this.onDelete,
  });

  final NaiKey k;

  /// 是不是主账号(跟排第几无关,见 [NaiKey.primary])。三个身份合成一个标记:
  /// ①「一次只能对一个账号」的操作(点数读数、超分、标签预览、续期)认它;
  /// ② 出图取 Key 时它排头,点数**先被花**;③ 必定参与出图、必定可花点数。
  final bool primary;

  /// (哪个选项, 新值)。选项名:gen / pts。
  final void Function(String flag, bool on) onToggle;

  /// 点整块 = 把这把设为主账号(已经是主账号时不接手势)。
  final VoidCallback onPrimary;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final named = k.label.trim().isNotEmpty;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standard,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        // 描边两态同宽,只变色 —— 变宽度会让整块内容跟着抖一下。
        border: Border.all(
          color: primary
              ? scheme.primary.withValues(alpha: .45)
              : Colors.transparent,
        ),
      ),
      // 整卡可点 = 设为主账号。内边距搁在 InkWell **里面**,水波才铺满整块
      // (搁外层的话右下角会短一截)。改名/删除两颗按钮和两个勾选项各有自己的
      // 点击区,按在它们身上时子级先接手,不会误切主账号。
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: primary ? null : onPrimary,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Row(
                          children: [
                            // 单选钮:主账号是这一列里**只能有一个**的东西,
                            // 正是单选的语义。分组由外层 RadioGroup 管。
                            IgnorePointer(
                              child: Radio<String>(
                                value: k.id,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // 完全不参与的(副账号取消了生成)压暗:它还在列表里,
                            // 但一眼要能看出「这把现在不干活」。
                            Flexible(
                              child: AnimatedOpacity(
                                duration: Motion.fast,
                                opacity: primary || k.forGenerate ? 1 : .45,
                                child: Text(
                                  naiKeyTitle(k),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: named
                                      ? context.texts.bodyMedium!.copyWith(
                                          fontWeight: FontWeight.w600,
                                        )
                                      : mono(context, size: 13),
                                ),
                              ),
                            ),
                            // 主账号明标出来:圆钮只说明「选中的是它」,说不出这个
                            // 身份意味着什么,而它跟副账号的差别(强制生成 + 强制
                            // 花点数)是实打实的。
                            AnimatedSize(
                              duration: Motion.fast,
                              curve: Motion.standard,
                              child: AnimatedOpacity(
                                duration: Motion.fast,
                                opacity: primary ? 1 : 0,
                                child: primary
                                    ? Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            '主账号',
                                            style: context.texts.labelSmall!
                                                .copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      scheme.onPrimaryContainer,
                                                ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TileIcon(
                      icon: Icons.edit_outlined,
                      tooltip: '重命名',
                      color: scheme.outline,
                      onPressed: onRename,
                    ),
                    _TileIcon(
                      icon: Icons.delete_outline,
                      tooltip: '删除',
                      color: scheme.error,
                      onPressed: onDelete,
                    ),
                  ],
                ),
                Padding(
                  // 左边缩进对齐名字(让开那颗单选钮)
                  padding: const EdgeInsets.fromLTRB(32, 0, 4, 6),
                  child: AnimatedOpacity(
                    duration: Motion.fast,
                    opacity: primary || k.forGenerate ? 1 : .45,
                    child: NaiKeyStatusLine(
                      token: k.token,
                      // 起过名的才补尾号:没起名时标题本身就是尾号,写两遍是复述。
                      prefix: named ? naiKeyTail(k.token) : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 28, right: 4),
                  // 定高:主账号那行(一句说明)天生比副账号那行(两个勾选项)矮,
                  // 不钉死的话换主账号时整块会一涨一缩。钉死之后只剩内容交叉淡入。
                  child: SizedBox(
                    height: _kOptionRowHeight,
                    child: AnimatedSwitcher(
                      duration: Motion.fast,
                      child: primary
                          // 主账号没有开关:它是「一定会被用到」的那个 —— 点数读数、
                          // 超分、预览、续期都认它,再给个「不参与生成」的开关就自相
                          // 矛盾了。想换成别的号,去选别人那块。
                          ? Row(
                              key: const ValueKey('primary'),
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 14,
                                  color: scheme.outline,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '生成与点数都用它,不可关闭',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.labelMedium!.copyWith(
                                      color: scheme.outline,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('secondary'),
                              children: [
                                Expanded(
                                  child: _CheckOption(
                                    label: '并发生成',
                                    value: k.forGenerate,
                                    enabled: true,
                                    onChanged: (v) => onToggle('gen', v),
                                  ),
                                ),
                                Expanded(
                                  child: _CheckOption(
                                    label: '允许花点数',
                                    value: k.forGenerate && k.usePoints,
                                    // 都不生成了,花不花点数无从谈起
                                    enabled: k.forGenerate,
                                    onChanged: (v) => onToggle('pts', v),
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
    );
  }
}

/// 一个勾选项:复选框 + 文字,整块可点。
///
/// 用 Checkbox 而不是 Switch:Switch 是「开关某个东西」,Checkbox 是「勾选一个
/// 选项」—— 副账号要不要参与,正是选项。
class _CheckOption extends StatelessWidget {
  const _CheckOption({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;

  /// 可不可点;不可点时整项灰掉(如「不出图就无所谓花不花点数」)。
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? scheme.onSurfaceVariant
                        : scheme.outline.withValues(alpha: .6),
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

/// 标题行右侧那两颗小图标按钮,尺寸统一。
class _TileIcon extends StatelessWidget {
  const _TileIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: color,
      padding: EdgeInsets.zero,
    ),
  );
}

/// 一把 Key 的账户读数:档位 · Anlas · V5 额度。查询中/失败都占同一行位。
class NaiKeyStatusLine extends ConsumerWidget {
  const NaiKeyStatusLine({super.key, required this.token, this.prefix});

  final String token;

  /// 排在读数最前面的一段(这里放令牌尾号);null 则不写。
  final String? prefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final small = context.texts.labelSmall!;
    final async = ref.watch(naiKeyStatusProvider(token));
    return async.when(
      loading: () =>
          Text('查询账户状态…', style: small.copyWith(color: scheme.outline)),
      error: (_, _) => InkWell(
        onTap: () => ref.invalidate(naiKeyStatusProvider(token)),
        borderRadius: BorderRadius.circular(6),
        child: Text('状态查询失败,点按重试', style: small.copyWith(color: scheme.error)),
      ),
      data: (s) {
        final usage = s.usage;
        return Text(
          [
            ?prefix,
            naiTierName(s.tier),
            'Anlas ${fmtInt(s.anlas)}',
            // V5 额度只有拿得到才写:官方没承诺过这块字段,读不到就干脆不提 ——
            // 顶个假的 0% 上去比不显示糟得多。
            if (usage != null) '额度 ${usage.batteryPct.round()}%',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: small.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}

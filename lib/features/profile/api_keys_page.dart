import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/haptics.dart';
import '../generate/widgets/common.dart' show confirmDialog, hintSnack;

/// API 密钥(账号页二级,Bot):在自己的 NovelAI 客户端里填本站地址 + 这里的
/// 密钥,就能拿 Bot 账户出图,费用和 App 里一样从钱包扣。
///
/// 和网页个人中心、bot 私聊「API密钥」管的是同一份:每人最多 3 把,完整密钥只在
/// 新建那一刻给一次(服务端只存哈希),丢了只能撤销重建。
class ApiKeysPage extends ConsumerStatefulWidget {
  const ApiKeysPage({super.key});

  @override
  ConsumerState<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends ConsumerState<ApiKeysPage> {
  ApiKeyList? _list;
  String? _error;

  /// 新建 / 撤销请求在路上:按钮先灰掉,免得连点建出两把。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<String> _session() async {
    final s = await ref.read(botSessionProvider.future);
    if (s == null) throw BackendException('暂未开放');
    return s.sessionId;
  }

  /// 拉列表。失败时旧列表留着,只在还一把都没拿到时整页报错。
  Future<void> _load() async {
    try {
      final list = await ref
          .read(backendClientProvider)
          .apiKeys(await _session());
      if (!mounted) return;
      setState(() {
        _list = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is BackendException ? e.message : '读取失败,下拉重试');
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    Haptics.selection();
    hintSnack(context, '已复制$what', icon: Icons.check_circle_outline);
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建密钥'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            isDense: true,
            labelText: '名字(可不填)',
            hintText: '比如用在哪个客户端',
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
            child: const Text('新建'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final made = await ref
          .read(backendClientProvider)
          .createApiKey(await _session(), name: name.trim());
      if (!mounted) return;
      Haptics.medium();
      await _load();
      if (mounted) await _showCreated(made);
    } catch (e) {
      if (mounted) {
        hintSnack(
          context,
          e is BackendException ? e.message : '新建失败,稍后再试',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 完整密钥只这一次:弹窗里给全串和复制,关掉就再也看不到了。
  Future<void> _showCreated(CreatedApiKey made) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final scheme = context.scheme;
        return AlertDialog(
          title: const Text('密钥已新建'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '完整密钥只显示这一次,关掉就看不到了。先复制下来填进客户端;丢了只能撤销再建一把。',
                style: context.texts.bodySmall!.copyWith(color: scheme.error),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  made.key,
                  style: mono(context, size: 12.5),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _copy(made.key, '密钥'),
              icon: const Icon(Icons.copy, size: 17),
              label: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我已保存'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _revoke(ApiKeyInfo k) async {
    final ok = await confirmDialog(
      context,
      title: '撤销密钥',
      message: '撤销后,填着「${_title(k)}」的客户端马上就用不了了。',
      confirmLabel: '撤销',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(backendClientProvider)
          .revokeApiKey(await _session(), k.id);
      if (!mounted) return;
      Haptics.medium();
      hintSnack(context, '已撤销', icon: Icons.check_circle_outline);
    } catch (e) {
      if (mounted) {
        hintSnack(
          context,
          e is BackendException ? e.message : '撤销失败,稍后再试',
          icon: Icons.error_outline,
        );
      }
    } finally {
      // 撤销失败也重拉一遍:404 往往是别处(网页 / bot)已经撤过了
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _title(ApiKeyInfo k) =>
      k.name.trim().isEmpty ? k.prefix : k.name;

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final canAdd = list != null && !list.full && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 密钥'),
        actions: [
          IconButton(
            onPressed: canAdd ? _create : null,
            icon: const Icon(Icons.add),
            tooltip: list != null && list.full ? '最多 ${list.max} 把' : '新建密钥',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            if (list == null && _error == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (list == null)
              _Message(text: _error!, onRetry: _load)
            else ...[
              _UsageCard(
                baseUrl: list.baseUrl,
                onCopy: () => _copy(list.baseUrl, '地址'),
              ),
              const SizedBox(height: 12),
              if (list.keys.isEmpty)
                _Empty(onAdd: canAdd ? _create : null)
              else
                for (final k in list.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _KeyTile(
                      k: k,
                      title: _title(k),
                      onRevoke: _busy ? null : () => _revoke(k),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  '${list.keys.length} / ${list.max} 把 · 网页个人中心和 Bot 私聊「API密钥」管的是同一份',
                  style: context.texts.labelSmall!.copyWith(
                    color: context.scheme.outline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 怎么用:客户端里填哪两样,以及钱从哪扣。
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.baseUrl, required this.onCopy});

  final String baseUrl;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final small = context.texts.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Lifted(
      radius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用自己的 NovelAI 客户端出图',
                style: context.texts.labelMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '在客户端里把 API 地址换成下面这个、令牌换成这里新建的密钥。'
                '费用和 App 里一样从钱包扣,需要开着「中转出图」、钱包有余额。',
                style: small,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(context, size: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: baseUrl.isEmpty ? null : onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制地址',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一把密钥一块:名字 + 前缀,下面一行创建 / 最后使用时间,右边撤销。
class _KeyTile extends StatelessWidget {
  const _KeyTile({
    required this.k,
    required this.title,
    required this.onRevoke,
  });

  final ApiKeyInfo k;
  final String title;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final named = k.name.trim().isNotEmpty;
    final last = k.lastUsedAt;
    return Lifted(
      radius: BorderRadius.circular(14),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            children: [
              Icon(
                Icons.key_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: named
                                ? context.texts.bodyMedium!.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )
                                : mono(context, size: 13),
                          ),
                        ),
                        if (named) ...[
                          const SizedBox(width: 8),
                          Text(
                            k.prefix,
                            style: mono(
                              context,
                              size: 11.5,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '创建 ${ApiKeyInfo.shortTime(k.createdAt)} · '
                      '${last == null ? '还没用过' : '最后使用 ${ApiKeyInfo.shortTime(last)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall!.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onRevoke,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('撤销'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.key_off_outlined, size: 36, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Text(
            '还没有密钥',
            style: context.texts.bodyLarge!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建密钥'),
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
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 36,
            color: scheme.outlineVariant,
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

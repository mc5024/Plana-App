import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/nai_credential_login.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/net/nai_client.dart';
import '../../../core/net/nai_proxy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/haptics.dart';
import '../../../l10n/l10n.dart';

/// 邮箱密码登录弹层:本机派生 access key → 换 30 天 JWT → 存 token +
/// 续期凭证。成功 pop 出 JWT(调用方回填令牌输入框,顺带触发档位查询);
/// 取消返回 null。引导页与「账号与接入」共用。
Future<String?> showCredentialLoginSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CredentialLoginSheet(),
    );

class _CredentialLoginSheet extends ConsumerStatefulWidget {
  const _CredentialLoginSheet();

  @override
  ConsumerState<_CredentialLoginSheet> createState() =>
      _CredentialLoginSheetState();
}

class _CredentialLoginSheetState extends ConsumerState<_CredentialLoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(_onEdit);
    _password.addListener(_onEdit);
  }

  void _onEdit() => setState(() => _error = null);

  @override
  void dispose() {
    _email
      ..removeListener(_onEdit)
      ..dispose();
    _password
      ..removeListener(_onEdit)
      ..dispose();
    super.dispose();
  }

  bool get _ready =>
      _email.text.trim().contains('@') && _password.text.isNotEmpty && !_busy;

  Future<void> _login() async {
    if (!_ready) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 密码只进派生,不落盘;留下的是 accessKey(续期凭证)+ JWT。
      // 内部按官网同款顺序尝试多种邮箱大小写形态。
      // 邮箱登录是官方那条流程(第三方中转不发 NAI 账号),固定打官方(开了代理经代理)。
      final (jwt, key) = await naiCredentialLoginFlow(
        _email.text,
        _password.text,
        proxy: ref.read(naiProxyProvider),
      );
      // 续期凭证跟着这把 Key 一起存 —— 日后续期只会换它自己那把的令牌。
      await ref.read(tokenProvider.notifier).save(jwt, accessKey: key);
      if (!mounted) return;
      Haptics.selection();
      Navigator.of(context).pop(jwt);
    } on NaiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.loginFailed('$e');
      });
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) {
    final scheme = context.scheme;
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      hintText: hint,
      hintStyle: TextStyle(color: scheme.outline),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      // 键盘弹起时把内容顶上去
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.naiAccountLogin,
            style: context.texts.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.passwordLocalHint,
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: _dec(context.l10n.email),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _login(),
            decoration: _dec(
              context.l10n.password,
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  size: 20,
                ),
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: context.texts.labelSmall!.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _ready ? _login : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(23),
              ),
            ),
            child: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : Text(context.l10n.login),
          ),
        ],
      ),
    );
  }
}

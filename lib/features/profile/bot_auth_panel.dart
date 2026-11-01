import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_mode.dart';
import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/theme/app_theme.dart';
import '../generate/widgets/common.dart' show hintSnack;
import '../../core/util/haptics.dart';

/// Bot 绑定码授权面板(内嵌在「账号与接入」的 Bot 卡里):
/// 取 6 位码 → 用户在 QQ 发给 Bot → 本面板轮询 → 存会话并置接入方式。
class BotAuthPanel extends ConsumerStatefulWidget {
  const BotAuthPanel({super.key, required this.idleBuilder});

  /// 未取码时显示的内容:`start` 发起取码(取码中为 null),`loading` 取码中。
  final Widget Function(VoidCallback? start, bool loading) idleBuilder;

  @override
  ConsumerState<BotAuthPanel> createState() => _BotAuthPanelState();
}

class _BotAuthPanelState extends ConsumerState<BotAuthPanel> {
  Timer? _timer;
  String? _code;
  int _secondsLeft = 0;
  int _tick = 0;
  bool _loading = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _getCode() async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(backendClientProvider).authGenerate();
      if (!mounted) return;
      setState(() {
        _code = r.code;
        _secondsLeft = r.expiresIn;
        _tick = 0;
        _loading = false;
      });
      _startTimer();
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      hintSnack(context, e.message, icon: Icons.error_outline);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) return;
      _tick++;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 999));
      if (_secondsLeft <= 0) {
        t.cancel();
        setState(() => _code = null); // 过期 → 回到未取码状态
        return;
      }
      if (_tick % 3 == 0) await _poll(); // 每 3 秒轮询一次
    });
  }

  Future<void> _poll() async {
    final code = _code;
    if (code == null) return;
    try {
      final r = await ref.read(backendClientProvider).authCheck(code);
      if (!mounted || _code != code) return;
      if (r.verified && r.sessionId != null && r.sessionId!.isNotEmpty) {
        _timer?.cancel();
        await _onAuthorized(r.sessionId!);
      }
    } on BackendException catch (_) {
      // 单次轮询失败静默,下个周期再试
    }
  }

  Future<void> _onAuthorized(String sessionId) async {
    // 拿归属/过期(best-effort),存会话,切模式
    int? expiresAtMs;
    String? botUserId;
    try {
      final v = await ref.read(backendClientProvider).validate(sessionId);
      if (v.valid) {
        expiresAtMs = v.expiresAtMs;
        botUserId = v.botUserId;
      }
    } catch (_) {}
    await ref
        .read(botSessionProvider.notifier)
        .save(
          BotSession(
            sessionId: sessionId,
            botUserId: botUserId,
            expiresAtMs: expiresAtMs,
          ),
        );
    await ref.read(authModeProvider.notifier).set(AuthMode.bot);
    if (!mounted) return;
    setState(() => _code = null);
    Haptics.medium();
    hintSnack(context, 'Bot 授权成功', icon: Icons.verified_outlined);
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final code = _code;
    if (code == null) {
      return widget.idleBuilder(_loading ? null : _getCode, _loading);
    }
    return _CodePanel(
      code: code,
      secondsLeftText: _fmt(_secondsLeft),
      onCopy: () {
        // 复制完整指令(含 web授权 前缀),粘贴到 QQ 直接发送即可
        Clipboard.setData(ClipboardData(text: 'web授权$code'));
        hintSnack(context, '已复制,粘贴发给 Bot', icon: Icons.check_circle_outline);
      },
      onCancel: () {
        _timer?.cancel();
        setState(() => _code = null);
      },
    );
  }
}

/// 授权码面板:大号码 + 倒计时 + 复制 + 等待指示。
class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.code,
    required this.secondsLeftText,
    required this.onCopy,
    required this.onCancel,
  });

  final String code;
  final String secondsLeftText;
  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              children: [
                Text(
                  '复制指令发送给 Bot',
                  style: context.texts.bodySmall!.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: .8),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  code,
                  style: mono(
                    context,
                    size: 34,
                    weight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                  ).copyWith(letterSpacing: 6),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      secondsLeftText,
                      style: context.texts.labelLarge!.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    TextButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.content_copy, size: 15),
                      label: const Text('复制指令'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '等待 Bot 验证…',
              style: context.texts.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
      ],
    );
  }
}

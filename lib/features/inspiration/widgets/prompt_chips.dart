import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/editor_theme.dart' show EditorPalette;
import '../../editor/data/tag_translation_service.dart';
import '../../editor/editor_models.dart' show Tok, fmtMult, parseToks;

/// 一段提示词:可选段标签(多角色词条的「角色 N」)+ 原文。
typedef PromptSection = ({String? label, String body});

/// 只读提示词芯片流:观感对齐编辑器芯片模式(同一条权重深浅曲线、同款
/// 圆角边框、英文+译文双行),但纯展示不可点。法典翻面与灵感页详情共用。
///
/// 译文与编辑器同一条链路:[parseToks] 解析时先吃共享缓存/离线词库,
/// 缺的批量丢给 [TagTranslationService](增强补全模式才联网),到货即刷新。
/// 调用方另有更合适的译名(法典源自带的对照表)时从 [preferredTrans] 垫在最前面。
class PromptChips extends ConsumerStatefulWidget {
  const PromptChips({
    super.key,
    required this.sections,
    this.preferredTrans,
    this.preferredTransLoading = false,
  });

  PromptChips.single(String body, {Key? key})
    : this(key: key, sections: [(label: null, body: body)]);

  final List<PromptSection> sections;

  /// 先于 app 自有译名链路查的一层(入参是芯片上的名字),查不到才轮到共享
  /// 缓存 / 离线词库 / 后端。传方法 tear-off:同一对象的 tear-off 彼此 `==`,
  /// 外层重建不会触发重新分词。
  final String? Function(String name)? preferredTrans;

  /// [preferredTrans] 那层还在路上:缺译名的芯片先画加载态,也先不问后端 ——
  /// 表一到多半就有了,别白打一轮 LLM。
  final bool preferredTransLoading;

  @override
  ConsumerState<PromptChips> createState() => _PromptChipsState();
}

class _PromptChipsState extends ConsumerState<PromptChips>
    with SingleTickerProviderStateMixin {
  TagTranslationService? _svc;

  /// 解析结果缓存:这棵子树可能被外层动画频繁重建,不能每次重新分词。
  /// `trans` 是最终显示的译名([PromptChips.preferredTrans] 优先,否则 `Tok.trans`)。
  late List<({String? label, List<({Tok tok, String? trans})> toks})> _parsed;

  /// 译文加载态的脉动:整片芯片共用一个 ticker,且只在**真有词在等**时才转
  /// (编辑器芯片流同款;没人等还空转 = 白烧一整屏的帧)。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );
  bool _pulsing = false;

  @override
  void initState() {
    super.initState();
    _parse(); // 服务在 build 里才接上(要跟着 provider 换代),首帧先出词
  }

  @override
  void didUpdateWidget(covariant PromptChips old) {
    super.didUpdateWidget(old);
    final reparse =
        !listEquals(old.sections, widget.sections) ||
        old.preferredTrans != widget.preferredTrans;
    if (reparse) _parse();
    if (reparse || old.preferredTransLoading != widget.preferredTransLoading) {
      _requestMissing();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    // removeListener 允许晚于服务本体 dispose(provider 换代时先死的是它)
    _svc?.removeListener(_onTrans);
    super.dispose();
  }

  /// 起停脉动。**必须挪到帧后**:repeat/stop 会同步 notifyListeners,
  /// build 期间通知已经挂上的 AnimatedBuilder 会撞 markNeedsBuild 断言。
  void _syncPulse(bool on) {
    if (on == _pulsing) return;
    _pulsing = on;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pulsing) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    });
  }

  /// 译文到货(网络回填或词库灌注到片):重解析一遍,`trans` 由 [parseToks]
  /// 现查缓存填上。
  void _onTrans() {
    if (mounted) setState(_parse);
  }

  void _parse() {
    final pre = widget.preferredTrans;
    _parsed = [
      for (final s in widget.sections)
        (
          label: s.label,
          toks: [
            for (final t in parseToks(s.body))
              if (t.name.trim().isNotEmpty)
                (tok: t, trans: pre?.call(t.name) ?? t.trans),
          ],
        ),
    ];
  }

  void _requestMissing() {
    if (widget.preferredTransLoading) return; // 等那层到了再问剩下的
    _svc?.request([
      for (final sec in _parsed)
        for (final c in sec.toks)
          if (c.trans == null) c.tok.name,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 服务随补全来源/后端基址换代:换了就把监听挪过去,缺的补问一遍
    final svc = ref.watch(tagTranslationServiceProvider);
    if (!identical(svc, _svc)) {
      _svc?.removeListener(_onTrans);
      _svc = svc..addListener(_onTrans);
      _requestMissing();
    }
    var anyPending = false;
    bool pendingOf(({Tok tok, String? trans}) c) {
      final p =
          c.trans == null &&
          (widget.preferredTransLoading || svc.isPending(c.tok.name));
      anyPending |= p;
      return p;
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _parsed.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          if (_parsed[i].label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _parsed[i].label!,
                style: context.texts.labelSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _parsed[i].toks)
                _ReadTagChip(
                  c.tok,
                  trans: c.trans,
                  pending: pendingOf(c),
                  pulse: _pulse,
                ),
            ],
          ),
        ],
      ],
    );
    _syncPulse(anyPending);
    return content;
  }
}

/// 单颗只读词条芯片:配色对齐编辑器 _TagChip(权重底色/边框同一条曲线),
/// 去掉交互态;名字超长软换行不省略 —— 这里是给人读全文的。
/// 译文行**恒占位**(编辑器同款):有没有译文都一样高,异步到货/答不出
/// 都不跳版。
class _ReadTagChip extends StatelessWidget {
  const _ReadTagChip(
    this.tok, {
    required this.trans,
    required this.pending,
    required this.pulse,
  });

  final Tok tok;

  /// 显示的译名(可能来自 [PromptChips.preferredTrans],不一定是 `tok.trans`)。
  final String? trans;

  /// 译文在路上(排队/在问):行占住并画脉动条,到货不跳版。
  final bool pending;

  /// 加载态共用的脉动(整片芯片一个 ticker,不是一颗一个)。
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 这些弹层不在 editorTheme 作用域里,context.editor 会恒退回浅色变体,
    // 按亮暗自己挑
    final pal = Theme.of(context).brightness == Brightness.dark
        ? EditorPalette.dark
        : EditorPalette.light;
    final mult = tok.effMult;
    final off = tok.disabled;
    final up = mult > 1.0001, down = mult < 0.9999;
    var bg = scheme.surfaceContainerHigh;
    var border = scheme.outlineVariant;
    if ((up || down) && !off) {
      bg = Color.alphaBlend(pal.weightWash(mult)!, scheme.surfaceContainerHigh);
      final i = up
          ? ((mult - 1) / 1.5).clamp(0.0, 1.0)
          : ((1 - mult) / 0.7).clamp(0.0, 1.0);
      border = (up ? pal.weightUpBorder : pal.weightDownBorder).withValues(
        alpha: .45 + i * .35,
      );
    }
    final trans = this.trans;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: tok.name,
              children: [
                if ((up || down) && !off)
                  TextSpan(
                    text: ' ×${fmtMult(mult)}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: off ? scheme.outline : scheme.onSurface,
              decoration: off ? TextDecoration.lineThrough : null,
              decorationThickness: 2,
            ),
          ),
          // 恒占一行,空着/加载中/有字三态严格等高
          SizedBox(
            height: 13,
            child: Align(
              alignment: Alignment.bottomLeft,
              // widthFactor 必须给:不给 = Align 撑满可用宽度,Column 跟着
              // 变满宽,整颗芯片独占一整行(编辑器同一处坑)
              widthFactor: 1,
              child: trans != null
                  ? Text(
                      trans,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : pending
                  ? _TransPulse(pulse: pulse)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 译文加载中的占位条(编辑器 _TransPulse 同款):那一行反正要占着,
/// 空着分不清是「没译文」还是「还没到」。
class _TransPulse extends StatelessWidget {
  const _TransPulse({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final c = context.scheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Container(
        width: 24,
        height: 6.5,
        decoration: BoxDecoration(
          color: c.withValues(alpha: .10 + .16 * pulse.value),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

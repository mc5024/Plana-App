/// AI 回复正文:把反引号包着的内容画成代码样式,点一下就复制。
///
/// 预设的「写 tag 模式」要求把 tag 包进代码块(模型还会自己加个 `text` 之类的
/// 语言标注),而气泡原先是纯文本,用户看到的是字面的三个反引号,想复制那串
/// tag 还得长按整条回复、再自己删掉首尾的符号。**只改显示,不动预设** ——
/// 预设 bot 那边也在用,那边的聊天软件自己会渲染 markdown。
///
/// **只认反引号。** 粗体、列表这些不处理:模型偶尔会写,没渲染也只是多几个星号;
/// 反引号不一样,它包着的恰恰是用户要拿走的那段。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../core/theme/app_theme.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import '../domain/conversation.dart' show DrawProposal, promptTextOf;
import '../../../l10n/l10n.dart';

/// 复制到剪贴板并给一句回执。
Future<void> copyText(BuildContext context, String text) async {
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    hintSnack(context, context.l10n.copied, icon: Icons.copy_outlined);
  }
}

/// 开围栏:行首三个反引号,后面可以跟语言标注(`text`、`plaintext`……,不显示)。
final _fenceOpen = RegExp(r'^ {0,3}```[^`]*$');

/// 收围栏:只认光秃秃的三个反引号。
final _fenceClose = RegExp(r'^ {0,3}```\s*$');

/// 行内代码。三个反引号写在同一行里(```tag```)也当行内 —— 模型偶尔这么写,
/// 不单独认的话会被下面那条拆成「两个反引号 + 代码 + 两个反引号」。
final _inlineCode = RegExp(r'```([^`\n]+)```|`([^`\n]+)`');

/// 按代码围栏切段。`block` 为真的是代码块内容(已去掉围栏行与语言标注)。
///
/// 文字段去掉首尾空行 —— 代码块前后本来就留了间距,再叠上原文里的空行会空出一大截。
/// **没收尾的围栏,剩下的全当代码**:模型被截断时常见,当文字的话用户会看到一个
/// 孤零零的开围栏,当代码至少那串 tag 还是完整可复制的。
List<({String text, bool block})> splitCodeFences(String raw) {
  final out = <({String text, bool block})>[];
  final buf = <String>[];
  var inCode = false;

  void flush() {
    final joined = buf.join('\n');
    buf.clear();
    final text = inCode
        // 代码保留缩进,只去掉首尾的空行
        ? joined.replaceFirst(RegExp(r'^\n+'), '').trimRight()
        : joined.trim();
    if (text.isNotEmpty) out.add((text: text, block: inCode));
  }

  for (final rawLine in raw.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (!inCode && _fenceOpen.hasMatch(line)) {
      flush();
      inCode = true;
    } else if (inCode && _fenceClose.hasMatch(line)) {
      flush();
      inCode = false;
    } else {
      buf.add(line);
    }
  }
  flush();
  return out;
}

/// 一段文字里的行内代码。`code` 为真的是反引号里的内容。
List<({String text, bool code})> splitInlineCode(String text) {
  final out = <({String text, bool code})>[];
  var last = 0;
  for (final m in _inlineCode.allMatches(text)) {
    if (m.start > last) {
      out.add((text: text.substring(last, m.start), code: false));
    }
    out.add((text: m.group(1) ?? m.group(2)!, code: true));
    last = m.end;
  }
  if (last < text.length) out.add((text: text.substring(last), code: false));
  return out;
}

class ReplyBody extends StatelessWidget {
  const ReplyBody(this.text, {super.key, this.fontSize = 14});

  final String text;

  /// 正文字号(助手设置里调)。代码跟着走,比正文小一号。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = context.texts.bodyMedium!.copyWith(
      fontSize: fontSize,
      height: 1.6,
    );
    // 绝大多数回复一个反引号都没有:原样一个 Text,别为最常见的情况多搭几层
    if (!text.contains('`')) return Text(text, style: style);

    final segs = splitCodeFences(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < segs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          if (segs[i].block)
            CodeBlock(segs[i].text, size: fontSize - 1)
          else
            _Prose(segs[i].text, style: style),
        ],
      ],
    );
  }
}

/// 「纯文本格式」那一轮的提示词:纯文本,点一下复制。没有导入、没有生成。
///
/// 正向一块(角色按 `charN:` 一行一个,见 [promptTextOf]),有负向再单独一块 ——
/// 两块各点各的,正向框、负向框分别贴。只有正向时不加标签,多出一块负向才得标明哪块是哪块。
class PromptTextBlocks extends StatelessWidget {
  const PromptTextBlocks(this.draw, {super.key, this.fontSize = 14});

  final DrawProposal draw;

  /// 所在气泡的正文字号。块里的等宽字比它小一号,与回复里的代码块一致。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = promptTextOf(draw);
    final labeled = t.positive.isNotEmpty && t.negative.isNotEmpty;
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        s,
        style: context.texts.labelSmall!.copyWith(
          color: context.scheme.outline,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (t.positive.isNotEmpty) ...[
          if (labeled) label(context.l10n.positiveShort),
          CodeBlock(t.positive, size: fontSize - 1),
        ],
        if (t.negative.isNotEmpty) ...[
          if (labeled) const SizedBox(height: 10),
          if (labeled) label(context.l10n.negativeShort),
          CodeBlock(t.negative, size: fontSize - 1),
        ],
      ],
    );
  }
}

/// 代码块。整块可点,点了复制块里的内容。
///
/// 右上角那枚复制图标是**告诉用户这里能点**的,不是另一个按钮 —— 两处都能点、
/// 点的又是同一件事,用户得先分辨它俩有什么区别。
class CodeBlock extends StatelessWidget {
  const CodeBlock(this.code, {super.key, this.size = 13});

  final String code;

  /// 等宽字字号。
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => copyText(context, code),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 8, 9, 8),
          child: Row(
            // 宽度跟着内容走:一个角色 tag 的块不必撑满整个气泡,
            // 长串 tag 撞到气泡边缘自己会折行
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  code,
                  style: mono(
                    context,
                    size: size,
                    weight: FontWeight.w500,
                  ).copyWith(height: 1.45),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.copy_outlined,
                  size: 14,
                  color: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 普通文字,里面的行内代码画成小底色块,同样点一下复制。
class _Prose extends StatelessWidget {
  const _Prose(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = splitInlineCode(text);
    if (parts.every((p) => !p.code)) return Text(text, style: style);
    final scheme = context.scheme;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final p in parts)
            if (!p.code)
              TextSpan(text: p.text)
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Material(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => copyText(context, p.text),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      child: Text(
                        p.text,
                        style: mono(
                          context,
                          size: (style.fontSize ?? 14) - 1.5,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 提示词编辑器模型 —— 光标驱动定稿:**字符串(含权重原样语法)就是唯一真相**。
///
/// 权重两套**独立**语法叠加在同一枚标签上:
/// - 外层**括号** `{...}` / `[...]`:每层 ×1.05 / ÷1.05,`{ }`/`[ ]` 快捷键各套一层(互不换算)。
/// - 内层**数值** `N::name::`:`−`/`+` 只改这个数,不动括号。
/// 一枚 token 结构:`~ {{ [ N::name:: ] }} ~`(禁用 · 括号层 · 数值 · 名字)。
/// 有效倍率 = 数值 × 1.05^括号净档。翻译画在最内层名字下。
library;

import 'dart:math' as math;

import 'data/suggestions.dart';

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// 一枚标签的解析视图(全部是原字符串里的绝对下标)
class Tok {
  const Tok({
    required this.segStart,
    required this.segEnd,
    required this.coreStart,
    required this.coreEnd,
    required this.innerStart,
    required this.innerEnd,
    required this.nameStart,
    required this.nameEnd,
    required this.braceLevel,
    required this.numMult,
    required this.disabled,
    required this.name,
    this.trans,
    this.groupMult = 1.0,
  });

  /// 整枚(含 ~)
  final int segStart;
  final int segEnd;

  /// 剥掉 ~ 后的核(括号 + 数值 + 名字)—— 括号快捷键在这层套/剥
  final int coreStart;
  final int coreEnd;

  /// 剥掉外层括号后(数值 + 名字)—— 数值加减改这层
  final int innerStart;
  final int innerEnd;

  /// 最内层干净名字 —— 翻译画在这段下方
  final int nameStart;
  final int nameEnd;

  final int braceLevel; // 括号净档:+n = n 层 {},-n = n 层 []
  final double numMult; // 内层数值倍率(无则 1.0)
  final bool disabled;
  final String name;
  final String? trans;

  /// 跨词条权重组(`{a, b}` / `1.2::a, b::`)作用于本词的合成倍率(无则 1)。
  /// 组记号本身在 seg 之外(属于分隔区),故删词/清权重天然不碰组语法。
  final double groupMult;

  /// 自身倍率(不含组):数值 × 1.05^括号档。词条栏读数/操作用它。
  double get ownMult => numMult * math.pow(1.05, braceLevel).toDouble();

  /// 有效倍率 = 自身 × 组倍率
  double get effMult => ownMult * groupMult;
}

/// 权重可视化区间(权重底色绘制层用):[start, end) 为原文范围(**含**
/// 权重记号),mult 为该层单独的倍率。嵌套组/组内自带权重 = 多条区间
/// 叠加,绘制层半透明叠色,内层自然更深(web 装饰同款观感)。
class WeightSpan {
  const WeightSpan(this.start, this.end, this.mult);
  final int start;
  final int end;
  final double mult;
}

/// 折叠组 `<#名字: a, b>` —— 把一串词条收成一个命名整体。**仅编辑期语法**:
/// [outputOf] 剥掉记号只留内容,NAI 永远拿不到它;记号本身靠原文草稿持久化
/// (见 [pickEditorText])。记号落在词条 seg 之外(属分隔区),故删词/改权重/
/// 排序天然不碰折叠语法。
///
/// **恒为最外层且不嵌套**:批量加权包出来的是 `<#名字: {a, b}>` 而非
/// `{<#名字: a, b}>`(见 [_rangeBounds] 的记号回避),解析顺序也据此固定
/// 为「先剥折叠、再剥权重组」。
///
/// 开记号是 `<#` 两字符哨兵、名字后必须是**冒号加空格**,两道都满足才算
/// 折叠。少一道都不行:早期用的 `<名字:` 会把 SD 生态的 `<lora:x:0.8>`、
/// `<hypernet:f:1>` 误当折叠剥成 `x:0.8`,而本 app 带 SD→NAI 转换工具,
/// 用户粘这类串是可预期的——那是把用户的提示词**静默改写后发给 NAI**。
/// 颜文字 tag(`>_<`、`<o>_<o>`、`:<`、`<3`)本来就不含「冒号+空格」,
/// 两版都安全,但哨兵让这条保证不再依赖巧合。见 fold_test.dart 的对抗用例。
class FoldSpan {
  const FoldSpan({
    required this.start,
    required this.end,
    required this.nameStart,
    required this.nameEnd,
    required this.bodyStart,
    required this.bodyEnd,
    required this.name,
  });

  /// `<` 的下标 / `>` 之后(未闭合时兜到文末)
  final int start;
  final int end;

  /// 名字段(不含 `<` 与 `:`)
  final int nameStart;
  final int nameEnd;

  /// 内容段(不含记号):成员词条都落在这段里
  final int bodyStart;
  final int bodyEnd;

  final String name;

  /// 词条是否为本折叠的成员
  bool holds(Tok t) => t.segStart >= bodyStart && t.segEnd <= bodyEnd;
}

/// 数值组/数值权重前缀 `N::`。
/// 跨词条权重组栈条目:brace=`{`/`[`,否则数值组。openPos=开记号原文下标,
/// closeEnd=数值组的收口位置(由 [_numGroupsOf] 预扫定死;括号组为 -1)。
class _Group {
  const _Group(
    this.brace,
    this.mult,
    this.openPos, [
    this.closeEnd = -1,
    this.closed = false,
  ]);
  final bool brace;
  final double mult;
  final int openPos;
  final int closeEnd;

  /// closeEnd 处是不是真的闭记号(见 [_NumGroup.closed])。
  final bool closed;
}

/// 数值权重组的全文边界 —— **照抄桌面端** `PromptEditor.tsx` 的权重装饰
/// (Pass 2):逐个 `N::` 前缀扫,右界取「最近的闭合 `::`」与「下一个 `N::`
/// 前缀」中**靠前**的那个。
///
/// 两条保证,老实现一条都没有:
/// ① 闭合记号在**全文**里找,不按逗号切段 —— `0.5::a,::b` 这种闭记号落在
///    逗号**之后**的写法照样收得了口(老实现只认「段尾以 `::` 结尾」,
///    收不了口的组就一路开着吞掉后面所有段);
/// ② 组的右界恒被下一个前缀截断,**绝不吞掉后面的组** —— 老实现遇到新前缀
///    是再压一层栈(权重连乘),于是底色糊成一片、effMult 连乘成离谱的倍率。
final _numGroupRe = RegExp(r'-?\d+(?:\.\d+)?::');

class _NumGroup {
  const _NumGroup(
    this.start,
    this.contentStart,
    this.end,
    this.mult,
    this.closed,
  );

  /// 开记号 `N::` 的起点 / 内容起点(前缀之后)/ 组的右界(含闭记号)。
  final int start;
  final int contentStart;
  final int end;
  final double mult;

  /// [end] 处**真有**一对闭合 `::` 吗。false = 组没写收口,右界是被下一个前缀
  /// 或文末截出来的。区分这两者是必须的:剥记号的地方会按 `end - 2` 削掉两个
  /// 字符,右界不是记号时削掉的就是用户的正文(实测 `1.2::a, black lolita`
  /// 末尾会变成 `black loli`)。
  final bool closed;
}

List<_NumGroup> _numGroupsOf(String text) {
  final ms = _numGroupRe.allMatches(text).toList();
  final out = <_NumGroup>[];
  for (var i = 0; i < ms.length; i++) {
    final m = ms[i];
    final mult = double.tryParse(text.substring(m.start, m.end - 2));
    if (mult == null) continue;
    final nextStart = i + 1 < ms.length ? ms[i + 1].start : text.length;
    final closeIdx = text.indexOf('::', m.end);
    final closed = closeIdx >= 0 && closeIdx + 2 <= nextStart;
    out.add(
      _NumGroup(
        m.start,
        m.end,
        closed ? closeIdx + 2 : nextStart,
        mult,
        closed,
      ),
    );
  }
  return out;
}

/// 解析整段文本 → 标签列表。
/// 支持**跨词条权重组**(web analyzeTagGroups 对应):`{a, b}`、`[a, b]`、
/// `1.2::a, b::` —— 组记号剥在词条 seg 之外,组倍率灌进成员的 groupMult。
/// 不闭合的组容忍地延伸到文末;记号错配时只剥字符不计权(宽松解析)。
/// 传入 [weightSpans] 时顺带收集权重可视化区间(单词条自身权重一条,
/// 每层组一条,含记号;禁用词条不发自身区间)。
List<Tok> parseToks(
  String text, {
  List<WeightSpan>? weightSpans,
  List<FoldSpan>? folds,
}) {
  final res = <Tok>[];
  var start = 0;
  final groups = <_Group>[];
  // 数值组边界全文预扫(桌面端同款规则),逐段只做开/收记账
  final numGroups = _numGroupsOf(text);
  var ngi = 0;

  // 折叠不嵌套,同时最多一个开着;-1 = 当前不在折叠内
  var foldOpen = -1;
  var foldNameS = 0, foldNameE = 0, foldBodyS = 0;

  /// 折叠体里还没收口的 `<xxx` 层数。折叠的尾巴是 `>`,而**折叠体自己也可能
  /// 带尖括号** —— 画师串常见 `<artist>…</artist>` 这种包裹。不数一数就会在
  /// `<artist>` 那个 `>` 上提前收尾:折叠只吞下一个 `<artist>`,后面整串裸在
  /// 正文里,末尾还剩一个多余的 `>`(实测)。
  var foldAngle = 0;

  int trimL(int a, int b) {
    while (a < b && _isSpace(text[a])) {
      a++;
    }
    return a;
  }

  int trimR(int a, int b) {
    while (b > a && _isSpace(text[b - 1])) {
      b--;
    }
    return b;
  }

  void seg(int rawStart, int rawEnd) {
    var a = trimL(rawStart, rawEnd);
    var b = trimR(a, rawEnd);
    if (b <= a) return;
    final segS = a, segE = b;
    var groupMult = 1.0;
    for (final g in groups) {
      groupMult *= g.mult;
    }

    // 剥禁用 ~
    var disabled = false;
    if (text[a] == '~') {
      disabled = true;
      a++;
      if (b > a && text[b - 1] == '~') b--;
      a = trimL(a, b);
      b = trimR(a, b);
    }
    final coreS = a, coreE = b;

    // 剥外层括号(统计净档)
    var braceLevel = 0;
    var ia = a, ib = b;
    while (ib - ia >= 2) {
      if (text[ia] == '{' && text[ib - 1] == '}') {
        braceLevel++;
      } else if (text[ia] == '[' && text[ib - 1] == ']') {
        braceLevel--;
      } else {
        break;
      }
      ia++;
      ib--;
      ia = trimL(ia, ib);
      ib = trimR(ia, ib);
    }
    final innerS = ia, innerE = ib;

    // 剥内层数值 N::name::
    var numMult = 1.0;
    var nameS = ia, nameE = ib;
    final inner = text.substring(ia, ib);
    final di = inner.indexOf('::');
    final dj = inner.lastIndexOf('::');
    // 收口 `::` 必须与开记号**不重叠**(`dj >= di + 2`):`1.5:::` 的三个冒号里
    // 头一对是开记号(di=开)、后一对是收口(dj=开+1),两对共用中间那个冒号 ——
    // 只判 `dj > di` 会当成合法闭合,算出 nameStart(di+2) > nameEnd(dj) 的倒挂
    // 区间,substring 直接抛 RangeError(注音/权重底色/富文本三处 parseToks 全崩,
    // 屏上就是一大片渲染失败的灰底)。重叠时这里不认,整枚当普通文本走,打全
    // `1.5::x::` 再正常上色。
    if (di > 0 && dj >= di + 2 && dj == inner.length - 2) {
      final num = double.tryParse(inner.substring(0, di));
      if (num != null) {
        numMult = num;
        nameS = trimL(ia + di + 2, ib);
        nameE = trimR(nameS, ia + dj);
      }
    } else if (di > 0 && dj == di) {
      // 只有开记号没收口(`1.5::b`)。跨段的那种在上面已经进了组栈,能走到这里
      // 的是「组从这里开到文末、且整段就它一条」—— 老实现认不出,于是整枚词条
      // 的名字就是 `1.5::b` 这一串:注音查不着、词条栏读数也不对。
      final num = double.tryParse(inner.substring(0, di));
      if (num != null) {
        numMult = num;
        nameS = trimL(ia + di + 2, ib);
        nameE = ib;
      }
    }

    res.add(
      Tok(
        segStart: segS,
        segEnd: segE,
        coreStart: coreS,
        coreEnd: coreE,
        innerStart: innerS,
        innerEnd: innerE,
        nameStart: nameS,
        nameEnd: nameE,
        braceLevel: braceLevel,
        numMult: numMult,
        disabled: disabled,
        name: text.substring(nameS, nameE),
        trans: translationOf(text.substring(nameS, nameE)),
        groupMult: groupMult,
      ),
    );
    if (weightSpans != null && !disabled) {
      final own = numMult * math.pow(1.05, braceLevel).toDouble();
      if ((own - 1).abs() > 0.0001) {
        weightSpans.add(WeightSpan(segS, segE, own));
      }
    }
  }

  /// 一段逗号/换行间的 span:先剥折叠记号、再剥跨词条组记号(空 span 也要
  /// 记账,`{` 或 `1.2::` 可独占一段),剩余交给 seg 按单词条解析。
  void span(int rawStart, int rawEnd) {
    var a = trimL(rawStart, rawEnd);
    var b = trimR(a, rawEnd);

    // 折叠记号 `<#名字: … >` 在最外层,先剥;剥完的区间再走权重组/词条解析,
    // 所以折叠与权重可以叠加互不干扰。已在折叠内就不再认新的开记号(不嵌套)。
    // 认定要同时满足 `<#` 哨兵与「冒号+空格」——放宽任一道都会误伤真实提示词。
    if (a + 1 < b && text[a] == '<' && text[a + 1] == '#' && foldOpen < 0) {
      var colon = -1;
      for (var k = a + 2; k + 1 < b; k++) {
        if (text[k] == ':' && text[k + 1] == ' ') {
          colon = k;
          break;
        }
      }
      if (colon > a + 1) {
        foldOpen = a;
        foldNameS = trimL(a + 2, colon);
        foldNameE = trimR(foldNameS, colon);
        a = trimL(colon + 1, b);
        foldBodyS = a;
        foldAngle = 0;
      }
    }
    // 闭记号要在权重组收口**之前**量 body 右界:组的 `}`/`]` 属于 body 内容。
    var foldEnd = -1, foldBodyE = -1;
    if (b > a && foldOpen >= 0) {
      if (b - 2 >= a &&
          text[b - 2] == kFoldClose[0] &&
          text[b - 1] == kFoldClose[1]) {
        // 专用收尾记号 [kFoldClose]:一眼定死,不必猜
        foldEnd = b;
        b = trimR(a, b - 2);
        foldBodyE = b;
      } else {
        // 老草稿的裸 `>`:内容自己也可能带尖括号,只有**不欠着 body 里的 `<`**
        // 时段尾那个 `>` 才是尾巴。`</artist>>` 于是收对了 —— 前一个 `>` 替
        // `</artist` 收口,最后那个才是折叠的。见 [foldAngle] / [kFoldClose]。
        var depth = foldAngle;
        for (var k = a; k < b; k++) {
          final c = text[k];
          if (c == '<') {
            if (k + 1 < b && _isTagOpen(text[k + 1])) depth++;
          } else if (c == '>') {
            if (k == b - 1 && depth == 0) {
              foldEnd = b;
              b = trimR(a, b - 1);
              foldBodyE = b;
              break;
            }
            if (depth > 0) depth--;
          }
        }
        if (foldEnd < 0) foldAngle = depth;
      }
    }

    // 括号净差:>0 = 本段有未闭合的组开,<0 = 有替前文收口的组闭。
    // (标签名不含花/方括号,直接计数即可;单词条权重 `{a}` 差为 0 不受扰)
    var bal = 0;
    for (var k = a; k < b; k++) {
      final c = text[k];
      if (c == '{' || c == '[') {
        bal++;
      } else if (c == '}' || c == ']') {
        bal--;
      }
    }
    while (a < b && (text[a] == '{' || text[a] == '[') && bal > 0) {
      groups.add(_Group(true, text[a] == '{' ? 1.05 : 1 / 1.05, a));
      a++;
      bal--;
    }
    // 闭记号的**独占尾界**(右→左剥;倒序遍历 = 由内而外出栈)
    final closeEnds = <int>[];
    while (b > a && (text[b - 1] == '}' || text[b - 1] == ']') && bal < 0) {
      closeEnds.add(b);
      b--;
      bal++;
    }
    a = trimL(a, b);
    b = trimR(a, b);

    // ---- 数值组:边界已由 [_numGroupsOf] 定死,这里只按位置开/收 ----

    // ① 段首收口(`…,::b` 形态):闭记号落在本段内容**之前**,故本段内容
    //    不算在组里 —— 立即出栈,并把 `::` 剥掉别落进标签名。
    while (groups.isNotEmpty &&
        !groups.last.brace &&
        groups.last.closeEnd >= 0) {
      final g = groups.last;
      if (g.closeEnd > b) break;
      if (g.closed && g.closeEnd - 2 == a) {
        a = trimL(g.closeEnd, b);
      } else if (g.closeEnd > a) {
        break; // 闭记号在段尾/段中 → 本段内容仍属于该组,留到 seg 之后收
      }
      groups.removeLast();
      weightSpans?.add(WeightSpan(g.openPos, g.closeEnd, g.mult));
    }

    // ② 开组:起点落在本段、且**跨段延伸**的数值组。整组落在本段之内的是
    //    单词条自身权重(`N::a::`),交给 seg 的剥内层数值,不进组栈。
    while (ngi < numGroups.length && numGroups[ngi].start < b) {
      final g = numGroups[ngi];
      ngi++;
      if (g.start < a || g.end <= b) continue;
      // 开记号**前面还有内容**(`a::1.5::b` 这种写法):`::` 在 NAI 里本身就是
      // 分隔符,不少人拿它当逗号使,写完一个词直接跟下一段的权重。老实现在这里
      // 把 a 一跳跳到组内容处,这截头部就**整段丢了** —— 既不成词条(没有注音、
      // 没有翻译、词条栏点不着),也没人给它上色,屏幕上就是一截灰字。
      // 先把它当独立词条收掉再开组;结尾那对 `::` 是分隔符,不留进标签名。
      if (g.start > a) {
        var headEnd = trimR(a, g.start);
        if (headEnd - 2 >= a && text.substring(headEnd - 2, headEnd) == '::') {
          headEnd = trimR(a, headEnd - 2);
        }
        // 此刻还没压入新组,seg 读到的 groupMult 正是这截头部真正所属的层级
        if (headEnd > a) seg(a, headEnd);
      }
      groups.add(_Group(false, g.mult, g.start, g.end, g.closed));
      a = trimL(g.contentStart, b);
    }

    // ③ 段尾收口(`… b::` 形态):本段内容属于该组,故只在此剥记号 + 记账,
    //    出栈留到 seg 之后 —— 否则这枚词条会算不到该组的倍率。
    var tailClose = 0;
    for (var i = groups.length - 1; i >= 0; i--) {
      final g = groups[i];
      if (g.brace || g.closeEnd < 0 || g.closeEnd > b) break;
      // 只有真闭记号才削那两个字符;右界是截出来的就原样留着(否则削的是正文)
      if (g.closed && g.closeEnd == b) b = trimR(a, b - 2);
      tailClose++;
    }

    seg(a, b);

    // 组闭出栈:先内层数值,再括号(错配时跳过,宽松容忍)
    for (var i = 0; i < tailClose && groups.isNotEmpty; i++) {
      final g = groups.removeLast();
      weightSpans?.add(WeightSpan(g.openPos, g.closeEnd, g.mult));
    }
    for (final endPos in closeEnds.reversed) {
      if (groups.isNotEmpty && groups.last.brace) {
        final g = groups.removeLast();
        weightSpans?.add(WeightSpan(g.openPos, endPos, g.mult));
      } else {
        break;
      }
    }

    if (foldEnd > 0) {
      folds?.add(
        FoldSpan(
          start: foldOpen,
          end: foldEnd,
          nameStart: foldNameS,
          nameEnd: foldNameE,
          bodyStart: foldBodyS,
          bodyEnd: foldBodyE,
          name: text.substring(foldNameS, foldNameE),
        ),
      );
      foldOpen = -1;
      foldAngle = 0;
    }
  }

  for (var k = 0; k < text.length; k++) {
    final c = text[k];
    // 换行也是分隔:回车开新行即下一枚标签(名字里不留 \n,翻译反查才有命中)
    if (c == ',' || c == '，' || c == '\n') {
      span(start, k);
      start = k + 1;
    }
  }
  span(start, text.length);
  // 未闭合的组容忍延伸到文末(可视化区间同样兜到文末)
  if (weightSpans != null) {
    for (final g in groups.reversed) {
      weightSpans.add(WeightSpan(g.openPos, text.length, g.mult));
    }
  }
  // 未闭合的折叠同样兜到文末(边打字边成组时不闪断)
  if (foldOpen >= 0) {
    folds?.add(
      FoldSpan(
        start: foldOpen,
        end: text.length,
        nameStart: foldNameS,
        nameEnd: foldNameE,
        bodyStart: foldBodyS,
        bodyEnd: text.length,
        name: text.substring(foldNameS, foldNameE),
      ),
    );
  }
  return res;
}

/// 折叠的收尾记号。**不是**裸 `>`:折叠体就是一段提示词,里面本来就可能带
/// 尖括号 —— `<artist>…</artist>` 这类包裹、`<lora:x:1>`、`<3` 颜文字,裸 `>`
/// 判不清哪个才是尾巴。`#>` 与开头的 `<#` 对称,内容里撞不上。
///
/// 老草稿(裸 `>` 收尾)照常读得回,走 [parseToks] 里数尖括号那一支兜底;
/// 读回来再存一次就换成这个写法,不必迁移历史数据。
const String kFoldClose = '#>';

/// `<` 后面这个字符像不像 `<artist>` / `</artist>` 那种标签开头。
///
/// 只认字母与 `/`:`<3`、`>_<` 这类颜文字标签同样带尖括号,把它们也算成
/// 一层的话,反过来会把折叠**真正**的尾巴当成它们的收口吃掉。
bool _isTagOpen(String c) {
  if (c == '/') return true;
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}

/// 折叠列表(按出现顺序,不嵌套故互不重叠)。
List<FoldSpan> parseFolds(String text) {
  final out = <FoldSpan>[];
  parseToks(text, folds: out);
  return out;
}

/// 光标偏移 → 所在标签下标(区间含端点),无则 -1
int tokIndexAt(String text, int offset, [List<Tok>? toks]) {
  final t = toks ?? parseToks(text);
  for (var i = 0; i < t.length; i++) {
    if (offset >= t[i].segStart && offset <= t[i].segEnd) return i;
  }
  return -1;
}

/// 倍率显示:去掉尾随 0(1.30→"1.3"、1.00→"1"、1.05→"1.05")
String fmtMult(double m) {
  var s = m.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// 括号快捷键:给整个核**外套**一层 `{}`(up)或 `[]`,不动内层数值
String wrapBracket(String text, Tok t, {required bool up}) {
  final core = text.substring(t.coreStart, t.coreEnd);
  final s = up ? '{$core}' : '[$core]';
  return text.replaceRange(t.coreStart, t.coreEnd, s);
}

/// 数值加减:只改内层 `N::name::`(≈1.0 写回纯名),保留外层括号。
/// 不设上下限,支持负数(如 `-0.5::tag::`)。
String setTokMult(String text, Tok t, double newMult) {
  // 抹平浮点漂移:保留两位小数(0.05 步进的最小粒度)
  final m = (newMult * 100).roundToDouble() / 100;
  final inner = (m - 1.0).abs() < 0.005 ? t.name : '${fmtMult(m)}::${t.name}::';
  return text.replaceRange(t.innerStart, t.innerEnd, inner);
}

/// 清除权重:去掉全部括号 + 数值,回纯名(保留禁用 ~)
String clearWeight(String text, Tok t) =>
    text.replaceRange(t.coreStart, t.coreEnd, t.name);

/// 改名:只换名字那一段,权重/禁用记号原样留着(芯片模式没有光标,改字
/// 只能整名替换)。空名当没改——删词有专门的入口,别从改名这条路掉进去。
String renameTok(String text, Tok t, String name) {
  final n = name.trim();
  if (n.isEmpty) return text;
  return text.replaceRange(t.nameStart, t.nameEnd, n);
}

/// 切换禁用:整枚套/剥 `~`
String toggleTokDisabled(String text, Tok t) => t.disabled
    ? text.replaceRange(
        t.segStart,
        t.segEnd,
        text.substring(t.coreStart, t.coreEnd),
      )
    : text.replaceRange(
        t.segStart,
        t.segEnd,
        '~${text.substring(t.segStart, t.segEnd)}~',
      );

/// 删除某枚(连同一个相邻逗号)→ (新文本, 光标位置)
// ---- 划词多选批量操作(web multiSelectActions 移植)----
// 加权/数值走**整组包裹**(`{a, b}` / `1.2::a, b::`,web 同款,解析器已支持
// 跨词条组);禁用逐词应用(保留各自权重);删除按范围整段删。

/// 多选范围 = 分隔符边界:first 左至上一逗号/行首之后,last 右至下一
/// 逗号/行尾之前 —— 把词条两侧的**组权重记号**一并纳入(改写时不留残渣)。
(int, int) _rangeBounds(String text, Tok first, Tok last) {
  var a = first.segStart;
  while (a > 0 &&
      text[a - 1] != ',' &&
      text[a - 1] != '，' &&
      text[a - 1] != '\n') {
    a--;
  }
  while (a < first.segStart && (text[a] == ' ' || text[a] == '\t')) {
    a++;
  }
  var b = last.segEnd;
  while (b < text.length &&
      text[b] != ',' &&
      text[b] != '，' &&
      text[b] != '\n') {
    b++;
  }
  while (b > last.segEnd && (text[b - 1] == ' ' || text[b - 1] == '\t')) {
    b--;
  }
  // 折叠记号不进批量范围:折叠恒为最外层,批量加权/清除只作用于成员,
  // 包出来是 `<#名字: {a, b}>`;若把 `<#名字:` 卷进去会得到 `{<#名字: a, b}>`,
  // 记号错位、折叠再也解析不出来。
  for (final f in parseFolds(text)) {
    if (a >= f.start && a < f.bodyStart) a = f.bodyStart;
    if (b > f.bodyEnd && b <= f.end) b = f.bodyEnd;
  }
  return (a, b);
}

int _clampLast(List<Tok> toks, int last) =>
    last < toks.length ? last : toks.length - 1;

/// 批量套括号:整段外包一层 `{...}`(up)或 `[...]`(已有权重原样嵌套)。
String batchWrap(String text, int first, int last, {required bool up}) {
  final toks = parseToks(text);
  if (toks.isEmpty || first >= toks.length) return text;
  final l = _clampLast(toks, last);
  final (a, b) = _rangeBounds(text, toks[first], toks[l]);
  final sub = text.substring(a, b);
  return text.replaceRange(a, b, up ? '{$sub}' : '[$sub]');
}

/// 选中范围重建为干净名字串(保留禁用 ~;范围内换行摊平为「, 」)。
String _cleanJoin(String text, List<Tok> toks, int first, int last) => [
  for (var i = first; i <= last; i++)
    toks[i].disabled ? '~${toks[i].name}~' : toks[i].name,
].join(', ');

/// 批量统一数值权重:先清各枚权重,整段写成 `m::a, b::`(≈1 只清不包)。
String batchSetMult(String text, int first, int last, double m) {
  final toks = parseToks(text);
  if (toks.isEmpty || first >= toks.length) return text;
  final l = _clampLast(toks, last);
  final mm = (m * 100).roundToDouble() / 100;
  final cleaned = _cleanJoin(text, toks, first, l);
  final result = (mm - 1.0).abs() < 0.005
      ? cleaned
      : '${fmtMult(mm)}::$cleaned::';
  final (a, b) = _rangeBounds(text, toks[first], toks[l]);
  return text.replaceRange(a, b, result);
}

/// 批量清除权重:整段回干净名字串(组记号/括号/数值全去)。
String batchClearWeight(String text, int first, int last) {
  final toks = parseToks(text);
  if (toks.isEmpty || first >= toks.length) return text;
  final l = _clampLast(toks, last);
  final (a, b) = _rangeBounds(text, toks[first], toks[l]);
  return text.replaceRange(a, b, _cleanJoin(text, toks, first, l));
}

/// 逐词应用(倒序,前面词下标不漂移),每步重扫。禁用批量用。
String _batchEach(
  String text,
  int first,
  int last,
  String Function(String, Tok) op,
) {
  var out = text;
  for (var i = last; i >= first; i--) {
    final toks = parseToks(out);
    if (i >= toks.length) continue;
    out = op(out, toks[i]);
  }
  return out;
}

/// 批量设置禁用状态(web 语义:第一枚的状态决定目标,全体对齐)。
/// 逐词应用,保留各自权重与组记号。
String batchSetDisabled(String text, int first, int last, bool disabled) =>
    _batchEach(
      text,
      first,
      last,
      (s, t) => t.disabled == disabled ? s : toggleTokDisabled(s, t),
    );

/// 批量删除:整段(含组记号)连一侧分隔一起删,返回 (新文本, 光标)。
(String, int) batchDelete(String text, int first, int last) {
  final toks = parseToks(text);
  if (toks.isEmpty || first >= toks.length) return (text, 0);
  final l = _clampLast(toks, last);
  var (a, b) = _rangeBounds(text, toks[first], toks[l]);
  // 同 deleteTok:优先吞右侧逗号,否则吞左侧
  var e = b;
  while (e < text.length && (text[e] == ' ' || text[e] == '\t')) {
    e++;
  }
  if (e < text.length && (text[e] == ',' || text[e] == '，')) {
    e++;
    while (e < text.length && text[e] == ' ') {
      e++;
    }
    b = e;
  } else {
    var st = a;
    while (st > 0 && text[st - 1] == ' ') {
      st--;
    }
    if (st > 0 && (text[st - 1] == ',' || text[st - 1] == '，')) {
      st--;
      while (st > 0 && text[st - 1] == ' ') {
        st--;
      }
      a = st;
    }
  }
  final out = text.replaceRange(a, b, '');
  return (out, a.clamp(0, out.length));
}

// ---- SD WebUI 权重语法(web isSDWeightFormat / convertSDToNAI 移植)----

final _sdWeightRe = RegExp(r'^\((.+?)(?::(-?\d+(?:\.\d+)?))?\)$');

/// 词条是否为 SD 权重语法 `(tag:1.2)` 或 `(tag)`。
bool isSdWeightSeg(String seg) => _sdWeightRe.hasMatch(seg.trim());

/// SD → NAI 转换:`(tag)`→`{tag}`;`(tag:≈1)`→纯名;`(tag:w)`→`w::tag::`。
/// 非 SD 语法原样返回。下划线还原为空格(app 内标签统一空格形式)。
String sdToNaiSeg(String seg) {
  final m = _sdWeightRe.firstMatch(seg.trim());
  if (m == null) return seg;
  final tag = m.group(1)!.replaceAll('_', ' ').trim();
  final w = m.group(2) == null ? null : double.tryParse(m.group(2)!);
  if (w == null) return '{$tag}';
  if ((w - 1.0).abs() < 0.01) return tag;
  return '${fmtMult(w)}::$tag::';
}

(String, int) deleteTok(String text, Tok t) {
  var a = t.segStart, b = t.segEnd;
  var e = b;
  while (e < text.length && (text[e] == ' ' || text[e] == '\t')) {
    e++;
  }
  if (e < text.length && (text[e] == ',' || text[e] == '，')) {
    e++;
    while (e < text.length && text[e] == ' ') {
      e++;
    }
    b = e;
  } else {
    var st = a;
    while (st > 0 && text[st - 1] == ' ') {
      st--;
    }
    if (st > 0 && (text[st - 1] == ',' || text[st - 1] == '，')) {
      st--;
      while (st > 0 && text[st - 1] == ' ') {
        st--;
      }
      a = st;
    }
  }
  return (text.replaceRange(a, b, ''), a);
}

/// 词条重排(排序清单用):把第 [from] 枚移到 [to](移除后下标)。
/// 槽位填充:每枚的原样文本(含权重/禁用语法)按新顺序填回原有的
/// N 个槽,槽间分隔(逗号/换行/空格)原样保留——用户排版不被打平。
String reorderToks(String text, int from, int to) {
  final toks = parseToks(text);
  if (from < 0 || from >= toks.length || from == to) return text;
  final segs = [for (final t in toks) text.substring(t.segStart, t.segEnd)];
  final moved = segs.removeAt(from);
  segs.insert(to.clamp(0, segs.length), moved);
  var out = text;
  for (var i = toks.length - 1; i >= 0; i--) {
    out = out.replaceRange(toks[i].segStart, toks[i].segEnd, segs[i]);
  }
  return out;
}

// ---- 折叠的增删改 ----

/// 区间 [a,b) 连一侧分隔一起吞(同 deleteTok:优先右侧逗号,否则左侧)。
(int, int) _withSeparator(String text, int a, int b) {
  var e = b;
  while (e < text.length && (text[e] == ' ' || text[e] == '\t')) {
    e++;
  }
  if (e < text.length && (text[e] == ',' || text[e] == '，')) {
    e++;
    while (e < text.length && text[e] == ' ') {
      e++;
    }
    return (a, e);
  }
  var st = a;
  while (st > 0 && text[st - 1] == ' ') {
    st--;
  }
  if (st > 0 && (text[st - 1] == ',' || text[st - 1] == '，')) {
    st--;
    while (st > 0 && text[st - 1] == ' ') {
      st--;
    }
    return (st, b);
  }
  return (a, b);
}

/// 剥掉折叠记号,内容原样保留(含分隔与换行)。[outputOf] 的一环。
/// 内容被剔空的折叠(成员全被禁用)整只删掉并吞一侧逗号——否则
/// `a, <n: ~b~>, c` 会留下 `a, , c` 这样的空段发给 NAI。
String stripFolds(String text) {
  final folds = parseFolds(text);
  if (folds.isEmpty) return text;
  var out = text;
  // 倒序改写(折叠互不重叠且从左到右收集),前面的下标不漂移;
  // 单只折叠内先删尾记号再删头记号,同理。
  for (final f in folds.reversed) {
    if (out.substring(f.bodyStart, f.bodyEnd).trim().isEmpty) {
      final (a, b) = _withSeparator(out, f.start, f.end);
      out = out.replaceRange(a, b, '');
      continue;
    }
    if (f.end > f.bodyEnd) out = out.replaceRange(f.bodyEnd, f.end, '');
    out = out.replaceRange(f.start, f.bodyStart, '');
  }
  return out;
}

/// 折叠名里不能出现分隔与记号字符,否则解析必错位。空名兜底为「折叠」。
String sanitizeFoldName(String s) {
  final out = s
      .replaceAll(kFoldZw, '') // 零宽空格是占位符边界,名字里混入会毁掉解析
      .replaceAll(RegExp(r'[,，:<>\r\n\t]'), ' ')
      .trim();
  return out.isEmpty ? '折叠' : out;
}

/// 区间能否折叠:与任何既有折叠交叠则不行(折叠不嵌套)。
/// 按解析结果判而不是扫 `<`/`>` 字符——`>_<`、`<3` 这类颜文字 tag 是
/// 合法内容,不该因为长得像记号就被拦住。
/// 按钮可用态与 [foldRange] 的拒绝条件同源,不会出现「点了没反应」。
bool canFoldRange(String text, int first, int last) {
  final toks = parseToks(text);
  if (toks.isEmpty || first >= toks.length) return false;
  final l = _clampLast(toks, last);
  final (a, b) = _rangeBounds(text, toks[first], toks[l]);
  for (final f in parseFolds(text)) {
    if (a < f.end && b > f.start) return false;
  }
  return true;
}

/// 把词条区间 [first, last] 包成命名折叠。不可折时原样返回。
String foldRange(String text, int first, int last, String name) {
  if (!canFoldRange(text, first, last)) return text;
  final toks = parseToks(text);
  final l = _clampLast(toks, last);
  final (a, b) = _rangeBounds(text, toks[first], toks[l]);
  final sub = text.substring(a, b);
  return text.replaceRange(
    a,
    b,
    '<#${sanitizeFoldName(name)}: $sub$kFoldClose',
  );
}

/// 把一串标签包成命名折叠,供**批量加入**的来源调用(补全的画师串 / OC
/// 标签组、灵感的条目)。折叠是 app 内部产物,名字即来源,用户不再手工建组。
///
/// 三种情况原样返回不折:
/// - 空串;
/// - 只有一枚标签 —— 折一枚没有意义,徒增记号;
/// - 串里已经有折叠 —— 折叠不嵌套。
String foldWrap(String name, String tags) {
  final t = tags.trim();
  if (t.isEmpty) return t;
  if (parseToks(t).length < 2) return t;
  if (parseFolds(t).isNotEmpty) return t;
  return '<#${sanitizeFoldName(name)}: $t$kFoldClose';
}

// ---- 折叠占位符(编辑器会话内的表现形式)----
//
// 折叠体**不进 TextField**:正文里只放短占位符 `​#名字​`(外观即
// `#名字`,边界是零宽空格),折叠体存在编辑器
// 会话的旁路表(名字 → 内容)里;载入时 [collapseFolds] 把草稿的完整语法拆成
// 「占位符 + 表」,回写时 [expandFolds] 拼回完整语法落草稿。
//
// 为什么绕这一道:此前把完整语法留在正文、靠渲染层把折叠体「藏」起来
// (fontSize 0.01 → 真机字形引擎 clamp 亚像素字号,长折叠体累积撑爆行宽;
// 负 letterSpacing 收零 → 真机断行器算出鬼缩进)。任何在 EditableText 里藏字
// 的手段都是在跟字形引擎搏斗,测试环境(Ahem 字体)全过、真机接连翻车。
// 占位符方案下 **TextField 里没有任何不显示的字符**——正文所见即所有,
// 这类 bug 从机制上消失。消息 app 的 @mention chip 同款架构。

/// 占位符边界:零宽空格(U+200B)。**字体层面**无宽度——不是样式技巧,
/// 与此前翻车的 fontSize/letterSpacing 藏字是两回事;肉眼只看到 `#名字`。
/// 键盘打不出它,占位符因此**不可能**与用户手打的文本相撞,比 `<#…>`
/// 字面边界更稳(那版外观带尖括号,也可能被手打字符误触)。
const String kFoldZw = '​';

/// 占位符:`​#名字​`(两侧零宽空格)。名字沿用 [sanitizeFoldName] 的字符集。
final _foldRefRe = RegExp('$kFoldZw#([^$kFoldZw<>:,，\r\n]+)$kFoldZw');

/// 拼一枚占位符字面量。
String foldRefLiteral(String name) => '$kFoldZw#$name$kFoldZw';

/// 正文里的一枚折叠占位符。
class FoldRef {
  const FoldRef(this.start, this.end, this.name);

  /// 前导零宽空格下标 / 尾随零宽空格之后。
  final int start;
  final int end;
  final String name;

  /// 标题可见段 `#名字`(去掉两侧零宽空格),药丸底纹与点击热区用。
  (int, int) get titleRange => (start + 1, end - 1);
}

/// 扫出正文里的全部占位符(名字必须在 [bodies] 里挂了号才算折叠——
/// 用户手打的 `<#xx>` 不认,当普通文本走)。
List<FoldRef> parseFoldRefs(String text, Map<String, String> bodies) => [
  for (final m in _foldRefRe.allMatches(text))
    if (bodies.containsKey(m.group(1)!)) FoldRef(m.start, m.end, m.group(1)!),
];

/// 草稿(完整语法)→ (正文, 折叠表)。完整折叠 `<#名字: 内容#>` 收成占位符,
/// 内容进表;重名且内容不同 → 追加「 2」「 3」去重(名字是表键,必须唯一)。
/// [seed] 是已占用的名字表(正/负两侧共用一张表时,后收的一侧要避开先收的)。
(String, Map<String, String>) collapseFolds(
  String draft, {
  Map<String, String> seed = const {},
}) {
  final folds = parseFolds(draft);
  if (folds.isEmpty) return (draft, const {});
  final bodies = <String, String>{};
  var out = draft;
  for (final f in folds.reversed) {
    final body = draft.substring(f.bodyStart, f.bodyEnd).trim();
    var name = f.name;
    var n = 2;
    bool taken(String s) =>
        (bodies.containsKey(s) && bodies[s] != body) ||
        (seed.containsKey(s) && seed[s] != body);
    while (taken(name)) {
      name = '${f.name} ${n++}';
    }
    bodies[name] = body;
    out = out.replaceRange(f.start, f.end, foldRefLiteral(name));
  }
  return (out, bodies);
}

/// 给 [name] 找一个在 [taken] 里未占用(或同体可复用)的名字。
/// 插入路径(补全的画师串 / OC)注册折叠体时用。
String uniqueFoldName(String name, String body, Map<String, String> taken) {
  final base = sanitizeFoldName(name);
  var out = base;
  var n = 2;
  while (taken.containsKey(out) && taken[out] != body) {
    out = '$base ${n++}';
  }
  return out;
}

/// (正文, 折叠表)→ 草稿(完整语法)。按占位符所处的逗号段分三种情况:
/// - 段恰为占位符自身 → 还原完整折叠 `<#名字: 内容#>`(下次载入原样收回);
/// - 段为 `~<#名字>~`(折叠被整只禁用)→ 内容逐成员套 `~`(折叠随之解散);
/// - 其余(被 `{}` / `N::` 组语法包住等)→ 内容裸铺进去(组权重照常作用于
///   成员,折叠解散)——完整语法塞在组记号里会错位解析不出,宁可降级也
///   绝不让记号漏给 NAI。
String expandFolds(String text, Map<String, String> bodies) {
  final refs = parseFoldRefs(text, bodies);
  var out = text;
  for (final r in refs.reversed) {
    final body = bodies[r.name]!;
    // 占位符所处逗号段
    var a = r.start;
    while (a > 0 &&
        out[a - 1] != ',' &&
        out[a - 1] != '，' &&
        out[a - 1] != '\n') {
      a--;
    }
    var b = r.end;
    while (b < out.length && out[b] != ',' && out[b] != '，' && out[b] != '\n') {
      b++;
    }
    final seg = out.substring(a, b).trim();
    final String ins;
    if (seg == foldRefLiteral(r.name)) {
      ins = '<#${r.name}: $body$kFoldClose';
    } else if (seg == '~${foldRefLiteral(r.name)}~') {
      final toks = parseToks(body);
      ins = toks.isEmpty
          ? ''
          : batchSetDisabled(body, 0, toks.length - 1, true);
      // 替换含两侧 ~(整段重写)
      out = out.replaceRange(
        out.indexOf('~', a),
        out.indexOf('~', r.end) + 1,
        ins,
      );
      continue;
    } else {
      ins = body;
    }
    out = out.replaceRange(r.start, r.end, ins);
  }
  return out;
}

/// 顶层单元:排序视图的基本单位——一枚散标签,或一枚折叠占位符。
/// 折叠作为**一个整体**移动,绝不会被拆散或让别的标签卷进去。
class TopUnit {
  const TopUnit(this.start, this.end, this.fold, this.tok);
  final int start;
  final int end;

  /// 折叠单元:非空;散标签单元:null。
  final FoldRef? fold;

  /// 散标签单元:非空;折叠单元:null。
  final Tok? tok;

  bool get isFold => fold != null;
}

/// 把正文切成顶层单元序列。占位符必须独占一个逗号段(tok 与 ref 区间恰好
/// 重合)才算折叠单元;被杂字符粘连(`x<#n>`)的降级为普通标签,不误伤。
List<TopUnit> topLevelUnits(String text, Map<String, String> bodies) {
  final refs = parseFoldRefs(text, bodies);
  final toks = parseToks(text);
  final units = <TopUnit>[];
  for (final t in toks) {
    FoldRef? hit;
    for (final r in refs) {
      if (r.start == t.segStart && r.end == t.segEnd) {
        hit = r;
        break;
      }
    }
    units.add(
      hit != null
          ? TopUnit(t.segStart, t.segEnd, hit, null)
          : TopUnit(t.segStart, t.segEnd, null, t),
    );
  }
  return units;
}

/// 末尾追加一枚顶层单元(芯片模式尾部输入框的落地口径)。
/// 正文原本怎么收尾就怎么接:已有逗号只补空格,已有换行直接接在新行上,
/// 其余补 `, ` —— 用户的排版(换行分段)不因为加了个词就被拍平成一行。
String appendUnit(String text, String tag) {
  final add = tag.trim();
  if (add.isEmpty) return text;
  // 只吃行内空白,末尾的换行留着 —— 那是用户分的段
  var end = text.length;
  while (end > 0 && (text[end - 1] == ' ' || text[end - 1] == '\t')) {
    end--;
  }
  final base = text.substring(0, end);
  if (base.trim().isEmpty) return add;
  final last = base[base.length - 1];
  final sep = last == '\n'
      ? ''
      : (last == ',' || last == '，')
      ? ' '
      : ', ';
  return '$base$sep$add';
}

/// 顶层单元重排:把第 [from] 个单元移到 [to](移除后下标)。槽位法——各单元
/// 原文按新序填回原有槽,槽间分隔(逗号/换行)原样保留。
String reorderUnits(String text, Map<String, String> bodies, int from, int to) {
  final units = topLevelUnits(text, bodies);
  if (from < 0 || from >= units.length || from == to) return text;
  final segs = [for (final u in units) text.substring(u.start, u.end)];
  final moved = segs.removeAt(from);
  segs.insert(to.clamp(0, segs.length), moved);
  var out = text;
  for (var i = units.length - 1; i >= 0; i--) {
    out = out.replaceRange(units[i].start, units[i].end, segs[i]);
  }
  return out;
}

/// 顶层单元多选移动:把 [from] 里的若干单元整体搬到间隙 [to](原序下标,
/// 0..n 表示"插到第 to 个单元之前")。被选中的单元保持彼此原有相对顺序。
///
/// 与 [reorderUnits] 同一套槽位法:各单元原文按新序填回原槽,槽间分隔
/// (逗号/换行)原样留在原地,不会因为搬动而多出或吃掉逗号。
String moveUnits(
  String text,
  Map<String, String> bodies,
  Iterable<int> from,
  int to,
) {
  final units = topLevelUnits(text, bodies);
  final n = units.length;
  final sel = {
    for (final i in from)
      if (i >= 0 && i < n) i,
  }.toList()..sort();
  if (sel.isEmpty || sel.length == n) return text;
  // 选中的**正好**是一整个权重组 → 连组记号一起搬(见 [_moveGroupBlock])。
  // 只挑了组里的一部分不走这条:那时用户要的是把这几枚拿出去,组留在原地。
  for (final g in unitGroups(text, units)) {
    if (g.coversExactly(sel)) return _moveGroupBlock(text, units, g, to);
  }
  final segs = [for (final u in units) text.substring(u.start, u.end)];
  final picked = [for (final i in sel) segs[i]];
  // 目标位置换算到"剔除选中项之后"的下标:数一数 to 左边还剩几个没被选中的。
  var at = 0;
  for (var i = 0; i < to && i < n; i++) {
    if (!sel.contains(i)) at++;
  }
  final rest = [
    for (var i = 0; i < n; i++)
      if (!sel.contains(i)) segs[i],
  ]..insertAll(at.clamp(0, n - sel.length), picked);
  var out = text;
  for (var i = n - 1; i >= 0; i--) {
    out = out.replaceRange(units[i].start, units[i].end, rest[i]);
  }
  return out;
}

/// 选中单元切成**极大连续段**。权重类批量按段整体包裹(`{a, b}` /
/// `m::a, b::`),段与段互不牵连 —— 多选模式可以跳着选,没选中的词绝不能被
/// 卷进同一层括号里;划词多选天然只有一段,与从前逐字节一致。
///
/// 只含一枚折叠单元的段丢弃:给占位符**单独**套括号 / `::`,它的区间就不再
/// 与 tok 段重合,[topLevelUnits] 当场把它降级成普通标签,折叠就散了(同
/// [setUnitsDisabled] 的顾虑)。段里还有别的词条时括号落在**组**上,占位符
/// 自身区间不变,折叠安然无恙。
List<(int, int)> weightRuns(List<TopUnit> units, Iterable<int> idx) {
  final sel = {
    for (final i in idx)
      if (i >= 0 && i < units.length) i,
  }.toList()..sort();
  final runs = <(int, int)>[];
  var k = 0;
  while (k < sel.length) {
    var j = k;
    while (j + 1 < sel.length && sel[j + 1] == sel[j] + 1) {
      j++;
    }
    if (k != j || !units[sel[k]].isFold) runs.add((sel[k], sel[j]));
    k = j + 1;
  }
  return runs;
}

/// 整组搬动:把 [g] 的成员**连同外面那层组记号**当一整块挪到间隙 [to]。
///
/// 为什么要单开一条路:组记号(`1.3::` 与收尾的 `::`)落在词条 seg **之外**的
/// 分隔区,而 [moveUnits] 的槽位法只搬各单元自己那一格 —— 于是壳子会原地不动,
/// 谁滑进那两格谁就接管这份加权,搬走的那批反倒裸着出去。这里把整组并成一格
/// 槽,组内的逗号跟着一起走,记号自然也就跟着走了。
String _moveGroupBlock(String text, List<TopUnit> units, UnitGroup g, int to) {
  final n = units.length;
  // 槽:组前面每枚各一格 + 组自己一格(含记号)+ 组后面每枚各一格
  final slots = <(int, int)>[
    for (var i = 0; i < g.first; i++) (units[i].start, units[i].end),
    (g.start, g.end),
    for (var i = g.last + 1; i < n; i++) (units[i].start, units[i].end),
  ];
  // 单元间隙 → 槽间隙(剔掉组块之后的下标)。落在组内部/两端的间隙都是原位。
  final int at;
  if (to <= g.first) {
    at = to;
  } else if (to <= g.last + 1) {
    at = g.first;
  } else {
    at = to - g.length;
  }
  final segs = [for (final (a, b) in slots) text.substring(a, b)];
  final moved = segs.removeAt(g.first);
  segs.insert(at.clamp(0, segs.length), moved);
  var out = text;
  for (var i = slots.length - 1; i >= 0; i--) {
    out = out.replaceRange(slots[i].$1, slots[i].$2, segs[i]);
  }
  return out;
}

/// 顶层权重组:一层权重记号罩住的**连续**顶层单元区间。
class UnitGroup {
  const UnitGroup(this.first, this.last, this.mult, this.start, this.end);

  /// 首 / 末成员的顶层单元下标(闭区间)。
  final int first;
  final int last;

  /// 这一层记号自己的倍率(不含外层)。
  final double mult;

  /// 原文区间,**含**组记号与成员之间的逗号 —— 整组搬动时搬的就是这一段。
  final int start;
  final int end;

  int get length => last - first + 1;

  /// [sel] 是否**不多不少**正好是本组的全部成员。
  bool coversExactly(List<int> sortedSel) =>
      sortedSel.length == length &&
      sortedSel.first == first &&
      sortedSel.last == last;
}

/// 顶层权重组:一个权重记号罩住**≥2 枚**顶层单元(`1.3::a, b::` / `{a, b}`)
/// 时的成员区间与倍率。芯片模式据此把成员圈成一块、读数只报一次,整组搬动
/// 也认这个区间。
///
/// 单枚词条自带的数值/括号权重**不算组** —— 那是它自己的事,芯片上照常内联
/// 报数。判据就是「盖住几枚」:`1.2::solo::` 盖住一枚,`1.2::a, b::` 盖住两枚。
///
/// 嵌套只取**最外**那层:一层框已经够读,套娃只会把词挤没。内层剩下的那点
/// 倍率仍由成员芯片内联报出(它的 effMult 除掉这层),合起来还是有效权重。
List<UnitGroup> unitGroups(String text, List<TopUnit> units) {
  if (units.length < 2) return const [];
  final spans = <WeightSpan>[];
  parseToks(text, weightSpans: spans);
  final runs = <UnitGroup>[];
  for (final sp in spans) {
    var a = -1, b = -1;
    for (var i = 0; i < units.length; i++) {
      if (units[i].end <= sp.start || units[i].start >= sp.end) continue;
      if (a < 0) a = i;
      b = i;
    }
    if (a < 0 || b <= a) continue; // 只盖住一枚 = 它自己的权重,不是组
    runs.add(UnitGroup(a, b, sp.mult, sp.start, sp.end));
  }
  // 宽的先来,被别人整段包住的丢掉 —— 留下的就是互不重叠的最外层。
  runs.sort((x, y) => y.length.compareTo(x.length));
  final out = <UnitGroup>[];
  for (final r in runs) {
    if (out.any((o) => r.first >= o.first && r.last <= o.last)) continue;
    out.add(r);
  }
  out.sort((x, y) => x.first.compareTo(y.first));
  return out;
}

/// 顶层单元多选的权重批量(套括号 / 统一数值 / 清除):按 [weightRuns] 切出的
/// 连续段逐段应用,**倒序** —— 后面的段先改,前面的段下标不漂移。
///
/// 段边界直接喂给范围版 `batch*`:[topLevelUnits] 与 [parseToks] 一一对应
/// (一个逗号段一枚),单元下标与词条下标本就是同一个空间。
String batchWrapUnits(
  String text,
  Map<String, String> bodies,
  Iterable<int> idx, {
  required bool up,
}) {
  var out = text;
  for (final (a, b) in weightRuns(topLevelUnits(text, bodies), idx).reversed) {
    out = batchWrap(out, a, b, up: up);
  }
  return out;
}

String batchSetMultUnits(
  String text,
  Map<String, String> bodies,
  Iterable<int> idx,
  double m,
) {
  var out = text;
  for (final (a, b) in weightRuns(topLevelUnits(text, bodies), idx).reversed) {
    out = batchSetMult(out, a, b, m);
  }
  return out;
}

String batchClearWeightUnits(
  String text,
  Map<String, String> bodies,
  Iterable<int> idx,
) {
  var out = text;
  for (final (a, b) in weightRuns(topLevelUnits(text, bodies), idx).reversed) {
    out = batchClearWeight(out, a, b);
  }
  return out;
}

/// 顶层单元多选设禁用。**折叠单元跳过** —— 给占位符套上 `~` 会让它的区间
/// 不再与 tok 段重合,[topLevelUnits] 当场把它降级成普通标签,折叠就散了。
///
/// 倒序逐个应用,前面的下标不漂移(同 [_batchEach])。
String setUnitsDisabled(
  String text,
  Map<String, String> bodies,
  Iterable<int> idx,
  bool disabled,
) {
  final sel = idx.toList()..sort();
  var out = text;
  for (var k = sel.length - 1; k >= 0; k--) {
    final units = topLevelUnits(out, bodies);
    final i = sel[k];
    if (i < 0 || i >= units.length) continue;
    final t = units[i].tok;
    if (t == null || t.disabled == disabled) continue;
    out = toggleTokDisabled(out, t);
  }
  return out;
}

/// 顶层单元多选删除 → (新文本, 光标)。折叠走 [deleteFoldRef](整只删,
/// 不啃出残渣),散标签走 [deleteTok];同样倒序,下标不漂移。
(String, int) deleteUnits(
  String text,
  Map<String, String> bodies,
  Iterable<int> idx,
) {
  final sel = idx.toList()..sort();
  var out = text;
  var cursor = 0;
  for (var k = sel.length - 1; k >= 0; k--) {
    final units = topLevelUnits(out, bodies);
    final i = sel[k];
    if (i < 0 || i >= units.length) continue;
    final u = units[i];
    final (next, c) = u.isFold
        ? deleteFoldRef(out, u.fold!)
        : deleteTok(out, u.tok!);
    out = next;
    cursor = c;
  }
  return (out, cursor.clamp(0, out.length));
}

/// 整只删除折叠占位符(连同一侧分隔)→ (新文本, 光标)。折叠是 app 造的整体,
/// 正文里不给逐字啃——啃烂占位符会留下解析不出的残渣。
(String, int) deleteFoldRef(String text, FoldRef r) {
  final (a, b) = _withSeparator(text, r.start, r.end);
  final out = text.replaceRange(a, b, '');
  return (out, a.clamp(0, out.length));
}

/// 解散折叠(一次性):占位符原地替换为内容,标题消失、成员平铺。
String unfoldRef(String text, FoldRef r, Map<String, String> bodies) =>
    text.replaceRange(r.start, r.end, bodies[r.name] ?? '');

/// 输出串:**原样保留**(换行/间距/权重语法都不动),剔除禁用项
/// (连同邻近逗号,同 deleteTok)并剥掉折叠记号。回写生成页 + 计 token。
/// 早期按段 join(', ') 重组会抹掉用户换行,故改为原文剔除式。
String outputOf(String text) {
  var out = text;
  while (true) {
    Tok? victim;
    for (final t in parseToks(out)) {
      if (t.disabled) {
        victim = t;
        break;
      }
    }
    if (victim == null) break;
    final (next, _) = deleteTok(out, victim);
    out = next; // deleteTok 必删非空段,长度严格递减,不会死循环
  }
  // 零宽空格是占位符边界(仅编辑期),孤儿占位符降级直传时把它滤干净
  return stripFolds(out).replaceAll(kFoldZw, '').trim();
}

int estimateTokens(String output) =>
    (output.length / 2.2).round().clamp(0, 999);

// ---- 编辑器原文草稿 ----
// 禁用 `~tag~` 与折叠 `<#名字: …>` 是**仅编辑期**的语法:[outputOf] 会把它们
// 剥掉,所以定稿里没有它们,只回写定稿的话退出编辑器就丢。故定稿旁另存一份
// 原文草稿。有效性**只在读取侧判定**——草稿剔除编辑期语法后必须等于定稿,
// 否则说明提示词被编辑器之外改过(导入/灵感追加/清空/权重工具),草稿已过期。
// 这样写入方一个都不用改,也不会出现陈年草稿顶掉用户新提示词的鬼故事。

/// 取编辑器该载入的文本:草稿有效则用草稿(带回禁用/折叠),否则用定稿。
String pickEditorText(String raw, String finalText) =>
    raw.isNotEmpty && outputOf(raw) == finalText ? raw : finalText;

/// 取该落盘的草稿:与定稿无差别时返回空串,不在存档里存两份一样的串。
String draftOf(String raw, String finalText) =>
    raw.trim() == finalText ? '' : raw;

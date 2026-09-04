// 数值权重组 `N::…::` 的边界 —— 与桌面端 novelai_web_ui 的
// `src/components/PromptEditor.tsx` 权重装饰(Pass 2)同规则:
// 右界 = min(最近的闭合 `::`, 下一个 `N::` 前缀)。
//
// 钉这两条老实现踩过的坑:
// ① 闭记号落在逗号**之后**(`0.5::a,::b`)照样收口 —— 老实现按逗号切段、
//    只认「段尾以 :: 结尾」,收不了口的组一路吞到文末(实机截图:整屏权重
//    底色糊成一片);
// ② 未闭合的组被下一个 `N::` 前缀截断,不吞掉后面的组 —— 老实现是再压一层
//    栈,倍率连乘,后面的词条 effMult 被连乘成异常值(报橙色警告)。
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/editor/editor_models.dart';

/// (name, effMult) 便于逐词条断言
List<(String, double)> _toks(String text) => [
  for (final t in parseToks(text)) (t.name, t.effMult),
];

/// (原文片段, 倍率) 便于断言权重可视区间
List<(String, double)> _spans(String text) {
  final spans = <WeightSpan>[];
  parseToks(text, weightSpans: spans);
  return [for (final s in spans) (text.substring(s.start, s.end), s.mult)];
}

void main() {
  test('闭记号在逗号之后:收得了口,不吞后文', () {
    // 实机截图里的真实形态(画师串被写成 `w::name,::` )
    const t =
        '0.5::artist:fujiyama,::artist:motimoti067,'
        '0.8::artist:ham_melon::,tail';
    expect(_toks(t), [
      ('artist:fujiyama', 0.5),
      ('artist:motimoti067', 1.0), // 组已收口 → 不受 0.5 影响
      ('artist:ham_melon', 0.8),
      ('tail', 1.0),
    ]);
    expect(_spans(t), [
      ('0.5::artist:fujiyama,::', 0.5), // 底色恰好裹住该组,含闭记号
      ('0.8::artist:ham_melon::', 0.8),
    ]);
  });

  test('数字后接三冒号 `1.5:::` 不崩溃(开记号与收口重叠)', () {
    // 打权重时 `1.5::` 后再补一个冒号,三冒号里两对 `::` 共用中间那个,
    // 曾算出 nameStart > nameEnd 让 substring 抛 RangeError,连累注音/权重
    // 底色/富文本三处 parseToks 全崩,屏上一大片灰。现应降级为普通文本。
    for (final t in ['1:::', '1.5:::', '20:::', '-3:::']) {
      expect(() => parseToks(t), returnsNormally, reason: t);
      final spans = <WeightSpan>[];
      final toks = parseToks(t, weightSpans: spans);
      expect(toks.single.name, t, reason: '$t 整枚当普通文本'); // 未成词条权重
      expect(toks.single.effMult, 1.0, reason: t);
      expect(spans, isEmpty, reason: '$t 不铺权重底色');
    }
    // 打全收口即恢复正常上色
    expect(_toks('1.5::x::'), [('x', 1.5)]);
  });

  test('未闭合的组被下一个前缀截断,倍率不连乘', () {
    const t = '0.5::a, b, 0.8::c::';
    expect(_toks(t), [
      ('a', 0.5),
      ('b', 0.5),
      ('c', 0.8), // 不是 0.5×0.8 —— 前一组到此已被截断
    ]);
    expect(_spans(t), [('0.5::a, b, ', 0.5), ('0.8::c::', 0.8)]);
  });

  test('正常跨词条组:组内全员生效,组外不受影响', () {
    const t = '1.2::a, b::, c';
    expect(_toks(t), [('a', 1.2), ('b', 1.2), ('c', 1.0)]);
    expect(_spans(t), [('1.2::a, b::', 1.2)]);
  });

  test('单词条自身权重不当跨段组处理', () {
    const t = '1.2::a::, b';
    expect(_toks(t), [('a', 1.2), ('b', 1.0)]);
    expect(_spans(t), [('1.2::a::', 1.2)]);
  });

  test('括号组不受影响', () {
    const t = '{a, b}, c';
    expect(_toks(t), [('a', 1.05), ('b', 1.05), ('c', 1.0)]);
    expect(_spans(t), [('{a, b}', 1.05)]);
  });

  test('负权重组照常', () {
    const t = '-2::a, b::, c';
    expect(_toks(t), [('a', -2.0), ('b', -2.0), ('c', 1.0)]);
  });

  // `::` 在 NAI 里本身就是分隔符,不少人拿它当逗号使:写完一个词直接跟下一段
  // 的权重,中间不打逗号。老实现开组时把 a 一跳跳到组内容处,开记号前面那截
  // **整段丢了** —— 不成词条(没注音、没翻译、词条栏点不着),屏幕上是一截灰字。
  test('开记号前面的内容不能丢:`a::1.5::b` 里的 a 照样成词条', () {
    const t =
        'print,constellation print in grey pantyhose::1.5::gothic lolita,'
        'black lolita';
    expect(_toks(t), [
      ('print', 1.0),
      ('constellation print in grey pantyhose', 1.0), // 曾经整个消失
      ('gothic lolita', 1.5),
      ('black lolita', 1.5), // 未闭合的组延伸到文末
    ]);
    // 权重区间只圈组本身,前面那截不该被染色
    expect(_spans(t), [('1.5::gothic lolita,black lolita', 1.5)]);
  });

  test('开记号紧跟逗号时不误伤(本来就没有头部)', () {
    const t = 'a,1.5::b';
    expect(_toks(t), [('a', 1.0), ('b', 1.5)]);
  });

  // 未闭合的组右界是「下一个前缀 / 文末」截出来的,不是闭记号 —— 剥记号那步
  // 却照着 end-2 削两个字符,削掉的是用户的正文。
  test('未闭合的组不能把末尾两个字符当闭记号削掉', () {
    const t = '1.2::a, black lolita';
    expect(_toks(t), [('a', 1.2), ('black lolita', 1.2)]); // 曾经变成 black loli
  });

  // 已知未覆盖:闭记号落在段**中间**(`1.2::a, b::1.5::c` 里的 `b::`),
  // 现在整段会当成一枚名叫 `b::1.5::c` 的词条。段首/段尾收口都认,唯独段中
  // 不认 —— 真遇到再说,现网数据里没见过这种写法。
}

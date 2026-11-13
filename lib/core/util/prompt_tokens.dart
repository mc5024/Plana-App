/// 提示词分词:去权重记号/括号/冒号 → 压空白 → 小写 → 逗号切词。
/// 灵感库判断「这条提示词里已经有哪些标签」、图库按角色 / 画风归类都用它。
///
/// 起步口径同 bot 端 `utils/png_data.py` 的 `_clean_token`,另加三条归一 ——
/// 都是真实数据里撞出来的写法分歧,提示词与条目两边同归一才配得上:
///   - **下划线归空格**:`long_hair` 与 `long hair`;
///   - **圆括号归空格**:`lobelia(saclia)`、`lobelia (saclia)`、`lobelia_(saclia)`
///     三种写法都有,直接删括号会把第一种粘成一个词;
///   - **摘掉 `artist:` 前缀**:公共画师串库里同一个画师带前缀、不带前缀的写法
///     都有,而删冒号会把 `artist:wlop` 粘成 `artistwlop`,跟 `wlop` 永远对不上。
library;

final _reWeight = RegExp(r'[+-]?\d+(?:\.\d+)?::');
final _reBrackets = RegExp(r'[\[\]{}]');
final _reParens = RegExp(r'[()]');
// 不加词边界:检索索引会先删掉 `::`,`a::artist:b` 连写时第二个前缀就紧贴在
// 上一个画师名后面(`aartist:b`),加了词边界反而摘不掉。
final _reArtistPrefix = RegExp(r'artist:\s*', caseSensitive: false);
final _reSpaces = RegExp(r'\s+');

String cleanPromptToken(String s) {
  var t = s.replaceAll(_reWeight, '');
  t = t.replaceAll(_reBrackets, '');
  // 圆括号换成空格而不是删掉,`lobelia(saclia)` 才不会粘成一个词
  t = t.replaceAll(_reParens, ' ');
  // 前缀得赶在删冒号之前摘,删完冒号它就和画师名粘在一起了
  t = t.replaceAll(_reArtistPrefix, '');
  t = t.replaceAll(':', '');
  // 下划线归一为空格(提示词与词库两种写法都存在,双边同归一才配得上)
  t = t.replaceAll('_', ' ');
  return t.replaceAll(_reSpaces, ' ').trim().toLowerCase();
}

/// 逗号(中英文)/ 换行切词 → 清洗 → 去重集合。
Set<String> tokenizeSet(String text) {
  final out = <String>{};
  for (final p in text.split(RegExp(r'[，,\n]'))) {
    final t = cleanPromptToken(p);
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// 回复像不像在拒绝作画:正文命中词表就算。
///
/// 只拿不出图的回复来判 —— 交出了出图块就说明它做了事,正文里的「不能」多半是在解释某个 tag。
library;

const kRefusalKeywords = [
  '画不了',
  '不能画',
  '这个不行',
  '不能帮你',
  '停下来',
  '不能给你',
  '儿童性内容',
  '底线',
  '幼态角色',
  '安全版本',
  '幼女角色',
  '性内容',
  '没有商量',
  '性行为',
  '未成年',
  '幼女形象',
  '幼女体型',
  '儿童色情',
  '红线',
  '硬线',
  '性化',
  '内容政策',
  'CSAE',
  'CSAM',
  '违反了我的',
  '违背了我的',
];

/// 命中的那个词,不分大小写;没命中返回 null。
String? refusalHit(String reply, [List<String> keywords = kRefusalKeywords]) {
  final low = reply.toLowerCase();
  for (final k in keywords) {
    if (low.contains(k.toLowerCase())) return k;
  }
  return null;
}

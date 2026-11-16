/// AI 一轮回复里的 ```image_gen 块:交给出图模型的话、带哪些参考图、比例。
library;

/// 参考图:用户这条消息附的图。
const kImageRefAttached = 'attached';

/// 参考图:对话里最近一张出好的图。
const kImageRefLast = 'last';

/// 能指定的比例。
const kImageAspects = {'1:1', '2:3', '3:2', '3:4', '4:3', '9:16', '16:9'};

class ImageGenSpec {
  const ImageGenSpec({
    required this.prompt,
    this.refs = const [],
    this.aspect = '',
  });

  final String prompt;

  /// [kImageRefAttached] / [kImageRefLast]。
  final List<String> refs;

  /// 如 `16:9`;空 = 交给出图模型。
  final String aspect;

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    if (refs.isNotEmpty) 'refs': refs,
    if (aspect.isNotEmpty) 'aspect': aspect,
  };

  /// 认不出的参考图、比例丢掉;prompt 不是非空字符串返回 null。
  static ImageGenSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final prompt = j['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) return null;
    final refs = j['refs'];
    final aspect = '${j['aspect'] ?? ''}'.trim();
    return ImageGenSpec(
      prompt: prompt.trim(),
      refs: [
        if (refs is List)
          for (final r in {...refs.map((e) => '$e'.trim())})
            if (r == kImageRefAttached || r == kImageRefLast) r,
      ],
      aspect: kImageAspects.contains(aspect) ? aspect : '',
    );
  }
}

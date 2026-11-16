/// 选着图像模型时一轮的出图请求:交给图像模型的话、带哪些参考图。「重新生成」照它再出一次。
library;

class ImageGenSpec {
  const ImageGenSpec({required this.prompt, this.attached = false, this.refId});

  /// 用户的原话。
  final String prompt;

  /// 带上这轮提问附的图。
  final bool attached;

  /// 带上的上一轮出的图(图库条目 id)。
  final String? refId;

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    if (attached) 'attached': true,
    'refId': ?refId,
  };

  static ImageGenSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final prompt = j['prompt'];
    if (prompt is! String) return null;
    return ImageGenSpec(
      prompt: prompt,
      attached: j['attached'] == true,
      refId: j['refId'] as String?,
    );
  }
}

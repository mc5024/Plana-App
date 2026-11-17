/// 选着图像模型时一轮的出图请求:交给图像模型的话、带不带附图、分辨率、比例和张数。
/// 「重新生成」照它再出一次。
library;

/// 自定义接口能选的比例;后端的按它下发的。
const kImageAspects = ['1:1', '2:3', '3:2', '3:4', '4:3', '9:16', '16:9'];

final _aspect = RegExp(r'^[1-9]\d?:[1-9]\d?$');

/// 「宽:高」这种比例。
bool isImageAspect(String s) => _aspect.hasMatch(s);

/// 能选的分辨率档。
const kImageSizes = ['1K', '2K', '4K'];

/// 一轮最多出几张。
const kMaxImageCount = 4;

class ImageGenSpec {
  const ImageGenSpec({
    required this.prompt,
    this.attached = false,
    this.size = '',
    this.aspect = '',
    this.count = 1,
  });

  /// 用户的原话。
  final String prompt;

  /// 带上这轮提问附的图。
  final bool attached;

  /// 分辨率档 / 比例;空 = 交给图像模型。
  final String size;
  final String aspect;

  /// 出几张,1–[kMaxImageCount]。
  final int count;

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    if (attached) 'attached': true,
    if (size.isNotEmpty) 'size': size,
    if (aspect.isNotEmpty) 'aspect': aspect,
    if (count > 1) 'count': count,
  };

  static ImageGenSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final prompt = j['prompt'];
    if (prompt is! String) return null;
    return ImageGenSpec(
      prompt: prompt,
      attached: j['attached'] == true,
      size: j['size'] as String? ?? '',
      aspect: j['aspect'] as String? ?? '',
      count: ((j['count'] as num?)?.toInt() ?? 1).clamp(1, kMaxImageCount),
    );
  }
}

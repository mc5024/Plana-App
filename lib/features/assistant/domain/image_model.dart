import '../../generate/models.dart' show isAnimaModel, isKreaModel, isNai5Model;

/// 当前显示模型 → 助手认的**图片生成模型**档位,决定用哪份规则。
///
/// 只分三件事:是不是 `anima`、是不是 `krea`、是不是以 `nai_v5` 开头,其余一律回落 4.5。
String agentImageModel(String displayModel) {
  if (isAnimaModel(displayModel)) return 'anima';
  if (isKreaModel(displayModel)) return 'krea';
  if (isNai5Model(displayModel)) return 'nai_v5_full';
  return 'nai_v45_full';
}

/// 这个图片模型能不能用 AI 助手。
///
/// Anima / Krea 不行:提示词体系与 NAI 完全不同(krea 吃连贯自然语言),助手的规则、
/// 工具、`nai_draw` 围栏都是按 NAI 写的。
bool assistantSupportsModel(String displayModel) =>
    !isAnimaModel(displayModel) && !isKreaModel(displayModel);

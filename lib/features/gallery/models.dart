/// 图库数据模型。当前里程碑仅承载 UI 占位,
/// 后续接 NAI 生成链路时补 bytes / 本地缓存路径与生成参数快照。
library;

import 'dart:typed_data';
import 'dart:ui' show Color;

import '../../core/theme/app_theme.dart' show FixedSemantic;
import '../generate/models.dart' show GenerateState;
import '../../l10n/l10n.dart';

/// 结果图的处理标记 —— 决定缩略图角标与画布顶部标签。
enum ResultBadge { none, upscaled, inpaint, censored }

extension ResultBadgeX on ResultBadge {
  /// 角标短文案;none 无角标。
  String? get label => switch (this) {
    ResultBadge.upscaled => '4x',
    ResultBadge.inpaint => l10nNow.inpaint,
    ResultBadge.censored => l10nNow.tabCensor,
    ResultBadge.none => null,
  };

  /// 角标底色 —— 压在缩略图上,用固定语义色(见 [FixedSemantic]),
  /// 不跟种子色走,也与全局主色区隔。
  Color get color => switch (this) {
    ResultBadge.upscaled => FixedSemantic.ok,
    ResultBadge.inpaint => FixedSemantic.inpaint,
    ResultBadge.censored => FixedSemantic.censor,
    ResultBadge.none => const Color(0x00000000),
  };
}

/// 回收站保留天数(按自然日算),过了就彻底删除。
const kTrashKeepDays = 30;

/// 回收站里的一张:原条目 + 移入时刻(ms epoch)。
class TrashedImage {
  const TrashedImage(this.image, this.deletedAt);
  final ResultImage image;
  final int deletedAt;
}

/// 一张生成结果。bytes/input 只是**内存缓存**——重启水合或 RAM 减负后
/// 为 null,像素与快照按 id 从 GalleryStore 懒读;hasInput 记录盘上
/// 是否有参数快照(操作门禁用,与 input 是否驻留内存无关)。
class ResultImage {
  const ResultImage({
    required this.id,
    required this.width,
    required this.height,
    required this.seed,
    this.badge = ResultBadge.none,
    this.createdAt = 0,
    this.batchIndex = -1,
    this.bytes,
    this.input,
    this.inpaintFrom,
    this.saved = false,
    bool? hasInput,
  }) : hasInput = hasInput ?? input != null;

  final String id;
  final int width;
  final int height;
  final int seed;
  final ResultBadge badge;

  /// 重绘产物的**源图**在图库里的 id;非重绘产物为 null。
  ///
  /// 只存 id 不存字节:源图本来就在库里,复制一份等于把每张重绘图的占用翻倍。
  /// 源图被删了就取不到 —— 那时「按住对比」自己消失,不报错。
  final String? inpaintFrom;

  /// 存进过手机相册(任一保存入口成功过一次)。只是提示,不拦再存。
  final bool saved;

  /// 生成时刻(ms epoch)。0 = 未知(升级前的老索引由文件 mtime 回填,
  /// 回填也失败才会留 0,展开页归入「更早」段)。
  final int createdAt;

  /// 这张在批次里的位置。-1 = 不是批次产物(单张生成 / 老记录)。
  ///
  /// **和 seed、以及参数快照里的 batchCount 三个凑齐才能复现这一张。**
  /// 一批 N 张共用同一个 seed,ComfyUI 按批次布局从同一个生成器切噪声,
  /// 光有 seed 永远只能复现第 0 张;服务端靠 `LatentFromBatch` 按 index 还原。
  /// ⚠ 出图那一刻没存下来的话,那张图**以后永远复现不出来**,事后补不了 ——
  /// 所以哪怕 app 目前还没有「按 index 复现」的入口(服务端也还没把
  /// batch_index 接到 HTTP 层),这个字段也必须从第一天就开始存。
  final int batchIndex;

  /// PNG 字节(内存缓存);null 时按需从盘读,读不到才是真无像素。
  final Uint8List? bytes;

  /// 生成时的输入快照(prompt/角色/参考/参数);供「重新生成」按本图参数复现。
  final GenerateState? input;

  /// 本图有参数快照可用(内存或盘上)。
  final bool hasInput;

  double get aspect => width / height;

  /// 卸掉内存缓存的副本(字节/快照盘上都有,再用时懒读)。
  ResultImage stripped() => (bytes == null && input == null)
      ? this
      : ResultImage(
          id: id,
          width: width,
          height: height,
          seed: seed,
          badge: badge,
          createdAt: createdAt,
          batchIndex: batchIndex,
          inpaintFrom: inpaintFrom,
          saved: saved,
          hasInput: hasInput,
        );

  /// 回填生成时刻的副本(索引迁移用,其余字段原样)。
  ResultImage withCreatedAt(int t) => ResultImage(
    id: id,
    width: width,
    height: height,
    seed: seed,
    badge: badge,
    createdAt: t,
    batchIndex: batchIndex,
    inpaintFrom: inpaintFrom,
    saved: saved,
    bytes: bytes,
    input: input,
    hasInput: hasInput,
  );

  /// 标成已存进相册的副本(其余字段原样)。
  ResultImage asSaved() => saved
      ? this
      : ResultImage(
          id: id,
          width: width,
          height: height,
          seed: seed,
          badge: badge,
          createdAt: createdAt,
          batchIndex: batchIndex,
          inpaintFrom: inpaintFrom,
          saved: true,
          bytes: bytes,
          input: input,
          hasInput: hasInput,
        );
}

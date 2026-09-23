/// 生成任务池的数据模型 —— 「一次一张」放开成「同时 N 条」之后,原先那份全局
/// `GenStatus` 就不够用了:进度、预览、排队位次都得一任务一份,否则后提交的会
/// 把前一条的进度整个盖掉(web 侧 2026-08-12 踩的正是这个坑)。
///
/// 画布跟随哪条由 [GenPool.selectedId] 决定;它为 null 表示画布看的是成图/历史图。
library;

import 'dart:typed_data';
import '../gallery/albums/album_models.dart';

/// 任务类型。重绘与普通出图并行不冲突,但**重绘之间仍是一次一条** ——
/// 回贴信息(裁切框/原图)是随会话共享的,两条同时跑会串。
enum GenJobKind { normal, inpaint }

/// 任务所处阶段。分这么细是因为每一档对用户的含义都不同:
/// 「池满等位」和「服务端排着」都显示成排队会让人以为是同一件事,
/// 前者取消不掉后端(压根还没提交)、后者可以。
enum GenJobStage {
  /// 本地等位:池子满了,还没轮到它提交。
  waiting,

  /// 拼载荷中(vibe 编码、参考图缩放),纯本地耗时。
  preparing,

  /// 已提交,在服务端队列里排着(仅 bot 模式)。
  queued,

  /// Modal 容器冷启动中(anima / krea)。
  starting,

  /// 正在出图,[GenJob.step] / [GenJob.total] 此时才有意义。
  running,

  /// 已收到终图，正在保存及归类；保留画布预览直到历史可以接管。
  saving,
}

/// 一条在跑(或等着跑)的生成任务。
class GenJob {
  const GenJob({
    required this.id,
    required this.kind,
    required this.stage,
    required this.width,
    required this.height,
    required this.seq,
    this.step = 0,
    this.total = 0,
    this.prepPct = -1,
    this.preview,
    this.note,
    this.taskId,
    this.pasteUnder,
    this.pasteAt,
    this.galleryTarget = const GallerySaveTarget.all(),
  });

  final String id;
  final GallerySaveTarget galleryTarget;
  final GenJobKind kind;
  final GenJobStage stage;

  /// 目标尺寸。占位卡按它摆比例,免得出图前后跳一下。
  final int width;
  final int height;

  /// 提交序号,越大越新。列表按它倒序展示(新的在最前,与图库一致)。
  final int seq;

  /// 局部重绘的**预览底**:整张原图,以及流帧该盖回去的位置(原图坐标)。
  ///
  /// 局部重绘发出去的只是那块裁切区,所以流帧本身是一小张。不贴回原位的话,
  /// 画布上会先显示一张小图、出图入库那一刻再啪地换成整图 —— 而入库结果本来
  /// 就是贴回去的。两个都为空 = 整图生成,流帧直接就是全貌。
  final Uint8List? pasteUnder;
  final ({int x, int y, int w, int h})? pasteAt;

  final int step;
  final int total;

  /// 采样**开始之前**那段(拉 LoRA / 加载模型)的百分比 0..100;
  /// -1 = 这段没有可量化进度。现在只有「拉 LoRA」给得出来。
  final int prepPct;

  /// 最新一帧逐步预览。
  final Uint8List? preview;

  /// 非进度类状态文案(排队位次、冷启动、限流重试倒计时)。
  final String? note;

  /// 服务端任务 id(仅 bot 模式,提交成功后才有)。取消排队要用。
  final String? taskId;

  /// 真的在逐步出图。读数只有这时候才有意义 —— 准备阶段和收尾阶段都不是。
  bool get sampling => total > 0 && step > 0;

  /// 0..1;null → 走不确定进度。
  ///
  /// **一根条按阶段各走各的**(与 web 同一套):采样开始前借「拉 LoRA」的百分比,
  /// 拉完归零,采样再从头走一遍 —— 当前在哪一段由旁边的文案说明。跨境拉一个
  /// 448MB 的 LoRA 可能要好几分钟,一根空条比有百分比更让人以为卡了。
  double? get progress => sampling
      ? (step / total).clamp(0.0, 1.0)
      : (prepPct >= 0 ? (prepPct / 100).clamp(0.0, 1.0) : null);

  bool get isRunning => stage == GenJobStage.running;

  GenJob copyWith({
    GenJobStage? stage,
    int? step,
    int? total,
    int? prepPct,
    Uint8List? preview,
    String? note,
    bool clearNote = false,
    String? taskId,
  }) => GenJob(
    id: id,
    galleryTarget: galleryTarget,
    kind: kind,
    stage: stage ?? this.stage,
    width: width,
    height: height,
    seq: seq,
    step: step ?? this.step,
    total: total ?? this.total,
    prepPct: prepPct ?? this.prepPct,
    preview: preview ?? this.preview,
    pasteUnder: pasteUnder,
    pasteAt: pasteAt,
    note: clearNote ? null : (note ?? this.note),
    taskId: taskId ?? this.taskId,
  );
}

/// 任务池。
///
/// [error] 是池级而非任务级的:任务一失败就从 [jobs] 里摘掉,错误交给创作页那条
/// 统一的错误提示显示(与并行前的行为一致,只是"最近一次失败"可能来自任何一条)。
/// 哨兵 `no-token` 仍表示未设置令牌,引导去「我的」页。
class GenPool {
  const GenPool({this.jobs = const [], this.selectedId, this.error});

  final List<GenJob> jobs;

  /// 画布正在跟随的任务;null = 看成图/历史图。
  final String? selectedId;

  final String? error;

  bool get noToken => error == 'no-token';

  /// 有任务在池子里(等位的也算 —— 用户点了按钮就该看见东西在转)。
  bool get busy => jobs.isNotEmpty;

  /// 画布跟随的那条;选中项已经跑完(或压根没选)时为 null。
  GenJob? get selected {
    if (selectedId == null) return null;
    for (final j in jobs) {
      if (j.id == selectedId) return j;
    }
    return null;
  }

  /// 展示顺序:新提交的在最前,与图库缩略图一致。
  List<GenJob> get newestFirst =>
      [...jobs]..sort((a, b) => b.seq.compareTo(a.seq));

  GenPool copyWith({
    List<GenJob>? jobs,
    String? selectedId,
    bool clearSelected = false,
    String? error,
    bool clearError = false,
  }) => GenPool(
    jobs: jobs ?? this.jobs,
    selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
    error: clearError ? null : (error ?? this.error),
  );
}

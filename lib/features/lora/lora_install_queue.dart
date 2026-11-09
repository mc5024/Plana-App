import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';

/// LoRA 后台安装队列(跨页面存活)。
///
/// 机房直拉一个 LoRA 慢则数分钟,把用户钉在导入页干等是错的:这里让「下载」
/// 变成入队即返回,队列跑在 provider 上,退出导入页也不中断;生成页显示进度,
/// 装好后由订阅方自动挂载。
///
/// 串行执行 —— Civitai 有速率限制,并发只会互相拖慢。
enum LoraInstallStatus { queued, installing, done, failed }

class LoraInstallJob {
  const LoraInstallJob({
    required this.versionId,
    required this.name,
    this.base = 'anima',
    this.status = LoraInstallStatus.queued,
    this.lrId,
    this.message,
    this.weight,
    this.clipWeight,
    this.downloaded = 0,
    this.total = 0,
  });

  final int versionId;

  /// 装进哪个底模的库(`anima` / `krea`)。**入队时定死**:队列跨页面存活,
  /// 跑起来之后用户可能已经切走模型,现读会把文件装进错的目录。
  final String base;

  /// 展示名(Civitai 上的模型名),进度上给人看的。
  final String name;
  final LoraInstallStatus status;

  /// 装好后的 LR 编号,订阅方据此挂到生成参数上。
  final String? lrId;
  final String? message;

  /// 元数据里带的权重,装好后按这个挂载(复现原图的关键)。
  final double? weight;
  final double? clipWeight;

  /// 机房侧下载进度(server 每秒从容器共享 Dict 取)。total=0 = 对面没给长度。
  final int downloaded;
  final int total;

  bool get pending =>
      status == LoraInstallStatus.queued ||
      status == LoraInstallStatus.installing;

  /// 副标题文案:「45% · 12.3/27.1MB」/「已下 12.3MB」/「连接中…」
  String get progressText {
    String mb(int n) => (n / 1048576).toStringAsFixed(1);
    if (total > 0) {
      return '${(downloaded / total * 100).floor()}% · ${mb(downloaded)}/${mb(total)}MB';
    }
    if (downloaded > 0) return '已下 ${mb(downloaded)}MB';
    return '连接中…';
  }

  LoraInstallJob copyWith({
    LoraInstallStatus? status,
    String? lrId,
    String? message,
    int? downloaded,
    int? total,
  }) => LoraInstallJob(
    versionId: versionId,
    name: name,
    base: base,
    status: status ?? this.status,
    lrId: lrId ?? this.lrId,
    message: message ?? this.message,
    weight: weight,
    clipWeight: clipWeight,
    downloaded: downloaded ?? this.downloaded,
    total: total ?? this.total,
  );
}

final loraInstallQueueProvider =
    NotifierProvider<LoraInstallQueue, List<LoraInstallJob>>(
      LoraInstallQueue.new,
    );

class LoraInstallQueue extends Notifier<List<LoraInstallJob>> {
  @override
  List<LoraInstallJob> build() => const [];

  bool _running = false;

  /// 装好一个就回调一次(生成页用它自动挂载 + 提示)。
  final _doneHandlers = <void Function(LoraInstallJob)>{};

  void Function() onInstalled(void Function(LoraInstallJob) h) {
    _doneHandlers.add(h);
    return () => _doneHandlers.remove(h);
  }

  int get pendingCount => state.where((j) => j.pending).length;

  LoraInstallJob? get current =>
      state.where((j) => j.status == LoraInstallStatus.installing).firstOrNull;

  /// 入队;同版本已在队列里(且没失败)则忽略。返回是否新入队。
  ///
  /// 重试同一版本时先把上一条失败记录摘掉 —— **versionId 在队列里必须唯一**,
  /// 它是进度回填、状态更新、占位条查进度的唯一定位依据(见 [_patch]),
  /// 留着重号会让这些查询命中那条早已失效的失败记录。
  bool enqueue({
    required int versionId,
    required String name,
    String base = 'anima',
    double? weight,
    double? clipWeight,
  }) {
    if (state.any(
      (j) => j.versionId == versionId && j.status != LoraInstallStatus.failed,
    )) {
      return false;
    }
    state = [
      for (final j in state)
        if (j.versionId != versionId) j,
      LoraInstallJob(
        versionId: versionId,
        name: name,
        base: base,
        weight: weight,
        clipWeight: clipWeight,
      ),
    ];
    _pump();
    return true;
  }

  /// 完成的从列表里摘掉(订阅方消费过就不用再显示)。
  void clearFinished() {
    final next = state.where((j) => j.pending).toList();
    if (next.length != state.length) state = next;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final job = state
            .where((j) => j.status == LoraInstallStatus.queued)
            .firstOrNull;
        if (job == null) break;
        // 全程按 versionId 定位,**不留下标** —— 订阅方消费完会 clearFinished()
        // 把已完成项摘掉,在途任务的下标随之前移:拿着旧下标改,轻则 patch 打空
        // (这条永远停在「下载中」),重则 state[idx] 越界把整条队列掀了。
        final vid = job.versionId;
        _patch(vid, status: LoraInstallStatus.installing);

        final sid = (await ref.read(botSessionProvider.future))?.sessionId;
        if (sid == null || sid.isEmpty) {
          _patch(vid, status: LoraInstallStatus.failed, message: '暂未开放');
        } else {
          // 下载期间每秒把机房侧进度贴上来(拿不到不影响下载本身)
          final ticker = Stream.periodic(const Duration(seconds: 1)).listen((
            _,
          ) async {
            try {
              final items = await ref
                  .read(backendClientProvider)
                  .loraInstallProgress();
              final p = items
                  .where((x) => x.versionId == job.versionId)
                  .firstOrNull;
              if (p != null) {
                _patch(vid, downloaded: p.downloaded, total: p.total);
              }
            } catch (_) {}
          });
          try {
            final res = await ref
                .read(backendClientProvider)
                .installLora(sessionId: sid, versionId: vid, base: job.base);
            if (res.ok || res.lrId != null) {
              _patch(vid, status: LoraInstallStatus.done, lrId: res.lrId);
            } else {
              _patch(
                vid,
                status: LoraInstallStatus.failed,
                message: res.message.isEmpty ? '下载失败' : res.message,
              );
            }
          } catch (e) {
            _patch(vid, status: LoraInstallStatus.failed, message: '$e');
          } finally {
            await ticker.cancel();
          }
        }
        // 这一趟的最终态。被 clearFinished 抢先摘掉就没什么可通知的了。
        final done = state.where((j) => j.versionId == vid).firstOrNull;
        if (done == null) continue;
        for (final h in _doneHandlers.toList()) {
          h(done);
        }
      }
    } finally {
      _running = false;
    }
  }

  /// 按 versionId 就地更新那一条(队列里 versionId 唯一,见 [enqueue])。
  /// 对不上号就什么都不做 —— 那条已被 [clearFinished] 摘掉了。
  void _patch(
    int versionId, {
    LoraInstallStatus? status,
    String? lrId,
    String? message,
    int? downloaded,
    int? total,
  }) {
    state = [
      for (final j in state)
        if (j.versionId == versionId)
          j.copyWith(
            status: status,
            lrId: lrId,
            message: message,
            downloaded: downloaded,
            total: total,
          )
        else
          j,
    ];
  }
}

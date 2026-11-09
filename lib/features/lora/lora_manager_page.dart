import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/bot_session_store.dart';
import '../../core/net/backend_client.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../generate/generate_state.dart';
import '../generate/models.dart';
import '../generate/widgets/common.dart' show InfoNote, hintSnack;
import '../generate/widgets/lora_card.dart' show LoraThumb, LoraTypeBadge;
import 'lora_providers.dart';
import 'lora_stack_ui.dart';
import 'lora_stacks.dart';
import 'lora_upload_sheet.dart';

/// LoRA 管理器(anima / krea 出图渠道,结构对齐 web LoraManagerModal):
/// 我的(我下载过的 + 我上传的,🗑=移出;无人拥有的 web 条目由后端回收)
/// LoRA 堆(存下来的整组挂载;「应用」直接替换当前挂载并关页,见 lora_stacks.dart)
/// 公共库(机房里的公开条目,⭐=加入/移出我的库,按人气排序)
/// 在线搜索(Civitai 代理,ℹ=详情 ⬇=机房直拉下载,滚到底自动翻页)
/// 整卡点选 → 底栏「确认挂载」写回创作页(上限 [kMaxActiveLoras] 个)。
///
/// 全程只看**一个**底模([_base],进页时从当前模型定死):Anima 与 Krea2 的
/// 权重互不通用,列表、在线搜索、下载、上传都带着它 —— 混着列只会让人挂上
/// 一个静默无效的 LoRA。
class LoraManagerPage extends ConsumerStatefulWidget {
  const LoraManagerPage({super.key});

  @override
  ConsumerState<LoraManagerPage> createState() => _LoraManagerPageState();
}

const _kEdge = 16.0;

/// 页签序:我的 · LoRA 堆 · 公共库 · 在线搜索。
const _kTabStacks = 1;
const _kTabOnline = 3;

/// 上传入口的高度。空闲态是按钮、传输态是进度条,两者必须等高,
/// 否则一开传整个列表会往下跳一格。
const _kUploadBarHeight = 42.0;
const _cats = <(String, String)>[
  ('all', '全部'),
  ('character', '角色'),
  ('style', '画风'),
  ('concept', '概念'),
];

class _LoraManagerPageState extends ConsumerState<LoraManagerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);
  int _lastTabIndex = 0;

  /// 本页认哪个底模的库。进页时定死:模型只能在创作页换,本页开着时不会变,
  /// 而中途改基准会让已选中的条目跨库串到确认挂载里去。
  late final String _base = ref.read(loraBaseProvider);

  String _search = '';
  final _searchCtl = TextEditingController();
  final Set<String> _selected = {};

  // 我的/公共库共用一份全集(/api/lora/list),常驻在 installedLorasProvider,
  // 管理器重开不重拉;下面这些只是本页的瞬时 UI 态。
  String? _busyName; // favorite/unfavorite 进行中的条目

  String _commCat = 'all';

  /// 库内条目的 Civitai 简介缓存(LR 编号 → 简介;null = 查过、没查着)。
  /// 挂在页上而不是弹层里:同一条反复开详情不该反复去搜一遍。
  final Map<String, String?> _descCache = {};

  // 上传自己的 LoRA:0~100 = 本机→server 的百分比,null = 没在传。
  // 传输跑在本页而不是上传面板里,面板关掉、切 tab 都不打断。
  int? _uploadPct;

  /// server→机房的推送轮询,按 LR 编号一条一个(重进本页会给自己那些
  /// 还在推的条目重新接上)。
  final _pushTimers = <String, Timer>{};

  /// 在线安装的进度轮询与最新读数,按 Civitai versionId 一条一个。
  /// `/lora/install` 现在开始下载就返回,结论只能靠这条轮出来。
  final _installTimers = <int, Timer>{};
  final _installProgress =
      <
        int,
        ({
          int versionId,
          String name,
          String state,
          String phase,
          int downloaded,
          int total,
          String lrId,
          String message,
          bool stale,
        })
      >{};

  // 在线搜索
  final _onlineScroll = ScrollController();
  List<CivitaiLoraInfo> _onlineItems = [];
  String? _onlineCursor;
  bool _loadingOnline = false;
  bool _onlineLoadedOnce = false;
  String _onlineCat = 'all';

  /// 「二次元」开关,与左边的分类**可叠加**:分类是本地按推断出的 type 筛,
  /// 这个是服务端去 Civitai 侧按 tag=anime 筛,两者作用在不同环节。
  /// 对 krea 尤其必要 —— k2 是写实向底模,不筛的话默认列表里几乎翻不到二次元的。
  bool _onlineAnimeOnly = false;

  /// 当前这批在线结果对应的关键词(可能落后于输入框:切走时改过词)。
  String _onlineQuery = '';

  /// 每次新搜索自增,在途的旧请求回来时按它作废(不覆盖新结果)。
  int _searchSeq = 0;

  /// 「没铺满一屏就继续翻」的连翻计数,防分类过滤把整批滤空时无限翻页。
  int _autoPages = 0;

  /// 上一次搜索失败的原因:列表空时要说清是「搜不通」还是「真没有」。
  String? _onlineError;
  int? _downloadingVid;
  final Set<int> _downloadedVids = {};
  final Map<String, int> _vidByLrId = {}; // 移出我的库时回退在线「已下载」✓
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _selected.addAll(ref.read(generateProvider).loras.map((l) => l.name));
    _tab.addListener(() {
      if (_tab.index == _lastTabIndex) return;
      _lastTabIndex = _tab.index;
      setState(() {});
      // 切到在线页:没搜过、或搜索框在别的页被改过 → 重搜(省无谓请求,但不留旧词的结果)
      if (_tab.index == _kTabOnline &&
          (!_onlineLoadedOnce || _onlineQuery != _search.trim())) {
        _searchDebounce?.cancel();
        _runSearch(reset: true);
      }
    });
    _onlineScroll.addListener(() {
      if (_tab.index != _kTabOnline ||
          _loadingOnline ||
          _onlineCursor == null) {
        return;
      }
      if (_onlineScroll.position.extentAfter < 400) {
        _autoPages = 0; // 用户自己滚到底,连翻计数重新起算
        _runSearch(reset: false);
      }
    });
    // 全集不在这儿拉:provider 常驻,首次 watch 才发请求,之后重开直接命中。
    // 但常驻也意味着重开时不会再触发 ref.listen —— 手上这份已有的值要自己看一眼
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resumeWatch(ref.read(installedLorasProvider(_base)).value ?? const []);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    for (final t in [..._pushTimers.values, ..._installTimers.values]) {
      t.cancel();
    }
    _searchCtl.dispose();
    _onlineScroll.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<String?> _sid() async =>
      (await ref.read(botSessionProvider.future))?.sessionId;

  Future<void> _loadInstalled() =>
      ref.read(installedLorasProvider(_base).notifier).reload();

  /// 在线搜索。[reset] = 换词/换分类的新搜索(丢弃在途请求),否则是续下一页。
  ///
  /// 新搜索**不能**因为「有请求在跑」就被丢掉 —— Civitai 代理一趟好几秒,
  /// 边打字边翻页时几乎次次撞上,那正是「搜了没反应」的由来。
  /// 改成发号作废:每次新搜索 [_searchSeq] 自增,旧请求回来时对不上号就整个忽略。
  Future<void> _runSearch({required bool reset}) async {
    if (!reset && (_loadingOnline || _onlineCursor == null)) return;
    final seq = ++_searchSeq;
    // 游标属于产出它的那次搜索:续页仍用当批的词,不跟着输入框半路改口
    final query = reset ? _search.trim() : _onlineQuery;
    final cat = _onlineCat;
    // 与 cat 同样先取快照:这趟要 await 好几秒,期间用户完全可能再点开关
    final animeOnly = _onlineAnimeOnly;
    final cursor = reset ? null : _onlineCursor;
    if (reset) _autoPages = 0;
    setState(() {
      _loadingOnline = true;
      _onlineError = null;
    });
    try {
      final r = await ref
          .read(backendClientProvider)
          .searchLoras(
            query: query,
            cursor: cursor,
            // 具体分类是客户端过滤,用大页一次出一整批;「全部」小页更快(对齐 web)
            limit: cat == 'all' ? 24 : 60,
            base: _base, // Civitai 那边按 baseModel=Anima / Krea 2 过滤
            tag: animeOnly ? 'anime' : '',
          );
      if (!mounted || seq != _searchSeq) return; // 已被更新的搜索取代
      final next = r.nextCursor;
      setState(() {
        _onlineLoadedOnce = true;
        _onlineQuery = query;
        _onlineItems = reset ? r.items : [..._onlineItems, ...r.items];
        _onlineCursor = (next == null || next.isEmpty) ? null : next;
        _loadingOnline = false;
      });
      _autoPageIfShort();
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _loadingOnline = false;
        _onlineError = '$e';
      });
      hintSnack(context, '$e', icon: Icons.cloud_off);
    }
  }

  /// 一批结果被分类过滤后可能只剩几条,列表压根没到能滚的长度 ——
  /// 滚动监听永远不触发,自动翻页就断在这儿。所以每批落地后补一次判断:
  /// 还没铺满一屏且有下一页游标就接着翻(最多连翻 [_kMaxAutoPages] 次,
  /// 再多就交给列表底部的「加载更多」,免得整批滤空时无限打 Civitai)。
  static const _kMaxAutoPages = 5;

  void _autoPageIfShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _tab.index != _kTabOnline ||
          _loadingOnline ||
          _onlineCursor == null ||
          _autoPages >= _kMaxAutoPages ||
          _onlineScroll.positions.length != 1) {
        return;
      }
      if (_onlineScroll.position.extentAfter < 400) {
        _autoPages++;
        _runSearch(reset: false);
      }
    });
  }

  void _onSearchChanged(String v) {
    setState(() => _search = v);
    if (_tab.index != _kTabOnline) return; // 本地几页是纯前端过滤,切回在线页时再重搜
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _startSearch();
    });
  }

  /// 键盘「搜索」键 / 清空按钮 / 换分类:不等防抖,立刻发。
  void _startSearch() {
    _searchDebounce?.cancel();
    _runSearch(reset: true);
  }

  void _toggleSelect(LoraCardInfo item) {
    if (_selected.contains(item.name)) {
      setState(() => _selected.remove(item.name));
      return;
    }
    // 还没推进机房的条目挂上去出图必炸,拦在这儿(对齐 web)
    if (!item.ready) {
      hintSnack(context, item.pushing ? '还在推送到机房,就绪后可挂载' : '该 LoRA 未就绪,暂不能挂载');
      return;
    }
    if (_selected.length >= kMaxActiveLoras) {
      hintSnack(context, '最多同时挂载 $kMaxActiveLoras 个 LoRA');
      return;
    }
    setState(() => _selected.add(item.name));
  }

  /// 上传就绪 / 去重命中后替用户选上。已达上限就不硬塞(返回 false,由调用方改口)。
  bool _autoSelect(String name) {
    if (_selected.contains(name)) return true;
    if (_selected.length >= kMaxActiveLoras) return false;
    setState(() => _selected.add(name));
    return true;
  }

  // 我的库移除 / 公共库星标共用:移出我的库,必要时后端回收
  Future<void> _unfavorite(LoraCardInfo item) async {
    setState(() => _busyName = item.name);
    try {
      final sid = await _sid();
      if (sid == null) return;
      final r = await ref
          .read(backendClientProvider)
          .unfavoriteLora(sessionId: sid, lrId: item.name);
      if (!mounted) return;
      if (!r.ok) {
        hintSnack(context, r.message.isEmpty ? '移除失败' : r.message);
        return;
      }
      setState(() {
        _selected.remove(item.name);
        final vid = _vidByLrId.remove(item.name);
        if (vid != null) _downloadedVids.remove(vid);
      });
      final loras = ref.read(installedLorasProvider(_base).notifier);
      if (r.deleted) {
        loras.dropByName(item.name);
      } else {
        loras.patch(
          item.name,
          favorited: false,
          favoriteCount: r.favoriteCount,
        );
      }
      hintSnack(context, '已移出我的库', icon: Icons.check);
    } catch (e) {
      if (mounted) hintSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busyName = null);
    }
  }

  Future<void> _favorite(LoraCardInfo item) async {
    setState(() => _busyName = item.name);
    try {
      final sid = await _sid();
      if (sid == null) return;
      final r = await ref
          .read(backendClientProvider)
          .favoriteLora(sessionId: sid, lrId: item.name);
      if (!mounted) return;
      if (!r.ok) {
        hintSnack(context, r.message.isEmpty ? '加入失败' : r.message);
        return;
      }
      ref
          .read(installedLorasProvider(_base).notifier)
          .patch(item.name, favorited: true, favoriteCount: r.favoriteCount);
      hintSnack(context, '已加入我的库', icon: Icons.check);
    } catch (e) {
      if (mounted) hintSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busyName = null);
    }
  }

  // ---- 上传自己的 LoRA ----

  /// 选文件填表 → 传给 server(它校验完只登记就返回,推进机房是它的后台活)。
  /// 所以传完不算完:拿到编号后接着 [_watchPush] 盯推送,synced 才是能挂载。
  Future<void> _startUpload() async {
    final draft = await showLoraUploadSheet(context);
    if (draft == null || !mounted) return;
    final sid = await _sid();
    if (!mounted) return;
    if (sid == null) {
      hintSnack(context, '暂未开放');
      return;
    }
    setState(() => _uploadPct = 0);
    try {
      final r = await ref
          .read(backendClientProvider)
          .uploadLora(
            sessionId: sid,
            filePath: draft.path,
            fileName: draft.fileName,
            fileSize: draft.size,
            displayName: draft.displayName,
            triggerGroups: draft.triggerGroups,
            type: draft.type,
            public: draft.public,
            base: _base, // 决定文件落 Volume 的哪个子目录 → 之后能被哪个渠道挂载
            onProgress: (p) {
              // 每块都回调(几百兆能有几千次),整数百分比不变就不重建
              final v = (p * 100).clamp(0, 100).round();
              if (!mounted || v == _uploadPct) return;
              setState(() => _uploadPct = v);
            },
          );
      if (!mounted) return;
      if (!r.ok) {
        hintSnack(context, r.message.isEmpty ? '上传失败' : r.message);
        return;
      }
      await _loadInstalled();
      final id = r.lrId;
      if (!mounted || id == null) return;
      if (r.dedup) {
        // 同一个文件机房里已经有了,后端没重复存,直接给收藏了
        final ok = _autoSelect(id);
        hintSnack(
          context,
          r.message.isEmpty ? '该文件已在库中,已为你收藏' : r.message,
          icon: ok ? Icons.check : Icons.info_outline,
        );
      } else {
        hintSnack(context, '已接收,正在推送到机房…', icon: Icons.cloud_upload_outlined);
        _watchPush(id);
      }
    } catch (e) {
      if (mounted) hintSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _uploadPct = null);
    }
  }

  /// 盯 server→机房的推送(3s 一问,对齐 web)。就绪→刷新列表并替用户选上;
  /// 失败→刷新列表,卡片上会出现重试按钮。
  void _watchPush(String lrId) {
    if (_pushTimers.containsKey(lrId)) return;
    _pushTimers[lrId] = Timer.periodic(const Duration(seconds: 3), (t) async {
      final ({bool ok, String status, String? error}) st;
      try {
        st = await ref.read(backendClientProvider).loraUploadStatus(lrId);
      } catch (_) {
        return; // 网络抖一下不算数,下一轮再问
      }
      if (!mounted || st.status == 'uploading' || st.status == 'pending') {
        return;
      }
      t.cancel();
      _pushTimers.remove(lrId);
      await _loadInstalled();
      if (!mounted) return;
      if (st.status == 'synced') {
        final ok = _autoSelect(lrId);
        hintSnack(
          context,
          ok ? '$lrId 已就绪并选中,点「确认挂载」生效' : '$lrId 已就绪',
          icon: Icons.check,
        );
      } else if (st.status == 'failed') {
        hintSnack(
          context,
          '推送机房失败:${st.error ?? '未知原因'},可在卡片上重试',
          icon: Icons.cloud_off,
        );
      }
    });
  }

  /// 轮询只活在本页:重进管理器时,把自己那些还在推送的条目重新接上。
  void _resumeWatch(List<LoraCardInfo> all) {
    for (final x in all) {
      if (x.pushing && x.isOwner) _watchPush(x.name);
    }
  }

  /// 推送失败重来(服务端留着收到的那份临时文件,不用重传)。
  Future<void> _retryPush(LoraCardInfo item) async {
    setState(() => _busyName = item.name);
    try {
      final sid = await _sid();
      if (sid == null) return;
      final r = await ref
          .read(backendClientProvider)
          .retryLoraUpload(sessionId: sid, lrId: item.name);
      if (!mounted) return;
      hintSnack(
        context,
        r.message.isEmpty ? (r.ok ? '已重新开始推送' : '重试失败') : r.message,
        icon: r.ok ? Icons.cloud_upload_outlined : Icons.error_outline,
      );
      if (!r.ok) return;
      await _loadInstalled();
      if (!mounted) return;
      _watchPush(item.name);
    } catch (e) {
      if (mounted) hintSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busyName = null);
    }
  }

  Future<void> _download(CivitaiLoraInfo item) async {
    if (_downloadingVid != null) return;
    setState(() => _downloadingVid = item.versionId);
    try {
      final sid = await _sid();
      if (!mounted) return;
      if (sid == null) {
        hintSnack(context, '暂未开放');
        return;
      }
      final r = await ref
          .read(backendClientProvider)
          .installLora(sessionId: sid, versionId: item.versionId, base: _base);
      if (!mounted) return;
      if (!r.ok && r.lrId == null) {
        hintSnack(context, r.message.isEmpty ? '下载失败' : r.message);
        return;
      }
      final id = r.lrId;
      if (id != null) setState(() => _vidByLrId[id] = item.versionId);
      // pending = 服务端**只是开始下载了**。这时标成「已加入我的库」是撒谎:
      // 走租用实例时下载 + 传库前后好几分钟,中途还可能失败。结论去进度接口拿。
      if (r.pending) {
        hintSnack(context, '正在下载…', icon: Icons.cloud_download_outlined);
        _watchInstall(item.versionId);
        return;
      }
      setState(() => _downloadedVids.add(item.versionId));
      hintSnack(
        context,
        r.message.isEmpty ? '已加入我的库' : r.message,
        icon: Icons.check,
      );
      await _loadInstalled();
    } catch (e) {
      if (mounted) hintSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _downloadingVid = null);
    }
  }

  /// 盯一个安装任务到出结论(1s 一问,对齐 web)。
  ///
  /// 连续取不到进度**不判死** —— 跨境抖一下是常态,后台任务照跑;只有服务端
  /// 自己说 `failed`,或长时间连这条记录都没了(server 重启),才认输。
  void _watchInstall(int versionId) {
    if (_installTimers.containsKey(versionId)) return;
    var misses = 0;
    _installTimers[versionId] = Timer.periodic(const Duration(seconds: 1), (
      t,
    ) async {
      List<
        ({
          int versionId,
          String name,
          String state,
          String phase,
          int downloaded,
          int total,
          String lrId,
          String message,
          bool stale,
        })
      >
      items;
      try {
        items = await ref.read(backendClientProvider).loraInstallProgress();
      } catch (_) {
        return; // 网络抖一下不算数,下一轮再问
      }
      if (!mounted) return;
      final hit = items.where((e) => e.versionId == versionId).firstOrNull;
      if (hit == null) {
        // 终态过了 TTL 会被服务端清掉,所以「查不到」也可能是**成功后过了会儿**。
        // 给一段宽限再去列表里确认,别急着报错。
        if (++misses < 20) return;
        t.cancel();
        _installTimers.remove(versionId);
        await _loadInstalled();
        return;
      }
      misses = 0;
      if (hit.state == 'running') {
        setState(() => _installProgress[versionId] = hit);
        return;
      }
      t.cancel();
      _installTimers.remove(versionId);
      setState(() => _installProgress.remove(versionId));
      if (hit.state == 'done') {
        setState(() => _downloadedVids.add(versionId));
        await _loadInstalled();
        if (mounted) hintSnack(context, '已加入我的库', icon: Icons.check);
      } else if (mounted) {
        hintSnack(
          context,
          hit.message.isEmpty ? '下载失败' : '下载失败:${hit.message}',
          icon: Icons.error_outline,
        );
      }
    });
  }

  void _confirm() {
    final all =
        ref.read(installedLorasProvider(_base)).value ?? const <LoraCardInfo>[];
    final picked = [
      for (final c in all)
        if (_selected.contains(c.name))
          ActiveLora(
            name: c.name,
            displayName: c.displayName,
            weight: c.recommendedWeight,
            triggerWords: c.triggerWords,
            previewUrl: c.previewUrl,
            type: c.type,
            hasTe: c.hasTe,
          ),
    ];
    ref.read(generateProvider.notifier).applyLoraSelection(picked);
    Navigator.of(context).pop();
  }

  bool _matchSearch(LoraCardInfo x) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return x.displayName.toLowerCase().contains(q) ||
        x.name.toLowerCase().contains(q) ||
        x.triggerWords.join(' ').toLowerCase().contains(q);
  }

  /// 未授权(provider 抛 need-bot)给人话,其余原样透出。
  static String? _errText(Object? e) {
    if (e == null) return null;
    if (e is StateError && e.message == 'need-bot') return '暂未开放';
    return '$e';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // 刷新后可能多出「还在推送」的自家条目(比如另一端传的),接着盯
    ref.listen(installedLorasProvider(_base), (_, next) {
      final items = next.value;
      if (items != null) _resumeWatch(items);
    });
    final async = ref.watch(installedLorasProvider(_base));
    final all = async.value ?? const <LoraCardInfo>[];
    final mine = [
      for (final x in all)
        if (x.favorited) x,
    ];
    // 私有条目(自己上传、只有自己拉得到)不进公共库,只留在「我的」
    final community = [
      for (final x in all)
        if (!x.isPrivate) x,
    ];
    // 有旧值就照常渲染,刷新只在标题栏转圈;首拉才整页 loading。
    // 刷新失败同理不掀桌 —— 手上这份还能用来挂载。
    final firstLoad = async.isLoading && !async.hasValue;
    final error = async.hasValue ? null : _errText(async.error);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LoRA 管理器'),
        actions: [
          if (async.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _loadInstalled,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 6, _kEdge, 0),
            child: TextField(
              controller: _searchCtl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (_tab.index == _kTabOnline) _startSearch();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: switch (_tab.index) {
                  _kTabOnline =>
                    '搜索 Civitai 上的 ${_base == 'krea' ? 'Krea 2' : 'Anima'} LoRA…',
                  _kTabStacks => '搜索 LoRA 堆…',
                  _ => '搜索名称或触发词…',
                },
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '清空',
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() => _search = '');
                          if (_tab.index == _kTabOnline) _startSearch();
                        },
                      ),
                filled: true,
                fillColor: context.pageControlFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 8),
            child: _segTabs(scheme),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _mineTab(mine, firstLoad: firstLoad, error: error),
                _stacksTab(async.hasValue ? all : null),
                _communityTab(community, firstLoad: firstLoad, error: error),
                _onlineTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(scheme, ready: async.hasValue),
    );
  }

  // ---- 分段 Tab(视觉对齐 Vibe/画风管理器,4 段) ----
  Widget _segTabs(ColorScheme scheme) {
    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.pageControlFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedBuilder(
          animation: _tab.animation!,
          builder: (context, _) {
            final t = _tab.animation!.value.clamp(0.0, 3.0);
            return LayoutBuilder(
              builder: (context, c) {
                final segW = c.maxWidth / 4;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 3,
                      bottom: 3,
                      left: 3 + t * segW,
                      width: segW - 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.segThumb,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _segLabel(0, Icons.smartphone, '我的', t),
                        _segLabel(1, Icons.layers_outlined, 'LoRA 堆', t),
                        _segLabel(2, Icons.dns_outlined, '公共库', t),
                        _segLabel(3, Icons.public, '在线搜索', t),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _segLabel(int index, IconData icon, String text, double t) {
    final scheme = context.scheme;
    final sel = (1 - (t - index).abs()).clamp(0.0, 1.0);
    final color = Color.lerp(
      scheme.onSurfaceVariant,
      context.segLabel(scheme.onSurface),
      sel,
    )!;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _tab.animateTo(index),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelLarge!.copyWith(
                    color: color,
                    fontWeight: FontWeight.lerp(
                      FontWeight.w500,
                      FontWeight.w700,
                      sel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 我的 ----
  Widget _mineTab(
    List<LoraCardInfo> mine, {
    required bool firstLoad,
    required String? error,
  }) {
    final items = [
      for (final x in mine)
        if (_matchSearch(x)) x,
    ];
    if (error != null) return _errorBody(error);
    if (firstLoad) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_kEdge, 4, _kEdge, 8),
          child: _uploadEntry(),
        ),
        Expanded(
          child: items.isEmpty
              ? _emptyBody(
                  icon: Icons.smartphone,
                  text: mine.isEmpty ? '我的库还是空的' : '没有匹配的 LoRA',
                  action: mine.isEmpty
                      ? TextButton(
                          onPressed: () => _tab.animateTo(_kTabOnline),
                          child: const Text('去在线下载 →'),
                        )
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final x = items[i];
                    return _LibraryCard(
                      item: x,
                      selected: _selected.contains(x.name),
                      onTap: () => _toggleSelect(x),
                      // 三个页一套规矩:ℹ 常驻,忙的只是右边那颗。
                      // 原先整排在收藏请求期间被一个转圈整个换掉,
                      // 详情跟着一起消失 —— 而看详情和收藏没有半点关系。
                      action: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (x.syncStatus == 'failed' && x.isOwner)
                            IconButton(
                              tooltip: '重试推送到机房',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.refresh),
                              onPressed: () => _retryPush(x),
                            ),
                          IconButton(
                            tooltip: '详情',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.info_outline),
                            color: context.scheme.onSurfaceVariant,
                            onPressed: () => _showLibraryDetail(x),
                          ),
                          if (_busyName == x.name)
                            const _BusyIcon()
                          else
                            IconButton(
                              tooltip: '删除(移出我的库)',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.delete_outline,
                                color: context.scheme.error,
                              ),
                              onPressed: () => _unfavorite(x),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 上传入口。传输期间整条按钮变成进度条(从左往右填),不另占位置 ——
  /// 传输跑在本页,面板关掉、切 tab 都还看得见它走到哪了。
  Widget _uploadEntry() {
    final scheme = context.scheme;
    final pct = _uploadPct;
    if (pct == null) {
      return OutlinedButton.icon(
        onPressed: _startUpload,
        icon: const Icon(Icons.upload_file, size: 18),
        label: const Text('上传我的 LoRA(.safetensors)'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(_kUploadBarHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    // 100% 之后还要等服务端算完整份文件的 SHA 才回执,那段没进度可报:
    // 条填满不动,换个转圈告诉用户还没完
    final verifying = pct >= 100;
    return Container(
      height: _kUploadBarHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: .5)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (pct / 100).clamp(0.0, 1.0),
            heightFactor: 1,
            child: ColoredBox(color: scheme.primary.withValues(alpha: .22)),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (verifying)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                else
                  Icon(Icons.upload_file, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  verifying ? '校验中…' : '上传中 $pct%',
                  style: context.texts.labelLarge!.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- LoRA 堆 ----
  /// [library] 为 null = 全集还没读到:列表照常显示,只是不标缺失、不让应用。
  Widget _stacksTab(List<LoraCardInfo>? library) {
    final all = ref.watch(loraStacksProvider).value ?? const <LoraStack>[];
    final stacks = [
      for (final s in all)
        if (s.base == _base) s,
    ];
    final q = _search.trim().toLowerCase();
    final items = q.isEmpty
        ? stacks
        : [
            for (final s in stacks)
              if (s.name.toLowerCase().contains(q) ||
                  s.loras.any(
                    (e) =>
                        e.displayName.toLowerCase().contains(q) ||
                        e.name.toLowerCase().contains(q),
                  ))
                s,
          ];
    final ready = ref
        .watch(generateProvider.select((s) => s.loras))
        .where((l) => l.pending == null)
        .length;
    final installed = library == null
        ? null
        : {for (final x in library) x.name};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_kEdge, 4, _kEdge, 8),
          child: OutlinedButton.icon(
            onPressed: ready == 0
                ? null
                : () => showSaveLoraStackDialog(context, ref),
            icon: const Icon(Icons.layers_outlined, size: 18),
            label: Text(
              ready == 0 ? '当前没有挂载 LoRA' : '把当前挂载的 $ready 个存为 LoRA 堆',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(_kUploadBarHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _emptyBody(
                  icon: Icons.layers_outlined,
                  text: stacks.isEmpty ? '还没有 LoRA 堆' : '没有匹配的 LoRA 堆',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = items[i];
                    return LoraStackCard(
                      key: ValueKey(s.id),
                      stack: s,
                      installed: installed,
                      onApply: () => _applyStack(s),
                      onDelete: () => _deleteStack(s),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 整组替换当前挂载并关页。库里没有 / 未就绪的条目跳过并提示。
  void _applyStack(LoraStack stack) {
    final async = ref.read(installedLorasProvider(_base));
    final library = async.value;
    if (library == null) {
      hintSnack(
        context,
        async.hasError ? '没读到 LoRA 库,暂时没法应用' : 'LoRA 库还在读取,稍等再应用',
      );
      return;
    }
    final r = resolveLoraStack(stack, library);
    if (r.loras.isEmpty) {
      hintSnack(context, '「${stack.name}」里的 LoRA 现在都用不了');
      return;
    }
    ref.read(generateProvider.notifier).applyLoraStack(r.loras);
    final skipped = [...r.missing, ...r.notReady];
    hintSnack(
      context,
      skipped.isEmpty
          ? '已应用「${stack.name}」'
          : '已应用「${stack.name}」,跳过 ${skipped.length} 个用不了的:${skipped.join('、')}',
      icon: Icons.layers_outlined,
    );
    Navigator.of(context).pop();
  }

  Future<void> _deleteStack(LoraStack stack) async {
    final stacks = ref.read(loraStacksProvider.notifier);
    final index = await stacks.remove(stack.id);
    if (index < 0 || !mounted) return;
    hintSnack(
      context,
      '已删除「${stack.name}」',
      icon: Icons.delete_outline,
      actionLabel: '撤销',
      onAction: () => stacks.restore(stack, index),
    );
  }

  // ---- 公共库 ----
  Widget _communityTab(
    List<LoraCardInfo> all, {
    required bool firstLoad,
    required String? error,
  }) {
    if (error != null) return _errorBody(error);
    if (firstLoad) return const Center(child: CircularProgressIndicator());
    final items =
        [
            for (final x in all)
              if ((_commCat == 'all' || x.type == _commCat) && _matchSearch(x))
                x,
          ]
          // 人气(收藏人数)降序 → 使用次数降序(对齐 web)
          ..sort(
            (a, b) => b.favoriteCount != a.favoriteCount
                ? b.favoriteCount - a.favoriteCount
                : b.usageCount - a.usageCount,
          );
    return Column(
      children: [
        _catChips(_commCat, (k) => setState(() => _commCat = k)),
        Expanded(
          child: items.isEmpty
              ? _emptyBody(
                  icon: Icons.dns_outlined,
                  text: all.isEmpty ? '机房里还没有 LoRA' : '没有匹配的 LoRA',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(_kEdge, 4, _kEdge, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final x = items[i];
                    return _LibraryCard(
                      item: x,
                      selected: _selected.contains(x.name),
                      showOfficial: true,
                      onTap: () => _toggleSelect(x),
                      action: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 与在线页同位的 ℹ:那边看 Civitai 的卡片,这边看机房里
                          // 这一份(编号 / 谁传的 / 推送状态 / CLIP 能不能调)
                          IconButton(
                            tooltip: '详情',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.info_outline),
                            color: context.scheme.onSurfaceVariant,
                            onPressed: () => _showLibraryDetail(x),
                          ),
                          if (_busyName == x.name)
                            const _BusyIcon()
                          else
                            IconButton(
                              tooltip: x.favorited ? '移出我的库' : '加入我的库',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                x.favorited ? Icons.star : Icons.star_border,
                                color: x.favorited
                                    ? context.scheme.primary
                                    : context.scheme.onSurfaceVariant,
                              ),
                              onPressed: () =>
                                  x.favorited ? _unfavorite(x) : _favorite(x),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---- 在线搜索 ----
  Widget _onlineTab() {
    final items = [
      for (final x in _onlineItems)
        if (_onlineCat == 'all' || x.type == _onlineCat) x,
    ];
    return Column(
      children: [
        // 「二次元」排在分类前面:它是服务端按 tag 筛(决定拉回什么),分类是本地
        // 按 type 筛(在拉回的结果里挑),两者可叠加。用带勾的 FilterChip 而不是
        // 第五个分类 chip —— 后者会被读成「和角色/画风四选一」。
        _catChips(
          _onlineCat,
          (k) {
            if (k == _onlineCat) return;
            setState(() {
              _onlineCat = k;
              _onlineItems = [];
              _onlineCursor = null;
            });
            _startSearch();
          },
          leading: FilterChip(
            label: const Text('二次元'),
            selected: _onlineAnimeOnly,
            visualDensity: VisualDensity.compact,
            tooltip: _onlineAnimeOnly ? '点击取消,显示全部内容' : '只看二次元',
            // 服务端过滤,不像分类那样能在已有结果里筛 —— 必须重发请求
            onSelected: (v) {
              setState(() {
                _onlineAnimeOnly = v;
                _onlineItems = [];
                _onlineCursor = null;
              });
              _startSearch();
            },
          ),
        ),
        Expanded(
          child: !_onlineLoadedOnce && _onlineError == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty && !_loadingOnline && _onlineCursor == null
              ? (_onlineError != null
                    // 搜不通和真没有,得能一眼分清(以前都写「没有结果」)
                    ? _emptyBody(
                        icon: Icons.cloud_off,
                        text: _onlineError!,
                        action: TextButton(
                          onPressed: _startSearch,
                          child: const Text('重试'),
                        ),
                      )
                    : _emptyBody(icon: Icons.public, text: '没有结果'))
              : ListView.separated(
                  controller: _onlineScroll,
                  padding: const EdgeInsets.fromLTRB(_kEdge, 4, _kEdge, 16),
                  itemCount: items.length + (_onlineFooter == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => i >= items.length
                      ? _onlineFooter!
                      : _onlineCardRow(items[i]),
                ),
        ),
      ],
    );
  }

  /// 列表尾:加载中转圈;还有下一页给个手点入口(连翻到上限、或列表短到滚不动时的退路);
  /// 翻完了就不占位。
  Widget? get _onlineFooter {
    if (_loadingOnline) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_onlineCursor == null) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton(
          onPressed: () {
            _autoPages = 0;
            _runSearch(reset: false);
          },
          child: const Text('加载更多'),
        ),
      ),
    );
  }

  /// 安装中那行小字:`下载 42%` / `入库 18MB`。
  /// **两段要分开报** —— 走租用实例时下完还要传进库,不区分的话进度条会在
  /// 100% 上干等好几分钟,看着就像卡死了。
  String? _installLabel(int versionId) {
    final p = _installProgress[versionId];
    if (p == null) return null;
    final seg = p.phase == 'uploading' ? '入库' : '下载';
    if (p.stale) return '$seg · 无响应';
    if (p.total > 0) {
      return '$seg ${(p.downloaded / p.total * 100).clamp(0, 100).round()}%';
    }
    return '$seg ${(p.downloaded / 1048576).toStringAsFixed(0)}MB';
  }

  Widget _onlineCardRow(CivitaiLoraInfo x) {
    final scheme = context.scheme;
    final done = _downloadedVids.contains(x.versionId);
    // 请求返回后 _downloadingVid 就清了,但那时下载才刚开始 —— 轮询里还有
    // 记录的一律仍算「忙」,否则按钮会在下载途中变回可点的下载图标。
    final installing = _installTimers.containsKey(x.versionId);
    final busy = _downloadingVid == x.versionId || installing;
    final label = _installLabel(x.versionId);
    return _CardShell(
      selected: false,
      onTap: () => _showDetail(x),
      child: Row(
        children: [
          LoraThumb(x.previewUrl, size: 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  x.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    LoraTypeBadge(x.type),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.download_outlined,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        '${x.downloadCount}'
                        '${x.sizeMb != null ? ' · ${x.sizeMb!.toStringAsFixed(0)}MB' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 与公共库同位的 ℹ。整卡点开也是详情,但那不显眼 —— 公共库那边有按钮、
          // 这边只能靠猜,同一页两套规矩。
          IconButton(
            tooltip: '详情',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.info_outline),
            color: scheme.onSurfaceVariant,
            onPressed: () => _showDetail(x),
          ),
          if (busy) ...[
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  label,
                  style: mono(
                    context,
                    size: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const _BusyIcon(),
          ] else if (done)
            IconButton(
              tooltip: '已在我的库',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.check, color: scheme.primary),
              onPressed: null,
            )
          else
            IconButton(
              tooltip: x.installed ? '加入我的库(库内已有,不重复下载)' : '下载到我的库(机房直拉)',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.download_outlined, color: scheme.primary),
              onPressed: () => _download(x),
            ),
        ],
      ),
    );
  }

  void _showDetail(CivitaiLoraInfo x) {
    final scheme = context.scheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        maxChildSize: .92,
        builder: (_, scroll) => StatefulBuilder(
          builder: (_, setSheet) {
            final done = _downloadedVids.contains(x.versionId);
            // 同卡片行:请求返回 ≠ 下完,轮询里还有记录就仍算忙
            final busy =
                _downloadingVid == x.versionId ||
                _installTimers.containsKey(x.versionId);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    children: [
                      Row(
                        children: [
                          LoraThumb(x.previewUrl, size: 52),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  x.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.titleSmall!.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    LoraTypeBadge(x.type),
                                    if (x.installed) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '库内已有',
                                        style: context.texts.labelSmall!
                                            .copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _metaGrid(x),
                      const SizedBox(height: 14),
                      Text(
                        '触发词',
                        style: context.texts.labelMedium!.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (x.triggerWords.isEmpty)
                        Text(
                          '无',
                          style: context.texts.bodySmall!.copyWith(
                            color: scheme.outline,
                          ),
                        )
                      else
                        for (final t in x.triggerWords)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.key,
                                    size: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: context.texts.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      if (x.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '标签',
                          style: context.texts.labelMedium!.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in x.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  t,
                                  style: context.texts.labelSmall!.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _DescSection(text: x.description),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(x.civitaiUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('在 Civitai 查看'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          // 先发车、立刻重建,再等结果:_download 的头两行是同步的
                          // (置 _downloadingVid),所以这时 setSheet 就能把按钮切成
                          // 「下载中…」。只在 await 之后刷新的话,整个下载期间弹层
                          // 纹丝不动 —— 用户看到的就是「点了没反应」,退出去才发现
                          // 列表那行在转圈。
                          onPressed: done || busy
                              ? null
                              : () async {
                                  final task = _download(x);
                                  setSheet(() {});
                                  await task;
                                  if (sheetCtx.mounted) setSheet(() {});
                                },
                          icon: Icon(
                            done ? Icons.check : Icons.download_outlined,
                            size: 18,
                          ),
                          label: Text(
                            busy
                                ? '下载中…'
                                : done
                                ? '已在我的库'
                                : '下载',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 详情页的一格「标签 + 值」。在线卡与库内卡两张详情共用同一套版式。
  Widget _metaCell(String label, String value) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.texts.labelSmall!.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _metaGridOf(List<Widget> cells) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 3.4,
    mainAxisSpacing: 6,
    crossAxisSpacing: 6,
    children: cells,
  );

  Widget _metaGrid(CivitaiLoraInfo x) {
    return _metaGridOf([
      _metaCell('作者', x.creator.isEmpty ? '—' : x.creator),
      _metaCell('推荐权重', '${x.recommendedWeight}'),
      _metaCell('下载数', '${x.downloadCount}'),
      _metaCell('大小', x.sizeMb != null ? '${x.sizeMb} MB' : '—'),
      _metaCell('基础模型', x.baseModel.isEmpty ? '—' : x.baseModel),
      _metaCell('文件', x.fileName.isEmpty ? '—' : x.fileName),
    ]);
  }

  /// 库内条目详情(公共库的 ℹ)。在线那张详情看的是 Civitai 的卡片,这张看的是
  /// **机房里这一份**:LR 编号、谁传的、推送状态、CLIP 能不能调 —— 都是卡片行上
  /// 放不下、但决定「挂上去会怎样」的信息。
  void _showLibraryDetail(LoraCardInfo opened) {
    final scheme = context.scheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        maxChildSize: .92,
        // StatefulBuilder 在外、Consumer 在内:收藏结果靠 provider 通知(Consumer),
        // 但「正在请求」是本页的 _busyName、provider 不会动 —— 那段得靠 setSheet
        // 自己重建,否则整个请求期间弹层纹丝不动。
        builder: (_, scroll) => StatefulBuilder(
          builder: (_, setSheet) => Consumer(
            builder: (_, ref2, _) {
              // 收藏关系会被弹层自己底下那颗按钮改掉,所以每次都从库里取最新那条;
              // 条目被回收(最后一个收藏者移出)后回落到打开时的快照,按钮那边会收场。
              final all =
                  ref2.watch(installedLorasProvider(_base)).value ??
                  const <LoraCardInfo>[];
              final x =
                  all.where((e) => e.name == opened.name).firstOrNull ?? opened;
              final busy = _busyName == x.name;
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      children: [
                        Row(
                          children: [
                            LoraThumb(x.previewUrl, size: 52),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    x.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.titleSmall!.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      LoraTypeBadge(x.type),
                                      if (x.isPrivate)
                                        Text(
                                          '私有',
                                          style: context.texts.labelSmall!
                                              .copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      if (!x.ready)
                                        Text(
                                          switch (x.syncStatus) {
                                            'uploading' => '推送中',
                                            'failed' => '推送失败',
                                            _ => '未就绪',
                                          },
                                          style: context.texts.labelSmall!
                                              .copyWith(
                                                color: x.syncStatus == 'failed'
                                                    ? scheme.error
                                                    : scheme.tertiary,
                                              ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _metaGridOf([
                          // 编号就是进生成载荷的那个键,排第一
                          _metaCell('编号', x.name),
                          _metaCell('推荐权重', '${x.recommendedWeight}'),
                          _metaCell('收藏人数', '${x.favoriteCount}'),
                          _metaCell('使用次数', '${x.usageCount}'),
                          _metaCell(
                            '大小',
                            x.sizeMb != null ? '${x.sizeMb} MB' : '—',
                          ),
                          _metaCell(
                            '来源',
                            x.addedBy == 'bot'
                                ? '官方'
                                : (x.isOwner ? '我上传的' : '用户上传'),
                          ),
                          // 没训文本编码器的,CLIP 强度调了不会有任何变化 ——
                          // 挂之前就该知道,不然会对着没反应的滑杆调半天
                          _metaCell('CLIP 强度', switch (x.hasTe) {
                            false => '不可调(无 TE)',
                            true => '可调',
                            _ => '未探测',
                          }),
                        ]),
                        if (x.syncError != null) ...[
                          const SizedBox(height: 12),
                          InfoNote(
                            '推送失败:${x.syncError}',
                            icon: Icons.cloud_off,
                            color: scheme.error,
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          '触发词',
                          style: context.texts.labelMedium!.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (x.triggerWords.isEmpty)
                          Text(
                            '无',
                            style: context.texts.bodySmall!.copyWith(
                              color: scheme.outline,
                            ),
                          )
                        else
                          for (final t in x.triggerWords)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.key,
                                      size: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        t,
                                        style: context.texts.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        const SizedBox(height: 12),
                        _LibraryDesc(item: x, base: _base, cache: _descCache),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                      child: Row(
                        children: [
                          if (x.sourceUrl.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(x.sourceUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('查看来源'),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            // 同在线详情那颗:先发车再重建(_favorite / _unfavorite
                            // 的头一行同步置 _busyName),否则请求期间按钮毫无反应
                            onPressed: busy
                                ? null
                                : () async {
                                    final task = x.favorited
                                        ? _unfavorite(x)
                                        : _favorite(x);
                                    setSheet(() {});
                                    await task;
                                    if (!sheetCtx.mounted) return;
                                    setSheet(() {});
                                    // 移出后这条被机房回收了(最后一个拥有者),
                                    // 详情已经没有对应实体,别留在原地
                                    final gone =
                                        !(ref2
                                                    .read(
                                                      installedLorasProvider(
                                                        _base,
                                                      ),
                                                    )
                                                    .value ??
                                                const <LoraCardInfo>[])
                                            .any((e) => e.name == x.name);
                                    if (gone) Navigator.pop(sheetCtx);
                                  },
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    x.favorited
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 18,
                                  ),
                            label: Text(x.favorited ? '移出我的库' : '加入我的库'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- 公共小件 ----
  /// 分类筛选行。[leading] 是排在分类前面的额外筛选件(在线页的「二次元」),
  /// 跟着一起横向滚 —— 钉在右端的话窄屏上会把分类挤没。
  Widget _catChips(
    String current,
    ValueChanged<String> onPick, {
    Widget? leading,
  }) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        children: [
          if (leading != null) ...[
            Center(child: leading),
            // 竖线分组:左边这个是服务端筛(决定拉回什么),右边是本地筛(在拉回的
            // 结果里挑)。不隔开会被读成同一组五选一。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SizedBox(
                  height: 18,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: context.scheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ],
          for (final (key, label) in _cats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: current == key,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onPick(key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyBody({
    required IconData icon,
    required String text,
    Widget? action,
  }) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Text(
            text,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 4), action],
        ],
      ),
    );
  }

  Widget _errorBody(String message) {
    return _emptyBody(
      icon: Icons.cloud_off,
      text: message,
      action: TextButton(onPressed: _loadInstalled, child: const Text('重试')),
    );
  }

  Widget _bottomBar(ColorScheme scheme, {required bool ready}) {
    return Docked(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.raisedFill(scheme.surface),
          border: context.skin.float
              ? null
              : Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .4),
                  ),
                ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 10),
            child: Row(
              children: [
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: Text(
                    '清空',
                    style: TextStyle(
                      color: _selected.isEmpty ? null : scheme.error,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  // 全集没加载出来时确认会把已挂的误清空,禁掉
                  onPressed: ready ? _confirm : null,
                  child: Text('确认挂载 (${_selected.length})'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 库卡片(我的/公共库共用):整卡点=选中挂载,右侧动作按 tab 注入。
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.action,
    this.showOfficial = false,
  });

  final LoraCardInfo item;
  final bool selected;
  final VoidCallback onTap;
  final Widget action;
  final bool showOfficial;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final label = context.texts.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    Widget stat(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: scheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Text(text, style: label),
      ],
    );

    return _CardShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          LoraThumb(item.previewUrl, size: 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                // 徽标最多能同时挂到六七个(私有 + 推送状态都算),窄屏放不下,
                // 用 Wrap 让它折行而不是压出溢出条
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LoraTypeBadge(item.type),
                    Text('w${item.recommendedWeight}', style: label),
                    if (item.triggerWords.isNotEmpty)
                      stat(Icons.key, '${item.triggerWords.length}'),
                    if (item.favoriteCount > 0)
                      stat(Icons.people_outline, '${item.favoriteCount}'),
                    if (item.isPrivate) stat(Icons.lock_outline, '私有'),
                    if (showOfficial && item.addedBy == 'bot')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '官方',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    if (!item.ready)
                      Text(
                        switch (item.syncStatus) {
                          'uploading' => '推送中',
                          'failed' => '推送失败',
                          _ => '未就绪',
                        },
                        style: context.texts.labelSmall!.copyWith(
                          color: item.syncStatus == 'failed'
                              ? scheme.error
                              : scheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Lifted(
      radius: BorderRadius.circular(14),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .08)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: .35),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BusyIcon extends StatelessWidget {
  const _BusyIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// 详情弹层里的「简介」块(三张详情共用)。
///
/// 正文**可划词**:Civitai 的简介常写着触发词怎么配、推荐权重、训练素材来源,
/// 弹层里选不中的纯文本最烦人 —— 长按起选,想要哪句拖哪句。
class _DescSection extends StatelessWidget {
  const _DescSection({required this.text, this.loading = false});

  final String text;

  /// 还在去 Civitai 取的路上(库内条目才有这一态)。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final body = text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '简介',
          style: context.texts.labelMedium!.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (loading)
          Row(
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '读取中…',
                style: context.texts.bodySmall!.copyWith(color: scheme.outline),
              ),
            ],
          )
        else if (body.isEmpty)
          Text(
            '(无简介)',
            style: context.texts.bodySmall!.copyWith(color: scheme.outline),
          )
        else
          // 划词,不是整段一把抓:简介里真正想拿走的通常只是其中一句
          // (触发词怎么配、推荐权重多少),整段拍进剪贴板还得再删一遍。
          // SelectableText 自带长按起选 + 拖拽把手 + 系统那条复制/全选。
          SelectableText(
            body,
            style: context.texts.bodySmall!.copyWith(height: 1.5),
          ),
      ],
    );
  }
}

/// 库内条目(我的 / 公共库)的简介块。
///
/// 注册表没存 description —— `/api/lora/list` 那张卡里根本没有这个字段,所以
/// 只能回头去 Civitai 取:source_url 里带着 `models/<model_id>`,拿显示名去
/// 现成的 `/api/lora/search`(服务端代理)搜一次,结果里对上同一个 model_id
/// 就是它的简介。简介是模型级的、与具体版本无关,所以按 model_id 对就够了。
///
/// 搜不着就当没有:简介是锦上添花,不值得为它把详情弹层拦住或弹错。
/// 自己上传的 LoRA(没有 Civitai 来源)直接显示「(无简介)」,不发请求。
class _LibraryDesc extends ConsumerStatefulWidget {
  const _LibraryDesc({
    required this.item,
    required this.base,
    required this.cache,
  });

  final LoraCardInfo item;
  final String base;

  /// 页面级缓存(LR 编号 → 简介),重开详情不重搜。
  final Map<String, String?> cache;

  @override
  ConsumerState<_LibraryDesc> createState() => _LibraryDescState();
}

class _LibraryDescState extends ConsumerState<_LibraryDesc> {
  bool _loading = false;
  String? _desc;

  /// `https://civitai.com/models/1234?modelVersionId=5678` → 1234。
  static int? _modelIdOf(String sourceUrl) {
    if (!sourceUrl.contains('civitai.com')) return null;
    final m = RegExp(r'/models/(\d+)').firstMatch(sourceUrl);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 搜索用的关键词。显示名可能被后端加过工:同名冲突时挂了 ` (LR7)` 后缀,
  /// 版本名与模型名不同时拼成 `模型 - 版本` —— 两截都会把全文搜索带偏,
  /// 而我们是按 model_id 对结果的,词越宽越容易命中。
  static String _queryOf(String displayName) {
    var q = displayName.replaceFirst(RegExp(r'\s*\(LR\d+\)$'), '').trim();
    final cut = q.lastIndexOf(' - ');
    if (cut > 0) q = q.substring(0, cut).trim();
    return q;
  }

  @override
  void initState() {
    super.initState();
    final cached = widget.cache;
    if (cached.containsKey(widget.item.name)) {
      _desc = cached[widget.item.name];
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    final x = widget.item;
    final modelId = _modelIdOf(x.sourceUrl);
    final query = _queryOf(x.displayName);
    if (modelId == null || query.isEmpty) {
      widget.cache[x.name] = null;
      return;
    }
    _loading = true; // 还在 initState 里,直接置位就行(第一帧还没画)
    String? found;
    try {
      final res = await ref
          .read(backendClientProvider)
          .searchLoras(query: query, base: widget.base);
      for (final it in res.items) {
        if (it.modelId == modelId && it.description.trim().isNotEmpty) {
          found = it.description.trim();
          break;
        }
      }
    } catch (_) {
      // 搜不通就当没简介 —— 这条路本来就是尽力而为
    }
    widget.cache[x.name] = found;
    if (mounted) {
      setState(() {
        _loading = false;
        _desc = found;
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      _DescSection(text: _desc ?? '', loading: _loading);
}

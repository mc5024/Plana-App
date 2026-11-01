import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/store/ui_prefs.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/fast_scroll_handle.dart';
import '../../../core/ui/pinch_columns.dart';
import '../../../core/ui/scroll_memory.dart';
import '../../generate/widgets/common.dart' show hintSnack;
import 'codex_block.dart';
import 'codex_card.dart';
import 'codex_favorites.dart';
import 'codex_masonry.dart';
import 'codex_models.dart';
import 'codex_providers.dart';
import 'codex_sheets.dart';

/// 法典浏览器:灵感页选中「法典」分类时的正文。
/// 顶部选法典 + 来源;下面搜索 + 顶级分类筛选 + 瀑布流(双指捏合换列数)。
/// 只读,点词条看详情。
class CodexView extends ConsumerStatefulWidget {
  const CodexView({super.key});

  @override
  ConsumerState<CodexView> createState() => _CodexViewState();
}

const _edge = 14.0;
const _gap = 10.0;

/// 瀑布流默认列数;捏合可在 1 ~ 4 列之间换。偏好里与标签库四类同表,键 `codex`。
const _kCols = 2;
const _kColsKey = 'codex';

class _CodexViewState extends ConsumerState<CodexView>
    with SingleTickerProviderStateMixin, PinchColumnsMixin {
  String _search = '';
  List<String> _catPath = const []; // 分类树选中路径(空=全部;前缀匹配词条 path)
  Timer? _debounce;
  bool _introScheduled = false; // 首次说明弹窗本会话是否已排期(防重复弹)
  final _masonry = CodexMasonry(gap: _gap);

  /// 正在显示的是哪一部(build 时定下)。换法典时按它把当前状态存回原主。
  String? _viewId;

  /// 每部法典各记各的搜索词与分类筛选,换走再换回来原样还原。
  /// 滚动位置记在 [ScrollMemory] 里,键带法典 id。
  final _views = <String, ({String search, List<String> cat})>{};

  late final _scroll = MemoScrollController.keyed(
    () => 'inspiration.codex.${_viewId ?? ''}',
  );

  /// 搜索框要能被程序清空(换法典时),所以不能是裸 TextField。
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- 双指捏合改列数(见 PinchColumnsMixin) ----

  @override
  int get initialGridColumns =>
      ref.read(uiPrefsProvider).inspirationColumns[_kColsKey] ?? _kCols;

  @override
  int get minGridColumns => 1;

  @override
  int get maxGridColumns => 4;

  @override
  ScrollController get pinchScrollController => _scroll;

  @override
  void onGridColumnsChanged(int cols) => ref
      .read(uiPrefsProvider.notifier)
      .patch(
        (p) => p.copyWith(
          inspirationColumns: {...p.inspirationColumns, _kColsKey: cols},
        ),
      );

  void _onSearch(String v) {
    _debounce?.cancel();
    // 上万词条,逐键过滤会卡;250ms 防抖
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = v);
    });
  }

  String _resolveSelectedId(List<CodexMeta> index) =>
      resolveSelectedCodex(index, ref.watch(selectedCodexProvider)).id;

  List<CodexEntry> _filtered(CodexData d, CodexBlock block) {
    final q = _search.trim().toLowerCase();
    return [
      for (final e in d.entries)
        if (_underCat(e) &&
            !block.hides(e.path) &&
            (q.isEmpty ||
                e.title.toLowerCase().contains(q) ||
                e.tags.toLowerCase().contains(q) ||
                e.characters.any((c) => c.prompt.toLowerCase().contains(q))))
          e,
    ];
  }

  bool _underCat(CodexEntry e) => codexPathUnder(e.path, _catPath);

  @override
  Widget build(BuildContext context) {
    // 换法典:当前这部的搜索与分类存回它名下,换上目标那部上次的(没去过就是空)。
    // 选择器在外层顶栏,靠 provider 联动。
    //
    // 搜索不能跨法典带过去:新法典多半一条都匹配不上,切过去只看到「没有匹配的
    // 词条」,没人会想到是上面那个旧关键词在过滤。输入框文本、过滤用的 _search、
    // 以及**防抖里压着的那次**三样一起换(不取消的话它会在切换后才落地,把旧
    // 关键词写进新法典)。滚动位置不用管:网格按法典 id 换 key 重建,从那部的
    // 账上落位。
    ref.listen(selectedCodexProvider, (_, next) {
      if (!mounted || next == null || next == _viewId) return;
      _debounce?.cancel();
      final from = _viewId;
      if (from != null) {
        _views[from] = (search: _searchCtrl.text, cat: _catPath);
      }
      final to = _views[next];
      _searchCtrl.text = to?.search ?? '';
      setState(() {
        _catPath = to?.cat ?? const [];
        _search = to?.search ?? '';
      });
    });
    final indexAsync = ref.watch(codexIndexProvider);
    return indexAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          _error('法典索引加载失败', () => ref.invalidate(codexIndexProvider)),
      data: (index) {
        if (index.isEmpty) return _msg('暂无法典');
        final selId = _viewId = _resolveSelectedId(index);
        final meta = index.firstWhere((m) => m.id == selId);
        // 首次进入法典功能:读盘确认为「没读过」时弹一次说明。
        if (ref.watch(codexIntroProvider) == false) _maybeShowIntro();
        return _body(index, meta);
      },
    );
  }

  /// 首次进入弹一次说明(post-frame 起弹,防重入)。
  void _maybeShowIntro() {
    if (_introScheduled) return;
    _introScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showIntroDialog();
    });
  }

  void _showIntroDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.menu_book_outlined, color: context.scheme.primary),
        title: const Text('法典图鉴'),
        content: SelectableText(
          '词条与例图数据来自\nhttps://novelai.quicktagcloud.com/\n\n'
          '本应用仅作展示与检索,内容版权归各法典作者所有。\n\n'
          '感谢所有法典作者与贡献者的整理分享。',
          style: context.texts.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(codexIntroProvider.notifier).ack();
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse('https://novelai.quicktagcloud.com/'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('来源与致谢'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(codexIntroProvider.notifier).ack();
              Navigator.pop(ctx);
            },
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Widget _body(List<CodexMeta> index, CodexMeta meta) {
    final dataAsync = ref.watch(codexDataProvider(meta.id));
    return dataAsync.when(
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              '正在载入 ${meta.entryCount} 条词条…',
              style: context.texts.bodySmall!.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      error: (e, _) =>
          _error('法典加载失败', () => ref.invalidate(codexDataProvider(meta.id))),
      data: (d) {
        // 词条到手就把这部的中文对照也拉上:点开详情时表多半已就绪,芯片不用
        // 先出离线词库的译名、再被对照表换一遍字。listen 不 watch —— 表到了
        // 这层不用重建。
        ref.listen(codexTagZhProvider(meta.id), (_, _) {});
        // 正选着的分类被屏蔽了:退回全部
        ref.listen(codexBlockProvider(meta.id), (_, b) {
          if (b.hides(_catPath)) setState(() => _catPath = const []);
        });
        final block = ref.watch(codexBlockProvider(meta.id));
        final media =
            ref.watch(codexMediaProvider).value ?? CodexMedia.fallback;
        final entries = _filtered(d, block);
        return Column(
          children: [
            _searchRow(),
            _filterBar(d, meta, media, entries, block),
            Expanded(
              child: entries.isEmpty
                  ? _msg(_search.isNotEmpty ? '没有匹配的词条' : '暂无词条')
                  : _grid(meta, media, entries),
            ),
          ],
        );
      },
    );
  }

  Widget _searchRow() {
    // 选法典单独一行当标题,搜索框占满整行
    return Padding(
      padding: const EdgeInsets.fromLTRB(_edge, 4, _edge, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CodexPickerButton(),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索标题 / 提示词…',
                prefixIcon: const Icon(Icons.search, size: 20),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                filled: true,
                fillColor: context.pageControlFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 筛选行:分类树入口(全部分类栏)+ 右侧收藏 / 随机。上下外边距相等。
  /// 分类按钮用 Expanded 占左、右侧两枚自然宽靠右——单个 Expanded 吸掉所有
  /// 余量,右侧才会真正贴右(Flexible + Spacer 双 flex 会把余量甩到行尾)。
  Widget _filterBar(
    CodexData d,
    CodexMeta meta,
    CodexMedia media,
    List<CodexEntry> entries,
    CodexBlock block,
  ) {
    final tree = d.effectiveTree;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_edge, 8, _edge, 8),
      child: Row(
        children: [
          Expanded(
            child: tree.isNotEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _catButton(d, meta, block),
                  )
                : const SizedBox.shrink(),
          ),
          _favButton(),
          const SizedBox(width: 8),
          _randomButton(meta, media, entries),
        ],
      ),
    );
  }

  /// 收藏入口:进去是收藏夹(跨法典,不受当前筛选影响)。带条数,
  /// 一眼知道里面有没有东西 —— 空收藏夹点进去再看到空页是白跑一趟。
  Widget _favButton() {
    final scheme = context.scheme;
    final n = ref.watch(codexFavKeysProvider).length;
    return Material(
      color: context.pageControlFill,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showCodexFavoritesSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                n > 0 ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 16,
                color: n > 0 ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '收藏',
                style: context.texts.labelMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (n > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$n',
                  style: mono(context, size: 11, color: scheme.primary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 分类胶囊:点开层级树选;已选时显示末级名 + 清除叉,主色实底标记。
  /// 有屏蔽生效时名字后带闭眼 + 屏蔽数。
  Widget _catButton(CodexData d, CodexMeta meta, CodexBlock block) {
    final scheme = context.scheme;
    final on = _catPath.isNotEmpty;
    final label = on ? _catPath.last : '全部分类';
    return Material(
      color: on ? scheme.primary : context.pageControlFill,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final picked = await showCodexCategorySheet(
            context,
            meta.id,
            d.effectiveTree,
            _catPath,
            d.entries,
          );
          if (picked != null && mounted) setState(() => _catPath = picked);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 15,
                color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (block.active) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.visibility_off_outlined,
                  size: 14,
                  color: on ? scheme.onPrimary : scheme.primary,
                ),
                const SizedBox(width: 3),
                Text(
                  '${block.paths.length}',
                  style: mono(
                    context,
                    size: 11,
                    color: on ? scheme.onPrimary : scheme.primary,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              if (on)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _catPath = const []),
                  child: Icon(Icons.close, size: 16, color: scheme.onPrimary),
                )
              else
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 随机按钮:从当前筛选出的词条里随机抽一条,弹详情并可「继续抽」。
  Widget _randomButton(
    CodexMeta meta,
    CodexMedia media,
    List<CodexEntry> entries,
  ) {
    final scheme = context.scheme;
    return Material(
      color: context.pageControlFill,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (entries.isEmpty) {
            hintSnack(context, '当前没有可抽的词条', icon: Icons.casino_outlined);
            return;
          }
          showCodexRandomSheet(context, meta, media, entries);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.casino_outlined,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '随机',
                style: context.texts.labelMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 瀑布流。几何见 [CodexMasonryLayout];捏合与过渡只重建 pinchBuilder 里那一块,
  /// 上面的筛选(上万条逐条比对)不跟着每帧重跑。
  Widget _grid(CodexMeta meta, CodexMedia media, List<CodexEntry> entries) =>
      pinchLayer(
        child: FastScrollHandle(
          child: pinchBuilder((_) {
            // 例图按落定列数下的列宽解码(gridColumns 在换档过渡中是起点那一档)
            final cols = gridColumns;
            final decodeW =
                (MediaQuery.sizeOf(context).width -
                    _edge * 2 -
                    _gap * (cols - 1)) /
                cols;
            return CustomScrollView(
              key: ValueKey(meta.id), // 换法典即换一份列表,从那部的滚动账上落位
              controller: _scroll,
              physics: pinchPhysics(const AlwaysScrollableScrollPhysics()),
              slivers: [
                // 顶部不留边:筛选行自带下外边距,再留一道就叠出双倍空隙
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(_edge, 0, _edge, _gap),
                  sliver: SliverGrid(
                    gridDelegate: zoomGridDelegate(
                      (n) => _masonry.delegate(entries, n),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => CodexCard(
                        codex: meta,
                        entry: entries[i],
                        media: media,
                        decodeWidth: decodeW,
                        // 详情页左右滑动就在当前筛选出的这一整批里翻
                        onTap: () => showCodexDetailSheet(
                          context,
                          meta,
                          media,
                          entries: entries,
                          index: i,
                        ),
                      ),
                      childCount: entries.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            );
          }),
        ),
      );

  Widget _error(String text, VoidCallback onRetry) {
    final scheme = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: scheme.outlineVariant,
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: context.texts.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: onRetry,
            style: context.pageTonalStyle,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _msg(String text) {
    final scheme = context.scheme;
    return Center(
      child: Text(
        text,
        style: context.texts.bodyMedium!.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Widget _miniTag(BuildContext context, String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .16),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text(
    label,
    style: context.texts.labelSmall!.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
    ),
  ),
);

/// 解析当前应显示的法典:选过就用选中项,否则取索引首个非 R18(退而取首个)。
CodexMeta resolveSelectedCodex(List<CodexMeta> index, String? sel) {
  if (sel != null) {
    for (final m in index) {
      if (m.id == sel) return m;
    }
  }
  final sfw = index.where((m) => !m.nsfw);
  return sfw.isNotEmpty ? sfw.first : index.first;
}

/// 「选择主法典」:法典页搜索框上面那行标题,写当前法典名与条数,点开换法典。
/// 换法典只改 [selectedCodexProvider],正文的分类筛选由 CodexView 监听联动重置。
class CodexPickerButton extends ConsumerWidget {
  const CodexPickerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final index = ref.watch(codexIndexProvider).value;
    if (index == null || index.isEmpty) return const SizedBox(height: 40);
    final meta = resolveSelectedCodex(index, ref.watch(selectedCodexProvider));
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final id = await showCodexPickerSheet(context, index, meta.id);
        if (id != null) {
          ref.read(selectedCodexProvider.notifier).select(id);
        }
      },
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 19, color: scheme.primary),
            const SizedBox(width: 8),
            // 整行都给了标题:写全名(选择器里那个是缩短的)。标题与箭头一组
            // 吃掉条数以外的全部宽度 —— Flexible 配 Spacer 会把余量对半分,
            // 标题只拿得到一半
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      meta.title.isNotEmpty ? meta.title : meta.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (meta.nsfw) ...[
                    const SizedBox(width: 6),
                    _miniTag(context, 'R18', scheme.error),
                  ],
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${meta.entryCount} 条',
              style: context.texts.labelMedium!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

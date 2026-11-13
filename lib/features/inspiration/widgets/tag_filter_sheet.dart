import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../artist_models.dart';
import '../tag_models.dart';
import '../../../l10n/l10n.dart';

/// 灵感页搜索框右侧那个漏斗的弹层:作者 + 适用模型两个筛选维度,外加排序。
///
/// 两者正交(「小明发的 + 标了 NAI 5 的」),所以合成一张表而不是各开一个入口。
/// 表内**左右切维、不上下堆**:两维各自都是一列长名单,叠起来第二节永远被顶在
/// 屏幕外,键盘一起来更看不见。角色没有适用模型这一维,切换那一行整行不出。

/// 一个候选作者。[id] 是条目上的归属键(QQ 号;存量数据可能是个名字串),
/// [nickname] 由公共库作者目录给,[count] 是当前范围内属于他的条目数。
class TagAuthor {
  const TagAuthor({required this.id, this.nickname, this.count = 0});

  final String id;
  final String? nickname;
  final int count;

  /// 展示名:有昵称用昵称,没有就是那串 QQ 号。
  String get label => nickname != null && nickname!.isNotEmpty ? nickname! : id;

  /// 昵称和 QQ 号都能搜到 —— 记得住名字的按名字找,记不住的按号找。
  bool matches(String q) =>
      label.toLowerCase().contains(q) || id.toLowerCase().contains(q);
}

/// 作者的完整署名 `昵称(QQ 号)`,查不到昵称就只剩号码。分组标题这种只有一行字
/// 的地方用它:光给昵称认不出是谁重名了,光给号码谁也记不住。
String authorDisplay(String id, Map<String, String> names) {
  final nick = names[id];
  return nick == null || nick.isEmpty ? id : '$nick($id)';
}

/// 从条目里点出候选作者:**列表里真有的人**才进候选,条目多的排前面。
/// [names] 为作者目录(id → 昵称),缺的那些回落成 QQ 号显示。
List<TagAuthor> collectTagAuthors(
  Iterable<TagEntry> entries,
  Map<String, String> names,
) {
  final count = <String, int>{};
  for (final e in entries) {
    final id = e.createdBy?.trim();
    if (id == null || id.isEmpty) continue;
    count[id] = (count[id] ?? 0) + 1;
  }
  final out = [
    for (final e in count.entries)
      TagAuthor(id: e.key, nickname: names[e.key], count: e.value),
  ];
  out.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : a.label.compareTo(b.label);
  });
  return out;
}

/// 一次筛选的两个维度(null = 该维度不筛)与排序档。
typedef TagFilters = ({String? author, String? model, TagSort sort});

/// 返回新的筛选值;点外面关掉返回 null(= 什么都不改)。
Future<TagFilters?> showTagFilterSheet(
  BuildContext context, {
  required List<TagAuthor> authors,
  required TagFilters current,
  required bool hasModels,
  required List<TagSort> sorts,
  required TagSort defaultSort,
}) => showModalBottomSheet<TagFilters>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _FilterSheet(
    authors: authors,
    current: current,
    hasModels: hasModels,
    sorts: sorts,
    defaultSort: defaultSort,
  ),
);

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.authors,
    required this.current,
    required this.hasModels,
    required this.sorts,
    required this.defaultSort,
  });

  final List<TagAuthor> authors;
  final TagFilters current;
  final bool hasModels;
  final List<TagSort> sorts;
  final TagSort defaultSort;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  final _input = TextEditingController();
  String _q = '';

  /// 当前在看哪一维:0=作者,1=适用模型,2=排序。开局落在已经改过的那一维。
  late int _dim = widget.current.author != null
      ? 0
      : widget.current.model != null
      ? 1
      : widget.current.sort != widget.defaultSort
      ? 2
      : 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  List<TagAuthor> get _hits {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return widget.authors;
    return [
      for (final a in widget.authors)
        if (a.matches(q)) a,
    ];
  }

  /// 选中一维即落地关闭:另一维保持原值,想两维都改就再开一次
  /// (常见情形是只筛一个,别为了少见的组合让每次都多一次点)。
  ///
  /// 参数三态:不传 = 这一维不动;[_Clear] = 清掉;字符串 = 换成它。
  void _apply({Object? author, Object? model, TagSort? sort}) {
    String? pick(Object? v, String? cur) => switch (v) {
      null => cur,
      _Clear() => null,
      _ => v as String,
    };
    Navigator.pop(context, (
      author: pick(author, widget.current.author),
      model: pick(model, widget.current.model),
      sort: sort ?? widget.current.sort,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;
    final sorted = widget.current.sort != widget.defaultSort;
    final dirty =
        widget.current.author != null || widget.current.model != null || sorted;
    final byAuthor = _dim == 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
            child: Row(
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.filter,
                  style: texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: dirty
                      ? () => Navigator.pop(context, (
                          author: null,
                          model: null,
                          sort: widget.defaultSort,
                        ))
                      : null,
                  child: Text(context.l10n.reset),
                ),
              ],
            ),
          ),
          // 各维**并排切换**,不上下堆:各自都是一列长名单,叠起来的话下面那节
          // 会被列表挤到屏外,键盘一顶更看不见。
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                _dimTab(
                  context,
                  0,
                  context.l10n.author,
                  widget.current.author != null,
                ),
                if (widget.hasModels) ...[
                  const SizedBox(width: 8),
                  _dimTab(
                    context,
                    1,
                    context.l10n.applicableModels,
                    widget.current.model != null,
                  ),
                ],
                const SizedBox(width: 8),
                _dimTab(context, 2, context.l10n.sort, sorted),
              ],
            ),
          ),
          if (byAuthor)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (_) {
                  // 敲回车 = 用补全里的第一条,省一次点。
                  final hits = _hits;
                  if (hits.isNotEmpty) _apply(author: hits.first.id);
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.l10n.nicknameOrQq,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          // 名单封顶 264 自己滚;键盘顶上来时再让它继续缩(Flexible)。
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 264),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: switch (_dim) {
                  0 => _authorRows(context),
                  1 => _modelRows(context),
                  _ => _sortRows(context),
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  /// 维度切换的药丸。右上角一个小点 = 这一维已经在筛(具体筛的哪个进去看勾)。
  Widget _dimTab(BuildContext context, int i, String label, bool on) {
    final scheme = context.scheme;
    final sel = _dim == i;
    final fg = sel ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Expanded(
      child: Material(
        color: sel ? scheme.primary : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _dim = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: context.texts.labelLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (on) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: fg,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _authorRows(BuildContext context) {
    final hits = _hits;
    return [
      if (_q.trim().isEmpty)
        _row(
          context,
          label: context.l10n.all,
          selected: widget.current.author == null,
          onTap: () => _apply(author: const _Clear()),
        ),
      for (final a in hits)
        _row(
          context,
          label: a.label,
          sub: a.nickname == null ? null : a.id,
          count: a.count,
          selected: widget.current.author == a.id,
          onTap: () => _apply(author: a.id),
        ),
      if (hits.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Text(
            widget.authors.isEmpty
                ? context.l10n.noSignedEntries
                : context.l10n.noMatchingAuthors,
            style: context.texts.bodySmall!.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }

  List<Widget> _modelRows(BuildContext context) => [
    for (final e in <(String?, String)>[
      (null, context.l10n.all),
      for (final g in ArtistModelGroup.values) (g.name, g.filterLabel),
      (kGenericModelFilter, context.l10n.genericUnlabeled(kGenericModelLabel)),
    ])
      _row(
        context,
        label: e.$2,
        selected: widget.current.model == e.$1,
        onTap: () => _apply(model: e.$1 ?? const _Clear()),
      ),
  ];

  List<Widget> _sortRows(BuildContext context) => [
    for (final s in widget.sorts)
      _row(
        context,
        label: s.label,
        selected: widget.current.sort == s,
        onTap: () => _apply(sort: s),
      ),
  ];

  /// 单行候选:左边名字(有昵称时后缀灰色 QQ 号),右边条目数 + 选中勾。
  Widget _row(
    BuildContext context, {
    required String label,
    String? sub,
    int? count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = context.scheme;
    final texts = context.texts;
    final muted = texts.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          children: [
            // 名字吃掉剩余宽度(长昵称截断),QQ 号 / 计数 / 勾都是定宽的
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: texts.bodyMedium!.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? scheme.primary : null,
                ),
              ),
            ),
            if (sub != null) ...[
              const SizedBox(width: 8),
              Text(sub, style: muted),
            ],
            if (count != null) ...[
              const SizedBox(width: 10),
              Text('$count', style: muted),
            ],
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check, size: 18, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「清空这一维」的哨兵:[_FilterSheetState._apply] 的 null 表示「这一维不动」,
/// 两者混在一起就没法表达「把作者筛选清掉」。
class _Clear {
  const _Clear();
}

import '../../core/util/prompt_tokens.dart' show cleanPromptToken, tokenizeSet;
import '../editor/editor_models.dart'
    show
        draftOf,
        outputOf,
        pickEditorText,
        setUnitsDisabled,
        stripFolds,
        topLevelUnits;
import '../inspiration/tag_models.dart' show TagCategory, TagEntry;
import 'models.dart';

/// 主提示词分区的纯函数:拼接、计数口径、列表整理。状态写入在 GenerateNotifier
/// 与 CanvasWorkspaceNotifier.updatePrompts。

/// 分区头尾的空白与逗号:拼接时去掉,免得出现 `a,, b`。
String _clean(String s) =>
    s.trim().replaceAll(RegExp(r'^[,，\s]+|[,，\s]+$'), '');

/// 这一格的这一侧进不进载荷。主体的负面一直进:卡上负面那行是整张卡的,
/// 停用 / 删掉主体那一行只管它的正向。
bool _on(PromptSection s, {required bool positive}) =>
    (s.isMain && !positive) || s.enabled;

/// 主体那一行删掉了,主体的词还在(负面一直在;正向是之后又被写进来的),
/// 按排在最上面算 —— 卡上也是补在最上面(见 [withMainRow])。
List<PromptSection> _withMain(List<PromptSection> list) =>
    list.any((x) => x.isMain) ? list : [const PromptSection.main(), ...list];

/// 卡上和改分区时用的那份行:主体那一行删掉之后主体又被写进了正向(读图导入、
/// AI 助手…),主体回到最上面。
List<PromptSection> withMainRow(List<PromptSection> list, String mainPrompt) =>
    list.isEmpty || list.any((x) => x.isMain) || mainPrompt.trim().isEmpty
    ? list
    : [const PromptSection.main(), ...list];

/// 主体的正向进不进载荷。没分区、主体那一行删掉了都算进:那时它要么就是
/// 全部的词,要么是空的。
bool mainEnabled(List<PromptSection> list) => list
    .firstWhere((x) => x.isMain, orElse: () => const PromptSection.main())
    .enabled;

/// 按行序把主体和启用的分区拼成一整串。[main] 是主体那一侧的词(正或负)。
///
/// 前面几格已经有的普通词,后面的格子里不再重复 —— 画风条目自带的负面常和
/// 主体负面撞(lowres、blurry),以前追加进同一串时就是去重的。
String joinSections(
  List<PromptSection> sections,
  String main, {
  required bool positive,
}) {
  if (sections.isEmpty) return main;
  final seen = <String>{};
  return [
    for (final s in _withMain(sections))
      if (_on(s, positive: positive))
        _dropSeen(
          _clean(s.isMain ? main : (positive ? s.positive : s.negative)),
          seen,
        ),
  ].where((p) => p.isNotEmpty).join(', ');
}

/// 带记号(权重、折叠、禁用、换行)的词不参与去重:拆开比对会拆坏它们。
final _syntax = RegExp(r'[{}\[\]:~<>#|\n]');

/// 去掉 [text] 里 [seen] 已有的普通词,再把这一格的普通词记进 [seen]。
/// 同一格里自己重复的照原样留着。
String _dropSeen(String text, Set<String> seen) {
  if (text.isEmpty) return text;
  final own = <String>{};
  final kept = <String>[];
  for (final piece in text.split(RegExp(r'[,，]'))) {
    final key = _syntax.hasMatch(piece) ? '' : cleanPromptToken(piece);
    if (key.isNotEmpty) {
      if (seen.contains(key)) continue;
      own.add(key);
    }
    kept.add(piece);
  }
  seen.addAll(own);
  return _clean(kept.join(','));
}

/// 去重比对用的键:普通词按 [cleanPromptToken],带记号的按原样(空白归一)。
String _wordKey(String piece) {
  final t = piece.trim();
  if (!_syntax.hasMatch(t)) return 'p:${cleanPromptToken(t)}';
  return 's:${t.replaceAll(RegExp(r'\s+'), ' ').toLowerCase()}';
}

/// 逗号切开,标出哪几段是能整段拿掉的顶层词:不在 `{}` `[]` `::` 组里,
/// 自身记号也收了口。
List<(String, bool)> _topPieces(String text) {
  final out = <(String, bool)>[];
  var depth = 0;
  var inWeight = false;
  for (final piece in text.split(RegExp(r'[,，]'))) {
    final top = depth == 0 && !inWeight;
    var d = 0;
    var tildes = 0;
    for (final c in piece.split('')) {
      if (c == '{' || c == '[') d++;
      if (c == '}' || c == ']') d--;
      if (c == '~') tildes++;
    }
    final weights = '::'.allMatches(piece).length;
    depth += d;
    if (weights.isOdd) inWeight = !inWeight;
    out.add((
      piece,
      top &&
          d == 0 &&
          weights.isEven &&
          tildes.isEven &&
          piece.trim().isNotEmpty,
    ));
  }
  return out;
}

/// 从 [text] 里拿掉启用的格子里已有的顶层词。[main] 是主体那一侧的词,
/// [withMain] 为 false 时主体不算。
String dropSectionWords(
  String text,
  List<PromptSection> sections,
  String main, {
  required bool positive,
  bool withMain = false,
}) {
  if (text.trim().isEmpty) return text;
  final have = <String>{
    for (final s in _withMain(sections))
      if ((withMain || !s.isMain) && _on(s, positive: positive))
        for (final (p, top) in _topPieces(
          s.isMain ? main : (positive ? s.positive : s.negative),
        ))
          if (top) _wordKey(p),
  };
  if (have.isEmpty) return text;
  return _clean(
    [
      for (final (p, top) in _topPieces(text))
        if (!top || !have.contains(_wordKey(p))) p,
    ].join(','),
  );
}

/// AI 助手的提议写进创作页的方式。
enum SectionImport {
  /// 只换主体,分区留着;分区里已有的词不再写进主体。
  main,

  /// 接在最后新建一格,原有的不动;已有的词不再写进这一格。
  newSection,

  /// 分区整列清掉,整份写进主体。
  clear,
}

/// 一组正负向按 [mode] 写进 [s]。导入和「直接生成」共用,两条路出同一张图。
/// [sectionName] 是「新建分区」那一格的名字。
GenerateState importPromptsInto(
  GenerateState s,
  String positive,
  String negative,
  SectionImport mode, {
  required String Function() newId,
  String sectionName = 'AI',
}) {
  final mainMode = mode == SectionImport.main && s.sections.isNotEmpty;
  if (mode == SectionImport.newSection) {
    final pos = dropSectionWords(
      positive,
      s.sections,
      s.prompt,
      positive: true,
      withMain: true,
    );
    final neg = dropSectionWords(
      negative,
      s.sections,
      s.negativePrompt,
      positive: false,
      withMain: true,
    );
    if (pos.trim().isEmpty && neg.trim().isEmpty) return s;
    final rows = s.sections.isEmpty
        ? const [PromptSection.main()]
        : withMainRow(s.sections, s.prompt);
    return s.copyWith(
      sections: [
        ...rows,
        PromptSection(
          id: newId(),
          name: sectionName,
          positive: pos,
          negative: neg,
        ),
      ],
    );
  }
  final pos = mainMode
      ? dropSectionWords(positive, s.sections, s.prompt, positive: true)
      : positive;
  final neg = mainMode
      ? dropSectionWords(
          negative,
          s.sections,
          s.negativePrompt,
          positive: false,
        )
      : negative;
  return s.copyWith(
    prompt: pos,
    promptRaw: pos == s.prompt ? s.promptRaw : '',
    negativePrompt: neg,
    negativePromptRaw: neg == s.negativePrompt ? s.negativePromptRaw : '',
    sections: !mainMode
        ? const []
        : [
            for (final x in withMainRow(s.sections, pos))
              x.isMain && pos.trim().isNotEmpty ? x.copyWith(enabled: true) : x,
          ],
  );
}

/// 同 [joinSections],拼的是编辑器草稿(带折叠 / 禁用)。草稿过期的那一格
/// 退回定稿,与载入编辑器时同一口径。
String _joinDrafts(
  List<PromptSection> sections,
  String mainDraft, {
  required bool positive,
}) => [
  for (final s in _withMain(sections))
    if (_on(s, positive: positive))
      _clean(
        s.isMain
            ? mainDraft
            : positive
            ? pickEditorText(s.positiveRaw, s.positive)
            : pickEditorText(s.negativeRaw, s.negative),
      ),
].where((p) => p.isNotEmpty).join(', ');

/// 生成快照:分区拼进主提示词,快照里不再带分区。
///
/// 入库、「重新生成」、图库搜索、图片元数据都按这一整串走,和发给 NAI 的一致;
/// 草稿也照样拼一份,导回创作页时折叠还在。拼进去的那几格记在
/// [GenerateState.composedSections]。没有分区原样返回。
GenerateState composeSections(GenerateState s) {
  if (s.sections.isEmpty) {
    return s.composedSections.isEmpty
        ? s
        : s.copyWith(composedSections: const []);
  }
  final pos = joinSections(s.sections, s.prompt, positive: true);
  final neg = joinSections(s.sections, s.negativePrompt, positive: false);
  final posDraft = _joinDrafts(
    s.sections,
    pickEditorText(s.promptRaw, s.prompt),
    positive: true,
  );
  final negDraft = _joinDrafts(
    s.sections,
    pickEditorText(s.negativePromptRaw, s.negativePrompt),
    positive: false,
  );
  // 跨格去重删过词时草稿对不上定稿,不带(读取侧也会这么判,这里先省一份)
  String draft(String d, String out) =>
      outputOf(d) == out ? draftOf(d, out) : '';
  return s.copyWith(
    prompt: pos,
    negativePrompt: neg,
    promptRaw: draft(posDraft, pos),
    negativePromptRaw: draft(negDraft, neg),
    sections: const [],
    composedSections: [
      for (final x in _withMain(s.sections))
        if (x.isMain)
          PromptSection(
            id: kMainSectionId,
            name: x.name,
            positive: x.enabled ? _clean(s.prompt) : '',
            negative: _clean(s.negativePrompt),
          )
        else if (x.enabled)
          PromptSection(
            id: x.id,
            name: x.name,
            positive: _clean(x.positive),
            negative: _clean(x.negative),
            artist: x.artist,
          ),
    ],
  );
}

/// 读图导入的分区按 [append] 写进 [s]。[rows] 是图里存的那几格(主体的词写在
/// 主体行里);[mainNegative] 为 null 时负面不动。
///
/// 完全覆盖:主提示词换成这几格,主体没选就空着。新建分区:每格接在最后,
/// 主体那格叫「分区 N」,已有的词不再写进去(同 [importPromptsInto]);
/// [mainNegative] 跟着主体那格走,主体没选就跟第一格。
GenerateState importSectionsInto(
  GenerateState s,
  List<PromptSection> rows, {
  String? mainNegative,
  required bool append,
  required String Function() newId,
}) {
  if (!append) {
    final main = rows.where((x) => x.isMain).firstOrNull;
    return s.copyWith(
      prompt: main?.positive ?? '',
      promptRaw: '',
      negativePrompt: mainNegative,
      negativePromptRaw: mainNegative == null ? null : '',
      sections: normalizeSections([
        for (final x in rows)
          x.isMain
              ? PromptSection.main(name: x.name)
              : PromptSection(
                  id: newId(),
                  name: x.name,
                  positive: x.positive,
                  negative: x.negative,
                  artist: x.artist,
                ),
      ]),
    );
  }
  final hasMain = rows.any((x) => x.isMain);
  var out = s;
  for (var i = 0; i < rows.length; i++) {
    final x = rows[i];
    final neg = x.isMain
        ? mainNegative ?? ''
        : !hasMain && i == 0 && mainNegative != null
        ? [
            mainNegative,
            x.negative,
          ].map(_clean).where((p) => p.isNotEmpty).join(', ')
        : x.negative;
    final next = importPromptsInto(
      out,
      x.positive,
      neg,
      SectionImport.newSection,
      newId: newId,
      sectionName: x.isMain
          ? nextSectionName(
              out.sections.isEmpty
                  ? const [PromptSection.main()]
                  : withMainRow(out.sections, out.prompt),
            )
          : x.name,
    );
    if (identical(next, out)) continue;
    out = x.artist
        ? next.copyWith(
            sections: [
              ...next.sections.take(next.sections.length - 1),
              PromptSection(
                id: next.sections.last.id,
                name: next.sections.last.name,
                positive: next.sections.last.positive,
                negative: next.sections.last.negative,
                artist: true,
              ),
            ],
          )
        : next;
  }
  return out;
}

/// token 读数要算进去的分区词(启用、不含主体),[except] 那一格除外
/// (编辑器里正开着它,读数用编辑器里的实时文本)。
List<String> sectionTexts(
  List<PromptSection> sections, {
  required bool positive,
  String? except,
}) => [
  for (final s in sections)
    if (!s.isMain && s.enabled && s.id != except)
      positive ? s.positive : s.negative,
];

/// 主体最多一行(可以没有:那一行删掉了)。只剩主体(或什么都没有)就整列清空,
/// 卡片回到原来的样子 —— 剩下的主体是停用着的除外:回到原样就没处看出它停着,
/// 正向会悄悄又进载荷。
List<PromptSection> normalizeSections(List<PromptSection> list) {
  if (!list.any((s) => !s.isMain)) {
    final main = list.where((s) => s.isMain).firstOrNull;
    return main != null && !main.enabled ? [main] : const [];
  }
  final out = <PromptSection>[];
  var hasMain = false;
  for (final s in list) {
    if (s.isMain) {
      if (hasMain) continue;
      hasMain = true;
    }
    out.add(s);
  }
  return out;
}

/// 整段的词都标成禁用(`~tag~`)。折叠先摊开:折叠单元套不了禁用。
String disableAllTags(String draft) {
  final plain = stripFolds(draft);
  final n = topLevelUnits(plain, const {}).length;
  if (n == 0) return plain;
  return setUnitsDisabled(plain, const {}, [
    for (var i = 0; i < n; i++) i,
  ], true);
}

/// 多选「合并」:勾的几格合成一格。留下的是勾选里的主体(勾了的话,主体删不掉),
/// 否则最上面那格,名字、位置不变;各格的词按行序从上往下接,挨着的几格合完
/// 拼出来的串一字不差。有一格开着合完就开着,停用那几格的词带着禁用标记进来:
/// 原来不出图的合完也不出图。不到两格返回 null。
GenerateState? mergeSectionsIn(GenerateState s, Set<String> ids) {
  final picked = [
    for (final x in s.sections)
      if (ids.contains(x.id)) x,
  ];
  if (picked.length < 2) return null;
  final target = picked.firstWhere((x) => x.isMain, orElse: () => picked.first);
  String pos(PromptSection x) => x.isMain
      ? pickEditorText(s.promptRaw, s.prompt)
      : pickEditorText(x.positiveRaw, x.positive);
  String neg(PromptSection x) => x.isMain
      ? pickEditorText(s.negativePromptRaw, s.negativePrompt)
      : pickEditorText(x.negativeRaw, x.negative);
  final on = picked.any((x) => x.enabled);
  // 合完那一格(那一侧)开着,才需要给停用那几段打禁用标记;主体的负面
  // 一直开着(见 _on),合进主体时负面那侧也就一直开着
  final negOn = target.isMain || on;
  String side(PromptSection x, String d, {required bool positive}) =>
      (positive ? on : negOn) &&
          !_on(x, positive: positive) &&
          d.trim().isNotEmpty
      ? disableAllTags(d)
      : d;
  String join(Iterable<String> parts) =>
      parts.map(_clean).where((p) => p.isNotEmpty).join(', ');
  final pDraft = join([
    for (final x in picked) side(x, pos(x), positive: true),
  ]);
  final nDraft = join([
    for (final x in picked) side(x, neg(x), positive: false),
  ]);
  final p = outputOf(pDraft), n = outputOf(nDraft);
  final rest = [
    for (final x in s.sections)
      if (!ids.contains(x.id) || x.id == target.id) x,
  ];
  if (target.isMain) {
    return s.copyWith(
      prompt: p,
      promptRaw: draftOf(pDraft, p),
      negativePrompt: n,
      negativePromptRaw: draftOf(nDraft, n),
      sections: normalizeSections([
        for (final x in rest) x.isMain ? x.copyWith(enabled: on) : x,
      ]),
    );
  }
  return s.copyWith(
    sections: normalizeSections([
      for (final x in rest)
        x.id == target.id
            ? x.copyWith(
                positive: p,
                positiveRaw: draftOf(pDraft, p),
                negative: n,
                negativeRaw: draftOf(nDraft, n),
                enabled: on,
              )
            : x,
    ]),
  );
}

/// 新分区的默认名「分区 N」,N 取第一个没被占用的序号。
String nextSectionName(List<PromptSection> list) {
  final used = {for (final s in list) s.name};
  var n = 1;
  while (used.contains('分区 $n')) {
    n++;
  }
  return '分区 $n';
}

/// 删掉的分区放回原位。删的是最后一格时主体也跟着没了,[main] 是当时的主体
/// (那时本来就没有主体那一行就是 null)。
List<PromptSection> restoreSection(
  List<PromptSection> list,
  PromptSection removed,
  int index, {
  PromptSection? main = const PromptSection.main(),
}) {
  final out = list.isEmpty && main != null && !removed.isMain
      ? [main]
      : [...list];
  out.insert(index.clamp(0, out.length), removed);
  return normalizeSections(out);
}

/// 灵感库条目各自成一格,不折叠:名字取条目名(调用方换成分类名),正负向原样
/// 放进这一格。新格子一律接在最后,按加进来的先后往下排 —— 别按分类插到
/// 主体前后,那样主体看着像在跳。
///
/// 去重同以前追加时:词已经全在提示词里的跳过;同名同词的格子已经在
/// (多半是停用了)就打开它,不另建。没分区时连主体一起建出来。
List<PromptSection> withEntrySections(
  List<PromptSection> list,
  String mainPrompt,
  Iterable<TagEntry> entries, {
  required String Function() newId,
}) {
  final out = list.isEmpty ? [const PromptSection.main()] : [...list];
  final have = tokenizeSet(joinSections(out, mainPrompt, positive: true));
  for (final e in entries) {
    final rawPos = e.positive.trim(), rawNeg = e.negative.trim();
    if (rawPos.isEmpty && rawNeg.isEmpty) continue;
    final pos = outputOf(rawPos), neg = outputOf(rawNeg);
    final name = e.name.trim();
    final same = out.indexWhere(
      (s) => !s.isMain && s.name.trim() == name && s.positive.trim() == pos,
    );
    if (same >= 0) {
      out[same] = out[same].copyWith(enabled: true);
      continue;
    }
    final toks = tokenizeSet(pos);
    if (toks.isNotEmpty && have.containsAll(toks)) continue;
    have.addAll(toks);
    final sec = PromptSection(
      id: newId(),
      name: name.isEmpty ? nextSectionName(out) : name,
      positive: pos,
      positiveRaw: draftOf(rawPos, pos),
      negative: neg,
      negativeRaw: draftOf(rawNeg, neg),
      artist: e.category == TagCategory.artist,
    );
    out.add(sec);
  }
  return normalizeSections(out);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/ui_prefs.dart';
import '../../editor/editor_models.dart' show outputOf;
import '../../inspiration/public_tags.dart';
import '../../inspiration/tag_editor_page.dart';
import '../../inspiration/tag_library.dart';
import '../../inspiration/tag_models.dart';
import '../../inspiration/widgets/char_pick_sheet.dart' show panelTagCats;
import '../generate_state.dart';
import '../models.dart' show PromptSection;
import 'common.dart';
import '../../../l10n/l10n.dart';

/// 这一格存进灵感库的词:实际出图的那份(停用的不算、折叠展开)。主体只存正向,
/// 卡上负面那行是整张卡的。
({String positive, String negative}) sectionSaveText(
  PromptSection s,
  String mainPrompt,
) => s.isMain
    ? (positive: mainPrompt.trim(), negative: '')
    : (positive: s.positive.trim(), negative: s.negative.trim());

/// 存进灵感库时默认落的分类:画风格是画风;从灵感库条目加进来的落那条的分类;
/// 名字就叫「画风」「角色」「场景」或某个自定义类别名的落那一类;别的不猜。
TagCategory? sectionSaveCategory(
  PromptSection s,
  List<TagCategory> cats,
  Iterable<TagEntry> known,
) {
  if (s.artist) return TagCategory.artist;
  for (final e in known) {
    if (s.sources.contains(e.id) && cats.contains(e.category)) {
      return e.category;
    }
  }
  final name = s.name.trim();
  for (final c in cats) {
    if (tagCategoryDef(c).label == name) return c;
  }
  return null;
}

/// 自己起的分区名,存进灵感库时直接当条目名。主体、「分区 N」、分类名、
/// 法典(含改过的名字)、来源条目的名字这类默认名不算。
String? customSectionName(
  PromptSection s,
  List<TagCategory> cats,
  Iterable<TagEntry> known,
) {
  final name = s.name.trim();
  if (name.isEmpty ||
      name == '主体' ||
      name == '法典' ||
      name == codexTabLabel() ||
      RegExp(r'^分区 \d+$').hasMatch(name) ||
      kTagCategoryDefs.any((d) => d.label == name) ||
      cats.any((c) => tagCategoryDef(c).label == name) ||
      known.any((e) => s.sources.contains(e.id) && e.name.trim() == name)) {
    return null;
  }
  return name;
}

/// 库里同分类已有同样词的那条(逗号两边的空白不算)。
TagEntry? sameLibraryEntry(
  Iterable<TagEntry> entries,
  TagCategory category,
  String positive,
  String negative,
) {
  String norm(String s) => outputOf(s)
      .split(RegExp(r'[,，]'))
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .join(',');
  final p = norm(positive), n = norm(negative);
  for (final e in entries) {
    if (e.category == category &&
        norm(e.positive) == p &&
        norm(e.negative) == n) {
      return e;
    }
  }
  return null;
}

/// 「存到灵感库」上次落的类别记在偏好里的这一格。
const _kLastPage = 'sectionSave';

/// 猜不出分类时落哪一类:上次存到的那类,没有就是第一类。
TagCategory _fallbackCategory(WidgetRef ref, List<TagCategory> cats) {
  final last = ref.read(uiPrefsProvider).lastPages[_kLastPage];
  final c = last == null ? null : tagCategoryByWebId(last);
  return c != null && cats.contains(c) ? c : cats.first;
}

/// 多选栏「存到灵感库」(勾一格):这一格进灵感页的新建页,词、分类、画风编号
/// 都填好,封面、标签在那页补,存不存也由那页定。分类猜不出来时落上次存到的
/// 那类,新建页标题可点换类别。同分类里已有一样的词就不新建,提示是哪一条。
/// 进了新建页(或碰到已有的)返回 true,调用方据此退出多选。
Future<bool> saveSectionToLibrary(
  BuildContext anchor,
  WidgetRef ref,
  PromptSection section,
) async {
  final text = sectionSaveText(section, ref.read(generateProvider).prompt);
  if (text.positive.isEmpty) return false;
  final lib = await ref.read(tagLibraryProvider.future);
  if (!anchor.mounted) return false;
  final cats = panelTagCats(lib);
  if (cats.isEmpty) return false;
  final known = _knownEntries(ref, lib);
  final cat =
      sectionSaveCategory(section, cats, known) ?? _fallbackCategory(ref, cats);
  // 调用方随后退出多选,这颗钮就没了:导航先拿在手里
  final nav = Navigator.of(anchor);
  if (sameLibraryEntry(lib.entries, cat, text.positive, text.negative)
      case final e?) {
    hintSnack(
      anchor,
      anchor.l10n.inspirationAlreadyHas(e.name),
      actionLabel: anchor.l10n.edit,
      onAction: () =>
          nav.push(sharedAxisRoute(TagEditorPage(cat: e.category, edit: e))),
    );
    return true;
  }
  final code = cat == TagCategory.artist
      ? suggestArtistCode(_artistNames(ref, lib))
      : null;
  unawaited(
    nav.push(
      sharedAxisRoute(
        TagEditorPage(
          cat: cat,
          draft: (
            name: customSectionName(section, cats, known) ?? code ?? '',
            positive: text.positive,
            negative: text.negative,
            tags: const [],
          ),
          categories: cats,
          lastPageKey: _kLastPage,
        ),
      ),
    ),
  );
  return true;
}

/// 分区来源条目(按 id 认分类和默认名):本地库和公共库。
List<TagEntry> _knownEntries(WidgetRef ref, TagLibraryState lib) => [
  ...lib.entries,
  ...?ref.read(publicTagsProvider(TagCategory.character)).value,
  ...?ref.read(publicTagsProvider(TagCategory.artist)).value,
];

/// 画风编号要避开的名字:本地和公共库(公共库没拉到就只看本地,同新建页的「编号」)。
Set<String> _artistNames(WidgetRef ref, TagLibraryState lib) => {
  for (final e in lib.of(TagCategory.artist)) e.name,
  for (final e
      in ref.read(publicTagsProvider(TagCategory.artist)).value ??
          const <TagEntry>[])
    e.name,
};

/// 多选栏「存到灵感库」(勾了几格):不进新建页,每格直接存成一条。分类照单格
/// 那样猜,猜不出的落上次存到的那类;名字用自己起的分区名,画风格用新编号,
/// 都没有就取第一个词;同类重名加「(副本)」。同类里已有一样词的跳过。
/// 返回 (存了几条, 跳过几条)。
Future<({int saved, int skipped})> saveSectionsToLibrary(
  WidgetRef ref,
  List<PromptSection> sections,
) async {
  final prompt = ref.read(generateProvider).prompt;
  final notifier = ref.read(tagLibraryProvider.notifier);
  var lib = await ref.read(tagLibraryProvider.future);
  final cats = panelTagCats(lib);
  if (cats.isEmpty) return (saved: 0, skipped: 0);
  final fallback = _fallbackCategory(ref, cats);
  final occupied = _artistNames(ref, lib);
  var saved = 0, skipped = 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final s in sections) {
    final text = sectionSaveText(s, prompt);
    if (text.positive.isEmpty) continue;
    final known = _knownEntries(ref, lib);
    final cat = sectionSaveCategory(s, cats, known) ?? fallback;
    if (sameLibraryEntry(lib.entries, cat, text.positive, text.negative) !=
        null) {
      skipped++;
      continue;
    }
    String? name = customSectionName(s, cats, known);
    if (name == null && cat == TagCategory.artist) {
      name = suggestArtistCode(occupied);
    }
    name ??= _firstTag(text.positive);
    occupied.add(name);
    await notifier.upsert(
      TagEntry(
        id: TagLibrary.newId(cat),
        category: cat,
        name: notifier.uniqueName(cat, name),
        positive: text.positive,
        negative: text.negative,
        createdAt: now + saved,
      ),
    );
    lib = ref.read(tagLibraryProvider).value ?? lib;
    saved++;
  }
  return (saved: saved, skipped: skipped);
}

/// 第一个词(去掉权重括号),太长截断,当条目名。
String _firstTag(String positive) {
  final first = outputOf(positive)
      .split(RegExp(r'[,，]'))
      .map((x) => x.trim())
      .firstWhere((x) => x.isNotEmpty, orElse: () => '未命名');
  final clean = first.replaceAll(RegExp(r'^[\[{(]+|[\]})]+$'), '');
  final t = clean.isEmpty ? first : clean;
  return t.length > 16 ? '${t.substring(0, 16)}…' : t;
}

import '../../l10n/l10n.dart';

// 存档里的默认名都是中文原文(分区、角色、画布……),换界面语言不改数据,
// 只在显示时换成译名;用户自己起的名字原样。

final _sectionN = RegExp(r'^分区 (\d+)$');

/// 分区名:主体 / 画风 / 法典 / 分区 n。
String sectionDisplayName(AppLocalizations l, String name) {
  switch (name) {
    case '主体':
      return l.sectionMain;
    case '画风':
      return l.sectionStyle;
    case '法典':
      return l.sectionCodex;
  }
  if (_sectionN.firstMatch(name) case final m?) {
    return l.sectionN(int.parse(m[1]!));
  }
  return name;
}

/// 角色参考图入库时的默认名。
String refDisplayName(AppLocalizations l, String name) =>
    name == '参考图' ? l.refDefaultName : name;

final _canvasN = RegExp(r'^画布 (\d+)$');
const _copySuffix = ' · 副本';

/// 画布名:默认画布 / 画布 n,复制出来的带「 · 副本」后缀。
String canvasDisplayName(AppLocalizations l, String name) {
  if (name.endsWith(_copySuffix)) {
    final base = name.substring(0, name.length - _copySuffix.length);
    return '${canvasDisplayName(l, base)}${l.canvasCopySuffix}';
  }
  if (name == '默认画布') return l.defaultCanvas;
  if (_canvasN.firstMatch(name) case final m?) {
    return l.canvasN(int.parse(m[1]!));
  }
  return name;
}

final _characterN = RegExp(r'^角色 (\d+)$');

/// 角色卡默认名:角色 n。
String characterDisplayName(AppLocalizations l, String name) {
  if (name == '角色') return l.refCharacter;
  if (_characterN.firstMatch(name) case final m?) {
    return l.characterN(int.parse(m[1]!));
  }
  return name;
}

/// Vibe 入库时的默认名。
String vibeDisplayName(AppLocalizations l, String name) =>
    name == '未命名 Vibe' ? l.untitledVibe : name;

/// Vibe 的保留标签「收藏」。
String vibeTagDisplayName(AppLocalizations l, String tag) =>
    tag == '收藏' ? l.favorites : tag;

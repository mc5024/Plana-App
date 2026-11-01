import 'package:flutter/material.dart';

import 'app_skin.dart';

/// 编辑器专用「实体类型」强调色。
/// 说明:正面=primary、负面=error 由 M3 语义角色天然给出;
/// 但「角色 / OC / 作品 / 加权 / 降权」是种子色无法表达的类型语义,集中定义在此扩展里,
/// 不散落到各处硬编码,将来换皮改这一处即可。
@immutable
class EditorPalette extends ThemeExtension<EditorPalette> {
  const EditorPalette({
    required this.character,
    required this.oc,
    required this.work,
    required this.artist,
    required this.weightUp,
    required this.weightDown,
    required this.weightUpWash,
    required this.weightDownWash,
    required this.weightUpBorder,
    required this.weightDownBorder,
    required this.cursor,
  });

  /// 角色(靛紫)· 也是光标高亮色
  final Color character;

  /// 我的 OC(绿)
  final Color oc;

  /// 作品(紫罗兰)
  final Color work;

  /// 画师串(品红)。两个变体同值:原先在 `completion_bar` 内联硬编码时就是
  /// 一个值通吃亮暗,搬进来只做归位不改观感;要分变体随时在这里加。
  final Color artist;

  /// 加权 {} (橙,文本/读数/按钮用)
  final Color weightUp;

  /// 降权 [] (蓝,文本/读数/按钮用)
  final Color weightDown;

  /// 加权底色(朱红;web 的深锈红在浅色底上会被冲成棕褐,改用更红的
  /// 色相并抬高透明度下限,浅色主题下才读得出「红」)
  final Color weightUpWash;

  /// 降权底色(web rgba(59,130,246) 蓝)
  final Color weightDownWash;

  /// 加权 chip 边框(web rgba(251,146,60) 橙)
  final Color weightUpBorder;

  /// 降权 chip 边框(web rgba(96,165,250) 浅蓝)
  final Color weightDownBorder;

  /// 输入光标
  final Color cursor;

  /// 浅色变体:在浅色表面上仍清晰可辨的类型强调色(比暗色稿加深提高对比)。
  static const light = EditorPalette(
    character: Color(0xFF6750A4), // 靛紫
    oc: Color(0xFF2E7D32), // 绿
    work: Color(0xFF8E44AD), // 紫罗兰
    artist: Color(0xFFC2569B), // 品红
    weightUp: Color(0xFFC7620E), // 橙
    weightDown: Color(0xFF1B66C9), // 蓝
    weightUpWash: Color(0xFFC63A10), // 朱红(浅底上显红)
    weightDownWash: Color(0xFF3B82F6), // web 蓝
    weightUpBorder: Color(0xFFFB923C), // web 橙
    weightDownBorder: Color(0xFF60A5FA), // web 浅蓝
    cursor: Color(0xFF6750A4),
  );

  /// 深色变体:文本强调色提亮保证暗底可读,底色/边框回到 web 暗色稿原色。
  static const dark = EditorPalette(
    character: Color(0xFFCBB8FF),
    oc: Color(0xFF81C784),
    work: Color(0xFFCE93D8),
    artist: Color(0xFFC2569B),
    weightUp: Color(0xFFFFB74D),
    weightDown: Color(0xFF64B5F6),
    weightUpWash: Color(0xFFC2410C),
    weightDownWash: Color(0xFF3B82F6),
    weightUpBorder: Color(0xFFFB923C),
    weightDownBorder: Color(0xFF60A5FA),
    cursor: Color(0xFFCBB8FF),
  );

  @override
  EditorPalette copyWith({
    Color? character,
    Color? oc,
    Color? work,
    Color? artist,
    Color? weightUp,
    Color? weightDown,
    Color? weightUpWash,
    Color? weightDownWash,
    Color? weightUpBorder,
    Color? weightDownBorder,
    Color? cursor,
  }) => EditorPalette(
    character: character ?? this.character,
    oc: oc ?? this.oc,
    work: work ?? this.work,
    artist: artist ?? this.artist,
    weightUp: weightUp ?? this.weightUp,
    weightDown: weightDown ?? this.weightDown,
    weightUpWash: weightUpWash ?? this.weightUpWash,
    weightDownWash: weightDownWash ?? this.weightDownWash,
    weightUpBorder: weightUpBorder ?? this.weightUpBorder,
    weightDownBorder: weightDownBorder ?? this.weightDownBorder,
    cursor: cursor ?? this.cursor,
  );

  /// 权重底色(强度曲线集中在此,正文色带与排序 chip 共用):
  /// 加权 (w−1)/1.5、降权 (1−w)/0.7 定强度,越偏离 1 越深;
  /// 浅色主题下限抬高(加权 .20 起、降权 .12 起),1.05 也看得出色相。
  Color? weightWash(double m) {
    if (m > 1.0001) {
      final i = ((m - 1) / 1.5).clamp(0.0, 1.0);
      return weightUpWash.withValues(alpha: .20 + i * .50);
    }
    if (m < 0.9999) {
      final i = ((1 - m) / 0.7).clamp(0.0, 1.0);
      return weightDownWash.withValues(alpha: .12 + i * .45);
    }
    return null;
  }

  @override
  EditorPalette lerp(EditorPalette? other, double t) {
    if (other == null) return this;
    return EditorPalette(
      character: Color.lerp(character, other.character, t)!,
      oc: Color.lerp(oc, other.oc, t)!,
      work: Color.lerp(work, other.work, t)!,
      artist: Color.lerp(artist, other.artist, t)!,
      weightUp: Color.lerp(weightUp, other.weightUp, t)!,
      weightDown: Color.lerp(weightDown, other.weightDown, t)!,
      weightUpWash: Color.lerp(weightUpWash, other.weightUpWash, t)!,
      weightDownWash: Color.lerp(weightDownWash, other.weightDownWash, t)!,
      weightUpBorder: Color.lerp(weightUpBorder, other.weightUpBorder, t)!,
      weightDownBorder: Color.lerp(
        weightDownBorder,
        other.weightDownBorder,
        t,
      )!,
      cursor: Color.lerp(cursor, other.cursor, t)!,
    );
  }
}

/// 编辑器主题 = 当前全局主题 + 「类型强调」扩展色(按亮暗选变体)。
ThemeData editorTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    extensions: [
      ...base.extensions.values,
      base.brightness == Brightness.dark
          ? EditorPalette.dark
          : EditorPalette.light,
    ],
  );
}

extension EditorPaletteX on BuildContext {
  EditorPalette get editor =>
      Theme.of(this).extension<EditorPalette>() ?? EditorPalette.light;

  /// 底部 dock(词条栏 / 批量面板 / 补全条)的底色。
  ///
  /// 浅色下走 surfaceBright(中性 tone 98,随种子取色):原先的 surfaceContainer
  /// (92)夹在正文底(96)和 chip 底(89)中间,三层挨着,面板和标签糊成一片;
  /// 抬到 98 既把面板从正文里拎出来,也让面板内那些灰按钮(86/89)自己站得住。
  /// 不用 surfaceContainerLowest:本主题把它定在 tone 100,而 100 是整条色阶上
  /// 唯一 chroma 为 0 的一档 —— 纯白不跟种子走,换主题色时只有这块不变。
  /// 深色下 surfaceBright 是 tone 24,正好撞上 chip 底,仍用容器色。
  /// 浮卡样式用卡片色。
  Color get editorDock {
    final t = Theme.of(this);
    if (skin.float) return t.colorScheme.surfaceContainerLow;
    return t.brightness == Brightness.dark
        ? t.colorScheme.surfaceContainer
        : t.colorScheme.surfaceBright;
  }

  /// dock 顶边的发丝线。98 只比正文底高 2 阶,光靠明暗托不住边界,
  /// 补一条线把面板的上沿说清楚。
  Color get editorDockLine =>
      Theme.of(this).colorScheme.outlineVariant.withValues(alpha: .5);
}

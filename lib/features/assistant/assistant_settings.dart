/// AI 助手的偏好(持久化)。
///
/// 几个开关都是**把默认的手动改成自动**,所以默认一律关着 —— 这套流程的地基是
/// 「AI 碰创作页、花点数出图,两件事都得用户按一下」;打开哪一项都是用户明知
/// 自己在放权,不能替他决定。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/app_stores.dart';
import '../generate/prompt_sections.dart' show SectionImport;
import '../../l10n/l10n.dart';
import 'domain/image_gen.dart' show isImageAspect, kImageSizes, kMaxImageCount;
import 'runtime/refusal.dart' show kRefusalKeywords;
import 'tools/tool_settings.dart' show migrateLegacyToolSettings;

const _key = 'assistant_settings';

/// 思考等级。当前模型调得了才随请求发出(见 `LlmCapabilities.thinking`)。
/// **声明顺序即滑杆顺序**(关 → 自动 → 由低到高),别乱动。
/// 落盘存的是 `name` 不是序号,所以将来插一档不会把老存档串位。
enum ThinkLevel {
  /// 明确关掉思考。会思考的模型上能省一大截时间和钱。
  off,

  /// 不发这个字段,用模型/服务方自己的默认。
  auto,

  low,
  medium,
  high,

  /// 比「高」再往上一档。三家里只有给 token 预算的那两家真有这一档,
  /// OpenAI 的 `reasoning_effort` 封顶就是 high。
  ultra,
}

String thinkLevelLabel(ThinkLevel l) => switch (l) {
  ThinkLevel.off => l10nNow.thinkOff,
  ThinkLevel.auto => l10nNow.thinkAuto,
  ThinkLevel.low => l10nNow.thinkLow,
  ThinkLevel.medium => l10nNow.thinkMedium,
  ThinkLevel.high => l10nNow.thinkHigh,
  ThinkLevel.ultra => l10nNow.thinkUltra,
};

String sectionImportLabel(SectionImport m) => switch (m) {
  SectionImport.main => l10nNow.importReplaceMain,
  SectionImport.newSection => l10nNow.importNewSection,
  SectionImport.clear => l10nNow.importClearSections,
};

/// 首次引导的版本。引导内容改版时加一:走过旧版的人进 AI 页会再看到一次。
const kAssistantIntroVersion = 2;

class AssistantSettings {
  const AssistantSettings({
    this.autoGenerate = false,
    this.inlineImage = false,
    this.autoImport = false,
    this.thinkLevel = ThinkLevel.auto,
    this.noDraw = false,
    this.introVersion = 0,
    this.fontSize = fontSizeDefault,
    this.historyTurns = historyTurnsDefault,
    this.stream = true,
    this.importTo = SectionImport.main,
    this.retries = retriesDefault,
    this.retryStripImage = false,
    this.rerolls = rerollsDefault,
    this.refusalKeywords = kRefusalKeywords,
    this.imageSize = '',
    this.imageAspect = '',
    this.imageCount = 1,
  });

  /// 失败重试 / 拒绝重试的默认次数与上限。0 = 关。
  static const retriesDefault = 3;
  static const rerollsDefault = 3;
  static const retriesMax = 5;

  /// 上下文轮数的默认值、可调范围与步长。
  ///
  /// 默认 20 与 bot 的历史窗口一样。上界 200 落在后端模型通道收的消息条数以内
  /// (`CHANNEL_MESSAGES_MAX`):走后端渠道时 token 是服务端付的,拉满一个请求光历史
  /// 就三万多。自定义接口那条也按同一个上限走。
  ///
  /// 十轮一档:两百轮的范围,一轮一轮地按太碎。
  static const historyTurnsDefault = 20;
  static const historyTurnsMin = 10;
  static const historyTurnsMax = 200;
  static const historyTurnsStep = 10;

  /// 消息字号的默认值、可调范围与步长。
  ///
  /// 默认比系统正文(14)大一号:回复动辄几段,14 号读着吃力。和编辑器的字号一样按
  /// 加减调、不给档位;上界再大,84% 宽的气泡一行就放不下几个词了。
  static const fontSizeDefault = 15.0;
  static const fontSizeMin = 12.0;
  static const fontSizeMax = 22.0;
  static const fontSizeStep = 1.0;

  /// AI 一给出提示词就直接出图,不必再按「生成」。
  ///
  /// 花的是真点数,所以默认关。开着的时候「生成」按钮照常在,重复按就是再出一张。
  final bool autoGenerate;

  /// 出的图显示在对话里,并且**不再把页面拽去图库**。
  ///
  /// 图照常入库 —— 这一项改的只是「看它要不要切页」,不是「存不存」。
  final bool inlineImage;

  /// AI 出了提示词就直接导入创作页,不必再按「导入」。
  ///
  /// **只管写,不管读**。原先这一项叫「总是读写创作页」,连读画布一起常开着,
  /// 撤掉是因为两个方向常开会互相咬:自动写进去的词下一轮又被自动读回来当基底,
  /// 用户改的和 AI 改的分不清谁覆盖谁。读画布现在**只有一次性**的那颗按钮
  /// (每发一次回到关),每一轮它看见什么都是当场按出来的。
  ///
  /// 默认关:拿助手当草稿本、不想动画布的人一旦被自动覆盖,丢的是他自己写的词。
  final bool autoImport;

  /// 思考等级。默认 [ThinkLevel.auto] = 不发这个字段。
  final ThinkLevel thinkLevel;

  /// 纯文本格式:AI 照常写提示词,提议只显示成纯文本给复制,不出结果卡、不导入、不出图
  /// (见 [AssistantMsg.promptAsText])。什么都不发给模型。
  ///
  /// 开着时「自动出图」「自动写入创作页」都不会发生 —— 纯文本那种提议没有可导入、
  /// 可生成的东西。
  final bool noDraw;

  /// 走完的是第几版首次引导(见 [kAssistantIntroVersion])。0 = 没走过。
  final int introVersion;

  /// 第一次打开 AI 页的引导走完了没有。没走完每次进 AI 页都会弹,
  /// 引导里定下的使用习惯要用户点过「开始使用」才算数。
  bool get introDone => introVersion >= kAssistantIntroVersion;

  /// 对话消息的正文字号:用户气泡、AI 回复、报错,见 [fontSizeMin] / [fontSizeMax]。
  /// 轨迹、结果条、按钮这些不跟着变 —— 它们是控件,放大了一行就挤不下。
  final double fontSize;

  /// 每次发送带上最近几轮对话(一轮从一句提问算起,更早的整轮不发)。
  ///
  /// 少了省 token,但更早说过的话模型就看不见了。提示词代码块本来就只带最近两份
  /// (见 `historyFenceIds`);画师串 / OC 的出处走账本(`latestResources`),
  /// 不占轮数,调小了也不会丢。
  final int historyTurns;

  /// 回复边写边显示。当前模型支持才生效(见 `LlmCapabilities.streaming`)。
  ///
  /// 这一项与上面那几个「放权」开关不同类,默认**开着**:它不替用户决定任何事,
  /// 只是把已经在发生的事显示出来。关掉 = 整段写完一次出,留给中转不认 `stream`
  /// 字段、或者就是不想看字一个个蹦的人。
  final bool stream;

  /// 导入 / 直接生成时提议写进主提示词的方式(见 [SectionImport])。
  final SectionImport importTo;

  /// 出错后自动重发几次。
  final int retries;

  /// 最后一次失败重试时去掉附图。
  final bool retryStripImage;

  /// 回复像拒绝时原地重掷几次。0 = 不判拒绝,回复照常显示。
  final int rerolls;

  /// 回复命中这些词就算拒绝。和默认一样时不落盘,默认词表更新能跟上。
  final List<String> refusalKeywords;

  /// 图像模型的分辨率档 / 比例(输入框上方那排);空 = 交给图像模型。
  /// 当前模型出不了的照存着,发的时候按「自动」走,换回能出的模型还是它。
  final String imageSize;
  final String imageAspect;

  /// 图像模型一轮出几张。
  final int imageCount;

  bool get defaultRefusalKeywords =>
      _sameList(refusalKeywords, kRefusalKeywords);

  AssistantSettings copyWith({
    bool? autoGenerate,
    bool? inlineImage,
    bool? autoImport,
    ThinkLevel? thinkLevel,
    bool? noDraw,
    int? introVersion,
    double? fontSize,
    int? historyTurns,
    bool? stream,
    SectionImport? importTo,
    int? retries,
    bool? retryStripImage,
    int? rerolls,
    List<String>? refusalKeywords,
    String? imageSize,
    String? imageAspect,
    int? imageCount,
  }) => AssistantSettings(
    autoGenerate: autoGenerate ?? this.autoGenerate,
    inlineImage: inlineImage ?? this.inlineImage,
    autoImport: autoImport ?? this.autoImport,
    thinkLevel: thinkLevel ?? this.thinkLevel,
    noDraw: noDraw ?? this.noDraw,
    introVersion: introVersion ?? this.introVersion,
    fontSize: fontSize ?? this.fontSize,
    historyTurns: historyTurns ?? this.historyTurns,
    stream: stream ?? this.stream,
    importTo: importTo ?? this.importTo,
    retries: retries ?? this.retries,
    retryStripImage: retryStripImage ?? this.retryStripImage,
    rerolls: rerolls ?? this.rerolls,
    refusalKeywords: refusalKeywords ?? this.refusalKeywords,
    imageSize: imageSize ?? this.imageSize,
    imageAspect: imageAspect ?? this.imageAspect,
    imageCount: imageCount ?? this.imageCount,
  );

  Map<String, dynamic> toJson() => {
    'autoGenerate': autoGenerate,
    'inlineImage': inlineImage,
    'autoImport': autoImport,
    'thinkLevel': thinkLevel.name,
    'noDraw': noDraw,
    'introVersion': introVersion,
    'fontSize': fontSize,
    'historyTurns': historyTurns,
    'stream': stream,
    'importTo': importTo.name,
    'retries': retries,
    'retryStripImage': retryStripImage,
    'rerolls': rerolls,
    if (!defaultRefusalKeywords) 'refusalKeywords': refusalKeywords,
    if (imageSize.isNotEmpty) 'imageSize': imageSize,
    if (imageAspect.isNotEmpty) 'imageAspect': imageAspect,
    if (imageCount != 1) 'imageCount': imageCount,
  };

  factory AssistantSettings.fromJson(Map<String, dynamic> j) =>
      AssistantSettings(
        autoGenerate: j['autoGenerate'] == true,
        inlineImage: j['inlineImage'] == true,
        // alwaysCanvas 是它的旧名(那会儿还连着读画布)。老存档里开着的,
        // 保留它「自动导入」那一半 —— 读那一半已经不存在了。
        autoImport: j['autoImport'] == true || j['alwaysCanvas'] == true,
        thinkLevel:
            ThinkLevel.values.asNameMap()[j['thinkLevel']] ?? ThinkLevel.auto,
        noDraw: j['noDraw'] == true,
        // 缺键 = 老存档,按开算:新行为更好,不必等用户自己去翻设置
        stream: j['stream'] != false,
        importTo:
            SectionImport.values.asNameMap()[j['importTo']] ??
            SectionImport.main,
        introVersion: switch (j['introVersion']) {
          final num v => v.toInt(),
          _ => 0,
        },
        // 越界(以后收窄了范围,或者脏数据)夹回来,不把调过的偏好整个丢回默认
        fontSize: switch (j['fontSize']) {
          final num v when !v.isNaN =>
            v.toDouble().clamp(fontSizeMin, fontSizeMax).toDouble(),
          _ => fontSizeDefault,
        },
        // 以前一轮一轮调出来的(比如 35)就近落到档上,不然按一下加减会跳两档
        historyTurns: switch (j['historyTurns']) {
          final num v when v.isFinite =>
            ((v / historyTurnsStep).round() * historyTurnsStep).clamp(
              historyTurnsMin,
              historyTurnsMax,
            ),
          _ => historyTurnsDefault,
        },
        retries: _count(j['retries'], retriesDefault),
        retryStripImage: j['retryStripImage'] == true,
        rerolls: _count(j['rerolls'], rerollsDefault),
        refusalKeywords: switch (j['refusalKeywords']) {
          final List<dynamic> l => [
            for (final k in l)
              if (k is String && k.trim().isNotEmpty) k.trim(),
          ],
          _ => kRefusalKeywords,
        },
        imageSize: switch (j['imageSize']) {
          final String s when kImageSizes.contains(s) => s,
          _ => '',
        },
        imageAspect: switch (j['imageAspect']) {
          final String s when isImageAspect(s) => s,
          _ => '',
        },
        imageCount: switch (j['imageCount']) {
          final int n when n >= 1 && n <= kMaxImageCount => n,
          _ => 1,
        },
      );

  static int _count(Object? v, int fallback) => switch (v) {
    final num n when n.isFinite => n.round().clamp(0, retriesMax),
    _ => fallback,
  };
}

bool _sameList(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final assistantSettingsProvider =
    AsyncNotifierProvider<AssistantSettingsNotifier, AssistantSettings>(
      AssistantSettingsNotifier.new,
    );

class AssistantSettingsNotifier extends AsyncNotifier<AssistantSettings> {
  @override
  Future<AssistantSettings> build() async {
    try {
      final prefs = ref.read(prefsStoreProvider);
      // 先把旧字段迁走:这份设置一改就整份重写,旧字段就没了
      await migrateLegacyToolSettings(prefs);
      final raw = await prefs.read(key: _key);
      if (raw == null || raw.isEmpty) return const AssistantSettings();
      return AssistantSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AssistantSettings();
    }
  }

  /// 先改状态(立即生效),再尽力持久化。
  Future<void> patch(
    AssistantSettings Function(AssistantSettings) change,
  ) async {
    final next = change(state.value ?? const AssistantSettings());
    state = AsyncData(next);
    try {
      await ref
          .read(prefsStoreProvider)
          .write(key: _key, value: jsonEncode(next.toJson()));
    } catch (_) {}
  }
}

/// 同步读一份。三项都在「发消息 / 出词回来」这种时刻用,那时候偏好早读完了;
/// 万一还没到货就按全关走 —— 全关 = 现在这套手动流程,不会替用户做任何事。
AssistantSettings assistantSettingsOf(Ref ref) =>
    ref.read(assistantSettingsProvider).value ?? const AssistantSettings();

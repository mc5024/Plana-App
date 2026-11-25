import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @uiLanguage.
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get uiLanguage;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @generate.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get generate;

  /// No description provided for @model.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get model;

  /// No description provided for @prompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get prompt;

  /// No description provided for @positivePrompt.
  ///
  /// In zh, this message translates to:
  /// **'正向提示词'**
  String get positivePrompt;

  /// No description provided for @negativePrompt.
  ///
  /// In zh, this message translates to:
  /// **'负向提示词'**
  String get negativePrompt;

  /// No description provided for @characterPrompts.
  ///
  /// In zh, this message translates to:
  /// **'角色提示词'**
  String get characterPrompts;

  /// No description provided for @importImage.
  ///
  /// In zh, this message translates to:
  /// **'导入图片'**
  String get importImage;

  /// No description provided for @advanced.
  ///
  /// In zh, this message translates to:
  /// **'高级'**
  String get advanced;

  /// No description provided for @advancedSettings.
  ///
  /// In zh, this message translates to:
  /// **'高级设置'**
  String get advancedSettings;

  /// No description provided for @resetSettings.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get resetSettings;

  /// No description provided for @resolution.
  ///
  /// In zh, this message translates to:
  /// **'分辨率'**
  String get resolution;

  /// No description provided for @size.
  ///
  /// In zh, this message translates to:
  /// **'尺寸'**
  String get size;

  /// No description provided for @imageCount.
  ///
  /// In zh, this message translates to:
  /// **'张数'**
  String get imageCount;

  /// No description provided for @steps.
  ///
  /// In zh, this message translates to:
  /// **'步数'**
  String get steps;

  /// No description provided for @seedRandom.
  ///
  /// In zh, this message translates to:
  /// **'每次随机'**
  String get seedRandom;

  /// No description provided for @paramSteps.
  ///
  /// In zh, this message translates to:
  /// **'步数 Steps'**
  String get paramSteps;

  /// No description provided for @paramCfg.
  ///
  /// In zh, this message translates to:
  /// **'提示词引导 CFG'**
  String get paramCfg;

  /// No description provided for @paramSampler.
  ///
  /// In zh, this message translates to:
  /// **'采样器 Sampler'**
  String get paramSampler;

  /// No description provided for @paramScheduler.
  ///
  /// In zh, this message translates to:
  /// **'调度器 Scheduler'**
  String get paramScheduler;

  /// No description provided for @paramNoiseSchedule.
  ///
  /// In zh, this message translates to:
  /// **'噪声调度 Noise Schedule'**
  String get paramNoiseSchedule;

  /// No description provided for @paramSeed.
  ///
  /// In zh, this message translates to:
  /// **'种子 Seed'**
  String get paramSeed;

  /// No description provided for @cfgRescale.
  ///
  /// In zh, this message translates to:
  /// **'CFG Rescale'**
  String get cfgRescale;

  /// No description provided for @varietyPlus.
  ///
  /// In zh, this message translates to:
  /// **'Variety+'**
  String get varietyPlus;

  /// No description provided for @sizeNormal.
  ///
  /// In zh, this message translates to:
  /// **'小图'**
  String get sizeNormal;

  /// No description provided for @sizeLarge.
  ///
  /// In zh, this message translates to:
  /// **'大图'**
  String get sizeLarge;

  /// No description provided for @sizeWallpaper.
  ///
  /// In zh, this message translates to:
  /// **'壁纸'**
  String get sizeWallpaper;

  /// No description provided for @sizeCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get sizeCustom;

  /// No description provided for @sizePortrait.
  ///
  /// In zh, this message translates to:
  /// **'竖图'**
  String get sizePortrait;

  /// No description provided for @sizeLandscape.
  ///
  /// In zh, this message translates to:
  /// **'横图'**
  String get sizeLandscape;

  /// No description provided for @sizeSquare.
  ///
  /// In zh, this message translates to:
  /// **'方形'**
  String get sizeSquare;

  /// No description provided for @sizePortraitScreen.
  ///
  /// In zh, this message translates to:
  /// **'竖屏'**
  String get sizePortraitScreen;

  /// No description provided for @sizeLandscapeScreen.
  ///
  /// In zh, this message translates to:
  /// **'横屏'**
  String get sizeLandscapeScreen;

  /// No description provided for @width.
  ///
  /// In zh, this message translates to:
  /// **'宽度'**
  String get width;

  /// No description provided for @height.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get height;

  /// No description provided for @swapDimensions.
  ///
  /// In zh, this message translates to:
  /// **'交换宽高'**
  String get swapDimensions;

  /// No description provided for @img2img.
  ///
  /// In zh, this message translates to:
  /// **'图生图'**
  String get img2img;

  /// No description provided for @paramStrength.
  ///
  /// In zh, this message translates to:
  /// **'强度 Strength'**
  String get paramStrength;

  /// No description provided for @paramNoise.
  ///
  /// In zh, this message translates to:
  /// **'噪声 Noise'**
  String get paramNoise;

  /// No description provided for @strength.
  ///
  /// In zh, this message translates to:
  /// **'强度'**
  String get strength;

  /// No description provided for @inpaint.
  ///
  /// In zh, this message translates to:
  /// **'重绘'**
  String get inpaint;

  /// No description provided for @inpaintStrength.
  ///
  /// In zh, this message translates to:
  /// **'重绘强度'**
  String get inpaintStrength;

  /// No description provided for @inpaintPaint.
  ///
  /// In zh, this message translates to:
  /// **'涂抹'**
  String get inpaintPaint;

  /// No description provided for @removeMask.
  ///
  /// In zh, this message translates to:
  /// **'移除遮罩'**
  String get removeMask;

  /// No description provided for @draw.
  ///
  /// In zh, this message translates to:
  /// **'画笔'**
  String get draw;

  /// No description provided for @erase.
  ///
  /// In zh, this message translates to:
  /// **'橡皮'**
  String get erase;

  /// No description provided for @penSize.
  ///
  /// In zh, this message translates to:
  /// **'笔刷大小'**
  String get penSize;

  /// No description provided for @penSizeShort.
  ///
  /// In zh, this message translates to:
  /// **'笔刷'**
  String get penSizeShort;

  /// No description provided for @holdToCompare.
  ///
  /// In zh, this message translates to:
  /// **'按住对比'**
  String get holdToCompare;

  /// No description provided for @presetHeavy.
  ///
  /// In zh, this message translates to:
  /// **'Heavy (重度)'**
  String get presetHeavy;

  /// No description provided for @presetLight.
  ///
  /// In zh, this message translates to:
  /// **'Light (轻度)'**
  String get presetLight;

  /// No description provided for @presetStandard.
  ///
  /// In zh, this message translates to:
  /// **'Standard (标准)'**
  String get presetStandard;

  /// No description provided for @presetNone.
  ///
  /// In zh, this message translates to:
  /// **'None (无)'**
  String get presetNone;

  /// No description provided for @vibeTransfer.
  ///
  /// In zh, this message translates to:
  /// **'Vibe Transfer'**
  String get vibeTransfer;

  /// No description provided for @referenceStrength.
  ///
  /// In zh, this message translates to:
  /// **'Strength 参考强度'**
  String get referenceStrength;

  /// No description provided for @infoExtracted.
  ///
  /// In zh, this message translates to:
  /// **'Info Extracted 信息提取'**
  String get infoExtracted;

  /// No description provided for @normalizeStrength.
  ///
  /// In zh, this message translates to:
  /// **'均衡强度'**
  String get normalizeStrength;

  /// No description provided for @preciseReference.
  ///
  /// In zh, this message translates to:
  /// **'角色参考'**
  String get preciseReference;

  /// No description provided for @fidelity.
  ///
  /// In zh, this message translates to:
  /// **'Fidelity 保真度'**
  String get fidelity;

  /// No description provided for @refCharacter.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get refCharacter;

  /// No description provided for @refStyle.
  ///
  /// In zh, this message translates to:
  /// **'风格'**
  String get refStyle;

  /// No description provided for @refCharacterStyle.
  ///
  /// In zh, this message translates to:
  /// **'角色&风格'**
  String get refCharacterStyle;

  /// No description provided for @refOutfit.
  ///
  /// In zh, this message translates to:
  /// **'服装'**
  String get refOutfit;

  /// No description provided for @preferSameOutfit.
  ///
  /// In zh, this message translates to:
  /// **'优先相同服装'**
  String get preferSameOutfit;

  /// No description provided for @characters.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get characters;

  /// No description provided for @addCharacter.
  ///
  /// In zh, this message translates to:
  /// **'添加角色'**
  String get addCharacter;

  /// No description provided for @position.
  ///
  /// In zh, this message translates to:
  /// **'设置角色位置'**
  String get position;

  /// No description provided for @aiChoice.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get aiChoice;

  /// No description provided for @aiChoicePosition.
  ///
  /// In zh, this message translates to:
  /// **'自动定位'**
  String get aiChoicePosition;

  /// No description provided for @aiChoiceAll.
  ///
  /// In zh, this message translates to:
  /// **'全部自动 (AUTO)'**
  String get aiChoiceAll;

  /// No description provided for @savePosition.
  ///
  /// In zh, this message translates to:
  /// **'确认保存'**
  String get savePosition;

  /// No description provided for @importSteps.
  ///
  /// In zh, this message translates to:
  /// **'Steps'**
  String get importSteps;

  /// No description provided for @importCfg.
  ///
  /// In zh, this message translates to:
  /// **'CFG'**
  String get importCfg;

  /// No description provided for @importSampler.
  ///
  /// In zh, this message translates to:
  /// **'Sampler'**
  String get importSampler;

  /// No description provided for @importScheduler.
  ///
  /// In zh, this message translates to:
  /// **'Scheduler'**
  String get importScheduler;

  /// No description provided for @importSeed.
  ///
  /// In zh, this message translates to:
  /// **'Seed'**
  String get importSeed;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @enable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get enable;

  /// No description provided for @start.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get start;

  /// No description provided for @free.
  ///
  /// In zh, this message translates to:
  /// **'免费'**
  String get free;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中'**
  String get loading;

  /// No description provided for @notFetched.
  ///
  /// In zh, this message translates to:
  /// **'未获取'**
  String get notFetched;

  /// No description provided for @commaSep.
  ///
  /// In zh, this message translates to:
  /// **'，'**
  String get commaSep;

  /// No description provided for @tapToView.
  ///
  /// In zh, this message translates to:
  /// **'点按查看'**
  String get tapToView;

  /// No description provided for @tapToReturn.
  ///
  /// In zh, this message translates to:
  /// **'点按回到应用'**
  String get tapToReturn;

  /// No description provided for @shortDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get shortDone;

  /// No description provided for @shortStopped.
  ///
  /// In zh, this message translates to:
  /// **'中止'**
  String get shortStopped;

  /// No description provided for @shortPaused.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get shortPaused;

  /// No description provided for @shortFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get shortFailed;

  /// No description provided for @shortPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备'**
  String get shortPreparing;

  /// No description provided for @lpPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备生成…'**
  String get lpPreparing;

  /// No description provided for @lpGenDone.
  ///
  /// In zh, this message translates to:
  /// **'生成完成'**
  String get lpGenDone;

  /// No description provided for @lpAssistantThinking.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手思考中…'**
  String get lpAssistantThinking;

  /// No description provided for @lpAssistantThinkingShort.
  ///
  /// In zh, this message translates to:
  /// **'思考中'**
  String get lpAssistantThinkingShort;

  /// No description provided for @lpAssistantReplied.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手已回复'**
  String get lpAssistantReplied;

  /// No description provided for @lpAssistantFailed.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手回复失败'**
  String get lpAssistantFailed;

  /// No description provided for @loopGenerate.
  ///
  /// In zh, this message translates to:
  /// **'循环生成'**
  String get loopGenerate;

  /// No description provided for @vibesDisabledNoEncoding.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个 Vibe 缺当前模型编码,已停用'**
  String vibesDisabledNoEncoding(int n);

  /// No description provided for @cancelTrackedJob.
  ///
  /// In zh, this message translates to:
  /// **'取消当前跟随的这条({count} 条在跑)'**
  String cancelTrackedJob(int count);

  /// No description provided for @cancelGeneration.
  ///
  /// In zh, this message translates to:
  /// **'取消生成'**
  String get cancelGeneration;

  /// No description provided for @stepsFixed.
  ///
  /// In zh, this message translates to:
  /// **'{model} 步数固定为 {steps}'**
  String stepsFixed(String model, int steps);

  /// No description provided for @samplerFixed.
  ///
  /// In zh, this message translates to:
  /// **'{model} 采样器固定为 {sampler}'**
  String samplerFixed(String model, String sampler);

  /// No description provided for @noiseScheduleFixed.
  ///
  /// In zh, this message translates to:
  /// **'{model} 噪声调度固定为 karras'**
  String noiseScheduleFixed(String model);

  /// No description provided for @paramUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'{model} 不支持「{param}」'**
  String paramUnsupported(String model, String param);

  /// No description provided for @batchLockedHires.
  ///
  /// In zh, this message translates to:
  /// **'重绘放大开着时只能出 1 张:二段采样要按放大后的尺寸再跑一遍,显存吃不下一批。'**
  String get batchLockedHires;

  /// No description provided for @refDisable.
  ///
  /// In zh, this message translates to:
  /// **'停用此参考图'**
  String get refDisable;

  /// No description provided for @refIndex.
  ///
  /// In zh, this message translates to:
  /// **'参考图 {index}'**
  String refIndex(int index);

  /// No description provided for @switchModelTooltip.
  ///
  /// In zh, this message translates to:
  /// **'切换模型：{model}'**
  String switchModelTooltip(String model);

  /// No description provided for @switchModelSemantics.
  ///
  /// In zh, this message translates to:
  /// **'切换模型，当前 {model}'**
  String switchModelSemantics(String model);

  /// No description provided for @descNai5Full.
  ///
  /// In zh, this message translates to:
  /// **'最新旗舰模型 · 1471 token · NSFW'**
  String get descNai5Full;

  /// No description provided for @descNai5Medium.
  ///
  /// In zh, this message translates to:
  /// **'最新旗舰 Medium 档 · 节约 40% 额度 · NSFW'**
  String get descNai5Medium;

  /// No description provided for @descNai5Curated.
  ///
  /// In zh, this message translates to:
  /// **'最新精选版 · 703 token · SFW'**
  String get descNai5Curated;

  /// No description provided for @descNai45Full.
  ///
  /// In zh, this message translates to:
  /// **'V4.5 旧模型 · NSFW'**
  String get descNai45Full;

  /// No description provided for @descNai45Curated.
  ///
  /// In zh, this message translates to:
  /// **'V4.5 旧模型精选版 · SFW'**
  String get descNai45Curated;

  /// No description provided for @descNai4Full.
  ///
  /// In zh, this message translates to:
  /// **'V4 旧模型 · NSFW'**
  String get descNai4Full;

  /// No description provided for @descNai4Curated.
  ///
  /// In zh, this message translates to:
  /// **'V4 旧模型精选版 · SFW'**
  String get descNai4Curated;

  /// No description provided for @positionHint.
  ///
  /// In zh, this message translates to:
  /// **'{w}×{h} · 点按或拖动放置角色'**
  String positionHint(int w, int h);

  /// No description provided for @sizeMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get sizeMine;

  /// No description provided for @sizePhone.
  ///
  /// In zh, this message translates to:
  /// **'手机'**
  String get sizePhone;

  /// No description provided for @savePreset.
  ///
  /// In zh, this message translates to:
  /// **'存为预设'**
  String get savePreset;

  /// No description provided for @overPixelLimit.
  ///
  /// In zh, this message translates to:
  /// **'超出像素上限'**
  String get overPixelLimit;

  /// No description provided for @confirmSize.
  ///
  /// In zh, this message translates to:
  /// **'确认 · {w}×{h}'**
  String confirmSize(int w, int h);

  /// No description provided for @tierCostsAnlas.
  ///
  /// In zh, this message translates to:
  /// **'消耗点数'**
  String get tierCostsAnlas;

  /// No description provided for @tierOverLimit.
  ///
  /// In zh, this message translates to:
  /// **'超出上限'**
  String get tierOverLimit;

  /// No description provided for @shrinkToLimit.
  ///
  /// In zh, this message translates to:
  /// **'缩到上限'**
  String get shrinkToLimit;

  /// No description provided for @shrinkToFree.
  ///
  /// In zh, this message translates to:
  /// **'缩到免费'**
  String get shrinkToFree;

  /// No description provided for @promptPresets.
  ///
  /// In zh, this message translates to:
  /// **'提示词预设'**
  String get promptPresets;

  /// No description provided for @promptPresetsHelp.
  ///
  /// In zh, this message translates to:
  /// **'生成时自动拼进正/负提示词,不占用输入框。V5 与 4.5 各有一套档。'**
  String get promptPresetsHelp;

  /// No description provided for @sectionSampling.
  ///
  /// In zh, this message translates to:
  /// **'采样'**
  String get sectionSampling;

  /// No description provided for @sectionAdjust.
  ///
  /// In zh, this message translates to:
  /// **'修正'**
  String get sectionAdjust;

  /// No description provided for @freeUpTo28.
  ///
  /// In zh, this message translates to:
  /// **'≤28 免费'**
  String get freeUpTo28;

  /// No description provided for @seedRandomTooltip.
  ///
  /// In zh, this message translates to:
  /// **'每次随机 · 点击手填种子'**
  String get seedRandomTooltip;

  /// No description provided for @seedManualTooltip.
  ///
  /// In zh, this message translates to:
  /// **'手填种子 · 点击改为每次随机'**
  String get seedManualTooltip;

  /// No description provided for @managePresets.
  ///
  /// In zh, this message translates to:
  /// **'管理预设'**
  String get managePresets;

  /// No description provided for @loopIntro.
  ///
  /// In zh, this message translates to:
  /// **'按当前参数一张接一张地出图,种子留空就每张随机。中途出错会自动停下,也可以退到后台,进度在通知栏继续。'**
  String get loopIntro;

  /// No description provided for @estimatedCost.
  ///
  /// In zh, this message translates to:
  /// **'预估消耗'**
  String get estimatedCost;

  /// No description provided for @costPerImageTotal.
  ///
  /// In zh, this message translates to:
  /// **'{cost}/张 · 共 {total} Anlas'**
  String costPerImageTotal(int cost, int total);

  /// No description provided for @costPerImage.
  ///
  /// In zh, this message translates to:
  /// **'{cost} Anlas/张'**
  String costPerImage(int cost);

  /// No description provided for @costEncodeExtra.
  ///
  /// In zh, this message translates to:
  /// **' + 编码 {fee}'**
  String costEncodeExtra(int fee);

  /// No description provided for @infiniteLoopTitle.
  ///
  /// In zh, this message translates to:
  /// **'无限循环会持续扣点'**
  String get infiniteLoopTitle;

  /// No description provided for @infiniteLoopBody.
  ///
  /// In zh, this message translates to:
  /// **'当前参数每张约 {cost} Anlas,张数为无限——不点停止就会一直生成,退到后台也会继续。确定开始?'**
  String infiniteLoopBody(int cost);

  /// No description provided for @infiniteLoopBodyFee.
  ///
  /// In zh, this message translates to:
  /// **'当前参数每张约 {cost} Anlas(另首张含 {fee} 点 Vibe 编码费),张数为无限——不点停止就会一直生成,退到后台也会继续。确定开始?'**
  String infiniteLoopBodyFee(int cost, int fee);

  /// No description provided for @generationBusy.
  ///
  /// In zh, this message translates to:
  /// **'当前有生成进行中'**
  String get generationBusy;

  /// No description provided for @startLoop.
  ///
  /// In zh, this message translates to:
  /// **'开始循环 {count}'**
  String startLoop(String count);

  /// No description provided for @loopRunning.
  ///
  /// In zh, this message translates to:
  /// **'循环生成中'**
  String get loopRunning;

  /// No description provided for @loopImageOf.
  ///
  /// In zh, this message translates to:
  /// **'第 {n} / {total} 张'**
  String loopImageOf(int n, int total);

  /// No description provided for @loopImage.
  ///
  /// In zh, this message translates to:
  /// **'第 {n} 张'**
  String loopImage(int n);

  /// No description provided for @loopStopping.
  ///
  /// In zh, this message translates to:
  /// **'本张后停止'**
  String get loopStopping;

  /// No description provided for @loopStopAfterThis.
  ///
  /// In zh, this message translates to:
  /// **'停止(本张跑完后)'**
  String get loopStopAfterThis;

  /// No description provided for @loopDone.
  ///
  /// In zh, this message translates to:
  /// **'循环完成'**
  String get loopDone;

  /// No description provided for @loopAborted.
  ///
  /// In zh, this message translates to:
  /// **'循环中止'**
  String get loopAborted;

  /// No description provided for @generationFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败'**
  String get generationFailed;

  /// No description provided for @loopDoneText.
  ///
  /// In zh, this message translates to:
  /// **'已出 {n} 张 · 点按查看'**
  String loopDoneText(int n);

  /// No description provided for @queueDone.
  ///
  /// In zh, this message translates to:
  /// **'队列完成'**
  String get queueDone;

  /// No description provided for @queuePaused.
  ///
  /// In zh, this message translates to:
  /// **'队列暂停'**
  String get queuePaused;

  /// No description provided for @queueDoneText.
  ///
  /// In zh, this message translates to:
  /// **'共 {n} 张 · 点按查看'**
  String queueDoneText(int n);

  /// No description provided for @queueLeftText.
  ///
  /// In zh, this message translates to:
  /// **'剩 {n} 项'**
  String queueLeftText(int n);

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @rename.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get rename;

  /// No description provided for @disable.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get disable;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @view.
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get view;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @name.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get name;

  /// No description provided for @on.
  ///
  /// In zh, this message translates to:
  /// **'开'**
  String get on;

  /// No description provided for @off.
  ///
  /// In zh, this message translates to:
  /// **'关'**
  String get off;

  /// No description provided for @untitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名'**
  String get untitled;

  /// No description provided for @sectionMain.
  ///
  /// In zh, this message translates to:
  /// **'主体'**
  String get sectionMain;

  /// No description provided for @sectionStyle.
  ///
  /// In zh, this message translates to:
  /// **'画风'**
  String get sectionStyle;

  /// No description provided for @sectionCodex.
  ///
  /// In zh, this message translates to:
  /// **'法典'**
  String get sectionCodex;

  /// No description provided for @sectionN.
  ///
  /// In zh, this message translates to:
  /// **'分区 {n}'**
  String sectionN(int n);

  /// No description provided for @clearPositivePrompt.
  ///
  /// In zh, this message translates to:
  /// **'清空正向提示词'**
  String get clearPositivePrompt;

  /// No description provided for @clearPromptAndSections.
  ///
  /// In zh, this message translates to:
  /// **'清空提示词和分区'**
  String get clearPromptAndSections;

  /// No description provided for @inspirationLibrary.
  ///
  /// In zh, this message translates to:
  /// **'灵感库'**
  String get inspirationLibrary;

  /// No description provided for @addSection.
  ///
  /// In zh, this message translates to:
  /// **'添加分区'**
  String get addSection;

  /// No description provided for @tapToEditPositive.
  ///
  /// In zh, this message translates to:
  /// **'点击编辑正面提示词…'**
  String get tapToEditPositive;

  /// No description provided for @tapToEditNegative.
  ///
  /// In zh, this message translates to:
  /// **'点击编辑负面提示词…'**
  String get tapToEditNegative;

  /// No description provided for @tapToEdit.
  ///
  /// In zh, this message translates to:
  /// **'点击编辑…'**
  String get tapToEdit;

  /// No description provided for @exitMultiSelect.
  ///
  /// In zh, this message translates to:
  /// **'退出多选'**
  String get exitMultiSelect;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n}'**
  String selectedCount(int n);

  /// No description provided for @saveToInspiration.
  ///
  /// In zh, this message translates to:
  /// **'存到灵感库'**
  String get saveToInspiration;

  /// No description provided for @merge.
  ///
  /// In zh, this message translates to:
  /// **'合并'**
  String get merge;

  /// No description provided for @sectionsDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {n} 个分区'**
  String sectionsDeleted(int n);

  /// No description provided for @mergedInto.
  ///
  /// In zh, this message translates to:
  /// **'已合并到「{name}」'**
  String mergedInto(String name);

  /// No description provided for @inspirationAllExist.
  ///
  /// In zh, this message translates to:
  /// **'灵感库里都已有了'**
  String get inspirationAllExist;

  /// No description provided for @inspirationSavedSkipped.
  ///
  /// In zh, this message translates to:
  /// **'已存 {saved} 条到灵感库,{skipped} 条已有'**
  String inspirationSavedSkipped(int saved, int skipped);

  /// No description provided for @inspirationSaved.
  ///
  /// In zh, this message translates to:
  /// **'已存 {saved} 条到灵感库'**
  String inspirationSaved(int saved);

  /// No description provided for @inspirationAlreadyHas.
  ///
  /// In zh, this message translates to:
  /// **'灵感库里已有「{name}」'**
  String inspirationAlreadyHas(String name);

  /// No description provided for @clearedPositivePrompt.
  ///
  /// In zh, this message translates to:
  /// **'已清空正向提示词'**
  String get clearedPositivePrompt;

  /// No description provided for @clearedPromptAndSections.
  ///
  /// In zh, this message translates to:
  /// **'已清空提示词和分区'**
  String get clearedPromptAndSections;

  /// No description provided for @charactersFull.
  ///
  /// In zh, this message translates to:
  /// **'角色已满 {cap} 个,{dropped} 个没加进去'**
  String charactersFull(int cap, int dropped);

  /// No description provided for @disableKeepConfig.
  ///
  /// In zh, this message translates to:
  /// **'停用(保留配置)'**
  String get disableKeepConfig;

  /// No description provided for @deleteSection.
  ///
  /// In zh, this message translates to:
  /// **'删除分区'**
  String get deleteSection;

  /// No description provided for @deletedNamed.
  ///
  /// In zh, this message translates to:
  /// **'已删除「{name}」'**
  String deletedNamed(String name);

  /// No description provided for @deletePreset.
  ///
  /// In zh, this message translates to:
  /// **'删除预设'**
  String get deletePreset;

  /// No description provided for @deletePresetBody.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」将被删除;若正在激活,回落到「无」。'**
  String deletePresetBody(String name);

  /// No description provided for @newPreset.
  ///
  /// In zh, this message translates to:
  /// **'新建预设'**
  String get newPreset;

  /// No description provided for @viewPreset.
  ///
  /// In zh, this message translates to:
  /// **'查看预设'**
  String get viewPreset;

  /// No description provided for @editPreset.
  ///
  /// In zh, this message translates to:
  /// **'编辑预设'**
  String get editPreset;

  /// No description provided for @presetPageIntro.
  ///
  /// In zh, this message translates to:
  /// **'激活的预设在生成时自动作为前缀拼进正/负提示词,不占用输入框。默认预设不可修改;右上角可新建自定义预设。'**
  String get presetPageIntro;

  /// No description provided for @presetGroupLegacy.
  ///
  /// In zh, this message translates to:
  /// **'4.5 及更早'**
  String get presetGroupLegacy;

  /// No description provided for @presetGroupDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get presetGroupDefault;

  /// No description provided for @noPrefix.
  ///
  /// In zh, this message translates to:
  /// **'无前缀'**
  String get noPrefix;

  /// No description provided for @placement.
  ///
  /// In zh, this message translates to:
  /// **'拼接位置'**
  String get placement;

  /// No description provided for @placementStart.
  ///
  /// In zh, this message translates to:
  /// **'开头'**
  String get placementStart;

  /// No description provided for @placementEnd.
  ///
  /// In zh, this message translates to:
  /// **'末尾'**
  String get placementEnd;

  /// No description provided for @emptyHint.
  ///
  /// In zh, this message translates to:
  /// **'空…'**
  String get emptyHint;

  /// No description provided for @presetName.
  ///
  /// In zh, this message translates to:
  /// **'预设名称'**
  String get presetName;

  /// No description provided for @defaultPresetReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'默认预设不可修改,可新建自定义预设替代。'**
  String get defaultPresetReadOnly;

  /// No description provided for @positivePrefix.
  ///
  /// In zh, this message translates to:
  /// **'正向前缀'**
  String get positivePrefix;

  /// No description provided for @positiveSuffix.
  ///
  /// In zh, this message translates to:
  /// **'正向后缀'**
  String get positiveSuffix;

  /// No description provided for @negativePrefix.
  ///
  /// In zh, this message translates to:
  /// **'负向前缀'**
  String get negativePrefix;

  /// No description provided for @stepsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 步'**
  String stepsN(int n);

  /// No description provided for @sampler.
  ///
  /// In zh, this message translates to:
  /// **'采样器'**
  String get sampler;

  /// No description provided for @noiseSchedule.
  ///
  /// In zh, this message translates to:
  /// **'噪声调度'**
  String get noiseSchedule;

  /// No description provided for @scheduler.
  ///
  /// In zh, this message translates to:
  /// **'调度器'**
  String get scheduler;

  /// No description provided for @applyRecipeTitle.
  ///
  /// In zh, this message translates to:
  /// **'套用「{name}」的推荐参数?'**
  String applyRecipeTitle(String name);

  /// No description provided for @apply.
  ///
  /// In zh, this message translates to:
  /// **'套用'**
  String get apply;

  /// No description provided for @dontApply.
  ///
  /// In zh, this message translates to:
  /// **'不用'**
  String get dontApply;

  /// No description provided for @recipeApplied.
  ///
  /// In zh, this message translates to:
  /// **'已套用「{name}」的推荐参数'**
  String recipeApplied(String name);

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @refDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'参考图'**
  String get refDefaultName;

  /// No description provided for @refMutexVibePaused.
  ///
  /// In zh, this message translates to:
  /// **'与 Vibe 互斥,已暂停 Vibe 参考'**
  String get refMutexVibePaused;

  /// No description provided for @refMutexCharRefPaused.
  ///
  /// In zh, this message translates to:
  /// **'与角色参考互斥,已暂停角色参考'**
  String get refMutexCharRefPaused;

  /// No description provided for @refLibrary.
  ///
  /// In zh, this message translates to:
  /// **'参考图库'**
  String get refLibrary;

  /// No description provided for @importCharRef.
  ///
  /// In zh, this message translates to:
  /// **'导入角色参考图'**
  String get importCharRef;

  /// No description provided for @charRefOnly45.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持角色参考，生成时不会发送。'**
  String get charRefOnly45;

  /// No description provided for @charRefOutfitSkipped.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持「服装」参考，已选的服装参考图在生成时将被跳过。'**
  String get charRefOutfitSkipped;

  /// No description provided for @charRefIgnoredInpaint.
  ///
  /// In zh, this message translates to:
  /// **'当前模型重绘时不支持角色参考'**
  String get charRefIgnoredInpaint;

  /// No description provided for @charRefMaxExceeded.
  ///
  /// In zh, this message translates to:
  /// **'最多同时生效 {max} 张角色参考图，超出的将在生成时被跳过。'**
  String charRefMaxExceeded(int max);

  /// No description provided for @filesImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个文件无法导入'**
  String filesImportFailed(int n);

  /// No description provided for @nothingToImport.
  ///
  /// In zh, this message translates to:
  /// **'没有可导入的内容'**
  String get nothingToImport;

  /// No description provided for @inactiveWhenInpainting.
  ///
  /// In zh, this message translates to:
  /// **'重绘时不生效'**
  String get inactiveWhenInpainting;

  /// No description provided for @vibeLibrary.
  ///
  /// In zh, this message translates to:
  /// **'Vibe 库'**
  String get vibeLibrary;

  /// No description provided for @importVibe.
  ///
  /// In zh, this message translates to:
  /// **'导入 Vibe 参考图'**
  String get importVibe;

  /// No description provided for @infoExtractedFixed.
  ///
  /// In zh, this message translates to:
  /// **'Info Extracted 信息提取(随编码固定)'**
  String get infoExtractedFixed;

  /// No description provided for @resolutionMatchedBase.
  ///
  /// In zh, this message translates to:
  /// **'分辨率已按底图调整为 {w}×{h}'**
  String resolutionMatchedBase(int w, int h);

  /// No description provided for @removeBaseImage.
  ///
  /// In zh, this message translates to:
  /// **'移除底图'**
  String get removeBaseImage;

  /// No description provided for @changeBaseImage.
  ///
  /// In zh, this message translates to:
  /// **'更换底图'**
  String get changeBaseImage;

  /// No description provided for @selectBaseImage.
  ///
  /// In zh, this message translates to:
  /// **'选择底图'**
  String get selectBaseImage;

  /// No description provided for @cantReadRef.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该参考图'**
  String get cantReadRef;

  /// No description provided for @deleteRefImage.
  ///
  /// In zh, this message translates to:
  /// **'删除参考图'**
  String get deleteRefImage;

  /// No description provided for @deleteRefsBody.
  ///
  /// In zh, this message translates to:
  /// **'将从库中删除选中的 {n} 张(文件与缩略图一并移除),不可恢复。'**
  String deleteRefsBody(int n);

  /// No description provided for @refImageName.
  ///
  /// In zh, this message translates to:
  /// **'参考图名称'**
  String get refImageName;

  /// No description provided for @deleteRefBody.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」将从图库移除(不影响已添加到生成面板的),不可恢复。'**
  String deleteRefBody(String name);

  /// No description provided for @refsAdded.
  ///
  /// In zh, this message translates to:
  /// **'已入库 {n} 张参考图'**
  String refsAdded(int n);

  /// No description provided for @charRefLibrary.
  ///
  /// In zh, this message translates to:
  /// **'角色参考图库'**
  String get charRefLibrary;

  /// No description provided for @searchName.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称…'**
  String get searchName;

  /// No description provided for @noCharRefs.
  ///
  /// In zh, this message translates to:
  /// **'还没有角色参考图'**
  String get noCharRefs;

  /// No description provided for @noMatchingRefs.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的参考图'**
  String get noMatchingRefs;

  /// No description provided for @charRefLibraryHint.
  ///
  /// In zh, this message translates to:
  /// **'在生成页导入参考图后会自动收藏到这里'**
  String get charRefLibraryHint;

  /// No description provided for @confirmSelectionN.
  ///
  /// In zh, this message translates to:
  /// **'确认选择 ({n})'**
  String confirmSelectionN(int n);

  /// No description provided for @confirmSelection.
  ///
  /// In zh, this message translates to:
  /// **'确认选择'**
  String get confirmSelection;

  /// No description provided for @defaultCanvas.
  ///
  /// In zh, this message translates to:
  /// **'默认画布'**
  String get defaultCanvas;

  /// No description provided for @canvasN.
  ///
  /// In zh, this message translates to:
  /// **'画布 {n}'**
  String canvasN(int n);

  /// No description provided for @canvasCopySuffix.
  ///
  /// In zh, this message translates to:
  /// **' · 副本'**
  String get canvasCopySuffix;

  /// No description provided for @characterN.
  ///
  /// In zh, this message translates to:
  /// **'角色 {n}'**
  String characterN(int n);

  /// No description provided for @switchCanvas.
  ///
  /// In zh, this message translates to:
  /// **'切换画布'**
  String get switchCanvas;

  /// No description provided for @currentCanvasSemantics.
  ///
  /// In zh, this message translates to:
  /// **'当前画布：{name}，共 {count} 张'**
  String currentCanvasSemantics(String name, int count);

  /// No description provided for @renameCanvas.
  ///
  /// In zh, this message translates to:
  /// **'重命名画布'**
  String get renameCanvas;

  /// No description provided for @canvasName.
  ///
  /// In zh, this message translates to:
  /// **'画布名称'**
  String get canvasName;

  /// No description provided for @canvases.
  ///
  /// In zh, this message translates to:
  /// **'画布'**
  String get canvases;

  /// No description provided for @newCanvas.
  ///
  /// In zh, this message translates to:
  /// **'新建画布'**
  String get newCanvas;

  /// No description provided for @duplicateCurrent.
  ///
  /// In zh, this message translates to:
  /// **'复制当前'**
  String get duplicateCurrent;

  /// No description provided for @history.
  ///
  /// In zh, this message translates to:
  /// **'历史'**
  String get history;

  /// No description provided for @defaultCanvasLocked.
  ///
  /// In zh, this message translates to:
  /// **'默认画布，固定在最上面，不能删除或改名'**
  String get defaultCanvasLocked;

  /// No description provided for @noPromptYet.
  ///
  /// In zh, this message translates to:
  /// **'尚未填写提示词'**
  String get noPromptYet;

  /// No description provided for @noCharacters.
  ///
  /// In zh, this message translates to:
  /// **'无角色'**
  String get noCharacters;

  /// No description provided for @previewOnlyNoImage.
  ///
  /// In zh, this message translates to:
  /// **'没收到成图,只拿到了预览帧'**
  String get previewOnlyNoImage;

  /// No description provided for @poolFull.
  ///
  /// In zh, this message translates to:
  /// **'同时最多 {n} 条任务,等前面的出完再提交'**
  String poolFull(int n);

  /// No description provided for @jobWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get jobWaiting;

  /// No description provided for @jobSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中'**
  String get jobSaving;

  /// No description provided for @noEligibleToken.
  ///
  /// In zh, this message translates to:
  /// **'没有能接这一单的令牌(检查各令牌的参与条件)'**
  String get noEligibleToken;

  /// No description provided for @naiTokenNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置 NovelAI 令牌'**
  String get naiTokenNotSet;

  /// No description provided for @generationFailedWith.
  ///
  /// In zh, this message translates to:
  /// **'生成失败:{error}'**
  String generationFailedWith(String error);

  /// No description provided for @rateLimitedRetryIn.
  ///
  /// In zh, this message translates to:
  /// **'限流 · {secs}s 后重试({n}/{total})'**
  String rateLimitedRetryIn(int secs, int n, int total);

  /// No description provided for @rateLimitedRetryNow.
  ///
  /// In zh, this message translates to:
  /// **'限流 · 立即重试({n}/{total})'**
  String rateLimitedRetryNow(int n, int total);

  /// No description provided for @shortRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'限流'**
  String get shortRateLimited;

  /// No description provided for @notifyImageOf.
  ///
  /// In zh, this message translates to:
  /// **'第 {n}/{total} 张'**
  String notifyImageOf(int n, int total);

  /// No description provided for @notifyQueueOf.
  ///
  /// In zh, this message translates to:
  /// **'队列 {n}/{total}'**
  String notifyQueueOf(int n, int total);

  /// No description provided for @shortImages.
  ///
  /// In zh, this message translates to:
  /// **'{n} 张'**
  String shortImages(int n);

  /// No description provided for @generatingCount.
  ///
  /// In zh, this message translates to:
  /// **'生成中 · {n} 张'**
  String generatingCount(int n);

  /// No description provided for @generatingEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'生成中…'**
  String get generatingEllipsis;

  /// No description provided for @generatingCountStep.
  ///
  /// In zh, this message translates to:
  /// **'生成中 · {n} 张 ({step}/{total})'**
  String generatingCountStep(int n, int step, int total);

  /// No description provided for @generatingStep.
  ///
  /// In zh, this message translates to:
  /// **'生成中 {step}/{total}'**
  String generatingStep(int step, int total);

  /// No description provided for @noTokenCantEncode.
  ///
  /// In zh, this message translates to:
  /// **'未设置令牌,无法编码'**
  String get noTokenCantEncode;

  /// No description provided for @anlasAndQuota.
  ///
  /// In zh, this message translates to:
  /// **'点数与额度'**
  String get anlasAndQuota;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @subscriptionTier.
  ///
  /// In zh, this message translates to:
  /// **'订阅档位'**
  String get subscriptionTier;

  /// No description provided for @anlasPoints.
  ///
  /// In zh, this message translates to:
  /// **'Anlas 点数'**
  String get anlasPoints;

  /// No description provided for @refillRate.
  ///
  /// In zh, this message translates to:
  /// **'回充速率'**
  String get refillRate;

  /// No description provided for @imagesPerHour.
  ///
  /// In zh, this message translates to:
  /// **'{n} 张 / 时'**
  String imagesPerHour(String n);

  /// No description provided for @timeToFull.
  ///
  /// In zh, this message translates to:
  /// **'距充满'**
  String get timeToFull;

  /// No description provided for @nai5Quota.
  ///
  /// In zh, this message translates to:
  /// **'NAI 5 额度'**
  String get nai5Quota;

  /// No description provided for @nai5QuotaAccounts.
  ///
  /// In zh, this message translates to:
  /// **'NAI 5 额度 · {n} 号'**
  String nai5QuotaAccounts(int n);

  /// No description provided for @notProvided.
  ///
  /// In zh, this message translates to:
  /// **'接口未下发'**
  String get notProvided;

  /// No description provided for @opusOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅 Opus'**
  String get opusOnly;

  /// No description provided for @aboutImages.
  ///
  /// In zh, this message translates to:
  /// **'约 {n} 张'**
  String aboutImages(String n);

  /// No description provided for @quotaExhausted.
  ///
  /// In zh, this message translates to:
  /// **'已用尽 · 免费尺寸图改扣 Anlas'**
  String get quotaExhausted;

  /// No description provided for @quotaFull.
  ///
  /// In zh, this message translates to:
  /// **'已充满'**
  String get quotaFull;

  /// No description provided for @quotaIn24h.
  ///
  /// In zh, this message translates to:
  /// **'24 小时后 {pct}%'**
  String quotaIn24h(String pct);

  /// No description provided for @aboutHours.
  ///
  /// In zh, this message translates to:
  /// **'约 {n} 小时'**
  String aboutHours(int n);

  /// No description provided for @aboutDays.
  ///
  /// In zh, this message translates to:
  /// **'约 {n} 天'**
  String aboutDays(String n);

  /// No description provided for @switchedToModel.
  ///
  /// In zh, this message translates to:
  /// **'已切换到 {model} 模型'**
  String switchedToModel(String model);

  /// No description provided for @moduleOfProvider.
  ///
  /// In zh, this message translates to:
  /// **'「{module}」是 {provider} 的功能'**
  String moduleOfProvider(String module, String provider);

  /// No description provided for @moduleHidden.
  ///
  /// In zh, this message translates to:
  /// **'「{module}」已在创作页模块里隐藏'**
  String moduleHidden(String module);

  /// No description provided for @importedPreset.
  ///
  /// In zh, this message translates to:
  /// **'预设 {name}'**
  String importedPreset(String name);

  /// No description provided for @vibesEncodingOnly.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个 Vibe 仅编码,只在 {model} 下可用'**
  String vibesEncodingOnly(int n, String model);

  /// No description provided for @importedToCreate.
  ///
  /// In zh, this message translates to:
  /// **'已导入到创作页'**
  String get importedToCreate;

  /// No description provided for @importedWith.
  ///
  /// In zh, this message translates to:
  /// **'已导入 · {details}'**
  String importedWith(String details);

  /// No description provided for @setAsBaseImageRes.
  ///
  /// In zh, this message translates to:
  /// **'已设为图生图底图 · 分辨率 {w}×{h}'**
  String setAsBaseImageRes(int w, int h);

  /// No description provided for @setAsBaseImage.
  ///
  /// In zh, this message translates to:
  /// **'已设为图生图底图'**
  String get setAsBaseImage;

  /// No description provided for @addedVibeMutex.
  ///
  /// In zh, this message translates to:
  /// **'已加入 Vibe · 与角色参考互斥,已暂停角色参考'**
  String get addedVibeMutex;

  /// No description provided for @addedVibe.
  ///
  /// In zh, this message translates to:
  /// **'已加入 Vibe 参考'**
  String get addedVibe;

  /// No description provided for @addedCharRefMutex.
  ///
  /// In zh, this message translates to:
  /// **'已加入角色参考 · 与 Vibe 互斥,已暂停 Vibe'**
  String get addedCharRefMutex;

  /// No description provided for @addedCharRef.
  ///
  /// In zh, this message translates to:
  /// **'已加入角色参考'**
  String get addedCharRef;

  /// No description provided for @importReplace.
  ///
  /// In zh, this message translates to:
  /// **'完全覆盖'**
  String get importReplace;

  /// No description provided for @importNewSection.
  ///
  /// In zh, this message translates to:
  /// **'新建分区'**
  String get importNewSection;

  /// No description provided for @importAppend.
  ///
  /// In zh, this message translates to:
  /// **'额外添加'**
  String get importAppend;

  /// No description provided for @noParamsUseAsRef.
  ///
  /// In zh, this message translates to:
  /// **'未在这张图里找到生成参数,仍可把它用作参考。'**
  String get noParamsUseAsRef;

  /// No description provided for @useImageAs.
  ///
  /// In zh, this message translates to:
  /// **'把这张图用作'**
  String get useImageAs;

  /// No description provided for @importToCreate.
  ///
  /// In zh, this message translates to:
  /// **'导入到生成页'**
  String get importToCreate;

  /// No description provided for @promptOnlyCrossModel.
  ///
  /// In zh, this message translates to:
  /// **'这是 {image} 模型的图片,当前为 {current} 模型,只能导入提示词。'**
  String promptOnlyCrossModel(String image, String current);

  /// No description provided for @promptOnlyUnknown.
  ///
  /// In zh, this message translates to:
  /// **'{source} 图片在本机没有对应的模型,只能导入提示词。'**
  String promptOnlyUnknown(String source);

  /// No description provided for @partialCrossModel.
  ///
  /// In zh, this message translates to:
  /// **'这张图用的是 {other} 的模型,当前为 {current},仅能导入部分参数'**
  String partialCrossModel(String other, String current);

  /// No description provided for @partialUnknown.
  ///
  /// In zh, this message translates to:
  /// **'这张图用的模型本机没有,仅能导入部分参数'**
  String get partialUnknown;

  /// No description provided for @foreignModel.
  ///
  /// In zh, this message translates to:
  /// **'这张图用的是 {other} 的模型'**
  String foreignModel(String other);

  /// No description provided for @notLocalModel.
  ///
  /// In zh, this message translates to:
  /// **'不是本机支持的模型'**
  String get notLocalModel;

  /// No description provided for @presetNeedPrompt.
  ///
  /// In zh, this message translates to:
  /// **'需要先勾选正向或负向提示词'**
  String get presetNeedPrompt;

  /// No description provided for @presetStripSwitch.
  ///
  /// In zh, this message translates to:
  /// **'以上文本会从提示词里删掉,档位切成「{name}」。'**
  String presetStripSwitch(String name);

  /// No description provided for @presetStripKeep.
  ///
  /// In zh, this message translates to:
  /// **'以上文本会从提示词里删掉,档位不变。'**
  String get presetStripKeep;

  /// No description provided for @presetNoPositive.
  ///
  /// In zh, this message translates to:
  /// **'(这一档不加正向文本)'**
  String get presetNoPositive;

  /// No description provided for @autoConvertPrompt.
  ///
  /// In zh, this message translates to:
  /// **'自动转换提示词格式'**
  String get autoConvertPrompt;

  /// No description provided for @autoConvertPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'把 (tag:1.2) 转成 NovelAI 的 1.2::tag::'**
  String get autoConvertPromptHint;

  /// No description provided for @noParamsSize.
  ///
  /// In zh, this message translates to:
  /// **'未找到生成参数 · {size}'**
  String noParamsSize(String size);

  /// No description provided for @charactersBadge.
  ///
  /// In zh, this message translates to:
  /// **'{n} 角色'**
  String charactersBadge(int n);

  /// No description provided for @copyWhat.
  ///
  /// In zh, this message translates to:
  /// **'复制{what}'**
  String copyWhat(String what);

  /// No description provided for @copiedWhat.
  ///
  /// In zh, this message translates to:
  /// **'已复制{what}'**
  String copiedWhat(String what);

  /// No description provided for @seed.
  ///
  /// In zh, this message translates to:
  /// **'种子'**
  String get seed;

  /// No description provided for @copiedSeed.
  ///
  /// In zh, this message translates to:
  /// **'已复制种子 {value}'**
  String copiedSeed(String value);

  /// No description provided for @vibeParams.
  ///
  /// In zh, this message translates to:
  /// **'强度 {strength} · IE {ie}'**
  String vibeParams(String strength, String ie);

  /// No description provided for @encodingOnlyParams.
  ///
  /// In zh, this message translates to:
  /// **'仅编码 · {params}'**
  String encodingOnlyParams(String params);

  /// No description provided for @encodingOnlyUnknown.
  ///
  /// In zh, this message translates to:
  /// **'仅编码 · 来源模型未知,无法导入'**
  String get encodingOnlyUnknown;

  /// No description provided for @paramsOnlyCantImport.
  ///
  /// In zh, this message translates to:
  /// **'仅有参数,无法导入'**
  String get paramsOnlyCantImport;

  /// No description provided for @genSettings.
  ///
  /// In zh, this message translates to:
  /// **'生成设置'**
  String get genSettings;

  /// No description provided for @unsupportedParams.
  ///
  /// In zh, this message translates to:
  /// **'含当前版本不支持的参数({params}),无法导入生成设置。'**
  String unsupportedParams(String params);

  /// No description provided for @importMode.
  ///
  /// In zh, this message translates to:
  /// **'导入方式'**
  String get importMode;

  /// No description provided for @emptyParen.
  ///
  /// In zh, this message translates to:
  /// **'(空)'**
  String get emptyParen;

  /// No description provided for @importSelected.
  ///
  /// In zh, this message translates to:
  /// **'导入所选内容'**
  String get importSelected;

  /// No description provided for @useAsReference.
  ///
  /// In zh, this message translates to:
  /// **'参考'**
  String get useAsReference;

  /// No description provided for @unknownSource.
  ///
  /// In zh, this message translates to:
  /// **'未知来源'**
  String get unknownSource;

  /// No description provided for @fullMetadataTwoLine.
  ///
  /// In zh, this message translates to:
  /// **'完整\n元数据'**
  String get fullMetadataTwoLine;

  /// No description provided for @fullMetadata.
  ///
  /// In zh, this message translates to:
  /// **'完整元数据'**
  String get fullMetadata;

  /// No description provided for @closeImport.
  ///
  /// In zh, this message translates to:
  /// **'关闭导入'**
  String get closeImport;

  /// No description provided for @goToImportPanel.
  ///
  /// In zh, this message translates to:
  /// **'去导入面板(导入参数 / 用作参考)'**
  String get goToImportPanel;

  /// No description provided for @fileSize.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get fileSize;

  /// No description provided for @format.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get format;

  /// No description provided for @source.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get source;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @transparentBg.
  ///
  /// In zh, this message translates to:
  /// **'透明背景'**
  String get transparentBg;

  /// No description provided for @yes.
  ///
  /// In zh, this message translates to:
  /// **'是'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In zh, this message translates to:
  /// **'否'**
  String get no;

  /// No description provided for @alphaStraight.
  ///
  /// In zh, this message translates to:
  /// **'直通 Straight'**
  String get alphaStraight;

  /// No description provided for @alphaPremultiplied.
  ///
  /// In zh, this message translates to:
  /// **'预乘 Premultiplied'**
  String get alphaPremultiplied;

  /// No description provided for @genParams.
  ///
  /// In zh, this message translates to:
  /// **'生成参数'**
  String get genParams;

  /// No description provided for @vibeStrengthLabel.
  ///
  /// In zh, this message translates to:
  /// **'强度: {v}'**
  String vibeStrengthLabel(String v);

  /// No description provided for @vibeExtractedLabel.
  ///
  /// In zh, this message translates to:
  /// **'提取: {v}'**
  String vibeExtractedLabel(String v);

  /// No description provided for @rawData.
  ///
  /// In zh, this message translates to:
  /// **'原始数据'**
  String get rawData;

  /// No description provided for @genInProgressWait.
  ///
  /// In zh, this message translates to:
  /// **'生成进行中,请稍候'**
  String get genInProgressWait;

  /// No description provided for @notAligned64Expand.
  ///
  /// In zh, this message translates to:
  /// **'图片尺寸非 64 对齐,无法扩图'**
  String get notAligned64Expand;

  /// No description provided for @expandTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'扩图后尺寸过大,请缩小扩展范围'**
  String get expandTooLarge;

  /// No description provided for @savedToInpaint.
  ///
  /// In zh, this message translates to:
  /// **'已存入重绘'**
  String get savedToInpaint;

  /// No description provided for @censorNothingFound.
  ///
  /// In zh, this message translates to:
  /// **'没检测到需要打码的区域'**
  String get censorNothingFound;

  /// No description provided for @censorDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到 {n} 处,已预填'**
  String censorDetected(int n);

  /// No description provided for @censorDetectFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动识别失败: {error}'**
  String censorDetectFailed(String error);

  /// No description provided for @censorColor.
  ///
  /// In zh, this message translates to:
  /// **'打码颜色'**
  String get censorColor;

  /// No description provided for @paintCensorFirst.
  ///
  /// In zh, this message translates to:
  /// **'先涂抹要打码的区域'**
  String get paintCensorFirst;

  /// No description provided for @censoredSaved.
  ///
  /// In zh, this message translates to:
  /// **'已打码并存入图库'**
  String get censoredSaved;

  /// No description provided for @censorFailed.
  ///
  /// In zh, this message translates to:
  /// **'打码失败: {error}'**
  String censorFailed(String error);

  /// No description provided for @inpaintNeedNai.
  ///
  /// In zh, this message translates to:
  /// **'{model} 模型不支持重绘,请先切回 NovelAI 模型'**
  String inpaintNeedNai(String model);

  /// No description provided for @dragEdgesFirst.
  ///
  /// In zh, this message translates to:
  /// **'先拖动边缘扩展画布'**
  String get dragEdgesFirst;

  /// No description provided for @paintInpaintFirst.
  ///
  /// In zh, this message translates to:
  /// **'先用画笔涂抹要重绘的区域'**
  String get paintInpaintFirst;

  /// No description provided for @noPaintInBox.
  ///
  /// In zh, this message translates to:
  /// **'黄框内没有涂抹区域'**
  String get noPaintInBox;

  /// No description provided for @paintOutsideBox.
  ///
  /// In zh, this message translates to:
  /// **'黄框外还有涂抹,拉大黄框或分两次重绘'**
  String get paintOutsideBox;

  /// No description provided for @sendTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'发送尺寸过大,请开启「局部」缩小范围'**
  String get sendTooLarge;

  /// No description provided for @notAligned64UseRegion.
  ///
  /// In zh, this message translates to:
  /// **'图片尺寸非 64 对齐,请使用「局部」模式'**
  String get notAligned64UseRegion;

  /// No description provided for @tabExpand.
  ///
  /// In zh, this message translates to:
  /// **'扩图'**
  String get tabExpand;

  /// No description provided for @tabCensor.
  ///
  /// In zh, this message translates to:
  /// **'打码'**
  String get tabCensor;

  /// No description provided for @toolOffset.
  ///
  /// In zh, this message translates to:
  /// **'偏位'**
  String get toolOffset;

  /// No description provided for @toolRegion.
  ///
  /// In zh, this message translates to:
  /// **'局部'**
  String get toolRegion;

  /// No description provided for @censorBlock.
  ///
  /// In zh, this message translates to:
  /// **'块'**
  String get censorBlock;

  /// No description provided for @censorColorShort.
  ///
  /// In zh, this message translates to:
  /// **'颜色'**
  String get censorColorShort;

  /// No description provided for @saveMask.
  ///
  /// In zh, this message translates to:
  /// **'保存遮罩'**
  String get saveMask;

  /// No description provided for @saveExpand.
  ///
  /// In zh, this message translates to:
  /// **'保存扩图'**
  String get saveExpand;

  /// No description provided for @autoDetect.
  ///
  /// In zh, this message translates to:
  /// **'自动识别'**
  String get autoDetect;

  /// No description provided for @detecting.
  ///
  /// In zh, this message translates to:
  /// **'识别中…'**
  String get detecting;

  /// No description provided for @savingEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get savingEllipsis;

  /// No description provided for @mosaicBlock.
  ///
  /// In zh, this message translates to:
  /// **'马赛克块'**
  String get mosaicBlock;

  /// No description provided for @expandSize.
  ///
  /// In zh, this message translates to:
  /// **'扩图尺寸'**
  String get expandSize;

  /// No description provided for @widthShort.
  ///
  /// In zh, this message translates to:
  /// **'宽'**
  String get widthShort;

  /// No description provided for @heightShort.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get heightShort;

  /// No description provided for @expandHint.
  ///
  /// In zh, this message translates to:
  /// **'原图 {w}×{h},增量对称分配到两侧(64 对齐)'**
  String expandHint(int w, int h);

  /// No description provided for @censorMosaic.
  ///
  /// In zh, this message translates to:
  /// **'马赛克'**
  String get censorMosaic;

  /// No description provided for @censorSolid.
  ///
  /// In zh, this message translates to:
  /// **'纯色'**
  String get censorSolid;

  /// No description provided for @colorBlack.
  ///
  /// In zh, this message translates to:
  /// **'黑'**
  String get colorBlack;

  /// No description provided for @colorDarkGray.
  ///
  /// In zh, this message translates to:
  /// **'深灰'**
  String get colorDarkGray;

  /// No description provided for @colorLightGray.
  ///
  /// In zh, this message translates to:
  /// **'浅灰'**
  String get colorLightGray;

  /// No description provided for @colorWhite.
  ///
  /// In zh, this message translates to:
  /// **'白'**
  String get colorWhite;

  /// No description provided for @weightGroupInfo.
  ///
  /// In zh, this message translates to:
  /// **'处于权重组 ×{group} · 合计 ×{total}'**
  String weightGroupInfo(String group, String total);

  /// No description provided for @weightGroupOnly.
  ///
  /// In zh, this message translates to:
  /// **'处于权重组 ×{group}'**
  String weightGroupOnly(String group);

  /// No description provided for @selectWholeGroup.
  ///
  /// In zh, this message translates to:
  /// **'选中整组'**
  String get selectWholeGroup;

  /// No description provided for @sdWeightConvert.
  ///
  /// In zh, this message translates to:
  /// **'SD 权重语法 · 点击转换为 NAI 格式'**
  String get sdWeightConvert;

  /// No description provided for @sdWeightConvertShort.
  ///
  /// In zh, this message translates to:
  /// **'SD 权重语法 · 转成 NAI'**
  String get sdWeightConvertShort;

  /// No description provided for @weight.
  ///
  /// In zh, this message translates to:
  /// **'权重'**
  String get weight;

  /// No description provided for @clearWeight.
  ///
  /// In zh, this message translates to:
  /// **'清除权重'**
  String get clearWeight;

  /// No description provided for @clearWeightShort.
  ///
  /// In zh, this message translates to:
  /// **'清除权重'**
  String get clearWeightShort;

  /// No description provided for @related.
  ///
  /// In zh, this message translates to:
  /// **'关联'**
  String get related;

  /// No description provided for @disableTag.
  ///
  /// In zh, this message translates to:
  /// **'禁用'**
  String get disableTag;

  /// No description provided for @tagLabel.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get tagLabel;

  /// No description provided for @tagCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制标签'**
  String get tagCopied;

  /// No description provided for @cantOpenBrowser.
  ///
  /// In zh, this message translates to:
  /// **'无法打开浏览器'**
  String get cantOpenBrowser;

  /// No description provided for @tapPlusToMove.
  ///
  /// In zh, this message translates to:
  /// **'点击加号移动'**
  String get tapPlusToMove;

  /// No description provided for @selectedItems.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 项'**
  String selectedItems(int n);

  /// No description provided for @tapTagsToSelect.
  ///
  /// In zh, this message translates to:
  /// **'点词条可多选'**
  String get tapTagsToSelect;

  /// No description provided for @extractAsSection.
  ///
  /// In zh, this message translates to:
  /// **'提取为新分区'**
  String get extractAsSection;

  /// No description provided for @foldSegment.
  ///
  /// In zh, this message translates to:
  /// **'折叠段 · {n} 个标签'**
  String foldSegment(int n);

  /// No description provided for @expand.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get expand;

  /// No description provided for @collapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get collapse;

  /// No description provided for @overall.
  ///
  /// In zh, this message translates to:
  /// **'整体'**
  String get overall;

  /// No description provided for @move.
  ///
  /// In zh, this message translates to:
  /// **'移动'**
  String get move;

  /// No description provided for @editorSettings.
  ///
  /// In zh, this message translates to:
  /// **'编辑器设置'**
  String get editorSettings;

  /// No description provided for @settingDisplay.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get settingDisplay;

  /// No description provided for @showTranslations.
  ///
  /// In zh, this message translates to:
  /// **'显示注释翻译'**
  String get showTranslations;

  /// No description provided for @showTranslationsDesc.
  ///
  /// In zh, this message translates to:
  /// **'在词条下方以小字标注中文翻译'**
  String get showTranslationsDesc;

  /// No description provided for @weightHighlight.
  ///
  /// In zh, this message translates to:
  /// **'权重高亮'**
  String get weightHighlight;

  /// No description provided for @weightHighlightDesc.
  ///
  /// In zh, this message translates to:
  /// **'加权 / 降权词条按强度显示红 / 蓝色'**
  String get weightHighlightDesc;

  /// No description provided for @textFontSize.
  ///
  /// In zh, this message translates to:
  /// **'文本字号'**
  String get textFontSize;

  /// No description provided for @textFontSizeDesc.
  ///
  /// In zh, this message translates to:
  /// **'文本模式下的文本显示大小'**
  String get textFontSizeDesc;

  /// No description provided for @chipFontSize.
  ///
  /// In zh, this message translates to:
  /// **'芯片字号'**
  String get chipFontSize;

  /// No description provided for @chipFontSizeDesc.
  ///
  /// In zh, this message translates to:
  /// **'芯片模式下的芯片显示大小'**
  String get chipFontSizeDesc;

  /// No description provided for @settingCompletion.
  ///
  /// In zh, this message translates to:
  /// **'补全'**
  String get settingCompletion;

  /// No description provided for @enableCompletion.
  ///
  /// In zh, this message translates to:
  /// **'启用补全提示'**
  String get enableCompletion;

  /// No description provided for @enableCompletionDesc.
  ///
  /// In zh, this message translates to:
  /// **'输入时在底部给出标签补全建议'**
  String get enableCompletionDesc;

  /// No description provided for @entitySuggestions.
  ///
  /// In zh, this message translates to:
  /// **'实体建议'**
  String get entitySuggestions;

  /// No description provided for @entitySuggestionsDesc.
  ///
  /// In zh, this message translates to:
  /// **'补全中包含画师 / 角色 / OC / 作品'**
  String get entitySuggestionsDesc;

  /// No description provided for @autoComma.
  ///
  /// In zh, this message translates to:
  /// **'选词自动补逗号'**
  String get autoComma;

  /// No description provided for @autoCommaDesc.
  ///
  /// In zh, this message translates to:
  /// **'选中补全后自动加「, 」,方便连打下一枚'**
  String get autoCommaDesc;

  /// No description provided for @settingTagBar.
  ///
  /// In zh, this message translates to:
  /// **'词条栏'**
  String get settingTagBar;

  /// No description provided for @enableTagPanel.
  ///
  /// In zh, this message translates to:
  /// **'启用标签面板'**
  String get enableTagPanel;

  /// No description provided for @enableTagPanelDesc.
  ///
  /// In zh, this message translates to:
  /// **'光标停在词条上时显示权重与操作栏'**
  String get enableTagPanelDesc;

  /// No description provided for @compactTagBar.
  ///
  /// In zh, this message translates to:
  /// **'精简词条栏'**
  String get compactTagBar;

  /// No description provided for @compactTagBarDesc.
  ///
  /// In zh, this message translates to:
  /// **'压成一行,只留权重与删除,正文多露两行'**
  String get compactTagBarDesc;

  /// No description provided for @weightStep.
  ///
  /// In zh, this message translates to:
  /// **'权重步进'**
  String get weightStep;

  /// No description provided for @weightStepDesc.
  ///
  /// In zh, this message translates to:
  /// **'数值 +/− 每步的调整量'**
  String get weightStepDesc;

  /// No description provided for @kindArtist.
  ///
  /// In zh, this message translates to:
  /// **'画师'**
  String get kindArtist;

  /// No description provided for @kindWork.
  ///
  /// In zh, this message translates to:
  /// **'作品'**
  String get kindWork;

  /// No description provided for @kindTag.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get kindTag;

  /// No description provided for @completionResults.
  ///
  /// In zh, this message translates to:
  /// **'补全结果'**
  String get completionResults;

  /// No description provided for @itemsCount.
  ///
  /// In zh, this message translates to:
  /// **'{n} 项'**
  String itemsCount(int n);

  /// No description provided for @byHeat.
  ///
  /// In zh, this message translates to:
  /// **'热度'**
  String get byHeat;

  /// No description provided for @wikiMissing.
  ///
  /// In zh, this message translates to:
  /// **'没拿到 Wiki 摘要,可再点一次或前往 Danbooru 查看。'**
  String get wikiMissing;

  /// No description provided for @loadingWiki.
  ///
  /// In zh, this message translates to:
  /// **'加载 Wiki…'**
  String get loadingWiki;

  /// No description provided for @aliases.
  ///
  /// In zh, this message translates to:
  /// **'别名: {list}'**
  String aliases(String list);

  /// No description provided for @wikiLinkCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制 Wiki 链接:{url}'**
  String wikiLinkCopied(String url);

  /// No description provided for @unfavorited.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏「{tag}」'**
  String unfavorited(String tag);

  /// No description provided for @noFavorites.
  ///
  /// In zh, this message translates to:
  /// **'暂无收藏'**
  String get noFavorites;

  /// No description provided for @modeText.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get modeText;

  /// No description provided for @modeChips.
  ///
  /// In zh, this message translates to:
  /// **'芯片'**
  String get modeChips;

  /// No description provided for @positiveShort.
  ///
  /// In zh, this message translates to:
  /// **'正面'**
  String get positiveShort;

  /// No description provided for @negativeShort.
  ///
  /// In zh, this message translates to:
  /// **'负面'**
  String get negativeShort;

  /// No description provided for @translateFailed.
  ///
  /// In zh, this message translates to:
  /// **'翻译失败,稍后再试'**
  String get translateFailed;

  /// No description provided for @copiedItems.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {n} 项'**
  String copiedItems(int n);

  /// No description provided for @cantExtractFold.
  ///
  /// In zh, this message translates to:
  /// **'所选和折叠连在一起,没法提取'**
  String get cantExtractFold;

  /// No description provided for @extractedTo.
  ///
  /// In zh, this message translates to:
  /// **'已提取到「{name}」'**
  String extractedTo(String name);

  /// No description provided for @editorInputHint.
  ///
  /// In zh, this message translates to:
  /// **'点击输入标签,可输入中文自动触发翻译与联想'**
  String get editorInputHint;

  /// No description provided for @translating.
  ///
  /// In zh, this message translates to:
  /// **'翻译中…'**
  String get translating;

  /// No description provided for @querying.
  ///
  /// In zh, this message translates to:
  /// **'查询「{q}」…'**
  String querying(String q);

  /// No description provided for @noMatchAddTag.
  ///
  /// In zh, this message translates to:
  /// **'无匹配 · 点此把「{q}」加为新标签'**
  String noMatchAddTag(String q);

  /// No description provided for @workNote.
  ///
  /// In zh, this message translates to:
  /// **'点骰子随机抽一个角色'**
  String get workNote;

  /// No description provided for @translateToEnglish.
  ///
  /// In zh, this message translates to:
  /// **'翻译为英文'**
  String get translateToEnglish;

  /// No description provided for @chipInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入标签,可输入中文自动翻译'**
  String get chipInputHint;

  /// No description provided for @addMore.
  ///
  /// In zh, this message translates to:
  /// **'继续添加…'**
  String get addMore;

  /// No description provided for @saveAndBack.
  ///
  /// In zh, this message translates to:
  /// **'保存并返回'**
  String get saveAndBack;

  /// No description provided for @localLibrary.
  ///
  /// In zh, this message translates to:
  /// **'本地库'**
  String get localLibrary;

  /// No description provided for @untitledVibe.
  ///
  /// In zh, this message translates to:
  /// **'未命名 Vibe'**
  String get untitledVibe;

  /// No description provided for @favorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favorites;

  /// No description provided for @vibeNoEncodingForModel.
  ///
  /// In zh, this message translates to:
  /// **'该 Vibe 无当前模型的编码,无法使用'**
  String get vibeNoEncodingForModel;

  /// No description provided for @cantReadVibe.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该 Vibe 文件'**
  String get cantReadVibe;

  /// No description provided for @ingestVibes.
  ///
  /// In zh, this message translates to:
  /// **'{n} 条 Vibe'**
  String ingestVibes(int n);

  /// No description provided for @ingestImages.
  ///
  /// In zh, this message translates to:
  /// **'{n} 张图'**
  String ingestImages(int n);

  /// No description provided for @ingestFailed.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个失败'**
  String ingestFailed(int n);

  /// No description provided for @importDone.
  ///
  /// In zh, this message translates to:
  /// **'导入完成:{details}'**
  String importDone(String details);

  /// No description provided for @deleteVibe.
  ///
  /// In zh, this message translates to:
  /// **'删除 Vibe'**
  String get deleteVibe;

  /// No description provided for @deleteVibesBody.
  ///
  /// In zh, this message translates to:
  /// **'将从库中删除选中的 {n} 条 Vibe(文件与缩略图一并移除),不可恢复。'**
  String deleteVibesBody(int n);

  /// No description provided for @deleteVibeBody.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」将从库中删除(文件与缩略图一并移除),不可恢复。'**
  String deleteVibeBody(String name);

  /// No description provided for @vibesExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {n} 条 Vibe'**
  String vibesExported(int n);

  /// No description provided for @exportedName.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {name}'**
  String exportedName(String name);

  /// No description provided for @exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败:{error}'**
  String exportFailed(String error);

  /// No description provided for @batchAddTag.
  ///
  /// In zh, this message translates to:
  /// **'批量添加标签'**
  String get batchAddTag;

  /// No description provided for @tagNameHint.
  ///
  /// In zh, this message translates to:
  /// **'标签名,如 风景'**
  String get tagNameHint;

  /// No description provided for @tagAddedToN.
  ///
  /// In zh, this message translates to:
  /// **'已为 {n} 条添加标签「{tag}」'**
  String tagAddedToN(int n, String tag);

  /// No description provided for @addedToGenerate.
  ///
  /// In zh, this message translates to:
  /// **'已添加到生成'**
  String get addedToGenerate;

  /// No description provided for @alreadyInGenerate.
  ///
  /// In zh, this message translates to:
  /// **'已在生成面板中'**
  String get alreadyInGenerate;

  /// No description provided for @notAvailableYet.
  ///
  /// In zh, this message translates to:
  /// **'暂未开放'**
  String get notAvailableYet;

  /// No description provided for @vibeManager.
  ///
  /// In zh, this message translates to:
  /// **'Vibe 管理器'**
  String get vibeManager;

  /// No description provided for @importLabel.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get importLabel;

  /// No description provided for @importVibeFile.
  ///
  /// In zh, this message translates to:
  /// **'导入 Vibe 文件'**
  String get importVibeFile;

  /// No description provided for @searchNameOrTag.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称或标签…'**
  String get searchNameOrTag;

  /// No description provided for @localCount.
  ///
  /// In zh, this message translates to:
  /// **'本地 · {n}'**
  String localCount(int n);

  /// No description provided for @publicLibrary.
  ///
  /// In zh, this message translates to:
  /// **'公共库'**
  String get publicLibrary;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @manageTags.
  ///
  /// In zh, this message translates to:
  /// **'管理标签'**
  String get manageTags;

  /// No description provided for @noLocalVibes.
  ///
  /// In zh, this message translates to:
  /// **'暂无本地 Vibe'**
  String get noLocalVibes;

  /// No description provided for @noMatchingVibes.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的 Vibe'**
  String get noMatchingVibes;

  /// No description provided for @tapPlusToImport.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角 + 导入'**
  String get tapPlusToImport;

  /// No description provided for @publicVibeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'公共 Vibe 库暂未开放'**
  String get publicVibeUnavailable;

  /// No description provided for @bundle.
  ///
  /// In zh, this message translates to:
  /// **'打包'**
  String get bundle;

  /// No description provided for @notEncoded.
  ///
  /// In zh, this message translates to:
  /// **'未编码'**
  String get notEncoded;

  /// No description provided for @needsModels.
  ///
  /// In zh, this message translates to:
  /// **'需 {models}'**
  String needsModels(String models);

  /// No description provided for @detailsAndParams.
  ///
  /// In zh, this message translates to:
  /// **'详情与参数'**
  String get detailsAndParams;

  /// No description provided for @editTags.
  ///
  /// In zh, this message translates to:
  /// **'编辑标签'**
  String get editTags;

  /// No description provided for @publishToPublic.
  ///
  /// In zh, this message translates to:
  /// **'发布到公共'**
  String get publishToPublic;

  /// No description provided for @export.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get export;

  /// No description provided for @noTagsYetBelow.
  ///
  /// In zh, this message translates to:
  /// **'还没有标签,在下方输入新建。'**
  String get noTagsYetBelow;

  /// No description provided for @newTagHint.
  ///
  /// In zh, this message translates to:
  /// **'新建标签,如 风景'**
  String get newTagHint;

  /// No description provided for @tagExists.
  ///
  /// In zh, this message translates to:
  /// **'标签「{name}」已存在'**
  String tagExists(String name);

  /// No description provided for @renameTag.
  ///
  /// In zh, this message translates to:
  /// **'重命名标签'**
  String get renameTag;

  /// No description provided for @deleteTag.
  ///
  /// In zh, this message translates to:
  /// **'删除标签'**
  String get deleteTag;

  /// No description provided for @deleteTagBody.
  ///
  /// In zh, this message translates to:
  /// **'标签「{tag}」将从所有 Vibe 上移除(不删除 Vibe 本身)。'**
  String deleteTagBody(String tag);

  /// No description provided for @newLabel.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get newLabel;

  /// No description provided for @noTagsYetHint.
  ///
  /// In zh, this message translates to:
  /// **'还没有标签\n在上方输入框新建,或在某条 Vibe 的「编辑标签」里新建'**
  String get noTagsYetHint;

  /// No description provided for @vibeNoImageOrEncoding.
  ///
  /// In zh, this message translates to:
  /// **'该 Vibe 没有可用的图片或编码'**
  String get vibeNoImageOrEncoding;

  /// No description provided for @encodingOnlyNoImage.
  ///
  /// In zh, this message translates to:
  /// **'仅编码(无原图)'**
  String get encodingOnlyNoImage;

  /// No description provided for @defaultStrength.
  ///
  /// In zh, this message translates to:
  /// **'Strength 默认强度'**
  String get defaultStrength;

  /// No description provided for @defaultInfoExtracted.
  ///
  /// In zh, this message translates to:
  /// **'Info Extracted 默认信息提取'**
  String get defaultInfoExtracted;

  /// No description provided for @ieFixedNoImage.
  ///
  /// In zh, this message translates to:
  /// **'Info Extracted 随编码固定,无原图不可调整。'**
  String get ieFixedNoImage;

  /// No description provided for @addToGenerate.
  ///
  /// In zh, this message translates to:
  /// **'添加到生成'**
  String get addToGenerate;

  /// No description provided for @encodings.
  ///
  /// In zh, this message translates to:
  /// **'编码'**
  String get encodings;

  /// No description provided for @checking.
  ///
  /// In zh, this message translates to:
  /// **'检查中…'**
  String get checking;

  /// No description provided for @encodedN.
  ///
  /// In zh, this message translates to:
  /// **'已编码 {n}'**
  String encodedN(int n);

  /// No description provided for @clearAllCharacters.
  ///
  /// In zh, this message translates to:
  /// **'清空全部角色'**
  String get clearAllCharacters;

  /// No description provided for @characterLibrary.
  ///
  /// In zh, this message translates to:
  /// **'角色库'**
  String get characterLibrary;

  /// No description provided for @clearAllCharactersQ.
  ///
  /// In zh, this message translates to:
  /// **'清空全部角色?'**
  String get clearAllCharactersQ;

  /// No description provided for @clearAllCharactersBody.
  ///
  /// In zh, this message translates to:
  /// **'将移除所有角色及其配置,此操作不可撤销。'**
  String get clearAllCharactersBody;

  /// No description provided for @replaceCharQ.
  ///
  /// In zh, this message translates to:
  /// **'替换「{name}」?'**
  String replaceCharQ(String name);

  /// No description provided for @replaceCharBody.
  ///
  /// In zh, this message translates to:
  /// **'提示词将换成「{name}」的。'**
  String replaceCharBody(String name);

  /// No description provided for @replace.
  ///
  /// In zh, this message translates to:
  /// **'替换'**
  String get replace;

  /// No description provided for @deleteCharacter.
  ///
  /// In zh, this message translates to:
  /// **'删除角色'**
  String get deleteCharacter;

  /// No description provided for @setCharPosition.
  ///
  /// In zh, this message translates to:
  /// **'设置角色位置：{pos}'**
  String setCharPosition(String pos);

  /// No description provided for @tapToEditPrompt.
  ///
  /// In zh, this message translates to:
  /// **'点击编辑提示词…'**
  String get tapToEditPrompt;

  /// No description provided for @pickFromCharLibrary.
  ///
  /// In zh, this message translates to:
  /// **'从角色库选'**
  String get pickFromCharLibrary;

  /// No description provided for @swapCharacter.
  ///
  /// In zh, this message translates to:
  /// **'换角色'**
  String get swapCharacter;

  /// No description provided for @canvasSingular.
  ///
  /// In zh, this message translates to:
  /// **'画布'**
  String get canvasSingular;

  /// No description provided for @canvasHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 历史'**
  String canvasHistoryTitle(String name);

  /// No description provided for @noHistoryYet.
  ///
  /// In zh, this message translates to:
  /// **'这张画布还没有出过图'**
  String get noHistoryYet;

  /// No description provided for @restoreThisVersion.
  ///
  /// In zh, this message translates to:
  /// **'恢复到这版'**
  String get restoreThisVersion;

  /// No description provided for @duplicateAsNewCanvas.
  ///
  /// In zh, this message translates to:
  /// **'复制为新画布'**
  String get duplicateAsNewCanvas;

  /// No description provided for @duplicatedAsNewCanvas.
  ///
  /// In zh, this message translates to:
  /// **'已复制为新画布'**
  String get duplicatedAsNewCanvas;

  /// No description provided for @restoredTo.
  ///
  /// In zh, this message translates to:
  /// **'已恢复到 {time} 的版本'**
  String restoredTo(String time);

  /// No description provided for @imagesN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 张'**
  String imagesN(int n);

  /// No description provided for @noPrompt.
  ///
  /// In zh, this message translates to:
  /// **'没有提示词'**
  String get noPrompt;

  /// No description provided for @negChanged.
  ///
  /// In zh, this message translates to:
  /// **'负面有改动'**
  String get negChanged;

  /// No description provided for @charsChange.
  ///
  /// In zh, this message translates to:
  /// **'角色 {a}→{b}'**
  String charsChange(int a, int b);

  /// No description provided for @addedBaseImage.
  ///
  /// In zh, this message translates to:
  /// **'加了底图'**
  String get addedBaseImage;

  /// No description provided for @removedBaseImage.
  ///
  /// In zh, this message translates to:
  /// **'去掉底图'**
  String get removedBaseImage;

  /// No description provided for @addedInpaint.
  ///
  /// In zh, this message translates to:
  /// **'加了重绘'**
  String get addedInpaint;

  /// No description provided for @removedInpaint.
  ///
  /// In zh, this message translates to:
  /// **'去掉重绘'**
  String get removedInpaint;

  /// No description provided for @stepsChange.
  ///
  /// In zh, this message translates to:
  /// **'{a}→{b} 步'**
  String stepsChange(int a, int b);

  /// No description provided for @paramsChanged.
  ///
  /// In zh, this message translates to:
  /// **'参数有改动'**
  String get paramsChanged;

  /// No description provided for @dateYesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String dateYesterday(String time);

  /// No description provided for @dateMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {time}'**
  String dateMonthDay(String month, int day, String time);

  /// No description provided for @dateYearMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日 {time}'**
  String dateYearMonthDay(int year, String month, int day, String time);

  /// No description provided for @tabCreate.
  ///
  /// In zh, this message translates to:
  /// **'创作'**
  String get tabCreate;

  /// No description provided for @gallery.
  ///
  /// In zh, this message translates to:
  /// **'图库'**
  String get gallery;

  /// No description provided for @tabInspiration.
  ///
  /// In zh, this message translates to:
  /// **'灵感'**
  String get tabInspiration;

  /// No description provided for @tabProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabProfile;

  /// No description provided for @setTokenFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先在「我的」页设置 NovelAI API Token'**
  String get setTokenFirst;

  /// No description provided for @goToSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get goToSettings;

  /// No description provided for @savedToAlbum.
  ///
  /// In zh, this message translates to:
  /// **'新图片已保存到「{name}」'**
  String savedToAlbum(String name);

  /// No description provided for @viewAfterEditing.
  ///
  /// In zh, this message translates to:
  /// **'结束编辑后可查看新图片'**
  String get viewAfterEditing;

  /// No description provided for @imageDeleted.
  ///
  /// In zh, this message translates to:
  /// **'这张图片已被删除'**
  String get imageDeleted;

  /// No description provided for @keyWiped.
  ///
  /// In zh, this message translates to:
  /// **'已存的 Key 被系统清掉了,重新添加后不会再丢'**
  String get keyWiped;

  /// No description provided for @goToAdd.
  ///
  /// In zh, this message translates to:
  /// **'去添加'**
  String get goToAdd;

  /// No description provided for @allImages.
  ///
  /// In zh, this message translates to:
  /// **'全部图片'**
  String get allImages;

  /// No description provided for @albums.
  ///
  /// In zh, this message translates to:
  /// **'相册'**
  String get albums;

  /// No description provided for @noAlbums.
  ///
  /// In zh, this message translates to:
  /// **'没有相册'**
  String get noAlbums;

  /// No description provided for @selectImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get selectImage;

  /// No description provided for @pickFromFiles.
  ///
  /// In zh, this message translates to:
  /// **'从文件选'**
  String get pickFromFiles;

  /// No description provided for @noImages.
  ///
  /// In zh, this message translates to:
  /// **'没有图片'**
  String get noImages;

  /// No description provided for @okCount.
  ///
  /// In zh, this message translates to:
  /// **'确定 ({n})'**
  String okCount(int n);

  /// No description provided for @limitedPhotoAccess.
  ///
  /// In zh, this message translates to:
  /// **'仅可访问部分图片'**
  String get limitedPhotoAccess;

  /// No description provided for @adjust.
  ///
  /// In zh, this message translates to:
  /// **'调整'**
  String get adjust;

  /// No description provided for @needPhotoPermission.
  ///
  /// In zh, this message translates to:
  /// **'需要相册访问权限'**
  String get needPhotoPermission;

  /// No description provided for @recheck.
  ///
  /// In zh, this message translates to:
  /// **'重新检查'**
  String get recheck;

  /// No description provided for @enterNumber.
  ///
  /// In zh, this message translates to:
  /// **'请输入数字'**
  String get enterNumber;

  /// No description provided for @outOfRange.
  ///
  /// In zh, this message translates to:
  /// **'超出范围 {range}'**
  String outOfRange(String range);

  /// No description provided for @rangeHint.
  ///
  /// In zh, this message translates to:
  /// **'范围 {range}'**
  String rangeHint(String range);

  /// No description provided for @rangeStepHint.
  ///
  /// In zh, this message translates to:
  /// **'范围 {range} · 步长 {step}'**
  String rangeStepHint(String range, String step);

  /// No description provided for @overwriteConflicts.
  ///
  /// In zh, this message translates to:
  /// **'其中 {n} 条覆盖本地同 id'**
  String overwriteConflicts(int n);

  /// No description provided for @mergeWithConflicts.
  ///
  /// In zh, this message translates to:
  /// **'按 id 合并:同 id 覆盖({n} 条),其余新增;本地独有的条目保留。'**
  String mergeWithConflicts(int n);

  /// No description provided for @mergeNoLoss.
  ///
  /// In zh, this message translates to:
  /// **'按 id 合并:本地已有的条目一个都不会丢。'**
  String get mergeNoLoss;

  /// No description provided for @clearSelection.
  ///
  /// In zh, this message translates to:
  /// **'取消选择'**
  String get clearSelection;

  /// No description provided for @closeMenu.
  ///
  /// In zh, this message translates to:
  /// **'关闭菜单'**
  String get closeMenu;

  /// No description provided for @floatCardsColor.
  ///
  /// In zh, this message translates to:
  /// **'浮卡 {color}'**
  String floatCardsColor(String color);

  /// No description provided for @colorBlue.
  ///
  /// In zh, this message translates to:
  /// **'蓝'**
  String get colorBlue;

  /// No description provided for @colorOrange.
  ///
  /// In zh, this message translates to:
  /// **'橙'**
  String get colorOrange;

  /// No description provided for @colorPink.
  ///
  /// In zh, this message translates to:
  /// **'粉'**
  String get colorPink;

  /// No description provided for @colorPurple.
  ///
  /// In zh, this message translates to:
  /// **'紫'**
  String get colorPurple;

  /// No description provided for @colorGreen.
  ///
  /// In zh, this message translates to:
  /// **'绿'**
  String get colorGreen;

  /// No description provided for @colorGold.
  ///
  /// In zh, this message translates to:
  /// **'金'**
  String get colorGold;

  /// No description provided for @colorLightBlue.
  ///
  /// In zh, this message translates to:
  /// **'浅蓝'**
  String get colorLightBlue;

  /// No description provided for @colorTeal.
  ///
  /// In zh, this message translates to:
  /// **'青'**
  String get colorTeal;

  /// No description provided for @switchedToFloat.
  ///
  /// In zh, this message translates to:
  /// **'已换成浮卡,可在「外观与触感」换回'**
  String get switchedToFloat;

  /// No description provided for @switchBack.
  ///
  /// In zh, this message translates to:
  /// **'换回'**
  String get switchBack;

  /// No description provided for @tryNewTheme.
  ///
  /// In zh, this message translates to:
  /// **'试试新主题？'**
  String get tryNewTheme;

  /// No description provided for @newThemeBody.
  ///
  /// In zh, this message translates to:
  /// **'全新外观上线啦!卡片更清爽,挑个喜欢的吧~'**
  String get newThemeBody;

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'以后再说'**
  String get later;

  /// No description provided for @tryIt.
  ///
  /// In zh, this message translates to:
  /// **'试试'**
  String get tryIt;

  /// No description provided for @backup.
  ///
  /// In zh, this message translates to:
  /// **'备份'**
  String get backup;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @accountAccess.
  ///
  /// In zh, this message translates to:
  /// **'账号与接入'**
  String get accountAccess;

  /// No description provided for @accountAccessSub.
  ///
  /// In zh, this message translates to:
  /// **'Token 与 Bot 授权'**
  String get accountAccessSub;

  /// No description provided for @stats.
  ///
  /// In zh, this message translates to:
  /// **'统计'**
  String get stats;

  /// No description provided for @statsSub.
  ///
  /// In zh, this message translates to:
  /// **'用量 · 钱包 · 全平台统计'**
  String get statsSub;

  /// No description provided for @promptPresetsSub.
  ///
  /// In zh, this message translates to:
  /// **'正负面提示词模板'**
  String get promptPresetsSub;

  /// No description provided for @genSettingsSub.
  ///
  /// In zh, this message translates to:
  /// **'自动重试 · 功能模块 · 默认保存'**
  String get genSettingsSub;

  /// No description provided for @toolbox.
  ///
  /// In zh, this message translates to:
  /// **'工具箱'**
  String get toolbox;

  /// No description provided for @toolboxSub.
  ///
  /// In zh, this message translates to:
  /// **'权重转换 · 图片元数据'**
  String get toolboxSub;

  /// No description provided for @appearanceHaptics.
  ///
  /// In zh, this message translates to:
  /// **'外观与触感'**
  String get appearanceHaptics;

  /// No description provided for @appearanceSub.
  ///
  /// In zh, this message translates to:
  /// **'主题配色 · 振动反馈'**
  String get appearanceSub;

  /// No description provided for @storage.
  ///
  /// In zh, this message translates to:
  /// **'存储管理'**
  String get storage;

  /// No description provided for @storageSub.
  ///
  /// In zh, this message translates to:
  /// **'空间占用与清理'**
  String get storageSub;

  /// No description provided for @themeMode.
  ///
  /// In zh, this message translates to:
  /// **'深浅模式'**
  String get themeMode;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @themeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题色'**
  String get themeColor;

  /// No description provided for @bottomNav.
  ///
  /// In zh, this message translates to:
  /// **'底部导航'**
  String get bottomNav;

  /// No description provided for @showAssistant.
  ///
  /// In zh, this message translates to:
  /// **'显示 AI 助手'**
  String get showAssistant;

  /// No description provided for @showAssistantSub.
  ///
  /// In zh, this message translates to:
  /// **'关掉后底栏不再显示 AI 入口'**
  String get showAssistantSub;

  /// No description provided for @createPage.
  ///
  /// In zh, this message translates to:
  /// **'创作页'**
  String get createPage;

  /// No description provided for @compactCharCards.
  ///
  /// In zh, this message translates to:
  /// **'紧凑角色卡'**
  String get compactCharCards;

  /// No description provided for @haptics.
  ///
  /// In zh, this message translates to:
  /// **'触感'**
  String get haptics;

  /// No description provided for @hapticFeedback.
  ///
  /// In zh, this message translates to:
  /// **'振动反馈'**
  String get hapticFeedback;

  /// No description provided for @galleryPicker.
  ///
  /// In zh, this message translates to:
  /// **'图库选择器'**
  String get galleryPicker;

  /// No description provided for @inApp.
  ///
  /// In zh, this message translates to:
  /// **'应用内'**
  String get inApp;

  /// No description provided for @system.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get system;

  /// No description provided for @beta.
  ///
  /// In zh, this message translates to:
  /// **'内测'**
  String get beta;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @dataResources.
  ///
  /// In zh, this message translates to:
  /// **'数据与资源'**
  String get dataResources;

  /// No description provided for @codexSource.
  ///
  /// In zh, this message translates to:
  /// **'法典图鉴'**
  String get codexSource;

  /// No description provided for @offlineDict.
  ///
  /// In zh, this message translates to:
  /// **'离线补全词库'**
  String get offlineDict;

  /// No description provided for @zhSearch.
  ///
  /// In zh, this message translates to:
  /// **'中文搜词与译名'**
  String get zhSearch;

  /// No description provided for @imageGen.
  ///
  /// In zh, this message translates to:
  /// **'图像生成'**
  String get imageGen;

  /// No description provided for @censorModel.
  ///
  /// In zh, this message translates to:
  /// **'自动打码模型'**
  String get censorModel;

  /// No description provided for @community.
  ///
  /// In zh, this message translates to:
  /// **'交流'**
  String get community;

  /// No description provided for @qqGroup.
  ///
  /// In zh, this message translates to:
  /// **'QQ 交流群'**
  String get qqGroup;

  /// No description provided for @guide.
  ///
  /// In zh, this message translates to:
  /// **'引导'**
  String get guide;

  /// No description provided for @reviewGuide.
  ///
  /// In zh, this message translates to:
  /// **'重新查看引导'**
  String get reviewGuide;

  /// No description provided for @legal.
  ///
  /// In zh, this message translates to:
  /// **'法律'**
  String get legal;

  /// No description provided for @sourceCode.
  ///
  /// In zh, this message translates to:
  /// **'源码'**
  String get sourceCode;

  /// No description provided for @license.
  ///
  /// In zh, this message translates to:
  /// **'开源协议'**
  String get license;

  /// No description provided for @thirdPartyLicenses.
  ///
  /// In zh, this message translates to:
  /// **'第三方许可'**
  String get thirdPartyLicenses;

  /// No description provided for @disclaimer.
  ///
  /// In zh, this message translates to:
  /// **'{app} 是第三方客户端,与 NovelAI 官方无关联。图像由 NovelAI 生成,账号与生成内容产生的一切责任由使用者承担。'**
  String disclaimer(String app);

  /// No description provided for @qqCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制群号 {id}'**
  String qqCopied(String id);

  /// No description provided for @cantOpenBrowserShort.
  ///
  /// In zh, this message translates to:
  /// **'打不开浏览器'**
  String get cantOpenBrowserShort;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 移动创作端'**
  String get appTagline;

  /// No description provided for @legaleseBody.
  ///
  /// In zh, this message translates to:
  /// **'本程序是自由软件,依据 GNU GPL v3 或更新版本分发。分发本程序是希望它有用,但不作任何担保。\n\n{app} 是第三方客户端,与 NovelAI 官方无关联。'**
  String legaleseBody(String app);

  /// No description provided for @noUpdateInfo.
  ///
  /// In zh, this message translates to:
  /// **'暂无更新信息'**
  String get noUpdateInfo;

  /// No description provided for @onLatestVersion.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get onLatestVersion;

  /// No description provided for @checkFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查失败'**
  String get checkFailed;

  /// No description provided for @newVersion.
  ///
  /// In zh, this message translates to:
  /// **'新版本 {v}'**
  String newVersion(String v);

  /// No description provided for @upToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新'**
  String get upToDate;

  /// No description provided for @checkUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdates;

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前 {v}'**
  String currentVersion(String v);

  /// No description provided for @downloadOnGithub.
  ///
  /// In zh, this message translates to:
  /// **'去 GitHub 下载'**
  String get downloadOnGithub;

  /// No description provided for @downloadUpdate.
  ///
  /// In zh, this message translates to:
  /// **'下载新版'**
  String get downloadUpdate;

  /// No description provided for @updateHttpFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败(HTTP {code})'**
  String updateHttpFailed(int code);

  /// No description provided for @updateBadFormat.
  ///
  /// In zh, this message translates to:
  /// **'更新信息格式异常'**
  String get updateBadFormat;

  /// No description provided for @updateTimeout.
  ///
  /// In zh, this message translates to:
  /// **'检查更新超时,请检查网络后重试'**
  String get updateTimeout;

  /// No description provided for @cantReachUpdateServer.
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器,请检查网络后重试'**
  String get cantReachUpdateServer;

  /// No description provided for @updateFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败,请稍后重试'**
  String get updateFailed;

  /// No description provided for @weightConverter.
  ///
  /// In zh, this message translates to:
  /// **'权重转换'**
  String get weightConverter;

  /// No description provided for @imageMetadata.
  ///
  /// In zh, this message translates to:
  /// **'图片元数据'**
  String get imageMetadata;

  /// No description provided for @compareImages.
  ///
  /// In zh, this message translates to:
  /// **'图片比对'**
  String get compareImages;

  /// No description provided for @swapAB.
  ///
  /// In zh, this message translates to:
  /// **'交换 A / B'**
  String get swapAB;

  /// No description provided for @onlyInA.
  ///
  /// In zh, this message translates to:
  /// **'仅 A'**
  String get onlyInA;

  /// No description provided for @onlyInB.
  ///
  /// In zh, this message translates to:
  /// **'仅 B'**
  String get onlyInB;

  /// No description provided for @weightChanged.
  ///
  /// In zh, this message translates to:
  /// **'权重不同'**
  String get weightChanged;

  /// No description provided for @orderChanged.
  ///
  /// In zh, this message translates to:
  /// **'位置不同'**
  String get orderChanged;

  /// No description provided for @identical.
  ///
  /// In zh, this message translates to:
  /// **'相同'**
  String get identical;

  /// No description provided for @identicalN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 项相同'**
  String identicalN(int n);

  /// No description provided for @differentN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 项不同'**
  String differentN(int n);

  /// No description provided for @enterOverwritePrompt.
  ///
  /// In zh, this message translates to:
  /// **'先填要覆写的提示词'**
  String get enterOverwritePrompt;

  /// No description provided for @noPhotoPermission.
  ///
  /// In zh, this message translates to:
  /// **'未获相册权限'**
  String get noPhotoPermission;

  /// No description provided for @savedToPhotos.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {n} 张到相册'**
  String savedToPhotos(int n);

  /// No description provided for @savedToPhotosFailed.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {saved} 张 · {failed} 张失败'**
  String savedToPhotosFailed(int saved, int failed);

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In zh, this message translates to:
  /// **'取消全选'**
  String get deselectAll;

  /// No description provided for @addImages.
  ///
  /// In zh, this message translates to:
  /// **'添加图片'**
  String get addImages;

  /// No description provided for @metadataToolIntro.
  ///
  /// In zh, this message translates to:
  /// **'查看生成参数 · 批量清除或覆写元数据'**
  String get metadataToolIntro;

  /// No description provided for @overwritePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'要覆写进图片的提示词…'**
  String get overwritePromptHint;

  /// No description provided for @clearMeta.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clearMeta;

  /// No description provided for @overwrite.
  ///
  /// In zh, this message translates to:
  /// **'覆写'**
  String get overwrite;

  /// No description provided for @saveToPhotosN.
  ///
  /// In zh, this message translates to:
  /// **'存相册 ({n})'**
  String saveToPhotosN(int n);

  /// No description provided for @imageInfo.
  ///
  /// In zh, this message translates to:
  /// **'图片信息'**
  String get imageInfo;

  /// No description provided for @noMetadataFor.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 未识别到元数据'**
  String noMetadataFor(String name);

  /// No description provided for @promptImported.
  ///
  /// In zh, this message translates to:
  /// **'已导入提示词'**
  String get promptImported;

  /// No description provided for @stripLora.
  ///
  /// In zh, this message translates to:
  /// **'去 Lora'**
  String get stripLora;

  /// No description provided for @convert.
  ///
  /// In zh, this message translates to:
  /// **'转换'**
  String get convert;

  /// No description provided for @importPrompt.
  ///
  /// In zh, this message translates to:
  /// **'导入提示词'**
  String get importPrompt;

  /// No description provided for @copyResult.
  ///
  /// In zh, this message translates to:
  /// **'复制结果'**
  String get copyResult;

  /// No description provided for @genNotify.
  ///
  /// In zh, this message translates to:
  /// **'生成通知'**
  String get genNotify;

  /// No description provided for @streamingGen.
  ///
  /// In zh, this message translates to:
  /// **'流式生成'**
  String get streamingGen;

  /// No description provided for @straightAlpha.
  ///
  /// In zh, this message translates to:
  /// **'透明图直通 Alpha'**
  String get straightAlpha;

  /// No description provided for @keepImageFormat.
  ///
  /// In zh, this message translates to:
  /// **'保持图片格式'**
  String get keepImageFormat;

  /// No description provided for @autoRetry.
  ///
  /// In zh, this message translates to:
  /// **'限流后自动重试'**
  String get autoRetry;

  /// No description provided for @retryDelay.
  ///
  /// In zh, this message translates to:
  /// **'重试间隔'**
  String get retryDelay;

  /// No description provided for @secondsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 秒'**
  String secondsN(int n);

  /// No description provided for @immediately.
  ///
  /// In zh, this message translates to:
  /// **'立即'**
  String get immediately;

  /// No description provided for @unitSeconds.
  ///
  /// In zh, this message translates to:
  /// **'秒'**
  String get unitSeconds;

  /// No description provided for @retryCount.
  ///
  /// In zh, this message translates to:
  /// **'重试次数'**
  String get retryCount;

  /// No description provided for @timesN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 次'**
  String timesN(int n);

  /// No description provided for @unitTimes.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get unitTimes;

  /// No description provided for @galleryDefaultSave.
  ///
  /// In zh, this message translates to:
  /// **'图库默认保存'**
  String get galleryDefaultSave;

  /// No description provided for @createPageModules.
  ///
  /// In zh, this message translates to:
  /// **'创作页模块'**
  String get createPageModules;

  /// No description provided for @modulesOn.
  ///
  /// In zh, this message translates to:
  /// **'已开 {on}/{total}'**
  String modulesOn(int on, int total);

  /// No description provided for @pngLossless.
  ///
  /// In zh, this message translates to:
  /// **'PNG 无损'**
  String get pngLossless;

  /// No description provided for @jpgLossy.
  ///
  /// In zh, this message translates to:
  /// **'JPG 有损'**
  String get jpgLossy;

  /// No description provided for @rawMetadata.
  ///
  /// In zh, this message translates to:
  /// **'原始元数据'**
  String get rawMetadata;

  /// No description provided for @compressQuality.
  ///
  /// In zh, this message translates to:
  /// **'压缩质量'**
  String get compressQuality;

  /// No description provided for @compressQualityDialog.
  ///
  /// In zh, this message translates to:
  /// **'压缩质量(10~100)'**
  String get compressQualityDialog;

  /// No description provided for @customPrompt.
  ///
  /// In zh, this message translates to:
  /// **'自定义提示词'**
  String get customPrompt;

  /// No description provided for @customPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'写入图片的提示词(其余参数清除)…'**
  String get customPromptHint;

  /// No description provided for @notSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get notSet;

  /// No description provided for @catCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存文件'**
  String get catCache;

  /// No description provided for @catVibeEnc.
  ///
  /// In zh, this message translates to:
  /// **'Vibe 编码缓存'**
  String get catVibeEnc;

  /// No description provided for @catModels.
  ///
  /// In zh, this message translates to:
  /// **'超分模型(遗留)'**
  String get catModels;

  /// No description provided for @catTagPrev.
  ///
  /// In zh, this message translates to:
  /// **'灵感预览图'**
  String get catTagPrev;

  /// No description provided for @catGallery.
  ///
  /// In zh, this message translates to:
  /// **'图库作品'**
  String get catGallery;

  /// No description provided for @catCharLib.
  ///
  /// In zh, this message translates to:
  /// **'角色参考库'**
  String get catCharLib;

  /// No description provided for @actClean.
  ///
  /// In zh, this message translates to:
  /// **'清理'**
  String get actClean;

  /// No description provided for @freedSize.
  ///
  /// In zh, this message translates to:
  /// **'已释放 {size}'**
  String freedSize(String size);

  /// No description provided for @nothingToClean.
  ///
  /// In zh, this message translates to:
  /// **'没有可清理的内容'**
  String get nothingToClean;

  /// No description provided for @cleanFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理失败: {error}'**
  String cleanFailed(String error);

  /// No description provided for @clearTagPreviews.
  ///
  /// In zh, this message translates to:
  /// **'清空灵感预览图'**
  String get clearTagPreviews;

  /// No description provided for @clearTagPreviewsBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除本机生成的条目预览图,并从条目上摘除引用;条目本身与提示词不受影响,预览需重新生成。'**
  String get clearTagPreviewsBody;

  /// No description provided for @clearTagPreviewsBodyN.
  ///
  /// In zh, this message translates to:
  /// **'将删除本机生成的 {n} 张条目预览图,并从条目上摘除引用;条目本身与提示词不受影响,预览需重新生成。'**
  String clearTagPreviewsBodyN(int n);

  /// No description provided for @clearAllAlbums.
  ///
  /// In zh, this message translates to:
  /// **'清空全部相册数据'**
  String get clearAllAlbums;

  /// No description provided for @clearAllAlbumsBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除全部作品、参数快照和自建相册及封面，不可恢复。已保存到系统相册的图片不受影响。'**
  String get clearAllAlbumsBody;

  /// No description provided for @clearAllAlbumsBodyN.
  ///
  /// In zh, this message translates to:
  /// **'将删除全部 {n} 张作品、参数快照和自建相册及封面，不可恢复。已保存到系统相册的图片不受影响。'**
  String clearAllAlbumsBodyN(int n);

  /// No description provided for @clearEncodingCache.
  ///
  /// In zh, this message translates to:
  /// **'清空编码缓存'**
  String get clearEncodingCache;

  /// No description provided for @clearEncodingCacheBody.
  ///
  /// In zh, this message translates to:
  /// **'清空后,下次用这些图生成时需重新编码;直连线路每张图约扣 2 Anlas。不影响 Vibe 库文件本身。'**
  String get clearEncodingCacheBody;

  /// No description provided for @clearVibeLib.
  ///
  /// In zh, this message translates to:
  /// **'清空 Vibe 库'**
  String get clearVibeLib;

  /// No description provided for @clearVibeLibBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除库内全部文件(原图 / 缩略图 / 已存编码),不可恢复。'**
  String get clearVibeLibBody;

  /// No description provided for @clearVibeLibBodyN.
  ///
  /// In zh, this message translates to:
  /// **'将删除库内全部 {n} 个文件(原图 / 缩略图 / 已存编码),不可恢复。'**
  String clearVibeLibBodyN(int n);

  /// No description provided for @clearCharRefLib.
  ///
  /// In zh, this message translates to:
  /// **'清空角色参考库'**
  String get clearCharRefLib;

  /// No description provided for @clearCharRefLibBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除库内全部文件,不可恢复。图库作品里的参数快照不受影响。'**
  String get clearCharRefLibBody;

  /// No description provided for @clearCharRefLibBodyN.
  ///
  /// In zh, this message translates to:
  /// **'将删除库内全部 {n} 个文件,不可恢复。图库作品里的参数快照不受影响。'**
  String clearCharRefLibBodyN(int n);

  /// No description provided for @deleteUpscaleModels.
  ///
  /// In zh, this message translates to:
  /// **'删除超分模型'**
  String get deleteUpscaleModels;

  /// No description provided for @deleteUpscaleModelsBody.
  ///
  /// In zh, this message translates to:
  /// **'本地超分功能已下线,这 {size} 模型文件已经用不上了,删掉不会少任何功能。'**
  String deleteUpscaleModelsBody(String size);

  /// No description provided for @rescan.
  ///
  /// In zh, this message translates to:
  /// **'重新扫描'**
  String get rescan;

  /// No description provided for @autoCleanLimits.
  ///
  /// In zh, this message translates to:
  /// **'自动清理上限'**
  String get autoCleanLimits;

  /// No description provided for @cleanable.
  ///
  /// In zh, this message translates to:
  /// **'可清理'**
  String get cleanable;

  /// No description provided for @totalUsage.
  ///
  /// In zh, this message translates to:
  /// **'总占用'**
  String get totalUsage;

  /// No description provided for @otherSize.
  ///
  /// In zh, this message translates to:
  /// **'其他 {size}'**
  String otherSize(String size);

  /// No description provided for @unitImages.
  ///
  /// In zh, this message translates to:
  /// **'张'**
  String get unitImages;

  /// No description provided for @unitItems.
  ///
  /// In zh, this message translates to:
  /// **'条'**
  String get unitItems;

  /// No description provided for @capOf.
  ///
  /// In zh, this message translates to:
  /// **'{label}上限'**
  String capOf(String label);

  /// No description provided for @noLimit.
  ///
  /// In zh, this message translates to:
  /// **'无上限'**
  String get noLimit;

  /// No description provided for @accountsCount.
  ///
  /// In zh, this message translates to:
  /// **'{n} 账号'**
  String accountsCount(int n);

  /// No description provided for @tokenNeededHint.
  ///
  /// In zh, this message translates to:
  /// **'直连生成需要你自己的 NovelAI 令牌,仅加密存储在本机'**
  String get tokenNeededHint;

  /// No description provided for @tokensNoneJoined.
  ///
  /// In zh, this message translates to:
  /// **'存了 {n} 把,但一把都没参与生成'**
  String tokensNoneJoined(int n);

  /// No description provided for @manageTokens.
  ///
  /// In zh, this message translates to:
  /// **'管理令牌'**
  String get manageTokens;

  /// No description provided for @naiProxy.
  ///
  /// In zh, this message translates to:
  /// **'代理访问 NovelAI'**
  String get naiProxy;

  /// No description provided for @naiProxyHint.
  ///
  /// In zh, this message translates to:
  /// **'经 Cloudflare 转发,无法访问官网时开启'**
  String get naiProxyHint;

  /// No description provided for @queryingAccount.
  ///
  /// In zh, this message translates to:
  /// **'查询账户状态…'**
  String get queryingAccount;

  /// No description provided for @quotaPct.
  ///
  /// In zh, this message translates to:
  /// **'额度 {pct}%'**
  String quotaPct(int pct);

  /// No description provided for @statusSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get statusSaved;

  /// No description provided for @genMethod.
  ///
  /// In zh, this message translates to:
  /// **'生成方式'**
  String get genMethod;

  /// No description provided for @directToken.
  ///
  /// In zh, this message translates to:
  /// **'API Token'**
  String get directToken;

  /// No description provided for @useBotAccount.
  ///
  /// In zh, this message translates to:
  /// **'使用 Bot 账户'**
  String get useBotAccount;

  /// No description provided for @tokenMissing.
  ///
  /// In zh, this message translates to:
  /// **'尚未保存 Token,当前无法生成'**
  String get tokenMissing;

  /// No description provided for @useOwnAccount.
  ///
  /// In zh, this message translates to:
  /// **'使用你的 NovelAI 账户生成图片'**
  String get useOwnAccount;

  /// No description provided for @notSubscribed.
  ///
  /// In zh, this message translates to:
  /// **'未订阅'**
  String get notSubscribed;

  /// No description provided for @tokenCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制令牌'**
  String get tokenCopied;

  /// No description provided for @deleteToken.
  ///
  /// In zh, this message translates to:
  /// **'删除令牌'**
  String get deleteToken;

  /// No description provided for @deleteTokenBody.
  ///
  /// In zh, this message translates to:
  /// **'将从本机删除「{name}」,直连能同时出的张数也会少一路。'**
  String deleteTokenBody(String name);

  /// No description provided for @tokenManage.
  ///
  /// In zh, this message translates to:
  /// **'令牌管理'**
  String get tokenManage;

  /// No description provided for @maxTokens.
  ///
  /// In zh, this message translates to:
  /// **'最多 {n} 把'**
  String maxTokens(int n);

  /// No description provided for @addToken.
  ///
  /// In zh, this message translates to:
  /// **'添加令牌'**
  String get addToken;

  /// No description provided for @noTokensYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有令牌'**
  String get noTokensYet;

  /// No description provided for @multiTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'存多把可以同时出多张 —— NAI 按账号限流,一把只能跑一条'**
  String get multiTokenHint;

  /// No description provided for @primaryAccount.
  ///
  /// In zh, this message translates to:
  /// **'主账号'**
  String get primaryAccount;

  /// No description provided for @copyToken.
  ///
  /// In zh, this message translates to:
  /// **'复制令牌'**
  String get copyToken;

  /// No description provided for @primaryAlwaysOn.
  ///
  /// In zh, this message translates to:
  /// **'生成与点数都用它,不可关闭'**
  String get primaryAlwaysOn;

  /// No description provided for @joinFree.
  ///
  /// In zh, this message translates to:
  /// **'参与免费生成'**
  String get joinFree;

  /// No description provided for @joinPaid.
  ///
  /// In zh, this message translates to:
  /// **'参与点数生成'**
  String get joinPaid;

  /// No description provided for @thirdPartyNoStatus.
  ///
  /// In zh, this message translates to:
  /// **'第三方接口未提供账户状态'**
  String get thirdPartyNoStatus;

  /// No description provided for @tokenExpired.
  ///
  /// In zh, this message translates to:
  /// **'令牌已失效'**
  String get tokenExpired;

  /// No description provided for @statusQueryFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'状态查询失败,点按重试'**
  String get statusQueryFailedRetry;

  /// No description provided for @maxTokensSaved.
  ///
  /// In zh, this message translates to:
  /// **'最多保存 {n} 把令牌'**
  String maxTokensSaved(int n);

  /// No description provided for @loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败:{error}'**
  String loginFailed(String error);

  /// No description provided for @urlNeedsHttp.
  ///
  /// In zh, this message translates to:
  /// **'请填 http:// 或 https:// 开头的接口地址'**
  String get urlNeedsHttp;

  /// No description provided for @pasteToken.
  ///
  /// In zh, this message translates to:
  /// **'粘贴令牌'**
  String get pasteToken;

  /// No description provided for @emailLogin.
  ///
  /// In zh, this message translates to:
  /// **'邮箱登录'**
  String get emailLogin;

  /// No description provided for @thirdParty.
  ///
  /// In zh, this message translates to:
  /// **'第三方'**
  String get thirdParty;

  /// No description provided for @thirdPartyApi.
  ///
  /// In zh, this message translates to:
  /// **'第三方接口'**
  String get thirdPartyApi;

  /// No description provided for @loginAndAdd.
  ///
  /// In zh, this message translates to:
  /// **'登录并添加'**
  String get loginAndAdd;

  /// No description provided for @tokenWhere.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 网站 → User Settings → Account → Get Persistent API Token。'**
  String get tokenWhere;

  /// No description provided for @needNaiAccess.
  ///
  /// In zh, this message translates to:
  /// **'直连生成需要你的网络可以访问 NovelAI 官网。'**
  String get needNaiAccess;

  /// No description provided for @sentenceJoin.
  ///
  /// In zh, this message translates to:
  /// **''**
  String get sentenceJoin;

  /// No description provided for @pasteTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴 pst-… 令牌或网页 eyJ… JWT'**
  String get pasteTokenHint;

  /// No description provided for @paste.
  ///
  /// In zh, this message translates to:
  /// **'粘贴'**
  String get paste;

  /// No description provided for @show.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get hide;

  /// No description provided for @storedEncryptedLocal.
  ///
  /// In zh, this message translates to:
  /// **'仅加密存储在本机'**
  String get storedEncryptedLocal;

  /// No description provided for @apiKey.
  ///
  /// In zh, this message translates to:
  /// **'接口 key'**
  String get apiKey;

  /// No description provided for @passwordLocalHint.
  ///
  /// In zh, this message translates to:
  /// **'密码只在本机参与密钥计算,不上传也不保存;登录得到 30 天有效的令牌,到期前 App 会自动换新。'**
  String get passwordLocalHint;

  /// No description provided for @email.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get email;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @formatNai.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 格式'**
  String get formatNai;

  /// No description provided for @formatNaiHint.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 接口格式：/ai/generate-image'**
  String get formatNaiHint;

  /// No description provided for @formatOpenai.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI 格式'**
  String get formatOpenai;

  /// No description provided for @formatOpenaiHint.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI 接口格式：/v1/chat/completions'**
  String get formatOpenaiHint;

  /// No description provided for @naiAccountLogin.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 账号登录'**
  String get naiAccountLogin;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @tokenInvalid.
  ///
  /// In zh, this message translates to:
  /// **'令牌无效'**
  String get tokenInvalid;

  /// No description provided for @accountQueryFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'账户状态查询失败,点按重试'**
  String get accountQueryFailedRetry;

  /// No description provided for @networkError.
  ///
  /// In zh, this message translates to:
  /// **'网络错误:{error}'**
  String networkError(String error);

  /// No description provided for @wrongCredentials.
  ///
  /// In zh, this message translates to:
  /// **'邮箱或密码错误'**
  String get wrongCredentials;

  /// No description provided for @loginHttpFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败(HTTP {code})'**
  String loginHttpFailed(int code);

  /// No description provided for @loginNoToken.
  ///
  /// In zh, this message translates to:
  /// **'登录响应缺少 accessToken'**
  String get loginNoToken;

  /// No description provided for @getStarted.
  ///
  /// In zh, this message translates to:
  /// **'开始使用'**
  String get getStarted;

  /// No description provided for @enableNotifications.
  ///
  /// In zh, this message translates to:
  /// **'开启通知'**
  String get enableNotifications;

  /// No description provided for @next.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get next;

  /// No description provided for @notNow.
  ///
  /// In zh, this message translates to:
  /// **'暂不开启'**
  String get notNow;

  /// No description provided for @skipForNow.
  ///
  /// In zh, this message translates to:
  /// **'暂时跳过'**
  String get skipForNow;

  /// No description provided for @welcomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用 Plana'**
  String get welcomeTitle;

  /// No description provided for @featEditor.
  ///
  /// In zh, this message translates to:
  /// **'全屏提示词编辑器'**
  String get featEditor;

  /// No description provided for @featGallery.
  ///
  /// In zh, this message translates to:
  /// **'图库留参数,随时复现'**
  String get featGallery;

  /// No description provided for @featTools.
  ///
  /// In zh, this message translates to:
  /// **'Vibe · 参考 · 重绘 · 超分'**
  String get featTools;

  /// No description provided for @appearanceColors.
  ///
  /// In zh, this message translates to:
  /// **'外观配色'**
  String get appearanceColors;

  /// No description provided for @accessMethod.
  ///
  /// In zh, this message translates to:
  /// **'生成接入方式'**
  String get accessMethod;

  /// No description provided for @subscriptionRequired.
  ///
  /// In zh, this message translates to:
  /// **'必须拥有官方或中转订阅才能进行生成'**
  String get subscriptionRequired;

  /// No description provided for @directNaiToken.
  ///
  /// In zh, this message translates to:
  /// **'官方订阅'**
  String get directNaiToken;

  /// No description provided for @official.
  ///
  /// In zh, this message translates to:
  /// **'官方'**
  String get official;

  /// No description provided for @noTokenUseLogin.
  ///
  /// In zh, this message translates to:
  /// **'没有令牌?用邮箱密码登录'**
  String get noTokenUseLogin;

  /// No description provided for @notifyTitle.
  ///
  /// In zh, this message translates to:
  /// **'生成进度通知'**
  String get notifyTitle;

  /// No description provided for @notifyDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后可接收生成进度及完成通知,Android 16+ 支持灵动岛显示'**
  String get notifyDesc;

  /// No description provided for @allDone.
  ///
  /// In zh, this message translates to:
  /// **'全部完成'**
  String get allDone;

  /// No description provided for @channelProgress.
  ///
  /// In zh, this message translates to:
  /// **'生成进度'**
  String get channelProgress;

  /// No description provided for @channelProgressDesc.
  ///
  /// In zh, this message translates to:
  /// **'生成期间的常驻进度条(静默)'**
  String get channelProgressDesc;

  /// No description provided for @channelDone.
  ///
  /// In zh, this message translates to:
  /// **'生成完成'**
  String get channelDone;

  /// No description provided for @channelDoneDesc.
  ///
  /// In zh, this message translates to:
  /// **'出图 / 队列 / 循环结束时提醒一次'**
  String get channelDoneDesc;

  /// No description provided for @cloudBackup.
  ///
  /// In zh, this message translates to:
  /// **'Plana 云端'**
  String get cloudBackup;

  /// No description provided for @backupToCloud.
  ///
  /// In zh, this message translates to:
  /// **'备份到 Plana 云端'**
  String get backupToCloud;

  /// No description provided for @restoreFromCloud.
  ///
  /// In zh, this message translates to:
  /// **'从 Plana 云端恢复'**
  String get restoreFromCloud;

  /// No description provided for @selectBackupFile.
  ///
  /// In zh, this message translates to:
  /// **'选择备份文件'**
  String get selectBackupFile;

  /// No description provided for @notBackupFile.
  ///
  /// In zh, this message translates to:
  /// **'不是可识别的备份文件'**
  String get notBackupFile;

  /// No description provided for @importComplete.
  ///
  /// In zh, this message translates to:
  /// **'导入完成'**
  String get importComplete;

  /// No description provided for @importCompleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入完成,{n} 项失败'**
  String importCompleteFailed(int n);

  /// No description provided for @notValidJson.
  ///
  /// In zh, this message translates to:
  /// **'不是有效的 JSON 文件'**
  String get notValidJson;

  /// No description provided for @importFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败:{error}'**
  String importFailed(String error);

  /// No description provided for @webBackupEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这份 web 备份里没有可导入的内容'**
  String get webBackupEmpty;

  /// No description provided for @customCatMissing.
  ///
  /// In zh, this message translates to:
  /// **'文件里的自定义分类在本机不存在'**
  String get customCatMissing;

  /// No description provided for @fileNoEntries.
  ///
  /// In zh, this message translates to:
  /// **'文件里没有条目'**
  String get fileNoEntries;

  /// No description provided for @inspirationOf.
  ///
  /// In zh, this message translates to:
  /// **'灵感库 · {cat}'**
  String inspirationOf(String cat);

  /// No description provided for @chooseImportContent.
  ///
  /// In zh, this message translates to:
  /// **'选择要导入的内容'**
  String get chooseImportContent;

  /// No description provided for @itemsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 条'**
  String itemsN(int n);

  /// No description provided for @addedUpdated.
  ///
  /// In zh, this message translates to:
  /// **'新增 {a} · 覆盖 {u}'**
  String addedUpdated(int a, int u);

  /// No description provided for @exportedNOf.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {n} 个{cat}'**
  String exportedNOf(int n, String cat);

  /// No description provided for @processing.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get processing;

  /// No description provided for @importResult.
  ///
  /// In zh, this message translates to:
  /// **'导入结果'**
  String get importResult;

  /// No description provided for @dupImagesSkipped.
  ///
  /// In zh, this message translates to:
  /// **'重复图自动跳过'**
  String get dupImagesSkipped;

  /// No description provided for @embeddedPreviewsSkipped.
  ///
  /// In zh, this message translates to:
  /// **'内嵌预览图不导入'**
  String get embeddedPreviewsSkipped;

  /// No description provided for @vibeImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'Vibe 导入失败: {error}'**
  String vibeImportFailed(String error);

  /// No description provided for @charRefImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'角色参考「{name}」失败: {error}'**
  String charRefImportFailed(String name, String error);

  /// No description provided for @inspirationImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'灵感库导入失败: {error}'**
  String inspirationImportFailed(String error);

  /// No description provided for @presetImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'预设导入失败: {error}'**
  String presetImportFailed(String error);

  /// No description provided for @notValidBackup.
  ///
  /// In zh, this message translates to:
  /// **'不是有效的备份文件'**
  String get notValidBackup;

  /// No description provided for @backupIdMismatch.
  ///
  /// In zh, this message translates to:
  /// **'无效的备份文件:文件标识不匹配'**
  String get backupIdMismatch;

  /// No description provided for @backupVersionUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'不支持的备份版本:{ver}(本 app 支持 v{supported})'**
  String backupVersionUnsupported(String ver, String supported);

  /// No description provided for @backupIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'无效的备份文件:数据结构不完整'**
  String get backupIncomplete;

  /// No description provided for @fileReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件读取失败'**
  String get fileReadFailed;

  /// No description provided for @fileEmpty.
  ///
  /// In zh, this message translates to:
  /// **'文件是空的'**
  String get fileEmpty;

  /// No description provided for @genCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消生成'**
  String get genCancelled;

  /// No description provided for @streamBadFrame.
  ///
  /// In zh, this message translates to:
  /// **'流数据格式异常(帧长 {len})'**
  String streamBadFrame(String len);

  /// No description provided for @genFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'生成失败(code {code})'**
  String genFailedCode(String code);

  /// No description provided for @noImageFrame.
  ///
  /// In zh, this message translates to:
  /// **'未收到图片帧(收到 {bytes} 字节)'**
  String noImageFrame(int bytes);

  /// No description provided for @noImageFrameParse.
  ///
  /// In zh, this message translates to:
  /// **'未收到图片帧(收到 {bytes} 字节,{fails} 帧解析失败:{err})'**
  String noImageFrameParse(int bytes, int fails, String err);

  /// No description provided for @genTimeout.
  ///
  /// In zh, this message translates to:
  /// **'生成超时,请重试'**
  String get genTimeout;

  /// No description provided for @cantConnect.
  ///
  /// In zh, this message translates to:
  /// **'无法连接 {host}:{msg}'**
  String cantConnect(String host, String msg);

  /// No description provided for @tlsFailed.
  ///
  /// In zh, this message translates to:
  /// **'TLS 握手失败,当前网络可能拦截了 {host}'**
  String tlsFailed(String host);

  /// No description provided for @streamGenFailed.
  ///
  /// In zh, this message translates to:
  /// **'流式生成失败:{error}'**
  String streamGenFailed(String error);

  /// No description provided for @unzipFailed.
  ///
  /// In zh, this message translates to:
  /// **'解压结果失败:{error}'**
  String unzipFailed(String error);

  /// No description provided for @noImageInResult.
  ///
  /// In zh, this message translates to:
  /// **'结果中未找到图片'**
  String get noImageInResult;

  /// No description provided for @apiNoUpscale.
  ///
  /// In zh, this message translates to:
  /// **'这个接口没有超分'**
  String get apiNoUpscale;

  /// No description provided for @apiNoAccountStatus.
  ///
  /// In zh, this message translates to:
  /// **'这个接口不提供账户状态'**
  String get apiNoAccountStatus;

  /// No description provided for @apiNoVibe.
  ///
  /// In zh, this message translates to:
  /// **'这个接口没有 Vibe 编码'**
  String get apiNoVibe;

  /// No description provided for @vibeEncodeFailed.
  ///
  /// In zh, this message translates to:
  /// **'编码参考图失败:{error}'**
  String vibeEncodeFailed(String error);

  /// No description provided for @http401.
  ///
  /// In zh, this message translates to:
  /// **'Token 无效或已过期'**
  String get http401;

  /// No description provided for @http402.
  ///
  /// In zh, this message translates to:
  /// **'订阅 / 点数不足'**
  String get http402;

  /// No description provided for @http429.
  ///
  /// In zh, this message translates to:
  /// **'并发过多或触发限流,请稍后重试'**
  String get http429;

  /// No description provided for @httpFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败(HTTP {code})'**
  String httpFailed(int code);

  /// No description provided for @notJsonResponse.
  ///
  /// In zh, this message translates to:
  /// **'接口返回的不是 JSON'**
  String get notJsonResponse;

  /// No description provided for @noImageData.
  ///
  /// In zh, this message translates to:
  /// **'未收到图片数据'**
  String get noImageData;

  /// No description provided for @helpCanvasTitle.
  ///
  /// In zh, this message translates to:
  /// **'画布'**
  String get helpCanvasTitle;

  /// No description provided for @helpCanvasBody.
  ///
  /// In zh, this message translates to:
  /// **'每张画布各存一套提示词和出图参数，随时切换。\n· 只有张数和循环档位是所有画布共用的\n💡 切换画布不影响进行中的出图\n💡「历史」保留最近 50 次出图，可恢复'**
  String get helpCanvasBody;

  /// No description provided for @helpResolutionTitle.
  ///
  /// In zh, this message translates to:
  /// **'分辨率'**
  String get helpResolutionTitle;

  /// No description provided for @helpResolutionBody.
  ///
  /// In zh, this message translates to:
  /// **'按总像素(宽 × 高)分档:\n· 免费 → ≤ 1024×1024,即绿线以内;需 Opus 订阅、步数 ≤28\n· 消耗点数 → 超出绿线,尺寸越大越贵\n· 超出上限 → 超过 1024×3072(红线),无法生成'**
  String get helpResolutionBody;

  /// No description provided for @helpImg2imgStrengthTitle.
  ///
  /// In zh, this message translates to:
  /// **'图生图强度 (Strength)'**
  String get helpImg2imgStrengthTitle;

  /// No description provided for @helpImg2imgStrengthBody.
  ///
  /// In zh, this message translates to:
  /// **'控制原图对最终画面的影响程度。\n· 值越低 → 越接近原图，改动越少\n· 值越高 → 越自由发挥，重绘越多\n💡 0.01 时几乎不重绘；与 Noise 同时调到最低 → 完美复制原图\n💡 AI 过度忽略提示词时，可尝试提高 Prompt Guidance'**
  String get helpImg2imgStrengthBody;

  /// No description provided for @helpImg2imgNoiseTitle.
  ///
  /// In zh, this message translates to:
  /// **'噪声 (Noise)'**
  String get helpImg2imgNoiseTitle;

  /// No description provided for @helpImg2imgNoiseBody.
  ///
  /// In zh, this message translates to:
  /// **'在原图基础上额外注入随机扰动。\n· 0 → 完全基于原图，结果更稳定\n· 值越高 → 增加创作自由度，更多新元素\n💡 原图大面积空白时，调高可让 AI 主动补充细节\n💡 高 Noise 反复重生成可能产生视觉瑕疵'**
  String get helpImg2imgNoiseBody;

  /// No description provided for @helpVibeStrengthTitle.
  ///
  /// In zh, this message translates to:
  /// **'风格强度 (Reference Strength)'**
  String get helpVibeStrengthTitle;

  /// No description provided for @helpVibeStrengthBody.
  ///
  /// In zh, this message translates to:
  /// **'控制 Vibe 风格对画面的影响力度。\n· 值越高 → 越接近参考图的风格、配色等视觉线索\n· 值越低 → 仅作轻微风格指引\n💡 多个 Vibe 同时使用时，强度总和建议 ≤ 1\n💡 过高时 AI 会开始忽略文字 prompt'**
  String get helpVibeStrengthBody;

  /// No description provided for @helpNormalizeVibeTitle.
  ///
  /// In zh, this message translates to:
  /// **'均衡强度 (Normalize)'**
  String get helpNormalizeVibeTitle;

  /// No description provided for @helpNormalizeVibeBody.
  ///
  /// In zh, this message translates to:
  /// **'开启 → 所有 Vibe 的强度按比例缩小，合计强度 ≤ 1\n关闭 → 每个 Vibe 的强度独立相加'**
  String get helpNormalizeVibeBody;

  /// No description provided for @helpInfoExtractedTitle.
  ///
  /// In zh, this message translates to:
  /// **'信息提取 (Information Extracted)'**
  String get helpInfoExtractedTitle;

  /// No description provided for @helpInfoExtractedBody.
  ///
  /// In zh, this message translates to:
  /// **'从原图中提取的信息量。\n· 值越低 → 先丢失高频细节（纹理、风格），优先保留构图\n· 值越高 → 同时保留构图与纹理 / 风格细节\n💡 设置为新值时扣 2 点数，使用历史值时免费\n💡 无原图时无法重设该值'**
  String get helpInfoExtractedBody;

  /// No description provided for @helpCharRefStrengthTitle.
  ///
  /// In zh, this message translates to:
  /// **'参考强度 (Strength)'**
  String get helpCharRefStrengthTitle;

  /// No description provided for @helpCharRefStrengthBody.
  ///
  /// In zh, this message translates to:
  /// **'控制角色 / 风格参考对画面的整体影响力。\n· 值越高 → 越严格还原参考图特征\n· 值越低 → 参考图仅作弱引导\n💡 每张图额外消耗 5 Anlas，多个 PR 累加\n💡 过高时面部表情 / 角度 / 姿势会过度贴近参考图'**
  String get helpCharRefStrengthBody;

  /// No description provided for @helpFidelityTitle.
  ///
  /// In zh, this message translates to:
  /// **'还原度 (Fidelity)'**
  String get helpFidelityTitle;

  /// No description provided for @helpFidelityBody.
  ///
  /// In zh, this message translates to:
  /// **'控制 prompt 能否压过参考图。\n· 值越高 → 参考图占主导，prompt 难以改变它\n· 值越低 → prompt 占主导，更易调整画面\n💡 实际效果可能因图而异，建议多尝试'**
  String get helpFidelityBody;

  /// No description provided for @helpStepsTitle.
  ///
  /// In zh, this message translates to:
  /// **'采样步数 (Steps)'**
  String get helpStepsTitle;

  /// No description provided for @helpStepsBody.
  ///
  /// In zh, this message translates to:
  /// **'采样步数，控制去噪迭代次数。\n步数越高画面越精细，但生成越慢。\n步数过多反而收益递减，甚至适得其反。\n💡 步数 ≤28 时不额外消耗 Anlas'**
  String get helpStepsBody;

  /// No description provided for @helpCfgTitle.
  ///
  /// In zh, this message translates to:
  /// **'提示词引导强度 (CFG Scale)'**
  String get helpCfgTitle;

  /// No description provided for @helpCfgBody.
  ///
  /// In zh, this message translates to:
  /// **'控制 AI 对提示词的遵循程度。\n· 值越低 → AI 越自由发挥，画面更绘画感、柔和、梦幻\n· 值越高 → 越严格遵循描述，细节更精细锐利\n💡 V3 及以上模型官方推荐 5~6\n💡 过高反而会反作用，色彩过饱和、画面崩坏'**
  String get helpCfgBody;

  /// No description provided for @helpVarietyPlusTitle.
  ///
  /// In zh, this message translates to:
  /// **'多样性增强模式 (Variety+)'**
  String get helpVarietyPlusTitle;

  /// No description provided for @helpVarietyPlusBody.
  ///
  /// In zh, this message translates to:
  /// **'轻微调整采样过程，提升构图与姿势的多样性。\n开启 → 增加构图和姿势的变化\n关闭 → 出图更稳定一致\n💡 在低 Prompt Guidance 下效果更明显'**
  String get helpVarietyPlusBody;

  /// No description provided for @helpSamplerTitle.
  ///
  /// In zh, this message translates to:
  /// **'采样算法 (Sampler)'**
  String get helpSamplerTitle;

  /// No description provided for @helpSamplerBody.
  ///
  /// In zh, this message translates to:
  /// **'决定去噪路径，影响画面风格与稳定性。\n· Euler Ancestral — 经典万能，随机性高\n· Euler — 确定性版本，构图更稳定\n· DPM++ 2S Ancestral — 细节丰富\n· DPM++ 2M SDE — 高质量 + 随机性\n· DPM++ 2M — 高质量确定性采样\n· DPM++ SDE — 兼具细节与多样性\n💡 建议保持默认或推荐 DPM++ 2M / Euler Ancestral\n💡 不同 sampler 的差异在低 Steps 时更明显'**
  String get helpSamplerBody;

  /// No description provided for @helpNoiseScheduleTitle.
  ///
  /// In zh, this message translates to:
  /// **'噪声衰减曲线 (Noise Schedule)'**
  String get helpNoiseScheduleTitle;

  /// No description provided for @helpNoiseScheduleBody.
  ///
  /// In zh, this message translates to:
  /// **'决定 Sampler 在每一步的噪声衰减节奏，影响画面质感。\n· karras — 最常用，出图稳定细节好\n· exponential — 指数衰减，对比度更强\n· polyexponential — 多项式衰减，过渡平滑\n💡建议保持默认 karras'**
  String get helpNoiseScheduleBody;

  /// No description provided for @helpSeedTitle.
  ///
  /// In zh, this message translates to:
  /// **'随机种子 (Seed)'**
  String get helpSeedTitle;

  /// No description provided for @helpSeedBody.
  ///
  /// In zh, this message translates to:
  /// **'随机种子，决定初始噪声。\n相同种子 + 相同参数 → 基本一致的画面\n适合微调时锁定构图。\n留空 → 每次随机生成不同结果\n💡 sampler 本身有微小随机性，相同种子也可能存在细微差别\n💡 NAI / Anima / Krea 三者的 seed 互不通用，与外部 Stable Diffusion 也不通用'**
  String get helpSeedBody;

  /// No description provided for @helpCfgRescaleTitle.
  ///
  /// In zh, this message translates to:
  /// **'CFG 引导修正系数 (Rescale)'**
  String get helpCfgRescaleTitle;

  /// No description provided for @helpCfgRescaleBody.
  ///
  /// In zh, this message translates to:
  /// **'抑制高引导值带来的过饱和与色彩溢出。\n0 = 不修正，值越高 → 修正越强\n通常保持 0；Guidance >7 时可尝试 0.1~0.3\n💡 画面出现「边缘色彩过强 / 油炸感 (deepfried)」时调高'**
  String get helpCfgRescaleBody;

  /// No description provided for @allAlbumsName.
  ///
  /// In zh, this message translates to:
  /// **'全部相册'**
  String get allAlbumsName;

  /// No description provided for @trashName.
  ///
  /// In zh, this message translates to:
  /// **'回收站'**
  String get trashName;

  /// No description provided for @albumNameInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 1–40 个字符的相册名称'**
  String get albumNameInvalid;

  /// No description provided for @albumNameExists.
  ///
  /// In zh, this message translates to:
  /// **'这个相册名称已存在'**
  String get albumNameExists;

  /// No description provided for @cantRenameFav.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」不能改名'**
  String cantRenameFav(String name);

  /// No description provided for @cantDeleteFav.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」不能删除'**
  String cantDeleteFav(String name);

  /// No description provided for @cantBrowseFav.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」不能作为浏览相册'**
  String cantBrowseFav(String name);

  /// No description provided for @cantSaveFav.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」不能设为保存相册'**
  String cantSaveFav(String name);

  /// No description provided for @albumDeleted.
  ///
  /// In zh, this message translates to:
  /// **'相册已被删除'**
  String get albumDeleted;

  /// No description provided for @imageWasDeleted.
  ///
  /// In zh, this message translates to:
  /// **'图片已被删除'**
  String get imageWasDeleted;

  /// No description provided for @galleryGone.
  ///
  /// In zh, this message translates to:
  /// **'图库已不存在，请重新选择'**
  String get galleryGone;

  /// No description provided for @chooseDifferentAlbums.
  ///
  /// In zh, this message translates to:
  /// **'请选择不同的来源和目标图库'**
  String get chooseDifferentAlbums;

  /// No description provided for @albumsRestored.
  ///
  /// In zh, this message translates to:
  /// **'相册数据已从最近一次备份恢复'**
  String get albumsRestored;

  /// No description provided for @albumsUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'相册归属数据暂时无法读取，原文件已保留；全部相册仍可查看'**
  String get albumsUnreadable;

  /// No description provided for @albumsReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'相册数据需要恢复，暂时不能修改'**
  String get albumsReadOnly;

  /// No description provided for @favorited.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get favorited;

  /// No description provided for @unfavoritedSnack.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏'**
  String get unfavoritedSnack;

  /// No description provided for @saveTo.
  ///
  /// In zh, this message translates to:
  /// **'保存到'**
  String get saveTo;

  /// No description provided for @chooseAlbum.
  ///
  /// In zh, this message translates to:
  /// **'选择相册'**
  String get chooseAlbum;

  /// No description provided for @moveTo.
  ///
  /// In zh, this message translates to:
  /// **'移动到'**
  String get moveTo;

  /// No description provided for @newAlbum.
  ///
  /// In zh, this message translates to:
  /// **'新建相册'**
  String get newAlbum;

  /// No description provided for @renameAlbum.
  ///
  /// In zh, this message translates to:
  /// **'重命名相册'**
  String get renameAlbum;

  /// No description provided for @albumName.
  ///
  /// In zh, this message translates to:
  /// **'相册名称'**
  String get albumName;

  /// No description provided for @setAsSaveAlbum.
  ///
  /// In zh, this message translates to:
  /// **'设为保存相册'**
  String get setAsSaveAlbum;

  /// No description provided for @dateLabel.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get dateLabel;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @earlier.
  ///
  /// In zh, this message translates to:
  /// **'更早'**
  String get earlier;

  /// No description provided for @last7Days.
  ///
  /// In zh, this message translates to:
  /// **'近 7 天'**
  String get last7Days;

  /// No description provided for @last30Days.
  ///
  /// In zh, this message translates to:
  /// **'近 30 天'**
  String get last30Days;

  /// No description provided for @dayMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String dayMonthDay(String month, int day);

  /// No description provided for @dayYearMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日'**
  String dayYearMonthDay(int year, String month, int day);

  /// No description provided for @groupByTime.
  ///
  /// In zh, this message translates to:
  /// **'按时间'**
  String get groupByTime;

  /// No description provided for @groupByCharacter.
  ///
  /// In zh, this message translates to:
  /// **'按角色'**
  String get groupByCharacter;

  /// No description provided for @groupByStyle.
  ///
  /// In zh, this message translates to:
  /// **'按画风'**
  String get groupByStyle;

  /// No description provided for @ungrouped.
  ///
  /// In zh, this message translates to:
  /// **'未归类'**
  String get ungrouped;

  /// No description provided for @hintSaveLongPress.
  ///
  /// In zh, this message translates to:
  /// **'长按「保存」可进入下载设置'**
  String get hintSaveLongPress;

  /// No description provided for @hintStripSwipe.
  ///
  /// In zh, this message translates to:
  /// **'底部胶片条里的图,向上滑可以分享、收藏或删除'**
  String get hintStripSwipe;

  /// No description provided for @nothingToShare.
  ///
  /// In zh, this message translates to:
  /// **'没有可分享的图片'**
  String get nothingToShare;

  /// No description provided for @backToHistory.
  ///
  /// In zh, this message translates to:
  /// **'返回历史'**
  String get backToHistory;

  /// No description provided for @savedToNamed.
  ///
  /// In zh, this message translates to:
  /// **'已保存到 {name}'**
  String savedToNamed(String name);

  /// No description provided for @browseAlbums.
  ///
  /// In zh, this message translates to:
  /// **'浏览相册'**
  String get browseAlbums;

  /// No description provided for @movedToTrash.
  ///
  /// In zh, this message translates to:
  /// **'已移到回收站'**
  String get movedToTrash;

  /// No description provided for @albumEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个相册还没有照片'**
  String get albumEmpty;

  /// No description provided for @noWorksYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有作品'**
  String get noWorksYet;

  /// No description provided for @viewTrash.
  ///
  /// In zh, this message translates to:
  /// **'查看回收站'**
  String get viewTrash;

  /// No description provided for @goCreateFirst.
  ///
  /// In zh, this message translates to:
  /// **'去「创作」生成第一张'**
  String get goCreateFirst;

  /// No description provided for @savedAllAlbumFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片已保存在全部作品，目标图库不可用或归类失败'**
  String get savedAllAlbumFailed;

  /// No description provided for @deletedAlbumCleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片已删除，图库归属清理失败'**
  String get deletedAlbumCleanupFailed;

  /// No description provided for @upscaleV5.
  ///
  /// In zh, this message translates to:
  /// **'V5 超分'**
  String get upscaleV5;

  /// No description provided for @redrawUpscale.
  ///
  /// In zh, this message translates to:
  /// **'重绘放大'**
  String get redrawUpscale;

  /// No description provided for @encodingImage.
  ///
  /// In zh, this message translates to:
  /// **'编码图片…'**
  String get encodingImage;

  /// No description provided for @uploadingNai.
  ///
  /// In zh, this message translates to:
  /// **'上传 NAI…'**
  String get uploadingNai;

  /// No description provided for @noPaidToken.
  ///
  /// In zh, this message translates to:
  /// **'没有可用于付费操作的 NAI Token'**
  String get noPaidToken;

  /// No description provided for @receivingResult.
  ///
  /// In zh, this message translates to:
  /// **'接收结果…'**
  String get receivingResult;

  /// No description provided for @saveToPhoneAlbum.
  ///
  /// In zh, this message translates to:
  /// **'保存到手机相册'**
  String get saveToPhoneAlbum;

  /// No description provided for @saveToPhoneAlbumBody.
  ///
  /// In zh, this message translates to:
  /// **'{n} 张将存入系统相册的「{album}」;相册不存在会自动创建。'**
  String saveToPhoneAlbumBody(int n, String album);

  /// No description provided for @albumNameExample.
  ///
  /// In zh, this message translates to:
  /// **'如 Plana 精选'**
  String get albumNameExample;

  /// No description provided for @dropToDelete.
  ///
  /// In zh, this message translates to:
  /// **'拖到这里删除'**
  String get dropToDelete;

  /// No description provided for @releaseToDelete.
  ///
  /// In zh, this message translates to:
  /// **'松手删除'**
  String get releaseToDelete;

  /// No description provided for @dropToUnfav.
  ///
  /// In zh, this message translates to:
  /// **'拖到这里取消收藏'**
  String get dropToUnfav;

  /// No description provided for @dropToFav.
  ///
  /// In zh, this message translates to:
  /// **'拖到这里收藏'**
  String get dropToFav;

  /// No description provided for @releaseToUnfav.
  ///
  /// In zh, this message translates to:
  /// **'松手取消收藏'**
  String get releaseToUnfav;

  /// No description provided for @releaseToFav.
  ///
  /// In zh, this message translates to:
  /// **'松手收藏'**
  String get releaseToFav;

  /// No description provided for @dropToShare.
  ///
  /// In zh, this message translates to:
  /// **'拖到这里分享'**
  String get dropToShare;

  /// No description provided for @releaseToShare.
  ///
  /// In zh, this message translates to:
  /// **'松手分享'**
  String get releaseToShare;

  /// No description provided for @selectDate.
  ///
  /// In zh, this message translates to:
  /// **'选择日期'**
  String get selectDate;

  /// No description provided for @applyLabel.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get applyLabel;

  /// No description provided for @dateFieldHint.
  ///
  /// In zh, this message translates to:
  /// **'年/月/日'**
  String get dateFieldHint;

  /// No description provided for @filterByDate.
  ///
  /// In zh, this message translates to:
  /// **'按日期筛选'**
  String get filterByDate;

  /// No description provided for @reset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get reset;

  /// No description provided for @specificDate.
  ///
  /// In zh, this message translates to:
  /// **'指定日期'**
  String get specificDate;

  /// No description provided for @pickADay.
  ///
  /// In zh, this message translates to:
  /// **'选择某一天'**
  String get pickADay;

  /// No description provided for @dateRange.
  ///
  /// In zh, this message translates to:
  /// **'日期范围'**
  String get dateRange;

  /// No description provided for @dateRangeValue.
  ///
  /// In zh, this message translates to:
  /// **'{start} 至 {end}'**
  String dateRangeValue(String start, String end);

  /// No description provided for @pickStartEnd.
  ///
  /// In zh, this message translates to:
  /// **'选择开始与结束日期'**
  String get pickStartEnd;

  /// No description provided for @hintLongPressPreview.
  ///
  /// In zh, this message translates to:
  /// **'点开「全部相册」后，长按图片可预览并导入 / 保存 / 删除'**
  String get hintLongPressPreview;

  /// No description provided for @restoreAll.
  ///
  /// In zh, this message translates to:
  /// **'全部恢复'**
  String get restoreAll;

  /// No description provided for @emptyTrash.
  ///
  /// In zh, this message translates to:
  /// **'清空回收站'**
  String get emptyTrash;

  /// No description provided for @deleteAlbum.
  ///
  /// In zh, this message translates to:
  /// **'删除相册'**
  String get deleteAlbum;

  /// No description provided for @reorderAlbums.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get reorderAlbums;

  /// No description provided for @restoredN.
  ///
  /// In zh, this message translates to:
  /// **'已恢复 {n} 张'**
  String restoredN(int n);

  /// No description provided for @emptyTrashQ.
  ///
  /// In zh, this message translates to:
  /// **'清空回收站?'**
  String get emptyTrashQ;

  /// No description provided for @deletedForeverN.
  ///
  /// In zh, this message translates to:
  /// **'已彻底删除 {n} 张'**
  String deletedForeverN(int n);

  /// No description provided for @deleteAlbumQ.
  ///
  /// In zh, this message translates to:
  /// **'删除「{name}」？'**
  String deleteAlbumQ(String name);

  /// No description provided for @deleteAlbumBody.
  ///
  /// In zh, this message translates to:
  /// **'只删除相册，图片仍保留在全部相册。'**
  String get deleteAlbumBody;

  /// No description provided for @newImagesSaveTo.
  ///
  /// In zh, this message translates to:
  /// **'新图将保存到「{name}」'**
  String newImagesSaveTo(String name);

  /// No description provided for @backToTop.
  ///
  /// In zh, this message translates to:
  /// **'回到顶部'**
  String get backToTop;

  /// No description provided for @filterByModel.
  ///
  /// In zh, this message translates to:
  /// **'按模型筛选'**
  String get filterByModel;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @groupMode.
  ///
  /// In zh, this message translates to:
  /// **'分组方式'**
  String get groupMode;

  /// No description provided for @savingProgress.
  ///
  /// In zh, this message translates to:
  /// **'保存中 {done}/{total}'**
  String savingProgress(int done, int total);

  /// No description provided for @zipping.
  ///
  /// In zh, this message translates to:
  /// **'打包中'**
  String get zipping;

  /// No description provided for @packZip.
  ///
  /// In zh, this message translates to:
  /// **'打包 ZIP'**
  String get packZip;

  /// No description provided for @restoreN.
  ///
  /// In zh, this message translates to:
  /// **'恢复 ({n})'**
  String restoreN(int n);

  /// No description provided for @deleteForeverN.
  ///
  /// In zh, this message translates to:
  /// **'彻底删除 ({n})'**
  String deleteForeverN(int n);

  /// No description provided for @photosAlbum.
  ///
  /// In zh, this message translates to:
  /// **'相册'**
  String get photosAlbum;

  /// No description provided for @quotedName.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」'**
  String quotedName(String name);

  /// No description provided for @savedNTo.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {n} 张到{where}'**
  String savedNTo(int n, String where);

  /// No description provided for @savedNToFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存 {n} 张到{where},失败 {failed} 张'**
  String savedNToFailed(int n, String where, int failed);

  /// No description provided for @albumsNoImages.
  ///
  /// In zh, this message translates to:
  /// **'所选相册里还没有图片'**
  String get albumsNoImages;

  /// No description provided for @savedAlbumsN.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {albums} 个相册,共 {n} 张'**
  String savedAlbumsN(int albums, int n);

  /// No description provided for @savedNFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存 {n} 张,失败 {failed} 张'**
  String savedNFailed(int n, int failed);

  /// No description provided for @deleteNAlbumsQ.
  ///
  /// In zh, this message translates to:
  /// **'删除 {n} 个相册？'**
  String deleteNAlbumsQ(int n);

  /// No description provided for @deletedNAlbums.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {n} 个相册'**
  String deletedNAlbums(int n);

  /// No description provided for @packFailed.
  ///
  /// In zh, this message translates to:
  /// **'打包失败'**
  String get packFailed;

  /// No description provided for @packedN.
  ///
  /// In zh, this message translates to:
  /// **'已打包 {n} 张'**
  String packedN(int n);

  /// No description provided for @packedNFailed.
  ///
  /// In zh, this message translates to:
  /// **'已打包 {n} 张,失败 {failed} 张'**
  String packedNFailed(int n, int failed);

  /// No description provided for @saveFailedWith.
  ///
  /// In zh, this message translates to:
  /// **'保存失败:{error}'**
  String saveFailedWith(String error);

  /// No description provided for @restore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get restore;

  /// No description provided for @deleteForever.
  ///
  /// In zh, this message translates to:
  /// **'彻底删除'**
  String get deleteForever;

  /// No description provided for @unfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get unfavorite;

  /// No description provided for @favoriteAction.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favoriteAction;

  /// No description provided for @removeCover.
  ///
  /// In zh, this message translates to:
  /// **'取消封面'**
  String get removeCover;

  /// No description provided for @setAsCover.
  ///
  /// In zh, this message translates to:
  /// **'设为封面'**
  String get setAsCover;

  /// No description provided for @restored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复'**
  String get restored;

  /// No description provided for @deleteForeverQ.
  ///
  /// In zh, this message translates to:
  /// **'彻底删除这张作品?'**
  String get deleteForeverQ;

  /// No description provided for @deletedForever.
  ///
  /// In zh, this message translates to:
  /// **'已彻底删除'**
  String get deletedForever;

  /// No description provided for @coverRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已取消「{name}」的封面'**
  String coverRemoved(String name);

  /// No description provided for @coverSet.
  ///
  /// In zh, this message translates to:
  /// **'已设为「{name}」的封面'**
  String coverSet(String name);

  /// No description provided for @imageNotReady.
  ///
  /// In zh, this message translates to:
  /// **'图片尚未就绪'**
  String get imageNotReady;

  /// No description provided for @unreadableSkipped.
  ///
  /// In zh, this message translates to:
  /// **'{n} 张读不出来,已跳过'**
  String unreadableSkipped(int n);

  /// No description provided for @movedNToTrash.
  ///
  /// In zh, this message translates to:
  /// **'已将 {n} 张移到回收站'**
  String movedNToTrash(int n);

  /// No description provided for @deleteNForeverQ.
  ///
  /// In zh, this message translates to:
  /// **'彻底删除 {n} 张作品?'**
  String deleteNForeverQ(int n);

  /// No description provided for @cantUndo.
  ///
  /// In zh, this message translates to:
  /// **'删除后无法恢复。'**
  String get cantUndo;

  /// No description provided for @deleteNImagesQ.
  ///
  /// In zh, this message translates to:
  /// **'删除 {n} 张作品?'**
  String deleteNImagesQ(int n);

  /// No description provided for @alreadyInAlbum.
  ///
  /// In zh, this message translates to:
  /// **'图片已在「{name}」'**
  String alreadyInAlbum(String name);

  /// No description provided for @movedNTo.
  ///
  /// In zh, this message translates to:
  /// **'已移动 {n} 张到「{name}」'**
  String movedNTo(int n, String name);

  /// No description provided for @deletesInDays.
  ///
  /// In zh, this message translates to:
  /// **'{n} 天后删除'**
  String deletesInDays(int n);

  /// No description provided for @selectedNAlbums.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 个相册'**
  String selectedNAlbums(int n);

  /// No description provided for @selectedNImages.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 张'**
  String selectedNImages(int n);

  /// No description provided for @selectNone.
  ///
  /// In zh, this message translates to:
  /// **'全不选'**
  String get selectNone;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @backToAll.
  ///
  /// In zh, this message translates to:
  /// **'回到全部'**
  String get backToAll;

  /// No description provided for @backToAlbums.
  ///
  /// In zh, this message translates to:
  /// **'回到相册'**
  String get backToAlbums;

  /// No description provided for @nAlbums.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个相册'**
  String nAlbums(int n);

  /// No description provided for @filteredOfTotal.
  ///
  /// In zh, this message translates to:
  /// **'{n}/{total} 张'**
  String filteredOfTotal(int n, int total);

  /// No description provided for @multiSelect.
  ///
  /// In zh, this message translates to:
  /// **'多选'**
  String get multiSelect;

  /// No description provided for @searchPromptTags.
  ///
  /// In zh, this message translates to:
  /// **'搜索提示词标签'**
  String get searchPromptTags;

  /// No description provided for @searchPromptTagsHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索提示词标签…'**
  String get searchPromptTagsHint;

  /// No description provided for @indexingProgress.
  ///
  /// In zh, this message translates to:
  /// **'索引 {done}/{total}'**
  String indexingProgress(int done, int total);

  /// No description provided for @grouping.
  ///
  /// In zh, this message translates to:
  /// **'分组中'**
  String get grouping;

  /// No description provided for @noMatchingWorks.
  ///
  /// In zh, this message translates to:
  /// **'没有符合条件的作品'**
  String get noMatchingWorks;

  /// No description provided for @trashEmpty.
  ///
  /// In zh, this message translates to:
  /// **'回收站是空的'**
  String get trashEmpty;

  /// No description provided for @galleryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'图库是空的'**
  String get galleryEmpty;

  /// No description provided for @albumNoImages.
  ///
  /// In zh, this message translates to:
  /// **'这个相册还没有图片'**
  String get albumNoImages;

  /// No description provided for @saveN.
  ///
  /// In zh, this message translates to:
  /// **'保存 ({n})'**
  String saveN(int n);

  /// No description provided for @deleteN.
  ///
  /// In zh, this message translates to:
  /// **'删除 ({n})'**
  String deleteN(int n);

  /// No description provided for @preparingProgress.
  ///
  /// In zh, this message translates to:
  /// **'准备 {done}/{total}'**
  String preparingProgress(int done, int total);

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @customAlbum.
  ///
  /// In zh, this message translates to:
  /// **'自定义相册'**
  String get customAlbum;

  /// No description provided for @finishing.
  ///
  /// In zh, this message translates to:
  /// **'收尾中'**
  String get finishing;

  /// No description provided for @preparing.
  ///
  /// In zh, this message translates to:
  /// **'准备中'**
  String get preparing;

  /// No description provided for @upscale.
  ///
  /// In zh, this message translates to:
  /// **'放大'**
  String get upscale;

  /// No description provided for @savedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get savedLabel;

  /// No description provided for @compare.
  ///
  /// In zh, this message translates to:
  /// **'对比'**
  String get compare;

  /// No description provided for @regenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get regenerate;

  /// No description provided for @inpaintInProgress.
  ///
  /// In zh, this message translates to:
  /// **'重绘进行中,请稍候'**
  String get inpaintInProgress;

  /// No description provided for @noPixelData.
  ///
  /// In zh, this message translates to:
  /// **'此图无像素数据'**
  String get noPixelData;

  /// No description provided for @redrawNoSnapshot.
  ///
  /// In zh, this message translates to:
  /// **'这张图没有参数快照,重绘放大用不了(只有本机生成的图带快照)'**
  String get redrawNoSnapshot;

  /// No description provided for @redrawModelUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'{model} 不支持图生图,重绘放大要先切回 NAI 模型'**
  String redrawModelUnsupported(String model);

  /// No description provided for @redrawTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'源图 {w}×{h} 已超过 NAI 的总像素上限,重绘放不出任何倍率'**
  String redrawTooLarge(int w, int h);

  /// No description provided for @preparingEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'准备…'**
  String get preparingEllipsis;

  /// No description provided for @upscaleDone.
  ///
  /// In zh, this message translates to:
  /// **'{method}完成 {w}×{h},已存入图库'**
  String upscaleDone(String method, int w, int h);

  /// No description provided for @upscaleFailed.
  ///
  /// In zh, this message translates to:
  /// **'超分失败: {error}'**
  String upscaleFailed(String error);

  /// No description provided for @redrawNoSnapshotShort.
  ///
  /// In zh, this message translates to:
  /// **'缺少参数快照,无法重绘放大'**
  String get redrawNoSnapshotShort;

  /// No description provided for @redrawStartMax.
  ///
  /// In zh, this message translates to:
  /// **'开始 Max 重绘 ≈{w}×{h} · {model}'**
  String redrawStartMax(int w, int h, String model);

  /// No description provided for @upscaleStart.
  ///
  /// In zh, this message translates to:
  /// **'开始 V5 超分 {w}×{h}'**
  String upscaleStart(int w, int h);

  /// No description provided for @addToCreate.
  ///
  /// In zh, this message translates to:
  /// **'存入创作页'**
  String get addToCreate;

  /// No description provided for @savedToImg2ImgUpscale.
  ///
  /// In zh, this message translates to:
  /// **'已存入图生图放大'**
  String get savedToImg2ImgUpscale;

  /// No description provided for @redrawStart.
  ///
  /// In zh, this message translates to:
  /// **'开始 {scale} 重绘 {w}×{h} · {model}'**
  String redrawStart(String scale, int w, int h, String model);

  /// No description provided for @savedToPhotos1.
  ///
  /// In zh, this message translates to:
  /// **'已保存到相册'**
  String get savedToPhotos1;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get saveFailed;

  /// No description provided for @saveFailedSpace.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {error}'**
  String saveFailedSpace(String error);

  /// No description provided for @regenNoSnapshot.
  ///
  /// In zh, this message translates to:
  /// **'缺少参数快照,无法重新生成'**
  String get regenNoSnapshot;

  /// No description provided for @saveToNamed.
  ///
  /// In zh, this message translates to:
  /// **'保存到 {name}'**
  String saveToNamed(String name);

  /// No description provided for @cantReadImage.
  ///
  /// In zh, this message translates to:
  /// **'无法读取这张图片'**
  String get cantReadImage;

  /// No description provided for @upscaleNote.
  ///
  /// In zh, this message translates to:
  /// **'V5 扩散超分 · 固定 2× · {price} 点'**
  String upscaleNote(int price);

  /// No description provided for @upscaleTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'源图 {w}×{h} 超过 3,145,728 像素,超分不受理'**
  String upscaleTooLarge(int w, int h);

  /// No description provided for @scaleNoteX1.
  ///
  /// In zh, this message translates to:
  /// **'同尺寸重新生成,只精修细节、不放大'**
  String get scaleNoteX1;

  /// No description provided for @scaleNoteMax.
  ///
  /// In zh, this message translates to:
  /// **'发原图尺寸,由 NovelAI 放到最大后重绘'**
  String get scaleNoteMax;

  /// No description provided for @scaleNoteScale.
  ///
  /// In zh, this message translates to:
  /// **'以 {scale} 分辨率重新生成,画面会变'**
  String scaleNoteScale(String scale);

  /// No description provided for @maxOnlyV5.
  ///
  /// In zh, this message translates to:
  /// **'Max 档只有 V5 有;当前模型是 {model},重绘也按它跑'**
  String maxOnlyV5(String model);

  /// No description provided for @maxTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'Max 档要求源图小于 2,516,582 像素,这张 {w}×{h} 太大了'**
  String maxTooLarge(int w, int h);

  /// No description provided for @upscaleResolution.
  ///
  /// In zh, this message translates to:
  /// **'超分辨率'**
  String get upscaleResolution;

  /// No description provided for @img2imgUpscale.
  ///
  /// In zh, this message translates to:
  /// **'图生图放大'**
  String get img2imgUpscale;

  /// No description provided for @scaleLabel.
  ///
  /// In zh, this message translates to:
  /// **'倍率'**
  String get scaleLabel;

  /// No description provided for @magnitudeLabel.
  ///
  /// In zh, this message translates to:
  /// **'档位'**
  String get magnitudeLabel;

  /// No description provided for @magnitudeN.
  ///
  /// In zh, this message translates to:
  /// **'档 {n}'**
  String magnitudeN(String n);

  /// No description provided for @strengthStrength.
  ///
  /// In zh, this message translates to:
  /// **'强度 Strength'**
  String get strengthStrength;

  /// No description provided for @noiseNoise.
  ///
  /// In zh, this message translates to:
  /// **'噪声 Noise'**
  String get noiseNoise;

  /// No description provided for @startUpscale.
  ///
  /// In zh, this message translates to:
  /// **'开始放大'**
  String get startUpscale;

  /// No description provided for @savedToPhotosSize.
  ///
  /// In zh, this message translates to:
  /// **'已保存到相册 · {size}'**
  String savedToPhotosSize(String size);

  /// No description provided for @setAsDefaultSave.
  ///
  /// In zh, this message translates to:
  /// **'已设为默认保存方式'**
  String get setAsDefaultSave;

  /// No description provided for @estimatedSize.
  ///
  /// In zh, this message translates to:
  /// **'预估大小 {size}'**
  String estimatedSize(String size);

  /// No description provided for @calculating.
  ///
  /// In zh, this message translates to:
  /// **'计算中…'**
  String get calculating;

  /// No description provided for @jpgNoParams.
  ///
  /// In zh, this message translates to:
  /// **'JPG 不保留生成参数'**
  String get jpgNoParams;

  /// No description provided for @keepOriginalMeta.
  ///
  /// In zh, this message translates to:
  /// **'保留原始元数据'**
  String get keepOriginalMeta;

  /// No description provided for @clearGenInfo.
  ///
  /// In zh, this message translates to:
  /// **'清除生成信息'**
  String get clearGenInfo;

  /// No description provided for @saveOnce.
  ///
  /// In zh, this message translates to:
  /// **'单次保存'**
  String get saveOnce;

  /// No description provided for @setAsDefault.
  ///
  /// In zh, this message translates to:
  /// **'设为默认'**
  String get setAsDefault;

  /// No description provided for @newImagesSaveHere.
  ///
  /// In zh, this message translates to:
  /// **'新图保存到这里'**
  String get newImagesSaveHere;

  /// No description provided for @zipName.
  ///
  /// In zh, this message translates to:
  /// **'压缩包名称'**
  String get zipName;

  /// No description provided for @zipPassword.
  ///
  /// In zh, this message translates to:
  /// **'压缩密码(可选)'**
  String get zipPassword;

  /// No description provided for @stopping.
  ///
  /// In zh, this message translates to:
  /// **'正在停下'**
  String get stopping;

  /// No description provided for @pack.
  ///
  /// In zh, this message translates to:
  /// **'打包'**
  String get pack;

  /// No description provided for @selectDateRange.
  ///
  /// In zh, this message translates to:
  /// **'选择日期范围'**
  String get selectDateRange;

  /// No description provided for @backToCalendar.
  ///
  /// In zh, this message translates to:
  /// **'返回日历'**
  String get backToCalendar;

  /// No description provided for @startDate.
  ///
  /// In zh, this message translates to:
  /// **'开始日期'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In zh, this message translates to:
  /// **'结束日期'**
  String get endDate;

  /// No description provided for @dragToAdjustDate.
  ///
  /// In zh, this message translates to:
  /// **'可直接拖动调整日期'**
  String get dragToAdjustDate;

  /// No description provided for @zipTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'包太大,超出 zip 的表示范围'**
  String get zipTooLarge;

  /// No description provided for @zipInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'打包中断'**
  String get zipInterrupted;

  /// No description provided for @enterNameFirst.
  ///
  /// In zh, this message translates to:
  /// **'先填写名称'**
  String get enterNameFirst;

  /// No description provided for @enterPromptFirst.
  ///
  /// In zh, this message translates to:
  /// **'先填写提示词'**
  String get enterPromptFirst;

  /// No description provided for @deleteNamedQ.
  ///
  /// In zh, this message translates to:
  /// **'删除「{name}」?'**
  String deleteNamedQ(String name);

  /// No description provided for @localOnlyDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'仅删除本地条目,不可恢复。'**
  String get localOnlyDeleteBody;

  /// No description provided for @deletedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get deletedLabel;

  /// No description provided for @numbersExhausted.
  ///
  /// In zh, this message translates to:
  /// **'编号已用尽'**
  String get numbersExhausted;

  /// No description provided for @importCharPrompt.
  ///
  /// In zh, this message translates to:
  /// **'导入角色提示词'**
  String get importCharPrompt;

  /// No description provided for @importMainPrompt.
  ///
  /// In zh, this message translates to:
  /// **'导入主提示词'**
  String get importMainPrompt;

  /// No description provided for @galleryNoImages.
  ///
  /// In zh, this message translates to:
  /// **'图库还没有图片'**
  String get galleryNoImages;

  /// No description provided for @pickFromGallery.
  ///
  /// In zh, this message translates to:
  /// **'从图库选取'**
  String get pickFromGallery;

  /// No description provided for @totalImagesN.
  ///
  /// In zh, this message translates to:
  /// **'共 {n} 张'**
  String totalImagesN(int n);

  /// No description provided for @readImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取图片失败'**
  String get readImageFailed;

  /// No description provided for @enterPositiveFirst.
  ///
  /// In zh, this message translates to:
  /// **'先填写正向提示词'**
  String get enterPositiveFirst;

  /// No description provided for @editInCat.
  ///
  /// In zh, this message translates to:
  /// **'编辑{cat}'**
  String editInCat(String cat);

  /// No description provided for @newInCat.
  ///
  /// In zh, this message translates to:
  /// **'新建{cat}'**
  String newInCat(String cat);

  /// No description provided for @aliasLabel.
  ///
  /// In zh, this message translates to:
  /// **'别名'**
  String get aliasLabel;

  /// No description provided for @enterAlias.
  ///
  /// In zh, this message translates to:
  /// **'输入别名…'**
  String get enterAlias;

  /// No description provided for @numberLabel.
  ///
  /// In zh, this message translates to:
  /// **'编号'**
  String get numberLabel;

  /// No description provided for @upload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get upload;

  /// No description provided for @generating.
  ///
  /// In zh, this message translates to:
  /// **'生成中'**
  String get generating;

  /// No description provided for @exampleArtists.
  ///
  /// In zh, this message translates to:
  /// **'例如: wlop, rurudo'**
  String get exampleArtists;

  /// No description provided for @negativePromptAlt.
  ///
  /// In zh, this message translates to:
  /// **'负面提示词'**
  String get negativePromptAlt;

  /// No description provided for @exampleNegative.
  ///
  /// In zh, this message translates to:
  /// **'例如: bad anatomy, worst quality'**
  String get exampleNegative;

  /// No description provided for @applicableModels.
  ///
  /// In zh, this message translates to:
  /// **'适用模型'**
  String get applicableModels;

  /// No description provided for @recommendedParams.
  ///
  /// In zh, this message translates to:
  /// **'推荐参数'**
  String get recommendedParams;

  /// No description provided for @importToCreatePage.
  ///
  /// In zh, this message translates to:
  /// **'导入创作页'**
  String get importToCreatePage;

  /// No description provided for @tapToUpload.
  ///
  /// In zh, this message translates to:
  /// **'点击上传'**
  String get tapToUpload;

  /// No description provided for @modelsNoneMeansAll.
  ///
  /// In zh, this message translates to:
  /// **'一个都不选 = 通用,在所有模型下都会出现'**
  String get modelsNoneMeansAll;

  /// No description provided for @selectedNCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 个'**
  String selectedNCount(int n);

  /// No description provided for @unknownModelOtherVersion.
  ///
  /// In zh, this message translates to:
  /// **'未知模型(来自其它版本)'**
  String get unknownModelOtherVersion;

  /// No description provided for @useCurrent.
  ///
  /// In zh, this message translates to:
  /// **'换成当前'**
  String get useCurrent;

  /// No description provided for @saveLocal.
  ///
  /// In zh, this message translates to:
  /// **'保存到本地'**
  String get saveLocal;

  /// No description provided for @saveAndPublish.
  ///
  /// In zh, this message translates to:
  /// **'保存并发布'**
  String get saveAndPublish;

  /// No description provided for @saveChanges.
  ///
  /// In zh, this message translates to:
  /// **'保存修改'**
  String get saveChanges;

  /// No description provided for @saveTagChanges.
  ///
  /// In zh, this message translates to:
  /// **'保存标签修改'**
  String get saveTagChanges;

  /// No description provided for @storeIn.
  ///
  /// In zh, this message translates to:
  /// **'存到'**
  String get storeIn;

  /// No description provided for @maxSelectN.
  ///
  /// In zh, this message translates to:
  /// **'最多选 {n} 个'**
  String maxSelectN(int n);

  /// No description provided for @charsFullN.
  ///
  /// In zh, this message translates to:
  /// **'角色已满 {n} 个'**
  String charsFullN(int n);

  /// No description provided for @addedCharsTruncated.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {added} 个角色(超出 {cap} 个截断)'**
  String addedCharsTruncated(int added, int cap);

  /// No description provided for @addedChars.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {n} 个角色'**
  String addedChars(int n);

  /// No description provided for @addedToPrompt.
  ///
  /// In zh, this message translates to:
  /// **'已加入提示词'**
  String get addedToPrompt;

  /// No description provided for @taggedN.
  ///
  /// In zh, this message translates to:
  /// **'已给 {n} 项加上「{tag}」'**
  String taggedN(int n, String tag);

  /// No description provided for @deleteNItemsQ.
  ///
  /// In zh, this message translates to:
  /// **'删除 {n} 项?'**
  String deleteNItemsQ(int n);

  /// No description provided for @localOnlyNLine.
  ///
  /// In zh, this message translates to:
  /// **'· 本地的 {n} 项:仅删除本地'**
  String localOnlyNLine(int n);

  /// No description provided for @cantUndoShort.
  ///
  /// In zh, this message translates to:
  /// **'不可恢复。'**
  String get cantUndoShort;

  /// No description provided for @deletedNFailed.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {done} 项,{failed} 项失败'**
  String deletedNFailed(int done, int failed);

  /// No description provided for @deletedNItems.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {n} 项'**
  String deletedNItems(int n);

  /// No description provided for @addN.
  ///
  /// In zh, this message translates to:
  /// **'添加 ({n})'**
  String addN(int n);

  /// No description provided for @filter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get filter;

  /// No description provided for @noMatchingInCat.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的{cat}'**
  String noMatchingInCat(String cat);

  /// No description provided for @noneYetInCat.
  ///
  /// In zh, this message translates to:
  /// **'还没有{cat}'**
  String noneYetInCat(String cat);

  /// No description provided for @myInCat.
  ///
  /// In zh, this message translates to:
  /// **'我的{cat}'**
  String myInCat(String cat);

  /// No description provided for @savedInCat.
  ///
  /// In zh, this message translates to:
  /// **'收藏的{cat}'**
  String savedInCat(String cat);

  /// No description provided for @publicLibUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'公共库暂未开放'**
  String get publicLibUnavailable;

  /// No description provided for @viewPrompt.
  ///
  /// In zh, this message translates to:
  /// **'查看提示词'**
  String get viewPrompt;

  /// No description provided for @copyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'复制提示词'**
  String get copyPrompt;

  /// No description provided for @promptCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制提示词'**
  String get promptCopied;

  /// No description provided for @catCharacter.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get catCharacter;

  /// No description provided for @catStyle.
  ///
  /// In zh, this message translates to:
  /// **'画风'**
  String get catStyle;

  /// No description provided for @catScene.
  ///
  /// In zh, this message translates to:
  /// **'场景'**
  String get catScene;

  /// No description provided for @catOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get catOther;

  /// No description provided for @searchCharHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索角色 / 别名…'**
  String get searchCharHint;

  /// No description provided for @searchStyleHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称 / 提示词 / 标签…'**
  String get searchStyleHint;

  /// No description provided for @searchSceneHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索场景…'**
  String get searchSceneHint;

  /// No description provided for @searchNamePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称 / 提示词…'**
  String get searchNamePromptHint;

  /// No description provided for @layoutPortrait.
  ///
  /// In zh, this message translates to:
  /// **'竖图'**
  String get layoutPortrait;

  /// No description provided for @layoutLandscape.
  ///
  /// In zh, this message translates to:
  /// **'横图'**
  String get layoutLandscape;

  /// No description provided for @layoutSquare.
  ///
  /// In zh, this message translates to:
  /// **'方图'**
  String get layoutSquare;

  /// No description provided for @layoutNoImage.
  ///
  /// In zh, this message translates to:
  /// **'无图'**
  String get layoutNoImage;

  /// No description provided for @sortNumber.
  ///
  /// In zh, this message translates to:
  /// **'编号'**
  String get sortNumber;

  /// No description provided for @sortLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get sortLatest;

  /// No description provided for @sortAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者'**
  String get sortAuthor;

  /// No description provided for @notTagBackup.
  ///
  /// In zh, this message translates to:
  /// **'不是 Tag 管理器的备份文件'**
  String get notTagBackup;

  /// No description provided for @backupCatUnknown.
  ///
  /// In zh, this message translates to:
  /// **'备份文件的分类无法识别'**
  String get backupCatUnknown;

  /// No description provided for @noPreviewForCat.
  ///
  /// In zh, this message translates to:
  /// **'该分类不支持生成预览'**
  String get noPreviewForCat;

  /// No description provided for @copySuffix.
  ///
  /// In zh, this message translates to:
  /// **'(副本)'**
  String get copySuffix;

  /// No description provided for @codexTypeDict.
  ///
  /// In zh, this message translates to:
  /// **'词典'**
  String get codexTypeDict;

  /// No description provided for @codexTypeComposition.
  ///
  /// In zh, this message translates to:
  /// **'构图'**
  String get codexTypeComposition;

  /// No description provided for @codexTypePack.
  ///
  /// In zh, this message translates to:
  /// **'合集'**
  String get codexTypePack;

  /// No description provided for @codexNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到法典:{id}'**
  String codexNotFound(String id);

  /// No description provided for @codexBadImageHost.
  ///
  /// In zh, this message translates to:
  /// **'图床配置格式异常'**
  String get codexBadImageHost;

  /// No description provided for @codexBadIndex.
  ///
  /// In zh, this message translates to:
  /// **'法典索引格式异常'**
  String get codexBadIndex;

  /// No description provided for @codexBadData.
  ///
  /// In zh, this message translates to:
  /// **'法典数据格式异常'**
  String get codexBadData;

  /// No description provided for @codexOriginalImage.
  ///
  /// In zh, this message translates to:
  /// **'法典原图'**
  String get codexOriginalImage;

  /// No description provided for @originalNotDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'原图没下下来,检查下网络'**
  String get originalNotDownloaded;

  /// No description provided for @shuffleAnother.
  ///
  /// In zh, this message translates to:
  /// **'换一个'**
  String get shuffleAnother;

  /// No description provided for @addedToPromptCharsDropped.
  ///
  /// In zh, this message translates to:
  /// **'已加入提示词 · {added} 个角色(另 {dropped} 个超出上限)'**
  String addedToPromptCharsDropped(int added, int dropped);

  /// No description provided for @addedToPromptChars.
  ///
  /// In zh, this message translates to:
  /// **'已加入提示词 · {added} 个角色'**
  String addedToPromptChars(int added);

  /// No description provided for @goCreate.
  ///
  /// In zh, this message translates to:
  /// **'去创作'**
  String get goCreate;

  /// No description provided for @addToPrompt.
  ///
  /// In zh, this message translates to:
  /// **'加入提示词'**
  String get addToPrompt;

  /// No description provided for @favoritesFull.
  ///
  /// In zh, this message translates to:
  /// **'收藏已满({n} 条),先去收藏夹清一些'**
  String favoritesFull(int n);

  /// No description provided for @random.
  ///
  /// In zh, this message translates to:
  /// **'随机'**
  String get random;

  /// No description provided for @tapToFlip.
  ///
  /// In zh, this message translates to:
  /// **'点击翻转查看提示词'**
  String get tapToFlip;

  /// No description provided for @charNNegative.
  ///
  /// In zh, this message translates to:
  /// **'角色 {n} · 负向'**
  String charNNegative(int n);

  /// No description provided for @selectCodex.
  ///
  /// In zh, this message translates to:
  /// **'选择法典'**
  String get selectCodex;

  /// No description provided for @clearFavorites.
  ///
  /// In zh, this message translates to:
  /// **'清空收藏'**
  String get clearFavorites;

  /// No description provided for @clearFavoritesBody.
  ///
  /// In zh, this message translates to:
  /// **'将移除全部 {n} 条收藏,不可恢复。法典词条本身不受影响。'**
  String clearFavoritesBody(int n);

  /// No description provided for @noFavoritesYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有收藏'**
  String get noFavoritesYet;

  /// No description provided for @favoriteHowTo.
  ///
  /// In zh, this message translates to:
  /// **'点开任意词条,左下角那颗星即可收藏'**
  String get favoriteHowTo;

  /// No description provided for @allIn.
  ///
  /// In zh, this message translates to:
  /// **'全部「{name}」'**
  String allIn(String name);

  /// No description provided for @unblock.
  ///
  /// In zh, this message translates to:
  /// **'解除屏蔽'**
  String get unblock;

  /// No description provided for @block.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽'**
  String get block;

  /// No description provided for @unblockAll.
  ///
  /// In zh, this message translates to:
  /// **'全部解除'**
  String get unblockAll;

  /// No description provided for @upLevel.
  ///
  /// In zh, this message translates to:
  /// **'上一级'**
  String get upLevel;

  /// No description provided for @categories.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get categories;

  /// No description provided for @author.
  ///
  /// In zh, this message translates to:
  /// **'作者'**
  String get author;

  /// No description provided for @contributors.
  ///
  /// In zh, this message translates to:
  /// **'贡献者'**
  String get contributors;

  /// No description provided for @codexCopyright.
  ///
  /// In zh, this message translates to:
  /// **'内容与例图版权归各法典作者所有,本页仅作可视化索引。'**
  String get codexCopyright;

  /// No description provided for @codexSiteLink.
  ///
  /// In zh, this message translates to:
  /// **'法典图鉴 · 原站'**
  String get codexSiteLink;

  /// No description provided for @codexIndexFailed.
  ///
  /// In zh, this message translates to:
  /// **'法典索引加载失败'**
  String get codexIndexFailed;

  /// No description provided for @noCodex.
  ///
  /// In zh, this message translates to:
  /// **'暂无法典'**
  String get noCodex;

  /// No description provided for @codexAbout.
  ///
  /// In zh, this message translates to:
  /// **'词条与例图数据来自\nhttps://novelai.quicktagcloud.com/\n\n本应用仅作展示与检索,内容版权归各法典作者所有。\n\n感谢所有法典作者与贡献者的整理分享。'**
  String get codexAbout;

  /// No description provided for @sourcesThanks.
  ///
  /// In zh, this message translates to:
  /// **'来源与致谢'**
  String get sourcesThanks;

  /// No description provided for @gotIt.
  ///
  /// In zh, this message translates to:
  /// **'我知道了'**
  String get gotIt;

  /// No description provided for @loadingEntries.
  ///
  /// In zh, this message translates to:
  /// **'正在载入 {n} 条词条…'**
  String loadingEntries(int n);

  /// No description provided for @codexLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'法典加载失败'**
  String get codexLoadFailed;

  /// No description provided for @noMatchingEntries.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的词条'**
  String get noMatchingEntries;

  /// No description provided for @noEntries.
  ///
  /// In zh, this message translates to:
  /// **'暂无词条'**
  String get noEntries;

  /// No description provided for @searchTitlePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索标题 / 提示词…'**
  String get searchTitlePromptHint;

  /// No description provided for @allCategories.
  ///
  /// In zh, this message translates to:
  /// **'全部分类'**
  String get allCategories;

  /// No description provided for @nothingToDraw.
  ///
  /// In zh, this message translates to:
  /// **'当前没有可抽的词条'**
  String get nothingToDraw;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @categoryLabel.
  ///
  /// In zh, this message translates to:
  /// **'类别'**
  String get categoryLabel;

  /// No description provided for @newCategory.
  ///
  /// In zh, this message translates to:
  /// **'新建类别'**
  String get newCategory;

  /// No description provided for @renameShort.
  ///
  /// In zh, this message translates to:
  /// **'改名'**
  String get renameShort;

  /// No description provided for @categoryExists.
  ///
  /// In zh, this message translates to:
  /// **'已有同名类别'**
  String get categoryExists;

  /// No description provided for @categoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个类别还没有条目。'**
  String get categoryEmpty;

  /// No description provided for @categoryDeleteN.
  ///
  /// In zh, this message translates to:
  /// **'类别里的 {n} 个条目会一起删除,不可恢复。'**
  String categoryDeleteN(int n);

  /// No description provided for @categoryReAdd.
  ///
  /// In zh, this message translates to:
  /// **'之后新建一个叫「{name}」的类别,可以把它加回来。'**
  String categoryReAdd(String name);

  /// No description provided for @editCategory.
  ///
  /// In zh, this message translates to:
  /// **'编辑类别'**
  String get editCategory;

  /// No description provided for @categoryName.
  ///
  /// In zh, this message translates to:
  /// **'类别名称'**
  String get categoryName;

  /// No description provided for @icon.
  ///
  /// In zh, this message translates to:
  /// **'图标'**
  String get icon;

  /// No description provided for @previewImage.
  ///
  /// In zh, this message translates to:
  /// **'预览图'**
  String get previewImage;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @manageCategories.
  ///
  /// In zh, this message translates to:
  /// **'类别管理'**
  String get manageCategories;

  /// No description provided for @addLibN.
  ///
  /// In zh, this message translates to:
  /// **'加入 ({n})'**
  String addLibN(int n);

  /// No description provided for @addCharsN.
  ///
  /// In zh, this message translates to:
  /// **'加入角色 ({n})'**
  String addCharsN(int n);

  /// No description provided for @scopeMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get scopeMine;

  /// No description provided for @scopeMineN.
  ///
  /// In zh, this message translates to:
  /// **'我的 · {n}'**
  String scopeMineN(int n);

  /// No description provided for @scopePublicShortN.
  ///
  /// In zh, this message translates to:
  /// **'公共 {n}'**
  String scopePublicShortN(int n);

  /// No description provided for @scopePublicShort.
  ///
  /// In zh, this message translates to:
  /// **'公共'**
  String get scopePublicShort;

  /// No description provided for @scopePublicN.
  ///
  /// In zh, this message translates to:
  /// **'公共库 · {n}'**
  String scopePublicN(int n);

  /// No description provided for @manageTagPool.
  ///
  /// In zh, this message translates to:
  /// **'标签池管理'**
  String get manageTagPool;

  /// No description provided for @sort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sort;

  /// No description provided for @nicknameOrQq.
  ///
  /// In zh, this message translates to:
  /// **'昵称或 QQ 号'**
  String get nicknameOrQq;

  /// No description provided for @noSignedEntries.
  ///
  /// In zh, this message translates to:
  /// **'库里还没有署名的条目'**
  String get noSignedEntries;

  /// No description provided for @noMatchingAuthors.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的作者'**
  String get noMatchingAuthors;

  /// No description provided for @genericModel.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get genericModel;

  /// No description provided for @genericUnlabeled.
  ///
  /// In zh, this message translates to:
  /// **'{label}(没标注的)'**
  String genericUnlabeled(String label);

  /// No description provided for @authorNamed.
  ///
  /// In zh, this message translates to:
  /// **'作者 {name}'**
  String authorNamed(String name);

  /// No description provided for @positiveLabel.
  ///
  /// In zh, this message translates to:
  /// **'正向'**
  String get positiveLabel;

  /// No description provided for @negativeLabel.
  ///
  /// In zh, this message translates to:
  /// **'负面'**
  String get negativeLabel;

  /// No description provided for @tagExistsShort.
  ///
  /// In zh, this message translates to:
  /// **'标签已存在'**
  String get tagExistsShort;

  /// No description provided for @catTagPool.
  ///
  /// In zh, this message translates to:
  /// **'{cat}标签池'**
  String catTagPool(String cat);

  /// No description provided for @newTagEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'新建标签…'**
  String get newTagEllipsis;

  /// No description provided for @noTags.
  ///
  /// In zh, this message translates to:
  /// **'暂无标签'**
  String get noTags;

  /// No description provided for @deleteTagQ.
  ///
  /// In zh, this message translates to:
  /// **'删除标签「{tag}」?'**
  String deleteTagQ(String tag);

  /// No description provided for @deleteTagEntriesBody.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个条目会摘掉该标签,条目本身保留。'**
  String deleteTagEntriesBody(int n);

  /// No description provided for @addTag.
  ///
  /// In zh, this message translates to:
  /// **'添加标签'**
  String get addTag;

  /// No description provided for @use.
  ///
  /// In zh, this message translates to:
  /// **'使用'**
  String get use;

  /// No description provided for @charRangeLabel.
  ///
  /// In zh, this message translates to:
  /// **'角色 {n}'**
  String charRangeLabel(String n);

  /// No description provided for @imagesScopeSuffix.
  ///
  /// In zh, this message translates to:
  /// **'张 · {scope}生图'**
  String imagesScopeSuffix(String scope);

  /// No description provided for @costPts.
  ///
  /// In zh, this message translates to:
  /// **'消耗 {n} 点'**
  String costPts(String n);

  /// No description provided for @selectedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已选 {name}'**
  String selectedLabel(String name);

  /// No description provided for @peakSlot.
  ///
  /// In zh, this message translates to:
  /// **'最高时段'**
  String get peakSlot;

  /// No description provided for @peakDay.
  ///
  /// In zh, this message translates to:
  /// **'最高单日'**
  String get peakDay;

  /// No description provided for @unitTxns.
  ///
  /// In zh, this message translates to:
  /// **'笔'**
  String get unitTxns;

  /// No description provided for @genDetails.
  ///
  /// In zh, this message translates to:
  /// **'生成详情'**
  String get genDetails;

  /// No description provided for @pointsDetails.
  ///
  /// In zh, this message translates to:
  /// **'点数详情'**
  String get pointsDetails;

  /// No description provided for @activeSlots.
  ///
  /// In zh, this message translates to:
  /// **'活跃时段'**
  String get activeSlots;

  /// No description provided for @activeDays.
  ///
  /// In zh, this message translates to:
  /// **'活跃天数'**
  String get activeDays;

  /// No description provided for @avgPerSlot.
  ///
  /// In zh, this message translates to:
  /// **'段均生图'**
  String get avgPerSlot;

  /// No description provided for @avgPerDay.
  ///
  /// In zh, this message translates to:
  /// **'日均生图'**
  String get avgPerDay;

  /// No description provided for @v5Gens.
  ///
  /// In zh, this message translates to:
  /// **'V5 生图'**
  String get v5Gens;

  /// No description provided for @v5Anlas.
  ///
  /// In zh, this message translates to:
  /// **'V5 点数'**
  String get v5Anlas;

  /// No description provided for @estimatedSpend.
  ///
  /// In zh, this message translates to:
  /// **'估算消耗'**
  String get estimatedSpend;

  /// No description provided for @vsPrevSlot.
  ///
  /// In zh, this message translates to:
  /// **'较上一时段'**
  String get vsPrevSlot;

  /// No description provided for @vsPrevDay.
  ///
  /// In zh, this message translates to:
  /// **'较上一日'**
  String get vsPrevDay;

  /// No description provided for @unchanged.
  ///
  /// In zh, this message translates to:
  /// **'持平'**
  String get unchanged;

  /// No description provided for @todayRange.
  ///
  /// In zh, this message translates to:
  /// **'今天 {from}–{to}'**
  String todayRange(String from, String to);

  /// No description provided for @todayHour.
  ///
  /// In zh, this message translates to:
  /// **'今天 {h}:00'**
  String todayHour(String h);

  /// No description provided for @dataSource.
  ///
  /// In zh, this message translates to:
  /// **'数据源'**
  String get dataSource;

  /// No description provided for @directKey.
  ///
  /// In zh, this message translates to:
  /// **'直连 Key'**
  String get directKey;

  /// No description provided for @botAuth.
  ///
  /// In zh, this message translates to:
  /// **'Bot 授权'**
  String get botAuth;

  /// No description provided for @rangeToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get rangeToday;

  /// No description provided for @rangeWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get rangeWeek;

  /// No description provided for @rangeMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get rangeMonth;

  /// No description provided for @minusPts.
  ///
  /// In zh, this message translates to:
  /// **'-{n} 点'**
  String minusPts(String n);

  /// No description provided for @genSize.
  ///
  /// In zh, this message translates to:
  /// **'生图 {w}×{h}'**
  String genSize(int w, int h);

  /// No description provided for @upscale4x.
  ///
  /// In zh, this message translates to:
  /// **'超分 4x'**
  String get upscale4x;

  /// No description provided for @vibeEncoding.
  ///
  /// In zh, this message translates to:
  /// **'Vibe 编码'**
  String get vibeEncoding;

  /// No description provided for @dayGens.
  ///
  /// In zh, this message translates to:
  /// **'当日生图'**
  String get dayGens;

  /// No description provided for @freeN.
  ///
  /// In zh, this message translates to:
  /// **'免费 {n}'**
  String freeN(int n);

  /// No description provided for @perItemSpend.
  ///
  /// In zh, this message translates to:
  /// **'逐笔消耗'**
  String get perItemSpend;

  /// No description provided for @perItemGens.
  ///
  /// In zh, this message translates to:
  /// **'逐笔生成'**
  String get perItemGens;

  /// No description provided for @detailsRolledOff.
  ///
  /// In zh, this message translates to:
  /// **'该日明细已超出保留窗口,仅剩汇总'**
  String get detailsRolledOff;

  /// No description provided for @noRecordsDay.
  ///
  /// In zh, this message translates to:
  /// **'该日无记录'**
  String get noRecordsDay;

  /// No description provided for @noData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get noData;

  /// No description provided for @modeNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get modeNone;

  /// No description provided for @modeComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画模式'**
  String get modeComic;

  /// No description provided for @modeNatural.
  ///
  /// In zh, this message translates to:
  /// **'仅自然语言'**
  String get modeNatural;

  /// No description provided for @toolCharLib.
  ///
  /// In zh, this message translates to:
  /// **'角色库'**
  String get toolCharLib;

  /// No description provided for @toolStyleLib.
  ///
  /// In zh, this message translates to:
  /// **'画风库'**
  String get toolStyleLib;

  /// No description provided for @toolTagWiki.
  ///
  /// In zh, this message translates to:
  /// **'Tag 百科'**
  String get toolTagWiki;

  /// No description provided for @toolSafeMode.
  ///
  /// In zh, this message translates to:
  /// **'安全模式'**
  String get toolSafeMode;

  /// No description provided for @toolOcLib.
  ///
  /// In zh, this message translates to:
  /// **'OC 库'**
  String get toolOcLib;

  /// No description provided for @assistantTools.
  ///
  /// In zh, this message translates to:
  /// **'工具'**
  String get assistantTools;

  /// No description provided for @assistantToolsDesc.
  ///
  /// In zh, this message translates to:
  /// **'AI 查资料时能用的工具'**
  String get assistantToolsDesc;

  /// No description provided for @toolsEnabledN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个已开'**
  String toolsEnabledN(int n);

  /// No description provided for @imageModelField.
  ///
  /// In zh, this message translates to:
  /// **'出图模型'**
  String get imageModelField;

  /// No description provided for @drawingImage.
  ///
  /// In zh, this message translates to:
  /// **'出图中'**
  String get drawingImage;

  /// No description provided for @imagePromptEmpty.
  ///
  /// In zh, this message translates to:
  /// **'说一句要画什么或者怎么改'**
  String get imagePromptEmpty;

  /// No description provided for @aspectLabel.
  ///
  /// In zh, this message translates to:
  /// **'比例'**
  String get aspectLabel;

  /// No description provided for @resolutionChip.
  ///
  /// In zh, this message translates to:
  /// **'分辨率 {v}'**
  String resolutionChip(String v);

  /// No description provided for @aspectChip.
  ///
  /// In zh, this message translates to:
  /// **'比例 {v}'**
  String aspectChip(String v);

  /// No description provided for @imageAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get imageAuto;

  /// No description provided for @quoteImage.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get quoteImage;

  /// No description provided for @imagesMax.
  ///
  /// In zh, this message translates to:
  /// **'最多带 {n} 张图'**
  String imagesMax(int n);

  /// No description provided for @imageGenNoModel.
  ///
  /// In zh, this message translates to:
  /// **'这个图像模型现在用不了'**
  String get imageGenNoModel;

  /// No description provided for @imageGenNoImage.
  ///
  /// In zh, this message translates to:
  /// **'没有出图'**
  String get imageGenNoImage;

  /// No description provided for @toolSearchArtist.
  ///
  /// In zh, this message translates to:
  /// **'使用画风库'**
  String get toolSearchArtist;

  /// No description provided for @toolSearchOc.
  ///
  /// In zh, this message translates to:
  /// **'使用角色库'**
  String get toolSearchOc;

  /// No description provided for @toolSearchCharacter.
  ///
  /// In zh, this message translates to:
  /// **'搜索角色'**
  String get toolSearchCharacter;

  /// No description provided for @toolLookupTag.
  ///
  /// In zh, this message translates to:
  /// **'搜索 tag'**
  String get toolLookupTag;

  /// No description provided for @randomN.
  ///
  /// In zh, this message translates to:
  /// **'随机 {n} 个'**
  String randomN(int n);

  /// No description provided for @lookedUpN.
  ///
  /// In zh, this message translates to:
  /// **'查了 {n} 处资料'**
  String lookedUpN(int n);

  /// No description provided for @untitledChat.
  ///
  /// In zh, this message translates to:
  /// **'未命名对话'**
  String get untitledChat;

  /// No description provided for @thinkOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get thinkOff;

  /// No description provided for @thinkAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get thinkAuto;

  /// No description provided for @thinkLow.
  ///
  /// In zh, this message translates to:
  /// **'低'**
  String get thinkLow;

  /// No description provided for @thinkMedium.
  ///
  /// In zh, this message translates to:
  /// **'中等'**
  String get thinkMedium;

  /// No description provided for @thinkHigh.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get thinkHigh;

  /// No description provided for @thinkUltra.
  ///
  /// In zh, this message translates to:
  /// **'超高'**
  String get thinkUltra;

  /// No description provided for @importReplaceMain.
  ///
  /// In zh, this message translates to:
  /// **'替换主体'**
  String get importReplaceMain;

  /// No description provided for @importClearSections.
  ///
  /// In zh, this message translates to:
  /// **'清空分区'**
  String get importClearSections;

  /// No description provided for @assistantNoModal.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手暂不支持 Anima / Krea,去创作页换成 NAI 再来'**
  String get assistantNoModal;

  /// No description provided for @builtinModelUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'内置模型暂未开放,先在顶部选一个自定义接口'**
  String get builtinModelUnavailable;

  /// No description provided for @thinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中'**
  String get thinking;

  /// No description provided for @lookingUp.
  ///
  /// In zh, this message translates to:
  /// **'查资料中'**
  String get lookingUp;

  /// No description provided for @turnInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'AI 这轮没跑完就断了,再试一次'**
  String get turnInterrupted;

  /// No description provided for @replyDoneFallback.
  ///
  /// In zh, this message translates to:
  /// **'改好了喵~'**
  String get replyDoneFallback;

  /// No description provided for @replyEmptyFallback.
  ///
  /// In zh, this message translates to:
  /// **'这轮没什么可说的喵…'**
  String get replyEmptyFallback;

  /// No description provided for @epNoModels.
  ///
  /// In zh, this message translates to:
  /// **'拿到了,但一个模型都没有'**
  String get epNoModels;

  /// No description provided for @modelEmptyReply.
  ///
  /// In zh, this message translates to:
  /// **'模型回了一段空的'**
  String get modelEmptyReply;

  /// No description provided for @backendUnset.
  ///
  /// In zh, this message translates to:
  /// **'未配置后端地址'**
  String get backendUnset;

  /// No description provided for @noDataIn.
  ///
  /// In zh, this message translates to:
  /// **'{secs} 秒内没有收到数据'**
  String noDataIn(String secs);

  /// No description provided for @channelEndedEarly.
  ///
  /// In zh, this message translates to:
  /// **'连接在收到结果前结束了'**
  String get channelEndedEarly;

  /// No description provided for @modelBadDraw.
  ///
  /// In zh, this message translates to:
  /// **'出图块重写 {count} 次仍不对,模型最后一次的原文:'**
  String modelBadDraw(String count);

  /// No description provided for @assistantRefused.
  ///
  /// In zh, this message translates to:
  /// **'模型拒绝了这次请求(重试 {count} 次仍命中「{keyword}」)'**
  String assistantRefused(String count, String keyword);

  /// No description provided for @modelNoReplyIn.
  ///
  /// In zh, this message translates to:
  /// **'模型 {secs} 秒内没有回复'**
  String modelNoReplyIn(String secs);

  /// No description provided for @thinkNoOffFormat.
  ///
  /// In zh, this message translates to:
  /// **'该格式没有「关闭」档,按最低档发送'**
  String get thinkNoOffFormat;

  /// No description provided for @thinkNoUltraFormat.
  ///
  /// In zh, this message translates to:
  /// **'该格式没有「超高」档,按「高」发送'**
  String get thinkNoUltraFormat;

  /// No description provided for @thinkNoOffModel.
  ///
  /// In zh, this message translates to:
  /// **'该模型不能关闭思考,按「低」发送'**
  String get thinkNoOffModel;

  /// No description provided for @thinkNoUltraModel.
  ///
  /// In zh, this message translates to:
  /// **'该模型没有「超高」档,按「高」发送'**
  String get thinkNoUltraModel;

  /// No description provided for @replyUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'接口有响应,但没读出回复内容,检查格式是否选对'**
  String get replyUnreadable;

  /// No description provided for @suggest1.
  ///
  /// In zh, this message translates to:
  /// **'画一个白发红瞳的猫娘,站在樱花树下'**
  String get suggest1;

  /// No description provided for @suggest2.
  ///
  /// In zh, this message translates to:
  /// **'帮我抽一个好看的画风'**
  String get suggest2;

  /// No description provided for @suggest3.
  ///
  /// In zh, this message translates to:
  /// **'随机画一个蔚蓝档案的角色'**
  String get suggest3;

  /// No description provided for @suggest4.
  ///
  /// In zh, this message translates to:
  /// **'看看我现在这串 tag 有什么问题'**
  String get suggest4;

  /// No description provided for @aiAssistant.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get aiAssistant;

  /// No description provided for @selectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get selectModel;

  /// No description provided for @assistantSettings.
  ///
  /// In zh, this message translates to:
  /// **'助手设置'**
  String get assistantSettings;

  /// No description provided for @chatHistory.
  ///
  /// In zh, this message translates to:
  /// **'历史会话'**
  String get chatHistory;

  /// No description provided for @newChat.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get newChat;

  /// No description provided for @askAnything.
  ///
  /// In zh, this message translates to:
  /// **'想画什么,直接说'**
  String get askAnything;

  /// No description provided for @copyContent.
  ///
  /// In zh, this message translates to:
  /// **'复制内容'**
  String get copyContent;

  /// No description provided for @editMessage.
  ///
  /// In zh, this message translates to:
  /// **'编辑该消息'**
  String get editMessage;

  /// No description provided for @regenerateFromHere.
  ///
  /// In zh, this message translates to:
  /// **'从这里重新生成'**
  String get regenerateFromHere;

  /// No description provided for @cancelSend.
  ///
  /// In zh, this message translates to:
  /// **'取消发送'**
  String get cancelSend;

  /// No description provided for @discardAfterQ.
  ///
  /// In zh, this message translates to:
  /// **'丢掉之后的对话?'**
  String get discardAfterQ;

  /// No description provided for @discardAfterBody.
  ///
  /// In zh, this message translates to:
  /// **'这条之后的对话都会丢掉,已经写进创作页的改动不受影响。'**
  String get discardAfterBody;

  /// No description provided for @discard.
  ///
  /// In zh, this message translates to:
  /// **'丢掉'**
  String get discard;

  /// No description provided for @createPageShort.
  ///
  /// In zh, this message translates to:
  /// **'创作页'**
  String get createPageShort;

  /// No description provided for @quoteCreatePage.
  ///
  /// In zh, this message translates to:
  /// **'引用创作页'**
  String get quoteCreatePage;

  /// No description provided for @createPageEmpty.
  ///
  /// In zh, this message translates to:
  /// **'创作页还没写提示词,没东西可引用'**
  String get createPageEmpty;

  /// No description provided for @modeLabel.
  ///
  /// In zh, this message translates to:
  /// **'模式'**
  String get modeLabel;

  /// No description provided for @rulesNoMode.
  ///
  /// In zh, this message translates to:
  /// **'当前规则预设不支持「{mode}」'**
  String rulesNoMode(String mode);

  /// No description provided for @thinkChip.
  ///
  /// In zh, this message translates to:
  /// **'思考 {level}'**
  String thinkChip(String level);

  /// No description provided for @attachImage.
  ///
  /// In zh, this message translates to:
  /// **'带图'**
  String get attachImage;

  /// No description provided for @systemAlbum.
  ///
  /// In zh, this message translates to:
  /// **'系统相册'**
  String get systemAlbum;

  /// No description provided for @inputHint.
  ///
  /// In zh, this message translates to:
  /// **'想画什么、想改哪里…'**
  String get inputHint;

  /// No description provided for @stop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get stop;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @assistantModelUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手暂不支持这个模型'**
  String get assistantModelUnsupported;

  /// No description provided for @assistantModelUnsupportedBody.
  ///
  /// In zh, this message translates to:
  /// **'Anima 与 Krea 的提示词体系和 NAI 是两套。\n去创作页换成 NAI 4.5 或 5 再来。'**
  String get assistantModelUnsupportedBody;

  /// No description provided for @goChangeModel.
  ///
  /// In zh, this message translates to:
  /// **'去换模型'**
  String get goChangeModel;

  /// No description provided for @pickEndpointFirst.
  ///
  /// In zh, this message translates to:
  /// **'还没有可用的模型'**
  String get pickEndpointFirst;

  /// No description provided for @builtinUnavailableBody.
  ///
  /// In zh, this message translates to:
  /// **'先添加一个自己的模型接口'**
  String get builtinUnavailableBody;

  /// No description provided for @selectEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'选择模型接口'**
  String get selectEndpoint;

  /// No description provided for @queued.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get queued;

  /// No description provided for @quotedCreatePage.
  ///
  /// In zh, this message translates to:
  /// **'引用了创作页'**
  String get quotedCreatePage;

  /// No description provided for @durSecs.
  ///
  /// In zh, this message translates to:
  /// **'{s} 秒'**
  String durSecs(int s);

  /// No description provided for @durMinSecs.
  ///
  /// In zh, this message translates to:
  /// **'{m} 分 {s} 秒'**
  String durMinSecs(int m, String s);

  /// No description provided for @discardChangesQ.
  ///
  /// In zh, this message translates to:
  /// **'放弃修改?'**
  String get discardChangesQ;

  /// No description provided for @unsavedLost.
  ///
  /// In zh, this message translates to:
  /// **'没保存的改动会丢掉。'**
  String get unsavedLost;

  /// No description provided for @unsavedLost2.
  ///
  /// In zh, this message translates to:
  /// **'还没保存的改动会丢掉。'**
  String get unsavedLost2;

  /// No description provided for @discardAction.
  ///
  /// In zh, this message translates to:
  /// **'放弃'**
  String get discardAction;

  /// No description provided for @savedNamed.
  ///
  /// In zh, this message translates to:
  /// **'已保存「{name}」'**
  String savedNamed(String name);

  /// No description provided for @deleteEndpointQ.
  ///
  /// In zh, this message translates to:
  /// **'删除这个接口?'**
  String get deleteEndpointQ;

  /// No description provided for @deleteEndpointBody.
  ///
  /// In zh, this message translates to:
  /// **'地址和 API Key 都会从本机删除。已经发生过的对话不受影响。'**
  String get deleteEndpointBody;

  /// No description provided for @myEndpoints.
  ///
  /// In zh, this message translates to:
  /// **'我的接口'**
  String get myEndpoints;

  /// No description provided for @addEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'添加接口'**
  String get addEndpoint;

  /// No description provided for @notComplete.
  ///
  /// In zh, this message translates to:
  /// **'还没填全'**
  String get notComplete;

  /// No description provided for @formatOf.
  ///
  /// In zh, this message translates to:
  /// **'{format} 格式'**
  String formatOf(String format);

  /// No description provided for @inUse.
  ///
  /// In zh, this message translates to:
  /// **'使用中'**
  String get inUse;

  /// No description provided for @pickServiceOrUrl.
  ///
  /// In zh, this message translates to:
  /// **'先选服务或填接口地址'**
  String get pickServiceOrUrl;

  /// No description provided for @urlMustHttp.
  ///
  /// In zh, this message translates to:
  /// **'接口地址要以 http:// 或 https:// 开头'**
  String get urlMustHttp;

  /// No description provided for @noApiKeyYet.
  ///
  /// In zh, this message translates to:
  /// **'还没填 API Key'**
  String get noApiKeyYet;

  /// No description provided for @noModelYet.
  ///
  /// In zh, this message translates to:
  /// **'还没添加模型'**
  String get noModelYet;

  /// No description provided for @headerLineBad.
  ///
  /// In zh, this message translates to:
  /// **'请求头第 {n} 行要写成「名称: 值」,只能用英文字符'**
  String headerLineBad(int n);

  /// No description provided for @linkCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制链接:{url}'**
  String linkCopied(String url);

  /// No description provided for @modelConnOk.
  ///
  /// In zh, this message translates to:
  /// **'{model} 连接正常 · {secs} 秒'**
  String modelConnOk(String model, String secs);

  /// No description provided for @connOk.
  ///
  /// In zh, this message translates to:
  /// **'连接正常 · {secs} 秒'**
  String connOk(String secs);

  /// No description provided for @formatField.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get formatField;

  /// No description provided for @urlField.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get urlField;

  /// No description provided for @getKey.
  ///
  /// In zh, this message translates to:
  /// **'获取 Key'**
  String get getKey;

  /// No description provided for @modelField.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get modelField;

  /// No description provided for @modelIdHint.
  ///
  /// In zh, this message translates to:
  /// **'模型 ID'**
  String get modelIdHint;

  /// No description provided for @addAnotherModel.
  ///
  /// In zh, this message translates to:
  /// **'再加一个模型'**
  String get addAnotherModel;

  /// No description provided for @modelList.
  ///
  /// In zh, this message translates to:
  /// **'模型列表'**
  String get modelList;

  /// No description provided for @pathField.
  ///
  /// In zh, this message translates to:
  /// **'路径'**
  String get pathField;

  /// No description provided for @headersField.
  ///
  /// In zh, this message translates to:
  /// **'请求头'**
  String get headersField;

  /// No description provided for @headersHint.
  ///
  /// In zh, this message translates to:
  /// **'一行一条,如 X-Title: Plana'**
  String get headersHint;

  /// No description provided for @headersN.
  ///
  /// In zh, this message translates to:
  /// **'请求头 {n}'**
  String headersN(int n);

  /// No description provided for @test.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get test;

  /// No description provided for @searchNModels.
  ///
  /// In zh, this message translates to:
  /// **'搜索 {n} 个模型'**
  String searchNModels(int n);

  /// No description provided for @doneSelectedN.
  ///
  /// In zh, this message translates to:
  /// **'完成 · 已选 {n} 个'**
  String doneSelectedN(int n);

  /// No description provided for @rulePresets.
  ///
  /// In zh, this message translates to:
  /// **'规则预设'**
  String get rulePresets;

  /// No description provided for @sectionsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 段'**
  String sectionsN(int n);

  /// No description provided for @notUtf8.
  ///
  /// In zh, this message translates to:
  /// **'读不了这个文件,请确认是 UTF-8 文本'**
  String get notUtf8;

  /// No description provided for @importedNamed.
  ///
  /// In zh, this message translates to:
  /// **'已导入「{name}」'**
  String importedNamed(String name);

  /// No description provided for @savedAsNamed.
  ///
  /// In zh, this message translates to:
  /// **'已另存为「{name}」'**
  String savedAsNamed(String name);

  /// No description provided for @exportedNamed.
  ///
  /// In zh, this message translates to:
  /// **'已导出「{name}」'**
  String exportedNamed(String name);

  /// No description provided for @deletePresetQ.
  ///
  /// In zh, this message translates to:
  /// **'删除预设?'**
  String get deletePresetQ;

  /// No description provided for @deleteRulePresetBody.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」将被删除,正在使用它的模型改用默认规则。'**
  String deleteRulePresetBody(String name);

  /// No description provided for @listSep.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get listSep;

  /// No description provided for @importRulePreset.
  ///
  /// In zh, this message translates to:
  /// **'导入规则预设'**
  String get importRulePreset;

  /// No description provided for @totalSectionsN.
  ///
  /// In zh, this message translates to:
  /// **'共 {n} 段'**
  String totalSectionsN(int n);

  /// No description provided for @hasConditional.
  ///
  /// In zh, this message translates to:
  /// **'含条件段'**
  String get hasConditional;

  /// No description provided for @ruleSecRole.
  ///
  /// In zh, this message translates to:
  /// **'角色定义'**
  String get ruleSecRole;

  /// No description provided for @ruleSecModelTraits.
  ///
  /// In zh, this message translates to:
  /// **'模型特性'**
  String get ruleSecModelTraits;

  /// No description provided for @ruleSecPromptConstruction.
  ///
  /// In zh, this message translates to:
  /// **'提示词构建'**
  String get ruleSecPromptConstruction;

  /// No description provided for @ruleSecNaturalConstruction.
  ///
  /// In zh, this message translates to:
  /// **'纯自然语言构建'**
  String get ruleSecNaturalConstruction;

  /// No description provided for @ruleSecWeightControl.
  ///
  /// In zh, this message translates to:
  /// **'权重控制'**
  String get ruleSecWeightControl;

  /// No description provided for @ruleSecCharacters.
  ///
  /// In zh, this message translates to:
  /// **'角色处理'**
  String get ruleSecCharacters;

  /// No description provided for @ruleSecMultiCharacter.
  ///
  /// In zh, this message translates to:
  /// **'多角色绘图'**
  String get ruleSecMultiCharacter;

  /// No description provided for @ruleSecComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画 / 分镜'**
  String get ruleSecComic;

  /// No description provided for @ruleSecCustomTags.
  ///
  /// In zh, this message translates to:
  /// **'自定义标签'**
  String get ruleSecCustomTags;

  /// No description provided for @ruleSecTextRendering.
  ///
  /// In zh, this message translates to:
  /// **'画面文字'**
  String get ruleSecTextRendering;

  /// No description provided for @ruleSecAlpha.
  ///
  /// In zh, this message translates to:
  /// **'透明通道'**
  String get ruleSecAlpha;

  /// No description provided for @ruleSecOutput.
  ///
  /// In zh, this message translates to:
  /// **'绘图输出'**
  String get ruleSecOutput;

  /// No description provided for @ruleSecModeComic.
  ///
  /// In zh, this message translates to:
  /// **'当前模式：漫画'**
  String get ruleSecModeComic;

  /// No description provided for @ruleSecModeNatural.
  ///
  /// In zh, this message translates to:
  /// **'当前模式：仅自然语言'**
  String get ruleSecModeNatural;

  /// No description provided for @enabledModels.
  ///
  /// In zh, this message translates to:
  /// **'启用的模型'**
  String get enabledModels;

  /// No description provided for @notEnabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get notEnabled;

  /// No description provided for @duplicatePreset.
  ///
  /// In zh, this message translates to:
  /// **'创建副本'**
  String get duplicatePreset;

  /// No description provided for @ruleSectionsLabel.
  ///
  /// In zh, this message translates to:
  /// **'段落'**
  String get ruleSectionsLabel;

  /// No description provided for @whenOffTag.
  ///
  /// In zh, this message translates to:
  /// **'{mode}时不发'**
  String whenOffTag(String mode);

  /// No description provided for @charsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 字'**
  String charsN(int n);

  /// No description provided for @fullTextEdit.
  ///
  /// In zh, this message translates to:
  /// **'全文编辑'**
  String get fullTextEdit;

  /// No description provided for @addRuleSection.
  ///
  /// In zh, this message translates to:
  /// **'添加一段'**
  String get addRuleSection;

  /// No description provided for @ruleSectionName.
  ///
  /// In zh, this message translates to:
  /// **'标题名称'**
  String get ruleSectionName;

  /// No description provided for @deleteRuleSectionQ.
  ///
  /// In zh, this message translates to:
  /// **'删除这一段?'**
  String get deleteRuleSectionQ;

  /// No description provided for @deleteRuleSectionBody.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」的内容会一起删掉。'**
  String deleteRuleSectionBody(String name);

  /// No description provided for @ruleSectionEmpty.
  ///
  /// In zh, this message translates to:
  /// **'内容不能为空'**
  String get ruleSectionEmpty;

  /// No description provided for @ruleSectionNameReserved.
  ///
  /// In zh, this message translates to:
  /// **'这个段名留给工具层,换一个'**
  String get ruleSectionNameReserved;

  /// No description provided for @supportedModels.
  ///
  /// In zh, this message translates to:
  /// **'支持的模型'**
  String get supportedModels;

  /// No description provided for @missingPresetName.
  ///
  /// In zh, this message translates to:
  /// **'缺少预设名称(name)'**
  String get missingPresetName;

  /// No description provided for @missingModels.
  ///
  /// In zh, this message translates to:
  /// **'缺少支持的模型(models 写 nai45、nai5)'**
  String get missingModels;

  /// No description provided for @rulesTooManySections.
  ///
  /// In zh, this message translates to:
  /// **'规则段数太多(上限 {n} 段)'**
  String rulesTooManySections(int n);

  /// No description provided for @rulesTooLong.
  ///
  /// In zh, this message translates to:
  /// **'规则太长(上限 {n} 字)'**
  String rulesTooLong(int n);

  /// No description provided for @rulesHeader1.
  ///
  /// In zh, this message translates to:
  /// **'# Plana AI 助手规则预设'**
  String get rulesHeader1;

  /// No description provided for @rulesHeader2.
  ///
  /// In zh, this message translates to:
  /// **'# 每段一个 name 和 content。带 when 的是条件段,例如 when: comic 只在画漫画时发送。'**
  String get rulesHeader2;

  /// No description provided for @rulesHeader3.
  ///
  /// In zh, this message translates to:
  /// **'# when 以 mode: 开头的是模式段,例如 when: \"mode:comic\" 只在选了漫画模式时发送。'**
  String get rulesHeader3;

  /// No description provided for @rulesHeader4.
  ///
  /// In zh, this message translates to:
  /// **'# when 前面加 ! 表示没选时才发送,例如 when: \"!mode:natural\" 选了仅自然语言就不发。'**
  String get rulesHeader4;

  /// No description provided for @badFileFormat.
  ///
  /// In zh, this message translates to:
  /// **'文件格式不对:{detail}'**
  String badFileFormat(String detail);

  /// No description provided for @badFileFormatLine.
  ///
  /// In zh, this message translates to:
  /// **'文件格式不对(第 {line} 行):{detail}'**
  String badFileFormatLine(int line, String detail);

  /// No description provided for @noSections.
  ///
  /// In zh, this message translates to:
  /// **'文件格式不对:找不到 sections'**
  String get noSections;

  /// No description provided for @noUsableRules.
  ///
  /// In zh, this message translates to:
  /// **'文件里没有可用的规则段'**
  String get noUsableRules;

  /// No description provided for @clearHistoryQ.
  ///
  /// In zh, this message translates to:
  /// **'清空历史会话?'**
  String get clearHistoryQ;

  /// No description provided for @clearHistoryBody.
  ///
  /// In zh, this message translates to:
  /// **'{n} 段对话都会删掉,已经写进创作页的改动不受影响。'**
  String clearHistoryBody(int n);

  /// No description provided for @noArchivedChats.
  ///
  /// In zh, this message translates to:
  /// **'还没有归档的对话。\n点右上角「新对话」就会把当前这段存进来。'**
  String get noArchivedChats;

  /// No description provided for @turnsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 轮'**
  String turnsN(int n);

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @libraryScope.
  ///
  /// In zh, this message translates to:
  /// **'资料库范围'**
  String get libraryScope;

  /// No description provided for @usageHabits.
  ///
  /// In zh, this message translates to:
  /// **'使用习惯'**
  String get usageHabits;

  /// No description provided for @autoDraw.
  ///
  /// In zh, this message translates to:
  /// **'生成提示词后自动出图'**
  String get autoDraw;

  /// No description provided for @autoDrawDesc.
  ///
  /// In zh, this message translates to:
  /// **'提示词生成完成后立即开始出图'**
  String get autoDrawDesc;

  /// No description provided for @inlineImages.
  ///
  /// In zh, this message translates to:
  /// **'在对话内显示图片'**
  String get inlineImages;

  /// No description provided for @inlineImagesDesc.
  ///
  /// In zh, this message translates to:
  /// **'生成的图片显示在对话内,同时保存至图库'**
  String get inlineImagesDesc;

  /// No description provided for @autoWrite.
  ///
  /// In zh, this message translates to:
  /// **'自动写入创作页'**
  String get autoWrite;

  /// No description provided for @autoWriteDesc.
  ///
  /// In zh, this message translates to:
  /// **'生成的提示词自动写回创作页,无需手动导入'**
  String get autoWriteDesc;

  /// No description provided for @startUsingAssistant.
  ///
  /// In zh, this message translates to:
  /// **'开始使用 AI 助手'**
  String get startUsingAssistant;

  /// No description provided for @previous.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get previous;

  /// No description provided for @chatMode.
  ///
  /// In zh, this message translates to:
  /// **'对话模式'**
  String get chatMode;

  /// No description provided for @planaBackend.
  ///
  /// In zh, this message translates to:
  /// **'Plana Bot'**
  String get planaBackend;

  /// No description provided for @freeModels.
  ///
  /// In zh, this message translates to:
  /// **'免费模型'**
  String get freeModels;

  /// No description provided for @incompleteTapToFix.
  ///
  /// In zh, this message translates to:
  /// **'还没填全,点一下去补'**
  String get incompleteTapToFix;

  /// No description provided for @writtenToCreate.
  ///
  /// In zh, this message translates to:
  /// **'已写入创作页'**
  String get writtenToCreate;

  /// No description provided for @undoImportQ.
  ///
  /// In zh, this message translates to:
  /// **'撤销这次导入?'**
  String get undoImportQ;

  /// No description provided for @undoImportBody.
  ///
  /// In zh, this message translates to:
  /// **'你在导入之后又动过提示词。撤销会一并丢掉你那些改动,回到导入之前的样子。'**
  String get undoImportBody;

  /// No description provided for @undoAnyway.
  ///
  /// In zh, this message translates to:
  /// **'仍要撤销'**
  String get undoAnyway;

  /// No description provided for @undone.
  ///
  /// In zh, this message translates to:
  /// **'已撤销'**
  String get undone;

  /// No description provided for @imported.
  ///
  /// In zh, this message translates to:
  /// **'已导入'**
  String get imported;

  /// No description provided for @added.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get added;

  /// No description provided for @fullPrompt.
  ///
  /// In zh, this message translates to:
  /// **'完整提示词'**
  String get fullPrompt;

  /// No description provided for @sameAsLastTurn.
  ///
  /// In zh, this message translates to:
  /// **'和上一轮的提示词一样'**
  String get sameAsLastTurn;

  /// No description provided for @generatedNTags.
  ///
  /// In zh, this message translates to:
  /// **'生成了 {n} tag'**
  String generatedNTags(int n);

  /// No description provided for @writtenNChars.
  ///
  /// In zh, this message translates to:
  /// **'已写入 · {n} 个角色'**
  String writtenNChars(int n);

  /// No description provided for @aiGaveNChars.
  ///
  /// In zh, this message translates to:
  /// **'AI 给了 {n} 个角色'**
  String aiGaveNChars(int n);

  /// No description provided for @aiWroteFull.
  ///
  /// In zh, this message translates to:
  /// **'AI 写了一整份提示词'**
  String get aiWroteFull;

  /// No description provided for @sameAsYours.
  ///
  /// In zh, this message translates to:
  /// **'和你现在的提示词一样'**
  String get sameAsYours;

  /// No description provided for @aiChanges.
  ///
  /// In zh, this message translates to:
  /// **'AI 的改动'**
  String get aiChanges;

  /// No description provided for @settingMessageSize.
  ///
  /// In zh, this message translates to:
  /// **'消息字号'**
  String get settingMessageSize;

  /// No description provided for @settingMessageSizeDesc.
  ///
  /// In zh, this message translates to:
  /// **'对话消息的文字显示大小'**
  String get settingMessageSizeDesc;

  /// No description provided for @streamOutput.
  ///
  /// In zh, this message translates to:
  /// **'流式输出'**
  String get streamOutput;

  /// No description provided for @streamOutputDesc.
  ///
  /// In zh, this message translates to:
  /// **'逐字显示回复'**
  String get streamOutputDesc;

  /// No description provided for @settingDraw.
  ///
  /// In zh, this message translates to:
  /// **'出图'**
  String get settingDraw;

  /// No description provided for @plainTextFormat.
  ///
  /// In zh, this message translates to:
  /// **'纯文本格式'**
  String get plainTextFormat;

  /// No description provided for @plainTextFormatDesc.
  ///
  /// In zh, this message translates to:
  /// **'提示词只显示为文本,不导入也不出图'**
  String get plainTextFormatDesc;

  /// No description provided for @importModeDesc.
  ///
  /// In zh, this message translates to:
  /// **'提示词写入创作页主提示词的位置'**
  String get importModeDesc;

  /// No description provided for @settingAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get settingAuto;

  /// No description provided for @settingChat.
  ///
  /// In zh, this message translates to:
  /// **'对话'**
  String get settingChat;

  /// No description provided for @contextTurns.
  ///
  /// In zh, this message translates to:
  /// **'上下文轮数'**
  String get contextTurns;

  /// No description provided for @contextTurnsDesc.
  ///
  /// In zh, this message translates to:
  /// **'每次发送带上最近几轮对话'**
  String get contextTurnsDesc;

  /// No description provided for @failRetries.
  ///
  /// In zh, this message translates to:
  /// **'失败重试'**
  String get failRetries;

  /// No description provided for @failRetriesDesc.
  ///
  /// In zh, this message translates to:
  /// **'出错时自动重发'**
  String get failRetriesDesc;

  /// No description provided for @retryStripImage.
  ///
  /// In zh, this message translates to:
  /// **'最后一次重试不带图'**
  String get retryStripImage;

  /// No description provided for @retryStripImageDesc.
  ///
  /// In zh, this message translates to:
  /// **'最后一次失败重试时去掉附图'**
  String get retryStripImageDesc;

  /// No description provided for @refusalRetries.
  ///
  /// In zh, this message translates to:
  /// **'拒绝重试'**
  String get refusalRetries;

  /// No description provided for @refusalRetriesDesc.
  ///
  /// In zh, this message translates to:
  /// **'回复像拒绝时自动重新生成'**
  String get refusalRetriesDesc;

  /// No description provided for @refusalKeywords.
  ///
  /// In zh, this message translates to:
  /// **'拒绝关键词'**
  String get refusalKeywords;

  /// No description provided for @refusalKeywordsDesc.
  ///
  /// In zh, this message translates to:
  /// **'不出图的回复命中其中一个就算拒绝'**
  String get refusalKeywordsDesc;

  /// No description provided for @addRefusalKeyword.
  ///
  /// In zh, this message translates to:
  /// **'添加关键词，逗号隔开可加多个'**
  String get addRefusalKeyword;

  /// No description provided for @restoreDefaultKeywordsQ.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认关键词？'**
  String get restoreDefaultKeywordsQ;

  /// No description provided for @restoreDefaultKeywordsBody.
  ///
  /// In zh, this message translates to:
  /// **'添加和删除过的关键词都会还原'**
  String get restoreDefaultKeywordsBody;

  /// No description provided for @keywordsN.
  ///
  /// In zh, this message translates to:
  /// **'{n} 个'**
  String keywordsN(int n);

  /// No description provided for @settingLibrary.
  ///
  /// In zh, this message translates to:
  /// **'资料'**
  String get settingLibrary;

  /// No description provided for @ocPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'OC 使用占位符'**
  String get ocPlaceholder;

  /// No description provided for @ocPlaceholderDesc.
  ///
  /// In zh, this message translates to:
  /// **'OC 只给 AI 占位符，出图时还原；调整原设时请关闭'**
  String get ocPlaceholderDesc;

  /// No description provided for @modelUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持'**
  String get modelUnsupported;

  /// No description provided for @settingRules.
  ///
  /// In zh, this message translates to:
  /// **'规则'**
  String get settingRules;

  /// No description provided for @rulePresetsDesc.
  ///
  /// In zh, this message translates to:
  /// **'生成提示词时遵循的规则'**
  String get rulePresetsDesc;

  /// No description provided for @settingDebug.
  ///
  /// In zh, this message translates to:
  /// **'调试'**
  String get settingDebug;

  /// No description provided for @exportChatLog.
  ///
  /// In zh, this message translates to:
  /// **'导出对话记录'**
  String get exportChatLog;

  /// No description provided for @exportChatLogDesc.
  ///
  /// In zh, this message translates to:
  /// **'当前对话每一轮发给 AI 的内容和返回'**
  String get exportChatLogDesc;

  /// No description provided for @chatEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前对话是空的'**
  String get chatEmpty;

  /// No description provided for @chatLogExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出对话记录'**
  String get chatLogExported;

  /// No description provided for @adjustThinkDepth.
  ///
  /// In zh, this message translates to:
  /// **'调整模型思考深度'**
  String get adjustThinkDepth;

  /// No description provided for @thinkDepthNote.
  ///
  /// In zh, this message translates to:
  /// **'并非所有模型都支持深度调整,请参考模型和提供商的文档。'**
  String get thinkDepthNote;

  /// No description provided for @naiStatusLine.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 官方:图像生成{state}'**
  String naiStatusLine(String state);

  /// No description provided for @naiStateDown.
  ///
  /// In zh, this message translates to:
  /// **'服务中断'**
  String get naiStateDown;

  /// No description provided for @naiStatePartial.
  ///
  /// In zh, this message translates to:
  /// **'部分中断'**
  String get naiStatePartial;

  /// No description provided for @naiStateDegraded.
  ///
  /// In zh, this message translates to:
  /// **'性能下降'**
  String get naiStateDegraded;

  /// No description provided for @naiStateMaintenance.
  ///
  /// In zh, this message translates to:
  /// **'维护中'**
  String get naiStateMaintenance;

  /// No description provided for @naiStateSecurity.
  ///
  /// In zh, this message translates to:
  /// **'安全事件'**
  String get naiStateSecurity;

  /// No description provided for @naiStateIssue.
  ///
  /// In zh, this message translates to:
  /// **'异常'**
  String get naiStateIssue;

  /// No description provided for @naiStatusDetails.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get naiStatusDetails;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

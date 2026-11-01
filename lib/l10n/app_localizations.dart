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

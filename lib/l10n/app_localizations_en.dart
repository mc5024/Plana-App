// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get language => 'Language';

  @override
  String get uiLanguage => 'UI Language';

  @override
  String get followSystem => 'System';

  @override
  String get cancel => 'Cancel';

  @override
  String get undo => 'Undo';

  @override
  String get clear => 'Clear';

  @override
  String get confirm => 'Confirm';

  @override
  String get generate => 'Generate';

  @override
  String get model => 'Model';

  @override
  String get prompt => 'Prompt';

  @override
  String get positivePrompt => 'Prompt';

  @override
  String get negativePrompt => 'Undesired Content';

  @override
  String get characterPrompts => 'Character Prompts';

  @override
  String get importImage => 'Import Image';

  @override
  String get advanced => 'Advanced';

  @override
  String get advancedSettings => 'Advanced Settings';

  @override
  String get resetSettings => 'Reset Settings';

  @override
  String get resolution => 'Resolution';

  @override
  String get size => 'Size';

  @override
  String get imageCount => 'Images';

  @override
  String get steps => 'Steps';

  @override
  String get seedRandom => 'Random';

  @override
  String get paramSteps => 'Steps';

  @override
  String get paramCfg => 'Prompt Guidance';

  @override
  String get paramSampler => 'Sampler';

  @override
  String get paramScheduler => 'Noise Schedule';

  @override
  String get paramNoiseSchedule => 'Noise Schedule';

  @override
  String get paramSeed => 'Seed';

  @override
  String get cfgRescale => 'CFG Rescale';

  @override
  String get varietyPlus => 'Variety+';

  @override
  String get sizeNormal => 'Normal';

  @override
  String get sizeLarge => 'Large';

  @override
  String get sizeWallpaper => 'Wallpaper';

  @override
  String get sizeCustom => 'Custom';

  @override
  String get sizePortrait => 'Portrait';

  @override
  String get sizeLandscape => 'Landscape';

  @override
  String get sizeSquare => 'Square';

  @override
  String get sizePortraitScreen => 'Portrait';

  @override
  String get sizeLandscapeScreen => 'Landscape';

  @override
  String get width => 'Width';

  @override
  String get height => 'Height';

  @override
  String get swapDimensions => 'Swap width and height';

  @override
  String get img2img => 'Image2Image';

  @override
  String get paramStrength => 'Strength';

  @override
  String get paramNoise => 'Noise';

  @override
  String get strength => 'Strength';

  @override
  String get inpaint => 'Inpaint';

  @override
  String get inpaintStrength => 'Strength';

  @override
  String get inpaintPaint => 'Inpaint';

  @override
  String get removeMask => 'Remove Inpainting Mask';

  @override
  String get draw => 'Draw';

  @override
  String get erase => 'Erase';

  @override
  String get penSize => 'Pen Size';

  @override
  String get penSizeShort => 'Brush';

  @override
  String get holdToCompare => 'Compare with Original';

  @override
  String get presetHeavy => 'Heavy';

  @override
  String get presetLight => 'Light';

  @override
  String get presetStandard => 'Standard';

  @override
  String get presetNone => 'None';

  @override
  String get vibeTransfer => 'Vibe Transfer';

  @override
  String get referenceStrength => 'Reference Strength';

  @override
  String get infoExtracted => 'Information Extracted';

  @override
  String get normalizeStrength => 'Normalize Reference Strength Values';

  @override
  String get preciseReference => 'Precise Reference';

  @override
  String get fidelity => 'Fidelity';

  @override
  String get refCharacter => 'Character';

  @override
  String get refStyle => 'Style';

  @override
  String get refCharacterStyle => 'Char & Style';

  @override
  String get refOutfit => 'Outfit';

  @override
  String get preferSameOutfit => 'Prefer same outfit';

  @override
  String get characters => 'Characters';

  @override
  String get addCharacter => 'Add Character';

  @override
  String get position => 'Position';

  @override
  String get aiChoice => 'AI\'s Choice';

  @override
  String get aiChoicePosition => 'AI\'s Choice';

  @override
  String get aiChoiceAll => 'AI\'s Choice';

  @override
  String get savePosition => 'Save';

  @override
  String get importSteps => 'Steps';

  @override
  String get importCfg => 'Prompt Guidance';

  @override
  String get importSampler => 'Sampler';

  @override
  String get importScheduler => 'Noise Schedule';

  @override
  String get importSeed => 'Seed';

  @override
  String get ok => 'OK';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get enable => 'Enable';

  @override
  String get start => 'Start';

  @override
  String get free => 'Free';

  @override
  String get loading => 'Loading';

  @override
  String get notFetched => 'Not fetched';

  @override
  String get commaSep => ', ';

  @override
  String get tapToView => 'Tap to view';

  @override
  String get tapToReturn => 'Tap to return to the app';

  @override
  String get shortDone => 'Done';

  @override
  String get shortStopped => 'Stopped';

  @override
  String get shortPaused => 'Paused';

  @override
  String get shortFailed => 'Failed';

  @override
  String get shortPreparing => 'Prep';

  @override
  String get lpPreparing => 'Preparing…';

  @override
  String get lpGenDone => 'Generation complete';

  @override
  String get lpAssistantThinking => 'AI Assistant is thinking…';

  @override
  String get lpAssistantThinkingShort => 'Think…';

  @override
  String get lpAssistantReplied => 'AI Assistant replied';

  @override
  String get lpAssistantFailed => 'AI Assistant failed to reply';

  @override
  String get loopGenerate => 'Loop Generation';

  @override
  String vibesDisabledNoEncoding(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Vibes have no encoding for this model and were disabled',
      one: '1 Vibe has no encoding for this model and was disabled',
    );
    return '$_temp0';
  }

  @override
  String cancelTrackedJob(int count) {
    return 'Cancel the tracked job ($count running)';
  }

  @override
  String get cancelGeneration => 'Cancel Generation';

  @override
  String stepsFixed(String model, int steps) {
    return '$model always uses $steps steps';
  }

  @override
  String samplerFixed(String model, String sampler) {
    return '$model always uses the $sampler sampler';
  }

  @override
  String noiseScheduleFixed(String model) {
    return '$model always uses the karras noise schedule';
  }

  @override
  String paramUnsupported(String model, String param) {
    return '$model doesn\'t support “$param”';
  }

  @override
  String get batchLockedHires =>
      'Only 1 image while Hires Upscale is on: the second pass reruns at the upscaled size, and a batch won\'t fit in VRAM.';

  @override
  String get refDisable => 'Disable this reference';

  @override
  String refIndex(int index) {
    return 'Ref $index';
  }

  @override
  String switchModelTooltip(String model) {
    return 'Switch model: $model';
  }

  @override
  String switchModelSemantics(String model) {
    return 'Switch model, current: $model';
  }

  @override
  String get descNai5Full => 'Latest flagship · 1471 tokens · NSFW';

  @override
  String get descNai5Medium => 'Flagship, Medium tier · 40% less quota · NSFW';

  @override
  String get descNai5Curated => 'Latest curated · 703 tokens · SFW';

  @override
  String get descNai45Full => 'Legacy V4.5 · NSFW';

  @override
  String get descNai45Curated => 'Legacy V4.5 curated · SFW';

  @override
  String get descNai4Full => 'Legacy V4 · NSFW';

  @override
  String get descNai4Curated => 'Legacy V4 curated · SFW';

  @override
  String positionHint(int w, int h) {
    return '$w×$h · Tap or drag to place characters';
  }

  @override
  String get sizeMine => 'Mine';

  @override
  String get sizePhone => 'Phone';

  @override
  String get savePreset => 'Save Preset';

  @override
  String get overPixelLimit => 'Exceeds Pixel Limit';

  @override
  String confirmSize(int w, int h) {
    return 'Use $w×$h';
  }

  @override
  String get tierCostsAnlas => 'Costs Anlas';

  @override
  String get tierOverLimit => 'Over Limit';

  @override
  String get shrinkToLimit => 'Fit to Limit';

  @override
  String get shrinkToFree => 'Fit to Free';

  @override
  String get promptPresets => 'Prompt Presets';

  @override
  String get promptPresetsHelp =>
      'Added to the prompt and undesired content when generating, without filling the input boxes. V5 and 4.5 each have their own set.';

  @override
  String get sectionSampling => 'Sampling';

  @override
  String get sectionAdjust => 'Adjustments';

  @override
  String get freeUpTo28 => '≤28 Free';

  @override
  String get seedRandomTooltip => 'Random every time · Tap to enter a seed';

  @override
  String get seedManualTooltip => 'Fixed seed · Tap to randomize every time';

  @override
  String get managePresets => 'Manage Presets';

  @override
  String get loopIntro =>
      'Generates image after image with the current settings; leave the seed empty for a random one each time. Stops on errors. You can leave the app — progress continues in the notification bar.';

  @override
  String get estimatedCost => 'Estimated Cost';

  @override
  String costPerImageTotal(int cost, int total) {
    return '$cost/image · $total Anlas total';
  }

  @override
  String costPerImage(int cost) {
    return '$cost Anlas/image';
  }

  @override
  String costEncodeExtra(int fee) {
    return ' + $fee encoding';
  }

  @override
  String get infiniteLoopTitle => 'Infinite loop keeps spending Anlas';

  @override
  String infiniteLoopBody(int cost) {
    return 'About $cost Anlas per image with the current settings, and there\'s no image limit — it keeps generating until you tap Stop, even in the background. Start?';
  }

  @override
  String infiniteLoopBodyFee(int cost, int fee) {
    return 'About $cost Anlas per image with the current settings (plus $fee Anlas Vibe encoding on the first), and there\'s no image limit — it keeps generating until you tap Stop, even in the background. Start?';
  }

  @override
  String get generationBusy => 'A generation is in progress';

  @override
  String startLoop(String count) {
    return 'Start Loop $count';
  }

  @override
  String get loopRunning => 'Looping';

  @override
  String loopImageOf(int n, int total) {
    return 'Image $n / $total';
  }

  @override
  String loopImage(int n) {
    return 'Image $n';
  }

  @override
  String get loopStopping => 'Stopping after this image';

  @override
  String get loopStopAfterThis => 'Stop (after this image)';

  @override
  String get loopDone => 'Loop complete';

  @override
  String get loopAborted => 'Loop stopped';

  @override
  String get generationFailed => 'Generation failed';

  @override
  String loopDoneText(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return '$_temp0 · Tap to view';
  }

  @override
  String get queueDone => 'Queue complete';

  @override
  String get queuePaused => 'Queue paused';

  @override
  String queueDoneText(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images in total',
      one: '1 image in total',
    );
    return '$_temp0 · Tap to view';
  }

  @override
  String queueLeftText(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items left',
      one: '1 item left',
    );
    return '$_temp0';
  }

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get rename => 'Rename';

  @override
  String get disable => 'Disable';

  @override
  String get edit => 'Edit';

  @override
  String get view => 'View';

  @override
  String get close => 'Close';

  @override
  String get name => 'Name';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get untitled => 'Untitled';

  @override
  String get sectionMain => 'Main';

  @override
  String get sectionStyle => 'Style';

  @override
  String get sectionCodex => 'Codex';

  @override
  String sectionN(int n) {
    return 'Section $n';
  }

  @override
  String get clearPositivePrompt => 'Clear Prompt';

  @override
  String get clearPromptAndSections => 'Clear Prompt and Sections';

  @override
  String get inspirationLibrary => 'Inspiration Library';

  @override
  String get addSection => 'Add Section';

  @override
  String get tapToEditPositive => 'Tap to edit the prompt…';

  @override
  String get tapToEditNegative => 'Tap to edit undesired content…';

  @override
  String get tapToEdit => 'Tap to edit…';

  @override
  String get exitMultiSelect => 'Exit Selection';

  @override
  String selectedCount(int n) {
    return '$n selected';
  }

  @override
  String get saveToInspiration => 'Save to Inspiration Library';

  @override
  String get merge => 'Merge';

  @override
  String sectionsDeleted(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sections',
      one: '1 section',
    );
    return 'Deleted $_temp0';
  }

  @override
  String mergedInto(String name) {
    return 'Merged into “$name”';
  }

  @override
  String get inspirationAllExist => 'All already in the Inspiration Library';

  @override
  String inspirationSavedSkipped(int saved, int skipped) {
    return 'Saved $saved to the Inspiration Library; $skipped already there';
  }

  @override
  String inspirationSaved(int saved) {
    return 'Saved $saved to the Inspiration Library';
  }

  @override
  String inspirationAlreadyHas(String name) {
    return '“$name” is already in the Inspiration Library';
  }

  @override
  String get clearedPositivePrompt => 'Prompt cleared';

  @override
  String get clearedPromptAndSections => 'Prompt and sections cleared';

  @override
  String charactersFull(int cap, int dropped) {
    return 'Character limit ($cap) reached; $dropped not added';
  }

  @override
  String get disableKeepConfig => 'Disable (keep settings)';

  @override
  String get deleteSection => 'Delete Section';

  @override
  String deletedNamed(String name) {
    return 'Deleted “$name”';
  }

  @override
  String get deletePreset => 'Delete Preset';

  @override
  String deletePresetBody(String name) {
    return '“$name” will be deleted. If it\'s active, it falls back to “None”.';
  }

  @override
  String get newPreset => 'New Preset';

  @override
  String get viewPreset => 'View Preset';

  @override
  String get editPreset => 'Edit Preset';

  @override
  String get presetPageIntro =>
      'The active preset is added to the prompt and undesired content when generating, without filling the input boxes. Default presets can\'t be changed; create your own from the top right.';

  @override
  String get presetGroupLegacy => '4.5 and earlier';

  @override
  String get presetGroupDefault => 'Default';

  @override
  String get noPrefix => 'No prefix';

  @override
  String get placement => 'Placement';

  @override
  String get placementStart => 'Start';

  @override
  String get placementEnd => 'End';

  @override
  String get emptyHint => 'Empty…';

  @override
  String get presetName => 'Preset name';

  @override
  String get defaultPresetReadOnly =>
      'Default presets can\'t be changed; create a custom preset instead.';

  @override
  String get positivePrefix => 'Prompt Prefix';

  @override
  String get positiveSuffix => 'Prompt Suffix';

  @override
  String get negativePrefix => 'Undesired Content Prefix';

  @override
  String stepsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n steps',
      one: '1 step',
    );
    return '$_temp0';
  }

  @override
  String get sampler => 'Sampler';

  @override
  String get noiseSchedule => 'Noise Schedule';

  @override
  String get scheduler => 'Scheduler';

  @override
  String applyRecipeTitle(String name) {
    return 'Apply the recommended settings from “$name”?';
  }

  @override
  String get apply => 'Apply';

  @override
  String get dontApply => 'Skip';

  @override
  String recipeApplied(String name) {
    return 'Applied the recommended settings from “$name”';
  }

  @override
  String get more => 'More';

  @override
  String get refDefaultName => 'Reference';

  @override
  String get refMutexVibePaused =>
      'Can\'t be combined with Vibe Transfer; Vibe Transfer paused';

  @override
  String get refMutexCharRefPaused =>
      'Can\'t be combined with Precise Reference; Precise Reference paused';

  @override
  String get refLibrary => 'Reference Library';

  @override
  String get importCharRef => 'Import Reference Image';

  @override
  String get charRefOnly45 =>
      'Precise Reference isn\'t supported by the current model and won\'t be sent.';

  @override
  String get charRefOutfitSkipped =>
      'The current model doesn\'t support Outfit references; enabled Outfit images will be skipped.';

  @override
  String get charRefIgnoredInpaint =>
      'Precise Reference isn\'t supported when inpainting with this model.';

  @override
  String charRefMaxExceeded(int max) {
    return 'Up to $max reference images can be used at once; extra ones will be skipped.';
  }

  @override
  String filesImportFailed(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n files couldn\'t be imported',
      one: '1 file couldn\'t be imported',
    );
    return '$_temp0';
  }

  @override
  String get nothingToImport => 'Nothing to import';

  @override
  String get inactiveWhenInpainting => 'Not used when inpainting';

  @override
  String get vibeLibrary => 'Vibe Library';

  @override
  String get importVibe => 'Import Vibe Image';

  @override
  String get infoExtractedFixed => 'Information Extracted (fixed by encoding)';

  @override
  String resolutionMatchedBase(int w, int h) {
    return 'Resolution set to $w×$h to match the base image';
  }

  @override
  String get removeBaseImage => 'Remove Base Image';

  @override
  String get changeBaseImage => 'Change Base Image';

  @override
  String get selectBaseImage => 'Select Base Image';

  @override
  String get cantReadRef => 'Couldn\'t read this reference image';

  @override
  String get deleteRefImage => 'Delete Reference Image';

  @override
  String deleteRefsBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'The $n selected images',
      one: 'The selected image',
    );
    return '$_temp0 will be deleted from the library along with files and thumbnails. This can\'t be undone.';
  }

  @override
  String get refImageName => 'Reference name';

  @override
  String deleteRefBody(String name) {
    return '“$name” will be removed from the library (copies already on the Create page stay). This can\'t be undone.';
  }

  @override
  String refsAdded(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Added $n reference images',
      one: 'Added 1 reference image',
    );
    return '$_temp0';
  }

  @override
  String get charRefLibrary => 'Precise Reference Library';

  @override
  String get searchName => 'Search names…';

  @override
  String get noCharRefs => 'No reference images yet';

  @override
  String get noMatchingRefs => 'No matching reference images';

  @override
  String get charRefLibraryHint =>
      'Reference images you import on the Create page are saved here automatically';

  @override
  String confirmSelectionN(int n) {
    return 'Confirm ($n)';
  }

  @override
  String get confirmSelection => 'Confirm';

  @override
  String get defaultCanvas => 'Default Canvas';

  @override
  String canvasN(int n) {
    return 'Canvas $n';
  }

  @override
  String get canvasCopySuffix => ' · Copy';

  @override
  String characterN(int n) {
    return 'Character $n';
  }

  @override
  String get switchCanvas => 'Switch Canvas';

  @override
  String currentCanvasSemantics(String name, int count) {
    return 'Current canvas: $name, $count in total';
  }

  @override
  String get renameCanvas => 'Rename Canvas';

  @override
  String get canvasName => 'Canvas name';

  @override
  String get canvases => 'Canvases';

  @override
  String get newCanvas => 'New Canvas';

  @override
  String get duplicateCurrent => 'Duplicate';

  @override
  String get history => 'History';

  @override
  String get defaultCanvasLocked =>
      'Default canvas — pinned to the top; can\'t be deleted or renamed';

  @override
  String get noPromptYet => 'No prompt yet';

  @override
  String get noCharacters => 'No characters';

  @override
  String get previewOnlyNoImage =>
      'No final image received, only a preview frame';

  @override
  String poolFull(int n) {
    return 'Up to $n jobs at a time; wait for earlier ones to finish';
  }

  @override
  String get jobWaiting => 'Waiting';

  @override
  String get jobSaving => 'Saving';

  @override
  String get noEligibleToken =>
      'No token can take this job (check each token\'s participation settings)';

  @override
  String get naiTokenNotSet => 'NovelAI token not set';

  @override
  String generationFailedWith(String error) {
    return 'Generation failed: $error';
  }

  @override
  String rateLimitedRetryIn(int secs, int n, int total) {
    return 'Rate limited · retrying in ${secs}s ($n/$total)';
  }

  @override
  String rateLimitedRetryNow(int n, int total) {
    return 'Rate limited · retrying now ($n/$total)';
  }

  @override
  String get shortRateLimited => 'Limited';

  @override
  String notifyImageOf(int n, int total) {
    return 'Image $n/$total';
  }

  @override
  String notifyQueueOf(int n, int total) {
    return 'Queue $n/$total';
  }

  @override
  String shortImages(int n) {
    return '$n imgs';
  }

  @override
  String generatingCount(int n) {
    return 'Generating · $n images';
  }

  @override
  String get generatingEllipsis => 'Generating…';

  @override
  String generatingCountStep(int n, int step, int total) {
    return 'Generating · $n images ($step/$total)';
  }

  @override
  String generatingStep(int step, int total) {
    return 'Generating $step/$total';
  }

  @override
  String get noTokenCantEncode => 'No token set; can\'t encode';

  @override
  String get anlasAndQuota => 'Anlas & Quota';

  @override
  String get refresh => 'Refresh';

  @override
  String get subscriptionTier => 'Subscription';

  @override
  String get anlasPoints => 'Anlas';

  @override
  String get refillRate => 'Refill Rate';

  @override
  String imagesPerHour(String n) {
    return '$n images / hr';
  }

  @override
  String get timeToFull => 'Until Full';

  @override
  String get nai5Quota => 'NAI 5 Quota';

  @override
  String nai5QuotaAccounts(int n) {
    return 'NAI 5 Quota · $n accounts';
  }

  @override
  String get notProvided => 'Not provided';

  @override
  String get opusOnly => 'Opus only';

  @override
  String aboutImages(String n) {
    return '~$n images';
  }

  @override
  String get quotaExhausted => 'Used up · free sizes now cost Anlas';

  @override
  String get quotaFull => 'Full';

  @override
  String quotaIn24h(String pct) {
    return '$pct% in 24 h';
  }

  @override
  String aboutHours(int n) {
    return '~$n h';
  }

  @override
  String aboutDays(String n) {
    return '~$n days';
  }

  @override
  String switchedToModel(String model) {
    return 'Switched to $model';
  }

  @override
  String moduleOfProvider(String module, String provider) {
    return '“$module” is a $provider feature';
  }

  @override
  String moduleHidden(String module) {
    return '“$module” is hidden in the Create page modules';
  }

  @override
  String importedPreset(String name) {
    return 'Preset $name';
  }

  @override
  String vibesEncodingOnly(int n, String model) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Vibes are',
      one: '1 Vibe is',
    );
    return '$_temp0 encoding-only and usable with $model only';
  }

  @override
  String get importedToCreate => 'Imported to the Create page';

  @override
  String importedWith(String details) {
    return 'Imported · $details';
  }

  @override
  String setAsBaseImageRes(int w, int h) {
    return 'Set as the Image2Image base · resolution $w×$h';
  }

  @override
  String get setAsBaseImage => 'Set as the Image2Image base';

  @override
  String get addedVibeMutex =>
      'Added to Vibe Transfer · Precise Reference paused (can\'t be combined)';

  @override
  String get addedVibe => 'Added to Vibe Transfer';

  @override
  String get addedCharRefMutex =>
      'Added to Precise Reference · Vibe Transfer paused (can\'t be combined)';

  @override
  String get addedCharRef => 'Added to Precise Reference';

  @override
  String get importReplace => 'Replace';

  @override
  String get importNewSection => 'New Section';

  @override
  String get importAppend => 'Append';

  @override
  String get noParamsUseAsRef =>
      'No generation settings found in this image; you can still use it as a reference.';

  @override
  String get useImageAs => 'Use this image as';

  @override
  String get importToCreate => 'Import to Create Page';

  @override
  String promptOnlyCrossModel(String image, String current) {
    return 'This image was made with $image; the current model is $current, so only prompts can be imported.';
  }

  @override
  String promptOnlyUnknown(String source) {
    return 'There\'s no matching model here for $source images, so only prompts can be imported.';
  }

  @override
  String partialCrossModel(String other, String current) {
    return 'This image used a $other model and the current model is $current; only some settings can be imported';
  }

  @override
  String get partialUnknown =>
      'This image\'s model isn\'t available here; only some settings can be imported';

  @override
  String foreignModel(String other) {
    return 'This image used a $other model';
  }

  @override
  String get notLocalModel => 'Not a model supported here';

  @override
  String get presetNeedPrompt => 'Select the prompt or undesired content first';

  @override
  String presetStripSwitch(String name) {
    return 'The text above will be removed from the prompt and the preset switched to “$name”.';
  }

  @override
  String get presetStripKeep =>
      'The text above will be removed from the prompt; the preset stays the same.';

  @override
  String get presetNoPositive => '(This preset adds no prompt text)';

  @override
  String get autoConvertPrompt => 'Convert Prompt Syntax';

  @override
  String get autoConvertPromptHint =>
      'Turns (tag:1.2) into NovelAI\'s 1.2::tag::';

  @override
  String noParamsSize(String size) {
    return 'No generation settings · $size';
  }

  @override
  String charactersBadge(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String copyWhat(String what) {
    return 'Copy $what';
  }

  @override
  String copiedWhat(String what) {
    return 'Copied $what';
  }

  @override
  String get seed => 'Seed';

  @override
  String copiedSeed(String value) {
    return 'Copied seed $value';
  }

  @override
  String vibeParams(String strength, String ie) {
    return 'Strength $strength · IE $ie';
  }

  @override
  String encodingOnlyParams(String params) {
    return 'Encoding only · $params';
  }

  @override
  String get encodingOnlyUnknown =>
      'Encoding only · unknown source model; can\'t import';

  @override
  String get paramsOnlyCantImport => 'Settings only; can\'t import';

  @override
  String get genSettings => 'Generation Settings';

  @override
  String unsupportedParams(String params) {
    return 'Contains settings this version doesn\'t support ($params); generation settings can\'t be imported.';
  }

  @override
  String get importMode => 'Import Mode';

  @override
  String get emptyParen => '(empty)';

  @override
  String get importSelected => 'Import Selected';

  @override
  String get useAsReference => 'Reference';

  @override
  String get unknownSource => 'Unknown Source';

  @override
  String get fullMetadataTwoLine => 'Full\nMetadata';

  @override
  String get fullMetadata => 'Full Metadata';

  @override
  String get closeImport => 'Close Import';

  @override
  String get goToImportPanel =>
      'Open Import Panel (settings / use as reference)';

  @override
  String get fileSize => 'File Size';

  @override
  String get format => 'Format';

  @override
  String get source => 'Source';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get transparentBg => 'Transparent Background';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get alphaStraight => 'Straight';

  @override
  String get alphaPremultiplied => 'Premultiplied';

  @override
  String get genParams => 'Generation Parameters';

  @override
  String vibeStrengthLabel(String v) {
    return 'Strength: $v';
  }

  @override
  String vibeExtractedLabel(String v) {
    return 'Extracted: $v';
  }

  @override
  String get rawData => 'Raw Data';

  @override
  String get genInProgressWait => 'Generation in progress, please wait';

  @override
  String get notAligned64Expand =>
      'Image size isn\'t a multiple of 64; can\'t expand';

  @override
  String get expandTooLarge =>
      'Expanded size is too large; reduce the expansion';

  @override
  String get savedToInpaint => 'Saved to Inpaint';

  @override
  String get censorNothingFound => 'No areas to censor were detected';

  @override
  String censorDetected(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Detected $n areas',
      one: 'Detected 1 area',
    );
    return '$_temp0, pre-filled';
  }

  @override
  String censorDetectFailed(String error) {
    return 'Auto-detect failed: $error';
  }

  @override
  String get censorColor => 'Censor Color';

  @override
  String get paintCensorFirst => 'Paint the areas to censor first';

  @override
  String get censoredSaved => 'Censored and saved to the gallery';

  @override
  String censorFailed(String error) {
    return 'Censoring failed: $error';
  }

  @override
  String inpaintNeedNai(String model) {
    return '$model doesn\'t support inpainting; switch back to a NovelAI model';
  }

  @override
  String get dragEdgesFirst => 'Drag the edges to expand the canvas first';

  @override
  String get paintInpaintFirst => 'Paint the areas to inpaint first';

  @override
  String get noPaintInBox => 'Nothing painted inside the yellow box';

  @override
  String get paintOutsideBox =>
      'There\'s paint outside the yellow box; enlarge the box or inpaint in two passes';

  @override
  String get sendTooLarge =>
      'Send size is too large; turn on “Region” to narrow it';

  @override
  String get notAligned64UseRegion =>
      'Image size isn\'t a multiple of 64; use “Region” mode';

  @override
  String get tabExpand => 'Expand';

  @override
  String get tabCensor => 'Censor';

  @override
  String get toolOffset => 'Offset';

  @override
  String get toolRegion => 'Region';

  @override
  String get censorBlock => 'Block';

  @override
  String get censorColorShort => 'Color';

  @override
  String get saveMask => 'Save';

  @override
  String get saveExpand => 'Save Expansion';

  @override
  String get autoDetect => 'Detect';

  @override
  String get detecting => 'Detecting…';

  @override
  String get savingEllipsis => 'Saving…';

  @override
  String get mosaicBlock => 'Mosaic Block';

  @override
  String get expandSize => 'Expansion Size';

  @override
  String get widthShort => 'Width';

  @override
  String get heightShort => 'Height';

  @override
  String expandHint(int w, int h) {
    return 'Original $w×$h; added space is split evenly on both sides (64-aligned)';
  }

  @override
  String get censorMosaic => 'Mosaic';

  @override
  String get censorSolid => 'Solid';

  @override
  String get colorBlack => 'Black';

  @override
  String get colorDarkGray => 'Dark Gray';

  @override
  String get colorLightGray => 'Light Gray';

  @override
  String get colorWhite => 'White';

  @override
  String weightGroupInfo(String group, String total) {
    return 'In weight group ×$group · total ×$total';
  }

  @override
  String weightGroupOnly(String group) {
    return 'In weight group ×$group';
  }

  @override
  String get selectWholeGroup => 'Select Group';

  @override
  String get sdWeightConvert =>
      'SD weight syntax · tap to convert to NAI format';

  @override
  String get sdWeightConvertShort => 'SD weight syntax · convert to NAI';

  @override
  String get weight => 'Weight';

  @override
  String get clearWeight => 'Clear Weight';

  @override
  String get clearWeightShort => 'Reset';

  @override
  String get related => 'Related';

  @override
  String get disableTag => 'Disable';

  @override
  String get tagLabel => 'Tag';

  @override
  String get tagCopied => 'Tag copied';

  @override
  String get cantOpenBrowser => 'Couldn\'t open the browser';

  @override
  String get tapPlusToMove => 'Tap + to move';

  @override
  String selectedItems(int n) {
    return '$n selected';
  }

  @override
  String get tapTagsToSelect => 'Tap tags to select';

  @override
  String get extractAsSection => 'Extract as New Section';

  @override
  String foldSegment(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n tags',
      one: '1 tag',
    );
    return 'Fold · $_temp0';
  }

  @override
  String get expand => 'Expand';

  @override
  String get collapse => 'Collapse';

  @override
  String get overall => 'Overall';

  @override
  String get move => 'Move';

  @override
  String get editorSettings => 'Editor Settings';

  @override
  String get settingDisplay => 'Display';

  @override
  String get showTranslations => 'Show Translations';

  @override
  String get showTranslationsDesc =>
      'Show the Chinese translation in small text under each tag';

  @override
  String get weightHighlight => 'Weight Highlight';

  @override
  String get weightHighlightDesc =>
      'Color strengthened / weakened tags red / blue by amount';

  @override
  String get textFontSize => 'Text Size';

  @override
  String get textFontSizeDesc => 'Text size in text mode';

  @override
  String get chipFontSize => 'Chip Size';

  @override
  String get chipFontSizeDesc => 'Chip size in chip mode';

  @override
  String get settingCompletion => 'Autocomplete';

  @override
  String get enableCompletion => 'Autocomplete Suggestions';

  @override
  String get enableCompletionDesc => 'Suggest tags at the bottom while typing';

  @override
  String get entitySuggestions => 'Entity Suggestions';

  @override
  String get entitySuggestionsDesc =>
      'Include artists / characters / OCs / works in suggestions';

  @override
  String get autoComma => 'Auto Comma';

  @override
  String get autoCommaDesc =>
      'Add “, ” after picking a suggestion, ready for the next tag';

  @override
  String get settingTagBar => 'Tag Bar';

  @override
  String get enableTagPanel => 'Tag Panel';

  @override
  String get enableTagPanelDesc =>
      'Show weight and actions when the cursor is on a tag';

  @override
  String get compactTagBar => 'Compact Tag Bar';

  @override
  String get compactTagBarDesc =>
      'A single row with just weight and delete, leaving room for more text';

  @override
  String get weightStep => 'Weight Step';

  @override
  String get weightStepDesc => 'How much each +/− step changes the value';

  @override
  String get kindArtist => 'Artists';

  @override
  String get kindWork => 'Works';

  @override
  String get kindTag => 'Tags';

  @override
  String get completionResults => 'Suggestions';

  @override
  String itemsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get byHeat => 'Popular';

  @override
  String get wikiMissing =>
      'Couldn\'t get the Wiki summary. Tap again or view it on Danbooru.';

  @override
  String get loadingWiki => 'Loading Wiki…';

  @override
  String aliases(String list) {
    return 'Aliases: $list';
  }

  @override
  String wikiLinkCopied(String url) {
    return 'Copied Wiki link: $url';
  }

  @override
  String unfavorited(String tag) {
    return 'Removed “$tag” from favorites';
  }

  @override
  String get noFavorites => 'No favorites';

  @override
  String get modeText => 'Text';

  @override
  String get modeChips => 'Chips';

  @override
  String get positiveShort => 'Positive';

  @override
  String get negativeShort => 'Negative';

  @override
  String get translateFailed => 'Translation failed; try again later';

  @override
  String copiedItems(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return 'Copied $_temp0';
  }

  @override
  String get cantExtractFold =>
      'The selection is joined to a fold and can\'t be extracted';

  @override
  String extractedTo(String name) {
    return 'Extracted to “$name”';
  }

  @override
  String get editorInputHint =>
      'Tap to enter tags; typing Chinese brings up translations and suggestions';

  @override
  String get translating => 'Translating…';

  @override
  String querying(String q) {
    return 'Looking up “$q”…';
  }

  @override
  String noMatchAddTag(String q) {
    return 'No match · tap to add “$q” as a new tag';
  }

  @override
  String get workNote => 'Tap the die for a random character';

  @override
  String get translateToEnglish => 'Translate to English';

  @override
  String get chipInputHint => 'Enter tags; Chinese is translated automatically';

  @override
  String get addMore => 'Add more…';

  @override
  String get saveAndBack => 'Save and Return';

  @override
  String get localLibrary => 'Local';

  @override
  String get untitledVibe => 'Untitled Vibe';

  @override
  String get favorites => 'Favorites';

  @override
  String get vibeNoEncodingForModel =>
      'This Vibe has no encoding for the current model and can\'t be used';

  @override
  String get cantReadVibe => 'Couldn\'t read this Vibe file';

  @override
  String ingestVibes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Vibes',
      one: '1 Vibe',
    );
    return '$_temp0';
  }

  @override
  String ingestImages(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String ingestFailed(int n) {
    return '$n failed';
  }

  @override
  String importDone(String details) {
    return 'Import complete: $details';
  }

  @override
  String get deleteVibe => 'Delete Vibe';

  @override
  String deleteVibesBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'The $n selected Vibes',
      one: 'The selected Vibe',
    );
    return '$_temp0 will be deleted from the library along with files and thumbnails. This can\'t be undone.';
  }

  @override
  String deleteVibeBody(String name) {
    return '“$name” will be deleted from the library along with its file and thumbnail. This can\'t be undone.';
  }

  @override
  String vibesExported(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Vibes',
      one: '1 Vibe',
    );
    return 'Exported $_temp0';
  }

  @override
  String exportedName(String name) {
    return 'Exported $name';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get batchAddTag => 'Add Tag to Selected';

  @override
  String get tagNameHint => 'Tag name, e.g. landscape';

  @override
  String tagAddedToN(int n, String tag) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Vibes',
      one: '1 Vibe',
    );
    return 'Added tag “$tag” to $_temp0';
  }

  @override
  String get addedToGenerate => 'Added to the Create page';

  @override
  String get alreadyInGenerate => 'Already on the Create page';

  @override
  String get notAvailableYet => 'Not available yet';

  @override
  String get vibeManager => 'Vibe Manager';

  @override
  String get importLabel => 'Import';

  @override
  String get importVibeFile => 'Import Vibe File';

  @override
  String get searchNameOrTag => 'Search names or tags…';

  @override
  String localCount(int n) {
    return 'Local · $n';
  }

  @override
  String get publicLibrary => 'Public';

  @override
  String get all => 'All';

  @override
  String get manageTags => 'Manage Tags';

  @override
  String get noLocalVibes => 'No local Vibes';

  @override
  String get noMatchingVibes => 'No matching Vibes';

  @override
  String get tapPlusToImport => 'Tap + at the top right to import';

  @override
  String get publicVibeUnavailable =>
      'The public Vibe library isn\'t available yet';

  @override
  String get bundle => 'Bundle';

  @override
  String get notEncoded => 'Not encoded';

  @override
  String needsModels(String models) {
    return 'Needs $models';
  }

  @override
  String get detailsAndParams => 'Details & Settings';

  @override
  String get editTags => 'Edit Tags';

  @override
  String get publishToPublic => 'Publish to Public';

  @override
  String get export => 'Export';

  @override
  String get noTagsYetBelow => 'No tags yet. Type below to create one.';

  @override
  String get newTagHint => 'New tag, e.g. landscape';

  @override
  String tagExists(String name) {
    return 'Tag “$name” already exists';
  }

  @override
  String get renameTag => 'Rename Tag';

  @override
  String get deleteTag => 'Delete Tag';

  @override
  String deleteTagBody(String tag) {
    return 'Tag “$tag” will be removed from all Vibes (the Vibes themselves stay).';
  }

  @override
  String get newLabel => 'New';

  @override
  String get noTagsYetHint =>
      'No tags yet\nCreate one in the box above, or from a Vibe\'s “Edit Tags”';

  @override
  String get vibeNoImageOrEncoding =>
      'This Vibe has no usable image or encoding';

  @override
  String get encodingOnlyNoImage => 'Encoding only (no original image)';

  @override
  String get defaultStrength => 'Default Reference Strength';

  @override
  String get defaultInfoExtracted => 'Default Information Extracted';

  @override
  String get ieFixedNoImage =>
      'Information Extracted is fixed by the encoding and can\'t be changed without the original image.';

  @override
  String get addToGenerate => 'Add to Create Page';

  @override
  String get encodings => 'Encodings';

  @override
  String get checking => 'Checking…';

  @override
  String encodedN(int n) {
    return 'Encoded $n';
  }

  @override
  String get clearAllCharacters => 'Clear All Characters';

  @override
  String get characterLibrary => 'Character Library';

  @override
  String get clearAllCharactersQ => 'Clear all characters?';

  @override
  String get clearAllCharactersBody =>
      'All characters and their settings will be removed. This can\'t be undone.';

  @override
  String replaceCharQ(String name) {
    return 'Replace “$name”?';
  }

  @override
  String replaceCharBody(String name) {
    return 'Its prompts will be replaced with those of “$name”.';
  }

  @override
  String get replace => 'Replace';

  @override
  String get deleteCharacter => 'Delete Character';

  @override
  String setCharPosition(String pos) {
    return 'Set character position: $pos';
  }

  @override
  String get tapToEditPrompt => 'Tap to edit the prompt…';

  @override
  String get pickFromCharLibrary => 'Pick from Character Library';

  @override
  String get swapCharacter => 'Change Character';

  @override
  String get canvasSingular => 'Canvas';

  @override
  String canvasHistoryTitle(String name) {
    return '$name · History';
  }

  @override
  String get noHistoryYet => 'No images generated on this canvas yet';

  @override
  String get restoreThisVersion => 'Restore This Version';

  @override
  String get duplicateAsNewCanvas => 'Duplicate as New Canvas';

  @override
  String get duplicatedAsNewCanvas => 'Duplicated as a new canvas';

  @override
  String restoredTo(String time) {
    return 'Restored the version from $time';
  }

  @override
  String imagesN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get noPrompt => 'No prompt';

  @override
  String get negChanged => 'Undesired content changed';

  @override
  String charsChange(int a, int b) {
    return 'Characters $a→$b';
  }

  @override
  String get addedBaseImage => 'Base image added';

  @override
  String get removedBaseImage => 'Base image removed';

  @override
  String get addedInpaint => 'Inpaint added';

  @override
  String get removedInpaint => 'Inpaint removed';

  @override
  String stepsChange(int a, int b) {
    return '$a→$b steps';
  }

  @override
  String get paramsChanged => 'Settings changed';

  @override
  String dateYesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String dateMonthDay(String month, int day, String time) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '$month',
    });
    return '$_temp0 $day $time';
  }

  @override
  String dateYearMonthDay(int year, String month, int day, String time) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '$month',
    });
    return '$_temp0 $day, $year $time';
  }

  @override
  String get tabCreate => 'Create';

  @override
  String get gallery => 'Gallery';

  @override
  String get tabInspiration => 'Ideas';

  @override
  String get tabProfile => 'Profile';

  @override
  String get setTokenFirst =>
      'Set up your NovelAI API Token on the Profile page first';

  @override
  String get goToSettings => 'Go to Settings';

  @override
  String savedToAlbum(String name) {
    return 'New images saved to “$name”';
  }

  @override
  String get viewAfterEditing => 'Finish editing to view the new images';

  @override
  String get imageDeleted => 'This image has been deleted';

  @override
  String get keyWiped =>
      'Your saved key was cleared by the system. Add it again and it will stay.';

  @override
  String get goToAdd => 'Add Key';

  @override
  String get allImages => 'All Images';

  @override
  String get albums => 'Albums';

  @override
  String get noAlbums => 'No albums';

  @override
  String get selectImage => 'Select Image';

  @override
  String get pickFromFiles => 'Pick from Files';

  @override
  String get noImages => 'No images';

  @override
  String okCount(int n) {
    return 'OK ($n)';
  }

  @override
  String get limitedPhotoAccess => 'Access to some photos only';

  @override
  String get adjust => 'Manage';

  @override
  String get needPhotoPermission => 'Photo access needed';

  @override
  String get recheck => 'Check Again';

  @override
  String get enterNumber => 'Enter a number';

  @override
  String outOfRange(String range) {
    return 'Out of range $range';
  }

  @override
  String rangeHint(String range) {
    return 'Range $range';
  }

  @override
  String rangeStepHint(String range, String step) {
    return 'Range $range · step $step';
  }

  @override
  String overwriteConflicts(int n) {
    return '$n will overwrite local items with the same id';
  }

  @override
  String mergeWithConflicts(int n) {
    return 'Merged by id: $n items with the same id are overwritten and the rest added; local-only items are kept.';
  }

  @override
  String get mergeNoLoss => 'Merged by id: nothing already here will be lost.';

  @override
  String get clearSelection => 'Deselect';

  @override
  String get closeMenu => 'Close menu';

  @override
  String floatCardsColor(String color) {
    return 'Floating Cards · $color';
  }

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorGold => 'Gold';

  @override
  String get colorLightBlue => 'Light Blue';

  @override
  String get colorTeal => 'Teal';

  @override
  String get switchedToFloat =>
      'Switched to Floating Cards; you can switch back in Appearance & Haptics';

  @override
  String get switchBack => 'Switch Back';

  @override
  String get tryNewTheme => 'Try the new theme?';

  @override
  String get newThemeBody =>
      'A fresh new look is here! Cleaner cards — pick a color you like~';

  @override
  String get later => 'Later';

  @override
  String get tryIt => 'Try It';

  @override
  String get backup => 'Backup';

  @override
  String get about => 'About';

  @override
  String get accountAccess => 'Account & Access';

  @override
  String get accountAccessSub => 'Token & Bot authorization';

  @override
  String get stats => 'Statistics';

  @override
  String get statsSub => 'Usage · Wallet · Platform stats';

  @override
  String get promptPresetsSub => 'Prompt & undesired content templates';

  @override
  String get genSettingsSub => 'Auto-retry · Modules · Saving';

  @override
  String get toolbox => 'Toolbox';

  @override
  String get toolboxSub => 'Weight converter · Image metadata';

  @override
  String get appearanceHaptics => 'Appearance & Haptics';

  @override
  String get appearanceSub => 'Theme colors · Haptic feedback';

  @override
  String get storage => 'Storage';

  @override
  String get storageSub => 'Space usage & cleanup';

  @override
  String get themeMode => 'Dark Mode';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get bottomNav => 'Bottom Navigation';

  @override
  String get showAssistant => 'Show AI Assistant';

  @override
  String get showAssistantSub =>
      'When off, the AI tab is hidden from the bottom bar';

  @override
  String get createPage => 'Create Page';

  @override
  String get compactCharCards => 'Compact Character Cards';

  @override
  String get haptics => 'Haptics';

  @override
  String get hapticFeedback => 'Haptic Feedback';

  @override
  String get galleryPicker => 'Image Picker';

  @override
  String get inApp => 'In-App';

  @override
  String get system => 'System';

  @override
  String get beta => 'Beta';

  @override
  String get version => 'Version';

  @override
  String get dataResources => 'Data & Resources';

  @override
  String get codexSource => 'Codex';

  @override
  String get offlineDict => 'Offline Tag Dictionary';

  @override
  String get zhSearch => 'Chinese Search & Translations';

  @override
  String get imageGen => 'Image Generation';

  @override
  String get censorModel => 'Auto-censor Model';

  @override
  String get community => 'Community';

  @override
  String get qqGroup => 'QQ Group';

  @override
  String get guide => 'Guide';

  @override
  String get reviewGuide => 'View the Guide Again';

  @override
  String get legal => 'Legal';

  @override
  String get sourceCode => 'Source Code';

  @override
  String get license => 'License';

  @override
  String get thirdPartyLicenses => 'Third-party Licenses';

  @override
  String disclaimer(String app) {
    return '$app is a third-party client and isn\'t affiliated with NovelAI. Images are generated by NovelAI; you\'re responsible for your account and everything you generate.';
  }

  @override
  String qqCopied(String id) {
    return 'Group number $id copied';
  }

  @override
  String get cantOpenBrowserShort => 'Couldn\'t open the browser';

  @override
  String get appTagline => 'A mobile client for NovelAI';

  @override
  String legaleseBody(String app) {
    return 'This program is free software, distributed under the GNU GPL v3 or later. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY.\n\n$app is a third-party client and isn\'t affiliated with NovelAI.';
  }

  @override
  String get noUpdateInfo => 'No update info';

  @override
  String get onLatestVersion => 'You\'re on the latest version';

  @override
  String get checkFailed => 'Check failed';

  @override
  String newVersion(String v) {
    return 'New version $v';
  }

  @override
  String get upToDate => 'Up to date';

  @override
  String get checkUpdates => 'Check for Updates';

  @override
  String currentVersion(String v) {
    return 'Current $v';
  }

  @override
  String get downloadOnGithub => 'Download on GitHub';

  @override
  String get downloadUpdate => 'Download update';

  @override
  String updateHttpFailed(int code) {
    return 'Update check failed (HTTP $code)';
  }

  @override
  String get updateBadFormat => 'Unexpected update info format';

  @override
  String get updateTimeout =>
      'Update check timed out; check your network and try again';

  @override
  String get cantReachUpdateServer =>
      'Can\'t reach the server; check your network and try again';

  @override
  String get updateFailed => 'Update check failed; try again later';

  @override
  String get weightConverter => 'Convert Weights';

  @override
  String get imageMetadata => 'Image Metadata';

  @override
  String get compareImages => 'Compare';

  @override
  String get swapAB => 'Swap A / B';

  @override
  String get onlyInA => 'A only';

  @override
  String get onlyInB => 'B only';

  @override
  String get weightChanged => 'Weight';

  @override
  String get orderChanged => 'Moved';

  @override
  String get identical => 'Same';

  @override
  String identicalN(int n) {
    return '$n same';
  }

  @override
  String differentN(int n) {
    return '$n different';
  }

  @override
  String get enterOverwritePrompt => 'Enter the prompt to write first';

  @override
  String get noPhotoPermission => 'No photo access';

  @override
  String savedToPhotos(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return 'Saved $_temp0 to Photos';
  }

  @override
  String savedToPhotosFailed(int saved, int failed) {
    return 'Saved $saved · $failed failed';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String get addImages => 'Add Images';

  @override
  String get metadataToolIntro =>
      'View generation settings · Clear or overwrite metadata in bulk';

  @override
  String get overwritePromptHint => 'Prompt to write into the images…';

  @override
  String get clearMeta => 'Clear';

  @override
  String get overwrite => 'Overwrite';

  @override
  String saveToPhotosN(int n) {
    return 'Save ($n)';
  }

  @override
  String get imageInfo => 'Image Info';

  @override
  String noMetadataFor(String name) {
    return '$name · No metadata found';
  }

  @override
  String get promptImported => 'Prompt imported';

  @override
  String get stripLora => 'Strip LoRA';

  @override
  String get convert => 'Convert';

  @override
  String get importPrompt => 'Import Prompt';

  @override
  String get copyResult => 'Copy Result';

  @override
  String get genNotify => 'Generation Notifications';

  @override
  String get streamingGen => 'Streaming Preview';

  @override
  String get straightAlpha => 'Straight Alpha for Transparency';

  @override
  String get keepImageFormat => 'Keep Image Format';

  @override
  String get autoRetry => 'Auto-retry When Rate Limited';

  @override
  String get retryDelay => 'Retry Delay';

  @override
  String secondsN(int n) {
    return '$n s';
  }

  @override
  String get immediately => 'Immediately';

  @override
  String get unitSeconds => 's';

  @override
  String get retryCount => 'Retries';

  @override
  String timesN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n times',
      one: '1 time',
    );
    return '$_temp0';
  }

  @override
  String get unitTimes => 'times';

  @override
  String get galleryDefaultSave => 'Gallery Save Defaults';

  @override
  String get createPageModules => 'Create Page Modules';

  @override
  String modulesOn(int on, int total) {
    return '$on/$total on';
  }

  @override
  String get pngLossless => 'PNG Lossless';

  @override
  String get jpgLossy => 'JPG Lossy';

  @override
  String get rawMetadata => 'Original';

  @override
  String get compressQuality => 'Quality';

  @override
  String get compressQualityDialog => 'Quality (10–100)';

  @override
  String get customPrompt => 'Custom Prompt';

  @override
  String get customPromptHint =>
      'Prompt to write into images (other settings are cleared)…';

  @override
  String get notSet => 'Not set';

  @override
  String get catCache => 'Cache Files';

  @override
  String get catVibeEnc => 'Vibe Encoding Cache';

  @override
  String get catModels => 'Upscale Models (legacy)';

  @override
  String get catTagPrev => 'Inspiration Previews';

  @override
  String get catGallery => 'Gallery Images';

  @override
  String get catCharLib => 'Reference Library';

  @override
  String get actClean => 'Clean';

  @override
  String freedSize(String size) {
    return 'Freed $size';
  }

  @override
  String get nothingToClean => 'Nothing to clean up';

  @override
  String cleanFailed(String error) {
    return 'Cleanup failed: $error';
  }

  @override
  String get clearTagPreviews => 'Clear Inspiration Previews';

  @override
  String get clearTagPreviewsBody =>
      'Deletes the entry previews generated on this device and unlinks them from their entries. Entries and prompts stay; previews will need to be regenerated.';

  @override
  String clearTagPreviewsBodyN(int n) {
    return 'Deletes the $n entry previews generated on this device and unlinks them from their entries. Entries and prompts stay; previews will need to be regenerated.';
  }

  @override
  String get clearAllAlbums => 'Clear All Gallery Data';

  @override
  String get clearAllAlbumsBody =>
      'Deletes all images, settings snapshots, and your albums and covers. This can\'t be undone. Images already saved to your device\'s photos stay.';

  @override
  String clearAllAlbumsBodyN(int n) {
    return 'Deletes all $n images, settings snapshots, and your albums and covers. This can\'t be undone. Images already saved to your device\'s photos stay.';
  }

  @override
  String get clearEncodingCache => 'Clear Encoding Cache';

  @override
  String get clearEncodingCacheBody =>
      'These images will need re-encoding the next time you use them; on a direct connection that costs about 2 Anlas each. Vibe library files themselves stay.';

  @override
  String get clearVibeLib => 'Clear Vibe Library';

  @override
  String get clearVibeLibBody =>
      'Deletes all files in the library (originals / thumbnails / saved encodings). This can\'t be undone.';

  @override
  String clearVibeLibBodyN(int n) {
    return 'Deletes all $n files in the library (originals / thumbnails / saved encodings). This can\'t be undone.';
  }

  @override
  String get clearCharRefLib => 'Clear Reference Library';

  @override
  String get clearCharRefLibBody =>
      'Deletes all files in the library. This can\'t be undone. Settings snapshots in the gallery stay.';

  @override
  String clearCharRefLibBodyN(int n) {
    return 'Deletes all $n files in the library. This can\'t be undone. Settings snapshots in the gallery stay.';
  }

  @override
  String get deleteUpscaleModels => 'Delete Upscale Models';

  @override
  String deleteUpscaleModelsBody(String size) {
    return 'Local upscaling has been retired; these $size of model files are no longer used, and deleting them removes nothing.';
  }

  @override
  String get rescan => 'Rescan';

  @override
  String get autoCleanLimits => 'Auto-cleanup Limits';

  @override
  String get cleanable => 'Can Be Cleaned';

  @override
  String get totalUsage => 'Total';

  @override
  String otherSize(String size) {
    return 'Other $size';
  }

  @override
  String get unitImages => 'images';

  @override
  String get unitItems => 'items';

  @override
  String capOf(String label) {
    return '$label Limit';
  }

  @override
  String get noLimit => 'No limit';

  @override
  String accountsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n accounts',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String get tokenNeededHint =>
      'Direct generation needs your own NovelAI token; it\'s stored encrypted on this device only';

  @override
  String tokensNoneJoined(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n tokens saved, but none are used',
      one: '1 token saved, but it isn\'t used',
    );
    return '$_temp0 for generation';
  }

  @override
  String get manageTokens => 'Manage Tokens';

  @override
  String get naiProxy => 'Proxy for NovelAI';

  @override
  String get naiProxyHint =>
      'Routes through Cloudflare; turn on if NovelAI is unreachable';

  @override
  String get queryingAccount => 'Checking account…';

  @override
  String quotaPct(int pct) {
    return 'Quota $pct%';
  }

  @override
  String get statusSaved => 'Saved';

  @override
  String get genMethod => 'Generation Method';

  @override
  String get directToken => 'API Token';

  @override
  String get useBotAccount => 'Bot Account';

  @override
  String get tokenMissing => 'No token saved yet; can\'t generate';

  @override
  String get useOwnAccount => 'Generate with your own NovelAI account';

  @override
  String get notSubscribed => 'None';

  @override
  String get tokenCopied => 'Token copied';

  @override
  String get deleteToken => 'Delete Token';

  @override
  String deleteTokenBody(String name) {
    return '“$name” will be removed from this device, and you\'ll be able to generate one fewer image at a time.';
  }

  @override
  String get tokenManage => 'Token Management';

  @override
  String maxTokens(int n) {
    return 'Up to $n tokens';
  }

  @override
  String get addToken => 'Add Token';

  @override
  String get noTokensYet => 'No tokens yet';

  @override
  String get multiTokenHint =>
      'Save several to generate several images at once — NAI limits each account to one job at a time';

  @override
  String get primaryAccount => 'Primary';

  @override
  String get copyToken => 'Copy Token';

  @override
  String get primaryAlwaysOn =>
      'Used for generation and Anlas; can\'t be turned off';

  @override
  String get joinFree => 'Free gens';

  @override
  String get joinPaid => 'Anlas gens';

  @override
  String get thirdPartyNoStatus =>
      'Third-party API doesn\'t report account status';

  @override
  String get tokenExpired => 'Token is no longer valid';

  @override
  String get statusQueryFailedRetry => 'Status check failed; tap to retry';

  @override
  String maxTokensSaved(int n) {
    return 'You can save up to $n tokens';
  }

  @override
  String loginFailed(String error) {
    return 'Login failed: $error';
  }

  @override
  String get urlNeedsHttp =>
      'Enter an API URL starting with http:// or https://';

  @override
  String get pasteToken => 'Paste Token';

  @override
  String get emailLogin => 'Email Login';

  @override
  String get thirdParty => 'Third-party';

  @override
  String get thirdPartyApi => 'Third-party API';

  @override
  String get loginAndAdd => 'Log In & Add';

  @override
  String get tokenWhere =>
      'NovelAI website → User Settings → Account → Get Persistent API Token.';

  @override
  String get needNaiAccess =>
      'Direct generation needs your network to reach NovelAI.';

  @override
  String get sentenceJoin => ' ';

  @override
  String get pasteTokenHint => 'Paste a pst-… token or a web eyJ… JWT';

  @override
  String get paste => 'Paste';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get storedEncryptedLocal => 'Stored encrypted on this device only';

  @override
  String get apiKey => 'API key';

  @override
  String get passwordLocalHint =>
      'Your password is only used on this device to derive the key — never uploaded or saved. Logging in gives a token valid for 30 days, which the app renews before it expires.';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get formatNai => 'NovelAI Format';

  @override
  String get formatNaiHint => 'NovelAI API format: /ai/generate-image';

  @override
  String get formatOpenai => 'OpenAI Format';

  @override
  String get formatOpenaiHint => 'OpenAI API format: /v1/chat/completions';

  @override
  String get naiAccountLogin => 'NovelAI Account Login';

  @override
  String get login => 'Log In';

  @override
  String get tokenInvalid => 'Invalid token';

  @override
  String get accountQueryFailedRetry => 'Account check failed; tap to retry';

  @override
  String networkError(String error) {
    return 'Network error: $error';
  }

  @override
  String get wrongCredentials => 'Wrong email or password';

  @override
  String loginHttpFailed(int code) {
    return 'Login failed (HTTP $code)';
  }

  @override
  String get loginNoToken => 'Login response is missing accessToken';

  @override
  String get getStarted => 'Get Started';

  @override
  String get enableNotifications => 'Enable Notifications';

  @override
  String get next => 'Next';

  @override
  String get notNow => 'Not Now';

  @override
  String get skipForNow => 'Skip for Now';

  @override
  String get welcomeTitle => 'Welcome to Plana';

  @override
  String get featEditor => 'Full-screen prompt editor';

  @override
  String get featGallery => 'Gallery keeps settings for easy reruns';

  @override
  String get featTools => 'Vibe · Reference · Inpaint · Upscale';

  @override
  String get appearanceColors => 'Appearance';

  @override
  String get accessMethod => 'How to Generate';

  @override
  String get subscriptionRequired =>
      'An official or relay subscription is required to generate';

  @override
  String get directNaiToken => 'Official Subscription';

  @override
  String get official => 'Official';

  @override
  String get noTokenUseLogin => 'No token? Log in with email and password';

  @override
  String get notifyTitle => 'Progress Notifications';

  @override
  String get notifyDesc =>
      'Get generation progress and completion notifications. On Android 16+, progress also shows as a Live Update.';

  @override
  String get allDone => 'All Done';

  @override
  String get channelProgress => 'Generation Progress';

  @override
  String get channelProgressDesc =>
      'Ongoing progress bar while generating (silent)';

  @override
  String get channelDone => 'Generation Complete';

  @override
  String get channelDoneDesc =>
      'One alert when an image, queue, or loop finishes';

  @override
  String get cloudBackup => 'Plana Cloud';

  @override
  String get backupToCloud => 'Back Up to Plana Cloud';

  @override
  String get restoreFromCloud => 'Restore from Plana Cloud';

  @override
  String get selectBackupFile => 'Choose Backup File';

  @override
  String get notBackupFile => 'Not a recognized backup file';

  @override
  String get importComplete => 'Import complete';

  @override
  String importCompleteFailed(int n) {
    return 'Import complete; $n failed';
  }

  @override
  String get notValidJson => 'Not a valid JSON file';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get webBackupEmpty => 'This web backup has nothing to import';

  @override
  String get customCatMissing =>
      'The custom category in this file doesn\'t exist here';

  @override
  String get fileNoEntries => 'The file has no entries';

  @override
  String inspirationOf(String cat) {
    return 'Inspiration · $cat';
  }

  @override
  String get chooseImportContent => 'Choose What to Import';

  @override
  String itemsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String addedUpdated(int a, int u) {
    return '$a added · $u overwritten';
  }

  @override
  String exportedNOf(int n, String cat) {
    return 'Exported $n from $cat';
  }

  @override
  String get processing => 'Processing…';

  @override
  String get importResult => 'Import Results';

  @override
  String get dupImagesSkipped => 'Duplicate images are skipped';

  @override
  String get embeddedPreviewsSkipped => 'Embedded previews aren\'t imported';

  @override
  String vibeImportFailed(String error) {
    return 'Vibe import failed: $error';
  }

  @override
  String charRefImportFailed(String name, String error) {
    return 'Reference “$name” failed: $error';
  }

  @override
  String inspirationImportFailed(String error) {
    return 'Inspiration import failed: $error';
  }

  @override
  String presetImportFailed(String error) {
    return 'Preset import failed: $error';
  }

  @override
  String get notValidBackup => 'Not a valid backup file';

  @override
  String get backupIdMismatch =>
      'Invalid backup file: identifier doesn\'t match';

  @override
  String backupVersionUnsupported(String ver, String supported) {
    return 'Unsupported backup version: $ver (this app supports v$supported)';
  }

  @override
  String get backupIncomplete => 'Invalid backup file: incomplete data';

  @override
  String get fileReadFailed => 'Couldn\'t read the file';

  @override
  String get fileEmpty => 'The file is empty';

  @override
  String get genCancelled => 'Generation cancelled';

  @override
  String streamBadFrame(String len) {
    return 'Malformed stream data (frame length $len)';
  }

  @override
  String genFailedCode(String code) {
    return 'Generation failed (code $code)';
  }

  @override
  String noImageFrame(int bytes) {
    return 'No image frame received ($bytes bytes received)';
  }

  @override
  String noImageFrameParse(int bytes, int fails, String err) {
    return 'No image frame received ($bytes bytes received, $fails frames failed to parse: $err)';
  }

  @override
  String get genTimeout => 'Generation timed out; try again';

  @override
  String cantConnect(String host, String msg) {
    return 'Can\'t connect to $host: $msg';
  }

  @override
  String tlsFailed(String host) {
    return 'TLS handshake failed; your network may be blocking $host';
  }

  @override
  String streamGenFailed(String error) {
    return 'Streaming generation failed: $error';
  }

  @override
  String unzipFailed(String error) {
    return 'Failed to unpack the result: $error';
  }

  @override
  String get noImageInResult => 'No image found in the result';

  @override
  String get apiNoUpscale => 'This API doesn\'t offer upscaling';

  @override
  String get apiNoAccountStatus => 'This API doesn\'t provide account status';

  @override
  String get apiNoVibe => 'This API doesn\'t offer Vibe encoding';

  @override
  String vibeEncodeFailed(String error) {
    return 'Failed to encode the reference image: $error';
  }

  @override
  String get http401 => 'Token invalid or expired';

  @override
  String get http402 => 'Subscription or Anlas insufficient';

  @override
  String get http429 =>
      'Too many concurrent requests or rate limited; try again later';

  @override
  String httpFailed(int code) {
    return 'Request failed (HTTP $code)';
  }

  @override
  String get notJsonResponse => 'The API didn\'t return JSON';

  @override
  String get noImageData => 'No image data received';

  @override
  String get helpCanvasTitle => 'Canvases';

  @override
  String get helpCanvasBody =>
      'Each canvas keeps its own prompts and generation settings; switch anytime.\n· Only the image count and loop setting are shared across canvases\n💡 Switching canvases doesn\'t affect generations in progress\n💡 “History” keeps the last 50 generations and can restore them';

  @override
  String get helpResolutionTitle => 'Resolution';

  @override
  String get helpResolutionBody =>
      'Tiers by total pixels (width × height):\n· Free → up to 1024×1024, inside the green line; needs Opus and ≤28 steps\n· Costs Anlas → beyond the green line; larger sizes cost more\n· Over the limit → beyond 1024×3072 (red line); can\'t generate';

  @override
  String get helpImg2imgStrengthTitle => 'Strength';

  @override
  String get helpImg2imgStrengthBody =>
      'How much the original image shapes the result.\n· Lower → closer to the original, fewer changes\n· Higher → more freedom, more repainting\n💡 At 0.01 almost nothing is repainted; with Noise also at minimum → an exact copy of the original\n💡 If the AI ignores your prompt too much, try raising Prompt Guidance';

  @override
  String get helpImg2imgNoiseTitle => 'Noise';

  @override
  String get helpImg2imgNoiseBody =>
      'Adds extra random noise on top of the original image.\n· 0 → based entirely on the original; more stable results\n· Higher → more creative freedom and new elements\n💡 For originals with large blank areas, raising it lets the AI fill in detail\n💡 Repeated regenerations at high Noise can introduce visual artifacts';

  @override
  String get helpVibeStrengthTitle => 'Reference Strength';

  @override
  String get helpVibeStrengthBody =>
      'How strongly the Vibe\'s style affects the image.\n· Higher → closer to the reference\'s style, colors, and other visual cues\n· Lower → only a light style hint\n💡 With multiple Vibes, keep the total strength ≤ 1\n💡 Too high and the AI starts ignoring the text prompt';

  @override
  String get helpNormalizeVibeTitle => 'Normalize Reference Strength';

  @override
  String get helpNormalizeVibeBody =>
      'On → all Vibe strengths are scaled down proportionally so the total is ≤ 1\nOff → each Vibe\'s strength adds up independently';

  @override
  String get helpInfoExtractedTitle => 'Information Extracted';

  @override
  String get helpInfoExtractedBody =>
      'How much information is extracted from the original image.\n· Lower → high-frequency detail (texture, style) goes first; composition is kept\n· Higher → keeps both composition and texture / style detail\n💡 Setting a new value costs 2 Anlas; previously used values are free\n💡 Can\'t be changed without the original image';

  @override
  String get helpCharRefStrengthTitle => 'Strength';

  @override
  String get helpCharRefStrengthBody =>
      'Overall influence of the character / style reference.\n· Higher → reproduces the reference\'s features more strictly\n· Lower → the reference is only a weak guide\n💡 Each image costs an extra 5 Anlas; multiple references add up\n💡 Too high and facial expression / angle / pose stick too closely to the reference';

  @override
  String get helpFidelityTitle => 'Fidelity';

  @override
  String get helpFidelityBody =>
      'Whether the prompt can override the reference.\n· Higher → the reference dominates; the prompt can hardly change it\n· Lower → the prompt dominates; easier to adjust the image\n💡 Results vary by image, so experiment';

  @override
  String get helpStepsTitle => 'Steps';

  @override
  String get helpStepsBody =>
      'Number of sampling steps, i.e. denoising iterations.\nMore steps give finer detail but take longer.\nToo many steps bring diminishing returns or even make things worse.\n💡 28 steps or fewer cost no extra Anlas';

  @override
  String get helpCfgTitle => 'Prompt Guidance (CFG Scale)';

  @override
  String get helpCfgBody =>
      'How closely the AI follows your prompt.\n· Lower → more freedom; softer, more painterly, dreamy images\n· Higher → follows the description more strictly; finer, sharper detail\n💡 NovelAI recommends 5–6 for V3 and newer models\n💡 Too high backfires: oversaturated colors and broken images';

  @override
  String get helpVarietyPlusTitle => 'Variety+';

  @override
  String get helpVarietyPlusBody =>
      'Slightly adjusts sampling to vary composition and poses more.\nOn → more variation in composition and poses\nOff → more stable, consistent results\n💡 More noticeable at low Prompt Guidance';

  @override
  String get helpSamplerTitle => 'Sampler';

  @override
  String get helpSamplerBody =>
      'Determines the denoising path, affecting style and stability.\n· Euler Ancestral — classic all-rounder, high randomness\n· Euler — deterministic version, more stable composition\n· DPM++ 2S Ancestral — rich detail\n· DPM++ 2M SDE — high quality + randomness\n· DPM++ 2M — high-quality deterministic sampling\n· DPM++ SDE — detail and variety combined\n💡 Keep the default, or try DPM++ 2M / Euler Ancestral\n💡 Differences between samplers are more visible at low Steps';

  @override
  String get helpNoiseScheduleTitle => 'Noise Schedule';

  @override
  String get helpNoiseScheduleBody =>
      'How noise decays at each sampler step, affecting texture.\n· karras — most common; stable with good detail\n· exponential — exponential decay; stronger contrast\n· polyexponential — polynomial decay; smooth transitions\n💡 Keep the default karras';

  @override
  String get helpSeedTitle => 'Seed';

  @override
  String get helpSeedBody =>
      'The random seed that determines the initial noise.\nSame seed + same settings → nearly identical images\nUseful for locking the composition while fine-tuning.\nEmpty → a different random result each time\n💡 Samplers have slight randomness, so the same seed may still differ a little\n💡 Seeds aren\'t interchangeable between NAI / Anima / Krea, or with external Stable Diffusion';

  @override
  String get helpCfgRescaleTitle => 'Prompt Guidance Rescale';

  @override
  String get helpCfgRescaleBody =>
      'Reduces oversaturation and color bleeding from high guidance.\n0 = no correction; higher → stronger correction\nUsually keep 0; with Guidance >7, try 0.1–0.3\n💡 Raise it when edges look over-colored or “deep-fried”';

  @override
  String get allAlbumsName => 'All Photos';

  @override
  String get trashName => 'Trash';

  @override
  String get albumNameInvalid => 'Enter an album name of 1–40 characters';

  @override
  String get albumNameExists => 'An album with this name already exists';

  @override
  String cantRenameFav(String name) {
    return '“$name” can\'t be renamed';
  }

  @override
  String cantDeleteFav(String name) {
    return '“$name” can\'t be deleted';
  }

  @override
  String cantBrowseFav(String name) {
    return '“$name” can\'t be the browsing album';
  }

  @override
  String cantSaveFav(String name) {
    return '“$name” can\'t be the save album';
  }

  @override
  String get albumDeleted => 'The album has been deleted';

  @override
  String get imageWasDeleted => 'The image has been deleted';

  @override
  String get galleryGone => 'That album no longer exists; choose again';

  @override
  String get chooseDifferentAlbums =>
      'Choose different source and target albums';

  @override
  String get albumsRestored => 'Album data was restored from the latest backup';

  @override
  String get albumsUnreadable =>
      'Album data can\'t be read right now; the original file is kept and All Photos is still available';

  @override
  String get albumsReadOnly =>
      'Album data needs recovery and can\'t be changed for now';

  @override
  String get favorited => 'Added to Favorites';

  @override
  String get unfavoritedSnack => 'Removed from Favorites';

  @override
  String get saveTo => 'Save To';

  @override
  String get chooseAlbum => 'Choose Album';

  @override
  String get moveTo => 'Move To';

  @override
  String get newAlbum => 'New Album';

  @override
  String get renameAlbum => 'Rename Album';

  @override
  String get albumName => 'Album name';

  @override
  String get setAsSaveAlbum => 'Use as Save Album';

  @override
  String get dateLabel => 'Date';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get earlier => 'Earlier';

  @override
  String get last7Days => 'Last 7 Days';

  @override
  String get last30Days => 'Last 30 Days';

  @override
  String dayMonthDay(String month, int day) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '$month',
    });
    return '$_temp0 $day';
  }

  @override
  String dayYearMonthDay(int year, String month, int day) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '$month',
    });
    return '$_temp0 $day, $year';
  }

  @override
  String get groupByTime => 'By Date';

  @override
  String get groupByCharacter => 'By Character';

  @override
  String get groupByStyle => 'By Style';

  @override
  String get ungrouped => 'Unsorted';

  @override
  String get hintSaveLongPress => 'Long-press “Save” for download settings';

  @override
  String get hintStripSwipe =>
      'Swipe up on images in the bottom film strip to share, favorite, or delete';

  @override
  String get nothingToShare => 'No images to share';

  @override
  String get backToHistory => 'Back to History';

  @override
  String savedToNamed(String name) {
    return 'Saved to $name';
  }

  @override
  String get browseAlbums => 'Browse Albums';

  @override
  String get movedToTrash => 'Moved to Trash';

  @override
  String get albumEmpty => 'No photos in this album yet';

  @override
  String get noWorksYet => 'No images yet';

  @override
  String get viewTrash => 'View Trash';

  @override
  String get goCreateFirst => 'Go to “Create” to generate your first image';

  @override
  String get savedAllAlbumFailed =>
      'Image saved to All Photos; the target album is unavailable or sorting failed';

  @override
  String get deletedAlbumCleanupFailed =>
      'Image deleted, but cleaning up its album entries failed';

  @override
  String get upscaleV5 => 'V5 Upscale';

  @override
  String get redrawUpscale => 'Enhance';

  @override
  String get encodingImage => 'Encoding image…';

  @override
  String get uploadingNai => 'Uploading to NAI…';

  @override
  String get noPaidToken => 'No NAI token available for paid actions';

  @override
  String get receivingResult => 'Receiving result…';

  @override
  String get saveToPhoneAlbum => 'Save to Phone Album';

  @override
  String saveToPhoneAlbumBody(int n, String album) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return '$_temp0 will be saved to the system album “$album”; it\'s created if it doesn\'t exist.';
  }

  @override
  String get albumNameExample => 'e.g. Plana Picks';

  @override
  String get dropToDelete => 'Drag here to delete';

  @override
  String get releaseToDelete => 'Release to delete';

  @override
  String get dropToUnfav => 'Drag here to unfavorite';

  @override
  String get dropToFav => 'Drag here to favorite';

  @override
  String get releaseToUnfav => 'Release to unfavorite';

  @override
  String get releaseToFav => 'Release to favorite';

  @override
  String get dropToShare => 'Drag here to share';

  @override
  String get releaseToShare => 'Release to share';

  @override
  String get selectDate => 'Select Date';

  @override
  String get applyLabel => 'Apply';

  @override
  String get dateFieldHint => 'mm/dd/yyyy';

  @override
  String get filterByDate => 'Filter by Date';

  @override
  String get reset => 'Reset';

  @override
  String get specificDate => 'Specific Date';

  @override
  String get pickADay => 'Pick a day';

  @override
  String get dateRange => 'Date Range';

  @override
  String dateRangeValue(String start, String end) {
    return '$start – $end';
  }

  @override
  String get pickStartEnd => 'Pick start and end dates';

  @override
  String get hintLongPressPreview =>
      'Open “All Photos”, then long-press an image to preview, import, save, or delete';

  @override
  String get restoreAll => 'Restore All';

  @override
  String get emptyTrash => 'Empty Trash';

  @override
  String get deleteAlbum => 'Delete Album';

  @override
  String get reorderAlbums => 'Reorder';

  @override
  String restoredN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return 'Restored $_temp0';
  }

  @override
  String get emptyTrashQ => 'Empty the Trash?';

  @override
  String deletedForeverN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return 'Permanently deleted $_temp0';
  }

  @override
  String deleteAlbumQ(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deleteAlbumBody =>
      'Only the album is deleted; its images stay in All Photos.';

  @override
  String newImagesSaveTo(String name) {
    return 'New images will be saved to “$name”';
  }

  @override
  String get backToTop => 'Back to Top';

  @override
  String get filterByModel => 'Filter by Model';

  @override
  String get unknown => 'Unknown';

  @override
  String get groupMode => 'Group By';

  @override
  String savingProgress(int done, int total) {
    return 'Saving $done/$total';
  }

  @override
  String get zipping => 'Packing';

  @override
  String get packZip => 'Pack ZIP';

  @override
  String restoreN(int n) {
    return 'Restore ($n)';
  }

  @override
  String deleteForeverN(int n) {
    return 'Delete Forever ($n)';
  }

  @override
  String get photosAlbum => 'Photos';

  @override
  String quotedName(String name) {
    return '“$name”';
  }

  @override
  String savedNTo(int n, String where) {
    return 'Saved $n to $where';
  }

  @override
  String savedNToFailed(int n, String where, int failed) {
    return 'Saved $n to $where; $failed failed';
  }

  @override
  String get albumsNoImages => 'The selected albums have no images yet';

  @override
  String savedAlbumsN(int albums, int n) {
    return 'Saved $albums albums, $n images in total';
  }

  @override
  String savedNFailed(int n, int failed) {
    return 'Saved $n; $failed failed';
  }

  @override
  String deleteNAlbumsQ(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n albums',
      one: '1 album',
    );
    return 'Delete $_temp0?';
  }

  @override
  String deletedNAlbums(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n albums',
      one: '1 album',
    );
    return 'Deleted $_temp0';
  }

  @override
  String get packFailed => 'Packing failed';

  @override
  String packedN(int n) {
    return 'Packed $n';
  }

  @override
  String packedNFailed(int n, int failed) {
    return 'Packed $n; $failed failed';
  }

  @override
  String saveFailedWith(String error) {
    return 'Save failed: $error';
  }

  @override
  String get restore => 'Restore';

  @override
  String get deleteForever => 'Delete Forever';

  @override
  String get unfavorite => 'Unfavorite';

  @override
  String get favoriteAction => 'Favorite';

  @override
  String get removeCover => 'Remove Cover';

  @override
  String get setAsCover => 'Set as Cover';

  @override
  String get restored => 'Restored';

  @override
  String get deleteForeverQ => 'Permanently delete this image?';

  @override
  String get deletedForever => 'Permanently deleted';

  @override
  String coverRemoved(String name) {
    return 'Removed the cover of “$name”';
  }

  @override
  String coverSet(String name) {
    return 'Set as the cover of “$name”';
  }

  @override
  String get imageNotReady => 'The image isn\'t ready yet';

  @override
  String unreadableSkipped(int n) {
    return '$n couldn\'t be read and were skipped';
  }

  @override
  String movedNToTrash(int n) {
    return 'Moved $n to Trash';
  }

  @override
  String deleteNForeverQ(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return 'Permanently delete $_temp0?';
  }

  @override
  String get cantUndo => 'This can\'t be undone.';

  @override
  String deleteNImagesQ(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return 'Delete $_temp0?';
  }

  @override
  String alreadyInAlbum(String name) {
    return 'The images are already in “$name”';
  }

  @override
  String movedNTo(int n, String name) {
    return 'Moved $n to “$name”';
  }

  @override
  String deletesInDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days',
      one: '1 day',
    );
    return 'Deleted in $_temp0';
  }

  @override
  String selectedNAlbums(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n albums',
      one: '1 album',
    );
    return '$_temp0 selected';
  }

  @override
  String selectedNImages(int n) {
    return '$n selected';
  }

  @override
  String get selectNone => 'Select None';

  @override
  String get done => 'Done';

  @override
  String get backToAll => 'Back to All';

  @override
  String get backToAlbums => 'Back to Albums';

  @override
  String nAlbums(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String filteredOfTotal(int n, int total) {
    return '$n/$total images';
  }

  @override
  String get multiSelect => 'Select';

  @override
  String get searchPromptTags => 'Search Prompt Tags';

  @override
  String get searchPromptTagsHint => 'Search prompt tags…';

  @override
  String indexingProgress(int done, int total) {
    return 'Indexing $done/$total';
  }

  @override
  String get grouping => 'Grouping';

  @override
  String get noMatchingWorks => 'No matching images';

  @override
  String get trashEmpty => 'Trash is empty';

  @override
  String get galleryEmpty => 'The gallery is empty';

  @override
  String get albumNoImages => 'No images in this album yet';

  @override
  String saveN(int n) {
    return 'Save ($n)';
  }

  @override
  String deleteN(int n) {
    return 'Delete ($n)';
  }

  @override
  String preparingProgress(int done, int total) {
    return 'Preparing $done/$total';
  }

  @override
  String get share => 'Share';

  @override
  String get customAlbum => 'Custom Album';

  @override
  String get finishing => 'Finishing';

  @override
  String get preparing => 'Preparing';

  @override
  String get upscale => 'Upscale';

  @override
  String get savedLabel => 'Saved';

  @override
  String get compare => 'Compare';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get inpaintInProgress => 'Inpainting in progress, please wait';

  @override
  String get noPixelData => 'This image has no pixel data';

  @override
  String get redrawNoSnapshot =>
      'This image has no settings snapshot, so Enhance isn\'t available (only images generated on this device have one)';

  @override
  String redrawModelUnsupported(String model) {
    return '$model doesn\'t support Image2Image; switch back to a NAI model to use Enhance';
  }

  @override
  String redrawTooLarge(int w, int h) {
    return 'The source $w×$h already exceeds NAI\'s pixel limit, so no Enhance scale is possible';
  }

  @override
  String get preparingEllipsis => 'Preparing…';

  @override
  String upscaleDone(String method, int w, int h) {
    return '$method done: $w×$h, saved to the gallery';
  }

  @override
  String upscaleFailed(String error) {
    return 'Upscale failed: $error';
  }

  @override
  String get redrawNoSnapshotShort => 'No settings snapshot; can\'t Enhance';

  @override
  String redrawStartMax(int w, int h, String model) {
    return 'Starting Max enhance ≈$w×$h · $model';
  }

  @override
  String upscaleStart(int w, int h) {
    return 'Starting V5 upscale $w×$h';
  }

  @override
  String get addToCreate => 'Add to Create';

  @override
  String get savedToImg2ImgUpscale => 'Saved to img2img upscale';

  @override
  String redrawStart(String scale, int w, int h, String model) {
    return 'Starting $scale enhance $w×$h · $model';
  }

  @override
  String get savedToPhotos1 => 'Saved to Photos';

  @override
  String get saveFailed => 'Save failed';

  @override
  String saveFailedSpace(String error) {
    return 'Save failed: $error';
  }

  @override
  String get regenNoSnapshot => 'No settings snapshot; can\'t regenerate';

  @override
  String saveToNamed(String name) {
    return 'Save to $name';
  }

  @override
  String get cantReadImage => 'Couldn\'t read this image';

  @override
  String upscaleNote(int price) {
    return 'V5 diffusion upscale · fixed 2× · $price Anlas';
  }

  @override
  String upscaleTooLarge(int w, int h) {
    return 'The source $w×$h exceeds 3,145,728 pixels and can\'t be upscaled';
  }

  @override
  String get scaleNoteX1 =>
      'Regenerates at the same size, refining details without enlarging';

  @override
  String get scaleNoteMax =>
      'Sends the original size; NovelAI enlarges it to the maximum and redraws';

  @override
  String scaleNoteScale(String scale) {
    return 'Regenerates at $scale resolution; the image will change';
  }

  @override
  String maxOnlyV5(String model) {
    return 'Max is V5 only; the current model is $model, which the enhance will use';
  }

  @override
  String maxTooLarge(int w, int h) {
    return 'Max needs a source under 2,516,582 pixels; this $w×$h image is too large';
  }

  @override
  String get upscaleResolution => 'Upscale';

  @override
  String get img2imgUpscale => 'Enhance';

  @override
  String get scaleLabel => 'Scale';

  @override
  String get magnitudeLabel => 'Magnitude';

  @override
  String magnitudeN(String n) {
    return 'Level $n';
  }

  @override
  String get strengthStrength => 'Strength';

  @override
  String get noiseNoise => 'Noise';

  @override
  String get startUpscale => 'Start';

  @override
  String savedToPhotosSize(String size) {
    return 'Saved to Photos · $size';
  }

  @override
  String get setAsDefaultSave => 'Set as the default save method';

  @override
  String estimatedSize(String size) {
    return 'Estimated size $size';
  }

  @override
  String get calculating => 'Calculating…';

  @override
  String get jpgNoParams => 'JPG doesn\'t keep generation settings';

  @override
  String get keepOriginalMeta => 'Keep original metadata';

  @override
  String get clearGenInfo => 'Clear generation info';

  @override
  String get saveOnce => 'Save Once';

  @override
  String get setAsDefault => 'Set as Default';

  @override
  String get newImagesSaveHere => 'New images save here';

  @override
  String get zipName => 'Archive name';

  @override
  String get zipPassword => 'Password (optional)';

  @override
  String get stopping => 'Stopping';

  @override
  String get pack => 'Pack';

  @override
  String get selectDateRange => 'Select Date Range';

  @override
  String get backToCalendar => 'Back to Calendar';

  @override
  String get startDate => 'Start date';

  @override
  String get endDate => 'End date';

  @override
  String get dragToAdjustDate => 'Drag to adjust the dates';

  @override
  String get zipTooLarge => 'The archive is too large for the zip format';

  @override
  String get zipInterrupted => 'Packing was interrupted';

  @override
  String get enterNameFirst => 'Enter a name first';

  @override
  String get enterPromptFirst => 'Enter a prompt first';

  @override
  String deleteNamedQ(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get localOnlyDeleteBody =>
      'Only the local entry is deleted. This can\'t be undone.';

  @override
  String get deletedLabel => 'Deleted';

  @override
  String get numbersExhausted => 'No numbers left';

  @override
  String get importCharPrompt => 'Import Character Prompt';

  @override
  String get importMainPrompt => 'Import Main Prompt';

  @override
  String get galleryNoImages => 'The gallery has no images yet';

  @override
  String get pickFromGallery => 'Pick from Gallery';

  @override
  String totalImagesN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get readImageFailed => 'Couldn\'t read the image';

  @override
  String get enterPositiveFirst => 'Enter the prompt first';

  @override
  String editInCat(String cat) {
    return 'Edit $cat';
  }

  @override
  String newInCat(String cat) {
    return 'New in $cat';
  }

  @override
  String get aliasLabel => 'Alias';

  @override
  String get enterAlias => 'Enter an alias…';

  @override
  String get numberLabel => 'Number';

  @override
  String get upload => 'Upload';

  @override
  String get generating => 'Generating';

  @override
  String get exampleArtists => 'e.g. wlop, rurudo';

  @override
  String get negativePromptAlt => 'Undesired Content';

  @override
  String get exampleNegative => 'e.g. bad anatomy, worst quality';

  @override
  String get applicableModels => 'Models';

  @override
  String get recommendedParams => 'Recommended Settings';

  @override
  String get importToCreatePage => 'From Create';

  @override
  String get tapToUpload => 'Tap to upload';

  @override
  String get modelsNoneMeansAll =>
      'None selected = universal; shows up for every model';

  @override
  String selectedNCount(int n) {
    return '$n selected';
  }

  @override
  String get unknownModelOtherVersion => 'Unknown model (from another version)';

  @override
  String get useCurrent => 'Use Current';

  @override
  String get saveLocal => 'Save Locally';

  @override
  String get saveAndPublish => 'Publish';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get saveTagChanges => 'Save Tag Changes';

  @override
  String get storeIn => 'Save to';

  @override
  String maxSelectN(int n) {
    return 'You can select up to $n';
  }

  @override
  String charsFullN(int n) {
    return 'Character limit ($n) reached';
  }

  @override
  String addedCharsTruncated(int added, int cap) {
    return 'Added $added characters (truncated at $cap)';
  }

  @override
  String addedChars(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n characters',
      one: '1 character',
    );
    return 'Added $_temp0';
  }

  @override
  String get addedToPrompt => 'Added to the prompt';

  @override
  String taggedN(int n, String tag) {
    return 'Tagged $n with “$tag”';
  }

  @override
  String deleteNItemsQ(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return 'Delete $_temp0?';
  }

  @override
  String localOnlyNLine(int n) {
    return '· $n local: deleted locally only';
  }

  @override
  String get cantUndoShort => 'This can\'t be undone.';

  @override
  String deletedNFailed(int done, int failed) {
    return 'Deleted $done; $failed failed';
  }

  @override
  String deletedNItems(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return 'Deleted $_temp0';
  }

  @override
  String addN(int n) {
    return 'Add ($n)';
  }

  @override
  String get filter => 'Filter';

  @override
  String noMatchingInCat(String cat) {
    return 'No matching $cat';
  }

  @override
  String noneYetInCat(String cat) {
    return 'No $cat yet';
  }

  @override
  String myInCat(String cat) {
    return 'My $cat';
  }

  @override
  String savedInCat(String cat) {
    return 'Saved $cat';
  }

  @override
  String get publicLibUnavailable => 'The public library isn\'t available yet';

  @override
  String get viewPrompt => 'View Prompt';

  @override
  String get copyPrompt => 'Copy Prompt';

  @override
  String get promptCopied => 'Prompt copied';

  @override
  String get catCharacter => 'Characters';

  @override
  String get catStyle => 'Styles';

  @override
  String get catScene => 'Scenes';

  @override
  String get catOther => 'Other';

  @override
  String get searchCharHint => 'Search characters / aliases…';

  @override
  String get searchStyleHint => 'Search names / prompts / tags…';

  @override
  String get searchSceneHint => 'Search scenes…';

  @override
  String get searchNamePromptHint => 'Search names / prompts…';

  @override
  String get layoutPortrait => 'Portrait';

  @override
  String get layoutLandscape => 'Landscape';

  @override
  String get layoutSquare => 'Square';

  @override
  String get layoutNoImage => 'No Image';

  @override
  String get sortNumber => 'Number';

  @override
  String get sortLatest => 'Latest';

  @override
  String get sortAuthor => 'Author';

  @override
  String get notTagBackup => 'Not a Tag Manager backup file';

  @override
  String get backupCatUnknown =>
      'The backup file\'s category isn\'t recognized';

  @override
  String get noPreviewForCat => 'This category doesn\'t support previews';

  @override
  String get copySuffix => '(copy)';

  @override
  String get codexTypeDict => 'Dictionary';

  @override
  String get codexTypeComposition => 'Composition';

  @override
  String get codexTypePack => 'Pack';

  @override
  String codexNotFound(String id) {
    return 'Codex not found: $id';
  }

  @override
  String get codexBadImageHost => 'Malformed image host config';

  @override
  String get codexBadIndex => 'Malformed codex index';

  @override
  String get codexBadData => 'Malformed codex data';

  @override
  String get codexOriginalImage => 'Codex image';

  @override
  String get originalNotDownloaded =>
      'Couldn\'t download the image; check your network';

  @override
  String get shuffleAnother => 'Another';

  @override
  String addedToPromptCharsDropped(int added, int dropped) {
    return 'Added to the prompt · $added characters ($dropped over the limit)';
  }

  @override
  String addedToPromptChars(int added) {
    String _temp0 = intl.Intl.pluralLogic(
      added,
      locale: localeName,
      other: '$added characters',
      one: '1 character',
    );
    return 'Added to the prompt · $_temp0';
  }

  @override
  String get goCreate => 'Go to Create';

  @override
  String get addToPrompt => 'Add to Prompt';

  @override
  String favoritesFull(int n) {
    return 'Favorites are full ($n); clear some first';
  }

  @override
  String get random => 'Random';

  @override
  String get tapToFlip => 'Tap to flip and see the prompt';

  @override
  String charNNegative(int n) {
    return 'Character $n · Undesired';
  }

  @override
  String get selectCodex => 'Choose Codex';

  @override
  String get clearFavorites => 'Clear Favorites';

  @override
  String clearFavoritesBody(int n) {
    return 'All $n favorites will be removed. This can\'t be undone. The codex entries themselves stay.';
  }

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get favoriteHowTo =>
      'Open any entry and tap the star at the bottom left to favorite it';

  @override
  String allIn(String name) {
    return 'All “$name”';
  }

  @override
  String get unblock => 'Unblock';

  @override
  String get block => 'Block';

  @override
  String get unblockAll => 'Unblock All';

  @override
  String get upLevel => 'Up';

  @override
  String get categories => 'Categories';

  @override
  String get author => 'Author';

  @override
  String get contributors => 'Contributors';

  @override
  String get codexCopyright =>
      'Content and sample images belong to their codex authors; this page is only a visual index.';

  @override
  String get codexSiteLink => 'Codex · Original site';

  @override
  String get codexIndexFailed => 'Couldn\'t load the codex index';

  @override
  String get noCodex => 'No codex yet';

  @override
  String get codexAbout =>
      'Entries and sample images come from\nhttps://novelai.quicktagcloud.com/\n\nThis app only displays and searches them; all content belongs to the codex authors.\n\nThanks to every codex author and contributor for sharing.';

  @override
  String get sourcesThanks => 'Sources & Thanks';

  @override
  String get gotIt => 'Got It';

  @override
  String loadingEntries(int n) {
    return 'Loading $n entries…';
  }

  @override
  String get codexLoadFailed => 'Couldn\'t load the codex';

  @override
  String get noMatchingEntries => 'No matching entries';

  @override
  String get noEntries => 'No entries yet';

  @override
  String get searchTitlePromptHint => 'Search titles / prompts…';

  @override
  String get allCategories => 'All Categories';

  @override
  String get nothingToDraw => 'No entries to draw from right now';

  @override
  String get retry => 'Retry';

  @override
  String get categoryLabel => 'Categories';

  @override
  String get newCategory => 'New Category';

  @override
  String get renameShort => 'Rename';

  @override
  String get categoryExists => 'A category with this name already exists';

  @override
  String get categoryEmpty => 'This category has no entries yet.';

  @override
  String categoryDeleteN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Its $n entries',
      one: 'Its 1 entry',
    );
    return '$_temp0 will be deleted too. This can\'t be undone.';
  }

  @override
  String categoryReAdd(String name) {
    return 'Create a category named “$name” later to bring it back.';
  }

  @override
  String get editCategory => 'Edit Category';

  @override
  String get categoryName => 'Category name';

  @override
  String get icon => 'Icon';

  @override
  String get previewImage => 'Preview';

  @override
  String get create => 'Create';

  @override
  String get manageCategories => 'Manage Categories';

  @override
  String addLibN(int n) {
    return 'Add ($n)';
  }

  @override
  String addCharsN(int n) {
    return 'Add Characters ($n)';
  }

  @override
  String get scopeMine => 'Mine';

  @override
  String scopeMineN(int n) {
    return 'Mine · $n';
  }

  @override
  String scopePublicShortN(int n) {
    return 'Public $n';
  }

  @override
  String get scopePublicShort => 'Public';

  @override
  String scopePublicN(int n) {
    return 'Public · $n';
  }

  @override
  String get manageTagPool => 'Manage Tag Pool';

  @override
  String get sort => 'Sort';

  @override
  String get nicknameOrQq => 'Nickname or QQ number';

  @override
  String get noSignedEntries => 'No signed entries in the library yet';

  @override
  String get noMatchingAuthors => 'No matching authors';

  @override
  String get genericModel => 'Universal';

  @override
  String genericUnlabeled(String label) {
    return '$label (unlabeled)';
  }

  @override
  String authorNamed(String name) {
    return 'Author $name';
  }

  @override
  String get positiveLabel => 'Prompt';

  @override
  String get negativeLabel => 'Undesired';

  @override
  String get tagExistsShort => 'Tag already exists';

  @override
  String catTagPool(String cat) {
    return '$cat Tag Pool';
  }

  @override
  String get newTagEllipsis => 'New tag…';

  @override
  String get noTags => 'No tags';

  @override
  String deleteTagQ(String tag) {
    return 'Delete tag “$tag”?';
  }

  @override
  String deleteTagEntriesBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n entries',
      one: '1 entry',
    );
    return 'The tag will be removed from $_temp0; the entries stay.';
  }

  @override
  String get addTag => 'Add Tag';

  @override
  String get use => 'Use';

  @override
  String charRangeLabel(String n) {
    return 'Character $n';
  }

  @override
  String imagesScopeSuffix(String scope) {
    return 'images · $scope';
  }

  @override
  String costPts(String n) {
    return '$n Anlas spent';
  }

  @override
  String selectedLabel(String name) {
    return 'Selected: $name';
  }

  @override
  String get peakSlot => 'Peak Slot';

  @override
  String get peakDay => 'Peak Day';

  @override
  String get unitTxns => 'txns';

  @override
  String get genDetails => 'Generation Details';

  @override
  String get pointsDetails => 'Anlas Details';

  @override
  String get activeSlots => 'Active Slots';

  @override
  String get activeDays => 'Active Days';

  @override
  String get avgPerSlot => 'Avg per Slot';

  @override
  String get avgPerDay => 'Avg per Day';

  @override
  String get v5Gens => 'V5 Images';

  @override
  String get v5Anlas => 'V5 Anlas';

  @override
  String get estimatedSpend => 'Estimated Spend';

  @override
  String get vsPrevSlot => 'vs. Previous Slot';

  @override
  String get vsPrevDay => 'vs. Previous Day';

  @override
  String get unchanged => 'No change';

  @override
  String todayRange(String from, String to) {
    return 'Today $from–$to';
  }

  @override
  String todayHour(String h) {
    return 'Today $h:00';
  }

  @override
  String get dataSource => 'Data Source';

  @override
  String get directKey => 'Direct Key';

  @override
  String get botAuth => 'Bot Authorization';

  @override
  String get rangeToday => 'Today';

  @override
  String get rangeWeek => 'This Week';

  @override
  String get rangeMonth => 'This Month';

  @override
  String minusPts(String n) {
    return '-$n Anlas';
  }

  @override
  String genSize(int w, int h) {
    return 'Image $w×$h';
  }

  @override
  String get upscale4x => 'Upscale 4x';

  @override
  String get vibeEncoding => 'Vibe Encoding';

  @override
  String get dayGens => 'Images That Day';

  @override
  String freeN(int n) {
    return '$n free';
  }

  @override
  String get perItemSpend => 'Spending Details';

  @override
  String get perItemGens => 'Generations';

  @override
  String get detailsRolledOff =>
      'Details for this day have expired; only the summary remains';

  @override
  String get noRecordsDay => 'No records for this day';

  @override
  String get noData => 'No data';

  @override
  String get modeNone => 'None';

  @override
  String get modeComic => 'Comic Mode';

  @override
  String get modeNatural => 'Natural Language Only';

  @override
  String get toolCharLib => 'Character Library';

  @override
  String get toolStyleLib => 'Style Library';

  @override
  String get toolTagWiki => 'Tag Wiki';

  @override
  String get toolSafeMode => 'Safe Mode';

  @override
  String get toolOcLib => 'OC Library';

  @override
  String get assistantTools => 'Tools';

  @override
  String get assistantToolsDesc => 'What the AI can use to look things up';

  @override
  String toolsEnabledN(int n) {
    return '$n on';
  }

  @override
  String get imageModelField => 'Image models';

  @override
  String get drawingImage => 'Generating';

  @override
  String get imagePromptEmpty => 'Say what to draw or how to change it';

  @override
  String get aspectLabel => 'Aspect Ratio';

  @override
  String resolutionChip(String v) {
    return 'Size $v';
  }

  @override
  String aspectChip(String v) {
    return 'Ratio $v';
  }

  @override
  String get imageAuto => 'Auto';

  @override
  String get quoteImage => 'Quote';

  @override
  String imagesMax(int n) {
    return 'Up to $n images';
  }

  @override
  String get imageGenNoModel => 'This image model isn\'t available right now';

  @override
  String get imageGenNoImage => 'No image returned';

  @override
  String get toolSearchArtist => 'Use Style Library';

  @override
  String get toolSearchOc => 'Use Character Library';

  @override
  String get toolSearchCharacter => 'Character Search';

  @override
  String get toolLookupTag => 'Tag Search';

  @override
  String randomN(int n) {
    return '$n random';
  }

  @override
  String lookedUpN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sources',
      one: '1 source',
    );
    return 'Looked up $_temp0';
  }

  @override
  String get untitledChat => 'Untitled Chat';

  @override
  String get thinkOff => 'Off';

  @override
  String get thinkAuto => 'Auto';

  @override
  String get thinkLow => 'Low';

  @override
  String get thinkMedium => 'Medium';

  @override
  String get thinkHigh => 'High';

  @override
  String get thinkUltra => 'Ultra';

  @override
  String get importReplaceMain => 'Replace Main';

  @override
  String get importClearSections => 'Clear Sections';

  @override
  String get assistantNoModal =>
      'The AI Assistant doesn\'t support Anima / Krea yet; switch to NAI on the Create page';

  @override
  String get builtinModelUnavailable =>
      'The built-in model isn\'t available yet; pick a custom endpoint at the top first';

  @override
  String get thinking => 'Thinking';

  @override
  String get lookingUp => 'Looking things up';

  @override
  String get turnInterrupted =>
      'The AI stopped before finishing this turn; try again';

  @override
  String get replyDoneFallback => 'All done~';

  @override
  String get replyEmptyFallback => 'Nothing to add this time…';

  @override
  String get epNoModels => 'Got a response, but no models in it';

  @override
  String get modelEmptyReply => 'The model returned an empty reply';

  @override
  String get backendUnset => 'No backend address is set';

  @override
  String noDataIn(String secs) {
    return 'No data received within $secs s';
  }

  @override
  String get channelEndedEarly =>
      'The connection closed before the reply arrived';

  @override
  String modelBadDraw(String count) {
    return 'The draw block was still malformed after $count rewrites. The model\'s last reply:';
  }

  @override
  String assistantRefused(String count, String keyword) {
    return 'The model declined this request (still matched “$keyword” after $count retries)';
  }

  @override
  String modelNoReplyIn(String secs) {
    return 'The model didn\'t reply within $secs s';
  }

  @override
  String get thinkNoOffFormat =>
      'This format has no “Off” level; sending the lowest';

  @override
  String get thinkNoUltraFormat =>
      'This format has no “Ultra” level; sending “High”';

  @override
  String get thinkNoOffModel =>
      'This model can\'t turn thinking off; sending “Low”';

  @override
  String get thinkNoUltraModel =>
      'This model has no “Ultra” level; sending “High”';

  @override
  String get replyUnreadable =>
      'The endpoint responded, but no reply could be read; check that the format is right';

  @override
  String get suggest1 =>
      'Draw a white-haired, red-eyed catgirl standing under a cherry tree';

  @override
  String get suggest2 => 'Pick a nice art style for me';

  @override
  String get suggest3 => 'Draw a random Blue Archive character';

  @override
  String get suggest4 => 'Check what\'s wrong with my current tags';

  @override
  String get aiAssistant => 'Assistant';

  @override
  String get selectModel => 'Select Model';

  @override
  String get assistantSettings => 'Assistant Settings';

  @override
  String get chatHistory => 'Chat History';

  @override
  String get newChat => 'New Chat';

  @override
  String get askAnything => 'Just say what you want to draw';

  @override
  String get copyContent => 'Copy';

  @override
  String get editMessage => 'Edit Message';

  @override
  String get regenerateFromHere => 'Regenerate from Here';

  @override
  String get cancelSend => 'Cancel Send';

  @override
  String get discardAfterQ => 'Discard the rest of the chat?';

  @override
  String get discardAfterBody =>
      'Everything after this message will be discarded. Changes already written to the Create page stay.';

  @override
  String get discard => 'Discard';

  @override
  String get createPageShort => 'Create Page';

  @override
  String get quoteCreatePage => 'Quote Create Page';

  @override
  String get createPageEmpty =>
      'The Create page has no prompt yet; nothing to quote';

  @override
  String get modeLabel => 'Mode';

  @override
  String rulesNoMode(String mode) {
    return 'The current rule preset doesn\'t support “$mode”';
  }

  @override
  String thinkChip(String level) {
    return 'Think $level';
  }

  @override
  String get attachImage => 'Attach Images';

  @override
  String get systemAlbum => 'Photos';

  @override
  String get inputHint => 'What to draw or edit…';

  @override
  String get stop => 'Stop';

  @override
  String get send => 'Send';

  @override
  String get assistantModelUnsupported =>
      'The AI Assistant doesn\'t support this model yet';

  @override
  String get assistantModelUnsupportedBody =>
      'Anima and Krea use a different prompt system from NAI.\nSwitch to NAI 4.5 or 5 on the Create page.';

  @override
  String get goChangeModel => 'Change Model';

  @override
  String get pickEndpointFirst => 'No models available yet';

  @override
  String get builtinUnavailableBody => 'Add your own model endpoint first';

  @override
  String get selectEndpoint => 'Select Model Endpoint';

  @override
  String get queued => 'Queued';

  @override
  String get quotedCreatePage => 'Quoted the Create page';

  @override
  String durSecs(int s) {
    return '$s s';
  }

  @override
  String durMinSecs(int m, String s) {
    return '$m min $s s';
  }

  @override
  String get discardChangesQ => 'Discard changes?';

  @override
  String get unsavedLost => 'Unsaved changes will be lost.';

  @override
  String get unsavedLost2 => 'Unsaved changes will be lost.';

  @override
  String get discardAction => 'Discard';

  @override
  String savedNamed(String name) {
    return 'Saved “$name”';
  }

  @override
  String get deleteEndpointQ => 'Delete this endpoint?';

  @override
  String get deleteEndpointBody =>
      'The URL and API key will be removed from this device. Past chats stay.';

  @override
  String get myEndpoints => 'My Endpoints';

  @override
  String get addEndpoint => 'Add Endpoint';

  @override
  String get notComplete => 'Incomplete';

  @override
  String formatOf(String format) {
    return '$format format';
  }

  @override
  String get inUse => 'In Use';

  @override
  String get pickServiceOrUrl =>
      'Pick a service or enter an endpoint URL first';

  @override
  String get urlMustHttp =>
      'The endpoint URL must start with http:// or https://';

  @override
  String get noApiKeyYet => 'API key not entered';

  @override
  String get noModelYet => 'No model added yet';

  @override
  String headerLineBad(int n) {
    return 'Header line $n must look like “Name: value”, using English characters only';
  }

  @override
  String linkCopied(String url) {
    return 'Link copied: $url';
  }

  @override
  String modelConnOk(String model, String secs) {
    return '$model connected · $secs s';
  }

  @override
  String connOk(String secs) {
    return 'Connected · $secs s';
  }

  @override
  String get formatField => 'Format';

  @override
  String get urlField => 'URL';

  @override
  String get getKey => 'Get Key';

  @override
  String get modelField => 'Model';

  @override
  String get modelIdHint => 'Model ID';

  @override
  String get addAnotherModel => 'Add another model';

  @override
  String get modelList => 'Model List';

  @override
  String get pathField => 'Path';

  @override
  String get headersField => 'Headers';

  @override
  String get headersHint => 'One per line, e.g. X-Title: Plana';

  @override
  String headersN(int n) {
    return 'Headers $n';
  }

  @override
  String get test => 'Test';

  @override
  String searchNModels(int n) {
    return 'Search $n models';
  }

  @override
  String doneSelectedN(int n) {
    return 'Done · $n selected';
  }

  @override
  String get rulePresets => 'Rule Presets';

  @override
  String sectionsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sections',
      one: '1 section',
    );
    return '$_temp0';
  }

  @override
  String get notUtf8 => 'Can\'t read this file; make sure it\'s UTF-8 text';

  @override
  String importedNamed(String name) {
    return 'Imported “$name”';
  }

  @override
  String savedAsNamed(String name) {
    return 'Saved as “$name”';
  }

  @override
  String exportedNamed(String name) {
    return 'Exported “$name”';
  }

  @override
  String get deletePresetQ => 'Delete preset?';

  @override
  String deleteRulePresetBody(String name) {
    return '“$name” will be deleted; models using it switch to the default rules.';
  }

  @override
  String get listSep => ', ';

  @override
  String get importRulePreset => 'Import Rule Preset';

  @override
  String totalSectionsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sections',
      one: '1 section',
    );
    return '$_temp0';
  }

  @override
  String get hasConditional => 'Has conditional sections';

  @override
  String get ruleSecRole => 'Role';

  @override
  String get ruleSecModelTraits => 'Model Traits';

  @override
  String get ruleSecPromptConstruction => 'Prompt Construction';

  @override
  String get ruleSecNaturalConstruction => 'Natural-Language Construction';

  @override
  String get ruleSecWeightControl => 'Weight Control';

  @override
  String get ruleSecCharacters => 'Characters';

  @override
  String get ruleSecMultiCharacter => 'Multiple Characters';

  @override
  String get ruleSecComic => 'Comics / Panels';

  @override
  String get ruleSecCustomTags => 'Custom Tags';

  @override
  String get ruleSecTextRendering => 'On-Image Text';

  @override
  String get ruleSecAlpha => 'Alpha Channel';

  @override
  String get ruleSecOutput => 'Draw Output';

  @override
  String get ruleSecModeComic => 'Mode: Comic';

  @override
  String get ruleSecModeNatural => 'Mode: Natural Language Only';

  @override
  String get enabledModels => 'Enabled Models';

  @override
  String get notEnabled => 'Not in use';

  @override
  String get duplicatePreset => 'Duplicate';

  @override
  String get ruleSectionsLabel => 'Sections';

  @override
  String whenOffTag(String mode) {
    return 'Off in $mode';
  }

  @override
  String charsN(int n) {
    return '$n chars';
  }

  @override
  String get fullTextEdit => 'Edit Full Text';

  @override
  String get addRuleSection => 'Add Section';

  @override
  String get ruleSectionName => 'Title';

  @override
  String get deleteRuleSectionQ => 'Delete this section?';

  @override
  String deleteRuleSectionBody(String name) {
    return 'The content of “$name” will be deleted too.';
  }

  @override
  String get ruleSectionEmpty => 'Content can\'t be empty';

  @override
  String get ruleSectionNameReserved =>
      'This name is reserved for the tool layer';

  @override
  String get supportedModels => 'Supported Models';

  @override
  String get missingPresetName => 'Missing preset name (name)';

  @override
  String get missingModels =>
      'Missing supported models (set models to nai45, nai5)';

  @override
  String rulesTooManySections(int n) {
    return 'Too many rule sections (max $n)';
  }

  @override
  String rulesTooLong(int n) {
    return 'Rules are too long (max $n characters)';
  }

  @override
  String get rulesHeader1 => '# Plana AI Assistant rule preset';

  @override
  String get rulesHeader2 =>
      '# Each section has a name and content. Sections with when are conditional, e.g. when: comic is sent only when drawing comics.';

  @override
  String get rulesHeader3 =>
      '# A when starting with mode: is a mode section, e.g. when: \"mode:comic\" is sent only when Comic Mode is selected.';

  @override
  String get rulesHeader4 =>
      '# A leading ! means send only when not selected, e.g. when: \"!mode:natural\" isn\'t sent with Natural Language Only.';

  @override
  String badFileFormat(String detail) {
    return 'Bad file format: $detail';
  }

  @override
  String badFileFormatLine(int line, String detail) {
    return 'Bad file format (line $line): $detail';
  }

  @override
  String get noSections => 'Bad file format: sections not found';

  @override
  String get noUsableRules => 'The file has no usable rule sections';

  @override
  String get clearHistoryQ => 'Clear chat history?';

  @override
  String clearHistoryBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'All $n chats',
      one: '1 chat',
    );
    return '$_temp0 will be deleted. Changes already written to the Create page stay.';
  }

  @override
  String get noArchivedChats =>
      'No archived chats yet.\nTap “New Chat” at the top right to archive the current one.';

  @override
  String turnsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n turns',
      one: '1 turn',
    );
    return '$_temp0';
  }

  @override
  String get justNow => 'Just now';

  @override
  String get libraryScope => 'Library Scope';

  @override
  String get usageHabits => 'Preferences';

  @override
  String get autoDraw => 'Draw After Writing Prompts';

  @override
  String get autoDrawDesc => 'Start generating as soon as the prompt is ready';

  @override
  String get inlineImages => 'Show Images in Chat';

  @override
  String get inlineImagesDesc =>
      'Generated images show in the chat and are saved to the gallery';

  @override
  String get autoWrite => 'Write to Create Page';

  @override
  String get autoWriteDesc =>
      'Generated prompts go straight to the Create page, no manual import';

  @override
  String get startUsingAssistant => 'Get Started with the AI Assistant';

  @override
  String get previous => 'Back';

  @override
  String get chatMode => 'Chat Mode';

  @override
  String get planaBackend => 'Plana Bot';

  @override
  String get freeModels => 'Free Models';

  @override
  String get incompleteTapToFix => 'Incomplete; tap to finish';

  @override
  String get writtenToCreate => 'Written to the Create page';

  @override
  String get undoImportQ => 'Undo this import?';

  @override
  String get undoImportBody =>
      'You\'ve edited the prompt since importing. Undoing also discards those edits and goes back to before the import.';

  @override
  String get undoAnyway => 'Undo Anyway';

  @override
  String get undone => 'Undone';

  @override
  String get imported => 'Imported';

  @override
  String get added => 'Added';

  @override
  String get fullPrompt => 'Full Prompt';

  @override
  String get sameAsLastTurn => 'Same prompt as last turn';

  @override
  String generatedNTags(int n) {
    return 'Generated $n tags';
  }

  @override
  String writtenNChars(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n characters',
      one: '1 character',
    );
    return 'Written · $_temp0';
  }

  @override
  String aiGaveNChars(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n characters',
      one: '1 character',
    );
    return 'The AI gave $_temp0';
  }

  @override
  String get aiWroteFull => 'The AI wrote a full prompt';

  @override
  String get sameAsYours => 'Same as your current prompt';

  @override
  String get aiChanges => 'AI\'s Changes';

  @override
  String get settingMessageSize => 'Message Text Size';

  @override
  String get settingMessageSizeDesc => 'Text size of chat messages';

  @override
  String get streamOutput => 'Streaming';

  @override
  String get streamOutputDesc => 'Show replies as they\'re written';

  @override
  String get settingDraw => 'Generation';

  @override
  String get plainTextFormat => 'Plain Text';

  @override
  String get plainTextFormatDesc =>
      'Prompts show as text only; no import or generation';

  @override
  String get importModeDesc =>
      'Where prompts go in the Create page\'s main prompt';

  @override
  String get settingAuto => 'Automation';

  @override
  String get settingChat => 'Chat';

  @override
  String get contextTurns => 'Context Turns';

  @override
  String get contextTurnsDesc => 'How many recent turns to include each time';

  @override
  String get failRetries => 'Retry on error';

  @override
  String get failRetriesDesc => 'Resend on errors';

  @override
  String get retryStripImage => 'Drop images on last retry';

  @override
  String get retryStripImageDesc => 'Omit attached images on the final retry';

  @override
  String get refusalRetries => 'Retry on refusal';

  @override
  String get refusalRetriesDesc =>
      'Regenerate when the reply looks like a refusal';

  @override
  String get refusalKeywords => 'Refusal keywords';

  @override
  String get refusalKeywordsDesc =>
      'A reply without a prompt that contains any of these counts as a refusal';

  @override
  String get addRefusalKeyword => 'Add keywords, separated by commas';

  @override
  String get restoreDefaultKeywordsQ => 'Restore default keywords?';

  @override
  String get restoreDefaultKeywordsBody =>
      'Keywords you added or removed will be reverted';

  @override
  String keywordsN(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n keywords',
      one: '1 keyword',
    );
    return '$_temp0';
  }

  @override
  String get settingLibrary => 'Library';

  @override
  String get ocPlaceholder => 'OC Placeholders';

  @override
  String get ocPlaceholderDesc =>
      'The AI only sees placeholders for OCs, restored when drawing; turn off when editing an OC\'s design';

  @override
  String get modelUnsupported => 'Not supported by this model';

  @override
  String get settingRules => 'Rules';

  @override
  String get rulePresetsDesc => 'Rules followed when writing prompts';

  @override
  String get settingDebug => 'Debug';

  @override
  String get exportChatLog => 'Export Chat Log';

  @override
  String get exportChatLogDesc =>
      'What was sent to the AI and returned for each turn of this chat';

  @override
  String get chatEmpty => 'This chat is empty';

  @override
  String get chatLogExported => 'Chat log exported';

  @override
  String get adjustThinkDepth => 'Thinking Depth';

  @override
  String get thinkDepthNote =>
      'Not every model supports adjusting depth; check the model and provider docs.';

  @override
  String naiStatusLine(String state) {
    return 'NovelAI image generation: $state';
  }

  @override
  String get naiStateDown => 'service disruption';

  @override
  String get naiStatePartial => 'partial disruption';

  @override
  String get naiStateDegraded => 'degraded performance';

  @override
  String get naiStateMaintenance => 'maintenance';

  @override
  String get naiStateSecurity => 'security event';

  @override
  String get naiStateIssue => 'issue';

  @override
  String get naiStatusDetails => 'Details';
}

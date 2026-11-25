// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get language => '语言';

  @override
  String get uiLanguage => '界面语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get cancel => '取消';

  @override
  String get undo => '撤销';

  @override
  String get clear => '清空';

  @override
  String get confirm => '确认';

  @override
  String get generate => '生成';

  @override
  String get model => '模型';

  @override
  String get prompt => '提示词';

  @override
  String get positivePrompt => '正向提示词';

  @override
  String get negativePrompt => '负向提示词';

  @override
  String get characterPrompts => '角色提示词';

  @override
  String get importImage => '导入图片';

  @override
  String get advanced => '高级';

  @override
  String get advancedSettings => '高级设置';

  @override
  String get resetSettings => '恢复默认';

  @override
  String get resolution => '分辨率';

  @override
  String get size => '尺寸';

  @override
  String get imageCount => '张数';

  @override
  String get steps => '步数';

  @override
  String get seedRandom => '每次随机';

  @override
  String get paramSteps => '步数 Steps';

  @override
  String get paramCfg => '提示词引导 CFG';

  @override
  String get paramSampler => '采样器 Sampler';

  @override
  String get paramScheduler => '调度器 Scheduler';

  @override
  String get paramNoiseSchedule => '噪声调度 Noise Schedule';

  @override
  String get paramSeed => '种子 Seed';

  @override
  String get cfgRescale => 'CFG Rescale';

  @override
  String get varietyPlus => 'Variety+';

  @override
  String get sizeNormal => '小图';

  @override
  String get sizeLarge => '大图';

  @override
  String get sizeWallpaper => '壁纸';

  @override
  String get sizeCustom => '自定义';

  @override
  String get sizePortrait => '竖图';

  @override
  String get sizeLandscape => '横图';

  @override
  String get sizeSquare => '方形';

  @override
  String get sizePortraitScreen => '竖屏';

  @override
  String get sizeLandscapeScreen => '横屏';

  @override
  String get width => '宽度';

  @override
  String get height => '高度';

  @override
  String get swapDimensions => '交换宽高';

  @override
  String get img2img => '图生图';

  @override
  String get paramStrength => '强度 Strength';

  @override
  String get paramNoise => '噪声 Noise';

  @override
  String get strength => '强度';

  @override
  String get inpaint => '重绘';

  @override
  String get inpaintStrength => '重绘强度';

  @override
  String get inpaintPaint => '涂抹';

  @override
  String get removeMask => '移除遮罩';

  @override
  String get draw => '画笔';

  @override
  String get erase => '橡皮';

  @override
  String get penSize => '笔刷大小';

  @override
  String get penSizeShort => '笔刷';

  @override
  String get holdToCompare => '按住对比';

  @override
  String get presetHeavy => 'Heavy (重度)';

  @override
  String get presetLight => 'Light (轻度)';

  @override
  String get presetStandard => 'Standard (标准)';

  @override
  String get presetNone => 'None (无)';

  @override
  String get vibeTransfer => 'Vibe Transfer';

  @override
  String get referenceStrength => 'Strength 参考强度';

  @override
  String get infoExtracted => 'Info Extracted 信息提取';

  @override
  String get normalizeStrength => '均衡强度';

  @override
  String get preciseReference => '角色参考';

  @override
  String get fidelity => 'Fidelity 保真度';

  @override
  String get refCharacter => '角色';

  @override
  String get refStyle => '风格';

  @override
  String get refCharacterStyle => '角色&风格';

  @override
  String get refOutfit => '服装';

  @override
  String get preferSameOutfit => '优先相同服装';

  @override
  String get characters => '角色';

  @override
  String get addCharacter => '添加角色';

  @override
  String get position => '设置角色位置';

  @override
  String get aiChoice => '自动';

  @override
  String get aiChoicePosition => '自动定位';

  @override
  String get aiChoiceAll => '全部自动 (AUTO)';

  @override
  String get savePosition => '确认保存';

  @override
  String get importSteps => 'Steps';

  @override
  String get importCfg => 'CFG';

  @override
  String get importSampler => 'Sampler';

  @override
  String get importScheduler => 'Scheduler';

  @override
  String get importSeed => 'Seed';

  @override
  String get ok => '确定';

  @override
  String get add => '添加';

  @override
  String get remove => '移除';

  @override
  String get enable => '启用';

  @override
  String get start => '开始';

  @override
  String get free => '免费';

  @override
  String get loading => '加载中';

  @override
  String get notFetched => '未获取';

  @override
  String get commaSep => '，';

  @override
  String get tapToView => '点按查看';

  @override
  String get tapToReturn => '点按回到应用';

  @override
  String get shortDone => '完成';

  @override
  String get shortStopped => '中止';

  @override
  String get shortPaused => '暂停';

  @override
  String get shortFailed => '失败';

  @override
  String get shortPreparing => '准备';

  @override
  String get lpPreparing => '准备生成…';

  @override
  String get lpGenDone => '生成完成';

  @override
  String get lpAssistantThinking => 'AI 助手思考中…';

  @override
  String get lpAssistantThinkingShort => '思考中';

  @override
  String get lpAssistantReplied => 'AI 助手已回复';

  @override
  String get lpAssistantFailed => 'AI 助手回复失败';

  @override
  String get loopGenerate => '循环生成';

  @override
  String vibesDisabledNoEncoding(int n) {
    return '$n 个 Vibe 缺当前模型编码,已停用';
  }

  @override
  String cancelTrackedJob(int count) {
    return '取消当前跟随的这条($count 条在跑)';
  }

  @override
  String get cancelGeneration => '取消生成';

  @override
  String stepsFixed(String model, int steps) {
    return '$model 步数固定为 $steps';
  }

  @override
  String samplerFixed(String model, String sampler) {
    return '$model 采样器固定为 $sampler';
  }

  @override
  String noiseScheduleFixed(String model) {
    return '$model 噪声调度固定为 karras';
  }

  @override
  String paramUnsupported(String model, String param) {
    return '$model 不支持「$param」';
  }

  @override
  String get batchLockedHires => '重绘放大开着时只能出 1 张:二段采样要按放大后的尺寸再跑一遍,显存吃不下一批。';

  @override
  String get refDisable => '停用此参考图';

  @override
  String refIndex(int index) {
    return '参考图 $index';
  }

  @override
  String switchModelTooltip(String model) {
    return '切换模型：$model';
  }

  @override
  String switchModelSemantics(String model) {
    return '切换模型，当前 $model';
  }

  @override
  String get descNai5Full => '最新旗舰模型 · 1471 token · NSFW';

  @override
  String get descNai5Medium => '最新旗舰 Medium 档 · 节约 40% 额度 · NSFW';

  @override
  String get descNai5Curated => '最新精选版 · 703 token · SFW';

  @override
  String get descNai45Full => 'V4.5 旧模型 · NSFW';

  @override
  String get descNai45Curated => 'V4.5 旧模型精选版 · SFW';

  @override
  String get descNai4Full => 'V4 旧模型 · NSFW';

  @override
  String get descNai4Curated => 'V4 旧模型精选版 · SFW';

  @override
  String positionHint(int w, int h) {
    return '$w×$h · 点按或拖动放置角色';
  }

  @override
  String get sizeMine => '我的';

  @override
  String get sizePhone => '手机';

  @override
  String get savePreset => '存为预设';

  @override
  String get overPixelLimit => '超出像素上限';

  @override
  String confirmSize(int w, int h) {
    return '确认 · $w×$h';
  }

  @override
  String get tierCostsAnlas => '消耗点数';

  @override
  String get tierOverLimit => '超出上限';

  @override
  String get shrinkToLimit => '缩到上限';

  @override
  String get shrinkToFree => '缩到免费';

  @override
  String get promptPresets => '提示词预设';

  @override
  String get promptPresetsHelp => '生成时自动拼进正/负提示词,不占用输入框。V5 与 4.5 各有一套档。';

  @override
  String get sectionSampling => '采样';

  @override
  String get sectionAdjust => '修正';

  @override
  String get freeUpTo28 => '≤28 免费';

  @override
  String get seedRandomTooltip => '每次随机 · 点击手填种子';

  @override
  String get seedManualTooltip => '手填种子 · 点击改为每次随机';

  @override
  String get managePresets => '管理预设';

  @override
  String get loopIntro => '按当前参数一张接一张地出图,种子留空就每张随机。中途出错会自动停下,也可以退到后台,进度在通知栏继续。';

  @override
  String get estimatedCost => '预估消耗';

  @override
  String costPerImageTotal(int cost, int total) {
    return '$cost/张 · 共 $total Anlas';
  }

  @override
  String costPerImage(int cost) {
    return '$cost Anlas/张';
  }

  @override
  String costEncodeExtra(int fee) {
    return ' + 编码 $fee';
  }

  @override
  String get infiniteLoopTitle => '无限循环会持续扣点';

  @override
  String infiniteLoopBody(int cost) {
    return '当前参数每张约 $cost Anlas,张数为无限——不点停止就会一直生成,退到后台也会继续。确定开始?';
  }

  @override
  String infiniteLoopBodyFee(int cost, int fee) {
    return '当前参数每张约 $cost Anlas(另首张含 $fee 点 Vibe 编码费),张数为无限——不点停止就会一直生成,退到后台也会继续。确定开始?';
  }

  @override
  String get generationBusy => '当前有生成进行中';

  @override
  String startLoop(String count) {
    return '开始循环 $count';
  }

  @override
  String get loopRunning => '循环生成中';

  @override
  String loopImageOf(int n, int total) {
    return '第 $n / $total 张';
  }

  @override
  String loopImage(int n) {
    return '第 $n 张';
  }

  @override
  String get loopStopping => '本张后停止';

  @override
  String get loopStopAfterThis => '停止(本张跑完后)';

  @override
  String get loopDone => '循环完成';

  @override
  String get loopAborted => '循环中止';

  @override
  String get generationFailed => '生成失败';

  @override
  String loopDoneText(int n) {
    return '已出 $n 张 · 点按查看';
  }

  @override
  String get queueDone => '队列完成';

  @override
  String get queuePaused => '队列暂停';

  @override
  String queueDoneText(int n) {
    return '共 $n 张 · 点按查看';
  }

  @override
  String queueLeftText(int n) {
    return '剩 $n 项';
  }

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get rename => '重命名';

  @override
  String get disable => '停用';

  @override
  String get edit => '编辑';

  @override
  String get view => '查看';

  @override
  String get close => '关闭';

  @override
  String get name => '名称';

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get untitled => '未命名';

  @override
  String get sectionMain => '主体';

  @override
  String get sectionStyle => '画风';

  @override
  String get sectionCodex => '法典';

  @override
  String sectionN(int n) {
    return '分区 $n';
  }

  @override
  String get clearPositivePrompt => '清空正向提示词';

  @override
  String get clearPromptAndSections => '清空提示词和分区';

  @override
  String get inspirationLibrary => '灵感库';

  @override
  String get addSection => '添加分区';

  @override
  String get tapToEditPositive => '点击编辑正面提示词…';

  @override
  String get tapToEditNegative => '点击编辑负面提示词…';

  @override
  String get tapToEdit => '点击编辑…';

  @override
  String get exitMultiSelect => '退出多选';

  @override
  String selectedCount(int n) {
    return '已选 $n';
  }

  @override
  String get saveToInspiration => '存到灵感库';

  @override
  String get merge => '合并';

  @override
  String sectionsDeleted(int n) {
    return '已删除 $n 个分区';
  }

  @override
  String mergedInto(String name) {
    return '已合并到「$name」';
  }

  @override
  String get inspirationAllExist => '灵感库里都已有了';

  @override
  String inspirationSavedSkipped(int saved, int skipped) {
    return '已存 $saved 条到灵感库,$skipped 条已有';
  }

  @override
  String inspirationSaved(int saved) {
    return '已存 $saved 条到灵感库';
  }

  @override
  String inspirationAlreadyHas(String name) {
    return '灵感库里已有「$name」';
  }

  @override
  String get clearedPositivePrompt => '已清空正向提示词';

  @override
  String get clearedPromptAndSections => '已清空提示词和分区';

  @override
  String charactersFull(int cap, int dropped) {
    return '角色已满 $cap 个,$dropped 个没加进去';
  }

  @override
  String get disableKeepConfig => '停用(保留配置)';

  @override
  String get deleteSection => '删除分区';

  @override
  String deletedNamed(String name) {
    return '已删除「$name」';
  }

  @override
  String get deletePreset => '删除预设';

  @override
  String deletePresetBody(String name) {
    return '「$name」将被删除;若正在激活,回落到「无」。';
  }

  @override
  String get newPreset => '新建预设';

  @override
  String get viewPreset => '查看预设';

  @override
  String get editPreset => '编辑预设';

  @override
  String get presetPageIntro =>
      '激活的预设在生成时自动作为前缀拼进正/负提示词,不占用输入框。默认预设不可修改;右上角可新建自定义预设。';

  @override
  String get presetGroupLegacy => '4.5 及更早';

  @override
  String get presetGroupDefault => '默认';

  @override
  String get noPrefix => '无前缀';

  @override
  String get placement => '拼接位置';

  @override
  String get placementStart => '开头';

  @override
  String get placementEnd => '末尾';

  @override
  String get emptyHint => '空…';

  @override
  String get presetName => '预设名称';

  @override
  String get defaultPresetReadOnly => '默认预设不可修改,可新建自定义预设替代。';

  @override
  String get positivePrefix => '正向前缀';

  @override
  String get positiveSuffix => '正向后缀';

  @override
  String get negativePrefix => '负向前缀';

  @override
  String stepsN(int n) {
    return '$n 步';
  }

  @override
  String get sampler => '采样器';

  @override
  String get noiseSchedule => '噪声调度';

  @override
  String get scheduler => '调度器';

  @override
  String applyRecipeTitle(String name) {
    return '套用「$name」的推荐参数?';
  }

  @override
  String get apply => '套用';

  @override
  String get dontApply => '不用';

  @override
  String recipeApplied(String name) {
    return '已套用「$name」的推荐参数';
  }

  @override
  String get more => '更多';

  @override
  String get refDefaultName => '参考图';

  @override
  String get refMutexVibePaused => '与 Vibe 互斥,已暂停 Vibe 参考';

  @override
  String get refMutexCharRefPaused => '与角色参考互斥,已暂停角色参考';

  @override
  String get refLibrary => '参考图库';

  @override
  String get importCharRef => '导入角色参考图';

  @override
  String get charRefOnly45 => '当前模型不支持角色参考，生成时不会发送。';

  @override
  String get charRefOutfitSkipped => '当前模型不支持「服装」参考，已选的服装参考图在生成时将被跳过。';

  @override
  String get charRefIgnoredInpaint => '当前模型重绘时不支持角色参考';

  @override
  String charRefMaxExceeded(int max) {
    return '最多同时生效 $max 张角色参考图，超出的将在生成时被跳过。';
  }

  @override
  String filesImportFailed(int n) {
    return '$n 个文件无法导入';
  }

  @override
  String get nothingToImport => '没有可导入的内容';

  @override
  String get inactiveWhenInpainting => '重绘时不生效';

  @override
  String get vibeLibrary => 'Vibe 库';

  @override
  String get importVibe => '导入 Vibe 参考图';

  @override
  String get infoExtractedFixed => 'Info Extracted 信息提取(随编码固定)';

  @override
  String resolutionMatchedBase(int w, int h) {
    return '分辨率已按底图调整为 $w×$h';
  }

  @override
  String get removeBaseImage => '移除底图';

  @override
  String get changeBaseImage => '更换底图';

  @override
  String get selectBaseImage => '选择底图';

  @override
  String get cantReadRef => '无法读取该参考图';

  @override
  String get deleteRefImage => '删除参考图';

  @override
  String deleteRefsBody(int n) {
    return '将从库中删除选中的 $n 张(文件与缩略图一并移除),不可恢复。';
  }

  @override
  String get refImageName => '参考图名称';

  @override
  String deleteRefBody(String name) {
    return '「$name」将从图库移除(不影响已添加到生成面板的),不可恢复。';
  }

  @override
  String refsAdded(int n) {
    return '已入库 $n 张参考图';
  }

  @override
  String get charRefLibrary => '角色参考图库';

  @override
  String get searchName => '搜索名称…';

  @override
  String get noCharRefs => '还没有角色参考图';

  @override
  String get noMatchingRefs => '没有匹配的参考图';

  @override
  String get charRefLibraryHint => '在生成页导入参考图后会自动收藏到这里';

  @override
  String confirmSelectionN(int n) {
    return '确认选择 ($n)';
  }

  @override
  String get confirmSelection => '确认选择';

  @override
  String get defaultCanvas => '默认画布';

  @override
  String canvasN(int n) {
    return '画布 $n';
  }

  @override
  String get canvasCopySuffix => ' · 副本';

  @override
  String characterN(int n) {
    return '角色 $n';
  }

  @override
  String get switchCanvas => '切换画布';

  @override
  String currentCanvasSemantics(String name, int count) {
    return '当前画布：$name，共 $count 张';
  }

  @override
  String get renameCanvas => '重命名画布';

  @override
  String get canvasName => '画布名称';

  @override
  String get canvases => '画布';

  @override
  String get newCanvas => '新建画布';

  @override
  String get duplicateCurrent => '复制当前';

  @override
  String get history => '历史';

  @override
  String get defaultCanvasLocked => '默认画布，固定在最上面，不能删除或改名';

  @override
  String get noPromptYet => '尚未填写提示词';

  @override
  String get noCharacters => '无角色';

  @override
  String get previewOnlyNoImage => '没收到成图,只拿到了预览帧';

  @override
  String poolFull(int n) {
    return '同时最多 $n 条任务,等前面的出完再提交';
  }

  @override
  String get jobWaiting => '等待中';

  @override
  String get jobSaving => '保存中';

  @override
  String get noEligibleToken => '没有能接这一单的令牌(检查各令牌的参与条件)';

  @override
  String get naiTokenNotSet => '未设置 NovelAI 令牌';

  @override
  String generationFailedWith(String error) {
    return '生成失败:$error';
  }

  @override
  String rateLimitedRetryIn(int secs, int n, int total) {
    return '限流 · ${secs}s 后重试($n/$total)';
  }

  @override
  String rateLimitedRetryNow(int n, int total) {
    return '限流 · 立即重试($n/$total)';
  }

  @override
  String get shortRateLimited => '限流';

  @override
  String notifyImageOf(int n, int total) {
    return '第 $n/$total 张';
  }

  @override
  String notifyQueueOf(int n, int total) {
    return '队列 $n/$total';
  }

  @override
  String shortImages(int n) {
    return '$n 张';
  }

  @override
  String generatingCount(int n) {
    return '生成中 · $n 张';
  }

  @override
  String get generatingEllipsis => '生成中…';

  @override
  String generatingCountStep(int n, int step, int total) {
    return '生成中 · $n 张 ($step/$total)';
  }

  @override
  String generatingStep(int step, int total) {
    return '生成中 $step/$total';
  }

  @override
  String get noTokenCantEncode => '未设置令牌,无法编码';

  @override
  String get anlasAndQuota => '点数与额度';

  @override
  String get refresh => '刷新';

  @override
  String get subscriptionTier => '订阅档位';

  @override
  String get anlasPoints => 'Anlas 点数';

  @override
  String get refillRate => '回充速率';

  @override
  String imagesPerHour(String n) {
    return '$n 张 / 时';
  }

  @override
  String get timeToFull => '距充满';

  @override
  String get nai5Quota => 'NAI 5 额度';

  @override
  String nai5QuotaAccounts(int n) {
    return 'NAI 5 额度 · $n 号';
  }

  @override
  String get notProvided => '接口未下发';

  @override
  String get opusOnly => '仅 Opus';

  @override
  String aboutImages(String n) {
    return '约 $n 张';
  }

  @override
  String get quotaExhausted => '已用尽 · 免费尺寸图改扣 Anlas';

  @override
  String get quotaFull => '已充满';

  @override
  String quotaIn24h(String pct) {
    return '24 小时后 $pct%';
  }

  @override
  String aboutHours(int n) {
    return '约 $n 小时';
  }

  @override
  String aboutDays(String n) {
    return '约 $n 天';
  }

  @override
  String switchedToModel(String model) {
    return '已切换到 $model 模型';
  }

  @override
  String moduleOfProvider(String module, String provider) {
    return '「$module」是 $provider 的功能';
  }

  @override
  String moduleHidden(String module) {
    return '「$module」已在创作页模块里隐藏';
  }

  @override
  String importedPreset(String name) {
    return '预设 $name';
  }

  @override
  String vibesEncodingOnly(int n, String model) {
    return '$n 个 Vibe 仅编码,只在 $model 下可用';
  }

  @override
  String get importedToCreate => '已导入到创作页';

  @override
  String importedWith(String details) {
    return '已导入 · $details';
  }

  @override
  String setAsBaseImageRes(int w, int h) {
    return '已设为图生图底图 · 分辨率 $w×$h';
  }

  @override
  String get setAsBaseImage => '已设为图生图底图';

  @override
  String get addedVibeMutex => '已加入 Vibe · 与角色参考互斥,已暂停角色参考';

  @override
  String get addedVibe => '已加入 Vibe 参考';

  @override
  String get addedCharRefMutex => '已加入角色参考 · 与 Vibe 互斥,已暂停 Vibe';

  @override
  String get addedCharRef => '已加入角色参考';

  @override
  String get importReplace => '完全覆盖';

  @override
  String get importNewSection => '新建分区';

  @override
  String get importAppend => '额外添加';

  @override
  String get noParamsUseAsRef => '未在这张图里找到生成参数,仍可把它用作参考。';

  @override
  String get useImageAs => '把这张图用作';

  @override
  String get importToCreate => '导入到生成页';

  @override
  String promptOnlyCrossModel(String image, String current) {
    return '这是 $image 模型的图片,当前为 $current 模型,只能导入提示词。';
  }

  @override
  String promptOnlyUnknown(String source) {
    return '$source 图片在本机没有对应的模型,只能导入提示词。';
  }

  @override
  String partialCrossModel(String other, String current) {
    return '这张图用的是 $other 的模型,当前为 $current,仅能导入部分参数';
  }

  @override
  String get partialUnknown => '这张图用的模型本机没有,仅能导入部分参数';

  @override
  String foreignModel(String other) {
    return '这张图用的是 $other 的模型';
  }

  @override
  String get notLocalModel => '不是本机支持的模型';

  @override
  String get presetNeedPrompt => '需要先勾选正向或负向提示词';

  @override
  String presetStripSwitch(String name) {
    return '以上文本会从提示词里删掉,档位切成「$name」。';
  }

  @override
  String get presetStripKeep => '以上文本会从提示词里删掉,档位不变。';

  @override
  String get presetNoPositive => '(这一档不加正向文本)';

  @override
  String get autoConvertPrompt => '自动转换提示词格式';

  @override
  String get autoConvertPromptHint => '把 (tag:1.2) 转成 NovelAI 的 1.2::tag::';

  @override
  String noParamsSize(String size) {
    return '未找到生成参数 · $size';
  }

  @override
  String charactersBadge(int n) {
    return '$n 角色';
  }

  @override
  String copyWhat(String what) {
    return '复制$what';
  }

  @override
  String copiedWhat(String what) {
    return '已复制$what';
  }

  @override
  String get seed => '种子';

  @override
  String copiedSeed(String value) {
    return '已复制种子 $value';
  }

  @override
  String vibeParams(String strength, String ie) {
    return '强度 $strength · IE $ie';
  }

  @override
  String encodingOnlyParams(String params) {
    return '仅编码 · $params';
  }

  @override
  String get encodingOnlyUnknown => '仅编码 · 来源模型未知,无法导入';

  @override
  String get paramsOnlyCantImport => '仅有参数,无法导入';

  @override
  String get genSettings => '生成设置';

  @override
  String unsupportedParams(String params) {
    return '含当前版本不支持的参数($params),无法导入生成设置。';
  }

  @override
  String get importMode => '导入方式';

  @override
  String get emptyParen => '(空)';

  @override
  String get importSelected => '导入所选内容';

  @override
  String get useAsReference => '参考';

  @override
  String get unknownSource => '未知来源';

  @override
  String get fullMetadataTwoLine => '完整\n元数据';

  @override
  String get fullMetadata => '完整元数据';

  @override
  String get closeImport => '关闭导入';

  @override
  String get goToImportPanel => '去导入面板(导入参数 / 用作参考)';

  @override
  String get fileSize => '大小';

  @override
  String get format => '格式';

  @override
  String get source => '来源';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get transparentBg => '透明背景';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get alphaStraight => '直通 Straight';

  @override
  String get alphaPremultiplied => '预乘 Premultiplied';

  @override
  String get genParams => '生成参数';

  @override
  String vibeStrengthLabel(String v) {
    return '强度: $v';
  }

  @override
  String vibeExtractedLabel(String v) {
    return '提取: $v';
  }

  @override
  String get rawData => '原始数据';

  @override
  String get genInProgressWait => '生成进行中,请稍候';

  @override
  String get notAligned64Expand => '图片尺寸非 64 对齐,无法扩图';

  @override
  String get expandTooLarge => '扩图后尺寸过大,请缩小扩展范围';

  @override
  String get savedToInpaint => '已存入重绘';

  @override
  String get censorNothingFound => '没检测到需要打码的区域';

  @override
  String censorDetected(int n) {
    return '检测到 $n 处,已预填';
  }

  @override
  String censorDetectFailed(String error) {
    return '自动识别失败: $error';
  }

  @override
  String get censorColor => '打码颜色';

  @override
  String get paintCensorFirst => '先涂抹要打码的区域';

  @override
  String get censoredSaved => '已打码并存入图库';

  @override
  String censorFailed(String error) {
    return '打码失败: $error';
  }

  @override
  String inpaintNeedNai(String model) {
    return '$model 模型不支持重绘,请先切回 NovelAI 模型';
  }

  @override
  String get dragEdgesFirst => '先拖动边缘扩展画布';

  @override
  String get paintInpaintFirst => '先用画笔涂抹要重绘的区域';

  @override
  String get noPaintInBox => '黄框内没有涂抹区域';

  @override
  String get paintOutsideBox => '黄框外还有涂抹,拉大黄框或分两次重绘';

  @override
  String get sendTooLarge => '发送尺寸过大,请开启「局部」缩小范围';

  @override
  String get notAligned64UseRegion => '图片尺寸非 64 对齐,请使用「局部」模式';

  @override
  String get tabExpand => '扩图';

  @override
  String get tabCensor => '打码';

  @override
  String get toolOffset => '偏位';

  @override
  String get toolRegion => '局部';

  @override
  String get censorBlock => '块';

  @override
  String get censorColorShort => '颜色';

  @override
  String get saveMask => '保存遮罩';

  @override
  String get saveExpand => '保存扩图';

  @override
  String get autoDetect => '自动识别';

  @override
  String get detecting => '识别中…';

  @override
  String get savingEllipsis => '保存中…';

  @override
  String get mosaicBlock => '马赛克块';

  @override
  String get expandSize => '扩图尺寸';

  @override
  String get widthShort => '宽';

  @override
  String get heightShort => '高';

  @override
  String expandHint(int w, int h) {
    return '原图 $w×$h,增量对称分配到两侧(64 对齐)';
  }

  @override
  String get censorMosaic => '马赛克';

  @override
  String get censorSolid => '纯色';

  @override
  String get colorBlack => '黑';

  @override
  String get colorDarkGray => '深灰';

  @override
  String get colorLightGray => '浅灰';

  @override
  String get colorWhite => '白';

  @override
  String weightGroupInfo(String group, String total) {
    return '处于权重组 ×$group · 合计 ×$total';
  }

  @override
  String weightGroupOnly(String group) {
    return '处于权重组 ×$group';
  }

  @override
  String get selectWholeGroup => '选中整组';

  @override
  String get sdWeightConvert => 'SD 权重语法 · 点击转换为 NAI 格式';

  @override
  String get sdWeightConvertShort => 'SD 权重语法 · 转成 NAI';

  @override
  String get weight => '权重';

  @override
  String get clearWeight => '清除权重';

  @override
  String get clearWeightShort => '清除权重';

  @override
  String get related => '关联';

  @override
  String get disableTag => '禁用';

  @override
  String get tagLabel => '标签';

  @override
  String get tagCopied => '已复制标签';

  @override
  String get cantOpenBrowser => '无法打开浏览器';

  @override
  String get tapPlusToMove => '点击加号移动';

  @override
  String selectedItems(int n) {
    return '已选 $n 项';
  }

  @override
  String get tapTagsToSelect => '点词条可多选';

  @override
  String get extractAsSection => '提取为新分区';

  @override
  String foldSegment(int n) {
    return '折叠段 · $n 个标签';
  }

  @override
  String get expand => '展开';

  @override
  String get collapse => '收起';

  @override
  String get overall => '整体';

  @override
  String get move => '移动';

  @override
  String get editorSettings => '编辑器设置';

  @override
  String get settingDisplay => '显示';

  @override
  String get showTranslations => '显示注释翻译';

  @override
  String get showTranslationsDesc => '在词条下方以小字标注中文翻译';

  @override
  String get weightHighlight => '权重高亮';

  @override
  String get weightHighlightDesc => '加权 / 降权词条按强度显示红 / 蓝色';

  @override
  String get textFontSize => '文本字号';

  @override
  String get textFontSizeDesc => '文本模式下的文本显示大小';

  @override
  String get chipFontSize => '芯片字号';

  @override
  String get chipFontSizeDesc => '芯片模式下的芯片显示大小';

  @override
  String get settingCompletion => '补全';

  @override
  String get enableCompletion => '启用补全提示';

  @override
  String get enableCompletionDesc => '输入时在底部给出标签补全建议';

  @override
  String get entitySuggestions => '实体建议';

  @override
  String get entitySuggestionsDesc => '补全中包含画师 / 角色 / OC / 作品';

  @override
  String get autoComma => '选词自动补逗号';

  @override
  String get autoCommaDesc => '选中补全后自动加「, 」,方便连打下一枚';

  @override
  String get settingTagBar => '词条栏';

  @override
  String get enableTagPanel => '启用标签面板';

  @override
  String get enableTagPanelDesc => '光标停在词条上时显示权重与操作栏';

  @override
  String get compactTagBar => '精简词条栏';

  @override
  String get compactTagBarDesc => '压成一行,只留权重与删除,正文多露两行';

  @override
  String get weightStep => '权重步进';

  @override
  String get weightStepDesc => '数值 +/− 每步的调整量';

  @override
  String get kindArtist => '画师';

  @override
  String get kindWork => '作品';

  @override
  String get kindTag => '标签';

  @override
  String get completionResults => '补全结果';

  @override
  String itemsCount(int n) {
    return '$n 项';
  }

  @override
  String get byHeat => '热度';

  @override
  String get wikiMissing => '没拿到 Wiki 摘要,可再点一次或前往 Danbooru 查看。';

  @override
  String get loadingWiki => '加载 Wiki…';

  @override
  String aliases(String list) {
    return '别名: $list';
  }

  @override
  String wikiLinkCopied(String url) {
    return '已复制 Wiki 链接:$url';
  }

  @override
  String unfavorited(String tag) {
    return '已取消收藏「$tag」';
  }

  @override
  String get noFavorites => '暂无收藏';

  @override
  String get modeText => '文本';

  @override
  String get modeChips => '芯片';

  @override
  String get positiveShort => '正面';

  @override
  String get negativeShort => '负面';

  @override
  String get translateFailed => '翻译失败,稍后再试';

  @override
  String copiedItems(int n) {
    return '已复制 $n 项';
  }

  @override
  String get cantExtractFold => '所选和折叠连在一起,没法提取';

  @override
  String extractedTo(String name) {
    return '已提取到「$name」';
  }

  @override
  String get editorInputHint => '点击输入标签,可输入中文自动触发翻译与联想';

  @override
  String get translating => '翻译中…';

  @override
  String querying(String q) {
    return '查询「$q」…';
  }

  @override
  String noMatchAddTag(String q) {
    return '无匹配 · 点此把「$q」加为新标签';
  }

  @override
  String get workNote => '点骰子随机抽一个角色';

  @override
  String get translateToEnglish => '翻译为英文';

  @override
  String get chipInputHint => '输入标签,可输入中文自动翻译';

  @override
  String get addMore => '继续添加…';

  @override
  String get saveAndBack => '保存并返回';

  @override
  String get localLibrary => '本地库';

  @override
  String get untitledVibe => '未命名 Vibe';

  @override
  String get favorites => '收藏';

  @override
  String get vibeNoEncodingForModel => '该 Vibe 无当前模型的编码,无法使用';

  @override
  String get cantReadVibe => '无法读取该 Vibe 文件';

  @override
  String ingestVibes(int n) {
    return '$n 条 Vibe';
  }

  @override
  String ingestImages(int n) {
    return '$n 张图';
  }

  @override
  String ingestFailed(int n) {
    return '$n 个失败';
  }

  @override
  String importDone(String details) {
    return '导入完成:$details';
  }

  @override
  String get deleteVibe => '删除 Vibe';

  @override
  String deleteVibesBody(int n) {
    return '将从库中删除选中的 $n 条 Vibe(文件与缩略图一并移除),不可恢复。';
  }

  @override
  String deleteVibeBody(String name) {
    return '「$name」将从库中删除(文件与缩略图一并移除),不可恢复。';
  }

  @override
  String vibesExported(int n) {
    return '已导出 $n 条 Vibe';
  }

  @override
  String exportedName(String name) {
    return '已导出 $name';
  }

  @override
  String exportFailed(String error) {
    return '导出失败:$error';
  }

  @override
  String get batchAddTag => '批量添加标签';

  @override
  String get tagNameHint => '标签名,如 风景';

  @override
  String tagAddedToN(int n, String tag) {
    return '已为 $n 条添加标签「$tag」';
  }

  @override
  String get addedToGenerate => '已添加到生成';

  @override
  String get alreadyInGenerate => '已在生成面板中';

  @override
  String get notAvailableYet => '暂未开放';

  @override
  String get vibeManager => 'Vibe 管理器';

  @override
  String get importLabel => '导入';

  @override
  String get importVibeFile => '导入 Vibe 文件';

  @override
  String get searchNameOrTag => '搜索名称或标签…';

  @override
  String localCount(int n) {
    return '本地 · $n';
  }

  @override
  String get publicLibrary => '公共库';

  @override
  String get all => '全部';

  @override
  String get manageTags => '管理标签';

  @override
  String get noLocalVibes => '暂无本地 Vibe';

  @override
  String get noMatchingVibes => '没有匹配的 Vibe';

  @override
  String get tapPlusToImport => '点击右上角 + 导入';

  @override
  String get publicVibeUnavailable => '公共 Vibe 库暂未开放';

  @override
  String get bundle => '打包';

  @override
  String get notEncoded => '未编码';

  @override
  String needsModels(String models) {
    return '需 $models';
  }

  @override
  String get detailsAndParams => '详情与参数';

  @override
  String get editTags => '编辑标签';

  @override
  String get publishToPublic => '发布到公共';

  @override
  String get export => '导出';

  @override
  String get noTagsYetBelow => '还没有标签,在下方输入新建。';

  @override
  String get newTagHint => '新建标签,如 风景';

  @override
  String tagExists(String name) {
    return '标签「$name」已存在';
  }

  @override
  String get renameTag => '重命名标签';

  @override
  String get deleteTag => '删除标签';

  @override
  String deleteTagBody(String tag) {
    return '标签「$tag」将从所有 Vibe 上移除(不删除 Vibe 本身)。';
  }

  @override
  String get newLabel => '新建';

  @override
  String get noTagsYetHint => '还没有标签\n在上方输入框新建,或在某条 Vibe 的「编辑标签」里新建';

  @override
  String get vibeNoImageOrEncoding => '该 Vibe 没有可用的图片或编码';

  @override
  String get encodingOnlyNoImage => '仅编码(无原图)';

  @override
  String get defaultStrength => 'Strength 默认强度';

  @override
  String get defaultInfoExtracted => 'Info Extracted 默认信息提取';

  @override
  String get ieFixedNoImage => 'Info Extracted 随编码固定,无原图不可调整。';

  @override
  String get addToGenerate => '添加到生成';

  @override
  String get encodings => '编码';

  @override
  String get checking => '检查中…';

  @override
  String encodedN(int n) {
    return '已编码 $n';
  }

  @override
  String get clearAllCharacters => '清空全部角色';

  @override
  String get characterLibrary => '角色库';

  @override
  String get clearAllCharactersQ => '清空全部角色?';

  @override
  String get clearAllCharactersBody => '将移除所有角色及其配置,此操作不可撤销。';

  @override
  String replaceCharQ(String name) {
    return '替换「$name」?';
  }

  @override
  String replaceCharBody(String name) {
    return '提示词将换成「$name」的。';
  }

  @override
  String get replace => '替换';

  @override
  String get deleteCharacter => '删除角色';

  @override
  String setCharPosition(String pos) {
    return '设置角色位置：$pos';
  }

  @override
  String get tapToEditPrompt => '点击编辑提示词…';

  @override
  String get pickFromCharLibrary => '从角色库选';

  @override
  String get swapCharacter => '换角色';

  @override
  String get canvasSingular => '画布';

  @override
  String canvasHistoryTitle(String name) {
    return '$name · 历史';
  }

  @override
  String get noHistoryYet => '这张画布还没有出过图';

  @override
  String get restoreThisVersion => '恢复到这版';

  @override
  String get duplicateAsNewCanvas => '复制为新画布';

  @override
  String get duplicatedAsNewCanvas => '已复制为新画布';

  @override
  String restoredTo(String time) {
    return '已恢复到 $time 的版本';
  }

  @override
  String imagesN(int n) {
    return '$n 张';
  }

  @override
  String get noPrompt => '没有提示词';

  @override
  String get negChanged => '负面有改动';

  @override
  String charsChange(int a, int b) {
    return '角色 $a→$b';
  }

  @override
  String get addedBaseImage => '加了底图';

  @override
  String get removedBaseImage => '去掉底图';

  @override
  String get addedInpaint => '加了重绘';

  @override
  String get removedInpaint => '去掉重绘';

  @override
  String stepsChange(int a, int b) {
    return '$a→$b 步';
  }

  @override
  String get paramsChanged => '参数有改动';

  @override
  String dateYesterday(String time) {
    return '昨天 $time';
  }

  @override
  String dateMonthDay(String month, int day, String time) {
    return '$month月$day日 $time';
  }

  @override
  String dateYearMonthDay(int year, String month, int day, String time) {
    return '$year年$month月$day日 $time';
  }

  @override
  String get tabCreate => '创作';

  @override
  String get gallery => '图库';

  @override
  String get tabInspiration => '灵感';

  @override
  String get tabProfile => '我的';

  @override
  String get setTokenFirst => '请先在「我的」页设置 NovelAI API Token';

  @override
  String get goToSettings => '去设置';

  @override
  String savedToAlbum(String name) {
    return '新图片已保存到「$name」';
  }

  @override
  String get viewAfterEditing => '结束编辑后可查看新图片';

  @override
  String get imageDeleted => '这张图片已被删除';

  @override
  String get keyWiped => '已存的 Key 被系统清掉了,重新添加后不会再丢';

  @override
  String get goToAdd => '去添加';

  @override
  String get allImages => '全部图片';

  @override
  String get albums => '相册';

  @override
  String get noAlbums => '没有相册';

  @override
  String get selectImage => '选择图片';

  @override
  String get pickFromFiles => '从文件选';

  @override
  String get noImages => '没有图片';

  @override
  String okCount(int n) {
    return '确定 ($n)';
  }

  @override
  String get limitedPhotoAccess => '仅可访问部分图片';

  @override
  String get adjust => '调整';

  @override
  String get needPhotoPermission => '需要相册访问权限';

  @override
  String get recheck => '重新检查';

  @override
  String get enterNumber => '请输入数字';

  @override
  String outOfRange(String range) {
    return '超出范围 $range';
  }

  @override
  String rangeHint(String range) {
    return '范围 $range';
  }

  @override
  String rangeStepHint(String range, String step) {
    return '范围 $range · 步长 $step';
  }

  @override
  String overwriteConflicts(int n) {
    return '其中 $n 条覆盖本地同 id';
  }

  @override
  String mergeWithConflicts(int n) {
    return '按 id 合并:同 id 覆盖($n 条),其余新增;本地独有的条目保留。';
  }

  @override
  String get mergeNoLoss => '按 id 合并:本地已有的条目一个都不会丢。';

  @override
  String get clearSelection => '取消选择';

  @override
  String get closeMenu => '关闭菜单';

  @override
  String floatCardsColor(String color) {
    return '浮卡 $color';
  }

  @override
  String get colorBlue => '蓝';

  @override
  String get colorOrange => '橙';

  @override
  String get colorPink => '粉';

  @override
  String get colorPurple => '紫';

  @override
  String get colorGreen => '绿';

  @override
  String get colorGold => '金';

  @override
  String get colorLightBlue => '浅蓝';

  @override
  String get colorTeal => '青';

  @override
  String get switchedToFloat => '已换成浮卡,可在「外观与触感」换回';

  @override
  String get switchBack => '换回';

  @override
  String get tryNewTheme => '试试新主题？';

  @override
  String get newThemeBody => '全新外观上线啦!卡片更清爽,挑个喜欢的吧~';

  @override
  String get later => '以后再说';

  @override
  String get tryIt => '试试';

  @override
  String get backup => '备份';

  @override
  String get about => '关于';

  @override
  String get accountAccess => '账号与接入';

  @override
  String get accountAccessSub => 'Token 与 Bot 授权';

  @override
  String get stats => '统计';

  @override
  String get statsSub => '用量 · 钱包 · 全平台统计';

  @override
  String get promptPresetsSub => '正负面提示词模板';

  @override
  String get genSettingsSub => '自动重试 · 功能模块 · 默认保存';

  @override
  String get toolbox => '工具箱';

  @override
  String get toolboxSub => '权重转换 · 图片元数据';

  @override
  String get appearanceHaptics => '外观与触感';

  @override
  String get appearanceSub => '主题配色 · 振动反馈';

  @override
  String get storage => '存储管理';

  @override
  String get storageSub => '空间占用与清理';

  @override
  String get themeMode => '深浅模式';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeColor => '主题色';

  @override
  String get bottomNav => '底部导航';

  @override
  String get showAssistant => '显示 AI 助手';

  @override
  String get showAssistantSub => '关掉后底栏不再显示 AI 入口';

  @override
  String get createPage => '创作页';

  @override
  String get compactCharCards => '紧凑角色卡';

  @override
  String get haptics => '触感';

  @override
  String get hapticFeedback => '振动反馈';

  @override
  String get galleryPicker => '图库选择器';

  @override
  String get inApp => '应用内';

  @override
  String get system => '系统';

  @override
  String get beta => '内测';

  @override
  String get version => '版本';

  @override
  String get dataResources => '数据与资源';

  @override
  String get codexSource => '法典图鉴';

  @override
  String get offlineDict => '离线补全词库';

  @override
  String get zhSearch => '中文搜词与译名';

  @override
  String get imageGen => '图像生成';

  @override
  String get censorModel => '自动打码模型';

  @override
  String get community => '交流';

  @override
  String get qqGroup => 'QQ 交流群';

  @override
  String get guide => '引导';

  @override
  String get reviewGuide => '重新查看引导';

  @override
  String get legal => '法律';

  @override
  String get sourceCode => '源码';

  @override
  String get license => '开源协议';

  @override
  String get thirdPartyLicenses => '第三方许可';

  @override
  String disclaimer(String app) {
    return '$app 是第三方客户端,与 NovelAI 官方无关联。图像由 NovelAI 生成,账号与生成内容产生的一切责任由使用者承担。';
  }

  @override
  String qqCopied(String id) {
    return '已复制群号 $id';
  }

  @override
  String get cantOpenBrowserShort => '打不开浏览器';

  @override
  String get appTagline => 'NovelAI 移动创作端';

  @override
  String legaleseBody(String app) {
    return '本程序是自由软件,依据 GNU GPL v3 或更新版本分发。分发本程序是希望它有用,但不作任何担保。\n\n$app 是第三方客户端,与 NovelAI 官方无关联。';
  }

  @override
  String get noUpdateInfo => '暂无更新信息';

  @override
  String get onLatestVersion => '已是最新版本';

  @override
  String get checkFailed => '检查失败';

  @override
  String newVersion(String v) {
    return '新版本 $v';
  }

  @override
  String get upToDate => '已是最新';

  @override
  String get checkUpdates => '检查更新';

  @override
  String currentVersion(String v) {
    return '当前 $v';
  }

  @override
  String get downloadOnGithub => '去 GitHub 下载';

  @override
  String get downloadUpdate => '下载新版';

  @override
  String updateHttpFailed(int code) {
    return '检查更新失败(HTTP $code)';
  }

  @override
  String get updateBadFormat => '更新信息格式异常';

  @override
  String get updateTimeout => '检查更新超时,请检查网络后重试';

  @override
  String get cantReachUpdateServer => '连不上服务器,请检查网络后重试';

  @override
  String get updateFailed => '检查更新失败,请稍后重试';

  @override
  String get weightConverter => '权重转换';

  @override
  String get imageMetadata => '图片元数据';

  @override
  String get compareImages => '图片比对';

  @override
  String get swapAB => '交换 A / B';

  @override
  String get onlyInA => '仅 A';

  @override
  String get onlyInB => '仅 B';

  @override
  String get weightChanged => '权重不同';

  @override
  String get orderChanged => '位置不同';

  @override
  String get identical => '相同';

  @override
  String identicalN(int n) {
    return '$n 项相同';
  }

  @override
  String differentN(int n) {
    return '$n 项不同';
  }

  @override
  String get enterOverwritePrompt => '先填要覆写的提示词';

  @override
  String get noPhotoPermission => '未获相册权限';

  @override
  String savedToPhotos(int n) {
    return '已保存 $n 张到相册';
  }

  @override
  String savedToPhotosFailed(int saved, int failed) {
    return '已保存 $saved 张 · $failed 张失败';
  }

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get addImages => '添加图片';

  @override
  String get metadataToolIntro => '查看生成参数 · 批量清除或覆写元数据';

  @override
  String get overwritePromptHint => '要覆写进图片的提示词…';

  @override
  String get clearMeta => '清除';

  @override
  String get overwrite => '覆写';

  @override
  String saveToPhotosN(int n) {
    return '存相册 ($n)';
  }

  @override
  String get imageInfo => '图片信息';

  @override
  String noMetadataFor(String name) {
    return '$name · 未识别到元数据';
  }

  @override
  String get promptImported => '已导入提示词';

  @override
  String get stripLora => '去 Lora';

  @override
  String get convert => '转换';

  @override
  String get importPrompt => '导入提示词';

  @override
  String get copyResult => '复制结果';

  @override
  String get genNotify => '生成通知';

  @override
  String get streamingGen => '流式生成';

  @override
  String get straightAlpha => '透明图直通 Alpha';

  @override
  String get keepImageFormat => '保持图片格式';

  @override
  String get autoRetry => '限流后自动重试';

  @override
  String get retryDelay => '重试间隔';

  @override
  String secondsN(int n) {
    return '$n 秒';
  }

  @override
  String get immediately => '立即';

  @override
  String get unitSeconds => '秒';

  @override
  String get retryCount => '重试次数';

  @override
  String timesN(int n) {
    return '$n 次';
  }

  @override
  String get unitTimes => '次';

  @override
  String get galleryDefaultSave => '图库默认保存';

  @override
  String get createPageModules => '创作页模块';

  @override
  String modulesOn(int on, int total) {
    return '已开 $on/$total';
  }

  @override
  String get pngLossless => 'PNG 无损';

  @override
  String get jpgLossy => 'JPG 有损';

  @override
  String get rawMetadata => '原始元数据';

  @override
  String get compressQuality => '压缩质量';

  @override
  String get compressQualityDialog => '压缩质量(10~100)';

  @override
  String get customPrompt => '自定义提示词';

  @override
  String get customPromptHint => '写入图片的提示词(其余参数清除)…';

  @override
  String get notSet => '未设置';

  @override
  String get catCache => '缓存文件';

  @override
  String get catVibeEnc => 'Vibe 编码缓存';

  @override
  String get catModels => '超分模型(遗留)';

  @override
  String get catTagPrev => '灵感预览图';

  @override
  String get catGallery => '图库作品';

  @override
  String get catCharLib => '角色参考库';

  @override
  String get actClean => '清理';

  @override
  String freedSize(String size) {
    return '已释放 $size';
  }

  @override
  String get nothingToClean => '没有可清理的内容';

  @override
  String cleanFailed(String error) {
    return '清理失败: $error';
  }

  @override
  String get clearTagPreviews => '清空灵感预览图';

  @override
  String get clearTagPreviewsBody =>
      '将删除本机生成的条目预览图,并从条目上摘除引用;条目本身与提示词不受影响,预览需重新生成。';

  @override
  String clearTagPreviewsBodyN(int n) {
    return '将删除本机生成的 $n 张条目预览图,并从条目上摘除引用;条目本身与提示词不受影响,预览需重新生成。';
  }

  @override
  String get clearAllAlbums => '清空全部相册数据';

  @override
  String get clearAllAlbumsBody => '将删除全部作品、参数快照和自建相册及封面，不可恢复。已保存到系统相册的图片不受影响。';

  @override
  String clearAllAlbumsBodyN(int n) {
    return '将删除全部 $n 张作品、参数快照和自建相册及封面，不可恢复。已保存到系统相册的图片不受影响。';
  }

  @override
  String get clearEncodingCache => '清空编码缓存';

  @override
  String get clearEncodingCacheBody =>
      '清空后,下次用这些图生成时需重新编码;直连线路每张图约扣 2 Anlas。不影响 Vibe 库文件本身。';

  @override
  String get clearVibeLib => '清空 Vibe 库';

  @override
  String get clearVibeLibBody => '将删除库内全部文件(原图 / 缩略图 / 已存编码),不可恢复。';

  @override
  String clearVibeLibBodyN(int n) {
    return '将删除库内全部 $n 个文件(原图 / 缩略图 / 已存编码),不可恢复。';
  }

  @override
  String get clearCharRefLib => '清空角色参考库';

  @override
  String get clearCharRefLibBody => '将删除库内全部文件,不可恢复。图库作品里的参数快照不受影响。';

  @override
  String clearCharRefLibBodyN(int n) {
    return '将删除库内全部 $n 个文件,不可恢复。图库作品里的参数快照不受影响。';
  }

  @override
  String get deleteUpscaleModels => '删除超分模型';

  @override
  String deleteUpscaleModelsBody(String size) {
    return '本地超分功能已下线,这 $size 模型文件已经用不上了,删掉不会少任何功能。';
  }

  @override
  String get rescan => '重新扫描';

  @override
  String get autoCleanLimits => '自动清理上限';

  @override
  String get cleanable => '可清理';

  @override
  String get totalUsage => '总占用';

  @override
  String otherSize(String size) {
    return '其他 $size';
  }

  @override
  String get unitImages => '张';

  @override
  String get unitItems => '条';

  @override
  String capOf(String label) {
    return '$label上限';
  }

  @override
  String get noLimit => '无上限';

  @override
  String accountsCount(int n) {
    return '$n 账号';
  }

  @override
  String get tokenNeededHint => '直连生成需要你自己的 NovelAI 令牌,仅加密存储在本机';

  @override
  String tokensNoneJoined(int n) {
    return '存了 $n 把,但一把都没参与生成';
  }

  @override
  String get manageTokens => '管理令牌';

  @override
  String get naiProxy => '代理访问 NovelAI';

  @override
  String get naiProxyHint => '经 Cloudflare 转发,无法访问官网时开启';

  @override
  String get queryingAccount => '查询账户状态…';

  @override
  String quotaPct(int pct) {
    return '额度 $pct%';
  }

  @override
  String get statusSaved => '已保存';

  @override
  String get genMethod => '生成方式';

  @override
  String get directToken => 'API Token';

  @override
  String get useBotAccount => '使用 Bot 账户';

  @override
  String get tokenMissing => '尚未保存 Token,当前无法生成';

  @override
  String get useOwnAccount => '使用你的 NovelAI 账户生成图片';

  @override
  String get notSubscribed => '未订阅';

  @override
  String get tokenCopied => '已复制令牌';

  @override
  String get deleteToken => '删除令牌';

  @override
  String deleteTokenBody(String name) {
    return '将从本机删除「$name」,直连能同时出的张数也会少一路。';
  }

  @override
  String get tokenManage => '令牌管理';

  @override
  String maxTokens(int n) {
    return '最多 $n 把';
  }

  @override
  String get addToken => '添加令牌';

  @override
  String get noTokensYet => '还没有令牌';

  @override
  String get multiTokenHint => '存多把可以同时出多张 —— NAI 按账号限流,一把只能跑一条';

  @override
  String get primaryAccount => '主账号';

  @override
  String get copyToken => '复制令牌';

  @override
  String get primaryAlwaysOn => '生成与点数都用它,不可关闭';

  @override
  String get joinFree => '参与免费生成';

  @override
  String get joinPaid => '参与点数生成';

  @override
  String get thirdPartyNoStatus => '第三方接口未提供账户状态';

  @override
  String get tokenExpired => '令牌已失效';

  @override
  String get statusQueryFailedRetry => '状态查询失败,点按重试';

  @override
  String maxTokensSaved(int n) {
    return '最多保存 $n 把令牌';
  }

  @override
  String loginFailed(String error) {
    return '登录失败:$error';
  }

  @override
  String get urlNeedsHttp => '请填 http:// 或 https:// 开头的接口地址';

  @override
  String get pasteToken => '粘贴令牌';

  @override
  String get emailLogin => '邮箱登录';

  @override
  String get thirdParty => '第三方';

  @override
  String get thirdPartyApi => '第三方接口';

  @override
  String get loginAndAdd => '登录并添加';

  @override
  String get tokenWhere =>
      'NovelAI 网站 → User Settings → Account → Get Persistent API Token。';

  @override
  String get needNaiAccess => '直连生成需要你的网络可以访问 NovelAI 官网。';

  @override
  String get sentenceJoin => '';

  @override
  String get pasteTokenHint => '粘贴 pst-… 令牌或网页 eyJ… JWT';

  @override
  String get paste => '粘贴';

  @override
  String get show => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get storedEncryptedLocal => '仅加密存储在本机';

  @override
  String get apiKey => '接口 key';

  @override
  String get passwordLocalHint =>
      '密码只在本机参与密钥计算,不上传也不保存;登录得到 30 天有效的令牌,到期前 App 会自动换新。';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get formatNai => 'NovelAI 格式';

  @override
  String get formatNaiHint => 'NovelAI 接口格式：/ai/generate-image';

  @override
  String get formatOpenai => 'OpenAI 格式';

  @override
  String get formatOpenaiHint => 'OpenAI 接口格式：/v1/chat/completions';

  @override
  String get naiAccountLogin => 'NovelAI 账号登录';

  @override
  String get login => '登录';

  @override
  String get tokenInvalid => '令牌无效';

  @override
  String get accountQueryFailedRetry => '账户状态查询失败,点按重试';

  @override
  String networkError(String error) {
    return '网络错误:$error';
  }

  @override
  String get wrongCredentials => '邮箱或密码错误';

  @override
  String loginHttpFailed(int code) {
    return '登录失败(HTTP $code)';
  }

  @override
  String get loginNoToken => '登录响应缺少 accessToken';

  @override
  String get getStarted => '开始使用';

  @override
  String get enableNotifications => '开启通知';

  @override
  String get next => '下一步';

  @override
  String get notNow => '暂不开启';

  @override
  String get skipForNow => '暂时跳过';

  @override
  String get welcomeTitle => '欢迎使用 Plana';

  @override
  String get featEditor => '全屏提示词编辑器';

  @override
  String get featGallery => '图库留参数,随时复现';

  @override
  String get featTools => 'Vibe · 参考 · 重绘 · 超分';

  @override
  String get appearanceColors => '外观配色';

  @override
  String get accessMethod => '生成接入方式';

  @override
  String get subscriptionRequired => '必须拥有官方或中转订阅才能进行生成';

  @override
  String get directNaiToken => '官方订阅';

  @override
  String get official => '官方';

  @override
  String get noTokenUseLogin => '没有令牌?用邮箱密码登录';

  @override
  String get notifyTitle => '生成进度通知';

  @override
  String get notifyDesc => '开启后可接收生成进度及完成通知,Android 16+ 支持灵动岛显示';

  @override
  String get allDone => '全部完成';

  @override
  String get channelProgress => '生成进度';

  @override
  String get channelProgressDesc => '生成期间的常驻进度条(静默)';

  @override
  String get channelDone => '生成完成';

  @override
  String get channelDoneDesc => '出图 / 队列 / 循环结束时提醒一次';

  @override
  String get cloudBackup => 'Plana 云端';

  @override
  String get backupToCloud => '备份到 Plana 云端';

  @override
  String get restoreFromCloud => '从 Plana 云端恢复';

  @override
  String get selectBackupFile => '选择备份文件';

  @override
  String get notBackupFile => '不是可识别的备份文件';

  @override
  String get importComplete => '导入完成';

  @override
  String importCompleteFailed(int n) {
    return '导入完成,$n 项失败';
  }

  @override
  String get notValidJson => '不是有效的 JSON 文件';

  @override
  String importFailed(String error) {
    return '导入失败:$error';
  }

  @override
  String get webBackupEmpty => '这份 web 备份里没有可导入的内容';

  @override
  String get customCatMissing => '文件里的自定义分类在本机不存在';

  @override
  String get fileNoEntries => '文件里没有条目';

  @override
  String inspirationOf(String cat) {
    return '灵感库 · $cat';
  }

  @override
  String get chooseImportContent => '选择要导入的内容';

  @override
  String itemsN(int n) {
    return '$n 条';
  }

  @override
  String addedUpdated(int a, int u) {
    return '新增 $a · 覆盖 $u';
  }

  @override
  String exportedNOf(int n, String cat) {
    return '已导出 $n 个$cat';
  }

  @override
  String get processing => '处理中…';

  @override
  String get importResult => '导入结果';

  @override
  String get dupImagesSkipped => '重复图自动跳过';

  @override
  String get embeddedPreviewsSkipped => '内嵌预览图不导入';

  @override
  String vibeImportFailed(String error) {
    return 'Vibe 导入失败: $error';
  }

  @override
  String charRefImportFailed(String name, String error) {
    return '角色参考「$name」失败: $error';
  }

  @override
  String inspirationImportFailed(String error) {
    return '灵感库导入失败: $error';
  }

  @override
  String presetImportFailed(String error) {
    return '预设导入失败: $error';
  }

  @override
  String get notValidBackup => '不是有效的备份文件';

  @override
  String get backupIdMismatch => '无效的备份文件:文件标识不匹配';

  @override
  String backupVersionUnsupported(String ver, String supported) {
    return '不支持的备份版本:$ver(本 app 支持 v$supported)';
  }

  @override
  String get backupIncomplete => '无效的备份文件:数据结构不完整';

  @override
  String get fileReadFailed => '文件读取失败';

  @override
  String get fileEmpty => '文件是空的';

  @override
  String get genCancelled => '已取消生成';

  @override
  String streamBadFrame(String len) {
    return '流数据格式异常(帧长 $len)';
  }

  @override
  String genFailedCode(String code) {
    return '生成失败(code $code)';
  }

  @override
  String noImageFrame(int bytes) {
    return '未收到图片帧(收到 $bytes 字节)';
  }

  @override
  String noImageFrameParse(int bytes, int fails, String err) {
    return '未收到图片帧(收到 $bytes 字节,$fails 帧解析失败:$err)';
  }

  @override
  String get genTimeout => '生成超时,请重试';

  @override
  String cantConnect(String host, String msg) {
    return '无法连接 $host:$msg';
  }

  @override
  String tlsFailed(String host) {
    return 'TLS 握手失败,当前网络可能拦截了 $host';
  }

  @override
  String streamGenFailed(String error) {
    return '流式生成失败:$error';
  }

  @override
  String unzipFailed(String error) {
    return '解压结果失败:$error';
  }

  @override
  String get noImageInResult => '结果中未找到图片';

  @override
  String get apiNoUpscale => '这个接口没有超分';

  @override
  String get apiNoAccountStatus => '这个接口不提供账户状态';

  @override
  String get apiNoVibe => '这个接口没有 Vibe 编码';

  @override
  String vibeEncodeFailed(String error) {
    return '编码参考图失败:$error';
  }

  @override
  String get http401 => 'Token 无效或已过期';

  @override
  String get http402 => '订阅 / 点数不足';

  @override
  String get http429 => '并发过多或触发限流,请稍后重试';

  @override
  String httpFailed(int code) {
    return '请求失败(HTTP $code)';
  }

  @override
  String get notJsonResponse => '接口返回的不是 JSON';

  @override
  String get noImageData => '未收到图片数据';

  @override
  String get helpCanvasTitle => '画布';

  @override
  String get helpCanvasBody =>
      '每张画布各存一套提示词和出图参数，随时切换。\n· 只有张数和循环档位是所有画布共用的\n💡 切换画布不影响进行中的出图\n💡「历史」保留最近 50 次出图，可恢复';

  @override
  String get helpResolutionTitle => '分辨率';

  @override
  String get helpResolutionBody =>
      '按总像素(宽 × 高)分档:\n· 免费 → ≤ 1024×1024,即绿线以内;需 Opus 订阅、步数 ≤28\n· 消耗点数 → 超出绿线,尺寸越大越贵\n· 超出上限 → 超过 1024×3072(红线),无法生成';

  @override
  String get helpImg2imgStrengthTitle => '图生图强度 (Strength)';

  @override
  String get helpImg2imgStrengthBody =>
      '控制原图对最终画面的影响程度。\n· 值越低 → 越接近原图，改动越少\n· 值越高 → 越自由发挥，重绘越多\n💡 0.01 时几乎不重绘；与 Noise 同时调到最低 → 完美复制原图\n💡 AI 过度忽略提示词时，可尝试提高 Prompt Guidance';

  @override
  String get helpImg2imgNoiseTitle => '噪声 (Noise)';

  @override
  String get helpImg2imgNoiseBody =>
      '在原图基础上额外注入随机扰动。\n· 0 → 完全基于原图，结果更稳定\n· 值越高 → 增加创作自由度，更多新元素\n💡 原图大面积空白时，调高可让 AI 主动补充细节\n💡 高 Noise 反复重生成可能产生视觉瑕疵';

  @override
  String get helpVibeStrengthTitle => '风格强度 (Reference Strength)';

  @override
  String get helpVibeStrengthBody =>
      '控制 Vibe 风格对画面的影响力度。\n· 值越高 → 越接近参考图的风格、配色等视觉线索\n· 值越低 → 仅作轻微风格指引\n💡 多个 Vibe 同时使用时，强度总和建议 ≤ 1\n💡 过高时 AI 会开始忽略文字 prompt';

  @override
  String get helpNormalizeVibeTitle => '均衡强度 (Normalize)';

  @override
  String get helpNormalizeVibeBody =>
      '开启 → 所有 Vibe 的强度按比例缩小，合计强度 ≤ 1\n关闭 → 每个 Vibe 的强度独立相加';

  @override
  String get helpInfoExtractedTitle => '信息提取 (Information Extracted)';

  @override
  String get helpInfoExtractedBody =>
      '从原图中提取的信息量。\n· 值越低 → 先丢失高频细节（纹理、风格），优先保留构图\n· 值越高 → 同时保留构图与纹理 / 风格细节\n💡 设置为新值时扣 2 点数，使用历史值时免费\n💡 无原图时无法重设该值';

  @override
  String get helpCharRefStrengthTitle => '参考强度 (Strength)';

  @override
  String get helpCharRefStrengthBody =>
      '控制角色 / 风格参考对画面的整体影响力。\n· 值越高 → 越严格还原参考图特征\n· 值越低 → 参考图仅作弱引导\n💡 每张图额外消耗 5 Anlas，多个 PR 累加\n💡 过高时面部表情 / 角度 / 姿势会过度贴近参考图';

  @override
  String get helpFidelityTitle => '还原度 (Fidelity)';

  @override
  String get helpFidelityBody =>
      '控制 prompt 能否压过参考图。\n· 值越高 → 参考图占主导，prompt 难以改变它\n· 值越低 → prompt 占主导，更易调整画面\n💡 实际效果可能因图而异，建议多尝试';

  @override
  String get helpStepsTitle => '采样步数 (Steps)';

  @override
  String get helpStepsBody =>
      '采样步数，控制去噪迭代次数。\n步数越高画面越精细，但生成越慢。\n步数过多反而收益递减，甚至适得其反。\n💡 步数 ≤28 时不额外消耗 Anlas';

  @override
  String get helpCfgTitle => '提示词引导强度 (CFG Scale)';

  @override
  String get helpCfgBody =>
      '控制 AI 对提示词的遵循程度。\n· 值越低 → AI 越自由发挥，画面更绘画感、柔和、梦幻\n· 值越高 → 越严格遵循描述，细节更精细锐利\n💡 V3 及以上模型官方推荐 5~6\n💡 过高反而会反作用，色彩过饱和、画面崩坏';

  @override
  String get helpVarietyPlusTitle => '多样性增强模式 (Variety+)';

  @override
  String get helpVarietyPlusBody =>
      '轻微调整采样过程，提升构图与姿势的多样性。\n开启 → 增加构图和姿势的变化\n关闭 → 出图更稳定一致\n💡 在低 Prompt Guidance 下效果更明显';

  @override
  String get helpSamplerTitle => '采样算法 (Sampler)';

  @override
  String get helpSamplerBody =>
      '决定去噪路径，影响画面风格与稳定性。\n· Euler Ancestral — 经典万能，随机性高\n· Euler — 确定性版本，构图更稳定\n· DPM++ 2S Ancestral — 细节丰富\n· DPM++ 2M SDE — 高质量 + 随机性\n· DPM++ 2M — 高质量确定性采样\n· DPM++ SDE — 兼具细节与多样性\n💡 建议保持默认或推荐 DPM++ 2M / Euler Ancestral\n💡 不同 sampler 的差异在低 Steps 时更明显';

  @override
  String get helpNoiseScheduleTitle => '噪声衰减曲线 (Noise Schedule)';

  @override
  String get helpNoiseScheduleBody =>
      '决定 Sampler 在每一步的噪声衰减节奏，影响画面质感。\n· karras — 最常用，出图稳定细节好\n· exponential — 指数衰减，对比度更强\n· polyexponential — 多项式衰减，过渡平滑\n💡建议保持默认 karras';

  @override
  String get helpSeedTitle => '随机种子 (Seed)';

  @override
  String get helpSeedBody =>
      '随机种子，决定初始噪声。\n相同种子 + 相同参数 → 基本一致的画面\n适合微调时锁定构图。\n留空 → 每次随机生成不同结果\n💡 sampler 本身有微小随机性，相同种子也可能存在细微差别\n💡 NAI / Anima / Krea 三者的 seed 互不通用，与外部 Stable Diffusion 也不通用';

  @override
  String get helpCfgRescaleTitle => 'CFG 引导修正系数 (Rescale)';

  @override
  String get helpCfgRescaleBody =>
      '抑制高引导值带来的过饱和与色彩溢出。\n0 = 不修正，值越高 → 修正越强\n通常保持 0；Guidance >7 时可尝试 0.1~0.3\n💡 画面出现「边缘色彩过强 / 油炸感 (deepfried)」时调高';

  @override
  String get allAlbumsName => '全部相册';

  @override
  String get trashName => '回收站';

  @override
  String get albumNameInvalid => '请输入 1–40 个字符的相册名称';

  @override
  String get albumNameExists => '这个相册名称已存在';

  @override
  String cantRenameFav(String name) {
    return '「$name」不能改名';
  }

  @override
  String cantDeleteFav(String name) {
    return '「$name」不能删除';
  }

  @override
  String cantBrowseFav(String name) {
    return '「$name」不能作为浏览相册';
  }

  @override
  String cantSaveFav(String name) {
    return '「$name」不能设为保存相册';
  }

  @override
  String get albumDeleted => '相册已被删除';

  @override
  String get imageWasDeleted => '图片已被删除';

  @override
  String get galleryGone => '图库已不存在，请重新选择';

  @override
  String get chooseDifferentAlbums => '请选择不同的来源和目标图库';

  @override
  String get albumsRestored => '相册数据已从最近一次备份恢复';

  @override
  String get albumsUnreadable => '相册归属数据暂时无法读取，原文件已保留；全部相册仍可查看';

  @override
  String get albumsReadOnly => '相册数据需要恢复，暂时不能修改';

  @override
  String get favorited => '已收藏';

  @override
  String get unfavoritedSnack => '已取消收藏';

  @override
  String get saveTo => '保存到';

  @override
  String get chooseAlbum => '选择相册';

  @override
  String get moveTo => '移动到';

  @override
  String get newAlbum => '新建相册';

  @override
  String get renameAlbum => '重命名相册';

  @override
  String get albumName => '相册名称';

  @override
  String get setAsSaveAlbum => '设为保存相册';

  @override
  String get dateLabel => '日期';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get earlier => '更早';

  @override
  String get last7Days => '近 7 天';

  @override
  String get last30Days => '近 30 天';

  @override
  String dayMonthDay(String month, int day) {
    return '$month月$day日';
  }

  @override
  String dayYearMonthDay(int year, String month, int day) {
    return '$year年$month月$day日';
  }

  @override
  String get groupByTime => '按时间';

  @override
  String get groupByCharacter => '按角色';

  @override
  String get groupByStyle => '按画风';

  @override
  String get ungrouped => '未归类';

  @override
  String get hintSaveLongPress => '长按「保存」可进入下载设置';

  @override
  String get hintStripSwipe => '底部胶片条里的图,向上滑可以分享、收藏或删除';

  @override
  String get nothingToShare => '没有可分享的图片';

  @override
  String get backToHistory => '返回历史';

  @override
  String savedToNamed(String name) {
    return '已保存到 $name';
  }

  @override
  String get browseAlbums => '浏览相册';

  @override
  String get movedToTrash => '已移到回收站';

  @override
  String get albumEmpty => '这个相册还没有照片';

  @override
  String get noWorksYet => '还没有作品';

  @override
  String get viewTrash => '查看回收站';

  @override
  String get goCreateFirst => '去「创作」生成第一张';

  @override
  String get savedAllAlbumFailed => '图片已保存在全部作品，目标图库不可用或归类失败';

  @override
  String get deletedAlbumCleanupFailed => '图片已删除，图库归属清理失败';

  @override
  String get upscaleV5 => 'V5 超分';

  @override
  String get redrawUpscale => '重绘放大';

  @override
  String get encodingImage => '编码图片…';

  @override
  String get uploadingNai => '上传 NAI…';

  @override
  String get noPaidToken => '没有可用于付费操作的 NAI Token';

  @override
  String get receivingResult => '接收结果…';

  @override
  String get saveToPhoneAlbum => '保存到手机相册';

  @override
  String saveToPhoneAlbumBody(int n, String album) {
    return '$n 张将存入系统相册的「$album」;相册不存在会自动创建。';
  }

  @override
  String get albumNameExample => '如 Plana 精选';

  @override
  String get dropToDelete => '拖到这里删除';

  @override
  String get releaseToDelete => '松手删除';

  @override
  String get dropToUnfav => '拖到这里取消收藏';

  @override
  String get dropToFav => '拖到这里收藏';

  @override
  String get releaseToUnfav => '松手取消收藏';

  @override
  String get releaseToFav => '松手收藏';

  @override
  String get dropToShare => '拖到这里分享';

  @override
  String get releaseToShare => '松手分享';

  @override
  String get selectDate => '选择日期';

  @override
  String get applyLabel => '应用';

  @override
  String get dateFieldHint => '年/月/日';

  @override
  String get filterByDate => '按日期筛选';

  @override
  String get reset => '重置';

  @override
  String get specificDate => '指定日期';

  @override
  String get pickADay => '选择某一天';

  @override
  String get dateRange => '日期范围';

  @override
  String dateRangeValue(String start, String end) {
    return '$start 至 $end';
  }

  @override
  String get pickStartEnd => '选择开始与结束日期';

  @override
  String get hintLongPressPreview => '点开「全部相册」后，长按图片可预览并导入 / 保存 / 删除';

  @override
  String get restoreAll => '全部恢复';

  @override
  String get emptyTrash => '清空回收站';

  @override
  String get deleteAlbum => '删除相册';

  @override
  String get reorderAlbums => '排序';

  @override
  String restoredN(int n) {
    return '已恢复 $n 张';
  }

  @override
  String get emptyTrashQ => '清空回收站?';

  @override
  String deletedForeverN(int n) {
    return '已彻底删除 $n 张';
  }

  @override
  String deleteAlbumQ(String name) {
    return '删除「$name」？';
  }

  @override
  String get deleteAlbumBody => '只删除相册，图片仍保留在全部相册。';

  @override
  String newImagesSaveTo(String name) {
    return '新图将保存到「$name」';
  }

  @override
  String get backToTop => '回到顶部';

  @override
  String get filterByModel => '按模型筛选';

  @override
  String get unknown => '未知';

  @override
  String get groupMode => '分组方式';

  @override
  String savingProgress(int done, int total) {
    return '保存中 $done/$total';
  }

  @override
  String get zipping => '打包中';

  @override
  String get packZip => '打包 ZIP';

  @override
  String restoreN(int n) {
    return '恢复 ($n)';
  }

  @override
  String deleteForeverN(int n) {
    return '彻底删除 ($n)';
  }

  @override
  String get photosAlbum => '相册';

  @override
  String quotedName(String name) {
    return '「$name」';
  }

  @override
  String savedNTo(int n, String where) {
    return '已保存 $n 张到$where';
  }

  @override
  String savedNToFailed(int n, String where, int failed) {
    return '保存 $n 张到$where,失败 $failed 张';
  }

  @override
  String get albumsNoImages => '所选相册里还没有图片';

  @override
  String savedAlbumsN(int albums, int n) {
    return '已保存 $albums 个相册,共 $n 张';
  }

  @override
  String savedNFailed(int n, int failed) {
    return '保存 $n 张,失败 $failed 张';
  }

  @override
  String deleteNAlbumsQ(int n) {
    return '删除 $n 个相册？';
  }

  @override
  String deletedNAlbums(int n) {
    return '已删除 $n 个相册';
  }

  @override
  String get packFailed => '打包失败';

  @override
  String packedN(int n) {
    return '已打包 $n 张';
  }

  @override
  String packedNFailed(int n, int failed) {
    return '已打包 $n 张,失败 $failed 张';
  }

  @override
  String saveFailedWith(String error) {
    return '保存失败:$error';
  }

  @override
  String get restore => '恢复';

  @override
  String get deleteForever => '彻底删除';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get favoriteAction => '收藏';

  @override
  String get removeCover => '取消封面';

  @override
  String get setAsCover => '设为封面';

  @override
  String get restored => '已恢复';

  @override
  String get deleteForeverQ => '彻底删除这张作品?';

  @override
  String get deletedForever => '已彻底删除';

  @override
  String coverRemoved(String name) {
    return '已取消「$name」的封面';
  }

  @override
  String coverSet(String name) {
    return '已设为「$name」的封面';
  }

  @override
  String get imageNotReady => '图片尚未就绪';

  @override
  String unreadableSkipped(int n) {
    return '$n 张读不出来,已跳过';
  }

  @override
  String movedNToTrash(int n) {
    return '已将 $n 张移到回收站';
  }

  @override
  String deleteNForeverQ(int n) {
    return '彻底删除 $n 张作品?';
  }

  @override
  String get cantUndo => '删除后无法恢复。';

  @override
  String deleteNImagesQ(int n) {
    return '删除 $n 张作品?';
  }

  @override
  String alreadyInAlbum(String name) {
    return '图片已在「$name」';
  }

  @override
  String movedNTo(int n, String name) {
    return '已移动 $n 张到「$name」';
  }

  @override
  String deletesInDays(int n) {
    return '$n 天后删除';
  }

  @override
  String selectedNAlbums(int n) {
    return '已选 $n 个相册';
  }

  @override
  String selectedNImages(int n) {
    return '已选 $n 张';
  }

  @override
  String get selectNone => '全不选';

  @override
  String get done => '完成';

  @override
  String get backToAll => '回到全部';

  @override
  String get backToAlbums => '回到相册';

  @override
  String nAlbums(int n) {
    return '$n 个相册';
  }

  @override
  String filteredOfTotal(int n, int total) {
    return '$n/$total 张';
  }

  @override
  String get multiSelect => '多选';

  @override
  String get searchPromptTags => '搜索提示词标签';

  @override
  String get searchPromptTagsHint => '搜索提示词标签…';

  @override
  String indexingProgress(int done, int total) {
    return '索引 $done/$total';
  }

  @override
  String get grouping => '分组中';

  @override
  String get noMatchingWorks => '没有符合条件的作品';

  @override
  String get trashEmpty => '回收站是空的';

  @override
  String get galleryEmpty => '图库是空的';

  @override
  String get albumNoImages => '这个相册还没有图片';

  @override
  String saveN(int n) {
    return '保存 ($n)';
  }

  @override
  String deleteN(int n) {
    return '删除 ($n)';
  }

  @override
  String preparingProgress(int done, int total) {
    return '准备 $done/$total';
  }

  @override
  String get share => '分享';

  @override
  String get customAlbum => '自定义相册';

  @override
  String get finishing => '收尾中';

  @override
  String get preparing => '准备中';

  @override
  String get upscale => '放大';

  @override
  String get savedLabel => '已保存';

  @override
  String get compare => '对比';

  @override
  String get regenerate => '重新生成';

  @override
  String get inpaintInProgress => '重绘进行中,请稍候';

  @override
  String get noPixelData => '此图无像素数据';

  @override
  String get redrawNoSnapshot => '这张图没有参数快照,重绘放大用不了(只有本机生成的图带快照)';

  @override
  String redrawModelUnsupported(String model) {
    return '$model 不支持图生图,重绘放大要先切回 NAI 模型';
  }

  @override
  String redrawTooLarge(int w, int h) {
    return '源图 $w×$h 已超过 NAI 的总像素上限,重绘放不出任何倍率';
  }

  @override
  String get preparingEllipsis => '准备…';

  @override
  String upscaleDone(String method, int w, int h) {
    return '$method完成 $w×$h,已存入图库';
  }

  @override
  String upscaleFailed(String error) {
    return '超分失败: $error';
  }

  @override
  String get redrawNoSnapshotShort => '缺少参数快照,无法重绘放大';

  @override
  String redrawStartMax(int w, int h, String model) {
    return '开始 Max 重绘 ≈$w×$h · $model';
  }

  @override
  String upscaleStart(int w, int h) {
    return '开始 V5 超分 $w×$h';
  }

  @override
  String get addToCreate => '存入创作页';

  @override
  String get savedToImg2ImgUpscale => '已存入图生图放大';

  @override
  String redrawStart(String scale, int w, int h, String model) {
    return '开始 $scale 重绘 $w×$h · $model';
  }

  @override
  String get savedToPhotos1 => '已保存到相册';

  @override
  String get saveFailed => '保存失败';

  @override
  String saveFailedSpace(String error) {
    return '保存失败: $error';
  }

  @override
  String get regenNoSnapshot => '缺少参数快照,无法重新生成';

  @override
  String saveToNamed(String name) {
    return '保存到 $name';
  }

  @override
  String get cantReadImage => '无法读取这张图片';

  @override
  String upscaleNote(int price) {
    return 'V5 扩散超分 · 固定 2× · $price 点';
  }

  @override
  String upscaleTooLarge(int w, int h) {
    return '源图 $w×$h 超过 3,145,728 像素,超分不受理';
  }

  @override
  String get scaleNoteX1 => '同尺寸重新生成,只精修细节、不放大';

  @override
  String get scaleNoteMax => '发原图尺寸,由 NovelAI 放到最大后重绘';

  @override
  String scaleNoteScale(String scale) {
    return '以 $scale 分辨率重新生成,画面会变';
  }

  @override
  String maxOnlyV5(String model) {
    return 'Max 档只有 V5 有;当前模型是 $model,重绘也按它跑';
  }

  @override
  String maxTooLarge(int w, int h) {
    return 'Max 档要求源图小于 2,516,582 像素,这张 $w×$h 太大了';
  }

  @override
  String get upscaleResolution => '超分辨率';

  @override
  String get img2imgUpscale => '图生图放大';

  @override
  String get scaleLabel => '倍率';

  @override
  String get magnitudeLabel => '档位';

  @override
  String magnitudeN(String n) {
    return '档 $n';
  }

  @override
  String get strengthStrength => '强度 Strength';

  @override
  String get noiseNoise => '噪声 Noise';

  @override
  String get startUpscale => '开始放大';

  @override
  String savedToPhotosSize(String size) {
    return '已保存到相册 · $size';
  }

  @override
  String get setAsDefaultSave => '已设为默认保存方式';

  @override
  String estimatedSize(String size) {
    return '预估大小 $size';
  }

  @override
  String get calculating => '计算中…';

  @override
  String get jpgNoParams => 'JPG 不保留生成参数';

  @override
  String get keepOriginalMeta => '保留原始元数据';

  @override
  String get clearGenInfo => '清除生成信息';

  @override
  String get saveOnce => '单次保存';

  @override
  String get setAsDefault => '设为默认';

  @override
  String get newImagesSaveHere => '新图保存到这里';

  @override
  String get zipName => '压缩包名称';

  @override
  String get zipPassword => '压缩密码(可选)';

  @override
  String get stopping => '正在停下';

  @override
  String get pack => '打包';

  @override
  String get selectDateRange => '选择日期范围';

  @override
  String get backToCalendar => '返回日历';

  @override
  String get startDate => '开始日期';

  @override
  String get endDate => '结束日期';

  @override
  String get dragToAdjustDate => '可直接拖动调整日期';

  @override
  String get zipTooLarge => '包太大,超出 zip 的表示范围';

  @override
  String get zipInterrupted => '打包中断';

  @override
  String get enterNameFirst => '先填写名称';

  @override
  String get enterPromptFirst => '先填写提示词';

  @override
  String deleteNamedQ(String name) {
    return '删除「$name」?';
  }

  @override
  String get localOnlyDeleteBody => '仅删除本地条目,不可恢复。';

  @override
  String get deletedLabel => '已删除';

  @override
  String get numbersExhausted => '编号已用尽';

  @override
  String get importCharPrompt => '导入角色提示词';

  @override
  String get importMainPrompt => '导入主提示词';

  @override
  String get galleryNoImages => '图库还没有图片';

  @override
  String get pickFromGallery => '从图库选取';

  @override
  String totalImagesN(int n) {
    return '共 $n 张';
  }

  @override
  String get readImageFailed => '读取图片失败';

  @override
  String get enterPositiveFirst => '先填写正向提示词';

  @override
  String editInCat(String cat) {
    return '编辑$cat';
  }

  @override
  String newInCat(String cat) {
    return '新建$cat';
  }

  @override
  String get aliasLabel => '别名';

  @override
  String get enterAlias => '输入别名…';

  @override
  String get numberLabel => '编号';

  @override
  String get upload => '上传';

  @override
  String get generating => '生成中';

  @override
  String get exampleArtists => '例如: wlop, rurudo';

  @override
  String get negativePromptAlt => '负面提示词';

  @override
  String get exampleNegative => '例如: bad anatomy, worst quality';

  @override
  String get applicableModels => '适用模型';

  @override
  String get recommendedParams => '推荐参数';

  @override
  String get importToCreatePage => '导入创作页';

  @override
  String get tapToUpload => '点击上传';

  @override
  String get modelsNoneMeansAll => '一个都不选 = 通用,在所有模型下都会出现';

  @override
  String selectedNCount(int n) {
    return '已选 $n 个';
  }

  @override
  String get unknownModelOtherVersion => '未知模型(来自其它版本)';

  @override
  String get useCurrent => '换成当前';

  @override
  String get saveLocal => '保存到本地';

  @override
  String get saveAndPublish => '保存并发布';

  @override
  String get saveChanges => '保存修改';

  @override
  String get saveTagChanges => '保存标签修改';

  @override
  String get storeIn => '存到';

  @override
  String maxSelectN(int n) {
    return '最多选 $n 个';
  }

  @override
  String charsFullN(int n) {
    return '角色已满 $n 个';
  }

  @override
  String addedCharsTruncated(int added, int cap) {
    return '已加入 $added 个角色(超出 $cap 个截断)';
  }

  @override
  String addedChars(int n) {
    return '已加入 $n 个角色';
  }

  @override
  String get addedToPrompt => '已加入提示词';

  @override
  String taggedN(int n, String tag) {
    return '已给 $n 项加上「$tag」';
  }

  @override
  String deleteNItemsQ(int n) {
    return '删除 $n 项?';
  }

  @override
  String localOnlyNLine(int n) {
    return '· 本地的 $n 项:仅删除本地';
  }

  @override
  String get cantUndoShort => '不可恢复。';

  @override
  String deletedNFailed(int done, int failed) {
    return '已删除 $done 项,$failed 项失败';
  }

  @override
  String deletedNItems(int n) {
    return '已删除 $n 项';
  }

  @override
  String addN(int n) {
    return '添加 ($n)';
  }

  @override
  String get filter => '筛选';

  @override
  String noMatchingInCat(String cat) {
    return '没有匹配的$cat';
  }

  @override
  String noneYetInCat(String cat) {
    return '还没有$cat';
  }

  @override
  String myInCat(String cat) {
    return '我的$cat';
  }

  @override
  String savedInCat(String cat) {
    return '收藏的$cat';
  }

  @override
  String get publicLibUnavailable => '公共库暂未开放';

  @override
  String get viewPrompt => '查看提示词';

  @override
  String get copyPrompt => '复制提示词';

  @override
  String get promptCopied => '已复制提示词';

  @override
  String get catCharacter => '角色';

  @override
  String get catStyle => '画风';

  @override
  String get catScene => '场景';

  @override
  String get catOther => '其他';

  @override
  String get searchCharHint => '搜索角色 / 别名…';

  @override
  String get searchStyleHint => '搜索名称 / 提示词 / 标签…';

  @override
  String get searchSceneHint => '搜索场景…';

  @override
  String get searchNamePromptHint => '搜索名称 / 提示词…';

  @override
  String get layoutPortrait => '竖图';

  @override
  String get layoutLandscape => '横图';

  @override
  String get layoutSquare => '方图';

  @override
  String get layoutNoImage => '无图';

  @override
  String get sortNumber => '编号';

  @override
  String get sortLatest => '最新';

  @override
  String get sortAuthor => '作者';

  @override
  String get notTagBackup => '不是 Tag 管理器的备份文件';

  @override
  String get backupCatUnknown => '备份文件的分类无法识别';

  @override
  String get noPreviewForCat => '该分类不支持生成预览';

  @override
  String get copySuffix => '(副本)';

  @override
  String get codexTypeDict => '词典';

  @override
  String get codexTypeComposition => '构图';

  @override
  String get codexTypePack => '合集';

  @override
  String codexNotFound(String id) {
    return '未找到法典:$id';
  }

  @override
  String get codexBadImageHost => '图床配置格式异常';

  @override
  String get codexBadIndex => '法典索引格式异常';

  @override
  String get codexBadData => '法典数据格式异常';

  @override
  String get codexOriginalImage => '法典原图';

  @override
  String get originalNotDownloaded => '原图没下下来,检查下网络';

  @override
  String get shuffleAnother => '换一个';

  @override
  String addedToPromptCharsDropped(int added, int dropped) {
    return '已加入提示词 · $added 个角色(另 $dropped 个超出上限)';
  }

  @override
  String addedToPromptChars(int added) {
    return '已加入提示词 · $added 个角色';
  }

  @override
  String get goCreate => '去创作';

  @override
  String get addToPrompt => '加入提示词';

  @override
  String favoritesFull(int n) {
    return '收藏已满($n 条),先去收藏夹清一些';
  }

  @override
  String get random => '随机';

  @override
  String get tapToFlip => '点击翻转查看提示词';

  @override
  String charNNegative(int n) {
    return '角色 $n · 负向';
  }

  @override
  String get selectCodex => '选择法典';

  @override
  String get clearFavorites => '清空收藏';

  @override
  String clearFavoritesBody(int n) {
    return '将移除全部 $n 条收藏,不可恢复。法典词条本身不受影响。';
  }

  @override
  String get noFavoritesYet => '还没有收藏';

  @override
  String get favoriteHowTo => '点开任意词条,左下角那颗星即可收藏';

  @override
  String allIn(String name) {
    return '全部「$name」';
  }

  @override
  String get unblock => '解除屏蔽';

  @override
  String get block => '屏蔽';

  @override
  String get unblockAll => '全部解除';

  @override
  String get upLevel => '上一级';

  @override
  String get categories => '分类';

  @override
  String get author => '作者';

  @override
  String get contributors => '贡献者';

  @override
  String get codexCopyright => '内容与例图版权归各法典作者所有,本页仅作可视化索引。';

  @override
  String get codexSiteLink => '法典图鉴 · 原站';

  @override
  String get codexIndexFailed => '法典索引加载失败';

  @override
  String get noCodex => '暂无法典';

  @override
  String get codexAbout =>
      '词条与例图数据来自\nhttps://novelai.quicktagcloud.com/\n\n本应用仅作展示与检索,内容版权归各法典作者所有。\n\n感谢所有法典作者与贡献者的整理分享。';

  @override
  String get sourcesThanks => '来源与致谢';

  @override
  String get gotIt => '我知道了';

  @override
  String loadingEntries(int n) {
    return '正在载入 $n 条词条…';
  }

  @override
  String get codexLoadFailed => '法典加载失败';

  @override
  String get noMatchingEntries => '没有匹配的词条';

  @override
  String get noEntries => '暂无词条';

  @override
  String get searchTitlePromptHint => '搜索标题 / 提示词…';

  @override
  String get allCategories => '全部分类';

  @override
  String get nothingToDraw => '当前没有可抽的词条';

  @override
  String get retry => '重试';

  @override
  String get categoryLabel => '类别';

  @override
  String get newCategory => '新建类别';

  @override
  String get renameShort => '改名';

  @override
  String get categoryExists => '已有同名类别';

  @override
  String get categoryEmpty => '这个类别还没有条目。';

  @override
  String categoryDeleteN(int n) {
    return '类别里的 $n 个条目会一起删除,不可恢复。';
  }

  @override
  String categoryReAdd(String name) {
    return '之后新建一个叫「$name」的类别,可以把它加回来。';
  }

  @override
  String get editCategory => '编辑类别';

  @override
  String get categoryName => '类别名称';

  @override
  String get icon => '图标';

  @override
  String get previewImage => '预览图';

  @override
  String get create => '创建';

  @override
  String get manageCategories => '类别管理';

  @override
  String addLibN(int n) {
    return '加入 ($n)';
  }

  @override
  String addCharsN(int n) {
    return '加入角色 ($n)';
  }

  @override
  String get scopeMine => '我的';

  @override
  String scopeMineN(int n) {
    return '我的 · $n';
  }

  @override
  String scopePublicShortN(int n) {
    return '公共 $n';
  }

  @override
  String get scopePublicShort => '公共';

  @override
  String scopePublicN(int n) {
    return '公共库 · $n';
  }

  @override
  String get manageTagPool => '标签池管理';

  @override
  String get sort => '排序';

  @override
  String get nicknameOrQq => '昵称或 QQ 号';

  @override
  String get noSignedEntries => '库里还没有署名的条目';

  @override
  String get noMatchingAuthors => '没有匹配的作者';

  @override
  String get genericModel => '通用';

  @override
  String genericUnlabeled(String label) {
    return '$label(没标注的)';
  }

  @override
  String authorNamed(String name) {
    return '作者 $name';
  }

  @override
  String get positiveLabel => '正向';

  @override
  String get negativeLabel => '负面';

  @override
  String get tagExistsShort => '标签已存在';

  @override
  String catTagPool(String cat) {
    return '$cat标签池';
  }

  @override
  String get newTagEllipsis => '新建标签…';

  @override
  String get noTags => '暂无标签';

  @override
  String deleteTagQ(String tag) {
    return '删除标签「$tag」?';
  }

  @override
  String deleteTagEntriesBody(int n) {
    return '$n 个条目会摘掉该标签,条目本身保留。';
  }

  @override
  String get addTag => '添加标签';

  @override
  String get use => '使用';

  @override
  String charRangeLabel(String n) {
    return '角色 $n';
  }

  @override
  String imagesScopeSuffix(String scope) {
    return '张 · $scope生图';
  }

  @override
  String costPts(String n) {
    return '消耗 $n 点';
  }

  @override
  String selectedLabel(String name) {
    return '已选 $name';
  }

  @override
  String get peakSlot => '最高时段';

  @override
  String get peakDay => '最高单日';

  @override
  String get unitTxns => '笔';

  @override
  String get genDetails => '生成详情';

  @override
  String get pointsDetails => '点数详情';

  @override
  String get activeSlots => '活跃时段';

  @override
  String get activeDays => '活跃天数';

  @override
  String get avgPerSlot => '段均生图';

  @override
  String get avgPerDay => '日均生图';

  @override
  String get v5Gens => 'V5 生图';

  @override
  String get v5Anlas => 'V5 点数';

  @override
  String get estimatedSpend => '估算消耗';

  @override
  String get vsPrevSlot => '较上一时段';

  @override
  String get vsPrevDay => '较上一日';

  @override
  String get unchanged => '持平';

  @override
  String todayRange(String from, String to) {
    return '今天 $from–$to';
  }

  @override
  String todayHour(String h) {
    return '今天 $h:00';
  }

  @override
  String get dataSource => '数据源';

  @override
  String get directKey => '直连 Key';

  @override
  String get botAuth => 'Bot 授权';

  @override
  String get rangeToday => '今日';

  @override
  String get rangeWeek => '本周';

  @override
  String get rangeMonth => '本月';

  @override
  String minusPts(String n) {
    return '-$n 点';
  }

  @override
  String genSize(int w, int h) {
    return '生图 $w×$h';
  }

  @override
  String get upscale4x => '超分 4x';

  @override
  String get vibeEncoding => 'Vibe 编码';

  @override
  String get dayGens => '当日生图';

  @override
  String freeN(int n) {
    return '免费 $n';
  }

  @override
  String get perItemSpend => '逐笔消耗';

  @override
  String get perItemGens => '逐笔生成';

  @override
  String get detailsRolledOff => '该日明细已超出保留窗口,仅剩汇总';

  @override
  String get noRecordsDay => '该日无记录';

  @override
  String get noData => '暂无数据';

  @override
  String get modeNone => '无';

  @override
  String get modeComic => '漫画模式';

  @override
  String get modeNatural => '仅自然语言';

  @override
  String get toolCharLib => '角色库';

  @override
  String get toolStyleLib => '画风库';

  @override
  String get toolTagWiki => 'Tag 百科';

  @override
  String get toolSafeMode => '安全模式';

  @override
  String get toolOcLib => 'OC 库';

  @override
  String get assistantTools => '工具';

  @override
  String get assistantToolsDesc => 'AI 查资料时能用的工具';

  @override
  String toolsEnabledN(int n) {
    return '$n 个已开';
  }

  @override
  String get imageModelField => '出图模型';

  @override
  String get drawingImage => '出图中';

  @override
  String get imagePromptEmpty => '说一句要画什么或者怎么改';

  @override
  String get aspectLabel => '比例';

  @override
  String resolutionChip(String v) {
    return '分辨率 $v';
  }

  @override
  String aspectChip(String v) {
    return '比例 $v';
  }

  @override
  String get imageAuto => '自动';

  @override
  String get quoteImage => '引用';

  @override
  String imagesMax(int n) {
    return '最多带 $n 张图';
  }

  @override
  String get imageGenNoModel => '这个图像模型现在用不了';

  @override
  String get imageGenNoImage => '没有出图';

  @override
  String get toolSearchArtist => '使用画风库';

  @override
  String get toolSearchOc => '使用角色库';

  @override
  String get toolSearchCharacter => '搜索角色';

  @override
  String get toolLookupTag => '搜索 tag';

  @override
  String randomN(int n) {
    return '随机 $n 个';
  }

  @override
  String lookedUpN(int n) {
    return '查了 $n 处资料';
  }

  @override
  String get untitledChat => '未命名对话';

  @override
  String get thinkOff => '关闭';

  @override
  String get thinkAuto => '自动';

  @override
  String get thinkLow => '低';

  @override
  String get thinkMedium => '中等';

  @override
  String get thinkHigh => '高';

  @override
  String get thinkUltra => '超高';

  @override
  String get importReplaceMain => '替换主体';

  @override
  String get importClearSections => '清空分区';

  @override
  String get assistantNoModal => 'AI 助手暂不支持 Anima / Krea,去创作页换成 NAI 再来';

  @override
  String get builtinModelUnavailable => '内置模型暂未开放,先在顶部选一个自定义接口';

  @override
  String get thinking => '思考中';

  @override
  String get lookingUp => '查资料中';

  @override
  String get turnInterrupted => 'AI 这轮没跑完就断了,再试一次';

  @override
  String get replyDoneFallback => '改好了喵~';

  @override
  String get replyEmptyFallback => '这轮没什么可说的喵…';

  @override
  String get epNoModels => '拿到了,但一个模型都没有';

  @override
  String get modelEmptyReply => '模型回了一段空的';

  @override
  String get backendUnset => '未配置后端地址';

  @override
  String noDataIn(String secs) {
    return '$secs 秒内没有收到数据';
  }

  @override
  String get channelEndedEarly => '连接在收到结果前结束了';

  @override
  String modelBadDraw(String count) {
    return '出图块重写 $count 次仍不对,模型最后一次的原文:';
  }

  @override
  String assistantRefused(String count, String keyword) {
    return '模型拒绝了这次请求(重试 $count 次仍命中「$keyword」)';
  }

  @override
  String modelNoReplyIn(String secs) {
    return '模型 $secs 秒内没有回复';
  }

  @override
  String get thinkNoOffFormat => '该格式没有「关闭」档,按最低档发送';

  @override
  String get thinkNoUltraFormat => '该格式没有「超高」档,按「高」发送';

  @override
  String get thinkNoOffModel => '该模型不能关闭思考,按「低」发送';

  @override
  String get thinkNoUltraModel => '该模型没有「超高」档,按「高」发送';

  @override
  String get replyUnreadable => '接口有响应,但没读出回复内容,检查格式是否选对';

  @override
  String get suggest1 => '画一个白发红瞳的猫娘,站在樱花树下';

  @override
  String get suggest2 => '帮我抽一个好看的画风';

  @override
  String get suggest3 => '随机画一个蔚蓝档案的角色';

  @override
  String get suggest4 => '看看我现在这串 tag 有什么问题';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get selectModel => '选择模型';

  @override
  String get assistantSettings => '助手设置';

  @override
  String get chatHistory => '历史会话';

  @override
  String get newChat => '新对话';

  @override
  String get askAnything => '想画什么,直接说';

  @override
  String get copyContent => '复制内容';

  @override
  String get editMessage => '编辑该消息';

  @override
  String get regenerateFromHere => '从这里重新生成';

  @override
  String get cancelSend => '取消发送';

  @override
  String get discardAfterQ => '丢掉之后的对话?';

  @override
  String get discardAfterBody => '这条之后的对话都会丢掉,已经写进创作页的改动不受影响。';

  @override
  String get discard => '丢掉';

  @override
  String get createPageShort => '创作页';

  @override
  String get quoteCreatePage => '引用创作页';

  @override
  String get createPageEmpty => '创作页还没写提示词,没东西可引用';

  @override
  String get modeLabel => '模式';

  @override
  String rulesNoMode(String mode) {
    return '当前规则预设不支持「$mode」';
  }

  @override
  String thinkChip(String level) {
    return '思考 $level';
  }

  @override
  String get attachImage => '带图';

  @override
  String get systemAlbum => '系统相册';

  @override
  String get inputHint => '想画什么、想改哪里…';

  @override
  String get stop => '停止';

  @override
  String get send => '发送';

  @override
  String get assistantModelUnsupported => 'AI 助手暂不支持这个模型';

  @override
  String get assistantModelUnsupportedBody =>
      'Anima 与 Krea 的提示词体系和 NAI 是两套。\n去创作页换成 NAI 4.5 或 5 再来。';

  @override
  String get goChangeModel => '去换模型';

  @override
  String get pickEndpointFirst => '还没有可用的模型';

  @override
  String get builtinUnavailableBody => '先添加一个自己的模型接口';

  @override
  String get selectEndpoint => '选择模型接口';

  @override
  String get queued => '排队中';

  @override
  String get quotedCreatePage => '引用了创作页';

  @override
  String durSecs(int s) {
    return '$s 秒';
  }

  @override
  String durMinSecs(int m, String s) {
    return '$m 分 $s 秒';
  }

  @override
  String get discardChangesQ => '放弃修改?';

  @override
  String get unsavedLost => '没保存的改动会丢掉。';

  @override
  String get unsavedLost2 => '还没保存的改动会丢掉。';

  @override
  String get discardAction => '放弃';

  @override
  String savedNamed(String name) {
    return '已保存「$name」';
  }

  @override
  String get deleteEndpointQ => '删除这个接口?';

  @override
  String get deleteEndpointBody => '地址和 API Key 都会从本机删除。已经发生过的对话不受影响。';

  @override
  String get myEndpoints => '我的接口';

  @override
  String get addEndpoint => '添加接口';

  @override
  String get notComplete => '还没填全';

  @override
  String formatOf(String format) {
    return '$format 格式';
  }

  @override
  String get inUse => '使用中';

  @override
  String get pickServiceOrUrl => '先选服务或填接口地址';

  @override
  String get urlMustHttp => '接口地址要以 http:// 或 https:// 开头';

  @override
  String get noApiKeyYet => '还没填 API Key';

  @override
  String get noModelYet => '还没添加模型';

  @override
  String headerLineBad(int n) {
    return '请求头第 $n 行要写成「名称: 值」,只能用英文字符';
  }

  @override
  String linkCopied(String url) {
    return '已复制链接:$url';
  }

  @override
  String modelConnOk(String model, String secs) {
    return '$model 连接正常 · $secs 秒';
  }

  @override
  String connOk(String secs) {
    return '连接正常 · $secs 秒';
  }

  @override
  String get formatField => '格式';

  @override
  String get urlField => '地址';

  @override
  String get getKey => '获取 Key';

  @override
  String get modelField => '模型';

  @override
  String get modelIdHint => '模型 ID';

  @override
  String get addAnotherModel => '再加一个模型';

  @override
  String get modelList => '模型列表';

  @override
  String get pathField => '路径';

  @override
  String get headersField => '请求头';

  @override
  String get headersHint => '一行一条,如 X-Title: Plana';

  @override
  String headersN(int n) {
    return '请求头 $n';
  }

  @override
  String get test => '测试';

  @override
  String searchNModels(int n) {
    return '搜索 $n 个模型';
  }

  @override
  String doneSelectedN(int n) {
    return '完成 · 已选 $n 个';
  }

  @override
  String get rulePresets => '规则预设';

  @override
  String sectionsN(int n) {
    return '$n 段';
  }

  @override
  String get notUtf8 => '读不了这个文件,请确认是 UTF-8 文本';

  @override
  String importedNamed(String name) {
    return '已导入「$name」';
  }

  @override
  String savedAsNamed(String name) {
    return '已另存为「$name」';
  }

  @override
  String exportedNamed(String name) {
    return '已导出「$name」';
  }

  @override
  String get deletePresetQ => '删除预设?';

  @override
  String deleteRulePresetBody(String name) {
    return '「$name」将被删除,正在使用它的模型改用默认规则。';
  }

  @override
  String get listSep => '、';

  @override
  String get importRulePreset => '导入规则预设';

  @override
  String totalSectionsN(int n) {
    return '共 $n 段';
  }

  @override
  String get hasConditional => '含条件段';

  @override
  String get ruleSecRole => '角色定义';

  @override
  String get ruleSecModelTraits => '模型特性';

  @override
  String get ruleSecPromptConstruction => '提示词构建';

  @override
  String get ruleSecNaturalConstruction => '纯自然语言构建';

  @override
  String get ruleSecWeightControl => '权重控制';

  @override
  String get ruleSecCharacters => '角色处理';

  @override
  String get ruleSecMultiCharacter => '多角色绘图';

  @override
  String get ruleSecComic => '漫画 / 分镜';

  @override
  String get ruleSecCustomTags => '自定义标签';

  @override
  String get ruleSecTextRendering => '画面文字';

  @override
  String get ruleSecAlpha => '透明通道';

  @override
  String get ruleSecOutput => '绘图输出';

  @override
  String get ruleSecModeComic => '当前模式：漫画';

  @override
  String get ruleSecModeNatural => '当前模式：仅自然语言';

  @override
  String get enabledModels => '启用的模型';

  @override
  String get notEnabled => '未启用';

  @override
  String get duplicatePreset => '创建副本';

  @override
  String get ruleSectionsLabel => '段落';

  @override
  String whenOffTag(String mode) {
    return '$mode时不发';
  }

  @override
  String charsN(int n) {
    return '$n 字';
  }

  @override
  String get fullTextEdit => '全文编辑';

  @override
  String get addRuleSection => '添加一段';

  @override
  String get ruleSectionName => '标题名称';

  @override
  String get deleteRuleSectionQ => '删除这一段?';

  @override
  String deleteRuleSectionBody(String name) {
    return '「$name」的内容会一起删掉。';
  }

  @override
  String get ruleSectionEmpty => '内容不能为空';

  @override
  String get ruleSectionNameReserved => '这个段名留给工具层,换一个';

  @override
  String get supportedModels => '支持的模型';

  @override
  String get missingPresetName => '缺少预设名称(name)';

  @override
  String get missingModels => '缺少支持的模型(models 写 nai45、nai5)';

  @override
  String rulesTooManySections(int n) {
    return '规则段数太多(上限 $n 段)';
  }

  @override
  String rulesTooLong(int n) {
    return '规则太长(上限 $n 字)';
  }

  @override
  String get rulesHeader1 => '# Plana AI 助手规则预设';

  @override
  String get rulesHeader2 =>
      '# 每段一个 name 和 content。带 when 的是条件段,例如 when: comic 只在画漫画时发送。';

  @override
  String get rulesHeader3 =>
      '# when 以 mode: 开头的是模式段,例如 when: \"mode:comic\" 只在选了漫画模式时发送。';

  @override
  String get rulesHeader4 =>
      '# when 前面加 ! 表示没选时才发送,例如 when: \"!mode:natural\" 选了仅自然语言就不发。';

  @override
  String badFileFormat(String detail) {
    return '文件格式不对:$detail';
  }

  @override
  String badFileFormatLine(int line, String detail) {
    return '文件格式不对(第 $line 行):$detail';
  }

  @override
  String get noSections => '文件格式不对:找不到 sections';

  @override
  String get noUsableRules => '文件里没有可用的规则段';

  @override
  String get clearHistoryQ => '清空历史会话?';

  @override
  String clearHistoryBody(int n) {
    return '$n 段对话都会删掉,已经写进创作页的改动不受影响。';
  }

  @override
  String get noArchivedChats => '还没有归档的对话。\n点右上角「新对话」就会把当前这段存进来。';

  @override
  String turnsN(int n) {
    return '$n 轮';
  }

  @override
  String get justNow => '刚刚';

  @override
  String get libraryScope => '资料库范围';

  @override
  String get usageHabits => '使用习惯';

  @override
  String get autoDraw => '生成提示词后自动出图';

  @override
  String get autoDrawDesc => '提示词生成完成后立即开始出图';

  @override
  String get inlineImages => '在对话内显示图片';

  @override
  String get inlineImagesDesc => '生成的图片显示在对话内,同时保存至图库';

  @override
  String get autoWrite => '自动写入创作页';

  @override
  String get autoWriteDesc => '生成的提示词自动写回创作页,无需手动导入';

  @override
  String get startUsingAssistant => '开始使用 AI 助手';

  @override
  String get previous => '上一步';

  @override
  String get chatMode => '对话模式';

  @override
  String get planaBackend => 'Plana Bot';

  @override
  String get freeModels => '免费模型';

  @override
  String get incompleteTapToFix => '还没填全,点一下去补';

  @override
  String get writtenToCreate => '已写入创作页';

  @override
  String get undoImportQ => '撤销这次导入?';

  @override
  String get undoImportBody => '你在导入之后又动过提示词。撤销会一并丢掉你那些改动,回到导入之前的样子。';

  @override
  String get undoAnyway => '仍要撤销';

  @override
  String get undone => '已撤销';

  @override
  String get imported => '已导入';

  @override
  String get added => '新增';

  @override
  String get fullPrompt => '完整提示词';

  @override
  String get sameAsLastTurn => '和上一轮的提示词一样';

  @override
  String generatedNTags(int n) {
    return '生成了 $n tag';
  }

  @override
  String writtenNChars(int n) {
    return '已写入 · $n 个角色';
  }

  @override
  String aiGaveNChars(int n) {
    return 'AI 给了 $n 个角色';
  }

  @override
  String get aiWroteFull => 'AI 写了一整份提示词';

  @override
  String get sameAsYours => '和你现在的提示词一样';

  @override
  String get aiChanges => 'AI 的改动';

  @override
  String get settingMessageSize => '消息字号';

  @override
  String get settingMessageSizeDesc => '对话消息的文字显示大小';

  @override
  String get streamOutput => '流式输出';

  @override
  String get streamOutputDesc => '逐字显示回复';

  @override
  String get settingDraw => '出图';

  @override
  String get plainTextFormat => '纯文本格式';

  @override
  String get plainTextFormatDesc => '提示词只显示为文本,不导入也不出图';

  @override
  String get importModeDesc => '提示词写入创作页主提示词的位置';

  @override
  String get settingAuto => '自动';

  @override
  String get settingChat => '对话';

  @override
  String get contextTurns => '上下文轮数';

  @override
  String get contextTurnsDesc => '每次发送带上最近几轮对话';

  @override
  String get failRetries => '失败重试';

  @override
  String get failRetriesDesc => '出错时自动重发';

  @override
  String get retryStripImage => '最后一次重试不带图';

  @override
  String get retryStripImageDesc => '最后一次失败重试时去掉附图';

  @override
  String get refusalRetries => '拒绝重试';

  @override
  String get refusalRetriesDesc => '回复像拒绝时自动重新生成';

  @override
  String get refusalKeywords => '拒绝关键词';

  @override
  String get refusalKeywordsDesc => '不出图的回复命中其中一个就算拒绝';

  @override
  String get addRefusalKeyword => '添加关键词，逗号隔开可加多个';

  @override
  String get restoreDefaultKeywordsQ => '恢复默认关键词？';

  @override
  String get restoreDefaultKeywordsBody => '添加和删除过的关键词都会还原';

  @override
  String keywordsN(int n) {
    return '$n 个';
  }

  @override
  String get settingLibrary => '资料';

  @override
  String get ocPlaceholder => 'OC 使用占位符';

  @override
  String get ocPlaceholderDesc => 'OC 只给 AI 占位符，出图时还原；调整原设时请关闭';

  @override
  String get modelUnsupported => '当前模型不支持';

  @override
  String get settingRules => '规则';

  @override
  String get rulePresetsDesc => '生成提示词时遵循的规则';

  @override
  String get settingDebug => '调试';

  @override
  String get exportChatLog => '导出对话记录';

  @override
  String get exportChatLogDesc => '当前对话每一轮发给 AI 的内容和返回';

  @override
  String get chatEmpty => '当前对话是空的';

  @override
  String get chatLogExported => '已导出对话记录';

  @override
  String get adjustThinkDepth => '调整模型思考深度';

  @override
  String get thinkDepthNote => '并非所有模型都支持深度调整,请参考模型和提供商的文档。';

  @override
  String naiStatusLine(String state) {
    return 'NovelAI 官方:图像生成$state';
  }

  @override
  String get naiStateDown => '服务中断';

  @override
  String get naiStatePartial => '部分中断';

  @override
  String get naiStateDegraded => '性能下降';

  @override
  String get naiStateMaintenance => '维护中';

  @override
  String get naiStateSecurity => '安全事件';

  @override
  String get naiStateIssue => '异常';

  @override
  String get naiStatusDetails => '详情';
}

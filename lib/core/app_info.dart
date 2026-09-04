/// 应用标识与出处。
///
/// 版本号与 `pubspec.yaml` 手工同步 —— 只为读这一行去引 package_info 插件
/// 不划算;漂移由 `test/app_info_test.dart` 盯着,对不上直接红。
library;

/// 显示名。改这里要连 `android/app/src/main/AndroidManifest.xml` 的
/// `android:label` 一起改 —— 那个是桌面图标下的名字,读不到 Dart 常量。
const kAppName = 'Plana App';
const kAppTagline = 'NovelAI 移动创作端';
const kAppVersion = '1.0.9';
const kAppBuild = '16';

/// 预发布版(版号带 `-`):关于页加内测标,免得测试反馈回来分不清版本。
bool get kIsPrerelease => kAppVersion.contains('-');

/// 法典图鉴的数据来源。
const kCodexSourceUrl = 'https://novelai.quicktagcloud.com/';

/// 增强补全的中文搜词与译名来源。后端 `/api/tags/search` 是它的代理,
/// 中文名与一句话简介也出自它的建库产物(tags_enhanced.csv)。
const kDanbooruSearchUrl =
    'https://github.com/SuzumiyaAkizuki/DanbooruSearchOnline';

/// 离线补全词库(`assets/danbooru.tsv`,随包分发)的来源:标签表、热度与绝大部分
/// 中文译名取自其 `danbooru_e621_merged_with_zh.csv`。上游同为 GPL-3.0,再分发
/// 合规 —— 详见 THIRD_PARTY_NOTICES.md。
const kOfflineTagSourceUrl =
    'https://github.com/zhulinyv/Auto-NovelAI-Refactor';

/// NovelAI 官网。本应用是第三方客户端,出图能力全部来自它。
const kNovelAiUrl = 'https://novelai.net/';

/// QQ 交流群号。关于页那一行点了就是复制它 —— 不做跳转:
/// 一键加群短链会先弹一下浏览器再跳回 QQ,唤起 scheme 又得赌机型与 QQ 版本,
/// 两种都不如「复制群号,自己去搜」来得稳。
const kQqGroupId = '1078261982';

/// GitHub 仓库(`owner/repo`),「检查更新」据此查 Releases,关于页据此显示源码入口。
///
/// **开源发布后把仓库名填在这里 —— 只此一处。** 留空时检查更新显示「暂无更新信息」、
/// 关于页不显示源码行,都不报错。填了之后应用只做两件事:比版本、把用户送去
/// Release 页;下载和安装始终交给浏览器与系统。
const kGithubRepo = 'mc5024/Plana-App';

/// 本项目的许可证。GPL-3.0:分发修改版(含打包成 APK 分发)必须同样开源。
const kLicense = 'GPL-3.0';
const kLicenseUrl = 'https://www.gnu.org/licenses/gpl-3.0.html';

/// 版权与免责,用于 `showLicensePage` 的 legalese 区。
const kLegalese =
    'Copyright (C) 2026 Sora_Light\n\n'
    '本程序是自由软件,依据 GNU GPL v3 或更新版本分发。'
    '分发本程序是希望它有用,但不作任何担保。\n\n'
    '$kAppName 是第三方客户端,与 NovelAI 官方无关联。';

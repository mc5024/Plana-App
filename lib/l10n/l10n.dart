import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// 界面支持的语言,按回退顺序:系统语言都对不上时用第一个。
const kSupportedLocales = [Locale('zh'), Locale('en'), Locale('ja')];

final _zh = lookupAppLocalizations(const Locale('zh'));

AppLocalizations _now = _zh;

/// 当前界面语言的文案,给拿不到 BuildContext 的地方(通知、单例、异常)用。
/// 由 [syncL10nNow] 跟着界面语言更新;没同步过时取中文。
AppLocalizations get l10nNow => _now;

/// 在 MaterialApp.builder 里调:登记依赖,换语言时随之重跑。
void syncL10nNow(BuildContext context) => _now = context.l10n;

extension L10nContext on BuildContext {
  /// 当前界面语言的文案。树上没挂翻译(测试里的裸 MaterialApp)时取中文。
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _zh;
}

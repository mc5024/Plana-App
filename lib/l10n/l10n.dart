import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// 界面支持的语言,按回退顺序:系统语言都对不上时用第一个。
const kSupportedLocales = [Locale('zh'), Locale('en'), Locale('ja')];

final _zh = lookupAppLocalizations(const Locale('zh'));

extension L10nContext on BuildContext {
  /// 当前界面语言的文案。树上没挂翻译(测试里的裸 MaterialApp)时取中文。
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _zh;
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/import/import_prefs.dart';

void main() {
  test('默认值与「记住上次设置」之前的行为逐项一致', () {
    const p = ImportPrefs();
    // 这几条是改动前 _initSelections 里硬编码的默认,变了就是老用户的行为被改了
    expect(p.presetImport, isTrue); // _presetImport = true
    // 区级「这类要不要导」默认全开 = 改动前的行为(角色/Vibe/LoRA 都预勾满)
    expect(p.charImport, isTrue);
    expect(p.vibeImport, isTrue);
    expect(p.loraImport, isTrue);
    expect(p.charAppend, isFalse); // 完全覆盖
    expect(p.vibeAppend, isFalse);
    expect(p.loraAppend, isFalse);
    expect(p.useSeed, isFalse); // 默认不导入种子
    expect(p.charExpanded, isTrue);
    expect(p.vibeExpanded, isTrue);
    expect(p.settingsExpanded, isTrue);
    expect(p.loraExpanded, isTrue);
    // 参数项:空表 + 面板侧的 `?? true` = 全勾上,与改动前 e.set(supported) 一致
    expect(p.settings, isEmpty);
    expect(p.settings['Steps'] ?? true, isTrue);
  });

  test('往返序列化', () {
    const p = ImportPrefs(
      presetImport: false,
      charImport: false,
      vibeImport: false,
      loraImport: false,
      charAppend: true,
      vibeAppend: true,
      loraAppend: true,
      useSeed: true,
      settings: {'Steps': false, 'CFG': true},
      charExpanded: false,
      settingsExpanded: false,
    );
    final back = ImportPrefs.fromJson(
      jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
    );
    expect(back.presetImport, isFalse);
    expect(back.charImport, isFalse);
    expect(back.vibeImport, isFalse);
    expect(back.loraImport, isFalse);
    expect(back.charAppend, isTrue);
    expect(back.vibeAppend, isTrue);
    expect(back.loraAppend, isTrue);
    expect(back.useSeed, isTrue);
    expect(back.settings, {'Steps': false, 'CFG': true});
    expect(back.charExpanded, isFalse);
    expect(back.vibeExpanded, isTrue);
    expect(back.settingsExpanded, isFalse);
    expect(back.loraExpanded, isTrue);
  });

  test('坏字段逐项退默认,不因为一个坏值丢掉整份偏好', () {
    final p = ImportPrefs.fromJson({
      'presetImport': 'yes', // 类型不对
      'charAppend': true, // 好的那项要留住
      'settings': {'Steps': false, 'CFG': 'nope', 'Seed': 1},
      'vibeExpanded': null,
    });
    expect(p.presetImport, isTrue, reason: '坏值退默认');
    expect(p.charAppend, isTrue, reason: '同一份里好的项不能被牵连');
    expect(p.settings, {'Steps': false}, reason: '非 bool 的表项丢掉');
    expect(p.vibeExpanded, isTrue);
  });

  test('区级开关缺席时默认开:老用户升级后行为不变', () {
    // 旧偏好文件里没有这三个键(它们是后加的)。缺席必须当 true,否则老用户
    // 升级之后角色/Vibe/LoRA 会突然一个都不预勾。
    final p = ImportPrefs.fromJson({'presetImport': false, 'charAppend': true});
    expect(p.charImport, isTrue);
    expect(p.vibeImport, isTrue);
    expect(p.loraImport, isTrue);
    expect(p.presetImport, isFalse, reason: '同一份里已有的键照常读出来');
  });

  test('settings 只需存被取消的项:缺席即勾上', () {
    // 面板保存时写的是 {标题: 是否勾选};读回来后缺席的按 true 处理。
    const p = ImportPrefs(settings: {'Steps': false});
    expect(p.settings['Steps'] ?? true, isFalse, reason: '用户取消过的记住');
    expect(p.settings['CFG'] ?? true, isTrue, reason: '没记录过的仍默认勾上');
    expect(
      p.settings['某个新加的参数项'] ?? true,
      isTrue,
      reason: '以后新增参数项不会因为旧偏好里没有而默认不勾',
    );
  });
}

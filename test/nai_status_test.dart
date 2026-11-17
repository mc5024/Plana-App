import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/net/nai_status.dart';
import 'package:plana_app/l10n/l10n.dart';

final _now = DateTime.utc(2026, 11, 17, 12);

Map<String, dynamic> _resp({
  int imageCode = 100,
  List<Map<String, dynamic>> incidents = const [],
}) => {
  'ok': true,
  'fetched_at': 0,
  'stale_seconds': 10,
  'last_error': '',
  'data': {
    'overall': {'status': 'Operational', 'code': 100, 'updated_at': ''},
    'components': [
      {'id': 'a', 'name': 'Website', 'status': 'Operational', 'code': 100},
      {
        'id': 'b',
        'name': 'Image Generation',
        'status': 'x',
        'code': imageCode,
      },
    ],
    'incidents': incidents,
    'page_url': 'https://status.novelai.net/',
  },
};

Map<String, dynamic> _incident(
  String id, {
  List<String> components = const ['Image Generation'],
  int code = 500,
  String? datetime,
}) => {
  'id': id,
  'name': 'Incident $id',
  'status': 'Service Disruption',
  'code': code,
  'components': components,
  'message': '',
  'url': 'https://status.novelai.net/pages/incident/x/$id',
  'datetime': datetime,
};

NaiStatusAlert? _alert(Map<String, dynamic> j) =>
    naiStatusAlert(parseNaiStatus(j), now: _now);

void main() {
  test('后端还没抓到过:不解析', () {
    expect(parseNaiStatus({'ok': false, 'data': null}), isNull);
  });

  test('一切正常:不提醒', () {
    expect(_alert(_resp()), isNull);
  });

  test('影响出图的事故:取最严重那条,每条事故一个去重键', () {
    final a = _alert(
      _resp(
        incidents: [
          _incident('aa', code: 300),
          _incident('bb', code: 500),
        ],
      ),
    )!;
    expect(a.code, 500);
    expect(a.title, 'Incident bb');
    expect(a.url, endsWith('/bb'));
    expect(a.keys, ['aa', 'bb']);
  });

  test('只影响登录等其他组件的事故:不提醒', () {
    expect(
      _alert(_resp(incidents: [_incident('aa', components: ['Login'])])),
      isNull,
    );
  });

  test('开始超过一天的出图事故不提醒,组件异常也一并不提醒', () {
    expect(
      _alert(
        _resp(
          imageCode: 500,
          incidents: [_incident('aa', datetime: '2026-11-15T12:00:00Z')],
        ),
      ),
      isNull,
    );
  });

  test('开始时间读不出的事故照常提醒', () {
    expect(
      _alert(
        _resp(incidents: [_incident('aa', datetime: 'November 13, 2026')]),
      ),
      isNotNull,
    );
  });

  test('没有事故但图像生成组件异常:按组件状态提醒', () {
    final a = _alert(_resp(imageCode: 300))!;
    expect(a.code, 300);
    expect(a.title, isNull);
    expect(a.url, 'https://status.novelai.net/');
    expect(a.keys, ['image:300']);
  });

  test('状态那一行按严重度取文案', () {
    final l = lookupAppLocalizations(const Locale('zh'));
    NaiStatusAlert of(int? code) =>
        NaiStatusAlert(code: code, title: null, url: '', keys: const []);
    expect(naiStatusLine(l, of(500)), 'NovelAI 官方:图像生成服务中断');
    expect(naiStatusLine(l, of(400)), 'NovelAI 官方:图像生成部分中断');
    expect(naiStatusLine(l, of(300)), 'NovelAI 官方:图像生成性能下降');
    expect(naiStatusLine(l, of(200)), 'NovelAI 官方:图像生成维护中');
    expect(naiStatusLine(l, of(null)), 'NovelAI 官方:图像生成异常');
  });
}

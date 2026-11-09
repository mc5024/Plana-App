// API 密钥页:列表、新建时完整密钥只给一次、撤销。后端是假的。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/auth/bot_session_store.dart';
import 'package:plana_app/core/net/backend_client.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/profile/api_keys_page.dart';

class _Session extends BotSessionNotifier {
  @override
  Future<BotSession?> build() async =>
      const BotSession(sessionId: 's1', botUserId: 'me');
}

/// 服务端那张表的最小替身:每人最多 3 把,新建的排最前。
class _Backend extends BackendClient {
  _Backend() : super('http://test');

  final keys = <Map<String, dynamic>>[
    {
      'id': 1,
      'name': 'ComfyUI',
      'prefix': 'pk-Ab12Cd34',
      'created_at': '2026-11-02T19:04:11',
      'last_used_at': null,
    },
  ];
  final sessions = <String>[];
  var nextId = 2;

  Map<String, dynamic> _list() => {
    'keys': keys,
    'max': 3,
    'base_url': 'https://nai.sora214.top',
  };

  @override
  Future<ApiKeyList> apiKeys(String sessionId) async {
    sessions.add(sessionId);
    return ApiKeyList.fromJson(_list());
  }

  @override
  Future<CreatedApiKey> createApiKey(
    String sessionId, {
    String name = '',
  }) async {
    sessions.add(sessionId);
    final row = {
      'id': nextId++,
      'name': name,
      'prefix': 'pk-Zz99Yy88',
      'created_at': '2026-11-02T20:00:00',
      'last_used_at': null,
    };
    keys.insert(0, row);
    return CreatedApiKey.fromJson({
      ...row,
      'key': 'pk-Zz99Yy88${'x' * 32}',
      'base_url': 'https://nai.sora214.top',
    });
  }

  @override
  Future<void> revokeApiKey(String sessionId, int id) async {
    sessions.add(sessionId);
    keys.removeWhere((k) => k['id'] == id);
  }
}

Future<_Backend> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final backend = _Backend();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendClientProvider.overrideWithValue(backend),
        botSessionProvider.overrideWith(_Session.new),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ApiKeysPage()),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  testWidgets('列出密钥和要填的地址', (tester) async {
    final backend = await _open(tester);
    expect(find.text('https://nai.sora214.top'), findsOneWidget);
    expect(find.text('ComfyUI'), findsOneWidget);
    expect(find.text('pk-Ab12Cd34'), findsOneWidget);
    expect(find.textContaining('还没用过'), findsOneWidget);
    expect(find.textContaining('1 / 3 把'), findsOneWidget);
    expect(backend.sessions, everyElement('s1'));
  });

  testWidgets('新建后完整密钥只弹这一次,关掉回到列表', (tester) async {
    final backend = await _open(tester);
    await tester.tap(find.byTooltip('新建密钥'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  SillyTavern ');
    await tester.tap(find.widgetWithText(FilledButton, '新建'));
    await tester.pumpAndSettle();

    final full = 'pk-Zz99Yy88${'x' * 32}';
    expect(find.text('密钥已新建'), findsOneWidget);
    expect(find.text(full), findsOneWidget);
    await tester.tap(find.text('我已保存'));
    await tester.pumpAndSettle();

    expect(find.text(full), findsNothing); // 列表里只剩前缀
    expect(find.text('SillyTavern'), findsOneWidget);
    expect(backend.keys.first['name'], 'SillyTavern');
    expect(find.textContaining('2 / 3 把'), findsOneWidget);
  });

  testWidgets('撤销要确认,确认后从列表消失', (tester) async {
    final backend = await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, '撤销'));
    await tester.pumpAndSettle();
    expect(find.textContaining('「ComfyUI」'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '撤销'));
    await tester.pumpAndSettle();

    expect(backend.keys, isEmpty);
    expect(find.text('ComfyUI'), findsNothing);
    expect(find.text('还没有密钥'), findsOneWidget);
  });
}

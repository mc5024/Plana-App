import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/models.dart';
import 'package:plana_app/features/gallery/phone_gallery_save.dart';
import 'package:plana_app/features/gallery/phone_image_date.dart';
import 'package:plana_app/features/gallery/save_settings.dart';
import 'package:plana_app/features/gallery/widgets/gallery_grid_sheet.dart';
import 'package:plana_app/features/gallery/widgets/result_thumb.dart';
import 'package:plana_app/features/gallery/widgets/save_sheet.dart';

ResultImage picture(String id, int minute, {int seed = 7}) => ResultImage(
  id: id,
  width: 64,
  height: 64,
  seed: seed,
  createdAt: DateTime(2026, 9, 21, 13, minute).millisecondsSinceEpoch,
);

// 这里验证手机写入顺序；偏好文件落盘由保存设置自己的测试覆盖。
class _MemorySaveSettings extends SaveSettingsNotifier {
  @override
  Future<SaveSettings> build() async => const SaveSettings();

  @override
  Future<void> patch(SaveSettings Function(SaveSettings) change) async {
    state = AsyncData(change(state.value ?? const SaveSettings()));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const photos = MethodChannel('com.fluttercandies/photo_manager');
  const gal = MethodChannel('gal');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final writes = <Map<dynamic, dynamic>>[];
  final legacyWrites = <Map<dynamic, dynamic>>[];
  var sdk = '36';
  Future<void> Function(int)? onWrite;
  Uint8List pixels(SaveFormat format) {
    final image = img.Image(width: 4, height: 4);
    return format == SaveFormat.png
        ? img.encodePng(image)
        : img.encodeJpg(image);
  }

  setUp(() {
    writes.clear();
    legacyWrites.clear();
    sdk = '36';
    onWrite = null;
    messenger.setMockMethodCallHandler(photos, (call) async {
      if (call.method == 'systemVersion') return sdk;
      expect(call.method, 'saveImage');
      writes.add(call.arguments as Map);
      await onWrite?.call(writes.length);
      return {'id': '${writes.length}', 'type': 1, 'width': 64, 'height': 64};
    });
    messenger.setMockMethodCallHandler(gal, (call) async {
      if (call.method == 'hasAccess' || call.method == 'requestAccess') {
        return true;
      }
      expect(call.method, 'putImageBytes');
      legacyWrites.add(call.arguments as Map);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(photos, null);
    messenger.setMockMethodCallHandler(gal, null);
  });

  test('按生成时间排序，不改历史顺序；同毫秒按入库序号，未知日期最后', () {
    final input = [
      picture('gen99', 2).withCreatedAt(0),
      picture('gen10', 1),
      picture('gen2', 1),
      picture('gen8', 0),
    ];
    expect(oldestFirstForSave(input).map((e) => e.id), [
      'gen8',
      'gen2',
      'gen10',
      'gen99',
    ]);
    expect(input.map((e) => e.id), ['gen99', 'gen10', 'gen2', 'gen8']);
    final names = oldestFirstForSave(input).map(phoneGalleryImageName).toList();
    expect(names.toList()..sort(), names);
    expect(names.first, startsWith('plana_20260921_130000_000_'));
    expect(names.last, startsWith('plana_unknown_'));
    expect(names.toSet().length, 4); // 同 seed 不撞名。
  });

  for (final format in SaveFormat.values) {
    test('Android $format 写入可扫描的生成日期、文件名和手机相册', () async {
      final image = picture('gen1', 0);
      final bytes = pixels(format);
      await saveProcessedImageToPhone(
        bytes,
        image: image,
        format: format,
        album: '测试排序',
      );
      expect(
        writes.single['image'],
        withPhoneCaptureDate(bytes, image.createdAt, format),
      );
      expect(writes.single['creationDate'], image.createdAt);
      expect(
        writes.single['filename'],
        '${phoneGalleryImageName(image)}.${format.name}',
      );
      expect(writes.single['title'], writes.single['filename']);
      expect(writes.single['relativePath'], 'Pictures/测试排序/');
      expect(legacyWrites, isEmpty);
    });
  }

  test('无生成日期不写 1970 年，默认存到 Pictures', () async {
    await saveProcessedImageToPhone(
      Uint8List(1),
      image: picture('gen0', 0).withCreatedAt(0),
      format: SaveFormat.png,
    );
    expect(writes.single['creationDate'], isNull);
    expect(writes.single['relativePath'], 'Pictures/');
  });

  test('旧 Android 继续使用原有相册路径和权限机制', () async {
    sdk = '28';
    await saveProcessedImageToPhone(
      pixels(SaveFormat.png),
      image: picture('gen0', 0),
      format: SaveFormat.png,
      album: '相册',
    );
    expect(writes, isEmpty);
    expect(legacyWrites.single['album'], '相册');
    expect(
      legacyWrites.single['name'],
      startsWith('plana_20260921_130000_000_'),
    );
  });

  test('平台写入失败直接报告，不调用另一管线重复保存', () async {
    onWrite = (_) async => throw PlatformException(code: 'full');
    await expectLater(
      saveProcessedImageToPhone(
        pixels(SaveFormat.png),
        image: picture('gen0', 0),
        format: SaveFormat.png,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(writes, hasLength(1));
    expect(legacyWrites, isEmpty);
  });

  for (final toAlbum in [false, true]) {
    testWidgets('实际多选保存从 13:00 到 13:01，等待每张完成（指定相册 $toAlbum）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stores = AppStores.ephemeral();
      final bytes = File('assets/app_icon.png').readAsBytesSync();
      final old = picture('gen0', 0);
      final newer = picture('gen1', 1);
      stores.gallery.initialResults = [
        for (final image in [newer, old])
          ResultImage(
            id: image.id,
            width: 64,
            height: 64,
            seed: image.seed,
            createdAt: image.createdAt,
            bytes: bytes,
          ),
      ];
      await tester.runAsync(
        () => stores.prefs.write(key: 'hint_grid_longpress', value: '1'),
      );
      final container = ProviderContainer(
        overrides: [
          appStoresProvider.overrideWithValue(stores),
          saveSettingsProvider.overrideWith(_MemorySaveSettings.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showGalleryGrid(context),
                  child: const Text('历史'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('多选'));
      await tester.pumpAndSettle();
      // 按显示的「新→旧」勾选，保存必须重新按时间排列。
      await tester.tap(find.byType(ResultThumb).first);
      await tester.pump();
      await tester.tap(find.byType(ResultThumb).last);
      await tester.pump();
      final firstDone = Completer<void>();
      onWrite = (number) => number == 1 ? firstDone.future : Future.value();
      if (toAlbum) {
        await tester.tap(find.text('手机相册'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '测试排序');
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存').last);
      } else {
        await tester.tap(find.text('保存 (2)'));
      }
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(writes, hasLength(1));
      expect(writes.single['creationDate'], old.createdAt);
      firstDone.complete();
      await tester.pumpAndSettle();
      expect(writes.map((w) => w['creationDate']), [
        old.createdAt,
        newer.createdAt,
      ]);
      expect(
        writes.map((w) => w['relativePath']),
        everyElement(toAlbum ? 'Pictures/测试排序/' : 'Pictures/'),
      );
      expect(
        find.text(toAlbum ? '已保存 2 张到「测试排序」' : '已保存 2 张到相册'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        stores.flushNow();
        await stores.gallery.idle;
      });
    });
  }

  testWidgets('长按保存面板使用同样的生成时间和文件名', (tester) async {
    final stores = AppStores.ephemeral();
    final container = ProviderContainer(
      overrides: [appStoresProvider.overrideWithValue(stores)],
    );
    addTearDown(container.dispose);
    final image = picture('gen2', 1);
    final bytes = File('assets/app_icon.png').readAsBytesSync();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showSaveSheet(context, bytes: bytes, image: image),
                child: const Text('设置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('${phoneGalleryImageName(image)}.png'), findsOneWidget);
    await tester.tap(find.text('单次保存'));
    await tester.pumpAndSettle();
    expect(writes.single['creationDate'], image.createdAt);
    expect(
      writes.single['image'],
      withPhoneCaptureDate(bytes, image.createdAt, SaveFormat.png),
    );
    expect(tester.takeException(), isNull);
  });
}

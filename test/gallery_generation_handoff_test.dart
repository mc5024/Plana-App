import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/auth/auth_mode.dart';
import 'package:plana_app/core/auth/nai_keys.dart';
import 'package:plana_app/core/net/gen_abort.dart';
import 'package:plana_app/core/net/nai_client.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/core/theme/app_theme.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/features/gallery/albums/album_state.dart';
import 'package:plana_app/features/gallery/gallery_page.dart';
import 'package:plana_app/features/gallery/gallery_state.dart';
import 'package:plana_app/features/gallery/widgets/film_strip.dart';
import 'package:plana_app/features/gallery/widgets/result_canvas.dart';
import 'package:plana_app/features/generate/generation_controller.dart';
import 'package:plana_app/features/generate/models.dart';

class _Auth extends AuthModeNotifier {
  @override
  Future<AuthMode?> build() async => AuthMode.token;
}

class _Keys extends NaiKeysNotifier {
  @override
  Future<List<NaiKey>> build() async => [
    const NaiKey(id: 'test', token: 'local-test-only', primary: true),
  ];
}

class _Frames extends NaiClient {
  final started = Completer<void>();
  final stream = StreamController<NaiFrame>();

  @override
  Stream<NaiFrame> generateImageStream({
    required String token,
    required Map<String, dynamic> body,
    GenAbort? abort,
  }) {
    started.complete();
    return stream.stream;
  }

  @override
  Future<NaiSubscription> subscription(String token) async => (
    anlas: 10000,
    fixedAnlas: 10000,
    purchasedAnlas: 0,
    isOpus: true,
    tier: 3,
    usage: null,
  );
}

class _HeldAlbums extends AlbumsNotifier {
  Completer<void>? saving, release;

  void hold() {
    saving = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<AlbumChange> organize(
    Set<String> images,
    Set<String> targets, {
    Set<String>? sources,
  }) async {
    final wait = release;
    if (wait != null) {
      saving!.complete();
      await wait.future;
    }
    return super.organize(images, targets, sources: sources);
  }
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 512);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppStores stores;
  late ProviderContainer c;
  late _Frames client;
  late _HeldAlbums albums;
  late Uint8List oldBytes, previewBytes, finalBytes;
  late String albumId, oldId;
  final capture = GlobalKey();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('plana_handoff_');
    stores = await AppStores.open(rootOverride: root);
    for (final hint in [
      'hint_grid_longpress',
      'hint_save_longpress',
      'hint_strip_swipe',
    ]) {
      await stores.prefs.write(key: hint, value: '1');
    }
    client = _Frames();
    albums = _HeldAlbums();
    c = ProviderContainer(
      overrides: [
        appStoresProvider.overrideWithValue(stores),
        authModeProvider.overrideWith(_Auth.new),
        naiKeysStoreProvider.overrideWith(_Keys.new),
        naiClientProvider.overrideWith((ref, base) => client),
        albumsProvider.overrideWith(() => albums),
      ],
    );
    await c.read(authModeProvider.future);
    await c.read(naiKeysStoreProvider.future);
    albumId = await c.read(albumsProvider.notifier).create('表情包');
    oldBytes = await _png(const Color(0xffff0000));
    previewBytes = await _png(const Color(0xff00ff00));
    finalBytes = await _png(const Color(0xff0000ff));
    oldId =
        (await c
                .read(galleryProvider.notifier)
                .addResultToGallery(
                  bytes: oldBytes,
                  width: 32,
                  height: 32,
                  seed: 1,
                  target: GallerySaveTarget.album(albumId),
                ))
            .id;
  });

  tearDown(() async {
    if (albums.release?.isCompleted == false) albums.release!.complete();
    if (client.stream.hasListener) {
      await client.stream.close();
    } else {
      unawaited(client.stream.close());
    }
    stores.flushNow();
    await stores.gallery.idle;
    await stores.albums.idle;
    c.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: GalleryPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 在真实异步区使用：同时推进图片解码和实际画布帧，不只验最后的 selectedId。
  Future<List<int>> pixel(WidgetTester tester, {bool decode = true}) async {
    // 首帧构建 Image，下一帧显示异步解码结果；交接检查只推进一帧。
    for (var i = 0; i < (decode ? 2 : 1); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final i = (230 * image.width + 120) * 4;
    final rgb = bytes!.buffer.asUint8List().sublist(i, i + 3);
    image.dispose();
    return rgb;
  }

  for (final scope in ['所有照片', '目标图库', '其他图库']) {
    testWidgets('生成预览到入库交接全程不露旧图：$scope', (tester) async {
      final target = scope == '其他图库'
          ? (await tester.runAsync(() => albums.create('新图目标')))!
          : albumId;
      if (scope != '所有照片') albums.browse(albumId);
      albums.setSave(target);
      await mount(tester);
      await tester.runAsync(() async {
        expect(await pixel(tester), [255, 0, 0]);
        final generation = c
            .read(generationProvider.notifier)
            .generate(
              using: GenerateState.initial(),
              stay: true,
              galleryTarget: GallerySaveTarget.album(target),
            );
        await client.started.future;
        client.stream.add((step: 27, isFinal: false, bytes: previewBytes));
        final duringSampling = await pixel(tester);
        albums.hold();
        client.stream.add((step: 28, isFinal: true, bytes: finalBytes));
        await albums.saving!.future;
        final duringSave = await pixel(tester);
        albums.release!.complete();
        final outcome = await generation;
        final afterSave = await pixel(tester, decode: false);
        expect(outcome, GenOutcome.ok);
        expect(duringSampling, [0, 255, 0]);
        expect(duringSave, [0, 0, 255], reason: '落盘等待期间必须保留终图');
        expect(afterSave, [0, 0, 255], reason: '交给历史的首帧也不能露出旧图');
        expect(c.read(generationProvider).jobs, isEmpty);
        final result = c.read(galleryProvider).results.first;
        expect(c.read(albumsProvider).ofImage(result.id), {target});
        expect(
          tester.widget<ResultChrome>(find.byType(ResultChrome)).result.id,
          result.id,
        );
        expect(
          c.read(galleryBrowseAlbumProvider),
          scope == '所有照片' ? null : albumId,
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('保存终图时主动查看历史，完成后保留用户选择', (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final generation = c
          .read(generationProvider.notifier)
          .generate(
            using: GenerateState.initial(),
            stay: true,
            galleryTarget: GallerySaveTarget.album(albumId),
          );
      await client.started.future;
      albums.hold();
      client.stream.add((step: 28, isFinal: true, bytes: finalBytes));
      await albums.saving!.future;
      await tester.pump();
      tester.widget<FilmStrip>(find.byType(FilmStrip)).onSelect(oldId);
      albums.release!.complete();
      expect(await generation, GenOutcome.ok);
      expect(await pixel(tester), [255, 0, 0]);
      expect(c.read(galleryViewProvider).selectedId, oldId);
      expect(c.read(galleryResultPreviewProvider), isNull);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('终图写入失败会退出生成状态，不留下任务卡', (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      // 用同名目录制造真实原子写入失败，不发送网络请求。
      await Directory('${root.path}/gallery/images/gen1.png').create();
      final generation = c
          .read(generationProvider.notifier)
          .generate(
            using: GenerateState.initial(),
            stay: true,
            galleryTarget: GallerySaveTarget.album(albumId),
          );
      await client.started.future;
      client.stream.add((step: 28, isFinal: true, bytes: finalBytes));
      expect(await generation, GenOutcome.maybeCharged);
      await tester.pump();
      expect(c.read(generationProvider).jobs, isEmpty);
      expect(c.read(genStatusProvider).busy, isFalse);
      expect(c.read(galleryViewProvider).selectedId, oldId);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

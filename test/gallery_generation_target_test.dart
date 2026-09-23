import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/store/app_stores.dart';
import 'package:plana_app/features/gallery/albums/album_models.dart';
import 'package:plana_app/features/gallery/albums/album_state.dart';
import 'package:plana_app/features/generate/gen_jobs.dart';
import 'package:plana_app/features/generate/gen_queue.dart';
import 'package:plana_app/features/generate/generate_state.dart';
import 'package:plana_app/features/generate/generation_controller.dart';
import 'package:plana_app/features/generate/loop_controller.dart';
import 'package:plana_app/features/generate/models.dart';

class _ControlledGeneration extends GenerationNotifier {
  final targets = <GallerySaveTarget?>[];
  final replies = <Completer<GenOutcome>>[];
  int workers = 1;
  @override
  GenPool build() => const GenPool(jobs: [], selectedId: null);
  @override
  Future<int> concurrency() async => workers;
  @override
  Future<GenOutcome> generate({
    GallerySaveTarget? galleryTarget,
    GenerateState? using,
    bool stay = false,
    void Function(String)? onJob,
  }) {
    targets.add(galleryTarget);
    final reply = Completer<GenOutcome>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStores stores;
  late ProviderContainer c;
  late _ControlledGeneration gen;
  late String a, b;
  setUp(() async {
    stores = AppStores.ephemeral();
    gen = _ControlledGeneration();
    c = ProviderContainer(
      overrides: [
        appStoresProvider.overrideWithValue(stores),
        generationProvider.overrideWith(() => gen),
      ],
    );
    a = await c.read(albumsProvider.notifier).create('A');
    b = await c.read(albumsProvider.notifier).create('B');
  });
  tearDown(() async {
    stores.flushNow();
    await stores.gallery.idle;
    await stores.albums.idle;
    c.dispose();
  });
  Future<void> dispatched(int count) async {
    for (var i = 0; i < 100 && gen.replies.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(gen.replies.length, count);
  }

  test('队列失败重试与暂停后继续都使用入队目标，显式所有照片不读当前设置', () async {
    final albums = c.read(albumsProvider.notifier);
    final queue = c.read(genQueueProvider.notifier);
    albums.setSave(a);
    queue.enqueue();
    albums.setSave(null);
    queue.enqueue();
    albums.setSave(b);
    final first = queue.maybeStart();
    await dispatched(1);
    gen.replies[0].complete(GenOutcome.notCharged);
    await dispatched(2);
    gen.replies[1].complete(GenOutcome.notCharged);
    await first;
    expect(c.read(genQueueProvider).items, hasLength(2));
    final resume = queue.maybeStart();
    await dispatched(3);
    gen.replies[2].complete(GenOutcome.ok);
    await dispatched(4);
    gen.replies[3].complete(GenOutcome.ok);
    await resume;
    expect(gen.targets.map((v) => v?.albumId), [a, a, a, null]);
    expect(gen.targets.every((v) => v != null), isTrue);
    expect(c.read(gallerySaveTargetProvider).albumId, b);
  });

  test('并发循环整轮冻结目标，续张不会读中途更改的设置', () async {
    gen.workers = 2;
    final albums = c.read(albumsProvider.notifier);
    albums.setSave(a);
    c.read(generateProvider.notifier).setLoop(LoopCount.x4);
    final loop = c.read(loopStatusProvider.notifier).start();
    await dispatched(2);
    albums.browse(b, alsoSave: true);
    gen.replies[1].complete(GenOutcome.ok);
    await dispatched(3);
    gen.replies[0].complete(GenOutcome.ok);
    await dispatched(4);
    gen.replies[2].complete(GenOutcome.ok);
    gen.replies[3].complete(GenOutcome.ok);
    await loop;
    expect(gen.targets.map((v) => v?.albumId), [a, a, a, a]);
    expect(c.read(galleryBrowseAlbumProvider), b);
    expect(c.read(gallerySaveTargetProvider).albumId, b);
  });
}

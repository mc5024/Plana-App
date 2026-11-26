import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/ui/gallery_picker_page.dart';

void main() {
  test('并发不超过上限且排队项按 LIFO 优先派发', () async {
    final queue = PickerThumbQueue(maxConcurrent: 2, maxCache: 10);
    final started = <String>[];
    final completers = <String, Completer<Uint8List?>>{};
    final done = <String>[];

    for (final k in ['a', 'b', 'c', 'd']) {
      final c = Completer<Uint8List?>();
      completers[k] = c;
      queue.enqueue(
        key: k,
        fetch: () {
          started.add(k);
          return c.future;
        },
        onDone: (_) => done.add(k),
      );
    }

    // 最多同时派发 2 个
    expect(started, ['a', 'b']);

    // a 完成后应优先派发最后入队的 d(LIFO),而不是 c
    completers['a']!.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(started, ['a', 'b', 'd']);

    completers['b']!.complete(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);
    expect(started, ['a', 'b', 'd', 'c']);

    completers['d']!.complete(Uint8List.fromList([3]));
    completers['c']!.complete(Uint8List.fromList([4]));
    await Future<void>.delayed(Duration.zero);
    expect(done, ['a', 'b', 'd', 'c']);
    queue.dispose();
  });

  test('排队期间取消的任务不会触发底层拉取', () async {
    final queue = PickerThumbQueue(maxConcurrent: 1, maxCache: 10);
    final c1 = Completer<Uint8List?>();
    final started = <String>[];
    var calledCancelled = false;

    queue.enqueue(
      key: 'first',
      fetch: () {
        started.add('first');
        return c1.future;
      },
      onDone: (_) {},
    );
    final cancelSecond = queue.enqueue(
      key: 'second',
      fetch: () async {
        started.add('second');
        return Uint8List.fromList([2]);
      },
      onDone: (_) => calledCancelled = true,
    );

    cancelSecond();
    c1.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);

    expect(started, ['first']);
    expect(calledCancelled, isFalse);
    queue.dispose();
  });

  test('pause 期间不继续派发新任务,resume 后恢复', () async {
    final queue = PickerThumbQueue(maxConcurrent: 1, maxCache: 10);
    final c1 = Completer<Uint8List?>();
    final started = <String>[];

    queue.enqueue(
      key: 'first',
      fetch: () {
        started.add('first');
        return c1.future;
      },
      onDone: (_) {},
    );
    queue.enqueue(
      key: 'second',
      fetch: () async {
        started.add('second');
        return Uint8List.fromList([2]);
      },
      onDone: (_) {},
    );

    queue.pause();
    c1.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(started, ['first']);

    queue.resume();
    await Future<void>.delayed(Duration.zero);
    expect(started, ['first', 'second']);
    queue.dispose();
  });

  test('LRU 缓存按上限淘汰最久未用项,peek 刷新顺位', () async {
    final queue = PickerThumbQueue(maxConcurrent: 2, maxCache: 2);
    final b1 = Uint8List.fromList([1]);
    final b2 = Uint8List.fromList([2]);
    final b3 = Uint8List.fromList([3]);

    queue.enqueue(key: 'k1', fetch: () async => b1, onDone: (_) {});
    queue.enqueue(key: 'k2', fetch: () async => b2, onDone: (_) {});
    await Future<void>.delayed(Duration.zero);

    // 读一次 k1 使其变成最新,再放 k3 应淘汰 k2
    expect(queue.peek('k1'), same(b1));
    queue.enqueue(key: 'k3', fetch: () async => b3, onDone: (_) {});
    await Future<void>.delayed(Duration.zero);

    expect(queue.peek('k1'), same(b1));
    expect(queue.peek('k2'), isNull);
    expect(queue.peek('k3'), same(b3));
    queue.dispose();
  });
}

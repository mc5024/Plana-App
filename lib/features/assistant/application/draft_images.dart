/// 输入框里待发的图(按附上的顺序)。放在 provider 里,对话里图上的「引用」也往这里加。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/image_pick.dart' show PickedImage;

/// 一条最多附几张图。
const kMaxAttach = 4;

final draftImagesProvider = NotifierProvider<DraftImages, List<PickedImage>>(
  DraftImages.new,
);

class DraftImages extends Notifier<List<PickedImage>> {
  @override
  List<PickedImage> build() => const [];

  /// 加到后面,满了的不收;返回收下了几张。
  int add(Iterable<PickedImage> images) {
    final take = images.take(kMaxAttach - state.length).toList();
    if (take.isNotEmpty) state = [...state, ...take];
    return take.length;
  }

  void removeAt(int i) => state = [...state]..removeAt(i);

  void set(List<PickedImage> images) =>
      state = images.take(kMaxAttach).toList();

  void clear() => state = const [];
}

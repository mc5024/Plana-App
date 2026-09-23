import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../gallery_state.dart';
import 'album_models.dart';
import 'album_state.dart';
import 'album_ui.dart';

Future<AlbumChange?> showAlbumOrganize(
  BuildContext context,
  Set<String> images, {
  String? sourceAlbum,
}) => showModalBottomSheet<AlbumChange>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: .82,
    child: _Organize(images: Set.of(images), sourceAlbum: sourceAlbum),
  ),
);

enum _Action { move, add, remove }

class _Organize extends ConsumerStatefulWidget {
  const _Organize({required this.images, this.sourceAlbum});
  final Set<String> images;
  final String? sourceAlbum;
  @override
  ConsumerState<_Organize> createState() => _OrganizeState();
}

class _OrganizeState extends ConsumerState<_Organize> {
  late _Action _action = widget.sourceAlbum == null
      ? _Action.add
      : _Action.move;
  late final _sources = <String>{
    if (widget.sourceAlbum != null) widget.sourceAlbum!,
  };
  final _targets = <String>{};
  bool _busy = false;
  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final change = await ref
          .read(albumsProvider.notifier)
          .organize(
            widget.images,
            _action == _Action.remove ? {} : Set.of(_targets),
            sources: _action == _Action.add ? null : Set.of(_sources),
          );
      if (mounted) Navigator.pop(context, change);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        albumError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(albumsProvider);
    final live = ref
        .watch(galleryProvider)
        .results
        .map((r) => r.id)
        .toSet()
        .intersection(widget.images);
    final sourceIds = <String>{for (final id in live) ...data.ofImage(id)};
    final sources = _sources.where(data.exists).toSet();
    final targets = _targets.where(data.exists).toSet();
    final count = _action == _Action.add
        ? live.length
        : live
              .where((id) => data.ofImage(id).intersection(sources).isNotEmpty)
              .length;
    final canSubmit =
        !_busy &&
        count > 0 &&
        (_action == _Action.remove || targets.isNotEmpty) &&
        (_action == _Action.add ||
            (sources.isNotEmpty && sources.intersection(targets).isEmpty));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(child: Text('整理到图库', style: context.texts.titleLarge)),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final id = await showAlbumName(context);
                        if (id != null && mounted) {
                          setState(() {
                            if (_action != _Action.add) _targets.clear();
                            _targets.add(id);
                          });
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (a, label) in [
                (_Action.move, '移动'),
                (_Action.add, '添加'),
                if (widget.sourceAlbum != null) (_Action.remove, '从本图库移除'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _action == a,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _action = a;
                          _targets.clear();
                        }),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (_action != _Action.add && widget.sourceAlbum == null) ...[
                const ListTile(
                  title: Text('从哪些图库移出'),
                  subtitle: Text('只移动属于所选来源的图片，其他归属保留'),
                ),
                for (final a in data.albums.where(
                  (a) => sourceIds.contains(a.id),
                ))
                  CheckboxListTile(
                    title: Text(a.name),
                    value: sources.contains(a.id),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              _sources.add(a.id);
                              _targets.remove(a.id);
                            } else {
                              _sources.remove(a.id);
                            }
                          }),
                  ),
                if (sourceIds.isEmpty)
                  const ListTile(title: Text('这些图片还没有所属图库，请使用“添加”')),
                const Divider(),
              ] else if (_action != _Action.add)
                ListTile(
                  title: Text('来源：${data.name(widget.sourceAlbum)}'),
                  subtitle: const Text('其他图库中的归属保留'),
                ),
              if (_action != _Action.remove) ...[
                ListTile(
                  title: Text(_action == _Action.add ? '添加到（可多选）' : '移动到'),
                ),
                for (final a in data.albums)
                  CheckboxListTile(
                    title: Text(a.name),
                    value: targets.contains(a.id),
                    enabled:
                        !_busy &&
                        (_action == _Action.add || !sources.contains(a.id)),
                    onChanged: (v) => setState(() {
                      if (_action != _Action.add) _targets.clear();
                      if (v == true) {
                        _targets.add(a.id);
                      } else {
                        _targets.remove(a.id);
                      }
                    }),
                  ),
                if (data.albums.isEmpty) const ListTile(title: Text('先创建一个图库')),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '涉及 $count 张${live.length > count ? ' · ${live.length - count} 张不属于所选来源' : ''}',
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: canSubmit ? _submit : null,
                    child: Text(
                      _busy
                          ? '保存中…'
                          : '${switch (_action) {
                              _Action.move => '移动',
                              _Action.add => '添加',
                              _Action.remove => '移除',
                            }} ($count)',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

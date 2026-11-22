import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/features/import/image_metadata.dart';
import 'package:plana_app/features/tools/metadata_diff.dart';
import 'package:plana_app/l10n/app_localizations.dart';

List<(TagChange, String)> _flat(List<TagDiff> d) => [
  for (final t in d) (t.change, t.text),
];

ImageMetadata _nai(
  Map<String, dynamic> comment, {
  String source = 'NovelAI Diffusion V4.5 4BDE2A90',
}) => parseNaiMetadataJson({'Source': source, 'Comment': jsonEncode(comment)})!;

void main() {
  group('diffTags', () {
    test('增删与权重变化', () {
      final d = diffTags(
        '1girl, solo, blue eyes, smile',
        '1girl, red eyes, solo, {smile}',
      );
      expect(_flat(d), [
        (TagChange.same, '1girl'),
        (TagChange.onlyB, 'red eyes'),
        (TagChange.same, 'solo'),
        (TagChange.onlyA, 'blue eyes'),
        (TagChange.weight, '{smile}'),
      ]);
      expect(d.last.weightA, 1);
      expect(d.last.weightB, closeTo(1.05, 1e-9));
    });

    test('挪了位置的标签只在 B 的位置出现一次', () {
      expect(_flat(diffTags('a, b, c', 'c, a, b')), [
        (TagChange.moved, 'c'),
        (TagChange.same, 'a'),
        (TagChange.same, 'b'),
      ]);
    });

    test('组权重算到每个成员上', () {
      final d = diffTags('1.2::a, b::, c', 'a, b, c');
      expect(d.map((t) => t.change), [
        TagChange.weight,
        TagChange.weight,
        TagChange.same,
      ]);
      expect(fmtWeight(d.first.weightA!), '1.2');
    });

    test('相同与空串', () {
      expect(tagsDiffer(diffTags('a, {b}', 'a, {b}')), isFalse);
      expect(diffTags('', ''), isEmpty);
      expect(_flat(diffTags('a', '')), [(TagChange.onlyA, 'a')]);
    });
  });

  group('diffParams', () {
    final l = lookupAppLocalizations(const Locale('zh'));
    final base = <String, dynamic>{
      'prompt': '1girl',
      'uc': 'lowres',
      'width': 832,
      'height': 1216,
      'seed': 1,
      'extra_noise_seed': 1,
      'steps': 28,
      'scale': 5.0,
      'sampler': 'k_euler_ancestral',
      'noise_schedule': 'karras',
      'cfg_rescale': 0,
      'dynamic_thresholding': false,
      'v4_prompt': {
        'caption': {'base_caption': '1girl', 'char_captions': []},
        'use_coords': false,
        'use_order': true,
      },
      'signed_hash': 'aaa',
    };

    test('只列出真不同的项,签名与跟随 seed 的 extra_noise_seed 不列', () {
      final a = _nai(base);
      final b = _nai({
        ...base,
        'seed': 2,
        'extra_noise_seed': 2,
        'scale': 5,
        'dynamic_thresholding': true,
        'v4_prompt': {...base['v4_prompt'] as Map, 'use_order': false},
        'signed_hash': 'bbb',
      });
      final rows = diffParams(a, b, l);
      expect(
        [
          for (final r in rows)
            if (r.differs) (r.label, r.a, r.b),
        ],
        [
          ('Seed', '1', '2'),
          ('dynamic_thresholding', 'false', 'true'),
          ('v4_prompt.use_order', 'true', 'false'),
        ],
      );
      final labels = rows.map((r) => r.label).toSet();
      expect(labels, isNot(contains('signed_hash')));
      expect(labels, isNot(contains('extra_noise_seed')));
      expect(labels, isNot(contains('v4_prompt.caption.base_caption')));
    });

    test('长值截断后带指纹,不同值不会显示成一样', () {
      final a = _nai({
        ...base,
        'director_reference_images': ['x' * 200],
      });
      final b = _nai({
        ...base,
        'director_reference_images': ['y' * 200],
      });
      final r = diffParams(
        a,
        b,
        l,
      ).firstWhere((r) => r.label == 'director_reference_images');
      expect(r.differs, isTrue);
      expect(r.a!.length, lessThan(64));
    });

    test('角色按下标对齐,多出来的整段算只在一边', () {
      final a = _nai({
        ...base,
        'v4_prompt': {
          'caption': {
            'base_caption': '1girl',
            'char_captions': [
              {
                'char_caption': 'girl, red hair',
                'centers': [
                  {'x': 0.3, 'y': 0.5},
                ],
              },
            ],
          },
          'use_coords': true,
        },
      });
      final b = _nai({
        ...base,
        'v4_prompt': {
          'caption': {
            'base_caption': '1girl',
            'char_captions': [
              {
                'char_caption': 'girl, blue hair',
                'centers': [
                  {'x': 0.7, 'y': 0.5},
                ],
              },
              {
                'char_caption': 'boy',
                'centers': [
                  {'x': 0.5, 'y': 0.5},
                ],
              },
            ],
          },
          'use_coords': true,
        },
      });
      final chars = diffCharacters(a, b);
      expect(chars, hasLength(2));
      expect(chars[0].posA, '(0.3, 0.5)');
      expect(chars[0].posB, '(0.7, 0.5)');
      expect(_flat(chars[0].prompt), [
        (TagChange.same, 'girl'),
        (TagChange.onlyA, 'red hair'),
        (TagChange.onlyB, 'blue hair'),
      ]);
      expect(chars[1].posA, isNull);
      expect(_flat(chars[1].prompt), [(TagChange.onlyB, 'boy')]);
    });
  });
}

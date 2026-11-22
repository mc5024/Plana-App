import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/ui_prefs.dart';
import '../generate/widgets/common.dart' show measureText;
import 'metadata_compare_page.dart';
import 'metadata_tool_page.dart';
import 'weight_convert_page.dart';
import '../../l10n/l10n.dart';

/// 工具箱(对齐 web):权重转换 / 图片元数据 / 图片比对 三个页签,
/// IndexedStack 保活,切页签不丢已输入内容与已选图。
class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  late int _tab = ref.read(uiPrefsProvider).toolsTab.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.swap_horiz, context.l10n.weightConverter),
      (Icons.document_scanner_outlined, context.l10n.imageMetadata),
      (Icons.difference_outlined, context.l10n.compareImages),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.toolbox)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: LayoutBuilder(
              builder: (context, c) {
                // 一颗放不下「图标 + 文案」就整排只留文案
                final room = c.maxWidth / tabs.length - 24 - 17 - 8 - 4;
                final style = Theme.of(context).textTheme.labelLarge!;
                final icons = tabs.every(
                  (t) => measureText(context, t.$2, style) <= room,
                );
                return SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      for (final (i, (icon, label)) in tabs.indexed)
                        ButtonSegment(
                          value: i,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label, maxLines: 1),
                          ),
                          icon: icons ? Icon(icon, size: 17) : null,
                        ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) {
                      ref
                          .read(uiPrefsProvider.notifier)
                          .patch((p) => p.copyWith(toolsTab: s.first));
                      setState(() => _tab = s.first);
                    },
                    showSelectedIcon: false,
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                WeightConvertView(),
                MetadataToolView(),
                MetadataCompareView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

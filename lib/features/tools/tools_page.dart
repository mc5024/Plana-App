import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/ui_prefs.dart';
import 'metadata_tool_page.dart';
import 'weight_convert_page.dart';
import '../../l10n/l10n.dart';

/// 工具箱(对齐 web):权重转换 / 图片元数据 两个页签,
/// IndexedStack 保活,切页签不丢已输入内容与已选图。
class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  late int _tab = ref.read(uiPrefsProvider).toolsTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.toolbox)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.l10n.weightConverter, maxLines: 1),
                    ),
                    icon: const Icon(Icons.swap_horiz, size: 17),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.l10n.imageMetadata, maxLines: 1),
                    ),
                    icon: const Icon(Icons.document_scanner_outlined, size: 17),
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
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [WeightConvertView(), MetadataToolView()],
            ),
          ),
        ],
      ),
    );
  }
}

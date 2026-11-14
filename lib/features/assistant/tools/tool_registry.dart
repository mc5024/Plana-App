import 'agent_tool.dart';
import 'artist_tool.dart';
import 'character_tool.dart';
import 'oc_tool.dart';
import 'tag_tool.dart';
import 'tool_settings.dart';

/// 内置工具。顺序就是预取资料块的排列顺序,也是工具页的顺序。
const kAgentTools = <AgentTool>[
  SearchArtistTool(),
  SearchOcTool(),
  SearchCharacterTool(),
  LookupTagTool(),
];

/// 这一轮能用的工具:工具开着,有来源的至少开着一个来源。
List<AgentTool> enabledTools(
  ToolSettings s, [
  List<AgentTool> all = kAgentTools,
]) => [
  for (final t in all)
    if (s.toolOn(t.name) &&
        (t.sources.isEmpty || t.sources.any((src) => s.sourceOn(t.name, src.id))))
      t,
];

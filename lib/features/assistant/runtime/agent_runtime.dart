import '../agent_trace.dart';
import '../custom_endpoint.dart' show CustomEndpoint;
import '../domain/agent_event.dart';
import '../domain/turn_request.dart';
import '../llm/http_provider.dart' show llmProviderFor;
import '../tools/tool_context.dart' show OnlineTags, TagLookup;
import 'backend_runtime.dart';
import 'direct_runtime.dart';

/// 跑一轮 AI 对话。事件序列见 [AgentEvent]:中间若干工具 / 增量事件,最后一个必是
/// [AgentDone];失败以 [AgentFailure] 结束流。只有 listen 之后才发请求。
abstract interface class AgentRuntime {
  /// 调试记录里的路线名([AgentTrace.routeBackend] / [AgentTrace.routeCustom])。
  String get route;

  /// [trace] 由 runtime 填请求、系统提示、每一跳这些只有它看得见的细节。
  Stream<AgentEvent> run(AgentTurnRequest request, {AgentTrace? trace});
}

/// 选了自定义接口([endpoint] 非 null)就在本机跑,否则走 Plana 后端。
/// [offline] / [online] 是本机那条的工具来源。
AgentRuntime agentRuntimeFor({
  required CustomEndpoint? endpoint,
  required String backendBase,
  required String sessionId,
  TagLookup? offline,
  OnlineTags? online,
}) => endpoint != null
    ? DirectAgentRuntime(
        provider: llmProviderFor(endpoint),
        offline: offline,
        online: online,
      )
    : BackendAgentRuntime(baseUrl: backendBase, sessionId: sessionId);

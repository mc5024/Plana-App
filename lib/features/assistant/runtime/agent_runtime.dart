import '../agent_trace.dart';
import '../custom_endpoint.dart' show CustomEndpoint;
import '../domain/agent_event.dart';
import '../domain/turn_request.dart';
import '../llm/http_provider.dart' show llmProviderFor;
import '../llm/plana_channel_provider.dart';
import '../tools/tool_context.dart' show OnlineTags, TagLookup;
import 'local_runtime.dart';

/// 跑一轮 AI 对话。事件序列见 [AgentEvent]:中间若干工具 / 增量事件,最后一个必是
/// [AgentDone];失败以 [AgentFailure] 结束流。只有 listen 之后才发请求。
abstract interface class AgentRuntime {
  /// 调试记录里的路线名([AgentTrace.routeBackend] / [AgentTrace.routeCustom])。
  String get route;

  /// [trace] 由 runtime 填系统提示、消息、每一跳这些只有它看得见的细节。
  Stream<AgentEvent> run(AgentTurnRequest request, {AgentTrace? trace});
}

/// 选了自定义接口([endpoint] 非 null)就直连它,否则经后端的模型通道([backendModel] 是渠道
/// key,空串 = 后端默认)。两条都在本机跑 [LocalAgentRuntime];[offline] / [online] 是工具来源。
AgentRuntime agentRuntimeFor({
  required CustomEndpoint? endpoint,
  required String backendBase,
  required String sessionId,
  required String backendModel,
  required String imageModel,
  TagLookup? offline,
  OnlineTags? online,
}) => LocalAgentRuntime(
  provider: endpoint != null
      ? llmProviderFor(endpoint)
      : PlanaChannelProvider(
          baseUrl: backendBase,
          sessionId: sessionId,
          model: backendModel,
          imageModel: imageModel,
        ),
  route: endpoint != null ? AgentTrace.routeCustom : AgentTrace.routeBackend,
  offline: offline,
  online: online,
);

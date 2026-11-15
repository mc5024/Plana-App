/// 工具:模型能调用的一项能力。工具页、系统提示里的工具清单、预取、执行都从这里取,
/// 加一个工具 = 写一个 [AgentTool] 子类 + 一份说明(`assets/prompts/tools/<name>.md`)
/// + 在 `tool_registry.dart` 里登记。
library;

import 'package:flutter/widgets.dart' show IconData;

import '../runtime/prompt_assets.dart';
import 'tool_context.dart';

/// 一项参数,渲染进工具清单。
class ToolParam {
  const ToolParam(this.name, this.type, {this.required = false});

  final String name;

  /// `string` / `integer` / `array`。
  final String type;
  final bool required;
}

/// 工具附带的一个选项(开关),默认关。
class ToolOption {
  ToolOption(this.id, this._label, this._desc);

  final String id;
  final String Function() _label;
  final String Function() _desc;

  String get label => _label();
  String get desc => _desc();
}

/// 预取出的一块资料(带块头),附在用户消息后面。
class ToolBlock {
  const ToolBlock(this.text, {this.resources = const {}});

  final String text;

  /// 本轮命中的资源 `{kind: {名字: 内容}}`,收尾时进账本。
  final Map<String, Map<String, String>> resources;
}

/// 一次调用的结果。
class ToolOutcome {
  const ToolOutcome(this.data, {this.resources = const {}});

  /// 回灌给模型的内容,要能 JSON 编码。
  final Object? data;

  /// 这次用到的资源 `{kind: {名字: 内容}}`:画师串记进占位符映射,收尾时进账本。
  final Map<String, Map<String, String>> resources;

  /// 轨迹上的完成信号(界面不显示)。
  String get summary => switch (data) {
    final List l => '${l.length} 条',
    _ => '已返回',
  };
}

abstract class AgentTool {
  const AgentTool();

  /// 模型调用时写的名字,也是设置里的键。
  String get name;

  /// 工具页上的名字。
  String get label;

  IconData get icon;

  List<ToolParam> get params;

  /// 附带的选项。
  List<ToolOption> get options => const [];

  /// 给模型看的说明。
  Future<String> guidance() => promptAsset('tools/$name.md');

  /// 按选项补在系统提示末尾的说明;没有返回空串。
  Future<String> systemNote(ToolContext ctx) async => '';

  /// 发第一跳前拿用户原话预取一块资料;没有返回 null。
  Future<ToolBlock?> prefetch(ToolContext ctx) async => null;

  /// 执行一次调用。参数不对时返回能告诉模型哪里不对的结果,不抛。
  Future<ToolOutcome> call(ToolContext ctx, Map<String, dynamic> args);
}

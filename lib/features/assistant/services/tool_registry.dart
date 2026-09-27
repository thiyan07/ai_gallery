import 'tool_interface.dart';
import '../models/action_state.dart';

/// Central registry of all available assistant tools.
///
/// Tools are registered at startup. The assistant queries this registry
/// to determine which tools are available, validate actions, and select
/// the appropriate tool for a given intent.
class ToolRegistry {
  final Map<String, AssistantTool> _tools = {};

  /// Register a tool.
  void register(AssistantTool tool) {
    _tools[tool.name] = tool;
  }

  /// Get a tool by name.
  AssistantTool? getTool(String name) => _tools[name];

  /// Check if a tool is registered.
  bool hasTool(String name) => _tools.containsKey(name);

  /// Get all registered tools.
  List<AssistantTool> get allTools => _tools.values.toList();

  /// Get all currently available tools (registered + isAvailable).
  List<AssistantTool> get availableTools =>
      _tools.values.where((t) => t.isAvailable).toList();

  /// Get tools filtered by permission level.
  List<AssistantTool> getToolsByPermission(ActionPermissionLevel level) =>
      availableTools.where((t) => t.permissionLevel == level).toList();

  /// Get tools that require confirmation.
  List<AssistantTool> get confirmationRequiredTools =>
      availableTools.where((t) => t.requiresConfirmation).toList();

  /// Get tools that support undo.
  List<AssistantTool> get undoableTools =>
      availableTools.where((t) => t.supportsUndo).toList();

  /// Validate an action by tool name.
  String? validate(String toolName, Map<String, dynamic> parameters) {
    final tool = getTool(toolName);
    if (tool == null) return 'Unknown tool: $toolName';
    if (!tool.isAvailable) return 'Tool not available: $toolName';
    return tool.validate(parameters);
  }

  /// Execute a tool by name with the given parameters.
  ///
  /// This is a convenience method. Prefer using [ToolExecutor] for
  /// lifecycle management.
  Future<dynamic> executeByName(
    String toolName,
    Map<String, dynamic> parameters,
  ) async {
    final tool = getTool(toolName);
    if (tool == null) {
      throw StateError('Tool not found: $toolName');
    }
    return tool.execute(parameters);
  }
}

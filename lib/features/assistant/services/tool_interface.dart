import '../models/action_state.dart';
import '../models/gallery_action.dart';

/// Result of executing an assistant action.
class ActionResult {
  final bool success;
  final String message;
  final ActionResultType type;
  final Map<String, dynamic> data;
  final String? undoReference;

  const ActionResult._({
    required this.success,
    required this.message,
    required this.type,
    this.data = const {},
    this.undoReference,
  });

  factory ActionResult.success(
    String message, {
    Map<String, dynamic> data = const {},
    String? undoReference,
  }) {
    return ActionResult._(
      success: true,
      message: message,
      type: ActionResultType.success,
      data: data,
      undoReference: undoReference,
    );
  }

  factory ActionResult.failure(String message) {
    return ActionResult._(
      success: false,
      message: message,
      type: ActionResultType.failure,
    );
  }

  factory ActionResult.confirmationRequired(String message,
      {Map<String, dynamic> data = const {}}) {
    return ActionResult._(
      success: false,
      message: message,
      type: ActionResultType.confirmationRequired,
      data: data,
    );
  }

  factory ActionResult.navigation(
    String message, {
    Map<String, dynamic> data = const {},
  }) {
    return ActionResult._(
      success: true,
      message: message,
      type: ActionResultType.navigation,
      data: data,
    );
  }

  factory ActionResult.informational(
    String message, {
    Map<String, dynamic> data = const {},
    List<String> photoIds = const [],
  }) {
    return ActionResult._(
      success: true,
      message: message,
      type: ActionResultType.informational,
      data: {...data, 'photoIds': photoIds},
    );
  }
}

/// A strongly-typed tool that the gallery assistant can invoke.
///
/// Each tool represents a discrete action: search, create, delete, navigate, etc.
/// Tools declare their permission requirements, confirmation behavior,
/// and undo capability.
///
/// Tools are registered in [ToolRegistry] and executed by [ToolExecutor].
abstract class AssistantTool {
  /// Machine-readable name (e.g. 'search_photos', 'create_album').
  String get name;

  /// Human-readable description shown in confirmation dialogs.
  String get description;

  /// Whether this tool requires user confirmation before execution.
  bool get requiresConfirmation;

  /// Whether this tool performs a destructive/destructive-like operation.
  bool get isDestructive;

  /// Permission level required to execute this tool.
  ActionPermissionLevel get permissionLevel;

  /// Whether this tool supports undo after execution.
  bool get supportsUndo => false;

  /// Whether this tool is available in the current state.
  ///
  /// Override to conditionally disable tools (e.g. no photos indexed yet).
  bool get isAvailable => true;

  /// Validate the action parameters before execution.
  ///
  /// Return null if valid, or a human-readable error message if invalid.
  String? validate(Map<String, dynamic> parameters);

  /// Execute the tool with the given parameters.
  ///
  /// Must return an [ActionResult] describing what happened.
  /// If the tool supports undo, include an [ActionResult.undoReference].
  Future<ActionResult> execute(Map<String, dynamic> parameters);

  /// Undo a previously executed action.
  ///
  /// [undoReference] is the reference returned by [execute].
  /// Only called if [supportsUndo] is true.
  Future<ActionResult> undo(String undoReference) {
    throw UnsupportedError('Tool $name does not support undo');
  }

  /// Convert this tool to a [GalleryAction] for backward compatibility.
  GalleryAction toAction(Map<String, dynamic> parameters) {
    return GalleryAction(
      type: _mapToActionType(),
      parameters: parameters,
      description: description,
      requiresConfirmation: requiresConfirmation,
      isDestructive: isDestructive,
    );
  }

  GalleryActionType _mapToActionType() {
    // Default mapping — subclasses can override via toAction
    return GalleryActionType.showSearchResults;
  }
}

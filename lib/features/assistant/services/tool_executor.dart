import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/action_state.dart';
import '../models/gallery_action.dart';
import 'tool_interface.dart';
import 'tool_registry.dart';

/// Tracks the state of a single action through its lifecycle.
class TrackedAction {
  final String id;
  final String toolName;
  final Map<String, dynamic> parameters;
  final String description;
  final ActionPermissionLevel permissionLevel;
  final bool isDestructive;
  final bool supportsUndo;

  ActionStatus status;
  ActionResult? result;
  String? undoReference;
  DateTime createdAt;
  DateTime? completedAt;
  String? errorMessage;

  TrackedAction({
    required this.id,
    required this.toolName,
    required this.parameters,
    required this.description,
    required this.permissionLevel,
    required this.isDestructive,
    required this.supportsUndo,
    this.status = ActionStatus.planned,
  }) : createdAt = DateTime.now();

  /// Whether this action can still be cancelled.
  bool get canCancel =>
      status == ActionStatus.planned ||
      status == ActionStatus.awaitingConfirmation ||
      status == ActionStatus.confirmed;

  /// Whether this action can be undone.
  bool get canUndo =>
      supportsUndo &&
      status == ActionStatus.completed &&
      undoReference != null;

  /// Convert to GalleryAction for backward compatibility.
  GalleryAction toGalleryAction() => GalleryAction(
        type: _reverseMapToolTypeFromName(toolName),
        parameters: parameters,
        description: description,
        requiresConfirmation: true,
        isDestructive: isDestructive,
      );
}

/// Executor that manages the full lifecycle of assistant actions.
///
/// Lifecycle: PLANNED -> AWAITING_CONFIRMATION -> CONFIRMED -> EXECUTING
///                                                       |
///                                              COMPLETED / FAILED
///                                                       |
///                                                 UNDONE (optional)
///
/// Maintains an in-memory action history for the current session.
/// Actions are not persisted (session-scoped, privacy-first).
class ToolExecutor {
  ToolExecutor({required ToolRegistry registry}) : _registry = registry;

  final ToolRegistry _registry;

  /// In-memory action history for the current session.
  final List<TrackedAction> _history = [];

  /// Change notifier for UI reactivity.
  final ValueNotifier<int> _historyVersion = ValueNotifier(0);
  ValueNotifier<int> get historyVersion => _historyVersion;

  /// Unmodifiable view of the action history.
  List<TrackedAction> get history => List.unmodifiable(_history);

  /// Get the most recent action.
  TrackedAction? get lastAction =>
      _history.isNotEmpty ? _history.last : null;

  /// Get actions that can be undone.
  List<TrackedAction> get undoableActions =>
      _history.where((a) => a.canUndo).toList();

  /// Generate a unique action ID.
  String _generateId() {
    return 'action_${DateTime.now().millisecondsSinceEpoch}_${_history.length}';
  }

  /// Create a tracked action from a GalleryAction (backward compatibility).
  TrackedAction trackFromGalleryAction(GalleryAction action) {
    final toolName = _reverseMapToolType(action.type);

    final tracked = TrackedAction(
      id: _generateId(),
      toolName: toolName,
      parameters: action.parameters,
      description: action.description,
      permissionLevel: ActionPermissionLevel.safeWrite,
      isDestructive: action.isDestructive,
      supportsUndo: false,
    );

    if (action.requiresConfirmation) {
      tracked.status = ActionStatus.awaitingConfirmation;
    }

    _history.add(tracked);
    _historyVersion.value++;
    return tracked;
  }

  /// Plan a new action (from tool name + parameters).
  ///
  /// Returns the tracked action in PLANNED or AWAITING_CONFIRMATION state.
  TrackedAction plan(String toolName, Map<String, dynamic> parameters) {
    final tool = _registry.getTool(toolName);
    if (tool == null) {
      throw StateError('Tool not found: $toolName');
    }

    final validation = tool.validate(parameters);
    if (validation != null) {
      throw ArgumentError('Invalid parameters: $validation');
    }

    final tracked = TrackedAction(
      id: _generateId(),
      toolName: toolName,
      parameters: parameters,
      description: tool.description,
      permissionLevel: tool.permissionLevel,
      isDestructive: tool.isDestructive,
      supportsUndo: tool.supportsUndo,
    );

    if (tool.requiresConfirmation) {
      tracked.status = ActionStatus.awaitingConfirmation;
    } else {
      tracked.status = ActionStatus.planned;
    }

    _history.add(tracked);
    _historyVersion.value++;
    return tracked;
  }

  /// Confirm a tracked action and execute it.
  Future<ActionResult> confirmAndExecute(TrackedAction tracked) async {
    if (!tracked.canCancel) {
      return ActionResult.failure(
        'Action cannot be confirmed in current state',
      );
    }

    tracked.status = ActionStatus.confirmed;
    return execute(tracked);
  }

  /// Execute a tracked action directly (skip confirmation).
  Future<ActionResult> execute(TrackedAction tracked) async {
    final tool = _registry.getTool(tracked.toolName);
    if (tool == null) {
      tracked.status = ActionStatus.failed;
      tracked.errorMessage = 'Tool not found: ${tracked.toolName}';
      _historyVersion.value++;
      return ActionResult.failure('Tool not found: ${tracked.toolName}');
    }

    tracked.status = ActionStatus.executing;
    _historyVersion.value++;

    try {
      final result = await tool.execute(tracked.parameters);
      tracked.result = result;
      tracked.undoReference = result.undoReference;

      if (result.success) {
        tracked.status = ActionStatus.completed;
      } else {
        tracked.status = ActionStatus.failed;
        tracked.errorMessage = result.message;
      }

      tracked.completedAt = DateTime.now();
      _historyVersion.value++;
      return result;
    } catch (e, st) {
      tracked.status = ActionStatus.failed;
      tracked.errorMessage = e.toString();
      tracked.completedAt = DateTime.now();
      _historyVersion.value++;
      debugPrint('Tool execution failed: $e\n$st');
      return ActionResult.failure('Execution failed: $e');
    }
  }

  /// Cancel a tracked action.
  bool cancel(TrackedAction tracked) {
    if (!tracked.canCancel) return false;
    tracked.status = ActionStatus.cancelled;
    tracked.completedAt = DateTime.now();
    _historyVersion.value++;
    return true;
  }

  /// Undo a completed action.
  Future<bool> undo(TrackedAction tracked) async {
    if (!tracked.canUndo) return false;

    final tool = _registry.getTool(tracked.toolName);
    if (tool == null) return false;

    try {
      final result = await tool.undo(tracked.undoReference!);
      if (result.success) {
        tracked.status = ActionStatus.undone;
        tracked.completedAt = DateTime.now();
        _historyVersion.value++;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Undo failed: $e');
      return false;
    }
  }

  /// Find a tracked action by its ID.
  TrackedAction? findById(String id) {
    try {
      return _history.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Clear the action history.
  void clearHistory() {
    _history.clear();
    _historyVersion.value++;
  }
}

/// Map a tool name to a GalleryActionType for legacy compatibility.
GalleryActionType _reverseMapToolTypeFromName(String toolName) {
  switch (toolName) {
    case 'search_photos':
      return GalleryActionType.showSearchResults;
    case 'open_photo':
      return GalleryActionType.openPhoto;
    case 'open_person':
      return GalleryActionType.openPerson;
    case 'open_event':
      return GalleryActionType.openEvent;
    case 'open_album':
      return GalleryActionType.openAlbum;
    case 'create_album':
      return GalleryActionType.createSmartAlbum;
    case 'create_memory':
      return GalleryActionType.createMemory;
    case 'open_editor':
      return GalleryActionType.openEditor;
    case 'delete_photos':
      return GalleryActionType.deletePhotos;
    case 'add_favorites':
      return GalleryActionType.addFavorites;
    case 'remove_favorites':
      return GalleryActionType.removeFavorites;
    default:
      return GalleryActionType.showSearchResults;
  }
}

/// Map a GalleryActionType enum to a tool name.
String _reverseMapToolType(GalleryActionType type) {
  switch (type) {
    case GalleryActionType.showSearchResults:
      return 'search_photos';
    case GalleryActionType.openPhoto:
      return 'open_photo';
    case GalleryActionType.openPerson:
      return 'open_person';
    case GalleryActionType.openEvent:
      return 'open_event';
    case GalleryActionType.openAlbum:
      return 'open_album';
    case GalleryActionType.createSmartAlbum:
      return 'create_album';
    case GalleryActionType.createMemory:
      return 'create_memory';
    case GalleryActionType.openEditor:
      return 'open_editor';
    case GalleryActionType.deletePhotos:
      return 'delete_photos';
    case GalleryActionType.addFavorites:
      return 'add_favorites';
    case GalleryActionType.removeFavorites:
      return 'remove_favorites';
  }
}

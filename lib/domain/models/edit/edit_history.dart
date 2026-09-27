import 'package:flutter/foundation.dart';

import 'edit_operation.dart';
import 'edit_recipe.dart';

/// Type of undo/redo snapshot, determines how it coalesces.
enum EditSnapshotType {
  discrete,
  slider,
  grouped,
  aiPlan,
}

/// A single undo/redo snapshot with metadata.
class EditSnapshot {
  final List<EditOperation> operations;
  final EditSnapshotType type;
  final String label;
  final DateTime timestamp;

  const EditSnapshot({
    required this.operations,
    required this.type,
    this.label = '',
    required this.timestamp,
  });

  EditSnapshot copyWith({
    List<EditOperation>? operations,
    EditSnapshotType? type,
    String? label,
    DateTime? timestamp,
  }) {
    return EditSnapshot(
      operations: operations ?? this.operations,
      type: type ?? this.type,
      label: label ?? this.label,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// In-memory undo/redo history for a single photo's edit session.
///
/// Maintains a stack of recipe snapshots with metadata. Each snapshot is a
/// full copy of the operations list at that point in time.
///
/// History coalescing:
/// - `pushState()` adds a new undo entry (for discrete edits like flip, crop)
/// - `replaceCurrent()` replaces the current snapshot in-place (for slider
///   interaction) — no new undo entry is created
/// - `commitState()` forces a new undo entry from the current state
/// - `coalesceState()` replaces the current entry if the previous action
///   was also a coalesce, otherwise adds a new entry.
/// - `pushGroup()` adds a named group entry (for batch, copy/paste, presets)
class EditHistoryManager extends ChangeNotifier {
  EditHistoryManager({EditRecipe? initial})
      : _initial = initial,
        _snapshots = [
          EditSnapshot(
            operations: initial?.operations.toList() ?? [],
            type: EditSnapshotType.discrete,
            label: 'Original',
            timestamp: DateTime.now(),
          ),
        ],
        _currentIndex = 0;

  final EditRecipe? _initial;
  final List<EditSnapshot> _snapshots;
  int _currentIndex;

  /// Maximum number of undo steps retained.
  static const int maxSnapshots = 50;

  /// Whether the last action was a coalesce (for grouping rapid changes).
  bool _lastWasCoalesce = false;

  /// Current operations list.
  List<EditOperation> get currentOperations =>
      List.unmodifiable(_snapshots[_currentIndex].operations);

  /// Current snapshot metadata.
  EditSnapshot get currentSnapshot => _snapshots[_currentIndex];

  /// Whether undo is available.
  bool get canUndo => _currentIndex > 0;

  /// Whether redo is available.
  bool get canRedo => _currentIndex < _snapshots.length - 1;

  /// Number of undo steps available.
  int get undoCount => _currentIndex;

  /// Number of redo steps available.
  int get redoCount => _snapshots.length - 1 - _currentIndex;

  /// Human-readable label for what undo would revert.
  String get undoLabel =>
      canUndo ? _snapshots[_currentIndex].label : '';

  /// Human-readable label for what redo would restore.
  String get redoLabel =>
      canRedo ? _snapshots[_currentIndex + 1].label : '';

  /// Total number of snapshots.
  int get snapshotCount => _snapshots.length;

  /// Get snapshot at a specific index (for UI display).
  EditSnapshot snapshotAt(int index) => _snapshots[index];

  /// Record a new state (after a discrete edit operation).
  void pushState(
    List<EditOperation> operations, {
    String label = '',
  }) {
    _lastWasCoalesce = false;
    _truncateRedo();
    _snapshots.add(EditSnapshot(
      operations: List.from(operations),
      type: EditSnapshotType.discrete,
      label: label,
      timestamp: DateTime.now(),
    ));
    _enforceLimit();
    notifyListeners();
  }

  /// Replace the current snapshot in-place without creating a new undo entry.
  void replaceCurrent(List<EditOperation> operations) {
    _lastWasCoalesce = false;
    _snapshots[_currentIndex] = _snapshots[_currentIndex].copyWith(
      operations: List.from(operations),
    );
    notifyListeners();
  }

  /// Coalesce a state change: if the last action was also a coalesce,
  /// replace the current entry. Otherwise, add a new entry.
  void coalesceState(
    List<EditOperation> operations, {
    String label = '',
  }) {
    if (_lastWasCoalesce) {
      _snapshots[_currentIndex] = _snapshots[_currentIndex].copyWith(
        operations: List.from(operations),
      );
    } else {
      _truncateRedo();
      _snapshots.add(EditSnapshot(
        operations: List.from(operations),
        type: EditSnapshotType.slider,
        label: label,
        timestamp: DateTime.now(),
      ));
      _enforceLimit();
      _lastWasCoalesce = true;
    }
    notifyListeners();
  }

  /// Force a new undo entry from the current state.
  void commitState(
    List<EditOperation> operations, {
    String label = '',
  }) {
    _lastWasCoalesce = false;
    if (_snapshots[_currentIndex].operations != operations) {
      _truncateRedo();
      _snapshots.add(EditSnapshot(
        operations: List.from(operations),
        type: EditSnapshotType.discrete,
        label: label,
        timestamp: DateTime.now(),
      ));
      _enforceLimit();
    }
    notifyListeners();
  }

  /// Push a named group of changes as a single undo step.
  ///
  /// Use for batch edits, copy/paste, preset application, or AI plans.
  /// The entire group collapses into one undo entry.
  void pushGroup(
    List<EditOperation> operations, {
    required String label,
    EditSnapshotType type = EditSnapshotType.grouped,
  }) {
    _lastWasCoalesce = false;
    _truncateRedo();
    _snapshots.add(EditSnapshot(
      operations: List.from(operations),
      type: type,
      label: label,
      timestamp: DateTime.now(),
    ));
    _enforceLimit();
    notifyListeners();
  }

  void _truncateRedo() {
    if (_currentIndex < _snapshots.length - 1) {
      _snapshots.removeRange(_currentIndex + 1, _snapshots.length);
    }
  }

  void _enforceLimit() {
    if (_snapshots.length > maxSnapshots) {
      _snapshots.removeAt(0);
    } else {
      _currentIndex++;
    }
  }

  /// Undo one step. Returns the restored operations, or null if nothing
  /// to undo.
  List<EditOperation>? undo() {
    if (!canUndo) return null;
    _lastWasCoalesce = false;
    _currentIndex--;
    notifyListeners();
    return currentOperations;
  }

  /// Redo one step. Returns the restored operations, or null if nothing
  /// to redo.
  List<EditOperation>? redo() {
    if (!canRedo) return null;
    _lastWasCoalesce = false;
    _currentIndex++;
    notifyListeners();
    return currentOperations;
  }

  /// Reset to the initial state (discards all history).
  void reset() {
    _lastWasCoalesce = false;
    _snapshots.clear();
    _snapshots.add(EditSnapshot(
      operations: _initial?.operations.toList() ?? [],
      type: EditSnapshotType.discrete,
      label: 'Original',
      timestamp: DateTime.now(),
    ));
    _currentIndex = 0;
    notifyListeners();
  }

  /// Build an [EditRecipe] from the current state.
  EditRecipe buildRecipe({
    required String photoId,
    required DateTime createdAt,
  }) {
    return EditRecipe(
      photoId: photoId,
      operations: currentOperations,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      version: _initial?.version ?? 1,
      isExported: false,
    );
  }

  @override
  String toString() =>
      'EditHistoryManager(idx: $_currentIndex, snapshots: ${_snapshots.length})';
}

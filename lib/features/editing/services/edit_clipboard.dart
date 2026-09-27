import '../../../domain/models/edit/edit_operation.dart';
import '../../../domain/models/edit/edit_recipe.dart';

/// In-memory clipboard for copy/paste editing between photos.
///
/// Stores a snapshot of operations that can be pasted onto another photo.
/// The clipboard is session-scoped (lost when the app restarts).
class EditClipboard {
  EditClipboard._();

  static final EditClipboard instance = EditClipboard._();

  List<EditOperation>? _copiedOperations;
  String? _sourcePhotoId;

  /// Whether there are operations in the clipboard.
  bool get hasContent => _copiedOperations != null && _copiedOperations!.isNotEmpty;

  /// The source photo ID (for display purposes).
  String? get sourcePhotoId => _sourcePhotoId;

  /// Number of operations in the clipboard.
  int get operationCount => _copiedOperations?.length ?? 0;

  /// Copy operations from a recipe.
  void copyFrom(String photoId, EditRecipe recipe) {
    _copiedOperations = List.from(recipe.operations);
    _sourcePhotoId = photoId;
  }

  /// Copy specific operation types from a recipe.
  /// If [types] is null, copies all non-noop operations.
  void copyTypesFrom(
    String photoId,
    EditRecipe recipe, {
    List<EditOperationType>? types,
  }) {
    var ops = recipe.operations.where((op) => !op.isNoOp).toList();
    if (types != null) {
      ops = ops.where((op) => types.contains(op.type)).toList();
    }
    _copiedOperations = ops;
    _sourcePhotoId = photoId;
  }

  /// Paste the clipboard contents into a recipe, replacing matching types.
  /// Returns a new recipe with the pasted operations merged in.
  EditRecipe? pasteInto(EditRecipe target) {
    if (_copiedOperations == null) return null;
    final newOps = List<EditOperation>.from(target.operations);

    for (final copiedOp in _copiedOperations!) {
      // Remove existing operation of the same type
      newOps.removeWhere((op) => op.type == copiedOp.type);
      // Add the copied operation
      newOps.add(copiedOp);
    }

    return target.copyWith(
      operations: newOps,
      updatedAt: DateTime.now(),
    );
  }

  /// Clear the clipboard.
  void clear() {
    _copiedOperations = null;
    _sourcePhotoId = null;
  }
}

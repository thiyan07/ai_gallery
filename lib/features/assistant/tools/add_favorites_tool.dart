import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: add_favorites — Mark photos as favorites.
///
/// SAFE_WRITE. Requires single confirmation. Supports undo.
class AddFavoritesTool extends AssistantTool {
  AddFavoritesTool({required this.onAdd, this.onUndoAdd});

  final Future<int> Function(List<String> photoIds) onAdd;

  /// Callback to undo: removes the photos that were just added.
  final Future<int> Function(List<String> photoIds)? onUndoAdd;

  @override
  String get name => 'add_favorites';

  @override
  String get description => 'Add photos to favorites';

  @override
  bool get requiresConfirmation => true;

  @override
  bool get isDestructive => false;

  @override
  bool get supportsUndo => onUndoAdd != null;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.safeWrite;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final ids = parameters['photoIds'] as List?;
    if (ids == null || ids.isEmpty) {
      return 'At least one photo ID is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final photoIds = (parameters['photoIds'] as List).cast<String>();
    final added = await onAdd(photoIds);

    return ActionResult.success(
      'Added $added photo${added == 1 ? '' : 's'} to favorites.',
      data: {'added': added, 'photoIds': photoIds},
      undoReference: 'fav_add_${photoIds.join(",")}',
    );
  }

  @override
  Future<ActionResult> undo(String undoReference) async {
    if (onUndoAdd == null) {
      return ActionResult.failure('Undo not available.');
    }
    // Parse photo IDs from undo reference: "fav_add_id1,id2,id3"
    final prefix = 'fav_add_';
    if (!undoReference.startsWith(prefix)) {
      return ActionResult.failure('Invalid undo reference.');
    }
    final ids = undoReference.substring(prefix.length).split(',');
    final removed = await onUndoAdd!(ids);
    return ActionResult.success(
      'Removed $removed photo${removed == 1 ? '' : 's'} from favorites (undo).',
    );
  }
}

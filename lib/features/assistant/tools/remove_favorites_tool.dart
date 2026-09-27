import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: remove_favorites — Remove photos from favorites.
///
/// SAFE_WRITE. Requires single confirmation. Supports undo.
class RemoveFavoritesTool extends AssistantTool {
  RemoveFavoritesTool({required this.onRemove, this.onUndoRemove});

  final Future<int> Function(List<String> photoIds) onRemove;

  /// Callback to undo: re-adds the photos that were just removed.
  final Future<int> Function(List<String> photoIds)? onUndoRemove;

  @override
  String get name => 'remove_favorites';

  @override
  String get description => 'Remove photos from favorites';

  @override
  bool get requiresConfirmation => true;

  @override
  bool get isDestructive => false;

  @override
  bool get supportsUndo => onUndoRemove != null;

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
    final removed = await onRemove(photoIds);

    return ActionResult.success(
      'Removed $removed photo${removed == 1 ? '' : 's'} from favorites.',
      data: {'removed': removed, 'photoIds': photoIds},
      undoReference: 'fav_remove_${photoIds.join(",")}',
    );
  }

  @override
  Future<ActionResult> undo(String undoReference) async {
    if (onUndoRemove == null) {
      return ActionResult.failure('Undo not available.');
    }
    // Parse photo IDs from undo reference: "fav_remove_id1,id2,id3"
    final prefix = 'fav_remove_';
    if (!undoReference.startsWith(prefix)) {
      return ActionResult.failure('Invalid undo reference.');
    }
    final ids = undoReference.substring(prefix.length).split(',');
    final readded = await onUndoRemove!(ids);
    return ActionResult.success(
      'Re-added $readded photo${readded == 1 ? '' : 's'} to favorites (undo).',
    );
  }
}

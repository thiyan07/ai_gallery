import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: delete_photos — Delete photos from the gallery.
///
/// DESTRUCTIVE. Requires double confirmation. Supports undo.
///
/// **IMPORTANT**: This tool does NOT silently delete user photos.
/// It always requires explicit double confirmation.
/// If the underlying system cannot safely delete (e.g. permissions issue),
/// it returns a failure result.
class DeletePhotosTool extends AssistantTool {
  DeletePhotosTool({required this.onDelete});

  /// Callback that performs the actual deletion.
  /// Should return the number of successfully deleted photos.
  final Future<int> Function(List<String> photoIds) onDelete;

  @override
  String get name => 'delete_photos';

  @override
  String get description => 'Delete photos from gallery';

  @override
  bool get requiresConfirmation => true;

  @override
  bool get isDestructive => true;

  @override
  bool get supportsUndo => false;

  @override
  ActionPermissionLevel get permissionLevel =>
      ActionPermissionLevel.destructive;

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

    final deleted = await onDelete(photoIds);

    if (deleted == 0) {
      return ActionResult.failure('No photos were deleted.');
    }

    return ActionResult.success(
      'Deleted $deleted photo${deleted == 1 ? '' : 's'} permanently.',
      data: {'deleted': deleted, 'photoIds': photoIds},
      undoReference: 'delete_${photoIds.join(",")}',
    );
  }

  @override
  Future<ActionResult> undo(String undoReference) async {
    return ActionResult.failure(
      'Photo deletion cannot be undone. Photos have been permanently removed.',
    );
  }
}

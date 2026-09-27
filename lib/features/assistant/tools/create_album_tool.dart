import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: create_album — Create a smart album from photos.
///
/// SAFE_WRITE. Requires single confirmation.
class CreateAlbumTool extends AssistantTool {
  CreateAlbumTool({required this.onCreate, this.onDelete});

  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) onCreate;
  final Future<bool> Function(String albumId)? onDelete;

  @override
  String get name => 'create_album';

  @override
  String get description => 'Create a smart album';

  @override
  bool get requiresConfirmation => true;

  @override
  bool get isDestructive => false;

  @override
  bool get supportsUndo => onDelete != null;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.safeWrite;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final title = parameters['title'] as String?;
    if (title == null || title.trim().isEmpty) {
      return 'Album title is required';
    }
    final photoIds = parameters['photoIds'] as List?;
    if (photoIds == null || photoIds.isEmpty) {
      return 'At least one photo is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final result = await onCreate(parameters);
    final albumId = result['albumId'] as String? ?? '';
    final title = parameters['title'] as String? ?? 'Untitled';
    final photoCount = (parameters['photoIds'] as List?)?.length ?? 0;

    return ActionResult.success(
      'Created album "$title" with $photoCount photo${photoCount == 1 ? '' : 's'}.',
      data: {'albumId': albumId, 'title': title},
      undoReference: albumId,
    );
  }

  @override
  Future<ActionResult> undo(String undoReference) async {
    if (onDelete != null) {
      final success = await onDelete!(undoReference);
      if (success) {
        return ActionResult.success(
          'Album deleted.',
          data: {'albumId': undoReference},
        );
      }
      return ActionResult.failure('Failed to delete album.');
    }
    return ActionResult.success(
      'Album deleted.',
      data: {'albumId': undoReference},
    );
  }
}

import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: create_memory — Create a memory from photos.
///
/// SAFE_WRITE. Requires single confirmation.
class CreateMemoryTool extends AssistantTool {
  CreateMemoryTool({required this.onCreate, this.onDelete});

  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) onCreate;
  final Future<bool> Function(String memoryId)? onDelete;

  @override
  String get name => 'create_memory';

  @override
  String get description => 'Create a photo memory';

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
    final title = parameters['memoryTitle'] as String?;
    if (title == null || title.trim().isEmpty) {
      return 'Memory title is required';
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
    final memoryId = result['memoryId'] as String? ?? '';
    final title = parameters['memoryTitle'] as String? ?? 'My Memory';
    final photoCount = (parameters['photoIds'] as List?)?.length ?? 0;

    return ActionResult.success(
      'Created memory "$title" with $photoCount photo${photoCount == 1 ? '' : 's'}.',
      data: {'memoryId': memoryId, 'title': title},
      undoReference: memoryId,
    );
  }

  @override
  Future<ActionResult> undo(String undoReference) async {
    if (onDelete != null) {
      final success = await onDelete!(undoReference);
      if (success) {
        return ActionResult.success(
          'Memory deleted.',
          data: {'memoryId': undoReference},
        );
      }
      return ActionResult.failure('Failed to delete memory.');
    }
    return ActionResult.success(
      'Memory deleted.',
      data: {'memoryId': undoReference},
    );
  }
}

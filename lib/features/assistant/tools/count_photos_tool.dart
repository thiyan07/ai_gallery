import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: count_photos — Count photos matching given filters.
///
/// READ-only. No confirmation required.
class CountPhotosTool extends AssistantTool {
  CountPhotosTool({required this.onCount});

  final Future<int> Function(Map<String, dynamic>) onCount;

  @override
  String get name => 'count_photos';

  @override
  String get description => 'Count photos matching criteria';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) => null;

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final count = await onCount(parameters);
    final description = parameters['description'] as String? ?? 'in your gallery';

    return ActionResult.informational(
      'You have $count $description.',
      data: {'count': count, 'description': description},
    );
  }
}

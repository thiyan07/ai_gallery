import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: find_best_photos — Find highest quality photos.
///
/// READ-only. No confirmation required.
class FindBestPhotosTool extends AssistantTool {
  FindBestPhotosTool({required this.onFind});

  final Future<List<String>> Function(Map<String, dynamic>) onFind;

  @override
  String get name => 'find_best_photos';

  @override
  String get description => 'Find best quality photos';

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
    final photoIds = await onFind(parameters);

    if (photoIds.isEmpty) {
      return ActionResult.informational('No best photos found.');
    }

    return ActionResult.informational(
      'Here are your best ${photoIds.length} photo${photoIds.length == 1 ? '' : 's'}.',
      data: {'count': photoIds.length, 'sortedBy': 'quality'},
      photoIds: photoIds,
    );
  }
}

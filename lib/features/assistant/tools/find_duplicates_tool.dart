import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: find_duplicates — Find duplicate photo groups.
///
/// READ-only. No confirmation required.
class FindDuplicatesTool extends AssistantTool {
  FindDuplicatesTool({required this.onFind});

  final Future<Map<String, dynamic>> Function() onFind;

  @override
  String get name => 'find_duplicates';

  @override
  String get description => 'Find duplicate photos';

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
    final report = await onFind();

    final totalGroups = report['totalGroups'] as int? ?? 0;
    if (totalGroups == 0) {
      return ActionResult.informational(
        'No duplicate photos found in your gallery.',
        data: report,
      );
    }

    final exactGroups = report['exactGroups'] as int? ?? 0;
    final nearDuplicateGroups = report['nearDuplicateGroups'] as int? ?? 0;
    final totalPhotos = report['totalPhotos'] as int? ?? 0;
    final photoIds = (report['photoIds'] as List?)?.cast<String>() ?? [];

    return ActionResult.informational(
      'Found $totalGroups duplicate groups '
      '($exactGroups exact, $nearDuplicateGroups near-duplicate) '
      'containing $totalPhotos photos total.',
      data: report,
      photoIds: photoIds,
    );
  }
}

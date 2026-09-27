import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: filter_by_quality — Find photos by quality (blurry, sharp, screenshots).
///
/// READ-only. No confirmation required.
class FilterByQualityTool extends AssistantTool {
  FilterByQualityTool({required this.onFilter});

  final Future<List<String>> Function(Map<String, dynamic>) onFilter;

  @override
  String get name => 'filter_by_quality';

  @override
  String get description => 'Filter photos by quality criteria';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final quality = parameters['quality'] as String?;
    if (quality == null || quality.isEmpty) {
      return 'Quality filter is required (blurry, sharp, screenshot)';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final photoIds = await onFilter(parameters);
    final quality = parameters['quality'] as String? ?? 'quality-filtered';

    if (photoIds.isEmpty) {
      return ActionResult.informational(
        'No $quality photos found.',
        data: {'quality': quality, 'count': 0},
      );
    }

    return ActionResult.informational(
      'Found ${photoIds.length} $quality photo${photoIds.length == 1 ? '' : 's'}.',
      data: {'quality': quality, 'count': photoIds.length},
      photoIds: photoIds,
    );
  }
}

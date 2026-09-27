import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: search_photos — Search gallery by text, date, person, object, etc.
///
/// READ-only. No confirmation required.
class SearchPhotosTool extends AssistantTool {
  SearchPhotosTool({required this.onSearch});

  final Future<List<String>> Function(Map<String, dynamic>) onSearch;

  @override
  String get name => 'search_photos';

  @override
  String get description => 'Search photos in gallery';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final query = parameters['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return 'Search query is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final photoIds = await onSearch(parameters);
    final query = parameters['query'] as String? ?? '';

    if (photoIds.isEmpty) {
      return ActionResult.informational(
        'No photos found for "$query".',
        data: {'query': query, 'count': 0},
      );
    }

    return ActionResult.informational(
      'Found ${photoIds.length} photo${photoIds.length == 1 ? '' : 's'} for "$query".',
      data: {'query': query, 'count': photoIds.length},
      photoIds: photoIds,
    );
  }
}

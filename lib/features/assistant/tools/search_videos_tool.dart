import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: search_videos — Search for moments within videos.
///
/// READ-only. No confirmation required.
class SearchVideosTool extends AssistantTool {
  SearchVideosTool({required this.onSearch});

  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>)
      onSearch;

  @override
  String get name => 'search_videos';

  @override
  String get description => 'Search for moments in videos';

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
    final results = await onSearch(parameters);
    final query = parameters['query'] as String? ?? '';

    if (results.isEmpty) {
      return ActionResult.informational(
        'No video moments found for "$query".',
        data: {'query': query, 'count': 0},
      );
    }

    final buffer = StringBuffer(
      'Found ${results.length} video moment${results.length == 1 ? '' : 's'} for "$query":',
    );

    final photoIds = <String>[];
    for (final r in results.take(5)) {
      final photoId = r['photoId'] as String? ?? '';
      final timestamp = r['timestamp'] as String? ?? '';
      final score = r['score'] as double? ?? 0;
      photoIds.add(photoId);
      buffer.write('\n  - $photoId${timestamp.isNotEmpty ? ' at $timestamp' : ''} (score: ${(score * 100).round()}%)');
    }

    return ActionResult.informational(
      buffer.toString(),
      data: {'query': query, 'count': results.length},
      photoIds: photoIds,
    );
  }
}

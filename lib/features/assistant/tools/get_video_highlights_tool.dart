import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: get_video_highlights — Get highlight moments from a video.
///
/// READ-only. No confirmation required.
class GetVideoHighlightsTool extends AssistantTool {
  GetVideoHighlightsTool({required this.onGetHighlights});

  final Future<List<Map<String, dynamic>>> Function(String videoId)
      onGetHighlights;

  @override
  String get name => 'get_video_highlights';

  @override
  String get description =>
      'Find the most interesting or noteworthy moments in a video';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final videoId = parameters['videoId'] as String?;
    if (videoId == null || videoId.trim().isEmpty) {
      return 'videoId is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final videoId = parameters['videoId'] as String;
    final highlights = await onGetHighlights(videoId);

    if (highlights.isEmpty) {
      return ActionResult.informational(
        'No highlight moments detected in this video yet.',
        data: {'videoId': videoId, 'count': 0},
      );
    }

    final buffer = StringBuffer(
      '${highlights.length} highlight${highlights.length == 1 ? '' : 's'}:',
    );

    for (final h in highlights.take(10)) {
      final score = h['score'] as double? ?? 0;
      final reason = h['reason'] as String? ?? '';
      final start = h['startTime'] as String? ?? '';
      final end = h['endTime'] as String? ?? '';
      buffer.write(
        '\n  [$start-$end] '
        '(${(score * 100).round()}%) $reason',
      );
    }

    return ActionResult.informational(
      buffer.toString(),
      data: {
        'videoId': videoId,
        'count': highlights.length,
        'highlights': highlights,
      },
      photoIds: [videoId],
    );
  }
}

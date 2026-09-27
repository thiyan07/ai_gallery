import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: get_video_chapters — Get navigation chapters for a video.
///
/// READ-only. No confirmation required.
class GetVideoChaptersTool extends AssistantTool {
  GetVideoChaptersTool({required this.onGetChapters});

  final Future<List<Map<String, dynamic>>> Function(String videoId)
      onGetChapters;

  @override
  String get name => 'get_video_chapters';

  @override
  String get description =>
      'Get chapter markers for a video to understand its structure';

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
    final chapters = await onGetChapters(videoId);

    if (chapters.isEmpty) {
      return ActionResult.informational(
        'No chapters available for this video yet.',
        data: {'videoId': videoId, 'count': 0},
      );
    }

    final buffer = StringBuffer(
      '${chapters.length} chapter${chapters.length == 1 ? '' : 's'}:',
    );

    for (final ch in chapters) {
      final title = ch['title'] as String? ?? 'Untitled';
      final time = ch['time'] as String? ?? '';
      buffer.write('\n  [$time] $title');
    }

    return ActionResult.informational(
      buffer.toString(),
      data: {'videoId': videoId, 'count': chapters.length, 'chapters': chapters},
      photoIds: [videoId],
    );
  }
}

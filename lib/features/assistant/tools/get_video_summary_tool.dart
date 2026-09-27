import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: get_video_summary — Get a structured summary of a video.
///
/// READ-only. No confirmation required.
class GetVideoSummaryTool extends AssistantTool {
  GetVideoSummaryTool({required this.onGetSummary});

  final Future<Map<String, dynamic>?> Function(String videoId) onGetSummary;

  @override
  String get name => 'get_video_summary';

  @override
  String get description =>
      'Get a summary of a video including people, objects, and key moments';

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
    final summary = await onGetSummary(videoId);

    if (summary == null) {
      return ActionResult.informational(
        'No analysis summary available for this video yet.',
        data: {'videoId': videoId},
      );
    }

    final buffer = StringBuffer('Video summary:');
    final duration = summary['duration'] as String? ?? '';
    if (duration.isNotEmpty) buffer.write(' Duration: $duration');

    final sceneCount = summary['scene_count'] as int? ?? 0;
    buffer.write('\n  Scenes: $sceneCount');

    final people = summary['people'] as List<dynamic>? ?? [];
    if (people.isNotEmpty) {
      buffer.write('\n  People: ${people.join(', ')}');
    }

    final objects = summary['object_labels'] as List<dynamic>? ?? [];
    if (objects.isNotEmpty) {
      buffer.write('\n  Objects: ${objects.join(', ')}');
    }

    final ocrTexts = summary['ocr_texts'] as List<dynamic>? ?? [];
    if (ocrTexts.isNotEmpty) {
      buffer.write('\n  Text visible: ${ocrTexts.take(3).join('; ')}');
    }

    final highlightCount = summary['highlight_count'] as int? ?? 0;
    if (highlightCount > 0) {
      buffer.write('\n  Highlights: $highlightCount');
    }

    final hasAudio = summary['has_audio'] as bool? ?? false;
    buffer.write('\n  Audio: ${hasAudio ? "Yes" : "No"}');

    return ActionResult.informational(
      buffer.toString(),
      data: {'videoId': videoId, 'summary': summary},
      photoIds: [videoId],
    );
  }
}

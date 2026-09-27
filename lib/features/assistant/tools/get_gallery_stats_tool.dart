import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: get_gallery_stats — Get overview statistics of the gallery.
///
/// READ-only. No confirmation required.
class GetGalleryStatsTool extends AssistantTool {
  GetGalleryStatsTool({required this.onGetStats});

  final Future<Map<String, dynamic>> Function() onGetStats;

  @override
  String get name => 'get_gallery_stats';

  @override
  String get description => 'Get gallery overview statistics';

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
    final stats = await onGetStats();

    final total = stats['totalPhotos'] as int? ?? 0;
    final videos = stats['totalVideos'] as int? ?? 0;
    final favorites = stats['favorites'] as int? ?? 0;
    final people = stats['people'] as int? ?? 0;
    final events = stats['events'] as int? ?? 0;
    final memories = stats['memories'] as int? ?? 0;
    final blurry = stats['blurry'] as int? ?? 0;
    final screenshots = stats['screenshots'] as int? ?? 0;
    final duplicates = stats['duplicateGroups'] as int? ?? 0;

    final buffer = StringBuffer('Here\'s your gallery overview:\n\n');
    buffer.write('$total photos');
    if (videos > 0) buffer.write(' and $videos videos');
    buffer.write(' in total.\n\n');

    if (favorites > 0) buffer.write('$favorites favorites\n');
    if (people > 0) buffer.write('$people people recognized\n');
    if (events > 0) buffer.write('$events events detected\n');
    if (memories > 0) buffer.write('$memories memories created\n');
    if (blurry > 0) buffer.write('$blurry blurry photos\n');
    if (screenshots > 0) buffer.write('$screenshots screenshots\n');
    if (duplicates > 0) buffer.write('$duplicates duplicate groups\n');

    return ActionResult.informational(
      buffer.toString().trimRight(),
      data: stats,
    );
  }
}

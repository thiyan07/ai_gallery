import '../services/tool_interface.dart';
import '../models/action_state.dart';

/// Tool: open_photo — Navigate to a specific photo.
///
/// READ-only. No confirmation required. Produces a navigation result.
class OpenPhotoTool extends AssistantTool {
  @override
  String get name => 'open_photo';

  @override
  String get description => 'Open a photo';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final photoId = parameters['photoId'] as String?;
    if (photoId == null || photoId.isEmpty) {
      return 'photoId is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final photoId = parameters['photoId'] as String;
    return ActionResult.navigation(
      'Opening photo $photoId.',
      data: {'photoId': photoId},
    );
  }
}

/// Tool: open_person — Navigate to a person's profile.
///
/// READ-only. No confirmation required. Produces a navigation result.
class OpenPersonTool extends AssistantTool {
  @override
  String get name => 'open_person';

  @override
  String get description => 'Open a person\'s profile';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final personId = parameters['personId'] as String?;
    final personName = parameters['personName'] as String?;
    if (personId == null && personName == null) {
      return 'personId or personName is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final name = parameters['personName'] as String? ??
        parameters['personId'] as String? ??
        'unknown';
    return ActionResult.navigation(
      'Opening profile for $name.',
      data: {
        'personId': parameters['personId'],
        'personName': parameters['personName'],
      },
    );
  }
}

/// Tool: open_event — Navigate to an event.
///
/// READ-only. No confirmation required. Produces a navigation result.
class OpenEventTool extends AssistantTool {
  @override
  String get name => 'open_event';

  @override
  String get description => 'Open an event';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final eventId = parameters['eventId'] as String?;
    if (eventId == null || eventId.isEmpty) {
      return 'eventId is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final eventId = parameters['eventId'] as String;
    return ActionResult.navigation(
      'Opening event $eventId.',
      data: {'eventId': eventId},
    );
  }
}

/// Tool: open_album — Navigate to an album.
///
/// READ-only. No confirmation required. Produces a navigation result.
class OpenAlbumTool extends AssistantTool {
  @override
  String get name => 'open_album';

  @override
  String get description => 'Open an album';

  @override
  bool get requiresConfirmation => false;

  @override
  bool get isDestructive => false;

  @override
  ActionPermissionLevel get permissionLevel => ActionPermissionLevel.read;

  @override
  String? validate(Map<String, dynamic> parameters) {
    final albumId = parameters['albumId'] as String?;
    if (albumId == null || albumId.isEmpty) {
      return 'albumId is required';
    }
    return null;
  }

  @override
  Future<ActionResult> execute(Map<String, dynamic> parameters) async {
    final albumId = parameters['albumId'] as String;
    return ActionResult.navigation(
      'Opening album $albumId.',
      data: {'albumId': albumId},
    );
  }
}

/// Tool: open_editor — Open the photo editor.
///
/// READ-only. No confirmation required. Produces a navigation result.
class OpenEditorTool extends AssistantTool {
  @override
  String get name => 'open_editor';

  @override
  String get description => 'Open photo editor';

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
    final photoId = parameters['photoId'] as String?;
    return ActionResult.navigation(
      'Opening photo editor.',
      data: {'photoId': photoId},
    );
  }
}

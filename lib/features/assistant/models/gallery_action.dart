/// Safe typed actions the gallery assistant can recommend or execute.
///
/// Actions are NEVER executed automatically. They are presented to the
/// user for confirmation before execution.
enum GalleryActionType {
  /// Show search results.
  showSearchResults,

  /// Open a specific photo.
  openPhoto,

  /// Open a person's profile.
  openPerson,

  /// Open an event.
  openEvent,

  /// Open an album.
  openAlbum,

  /// Create a smart album from a query.
  createSmartAlbum,

  /// Create a memory from photos.
  createMemory,

  /// Open the editor with a preconfigured operation.
  openEditor,

  /// Delete photos (requires confirmation).
  deletePhotos,

  /// Mark photos as favorites.
  addFavorites,

  /// Remove photos from favorites.
  removeFavorites,
}

/// A structured action with typed parameters.
///
/// The assistant generates these. The UI presents them for user confirmation.
/// The action executor runs them only after explicit user approval.
class GalleryAction {
  final GalleryActionType type;
  final Map<String, dynamic> parameters;
  final String description;
  final bool requiresConfirmation;
  final bool isDestructive;

  const GalleryAction({
    required this.type,
    required this.parameters,
    required this.description,
    this.requiresConfirmation = true,
    this.isDestructive = false,
  });

  /// Photo IDs this action applies to.
  List<String> get photoIds =>
      (parameters['photoIds'] as List<dynamic>?)?.cast<String>() ?? [];

  /// The photo ID to open.
  String? get targetPhotoId => parameters['photoId'] as String?;

  /// The person ID to open.
  String? get targetPersonId => parameters['personId'] as String?;

  /// The event ID to open.
  String? get targetEventId => parameters['eventId'] as String?;

  /// The album ID to open.
  String? get targetAlbumId => parameters['albumId'] as String?;

  /// Smart album title for creation.
  String? get albumTitle => parameters['title'] as String?;

  /// Memory title for creation.
  String? get memoryTitle => parameters['memoryTitle'] as String?;
}

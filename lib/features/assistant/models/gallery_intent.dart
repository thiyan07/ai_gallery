/// Types of user intents the gallery assistant can handle.
///
/// Extends the search SearchIntent with gallery-specific operations
/// like counting, statistics, creation, and explanation.
enum GalleryIntent {
  /// Search for photos matching criteria.
  search,

  /// Count photos matching criteria.
  count,

  /// Get gallery statistics.
  statistics,

  /// Find similar photos.
  similar,

  /// Find related photos.
  related,

  /// Find photos of a specific person.
  person,

  /// Find photos from a specific event.
  event,

  /// Find photos with specific objects.
  object,

  /// Find photos with specific scenes.
  scene,

  /// Find photos with OCR text.
  textSearch,

  /// Find photos by quality (blurry, sharp, etc.).
  quality,

  /// Find photos by date.
  date,

  /// Find photos by location.
  location,

  /// Explain why a photo appeared in results.
  explanation,

  /// Create an album from current results.
  createAlbum,

  /// Create a memory from current results.
  createMemory,

  /// Find duplicate photos.
  duplicates,

  /// Find best photos from a set.
  bestPhotos,

  /// Open a specific photo.
  openPhoto,

  /// Open a specific person.
  openPerson,

  /// Open a specific event.
  openEvent,

  /// Edit a photo.
  editPhoto,

  /// Get photo details/summary.
  photoDetails,

  /// Get event summary.
  eventSummary,

  /// Multi-step request (search + action).
  multiStep,

  /// Search within videos (temporal search — find specific moments).
  videoSearch,

  /// Find people who appear with a specific person.
  personCoOccurrences,

  /// Find events a person attended.
  personEvents,

  /// Find places a person has visited.
  personPlaces,

  /// Find people at a specific event.
  eventPeople,

  /// Greeting or general conversation.
  greeting,

  /// Add photos to favorites (batch action on previous results).
  addToFavorites,

  /// Remove photos from favorites (batch action on previous results).
  removeFromFavorites,

  /// Delete photos (batch action on previous results).
  deletePhotos,

  /// Clear or unknown intent.
  unknown,
}

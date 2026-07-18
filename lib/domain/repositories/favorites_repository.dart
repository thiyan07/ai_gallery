/// Repository for managing photo favorites.
abstract class FavoritesRepository {
  /// Returns all favorited photo asset IDs.
  Future<Set<String>> getAllFavoriteIds();

  /// Adds a photo to favorites.
  Future<void> add(String assetId);

  /// Removes a photo from favorites.
  Future<void> remove(String assetId);

  /// Toggles favorite status and returns the new state.
  Future<bool> toggle(String assetId);

  /// Checks if a photo is favorited.
  Future<bool> isFavorite(String assetId);
}

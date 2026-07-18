import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/favorites_service.dart';

/// Manages the set of favorited asset IDs, backed by SQLite.
final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);

class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => FavoritesService.getAllFavoriteIds();

  /// Toggles the favorite status of the given asset.
  Future<void> toggle(String assetId) async {
    final current = state.value ?? {};
    if (current.contains(assetId)) {
      await FavoritesService.remove(assetId);
      state = AsyncData({...current}..remove(assetId));
    } else {
      await FavoritesService.add(assetId);
      state = AsyncData({...current, assetId});
    }
  }

  /// Returns true if the asset is currently favorited.
  bool isFavorite(String assetId) {
    return state.value?.contains(assetId) ?? false;
  }
}

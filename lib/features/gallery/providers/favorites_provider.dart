import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../domain/repositories/favorites_repository.dart';

/// Manages the set of favorited asset IDs, backed by SQLite.
final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);

class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  late final FavoritesRepository _repository;

  @override
  Future<Set<String>> build() async {
    _repository = await ref.watch(favoritesRepositoryProvider.future);
    return _repository.getAllFavoriteIds();
  }

  /// Toggles the favorite status of the given asset.
  Future<void> toggle(String assetId) async {
    final current = state.value ?? {};
    if (current.contains(assetId)) {
      await _repository.remove(assetId);
      state = AsyncData({...current}..remove(assetId));
    } else {
      await _repository.add(assetId);
      state = AsyncData({...current, assetId});
    }
  }

  /// Returns true if the asset is currently favorited.
  bool isFavorite(String assetId) {
    return state.value?.contains(assetId) ?? false;
  }
}

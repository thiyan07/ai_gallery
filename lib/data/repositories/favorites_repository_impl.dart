import '../datasources/local_favorites_datasource.dart';
import '../../domain/repositories/favorites_repository.dart';

/// SQLite-backed implementation of [FavoritesRepository].
class FavoritesRepositoryImpl implements FavoritesRepository {
  FavoritesRepositoryImpl(this._dataSource);

  final LocalFavoritesDataSource _dataSource;

  @override
  Future<Set<String>> getAllFavoriteIds() => _dataSource.getAllIds();

  @override
  Future<void> add(String assetId) => _dataSource.add(assetId);

  @override
  Future<void> remove(String assetId) => _dataSource.remove(assetId);

  @override
  Future<bool> toggle(String assetId) async {
    final isFav = await _dataSource.isFavorite(assetId);
    if (isFav) {
      await _dataSource.remove(assetId);
      return false;
    } else {
      await _dataSource.add(assetId);
      return true;
    }
  }

  @override
  Future<bool> isFavorite(String assetId) => _dataSource.isFavorite(assetId);
}

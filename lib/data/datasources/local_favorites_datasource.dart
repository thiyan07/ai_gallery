import '../../core/database/app_database.dart';

/// Local SQLite data source for favorites.
class LocalFavoritesDataSource {
  LocalFavoritesDataSource(this._database);

  final AppDatabase _database;

  Future<void> add(String assetId) => _database.favorites.add(assetId);

  Future<void> remove(String assetId) => _database.favorites.remove(assetId);

  Future<Set<String>> getAllIds() => _database.favorites.getAllIds();

  Future<bool> isFavorite(String assetId) =>
      _database.favorites.isFavorite(assetId);
}

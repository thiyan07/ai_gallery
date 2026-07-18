import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/ai_manager.dart';
import '../../features/indexing/services/image_scanner.dart';
import '../../features/indexing/services/indexing_engine.dart';
import '../../features/indexing/services/metadata_extractor.dart';
import '../../data/datasources/device_media_datasource.dart';
import '../../data/datasources/local_favorites_datasource.dart';
import '../../data/repositories/device_photo_repository.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/photo_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../database/app_database.dart';
import '../jobs/background_job_queue.dart';
import '../logging/app_logger.dart';
import '../storage/secure_storage_service.dart';
import '../storage/storage_service.dart';

// ─────────────────────────────────────────────
// Core services
// ─────────────────────────────────────────────

/// Raw SharedPreferences instance — must be overridden in main().
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'Initialize SharedPreferences in main and override sharedPreferencesProvider',
  );
});

/// Application-wide logger.
final appLoggerProvider = Provider<AppLogger>((ref) {
  return const ConsoleAppLogger();
});

/// SharedPreferences-backed storage service.
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(sharedPreferencesProvider));
});

/// Secure storage for API keys.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// SQLite database singleton.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  return AppDatabase.open(logger: logger);
});

// ─────────────────────────────────────────────
// Data sources
// ─────────────────────────────────────────────

final deviceMediaDataSourceProvider = Provider<DeviceMediaDataSource>((ref) {
  return DeviceMediaDataSource(logger: ref.watch(appLoggerProvider));
});

final localFavoritesDataSourceProvider =
    FutureProvider<LocalFavoritesDataSource>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return LocalFavoritesDataSource(db);
});

// ─────────────────────────────────────────────
// Repositories
// ─────────────────────────────────────────────

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl(ref.watch(storageServiceProvider));
});

final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  return DevicePhotoRepository(
    dataSource: ref.watch(deviceMediaDataSourceProvider),
  );
});

final favoritesRepositoryProvider =
    FutureProvider<FavoritesRepository>((ref) async {
  final dataSource = await ref.watch(localFavoritesDataSourceProvider.future);
  return FavoritesRepositoryImpl(dataSource);
});

// ─────────────────────────────────────────────
// Background jobs & AI
// ─────────────────────────────────────────────

final backgroundJobQueueProvider =
    FutureProvider<BackgroundJobQueue>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final logger = ref.watch(appLoggerProvider);
  return BackgroundJobQueue(database: db, logger: logger);
});

final aiManagerProvider = FutureProvider<AIManager>((ref) async {
  final jobQueue = await ref.watch(backgroundJobQueueProvider.future);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return AIManagerImpl(
    jobQueue: jobQueue,
    secureStorage: secureStorage,
    settingsProvider: settingsRepo.getSettings,
  );
});

// ─────────────────────────────────────────────
// Indexing engine
// ─────────────────────────────────────────────

final metadataExtractorProvider = Provider<MetadataExtractor>((ref) {
  return MetadataExtractor(logger: ref.watch(appLoggerProvider));
});

final imageScannerProvider = FutureProvider<ImageScanner>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ImageScanner(
    metadataDao: db.photoMetadata,
    logger: ref.watch(appLoggerProvider),
  );
});

final indexingEngineProvider = FutureProvider<IndexingEngine>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final scanner = await ref.watch(imageScannerProvider.future);
  final extractor = ref.watch(metadataExtractorProvider);
  return IndexingEngine(
    db: db,
    scanner: scanner,
    extractor: extractor,
    logger: ref.watch(appLoggerProvider),
  );
});

// ─────────────────────────────────────────────
// User settings snapshot
// ─────────────────────────────────────────────

/// Current user settings from the repository.
final userSettingsProvider = Provider((ref) {
  return ref.watch(settingsRepositoryProvider).getSettings();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/ai_manager.dart';
import '../../ai/providers/embedding_provider.dart';
import '../../ai/providers/local_embedding_provider.dart';
import '../../ai/providers/local_object_detection_provider.dart';
import '../../ai/providers/object_detection_provider.dart';
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
import '../../domain/models/user_settings.dart';
import '../database/app_database.dart';
import '../jobs/background_job_queue.dart';
import '../logging/app_logger.dart';
import '../storage/storage_service.dart';
import '../storage/secure_storage_service.dart';
import '../services/model_downloader.dart';
import '../services/model_manager.dart';

// Provider for raw SharedPreferences instance - initialized in main.dart
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'Initialize SharedPreferences in main and override this provider',
  );
});

// ─────────────────────────────────────────────
// Core services
// ─────────────────────────────────────────────

/// Application-wide logger.
final appLoggerProvider = Provider<AppLogger>((ref) {
  return const ConsoleAppLogger();
});

/// SQLite database singleton.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  return AppDatabase.open(logger: logger);
});

/// Storage service for app settings (SharedPreferences wrapper).
final storageServiceProvider = Provider<StorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StorageService(prefs);
});

/// Secure storage service for API keys.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
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

/// Current user settings from the repository.
final userSettingsProvider = Provider((ref) {
  return ref.watch(settingsRepositoryProvider).getSettings();
});

/// Embedding provider (local or cloud based on settings).
final embeddingProviderProvider = FutureProvider<EmbeddingProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);

  if (settings.aiMode == AiMode.local) {
    final modelManager = ref.watch(modelManagerProvider);
    return LocalEmbeddingProvider(
      logger: logger,
      modelManager: modelManager,
    );
  }

  // TODO: Add cloud providers (OpenAI, Google Vision, Anthropic)
  // For hybrid/BYOK modes, return appropriate cloud provider
  // if (settings.aiMode == AiMode.byok || settings.aiMode == AiMode.hybrid) {
  //   return CloudEmbeddingProvider(...);
  // }

  return null;
});

final aiManagerProvider = FutureProvider<AIManager>((ref) async {
  final jobQueue = await ref.watch(backgroundJobQueueProvider.future);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final photoRepo = ref.watch(photoRepositoryProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final logger = ref.watch(appLoggerProvider);

  // Resolve providers from future providers
  final embeddingProvider = await ref.watch(embeddingProviderProvider.future);
  final objectDetectionProvider = await ref.watch(objectDetectionProviderProvider.future);

  return AIManagerImpl(
    jobQueue: jobQueue,
    secureStorage: secureStorage,
    settingsProvider: settingsRepo.getSettings,
    embeddingProvider: () => embeddingProvider,
    objectDetectionProvider: () => objectDetectionProvider,
    photoRepository: photoRepo,
    database: db,
    logger: logger,
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
  final aiManager = await ref.watch(aiManagerProvider.future);
  return IndexingEngine(
    db: db,
    scanner: scanner,
    extractor: extractor,
    aiManager: aiManager,
    logger: ref.watch(appLoggerProvider),
  );
});

// ─────────────────────────────────────────────
// Model Management
// ─────────────────────────────────────────────

/// Provider that initializes the model downloader on app startup.
final modelDownloaderInitializerProvider = FutureProvider<void>((ref) async {
  final downloader = ref.watch(modelDownloaderProvider);
  await downloader.initialize();
});

/// Model downloader service.
final modelDownloaderProvider = Provider<ModelDownloader>((ref) {
  final logger = ref.watch(appLoggerProvider);
  return ModelDownloader(logger: logger);
});

/// Model manager for selecting and managing ONNX models.
final modelManagerProvider = Provider<ModelManager>((ref) {
  final downloader = ref.watch(modelDownloaderProvider);
  final logger = ref.watch(appLoggerProvider);
  return ModelManager(downloader: downloader, logger: logger);
});

// ─────────────────────────────────────────────
// AI Object Detection
// ─────────────────────────────────────────────

/// Object detection provider (local YOLO via ONNX).
final objectDetectionProviderProvider = FutureProvider<ObjectDetectionProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);

  if (settings.aiMode == AiMode.local) {
    final modelManager = ref.watch(modelManagerProvider);
    final provider = LocalObjectDetectionProvider(
      logger: logger,
      modelManager: modelManager,
    );
    await provider.initialize();
    return provider;
  }

  return NullObjectDetectionProvider();
});

// ─────────────────────────────────────────────
// AI Embeddings & Search - Defined in features/search/providers/search_providers.dart
// ─────────────────────────────────────────────
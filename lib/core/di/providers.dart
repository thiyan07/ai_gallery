import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../ai/ai_manager.dart';
import '../../ai/providers/embedding_provider.dart';
import '../../ai/providers/local_embedding_provider.dart';
import '../../ai/providers/openai_embedding_provider.dart';
import '../../ai/providers/google_vision_provider.dart';
import '../../ai/providers/anthropic_embedding_provider.dart';
import '../../ai/providers/ocr_provider.dart';
import '../../ai/providers/local_object_detection_provider.dart';
import '../../ai/providers/object_detection_provider.dart';
import '../../ai/providers/blazeface_provider.dart';
import '../../ai/providers/face_embedding_provider.dart';
import '../../ai/providers/face_detection_provider.dart';
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
import '../../domain/models/ai_job.dart';
import '../database/app_database.dart';
import '../jobs/background_job_queue.dart';
import '../jobs/background_job_worker.dart';
import '../logging/app_logger.dart';
import '../storage/storage_service.dart';
import '../storage/secure_storage_service.dart';
import '../services/model_downloader.dart';
import '../services/model_manager.dart';
import '../utils/device_capabilities.dart';

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

/// Database file path for the worker isolate.
final databasePathProvider = FutureProvider<String>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return db.database.path;
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

/// Models directory path for the worker isolate.
final modelsDirProvider = FutureProvider<String>((ref) async {
  final downloader = ref.watch(modelDownloaderProvider);
  await downloader.initialize();
  final appDir = await getApplicationDocumentsDirectory();
  return p.join(appDir.path, 'models');
});

/// User settings as JSON for worker isolate.
final userSettingsJsonProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsRepositoryProvider).getSettings();
  return settings.toJsonString();
});

/// Background job queue using isolate worker.
final backgroundJobQueueProvider = FutureProvider<BackgroundJobQueue>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final logger = ref.watch(appLoggerProvider);
  final databasePath = await ref.watch(databasePathProvider.future);
  final modelsDir = await ref.watch(modelsDirProvider.future);
  final settingsJson = ref.watch(userSettingsJsonProvider);

  final queue = BackgroundJobQueue(
    database: db,
    logger: logger,
    databasePath: databasePath,
    modelsDir: modelsDir,
    settingsJson: settingsJson,
  );

  await queue.initialize();
  return queue;
});

/// Provider for pending AI jobs.
final pendingJobsProvider = FutureProvider<List<AIJob>>((ref) async {
  final jobQueue = await ref.watch(backgroundJobQueueProvider.future);
  final jobs = await jobQueue.getAllJobs();
  return jobs.where((j) => j.status == AIJobStatus.pending).toList();
});

/// Provider for failed AI jobs.
final failedJobsProvider = FutureProvider<List<AIJob>>((ref) async {
  final jobQueue = await ref.watch(backgroundJobQueueProvider.future);
  final jobs = await jobQueue.getAllJobs();
  return jobs.where((j) => j.status == AIJobStatus.failed).toList();
});

/// Worker status stream.
final workerStatusProvider = StreamProvider<WorkerStatus?>((ref) async* {
  final jobQueue = await ref.watch(backgroundJobQueueProvider.future);
  yield* jobQueue.watchWorkerStatus();
});

/// Current user settings from the repository.
final userSettingsProvider = Provider((ref) {
  return ref.watch(settingsRepositoryProvider).getSettings();
});

/// Embedding provider (local or cloud based on settings).
final embeddingProviderProvider = FutureProvider<EmbeddingProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);

  switch (settings.aiMode) {
    case AiMode.local:
      final modelManager = ref.watch(modelManagerProvider);
      return LocalEmbeddingProvider(
        logger: logger,
        modelManager: modelManager,
        modelAssetPath: 'assets/models/siglip_base_patch16_224.onnx',
        textModelAssetPath: 'assets/models/siglip_text_encoder.onnx',
        tokenizerAssetPath: 'assets/models/siglip_tokenizer.model',
      );

    case AiMode.byok:
    case AiMode.hybrid:
      // For BYOK and Hybrid modes, try to use cloud providers if API keys are configured
      final secureStorage = ref.watch(secureStorageServiceProvider);

      // Try OpenAI first
      final openaiKey = await secureStorage.getOpenAIKey();
      if (openaiKey != null && openaiKey.isNotEmpty) {
        return OpenAIEmbeddingProvider(
          logger: logger,
          secureStorage: secureStorage,
          model: 'text-embedding-3-small',
        );
      }

      // Try Google Vision
      final visionKey = await secureStorage.getGoogleVisionKey();
      if (visionKey != null && visionKey.isNotEmpty) {
        return GoogleVisionProvider(
          logger: logger,
          secureStorage: secureStorage,
        );
      }

      // Try Anthropic
      final anthropicKey = await secureStorage.getAnthropicKey();
      if (anthropicKey != null && anthropicKey.isNotEmpty) {
        return AnthropicEmbeddingProvider(
          logger: logger,
          secureStorage: secureStorage,
        );
      }

      // Fall back to local if no cloud keys configured
      logger.warning('No cloud API keys configured, falling back to local embedding');
      final modelManager = ref.watch(modelManagerProvider);
      return LocalEmbeddingProvider(
        logger: logger,
        modelManager: modelManager,
        // Don't pass asset paths - let LocalEmbeddingProvider handle tier-appropriate fallbacks
        // This prevents loading huge SigLIP models on low/mid tier devices
      );
  }
});

final aiManagerProvider = FutureProvider<AIManager>((ref) async {
  final jobQueue = await ref.watch(backgroundJobQueueProvider.future);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final photoRepo = ref.watch(photoRepositoryProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final logger = ref.watch(appLoggerProvider);

  // Resolve providers from future providers
  final embeddingProvider = await ref.watch(embeddingProviderProvider.future);
  final objectDetectionProvider = await ref.watch(objectDetectionProviderProvider.future);
  final faceDetectionProvider = await ref.watch(faceDetectionProviderProvider.future);
  final faceEmbeddingProvider = await ref.watch(faceEmbeddingProviderProvider.future);

  return AIManagerImpl(
    jobQueue: jobQueue,
    settingsProvider: settingsRepo.getSettings,
    embeddingProvider: () => embeddingProvider,
    faceEmbeddingProvider: () => faceEmbeddingProvider,
    objectDetectionProvider: () => objectDetectionProvider,
    faceDetectionProvider: () => faceDetectionProvider,
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

/// Object detection provider (local YOLO via ONNX or cloud via Google Vision).
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

  // For BYOK and Hybrid modes, try cloud providers
  final secureStorage = ref.watch(secureStorageServiceProvider);

  // Try Google Vision (supports object detection and OCR)
  final visionKey = await secureStorage.getGoogleVisionKey();
  if (visionKey != null && visionKey.isNotEmpty) {
    final provider = GoogleVisionProvider(
      logger: logger,
      secureStorage: secureStorage,
    );
    await provider.initialize();
    return provider;
  }

  // Fall back to null provider if no cloud keys configured
  logger.warning('No cloud API keys configured for object detection, disabling');
  return NullObjectDetectionProvider();
});

// ─────────────────────────────────────────────
// AI Face Detection
// ─────────────────────────────────────────────

/// Face detection provider (local BlazeFace via ONNX).
final faceDetectionProviderProvider = FutureProvider<FaceDetectionProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);

  if (settings.aiMode == AiMode.local) {
    final modelManager = ref.watch(modelManagerProvider);
    final provider = BlazeFaceProvider(
      logger: logger,
      modelManager: modelManager,
      modelVariant: 'short_range', // 128x128 for speed
      confidenceThreshold: 0.5,
      iouThreshold: 0.3,
      maxFaces: 10,
    );
    await provider.initialize();
    return provider;
  }

  // For BYOK and Hybrid modes, try cloud providers (Google Vision)
  final secureStorage = ref.watch(secureStorageServiceProvider);

  final visionKey = await secureStorage.getGoogleVisionKey();
  if (visionKey != null && visionKey.isNotEmpty) {
    final provider = GoogleVisionProvider(
      logger: logger,
      secureStorage: secureStorage,
    );
    await provider.initialize();
    return provider;
  }

  // Fall back to null provider if no cloud keys configured
  logger.warning('No cloud API keys configured for face detection, disabling');
  return NullFaceDetectionProvider();
});

// ─────────────────────────────────────────────
// AI Face Embedding
// ─────────────────────────────────────────────

/// Face embedding provider (local MobileFaceNet/ArcFace via ONNX).
final faceEmbeddingProviderProvider = FutureProvider<EmbeddingProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);

  if (settings.aiMode == AiMode.local) {
    final modelManager = ref.watch(modelManagerProvider);
    // Use MobileFaceNet for speed on mobile, ArcFace for quality
    final isHighEnd = (await DeviceCapabilities.instance).tier.index >= DeviceTier.high.index;

    final provider = FaceEmbeddingProvider(
      logger: logger,
      modelManager: modelManager,
      modelVariant: isHighEnd ? 'arcface_r18' : 'mobilefacenet',
    );
    await provider.initialize();
    return provider;
  }

  // For BYOK and Hybrid modes - we could use cloud face recognition APIs
  // For now, disable (would need different API)
  logger.warning('Face embedding only available in local mode');
  return null;
});

// ─────────────────────────────────────────────
// AI OCR (PaddleOCR)
// ─────────────────────────────────────────────

/// OCR provider (local PaddleOCR via ONNX or cloud via Google Vision).
final ocrProviderProvider = FutureProvider<ObjectDetectionProvider?>((ref) async {
  final logger = ref.watch(appLoggerProvider);
  final settings = ref.watch(userSettingsProvider);

  if (settings.aiMode == AiMode.local) {
    final modelManager = ref.watch(modelManagerProvider);
    final provider = PaddleOcrProvider(
      logger: logger,
      modelManager: modelManager,
      detectorAssetPath: 'assets/models/ppocr_det.onnx',
      recognizerAssetPath: 'assets/models/ppocr_rec.onnx',
    );
    await provider.initialize();
    return provider;
  }

  // For BYOK and Hybrid modes, try cloud providers (Google Vision)
  final secureStorage = ref.watch(secureStorageServiceProvider);

  final visionKey = await secureStorage.getGoogleVisionKey();
  if (visionKey != null && visionKey.isNotEmpty) {
    final provider = GoogleVisionProvider(
      logger: logger,
      secureStorage: secureStorage,
    );
    await provider.initialize();
    return provider;
  }

  // Fall back to null provider if no cloud keys configured
  logger.warning('No cloud API keys configured for OCR, disabling');
  return NullObjectDetectionProvider();
});

// ─────────────────────────────────────────────
// AI Embeddings & Search - Defined in features/search/providers/search_providers.dart
// ─────────────────────────────────────────────
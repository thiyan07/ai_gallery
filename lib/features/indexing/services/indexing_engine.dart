import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../../../ai/ai_manager.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/ai_job.dart';
import '../../../domain/models/index_status.dart';
import '../../../domain/models/photo.dart';
import 'image_scanner.dart';
import 'metadata_extractor.dart';
import '../../analysis/analysis_manager.dart';
import '../../knowledge_graph/services/knowledge_graph_service.dart';

/// Main AI Indexing Engine orchestrator.
class IndexingEngine {
  IndexingEngine({
    required AppDatabase db,
    required ImageScanner scanner,
    required MetadataExtractor extractor,
    required AIManager aiManager,
    required AppLogger logger,
    AnalysisManager? analysisManager,
    KnowledgeGraphService? knowledgeGraphService,
  })  : _db = db,
        _scanner = scanner,
        _extractor = extractor,
        _aiManager = aiManager,
        _logger = logger,
        _analysisManager = analysisManager,
        _knowledgeGraphService = knowledgeGraphService;

  final AppDatabase _db;
  final ImageScanner _scanner;
  final MetadataExtractor _extractor;
  final AIManager _aiManager;
  final AppLogger _logger;
  final AnalysisManager? _analysisManager;
  final KnowledgeGraphService? _knowledgeGraphService;

  final _statusController = StreamController<IndexStatus>.broadcast();
  IndexStatus _currentStatus = IndexStatus.initial;

  Stream<IndexStatus> get statusStream => _statusController.stream;
  IndexStatus get currentStatus => _currentStatus;

  bool _isPaused = false;
  bool _isCancelled = false;

  /// Starts the indexing process.
  Future<void> start() async {
    if (_currentStatus.isRunning) {
      _logger.warning('Indexing already running');
      return;
    }

    _isCancelled = false;
    _isPaused = false;

    _emitStatus(_currentStatus.copyWith(
      isRunning: true,
      isPaused: false,
      startedAt: DateTime.now(),
    ));

    try {
      await _runIndexing();
    } catch (e, st) {
      _logger.error('Indexing failed', error: e, stackTrace: st);
    } finally {
      _emitStatus(_currentStatus.copyWith(
        isRunning: false,
        isPaused: false,
        currentPhase: IndexingPhase.complete,
      ));
    }
  }

  /// Pauses indexing.
  void pause() {
    _isPaused = true;
    _emitStatus(_currentStatus.copyWith(isPaused: true));
  }

  /// Resumes indexing.
  void resume() {
    _isPaused = false;
    _emitStatus(_currentStatus.copyWith(isPaused: false));
  }

  /// Cancels indexing.
  void cancel() {
    _isCancelled = true;
  }

  Future<void> _runIndexing() async {
    // Phase 1: Scan
    _emitStatus(_currentStatus.copyWith(currentPhase: IndexingPhase.scanning));
    final scanResult = await _scanner.scan();

    if (_isCancelled) return;

    // Delete metadata and all related records for deleted photos
    for (final photoId in scanResult.deletedPhotos) {
      await _db.photoMetadata.deleteCascade(photoId);
    }

    final photosToIndex = [
      ...scanResult.newPhotos,
      ...scanResult.modifiedPhotos,
    ];

    _emitStatus(_currentStatus.copyWith(
      totalPhotos: photosToIndex.length,
      processedPhotos: 0,
    ));

    // Phase 2: Extract metadata
    for (var i = 0; i < photosToIndex.length; i++) {
      if (_isCancelled) return;

      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isCancelled) return;
      }

      final photo = photosToIndex[i];
      _emitStatus(_currentStatus.copyWith(
        currentPhase: IndexingPhase.extractingMetadata,
        currentPhotoId: photo.id,
      ));

      try {
        // Get AssetEntity to extract full metadata
        final asset = await AssetEntity.fromId(photo.id);
        if (asset == null) {
          _logger.warning('Asset not found for photo ID: ${photo.id}');
          _emitStatus(_currentStatus.copyWith(
            failedPhotos: _currentStatus.failedPhotos + 1,
          ));
          continue;
        }

        // Extract full metadata including EXIF, color analysis, quality metrics
        final metadata = await _extractor.extractFromAsset(asset);
        await _db.photoMetadata.upsert(metadata);

        _emitStatus(_currentStatus.copyWith(
          processedPhotos: i + 1,
        ));
      } catch (e, st) {
        _logger.error('Failed to index photo ${photo.id}', error: e, stackTrace: st);
        _emitStatus(_currentStatus.copyWith(
          failedPhotos: _currentStatus.failedPhotos + 1,
        ));
      }
    }

    // Phase 3: Video analysis (frames, segments, analysis record)
    if (!_isCancelled && _analysisManager != null && photosToIndex.isNotEmpty) {
      final videoIds = await _db.photoMetadata.getVideoPhotoIds();
      if (videoIds.isNotEmpty) {
        _emitStatus(_currentStatus.copyWith(
          currentPhase: IndexingPhase.analyzingContent,
          processedPhotos: 0,
        ));

        for (var i = 0; i < videoIds.length; i++) {
          if (_isCancelled) return;
          while (_isPaused) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (_isCancelled) return;
          }

          final videoId = videoIds[i];
          _emitStatus(_currentStatus.copyWith(
            currentPhase: IndexingPhase.analyzingContent,
            currentPhotoId: videoId,
          ));

          try {
            final asset = await AssetEntity.fromId(videoId);
            if (asset == null) continue;

            // Skip if already analyzed
            final existing = await _db.videoAnalysis.getByVideoId(videoId);
            if (existing != null) {
              _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
              continue;
            }

            // Analyze video: extract frames, detect segments
            await _analysisManager!.analyzeVideo(videoId);

            // Queue frame-level AI jobs (OCR, faces, objects)
            await _analysisManager!.queueVideoFrameJobs(videoId);

            _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
          } catch (e, st) {
            _logger.error('Failed to analyze video $videoId',
                error: e, stackTrace: st);
            _emitStatus(_currentStatus.copyWith(
              failedPhotos: _currentStatus.failedPhotos + 1,
            ));
          }
        }
      }
    }

    // Phase 4: Generate embeddings
    if (!_isCancelled && photosToIndex.isNotEmpty) {
      _emitStatus(_currentStatus.copyWith(
        currentPhase: IndexingPhase.generatingEmbeddings,
        processedPhotos: 0,
      ));

      await _enqueueEmbeddingJobs(photosToIndex);
    }

    // Phase 4: Object detection
    if (!_isCancelled && photosToIndex.isNotEmpty) {
      _emitStatus(_currentStatus.copyWith(
        currentPhase: IndexingPhase.detectingObjects,
        processedPhotos: 0,
      ));

      await _enqueueObjectDetectionJobs(photosToIndex);
    }

    // Phase 4b: Region embeddings (object crops for precise complex-scene search)
    if (!_isCancelled && photosToIndex.isNotEmpty) {
      _emitStatus(_currentStatus.copyWith(
        currentPhase: IndexingPhase.embeddingRegions,
        processedPhotos: 0,
      ));

      await _enqueueRegionEmbeddingJobs(photosToIndex);
    }

    // Phase 5: Build knowledge graph from all indexed data
    if (!_isCancelled && _knowledgeGraphService != null) {
      _emitStatus(_currentStatus.copyWith(
        currentPhase: IndexingPhase.buildingGraph,
        processedPhotos: 0,
      ));

      try {
        final stats = await _knowledgeGraphService!.buildGraph();
        _logger.info('Knowledge graph built: $stats');
      } catch (e, st) {
        _logger.error('Failed to build knowledge graph', error: e, stackTrace: st);
      }
    }
  }

  /// Enqueue AI embedding jobs for all photos.
  Future<void> _enqueueEmbeddingJobs(List<Photo> photos) async {
    for (var i = 0; i < photos.length; i++) {
      if (_isCancelled) return;

      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isCancelled) return;
      }

      final photo = photos[i];

      // Check if embedding already exists or is being processed
      final existingEmbedding = await _db.embeddings.getEmbeddingByPhotoId(photo.id);
      if (existingEmbedding != null) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }
      final hasActiveJob = await _db.aiJobs.hasActiveJobForPhoto(photo.id, AIJobType.embedding);
      if (hasActiveJob) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }

      // Enqueue embedding job
      final job = AIJob(
        id: 'embedding_${photo.id}_${DateTime.now().millisecondsSinceEpoch}',
        photoId: photo.id,
        type: AIJobType.embedding,
        status: AIJobStatus.pending,
        createdAt: DateTime.now(),
      );

      try {
        await _aiManager.enqueue(job);
      } catch (e, st) {
        _logger.error('Failed to enqueue embedding job for ${photo.id}', error: e, stackTrace: st);
      }

      _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
    }

    // Wait for embedding jobs to complete (with timeout)
    await _waitForEmbeddingJobs(photos);
  }

  /// Enqueue object detection jobs for all photos.
  Future<void> _enqueueObjectDetectionJobs(List<Photo> photos) async {
    for (var i = 0; i < photos.length; i++) {
      if (_isCancelled) return;

      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isCancelled) return;
      }

      final photo = photos[i];

      // Check if object tags already exist or are being processed
      final existingTags = await _db.objectTags.getObjectTagsByPhotoId(photo.id);
      if (existingTags.isNotEmpty) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }
      final hasActiveJob = await _db.aiJobs.hasActiveJobForPhoto(photo.id, AIJobType.objectTagging);
      if (hasActiveJob) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }

      // Enqueue object detection job
      final job = AIJob(
        id: 'object_detection_${photo.id}_${DateTime.now().millisecondsSinceEpoch}',
        photoId: photo.id,
        type: AIJobType.objectTagging,
        status: AIJobStatus.pending,
        createdAt: DateTime.now(),
      );

      try {
        await _aiManager.enqueue(job);
      } catch (e, st) {
        _logger.error('Failed to enqueue object detection job for ${photo.id}', error: e, stackTrace: st);
      }

      _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
    }

    // Wait for object detection jobs to complete (with timeout)
    await _waitForObjectDetectionJobs(photos);
  }

  /// Wait for embedding jobs to complete — batch query version (fixes N sequential queries per interval).
  Future<void> _waitForEmbeddingJobs(List<Photo> photos) async {
    const maxWaitSeconds = 300; // 5 minutes max
    const checkInterval = Duration(seconds: 5);
    int waitedSeconds = 0;
    final ids = photos.map((p) => p.id).toList();
    if (ids.isEmpty) return;

    while (waitedSeconds < maxWaitSeconds) {
      if (_isCancelled) return;

      // Single batched query instead of N× getEmbeddingByPhotoId
      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await _db.database.rawQuery(
        'SELECT COUNT(DISTINCT photo_id) as cnt FROM embeddings WHERE photo_id IN ($placeholders)',
        ids,
      );
      final completedCount = (rows.first['cnt'] as int?) ?? 0;

      if (completedCount >= photos.length) {
        _logger.info('All $completedCount embedding jobs completed');
        break;
      }

      await Future.delayed(checkInterval);
      waitedSeconds += checkInterval.inSeconds;
    }

    if (waitedSeconds >= maxWaitSeconds) {
      _logger.warning('Timeout waiting for embedding jobs to complete');
    }
  }

  /// Enqueue region-embedding jobs for photos with object detections.
  ///
  /// Each job embeds up to 3 prominent object crops so semantic search can
  /// match small/background objects in complex scenes. Photos without
  /// detections, or whose regions are already embedded, are skipped.
  Future<void> _enqueueRegionEmbeddingJobs(List<Photo> photos) async {
    for (var i = 0; i < photos.length; i++) {
      if (_isCancelled) return;

      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isCancelled) return;
      }

      final photo = photos[i];

      final tags = await _db.objectTags.getObjectTagsByPhotoId(photo.id);
      if (tags.isEmpty) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }
      final existingRegions = await _db.embeddings.countRegionsByPhotoId(photo.id);
      if (existingRegions > 0) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }
      final hasActiveJob = await _db.aiJobs.hasActiveJobForPhoto(photo.id, AIJobType.regionEmbedding);
      if (hasActiveJob) {
        _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
        continue;
      }

      final job = AIJob(
        id: 'region_embedding_${photo.id}_${DateTime.now().millisecondsSinceEpoch}',
        photoId: photo.id,
        type: AIJobType.regionEmbedding,
        status: AIJobStatus.pending,
        createdAt: DateTime.now(),
      );

      try {
        await _aiManager.enqueue(job);
      } catch (e, st) {
        _logger.error('Failed to enqueue region embedding job for ${photo.id}', error: e, stackTrace: st);
      }

      _emitStatus(_currentStatus.copyWith(processedPhotos: i + 1));
    }

    await _waitForRegionEmbeddingJobs(photos);
  }

  /// Wait for region embedding jobs — photos without detections count as done.
  Future<void> _waitForRegionEmbeddingJobs(List<Photo> photos) async {
    const maxWaitSeconds = 300;
    const checkInterval = Duration(seconds: 5);
    int waitedSeconds = 0;
    final ids = photos.map((p) => p.id).toList();
    if (ids.isEmpty) return;

    while (waitedSeconds < maxWaitSeconds) {
      if (_isCancelled) return;

      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await _db.database.rawQuery(
        'SELECT COUNT(DISTINCT t.photo_id) as cnt FROM object_tags t '
        'LEFT JOIN embeddings e ON e.photo_id = t.photo_id AND e.region_label IS NOT NULL '
        'WHERE t.photo_id IN ($placeholders) AND e.photo_id IS NULL',
        ids,
      );
      final remaining = (rows.first['cnt'] as int?) ?? 0;

      if (remaining == 0) {
        _logger.info('All region embedding jobs completed');
        break;
      }

      await Future.delayed(checkInterval);
      waitedSeconds += checkInterval.inSeconds;
    }

    if (waitedSeconds >= maxWaitSeconds) {
      _logger.warning('Timeout waiting for region embedding jobs to complete');
    }
  }

  /// Wait for object detection jobs to complete — batch version.
  Future<void> _waitForObjectDetectionJobs(List<Photo> photos) async {    const maxWaitSeconds = 300; // 5 minutes max
    const checkInterval = Duration(seconds: 5);
    int waitedSeconds = 0;
    final ids = photos.map((p) => p.id).toList();
    if (ids.isEmpty) return;

    while (waitedSeconds < maxWaitSeconds) {
      if (_isCancelled) return;

      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await _db.database.rawQuery(
        'SELECT COUNT(DISTINCT photo_id) as cnt FROM object_tags WHERE photo_id IN ($placeholders)',
        ids,
      );
      final completedCount = (rows.first['cnt'] as int?) ?? 0;

      if (completedCount >= photos.length) {
        _logger.info('All $completedCount object detection jobs completed');
        break;
      }

      await Future.delayed(checkInterval);
      waitedSeconds += checkInterval.inSeconds;
    }

    if (waitedSeconds >= maxWaitSeconds) {
      _logger.warning('Timeout waiting for object detection jobs to complete');
    }
  }

  void _emitStatus(IndexStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    _statusController.close();
  }
}
import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/index_status.dart';
import '../../../domain/models/photo_metadata.dart';
import 'image_scanner.dart';
import 'metadata_extractor.dart';

/// Main AI Indexing Engine orchestrator.
class IndexingEngine {
  IndexingEngine({
    required AppDatabase db,
    required ImageScanner scanner,
    required MetadataExtractor extractor,
    required AppLogger logger,
  })  : _db = db,
        _scanner = scanner,
        _extractor = extractor,
        _logger = logger;

  final AppDatabase _db;
  final ImageScanner _scanner;
  final MetadataExtractor _extractor;
  final AppLogger _logger;

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

    // Delete metadata for deleted photos
    for (final photoId in scanResult.deletedPhotos) {
      await _db.photoMetadata.deleteById(photoId);
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
  }

  void _emitStatus(IndexStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    _statusController.close();
  }
}
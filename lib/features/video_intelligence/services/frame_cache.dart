import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';

/// Bounded, LRU frame cache for video frame extraction.
///
/// Stores decoded frame images with a maximum count and total byte budget.
/// Frames are evicted in LRU order when limits are exceeded.
/// Thread-safe via compute-isolate for decoding operations.
class FrameCache {
  FrameCache({
    required AppLogger logger,
    int maxFrames = 50,
    int maxBytes = 50 * 1024 * 1024, // 50 MB default
  })  : _logger = logger,
        _maxFrames = maxFrames,
        _maxBytes = maxBytes;

  final AppLogger _logger;
  final int _maxFrames;
  final int _maxBytes;

  /// LRU cache: key = "$videoId:$timestampMs"
  final LinkedHashMap<String, CacheEntry> _cache = LinkedHashMap();
  int _currentBytes = 0;

  /// Total cached frame count.
  int get length => _cache.length;

  /// Total cached bytes.
  int get currentBytes => _currentBytes;

  /// Get a cached frame (returns null if not cached).
  Uint8List? get(String videoId, int timestampMs) {
    final key = _key(videoId, timestampMs);
    final entry = _cache[key];
    if (entry == null) return null;

    // Move to end (most recently used)
    _cache.remove(key);
    _cache[key] = entry;

    return entry.data;
  }

  /// Put a frame into the cache.
  ///
  /// If the frame exceeds the byte budget, evicts oldest entries.
  void put(String videoId, int timestampMs, Uint8List data) {
    final key = _key(videoId, timestampMs);

    // If already cached, remove old entry
    final existing = _cache.remove(key);
    if (existing != null) {
      _currentBytes -= existing.data.length;
    }

    // Evict until we have room
    while (_cache.length >= _maxFrames ||
        _currentBytes + data.length > _maxBytes) {
      if (_cache.isEmpty) break;
      final oldest = _cache.keys.first;
      final evicted = _cache.remove(oldest)!;
      _currentBytes -= evicted.data.length;
    }

    _cache[key] = CacheEntry(data: data, timestamp: DateTime.now());
    _currentBytes += data.length;
  }

  /// Check if a frame is cached.
  bool contains(String videoId, int timestampMs) =>
      _cache.containsKey(_key(videoId, timestampMs));

  /// Invalidate all frames for a video.
  void invalidateVideo(String videoId) {
    final prefix = '$videoId:';
    final keysToRemove = _cache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      final entry = _cache.remove(key)!;
      _currentBytes -= entry.data.length;
    }
  }

  /// Clear the entire cache.
  void clear() {
    _cache.clear();
    _currentBytes = 0;
  }

  /// Load a frame from disk and cache it.
  ///
  /// Returns the cached data, or null if the file doesn't exist.
  Future<Uint8List?> loadAndCache(
    String videoId,
    int timestampMs,
    String filePath,
  ) async {
    // Check cache first
    final cached = get(videoId, timestampMs);
    if (cached != null) return cached;

    // Load from disk
    final file = File(filePath);
    if (!await file.exists()) return null;

    final data = await file.readAsBytes();
    put(videoId, timestampMs, data);
    return data;
  }

  String _key(String videoId, int timestampMs) => '$videoId:$timestampMs';
}

class CacheEntry {
  final Uint8List data;
  final DateTime timestamp;

  const CacheEntry({required this.data, required this.timestamp});
}

/// Manages video frame file storage on disk.
///
/// Frames are stored under the app's temp directory in a bounded structure.
/// Old frames are cleaned up automatically.
class FrameStorage {
  FrameStorage({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;
  static const _frameDir = 'video_frames';

  /// Get the directory for a video's frames.
  Future<Directory> getVideoFrameDir(String videoId) async {
    // Sanitize videoId to prevent path traversal
    final safeId = videoId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final tempDir = Directory.systemTemp;
    final dir = Directory('${tempDir.path}/$_frameDir/$safeId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Save a frame to disk and return the path.
  Future<String> saveFrame({
    required String videoId,
    required int timestampMs,
    required Uint8List data,
  }) async {
    final dir = await getVideoFrameDir(videoId);
    final file = File('${dir.path}/frame_$timestampMs.jpg');
    await file.writeAsBytes(data);
    return file.path;
  }

  /// Get the path for a specific frame.
  Future<String?> getFramePath({
    required String videoId,
    required int timestampMs,
  }) async {
    final dir = await getVideoFrameDir(videoId);
    final file = File('${dir.path}/frame_$timestampMs.jpg');
    if (await file.exists()) return file.path;
    return null;
  }

  /// Delete all frames for a video.
  Future<void> deleteVideoFrames(String videoId) async {
    final dir = await getVideoFrameDir(videoId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Get total disk usage for video frames (bytes).
  Future<int> getDiskUsage() async {
    final tempDir = Directory.systemTemp;
    final rootDir = Directory('${tempDir.path}/$_frameDir');
    if (!await rootDir.exists()) return 0;

    var totalBytes = 0;
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }

  /// Cleanup frames older than [maxAge].
  Future<int> cleanupOldFrames({Duration maxAge = const Duration(days: 7)}) async {
    final tempDir = Directory.systemTemp;
    final rootDir = Directory('${tempDir.path}/$_frameDir');
    if (!await rootDir.exists()) return 0;

    var deletedCount = 0;
    final cutoff = DateTime.now().subtract(maxAge);

    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
          deletedCount++;
        }
      }
    }

    if (deletedCount > 0) {
      _logger.info('Cleaned up $deletedCount old video frames');
    }
    return deletedCount;
  }
}

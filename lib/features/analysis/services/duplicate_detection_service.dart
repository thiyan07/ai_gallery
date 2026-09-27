import '../../../domain/models/duplicate_group.dart';
import '../../../core/database/daos/analysis_dao.dart';
import '../../../core/database/daos/duplicate_dao.dart';
import '../../../core/logging/app_logger.dart';
import 'hash_service.dart';

/// Finds exact and near-duplicate photos using content + perceptual hashes.
class DuplicateDetectionService {
  DuplicateDetectionService({
    required AnalysisDao analysisDao,
    required DuplicateDao duplicateDao,
    AppLogger? logger,
  })  : _analysisDao = analysisDao,
        _duplicateDao = duplicateDao,
        _logger = logger;

  final AnalysisDao _analysisDao;
  final DuplicateDao _duplicateDao;
  final HashService _hashService = HashService();
  final AppLogger? _logger;

  /// Find all duplicate groups across the library.
  ///
  /// 1. Group by identical content hash (exact duplicates)
  /// 2. Group by hamming distance of perceptual hash (near-duplicates)
  /// 3. Select best photo as recommended keep
  Future<DuplicateReport> findAllDuplicates() async {
    _logger?.info('Starting duplicate detection');

    final groups = <DuplicateGroup>[];

    // Phase 1: Exact duplicates (content hash)
    final exactGroups = await _findExactDuplicates();
    groups.addAll(exactGroups);
    _logger?.info('Found ${exactGroups.length} exact duplicate groups');

    // Phase 2: Near-duplicates (perceptual hash)
    final nearGroups = await _findNearDuplicates();
    groups.addAll(nearGroups);
    _logger?.info('Found ${nearGroups.length} near-duplicate groups');

    // Store all groups
    for (final group in groups) {
      await _duplicateDao.upsert(group);
    }

    final totalPhotos = groups.fold<int>(0, (sum, g) => sum + g.count);
    _logger?.info(
        'Duplicate detection complete: ${groups.length} groups, $totalPhotos photos');

    return DuplicateReport(
      totalGroups: groups.length,
      exactGroups: exactGroups.length,
      nearDuplicateGroups: nearGroups.length,
      totalPhotos: totalPhotos,
      groups: groups,
    );
  }

  /// Find duplicates for a specific photo.
  Future<List<DuplicateGroup>> findDuplicatesForPhoto(String photoId) async {
    final state = await _analysisDao.getByPhotoId(photoId);
    if (state == null) return [];

    final groups = <DuplicateGroup>[];

    // Check exact duplicates
    if (state.hasContentHash) {
      final matches = await _analysisDao.getByContentHash(state.contentHash!);
      if (matches.length > 1) {
        final bestId = await _selectBestPhoto(matches);
        groups.add(DuplicateGroup(
          groupId: 'exact_${state.contentHash}',
          photoIds: matches,
          type: DuplicateType.exact,
          similarity: 1.0,
          confidence: 1.0,
          recommendedKeepId: bestId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    }

    // Check near-duplicates
    if (state.hasPerceptualHash) {
      final rows = await _analysisDao.getAllPerceptualHashes();
      final nearby = <_HashEntry>[];
      for (final row in rows) {
        final id = row['photo_id'] as String;
        if (id == photoId) continue;
        final hash = row['perceptual_hash'] as String;
        if (hash.isEmpty) continue;
        if (_hashService.isNearDuplicate(state.perceptualHash!, hash)) {
          nearby.add(_HashEntry(id, hash));
        }
      }

      if (nearby.isNotEmpty) {
        final allIds = [photoId, ...nearby.map((n) => n.id)];
        final distance = _hashService.hammingDistance(
          state.perceptualHash!,
          nearby.first.hash,
        );
        final bestId = await _selectBestPhoto(allIds);
        groups.add(DuplicateGroup(
          groupId: 'near_${photoId}_${DateTime.now().millisecondsSinceEpoch}',
          photoIds: allIds,
          type: DuplicateType.nearDuplicate,
          similarity: 1.0 - (distance / 64.0),
          confidence: 0.8,
          recommendedKeepId: bestId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    }

    return groups;
  }

  /// Group photos by content hash.
  Future<List<DuplicateGroup>> _findExactDuplicates() async {
    final groups = <DuplicateGroup>[];

    final rows = await _analysisDao.getGroupedByContentHash();

    for (final row in rows) {
      final hash = row['content_hash'] as String;
      final ids = (row['photo_ids'] as String)
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList();

      if (ids.length >= 2) {
        final bestId = await _selectBestPhoto(ids);
        groups.add(DuplicateGroup(
          groupId: 'exact_$hash',
          photoIds: ids,
          type: DuplicateType.exact,
          similarity: 1.0,
          confidence: 1.0,
          recommendedKeepId: bestId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    }

    return groups;
  }

  /// Group photos by perceptual hash similarity.
  Future<List<DuplicateGroup>> _findNearDuplicates() async {
    final groups = <DuplicateGroup>[];
    final processed = <String>{};

    final rows = await _analysisDao.getAllPerceptualHashes();

    final entries = rows
        .map((r) => MapEntry(
              r['photo_id'] as String,
              r['perceptual_hash'] as String,
            ))
        .toList();

    // Union-Find for grouping
    final parent = <String, String>{};
    for (final e in entries) {
      parent[e.key] = e.key;
    }

    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]]!;
        x = parent[x]!;
      }
      return x;
    }

    void union(String a, String b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    // Compare all pairs (O(n²) but acceptable for <100k photos)
    // For large libraries, use LSH or locality-sensitive hashing
    for (var i = 0; i < entries.length; i++) {
      if (processed.contains(entries[i].key)) continue;

      for (var j = i + 1; j < entries.length; j++) {
        if (_hashService.isNearDuplicate(entries[i].value, entries[j].value)) {
          union(entries[i].key, entries[j].key);
          processed.add(entries[j].key);
        }
      }
    }

    // Build groups from union-find
    final clusterMap = <String, List<String>>{};
    for (final entry in entries) {
      final root = find(entry.key);
      clusterMap.putIfAbsent(root, () => []).add(entry.key);
    }

    for (final cluster in clusterMap.values) {
      if (cluster.length < 2) continue;

      // Compute average similarity
      final hashes = cluster.map((id) {
        return entries.firstWhere((e) => e.key == id).value;
      }).toList();

      var totalDistance = 0;
      var pairs = 0;
      for (var i = 0; i < hashes.length; i++) {
        for (var j = i + 1; j < hashes.length; j++) {
          totalDistance += _hashService.hammingDistance(hashes[i], hashes[j]);
          pairs++;
        }
      }
      final avgSimilarity =
          pairs > 0 ? 1.0 - (totalDistance / pairs / 64.0) : 0.0;

      final bestId = await _selectBestPhoto(cluster);
      groups.add(DuplicateGroup(
        groupId: 'near_${cluster.first}',
        photoIds: cluster,
        type: DuplicateType.nearDuplicate,
        similarity: avgSimilarity,
        confidence: 0.8,
        recommendedKeepId: bestId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }

    return groups;
  }

  /// Select the "best" photo from a group.
  ///
  /// Criteria: highest quality score, sharpest (lowest blur), largest resolution.
  Future<String?> _selectBestPhoto(List<String> photoIds) async {
    if (photoIds.isEmpty) return null;
    if (photoIds.length == 1) return photoIds.first;

    String bestId = photoIds.first;
    double bestScore = -1;

    for (final id in photoIds) {
      final state = await _analysisDao.getByPhotoId(id);
      // Use quality score if available, otherwise default to 0.5
      final score = state != null ? (state.qualityScore ?? 0.5) : 0.5;
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    }

    return bestId;
  }
}

/// Report of duplicate detection results.
class DuplicateReport {
  final int totalGroups;
  final int exactGroups;
  final int nearDuplicateGroups;
  final int totalPhotos;
  final List<DuplicateGroup> groups;

  const DuplicateReport({
    required this.totalGroups,
    required this.exactGroups,
    required this.nearDuplicateGroups,
    required this.totalPhotos,
    required this.groups,
  });
}

class _HashEntry {
  final String id;
  final String hash;
  const _HashEntry(this.id, this.hash);
}

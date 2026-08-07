import 'dart:math';
import 'dart:typed_data';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';

/// Service for clustering faces into person groups using face embeddings.
///
/// Uses DBSCAN-like clustering on cosine similarity of face embeddings.
/// Each cluster represents a unique person.
class FaceClusteringService {
  FaceClusteringService({
    required AppLogger logger,
    required AppDatabase database,
  })  : _logger = logger,
        _database = database;

  final AppLogger _logger;
  final AppDatabase _database;

  /// Threshold for considering two faces as the same person (cosine similarity).
  /// Range: 0.0 to 1.0. Higher = more strict.
  static const double _similarityThreshold = 0.6;

  /// Minimum face embedding cluster size to consider as a valid person.
  static const int _minClusterSize = 2;

  /// Maximum number of faces to process in one batch.
  static const int _maxFacesPerBatch = 1000;

  /// Public getter for similarity threshold (for UI display).
  double get similarityThreshold => _similarityThreshold;

  /// Public getter for minimum cluster size (for UI display).
  int get minClusterSize => _minClusterSize;

  /// Cluster all unclustered faces in the database.
  ///
  /// Returns the number of clusters created/updated.
  Future<int> clusterAllFaces() async {
    _logger.info('Starting face clustering...');

    // Get all faces with embeddings
    final facesWithEmbeddings = await _database.faces.getFacesWithEmbeddings(
      limit: _maxFacesPerBatch,
    );

    if (facesWithEmbeddings.isEmpty) {
      _logger.info('No faces with embeddings to cluster');
      return 0;
    }

    _logger.info('Clustering ${facesWithEmbeddings.length} faces');

    // Build similarity matrix and cluster
    final clusters = _clusterFaces(facesWithEmbeddings);

    // Save clusters to database
    int clustersSaved = 0;
    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      if (cluster.length >= _minClusterSize) {
        final label = 'Person $i';
        await _saveCluster(cluster, label);
        clustersSaved++;
      }
    }

    _logger.info('Face clustering completed: $clustersSaved clusters created');
    return clustersSaved;
  }

  /// Re-cluster a specific face against existing clusters.
  ///
  /// Used when a new face embedding is added.
  Future<String?> clusterFace(FaceDetectionRecord face) async {
    if (face.embedding == null) return null;

    // Get all existing cluster representatives
    final clusters = await _getClusterRepresentatives();

    double bestSimilarity = -1;
    String? bestLabel;

    for (final (label, embedding) in clusters) {
      final similarity = _cosineSimilarity(face.embedding!, embedding);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestLabel = label;
      }
    }

    if (bestSimilarity >= _similarityThreshold && bestLabel != null) {
      // Assign to existing cluster
      await _database.faces.updateFaceLabel(face.id, bestLabel);
      _logger.info('Assigned face ${face.id} to cluster $bestLabel (similarity: ${bestSimilarity.toStringAsFixed(3)})');
      return bestLabel;
    }

    // Create new cluster (singleton for now)
    final newLabel = 'Person ${clusters.length}';
    await _database.faces.updateFaceLabel(face.id, newLabel);
    _logger.info('Created new cluster $newLabel for face ${face.id}');
    return newLabel;
  }

  /// Merge two clusters.
  Future<void> mergeClusters(String label1, String label2) async {
    final targetLabel = label1;
    final sourceLabel = label2;

    await _database.faces.mergeFaceLabels(sourceLabel, targetLabel);
    _logger.info('Merged cluster $sourceLabel into $targetLabel');
  }

  /// Get all cluster representatives (average embedding per cluster).
  Future<List<(String, Float32List)>> _getClusterRepresentatives() async {
    final clusters = await _database.faces.getClusteredFaces();

    final representatives = <String, (Float32List, int)>{};

    for (final face in clusters) {
      if (face.label == null || face.embedding == null) continue;

      final existing = representatives[face.label!];
      if (existing == null) {
        representatives[face.label!] = (face.embedding!, 1);
      } else {
        // Compute running average
        final newCount = existing.$2 + 1;
        final avgEmbedding = Float32List(face.embedding!.length);
        for (var i = 0; i < avgEmbedding.length; i++) {
          avgEmbedding[i] = (existing.$1[i] * existing.$2 + face.embedding![i]) / newCount;
        }
        representatives[face.label!] = (avgEmbedding, newCount);
      }
    }

    return representatives.entries.map((e) => (e.key, e.value.$1)).toList();
  }

  /// Cluster faces using a simple greedy approach based on cosine similarity.
  List<List<FaceDetectionRecord>> _clusterFaces(List<FaceDetectionRecord> faces) {
    if (faces.isEmpty) return [];

    final clusters = <List<FaceDetectionRecord>>[];
    final visited = List<bool>.filled(faces.length, false);

    for (var i = 0; i < faces.length; i++) {
      if (visited[i]) continue;

      final cluster = <FaceDetectionRecord>[faces[i]];
      visited[i] = true;

      // Find all similar faces
      for (var j = i + 1; j < faces.length; j++) {
        if (visited[j]) continue;

        if (faces[i].embedding != null && faces[j].embedding != null) {
          final similarity = _cosineSimilarity(faces[i].embedding!, faces[j].embedding!);
          if (similarity >= _similarityThreshold) {
            cluster.add(faces[j]);
            visited[j] = true;
          }
        }
      }

      if (cluster.length >= _minClusterSize) {
        clusters.add(cluster);
      }
    }

    // Sort clusters by size (largest first)
    clusters.sort((a, b) => b.length.compareTo(a.length));

    return clusters;
  }

  /// Compute cosine similarity between two normalized vectors.
  double _cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }

    // Vectors should already be L2 normalized
    return dot.clamp(-1.0, 1.0);
  }

  /// Save a cluster to the database.
  Future<void> _saveCluster(List<FaceDetectionRecord> cluster, String label) async {
    for (final face in cluster) {
      await _database.faces.updateFaceLabel(face.id, label);
    }
  }

  /// Get all people clusters.
  Future<List<PersonCluster>> getPeopleClusters() async {
    final faces = await _database.faces.getClusteredFaces();

    final clusters = <String, PersonCluster>{};

    for (final face in faces) {
      if (face.label == null) continue;

      final cluster = clusters.putIfAbsent(
        face.label!,
        () => PersonCluster(
          label: face.label!,
          faces: [],
          representativeFaceId: face.id,
        ),
      );
      cluster.faces.add(face);
    }

    // Sort faces within each cluster by confidence
    for (final cluster in clusters.values) {
      cluster.faces.sort((a, b) => b.confidence.compareTo(a.confidence));
      // Update representative to highest confidence face
      cluster.representativeFaceId = cluster.faces.first.id;
    }

    final result = clusters.values.toList();
    result.sort((a, b) => b.faces.length.compareTo(a.faces.length));

    return result;
  }

  /// Rename a person cluster.
  Future<void> renameCluster(String oldLabel, String newLabel) async {
    await _database.faces.mergeFaceLabels(oldLabel, newLabel);
  }

  /// Delete a person cluster (remove labels from faces).
  Future<void> deleteCluster(String label) async {
    await _database.faces.mergeFaceLabels(label, '');
  }
}

/// Represents a cluster of faces belonging to the same person.
class PersonCluster {
  PersonCluster({
    required this.label,
    required this.faces,
    required this.representativeFaceId,
  });

  final String label;
  final List<FaceDetectionRecord> faces;
  late String representativeFaceId;

  int get faceCount => faces.length;

  /// Get the representative face (highest confidence).
  FaceDetectionRecord? get representativeFace => faces.isNotEmpty ? faces.first : null;
}
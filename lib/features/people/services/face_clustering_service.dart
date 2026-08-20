import 'dart:typed_data';
import 'dart:math';

import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/person.dart';
import 'package:ai_gallery/domain/models/person_cluster.dart';
import 'package:ai_gallery/features/people/services/people_service.dart';

/// Service for clustering faces into person groups using face embeddings.
///
/// Uses DBSCAN-like clustering on cosine similarity of face embeddings.
/// Each cluster corresponds to a person (known or unknown) in the people
/// system.
class FaceClusteringService {
  FaceClusteringService({
    required AppLogger logger,
    required AppDatabase database,
  }) : _logger = logger,
       _database = database;

  final AppLogger _logger;
  final AppDatabase _database;

  /// Threshold for considering two faces as the same person (cosine similarity).
  /// Range: 0.0 to 1.0. Higher = more strict.
  static const double _similarityThreshold = 0.6;

  /// Minimum face embedding cluster size to consider as a valid person group.
  static const int _minClusterSize = 2;

  /// Maximum number of faces to process in one batch.
  static const int _maxFacesPerBatch = 1000;

  /// Public getter for similarity threshold (for UI display).
  double get similarityThreshold => _similarityThreshold;

  /// Public getter for minimum cluster size (for UI display).
  int get minClusterSize => _minClusterSize;

  /// Cluster all unprocessed faces with embeddings in the database.
  ///
  /// Returns the number of clusters created/updated.
  Future<int> clusterAllFaces() async {
    _logger.info('Starting face clustering...');

    // Get all faces with embeddings and no personId (unprocessed for person assignment)
    final facesWithEmbeddings = await _database.faces.getFacesWithEmbeddings(
      limit: _maxFacesPerBatch,
    );

    // Filter out faces that already have a personId assigned (already processed)
    final unprocessedFaces = facesWithEmbeddings.where((face) {
      return face.personId == null || face.personId!.isEmpty;
    }).toList();

    if (unprocessedFaces.isEmpty) {
      _logger.info('No unprocessed faces with embeddings to cluster');
      return 0;
    }

    _logger.info('Clustering ${unprocessedFaces.length} faces');

    // Build similarity matrix and cluster
    final clusters = _clusterFaces(unprocessedFaces);

    // Save clusters to database: create person records and assign faces
    int clustersSaved = 0;
    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      if (cluster.length >= _minClusterSize) {
        // Create or get a person record for this cluster
        final person = await _getOrCreatePersonForCluster(cluster);
        // Assign all faces in the cluster to this person
        final faceIds = cluster.map((face) => face.id).toList();
        await _database.faces.assignFacesToPerson(faceIds, person.personId);
        clustersSaved++;
      }
    }

    _logger.info(
      'Face clustering completed: $clustersSaved clusters created/updated',
    );
    return clustersSaved;
  }

  /// Re-cluster a specific face against existing clusters.
  ///
  /// Used when a new face embedding is added.
  /// Returns the personId of the cluster the face was assigned to, or null if no embedding.
  Future<String?> clusterFace(FaceDetectionRecord face) async {
    if (face.embedding == null) return null;

    // If face already has a personId, we trust the existing assignment
    // and don't unnecessarily change it during incremental clustering
    if (face.personId != null && face.personId!.isNotEmpty) {
      return face.personId;
    }

    // Get all faces that already have a personId (processed)
    final processedFaces = await _database.faces.getFacesWithPerson();

    if (processedFaces.isEmpty) {
      // No existing persons, create a new person and assign this face
      final person = await _createPersonFromFace(face);
      await _database.faces.updateFacePerson(face.id, person.personId);
      _logger.info('Created new person ${person.personId} for face ${face.id}');
      return person.personId;
    }

    double bestSimilarity = -1;
    String? bestPersonId;

    for (final processedFace in processedFaces) {
      if (processedFace.embedding == null) continue;

      // Check embedding compatibility before computing similarity
      if (!_areEmbeddingsCompatible(
        face.embedding!,
        processedFace.embedding!,
      )) {
        continue;
      }

      final similarity = cosineSimilarity(
        face.embedding!,
        processedFace.embedding!,
      );
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestPersonId = processedFace.personId;
      }
    }

    if (bestSimilarity >= _similarityThreshold && bestPersonId != null) {
      // Assign to existing person
      await _database.faces.updateFacePerson(face.id, bestPersonId);
      _logger.info(
        'Assigned face ${face.id} to person $bestPersonId '
        '(similarity: ${bestSimilarity.toStringAsFixed(3)})',
      );
      return bestPersonId;
    }

    // Create new person
    final person = await _createPersonFromFace(face);
    await _database.faces.updateFacePerson(face.id, person.personId);
    _logger.info('Created new person ${person.personId} for face ${face.id}');
    return person.personId;
  }

  /// Merge two clusters by merging their corresponding person records.
  Future<void> mergeClusters(String personId1, String personId2) async {
    final peopleService = PeopleService(logger: _logger, database: _database);
    await peopleService.mergePersons(personId1, personId2);
    _logger.info('Merged person $personId1 into $personId2');
  }

  /// Get all cluster representatives (average embedding per person).
  Future<List<(String, Float32List)>> getClusterRepresentatives() async {
    final facesWithPerson = await _database.faces.getFacesWithPerson();

    final representatives = <String, (Float32List, int)>{};

    for (final face in facesWithPerson) {
      if (face.personId == null || face.embedding == null) continue;

      final existing = representatives[face.personId!];
      if (existing == null) {
        representatives[face.personId!] = (face.embedding!, 1);
      } else {
        // Compute running average only for compatible embeddings
        // Note: In practice, all embeddings for a person should be from the same model
        // but we add a safety check
        final existingEmbedding = existing.$1;
        final existingCount = existing.$2;

        if (_areEmbeddingsCompatible(existingEmbedding, face.embedding!)) {
          final newCount = existingCount + 1;
          final avgEmbedding = Float32List(face.embedding!.length);
          for (var i = 0; i < avgEmbedding.length; i++) {
            avgEmbedding[i] =
                (existingEmbedding[i] * existingCount + face.embedding![i]) /
                newCount;
          }
          representatives[face.personId!] = (avgEmbedding, newCount);
        }
        // If incompatible, we skip adding this embedding to the average
        // This could indicate a data consistency issue that should be investigated
      }
    }

    return representatives.entries.map((e) => (e.key, e.value.$1)).toList();
  }

  /// Check if two embeddings are compatible for comparison.
  ///
  /// Returns true if embeddings have the same dimension, indicating they
  /// were likely generated by the same model version.
  bool _areEmbeddingsCompatible(Float32List a, Float32List b) {
    if (a.length != b.length) {
      _logger.warning(
        'Attempted to compare incompatible embeddings: '
        '${a.length}D vs ${b.length}D',
      );
      return false;
    }
    return true;
  }

  /// Cluster faces using a simple greedy approach based on cosine similarity.
  List<List<FaceDetectionRecord>> _clusterFaces(
    List<FaceDetectionRecord> faces,
  ) {
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
          // Check embedding compatibility before computing similarity
          if (!_areEmbeddingsCompatible(
            faces[i].embedding!,
            faces[j].embedding!,
          )) {
            continue;
          }

          final similarity = cosineSimilarity(
            faces[i].embedding!,
            faces[j].embedding!,
          );
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
  double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }

    // Vectors should already be L2 normalized
    return dot.clamp(-1.0, 1.0);
  }

  /// Create a person record from a single face (for new clusters).
  Future<Person> _createPersonFromFace(FaceDetectionRecord face) async {
    final person = Person(
      personId: _generatePersonId(),
      displayName: null, // Start as unknown person
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      coverPhotoId: null,
      status: PersonStatus.active,
    );

    await _database.peopleDao.upsert(person);
    return person;
  }

  /// Get or create a person record for a cluster of faces.
  Future<Person> _getOrCreatePersonForCluster(
    List<FaceDetectionRecord> cluster,
  ) async {
    // Check if any face in the cluster already has a personId (shouldn't happen for unprocessed faces)
    final existingPersonId = cluster
        .firstWhere(
          (face) => face.personId != null && face.personId!.isNotEmpty,
          orElse: () => FaceDetectionRecord(
            id: '',
            photoId: '',
            x: 0,
            y: 0,
            width: 0,
            height: 0,
            confidence: 0,
            personId: null,
          ),
        )
        .personId;

    if (existingPersonId != null && existingPersonId.isNotEmpty) {
      // Return existing person
      final person = await _database.peopleDao.getById(existingPersonId);
      if (person != null) return person;
    }

    // Create new person for this cluster
    return _createPersonFromCluster(cluster);
  }

  /// Create a person record representing a cluster of faces.
  Future<Person> _createPersonFromCluster(
    List<FaceDetectionRecord> cluster,
  ) async {
    // Use the first face's photo as potential cover photo
    String? coverPhotoId;
    if (cluster.isNotEmpty) {
      coverPhotoId = cluster.first.photoId;
    }

    final person = Person(
      personId: _generatePersonId(),
      displayName: null, // Unknown person
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      coverPhotoId: coverPhotoId,
      status: PersonStatus.active,
    );

    await _database.peopleDao.upsert(person);
    return person;
  }

  String _generatePersonId() {
    return 'person_${DateTime.now().millisecondsSinceEpoch}_'
        '${_generateRandomString(6)}';
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Returns all person clusters with their faces.
  Future<List<PersonCluster>> getPeopleClusters() async {
    final people = await _database.peopleDao.getAll();
    final clusters = <PersonCluster>[];

    for (final person in people) {
      final faces = await _database.faces.getFacesByPersonId(person.personId);
      if (faces.isNotEmpty) {
        clusters.add(
          PersonCluster(
            personId: person.personId,
            label: person.displayName ?? 'Unknown',
            faces: faces,
          ),
        );
      }
    }

    return clusters;
  }

  /// Renames a cluster identified by its current label.
  Future<void> renameCluster(String currentLabel, String newLabel) async {
    final clusters = await getPeopleClusters();
    final cluster = clusters.firstWhere(
      (c) => c.label == currentLabel,
      orElse: () => throw StateError('Cluster not found: $currentLabel'),
    );

    final person = await _database.peopleDao.getById(cluster.personId);
    if (person == null) return;

    await _database.peopleDao.upsert(
      person.copyWith(displayName: newLabel, updatedAt: DateTime.now()),
    );
    _logger.info(
      'Renamed person ${cluster.personId} from "$currentLabel" to "$newLabel"',
    );
  }

  /// Deletes a cluster by removing person assignment from all its faces.
  Future<void> deleteCluster(String label) async {
    final clusters = await getPeopleClusters();
    final cluster = clusters.firstWhere(
      (c) => c.label == label,
      orElse: () => throw StateError('Cluster not found: $label'),
    );

    // Clear person assignment from all faces
    final faceIds = cluster.faces.map((f) => f.id).toList();
    for (final faceId in faceIds) {
      await _database.faces.updateFacePerson(faceId, null);
    }

    // Mark person as deleted
    final person = await _database.peopleDao.getById(cluster.personId);
    if (person != null) {
      await _database.peopleDao.upsert(
        person.copyWith(
          status: PersonStatus.deleted,
          updatedAt: DateTime.now(),
        ),
      );
    }

    _logger.info(
      'Deleted cluster "$label" (${faceIds.length} faces unassigned)',
    );
  }
}

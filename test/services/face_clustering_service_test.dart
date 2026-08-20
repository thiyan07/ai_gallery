import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/face_dao.dart';
import 'package:ai_gallery/core/database/daos/people_dao.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/person.dart';
import 'package:ai_gallery/features/people/services/face_clustering_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FaceClusteringService Tests', () {
    late FaceClusteringService clusteringService;
    late AppDatabase database;
    late AppLogger logger;
    late FaceDao faceDao;
    late PeopleDao peopleDao;
    late Directory tempDir;

    setUp(() async {
      // Initialize FFI for sqflite
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      logger = const ConsoleAppLogger();

      // Create a temporary directory for the database
      tempDir = await Directory.systemTemp.createTemp('ai_gallery_test.');
      final dbPath = p.join(tempDir.path, 'test_ai_gallery.db');

      // Open database for testing (isolate style to avoid singleton issues)
      database = await AppDatabase.openForIsolate(
        databasePath: dbPath,
        logger: logger,
      );

      faceDao = database.faces;
      peopleDao = database.peopleDao;

      clusteringService = FaceClusteringService(
        logger: logger,
        database: database,
      );
    });

    tearDown(() async {
      await database.dispose();
      // Delete the temporary directory
      if (tempDir != null) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Cosine Similarity', () {
      test('returns 1.0 for identical vectors', () {
        final a = Float32List.fromList([1.0, 0.0, 0.0]);
        final b = Float32List.fromList([1.0, 0.0, 0.0]);
        final similarity = clusteringService.cosineSimilarity(a, b);
        expect(similarity, closeTo(1.0, 0.0001));
      });

      test('returns 0.0 for orthogonal vectors', () {
        final a = Float32List.fromList([1.0, 0.0, 0.0]);
        final b = Float32List.fromList([0.0, 1.0, 0.0]);
        final similarity = clusteringService.cosineSimilarity(a, b);
        expect(similarity, closeTo(0.0, 0.0001));
      });

      test('returns -1.0 for opposite vectors', () {
        final a = Float32List.fromList([1.0, 0.0, 0.0]);
        final b = Float32List.fromList([-1.0, 0.0, 0.0]);
        final similarity = clusteringService.cosineSimilarity(a, b);
        expect(similarity, closeTo(-1.0, 0.0001));
      });

      test('handles different length vectors', () {
        final a = Float32List.fromList([1.0, 0.0]);
        final b = Float32List.fromList([1.0, 0.0, 0.0]);
        final similarity = clusteringService.cosineSimilarity(a, b);
        expect(similarity, equals(0.0));
      });
    });

    group('Face Clustering', () {
      test('clusterAllFaces returns 0 for no faces', () async {
        final count = await clusteringService.clusterAllFaces();
        expect(count, equals(0));
      });

      test('creates clusters for similar faces', () async {
        // Insert test faces with similar embeddings
        final face1 = FaceDetectionRecord(
          id: 'face1',
          photoId: 'photo1',
          x: 0.1,
          y: 0.1,
          width: 0.2,
          height: 0.2,
          confidence: 0.9,
          embedding: Float32List.fromList([0.8, 0.6, 0.0]), // Will be normalized
        );

        final face2 = FaceDetectionRecord(
          id: 'face2',
          photoId: 'photo2',
          x: 0.3,
          y: 0.3,
          width: 0.2,
          height: 0.2,
          confidence: 0.8,
          embedding: Float32List.fromList([0.78, 0.62, 0.0]), // Similar to face1
        );

        final face3 = FaceDetectionRecord(
          id: 'face3',
          photoId: 'photo3',
          x: 0.5,
          y: 0.5,
          width: 0.2,
          height: 0.2,
          confidence: 0.7,
          embedding: Float32List.fromList([0.0, 0.0, 1.0]), // Different from face1/face2
        );

        await database.faces.insertFaces([face1, face2, face3]);

        // Run clustering
        final count = await clusteringService.clusterAllFaces();

        // Should create at least one cluster (face1 and face2 should be similar)
        expect(count, greaterThanOrEqualTo(1));

        // Check that faces were assigned to persons
        final facesWithPerson = await faceDao.getFacesWithPerson();
        expect(facesWithPerson.length, greaterThanOrEqualTo(2));
      });

      test('assigns face to existing person when similar enough', () async {
        // Create an existing person with a face
        final existingFace = FaceDetectionRecord(
          id: 'existing',
          photoId: 'photoExist',
          x: 0.1,
          y: 0.1,
          width: 0.2,
          height: 0.2,
          confidence: 0.9,
          embedding: Float32List.fromList([0.8, 0.6, 0.0]),
        );

        await database.faces.insertFace(existingFace);

        // Manually assign to a person to simulate existing cluster
        final person = Person(
          personId: 'person_test',
          displayName: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await peopleDao.upsert(person);
        await faceDao.updateFacePerson(existingFace.id, person.personId);

        // Create a new similar face
        final newFace = FaceDetectionRecord(
          id: 'new',
          photoId: 'photoNew',
          x: 0.3,
          y: 0.3,
          width: 0.2,
          height: 0.2,
          confidence: 0.8,
          embedding: Float32List.fromList([0.78, 0.62, 0.0]), // Similar to existing
        );

        await database.faces.insertFace(newFace);

        // Cluster the new face
        final personId = await clusteringService.clusterFace(newFace);

        // Should be assigned to existing person
        expect(personId, equals('person_test'));

        // Verify in database
        final updatedFace = await faceDao.getFaceById('new');
        expect(updatedFace?.personId, equals('person_test'));
      });

      test('creates new person when face is not similar enough', () async {
        // Create an existing person with a face
        final existingFace = FaceDetectionRecord(
          id: 'existing',
          photoId: 'photoExist',
          x: 0.1,
          y: 0.1,
          width: 0.2,
          height: 0.2,
          confidence: 0.9,
          embedding: Float32List.fromList([1.0, 0.0, 0.0]),
        );

        await database.faces.insertFace(existingFace);

        // Manually assign to a person to simulate existing cluster
        final person = Person(
          personId: 'person_test',
          displayName: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await peopleDao.upsert(person);
        await faceDao.updateFacePerson(existingFace.id, person.personId);

        // Create a new dissimilar face
        final newFace = FaceDetectionRecord(
          id: 'new',
          photoId: 'photoNew',
          x: 0.3,
          y: 0.3,
          width: 0.2,
          height: 0.2,
          confidence: 0.8,
          embedding: Float32List.fromList([0.0, 1.0, 0.0]), // Orthogonal to existing
        );

        await database.faces.insertFace(newFace);

        // Cluster the new face
        final personId = await clusteringService.clusterFace(newFace);

        // Should create a new person
        expect(personId, isNot(equals('person_test')));
        expect(personId, startsWith('person_'));

        // Verify in database
        final updatedFace = await database.faces.getFaceById('new');
        expect(updatedFace?.personId, equals(personId));
      });

      test('returns null for face with no embedding', () async {
        final faceWithoutEmbedding = FaceDetectionRecord(
          id: 'noembedding',
          photoId: 'photo1',
          x: 0.1,
          y: 0.1,
          width: 0.2,
          height: 0.2,
          confidence: 0.9,
          // No embedding
        );

        final personId = await clusteringService.clusterFace(faceWithoutEmbedding);
        expect(personId, isNull);
      });
    });

    group('Cluster Representatives', () {
      test('gets cluster representatives correctly', () async {
        // Insert faces for two clusters
        final faces = [
          FaceDetectionRecord(
            id: 'face1a',
            photoId: 'photo1',
            x: 0.1,
            y: 0.1,
            width: 0.2,
            height: 0.2,
            confidence: 0.9,
            embedding: Float32List.fromList([0.8, 0.6, 0.0]),
          ),
          FaceDetectionRecord(
            id: 'face1b',
            photoId: 'photo2',
            x: 0.3,
            y: 0.3,
            width: 0.2,
            height: 0.2,
            confidence: 0.7,
            embedding: Float32List.fromList([0.78, 0.62, 0.0]),
          ),
          FaceDetectionRecord(
            id: 'face2a',
            photoId: 'photo3',
            x: 0.5,
            y: 0.5,
            width: 0.2,
            height: 0.2,
            confidence: 0.8,
            embedding: Float32List.fromList([0.0, 0.0, 1.0]),
          ),
        ];

        await database.faces.insertFaces(faces);

        // Manually assign faces to persons to simulate existing clusters
        final personA = Person(
          personId: 'person_a',
          displayName: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final personB = Person(
          personId: 'person_b',
          displayName: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await peopleDao.upsert(personA);
        await peopleDao.upsert(personB);
        await faceDao.updateFacePerson('face1a', personA.personId);
        await faceDao.updateFacePerson('face1b', personA.personId);
        await faceDao.updateFacePerson('face2a', personB.personId);

        final representatives = await clusteringService.getClusterRepresentatives();
        expect(representatives.length, equals(2));

        // Check that we have both persons
        final personIds = representatives.map((e) => e.$1).toList();
        expect(personIds, contains('person_a'));
        expect(personIds, contains('person_b'));
      });
    });
  });
}
import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/people_dao.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/domain/models/face_detection.dart';
import 'package:ai_gallery/domain/models/person.dart';
import 'dart:math';

/// Service for managing people/person groups and face assignments.
class PeopleService {
  PeopleService({
    required AppLogger logger,
    required AppDatabase database,
  })  : _logger = logger,
        _database = database,
        _peopleDao = database.peopleDao;

  final AppLogger _logger;
  final AppDatabase _database;
  final PeopleDao _peopleDao;

  /// Creates a new person with the given display name.
  Future<String> createPerson(String displayName) async {
    _logger.info('Creating person: $displayName');

    final person = Person(
      personId: _generatePersonId(),
      displayName: displayName.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _peopleDao.upsert(person);
    return person.personId;
  }

  /// Creates a new unknown person group (null display name).
  Future<String> createUnknownPerson() async {
    _logger.info('Creating unknown person group');

    final person = Person(
      personId: _generatePersonId(),
      displayName: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _peopleDao.upsert(person);
    return person.personId;
  }

  /// Renames a person.
  Future<void> renamePerson(String personId, String newName) async {
    _logger.info('Renaming person $personId to: $newName');

    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Person name cannot be empty');
    }

    // Check if another active person already has this name (case-insensitive)
    final allActive = await _database.peopleDao.getAllActive();
    final existingPerson = allActive.firstWhere(
      (p) => p.personId != personId &&
             p.displayName?.toLowerCase() == trimmedName.toLowerCase(),
      orElse: () => Person(
        personId: '',
        displayName: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (existingPerson.personId.isNotEmpty) {
      throw ArgumentError('A person with the name "$trimmedName" already exists');
    }

    await _peopleDao.updateDisplayName(personId, trimmedName);
  }

  /// Assigns a face to a person.
  Future<void> assignFaceToPerson(String faceId, String personId) async {
    _logger.info('Assigning face $faceId to person $personId');

    // Verify the person exists and is active
    final person = await _peopleDao.getById(personId);
    if (person == null || person.status != PersonStatus.active) {
      throw ArgumentError('Person not found or not active');
    }

    // Verify the face exists
    final face = await _database.faces.getFaceById(faceId);
    if (face == null) {
      throw ArgumentError('Face not found: $faceId');
    }

    // Assign the face to the person
    await _database.faces.updateFacePerson(faceId, personId);

    // Update the person's timestamp
    await _peopleDao.updateDisplayName(personId, person.displayName);
  }

  /// Removes a face from its assigned person.
  Future<void> removeFaceFromPerson(String faceId) async {
    _logger.info('Removing face $faceId from person');

    await _database.faces.updateFacePerson(faceId, null);
  }

  /// Gets the person assigned to a face, or null if unassigned.
  Future<Person?> getPersonForFace(String faceId) async {
    final face = await _database.faces.getFaceById(faceId);
    if (face == null || face.personId == null) {
      return null;
    }
    return await _peopleDao.getById(face.personId!);
  }

  /// Gets all faces assigned to a person.
  Future<List<FaceDetectionRecord>> getFacesForPerson(String personId) async {
    return await _database.faces.getFacesByPersonId(personId);
  }

  /// Gets all active people.
  Future<List<Person>> getAllPeople() async {
    return await _peopleDao.getAllActive();
  }

  /// Gets all unknown people (null display name).
  Future<List<Person>> getUnknownPeople() async {
    return await _peopleDao.getUnknownPeople();
  }

  /// Gets all known people (non-null display name).
  Future<List<Person>> getKnownPeople() async {
    return await _peopleDao.getKnownPeople();
  }

  /// Gets the count of faces for a person.
  Future<int> getFaceCountForPerson(String personId) async {
    final faces = await _getFacesForPerson(personId);
    return faces.length;
  }

  /// Gets the count of distinct photos that contain faces for a person.
  Future<int> getPhotoCountForPerson(String personId) async {
    final faces = await _getFacesForPerson(personId);
    final photoIds = <String>{};
    for (final face in faces) {
      photoIds.add(face.photoId);
    }
    return photoIds.length;
  }

  /// Sets the cover photo for a person.
  /// Validates that the photo actually contains a face belonging to this person.
  Future<void> setPersonCoverPhoto(String personId, String photoId) async {
    _logger.info('Setting cover photo for person $personId to photo $photoId');

    // Verify the person exists and is active
    final person = await _peopleDao.getById(personId);
    if (person == null || person.status != PersonStatus.active) {
      throw ArgumentError('Person not found or not active');
    }

    // Verify the photo contains at least one face assigned to this person
    final personFaces = await _getFacesForPerson(personId);
    final hasFaceInPhoto = personFaces.any((face) => face.photoId == photoId);

    if (!hasFaceInPhoto) {
      throw ArgumentError('Photo $photoId does not contain any faces assigned to this person');
    }

    await _peopleDao.updateCoverPhoto(personId, photoId);
  }

  /// Merges source person into destination person.
  /// All faces from source person are reassigned to destination person.
  /// Source person is marked as merged.
  Future<void> mergePersons(String sourcePersonId, String destinationPersonId) async {
    _logger.info('Merging person $sourcePersonId into $destinationPersonId');

    // Verify both persons exist and are active
    final sourcePerson = await _peopleDao.getById(sourcePersonId);
    final destPerson = await _peopleDao.getById(destinationPersonId);

    if (sourcePerson == null || sourcePerson.status != PersonStatus.active) {
      throw ArgumentError('Source person not found or not active');
    }

    if (destPerson == null || destPerson.status != PersonStatus.active) {
      throw ArgumentError('Destination person not found or not active');
    }

    if (sourcePersonId == destinationPersonId) {
      throw ArgumentError('Cannot merge person with themselves');
    }

    // Use a transaction to ensure atomicity
    await _database.database.transaction((txn) async {
      // Reassign all faces from source to destination
      final sourceFaces = await _getFacesForPerson(sourcePersonId);
      final faceIds = sourceFaces.map((face) => face.id).toList();

      if (faceIds.isNotEmpty) {
        await _database.faces.assignFacesToPerson(faceIds, destinationPersonId);
      }

      // Mark source person as merged
      await _peopleDao.markAsMerged(sourcePersonId);

      // Update destination person's timestamp
      await _peopleDao.updateDisplayName(destinationPersonId, destPerson.displayName);
    });
  }

  /// Moves a face from its current person to a destination person.
  Future<void> moveFace(String faceId, String destinationPersonId) async {
    _logger.info('Moving face $faceId to person $destinationPersonId');

    // Verify destination person exists and is active
    final destPerson = await _peopleDao.getById(destinationPersonId);
    if (destPerson == null || destPerson.status != PersonStatus.active) {
      throw ArgumentError('Destination person not found or not active');
    }

    // Verify the face exists
    final face = await _database.faces.getFaceById(faceId);
    if (face == null) {
      throw ArgumentError('Face not found: $faceId');
    }

    // Assign face to destination person (this will remove from current person if any)
    await _database.faces.updateFacePerson(faceId, destinationPersonId);

    // Update destination person's timestamp
    await _peopleDao.updateDisplayName(destinationPersonId, destPerson.displayName);
  }

  /// Marks a person as deleted.
  /// Does not delete faces or photos, only removes person associations.
  Future<void> deletePerson(String personId) async {
    _logger.info('Deleting person $personId');

    // Verify the person exists and is active
    final person = await _peopleDao.getById(personId);
    if (person == null || person.status != PersonStatus.active) {
      throw ArgumentError('Person not found or not active');
    }

    // Use a transaction to ensure atomicity
    await _database.database.transaction((txn) async {
      // Remove person assignment from all faces
      final personFaces = await _getFacesForPerson(personId);
      final faceIds = personFaces.map((face) => face.id).toList();

      if (faceIds.isNotEmpty) {
        await _database.faces.removeFacesFromPerson(faceIds);
      }

      // Mark person as deleted
      await _peopleDao.markAsDeleted(personId);
    });
  }

  /// Reactivates a merged or deleted person.
  Future<void> reactivatePerson(String personId) async {
    _logger.info('Reactivating person $personId');

    final person = await _peopleDao.getById(personId);
    if (person == null) {
      throw ArgumentError('Person not found');
    }

    await _peopleDao.reactivate(personId);
  }

  /// Resets all face data: removes person associations, people groups,
  /// and face clustering data. Does NOT delete original photos,
  /// photo metadata, OCR data, or semantic embeddings.
  Future<void> resetAllFaceData() async {
    _logger.info('Resetting all face data');

    await _database.database.transaction((txn) async {
      // Remove all person_id assignments from faces
      await txn.update(
        'faces',
        {'person_id': null},
        where: 'person_id IS NOT NULL',
      );

      // Delete all people records
      await txn.delete('people');
    });

    _logger.info('Face data reset complete');
  }

  String _generatePersonId() {
    return 'person_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  // Helper method to get faces for person (avoiding code duplication)
  Future<List<FaceDetectionRecord>> _getFacesForPerson(String personId) async {
    return await _database.faces.getFacesByPersonId(personId);
  }
}
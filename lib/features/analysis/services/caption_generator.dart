import '../../../core/database/app_database.dart';
import '../../../domain/models/analysis_state.dart';
import '../../../domain/models/photo_metadata.dart';

/// Generates natural-language captions from existing photo metadata.
///
/// Uses scene labels, object tags, people, camera info, and location
/// to construct readable descriptions without any ML model.
class CaptionGenerator {
  final AppDatabase _db;

  CaptionGenerator(this._db);

  /// Generate a caption for a photo from its existing metadata.
  ///
  /// Returns a human-readable description like:
  /// "A sunset landscape photo taken with iPhone 14 Pro at f/1.8.
  ///  Contains: mountain, sky, clouds. Scene: outdoor, nature."
  Future<String> generateCaption(String photoId) async {
    final parts = <String>[];

    // 1. Scene description from analysis_state
    final analysis = await _db.analysisState.getByPhotoId(photoId);
    if (analysis != null) {
      final scenePart = _buildSceneDescription(analysis);
      if (scenePart.isNotEmpty) parts.add(scenePart);
    }

    // 2. Object tags
    final objects = await _db.objectTags.getObjectTagsByPhotoId(photoId);
    if (objects.isNotEmpty) {
      final labels = objects
          .where((o) => o.confidence > 0.5)
          .map((o) => o.label)
          .toSet()
          .toList();
      if (labels.isNotEmpty) {
        parts.add('Contains: ${labels.join(", ")}.');
      }
    }

    // 3. People count from faces
    final faces = await _db.faces.getFacesByPhotoId(photoId);
    if (faces.isNotEmpty) {
      final personFaces = faces.where((f) => f.personId != null).toList();
      if (personFaces.isNotEmpty) {
        parts.add('${personFaces.length} ${personFaces.length == 1 ? "person" : "people"} detected.');
      } else if (faces.length > 1) {
        parts.add('${faces.length} faces detected.');
      }
    }

    // 4. Camera info from metadata
    final metadata = await _db.photoMetadata.getById(photoId);
    if (metadata != null) {
      final cameraPart = _buildCameraDescription(metadata);
      if (cameraPart.isNotEmpty) parts.add(cameraPart);

      final locationPart = _buildLocationDescription(metadata);
      if (locationPart.isNotEmpty) parts.add(locationPart);
    }

    if (parts.isEmpty) {
      return 'Photo $photoId';
    }

    return parts.join(' ');
  }

  String _buildSceneDescription(AnalysisState analysis) {
    final parts = <String>[];

    if (analysis.sceneLabels != null && analysis.sceneLabels!.isNotEmpty) {
      final scenes = analysis.sceneLabels!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (scenes.isNotEmpty) {
        parts.add('Scene: ${scenes.join(", ")}.');
      }
    }

    if (analysis.activityLabels != null && analysis.activityLabels!.isNotEmpty) {
      final activities = analysis.activityLabels!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (activities.isNotEmpty) {
        parts.add('Activity: ${activities.join(", ")}.');
      }
    }

    if (analysis.isScreenshot == true) parts.add('Screenshot.');
    if (analysis.isDocument == true) parts.add('Document.');

    return parts.join(' ');
  }

  String _buildCameraDescription(PhotoMetadata metadata) {
    final parts = <String>[];

    if (metadata.cameraModel != null && metadata.cameraModel!.isNotEmpty) {
      parts.add('Taken with ${metadata.cameraModel}');
      if (metadata.aperture != null) {
        parts.add('at f/${metadata.aperture}');
      }
      if (metadata.iso != null) {
        parts.add('ISO ${metadata.iso}');
      }
      if (parts.length > 1) {
        return '${parts.first} ${parts.sublist(1).join(", ")}.';
      }
      return '${parts.first}.';
    }

    return '';
  }

  String _buildLocationDescription(PhotoMetadata metadata) {
    if (metadata.latitude != null && metadata.longitude != null) {
      return 'Location: ${metadata.latitude!.toStringAsFixed(4)}, ${metadata.longitude!.toStringAsFixed(4)}.';
    }
    return '';
  }
}

import 'package:ai_gallery/domain/models/face_detection.dart';

/// Represents a cluster of faces identified as the same person.
class PersonCluster {
  const PersonCluster({
    required this.personId,
    required this.label,
    required this.faces,
    this.coverPhotoId,
  });

  final String personId;
  final String label;
  final List<FaceDetectionRecord> faces;

  /// Optional cover photo ID from the Person record. When set, UI should
  /// prefer this photo's face as the cover thumbnail.
  final String? coverPhotoId;

  int get faceCount => faces.length;

  /// Distinct photo count for this person.
  int get photoCount => faces.map((f) => f.photoId).toSet().length;

  /// Whether this cluster represents an unnamed/unknown person.
  bool get isUnknown => label == 'Unknown' || label.startsWith('Unknown');

  FaceDetectionRecord? get representativeFace {
    if (faces.isEmpty) return null;
    if (coverPhotoId != null) {
      for (final f in faces) {
        if (f.photoId == coverPhotoId) return f;
      }
    }
    return faces.first;
  }
}

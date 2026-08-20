import 'package:ai_gallery/domain/models/face_detection.dart';

/// Represents a cluster of faces identified as the same person.
class PersonCluster {
  const PersonCluster({
    required this.personId,
    required this.label,
    required this.faces,
  });

  final String personId;
  final String label;
  final List<FaceDetectionRecord> faces;

  int get faceCount => faces.length;

  FaceDetectionRecord? get representativeFace =>
      faces.isNotEmpty ? faces.first : null;
}

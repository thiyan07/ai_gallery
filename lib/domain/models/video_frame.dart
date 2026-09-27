/// An extracted frame from a video.
class VideoFrame {
  final String id;
  final String videoId;
  final int timestampMs;
  final String framePath;
  final int width;
  final int height;
  final double? blurScore;
  final double? qualityScore;
  final bool isRepresentative;
  final DateTime createdAt;

  const VideoFrame({
    required this.id,
    required this.videoId,
    required this.timestampMs,
    required this.framePath,
    required this.width,
    required this.height,
    this.blurScore,
    this.qualityScore,
    this.isRepresentative = false,
    required this.createdAt,
  });

  Duration get timestamp => Duration(milliseconds: timestampMs);

  VideoFrame copyWith({
    String? id,
    String? videoId,
    int? timestampMs,
    String? framePath,
    int? width,
    int? height,
    double? blurScore,
    double? qualityScore,
    bool? isRepresentative,
  }) {
    return VideoFrame(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      timestampMs: timestampMs ?? this.timestampMs,
      framePath: framePath ?? this.framePath,
      width: width ?? this.width,
      height: height ?? this.height,
      blurScore: blurScore ?? this.blurScore,
      qualityScore: qualityScore ?? this.qualityScore,
      isRepresentative: isRepresentative ?? this.isRepresentative,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'video_id': videoId,
        'timestamp_ms': timestampMs,
        'frame_path': framePath,
        'width': width,
        'height': height,
        'blur_score': blurScore,
        'quality_score': qualityScore,
        'is_representative': isRepresentative ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory VideoFrame.fromMap(Map<String, Object?> row) {
    return VideoFrame(
      id: row['id'] as String,
      videoId: row['video_id'] as String,
      timestampMs: row['timestamp_ms'] as int,
      framePath: row['frame_path'] as String,
      width: row['width'] as int,
      height: row['height'] as int,
      blurScore: row['blur_score'] as double?,
      qualityScore: row['quality_score'] as double?,
      isRepresentative: (row['is_representative'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

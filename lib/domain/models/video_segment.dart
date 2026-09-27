import 'dart:typed_data';

/// Represents a temporal segment within a video.
class VideoSegment {
  final String id;
  final String videoId;
  final int startTimeMs;
  final int endTimeMs;
  final String? representativeFramePath;
  final List<double>? embedding;
  final List<String> labels;
  final String? ocrText;
  final List<String> people;
  final double? confidence;
  final DateTime createdAt;

  const VideoSegment({
    required this.id,
    required this.videoId,
    required this.startTimeMs,
    required this.endTimeMs,
    this.representativeFramePath,
    this.embedding,
    this.labels = const [],
    this.ocrText,
    this.people = const [],
    this.confidence,
    required this.createdAt,
  });

  int get durationMs => endTimeMs - startTimeMs;
  Duration get startTime => Duration(milliseconds: startTimeMs);
  Duration get endTime => Duration(milliseconds: endTimeMs);

  VideoSegment copyWith({
    String? id,
    String? videoId,
    int? startTimeMs,
    int? endTimeMs,
    String? representativeFramePath,
    List<double>? embedding,
    List<String>? labels,
    String? ocrText,
    List<String>? people,
    double? confidence,
    DateTime? createdAt,
  }) {
    return VideoSegment(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      representativeFramePath: representativeFramePath ?? this.representativeFramePath,
      embedding: embedding ?? this.embedding,
      labels: labels ?? this.labels,
      ocrText: ocrText ?? this.ocrText,
      people: people ?? this.people,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'video_id': videoId,
        'start_time_ms': startTimeMs,
        'end_time_ms': endTimeMs,
        'representative_frame_path': representativeFramePath,
        'embedding': embedding != null
            ? Float64List.fromList(embedding!).buffer.asUint8List()
            : null,
        'labels': labels.isEmpty ? null : labels.join(','),
        'ocr_text': ocrText,
        'people': people.isEmpty ? null : people.join(','),
        'confidence': confidence,
        'created_at': createdAt.toIso8601String(),
      };

  factory VideoSegment.fromMap(Map<String, Object?> row) {
    return VideoSegment(
      id: row['id'] as String,
      videoId: row['video_id'] as String,
      startTimeMs: row['start_time_ms'] as int,
      endTimeMs: row['end_time_ms'] as int,
      representativeFramePath: row['representative_frame_path'] as String?,
      embedding: row['embedding'] != null
          ? Float64List.view(
              (row['embedding'] as Uint8List).buffer,
            ).toList()
          : null,
      labels: (row['labels'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      ocrText: row['ocr_text'] as String?,
      people: (row['people'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      confidence: row['confidence'] as double?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

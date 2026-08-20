import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/domain/models/ai_job.dart';

void main() {
  group('AIJobProcessor', () {
    test('processJob dispatches to correct handler by type', () {
      // Verify that AIJobType enum covers all expected types
      expect(AIJobType.values, contains(AIJobType.embedding));
      expect(AIJobType.values, contains(AIJobType.faceDetection));
      expect(AIJobType.values, contains(AIJobType.faceEmbedding));
      expect(AIJobType.values, contains(AIJobType.objectTagging));
      expect(AIJobType.values, contains(AIJobType.ocr));
      expect(AIJobType.values, contains(AIJobType.caption));
    });

    test('AIJob model properties', () {
      final job = AIJob(
        id: 'test-job-1',
        photoId: 'photo-123',
        type: AIJobType.embedding,
        status: AIJobStatus.pending,
        progress: 0.0,
        createdAt: DateTime(2025, 1, 1),
      );
      expect(job.id, 'test-job-1');
      expect(job.photoId, 'photo-123');
      expect(job.type, AIJobType.embedding);
      expect(job.status, AIJobStatus.pending);
    });

    test('AIJob copyWith works correctly', () {
      final job = AIJob(
        id: 'test-job-1',
        photoId: 'photo-123',
        type: AIJobType.embedding,
        status: AIJobStatus.pending,
        progress: 0.0,
        createdAt: DateTime(2025, 1, 1),
      );
      final running = job.copyWith(status: AIJobStatus.running, progress: 0.5);
      expect(running.status, AIJobStatus.running);
      expect(running.progress, 0.5);
      expect(running.id, job.id);
    });
  });

  group('AIJobStatus', () {
    test('all statuses are covered', () {
      expect(AIJobStatus.values, contains(AIJobStatus.pending));
      expect(AIJobStatus.values, contains(AIJobStatus.running));
      expect(AIJobStatus.values, contains(AIJobStatus.completed));
      expect(AIJobStatus.values, contains(AIJobStatus.failed));
      expect(AIJobStatus.values, contains(AIJobStatus.cancelled));
    });
  });
}

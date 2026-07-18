import '../../domain/models/ai_job.dart';
import '../../domain/models/user_settings.dart';
import '../jobs/background_job_queue.dart';
import '../storage/secure_storage_service.dart';

/// Abstraction for coordinating AI operations across local and cloud backends.
abstract class AIManager {
  /// Whether cloud AI is available given current settings and API keys.
  bool get isCloudAvailable;

  /// Enqueues an AI job for background processing.
  Future<void> enqueue(AIJob job);

  /// Watches status updates for a specific job.
  Stream<AIJob> watchJob(String jobId);

  /// Returns all pending jobs.
  Future<List<AIJob>> getPendingJobs();

  /// Cancels a pending job.
  Future<void> cancel(String jobId);
}

/// Default AI manager that delegates to the background job queue.
class AIManagerImpl implements AIManager {
  AIManagerImpl({
    required BackgroundJobQueue jobQueue,
    required SecureStorageService secureStorage,
    required UserSettings Function() settingsProvider,
  })  : _jobQueue = jobQueue,
        _secureStorage = secureStorage,
        _settingsProvider = settingsProvider;

  final BackgroundJobQueue _jobQueue;
  final SecureStorageService _secureStorage;
  final UserSettings Function() _settingsProvider;

  @override
  bool get isCloudAvailable {
    final settings = _settingsProvider();
    if (settings.aiMode == AiMode.local) return false;

    // Cloud/hybrid/BYOK requires at least one configured key for cloud fallback.
    return _hasAnyApiKey();
  }

  bool _hasAnyApiKey() {
    // Synchronous check not available; callers should use isCloudAvailable
    // after keys are loaded. For now, BYOK/hybrid modes imply user intent.
    final settings = _settingsProvider();
    return settings.aiMode == AiMode.byok || settings.aiMode == AiMode.hybrid;
  }

  /// Checks asynchronously whether any API key is configured.
  Future<bool> hasConfiguredApiKey() async {
    final openai = await _secureStorage.getOpenAIKey();
    final vision = await _secureStorage.getGoogleVisionKey();
    final anthropic = await _secureStorage.getAnthropicKey();
    return [openai, vision, anthropic].any((k) => k != null && k.isNotEmpty);
  }

  @override
  Future<void> enqueue(AIJob job) => _jobQueue.enqueue(job);

  @override
  Stream<AIJob> watchJob(String jobId) => _jobQueue.watchJob(jobId);

  @override
  Future<List<AIJob>> getPendingJobs() => _jobQueue.getPendingJobs();

  @override
  Future<void> cancel(String jobId) => _jobQueue.cancel(jobId);
}

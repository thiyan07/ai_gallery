import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_gallery/core/di/providers.dart';
import 'package:ai_gallery/features/people/services/face_clustering_service.dart';
import 'package:ai_gallery/domain/models/person_cluster.dart';

/// Provider for FaceClusteringService.
final faceClusteringServiceProvider = Provider<FaceClusteringService>((ref) {
  throw UnimplementedError(
    'Use faceClusteringServiceProviderAsync for async initialization',
  );
});

/// Async provider for FaceClusteringService that initializes with database.
final faceClusteringServiceProviderAsync =
    AsyncNotifierProvider<FaceClusteringServiceNotifier, FaceClusteringService>(
      FaceClusteringServiceNotifier.new,
    );

class FaceClusteringServiceNotifier
    extends AsyncNotifier<FaceClusteringService> {
  @override
  Future<FaceClusteringService> build() async {
    final logger = ref.read(appLoggerProvider);
    final database = await ref.read(appDatabaseProvider.future);
    return FaceClusteringService(logger: logger, database: database);
  }
}

/// Provider for people clusters stream.
final peopleClustersProvider =
    AsyncNotifierProvider<PeopleClustersNotifier, List<PersonCluster>>(
      PeopleClustersNotifier.new,
    );

class PeopleClustersNotifier extends AsyncNotifier<List<PersonCluster>> {
  bool _isClustering = false;

  @override
  Future<List<PersonCluster>> build() async {
    final service = await ref.watch(faceClusteringServiceProviderAsync.future);
    return service.getPeopleClusters();
  }

  /// Refresh the clusters list.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = await ref.read(faceClusteringServiceProviderAsync.future);
      return service.getPeopleClusters();
    });
  }

  /// Recluster all faces. Guarded against concurrent calls.
  Future<void> recluster() async {
    if (_isClustering) return;
    _isClustering = true;
    try {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() async {
        final service = await ref.read(faceClusteringServiceProviderAsync.future);
        await service.clusterAllFaces();
        return service.getPeopleClusters();
      });
    } finally {
      _isClustering = false;
    }
  }
}

/// Provider for a single person cluster by label.
final personClusterProvider = FutureProvider.family<PersonCluster?, String>((
  ref,
  label,
) async {
  final service = await ref.watch(faceClusteringServiceProviderAsync.future);
  final clusters = await service.getPeopleClusters();
  try {
    return clusters.firstWhere((c) => c.label == label);
  } catch (_) {
    return null;
  }
});

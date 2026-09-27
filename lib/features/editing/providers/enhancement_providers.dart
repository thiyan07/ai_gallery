import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../services/image_enhancement_service.dart';

final imageEnhancementServiceProvider = Provider<ImageEnhancementService>((ref) {
  final logger = ref.watch(appLoggerProvider);
  final manager = ref.watch(modelManagerProvider);
  final downloader = ref.watch(modelDownloaderProvider);
  return ImageEnhancementService(
    logger: logger,
    modelManager: manager,
    modelDownloader: downloader,
  );
});

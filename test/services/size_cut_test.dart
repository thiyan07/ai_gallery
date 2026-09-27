import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/ai/providers/local_embedding_provider.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/utils/device_capabilities.dart';

/// APK size-cut: SigLIP must be runtime-downloadable, never bundled.
///
/// The 1.14 GB bundled SigLIP assets were removed from assets/models/.
/// These tests pin the new contract:
/// - SigLIP vision + text presets exist with remote URLs (download path).
/// - Bundled SigLIP .onnx files are absent (no 1.1 GB payload in APK).
/// - Missing model initializes to MODEL_NOT_READY (graceful), never a crash.
/// - Small on-device models (faces/OCR/objects) stay bundled (no loss).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Size-cut: SigLIP runtime-download-only', () {
    test('SigLIP vision preset is runtime-downloadable', () {
      final preset = ModelPresets.presets['siglip-base-patch16-224'];
      expect(preset, isNotNull);
      expect(preset!.modelId, contains('/'));
      expect(preset.filename, endsWith('.onnx'));
      expect(preset.modelType, ModelType.visionEncoder);
    });

    test('SigLIP text preset is runtime-downloadable', () {
      final preset = ModelPresets.presets['siglip-base-patch16-224-text'];
      expect(preset, isNotNull);
      expect(preset!.modelId, contains('/'));
      expect(preset.filename, endsWith('.onnx'));
      expect(preset.modelType, ModelType.textEncoder);
    });

    test('bundled SigLIP payload is absent from assets', () {
      expect(
        File('assets/models/siglip_base_patch16_224.onnx').existsSync(),
        isFalse,
        reason: '336M vision model must not ship in the APK',
      );
      expect(
        File('assets/models/siglip_text_encoder.onnx').existsSync(),
        isFalse,
        reason: '804M text encoder must not ship in the APK',
      );
    });

    test('small on-device models stay bundled (no feature loss)', () {
      for (final f in [
        'assets/models/yolov8n.onnx',
        'assets/models/mobilefacenet.onnx',
        'assets/models/ppocr_det.onnx',
        'assets/models/ppocr_rec.onnx',
        'assets/models/blaze_face_short_range.onnx',
        'assets/models/siglip_tokenizer.model',
      ]) {
        expect(File(f).existsSync(), isTrue, reason: '$f must stay bundled');
      }
    });

    test('missing model fails as MODEL_NOT_READY, not a crash', () async {
      final logger = const ConsoleAppLogger();
      final downloader = ModelDownloader(logger: logger);
      final manager = ModelManager(downloader: downloader, logger: logger);
      final provider = LocalEmbeddingProvider(
        logger: logger,
        modelManager: manager,
        modelAssetPath: 'assets/models/siglip_base_patch16_224.onnx',
        textModelAssetPath: 'assets/models/siglip_text_encoder.onnx',
        tokenizerAssetPath: 'assets/models/siglip_tokenizer.model',
        forceTier: DeviceTier.high,
      );
      try {
        await provider.initialize();
        // If init somehow succeeds (model downloaded), provider is usable.
        expect(await provider.isAvailable, isTrue);
      } on StateError catch (e) {
        expect(
          e.message,
          contains('MODEL_NOT_READY'),
          reason: 'fresh install without model must report MODEL_NOT_READY',
        );
        expect(
          e.message,
          isNot(contains('add a SigLIP')),
          reason: 'must not ask users to add files to assets/',
        );
      } finally {
        await provider.dispose();
      }
    });
  });
}

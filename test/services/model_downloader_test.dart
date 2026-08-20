import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelDownloader Tests', () {
    late ModelDownloader downloader;
    late AppLogger logger;
    late Directory tempDir;

    setUp(() async {
      logger = const ConsoleAppLogger();
      downloader = ModelDownloader(logger: logger);
      tempDir = await Directory.systemTemp.createTemp('ai_gallery_model_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Platform Detection', () {
      test('confirms current platform for test context', () {
        expect(Platform.operatingSystem, isNotEmpty);
      });
    });

    group('State Management', () {
      test('getModelState returns notInstalled for unknown model', () {
        final state = downloader.getModelState('nonexistent_model');
        expect(state, equals(ModelState.notInstalled));
      });
    });

    group('ModelConfig', () {
      test('resolvedLocalName falls back to modelId', () {
        const config = ModelConfig(
          modelId: 'test/model',
          filename: 'test.onnx',
          description: 'Test',
          inputSize: 224,
          embeddingDim: 768,
        );
        expect(config.resolvedLocalName, 'test_model');
      });

      test('resolvedLocalName uses localName when set', () {
        const config = ModelConfig(
          modelId: 'test/model',
          filename: 'test.onnx',
          description: 'Test',
          inputSize: 224,
          embeddingDim: 768,
          localName: 'custom_name',
        );
        expect(config.resolvedLocalName, 'custom_name');
      });

      test('downloadUrl builds correct URL with default revision', () {
        const config = ModelConfig(
          modelId: 'owner/repo',
          filename: 'model.onnx',
          description: 'Test',
          inputSize: 224,
          embeddingDim: 768,
        );
        expect(
          config.downloadUrl,
          'https://huggingface.co/owner/repo/resolve/main/model.onnx',
        );
      });

      test('downloadUrl uses custom revision', () {
        const config = ModelConfig(
          modelId: 'owner/repo',
          filename: 'model.onnx',
          description: 'Test',
          inputSize: 224,
          embeddingDim: 768,
          revision: 'v1.0',
        );
        expect(
          config.downloadUrl,
          'https://huggingface.co/owner/repo/resolve/v1.0/model.onnx',
        );
      });

      test('ModelConfig has correct default values', () {
        const config = ModelConfig(
          modelId: 'test',
          filename: 'test.onnx',
          description: 'Desc',
          inputSize: 224,
          embeddingDim: 768,
        );
        expect(config.modelType, ModelType.unknown);
        expect(config.revision, 'main');
        expect(config.sha256, isNull);
        expect(config.isRequired, isFalse);
        expect(config.localName, isNull);
        expect(config.expectedMinSizeBytes, isNull);
      });

      test('ModelConfig isPlatformSupported returns bool', () {
        const config = ModelConfig(
          modelId: 'test',
          filename: 'test.onnx',
          description: 'Desc',
          inputSize: 224,
          embeddingDim: 768,
        );
        expect(config.isPlatformSupported, isA<bool>());
      });
    });

    group('ModelState enum', () {
      test('all expected states exist', () {
        expect(ModelState.values, contains(ModelState.notInstalled));
        expect(ModelState.values, contains(ModelState.downloading));
        expect(ModelState.values, contains(ModelState.verifying));
        expect(ModelState.values, contains(ModelState.installed));
        expect(ModelState.values, contains(ModelState.loading));
        expect(ModelState.values, contains(ModelState.ready));
        expect(ModelState.values, contains(ModelState.failed));
      });
    });

    group('ModelDownloadResult', () {
      test('isSuccess is true for installed state', () {
        const result = ModelDownloadResult(
          localPath: '/test',
          state: ModelState.installed,
        );
        expect(result.isSuccess, isTrue);
      });

      test('isSuccess is true for ready state', () {
        const result = ModelDownloadResult(
          localPath: '/test',
          state: ModelState.ready,
        );
        expect(result.isSuccess, isTrue);
      });

      test('isSuccess is false for failed state', () {
        const result = ModelDownloadResult(
          localPath: '/test',
          state: ModelState.failed,
          errorMessage: 'error',
        );
        expect(result.isSuccess, isFalse);
      });
    });
  });
}

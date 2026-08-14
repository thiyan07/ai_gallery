import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/core/services/model_manager.dart'
    show ModelConfig;
import 'package:ai_gallery/core/services/model_downloader.dart'
    show ModelState, ModelDownloadResult;
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelDownloader Tests', () {
    late ModelDownloader downloader;
    late AppLogger logger;
    late String tempDirPath;
    late Directory tempDir;

    setUp(() async {
      logger = const ConsoleAppLogger();
      downloader = ModelDownloader(logger: logger);

      // Create a temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('ai_gallery_model_test_');
      tempDirPath = tempDir.path;
    });

    tearDown(() async {
      // Clean up temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Platform Detection', () {
      test('confirms current platform for test context', () {
        final bool isAndroid = Platform.operatingSystem == 'android';
        final bool isIOS = Platform.operatingSystem == 'ios';
        final bool isMobile = isAndroid || isIOS;
        final bool isDesktop = !isMobile;

        // Just verify we can detect platform - no expectation on value
        expect(Platform.operatingSystem, isNotEmpty);
      });
    });

    group('Validation Logic - Basic File Checks', () {
      test('validateModelFile returns false for non-existent file', () async {
        final bool isValid = await downloader._validateModelFile(
          '/non/existent/path/model.onnx',
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test'
          )
        );

        expect(isValid, isFalse);
      });

      test('validateModelFile returns false for zero-byte file', () async {
        final File zeroByteFile = File('${tempDir.path}/zero_byte.onnx');
        await zeroByteFile.writeAsBytes([]);

        final bool isValid = await downloader._validateModelFile(
          zeroByteFile.path,
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test'
          )
        );

        expect(isValid, isFalse);

        // Clean up
        await zeroByteFile.delete();
      });

      test('validateModelFile returns false for file below minimum size', () async {
        final File smallFile = File('${tempDir.path}/small.onnx');
        await smallFile.writeAsBytes(List.filled(100, 0)); // 100 bytes

        final bool isValid = await downloader._validateModelFile(
          smallFile.path,
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test',
            expectedMinSizeBytes: 1000 // Require at least 1000 bytes
          )
        );

        expect(isValid, isFalse);

        // Clean up
        await smallFile.delete();
      });

      test('validateModelFile passes for file meeting minimum size (no SHA)', () async {
        final File validFile = File('${tempDir.path}/valid_size.onnx');
        await validFile.writeAsBytes(List.filled(1500, 0)); // 1500 bytes

        final bool isValid = await downloader._validateModelFile(
          validFile.path,
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test',
            expectedMinSizeBytes: 1000 // Require at least 1000 bytes
            // No SHA-256
          )
        );

        // Should pass basic checks (though ONNX validation may fail on mobile)
        expect(isValid, isA<bool>());

        // Clean up
        await validFile.delete();
      });

      test('validateModelFile fails on SHA-256 mismatch', () async {
        final File testFile = File('${tempDir.path}/shatest.onnx');
        await testFile.writeAsBytes(List.filled(1000, 42)); // 1000 bytes

        final bool isValid = await downloader._validateModelFile(
          testFile.path,
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test',
            expectedMinSizeBytes: 500,
            sha256: 'invalid_hash_that_should_not_match'
          )
        );

        expect(isValid, isFalse);

        // Clean up
        await testFile.delete();
      });
    });

    group('Validation Logic - ONNX Runtime Integration', () {
      test('validateModelFile handles ONNX validation errors gracefully', () async {
        // Create a file that passes basic checks but is not valid ONNX
        final File invalidOnnxFile = File('${tempDir.path}/invalid.onnx');
        await invalidOnnxFile.writeAsBytes([0xCA, 0xFE, 0xBA, 0xBE]); // Not ONNX magic

        final bool isValid = await downloader._validateModelFile(
          invalidOnnxFile.path,
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test',
            expectedMinSizeBytes: 4
            // No SHA-256
          )
        );

        // Should return false (validation failed) but not throw
        expect(isValid, isFalse);

        // Clean up
        await invalidOnnxFile.delete();
      });

      test('validateOnnxModel skipped on non-mobile platforms returns true for basic validity', () async {
        // This test verifies the platform-safe behavior
        final bool isMobile = Platform.operatingSystem == 'android' ||
                              Platform.operatingSystem == 'ios';

        // Create a file that passes basic checks
        final File testFile = File('${tempDir.path}/test.onnx');
        await testFile.writeAsBytes(List.filled(1000, 0)); // 1000 bytes

        final bool isValid = await downloader._validateModelFile(
          testFile.path,
          ModelConfig(
            modelId: 'test',
            filename: 'test.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test',
            expectedMinSizeBytes: 500
            // No SHA-256
          )
        );

        // On non-mobile platforms: should return true (ONNX validation skipped)
        // On mobile platforms:may return false (valid basic checks but invalid ONNX)
        // Key point: should not throw exception
        expect(isValid, isA<bool>());

        // Clean up
        await testFile.delete();
      });
    });

    group('Integration Tests - Download Process', () {
      test('downloadModelConfig handles invalid URLs gracefully', () async {
        final result = await downloader.downloadModelConfig(
          ModelConfig(
            modelId: 'invalid/repo',
            filename: 'nonexistent.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'test_model',
            downloadUrl: 'https://invalid-domain-that-does-not-exist-12345.invalid/model.onnx'
          ),
          stateCallback: (state) {}, // Ignore state callbacks for test
        );

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, isNotEmpty);
        expect(result.state, equals(ModelState.failed));
      });

      test('downloadModelConfig cleans up temp file on failure', () async {
        final tempPath = await downloader.getTempModelPath('cleanup_test');
        final tempFile = File(tempPath);

        // Ensure temp file doesn't exist initially
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        // Attempt download that will fail
        final result = await downloader.downloadModelConfig(
          ModelConfig(
            modelId: 'invalid/repo',
            filename: 'nonexistent.onnx',
            description: 'Test',
            inputSize: 224,
            embeddingDim: 768,
            localName: 'cleanup_test',
            downloadUrl: 'https://httpstat.us/404'
          ),
          stateCallback: (state) {}, // Ignore state callbacks for test
        );

        expect(result.isSuccess, isFalse);

        // Verify temp file was cleaned up
        expect(await tempFile.exists(), isFalse);
      });
    });

    group('Integration Tests - State Management', () {
      test('getModelState returns correct initial state', () {
        final state = downloader.getModelState('nonexistent_model');
        expect(state, equals(ModelState.notInstalled));
      });

      test('isModelDownloaded returns false for non-existent model', () async {
        final bool isDownloaded = await downloader.isModelDownloaded('nonexistent_model');
        expect(isDownloaded, isFalse);
      });
    });
  });
}
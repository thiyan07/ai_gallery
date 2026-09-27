import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/storage/secure_storage_service.dart';

/// Result of an API connection test.
class ConnectionTestResult {
  final bool success;
  final String message;
  final int? statusCode;

  const ConnectionTestResult({
    required this.success,
    required this.message,
    this.statusCode,
  });
}

/// Tests API key connectivity by making lightweight requests.
///
/// Uses minimal token/cost requests to verify keys are valid.
class ApiConnectionTester {
  final SecureStorageService _secureStorage;

  ApiConnectionTester(this._secureStorage);

  /// Test OpenAI API key by listing models (minimal cost).
  Future<ConnectionTestResult> testOpenAI() async {
    final key = await _secureStorage.getOpenAIKey();
    if (key == null || key.isEmpty) {
      return const ConnectionTestResult(
        success: false,
        message: 'No API key configured.',
      );
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.openai.com/v1/models'),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return const ConnectionTestResult(
          success: true,
          message: 'Connection successful. API key is valid.',
          statusCode: 200,
        );
      } else if (response.statusCode == 401) {
        return const ConnectionTestResult(
          success: false,
          message: 'Invalid API key. Please check your key.',
          statusCode: 401,
        );
      } else {
        return ConnectionTestResult(
          success: false,
          message: 'Unexpected response (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: 'Connection failed: $e',
      );
    }
  }

  /// Test Google Vision API key by listing features (minimal cost).
  Future<ConnectionTestResult> testGoogleVision() async {
    final key = await _secureStorage.getGoogleVisionKey();
    if (key == null || key.isEmpty) {
      return const ConnectionTestResult(
        success: false,
        message: 'No API key configured.',
      );
    }

    try {
      // Use a minimal request to verify the key works
      final response = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [
            {
              'image': {'content': ''},
              'features': [{'type': 'LABEL_DETECTION', 'maxResults': 1}],
            }
          ],
        }),
      ).timeout(const Duration(seconds: 10));

      // 400 = bad request (expected with empty image) but key is valid
      // 401/403 = invalid key
      // 200 = success
      if (response.statusCode == 200 || response.statusCode == 400) {
        return const ConnectionTestResult(
          success: true,
          message: 'Connection successful. API key is valid.',
          statusCode: 200,
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return const ConnectionTestResult(
          success: false,
          message: 'Invalid API key. Please check your key.',
          statusCode: 401,
        );
      } else {
        return ConnectionTestResult(
          success: false,
          message: 'Unexpected response (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: 'Connection failed: $e',
      );
    }
  }

  /// Test Anthropic API key by listing models (minimal cost).
  Future<ConnectionTestResult> testAnthropic() async {
    final key = await _secureStorage.getAnthropicKey();
    if (key == null || key.isEmpty) {
      return const ConnectionTestResult(
        success: false,
        message: 'No API key configured.',
      );
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.anthropic.com/v1/models'),
        headers: {
          'x-api-key': key,
          'anthropic-version': '2023-06-01',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return const ConnectionTestResult(
          success: true,
          message: 'Connection successful. API key is valid.',
          statusCode: 200,
        );
      } else if (response.statusCode == 401) {
        return const ConnectionTestResult(
          success: false,
          message: 'Invalid API key. Please check your key.',
          statusCode: 401,
        );
      } else {
        return ConnectionTestResult(
          success: false,
          message: 'Unexpected response (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: 'Connection failed: $e',
      );
    }
  }
}

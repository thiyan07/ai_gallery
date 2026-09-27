import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const String _keyOpenAI = 'openai_api_key';
  static const String _keyGoogleVision = 'google_vision_api_key';
  static const String _keyAnthropic = 'anthropic_api_key';
  static const String _keyHiddenPin = 'hidden_album_pin';

  // OpenAI Key
  Future<String?> getOpenAIKey() => _secureStorage.read(key: _keyOpenAI);
  Future<void> setOpenAIKey(String value) => _secureStorage.write(key: _keyOpenAI, value: value);
  Future<void> deleteOpenAIKey() => _secureStorage.delete(key: _keyOpenAI);

  // Google Vision Key
  Future<String?> getGoogleVisionKey() => _secureStorage.read(key: _keyGoogleVision);
  Future<void> setGoogleVisionKey(String value) => _secureStorage.write(key: _keyGoogleVision, value: value);
  Future<void> deleteGoogleVisionKey() => _secureStorage.delete(key: _keyGoogleVision);

  // Anthropic Key
  Future<String?> getAnthropicKey() => _secureStorage.read(key: _keyAnthropic);
  Future<void> setAnthropicKey(String value) => _secureStorage.write(key: _keyAnthropic, value: value);
  Future<void> deleteAnthropicKey() => _secureStorage.delete(key: _keyAnthropic);

  // General helpers
  Future<void> clearAllKeys() => _secureStorage.deleteAll();

  // Hidden album PIN (4+ digits, stored in encrypted storage)
  Future<String?> getHiddenPin() => _secureStorage.read(key: _keyHiddenPin);
  Future<void> setHiddenPin(String pin) =>
      _secureStorage.write(key: _keyHiddenPin, value: pin);
  Future<void> deleteHiddenPin() => _secureStorage.delete(key: _keyHiddenPin);
  Future<bool> hasHiddenPin() async =>
      (await getHiddenPin())?.isNotEmpty ?? false;
  Future<bool> verifyHiddenPin(String pin) async =>
      (await getHiddenPin()) == pin;
}

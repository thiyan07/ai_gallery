import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/visibility_dao.dart';
import 'package:ai_gallery/core/storage/secure_storage_service.dart';

/// Archive + Hidden flows (Ente-style organization, reimplemented).
///
/// - Archived: hidden from the timeline grid, still visible in albums and
///   search results. No authentication needed.
/// - Hidden: excluded from timeline, albums, and search. Viewing requires
///   the Hidden PIN (stored in encrypted storage).
class VisibilityService {
  VisibilityService({
    required AppDatabase database,
    required SecureStorageService secureStorage,
  })  : _db = database,
        _secureStorage = secureStorage;

  final AppDatabase _db;
  final SecureStorageService _secureStorage;

  Future<void> archive(String photoId) =>
      _db.visibility.setMode(photoId, VisibilityMode.archived);

  Future<void> hide(String photoId) =>
      _db.visibility.setMode(photoId, VisibilityMode.hidden);

  /// Back to normal visibility.
  Future<void> unhide(String photoId) => _db.visibility.clearMode(photoId);

  Future<Set<String>> archivedIds() =>
      _db.visibility.idsInMode(VisibilityMode.archived);

  Future<Set<String>> hiddenIds() =>
      _db.visibility.idsInMode(VisibilityMode.hidden);

  Future<VisibilityMode?> modeOf(String photoId) =>
      _db.visibility.modeOf(photoId);

  // ── Hidden PIN ──

  Future<bool> hasPin() => _secureStorage.hasHiddenPin();

  /// Set a new PIN (must be 4+ digits).
  Future<bool> setPin(String pin) async {
    if (!isValidPin(pin)) return false;
    await _secureStorage.setHiddenPin(pin);
    return true;
  }

  Future<bool> verifyPin(String pin) => _secureStorage.verifyHiddenPin(pin);

  static bool isValidPin(String pin) =>
      pin.length >= 4 && RegExp(r'^\d+$').hasMatch(pin);
}

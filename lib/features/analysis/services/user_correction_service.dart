import 'package:uuid/uuid.dart';

import '../../../core/database/daos/correction_dao.dart';
import '../../../domain/models/user_correction.dart';

/// Manages user corrections to AI analysis results.
///
/// When the user says "this is not a dog" or "this photo is not blurry",
/// we record the correction and suppress the same incorrect result
/// in the future.
class UserCorrectionService {
  UserCorrectionService({required CorrectionDao correctionDao})
      : _correctionDao = correctionDao;

  final CorrectionDao _correctionDao;
  static const _uuid = Uuid();

  /// Record a correction where the user removes an incorrect label.
  Future<UserCorrection> removeLabel({
    required String photoId,
    required CorrectionType type,
    required String originalLabel,
  }) async {
    final correction = UserCorrection(
      correctionId: _uuid.v4(),
      photoId: photoId,
      type: type,
      originalLabel: originalLabel,
      action: CorrectionAction.removeLabel,
      createdAt: DateTime.now(),
    );

    await _correctionDao.insert(correction);
    return correction;
  }

  /// Record a correction where the user provides the correct label.
  Future<UserCorrection> replaceLabel({
    required String photoId,
    required CorrectionType type,
    required String originalLabel,
    required String correctedLabel,
  }) async {
    final correction = UserCorrection(
      correctionId: _uuid.v4(),
      photoId: photoId,
      type: type,
      originalLabel: originalLabel,
      correctedLabel: correctedLabel,
      action: CorrectionAction.replaceLabel,
      createdAt: DateTime.now(),
    );

    await _correctionDao.insert(correction);
    return correction;
  }

  /// Hide a result/group from appearing.
  Future<UserCorrection> hideResult({
    required String photoId,
    required CorrectionType type,
    required String originalLabel,
  }) async {
    final correction = UserCorrection(
      correctionId: _uuid.v4(),
      photoId: photoId,
      type: type,
      originalLabel: originalLabel,
      action: CorrectionAction.hide,
      createdAt: DateTime.now(),
    );

    await _correctionDao.insert(correction);
    return correction;
  }

  /// Check if a label has been corrected for a photo.
  Future<bool> isLabelCorrected(
    String photoId,
    CorrectionType type,
    String label,
  ) async {
    return _correctionDao.hasCorrection(photoId, type, label);
  }

  /// Get all removed labels for a photo (to suppress in future results).
  Future<List<String>> getRemovedLabels(
    String photoId,
    CorrectionType type,
  ) async {
    return _correctionDao.getRemovedLabels(photoId, type);
  }

  /// Get globally removed labels for a type (cross-photo suppression).
  Future<Set<String>> getGlobalRemovedLabels(CorrectionType type) async {
    return _correctionDao.getGlobalRemovedLabels(type);
  }

  /// Filter out corrected labels from a list of results.
  ///
  /// Returns labels that have NOT been removed by user corrections.
  Future<List<String>> filterCorrectedLabels(
    String photoId,
    CorrectionType type,
    List<String> labels,
  ) async {
    final removed = await getRemovedLabels(photoId, type);
    final removedSet = removed.toSet();
    return labels.where((l) => !removedSet.contains(l)).toList();
  }

  /// Get all corrections for a photo.
  Future<List<UserCorrection>> getCorrectionsForPhoto(String photoId) async {
    return _correctionDao.getByPhotoId(photoId);
  }

  /// Get total correction count.
  Future<int> getCorrectionCount() async {
    return _correctionDao.count();
  }
}

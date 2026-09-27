/// A user correction to an AI analysis result.
///
/// When the user says "this is not a dog" or "this photo is not blurry",
/// we record the correction and suppress the same incorrect result
/// in the future.
class UserCorrection {
  final String correctionId;
  final String photoId;
  final CorrectionType type;
  final String originalLabel;
  final String? correctedLabel;
  final CorrectionAction action;
  final DateTime createdAt;

  const UserCorrection({
    required this.correctionId,
    required this.photoId,
    required this.type,
    required this.originalLabel,
    this.correctedLabel,
    required this.action,
    required this.createdAt,
  });

  UserCorrection copyWith({
    String? correctionId,
    String? photoId,
    CorrectionType? type,
    String? originalLabel,
    String? correctedLabel,
    CorrectionAction? action,
    DateTime? createdAt,
  }) {
    return UserCorrection(
      correctionId: correctionId ?? this.correctionId,
      photoId: photoId ?? this.photoId,
      type: type ?? this.type,
      originalLabel: originalLabel ?? this.originalLabel,
      correctedLabel: correctedLabel ?? this.correctedLabel,
      action: action ?? this.action,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'correction_id': correctionId,
        'photo_id': photoId,
        'type': type.index,
        'original_label': originalLabel,
        'corrected_label': correctedLabel,
        'action': action.index,
        'created_at': createdAt.toIso8601String(),
      };

  factory UserCorrection.fromMap(Map<String, Object?> row) => UserCorrection(
        correctionId: row['correction_id'] as String,
        photoId: row['photo_id'] as String,
        type: CorrectionType.values[row['type'] as int],
        originalLabel: row['original_label'] as String,
        correctedLabel: row['corrected_label'] as String?,
        action: CorrectionAction.values[row['action'] as int],
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserCorrection &&
          runtimeType == other.runtimeType &&
          correctionId == other.correctionId;

  @override
  int get hashCode => correctionId.hashCode;
}

/// What type of AI result was corrected.
enum CorrectionType {
  objectLabel,
  sceneLabel,
  blurClassification,
  exposureClassification,
  screenshotDetection,
  documentDetection,
  personLabel,
  duplicateGroup,
}

/// What the user did.
enum CorrectionAction {
  /// User says the label is wrong (should be removed).
  removeLabel,

  /// User provides the correct label.
  replaceLabel,

  /// User hides this result/group.
  hide,

  /// User ignores this suggestion.
  ignore,
}

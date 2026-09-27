import '../models/gallery_action.dart';

/// Registry of available gallery actions with validation rules.
///
/// Each action type maps to a validation function that checks
/// whether the parameters are valid before execution.
class ActionRegistry {
  ActionRegistry() {
    _registerDefaults();
  }

  final Map<GalleryActionType, ActionValidator> _validators = {};

  /// Register a validator for an action type.
  void register(GalleryActionType type, ActionValidator validator) {
    _validators[type] = validator;
  }

  /// Validate an action before execution.
  ValidationResult validate(GalleryAction action) {
    final validator = _validators[action.type];
    if (validator == null) {
      return ValidationResult.valid();
    }
    return validator(action.parameters);
  }

  /// Check if an action type is registered.
  bool isRegistered(GalleryActionType type) {
    return _validators.containsKey(type);
  }

  /// Get all registered action types.
  List<GalleryActionType> get registeredTypes =>
      _validators.keys.toList();

  void _registerDefaults() {
    register(GalleryActionType.showSearchResults, (params) {
      if (params['photoIds'] == null && params['intent'] == null) {
        return ValidationResult.invalid('Either photoIds or intent required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.openPhoto, (params) {
      if (params['photoId'] == null || (params['photoId'] as String).isEmpty) {
        return ValidationResult.invalid('photoId is required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.openPerson, (params) {
      if (params['personId'] == null && params['personName'] == null) {
        return ValidationResult.invalid('personId or personName required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.openEvent, (params) {
      if (params['eventId'] == null) {
        return ValidationResult.invalid('eventId is required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.openAlbum, (params) {
      if (params['albumId'] == null) {
        return ValidationResult.invalid('albumId is required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.createSmartAlbum, (params) {
      if (params['title'] == null || (params['title'] as String).isEmpty) {
        return ValidationResult.invalid('Album title is required');
      }
      if (params['photoIds'] == null ||
          (params['photoIds'] as List).isEmpty) {
        return ValidationResult.invalid('At least one photo required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.createMemory, (params) {
      if (params['memoryTitle'] == null ||
          (params['memoryTitle'] as String).isEmpty) {
        return ValidationResult.invalid('Memory title is required');
      }
      if (params['photoIds'] == null ||
          (params['photoIds'] as List).isEmpty) {
        return ValidationResult.invalid('At least one photo required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.openEditor, (_) => ValidationResult.valid());

    register(GalleryActionType.deletePhotos, (params) {
      final ids = params['photoIds'] as List?;
      if (ids == null || ids.isEmpty) {
        return ValidationResult.invalid('photoIds is required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.addFavorites, (params) {
      final ids = params['photoIds'] as List?;
      if (ids == null || ids.isEmpty) {
        return ValidationResult.invalid('photoIds is required');
      }
      return ValidationResult.valid();
    });

    register(GalleryActionType.removeFavorites, (params) {
      final ids = params['photoIds'] as List?;
      if (ids == null || ids.isEmpty) {
        return ValidationResult.invalid('photoIds is required');
      }
      return ValidationResult.valid();
    });
  }
}

/// Validation result for an action.
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult._({required this.isValid, this.error});

  factory ValidationResult.valid() => const ValidationResult._(isValid: true);
  factory ValidationResult.invalid(String error) =>
      ValidationResult._(isValid: false, error: error);
}

/// Validator function type for action parameters.
typedef ActionValidator = ValidationResult Function(
    Map<String, dynamic> parameters);

import 'gallery_intent.dart';
import 'gallery_query.dart';

/// Short-lived conversational context for multi-turn gallery queries.
///
/// Scoped to a single gallery session. Never persists full photo data.
/// Supports follow-up queries like "only the ones with Alex".
class ConversationalContext {
  /// The last successful query executed.
  GalleryQuery? _lastQuery;

  /// The last set of photo IDs returned.
  List<String> _lastPhotoIds = [];

  /// The last intent.
  GalleryIntent _lastIntent = GalleryIntent.unknown;

  /// The original query text.
  String _lastQueryText = '';

  /// Timestamp of last interaction.
  DateTime _lastInteraction = DateTime.now();

  /// Get the last query.
  GalleryQuery? get lastQuery => _lastQuery;

  /// Get the last photo IDs.
  List<String> get lastPhotoIds => List.unmodifiable(_lastPhotoIds);

  /// Get the last intent.
  GalleryIntent get lastIntent => _lastIntent;

  /// Get the last query text.
  String get lastQueryText => _lastQueryText;

  /// Whether context is still fresh (within 30 minutes).
  bool get isStale =>
      DateTime.now().difference(_lastInteraction).inMinutes > 30;

  /// Whether there is an active context.
  bool get hasContext => _lastQuery != null && !isStale;

  /// Update context with a new query and result.
  void update({
    required GalleryQuery query,
    required List<String> photoIds,
    required String queryText,
  }) {
    _lastQuery = query;
    _lastPhotoIds = photoIds;
    _lastIntent = query.intent;
    _lastQueryText = queryText;
    _lastInteraction = DateTime.now();
  }

  /// Create a refined query by combining current context with new constraints.
  ///
  /// For example, user says "only the ones with Alex" after "show beach photos".
  /// This merges the person filter with the previous scene filter.
  GalleryQuery? refineWith({
    String? personName,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? objectLabels,
    String? locationLabel,
    double? minQuality,
    double? maxBlur,
    bool? isScreenshot,
  }) {
    if (!hasContext || _lastQuery == null) return null;

    return _lastQuery!.copyWith(
      personName: personName ?? _lastQuery!.personName,
      dateFrom: dateFrom ?? _lastQuery!.dateFrom,
      dateTo: dateTo ?? _lastQuery!.dateTo,
      objectLabels: objectLabels ?? _lastQuery!.objectLabels,
      locationLabel: locationLabel ?? _lastQuery!.locationLabel,
      minQuality: minQuality ?? _lastQuery!.minQuality,
      maxBlur: maxBlur ?? _lastQuery!.maxBlur,
      isScreenshot: isScreenshot ?? _lastQuery!.isScreenshot,
    );
  }

  /// Clear the context.
  void clear() {
    _lastQuery = null;
    _lastPhotoIds = [];
    _lastIntent = GalleryIntent.unknown;
    _lastQueryText = '';
    _lastInteraction = DateTime.now();
  }
}

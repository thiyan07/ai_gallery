import 'gallery_intent.dart';

/// A structured gallery query produced by the intent resolver.
///
/// Contains all extracted constraints from the user's natural language
/// query, ready for execution by the StructuredRetriever.
class GalleryQuery {
  final GalleryIntent intent;
  final String? semanticQuery;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? personName;
  final String? personId;
  final List<String> objectLabels;
  final List<String> sceneConcepts;
  final String? locationLabel;
  final double? latitude;
  final double? longitude;
  final double? minQuality;
  final double? maxBlur;
  final bool? isScreenshot;
  final bool? isDocument;
  final bool? favoritesOnly;
  final String? eventId;
  final String? photoId;
  final String? albumId;
  final int? limit;
  final double confidence;

  const GalleryQuery({
    required this.intent,
    this.semanticQuery,
    this.dateFrom,
    this.dateTo,
    this.personName,
    this.personId,
    this.objectLabels = const [],
    this.sceneConcepts = const [],
    this.locationLabel,
    this.latitude,
    this.longitude,
    this.minQuality,
    this.maxBlur,
    this.isScreenshot,
    this.isDocument,
    this.favoritesOnly,
    this.eventId,
    this.photoId,
    this.albumId,
    this.limit = 20,
    this.confidence = 0.5,
  });

  bool get hasDateFilter => dateFrom != null || dateTo != null;
  bool get hasPersonFilter => personName != null || personId != null;
  bool get hasObjectFilter => objectLabels.isNotEmpty;
  bool get hasSceneFilter => sceneConcepts.isNotEmpty;
  bool get hasLocationFilter => locationLabel != null;
  bool get hasQualityFilter => minQuality != null || maxBlur != null;
  bool get hasSemanticQuery => semanticQuery != null && semanticQuery!.isNotEmpty;
  bool get hasAnyFilter =>
      hasDateFilter ||
      hasPersonFilter ||
      hasObjectFilter ||
      hasSceneFilter ||
      hasLocationFilter ||
      hasQualityFilter ||
      isScreenshot != null ||
      isDocument != null ||
      favoritesOnly == true;

  GalleryQuery copyWith({
    GalleryIntent? intent,
    String? semanticQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? personName,
    String? personId,
    List<String>? objectLabels,
    List<String>? sceneConcepts,
    String? locationLabel,
    double? latitude,
    double? longitude,
    double? minQuality,
    double? maxBlur,
    bool? isScreenshot,
    bool? isDocument,
    bool? favoritesOnly,
    String? eventId,
    String? photoId,
    String? albumId,
    int? limit,
    double? confidence,
  }) {
    return GalleryQuery(
      intent: intent ?? this.intent,
      semanticQuery: semanticQuery ?? this.semanticQuery,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      personName: personName ?? this.personName,
      personId: personId ?? this.personId,
      objectLabels: objectLabels ?? this.objectLabels,
      sceneConcepts: sceneConcepts ?? this.sceneConcepts,
      locationLabel: locationLabel ?? this.locationLabel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      minQuality: minQuality ?? this.minQuality,
      maxBlur: maxBlur ?? this.maxBlur,
      isScreenshot: isScreenshot ?? this.isScreenshot,
      isDocument: isDocument ?? this.isDocument,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      eventId: eventId ?? this.eventId,
      photoId: photoId ?? this.photoId,
      albumId: albumId ?? this.albumId,
      limit: limit ?? this.limit,
      confidence: confidence ?? this.confidence,
    );
  }
}

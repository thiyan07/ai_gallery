import 'dart:convert';

/// A query-based smart album that dynamically shows photos matching rules.
///
/// Smart albums never copy photos — they store a query definition and
/// compute results on demand.
class SmartAlbum {
  final String albumId;
  final String title;
  final SmartAlbumCategory category;
  final SmartAlbumQuery query;
  final int sortOrder;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SmartAlbum({
    required this.albumId,
    required this.title,
    required this.category,
    required this.query,
    this.sortOrder = 0,
    this.isHidden = false,
    required this.createdAt,
    required this.updatedAt,
  });

  SmartAlbum copyWith({
    String? albumId,
    String? title,
    SmartAlbumCategory? category,
    SmartAlbumQuery? query,
    int? sortOrder,
    bool? isHidden,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SmartAlbum(
      albumId: albumId ?? this.albumId,
      title: title ?? this.title,
      category: category ?? this.category,
      query: query ?? this.query,
      sortOrder: sortOrder ?? this.sortOrder,
      isHidden: isHidden ?? this.isHidden,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'album_id': albumId,
        'title': title,
        'category': category.index,
        'query_json': query.toJson(),
        'sort_order': sortOrder,
        'is_hidden': isHidden ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory SmartAlbum.fromMap(Map<String, Object?> row) => SmartAlbum(
        albumId: row['album_id'] as String,
        title: row['title'] as String,
        category: SmartAlbumCategory.values[row['category'] as int],
        query: SmartAlbumQuery.fromJson(row['query_json'] as String),
        sortOrder: row['sort_order'] as int? ?? 0,
        isHidden: (row['is_hidden'] as int?) == 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartAlbum &&
          runtimeType == other.runtimeType &&
          albumId == other.albumId;

  @override
  int get hashCode => albumId.hashCode;
}

/// Predefined smart album categories.
enum SmartAlbumCategory {
  allPhotos,
  people,
  places,
  food,
  pets,
  travel,
  screenshots,
  documents,
  videos,
  favorites,
  recent,
  burst,
  edited,
  raw,
}

/// Query definition for a smart album.
class SmartAlbumQuery {
  final List<String>? objectTags;
  final List<String>? personIds;
  final bool? hasLocation;
  final String? locationLabel;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? mediaType;
  final bool? favoritesOnly;
  final double? minQualityScore;
  final bool? isScreenshot;
  final bool? isDocument;
  final int? minWidth;
  final int? minHeight;

  const SmartAlbumQuery({
    this.objectTags,
    this.personIds,
    this.hasLocation,
    this.locationLabel,
    this.dateFrom,
    this.dateTo,
    this.mediaType,
    this.favoritesOnly,
    this.minQualityScore,
    this.isScreenshot,
    this.isDocument,
    this.minWidth,
    this.minHeight,
  });

  bool get isEmpty =>
      objectTags == null &&
      personIds == null &&
      hasLocation == null &&
      locationLabel == null &&
      dateFrom == null &&
      dateTo == null &&
      mediaType == null &&
      favoritesOnly == null &&
      minQualityScore == null &&
      isScreenshot == null &&
      isDocument == null &&
      minWidth == null &&
      minHeight == null;

  String toJson() {
    final map = <String, dynamic>{};
    if (objectTags != null) map['objectTags'] = objectTags;
    if (personIds != null) map['personIds'] = personIds;
    if (hasLocation != null) map['hasLocation'] = hasLocation;
    if (locationLabel != null) map['locationLabel'] = locationLabel;
    if (dateFrom != null) map['dateFrom'] = dateFrom!.toIso8601String();
    if (dateTo != null) map['dateTo'] = dateTo!.toIso8601String();
    if (mediaType != null) map['mediaType'] = mediaType;
    if (favoritesOnly != null) map['favoritesOnly'] = favoritesOnly;
    if (minQualityScore != null) map['minQualityScore'] = minQualityScore;
    if (isScreenshot != null) map['isScreenshot'] = isScreenshot;
    if (isDocument != null) map['isDocument'] = isDocument;
    if (minWidth != null) map['minWidth'] = minWidth;
    if (minHeight != null) map['minHeight'] = minHeight;
    return jsonEncode(map);
  }

  factory SmartAlbumQuery.fromJson(String json) {
    if (json.isEmpty || json == '{}') return const SmartAlbumQuery();
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return SmartAlbumQuery(
        objectTags: (map['objectTags'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        personIds: (map['personIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        hasLocation: map['hasLocation'] as bool?,
        locationLabel: map['locationLabel'] as String?,
        dateFrom: map['dateFrom'] != null
            ? DateTime.parse(map['dateFrom'] as String)
            : null,
        dateTo: map['dateTo'] != null
            ? DateTime.parse(map['dateTo'] as String)
            : null,
        mediaType: map['mediaType'] as String?,
        favoritesOnly: map['favoritesOnly'] as bool?,
        minQualityScore: (map['minQualityScore'] as num?)?.toDouble(),
        isScreenshot: map['isScreenshot'] as bool?,
        isDocument: map['isDocument'] as bool?,
        minWidth: map['minWidth'] as int?,
        minHeight: map['minHeight'] as int?,
      );
    } catch (_) {
      return const SmartAlbumQuery();
    }
  }
}

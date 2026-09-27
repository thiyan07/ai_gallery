import '../models/gallery_intent.dart';
import '../models/gallery_query.dart';
import '../../../features/search/services/natural_language_parser.dart';
import '../../../core/database/app_database.dart';

/// Resolves user natural language queries into structured GalleryQuery objects.
///
/// Uses deterministic pattern matching. No LLM required.
/// Enhances the existing NaturalLanguageParser with gallery-specific intents.
class IntentResolver {
  IntentResolver({
    required AppDatabase database,
    required NaturalLanguageParser nlParser,
  })  : _database = database,
        _nlParser = nlParser;

  final AppDatabase _database;
  final NaturalLanguageParser _nlParser;

  /// Resolve a natural language query into a structured GalleryQuery.
  Future<GalleryQuery> resolve(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const GalleryQuery(intent: GalleryIntent.unknown, confidence: 0.0);
    }

    // Step 1: Classify intent
    final intent = _classifyIntent(trimmed);

    // Step 2: Check if this is a refinement of previous context
    // (handled by GalleryAssistant, not here)

    // Step 3: Use NL parser for structured extraction
    final parsed = _nlParser.parse(trimmed);

    // Step 4: Build GalleryQuery from parsed results
    final query = _buildQuery(intent, trimmed, parsed);

    // Step 5: Resolve person names to IDs if needed
    if (query.personName != null) {
      final personId = await _resolvePersonId(query.personName!);
      return query.copyWith(personId: personId);
    }

    return query;
  }

  /// Classify the intent from raw text.
  GalleryIntent _classifyIntent(String input) {
    final lower = input.toLowerCase();

    // Count queries
    if (_matchesAny(lower, [
      r'how many',
      r'count',
      r'number of',
      r'total.*photos',
      r'total.*pictures',
    ])) {
      return GalleryIntent.count;
    }

    // Statistics queries
    if (_matchesAny(lower, [
      r'statistics',
      r'stats',
      r'overview',
      r'summary.*gallery',
      r'gallery.*summary',
      r'what do i have',
      r'tell me about.*gallery',
    ])) {
      return GalleryIntent.statistics;
    }

    // Duplicate queries
    if (_matchesAny(lower, [
      r'duplicate',
      r'duplicates',
      r'copy.*photos',
      r'identical.*photos',
    ])) {
      return GalleryIntent.duplicates;
    }

    // Best photo queries
    if (_matchesAny(lower, [
      r'best.*photo',
      r'best.*picture',
      r'top.*photo',
      r'favorite.*photo',
      r'nicest',
      r'highest quality',
    ])) {
      return GalleryIntent.bestPhotos;
    }

    // Create album
    if (_matchesAny(lower, [
      r'create.*album',
      r'make.*album',
      r'new album',
      r'add.*album',
    ])) {
      return GalleryIntent.createAlbum;
    }

    // Create memory
    if (_matchesAny(lower, [
      r'create.*memory',
      r'make.*memory',
      r'new memory',
      r'generate.*memory',
    ])) {
      return GalleryIntent.createMemory;
    }

    // Explanation
    if (_matchesAny(lower, [
      r'why.*photo',
      r'why.*picture',
      r'explain.*result',
      r'how.*found',
      r'why.*show',
    ])) {
      return GalleryIntent.explanation;
    }

    // Edit
    if (_matchesAny(lower, [
      r'edit.*photo',
      r'enhance',
      r'remove.*background',
      r'crop.*photo',
      r'make.*brighter',
      r'make.*clearer',
    ])) {
      return GalleryIntent.editPhoto;
    }

    // Video search (temporal — find moments within videos)
    if (_matchesAny(lower, [
      r'video.*where',
      r'video.*showing',
      r'in.*video',
      r'find.*moment',
      r'when.*video',
      r'search.*video',
      r'what.*video',
    ])) {
      return GalleryIntent.videoSearch;
    }

    // Batch action: add to favorites
    if (_matchesAny(lower, [
      r'add.*favori',
      r'mark.*favori',
      r'favori.*these',
      r'favori.*those',
      r'heart.*these',
      r'heart.*those',
      r'like.*these',
      r'like.*those',
    ])) {
      return GalleryIntent.addToFavorites;
    }

    // Batch action: remove from favorites
    if (_matchesAny(lower, [
      r'remove.*favori',
      r'unfavori',
      r'unlike.*these',
      r'unlike.*those',
    ])) {
      return GalleryIntent.removeFromFavorites;
    }

    // Batch action: delete photos
    if (_matchesAny(lower, [
      r'delete.*these',
      r'delete.*those',
      r'remove.*these',
      r'remove.*those',
      r'trash.*these',
      r'trash.*those',
      r'get rid of',
    ])) {
      return GalleryIntent.deletePhotos;
    }

    // Person co-occurrence queries (graph-aware)
    if (_matchesAny(lower, [
      r'who.*appear.*with',
      r'who.*together.*with',
      r'who.*seen.*with',
      r'friends.*of',
      r'appear.*with\s+\w+',
      r'together.*with\s+\w+',
    ])) {
      return GalleryIntent.personCoOccurrences;
    }

    // Person events queries (graph-aware)
    if (_matchesAny(lower, [
      r'events.*person',
      r'events.*\bhe\b',
      r'events.*\bshe\b',
      r'which events.*\w+',
      r'attended.*events',
      r'events.*attended',
    ])) {
      return GalleryIntent.personEvents;
    }

    // Person places queries (graph-aware)
    if (_matchesAny(lower, [
      r'where.*been',
      r'where.*visited',
      r'places.*person',
      r'locations.*\bhe\b',
      r'locations.*\bshe\b',
      r'where.*\bhe\b.*photo',
      r'where.*\bshe\b.*photo',
    ])) {
      return GalleryIntent.personPlaces;
    }

    // Event people queries (graph-aware)
    if (_matchesAny(lower, [
      r'who.*at.*event',
      r'who.*was.*there',
      r'people.*at.*event',
      r'who.*attended',
    ])) {
      return GalleryIntent.eventPeople;
    }

    // Similar photos
    if (_matchesAny(lower, [
      r'similar.*photo',
      r'like.*this',
      r'resembles',
      r'looks like',
    ])) {
      return GalleryIntent.similar;
    }

    // Person queries — "photos with Alex", "pictures of Bob"
    if (_matchesAny(lower, [
      r'photo.*with\s+\w+',
      r'picture.*with\s+\w+',
      r'photo.*of\s+\w+',
      r'picture.*of\s+\w+',
    ])) {
      return GalleryIntent.person;
    }

    // Quality queries
    if (_matchesAny(lower, [
      r'blurry',
      r'out of focus',
      r'sharp',
      r'clear',
      r'high quality',
      r'low quality',
      r'screenshot',
    ])) {
      return GalleryIntent.quality;
    }

    // Location queries
    if (_matchesAny(lower, [
      r'in\s+[A-Z]\w+',
      r'at\s+[A-Z]\w+',
      r'near\s+[A-Z]\w+',
      r'location',
      r'where',
      r'place',
    ])) {
      return GalleryIntent.location;
    }

    // Date queries
    if (_matchesAny(lower, [
      r'today',
      r'yesterday',
      r'this week',
      r'last week',
      r'this month',
      r'last month',
      r'this year',
      r'last year',
      r'\d{4}',
      r'january|february|march|april|may|june|july|august|september|october|november|december',
    ])) {
      return GalleryIntent.date;
    }

    // Greetings
    if (_matchesAny(lower, [
      r'^(hi|hello|hey|howdy|good\s+(morning|afternoon|evening))',
      r"^what'?s?\s+up",
      r'^help',
    ])) {
      return GalleryIntent.greeting;
    }

    // Search (default — must be last)
    return GalleryIntent.search;
  }

  /// Build a GalleryQuery from parsed NL results and intent.
  GalleryQuery _buildQuery(
    GalleryIntent intent,
    String rawText,
    ParsedQuery parsed,
  ) {
    final filters = parsed.filters;

    return GalleryQuery(
      intent: intent,
      semanticQuery: parsed.semanticQuery.isNotEmpty
          ? parsed.semanticQuery
          : rawText,
      dateFrom: filters.dateFrom,
      dateTo: filters.dateTo,
      personName: filters.personName,
      objectLabels: filters.objectTags,
      sceneConcepts: filters.sceneConcepts,
      locationLabel: filters.locationLabel,
      minQuality: filters.minQualityScore,
      maxBlur: filters.maxBlurScore,
      favoritesOnly: filters.favoritesOnly ? true : null,
      confidence: parsed.confidence,
      limit: intent == GalleryIntent.count ? null : 20,
    );
  }

  /// Resolve a person name to their ID.
  Future<String?> _resolvePersonId(String name) async {
    final rows = await _database.database.rawQuery(
      "SELECT person_id FROM people "
      "WHERE LOWER(display_name) = LOWER(?) AND status = 'active' "
      "LIMIT 1",
      [name],
    );
    if (rows.isNotEmpty) {
      return rows.first['person_id'] as String;
    }
    return null;
  }

  /// Check if input matches any of the regex patterns.
  bool _matchesAny(String input, List<String> patterns) {
    for (final pattern in patterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(input)) {
        return true;
      }
    }
    return false;
  }
}

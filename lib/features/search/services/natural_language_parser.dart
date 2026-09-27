import 'dart:math';

import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';

/// Result of parsing a natural language query.
class ParsedQuery {
  const ParsedQuery({
    required this.semanticQuery,
    required this.filters,
    required this.confidence,
    this.originalQuery,
    this.intent = SearchIntent.unknown,
    this.detectedObjects = const [],
    this.sceneConcepts = const [],
    this.locationLabel,
  });

  /// The cleaned semantic query for vector search (original minus extracted filter terms).
  final String semanticQuery;

  /// Structured filters extracted from the query.
  final SearchFilters filters;

  /// Confidence score (0.0 - 1.0) indicating how much of the query was understood.
  final double confidence;

  /// The original raw query.
  final String? originalQuery;

  /// Detected search intent, used to select the optimal search path.
  final SearchIntent intent;

  /// Object labels detected in the query (e.g. 'dog', 'car').
  /// These are cross-referenced against YOLO object_tags for hard filtering.
  final List<String> detectedObjects;

  /// Scene/semantic concepts extracted from the query (e.g. 'beach', 'sunset').
  /// These are used as ranking signals via embedding similarity, not hard filters.
  final List<String> sceneConcepts;

  /// Human-readable location label extracted from the query.
  /// E.g. "Paris", "Tokyo". Used for GPS-based location matching.
  final String? locationLabel;

  /// Whether any structured filters were extracted.
  bool get hasFilters => filters.dateFrom != null ||
      filters.dateTo != null ||
      filters.minQualityScore != null ||
      filters.maxBlurScore != null ||
      filters.hasLocation ||
      filters.cameraMake != null ||
      filters.cameraModel != null ||
      filters.personName != null ||
      filters.objectTags.isNotEmpty ||
      filters.excludeTags.isNotEmpty ||
      filters.sceneConcepts.isNotEmpty ||
      filters.locationLabel != null;

  ParsedQuery copyWith({
    String? semanticQuery,
    SearchFilters? filters,
    double? confidence,
    String? originalQuery,
    SearchIntent? intent,
    List<String>? detectedObjects,
    List<String>? sceneConcepts,
    String? locationLabel,
  }) {
    return ParsedQuery(
      semanticQuery: semanticQuery ?? this.semanticQuery,
      filters: filters ?? this.filters,
      confidence: confidence ?? this.confidence,
      originalQuery: originalQuery ?? this.originalQuery,
      intent: intent ?? this.intent,
      detectedObjects: detectedObjects ?? this.detectedObjects,
      sceneConcepts: sceneConcepts ?? this.sceneConcepts,
      locationLabel: locationLabel ?? this.locationLabel,
    );
  }
}

/// Rule-based natural language query parser for photo search.
///
/// Converts queries like:
/// - "photos from last week" → dateFrom: 7 days ago
/// - "iPhone 14 photos" → cameraModel: "iPhone 14"
/// - "sharp photos" → minQualityScore: 0.7, maxBlurScore: 0.3
/// - "dog photos at beach" → semanticQuery: "dog beach", objectTag: "dog" (if indexed)
/// - "beach without people" → objectTag: none, excludeTags: ["person"]
/// - "not blurry photos from yesterday" → minQualityScore: 0.7, maxBlurScore: 0.3, dateFrom: yesterday
class NaturalLanguageParser {
  NaturalLanguageParser({DateTime? referenceTime, List<String>? personNames})
      : _referenceTime = referenceTime ?? DateTime.now(),
        _logger = null,
        _personNames = personNames ?? [];

  final DateTime _referenceTime;
  final AppLogger? _logger;
  final List<String> _personNames;

  NaturalLanguageParser.withLogger(this._logger, {DateTime? referenceTime, List<String>? personNames})
      : _referenceTime = referenceTime ?? DateTime.now(),
        _personNames = personNames ?? [];

  // ─────────────────────────────────────────────
  // Date/time patterns
  // ─────────────────────────────────────────────

  static final List<_DatePattern> _datePatterns = [
    // Relative: "last week", "this month", etc.
    _DatePattern(
      pattern: RegExp(r'\b(last|past|previous)\s+(week|month|year)\b', caseSensitive: false),
      handler: _handleLastPeriod,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(this|current)\s+(week|month|year)\b', caseSensitive: false),
      handler: _handleThisPeriod,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(yesterday|day before yesterday)\b', caseSensitive: false),
      handler: _handleYesterday,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(\d+)\s+(days?|weeks?|months?|years?)\s+ago\b', caseSensitive: false),
      handler: _handleTimeAgo,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(today|now)\b', caseSensitive: false),
      handler: _handleToday,
    ),
    // Explicit dates: "January 2025", "2025-01-15", "Jan 15"
    _DatePattern(
      pattern: RegExp(r'\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{4})?\b', caseSensitive: false),
      handler: _handleMonthDayYear,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b'),
      handler: _handleIsoDate,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(\d{1,2})[-/](\d{1,2})[-/](\d{4})\b'),
      handler: _handleUsDate,
    ),
    // "incomplete_date_patterns:
    _DatePattern(
      pattern: RegExp(r'\bin\s+(\d{4})\b'),
      handler: _handleYearOnly,
    ),
    _DatePattern(
      pattern: RegExp(r'\bfrom\s+(\d{4})(?:\s|$)'),
      handler: _handleYearOnly,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(?:in|from)\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b', caseSensitive: false),
      handler: _handleMonthOnly,
    ),
    _DatePattern(
      pattern: RegExp(r'\b(this|last)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', caseSensitive: false),
      handler: _handleWeekday,
    ),
  ];

  // ─────────────────────────────────────────────
  // Camera patterns
  // ─────────────────────────────────────────────

  static final List<_CameraPattern> _cameraPatterns = [
    // iPhone models
    _CameraPattern(
      pattern: RegExp(r'\b(iphone\s*(?:1[0-6]|[6-9]|se|pro\s*max?|plus|mini)?)\b', caseSensitive: false),
      handler: _handleIPhone,
    ),
    // Samsung
    _CameraPattern(
      pattern: RegExp(r'\b(galaxy\s*s\d+(?:\s*(?:ultra|plus|fe))?|galaxy\s*z\s*(?:fold|flip)\d*)\b', caseSensitive: false),
      handler: _handleSamsung,
    ),
    // Pixel
    _CameraPattern(
      pattern: RegExp(r'\b(pixel\s*\d+(?:\s*(?:pro|xl|a))?)\b', caseSensitive: false),
      handler: _handlePixel,
    ),
    // Generic camera makes
    _CameraPattern(
      pattern: RegExp(r'\b(canon|nikon|sony|fuji|fujifilm|olympus|panasonic|leica|hasselblad|pentax|ricoh|sigma)\b', caseSensitive: false),
      handler: _handleCameraMake,
    ),
    // Common model patterns
    _CameraPattern(
      pattern: RegExp(r'\b(a\d{3,4}|r\d{1,2}|z\d|xt-\d|x-t\d|gfx\s*\d{2,3})\b', caseSensitive: false),
      handler: _handleGenericModel,
    ),
  ];

  // ─────────────────────────────────────────────
  // Quality patterns
  // ─────────────────────────────────────────────

  static final List<_QualityPattern> _qualityPatterns = [
    // Sharp/high quality
    _QualityPattern(
      pattern: RegExp(r'\b(sharp|crisp|high.?quality|best.?quality|clear|in.?focus|detailed)\b', caseSensitive: false),
      minQuality: 0.7,
      maxBlur: 0.3,
      positiveQuality: true,
    ),
    // Blurry/low quality
    _QualityPattern(
      pattern: RegExp(r'\b(blurry|blur|out.?of.?focus|soft|low.?quality|poor.?quality|grainy|noisy)\b', caseSensitive: false),
      minQuality: null,
      maxBlur: 0.6,
      positiveQuality: false,
    ),
    // Professional/best
    _QualityPattern(
      pattern: RegExp(r'\b(professional|pro.?quality|dslr.?quality|raw)\b', caseSensitive: false),
      minQuality: 0.8,
      maxBlur: 0.2,
      positiveQuality: true,
    ),
    // Screenshots/UI (often low quality for photo search)
    _QualityPattern(
      pattern: RegExp(r'\b(screenshot|screen.?shot|screen.?capture)\b', caseSensitive: false),
      minQuality: 0.3,
      maxBlur: 0.7,
      positiveQuality: null,
    ),
  ];

  // ─────────────────────────────────────────────
  // Location patterns
  // ─────────────────────────────────────────────

  static final List<_LocationPattern> _locationPatterns = [
    _LocationPattern(
      pattern: RegExp(r'\b(?:in|at|near|around)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b'),
      handler: _handleLocation,
    ),
  ];

  // ─────────────────────────────────────────────
  // Object patterns (each trigger term maps to exactly one YOLO COCO label
  // for precise hard filtering — "dog" matches only dog photos, not all animals)
  // ─────────────────────────────────────────────

  static final List<_ObjectPattern> _objectPatterns = [
    // People (YOLO COCO 'person')
    _ObjectPattern(
      pattern: RegExp(r'\b(person|people|man|woman|men|women|child|children|kid|kids|baby|babies|boy|boys|girl|girls|human|humans|crowd)\b', caseSensitive: false),
      labelMap: {
        'person': 'person', 'people': 'person',
        'man': 'person', 'men': 'person', 'woman': 'person', 'women': 'person',
        'child': 'person', 'children': 'person', 'kid': 'person', 'kids': 'person',
        'baby': 'person', 'babies': 'person', 'boy': 'person', 'boys': 'person',
        'girl': 'person', 'girls': 'person', 'human': 'person', 'humans': 'person',
        'crowd': 'person',
      },
    ),
    // Animals (YOLO COCO labels + common synonyms/plurals)
    _ObjectPattern(
      pattern: RegExp(r'\b(dogs?|puppy|puppies|pup|cat|kitten|kittens|kitty|cats|horse|horses|cow|cows|sheep|elephant|elephants|bear|bears|zebra|zebras|giraffe|giraffes|bird|birds)\b', caseSensitive: false),
      labelMap: {
        'dog': 'dog', 'dogs': 'dog', 'puppy': 'dog', 'puppies': 'dog', 'pup': 'dog',
        'cat': 'cat', 'cats': 'cat', 'kitten': 'cat', 'kittens': 'cat', 'kitty': 'cat',
        'horse': 'horse', 'horses': 'horse', 'cow': 'cow', 'cows': 'cow',
        'sheep': 'sheep', 'elephant': 'elephant', 'elephants': 'elephant',
        'bear': 'bear', 'bears': 'bear', 'zebra': 'zebra', 'zebras': 'zebra',
        'giraffe': 'giraffe', 'giraffes': 'giraffe', 'bird': 'bird', 'birds': 'bird',
      },
    ),
    // Vehicles (YOLO COCO labels + synonyms)
    _ObjectPattern(
      pattern: RegExp(r'\b(car|cars|truck|trucks|bus|buses|motorcycle|motorcycles|motorbike|bicycle|bicycles|bike|bikes|van|vans|suv|sedan|auto|automobile|airplane|airplanes|plane|planes|boat|boats|ship|ships|train|trains)\b', caseSensitive: false),
      labelMap: {
        'car': 'car', 'cars': 'car', 'van': 'car', 'vans': 'car', 'suv': 'car',
        'sedan': 'car', 'auto': 'car', 'automobile': 'car',
        'truck': 'truck', 'trucks': 'truck', 'bus': 'bus', 'buses': 'bus',
        'motorcycle': 'motorcycle', 'motorcycles': 'motorcycle', 'motorbike': 'motorcycle',
        'bicycle': 'bicycle', 'bicycles': 'bicycle', 'bike': 'bicycle', 'bikes': 'bicycle',
        'airplane': 'airplane', 'airplanes': 'airplane', 'plane': 'airplane', 'planes': 'airplane',
        'boat': 'boat', 'boats': 'boat', 'ship': 'boat', 'ships': 'boat',
        'train': 'train', 'trains': 'train',
      },
    ),
    // Indoor objects (YOLO COCO labels + synonyms)
    _ObjectPattern(
      pattern: RegExp(r'\b(chair|chairs|couch|couches|sofa|sofas|bed|beds|table|tables|desk|desks|tv|tvs|television|laptop|laptops|computer|computers|pc|phone|phones|cell.?phone|mobile|book|books|vase|vases|bottle|bottles|cup|cups|mug|mugs|wine.?glass)\b', caseSensitive: false),
      labelMap: {
        'chair': 'chair', 'chairs': 'chair',
        'couch': 'couch', 'couches': 'couch', 'sofa': 'couch', 'sofas': 'couch',
        'bed': 'bed', 'beds': 'bed',
        'table': 'dining table', 'tables': 'dining table',
        'desk': 'dining table', 'desks': 'dining table',
        'tv': 'tv', 'tvs': 'tv', 'television': 'tv',
        'laptop': 'laptop', 'laptops': 'laptop',
        'computer': 'laptop', 'computers': 'laptop', 'pc': 'laptop',
        'phone': 'cell phone', 'phones': 'cell phone',
        'cell phone': 'cell phone', 'mobile': 'cell phone',
        'book': 'book', 'books': 'book',
        'vase': 'vase', 'vases': 'vase',
        'bottle': 'bottle', 'bottles': 'bottle',
        'cup': 'cup', 'cups': 'cup', 'mug': 'cup', 'mugs': 'cup',
        'wine glass': 'wine glass',
      },
    ),
    // Food (YOLO COCO labels + synonyms)
    _ObjectPattern(
      pattern: RegExp(r'\b(pizza|pizzas|banana|bananas|apple|apples|orange|oranges|sandwich|sandwiches|burger|burgers|broccoli|carrot|carrots|cake|cakes|donut|donuts|doughnut|hot.?dog)\b', caseSensitive: false),
      labelMap: {
        'pizza': 'pizza', 'pizzas': 'pizza',
        'banana': 'banana', 'bananas': 'banana',
        'apple': 'apple', 'apples': 'apple',
        'orange': 'orange', 'oranges': 'orange',
        'sandwich': 'sandwich', 'sandwiches': 'sandwich',
        'burger': 'sandwich', 'burgers': 'sandwich',
        'broccoli': 'broccoli', 'carrot': 'carrot', 'carrots': 'carrot',
        'cake': 'cake', 'cakes': 'cake',
        'donut': 'donut', 'donuts': 'donut', 'doughnut': 'donut',
        'hot dog': 'hot dog', 'hotdog': 'hot dog',
      },
    ),
    // Sports (YOLO COCO labels + synonyms)
    _ObjectPattern(
      pattern: RegExp(r'\b(surfboard|skateboard|skis|ski|tennis|racket|racke?s|kite|kites|frisbee|ball|balls|football|soccer|basketball|baseball)\b', caseSensitive: false),
      labelMap: {
        'surfboard': 'surfboard', 'skateboard': 'skateboard',
        'skis': 'skis', 'ski': 'skis',
        'tennis': 'tennis racket', 'racket': 'tennis racket', 'rackets': 'tennis racket',
        'kite': 'kite', 'kites': 'kite', 'frisbee': 'frisbee',
        'ball': 'sports ball', 'balls': 'sports ball',
        'football': 'sports ball', 'soccer': 'sports ball',
        'basketball': 'sports ball', 'baseball': 'sports ball',
      },
    ),
  ];

  /// All known object trigger terms (longest first for alternation priority),
  /// used to recognize exclusions like "without <term>".
  static List<String>? _allObjectTerms;
  static List<String> get allObjectTerms {
    if (_allObjectTerms == null) {
      final terms = <String>{};
      for (final pattern in _objectPatterns) {
        terms.addAll(pattern.labelMap.keys);
      }
      final sorted = terms.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      _allObjectTerms = sorted;
    }
    return _allObjectTerms!;
  }

  /// Resolve a matched trigger term to its COCO label (case-insensitive).
  static String? _labelForTerm(String term) {
    final lower = term.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final pattern in _objectPatterns) {
      final label = pattern.labelMap[lower];
      if (label != null) return label;
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // Scene/semantic concept patterns (embedding-based ranking signals)
  // ─────────────────────────────────────────────

  static final List<_ScenePattern> _scenePatterns = [
    // Nature/outdoor scenes
    _ScenePattern(
      pattern: RegExp(r'\b(beach|mountain|forest|park|garden|ocean|sea|lake|river|waterfall|sunset|sunrise|sky|clouds|desert|island|cave|cliff|valley)\b', caseSensitive: false),
      concepts: ['beach', 'mountain', 'forest', 'park', 'garden', 'ocean', 'sea', 'lake', 'river', 'waterfall', 'sunset', 'sunrise', 'sky', 'clouds', 'desert', 'island'],
    ),
    // Indoor scenes
    _ScenePattern(
      pattern: RegExp(r'\b(restaurant|cafe|kitchen|bathroom|office|gym|library|museum|theater|church|temmosque|stadium|airport|station)\b', caseSensitive: false),
      concepts: ['restaurant', 'cafe', 'kitchen', 'bathroom', 'office', 'gym', 'library', 'museum', 'theater', 'church', 'temple', 'mosque', 'stadium', 'airport', 'station'],
    ),
    // Weather/lighting
    _ScenePattern(
      pattern: RegExp(r'\b(rainy|snowy|sunny|cloudy|foggy|night|dark|bright|golden.?hour|blue.?hour|overcast)\b', caseSensitive: false),
      concepts: ['rain', 'snow', 'sunny', 'cloudy', 'fog', 'night', 'dark', 'bright', 'golden hour', 'blue hour'],
    ),
    // Activity/occasion
    _ScenePattern(
      pattern: RegExp(r'\b(wedding|birthday|party|concert|festival|ceremony|graduation|christmas|halloween|vacation|travel|hiking|camping|swimming|running|cooking|playing)\b', caseSensitive: false),
      concepts: ['wedding', 'birthday', 'party', 'concert', 'festival', 'ceremony', 'graduation', 'christmas', 'halloween', 'vacation', 'travel', 'hiking', 'camping', 'swimming', 'running', 'cooking'],
    ),
  ];

  /// Parse a natural language query into structured filters + semantic query.
  ParsedQuery parse(String query) {
    if (query.trim().isEmpty) {
      return ParsedQuery(semanticQuery: '', filters: SearchFilters(), confidence: 0.0);
    }

    String remainingQuery = query.trim();
    final filters = <String, dynamic>{};
    var matchedPatterns = 0;
    var totalPatterns = 0;

    // Keep track of removed spans to reconstruct semantic query
    final removedSpans = <_Span>[];

    // 1. Parse dates
    for (final pattern in _datePatterns) {
      totalPatterns++;
      final matches = pattern.pattern.allMatches(remainingQuery);
      for (final match in matches) {
        final result = pattern.handler(match, _referenceTime);
        if (result != null) {
          filters.addAll(result);
          removedSpans.add(_Span(match.start, match.end));
          matchedPatterns++;
        }
      }
    }

    // 2. Parse camera
    for (final pattern in _cameraPatterns) {
      totalPatterns++;
      final matches = pattern.pattern.allMatches(remainingQuery);
      for (final match in matches) {
        final result = pattern.handler(match);
        if (result != null) {
          filters.addAll(result);
          removedSpans.add(_Span(match.start, match.end));
          matchedPatterns++;
        }
      }
    }

    // 3. Parse quality (with negation: "not blurry" means sharp)
    for (final pattern in _qualityPatterns) {
      totalPatterns++;
      final matches = pattern.pattern.allMatches(remainingQuery);
      for (final match in matches) {
        final negated = _isNegated(remainingQuery, match.start);
        if (negated && pattern.positiveQuality == null) {
          continue; // e.g. "not a screenshot" — no quality equivalent, skip
        }
        if (negated && pattern.positiveQuality == true) {
          // "not sharp" → treat as blurry-ish
          filters['maxBlurScore'] = min(filters['maxBlurScore'] as double? ?? 1.0, 0.6);
        } else if (negated) {
          // "not blurry" → treat as sharp
          filters['minQualityScore'] = max(filters['minQualityScore'] as double? ?? 0.0, 0.7);
          filters['maxBlurScore'] = min(filters['maxBlurScore'] as double? ?? 1.0, 0.3);
        } else {
          if (pattern.minQuality != null) {
            filters['minQualityScore'] = max(filters['minQualityScore'] as double? ?? 0.0, pattern.minQuality!);
          }
          if (pattern.maxBlur != null) {
            filters['maxBlurScore'] = min(filters['maxBlurScore'] as double? ?? 1.0, pattern.maxBlur!);
          }
        }
        removedSpans.add(_Span(match.start, match.end));
        matchedPatterns++;
      }
    }

    // 4. Parse location
    for (final pattern in _locationPatterns) {
      totalPatterns++;
      final matches = pattern.pattern.allMatches(remainingQuery);
      for (final match in matches) {
        final result = pattern.handler(match);
        if (result != null) {
          filters.addAll(result);
          removedSpans.add(_Span(match.start, match.end));
          matchedPatterns++;
        }
      }
    }

    // 5a. Parse exclusions ("beach without people", "dog except puppy-photos
    // with cats"). Runs BEFORE inclusions so excluded terms are claimed first.
    final excludedObjects = <String>[];
    final exclusionSpans = <_Span>[];
    {
      totalPatterns++;
      final termAlternation =
          allObjectTerms.map(RegExp.escape).join('|');
      final exclusionPattern = RegExp(
        '\\b(without|except|excluding|minus)\\s+($termAlternation)\\b',
        caseSensitive: false,
      );
      for (final match in exclusionPattern.allMatches(remainingQuery)) {
        final label = _labelForTerm(match.group(2)!);
        if (label == null) continue;
        if (!excludedObjects.contains(label)) excludedObjects.add(label);
        exclusionSpans.add(_Span(match.start, match.end));
        removedSpans.add(_Span(match.start, match.end));
        matchedPatterns++;
      }
    }

    // 5. Parse objects (each trigger maps to exactly ONE COCO label).
    // Matches inside exclusion spans are skipped (already claimed above).
    final detectedObjects = <String>[];
    for (final pattern in _objectPatterns) {
      final matches = pattern.pattern.allMatches(remainingQuery);
      for (final match in matches) {
        if (_overlapsAny(match.start, match.end, exclusionSpans)) continue;
        final label = _labelForTerm(match.group(0)!);
        if (label == null) continue;
        if (!detectedObjects.contains(label)) detectedObjects.add(label);
        removedSpans.add(_Span(match.start, match.end));
        matchedPatterns++;
      }
    }

    // 6. Parse scene concepts (embedding-based ranking signals).
    // Matches inside exclusion spans are skipped.
    final sceneConcepts = <String>[];
    for (final pattern in _scenePatterns) {
      final matches = pattern.pattern.allMatches(remainingQuery);
      for (final match in matches) {
        if (_overlapsAny(match.start, match.end, exclusionSpans)) continue;
        sceneConcepts.addAll(pattern.concepts);
        removedSpans.add(_Span(match.start, match.end));
        matchedPatterns++;
      }
    }

    // 7. Parse person names (match against known people).
    // Names inside exclusion spans are skipped ("photos without John").
    String? detectedPersonName;
    for (final name in _personNames) {
      final namePattern = RegExp(
        r'\b' + RegExp.escape(name) + r'\b',
        caseSensitive: false,
      );
      final match = namePattern.firstMatch(remainingQuery);
      if (match != null) {
        if (_overlapsAny(match.start, match.end, exclusionSpans)) continue;
        detectedPersonName = name;
        removedSpans.add(_Span(match.start, match.end));
        matchedPatterns++;
        break; // Take the first matching person name
      }
    }

    // Build SearchFilters with new fields
    final searchFilters = SearchFilters(
      dateFrom: filters['dateFrom'] as DateTime?,
      dateTo: filters['dateTo'] as DateTime?,
      minQualityScore: filters['minQualityScore'] as double?,
      maxBlurScore: filters['maxBlurScore'] as double?,
      hasLocation: filters['hasLocation'] as bool? ?? false,
      cameraMake: filters['cameraMake'] as String?,
      cameraModel: filters['cameraModel'] as String?,
      personName: detectedPersonName,
      objectTags: detectedObjects.toSet().toList(),
      excludeTags: excludedObjects.toSet().toList(),
      sceneConcepts: sceneConcepts.toSet().toList(),
      locationLabel: filters['locationLabel'] as String?,
    );

    // Reconstruct semantic query by removing matched filter terms
    String semanticQuery = _removeSpans(remainingQuery, removedSpans);
    semanticQuery = _cleanupSemanticQuery(semanticQuery);

    // Add scene concepts to semantic query for embedding similarity
    if (sceneConcepts.isNotEmpty) {
      final sceneTerms = sceneConcepts.toSet().join(' ');
      if (semanticQuery.isNotEmpty) {
        semanticQuery = '$semanticQuery $sceneTerms';
      } else {
        semanticQuery = sceneTerms;
      }
    }

    // Add detected objects to semantic query if they weren't already there
    if (detectedObjects.isNotEmpty) {
      final objectTerms = detectedObjects.toSet().join(' ');
      if (semanticQuery.isNotEmpty) {
        semanticQuery = '$semanticQuery $objectTerms';
      } else {
        semanticQuery = objectTerms;
      }
    }

    // Fallback: if nothing understood, use original query as semantic
    if (semanticQuery.trim().isEmpty) {
      semanticQuery = query.trim();
    }

    // Calculate confidence
    final confidence = totalPatterns > 0 ? matchedPatterns / totalPatterns : 0.0;

    // Classify search intent
    final intent = _classifyIntent(
      personName: detectedPersonName,
      objectTags: detectedObjects,
      sceneConcepts: sceneConcepts,
      hasDateFilter: filters.containsKey('dateFrom') || filters.containsKey('dateTo'),
      hasLocation: filters['hasLocation'] as bool? ?? false,
      locationLabel: filters['locationLabel'] as String?,
      hasCameraFilter: filters.containsKey('cameraMake') || filters.containsKey('cameraModel'),
    );

    _logger?.info('Parsed query → intent: ${intent.name}, objects: $detectedObjects, scenes: $sceneConcepts, confidence: ${confidence.toStringAsFixed(2)}');

    return ParsedQuery(
      semanticQuery: semanticQuery.trim(),
      filters: searchFilters,
      confidence: confidence,
      originalQuery: query,
      intent: intent,
      detectedObjects: detectedObjects.toSet().toList(),
      sceneConcepts: sceneConcepts.toSet().toList(),
      locationLabel: filters['locationLabel'] as String?,
    );
  }

  /// Classify the primary intent of a parsed query to select the optimal search path.
  SearchIntent _classifyIntent({
    String? personName,
    required List<String> objectTags,
    required List<String> sceneConcepts,
    required bool hasDateFilter,
    required bool hasLocation,
    String? locationLabel,
    required bool hasCameraFilter,
  }) {
    final signals = <SearchIntent>[];

    if (personName != null) signals.add(SearchIntent.person);
    if (objectTags.isNotEmpty) signals.add(SearchIntent.object);
    if (sceneConcepts.isNotEmpty) signals.add(SearchIntent.scene);
    if (hasDateFilter) signals.add(SearchIntent.date);
    if (hasLocation || locationLabel != null) signals.add(SearchIntent.location);

    if (signals.isEmpty) return SearchIntent.unknown;
    if (signals.length == 1) return signals.first;
    return SearchIntent.combined;
  }

  /// Whether [matchStart] is directly preceded by a negation word
  /// ("not", "no", "without"), e.g. "not blurry".
  bool _isNegated(String text, int matchStart) {
    final before = text.substring(0, matchStart);
    return RegExp(r'\b(not|no|without)\s+$', caseSensitive: false).hasMatch(before);
  }

  /// Whether [start,end) overlaps any span in [spans].
  bool _overlapsAny(int start, int end, List<_Span> spans) {
    for (final span in spans) {
      if (start < span.end && end > span.start) return true;
    }
    return false;
  }

  /// Remove matched spans from text.
  String _removeSpans(String text, List<_Span> spans) {
    if (spans.isEmpty) return text;

    // Sort spans by start position
    spans.sort((a, b) => a.start.compareTo(b.start));

    // Merge overlapping spans
    final merged = <_Span>[];
    var current = spans.first;
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].start <= current.end) {
        current = _Span(current.start, max(current.end, spans[i].end));
      } else {
        merged.add(current);
        current = spans[i];
      }
    }
    merged.add(current);

    // Build result by skipping merged spans
    final buffer = StringBuffer();
    var lastEnd = 0;
    for (final span in merged) {
      buffer.write(text.substring(lastEnd, span.start));
      lastEnd = span.end;
    }
    buffer.write(text.substring(lastEnd));

    return buffer.toString();
  }

  /// Clean up the semantic query (remove extra whitespace, punctuation).
  String _cleanupSemanticQuery(String query) {
    return query
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.,;:]+$'), '')
        .replaceAll(RegExp(r'^\s*[.,;:]+\s*'), '')
        .trim();
  }
}

// ─────────────────────────────────────────────
// Pattern classes and handlers
// ─────────────────────────────────────────────

class _DatePattern {
  const _DatePattern({required this.pattern, required this.handler});
  final RegExp pattern;
  final Map<String, dynamic>? Function(RegExpMatch, DateTime) handler;
}

class _CameraPattern {
  const _CameraPattern({required this.pattern, required this.handler});
  final RegExp pattern;
  final Map<String, dynamic>? Function(RegExpMatch) handler;
}

class _QualityPattern {
  const _QualityPattern({required this.pattern, this.minQuality, this.maxBlur, this.positiveQuality});
  final RegExp pattern;
  final double? minQuality;
  final double? maxBlur;

  /// True for "good quality" patterns (sharp, professional), false for "bad
  /// quality" patterns (blurry), null for neutral ones (screenshot) where
  /// negation has no quality equivalent. Used to invert "not blurry".
  final bool? positiveQuality;
}

class _LocationPattern {
  const _LocationPattern({required this.pattern, required this.handler});
  final RegExp pattern;
  final Map<String, dynamic>? Function(RegExpMatch) handler;
}

class _ObjectPattern {
  const _ObjectPattern({required this.pattern, required this.labelMap});
  final RegExp pattern;

  /// Maps each trigger term (lowercase) to exactly one YOLO COCO label.
  final Map<String, String> labelMap;
}

class _ScenePattern {
  const _ScenePattern({required this.pattern, required this.concepts});
  final RegExp pattern;
  final List<String> concepts;
}

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}

// ─────────────────────────────────────────────
// Date handlers
// ─────────────────────────────────────────────

Map<String, dynamic>? _handleLastPeriod(RegExpMatch match, DateTime ref) {
  final period = match.group(2)!.toLowerCase();
  DateTime start;
  DateTime end = DateTime(ref.year, ref.month, ref.day);

  switch (period) {
    case 'week':
      start = end.subtract(const Duration(days: 7));
      break;
    case 'month':
      start = DateTime(ref.year, ref.month - 1, ref.day.clamp(1, _daysInMonth(ref.year, ref.month - 1)));
      break;
    case 'year':
      start = DateTime(ref.year - 1, ref.month, ref.day.clamp(1, _daysInMonth(ref.year - 1, ref.month)));
      break;
    default:
      return null;
  }
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleThisPeriod(RegExpMatch match, DateTime ref) {
  final period = match.group(2)!.toLowerCase();
  DateTime start;
  DateTime end = DateTime(ref.year, ref.month, ref.day, 23, 59, 59);

  switch (period) {
    case 'week':
      // Start of current week (Monday)
      final weekday = ref.weekday;
      start = ref.subtract(Duration(days: weekday - 1));
      break;
    case 'month':
      start = DateTime(ref.year, ref.month, 1);
      break;
    case 'year':
      start = DateTime(ref.year, 1, 1);
      break;
    default:
      return null;
  }
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleYesterday(RegExpMatch match, DateTime ref) {
  final term = match.group(0)!.toLowerCase();
  DateTime date;
  if (term == 'day before yesterday') {
    date = ref.subtract(const Duration(days: 2));
  } else {
    date = ref.subtract(const Duration(days: 1));
  }
  final start = DateTime(date.year, date.month, date.day);
  final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleTimeAgo(RegExpMatch match, DateTime ref) {
  final amount = int.tryParse(match.group(1) ?? '');
  final unit = match.group(2)!.toLowerCase();
  if (amount == null) return null;

  DateTime start;
  switch (unit) {
    case 'day':
    case 'days':
      start = ref.subtract(Duration(days: amount));
      break;
    case 'week':
    case 'weeks':
      start = ref.subtract(Duration(days: amount * 7));
      break;
    case 'month':
    case 'months':
      final targetMonth = ref.month - amount;
      final targetYear = ref.year + ((targetMonth - 1) ~/ 12);
      final normalizedMonth = ((targetMonth - 1) % 12) + 1;
      start = DateTime(targetYear, normalizedMonth, ref.day.clamp(1, _daysInMonth(targetYear, normalizedMonth)));
      break;
    case 'year':
    case 'years':
      start = DateTime(ref.year - amount, ref.month, ref.day.clamp(1, _daysInMonth(ref.year - amount, ref.month)));
      break;
    default:
      return null;
  }
  return {'dateFrom': start, 'dateTo': ref};
}

Map<String, dynamic>? _handleToday(RegExpMatch match, DateTime ref) {
  final start = DateTime(ref.year, ref.month, ref.day);
  final end = DateTime(ref.year, ref.month, ref.day, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleMonthDayYear(RegExpMatch match, DateTime ref) {
  final monthStr = match.group(1)!.toLowerCase();
  final day = int.tryParse(match.group(2) ?? '');
  final yearStr = match.group(3);
  final year = yearStr != null ? int.tryParse(yearStr) : ref.year;
  final month = _parseMonth(monthStr);
  if (month == null || day == null || year == null) return null;
  final start = DateTime(year, month, day);
  final end = DateTime(year, month, day, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

int? _parseMonth(String monthStr) {
  final months = {
    'jan': 1, 'january': 1,
    'feb': 2, 'february': 2,
    'mar': 3, 'march': 3,
    'apr': 4, 'april': 4,
    'may': 5,
    'jun': 6, 'june': 6,
    'jul': 7, 'july': 7,
    'aug': 8, 'august': 8,
    'sep': 9, 'september': 9,
    'oct': 10, 'october': 10,
    'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };
  return months[monthStr.toLowerCase()];
}

Map<String, dynamic>? _handleIsoDate(RegExpMatch match, DateTime ref) {
  final year = int.tryParse(match.group(1) ?? '');
  final month = int.tryParse(match.group(2) ?? '');
  final day = int.tryParse(match.group(3) ?? '');
  if (year == null || month == null || day == null) return null;
  final start = DateTime(year, month, day);
  final end = DateTime(year, month, day, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleUsDate(RegExpMatch match, DateTime ref) {
  final month = int.tryParse(match.group(1) ?? '');
  final day = int.tryParse(match.group(2) ?? '');
  final year = int.tryParse(match.group(3) ?? '');
  if (month == null || day == null || year == null) return null;
  final start = DateTime(year, month, day);
  final end = DateTime(year, month, day, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleYearOnly(RegExpMatch match, DateTime ref) {
  final year = int.tryParse(match.group(1) ?? '');
  if (year == null) return null;
  final start = DateTime(year, 1, 1);
  final end = DateTime(year, 12, 31, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleMonthOnly(RegExpMatch match, DateTime ref) {
  final monthStr = match.group(1)!.toLowerCase();
  final month = _parseMonth(monthStr);
  if (month == null) return null;
  final start = DateTime(ref.year, month, 1);
  final end = DateTime(ref.year, month + 1, 0, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

Map<String, dynamic>? _handleWeekday(RegExpMatch match, DateTime ref) {
  final isLast = match.group(1)!.toLowerCase() == 'last';
  final weekdayStr = match.group(2)!.toLowerCase();
  final targetWeekday = _parseWeekday(weekdayStr);
  if (targetWeekday == null) return null;

  int daysUntil = (targetWeekday - ref.weekday) % 7;
  if (isLast) {
    daysUntil -= 7;
  }
  if (daysUntil > 0) daysUntil -= 7; // Past only

  final date = ref.add(Duration(days: daysUntil));
  final start = DateTime(date.year, date.month, date.day);
  final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
  return {'dateFrom': start, 'dateTo': end};
}

int? _parseWeekday(String weekday) {
  const weekdays = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3,
    'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
  };
  return weekdays[weekday.toLowerCase()];
}

// ─────────────────────────────────────────────
// Camera handlers
// ─────────────────────────────────────────────

Map<String, dynamic>? _handleIPhone(RegExpMatch match) {
  final model = match.group(1)!.trim().toLowerCase().replaceAll(' ', '');
  return {
    'cameraMake': 'Apple',
    'cameraModel': 'iPhone $model',
  };
}

Map<String, dynamic>? _handleSamsung(RegExpMatch match) {
  final model = match.group(1)!.trim();
  return {
    'cameraMake': 'Samsung',
    'cameraModel': model,
  };
}

Map<String, dynamic>? _handlePixel(RegExpMatch match) {
  final model = match.group(1)!.trim();
  return {
    'cameraMake': 'Google',
    'cameraModel': model,
  };
}

Map<String, dynamic>? _handleCameraMake(RegExpMatch match) {
  final make = match.group(1)!.toLowerCase();
  return {
    'cameraMake': make[0].toUpperCase() + make.substring(1),
  };
}

Map<String, dynamic>? _handleGenericModel(RegExpMatch match) {
  final model = match.group(1)!.toUpperCase();
  return {
    'cameraModel': model,
  };
}

// ─────────────────────────────────────────────
// Location handlers
// ─────────────────────────────────────────────

Map<String, dynamic>? _handleLocation(RegExpMatch match) {
  final location = match.group(1)?.trim();
  if (location == null || location.isEmpty) return null;
  return {'hasLocation': true, 'locationLabel': location};
}

int _daysInMonth(int year, int month) {
  final m = month <= 0 ? 12 + ((month - 1) % 12) + 1 : month;
  final adjusted = month <= 0 ? year - 1 : year;
  return DateTime(adjusted, m + 1, 0).day;
}
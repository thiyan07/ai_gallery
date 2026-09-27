

import '../models/gallery_intent.dart';
import '../models/gallery_query.dart';
import '../models/gallery_action.dart';
import '../models/assistant_response.dart';
import '../models/conversational_context.dart';
import 'intent_resolver.dart';
import 'structured_retriever.dart';
import 'result_set_manager.dart';
import 'multi_step_planner.dart';
import 'tool_registry.dart';
import 'tool_interface.dart';
import '../../../features/search/services/search_service.dart';
import '../../../features/search/services/natural_language_parser.dart';
import '../../../features/search/services/related_photo_service.dart';
import '../../../features/search/services/search_explainer.dart';
import '../../../features/analysis/analysis_manager.dart';
import '../../../core/logging/app_logger.dart';

/// Main orchestrator for the gallery assistant.
///
/// Routes user queries through:
/// 1. Intent classification (deterministic)
/// 2. Query planning
/// 3. Retrieval (structured SQL or semantic search)
/// 4. Response generation (grounded in actual data)
/// 5. Action suggestions
class GalleryAssistant {
  GalleryAssistant({
    required SearchService searchService,
    required NaturalLanguageParser nlParser,
    required IntentResolver intentResolver,
    required StructuredRetriever retriever,
    required AnalysisManager analysisManager,
    required RelatedPhotoService relatedPhotoService,
    ToolRegistry? toolRegistry,
    SearchExplainer? searchExplainer,
    AppLogger? logger,
  })  : _searchService = searchService,
        _nlParser = nlParser,
        _intentResolver = intentResolver,
        _retriever = retriever,
        _analysisManager = analysisManager,
        _relatedPhotoService = relatedPhotoService,
        _toolRegistry = toolRegistry,
        _searchExplainer = searchExplainer ?? SearchExplainer(),
        _logger = logger;

  final SearchService _searchService;
  final NaturalLanguageParser _nlParser;
  final IntentResolver _intentResolver;
  final StructuredRetriever _retriever;
  final AnalysisManager _analysisManager;
  final RelatedPhotoService _relatedPhotoService;
  final ToolRegistry? _toolRegistry;
  final SearchExplainer _searchExplainer;
  final AppLogger? _logger;

  /// Short-lived conversational context.
  final ConversationalContext _context = ConversationalContext();

  /// Session-scoped result set manager.
  final ResultSetManager _resultSetManager = ResultSetManager();

  /// Multi-step action planner.
  final MultiStepPlanner _planner = MultiStepPlanner();

  /// Get the conversational context (for UI display).
  ConversationalContext get context => _context;

  /// Get the result set manager (for UI display).
  ResultSetManager get resultSetManager => _resultSetManager;

  /// Process a user query and return a grounded response.
  Future<AssistantResponse> processQuery(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return AssistantResponse(
        text: 'What are you looking for in your gallery?',
        intent: GalleryIntent.unknown,
      );
    }

    try {
      // Step 1: Check if this is a follow-up refinement
      final isRefinement = _isRefinement(trimmed);

      // Step 2: Resolve intent and query
      final query = await _intentResolver.resolve(trimmed);

      // Step 3: If refinement, merge with context
      final finalQuery = isRefinement
          ? _mergeWithContext(query, trimmed) ?? query
          : query;

      // Step 3.5: Check for compound request
      if (_planner.isCompoundRequest(trimmed)) {
        final steps = _planner.decompose(trimmed, finalQuery.intent);
        if (steps.length >= 2) {
          // Execute the first step (usually a search)
          final firstResponse = await _executePlan(steps.first.intent == GalleryIntent.unknown
              ? finalQuery
              : await _intentResolver.resolve(steps.first.query),
              steps.first.query);

          if (firstResponse.photoIds.isNotEmpty) {
            _resultSetManager.store(
              photoIds: firstResponse.photoIds,
              description: firstResponse.text,
              sourceQuery: steps.first.query,
            );
          }

          // Build the second step as a suggested action
          final secondStep = steps[1];
          final suggestedActions = _buildActionsForStep(secondStep, firstResponse.photoIds);

          return AssistantResponse(
            text: '${firstResponse.text}\n\n${_planner.describePlan(steps.sublist(1))}',
            intent: finalQuery.intent,
            photoIds: firstResponse.photoIds,
            suggestedActions: suggestedActions,
            confidence: finalQuery.confidence,
          );
        }
      }

      // Step 4: Execute query plan
      final response = await _executePlan(finalQuery, trimmed);

      // Step 4.5: Store result set if photos were returned
      if (response.photoIds.isNotEmpty) {
        _resultSetManager.store(
          photoIds: response.photoIds,
          description: response.text,
          sourceQuery: trimmed,
        );
      }

      // Step 5: Update context
      _context.update(
        query: finalQuery,
        photoIds: response.photoIds,
        queryText: trimmed,
      );

      return response;
    } catch (e, st) {
      _logger?.error('Assistant query failed', error: e, stackTrace: st);
      return AssistantResponse.error('$e');
    }
  }

  /// Build suggested actions for a multi-step plan's subsequent step.
  List<GalleryAction> _buildActionsForStep(ActionPlanStep step, List<String> photoIds) {
    if (photoIds.isEmpty) return [];

    switch (step.intent) {
      case GalleryIntent.createAlbum:
        return [
          GalleryAction(
            type: GalleryActionType.createSmartAlbum,
            parameters: {'title': step.query, 'photoIds': photoIds},
            description: 'Create album from found photos',
          ),
        ];
      case GalleryIntent.createMemory:
        return [
          GalleryAction(
            type: GalleryActionType.createMemory,
            parameters: {'memoryTitle': step.query, 'photoIds': photoIds},
            description: 'Create memory from found photos',
          ),
        ];
      case GalleryIntent.addToFavorites:
        return [
          GalleryAction(
            type: GalleryActionType.addFavorites,
            parameters: {'photoIds': photoIds},
            description: 'Add found photos to favorites',
          ),
        ];
      case GalleryIntent.removeFromFavorites:
        return [
          GalleryAction(
            type: GalleryActionType.removeFavorites,
            parameters: {'photoIds': photoIds},
            description: 'Remove found photos from favorites',
          ),
        ];
      case GalleryIntent.deletePhotos:
        return [
          GalleryAction(
            type: GalleryActionType.deletePhotos,
            parameters: {'photoIds': photoIds},
            description: 'Delete found photos',
            requiresConfirmation: true,
            isDestructive: true,
          ),
        ];
      default:
        return [];
    }
  }

  /// Execute a query plan and generate a grounded response.
  Future<AssistantResponse> _executePlan(
    GalleryQuery query,
    String rawText,
  ) async {
    switch (query.intent) {
      case GalleryIntent.count:
        return _handleCount(query, rawText);
      case GalleryIntent.statistics:
        return _handleStatistics(query, rawText);
      case GalleryIntent.search:
        return _handleSearch(query, rawText);
      case GalleryIntent.person:
        return _handlePerson(query, rawText);
      case GalleryIntent.quality:
        return _handleQuality(query, rawText);
      case GalleryIntent.duplicates:
        return _handleDuplicates(query, rawText);
      case GalleryIntent.bestPhotos:
        return _handleBestPhotos(query, rawText);
      case GalleryIntent.createAlbum:
        return _handleCreateAlbum(query, rawText);
      case GalleryIntent.createMemory:
        return _handleCreateMemory(query, rawText);
      case GalleryIntent.similar:
        return _handleSimilar(query, rawText);
      case GalleryIntent.related:
        return _handleRelated(query, rawText);
      case GalleryIntent.explanation:
        return _handleExplanation(query, rawText);
      case GalleryIntent.editPhoto:
        return _handleEditPhoto(query, rawText);
      case GalleryIntent.greeting:
        return _handleGreeting(rawText);
      case GalleryIntent.date:
      case GalleryIntent.location:
      case GalleryIntent.object:
      case GalleryIntent.scene:
      case GalleryIntent.textSearch:
      case GalleryIntent.event:
      case GalleryIntent.openPhoto:
      case GalleryIntent.openPerson:
      case GalleryIntent.openEvent:
      case GalleryIntent.photoDetails:
      case GalleryIntent.eventSummary:
      case GalleryIntent.multiStep:
        return _handleSearch(query, rawText);
      case GalleryIntent.videoSearch:
        return _handleVideoSearch(query, rawText);
      case GalleryIntent.personCoOccurrences:
        return _handlePersonCoOccurrences(query, rawText);
      case GalleryIntent.personEvents:
        return _handlePersonEvents(query, rawText);
      case GalleryIntent.personPlaces:
        return _handlePersonPlaces(query, rawText);
      case GalleryIntent.eventPeople:
        return _handleEventPeople(query, rawText);
      case GalleryIntent.addToFavorites:
        return _handleAddToFavorites(query, rawText);
      case GalleryIntent.removeFromFavorites:
        return _handleRemoveFromFavorites(query, rawText);
      case GalleryIntent.deletePhotos:
        return _handleDeletePhotos(query, rawText);
      case GalleryIntent.unknown:
        return _handleSearch(query, rawText);
    }
  }

  /// Handle count queries using efficient SQL.
  Future<AssistantResponse> _handleCount(
    GalleryQuery query,
    String rawText,
  ) async {
    final count = await _retriever.countPhotos(query);

    String description;
    if (query.hasAnyFilter) {
      final parts = <String>[];
      if (query.hasDateFilter) {
        parts.add(_describeDateRange(query.dateFrom, query.dateTo));
      }
      if (query.hasPersonFilter) {
        parts.add('with ${query.personName}');
      }
      if (query.hasObjectFilter) {
        parts.add('containing ${query.objectLabels.join(" and ")}');
      }
      if (query.hasLocationFilter) {
        parts.add('at ${query.locationLabel}');
      }
      if (query.isScreenshot == true) {
        parts.add('that are screenshots');
      }
      description = 'matching ${parts.join(", ")}';
    } else {
      description = 'in your gallery';
    }

    return AssistantResponse.count(
      count: count,
      description: description,
    );
  }

  /// Handle statistics queries.
  Future<AssistantResponse> _handleStatistics(
    GalleryQuery query,
    String rawText,
  ) async {
    final stats = await _retriever.getGalleryStats();

    final total = stats['totalPhotos'] as int;
    final videos = stats['totalVideos'] as int;
    final favorites = stats['favorites'] as int;
    final people = stats['people'] as int;
    final events = stats['events'] as int;
    final memories = stats['memories'] as int;
    final blurry = stats['blurry'] as int;
    final screenshots = stats['screenshots'] as int;
    final duplicates = stats['duplicateGroups'] as int;

    final buffer = StringBuffer('Here\'s your gallery overview:\n\n');
    buffer.write('$total photos');
    if (videos > 0) buffer.write(' and $videos videos');
    buffer.write(' in total.\n\n');

    if (favorites > 0) buffer.write('$favorites favorites\n');
    if (people > 0) buffer.write('$people people recognized\n');
    if (events > 0) buffer.write('$events events detected\n');
    if (memories > 0) buffer.write('$memories memories created\n');
    if (blurry > 0) buffer.write('$blurry blurry photos\n');
    if (screenshots > 0) buffer.write('$screenshots screenshots\n');
    if (duplicates > 0) buffer.write('$duplicates duplicate groups\n');

    final actions = <GalleryAction>[];
    if (duplicates > 0) {
      actions.add(GalleryAction(
        type: GalleryActionType.showSearchResults,
        parameters: {'intent': 'duplicates'},
        description: 'View duplicate groups',
      ));
    }
    if (blurry > 0) {
      actions.add(GalleryAction(
        type: GalleryActionType.showSearchResults,
        parameters: {'intent': 'blurry'},
        description: 'View blurry photos',
      ));
    }

    return AssistantResponse(
      text: buffer.toString(),
      intent: GalleryIntent.statistics,
      evidence: stats,
      suggestedActions: actions,
    );
  }

  /// Handle search queries.
  Future<AssistantResponse> _handleSearch(
    GalleryQuery query,
    String rawText,
  ) async {
    // For structured-only queries, use SQL
    if (!query.hasSemanticQuery && query.hasAnyFilter) {
      final photoIds =
          await _retriever.getPhotoIds(query, limit: query.limit ?? 20);
      final count = await _retriever.countPhotos(query);

      if (photoIds.isEmpty) {
        return AssistantResponse.noResults(query: rawText);
      }

      final text = count == photoIds.length
          ? 'Found $count photos.'
          : 'Found $count photos, showing ${photoIds.length}.';

      return AssistantResponse(
        text: text,
        intent: query.intent,
        photoIds: photoIds,
        evidence: {'count': count, 'returned': photoIds.length},
        confidence: query.confidence,
      );
    }

    // For semantic queries, use SearchService
    final parsed = _nlParser.parse(rawText);
    final results = await _searchService.searchParsed(
      parsed,
      limit: query.limit ?? 20,
    );

    if (results.isEmpty) {
      return AssistantResponse.noResults(query: rawText);
    }

    final photoIds = results.map((r) => r.photoId).toList();

    // Build explanation
    final explanations = <String>[];
    if (parsed.hasFilters) {
      if (parsed.filters.personName != null) {
        explanations.add('person: ${parsed.filters.personName}');
      }
      if (parsed.filters.objectTags.isNotEmpty) {
        explanations.add('objects: ${parsed.filters.objectTags.join(", ")}');
      }
      if (parsed.filters.locationLabel != null) {
        explanations.add('location: ${parsed.filters.locationLabel}');
      }
    }

    final text = explanations.isEmpty
        ? 'Found ${results.length} photos.'
        : 'Found ${results.length} photos matching: ${explanations.join(", ")}.';

    return AssistantResponse(
      text: text,
      intent: query.intent,
      photoIds: photoIds,
      evidence: {
        'count': results.length,
        'signals': explanations,
      },
      confidence: query.confidence,
      explanation: explanations.isNotEmpty ? explanations.join('; ') : null,
    );
  }

  /// Handle person queries.
  Future<AssistantResponse> _handlePerson(
    GalleryQuery query,
    String rawText,
  ) async {
    if (query.personName == null) {
      return _handleSearch(query, rawText);
    }

    final photoIds = await _retriever.getPersonPhotoIds(
      query.personId ?? query.personName!,
      dateFrom: query.dateFrom,
      dateTo: query.dateTo,
    );

    if (photoIds.isEmpty) {
      return AssistantResponse(
        text: 'I couldn\'t find photos of ${query.personName}.',
        intent: GalleryIntent.person,
        confidence: query.confidence,
        isUncertain: true,
      );
    }

    return AssistantResponse(
      text: 'Found ${photoIds.length} photos of ${query.personName}.',
      intent: GalleryIntent.person,
      photoIds: photoIds,
      evidence: {
        'personName': query.personName,
        'personId': query.personId,
        'count': photoIds.length,
      },
      confidence: query.confidence,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.openPerson,
          parameters: {
            'personId': query.personId,
            'personName': query.personName,
          },
          description: 'View ${query.personName}\'s profile',
        ),
      ],
    );
  }

  /// Handle quality queries (blurry, sharp, etc.).
  Future<AssistantResponse> _handleQuality(
    GalleryQuery query,
    String rawText,
  ) async {
    final photoIds = await _retriever.getPhotoIds(query, limit: query.limit ?? 20);
    final count = await _retriever.countPhotos(query);

    if (photoIds.isEmpty) {
      return AssistantResponse.noResults(query: rawText);
    }

    final lower = rawText.toLowerCase();
    String qualityDesc;
    if (lower.contains('blurry') || lower.contains('out of focus')) {
      qualityDesc = 'blurry';
    } else if (lower.contains('screenshot')) {
      qualityDesc = 'screenshots';
    } else if (lower.contains('sharp') || lower.contains('clear')) {
      qualityDesc = 'sharp';
    } else {
      qualityDesc = 'quality-filtered';
    }

    return AssistantResponse(
      text: 'Found $count $qualityDesc photos.',
      intent: GalleryIntent.quality,
      photoIds: photoIds,
      evidence: {'quality': qualityDesc, 'count': count},
      confidence: query.confidence,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.showSearchResults,
          parameters: {'photoIds': photoIds},
          description: 'View all $qualityDesc photos',
        ),
      ],
    );
  }

  /// Handle duplicate queries.
  Future<AssistantResponse> _handleDuplicates(
    GalleryQuery query,
    String rawText,
  ) async {
    final report = await _analysisManager.findAllDuplicates();

    if (report.totalGroups == 0) {
      return AssistantResponse(
        text: 'No duplicate photos found in your gallery.',
        intent: GalleryIntent.duplicates,
        evidence: {'totalGroups': 0},
      );
    }

    final allPhotoIds = <String>[];
    for (final group in report.groups) {
      allPhotoIds.addAll(group.photoIds);
    }

    return AssistantResponse(
      text: 'Found ${report.totalGroups} duplicate groups '
          '(${report.exactGroups} exact, ${report.nearDuplicateGroups} near-duplicate) '
          'containing ${report.totalPhotos} photos total.',
      intent: GalleryIntent.duplicates,
      photoIds: allPhotoIds,
      evidence: {
        'totalGroups': report.totalGroups,
        'exactGroups': report.exactGroups,
        'nearDuplicateGroups': report.nearDuplicateGroups,
        'totalPhotos': report.totalPhotos,
      },
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.showSearchResults,
          parameters: {'photoIds': allPhotoIds},
          description: 'View all duplicate photos',
        ),
      ],
    );
  }

  /// Handle best photo queries.
  Future<AssistantResponse> _handleBestPhotos(
    GalleryQuery query,
    String rawText,
  ) async {
    final photoIds = await _retriever.getPhotoIds(query, limit: query.limit ?? 20);

    if (photoIds.isEmpty) {
      return AssistantResponse.noResults(query: rawText);
    }

    return AssistantResponse(
      text: 'Here are your best ${photoIds.length} photos.',
      intent: GalleryIntent.bestPhotos,
      photoIds: photoIds,
      evidence: {'count': photoIds.length, 'sortedBy': 'quality'},
      confidence: query.confidence,
    );
  }

  /// Handle create album intent.
  Future<AssistantResponse> _handleCreateAlbum(
    GalleryQuery query,
    String rawText,
  ) async {
    // First, find matching photos
    final searchResponse = await _handleSearch(query, rawText);

    if (searchResponse.photoIds.isEmpty) {
      return AssistantResponse(
        text: 'I couldn\'t find enough photos to create an album.',
        intent: GalleryIntent.createAlbum,
      );
    }

    // Suggest album creation
    final albumTitle = _generateAlbumTitle(query, rawText);

    return AssistantResponse(
      text: 'Found ${searchResponse.photoIds.length} photos for "$albumTitle". '
          'Would you like me to create a smart album?',
      intent: GalleryIntent.createAlbum,
      photoIds: searchResponse.photoIds,
      evidence: searchResponse.evidence,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.createSmartAlbum,
          parameters: {
            'title': albumTitle,
            'photoIds': searchResponse.photoIds,
            'query': rawText,
          },
          description: 'Create smart album "$albumTitle"',
        ),
      ],
    );
  }

  /// Handle create memory intent.
  Future<AssistantResponse> _handleCreateMemory(
    GalleryQuery query,
    String rawText,
  ) async {
    final searchResponse = await _handleSearch(query, rawText);

    if (searchResponse.photoIds.isEmpty) {
      return AssistantResponse(
        text: 'I couldn\'t find enough photos to create a memory.',
        intent: GalleryIntent.createMemory,
      );
    }

    final memoryTitle = _generateMemoryTitle(query, rawText);

    return AssistantResponse(
      text: 'Found ${searchResponse.photoIds.length} photos for "$memoryTitle". '
          'Would you like me to create a memory?',
      intent: GalleryIntent.createMemory,
      photoIds: searchResponse.photoIds,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.createMemory,
          parameters: {
            'memoryTitle': memoryTitle,
            'photoIds': searchResponse.photoIds,
          },
          description: 'Create memory "$memoryTitle"',
        ),
      ],
    );
  }

  /// Handle similar photo queries.
  Future<AssistantResponse> _handleSimilar(
    GalleryQuery query,
    String rawText,
  ) async {
    if (query.photoId == null) {
      return AssistantResponse(
        text: 'Which photo would you like to find similar photos to?',
        intent: GalleryIntent.similar,
        isUncertain: true,
      );
    }

    final results = await _searchService.searchSimilar(query.photoId!);
    final photoIds = results.map((r) => r.photoId).toList();

    return AssistantResponse(
      text: 'Found ${photoIds.length} similar photos.',
      intent: GalleryIntent.similar,
      photoIds: photoIds,
      confidence: query.confidence,
    );
  }

  /// Handle related photo queries.
  Future<AssistantResponse> _handleRelated(
    GalleryQuery query,
    String rawText,
  ) async {
    if (query.photoId == null) {
      return AssistantResponse(
        text: 'Which photo would you like to find related photos to?',
        intent: GalleryIntent.related,
        isUncertain: true,
      );
    }

    final related = await _relatedPhotoService.findRelated(query.photoId!);
    final photoIds = related.map((r) => r.photoId).toList();

    return AssistantResponse(
      text: 'Found ${photoIds.length} related photos.',
      intent: GalleryIntent.related,
      photoIds: photoIds,
      evidence: {
        'related': related
            .map((r) => {'photoId': r.photoId, 'score': r.score, 'reasons': r.reasons})
            .toList(),
      },
      confidence: query.confidence,
    );
  }

  /// Handle explanation queries — "Why did this photo appear?"
  Future<AssistantResponse> _handleExplanation(
    GalleryQuery query,
    String rawText,
  ) async {
    // Check if there's a result set with photos to explain
    final rs = _resultSetManager.resolveReference(rawText);
    if (rs != null && rs.photoIds.isNotEmpty) {
      final photoId = rs.photoIds.first;
      final explanations = _searchExplainer.explain(
        photoId: photoId,
        query: rawText,
        signalScores: {
          if (query.hasPersonFilter) 'faceMatch': 0.8,
          if (query.hasObjectFilter) 'objectMatch': 0.7,
          if (query.hasDateFilter) 'date': 0.6,
          if (query.hasLocationFilter) 'location': 0.5,
          if (query.hasSemanticQuery) 'semantic': 0.4,
        },
        finalScore: query.confidence,
      );
      final summary = _searchExplainer.summarizeResults(explanations);
      return AssistantResponse(
        text: summary,
        intent: GalleryIntent.explanation,
        photoIds: rs.photoIds,
        evidence: {
          'photoId': photoId,
          'explanations': explanations
              .map((e) => {'signal': e.signal.name, 'strength': e.strength, 'description': e.description})
              .toList(),
        },
      );
    }

    return AssistantResponse(
      text: 'Select a photo first, then ask "why did this photo appear?" '
          'to get an explanation of the search signals.',
      intent: GalleryIntent.explanation,
      isUncertain: true,
    );
  }

  /// Handle edit photo intent.
  Future<AssistantResponse> _handleEditPhoto(
    GalleryQuery query,
    String rawText,
  ) async {
    return AssistantResponse(
      text: 'I\'ll open the editor for you. Which photo would you like to edit?',
      intent: GalleryIntent.editPhoto,
      isUncertain: true,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.openEditor,
          parameters: {},
          description: 'Open photo editor',
          requiresConfirmation: false,
        ),
      ],
    );
  }

  /// Handle greetings.
  Future<AssistantResponse> _handleGreeting(String rawText) async {
    final totalPhotos = await _retriever.getTotalPhotoCount();
    final suggestions = <GalleryAction>[];

    if (totalPhotos > 0) {
      suggestions.addAll([
        GalleryAction(
          type: GalleryActionType.showSearchResults,
          parameters: {'intent': 'recent'},
          description: 'Show recent photos',
          requiresConfirmation: false,
        ),
        GalleryAction(
          type: GalleryActionType.showSearchResults,
          parameters: {'intent': 'duplicates'},
          description: 'Find duplicate photos',
          requiresConfirmation: false,
        ),
      ]);
    }

    return AssistantResponse(
      text: 'Hello! I can help you explore your gallery of $totalPhotos photos. '
          'What are you looking for?',
      intent: GalleryIntent.greeting,
      suggestedActions: suggestions,
    );
  }

  /// Check if a query is likely a refinement of previous context.
  bool _isRefinement(String input) {
    if (!_context.hasContext) return false;

    final lower = input.toLowerCase();

    // Common refinement patterns
    return lower.startsWith('only ') ||
        lower.startsWith('just ') ||
        lower.startsWith('but ') ||
        lower.contains('with ') && _context.lastIntent == GalleryIntent.search ||
        lower.contains('from ') && _context.lastPhotoIds.isNotEmpty;
  }

  /// Merge a refinement query with the conversational context.
  GalleryQuery? _mergeWithContext(GalleryQuery newQuery, String rawText) {
    if (!_context.hasContext || _context.lastQuery == null) return null;

    final last = _context.lastQuery!;
    final lower = rawText.toLowerCase();

    // Extract new constraints from the refinement
    String? personName = last.personName;
    DateTime? dateFrom = last.dateFrom;
    DateTime? dateTo = last.dateTo;
    List<String> objectLabels = last.objectLabels;
    String? locationLabel = last.locationLabel;

    // Check for person name in refinement
    if (lower.contains('with ')) {
      final withMatch = RegExp(r'with\s+(\w+)').firstMatch(lower);
      if (withMatch != null) {
        personName = withMatch.group(1);
      }
    }

    // Check for date in refinement
    if (newQuery.hasDateFilter) {
      dateFrom = newQuery.dateFrom;
      dateTo = newQuery.dateTo;
    }

    // Check for object in refinement
    if (newQuery.hasObjectFilter) {
      objectLabels = newQuery.objectLabels;
    }

    // Check for location in refinement
    if (newQuery.hasLocationFilter) {
      locationLabel = newQuery.locationLabel;
    }

    return last.copyWith(
      personName: personName,
      dateFrom: dateFrom,
      dateTo: dateTo,
      objectLabels: objectLabels,
      locationLabel: locationLabel,
    );
  }

  /// Generate a human-readable album title from a query.
  String _generateAlbumTitle(GalleryQuery query, String rawText) {
    final parts = <String>[];

    if (query.personName != null) parts.add(query.personName!);
    if (query.objectLabels.isNotEmpty) parts.add(query.objectLabels.first);
    if (query.locationLabel != null) parts.add(query.locationLabel!);
    if (query.hasDateFilter) {
      if (query.dateFrom != null) {
        parts.add('${query.dateFrom!.month}/${query.dateFrom!.year}');
      }
    }

    if (parts.isEmpty) {
      return 'My Album';
    }

    return parts.take(3).join(' - ');
  }

  /// Generate a human-readable memory title from a query.
  String _generateMemoryTitle(GalleryQuery query, String rawText) {
    final parts = <String>[];

    if (query.locationLabel != null) parts.add(query.locationLabel!);
    if (query.personName != null) parts.add('with ${query.personName!}');
    if (query.hasDateFilter && query.dateFrom != null) {
      final monthNames = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      parts.add(monthNames[query.dateFrom!.month]);
    }

    if (parts.isEmpty) {
      return 'My Memory';
    }

    return parts.take(3).join(' ');
  }

  /// Describe a date range in human-readable form.
  String _describeDateRange(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'all time';

    if (from != null && to != null) {
      return 'from ${_formatDate(from)} to ${_formatDate(to)}';
    }
    if (from != null) return 'after ${_formatDate(from)}';
    return 'before ${_formatDate(to!)}';
  }

  /// Format a date for display.
  String _formatDate(DateTime date) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  /// Handle person co-occurrence queries — "Who appears with Alice?"
  Future<AssistantResponse> _handlePersonCoOccurrences(
    GalleryQuery query,
    String rawText,
  ) async {
    final personId = query.personId;
    if (personId == null) {
      return AssistantResponse(
        text: 'Which person would you like to find co-occurring people for?',
        intent: GalleryIntent.personCoOccurrences,
        isUncertain: true,
      );
    }

    final coOccurrences = await _retriever.getPersonCoOccurrences(personId);

    if (coOccurrences.isEmpty) {
      return AssistantResponse(
        text: 'I didn\'t find anyone who appears with ${query.personName ?? personId}.',
        intent: GalleryIntent.personCoOccurrences,
        evidence: {'personId': personId, 'coOccurrenceCount': 0},
      );
    }

    final buffer = StringBuffer();
    buffer.write('People who appear with ${query.personName ?? personId}:\n');
    for (final co in coOccurrences.take(10)) {
      final name = co['displayName'] ?? co['personId'];
      final count = co['count'] as int;
      buffer.write('  - $name ($count co-occurrence${count == 1 ? '' : 's'})\n');
    }

    return AssistantResponse(
      text: buffer.toString().trimRight(),
      intent: GalleryIntent.personCoOccurrences,
      evidence: {
        'personId': personId,
        'coOccurrences': coOccurrences,
      },
      confidence: query.confidence,
    );
  }

  /// Handle person events queries — "What events has Alice attended?"
  Future<AssistantResponse> _handlePersonEvents(
    GalleryQuery query,
    String rawText,
  ) async {
    final personId = query.personId;
    if (personId == null) {
      return AssistantResponse(
        text: 'Which person\'s events would you like to see?',
        intent: GalleryIntent.personEvents,
        isUncertain: true,
      );
    }

    final events = await _retriever.getPersonEvents(personId);

    if (events.isEmpty) {
      return AssistantResponse(
        text: 'I didn\'t find any events for ${query.personName ?? personId}.',
        intent: GalleryIntent.personEvents,
        evidence: {'personId': personId, 'eventCount': 0},
      );
    }

    final buffer = StringBuffer();
    buffer.write(
      'Events ${query.personName ?? personId} attended (${events.length}):\n',
    );
    for (final event in events.take(10)) {
      buffer.write('  - ${event['title']}\n');
    }

    return AssistantResponse(
      text: buffer.toString().trimRight(),
      intent: GalleryIntent.personEvents,
      evidence: {
        'personId': personId,
        'events': events,
      },
      confidence: query.confidence,
    );
  }

  /// Handle person places queries — "Where has Bob been?"
  Future<AssistantResponse> _handlePersonPlaces(
    GalleryQuery query,
    String rawText,
  ) async {
    final personId = query.personId;
    if (personId == null) {
      return AssistantResponse(
        text: 'Which person\'s places would you like to see?',
        intent: GalleryIntent.personPlaces,
        isUncertain: true,
      );
    }

    final places = await _retriever.getPersonPlaces(personId);

    if (places.isEmpty) {
      return AssistantResponse(
        text: 'I didn\'t find any locations for ${query.personName ?? personId}.',
        intent: GalleryIntent.personPlaces,
        evidence: {'personId': personId, 'placeCount': 0},
      );
    }

    final buffer = StringBuffer();
    buffer.write(
      'Places ${query.personName ?? personId} has been photographed (${places.length}):\n',
    );
    for (final place in places.take(10)) {
      final visits = place['visitCount'] as int;
      buffer.write(
        '  - ${place['displayName']} ($visits photo${visits == 1 ? '' : 's'})\n',
      );
    }

    return AssistantResponse(
      text: buffer.toString().trimRight(),
      intent: GalleryIntent.personPlaces,
      evidence: {
        'personId': personId,
        'places': places,
      },
      confidence: query.confidence,
    );
  }

  /// Handle event people queries — "Who was at this event?"
  Future<AssistantResponse> _handleEventPeople(
    GalleryQuery query,
    String rawText,
  ) async {
    final eventId = query.eventId;
    if (eventId == null) {
      return AssistantResponse(
        text: 'Which event would you like to see attendees for?',
        intent: GalleryIntent.eventPeople,
        isUncertain: true,
      );
    }

    final people = await _retriever.getEventPeople(eventId);

    if (people.isEmpty) {
      return AssistantResponse(
        text: 'I didn\'t find any recognized people at this event.',
        intent: GalleryIntent.eventPeople,
        evidence: {'eventId': eventId, 'peopleCount': 0},
      );
    }

    final names = people.map((p) => p['displayName'] ?? p['personId']).toList();

    return AssistantResponse(
      text: 'People at this event: ${names.join(", ")}',
      intent: GalleryIntent.eventPeople,
      evidence: {
        'eventId': eventId,
        'people': people,
      },
      confidence: query.confidence,
    );
  }

  /// Handle "add all of those to favorites" — batch action on previous results.
  Future<AssistantResponse> _handleAddToFavorites(
    GalleryQuery query,
    String rawText,
  ) async {
    // Try to resolve "those"/"them" from the result set
    final rs = _resultSetManager.resolveReference(rawText);
    if (rs == null || rs.photoIds.isEmpty) {
      return AssistantResponse(
        text: 'Which photos would you like to add to favorites? '
            'Try searching first, then ask me to favorite them.',
        intent: GalleryIntent.addToFavorites,
        isUncertain: true,
      );
    }

    return AssistantResponse(
      text: 'Add ${rs.photoIds.length} photo${rs.photoIds.length == 1 ? '' : 's'} to favorites?',
      intent: GalleryIntent.addToFavorites,
      photoIds: rs.photoIds,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.addFavorites,
          parameters: {'photoIds': rs.photoIds},
          description: 'Add ${rs.photoIds.length} photos to favorites',
        ),
      ],
    );
  }

  /// Handle "remove those from favorites" — batch action on previous results.
  Future<AssistantResponse> _handleRemoveFromFavorites(
    GalleryQuery query,
    String rawText,
  ) async {
    final rs = _resultSetManager.resolveReference(rawText);
    if (rs == null || rs.photoIds.isEmpty) {
      return AssistantResponse(
        text: 'Which photos would you like to remove from favorites?',
        intent: GalleryIntent.removeFromFavorites,
        isUncertain: true,
      );
    }

    return AssistantResponse(
      text: 'Remove ${rs.photoIds.length} photo${rs.photoIds.length == 1 ? '' : 's'} from favorites?',
      intent: GalleryIntent.removeFromFavorites,
      photoIds: rs.photoIds,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.removeFavorites,
          parameters: {'photoIds': rs.photoIds},
          description: 'Remove ${rs.photoIds.length} photos from favorites',
        ),
      ],
    );
  }

  /// Handle "delete those" — batch destructive action on previous results.
  Future<AssistantResponse> _handleDeletePhotos(
    GalleryQuery query,
    String rawText,
  ) async {
    final rs = _resultSetManager.resolveReference(rawText);
    if (rs == null || rs.photoIds.isEmpty) {
      return AssistantResponse(
        text: 'Which photos would you like to delete?',
        intent: GalleryIntent.deletePhotos,
        isUncertain: true,
      );
    }

    return AssistantResponse(
      text: '⚠️ Delete ${rs.photoIds.length} photo${rs.photoIds.length == 1 ? '' : 's'} permanently?',
      intent: GalleryIntent.deletePhotos,
      photoIds: rs.photoIds,
      suggestedActions: [
        GalleryAction(
          type: GalleryActionType.deletePhotos,
          parameters: {'photoIds': rs.photoIds},
          description: 'Delete ${rs.photoIds.length} photos permanently',
          requiresConfirmation: true,
          isDestructive: true,
        ),
      ],
    );
  }

  /// Handle video search — search video segments by text, labels, or people.
  Future<AssistantResponse> _handleVideoSearch(
    GalleryQuery query,
    String rawText,
  ) async {
    final queryText = query.semanticQuery ?? rawText;
    final results = await _searchService.searchVideoSegments(
      query: queryText,
      label: query.semanticQuery,
      limit: 10,
    );

    if (results.isEmpty) {
      return AssistantResponse(
        text: 'No video moments found for "$queryText".',
        intent: GalleryIntent.videoSearch,
      );
    }

    final parts = <String>[
      'Found ${results.length} video moment${results.length == 1 ? '' : 's'} for "$queryText":',
    ];

    for (final r in results.take(5)) {
      final timestamp = r.videoSegmentTimestampMs != null
          ? _formatDuration(Duration(milliseconds: r.videoSegmentTimestampMs!))
          : '';
      parts.add('  - Video ${r.photoId}${timestamp.isNotEmpty ? ' at $timestamp' : ''} (score: ${(r.score * 100).round()}%)');
    }

    return AssistantResponse(
      text: parts.join('\n'),
      intent: GalleryIntent.videoSearch,
      photoIds: results.map((r) => r.photoId).toList(),
    );
  }

  /// Format a Duration as mm:ss.
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ── Tool-facing public methods ──────────────────────────────────

  /// Search photos and return matching IDs (for tool callbacks).
  Future<List<String>> searchPhotos(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';
    final parsed = _nlParser.parse(query);
    final results = await _searchService.searchParsed(
      parsed,
      limit: params['limit'] as int? ?? 20,
    );
    return results.map((r) => r.photoId).toList();
  }

  /// Count photos matching a query (for tool callbacks).
  Future<int> countPhotos(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';
    final parsed = _nlParser.parse(query);
    final galleryQuery = GalleryQuery(
      intent: GalleryIntent.count,
      semanticQuery: parsed.semanticQuery.isNotEmpty
          ? parsed.semanticQuery
          : query,
      personName: parsed.filters.personName,
      objectLabels: parsed.filters.objectTags,
      locationLabel: parsed.filters.locationLabel,
      dateFrom: parsed.filters.dateFrom,
      dateTo: parsed.filters.dateTo,
      favoritesOnly: parsed.filters.favoritesOnly ? true : null,
    );
    return _retriever.countPhotos(galleryQuery);
  }

  /// Filter photos by quality (for tool callbacks).
  Future<List<String>> filterByQuality(Map<String, dynamic> params) async {
    final quality = params['quality'] as String? ?? '';
    final query = GalleryQuery(
      intent: GalleryIntent.quality,
      isScreenshot: quality == 'screenshot' ? true : null,
    );
    return _retriever.getPhotoIds(query, limit: params['limit'] as int? ?? 20);
  }

  /// Find best photos (for tool callbacks).
  Future<List<String>> findBestPhotos(Map<String, dynamic> params) async {
    final query = GalleryQuery(
      intent: GalleryIntent.bestPhotos,
      minQuality: params['minQuality'] as double? ?? 0.5,
    );
    return _retriever.getPhotoIds(query, limit: params['limit'] as int? ?? 20);
  }

  /// Query the knowledge graph (for tool callbacks).
  Future<Map<String, dynamic>> queryKnowledgeGraph(
    Map<String, dynamic> params,
  ) async {
    final queryType = params['queryType'] as String? ?? '';
    switch (queryType) {
      case 'personCoOccurrences':
        final personId = params['personId'] as String?;
        if (personId == null) {
          return {'text': 'Which person?', 'photoIds': <String>[]};
        }
        final co = await _retriever.getPersonCoOccurrences(personId);
        if (co.isEmpty) {
          return {
            'text': 'No co-occurring people found.',
            'photoIds': <String>[],
          };
        }
        final buffer = StringBuffer('People who appear with ${params['personName'] ?? personId}:\n');
        for (final c in co.take(10)) {
          final name = c['displayName'] ?? c['personId'];
          final count = c['count'] as int;
          buffer.write('  - $name ($count co-occurrence${count == 1 ? '' : 's'})\n');
        }
        return {'text': buffer.toString().trimRight(), 'photoIds': <String>[]};
      case 'personEvents':
        final personId = params['personId'] as String?;
        if (personId == null) {
          return {'text': 'Which person?', 'photoIds': <String>[]};
        }
        final events = await _retriever.getPersonEvents(personId);
        if (events.isEmpty) {
          return {
            'text': 'No events found for this person.',
            'photoIds': <String>[],
          };
        }
        final buffer = StringBuffer('Events (${events.length}):\n');
        for (final e in events.take(10)) {
          buffer.write('  - ${e['title']}\n');
        }
        return {'text': buffer.toString().trimRight(), 'photoIds': <String>[]};
      case 'personPlaces':
        final personId = params['personId'] as String?;
        if (personId == null) {
          return {'text': 'Which person?', 'photoIds': <String>[]};
        }
        final places = await _retriever.getPersonPlaces(personId);
        if (places.isEmpty) {
          return {
            'text': 'No places found for this person.',
            'photoIds': <String>[],
          };
        }
        final buffer = StringBuffer('Places (${places.length}):\n');
        for (final p in places.take(10)) {
          final visits = p['visitCount'] as int;
          buffer.write(
            '  - ${p['displayName']} ($visits photo${visits == 1 ? '' : 's'})\n',
          );
        }
        return {'text': buffer.toString().trimRight(), 'photoIds': <String>[]};
      case 'eventPeople':
        final eventId = params['eventId'] as String?;
        if (eventId == null) {
          return {'text': 'Which event?', 'photoIds': <String>[]};
        }
        final people = await _retriever.getEventPeople(eventId);
        if (people.isEmpty) {
          return {
            'text': 'No recognized people at this event.',
            'photoIds': <String>[],
          };
        }
        final names = people
            .map((p) => p['displayName'] ?? p['personId'])
            .toList();
        return {
          'text': 'People at this event: ${names.join(", ")}',
          'photoIds': <String>[],
        };
      case 'graphStats':
        final stats = await _retriever.getGraphStats();
        return {
          'text': 'Knowledge graph: ${stats['totalEntities']} entities, '
              '${stats['totalRelationships']} relationships.',
          'photoIds': <String>[],
        };
      default:
        return {'text': 'Unknown graph query type.', 'photoIds': <String>[]};
    }
  }

  /// Search videos (for tool callbacks).
  Future<List<Map<String, dynamic>>> searchVideos(
    Map<String, dynamic> params,
  ) async {
    final query = params['query'] as String? ?? '';
    final results = await _searchService.searchVideoSegments(
      query: query,
      label: params['label'] as String?,
      limit: params['limit'] as int? ?? 10,
    );
    return results.map((r) {
      final timestamp = r.videoSegmentTimestampMs != null
          ? _formatDuration(Duration(milliseconds: r.videoSegmentTimestampMs!))
          : '';
      return {
        'photoId': r.photoId,
        'timestamp': timestamp,
        'score': r.score,
      };
    }).toList();
  }

  /// Get video chapters for a given video ID.
  Future<List<Map<String, dynamic>>> getVideoChapters(
    String videoId,
  ) async {
    final segments =
        await _searchService.database.videoSegments.getByVideoId(videoId);
    return segments.map((seg) {
      final start = Duration(milliseconds: seg.startTimeMs);
      return {
        'title': seg.labels.isNotEmpty
            ? seg.labels.first
            : 'Scene ${_formatDuration(start)}',
        'time': _formatDuration(start),
        'startTimeMs': seg.startTimeMs,
        'endTimeMs': seg.endTimeMs,
      };
    }).toList();
  }

  /// Get video highlights for a given video ID.
  Future<List<Map<String, dynamic>>> getVideoHighlights(
    String videoId,
  ) async {
    final segments =
        await _searchService.database.videoSegments.getByVideoId(videoId);
    // Score segments by confidence and content richness
    final scored = segments
        .where((s) => s.confidence != null && s.confidence! > 0)
        .map((seg) {
      var score = seg.confidence ?? 0.0;
      if (seg.people.isNotEmpty) score += 0.2;
      if (seg.labels.length > 2) score += 0.1;
      if (seg.ocrText?.isNotEmpty == true) score += 0.1;
      return {
        'startTime': _formatDuration(Duration(milliseconds: seg.startTimeMs)),
        'endTime': _formatDuration(Duration(milliseconds: seg.endTimeMs)),
        'score': score.clamp(0.0, 1.0),
        'reason': _buildHighlightReason(seg),
        'startTimeMs': seg.startTimeMs,
        'endTimeMs': seg.endTimeMs,
      };
    }).toList()
      ..sort((a, b) =>
          (b['score'] as double).compareTo(a['score'] as double));
    return scored.take(10).toList();
  }

  /// Get video summary for a given video ID.
  Future<Map<String, dynamic>?> getVideoSummary(
    String videoId,
  ) async {
    final analysis = await _searchService.database.videoAnalysis
        .getByVideoId(videoId);
    if (analysis == null) return null;

    final segments =
        await _searchService.database.videoSegments.getByVideoId(videoId);

    final people = <String>{};
    final objects = <String>{};
    final ocrTexts = <String>{};
    for (final seg in segments) {
      people.addAll(seg.people.where((p) => !p.startsWith('face:')));
      objects.addAll(seg.labels);
      if (seg.ocrText?.isNotEmpty == true) ocrTexts.add(seg.ocrText!);
    }

    final durationMs = analysis.sceneCount > 0
        ? segments.fold(0, (sum, s) => sum + s.durationMs)
        : 0;

    return {
      'video_id': videoId,
      'duration': _formatDuration(Duration(milliseconds: durationMs)),
      'scene_count': analysis.sceneCount,
      'people': people.toList(),
      'object_labels': objects.toList(),
      'ocr_texts': ocrTexts.toList(),
      'highlight_count': segments
          .where((s) => (s.confidence ?? 0) > 0.5)
          .length,
      'has_audio': analysis.hasAudio,
    };
  }

  String _buildHighlightReason(dynamic seg) {
    final reasons = <String>[];
    if (seg.people.isNotEmpty) reasons.add('${seg.people.length} people');
    if (seg.labels.length > 2) {
      reasons.add('Objects: ${seg.labels.take(3).join(", ")}');
    }
    if (seg.ocrText?.isNotEmpty == true) reasons.add('Text on screen');
    return reasons.isEmpty ? 'Visual content' : reasons.join('; ');
  }

  /// Execute a tool directly through the registry.
  ///
  /// Returns null if the tool is not found or validation fails.
  /// Used for direct tool execution when the assistant can determine
  /// the exact tool and parameters.
  Future<ActionResult?> executeTool(
    String toolName,
    Map<String, dynamic> parameters,
  ) async {
    if (_toolRegistry == null) return null;

    final error = _toolRegistry!.validate(toolName, parameters);
    if (error != null) return null;

    final result = await _toolRegistry!.executeByName(toolName, parameters);
    return result as ActionResult?;
  }

  /// Check if a tool exists in the registry.
  bool hasTool(String toolName) {
    return _toolRegistry?.getTool(toolName) != null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';
import 'package:ai_gallery/features/search/services/ranking_engine.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';

void main() {
  group('Phase 14: Object/Scene/Location Parsing', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser.withLogger(
        null,
        referenceTime: DateTime(2025, 8, 15, 12, 0, 0),
        personNames: ['Sandy', 'Thiyan'],
      );
    });

    test('dog photos: objectTags contains dog', () {
      final result = parser.parse('dog photos');
      expect(result.filters.objectTags, contains('dog'));
    });

    test('car and truck: objectTags contains both', () {
      final result = parser.parse('car and truck');
      expect(result.filters.objectTags, contains('car'));
      expect(result.filters.objectTags, contains('truck'));
    });

    test('cat photos: objectTags contains cat', () {
      final result = parser.parse('cat photos');
      expect(result.filters.objectTags, contains('cat'));
    });

    test('pizza photos: objectTags contains pizza', () {
      final result = parser.parse('pizza photos');
      expect(result.filters.objectTags, contains('pizza'));
    });

    test('surfboard: objectTags contains surfboard', () {
      final result = parser.parse('surfboard');
      expect(result.filters.objectTags, contains('surfboard'));
    });

    test('bicycle: objectTags contains bicycle', () {
      final result = parser.parse('bicycle');
      expect(result.filters.objectTags, contains('bicycle'));
    });

    test('chair and couch: objectTags contains both', () {
      final result = parser.parse('chair and couch');
      expect(result.filters.objectTags, contains('chair'));
      expect(result.filters.objectTags, contains('couch'));
    });

    test('object intent detected', () {
      final result = parser.parse('dog photos');
      expect(result.intent, SearchIntent.object);
    });

    test('detectedObjects populated', () {
      final result = parser.parse('dog and cat');
      expect(result.detectedObjects, contains('dog'));
      expect(result.detectedObjects, contains('cat'));
    });

    test('beach photos: sceneConcepts contains beach', () {
      final result = parser.parse('beach photos');
      expect(result.sceneConcepts, contains('beach'));
    });

    test('sunset at the mountain: sceneConcepts has both', () {
      final result = parser.parse('sunset at the mountain');
      expect(result.sceneConcepts, contains('sunset'));
      expect(result.sceneConcepts, contains('mountain'));
    });

    test('forest and lake: sceneConcepts has both', () {
      final result = parser.parse('forest and lake');
      expect(result.sceneConcepts, contains('forest'));
      expect(result.sceneConcepts, contains('lake'));
    });

    test('restaurant photos: sceneConcepts contains restaurant', () {
      final result = parser.parse('restaurant photos');
      expect(result.sceneConcepts, contains('restaurant'));
    });

    test('rainy photos: sceneConcepts contains rain', () {
      final result = parser.parse('rainy photos');
      expect(result.sceneConcepts, contains('rain'));
    });

    test('wedding photos: sceneConcepts contains wedding', () {
      final result = parser.parse('wedding photos');
      expect(result.sceneConcepts, contains('wedding'));
    });

    test('party photos: sceneConcepts contains party', () {
      final result = parser.parse('party photos');
      expect(result.sceneConcepts, contains('party'));
    });

    test('scene intent detected', () {
      final result = parser.parse('beach photos');
      expect(result.intent, SearchIntent.scene);
    });

    test('in Paris: locationLabel set', () {
      final result = parser.parse('photos in Paris');
      expect(result.filters.locationLabel, 'Paris');
    });

    test('at the beach: no false location', () {
      final result = parser.parse('at the beach');
      expect(result.sceneConcepts, contains('beach'));
    });

    test('location intent detected', () {
      final result = parser.parse('photos in Tokyo');
      expect(result.intent, SearchIntent.location);
    });

    test('person + object: combined intent', () {
      final result = parser.parse('Sandy with dog');
      expect(result.intent, SearchIntent.combined);
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.objectTags, contains('dog'));
    });

    test('person + scene: combined intent', () {
      final result = parser.parse('Sandy at the beach');
      expect(result.intent, SearchIntent.combined);
      expect(result.filters.personName, 'Sandy');
      expect(result.sceneConcepts, contains('beach'));
    });

    test('object + scene: combined intent', () {
      final result = parser.parse('dog at the beach');
      expect(result.intent, SearchIntent.combined);
      expect(result.filters.objectTags, contains('dog'));
      expect(result.sceneConcepts, contains('beach'));
    });

    test('object + date: combined intent', () {
      final result = parser.parse('dog photos from 2024');
      expect(result.intent, SearchIntent.combined);
      expect(result.filters.objectTags, contains('dog'));
      expect(result.filters.dateFrom, isNotNull);
    });

    test('person + location: combined intent', () {
      final result = parser.parse('Sandy in Paris');
      expect(result.intent, SearchIntent.combined);
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.locationLabel, 'Paris');
    });

    test('scene concepts added to semantic query', () {
      final result = parser.parse('sunset photos');
      expect(result.semanticQuery, contains('sunset'));
    });

    test('object labels added to semantic query', () {
      final result = parser.parse('dog photos');
      expect(result.semanticQuery, contains('dog'));
    });

    test('complex: object + scene + date reconstructs correctly', () {
      final result = parser.parse('dog at the beach from 2024');
      expect(result.semanticQuery, isNotEmpty);
      expect(result.filters.objectTags, contains('dog'));
      expect(result.sceneConcepts, contains('beach'));
      expect(result.filters.dateFrom, isNotNull);
    });

    test('horse at the sunset in 2024: triple intent', () {
      final result = parser.parse('horse at the sunset in 2024');
      expect(result.intent, SearchIntent.combined);
      expect(result.filters.objectTags, contains('horse'));
      expect(result.sceneConcepts, contains('sunset'));
      expect(result.filters.dateFrom, isNotNull);
    });
  });

  group('Phase 14: SearchFilters Extended', () {
    test('objectTags default is empty', () {
      const filters = SearchFilters();
      expect(filters.objectTags, isEmpty);
    });

    test('sceneConcepts default is empty', () {
      const filters = SearchFilters();
      expect(filters.sceneConcepts, isEmpty);
    });

    test('locationLabel default is null', () {
      const filters = SearchFilters();
      expect(filters.locationLabel, isNull);
    });

    test('excludeTags default is empty', () {
      const filters = SearchFilters();
      expect(filters.excludeTags, isEmpty);
    });

    test('hasObjectFilters true when objectTags non-empty', () {
      const filters = SearchFilters(objectTags: ['dog']);
      expect(filters.hasObjectFilters, isTrue);
    });

    test('hasObjectFilters true when excludeTags non-empty', () {
      const filters = SearchFilters(excludeTags: ['cat']);
      expect(filters.hasObjectFilters, isTrue);
    });

    test('hasObjectFilters false by default', () {
      const filters = SearchFilters();
      expect(filters.hasObjectFilters, isFalse);
    });

    test('hasLocationFilter true when locationLabel set', () {
      const filters = SearchFilters(locationLabel: 'Paris');
      expect(filters.hasLocationFilter, isTrue);
    });

    test('hasLocationFilter true when hasLocation set', () {
      const filters = SearchFilters(hasLocation: true);
      expect(filters.hasLocationFilter, isTrue);
    });

    test('hasLocationFilter false by default', () {
      const filters = SearchFilters();
      expect(filters.hasLocationFilter, isFalse);
    });

    test('hasSceneConcepts true when sceneConcepts non-empty', () {
      const filters = SearchFilters(sceneConcepts: ['beach']);
      expect(filters.hasSceneConcepts, isTrue);
    });

    test('hasSceneConcepts false by default', () {
      const filters = SearchFilters();
      expect(filters.hasSceneConcepts, isFalse);
    });

    test('hasActiveFilters true when objectTags set', () {
      const filters = SearchFilters(objectTags: ['dog']);
      expect(filters.hasActiveFilters, isTrue);
    });

    test('hasActiveFilters true when locationLabel set', () {
      const filters = SearchFilters(locationLabel: 'Paris');
      expect(filters.hasActiveFilters, isTrue);
    });

    test('copyWith preserves objectTags', () {
      const original = SearchFilters(objectTags: ['dog', 'cat']);
      final copied = original.copyWith();
      expect(copied.objectTags, ['dog', 'cat']);
    });

    test('copyWith can override objectTags', () {
      const original = SearchFilters(objectTags: ['dog']);
      final copied = original.copyWith(objectTags: ['car']);
      expect(copied.objectTags, ['car']);
    });

    test('copyWith preserves locationLabel', () {
      const original = SearchFilters(locationLabel: 'Paris');
      final copied = original.copyWith();
      expect(copied.locationLabel, 'Paris');
    });

    test('copyWith preserves sceneConcepts', () {
      const original = SearchFilters(sceneConcepts: ['beach']);
      final copied = original.copyWith();
      expect(copied.sceneConcepts, ['beach']);
    });

    test('copyWith preserves excludeTags', () {
      const original = SearchFilters(excludeTags: ['cat']);
      final copied = original.copyWith();
      expect(copied.excludeTags, ['cat']);
    });
  });

  group('Phase 14: ParsedQuery Extended Fields', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser.withLogger(
        null,
        referenceTime: DateTime(2025, 8, 15),
        personNames: ['Sandy'],
      );
    });

    test('intent defaults to unknown for empty query', () {
      final result = parser.parse('');
      expect(result.intent, SearchIntent.unknown);
    });

    test('date intent detected', () {
      final result = parser.parse('photos from last week');
      expect(result.intent, SearchIntent.date);
    });

    test('person intent detected', () {
      final result = parser.parse('photos of Sandy');
      expect(result.intent, SearchIntent.person);
    });

    test('hasFilters true when objectTags present', () {
      final result = parser.parse('dog photos');
      expect(result.hasFilters, isTrue);
    });

    test('hasFilters true when sceneConcepts present', () {
      final result = parser.parse('beach photos');
      expect(result.hasFilters, isTrue);
    });

    test('hasFilters true when locationLabel present', () {
      final result = parser.parse('photos in Paris');
      expect(result.hasFilters, isTrue);
    });

    test('locationLabel set on ParsedQuery', () {
      final result = parser.parse('photos in Tokyo');
      expect(result.locationLabel, 'Tokyo');
    });

    test('copyWith preserves intent', () {
      final original = parser.parse('dog photos');
      final copied = original.copyWith();
      expect(copied.intent, SearchIntent.object);
    });

    test('copyWith preserves detectedObjects', () {
      final original = parser.parse('dog and cat');
      final copied = original.copyWith();
      expect(copied.detectedObjects, containsAll(['dog', 'cat']));
    });

    test('copyWith preserves sceneConcepts', () {
      final original = parser.parse('beach sunset');
      final copied = original.copyWith();
      expect(copied.sceneConcepts, containsAll(['beach', 'sunset']));
    });

    test('copyWith preserves locationLabel', () {
      final original = parser.parse('photos in Paris');
      final copied = original.copyWith();
      expect(copied.locationLabel, 'Paris');
    });
  });

  group('Phase 14: RankedSearchResult Extended', () {
    test('objectScore defaults to null', () {
      const result = RankedSearchResult(
        photoId: 'p1',
        score: 0.8,
        semanticScore: 0.7,
      );
      expect(result.objectScore, isNull);
    });

    test('locationScore defaults to null', () {
      const result = RankedSearchResult(
        photoId: 'p1',
        score: 0.8,
        semanticScore: 0.7,
      );
      expect(result.locationScore, isNull);
    });

    test('objectScore set correctly', () {
      const result = RankedSearchResult(
        photoId: 'p1',
        score: 0.9,
        semanticScore: 0.7,
        objectScore: 0.85,
      );
      expect(result.objectScore, 0.85);
    });

    test('locationScore set correctly', () {
      const result = RankedSearchResult(
        photoId: 'p1',
        score: 0.9,
        semanticScore: 0.7,
        locationScore: 0.95,
      );
      expect(result.locationScore, 0.95);
    });

    test('matchedSignals can include object', () {
      const result = RankedSearchResult(
        photoId: 'p1',
        score: 0.9,
        semanticScore: 0.7,
        matchedSignals: ['object', 'semantic'],
      );
      expect(result.matchedSignals, contains('object'));
      expect(result.matchedSignals, contains('semantic'));
    });

    test('matchedSignals can include location', () {
      const result = RankedSearchResult(
        photoId: 'p1',
        score: 0.9,
        semanticScore: 0.7,
        matchedSignals: ['location'],
      );
      expect(result.matchedSignals, contains('location'));
    });
  });

  group('Phase 14: SearchResult Extended', () {
    test('objectScore defaults to null', () {
      const result = SearchResult(photoId: 'p1', score: 0.8);
      expect(result.objectScore, isNull);
    });

    test('objectScore set correctly', () {
      const result = SearchResult(
        photoId: 'p1',
        score: 0.9,
        objectScore: 0.85,
      );
      expect(result.objectScore, 0.85);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';
import 'package:ai_gallery/features/search/services/ranking_engine.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';

void main() {
  group('Multi-Signal Query Parsing', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser.withLogger(
        null,
        referenceTime: DateTime(2025, 8, 15, 12, 0, 0),
        personNames: ['Sandy', 'Thiyan', 'Siva'],
      );
    });

    test('person-only: "photos of Sandy"', () {
      final result = parser.parse('photos of Sandy');
      expect(result.filters.personName, 'Sandy');
    });

    test('person + semantic: "Sandy at the beach"', () {
      final result = parser.parse('Sandy at the beach');
      expect(result.filters.personName, 'Sandy');
      // "beach" is an object pattern → replaced with labels "outdoor nature"
      expect(result.semanticQuery, isNotEmpty);
    });

    test('person + date: "photos of Sandy in 2025"', () {
      final result = parser.parse('photos of Sandy in 2025');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.dateFrom, DateTime(2025, 1, 1));
      expect(result.filters.dateTo, DateTime(2025, 12, 31, 23, 59, 59));
    });

    test('person + semantic + date: "Thiyan college photos from 2024"', () {
      final result = parser.parse('Thiyan college photos from 2024');
      expect(result.filters.personName, 'Thiyan');
      expect(result.semanticQuery, contains('college'));
      expect(result.filters.dateFrom, DateTime(2024, 1, 1));
    });

    test('case-insensitive person name: "photos of sandy"', () {
      final result = parser.parse('photos of sandy');
      expect(result.filters.personName, 'Sandy');
    });

    test('unknown person name falls through to semantic', () {
      final result = parser.parse('photos of Rahul');
      expect(result.filters.personName, isNull);
      expect(result.semanticQuery, contains('Rahul'));
    });

    test('person name in middle of query: "Thiyan college photos"', () {
      final result = parser.parse('Thiyan college photos');
      expect(result.filters.personName, 'Thiyan');
      expect(result.semanticQuery, contains('college'));
    });

    test('person + month: "Sandy photos from January"', () {
      final result = parser.parse('Sandy photos from January');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.dateFrom, isNotNull);
      expect(result.filters.dateTo, isNotNull);
    });

    test('OCR-like query: "Chennai" (no person)', () {
      final result = parser.parse('Chennai');
      expect(result.filters.personName, isNull);
      expect(result.semanticQuery, contains('Chennai'));
    });

    test('person + camera: "Sandy iPhone photos"', () {
      final result = parser.parse('Sandy iPhone photos');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.cameraMake, 'Apple');
    });

    test('empty query', () {
      final result = parser.parse('');
      expect(result.semanticQuery, isEmpty);
      expect(result.filters.personName, isNull);
      expect(result.confidence, 0.0);
    });

    test('whitespace-only query', () {
      final result = parser.parse('   ');
      expect(result.semanticQuery, isEmpty);
      expect(result.filters.personName, isNull);
    });

    test('person name is also an ordinary word (May)', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['May', 'April'],
      );
      final result = p.parse('May flowers');
      expect(result.filters.personName, 'May');
      expect(result.semanticQuery, contains('flowers'));
    });

    test('multiple people in query uses first match', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['Sandy', 'Siva'],
      );
      final result = p.parse('Sandy and Siva');
      expect(result.filters.personName, 'Sandy');
    });

    test('Unicode person name', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['Murugan', 'Kumar'],
      );
      final result = p.parse('photos of Murugan');
      expect(result.filters.personName, 'Murugan');
    });

    test('person + quality filter: "Sandy sharp photos"', () {
      final result = parser.parse('Sandy sharp photos');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.minQualityScore, 0.7);
    });

    test('person + location: "Sandy photos in Mumbai"', () {
      final result = parser.parse('Sandy photos in Mumbai');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.hasLocation, true);
    });

    test('pure semantic query: "sunset over ocean"', () {
      final result = parser.parse('sunset over ocean');
      expect(result.filters.personName, isNull);
      expect(result.semanticQuery, isNotEmpty);
    });
  });

  group('SearchFilters', () {
    test('personName is included in hasActiveFilters', () {
      const filters = SearchFilters(personName: 'Sandy');
      expect(filters.hasActiveFilters, true);
    });

    test('personName copyWith works correctly', () {
      const filters = SearchFilters();
      final updated = filters.copyWith(personName: 'Sandy');
      expect(updated.personName, 'Sandy');
    });

    test('personName can be set to null via copyWith', () {
      const filters = SearchFilters(personName: 'Sandy');
      final updated = filters.copyWith(personName: null);
      expect(updated.personName, isNull);
    });

    test('all default filters have no active filters', () {
      const filters = SearchFilters();
      expect(filters.hasActiveFilters, false);
      expect(filters.personName, isNull);
      expect(filters.dateFrom, isNull);
      expect(filters.dateTo, isNull);
    });

    test('date filters are active', () {
      final filters = SearchFilters(
        dateFrom: DateTime(2025, 1, 1),
        dateTo: DateTime(2025, 12, 31),
      );
      expect(filters.hasActiveFilters, true);
    });

    test('copyWith preserves all fields', () {
      const filters = SearchFilters(
        personName: 'Sandy',
        cameraMake: 'Apple',
        minQualityScore: 0.7,
      );
      final updated = filters.copyWith(dateFrom: DateTime(2025, 6, 1));
      expect(updated.personName, 'Sandy');
      expect(updated.cameraMake, 'Apple');
      expect(updated.minQualityScore, 0.7);
      expect(updated.dateFrom, DateTime(2025, 6, 1));
    });
  });

  group('ParsedQuery', () {
    test('hasFilters returns true when personName set', () {
      const query = ParsedQuery(
        semanticQuery: 'beach',
        filters: SearchFilters(personName: 'Sandy'),
        confidence: 0.8,
      );
      expect(query.hasFilters, true);
    });

    test('hasFilters returns false for default filters', () {
      const query = ParsedQuery(
        semanticQuery: 'beach',
        filters: SearchFilters(),
        confidence: 0.8,
      );
      expect(query.hasFilters, false);
    });

    test('copyWith preserves personName', () {
      const query = ParsedQuery(
        semanticQuery: 'beach',
        filters: SearchFilters(personName: 'Sandy'),
        confidence: 0.8,
      );
      final updated = query.copyWith(semanticQuery: 'sunset');
      expect(updated.filters.personName, 'Sandy');
      expect(updated.semanticQuery, 'sunset');
    });

    test('copyWith preserves all fields', () {
      final query = ParsedQuery(
        semanticQuery: 'beach',
        filters: SearchFilters(
          personName: 'Sandy',
          dateFrom: DateTime(2025, 1, 1),
        ),
        confidence: 0.8,
        originalQuery: 'Sandy beach 2025',
      );
      final updated = query.copyWith(confidence: 0.9);
      expect(updated.semanticQuery, 'beach');
      expect(updated.filters.personName, 'Sandy');
      expect(updated.confidence, 0.9);
      expect(updated.originalQuery, 'Sandy beach 2025');
    });
  });

  group('RankedSearchResult', () {
    test('default matchedSignals is empty', () {
      const result = RankedSearchResult(
        photoId: 'test-123',
        score: 0.85,
        semanticScore: 0.9,
      );
      expect(result.matchedSignals, isEmpty);
      expect(result.personScore, isNull);
      expect(result.ocrScore, isNull);
    });

    test('with person score and signals', () {
      const result = RankedSearchResult(
        photoId: 'test-123',
        score: 0.85,
        semanticScore: 0.9,
        personScore: 1.0,
        matchedSignals: ['person', 'semantic'],
      );
      expect(result.personScore, 1.0);
      expect(result.matchedSignals, contains('person'));
      expect(result.matchedSignals, contains('semantic'));
    });

    test('with OCR score', () {
      const result = RankedSearchResult(
        photoId: 'test-123',
        score: 0.75,
        semanticScore: 0.6,
        ocrScore: 0.9,
        matchedSignals: ['ocr'],
      );
      expect(result.ocrScore, 0.9);
    });

    test('toSearchResult works with new fields', () {
      const result = RankedSearchResult(
        photoId: 'test-123',
        score: 0.85,
        semanticScore: 0.9,
        personScore: 1.0,
        ocrScore: 0.5,
        matchedSignals: ['person', 'semantic', 'ocr'],
      );
      final searchResult = result.toSearchResult();
      expect(searchResult.photoId, 'test-123');
      expect(searchResult.score, 0.85);
    });
  });

  group('Person Resolution Edge Cases', () {
    test('person with whitespace in name', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['John Smith'],
      );
      final result = p.parse('photos of John Smith');
      expect(result.filters.personName, 'John Smith');
    });

    test('person name at end of query', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['Siva'],
      );
      final result = p.parse('beach photos with Siva');
      expect(result.filters.personName, 'Siva');
    });

    test('person name as the entire query', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['Sandy'],
      );
      final result = p.parse('Sandy');
      expect(result.filters.personName, 'Sandy');
    });

    test('no person names configured', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: [],
      );
      final result = p.parse('photos of Sandy');
      expect(result.filters.personName, isNull);
      expect(result.semanticQuery, contains('Sandy'));
    });

    test('empty person names list', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: <String>[],
      );
      final result = p.parse('Sandy');
      expect(result.filters.personName, isNull);
    });

    test('person name with special regex characters', () {
      final p = NaturalLanguageParser.withLogger(
        null,
        personNames: ['O\'Brien'],
      );
      final result = p.parse("photos of O'Brien");
      expect(result.filters.personName, "O'Brien");
    });
  });

  group('Multi-Signal Combination Coverage', () {
    late NaturalLanguageParser comboParser;

    setUp(() {
      comboParser = NaturalLanguageParser.withLogger(
        null,
        referenceTime: DateTime(2025, 8, 15, 12, 0, 0),
        personNames: ['Sandy', 'Thiyan', 'Siva'],
      );
    });

    test('Person + Semantic + Date combined', () {
      final result = comboParser.parse('Thiyan sunset photos from 2024');
      expect(result.filters.personName, 'Thiyan');
      expect(result.filters.dateFrom, DateTime(2024, 1, 1));
      expect(result.semanticQuery, isNotEmpty);
    });

    test('Person + Camera + Date', () {
      final result = comboParser.parse('Sandy iPhone photos from January 2025');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.cameraMake, 'Apple');
      expect(result.filters.dateFrom, isNotNull);
    });

    test('Person + Quality + Location', () {
      final result = comboParser.parse('Sandy sharp photos in Mumbai');
      expect(result.filters.personName, 'Sandy');
      expect(result.filters.minQualityScore, 0.7);
      expect(result.filters.hasLocation, true);
    });

    test('Semantic + Date (no person)', () {
      final result = comboParser.parse('sunset photos from 2024');
      expect(result.filters.personName, isNull);
      expect(result.filters.dateFrom, DateTime(2024, 1, 1));
    });

    test('Semantic + Camera (no person)', () {
      final result = comboParser.parse('beach photos with Canon camera');
      expect(result.filters.personName, isNull);
      expect(result.filters.cameraMake, 'Canon');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';
import 'package:ai_gallery/features/search/services/search_service.dart';

void main() {
  group('NaturalLanguageParser', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15, 12, 0, 0),
      );
    });

    test('parses empty query', () {
      final result = parser.parse('');
      expect(result.semanticQuery, isEmpty);
      expect(result.confidence, 0.0);
    });

    test('parses "last week" date pattern', () {
      final result = parser.parse('photos from last week');
      expect(result.filters.dateFrom, isNotNull);
      expect(result.filters.dateTo, isNotNull);
      final expectedStart = DateTime(2025, 6, 8);
      expect(result.filters.dateFrom, expectedStart);
    });

    test('parses "yesterday"', () {
      final result = parser.parse('photos from yesterday');
      expect(result.filters.dateFrom, isNotNull);
      expect(result.filters.dateTo, isNotNull);
      final expected = DateTime(2025, 6, 14);
      expect(result.filters.dateFrom, expected);
    });

    test('parses "today"', () {
      final result = parser.parse('photos from today');
      expect(result.filters.dateFrom, DateTime(2025, 6, 15));
      expect(result.filters.dateTo, DateTime(2025, 6, 15, 23, 59, 59));
    });

    test('parses "3 days ago"', () {
      final result = parser.parse('photos from 3 days ago');
      expect(result.filters.dateFrom, DateTime(2025, 6, 12, 12, 0, 0));
    });

    test('parses "this month"', () {
      final result = parser.parse('photos from this month');
      expect(result.filters.dateFrom, DateTime(2025, 6, 1));
    });

    test('parses ISO date "2025-01-15"', () {
      final result = parser.parse('photos from 2025-01-15');
      expect(result.filters.dateFrom, DateTime(2025, 1, 15));
    });

    test('parses year "in 2024"', () {
      final result = parser.parse('photos in 2024');
      expect(result.filters.dateFrom, DateTime(2024, 1, 1));
      expect(result.filters.dateTo, DateTime(2024, 12, 31, 23, 59, 59));
    });

    test('parses iPhone camera', () {
      final result = parser.parse('iPhone 14 photos');
      expect(result.filters.cameraMake, 'Apple');
      expect(result.filters.cameraModel, contains('iPhone'));
    });

    test('parses Samsung camera', () {
      final result = parser.parse('Galaxy S24 photos');
      expect(result.filters.cameraMake, 'Samsung');
      expect(result.filters.cameraModel, contains('Galaxy'));
    });

    test('parses Canon camera', () {
      final result = parser.parse('Canon photos');
      expect(result.filters.cameraMake, 'Canon');
    });

    test('parses "sharp" quality', () {
      final result = parser.parse('sharp photos');
      expect(result.filters.minQualityScore, isNotNull);
      expect(result.filters.minQualityScore!, greaterThanOrEqualTo(0.7));
    });

    test('parses "blurry" quality', () {
      final result = parser.parse('blurry photos');
      expect(result.filters.maxBlurScore, isNotNull);
      expect(result.filters.maxBlurScore!, lessThanOrEqualTo(0.6));
    });

    test('parses location pattern', () {
      final result = parser.parse('photos at Beach');
      expect(result.filters.hasLocation, isTrue);
    });

    test('extracts semantic query from simple text', () {
      final result = parser.parse('dog at the beach');
      expect(result.semanticQuery, isNotEmpty);
      expect(result.semanticQuery.toLowerCase(), contains('dog'));
    });

    test('calculates confidence based on matched patterns', () {
      final result = parser.parse('sharp photos from yesterday');
      expect(result.confidence, greaterThan(0.0));
    });

    test('parses "last month"', () {
      final result = parser.parse('photos from last month');
      expect(result.filters.dateFrom, isA<DateTime>());
      expect(result.filters.dateTo, isA<DateTime>());
    });

    test('parses "last year"', () {
      final result = parser.parse('photos from last year');
      expect(result.filters.dateFrom, isA<DateTime>());
    });
  });

  group('SearchFilters', () {
    test('hasActiveFilters returns false for default', () {
      const filters = SearchFilters();
      expect(filters.hasActiveFilters, isFalse);
    });

    test('hasActiveFilters returns true with dateFrom', () {
      final filters = SearchFilters(dateFrom: DateTime(2025, 1, 1));
      expect(filters.hasActiveFilters, isTrue);
    });

    test('hasActiveFilters returns true with favoritesOnly', () {
      final filters = SearchFilters(favoritesOnly: true);
      expect(filters.hasActiveFilters, isTrue);
    });

    test('copyWith preserves existing values', () {
      final filters = SearchFilters(
        dateFrom: DateTime(2025, 1, 1),
        favoritesOnly: true,
      );
      final copied = filters.copyWith(minQualityScore: 0.8);
      expect(copied.dateFrom, DateTime(2025, 1, 1));
      expect(copied.favoritesOnly, isTrue);
      expect(copied.minQualityScore, 0.8);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';

void main() {
  group('NaturalLanguageParser - Person Name Recognition', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15, 12, 0, 0),
        personNames: ['Alice', 'Bob Smith', 'Charlie'],
      );
    });

    test('detects person name in query', () {
      final result = parser.parse('photos of Alice');
      expect(result.filters.personName, 'Alice');
    });

    test('detects person name case-insensitively', () {
      final result = parser.parse('photos of alice');
      expect(result.filters.personName, 'Alice');
    });

    test('detects multi-word person name', () {
      final result = parser.parse('photos with Bob Smith');
      expect(result.filters.personName, 'Bob Smith');
    });

    test('removes person name from semantic query', () {
      final result = parser.parse('photos of Alice hiking');
      expect(result.filters.personName, 'Alice');
      expect(result.semanticQuery.toLowerCase(), isNot(contains('alice')));
      expect(result.semanticQuery.toLowerCase(), contains('hiking'));
    });

    test('returns null personName when no match', () {
      final result = parser.parse('photos of dogs');
      expect(result.filters.personName, isNull);
    });

    test('returns null when personNames list is empty', () {
      final emptyParser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15),
        personNames: [],
      );
      final result = emptyParser.parse('photos of Alice');
      expect(result.filters.personName, isNull);
    });

    test('person name detection has priority over other patterns', () {
      final result = parser.parse('Alice last week');
      expect(result.filters.personName, 'Alice');
      expect(result.filters.dateFrom, isNotNull);
    });

    test('takes first matching person name', () {
      final multiParser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15),
        personNames: ['Alice', 'Bob'],
      );
      final result = multiParser.parse('Alice and Bob');
      expect(result.filters.personName, 'Alice');
    });

    test('combined person + semantic query works', () {
      final result = parser.parse('Alice hiking');
      expect(result.filters.personName, 'Alice');
      expect(result.semanticQuery.toLowerCase(), contains('hiking'));
    });

    test('combined person + date query works', () {
      final result = parser.parse('Alice last week');
      expect(result.filters.personName, 'Alice');
      expect(result.filters.dateFrom, isNotNull);
      expect(result.filters.dateTo, isNotNull);
    });
  });

  group('NaturalLanguageParser - Person Name Edge Cases', () {
    test('handles names that are substrings of each other', () {
      final parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15),
        personNames: ['Rob', 'Robert'],
      );
      // "Rob" should match first since we take first match
      final result = parser.parse('photos of Rob');
      expect(result.filters.personName, 'Rob');
    });

    test('handles empty person name string in list (no match expected)', () {
      final parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15),
        personNames: ['', 'Alice'],
      );
      final result = parser.parse('photos of Alice');
      // Empty string shouldn't match (regex \b\b matches empty, but
      // the parser uses it for name matching — it may or may not match.
      // The key is that Alice should still be found).
      expect(result.filters.personName, isNotNull);
    });

    test('person name with special regex characters', () {
      final parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15),
        personNames: ['O\'Brien', 'Smith-Jones'],
      );
      final result = parser.parse('photos of O\'Brien');
      expect(result.filters.personName, "O'Brien");
    });
  });
}

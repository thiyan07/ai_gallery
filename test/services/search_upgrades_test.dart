import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/domain/models/embedding.dart';
import 'package:ai_gallery/features/search/services/natural_language_parser.dart';
import 'package:ai_gallery/features/search/services/ranking_engine.dart';
import 'package:ai_gallery/features/search/widgets/search_result_tile.dart';

void main() {
  group('Precise object labels', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15, 12, 0, 0),
      );
    });

    test('"dog" maps to exactly [dog], not all animals', () {
      final result = parser.parse('dog photos');
      expect(result.filters.objectTags, ['dog']);
    });

    test('synonyms resolve: puppy -> dog, sofa -> couch, bike -> bicycle', () {
      expect(parser.parse('puppy').filters.objectTags, ['dog']);
      expect(parser.parse('my sofa').filters.objectTags, ['couch']);
      expect(parser.parse('red bike').filters.objectTags, ['bicycle']);
    });

    test('plurals resolve: kittens -> cat, cars -> car', () {
      expect(parser.parse('kittens').filters.objectTags, ['cat']);
      expect(parser.parse('cars').filters.objectTags, ['car']);
    });

    test('people terms map to person label', () {
      expect(parser.parse('photos of kids').filters.objectTags, ['person']);
    });

    test('multiple distinct objects each map precisely', () {
      final result = parser.parse('dog and cat');
      expect(result.filters.objectTags.toSet(), {'dog', 'cat'});
    });
  });

  group('Exclusions', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15, 12, 0, 0),
      );
    });

    test('"beach without people" excludes person, keeps beach semantic', () {
      final result = parser.parse('beach without people');
      expect(result.filters.excludeTags, ['person']);
      expect(result.filters.objectTags, isEmpty);
      expect(result.semanticQuery.toLowerCase(), contains('beach'));
      expect(result.semanticQuery.toLowerCase(), isNot(contains('people')));
      expect(result.hasFilters, isTrue);
    });

    test('"dog except cat" includes dog, excludes cat', () {
      final result = parser.parse('dog except cat');
      expect(result.filters.objectTags, ['dog']);
      expect(result.filters.excludeTags, ['cat']);
    });

    test('"car minus truck" excludes truck', () {
      final result = parser.parse('car minus truck');
      expect(result.filters.objectTags, ['car']);
      expect(result.filters.excludeTags, ['truck']);
    });
  });

  group('Quality negation', () {
    late NaturalLanguageParser parser;

    setUp(() {
      parser = NaturalLanguageParser(
        referenceTime: DateTime(2025, 6, 15, 12, 0, 0),
      );
    });

    test('"not blurry" means sharp', () {
      final result = parser.parse('not blurry photos');
      expect(result.filters.minQualityScore, 0.7);
      expect(result.filters.maxBlurScore, 0.3);
    });

    test('"not sharp" means blurry-ish', () {
      final result = parser.parse('not sharp photos');
      expect(result.filters.maxBlurScore, 0.6);
    });
  });

  group('Region embedding records', () {
    test('EmbeddingRecord round-trips region fields', () {
      final record = EmbeddingRecord(
        id: 'p1_region_0',
        photoId: 'p1',
        vector: Float32List.fromList([0.1, 0.2, 0.3]),
        modelId: 'test-model',
        dimensions: 3,
        regionLabel: 'dog',
        regionBboxLeft: 0.1,
        regionBboxTop: 0.2,
        regionBboxWidth: 0.3,
        regionBboxHeight: 0.4,
      );
      expect(record.isRegion, isTrue);
      final restored = EmbeddingRecord.fromMap(record.toMap());
      expect(restored.regionLabel, 'dog');
      expect(restored.regionBboxWidth, 0.3);
      expect(restored.vector.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(restored.vector[i], closeTo(record.vector[i], 1e-6));
      }
    });

    test('global record has no region', () {
      final record = EmbeddingRecord(
        id: 'p1',
        photoId: 'p1',
        vector: Float32List.fromList([0.5]),
        modelId: 'test-model',
        dimensions: 1,
      );
      expect(record.isRegion, isFalse);
      final restored = EmbeddingRecord.fromMap(record.toMap());
      expect(restored.regionLabel, isNull);
    });
  });

  group('Result signal labels', () {
    RankedSearchResult makeResult(List<String> signals) {
      return RankedSearchResult(
        photoId: 'p1',
        score: 0.9,
        semanticScore: 0.9,
        matchedSignals: signals,
      );
    }

    test('region signal shows label', () {
      expect(resultSignalLabel(makeResult(['region:dog'])), 'Region · dog');
    });

    test('standard signals map to words', () {
      expect(resultSignalLabel(makeResult(['object'])), 'Object');
      expect(resultSignalLabel(makeResult(['person'])), 'Person');
      expect(resultSignalLabel(makeResult(['ocr'])), 'Text');
      expect(resultSignalLabel(makeResult(['semantic'])), 'Match');
    });

    test('empty signals give null', () {
      expect(resultSignalLabel(makeResult([])), isNull);
    });
  });
}

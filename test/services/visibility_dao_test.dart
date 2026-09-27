import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/visibility_dao.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:ai_gallery/features/gallery/services/visibility_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisibilityDao', () {
    late AppDatabase database;
    late VisibilityDao dao;
    late Directory tempDir;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      tempDir = await Directory.systemTemp.createTemp('ai_gallery_vis.');
      final dbPath = p.join(tempDir.path, 'test_visibility.db');
      database = await AppDatabase.openForIsolate(
        databasePath: dbPath,
        logger: const ConsoleAppLogger(),
      );
      dao = database.visibility;
    });

    tearDown(() async {
      await AppDatabase.closeForTesting();
      await tempDir.delete(recursive: true);
    });

    test('set/clear modes and idsInMode', () async {
      await dao.setMode('a', VisibilityMode.archived);
      await dao.setMode('b', VisibilityMode.hidden);
      expect(await dao.modeOf('a'), VisibilityMode.archived);
      expect(await dao.idsInMode(VisibilityMode.archived), {'a'});
      expect(await dao.idsInMode(VisibilityMode.hidden), {'b'});

      // Replacing mode works.
      await dao.setMode('a', VisibilityMode.hidden);
      expect(await dao.modeOf('a'), VisibilityMode.hidden);
      expect(await dao.idsInMode(VisibilityMode.archived), isEmpty);

      await dao.clearMode('a');
      expect(await dao.modeOf('a'), isNull);
    });
  });

  group('Hidden PIN validation', () {
    test('accepts 4+ digits only', () {
      expect(VisibilityService.isValidPin('1234'), isTrue);
      expect(VisibilityService.isValidPin('12345678'), isTrue);
      expect(VisibilityService.isValidPin('123'), isFalse);
      expect(VisibilityService.isValidPin('abcd'), isFalse);
      expect(VisibilityService.isValidPin('12a4'), isFalse);
      expect(VisibilityService.isValidPin(''), isFalse);
    });
  });
}

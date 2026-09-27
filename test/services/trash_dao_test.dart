import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/database/app_database.dart';
import 'package:ai_gallery/core/database/daos/trash_dao.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrashDao', () {
    late AppDatabase database;
    late TrashDao trashDao;
    late Directory tempDir;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      tempDir = await Directory.systemTemp.createTemp('ai_gallery_trash.');
      final dbPath = p.join(tempDir.path, 'test_trash.db');
      database = await AppDatabase.openForIsolate(
        databasePath: dbPath,
        logger: const ConsoleAppLogger(),
      );
      trashDao = database.trash;
    });

    tearDown(() async {
      await AppDatabase.closeForTesting();
      await tempDir.delete(recursive: true);
    });

    test('moveToTrash hides and restore brings back', () async {
      await trashDao.moveToTrash(['a', 'b']);
      expect(await trashDao.trashedIds(), {'a', 'b'});
      expect(await trashDao.isTrashed('a'), isTrue);

      await trashDao.restore(['a']);
      expect(await trashDao.trashedIds(), {'b'});
      expect(await trashDao.isTrashed('a'), isFalse);
    });

    test('purgeExpired removes only items past retention', () async {
      await trashDao.moveToTrash(['fresh']);
      // Backdate one row beyond the 30-day retention.
      final old = DateTime.now()
          .subtract(const Duration(days: 31))
          .toIso8601String();
      await database.database.insert(
        TrashDao.tableName,
        {'asset_id': 'stale', 'deleted_at': old},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final purged = await trashDao.purgeExpired();
      expect(purged, ['stale']);
      expect(await trashDao.trashedIds(), {'fresh'});
    });

    test('entries report days left', () async {
      await trashDao.moveToTrash(['a']);
      final entries = await trashDao.entries();
      expect(entries, hasLength(1));
      expect(entries.first.assetId, 'a');
      expect(entries.first.daysLeft(), inInclusiveRange(29, 30));
    });
  });
}

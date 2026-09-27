import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../domain/models/edit/edit_recipe.dart';

/// Set of all photo IDs that have edit recipes in the database.
///
/// Used by gallery grid to show edit badges on thumbnails.
final editedPhotoIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return db.editRecipes.getAllEditedPhotoIds();
});

/// Stream that periodically polls for edited photo IDs.
///
/// Refreshes every 5 seconds so the gallery grid updates after saving edits
/// without requiring a manual pull-to-refresh.
final editedPhotoIdsStreamProvider =
    StreamProvider.autoDispose<Set<String>>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);

  // Initial load
  yield await db.editRecipes.getAllEditedPhotoIds();

  // Poll every 5 seconds
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 5))) {
    yield await db.editRecipes.getAllEditedPhotoIds();
  }
});

/// Edit info for a single photo (used by photo viewer).
///
/// Returns a map with: hasEdits, summary, exportedPath.
/// Returns null if no recipe exists for the photo.
final photoEditInfoProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, photoId) async {
    final db = await ref.watch(appDatabaseProvider.future);
    final recipe = await db.editRecipes.getByPhotoId(photoId);
    if (recipe == null) return null;
    return {
      'hasEdits': recipe.isNotEmpty,
      'summary': recipe.summary,
      'exportedPath': recipe.exportedPath,
      'isExported': recipe.isExported,
    };
  },
);

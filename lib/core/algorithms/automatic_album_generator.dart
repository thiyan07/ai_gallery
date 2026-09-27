import 'dart:math' as math;

import '../../domain/models/memory/automatic_album.dart';
import '../../domain/models/memory/memory.dart';

/// Generates virtual automatic albums from memories and photo metadata.
///
/// Automatic albums are virtual groupings that don't create duplicate photo
/// copies — they reference existing photo IDs and are generated on-the-fly.
class AutomaticAlbumGenerator {
  /// Maximum photos per automatic album.
  static const maxPhotosPerAlbum = 100;

  /// Generates automatic albums from a list of memories.
  static List<AutomaticAlbum> generate({
    required List<Memory> memories,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final albums = <AutomaticAlbum>[];

    // Generate "Best of Year" albums
    albums.addAll(_generateBestOfYear(memories, now));

    // Generate "Monthly Highlights" albums
    albums.addAll(_generateMonthlyHighlights(memories, now));

    // Generate trip albums
    albums.addAll(_generateTripAlbums(memories));

    // Generate people albums
    albums.addAll(_generatePeopleAlbums(memories));

    // Generate seasonal albums
    albums.addAll(_generateSeasonalAlbums(memories, now));

    return albums;
  }

  static List<AutomaticAlbum> _generateBestOfYear(List<Memory> memories, DateTime now) {
    final albums = <AutomaticAlbum>[];
    final yearGroups = <int, List<Memory>>{};

    for (final memory in memories) {
      if (!memory.isActive) continue;
      final year = memory.startDate.year;
      yearGroups.putIfAbsent(year, () => []).add(memory);
    }

    for (final entry in yearGroups.entries) {
      if (entry.key == now.year) continue; // Don't generate for current year yet

      final yearMemories = entry.value
        ..sort((a, b) => b.score.compareTo(a.score));

      final topPhotos = yearMemories
          .expand((m) => m.photoIds)
          .take(maxPhotosPerAlbum)
          .toList();

      if (topPhotos.length < 10) continue;

      albums.add(AutomaticAlbum(
        albumId: 'auto_best_${entry.key}',
        title: 'Best of ${entry.key}',
        type: AutomaticAlbumType.bestOfYear,
        photoIds: topPhotos,
        coverPhotoId: topPhotos.first,
        startDate: DateTime(entry.key, 1, 1),
        endDate: DateTime(entry.key, 12, 31),
        score: yearMemories.map((m) => m.score).reduce(math.max),
        createdAt: now,
        updatedAt: now,
        year: entry.key,
      ));
    }

    return albums;
  }

  static List<AutomaticAlbum> _generateMonthlyHighlights(List<Memory> memories, DateTime now) {
    final albums = <AutomaticAlbum>[];
    final monthGroups = <String, List<Memory>>{};

    for (final memory in memories) {
      if (!memory.isActive) continue;
      final key = '${memory.startDate.year}-${memory.startDate.month}';
      monthGroups.putIfAbsent(key, () => []).add(memory);
    }

    for (final entry in monthGroups.entries) {
      final parts = entry.key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);

      // Skip current month
      if (year == now.year && month == now.month) continue;

      final monthMemories = entry.value
        ..sort((a, b) => b.score.compareTo(a.score));

      final topPhotos = monthMemories
          .expand((m) => m.photoIds)
          .take(maxPhotosPerAlbum)
          .toList();

      if (topPhotos.length < 5) continue;

      final monthName = _monthNames[month - 1];

      albums.add(AutomaticAlbum(
        albumId: 'auto_monthly_${year}_$month',
        title: '$monthName $year Highlights',
        type: AutomaticAlbumType.monthlyHighlights,
        photoIds: topPhotos,
        coverPhotoId: topPhotos.first,
        startDate: DateTime(year, month, 1),
        endDate: DateTime(year, month + 1, 0), // Last day of month
        score: monthMemories.map((m) => m.score).reduce(math.max),
        createdAt: now,
        updatedAt: now,
        year: year,
        month: month,
      ));
    }

    return albums;
  }

  static List<AutomaticAlbum> _generateTripAlbums(List<Memory> memories) {
    final albums = <AutomaticAlbum>[];

    for (final memory in memories) {
      if (!memory.isActive || memory.theme != MemoryTheme.trip) continue;
      if (memory.photoIds.length < 5) continue;

      albums.add(AutomaticAlbum(
        albumId: 'auto_trip_${memory.memoryId}',
        title: memory.title,
        type: AutomaticAlbumType.trip,
        photoIds: memory.photoIds,
        coverPhotoId: memory.coverPhotoId,
        startDate: memory.startDate,
        endDate: memory.endDate,
        score: memory.score,
        createdAt: memory.createdAt,
        updatedAt: memory.updatedAt,
        locationLabel: memory.locationLabel,
      ));
    }

    return albums;
  }

  static List<AutomaticAlbum> _generatePeopleAlbums(List<Memory> memories) {
    final albums = <AutomaticAlbum>[];
    final personPhotos = <String, Set<String>>{};

    for (final memory in memories) {
      if (!memory.isActive) continue;
      for (final personId in memory.personIds) {
        personPhotos.putIfAbsent(personId, () => {}).addAll(memory.photoIds);
      }
    }

    for (final entry in personPhotos.entries) {
      if (entry.value.length < 10) continue;

      final photos = entry.value.toList();
      albums.add(AutomaticAlbum(
        albumId: 'auto_people_${entry.key}',
        title: 'Photos with ${entry.key}',
        type: AutomaticAlbumType.people,
        photoIds: photos,
        coverPhotoId: photos.first,
        startDate: DateTime.now().subtract(const Duration(days: 365)),
        endDate: DateTime.now(),
        score: 0.5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }

    return albums;
  }

  static List<AutomaticAlbum> _generateSeasonalAlbums(List<Memory> memories, DateTime now) {
    final albums = <AutomaticAlbum>[];
    final seasonGroups = <String, List<Memory>>{};

    for (final memory in memories) {
      if (!memory.isActive) continue;
      final season = _getSeason(memory.startDate.month);
      final key = '${memory.startDate.year}_$season';
      seasonGroups.putIfAbsent(key, () => []).add(memory);
    }

    for (final entry in seasonGroups.entries) {
      final parts = entry.key.split('_');
      final year = int.parse(parts[0]);
      final season = parts[1];

      final seasonMemories = entry.value;
      final allPhotos = seasonMemories.expand((m) => m.photoIds).take(maxPhotosPerAlbum).toList();

      if (allPhotos.length < 15) continue;

      albums.add(AutomaticAlbum(
        albumId: 'auto_seasonal_${year}_$season',
        title: '$season $year',
        type: AutomaticAlbumType.seasonal,
        photoIds: allPhotos,
        coverPhotoId: allPhotos.first,
        startDate: seasonMemories.map((m) => m.startDate).reduce((a, b) => a.isBefore(b) ? a : b),
        endDate: seasonMemories.map((m) => m.endDate).reduce((a, b) => a.isAfter(b) ? a : b),
        score: seasonMemories.map((m) => m.score).reduce(math.max),
        createdAt: now,
        updatedAt: now,
        year: year,
      ));
    }

    return albums;
  }

  static String _getSeason(int month) {
    if (month >= 3 && month <= 5) return 'Spring';
    if (month >= 6 && month <= 8) return 'Summer';
    if (month >= 9 && month <= 11) return 'Fall';
    return 'Winter';
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}

import '../../domain/models/memory/memory_title_result.dart';
import '../../domain/models/memory/memory_candidate.dart';
import '../../domain/models/memory/memory.dart';

/// Generates human-readable titles for memory candidates.
///
/// Uses a combination of date, location, people, and theme signals
/// to produce descriptive titles without fabricating metadata.
class MemoryTitleGenerator {
  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static const seasonNames = {
    1: 'Winter', 2: 'Winter', 3: 'Spring', 4: 'Spring',
    5: 'Spring', 6: 'Summer', 7: 'Summer', 8: 'Summer',
    9: 'Fall', 10: 'Fall', 11: 'Fall', 12: 'Winter',
  };

  /// Generates a title for a memory candidate.
  ///
  /// [candidate] — the scored memory candidate
  /// [personNames] — names of people detected in the photos (optional)
  /// [locationLabel] — reverse-geocoded location label (optional)
  /// Returns a [MemoryTitleResult] with the generated title and metadata.
  static MemoryTitleResult generate({
    required MemoryCandidate candidate,
    List<String>? personNames,
    String? locationLabel,
  }) {
    final cluster = candidate.cluster;
    final startDate = cluster.startDate;
    final endDate = cluster.endDate;

    // Determine theme
    final theme = _detectTheme(candidate, personNames, locationLabel);

    // Build title components
    final parts = <String>[];
    var usesDate = false;
    var usesLocation = false;
    var usesPeople = false;
    var usesEvent = false;

    // Add theme prefix
    switch (theme) {
      case MemoryTheme.trip:
        parts.add('Trip');
        usesEvent = true;
      case MemoryTheme.birthday:
        parts.add('Birthday');
        usesEvent = true;
      case MemoryTheme.seasonal:
        parts.add(seasonNames[startDate.month] ?? 'Seasonal');
        usesDate = true;
      case MemoryTheme.event:
        parts.add('Event');
        usesEvent = true;
      case MemoryTheme.people:
        if (personNames != null && personNames.isNotEmpty) {
          parts.add(personNames.first);
          usesPeople = true;
        }
      case MemoryTheme.milestone:
        parts.add('Milestone');
        usesEvent = true;
      case MemoryTheme.everyday:
        // No prefix for everyday
        break;
    }

    // Add location
    if (locationLabel != null && locationLabel.isNotEmpty) {
      parts.add('in $locationLabel');
      usesLocation = true;
    }

    // Add date context
    if (cluster.isMultiDay) {
      if (startDate.month == endDate.month) {
        parts.add('${monthNames[startDate.month - 1]} ${startDate.day}–${endDate.day}');
      } else {
        parts.add(
          '${monthNames[startDate.month - 1]} ${startDate.day} – ${monthNames[endDate.month - 1]} ${endDate.day}',
        );
      }
      usesDate = true;
    } else {
      parts.add(_formatSingleDay(startDate));
      usesDate = true;
    }

    // Add year if different from current year
    final now = DateTime.now();
    if (startDate.year != now.year) {
      parts.add('${startDate.year}');
    }

    // Build final title
    final title = parts.join(' ');

    // Generate subtitle
    String? subtitle;
    if (cluster.photoCount > 10) {
      subtitle = '${cluster.photoCount} photos';
    }

    return MemoryTitleResult(
      title: title,
      subtitle: subtitle,
      theme: theme.name,
      confidence: candidate.overallScore,
      usesDate: usesDate,
      usesLocation: usesLocation,
      usesPeople: usesPeople,
      usesEvent: usesEvent,
    );
  }

  /// Detects the most appropriate theme for a candidate.
  static MemoryTheme _detectTheme(
    MemoryCandidate candidate,
    List<String>? personNames,
    String? locationLabel,
  ) {
    final cluster = candidate.cluster;

    // Trip detection: multi-day + location change
    if (cluster.isMultiDay && locationLabel != null) {
      return MemoryTheme.trip;
    }

    // People theme: multiple people present
    if (personNames != null && personNames.length >= 2) {
      return MemoryTheme.people;
    }

    // Single person with enough photos
    if (personNames != null && personNames.length == 1 && cluster.photoCount >= 5) {
      return MemoryTheme.people;
    }

    // Location-based event
    if (locationLabel != null && cluster.photoCount >= 5) {
      return MemoryTheme.event;
    }

    // Seasonal: photos from same month across different years
    if (cluster.span.inDays > 30) {
      return MemoryTheme.seasonal;
    }

    // Default: everyday
    return MemoryTheme.everyday;
  }

  static String _formatSingleDay(DateTime date) {
    return '${dayNames[date.weekday - 1]}, ${monthNames[date.month - 1]} ${date.day}';
  }
}

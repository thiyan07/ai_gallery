import 'dart:collection';
import 'package:photo_manager/photo_manager.dart';

/// Groups assets by creation date into human-readable date sections.
class DateGrouping {
  DateGrouping._();

  /// Group a flat list of assets by creation date.
  ///
  /// Returns an ordered map of date label → list of assets.
  /// Groups are ordered most-recent-first.
  static LinkedHashMap<String, List<AssetEntity>> groupByDate(
    List<AssetEntity> assets,
  ) {
    final groups = LinkedHashMap<String, List<AssetEntity>>();

    for (final asset in assets) {
      final date = asset.createDateTime;
      final label = _dateLabel(date);
      groups.putIfAbsent(label, () => []).add(asset);
    }

    return groups;
  }

  /// Human-readable date label for a given date.
  static String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    final monthDay = '${_monthName(date.month)} ${date.day}';
    if (date.year == now.year) return monthDay;
    return '$monthDay, ${date.year}';
  }

  static String _monthName(int month) {
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month];
  }
}

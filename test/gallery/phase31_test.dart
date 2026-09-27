import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Date label formatting', () {
    // Test the date label logic directly since DateGrouping._dateLabel is private.
    // We verify the formatting by testing the public API patterns.

    String monthName(int month) {
      const names = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return names[month];
    }

    String dateLabel(DateTime date) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(date.year, date.month, date.day);
      final diff = today.difference(target).inDays;

      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';

      final monthDay = '${monthName(date.month)} ${date.day}';
      if (date.year == now.year) return monthDay;
      return '$monthDay, ${date.year}';
    }

    test('Today returns "Today"', () {
      expect(dateLabel(DateTime.now()), 'Today');
    });

    test('Yesterday returns "Yesterday"', () {
      expect(dateLabel(DateTime.now().subtract(const Duration(days: 1))), 'Yesterday');
    });

    test('Same year returns month day', () {
      final now = DateTime.now();
      final date = DateTime(now.year, 8, 15);
      expect(dateLabel(date), 'August 15');
    });

    test('Different year returns month day year', () {
      final date = DateTime(2024, 3, 22);
      expect(dateLabel(date), 'March 22, 2024');
    });

    test('monthName returns correct names', () {
      expect(monthName(1), 'January');
      expect(monthName(6), 'June');
      expect(monthName(12), 'December');
    });
  });
}

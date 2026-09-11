import 'package:flutter_test/flutter_test.dart';
import 'package:sage/core/calendar_month.dart';
import 'package:sage/core/dates.dart';

void main() {
  const sunday = 0;
  const monday = 1;

  group('leading blanks', () {
    test('a month starting on Sunday, in a Sunday-first locale, has none', () {
      // 1 February 2026 was a Sunday.
      expect(DateTime(2026, 2, 1).weekday, DateTime.sunday);
      expect(CalendarMonth(2026, 2).leadingBlanks(sunday), 0);
    });

    test('the same month in a Monday-first locale has six', () {
      // Sunday is the last column when the week starts on Monday.
      expect(CalendarMonth(2026, 2).leadingBlanks(monday), 6);
    });

    test('a month starting on Tuesday', () {
      // 1 September 2026 is a Tuesday.
      expect(DateTime(2026, 9, 1).weekday, DateTime.tuesday);
      expect(CalendarMonth(2026, 9).leadingBlanks(sunday), 2);
      expect(CalendarMonth(2026, 9).leadingBlanks(monday), 1);
    });

    test('every weekday lands in its own column, for both conventions', () {
      // Exhaustive over a full year: an off-by-one here shifts every date in
      // the month under the wrong weekday, which is the classic grid bug.
      for (var m = 1; m <= 12; m++) {
        final month = CalendarMonth(2026, m);
        for (final first in [sunday, monday]) {
          final blanks = month.leadingBlanks(first);
          expect(blanks, inInclusiveRange(0, 6));
          final column = blanks % 7;
          final expected = (month.first.weekday % 7 - first + 7) % 7;
          expect(column, expected, reason: '2026-$m, week starts $first');
        }
      }
    });
  });

  group('shape', () {
    test('month lengths, including a leap February', () {
      expect(CalendarMonth(2026, 2).daysInMonth, 28);
      expect(CalendarMonth(2028, 2).daysInMonth, 29);
      expect(CalendarMonth(2026, 9).daysInMonth, 30);
      expect(CalendarMonth(2026, 12).daysInMonth, 31);
    });

    test('a 28-day month starting on the first column fits in four rows', () {
      expect(CalendarMonth(2026, 2).rows(sunday), 4);
    });

    test('a long month starting late needs six', () {
      // August 2026 starts on a Saturday and has 31 days.
      expect(DateTime(2026, 8, 1).weekday, DateTime.saturday);
      expect(CalendarMonth(2026, 8).rows(sunday), 6);
    });

    test('rows always hold every day', () {
      for (var m = 1; m <= 12; m++) {
        final month = CalendarMonth(2026, m);
        for (final first in [sunday, monday]) {
          final cells = month.rows(first) * 7;
          expect(
            cells,
            greaterThanOrEqualTo(
              month.leadingBlanks(first) + month.daysInMonth,
            ),
          );
          expect(
            cells - month.leadingBlanks(first) - month.daysInMonth,
            lessThan(7),
          );
        }
      }
    });
  });

  group('days', () {
    test('first and last day are local days of the 1st and the last', () {
      final m = CalendarMonth(2026, 9);
      expect(m.firstDay, localDayOf(DateTime(2026, 9, 1)));
      expect(m.lastDay, localDayOf(DateTime(2026, 9, 30)));
      expect(m.lastDay - m.firstDay + 1, 30);
    });

    test('contains is inclusive at both ends and nothing beyond', () {
      final m = CalendarMonth(2026, 9);
      expect(m.contains(m.firstDay), isTrue);
      expect(m.contains(m.lastDay), isTrue);
      expect(m.contains(m.firstDay - 1), isFalse);
      expect(m.contains(m.lastDay + 1), isFalse);
    });

    test('previous and next cross year boundaries', () {
      expect(CalendarMonth(2026, 1).previous.year, 2025);
      expect(CalendarMonth(2026, 1).previous.month, 12);
      expect(CalendarMonth(2026, 12).next.year, 2027);
      expect(CalendarMonth(2026, 12).next.month, 1);
    });
  });
}

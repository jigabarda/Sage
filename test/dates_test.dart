import 'package:flutter_test/flutter_test.dart';
import 'package:sage/core/dates.dart';

void main() {
  test('a day number is stable across every hour of that local day', () {
    final day = localDayOf(DateTime(2026, 9, 6, 0, 0));
    expect(localDayOf(DateTime(2026, 9, 6, 2, 0)), day);
    expect(localDayOf(DateTime(2026, 9, 6, 13, 30)), day);
    expect(localDayOf(DateTime(2026, 9, 6, 23, 59, 59)), day);
  });

  test('midnight rolls the day exactly once', () {
    final d1 = localDayOf(DateTime(2026, 9, 6, 23, 59));
    final d2 = localDayOf(DateTime(2026, 9, 7, 0, 1));
    expect(d2 - d1, 1);
  });

  test('startOfDay round-trips a day number', () {
    final day = localDayOf(DateTime(2026, 9, 6, 17, 4));
    final start = startOfDay(day);
    expect(start.hour, 0);
    expect(start.minute, 0);
    expect(localDayOf(start), day);
    expect(start.year, 2026);
    expect(start.month, 9);
    expect(start.day, 6);
  });

  test('weekdayOf matches the calendar', () {
    // 2026-09-06 is a Sunday.
    expect(weekdayOf(localDayOf(DateTime(2026, 9, 6))), DateTime.sunday);
    expect(weekdayOf(localDayOf(DateTime(2026, 9, 7))), DateTime.monday);
  });

  test('daysInclusive covers both ends and every gap between', () {
    final from = localDayOf(DateTime(2026, 9, 1));
    final to = localDayOf(DateTime(2026, 9, 7));
    final days = daysInclusive(from, to);

    expect(days, hasLength(7));
    expect(days.first, from);
    expect(days.last, to);
    // Rules iterate the window rather than the rows they have, so a day with
    // no daily_log entry still gets visited and counted as missing.
    expect(days, orderedEquals([for (var d = from; d <= to; d++) d]));
  });

  test('an episode after midnight belongs to that morning\'s sleep, not the '
      'previous day', () {
    // The convention the sleep rules depend on: daily_log.sleep_hours for day D
    // is the night that ended on the morning of D. A 02:00 episode on the 7th
    // is preceded by the 7th's recorded sleep, not the 6th's.
    final at2am = DateTime(2026, 9, 7, 2, 0).millisecondsSinceEpoch;
    expect(sleepDayForEpisode(at2am), localDayOf(DateTime(2026, 9, 7)));

    final at2340 = DateTime(2026, 9, 7, 23, 40).millisecondsSinceEpoch;
    expect(sleepDayForEpisode(at2340), localDayOf(DateTime(2026, 9, 7)));
  });
}

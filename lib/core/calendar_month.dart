import 'dates.dart';

/// The arithmetic behind a month grid, kept pure so it can be tested without a
/// widget tree.
///
/// Grids get this wrong in two classic ways: an off-by-one in the leading blank
/// cells, which shifts every date under the wrong weekday, and assuming the week
/// starts on Monday. It starts on Sunday in the Philippines and the US and on
/// Monday across most of Europe, so the first weekday comes from the locale and
/// is passed in rather than hardcoded.
class CalendarMonth {
  CalendarMonth(int year, int month)
    : first = DateTime(year, month),
      daysInMonth = DateTime(year, month + 1, 0).day;

  /// Midnight on the 1st, local time.
  final DateTime first;
  final int daysInMonth;

  int get year => first.year;
  int get month => first.month;

  LocalDay get firstDay => localDayOf(first);
  LocalDay get lastDay => firstDay + daysInMonth - 1;

  CalendarMonth get previous => CalendarMonth(year, month - 1);
  CalendarMonth get next => CalendarMonth(year, month + 1);

  /// Empty cells before the 1st.
  ///
  /// [firstDayOfWeekIndex] follows `MaterialLocalizations`: 0 is Sunday, 1 is
  /// Monday. `DateTime.weekday` runs Monday = 1 to Sunday = 7, and `% 7` maps it
  /// onto the same Sunday-is-0 scale before the two are compared.
  int leadingBlanks(int firstDayOfWeekIndex) =>
      (first.weekday % 7 - firstDayOfWeekIndex + 7) % 7;

  /// Rows needed to show the whole month. Four to six, depending on where the
  /// 1st lands.
  int rows(int firstDayOfWeekIndex) =>
      ((leadingBlanks(firstDayOfWeekIndex) + daysInMonth) / 7).ceil();

  bool contains(LocalDay day) => day >= firstDay && day <= lastDay;

  bool isSameMonth(CalendarMonth other) =>
      year == other.year && month == other.month;
}

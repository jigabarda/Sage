import '../../core/dates.dart';

/// Menstrual cycle arithmetic, kept pure and separate so the part that decides
/// what counts as "around a period" can be tested without a database.
///
/// ## What is stored, and what is derived
///
/// `daily_log.cycle_day` holds the day of the cycle, where **1 is the first day
/// of a period**. Everything else here is derived from the days recorded as 1:
/// the app never asks someone to work out that today is day 14.
///
/// The derivation matters for the correlation rule. A day is classifiable only
/// inside a span bracketed by recorded period starts — before the first one and
/// after the last, "not around a period" is a guess rather than a fact, and the
/// rule refuses to guess.
abstract final class Cycle {
  /// Days before a period starts that count as perimenstrual.
  ///
  /// Two before through three after is the window used in migraine research
  /// when talking about menstrual migraine. It is written here as a constant
  /// with its reason rather than inlined, because it is a clinical convention
  /// this app has adopted, not a number anyone should tune to fit their data.
  static const daysBefore = 2;
  static const daysAfter = 3;

  /// Period starts needed before the rule will say anything.
  ///
  /// Three, so at least two complete cycles have been observed. Two starts is
  /// one cycle, and one cycle is an anecdote.
  static const minPeriodStarts = 3;

  /// The days that count as around a period, given the days a period started.
  static Set<LocalDay> perimenstrualDays(Iterable<LocalDay> periodStarts) {
    final out = <LocalDay>{};
    for (final start in periodStarts) {
      for (var d = start - daysBefore; d <= start + daysAfter; d++) {
        out.add(d);
      }
    }
    return out;
  }

  /// The span over which every day can be honestly classified.
  ///
  /// Runs from the first period start to the last one plus [daysAfter]. Outside
  /// it there is no basis for calling a day "not around a period" — a day three
  /// weeks after the last recorded start might be mid-cycle or might be a
  /// period nobody logged.
  static (LocalDay, LocalDay)? classifiableSpan(List<LocalDay> periodStarts) {
    if (periodStarts.length < minPeriodStarts) return null;
    final sorted = [...periodStarts]..sort();
    return (sorted.first - daysBefore, sorted.last + daysAfter);
  }

  /// What day of the cycle [day] is, given the most recent period start on or
  /// before it.
  ///
  /// Used to pre-fill the daily log so nobody has to count. Null when there is
  /// no earlier start to count from.
  static int? dayNumberFor(LocalDay day, Iterable<LocalDay> periodStarts) {
    LocalDay? latest;
    for (final start in periodStarts) {
      if (start <= day && (latest == null || start > latest)) latest = start;
    }
    if (latest == null) return null;
    final n = day - latest + 1;
    // A "cycle day 97" is a period that was never logged, not a 97-day cycle.
    // Offering it as a suggestion would be worse than offering nothing.
    return n > 60 ? null : n;
  }
}

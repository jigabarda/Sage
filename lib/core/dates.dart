/// Day arithmetic for the correlation engine.
///
/// Everything the app stores as a *moment* is epoch milliseconds. Everything it
/// stores as a *day* is a [LocalDay] number. The two are not interchangeable,
/// and mixing them is the bug this file exists to prevent.
///
/// ## Why days are a separate type of number
///
/// The correlation rules ask questions like "did an episode follow a short
/// night?". Answering that by subtracting timestamps is wrong at the edges: an
/// episode at 02:00 and the sleep that preceded it are nineteen hours apart by
/// clock arithmetic but belong to the same day by every other measure. Compare
/// day numbers, never raw millis.
///
/// Day numbers are computed in **local time**, so a day boundary is midnight
/// where the user is, not UTC. A UTC-based day number puts a 07:30 episode in
/// Manila on the previous day and quietly attributes it to the wrong night.
library;

/// Days since the Unix epoch, in local time.
///
/// A plain `int` at the database boundary; this typedef exists so signatures
/// say which kind of number they mean.
typedef LocalDay = int;

/// The local day [at] falls on.
///
/// The local calendar date is read first, then re-anchored to **UTC midnight**
/// before dividing. Dividing a local midnight's epoch millis instead is off by
/// one for most of the world: in UTC+8, local midnight on the 6th is 16:00 on
/// the 5th in UTC, so the division returns the 5th. UTC has no offset and no
/// DST, which makes the division exact.
LocalDay localDayOf(DateTime at) {
  final l = at.toLocal();
  return DateTime.utc(l.year, l.month, l.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// The local day an epoch-millis timestamp falls on.
LocalDay localDayOfMillis(int millis) =>
    localDayOf(DateTime.fromMillisecondsSinceEpoch(millis));

/// Local midnight that starts [day].
///
/// The inverse of [localDayOf]: the day number is expanded back to a UTC
/// instant, its calendar date is read off, and *that* date becomes local
/// midnight. Going through the calendar rather than returning the instant
/// directly is what keeps it correct across a DST shift, where a local day is
/// not 24 hours long.
DateTime startOfDay(LocalDay day) {
  final utc = DateTime.fromMillisecondsSinceEpoch(
    day * Duration.millisecondsPerDay,
    isUtc: true,
  );
  return DateTime(utc.year, utc.month, utc.day);
}

/// Today's local day number.
LocalDay today() => localDayOf(DateTime.now());

/// Whole days from [from] to [to]; negative when [to] is earlier.
int daysBetween(LocalDay from, LocalDay to) => to - from;

/// Weekday of [day], `DateTime.monday`..`DateTime.sunday`.
///
/// Used by the day-of-week clustering rule. Going through [startOfDay] rather
/// than a modulo of the day number keeps it correct regardless of which
/// weekday the epoch happened to fall on.
int weekdayOf(LocalDay day) => startOfDay(day).weekday;

/// Inclusive list of days from [from] to [to].
///
/// Correlation rules iterate a window rather than the rows they happen to
/// have, because a day with no `daily_log` entry is *missing data* and must be
/// distinguishable from a day logged as zero. A rule that only walks existing
/// rows silently treats "not recorded" as "did not happen".
List<LocalDay> daysInclusive(LocalDay from, LocalDay to) => [
  for (var d = from; d <= to; d++) d,
];

/// The `daily_log` day whose overnight sleep precedes an episode at [millis].
///
/// **Convention, relied on by every sleep rule.** `daily_log.sleep_hours` for
/// day D is the sleep of the night that *ended* on the morning of D — how a
/// person naturally logs it ("I slept five hours last night"). So an episode
/// on day D, whether it starts at 02:00 or 23:40, is preceded by D's own
/// recorded sleep. This function is the single place that mapping lives; do
/// not re-derive it at a call site.
LocalDay sleepDayForEpisode(int millis) => localDayOfMillis(millis);

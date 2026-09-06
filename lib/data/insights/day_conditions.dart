import '../../constants/episode_kind.dart';

/// A yes/no property of a day, expressed as SQL over `daily_log`.
///
/// Kept as SQL fragments rather than Dart predicates so the comparison runs as
/// one aggregate query per condition instead of pulling every row into memory
/// — and, more importantly, so [guard] and [predicate] sit next to each other
/// where the relationship between them is obvious.
class DayCondition {
  const DayCondition({
    required this.code,
    required this.label,
    required this.opposite,
    required this.guard,
    required this.predicate,
    required this.kinds,
  });

  /// Stable identifier, used in the insight id.
  final String code;

  /// How the condition reads in a sentence: "the 9 days you *slept under six
  /// hours*".
  final String label;

  /// How the *absence* reads: "the 21 days you *slept more*".
  ///
  /// Written out rather than negated in prose, because "the days you did not
  /// sleep under six hours" is a sentence nobody parses on first read.
  final String opposite;

  /// SQL that must hold for the day to be counted at all.
  ///
  /// **Always a NOT NULL check on the specific column this condition reads.**
  /// This is the whole reason `daily_log` measures are nullable. A day where
  /// someone recorded their sleep but not their stress is evidence about
  /// sleep and no evidence at all about stress, and a guard that only checked
  /// "is there a row" would count it as a calm day.
  final String guard;

  /// SQL that is true on a day with the condition.
  final String predicate;

  /// Which conditions this is offered for. Late meals are a reflux measure;
  /// oversleeping is a migraine one.
  final Set<EpisodeKind> kinds;
}

/// The conditions the correlation engine tests.
///
/// Thresholds here are the commonly cited ones rather than anything derived
/// from this user's data. Fitting a threshold to the same data you then test
/// against is how you find a pattern in noise — pick the cut-off first, then
/// see whether it separates anything.
abstract final class DayConditions {
  static const all = <DayCondition>[
    DayCondition(
      code: 'short_sleep',
      label: 'slept under 6 hours',
      opposite: 'slept more',
      guard: 'sleep_hours IS NOT NULL',
      predicate: 'sleep_hours < 6',
      kinds: {EpisodeKind.migraine, EpisodeKind.reflux},
    ),
    DayCondition(
      code: 'long_sleep',
      label: 'slept over 9 hours',
      opposite: 'slept less',
      guard: 'sleep_hours IS NOT NULL',
      predicate: 'sleep_hours > 9',
      // Oversleeping is a well-known migraine trigger and surprises people,
      // which is exactly the sort of thing this engine exists to surface.
      kinds: {EpisodeKind.migraine},
    ),
    DayCondition(
      code: 'skipped_meal',
      label: 'skipped a meal',
      opposite: 'ate normally',
      guard: 'meals_skipped IS NOT NULL',
      predicate: 'meals_skipped > 0',
      kinds: {EpisodeKind.migraine},
    ),
    DayCondition(
      code: 'high_stress',
      label: 'rated your stress 4 or 5',
      opposite: 'rated it lower',
      guard: 'stress_level IS NOT NULL',
      predicate: 'stress_level >= 4',
      kinds: {EpisodeKind.migraine, EpisodeKind.reflux},
    ),
    DayCondition(
      code: 'alcohol',
      label: 'had alcohol',
      opposite: 'had none',
      guard: 'alcohol_units IS NOT NULL',
      predicate: 'alcohol_units > 0',
      kinds: {EpisodeKind.migraine, EpisodeKind.reflux},
    ),
    DayCondition(
      code: 'high_caffeine',
      label: 'had 3 or more caffeinated drinks',
      opposite: 'had fewer',
      guard: 'caffeine_units IS NOT NULL',
      predicate: 'caffeine_units >= 3',
      kinds: {EpisodeKind.migraine, EpisodeKind.reflux},
    ),
    DayCondition(
      code: 'low_water',
      label: 'drank 3 glasses of water or fewer',
      opposite: 'drank more',
      guard: 'water_glasses IS NOT NULL',
      predicate: 'water_glasses <= 3',
      kinds: {EpisodeKind.migraine},
    ),
    DayCondition(
      code: 'late_meal',
      label: 'ate close to lying down',
      opposite: 'left a gap after eating',
      guard: 'late_meal IS NOT NULL',
      predicate: 'late_meal = 1',
      kinds: {EpisodeKind.reflux},
    ),
  ];

  static List<DayCondition> forKind(EpisodeKind kind) =>
      all.where((c) => c.kinds.contains(kind)).toList(growable: false);
}

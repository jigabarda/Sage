import 'package:flutter/foundation.dart';

import '../../core/dates.dart';

/// One day's context: the things that might precede an episode.
///
/// **Every measure is nullable, and null means "not recorded".** That is the
/// single most important property of this class. A correlation rule must be
/// able to tell a day someone did not fill in apart from a day they filled in
/// as zero — otherwise every unlogged day silently becomes a day with no
/// sleep, no stress and no caffeine, and the rules start finding patterns in
/// the gaps.
@immutable
class DailyLog {
  const DailyLog({
    required this.day,
    this.sleepHours,
    this.stressLevel,
    this.mealsSkipped,
    this.caffeineUnits,
    this.alcoholUnits,
    this.waterGlasses,
    this.lateMeal,
    this.cycleDay,
    required this.updatedAt,
  });

  const DailyLog.empty(this.day)
    : sleepHours = null,
      stressLevel = null,
      mealsSkipped = null,
      caffeineUnits = null,
      alcoholUnits = null,
      waterGlasses = null,
      lateMeal = null,
      cycleDay = null,
      updatedAt = null;

  /// Local day number, not a timestamp. See `core/dates.dart`.
  final LocalDay day;

  /// Sleep of the night that *ended* on the morning of [day] — the convention
  /// every sleep rule depends on. See `sleepDayForEpisode`.
  final double? sleepHours;

  /// 1 (calm) to 5 (very stressed).
  final int? stressLevel;

  final int? mealsSkipped;
  final int? caffeineUnits;
  final int? alcoholUnits;
  final int? waterGlasses;

  /// Ate within about three hours of lying down. The main reflux day-measure.
  final bool? lateMeal;

  final int? cycleDay;

  final DateTime? updatedAt;

  /// True when nothing at all has been recorded for this day.
  bool get isEmpty =>
      sleepHours == null &&
      stressLevel == null &&
      mealsSkipped == null &&
      caffeineUnits == null &&
      alcoholUnits == null &&
      waterGlasses == null &&
      lateMeal == null &&
      cycleDay == null;

  factory DailyLog.fromRow(Map<String, Object?> row) => DailyLog(
    day: row['local_day']! as int,
    sleepHours: (row['sleep_hours'] as num?)?.toDouble(),
    stressLevel: row['stress_level'] as int?,
    mealsSkipped: row['meals_skipped'] as int?,
    caffeineUnits: row['caffeine_units'] as int?,
    alcoholUnits: row['alcohol_units'] as int?,
    waterGlasses: row['water_glasses'] as int?,
    // SQLite has no boolean. 1/0, and null stays null.
    lateMeal: row['late_meal'] == null ? null : row['late_meal'] == 1,
    cycleDay: row['cycle_day'] as int?,
    updatedAt: row['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );

  Map<String, Object?> toRow() => {
    'local_day': day,
    'sleep_hours': sleepHours,
    'stress_level': stressLevel,
    'meals_skipped': mealsSkipped,
    'caffeine_units': caffeineUnits,
    'alcohol_units': alcoholUnits,
    'water_glasses': waterGlasses,
    'late_meal': lateMeal == null ? null : (lateMeal! ? 1 : 0),
    'cycle_day': cycleDay,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };

  /// Every field is explicitly clearable, because "I did not mean to record
  /// that" has to be expressible. A `copyWith` that cannot set a field back to
  /// null would make an accidental tap permanent.
  DailyLog copyWith({
    double? sleepHours,
    bool clearSleep = false,
    int? stressLevel,
    bool clearStress = false,
    int? mealsSkipped,
    bool clearMealsSkipped = false,
    int? caffeineUnits,
    bool clearCaffeine = false,
    int? alcoholUnits,
    bool clearAlcohol = false,
    int? waterGlasses,
    bool clearWater = false,
    bool? lateMeal,
    bool clearLateMeal = false,
    int? cycleDay,
    bool clearCycleDay = false,
  }) => DailyLog(
    day: day,
    sleepHours: clearSleep ? null : (sleepHours ?? this.sleepHours),
    stressLevel: clearStress ? null : (stressLevel ?? this.stressLevel),
    mealsSkipped: clearMealsSkipped
        ? null
        : (mealsSkipped ?? this.mealsSkipped),
    caffeineUnits: clearCaffeine ? null : (caffeineUnits ?? this.caffeineUnits),
    alcoholUnits: clearAlcohol ? null : (alcoholUnits ?? this.alcoholUnits),
    waterGlasses: clearWater ? null : (waterGlasses ?? this.waterGlasses),
    lateMeal: clearLateMeal ? null : (lateMeal ?? this.lateMeal),
    cycleDay: clearCycleDay ? null : (cycleDay ?? this.cycleDay),
    updatedAt: DateTime.now(),
  );
}

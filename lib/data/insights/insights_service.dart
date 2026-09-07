import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../constants/episode_kind.dart';
import '../../constants/relievers.dart';
import '../../core/dates.dart';
import 'day_conditions.dart';
import 'insight.dart';

/// Derives plain-language observations from the person's own rows.
///
/// **Every rule here is arithmetic — no model, no network, no inference beyond
/// counting and dividing.** That is the point: the reader can check any
/// sentence this produces against numbers they already know, which is exactly
/// what they cannot do with generated text.
///
/// ## Every rule has a minimum-evidence gate, and the gate is part of the rule
///
/// A finding fired from two data points is as bad as an invented one, because
/// the reader has no way to tell it apart from a well-founded one. When a gate
/// fails the finding does not appear — it is **never** softened into "this may
/// be a pattern". A hedge reads as a finding to someone who is looking for an
/// explanation for their pain.
///
/// The gates here are deliberately tighter than the equivalents in Sellora.
/// Health data is noisier than sales data, and the cost of a false pattern is
/// different in kind: a wrong day-of-week finding about sales wastes a bit of
/// attention, a wrong food finding makes someone give up a food for nothing.
///
/// ## What this may never do
///
/// No insight tells anyone to seek care, and none is an alarm. Urgency belongs
/// to Tier 0, evaluated deterministically at the moment it matters. A card
/// someone might read next week is the wrong instrument for it entirely.
class InsightsService {
  InsightsService(this._db);

  final Database _db;

  /// Nothing fires below this many episodes of the condition, whatever the
  /// rule. Eight is not a lot; it is the floor below which every rule here is
  /// arithmetic on noise.
  static const minEpisodes = 8;

  /// Days with any `daily_log` entry needed before day-comparison rules run.
  static const minLoggedDays = 14;

  /// A comparison needs enough days on **both** sides. Five days of short
  /// sleep tells you nothing if there are only two normal nights to compare
  /// against.
  static const minDaysEachSide = 5;

  /// Episodes on the condition's own side, so a rule cannot fire off one bad
  /// week.
  static const minEpisodesOnCondition = 3;

  /// How much more often episodes must fall on condition days before it is
  /// worth saying. Twice as often, not 10% more.
  static const minLift = 2.0;

  /// Above this the finding is called strong rather than moderate.
  static const strongLift = 3.0;

  /// Weekday clustering needs a real window and real volume.
  static const weekdayWindowWeeks = 12;
  static const minOccurrencesPerWeekday = 4;
  static const minEpisodesForWeekday = 12;
  static const minEpisodesOnWeekday = 3;

  /// Frequency comparison: two equal windows, back to back.
  static const frequencyWindowDays = 28;
  static const minFrequencyChange = 0.5;

  /// The window the rescue-medication count is reported over. A month is the
  /// period clinicians ask about, so the figure is directly answerable.
  static const rescueWindowDays = 30;

  /// Rated attempts before a reliever's record is presented as a pattern.
  /// Tighter than the Tier 1 reminder, because this is framed as a finding.
  static const minRatedRelieverAttempts = 4;

  /// Each rule contributes at most this many findings, so one strong signal
  /// cannot bury every other rule.
  static const maxPerRule = 3;

  /// Everything worth saying, strongest first.
  Future<List<Insight>> all() async {
    final out = <Insight>[];
    for (final kind in EpisodeKind.values) {
      out.addAll(await forKind(kind));
    }
    // Not per-condition, and outside the per-condition episode gate: how often
    // rescue medication was needed is a fact about the person, not about one
    // diagnosis.
    final rescue = await rescueUseFinding();
    if (rescue != null) out.add(rescue);

    out.sort((a, b) => a.strength.index.compareTo(b.strength.index));
    return List.unmodifiable(out);
  }

  /// How many of the last [rescueWindowDays] days involved rescue medication.
  ///
  /// **A count, and deliberately nothing more.** How many days is too many is a
  /// clinical question with different answers for different drugs, and this app
  /// has no view on it — reporting the number only above some threshold would
  /// itself be a hidden judgement, so it is reported whenever there is anything
  /// to report. The reader takes it to someone qualified to interpret it.
  ///
  /// Info strength: it is a plain summary, not a pattern, and it must not
  /// outrank a correlation finding in the list or the weekly notification.
  Future<Insight?> rescueUseFinding({DateTime? now}) async {
    final at = now ?? DateTime.now();

    // The denominator has to describe a window that was actually observed.
    // "3 of the last 30 days" is misleading after a week of use.
    final first = await _firstRecordedDay();
    if (first == null) return null;
    if (localDayOf(at) - first < rescueWindowDays - 1) return null;

    final from = startOfDay(
      localDayOf(at) - (rescueWindowDays - 1),
    ).millisecondsSinceEpoch;
    final rows = await _db.rawQuery(
      '''
      SELECT COUNT(DISTINCT CAST((d.taken_at - ?) / 86400000 AS INTEGER)) AS n
      FROM med_doses d
      JOIN meds m ON m.id = d.med_id
      WHERE m.kind = 'rescue' AND d.taken_at >= ?
      ''',
      [from, from],
    );
    final days = (rows.single['n'] as int?) ?? 0;
    if (days == 0) return null;

    return Insight(
      id: 'rescue_use',
      strength: InsightStrength.info,
      icon: Icons.medication_outlined,
      title: 'Rescue medication',
      detail:
          'You recorded taking rescue medication on $days of the last '
          '$rescueWindowDays days.',
    );
  }

  Future<LocalDay?> _firstRecordedDay() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(d) AS first FROM ('
      ' SELECT MIN(started_day) AS d FROM episodes'
      ' UNION ALL SELECT MIN(local_day) FROM daily_log'
      ')',
    );
    return rows.single['first'] as int?;
  }

  Future<List<Insight>> forKind(EpisodeKind kind) async {
    final episodeCount = await _episodeCount(kind);
    // The global gate. Below this, none of the rules below can say anything
    // honest, and running them would just produce confident noise.
    if (episodeCount < minEpisodes) return const [];

    final out = <Insight>[
      ...await _dayConditionFindings(kind),
      ...?await _weekdayFinding(kind),
      ...?await _frequencyFinding(kind),
      ...?await _relieverFinding(kind),
    ];
    out.sort((a, b) => a.strength.index.compareTo(b.strength.index));
    return out;
  }

  /// Why nothing is showing yet, in the person's own numbers.
  ///
  /// An empty patterns screen with no explanation reads as broken. This says
  /// what is missing without implying a finding is waiting just out of reach.
  Future<String> progressNote() async {
    final episodes = await _totalEpisodeCount();
    final days = await _totalLoggedDays();
    final parts = <String>[];
    if (episodes < minEpisodes) {
      parts.add('$episodes of about $minEpisodes episodes');
    }
    if (days < minLoggedDays) {
      parts.add('$days of about $minLoggedDays days filled in');
    }
    if (parts.isEmpty) {
      return 'Nothing has cleared the evidence bar yet. That is a real '
          'answer, not a gap — a pattern reported from too little data is '
          'worse than none.';
    }
    return 'Patterns need something to work from: ${parts.join(', ')}. '
        'Nothing is shown until there is enough to say honestly.';
  }

  // ---------------------------------------------------------------------
  // Rule: episodes concentrate on days with some condition
  // ---------------------------------------------------------------------

  Future<List<Insight>> _dayConditionFindings(EpisodeKind kind) async {
    final window = await _window();
    if (window == null) return const [];

    final logged = await _loggedDayCount(window.$1, window.$2);
    if (logged < minLoggedDays) return const [];

    final found = <(Insight, double)>[];

    for (final c in DayConditions.forKind(kind)) {
      final row = await _conditionCounts(kind, c, window.$1, window.$2);
      final daysWith = row.$1;
      final daysWithout = row.$2;
      final epWith = row.$3;
      final epWithout = row.$4;

      // Both sides need enough days, or the comparison is between a sample
      // and an anecdote.
      if (daysWith < minDaysEachSide || daysWithout < minDaysEachSide) {
        continue;
      }
      if (epWith < minEpisodesOnCondition) continue;

      final rateWith = epWith / daysWith;
      final rateWithout = epWithout / daysWithout;

      // A zero baseline would make every lift infinite. Requiring the
      // condition side to clear an absolute floor as well keeps "3 of 5 days,
      // against 0 of 30" from being reported as an unbounded effect.
      if (rateWithout == 0) {
        if (rateWith < 0.4) continue;
      } else if (rateWith / rateWithout < minLift) {
        continue;
      }

      final lift = rateWithout == 0 ? double.infinity : rateWith / rateWithout;

      found.add((
        Insight(
          id: 'cond_${kind.code}_${c.code}',
          strength: lift >= strongLift
              ? InsightStrength.strong
              : InsightStrength.moderate,
          icon: Icons.trending_up,
          title: '${kind.label} and when you ${c.label}',
          detail:
              'You had ${kind.inSentence} on $epWith of the '
              '$daysWith days you ${c.label}, against $epWithout of the '
              '$daysWithout days you ${c.opposite}.',
        ),
        lift,
      ));
    }

    found.sort((a, b) => b.$2.compareTo(a.$2));
    return found.take(maxPerRule).map((e) => e.$1).toList(growable: false);
  }

  Future<(int, int, int, int)> _conditionCounts(
    EpisodeKind kind,
    DayCondition c,
    LocalDay from,
    LocalDay to,
  ) async {
    // One aggregate rather than a row-by-row walk. `has_ep` is per day, so a
    // day with two episodes counts once: the figure quoted is "days on which
    // you had one", which is a proportion someone can actually picture.
    final rows = await _db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN cond THEN 1 ELSE 0 END)                   AS days_with,
        SUM(CASE WHEN cond THEN 0 ELSE 1 END)                   AS days_without,
        SUM(CASE WHEN cond AND has_ep THEN 1 ELSE 0 END)        AS ep_with,
        SUM(CASE WHEN (NOT cond) AND has_ep THEN 1 ELSE 0 END)  AS ep_without
      FROM (
        SELECT
          (${c.predicate}) AS cond,
          EXISTS(
            SELECT 1 FROM episodes e
            WHERE e.started_day = d.local_day AND e.kind = ?
          ) AS has_ep
        FROM daily_log d
        WHERE ${c.guard} AND d.local_day >= ? AND d.local_day <= ?
      )
      ''',
      [kind.code, from, to],
    );
    final r = rows.single;
    int n(String k) => (r[k] as int?) ?? 0;
    return (n('days_with'), n('days_without'), n('ep_with'), n('ep_without'));
  }

  // ---------------------------------------------------------------------
  // Rule: episodes cluster on one weekday
  // ---------------------------------------------------------------------

  Future<List<Insight>?> _weekdayFinding(EpisodeKind kind) async {
    final to = localDayOf(DateTime.now());
    final from = to - (weekdayWindowWeeks * 7);

    final rows = await _db.rawQuery(
      'SELECT started_day FROM episodes WHERE kind = ? AND started_day >= ? AND started_day <= ?',
      [kind.code, from, to],
    );
    if (rows.length < minEpisodesForWeekday) return null;

    final episodesPerWeekday = <int, int>{};
    for (final r in rows) {
      final wd = weekdayOf(r['started_day']! as int);
      episodesPerWeekday[wd] = (episodesPerWeekday[wd] ?? 0) + 1;
    }

    // How many times each weekday actually came round in the window. Dividing
    // by a flat count instead would penalise whichever weekday happened to
    // occur once less.
    final occurrences = <int, int>{};
    for (final d in daysInclusive(from, to)) {
      final wd = weekdayOf(d);
      occurrences[wd] = (occurrences[wd] ?? 0) + 1;
    }
    if (occurrences.values.any((n) => n < minOccurrencesPerWeekday)) {
      return null;
    }

    final rates = <int, double>{
      for (final wd in occurrences.keys)
        wd: (episodesPerWeekday[wd] ?? 0) / occurrences[wd]!,
    };

    final best = rates.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if ((episodesPerWeekday[best.key] ?? 0) < minEpisodesOnWeekday) {
      return null;
    }

    final others = rates.entries.where((e) => e.key != best.key);
    final otherMean =
        others.map((e) => e.value).reduce((a, b) => a + b) / others.length;
    if (otherMean == 0 || best.value / otherMean < minLift) return null;

    final name = _weekdayName(best.key);
    return [
      Insight(
        id: 'weekday_${kind.code}_${best.key}',
        strength: best.value / otherMean >= strongLift
            ? InsightStrength.strong
            : InsightStrength.moderate,
        icon: Icons.calendar_today,
        title: '${kind.label} and $name',
        detail:
            '${episodesPerWeekday[best.key]} of your last ${rows.length} started on a '
            '$name, out of ${occurrences[best.key]} ${name}s in the window.',
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // Rule: how often, lately, against this person's own baseline
  // ---------------------------------------------------------------------

  Future<List<Insight>?> _frequencyFinding(EpisodeKind kind) async {
    final to = localDayOf(DateTime.now());
    final midpoint = to - frequencyWindowDays;
    final from = to - (frequencyWindowDays * 2);

    final first = await _firstEpisodeDay(kind);
    // Two full windows of history, or "the previous four weeks" includes time
    // before this person was logging at all.
    if (first == null || first > from) return null;

    final recent = await _episodeCountBetween(kind, midpoint + 1, to);
    final previous = await _episodeCountBetween(kind, from, midpoint);
    if (previous == 0) return null;

    final change = (recent - previous) / previous;
    if (change.abs() < minFrequencyChange) return null;

    final up = recent > previous;
    return [
      Insight(
        id: 'freq_${kind.code}_${up ? 'up' : 'down'}',
        strength: InsightStrength.info,
        icon: up ? Icons.arrow_upward : Icons.arrow_downward,
        title: up
            ? 'More ${kind.label.toLowerCase()} lately'
            : 'Fewer ${kind.label.toLowerCase()} lately',
        // Stated as a count, both ways, with no praise attached to the lower
        // number. A quiet month is not an achievement, and framing it as one
        // frames the next bad month as a failure.
        detail:
            'You logged $recent in the last four weeks, against '
            '$previous in the four weeks before.',
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // Rule: what has actually helped
  // ---------------------------------------------------------------------

  Future<List<Insight>?> _relieverFinding(EpisodeKind kind) async {
    final rows = await _db.rawQuery(
      '''
      SELECT r.reliever_code AS code,
             COUNT(*) AS rated,
             SUM(CASE WHEN r.helped = 1 THEN 1 ELSE 0 END) AS helped
      FROM episode_relievers r
      JOIN episodes e ON e.id = r.episode_id
      WHERE e.kind = ? AND r.helped IS NOT NULL
      GROUP BY r.reliever_code
      HAVING rated >= ?
      ORDER BY (CAST(helped AS REAL) / rated) DESC, rated DESC
      LIMIT ?
      ''',
      [kind.code, minRatedRelieverAttempts, maxPerRule],
    );
    if (rows.isEmpty) return null;

    final out = <Insight>[];
    for (final r in rows) {
      final rated = r['rated']! as int;
      final helped = (r['helped'] as num?)?.toInt() ?? 0;
      // Unrated attempts were excluded by the query, not counted as neutral.
      if (helped / rated < 0.6) continue;
      final label = Relievers.labelFor(r['code']! as String);
      out.add(
        Insight(
          id: 'reliever_${kind.code}_${r['code']}',
          strength: InsightStrength.info,
          icon: Icons.check_circle_outline,
          title: 'What has helped',
          detail:
              '"$label" helped $helped of the $rated times you rated it '
              'for ${kind.label.toLowerCase()}.',
        ),
      );
    }
    return out.isEmpty ? null : out;
  }

  // ---------------------------------------------------------------------
  // Counting helpers
  // ---------------------------------------------------------------------

  /// The span the day-comparison rules run over: everything on record.
  ///
  /// Returns null when there is no `daily_log` at all.
  Future<(LocalDay, LocalDay)?> _window() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(local_day) AS a, MAX(local_day) AS b FROM daily_log',
    );
    final a = rows.single['a'] as int?;
    final b = rows.single['b'] as int?;
    if (a == null || b == null) return null;
    return (a, b);
  }

  Future<int> _loggedDayCount(LocalDay from, LocalDay to) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM daily_log WHERE local_day >= ? AND local_day <= ?',
      [from, to],
    );
    return (rows.single['n'] as int?) ?? 0;
  }

  Future<int> _totalLoggedDays() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM daily_log');
    return (rows.single['n'] as int?) ?? 0;
  }

  Future<int> _episodeCount(EpisodeKind kind) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM episodes WHERE kind = ?',
      [kind.code],
    );
    return (rows.single['n'] as int?) ?? 0;
  }

  Future<int> _totalEpisodeCount() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM episodes');
    return (rows.single['n'] as int?) ?? 0;
  }

  Future<int> _episodeCountBetween(
    EpisodeKind kind,
    LocalDay from,
    LocalDay to,
  ) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM episodes WHERE kind = ? AND started_day >= ? AND started_day <= ?',
      [kind.code, from, to],
    );
    return (rows.single['n'] as int?) ?? 0;
  }

  Future<LocalDay?> _firstEpisodeDay(EpisodeKind kind) async {
    final rows = await _db.rawQuery(
      'SELECT MIN(started_day) AS d FROM episodes WHERE kind = ?',
      [kind.code],
    );
    return rows.single['d'] as int?;
  }

  static String _weekdayName(int weekday) => const {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  }[weekday]!;
}

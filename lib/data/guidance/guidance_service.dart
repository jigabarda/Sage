import 'package:sqflite/sqflite.dart';

import '../../constants/episode_kind.dart';
import '../../constants/relievers.dart';
import 'guidance.dart';

/// Tier 1. Fixed steps, plus at most a couple of sentences about this person's
/// own record.
///
/// ## The gates, and why they are here rather than in Phase 3
///
/// The personal notes below are aggregate claims — "4 of the 6 times you tried
/// this" — and every aggregate claim in Sage carries a minimum-evidence gate
/// that fails closed. Putting a claim in front of someone mid-attack does not
/// exempt it; if anything it raises the bar, because that is when they are
/// least able to weigh it.
///
/// A gate that fails produces **nothing**. It is never softened into "this may
/// have helped before" — a hedge is indistinguishable from a finding to
/// someone in pain, which is the whole reason the rule exists.
class GuidanceService {
  GuidanceService(this._db);

  final Database _db;

  /// Rated attempts of one reliever needed before its record can be quoted.
  ///
  /// Three, and rated ones only. Two is an anecdote. Unrated attempts are not
  /// counted at all — null means "never went back to say", and the people
  /// least likely to go back are the ones having the worst episodes, so
  /// treating unrated as "no change" would bias every reliever downwards.
  static const minRatedAttempts = 3;

  /// A reliever has to have helped more often than not to be worth repeating.
  static const minHelpedShare = 0.6;

  /// Closed episodes needed before a typical duration means anything.
  static const minEpisodesForDuration = 3;

  Future<Guidance> forKind(EpisodeKind kind) async {
    final notes = <String>[];

    final reliever = await _bestReliever(kind);
    if (reliever != null) notes.add(reliever);

    final duration = await _typicalDuration(kind);
    if (duration != null) notes.add(duration);

    return Guidance(
      kind: kind,
      steps: GuidanceContent.stepsFor(kind),
      avoid: GuidanceContent.avoidFor(kind),
      personalNotes: notes,
    );
  }

  /// "You have rated X as helping 4 of the 6 times you tried it."
  ///
  /// States the numbers it came from, so the reader can check it against what
  /// they already believe. "Cold compresses work for you" is not something
  /// anyone can check.
  Future<String?> _bestReliever(EpisodeKind kind) async {
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
      LIMIT 1
      ''',
      [kind.code, minRatedAttempts],
    );
    if (rows.isEmpty) return null;

    final row = rows.single;
    final rated = (row['rated']! as int);
    final helped = (row['helped'] as num?)?.toInt() ?? 0;
    if (helped / rated < minHelpedShare) return null;

    final label = Relievers.labelFor(row['code']! as String);
    return 'You have rated "$label" as helping $helped of the $rated times '
        'you tried it.';
  }

  /// "Your last 5 ended within about 4h."
  ///
  /// The median, not the mean. One 40-hour episode would drag a mean into
  /// something that describes none of them, and the point of the sentence is
  /// to tell someone roughly how long they are likely to be in this.
  Future<String?> _typicalDuration(EpisodeKind kind) async {
    final rows = await _db.rawQuery(
      '''
      SELECT (ended_at - started_at) AS ms
      FROM episodes
      WHERE kind = ? AND ended_at IS NOT NULL
      ORDER BY started_at DESC
      LIMIT 10
      ''',
      [kind.code],
    );
    if (rows.length < minEpisodesForDuration) return null;

    final durations = rows.map((r) => r['ms']! as int).toList()..sort();
    final mid = durations.length ~/ 2;
    final medianMs = durations.length.isOdd
        ? durations[mid]
        : (durations[mid - 1] + durations[mid]) ~/ 2;

    final median = Duration(milliseconds: medianMs);
    if (median.inMinutes < 1) return null;

    final text = median.inHours >= 1
        ? '${median.inHours}h'
        : '${median.inMinutes} minutes';
    // "Half of" rather than "on average": this is a median, and describing a
    // median as an average is a different claim about the same number.
    return 'Half of your last ${durations.length} were over within about '
        '$text.';
  }
}

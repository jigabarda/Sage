import 'package:sqflite/sqflite.dart';

import '../../constants/episode_kind.dart';
import '../../constants/triggers.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../models/episode.dart';

/// Every read and write of `episodes` and its child tables.
///
/// Two invariants live here rather than at call sites, because a screen that
/// forgets one produces data the correlation engine will quietly mis-read:
///
/// - **`started_day` is always derived from `started_at`.** It is denormalised
///   for the Phase 3 joins and must never be passed in. Editing an episode's
///   start time moves its day with it.
/// - **An episode and its children are written in one transaction.** A crash
///   between the parent insert and the symptom rows would leave an episode
///   that claims no symptoms, which is indistinguishable from one that truly
///   had none.
class EpisodeRepository {
  EpisodeRepository(this._db);

  final Database _db;

  /// Starts an episode that is happening right now.
  ///
  /// One row, no children, immediately committed. This is the path taken by
  /// someone who is in pain and should not be looking at a form — the point is
  /// to capture an accurate [startedAt] before anything else. Severity defaults
  /// to [Severity.quickLogDefault] and everything else is filled in later.
  Future<String> startNow(EpisodeKind kind, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    final id = newLocalId('ep');

    await _db.insert('episodes', {
      'id': id,
      'kind': kind.code,
      'started_at': ms,
      'ended_at': null,
      'severity': Severity.quickLogDefault,
      'notes': '',
      'started_day': localDayOf(now),
      'created_at': ms,
      'updated_at': ms,
    });
    return id;
  }

  /// Creates a fully specified episode and its children in one transaction.
  Future<String> create({
    required EpisodeKind kind,
    required DateTime startedAt,
    DateTime? endedAt,
    required int severity,
    String notes = '',
    List<String> symptomCodes = const [],
    List<EpisodeReliever> relievers = const [],
    List<String> userTriggerCodes = const [],
    List<String> medIds = const [],
  }) async {
    _assertSeverity(severity);
    _assertOrder(startedAt, endedAt);

    final id = newLocalId('ep');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
      await txn.insert('episodes', {
        'id': id,
        'kind': kind.code,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'severity': severity,
        'notes': notes,
        'started_day': localDayOf(startedAt),
        'created_at': nowMs,
        'updated_at': nowMs,
      });
      await _writeChildren(
        txn,
        id,
        symptomCodes: symptomCodes,
        relievers: relievers,
        userTriggerCodes: userTriggerCodes,
        medIds: medIds,
        takenAt: startedAt,
      );
    });
    return id;
  }

  /// Replaces an episode and all of its children.
  ///
  /// Children are deleted and rewritten rather than diffed. The sets are a
  /// handful of rows chosen by tapping chips, so a diff would be more code for
  /// no measurable gain — and a partial diff that drops a row is a silent data
  /// loss, where a full rewrite inside a transaction cannot be.
  Future<void> update({
    required String id,
    required EpisodeKind kind,
    required DateTime startedAt,
    DateTime? endedAt,
    required int severity,
    String notes = '',
    List<String> symptomCodes = const [],
    List<EpisodeReliever> relievers = const [],
    List<String> userTriggerCodes = const [],
    List<String> medIds = const [],
  }) async {
    _assertSeverity(severity);
    _assertOrder(startedAt, endedAt);

    await _db.transaction((txn) async {
      await txn.update(
        'episodes',
        {
          'kind': kind.code,
          'started_at': startedAt.millisecondsSinceEpoch,
          'ended_at': endedAt?.millisecondsSinceEpoch,
          'severity': severity,
          'notes': notes,
          // Moved with started_at, never left stale. A Phase 3 rule joining on
          // this would otherwise attribute the episode to the wrong day's
          // sleep.
          'started_day': localDayOf(startedAt),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await txn.delete(
        'episode_symptoms',
        where: 'episode_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'episode_relievers',
        where: 'episode_id = ?',
        whereArgs: [id],
      );
      // Only the user's own attributions are cleared. An inferred row belongs
      // to the correlation engine and is not the editor's to discard.
      await txn.delete(
        'episode_triggers',
        where: 'episode_id = ? AND source = ?',
        whereArgs: [id, TriggerSource.user],
      );

      // Only doses attached to *this* episode. A standalone dose, or one
      // recorded against another episode, is not the editor's to remove.
      await txn.delete('med_doses', where: 'episode_id = ?', whereArgs: [id]);

      await _writeChildren(
        txn,
        id,
        symptomCodes: symptomCodes,
        relievers: relievers,
        userTriggerCodes: userTriggerCodes,
        medIds: medIds,
        takenAt: startedAt,
      );
    });
  }

  /// Marks an ongoing episode as finished.
  Future<void> close(String id, {DateTime? at}) async {
    final end = at ?? DateTime.now();
    final rows = await _db.query(
      'episodes',
      columns: ['started_at'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return;

    final startedAt = DateTime.fromMillisecondsSinceEpoch(
      rows.single['started_at']! as int,
    );
    _assertOrder(startedAt, end);

    await _db.update(
      'episodes',
      {
        'ended_at': end.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Re-opens a closed episode.
  ///
  /// Exists because closing is one tap and therefore easy to do by accident,
  /// and an episode that is still going but recorded as over corrupts both its
  /// own duration and every duration average built on it.
  Future<void> reopen(String id) async {
    await _db.update(
      'episodes',
      {'ended_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    // Children go with it via ON DELETE CASCADE; a medication dose only has
    // its link nulled, because the dose still happened.
    await _db.delete('episodes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setSeverity(String id, int severity) async {
    _assertSeverity(severity);
    await _db.update(
      'episodes',
      {
        'severity': severity,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Newest first.
  Future<List<Episode>> recent({int limit = 100}) async {
    final rows = await _db.query(
      'episodes',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(Episode.fromRow).toList(growable: false);
  }

  /// Every episode that has not been closed, newest first.
  ///
  /// Usually zero or one. More than one is possible and legitimate — a
  /// migraine and reflux can overlap — so this returns a list rather than
  /// pretending there is only ever one.
  Future<List<Episode>> ongoing() async {
    final rows = await _db.query(
      'episodes',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
    );
    return rows.map(Episode.fromRow).toList(growable: false);
  }

  Future<Episode?> byId(String id) async {
    final rows = await _db.query(
      'episodes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Episode.fromRow(rows.single);
  }

  Future<EpisodeDetail?> detailById(String id) async {
    final episode = await byId(id);
    if (episode == null) return null;

    final symptoms = await _db.query(
      'episode_symptoms',
      where: 'episode_id = ?',
      whereArgs: [id],
    );
    final relievers = await _db.query(
      'episode_relievers',
      where: 'episode_id = ?',
      whereArgs: [id],
      orderBy: 'taken_at ASC',
    );
    final triggers = await _db.query(
      'episode_triggers',
      where: 'episode_id = ?',
      whereArgs: [id],
    );
    final doses = await _db.query(
      'med_doses',
      columns: ['med_id'],
      where: 'episode_id = ?',
      whereArgs: [id],
    );

    return EpisodeDetail(
      episode: episode,
      symptomCodes: symptoms
          .map((r) => r['symptom_code']! as String)
          .toList(growable: false),
      relievers: relievers.map(EpisodeReliever.fromRow).toList(growable: false),
      triggers: triggers.map(EpisodeTrigger.fromRow).toList(growable: false),
      medIds: doses.map((r) => r['med_id']! as String).toList(growable: false),
    );
  }

  /// The most recent reliever the user rated as having helped, for [kind].
  ///
  /// Feeds the Phase 1 "last time, this helped" line. Deliberately *not* a
  /// pattern claim — it is one remembered fact about one previous episode, and
  /// the wording at the call site has to stay that modest. Aggregate claims
  /// about what usually helps are a Phase 3 rule with an evidence gate.
  Future<String?> lastThingThatHelped(EpisodeKind kind) async {
    final rows = await _db.rawQuery(
      '''
      SELECT r.reliever_code
      FROM episode_relievers r
      JOIN episodes e ON e.id = r.episode_id
      WHERE e.kind = ? AND r.helped = 1
      ORDER BY r.taken_at DESC
      LIMIT 1
      ''',
      [kind.code],
    );
    return rows.isEmpty ? null : rows.single['reliever_code'] as String?;
  }

  Future<void> _writeChildren(
    DatabaseExecutor txn,
    String episodeId, {
    required List<String> symptomCodes,
    required List<EpisodeReliever> relievers,
    required List<String> userTriggerCodes,
    required List<String> medIds,
    required DateTime takenAt,
  }) async {
    for (final code in symptomCodes.toSet()) {
      await txn.insert('episode_symptoms', {
        'episode_id': episodeId,
        'symptom_code': code,
      });
    }
    for (final r in relievers) {
      await txn.insert(
        'episode_relievers',
        {
          'episode_id': episodeId,
          'reliever_code': r.relieverCode,
          'taken_at': r.takenAt.millisecondsSinceEpoch,
          'helped': r.helped,
        },
        // The primary key is (episode, reliever, taken_at). Two taps a second
        // apart are two genuine attempts; two taps in the same millisecond are
        // a double-tap, and replacing is the right answer to that.
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final code in userTriggerCodes.toSet()) {
      await txn.insert('episode_triggers', {
        'episode_id': episodeId,
        'trigger_code': code,
        'source': TriggerSource.user,
      });
    }
    for (final medId in medIds.toSet()) {
      // taken_at is the episode's start rather than 'now', so editing an
      // episode a week later does not record the dose as happening then -
      // which would move it into the wrong day for the rescue-use count.
      await txn.insert('med_doses', {
        'id': newLocalId('dose'),
        'med_id': medId,
        'taken_at': takenAt.millisecondsSinceEpoch,
        'episode_id': episodeId,
      });
    }
  }

  static void _assertSeverity(int severity) {
    if (!Severity.isValid(severity)) {
      throw ArgumentError.value(
        severity,
        'severity',
        'must be ${Severity.min}-${Severity.max}',
      );
    }
  }

  static void _assertOrder(DateTime startedAt, DateTime? endedAt) {
    if (endedAt != null && endedAt.isBefore(startedAt)) {
      // Rejected rather than silently swapped: an episode that ends before it
      // starts produces a negative duration, and a negative duration averaged
      // into a Phase 3 rule is worse than a missing one.
      throw ArgumentError('endedAt must not be before startedAt');
    }
  }
}

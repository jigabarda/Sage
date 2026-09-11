import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../models/med.dart';

/// Medications, and the record of when they were taken.
class MedsRepository {
  MedsRepository(this._db);

  final Database _db;

  Future<List<Med>> all({bool includeInactive = true}) async {
    final rows = await _db.query(
      'meds',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'active DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(Med.fromRow).toList(growable: false);
  }

  Future<List<Med>> active(MedKind kind) async {
    final rows = await _db.query(
      'meds',
      where: 'active = 1 AND kind = ?',
      whereArgs: [kind.code],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Med.fromRow).toList(growable: false);
  }

  Future<Med?> byId(String id) async {
    final rows = await _db.query(
      'meds',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Med.fromRow(rows.single);
  }

  /// The window every intake figure is reported over.
  ///
  /// Rolling rather than calendar. A limit expressed as "ten days a month"
  /// resets mentally on the 1st, and a calendar window would hand someone a
  /// clean slate on a date that means nothing physiologically — hiding exactly
  /// the sustained pattern this is for.
  static const windowDays = 30;

  Future<String> create({
    required String name,
    String doseText = '',
    required MedKind kind,
    int? monthlyLimitDays,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final id = newLocalId('med');
    await _db.insert('meds', {
      'id': id,
      'name': trimmed,
      // Stored exactly as typed. The app never parses, normalises or checks a
      // dose - see the note on Med.
      'dose_text': doseText.trim(),
      'kind': kind.code,
      'active': 1,
      // Null unless the person gave one. The app never invents a limit.
      'monthly_limit_days': monthlyLimitDays,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    required String doseText,
    required MedKind kind,
    required bool active,
    int? monthlyLimitDays,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    await _db.update(
      'meds',
      {
        'name': trimmed,
        'dose_text': doseText.trim(),
        'kind': kind.code,
        'active': active ? 1 : 0,
        'monthly_limit_days': monthlyLimitDays,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Stops offering a medication without erasing what was taken.
  ///
  /// The route the UI takes for "I don't take this any more". Deleting instead
  /// would cascade `med_doses` away, rewriting a history the person may be
  /// showing a doctor.
  Future<void> deactivate(String id) =>
      _db.update('meds', {'active': 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> reactivate(String id) =>
      _db.update('meds', {'active': 1}, where: 'id = ?', whereArgs: [id]);

  /// Removes a medication **and every dose of it**.
  ///
  /// Only for something entered by mistake. The UI names the consequence and
  /// offers [deactivate] first.
  Future<void> delete(String id) =>
      _db.delete('meds', where: 'id = ?', whereArgs: [id]);

  /// Records a dose taken on its own, with no episode attached.
  ///
  /// The gap Phase 9 left: a preventive taken every morning, or a rescue taken
  /// without logging an attack, previously had nowhere to go. Intake figures
  /// built only from episode-linked doses undercount by however much someone
  /// does not feel like logging.
  Future<String> recordDose(String medId, {DateTime? at}) async {
    final id = newLocalId('dose');
    await _db.insert('med_doses', {
      'id': id,
      'med_id': medId,
      'taken_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      'episode_id': null,
    });
    return id;
  }

  Future<void> deleteDose(String doseId) =>
      _db.delete('med_doses', where: 'id = ?', whereArgs: [doseId]);

  /// Doses of one medication, newest first.
  Future<List<MedDose>> dosesFor(String medId, {int limit = 200}) async {
    final rows = await _db.query(
      'med_doses',
      where: 'med_id = ?',
      whereArgs: [medId],
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    return rows.map(MedDose.fromRow).toList(growable: false);
  }

  /// Every dose across all medications, newest first.
  Future<List<MedDose>> recentDoses({int limit = 200}) async {
    final rows = await _db.query(
      'med_doses',
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    return rows.map(MedDose.fromRow).toList(growable: false);
  }

  /// Intake over the last [windowDays] for every medication that has any.
  ///
  /// Inactive medications are included when they have doses in the window —
  /// stopping something last week does not remove it from this month's
  /// picture.
  Future<List<MedIntake>> intake({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final from = startOfDay(
      localDayOf(at) - (windowDays - 1),
    ).millisecondsSinceEpoch;

    final out = <MedIntake>[];
    for (final med in await all()) {
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS doses,'
        ' COUNT(DISTINCT CAST((taken_at - ?) / 86400000 AS INTEGER)) AS days,'
        ' MAX(taken_at) AS last'
        ' FROM med_doses WHERE med_id = ? AND taken_at >= ?',
        [from, med.id, from],
      );
      final r = rows.single;
      final doses = (r['doses'] as int?) ?? 0;
      if (doses == 0 && !med.active) continue;

      final last = r['last'] as int?;
      out.add(
        MedIntake(
          med: med,
          doses: doses,
          days: (r['days'] as int?) ?? 0,
          windowDays: windowDays,
          lastTaken: last == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(last),
        ),
      );
    }
    return out;
  }

  Future<int> doseCount(String medId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM med_doses WHERE med_id = ?',
      [medId],
    );
    return (rows.single['n'] as int?) ?? 0;
  }

  /// The medication ids recorded against one episode.
  Future<List<String>> medIdsForEpisode(String episodeId) async {
    final rows = await _db.query(
      'med_doses',
      columns: ['med_id'],
      where: 'episode_id = ?',
      whereArgs: [episodeId],
    );
    return rows.map((r) => r['med_id']! as String).toList(growable: false);
  }

  /// Distinct days in the last [days] on which a rescue medication was taken.
  ///
  /// **A count, and nothing else.** How many days of rescue use is too many is
  /// a clinical question with different answers for different drugs, and this
  /// app has no business having a view on it. The insight built from this
  /// states the number and stops; the reader can take it to someone qualified
  /// to interpret it.
  Future<int> rescueDaysInLast(int days, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final from = startOfDay(localDayOf(at) - (days - 1)).millisecondsSinceEpoch;
    final rows = await _db.rawQuery(
      '''
      SELECT COUNT(DISTINCT CAST((d.taken_at - ?) / 86400000 AS INTEGER)) AS n
      FROM med_doses d
      JOIN meds m ON m.id = d.med_id
      WHERE m.kind = 'rescue' AND d.taken_at >= ?
      ''',
      [from, from],
    );
    return (rows.single['n'] as int?) ?? 0;
  }

  /// Whether there is enough history for [rescueDaysInLast] to mean anything.
  ///
  /// "3 of the last 30 days" is misleading when the app has only been in use
  /// for a week: the denominator implies a window that was never observed.
  Future<bool> hasHistoryFor(int days, {DateTime? now}) async {
    final rows = await _db.rawQuery(
      'SELECT MIN(d) AS first FROM ('
      ' SELECT MIN(started_day) AS d FROM episodes'
      ' UNION ALL SELECT MIN(local_day) FROM daily_log'
      ')',
    );
    final first = rows.single['first'] as int?;
    if (first == null) return false;
    return localDayOf(now ?? DateTime.now()) - first >= days - 1;
  }
}

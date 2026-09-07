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

  Future<String> create({
    required String name,
    String doseText = '',
    required MedKind kind,
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

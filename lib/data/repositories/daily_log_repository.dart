import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../models/daily_log.dart';

/// Reads and writes `daily_log`, one row per local day.
class DailyLogRepository {
  DailyLogRepository(this._db);

  final Database _db;

  /// The day's row, or an empty one if it has never been filled in.
  ///
  /// Returns [DailyLog.empty] rather than null so the entry screen has
  /// something to bind to without every field being a null check. The
  /// difference still survives: an empty log has every measure null, which is
  /// exactly what the rules read as "not recorded".
  Future<DailyLog> forDay(LocalDay day) async {
    final rows = await _db.query(
      'daily_log',
      where: 'local_day = ?',
      whereArgs: [day],
      limit: 1,
    );
    return rows.isEmpty ? DailyLog.empty(day) : DailyLog.fromRow(rows.single);
  }

  Future<DailyLog> today() => forDay(localDayOf(DateTime.now()));

  /// Writes the whole row.
  ///
  /// `ConflictAlgorithm.replace` rather than an update, because the row may
  /// not exist yet and the screen always holds a complete picture of the day.
  /// A partial update would need the caller to know which fields it owns,
  /// which is how a cleared field ends up not actually clearing.
  Future<void> save(DailyLog log) async {
    if (log.isEmpty) {
      // Nothing recorded means no row. An all-null row and a missing row read
      // the same to every rule, and keeping the table free of them makes
      // "days actually logged" a straight COUNT.
      await _db.delete(
        'daily_log',
        where: 'local_day = ?',
        whereArgs: [log.day],
      );
      return;
    }
    await _db.insert(
      'daily_log',
      log.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Every logged day in the window, oldest first. Days never filled in are
  /// simply absent — callers must not treat a gap as a zero.
  Future<List<DailyLog>> between(LocalDay from, LocalDay to) async {
    final rows = await _db.query(
      'daily_log',
      where: 'local_day >= ? AND local_day <= ?',
      whereArgs: [from, to],
      orderBy: 'local_day ASC',
    );
    return rows.map(DailyLog.fromRow).toList(growable: false);
  }

  /// How many days in the window have any entry at all.
  ///
  /// The coverage gate in `InsightsService` reads this: rules that compare
  /// days against each other are meaningless when only a handful of days were
  /// ever filled in.
  Future<int> loggedDayCount(LocalDay from, LocalDay to) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM daily_log WHERE local_day >= ? AND local_day <= ?',
      [from, to],
    );
    return (rows.single['n'] as int?) ?? 0;
  }

  /// Days recorded as the first day of a period (`cycle_day = 1`).
  ///
  /// The only thing the cycle rule and the day-number suggestion are built
  /// from — nobody is asked to work out that today is day 14.
  Future<List<LocalDay>> periodStarts() async {
    final rows = await _db.rawQuery(
      'SELECT local_day FROM daily_log WHERE cycle_day = 1 ORDER BY local_day',
    );
    return rows.map((r) => r['local_day']! as int).toList(growable: false);
  }

  /// The most recent day with any entry, or null if the table is empty.
  Future<LocalDay?> lastLoggedDay() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(local_day) AS d FROM daily_log',
    );
    return rows.single['d'] as int?;
  }
}

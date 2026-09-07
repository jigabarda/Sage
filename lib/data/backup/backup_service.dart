import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/sage_database.dart';

/// Thrown when a file cannot be restored. The message is shown to the user, so
/// it says what is wrong rather than what threw.
class BackupError implements Exception {
  BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a backup file contains, for the confirmation screen.
class BackupSummary {
  const BackupSummary({
    required this.schemaVersion,
    required this.exportedAt,
    required this.counts,
  });

  final int schemaVersion;
  final DateTime? exportedAt;

  /// Rows per table, in the order they are listed to the user.
  final Map<String, int> counts;

  int get episodes => counts['episodes'] ?? 0;
  int get loggedDays => counts['daily_log'] ?? 0;
  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Exports and restores the whole database as one JSON file.
///
/// ## Why this exists, and why it is not the doctor export
///
/// Non-negotiable 4 rules out cloud sync, so there is no server copy of this
/// person's log. That makes losing the phone equivalent to losing years of
/// data, and a manual backup is the only safety net that can exist under that
/// constraint.
///
/// The doctor export is a different artefact and deliberately not a substitute:
/// it is prose written for a human to read, lossy by design, and nothing could
/// reconstruct the database from it.
///
/// ## Restoring is destructive, and that is the honest design
///
/// A restore replaces everything rather than merging. Merging two logs of the
/// same condition would need identity rules nobody can specify — is an episode
/// at 09:00 in both files one episode or two? Getting that wrong silently
/// doubles someone's attack count and corrupts every rate the correlation
/// engine computes. Replacing is blunt, but it is knowable, and the UI says so
/// plainly before doing it.
class BackupService {
  BackupService(this._db);

  final Database _db;

  /// Bumped with `SageDatabase.schemaVersion`, and stamped into every file.
  ///
  /// Kept as its own constant read from the database class rather than a
  /// private copy: Sellora's guide records that a private duplicate of this
  /// number is exactly how the two drifted apart.
  static int get schemaVersion => SageDatabase.schemaVersion;

  /// Parents before children. Foreign keys are enforced during a restore, so
  /// inserting a child first fails outright — this order is load-bearing, not
  /// cosmetic.
  static const insertOrder = <String>[
    'episodes',
    'episode_symptoms',
    'episode_relievers',
    'episode_triggers',
    'daily_log',
    'meds',
    'med_doses',
    'chat_messages',
  ];

  /// The reverse, so a child is gone before the row it points at.
  static List<String> get deleteOrder => insertOrder.reversed.toList();

  String get suggestedFileName {
    String pad(int n) => n.toString().padLeft(2, '0');
    final d = DateTime.now();
    return 'sage-backup-${d.year}-${pad(d.month)}-${pad(d.day)}.json';
  }

  Future<String> export() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in insertOrder) {
      tables[table] = await _db.query(table);
    }
    return const JsonEncoder.withIndent('  ').convert({
      // Identifies the file as ours. A restore checks this before anything
      // else, so picking the wrong JSON from a file manager fails with a
      // sentence rather than a type error.
      'app': 'sage',
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// Parses and validates without writing anything.
  ///
  /// Separate from [restore] so the confirmation screen can say what is in the
  /// file — "1,204 rows over 143 episodes" — before someone agrees to replace
  /// what they have.
  BackupSummary inspect(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw BackupError('That file is not readable as a Sage backup.');
    }
    if (decoded is! Map<String, Object?>) {
      throw BackupError('That file is not readable as a Sage backup.');
    }
    if (decoded['app'] != 'sage') {
      throw BackupError('That file was not made by Sage.');
    }

    final version = decoded['schemaVersion'];
    if (version is! int) {
      throw BackupError('That backup has no version and cannot be restored.');
    }
    if (version > schemaVersion) {
      // A file from a newer build may carry columns this one has never heard
      // of. Refusing is the only safe answer: silently dropping them would
      // lose data the user believes they have backed up.
      throw BackupError(
        'That backup was made by a newer version of Sage (format $version, '
        'this build reads $schemaVersion). Update the app first.',
      );
    }

    final tables = decoded['tables'];
    if (tables is! Map<String, Object?>) {
      throw BackupError('That backup has no data in it.');
    }

    final counts = <String, int>{};
    for (final table in insertOrder) {
      final rows = tables[table];
      counts[table] = rows is List ? rows.length : 0;
    }

    return BackupSummary(
      schemaVersion: version,
      exportedAt: DateTime.tryParse(decoded['exportedAt'] as String? ?? ''),
      counts: counts,
    );
  }

  /// Replaces the entire database with the contents of [json].
  ///
  /// One transaction: either the whole backup lands or nothing changes. A
  /// half-applied restore — old episodes deleted, new ones not yet written —
  /// would be the single worst outcome this app could produce.
  Future<BackupSummary> restore(String json) async {
    final summary = inspect(json);
    final tables =
        (jsonDecode(json) as Map<String, Object?>)['tables']
            as Map<String, Object?>;

    // The columns this build actually has, so a backup from an older schema
    // can still be read: unknown keys are dropped and missing columns take
    // their schema default. That covers additive migrations, which is what
    // almost all of them are. A migration that *renames* or *repurposes* a
    // column needs handling here explicitly — see the guide.
    final columns = <String, Set<String>>{};
    for (final table in insertOrder) {
      final info = await _db.rawQuery('PRAGMA table_info($table)');
      columns[table] = info.map((r) => r['name']! as String).toSet();
    }

    await _db.transaction((txn) async {
      for (final table in deleteOrder) {
        await txn.delete(table);
      }
      for (final table in insertOrder) {
        final rows = tables[table];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          final known = <String, Object?>{};
          for (final entry in row.entries) {
            final key = entry.key;
            if (key is String && columns[table]!.contains(key)) {
              known[key] = entry.value;
            }
          }
          if (known.isEmpty) continue;
          await txn.insert(table, known);
        }
      }
    });

    return summary;
  }
}

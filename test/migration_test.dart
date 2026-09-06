import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives the database through the real production open path.
///
/// Every test here opens a temp file with [SageDatabase.openOptions] rather
/// than calling `createSchema`/`migrate` directly. That is the whole point:
/// the foreign-keys OFF/ON pragma sequence lives in `openOptions`, and a test
/// that bypasses it proves nothing about whether an upgrade is safe.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sage_migration_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<Database> openFresh() => databaseFactory.openDatabase(
    '${dir.path}/sage.db',
    options: SageDatabase.openOptions(),
  );

  Future<Set<String>> tablesIn(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((r) => r['name']! as String).toSet();
  }

  test('a fresh install creates every table at the current version', () async {
    final db = await openFresh();
    addTearDown(db.close);

    expect(await db.getVersion(), SageDatabase.schemaVersion);
    expect(
      await tablesIn(db),
      containsAll(<String>[
        'episodes',
        'episode_symptoms',
        'episode_relievers',
        'episode_triggers',
        'daily_log',
        'meds',
        'med_doses',
        'chat_messages',
      ]),
    );
  });

  test(
    'foreign keys are enforced by the time the app sees the database',
    () async {
      final db = await openFresh();
      addTearDown(db.close);

      // The pragma is off during create and must be back on afterwards. If this
      // fails, every ON DELETE rule below is decorative.
      final on = await db.rawQuery('PRAGMA foreign_keys');
      expect(on.first.values.first, 1);
    },
  );

  test('re-opening an existing database is a no-op, not a re-create', () async {
    final first = await openFresh();
    await first.insert('episodes', _episode('ep_keep'));
    await first.close();

    final second = await openFresh();
    addTearDown(second.close);

    final rows = await second.query('episodes');
    expect(rows, hasLength(1), reason: 'existing data must survive re-open');
    expect(rows.single['id'], 'ep_keep');
  });

  test('deleting an episode cascades to its child rows', () async {
    final db = await openFresh();
    addTearDown(db.close);

    await db.insert('episodes', _episode('ep_1'));
    await db.insert('episode_symptoms', {
      'episode_id': 'ep_1',
      'symptom_code': 'photophobia',
    });
    await db.insert('episode_triggers', {
      'episode_id': 'ep_1',
      'trigger_code': 'short_sleep',
      'source': 'user',
    });

    await db.delete('episodes', where: 'id = ?', whereArgs: ['ep_1']);

    expect(await db.query('episode_symptoms'), isEmpty);
    expect(await db.query('episode_triggers'), isEmpty);
  });

  test('deleting an episode does not erase a dose that was taken', () async {
    final db = await openFresh();
    addTearDown(db.close);

    await db.insert('episodes', _episode('ep_1'));
    await db.insert('meds', {
      'id': 'med_1',
      'name': 'Ibuprofen',
      'dose_text': 'whatever the user typed',
      'kind': 'rescue',
      'active': 1,
      'created_at': 0,
    });
    await db.insert('med_doses', {
      'id': 'dose_1',
      'med_id': 'med_1',
      'taken_at': 1000,
      'episode_id': 'ep_1',
    });

    await db.delete('episodes', where: 'id = ?', whereArgs: ['ep_1']);

    // SET NULL, not CASCADE. The dose happened; only its link to an episode
    // goes away.
    final doses = await db.query('med_doses');
    expect(doses, hasLength(1));
    expect(doses.single['episode_id'], isNull);
  });

  test('an unrecorded daily_log measure stays null, never zero', () async {
    final db = await openFresh();
    addTearDown(db.close);

    await db.insert('daily_log', {
      'local_day': 20000,
      'sleep_hours': 5.5,
      'updated_at': 0,
    });

    final row = (await db.query('daily_log')).single;
    expect(row['sleep_hours'], 5.5);
    // A correlation rule has to tell "not recorded" apart from "recorded as
    // none". A DEFAULT 0 here would silently turn every unlogged day into a
    // day with no stress and no caffeine.
    expect(row['stress_level'], isNull);
    expect(row['caffeine_units'], isNull);
    expect(row['late_meal'], isNull);
  });
}

Map<String, Object?> _episode(String id) => {
  'id': id,
  'kind': 'migraine',
  'started_at': 1700000000000,
  'ended_at': null,
  'severity': 6,
  'notes': '',
  'started_day': 19675,
  'created_at': 1700000000000,
  'updated_at': 1700000000000,
};

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

  group('v1 to v2', () {
    /// A v1 `meds` table: everything the current one has except
    /// monthly_limit_days, which v2 adds.
    Future<Database> openV1() => databaseFactory.openDatabase(
      '${dir.path}/sage.db',
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = OFF'),
        onCreate: (db, _) async {
          await SageDatabase.createSchema(db);
          // Rebuild `meds` as it was at v1, so the upgrade has something real
          // to alter rather than a table that already has the column.
          await db.execute('DROP TABLE med_doses');
          await db.execute('DROP TABLE meds');
          await db.execute('''
            CREATE TABLE meds (
              id         TEXT    PRIMARY KEY,
              name       TEXT    NOT NULL,
              dose_text  TEXT    NOT NULL DEFAULT '',
              kind       TEXT    NOT NULL,
              active     INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL
            );
          ''');
          await db.execute('''
            CREATE TABLE med_doses (
              id         TEXT    PRIMARY KEY,
              med_id     TEXT    NOT NULL REFERENCES meds(id) ON DELETE CASCADE,
              taken_at   INTEGER NOT NULL,
              episode_id TEXT    REFERENCES episodes(id) ON DELETE SET NULL
            );
          ''');
        },
        onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );

    test('the upgrade adds the column and keeps every row', () async {
      final v1 = await openV1();
      await v1.insert('episodes', _episode('ep_1'));
      await v1.insert('meds', {
        'id': 'med_1',
        'name': 'Ibuprofen',
        'dose_text': 'two at onset',
        'kind': 'rescue',
        'active': 1,
        'created_at': 1000,
      });
      await v1.insert('med_doses', {
        'id': 'dose_1',
        'med_id': 'med_1',
        'taken_at': 2000,
        'episode_id': 'ep_1',
      });
      await v1.close();

      // Through the production path, so the pragma sequence is what runs.
      final v2 = await openFresh();
      addTearDown(v2.close);

      expect(await v2.getVersion(), SageDatabase.schemaVersion);

      final med = (await v2.query('meds')).single;
      expect(med['name'], 'Ibuprofen');
      expect(med['dose_text'], 'two at onset');
      // Added by the migration, and null rather than 0: no limit set is not a
      // limit of zero, and the app must never invent one.
      expect(med['monthly_limit_days'], isNull);

      expect(await v2.query('med_doses'), hasLength(1));
      expect(await v2.query('episodes'), hasLength(1));
    });

    test('the upgrade does not cascade anything away', () async {
      // The pragma sequence exists for this. If foreign keys were on during
      // the upgrade, a table rebuild would take the children with it.
      final v1 = await openV1();
      await v1.insert('episodes', _episode('ep_1'));
      await v1.insert('episode_symptoms', {
        'episode_id': 'ep_1',
        'symptom_code': 'nausea',
      });
      await v1.close();

      final v2 = await openFresh();
      addTearDown(v2.close);
      expect(await v2.query('episode_symptoms'), hasLength(1));
    });

    test('a fresh install is not put through the v2 step', () async {
      // createSchema already declares monthly_limit_days, so an unguarded
      // ALTER would fail on a duplicate column for a brand-new database.
      final db = await openFresh();
      addTearDown(db.close);
      final info = await db.rawQuery('PRAGMA table_info(meds)');
      final columns = info.map((r) => r['name']).toList();
      expect(columns, contains('monthly_limit_days'));
      expect(columns.where((c) => c == 'monthly_limit_days'), hasLength(1));
    });
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

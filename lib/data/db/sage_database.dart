import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// The local SQLite database. Every read and write works offline; there is no
/// server copy of any of this.
///
/// Unlike Sellora there is no `user_id` or `business_id` scoping anywhere —
/// one person, one device, one dataset. Do not add a scope column "for later";
/// a sync layer, if it ever arrives, layers on top rather than reshaping this.
class SageDatabase {
  SageDatabase._();

  static const _fileName = 'sage.db';

  /// The schema this build creates and migrates to.
  ///
  /// Public because the export format has to stamp it into every file. Sellora
  /// learned that a private copy of this number is exactly how the two drift
  /// apart: a comment asks whoever bumps one to bump the other, and eventually
  /// nobody does.
  static const schemaVersion = 2;

  static Future<Database> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    return databaseFactory.openDatabase(path, options: openOptions());
  }

  /// How the app opens its database.
  ///
  /// Extracted so the migration test can upgrade a real file through the exact
  /// production path. Calling [migrate] directly cannot prove an upgrade is
  /// safe, because the pragma sequence below is the entire safety mechanism.
  static OpenDatabaseOptions openOptions() {
    return OpenDatabaseOptions(
      version: schemaVersion,
      // Foreign keys are deliberately OFF here and switched back ON in
      // `onOpen`.
      //
      // A migration that changes a table's shape has to rebuild it, and with
      // enforcement on, dropping a parent table performs an implicit delete of
      // every row — which fires the children's ON DELETE CASCADE and takes the
      // data with it. SQLite's own documented rebuild procedure requires the
      // pragma off for exactly this reason, and it cannot be toggled from
      // inside `onUpgrade`, where sqflite's transaction makes the statement a
      // silent no-op. The window is only ever open during create and upgrade;
      // the app itself never sees an unenforced database.
      //
      // This is carried over from Sellora almost verbatim, and is one of the
      // two things the guide says to lift rather than rewrite. It is not
      // stylistic.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => migrate(db, oldVersion),
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Brings a database created by an older release up to [schemaVersion].
  ///
  /// Public so tests can drive it against a hand-built old schema; there is no
  /// other way to exercise an upgrade path without an on-device file.
  ///
  /// Every schema change adds a case here that upgrades from *each* still
  /// plausible old version, not just the newest. Two traps Sellora hit and
  /// this will hit too:
  ///
  /// - Do not index a column in [createSchema] that a later migration step
  ///   adds. `createSchema` runs for a fresh install, before those steps.
  /// - Guard an `ALTER` that a `CREATE TABLE` in an earlier step already
  ///   covers, or a v1 install fails on a duplicate column.
  static Future<void> migrate(Database db, int oldVersion) async {
    if (oldVersion < 1) {
      await createSchema(db);
    }
    // Guarded on oldVersion >= 1: anything older had `meds` created a moment
    // ago by `createSchema`, which already declares the column. ALTERing again
    // would fail on a duplicate.
    if (oldVersion >= 1 && oldVersion < 2) {
      await db.execute(
        'ALTER TABLE meds ADD COLUMN monthly_limit_days INTEGER',
      );
    }
    // Next migration goes here as `if (oldVersion >= 2 && oldVersion < 3)`,
    // together with a case in test/migration_test.dart driving each still
    // plausible old version forward through openOptions() against a real
    // temp file.
  }

  /// Creates the current schema from nothing.
  ///
  /// Timestamps are epoch milliseconds. Day-valued columns are local day
  /// numbers (see `lib/core/dates.dart`) and are never timestamps.
  static Future<void> createSchema(Database db) async {
    await _createEpisodes(db);
    await _createDailyLog(db);
    await _createMeds(db);
    await _createChat(db);
  }

  static Future<void> _createEpisodes(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS episodes (
        id          TEXT    PRIMARY KEY,
        kind        TEXT    NOT NULL,
        started_at  INTEGER NOT NULL,
        ended_at    INTEGER,
        severity    INTEGER NOT NULL,
        notes       TEXT    NOT NULL DEFAULT '',
        -- Local day number for started_at, denormalised so the correlation
        -- rules can join episodes to daily_log without recomputing a local day
        -- for every row on every pass. Written by the repository from
        -- started_at; never set by hand, and never a timestamp.
        started_day INTEGER NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_started_at ON episodes(started_at);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_started_day ON episodes(started_day);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_kind ON episodes(kind);',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS episode_symptoms (
        episode_id   TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
        symptom_code TEXT NOT NULL,
        PRIMARY KEY (episode_id, symptom_code)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS episode_relievers (
        episode_id     TEXT    NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
        reliever_code  TEXT    NOT NULL,
        taken_at       INTEGER NOT NULL,
        helped         INTEGER,
        PRIMARY KEY (episode_id, reliever_code, taken_at)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS episode_triggers (
        episode_id   TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
        trigger_code TEXT NOT NULL,
        source       TEXT NOT NULL,
        PRIMARY KEY (episode_id, trigger_code)
      );
    ''');
  }

  static Future<void> _createDailyLog(Database db) async {
    // local_day is a day number, not a timestamp. Primary key because there is
    // exactly one row per day and an upsert on it is the whole write path.
    //
    // Every measure is nullable on purpose: a missing value means "not
    // recorded", which a correlation rule must be able to tell apart from a
    // recorded zero. Defaulting these to 0 would silently convert every
    // unlogged day into a day with no sleep and no stress.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_log (
        local_day     INTEGER PRIMARY KEY,
        sleep_hours   REAL,
        stress_level  INTEGER,
        meals_skipped INTEGER,
        caffeine_units INTEGER,
        alcohol_units INTEGER,
        water_glasses INTEGER,
        late_meal     INTEGER,
        cycle_day     INTEGER,
        updated_at    INTEGER NOT NULL
      );
    ''');
  }

  static Future<void> _createMeds(Database db) async {
    // dose_text is free text the user typed. The app never suggests, completes
    // or validates a dose — see non-negotiable 6 in the guide.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meds (
        id         TEXT    PRIMARY KEY,
        name       TEXT    NOT NULL,
        dose_text  TEXT    NOT NULL DEFAULT '',
        kind       TEXT    NOT NULL,
        active     INTEGER NOT NULL DEFAULT 1,
        -- Days per month the person is aiming to stay under. NULL means no
        -- limit set, which is different from a limit of zero.
        --
        -- The app never fills this in. A number here came from the user or
        -- from what their doctor told them, and the app only counts against
        -- it - see the note on Med.monthlyLimitDays.
        monthly_limit_days INTEGER,
        created_at INTEGER NOT NULL
      );
    ''');

    // ON DELETE SET NULL rather than CASCADE: deleting an episode must not
    // erase the record that a dose was taken. The dose happened.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS med_doses (
        id         TEXT    PRIMARY KEY,
        med_id     TEXT    NOT NULL REFERENCES meds(id) ON DELETE CASCADE,
        taken_at   INTEGER NOT NULL,
        episode_id TEXT    REFERENCES episodes(id) ON DELETE SET NULL
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_med_doses_taken_at ON med_doses(taken_at);',
    );
  }

  static Future<void> _createChat(Database db) async {
    // `tier` records which layer produced an assistant message: 'triage',
    // 'template' or 'online'. Provenance is not decoration — a triage fire has
    // to be visible in the doctor export, and an online answer has to be
    // distinguishable from a deterministic one after the fact.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id         TEXT    PRIMARY KEY,
        role       TEXT    NOT NULL,
        content    TEXT    NOT NULL,
        tier       TEXT,
        episode_id TEXT    REFERENCES episodes(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_created_at ON chat_messages(created_at);',
    );
  }
}

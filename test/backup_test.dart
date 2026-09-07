import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/backup/backup_service.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/models/daily_log.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/daily_log_repository.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sage/data/triage/triage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late BackupService backup;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );
    backup = BackupService(db);
  });

  tearDown(() => db.close());

  /// Something in every table, including the child rows and the foreign keys
  /// that make insert order matter.
  Future<void> seed() async {
    final episodes = EpisodeRepository(db);
    final daily = DailyLogRepository(db);
    final triage = TriageService(db);

    await db.insert('meds', {
      'id': 'med_1',
      'name': 'Ibuprofen',
      'dose_text': 'two at onset',
      'kind': 'rescue',
      'active': 1,
      'created_at': 1000,
    });

    for (var i = 1; i <= 3; i++) {
      final at = DateTime(2026, 9, i, 9);
      final id = await episodes.create(
        kind: i.isEven ? EpisodeKind.reflux : EpisodeKind.migraine,
        startedAt: at,
        endedAt: at.add(const Duration(hours: 3)),
        severity: 5 + i,
        notes: 'note $i with a "quote" and a \\ backslash',
        symptomCodes: const ['nausea'],
        userTriggerCodes: const ['stress'],
        relievers: [
          EpisodeReliever(
            relieverCode: 'water',
            takenAt: at.add(const Duration(minutes: 10)),
            helped: i == 1 ? 1 : null,
          ),
        ],
      );
      await db.insert('med_doses', {
        'id': 'dose_$i',
        'med_id': 'med_1',
        'taken_at': at.millisecondsSinceEpoch,
        'episode_id': id,
      });
      await daily.save(
        DailyLog(
          day: localDayOf(at),
          sleepHours: 5.5,
          stressLevel: 4,
          lateMeal: i.isEven,
          updatedAt: DateTime.now(),
        ),
      );
    }
    await triage.record(triage.evaluate({'thunderclap'}));
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in BackupService.insertOrder) {
      out[t] = await db.query(t, orderBy: 'rowid');
    }
    return out;
  }

  group('round trip', () {
    test('every row comes back exactly as it went in', () async {
      await seed();
      final before = await snapshot();
      final json = await backup.export();

      // Wipe by restoring an empty backup, so the restore path itself does the
      // clearing rather than a hand-written DELETE the app never runs.
      await backup.restore(
        jsonEncode({
          'app': 'sage',
          'schemaVersion': BackupService.schemaVersion,
          'tables': {for (final t in BackupService.insertOrder) t: []},
        }),
      );
      expect((await snapshot())['episodes'], isEmpty);

      await backup.restore(json);
      expect(await snapshot(), equals(before));
    });

    test('an empty database round-trips without complaint', () async {
      final json = await backup.export();
      await backup.restore(json);
      expect((await snapshot())['episodes'], isEmpty);
    });

    test('child rows survive, which means insert order held', () async {
      await seed();
      final json = await backup.export();
      await backup.restore(json);

      // Foreign keys are enforced during the restore, so if episodes were not
      // written before episode_symptoms this would have thrown rather than
      // arrived empty.
      expect(await db.query('episode_symptoms'), hasLength(3));
      expect(await db.query('med_doses'), hasLength(3));
      expect(await db.query('chat_messages'), hasLength(1));
    });

    test('the file records what the doctor export cannot', () async {
      await seed();
      final json = await backup.export();
      // The doctor export is prose and lossy by design. This one has to be
      // able to rebuild the database, so it carries raw rows.
      expect(json, contains('"schemaVersion"'));
      expect(json, contains('episode_relievers'));
      expect(json, contains('started_day'));
    });
  });

  group('inspect refuses what it cannot safely restore', () {
    test('a file that is not JSON', () {
      expect(
        () => backup.inspect('not json at all'),
        throwsA(isA<BackupError>()),
      );
    });

    test('JSON that is not a Sage backup', () {
      expect(
        () => backup.inspect(jsonEncode({'some': 'other app'})),
        throwsA(
          isA<BackupError>().having(
            (e) => e.message,
            'message',
            contains('not made by Sage'),
          ),
        ),
      );
    });

    test('a backup from a newer build', () {
      // Refusing is the only safe answer: a newer file may carry columns this
      // build has never heard of, and dropping them would lose data the user
      // believes is backed up.
      expect(
        () => backup.inspect(
          jsonEncode({
            'app': 'sage',
            'schemaVersion': BackupService.schemaVersion + 5,
            'tables': <String, Object?>{},
          }),
        ),
        throwsA(
          isA<BackupError>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('a backup with no version', () {
      expect(
        () => backup.inspect(jsonEncode({'app': 'sage', 'tables': {}})),
        throwsA(isA<BackupError>()),
      );
    });

    test('it reports what is in the file without writing anything', () async {
      await seed();
      final json = await backup.export();

      final summary = backup.inspect(json);
      expect(summary.episodes, 3);
      expect(summary.loggedDays, 3);
      expect(summary.total, greaterThan(10));
      expect(summary.exportedAt, isNotNull);

      // Inspecting is read-only. The confirmation screen calls this before the
      // user has agreed to anything.
      expect((await snapshot())['episodes'], hasLength(3));
    });
  });

  group('restore safety', () {
    test('a broken backup leaves the existing log untouched', () async {
      await seed();
      final before = await snapshot();

      // A child pointing at an episode that is not in the file. Foreign keys
      // are on, so this fails partway through - after the deletes.
      final broken = jsonEncode({
        'app': 'sage',
        'schemaVersion': BackupService.schemaVersion,
        'tables': {
          for (final t in BackupService.insertOrder) t: <Object?>[],
          'episode_symptoms': [
            {'episode_id': 'nonexistent', 'symptom_code': 'nausea'},
          ],
        },
      });

      await expectLater(backup.restore(broken), throwsA(anything));

      // One transaction: either the whole backup lands or nothing changes. A
      // half-applied restore is the worst outcome this app could produce.
      expect(await snapshot(), equals(before));
    });

    test('columns this build does not have are dropped, not fatal', () async {
      await seed();
      final json = await backup.export();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      final tables = decoded['tables']! as Map<String, Object?>;
      for (final row in tables['episodes']! as List) {
        (row as Map)['a_column_from_some_future_build'] = 'whatever';
      }

      await backup.restore(jsonEncode(decoded));
      expect(await db.query('episodes'), hasLength(3));
    });

    test('a restore replaces rather than merges', () async {
      await seed();
      final json = await backup.export();

      // Log something after the backup was taken.
      await EpisodeRepository(db).create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 20, 9),
        severity: 9,
        notes: 'logged after the backup',
      );
      expect(await db.query('episodes'), hasLength(4));

      await backup.restore(json);

      // Merging would need identity rules nobody can specify, and getting them
      // wrong would silently double someone's attack count. The UI says
      // plainly that this is what happens.
      final rows = await db.query('episodes');
      expect(rows, hasLength(3));
      expect(rows.any((r) => r['notes'] == 'logged after the backup'), isFalse);
    });
  });

  test('the filename is dated', () {
    expect(
      backup.suggestedFileName,
      matches(r'^sage-backup-\d{4}-\d{2}-\d{2}\.json$'),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/constants/triggers.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late EpisodeRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );
    repo = EpisodeRepository(db);
  });

  tearDown(() => db.close());

  group('startNow', () {
    test('records an ongoing episode at the given moment', () async {
      final at = DateTime(2026, 9, 6, 2, 15);
      final id = await repo.startNow(EpisodeKind.migraine, at: at);

      final e = (await repo.byId(id))!;
      expect(e.kind, EpisodeKind.migraine);
      expect(e.startedAt, at);
      expect(e.isOngoing, isTrue);
      expect(e.severity, Severity.quickLogDefault);
    });

    test('derives started_day rather than trusting a caller', () async {
      // 02:00 is the case that breaks if day numbers are computed from UTC:
      // it belongs to the 6th locally, and to the 5th in UTC+8.
      final at = DateTime(2026, 9, 6, 2, 15);
      final id = await repo.startNow(EpisodeKind.migraine, at: at);

      final e = (await repo.byId(id))!;
      expect(e.startedDay, localDayOf(at));
      expect(
        e.startedDay,
        localDayOf(DateTime(2026, 9, 6, 23, 40)),
        reason: 'the whole local day maps to one day number',
      );
    });
  });

  group('create', () {
    test('writes the episode and every child', () async {
      final id = await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        endedAt: DateTime(2026, 9, 5, 13),
        severity: 8,
        notes: 'bad one',
        symptomCodes: ['photophobia', 'nausea'],
        userTriggerCodes: ['short_sleep'],
        relievers: [
          EpisodeReliever(
            relieverCode: 'dark_room',
            takenAt: DateTime(2026, 9, 5, 9, 30),
            helped: 1,
          ),
        ],
      );

      final d = (await repo.detailById(id))!;
      expect(d.episode.severity, 8);
      expect(d.episode.notes, 'bad one');
      expect(d.symptomCodes, containsAll(['photophobia', 'nausea']));
      expect(d.triggers.single.triggerCode, 'short_sleep');
      expect(d.triggers.single.source, TriggerSource.user);
      expect(d.relievers.single.helped, 1);
    });

    test('duplicate symptom codes collapse to one row', () async {
      final id = await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        severity: 4,
        symptomCodes: ['nausea', 'nausea'],
      );
      final d = (await repo.detailById(id))!;
      expect(d.symptomCodes, ['nausea']);
    });

    test('rejects a severity outside the scale', () async {
      expect(
        () => repo.create(
          kind: EpisodeKind.migraine,
          startedAt: DateTime(2026, 9, 5),
          severity: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.create(
          kind: EpisodeKind.migraine,
          startedAt: DateTime(2026, 9, 5),
          severity: 11,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an end before the start', () async {
      // A negative duration averaged into a Phase 3 rule is worse than a
      // missing one, so this fails loudly instead of being swapped.
      expect(
        () => repo.create(
          kind: EpisodeKind.migraine,
          startedAt: DateTime(2026, 9, 5, 12),
          endedAt: DateTime(2026, 9, 5, 11),
          severity: 5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('update', () {
    test('moves started_day when the start time moves', () async {
      final id = await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        severity: 5,
      );

      final moved = DateTime(2026, 9, 8, 9);
      await repo.update(
        id: id,
        kind: EpisodeKind.migraine,
        startedAt: moved,
        severity: 5,
      );

      final e = (await repo.byId(id))!;
      expect(
        e.startedDay,
        localDayOf(moved),
        reason: 'a stale started_day would attribute it to the wrong night',
      );
    });

    test('replaces the user\'s own children', () async {
      final id = await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        severity: 5,
        symptomCodes: ['nausea'],
        userTriggerCodes: ['stress'],
      );

      await repo.update(
        id: id,
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        severity: 6,
        symptomCodes: ['photophobia'],
        userTriggerCodes: ['coffee'],
      );

      final d = (await repo.detailById(id))!;
      expect(d.symptomCodes, ['photophobia']);
      expect(d.triggers.map((t) => t.triggerCode), ['coffee']);
    });

    test('leaves an inferred trigger alone', () async {
      final id = await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        severity: 5,
        userTriggerCodes: ['stress'],
      );
      // Stand-in for what a Phase 3 rule writes.
      await db.insert('episode_triggers', {
        'episode_id': id,
        'trigger_code': 'short_sleep',
        'source': TriggerSource.inferred,
      });

      await repo.update(
        id: id,
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 5, 9),
        severity: 5,
        userTriggerCodes: [],
      );

      final d = (await repo.detailById(id))!;
      // The editor clears beliefs, never arithmetic.
      expect(d.triggers, hasLength(1));
      expect(d.triggers.single.triggerCode, 'short_sleep');
      expect(d.triggers.single.source, TriggerSource.inferred);
    });
  });

  group('close and reopen', () {
    test('close ends it, reopen makes it ongoing again', () async {
      final id = await repo.startNow(
        EpisodeKind.reflux,
        at: DateTime(2026, 9, 6, 20),
      );

      await repo.close(id, at: DateTime(2026, 9, 6, 22));
      var e = (await repo.byId(id))!;
      expect(e.isOngoing, isFalse);
      expect(e.duration, const Duration(hours: 2));

      await repo.reopen(id);
      e = (await repo.byId(id))!;
      expect(e.isOngoing, isTrue);
    });

    test('refuses to close before the start', () async {
      final id = await repo.startNow(
        EpisodeKind.reflux,
        at: DateTime(2026, 9, 6, 20),
      );
      expect(
        () => repo.close(id, at: DateTime(2026, 9, 6, 19)),
        throwsArgumentError,
      );
    });

    test('ongoing() returns only what is still open', () async {
      final open = await repo.startNow(EpisodeKind.migraine);
      final shut = await repo.startNow(EpisodeKind.reflux);
      await repo.close(shut);

      final list = await repo.ongoing();
      expect(list.map((e) => e.id), [open]);
    });
  });

  test('delete removes the episode and its children', () async {
    final id = await repo.create(
      kind: EpisodeKind.migraine,
      startedAt: DateTime(2026, 9, 5, 9),
      severity: 5,
      symptomCodes: ['nausea'],
    );

    await repo.delete(id);

    expect(await repo.byId(id), isNull);
    expect(await db.query('episode_symptoms'), isEmpty);
  });

  test('recent() is newest first', () async {
    await repo.startNow(EpisodeKind.migraine, at: DateTime(2026, 9, 1));
    await repo.startNow(EpisodeKind.migraine, at: DateTime(2026, 9, 4));
    await repo.startNow(EpisodeKind.migraine, at: DateTime(2026, 9, 2));

    final list = await repo.recent();
    expect(list.map((e) => e.startedAt.day), [4, 2, 1]);
  });

  group('lastThingThatHelped', () {
    test('returns the most recent reliever rated as helping', () async {
      await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 1, 9),
        severity: 5,
        relievers: [
          EpisodeReliever(
            relieverCode: 'cold_compress',
            takenAt: DateTime(2026, 9, 1, 10),
            helped: 1,
          ),
        ],
      );
      await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 4, 9),
        severity: 5,
        relievers: [
          EpisodeReliever(
            relieverCode: 'dark_room',
            takenAt: DateTime(2026, 9, 4, 10),
            helped: 1,
          ),
        ],
      );

      expect(await repo.lastThingThatHelped(EpisodeKind.migraine), 'dark_room');
    });

    test('ignores unrated and unhelpful attempts', () async {
      await repo.create(
        kind: EpisodeKind.migraine,
        startedAt: DateTime(2026, 9, 4, 9),
        severity: 5,
        relievers: [
          EpisodeReliever(
            relieverCode: 'waited',
            takenAt: DateTime(2026, 9, 4, 10),
            helped: null,
          ),
          EpisodeReliever(
            relieverCode: 'caffeine',
            takenAt: DateTime(2026, 9, 4, 11),
            helped: 0,
          ),
        ],
      );

      // Unrated is not a weak yes, and "no change" is not a yes at all.
      expect(await repo.lastThingThatHelped(EpisodeKind.migraine), isNull);
    });

    test('does not cross conditions', () async {
      await repo.create(
        kind: EpisodeKind.reflux,
        startedAt: DateTime(2026, 9, 4, 9),
        severity: 5,
        relievers: [
          EpisodeReliever(
            relieverCode: 'antacid',
            takenAt: DateTime(2026, 9, 4, 10),
            helped: 1,
          ),
        ],
      );

      expect(await repo.lastThingThatHelped(EpisodeKind.reflux), 'antacid');
      expect(await repo.lastThingThatHelped(EpisodeKind.migraine), isNull);
    });
  });
}

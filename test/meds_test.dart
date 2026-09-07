import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/insights/insights_service.dart';
import 'package:sage/data/models/med.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sage/data/repositories/meds_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late MedsRepository meds;
  late EpisodeRepository episodes;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );
    meds = MedsRepository(db);
    episodes = EpisodeRepository(db);
  });

  tearDown(() => db.close());

  DateTime ago(int days, {int hour = 10}) {
    final d = DateTime.now().subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour);
  }

  group('medications are stored as typed', () {
    test('the dose is kept verbatim, not parsed', () async {
      final id = await meds.create(
        name: 'Ibuprofen',
        doseText: 'two at onset, half if it is mild',
        kind: MedKind.rescue,
      );
      final m = (await meds.byId(id))!;
      // Free text on purpose. Forcing this into a number and a unit would
      // either lose the instruction or invent precision that was never there.
      expect(m.doseText, 'two at onset, half if it is mild');
    });

    test(
      'surrounding whitespace is trimmed but nothing else is touched',
      () async {
        final id = await meds.create(
          name: '  Sumatriptan  ',
          doseText: '  as needed  ',
          kind: MedKind.rescue,
        );
        final m = (await meds.byId(id))!;
        expect(m.name, 'Sumatriptan');
        expect(m.doseText, 'as needed');
      },
    );

    test('a nameless medication is refused', () async {
      expect(
        () => meds.create(name: '   ', kind: MedKind.rescue),
        throwsArgumentError,
      );
    });
  });

  group('no longer taken is not the same as deleted', () {
    test('deactivating keeps the row and its doses', () async {
      final medId = await meds.create(name: 'Old one', kind: MedKind.rescue);
      final epId = await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(5),
        severity: 6,
        medIds: [medId],
      );

      await meds.deactivate(medId);

      final m = (await meds.byId(medId))!;
      expect(m.active, isFalse);
      // The dose still names what was taken. Deleting would cascade it away
      // and rewrite a history the person may be showing a doctor.
      expect(await meds.doseCount(medId), 1);
      expect(await meds.medIdsForEpisode(epId), [medId]);
    });

    test(
      'deactivated medications leave the picker but stay in the list',
      () async {
        final a = await meds.create(name: 'Current', kind: MedKind.rescue);
        final b = await meds.create(name: 'Former', kind: MedKind.rescue);
        await meds.deactivate(b);

        expect((await meds.active(MedKind.rescue)).map((m) => m.id), [a]);
        expect((await meds.all()).length, 2);
      },
    );

    test('deleting really does take the doses with it', () async {
      final medId = await meds.create(name: 'Mistake', kind: MedKind.rescue);
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(2),
        severity: 5,
        medIds: [medId],
      );
      expect(await meds.doseCount(medId), 1);

      await meds.delete(medId);
      expect(await db.query('med_doses'), isEmpty);
    });

    test('a preventive medication is not offered as a rescue one', () async {
      await meds.create(name: 'Daily', kind: MedKind.preventive);
      expect(await meds.active(MedKind.rescue), isEmpty);
      expect(await meds.active(MedKind.preventive), hasLength(1));
    });
  });

  group('doses recorded against an episode', () {
    test('are written in the same transaction as the episode', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      final epId = await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(1),
        severity: 7,
        medIds: [medId],
      );

      final detail = (await episodes.detailById(epId))!;
      expect(detail.medIds, [medId]);
    });

    test(
      'are timed to the episode start, not to when the form was filled in',
      () async {
        // Editing an episode a week later must not move the dose into today,
        // which would put it in the wrong day for the rescue-use count.
        final medId = await meds.create(
          name: 'Ibuprofen',
          kind: MedKind.rescue,
        );
        final started = ago(9, hour: 14);
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: started,
          severity: 7,
          medIds: [medId],
        );

        final dose = (await db.query('med_doses')).single;
        expect(dose['taken_at'], started.millisecondsSinceEpoch);
      },
    );

    test('editing an episode rewrites only its own doses', () async {
      final a = await meds.create(name: 'A', kind: MedKind.rescue);
      final b = await meds.create(name: 'B', kind: MedKind.rescue);

      final keep = await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(4),
        severity: 5,
        medIds: [a],
      );
      final edit = await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(3),
        severity: 5,
        medIds: [a],
      );

      await episodes.update(
        id: edit,
        kind: EpisodeKind.migraine,
        startedAt: ago(3),
        severity: 5,
        medIds: [b],
      );

      expect(await meds.medIdsForEpisode(edit), [b]);
      // The other episode's dose is untouched.
      expect(await meds.medIdsForEpisode(keep), [a]);
    });

    test('deleting an episode keeps the dose but drops the link', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      final epId = await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(1),
        severity: 5,
        medIds: [medId],
      );

      await episodes.delete(epId);

      // ON DELETE SET NULL, from the Phase 0 schema. The dose happened.
      final dose = (await db.query('med_doses')).single;
      expect(dose['episode_id'], isNull);
      expect(dose['med_id'], medId);
    });
  });

  group('the rescue-use count', () {
    late InsightsService insights;
    setUp(() => insights = InsightsService(db));

    Future<void> takeOn(int daysAgo, String medId) async {
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(daysAgo),
        severity: 6,
        medIds: [medId],
      );
    }

    test('says nothing until the window has actually been observed', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      for (var i = 1; i <= 5; i++) {
        await takeOn(i, medId);
      }
      // Five days of history cannot support "of the last 30 days" — the
      // denominator would describe a window that was never observed.
      expect(await insights.rescueUseFinding(), isNull);
    });

    test('counts distinct days, not doses', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      await takeOn(40, medId); // history, outside the window
      // Two episodes on the same day, both with a dose.
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(3, hour: 9),
        severity: 6,
        medIds: [medId],
      );
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(3, hour: 20),
        severity: 6,
        medIds: [medId],
      );
      await takeOn(5, medId);

      final finding = (await insights.rescueUseFinding())!;
      expect(finding.detail, contains('on 2 of the last 30 days'));
    });

    test('ignores preventive medication', () async {
      final preventive = await meds.create(
        name: 'Daily',
        kind: MedKind.preventive,
      );
      await takeOn(40, preventive);
      for (var i = 1; i <= 10; i++) {
        await takeOn(i, preventive);
      }
      expect(await insights.rescueUseFinding(), isNull);
    });

    test('states the number and interprets nothing', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      await takeOn(40, medId);
      for (var i = 1; i <= 20; i++) {
        await takeOn(i, medId);
      }

      final finding = (await insights.rescueUseFinding())!;
      expect(finding.detail, contains('20 of the last 30 days'));

      // Twenty days of rescue use in a month is clinically notable, and the
      // app still says nothing about it. How many days is too many differs by
      // drug; reporting only above some threshold would itself be a hidden
      // judgement.
      final judgement = RegExp(
        r'\b(too (much|many|often)|overuse|rebound|cut down|reduce|limit|'
        r'careful|warning|risk|should|talk to|see a doctor|concerning)\b',
        caseSensitive: false,
      );
      expect(judgement.hasMatch('${finding.title} ${finding.detail}'), isFalse);
    });

    test(
      'appears in the full insight list without outranking a pattern',
      () async {
        final medId = await meds.create(
          name: 'Ibuprofen',
          kind: MedKind.rescue,
        );
        await takeOn(40, medId);
        await takeOn(2, medId);

        final all = await insights.all();
        final rescue = all.where((i) => i.id == 'rescue_use');
        expect(rescue, hasLength(1));
        // Info strength: a plain summary, not a pattern. It must not lead the
        // list or become the weekly notification.
        expect(rescue.single.strength.name, 'info');
      },
    );
  });

  group('intake', () {
    test('a dose can be logged with no episode at all', () async {
      // The gap Phase 9 left: a preventive taken every morning had nowhere to
      // go, so any intake figure built from episode-linked doses undercounts.
      final medId = await meds.create(name: 'Daily', kind: MedKind.preventive);
      await meds.recordDose(medId, at: ago(1));

      final dose = (await db.query('med_doses')).single;
      expect(dose['episode_id'], isNull);
      expect(dose['med_id'], medId);
    });

    test('counts days used, not doses', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      await meds.recordDose(medId, at: ago(2, hour: 9));
      await meds.recordDose(medId, at: ago(2, hour: 21));
      await meds.recordDose(medId, at: ago(5));

      final intake = (await meds.intake()).single;
      // Two tablets in one afternoon is one day. That is the unit a limit is
      // given in.
      expect(intake.doses, 3);
      expect(intake.days, 2);
    });

    test('counts episode-linked and standalone doses together', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(1),
        severity: 6,
        medIds: [medId],
      );
      await meds.recordDose(medId, at: ago(4));

      final intake = (await meds.intake()).single;
      expect(intake.days, 2);
    });

    test('ignores anything older than the window', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      await meds.recordDose(medId, at: ago(2));
      await meds.recordDose(medId, at: ago(60));

      final intake = (await meds.intake()).single;
      expect(intake.days, 1);
    });

    test('a dose can be removed when it was recorded by mistake', () async {
      final medId = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      final doseId = await meds.recordDose(medId);
      expect((await meds.intake()).single.days, 1);

      // A record someone cannot correct is one they stop trusting, and an
      // intake count is only worth having if they believe it.
      await meds.deleteDose(doseId);
      expect((await meds.intake()).single.days, 0);
    });
  });

  group('the limit belongs to the person, never to the app', () {
    test('a new medication has no limit until one is given', () async {
      final id = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      final m = (await meds.byId(id))!;
      // Null, not a default. A default here would be the app quietly issuing
      // medical advice.
      expect(m.monthlyLimitDays, isNull);
    });

    test('null is not zero', () async {
      final id = await meds.create(name: 'Ibuprofen', kind: MedKind.rescue);
      await meds.recordDose(id);

      final intake = (await meds.intake()).single;
      expect(intake.limit, isNull);
      expect(intake.remaining, isNull);
      // With no limit set there is nothing to be over. The app has no figure
      // of its own to compare against.
      expect(intake.overLimit, isFalse);
    });

    test('a limit of zero is a real limit', () async {
      final id = await meds.create(
        name: 'Stopped',
        kind: MedKind.rescue,
        monthlyLimitDays: 0,
      );
      await meds.recordDose(id);

      final intake = (await meds.intake()).single;
      expect(intake.limit, 0);
      expect(intake.overLimit, isTrue);
    });

    test('over is strictly over, not at', () async {
      final id = await meds.create(
        name: 'Ibuprofen',
        kind: MedKind.rescue,
        monthlyLimitDays: 2,
      );
      await meds.recordDose(id, at: ago(1));
      await meds.recordDose(id, at: ago(2));

      var intake = (await meds.intake()).single;
      expect(intake.days, 2);
      expect(intake.overLimit, isFalse, reason: 'at the limit is not over it');
      expect(intake.remaining, 0);

      await meds.recordDose(id, at: ago(3));
      intake = (await meds.intake()).single;
      expect(intake.overLimit, isTrue);
      expect(intake.remaining, -1);
    });

    test('a limit survives an edit that changes nothing else', () async {
      final id = await meds.create(
        name: 'Ibuprofen',
        kind: MedKind.rescue,
        monthlyLimitDays: 10,
      );
      await meds.update(
        id,
        name: 'Ibuprofen',
        doseText: 'two at onset',
        kind: MedKind.rescue,
        active: true,
        monthlyLimitDays: 10,
      );
      expect((await meds.byId(id))!.monthlyLimitDays, 10);
    });

    test('a limit can be cleared back to none', () async {
      final id = await meds.create(
        name: 'Ibuprofen',
        kind: MedKind.rescue,
        monthlyLimitDays: 10,
      );
      await meds.update(
        id,
        name: 'Ibuprofen',
        doseText: '',
        kind: MedKind.rescue,
        active: true,
        monthlyLimitDays: null,
      );
      expect((await meds.byId(id))!.monthlyLimitDays, isNull);
    });
  });
}

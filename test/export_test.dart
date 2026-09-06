import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/export/export_service.dart';
import 'package:sage/data/insights/insights_service.dart';
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
  late ExportService export;
  late EpisodeRepository episodes;
  late DailyLogRepository daily;
  late TriageService triage;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );
    export = ExportService(db, InsightsService(db));
    episodes = EpisodeRepository(db);
    daily = DailyLogRepository(db);
    triage = TriageService(db);
  });

  tearDown(() => db.close());

  DateTime ago(int days, {int hour = 9}) {
    final d = DateTime.now().subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour);
  }

  group('an empty log', () {
    test('still produces a complete, honest document', () async {
      final r = await export.buildReport();

      // Every section is present, so a doctor handed an early export sees the
      // shape of it rather than a fragment.
      expect(r, contains('SAGE — MIGRAINE AND REFLUX LOG'));
      expect(r, contains('PERIOD'));
      expect(r, contains('SUMMARY'));
      expect(r, contains('PATTERNS IN THE LOG'));
      expect(r, contains('SAFETY CHECKS THAT FLAGGED'));
      expect(r, contains('EPISODE LOG'));

      expect(r, contains('Nothing recorded yet.'));
      expect(r, contains('None recorded.'));
      // Not "no patterns found", which would imply the app had looked and
      // ruled things out.
      expect(r, contains('evidence threshold'));
    });
  });

  group('the period', () {
    test('covers the daily log too, not just episodes', () async {
      // Regression: the period used to come from the episode range while the
      // context count came from the whole table, which printed "40 of 37" -
      // more days filled in than days in the period.
      for (var i = 0; i < 40; i++) {
        await daily.save(
          DailyLog(
            day: localDayOf(ago(i + 1)),
            sleepHours: 7,
            updatedAt: DateTime.now(),
          ),
        );
      }
      // Episodes span a much narrower window than the daily log.
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(3),
        severity: 5,
      );

      final r = await export.buildReport();
      final m = RegExp(r'context entry[^:]*: (\d+) of (\d+)').firstMatch(r)!;
      final logged = int.parse(m.group(1)!);
      final span = int.parse(m.group(2)!);

      expect(logged, 40);
      expect(
        span,
        greaterThanOrEqualTo(logged),
        reason: 'more logged days than days in the period is impossible',
      );
    });

    test('says nothing is recorded when both tables are empty', () async {
      expect(await export.buildReport(), contains('Nothing recorded yet.'));
    });
  });

  group('what the document must always say', () {
    test(
      'it states that everything is self-reported, before the numbers',
      () async {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(1),
          severity: 8,
        );
        final r = await export.buildReport();

        expect(r, contains('self-reported'));
        // A clinician reading a tidy generated document can reasonably mistake
        // it for measured data unless it says otherwise before they start.
        expect(
          r.indexOf('self-reported'),
          lessThan(r.indexOf('SUMMARY')),
          reason: 'the caveat has to come before the figures',
        );
      },
    );

    test(
      'a medication dose is reproduced as the person\'s own words',
      () async {
        await db.insert('meds', {
          'id': 'med_1',
          'name': 'Whatever they typed',
          'dose_text': 'two in the morning',
          'kind': 'rescue',
          'active': 1,
          'created_at': 0,
        });

        final r = await export.buildReport();
        expect(r, contains('two in the morning'));
        expect(r, contains('free text the person typed'));
        expect(r, contains('not a'));
        expect(r, contains('prescription record'));
      },
    );

    test(
      'the correlational caveat sits with the patterns, not in a footer',
      () async {
        for (var i = 0; i < 10; i++) {
          await daily.save(
            DailyLog(
              day: localDayOf(ago(i + 1)),
              sleepHours: 4.5,
              updatedAt: DateTime.now(),
            ),
          );
          if (i < 7) {
            await episodes.create(
              kind: EpisodeKind.migraine,
              startedAt: ago(i + 1),
              severity: 7,
            );
          }
        }
        for (var i = 0; i < 20; i++) {
          await daily.save(
            DailyLog(
              day: localDayOf(ago(i + 12)),
              sleepHours: 8,
              updatedAt: DateTime.now(),
            ),
          );
        }
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(12),
          severity: 5,
        );

        final r = await export.buildReport();
        expect(r, contains('slept under 6 hours'));

        final caveat = r.indexOf('not the same as one');
        expect(caveat, greaterThan(r.indexOf('PATTERNS IN THE LOG')));
        expect(caveat, lessThan(r.indexOf('MEDICATIONS')));
      },
    );

    test('a safety check that fired appears in the document', () async {
      // Designed into Tier 0 for exactly this. "The app told me to go to A&E
      // on the 6th and I did not" cannot be reconstructed from episode rows.
      await triage.record(triage.evaluate({'thunderclap'}));

      final r = await export.buildReport();
      expect(r, contains('thunderclap'));
      expect(r, isNot(contains('None.\n\nEPISODE LOG')));
    });
  });

  group('the episode log', () {
    test(
      'carries symptoms, the person\'s own attribution, and what was tried',
      () async {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(2, hour: 14),
          endedAt: ago(2, hour: 18),
          severity: 8,
          notes: 'started at work',
          symptomCodes: const ['photophobia', 'nausea'],
          userTriggerCodes: const ['short_sleep'],
          relievers: [
            EpisodeReliever(
              relieverCode: 'dark_room',
              takenAt: ago(2, hour: 15),
              helped: 1,
            ),
            EpisodeReliever(
              relieverCode: 'caffeine',
              takenAt: ago(2, hour: 16),
              helped: null,
            ),
          ],
        );

        final r = await export.buildReport();
        expect(r, contains('8/10'));
        expect(r, contains('4h'));
        expect(r, contains('Light hurts'));
        // Labelled as the person's belief, kept separate from the app's own
        // findings in PATTERNS.
        expect(r, contains('they thought:'));
        expect(r, contains('Not enough sleep'));
        expect(r, contains('Lay down in the dark (helped)'));
        // An unrated attempt is visibly unrated rather than looking like it did
        // nothing.
        expect(r, contains('Caffeine (not rated)'));
        expect(r, contains('started at work'));
      },
    );

    test('an open episode is shown as open, not as zero duration', () async {
      await episodes.startNow(EpisodeKind.reflux, at: ago(0, hour: 8));
      final r = await export.buildReport();
      expect(r, contains('still open'));
    });

    test('a note with newlines does not break the layout', () async {
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(1),
        severity: 5,
        notes: 'line one\nline two',
      );
      final r = await export.buildReport();
      expect(r, contains('line one line two'));
    });

    test('episodes are oldest first', () async {
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(1),
        severity: 5,
        notes: 'newer',
      );
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(10),
        severity: 5,
        notes: 'older',
      );
      final r = await export.buildReport();
      expect(r.indexOf('older'), lessThan(r.indexOf('newer')));
    });
  });

  test(
    'the summary uses a median, so one long episode does not distort it',
    () async {
      for (var i = 0; i < 3; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(i + 1, hour: 9),
          endedAt: ago(i + 1, hour: 11),
          severity: 5,
        );
      }
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(5, hour: 9),
        endedAt: ago(4, hour: 1),
        severity: 5,
      );

      final r = await export.buildReport();
      // Three at 2h and one at 16h. A mean would report 5h30, describing none
      // of them.
      expect(r, contains('median duration 2h'));
    },
  );

  test('the filename is dated so exports do not overwrite each other', () {
    expect(
      export.suggestedFileName,
      matches(r'^sage-log-\d{4}-\d{2}-\d{2}\.txt$'),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/export/export_service.dart';
import 'package:sage/data/insights/insights_service.dart';
import 'package:sage/data/repositories/meds_repository.dart';
import 'package:sage/data/models/daily_log.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/daily_log_repository.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sage/data/triage/triage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prints the export a seeded database produces.
///
///     flutter test test/tools/dump_export.dart
///
/// Run it after touching the export. This is a document someone hands to a
/// doctor, and whether it reads well is not something a `contains` assertion
/// can tell you — the same reason `dump_insights.dart` exists.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('dump', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );
    addTearDown(db.close);

    final episodes = EpisodeRepository(db);
    final daily = DailyLogRepository(db);
    final export = ExportService(db, InsightsService(db), MedsRepository(db));

    DateTime ago(int days, {int hour = 9}) {
      final d = DateTime.now().subtract(Duration(days: days));
      return DateTime(d.year, d.month, d.day, hour);
    }

    await db.insert('meds', {
      'id': 'med_1',
      'name': 'Ibuprofen',
      'dose_text': '400, two at onset',
      'kind': 'rescue',
      'active': 1,
      'monthly_limit_days': 10,
      'created_at': 0,
    });

    for (var i = 1; i <= 40; i++) {
      final shortSleep = i % 5 == 1 || i % 5 == 2;
      await daily.save(
        DailyLog(
          day: localDayOf(ago(i)),
          sleepHours: shortSleep ? 4.5 : 7.5,
          stressLevel: i % 4 == 0 ? 5 : 2,
          mealsSkipped: shortSleep ? 1 : 0,
          waterGlasses: 6,
          lateMeal: i % 3 == 0,
          updatedAt: DateTime.now(),
        ),
      );

      if (shortSleep) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(i, hour: 14),
          endedAt: ago(i, hour: 18),
          severity: 7,
          notes: i == 2 ? 'started at work, had to leave early' : '',
          symptomCodes: const ['photophobia', 'nausea', 'throbbing'],
          medIds: i % 2 == 1 ? const ['med_1'] : const [],
          userTriggerCodes: const ['short_sleep', 'stress'],
          relievers: [
            EpisodeReliever(
              relieverCode: 'dark_room',
              takenAt: ago(i, hour: 15),
              helped: 1,
            ),
            if (i % 3 == 0)
              EpisodeReliever(
                relieverCode: 'caffeine',
                takenAt: ago(i, hour: 15),
                helped: null,
              ),
          ],
        );
      }
      if (i % 6 == 0) {
        await episodes.create(
          kind: EpisodeKind.reflux,
          startedAt: ago(i, hour: 22),
          endedAt: ago(i, hour: 23),
          severity: 4,
          symptomCodes: const ['heartburn'],
          userTriggerCodes: const ['late_meal'],
        );
      }
    }

    final triage = TriageService(db);
    await triage.record(triage.evaluate({'thunderclap'}));

    // ignore: avoid_print
    print('\n${await export.buildReport()}');
  });
}

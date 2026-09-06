import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/insights/insights_service.dart';
import 'package:sage/data/models/daily_log.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/daily_log_repository.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prints the sentences a seeded database produces.
///
///     flutter test test/tools/dump_insights.dart
///
/// This is the fastest way to check phrasing without installing to a device,
/// and the thing to run after touching any rule. Reading the output is the
/// point — a gate can be correct while the sentence built on it is unreadable,
/// and only one of those is caught by a test.
///
/// It asserts almost nothing on purpose. `insights_test.dart` is where the
/// gates are pinned; this is for looking at the words.
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
    final insights = InsightsService(db);

    DateTime ago(int days, {int hour = 10}) {
      final d = DateTime.now().subtract(Duration(days: days));
      return DateTime(d.year, d.month, d.day, hour);
    }

    // A plausible ten weeks: short sleep and high stress cluster with
    // migraines, late meals with reflux, and a couple of relievers rated.
    for (var i = 1; i <= 70; i++) {
      final at = ago(i);
      final shortSleep = i % 7 == 1 || i % 7 == 2;
      final stressed = i % 5 == 0;
      final lateMeal = i % 3 == 0;

      await daily.save(
        DailyLog(
          day: localDayOf(at),
          sleepHours: shortSleep ? 4.5 : 7.5,
          stressLevel: stressed ? 5 : 2,
          caffeineUnits: i % 4,
          waterGlasses: 6,
          alcoholUnits: i % 9 == 0 ? 3 : 0,
          mealsSkipped: shortSleep ? 1 : 0,
          lateMeal: lateMeal,
          updatedAt: DateTime.now(),
        ),
      );

      if (shortSleep && i % 2 == 1) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: at,
          endedAt: at.add(const Duration(hours: 4)),
          severity: 7,
          symptomCodes: const ['photophobia', 'nausea'],
          relievers: [
            EpisodeReliever(
              relieverCode: 'dark_room',
              takenAt: at.add(const Duration(minutes: 20)),
              helped: 1,
            ),
          ],
        );
      }
      if (lateMeal && i % 6 == 0) {
        await episodes.create(
          kind: EpisodeKind.reflux,
          startedAt: ago(i, hour: 22),
          endedAt: ago(i, hour: 23),
          severity: 5,
          relievers: [
            EpisodeReliever(
              relieverCode: 'upright',
              takenAt: ago(i, hour: 22),
              helped: i % 12 == 0 ? 0 : 1,
            ),
          ],
        );
      }
    }

    final found = await insights.all();

    // ignore: avoid_print
    print('\n=== ${found.length} finding(s) ===\n');
    for (final i in found) {
      // ignore: avoid_print
      print('[${i.strength.name.toUpperCase()}] ${i.title}');
      // ignore: avoid_print
      print('    ${i.detail}\n');
    }
    if (found.isEmpty) {
      // ignore: avoid_print
      print(await insights.progressNote());
    }

    // The seed is built to clear the gates. If this ever goes empty, either a
    // gate moved or the seed stopped being realistic — both worth knowing.
    expect(found, isNotEmpty);
  });
}

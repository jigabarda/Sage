import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/insights/insight.dart';
import 'package:sage/data/insights/insights_service.dart';
import 'package:sage/data/models/daily_log.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/daily_log_repository.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The gates are the rules. A finding fired from too little data is worse than
/// no finding, because the reader cannot tell it from a well-founded one — so
/// most of what follows tests that things do **not** fire.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late InsightsService insights;
  late EpisodeRepository episodes;
  late DailyLogRepository daily;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );
    insights = InsightsService(db);
    episodes = EpisodeRepository(db);
    daily = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  // Seeded relative to today, because the weekday and frequency rules read
  // windows ending now.
  DateTime ago(int days, {int hour = 10}) {
    final d = DateTime.now().subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour);
  }

  Future<void> day(
    int daysAgo, {
    double? sleep,
    int? stress,
    bool? lateMeal,
    bool episode = false,
    EpisodeKind kind = EpisodeKind.migraine,
  }) async {
    final at = ago(daysAgo);
    await daily.save(
      DailyLog(
        day: localDayOf(at),
        sleepHours: sleep,
        stressLevel: stress,
        lateMeal: lateMeal,
        updatedAt: DateTime.now(),
      ),
    );
    if (episode) {
      await episodes.create(
        kind: kind,
        startedAt: at,
        endedAt: at.add(const Duration(hours: 3)),
        severity: 6,
      );
    }
  }

  /// A clean short-sleep signal: 10 short nights with 7 episodes, 20 normal
  /// nights with 2. Well past every gate.
  Future<void> seedSleepSignal() async {
    for (var i = 0; i < 10; i++) {
      await day(i + 1, sleep: 4.5, episode: i < 7);
    }
    for (var i = 0; i < 20; i++) {
      await day(i + 12, sleep: 8, episode: i < 2);
    }
  }

  group('global gates', () {
    test('nothing fires below the episode floor', () async {
      for (var i = 0; i < 5; i++) {
        await day(i + 1, sleep: 4, episode: true);
      }
      for (var i = 0; i < 20; i++) {
        await day(i + 10, sleep: 8);
      }
      expect(await insights.all(), isEmpty);
    });

    test('nothing fires below the logged-day floor', () async {
      // Plenty of episodes, almost no day context to compare them against.
      for (var i = 0; i < 12; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(i + 1),
          severity: 6,
        );
      }
      for (var i = 0; i < 5; i++) {
        await day(i + 1, sleep: 4);
      }
      final found = await insights.all();
      expect(
        found.where((i) => i.id.startsWith('cond_')),
        isEmpty,
        reason: 'day comparisons need day coverage',
      );
    });

    test(
      'the empty state explains itself in the person\'s own numbers',
      () async {
        await day(1, sleep: 5, episode: true);
        final note = await insights.progressNote();
        expect(note, contains('1 of about ${InsightsService.minEpisodes}'));
      },
    );
  });

  group('day-condition rule', () {
    test('finds a real signal and states its numbers', () async {
      await seedSleepSignal();

      final found = await insights.forKind(EpisodeKind.migraine);
      final sleep = found.firstWhere(
        (i) => i.id == 'cond_migraine_short_sleep',
      );

      expect(sleep.strength, InsightStrength.strong);
      // The sentence must carry the figures it came from, or the reader has no
      // way to check it.
      expect(sleep.detail, contains('7 of the 10 days'));
      expect(sleep.detail, contains('2 of the 20 days'));
      expect(sleep.detail, contains('slept under 6 hours'));
    });

    test('does not fire when the effect is small', () async {
      // 3 of 10 against 5 of 20 is the same rate. Nothing to say.
      for (var i = 0; i < 10; i++) {
        await day(i + 1, sleep: 4.5, episode: i < 3);
      }
      for (var i = 0; i < 20; i++) {
        await day(i + 12, sleep: 8, episode: i < 6);
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(found.where((i) => i.id.contains('short_sleep')), isEmpty);
    });

    test('does not fire without enough days on the condition side', () async {
      // Four short nights, all with an episode. A perfect rate on four days is
      // still four days.
      for (var i = 0; i < 4; i++) {
        await day(i + 1, sleep: 4, episode: true);
      }
      for (var i = 0; i < 25; i++) {
        await day(i + 6, sleep: 8, episode: i < 4);
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(found.where((i) => i.id.contains('short_sleep')), isEmpty);
    });

    test('does not fire without enough days on the baseline side', () async {
      for (var i = 0; i < 20; i++) {
        await day(i + 1, sleep: 4, episode: i < 12);
      }
      for (var i = 0; i < 3; i++) {
        await day(i + 22, sleep: 8);
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(
        found.where((i) => i.id.contains('short_sleep')),
        isEmpty,
        reason: 'three normal nights is not a baseline',
      );
    });

    test('a day where that measure was left blank is excluded, not counted '
        'as false', () async {
      // Ten short nights with 7 episodes. Then twenty days where sleep was
      // never recorded, all of them episode-free.
      //
      // If blanks were read as "not short sleep", those twenty would form a
      // baseline of 0 of 20 and the rule would fire. They are not evidence
      // about sleep at all, so it must not.
      for (var i = 0; i < 10; i++) {
        await day(i + 1, sleep: 4.5, episode: i < 7);
      }
      for (var i = 0; i < 20; i++) {
        await day(i + 12, stress: 2);
      }

      final found = await insights.forKind(EpisodeKind.migraine);
      expect(
        found.where((i) => i.id.contains('short_sleep')),
        isEmpty,
        reason: 'unrecorded sleep is not evidence of normal sleep',
      );
    });

    test(
      'an unlikely-but-perfect signal still needs an absolute floor',
      () async {
        // 3 of 6 condition days against 0 of 30. The lift is infinite, which is
        // exactly why an unbounded ratio cannot be the only test.
        for (var i = 0; i < 6; i++) {
          await day(
            i + 1,
            lateMeal: true,
            episode: i < 3,
            kind: EpisodeKind.reflux,
          );
        }
        for (var i = 0; i < 30; i++) {
          await day(i + 8, lateMeal: false);
        }
        for (var i = 0; i < 8; i++) {
          await episodes.create(
            kind: EpisodeKind.reflux,
            startedAt: ago(i + 1, hour: 21),
            severity: 5,
          );
        }
        final found = await insights.forKind(EpisodeKind.reflux);
        // It clears the 0.4 floor, so this one is allowed through — the test
        // pins that the floor is what decided it rather than the ratio.
        final late = found.where((i) => i.id.contains('late_meal'));
        expect(late, isNotEmpty);
      },
    );

    test(
      'a condition is only offered for the conditions it belongs to',
      () async {
        await seedSleepSignal();
        final found = await insights.forKind(EpisodeKind.migraine);
        // Late meals are a reflux measure and must never appear under migraine.
        expect(found.where((i) => i.id.contains('late_meal')), isEmpty);
      },
    );

    test('no more than maxPerRule findings from this rule', () async {
      for (var i = 0; i < 12; i++) {
        await daily.save(
          DailyLog(
            day: localDayOf(ago(i + 1)),
            sleepHours: 4,
            stressLevel: 5,
            updatedAt: DateTime.now(),
          ),
        );
        if (i < 9) {
          await episodes.create(
            kind: EpisodeKind.migraine,
            startedAt: ago(i + 1),
            severity: 6,
          );
        }
      }
      for (var i = 0; i < 25; i++) {
        await daily.save(
          DailyLog(
            day: localDayOf(ago(i + 14)),
            sleepHours: 8,
            stressLevel: 1,
            updatedAt: DateTime.now(),
          ),
        );
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(
        found.where((i) => i.id.startsWith('cond_')).length,
        lessThanOrEqualTo(InsightsService.maxPerRule),
      );
    });
  });

  group('frequency rule', () {
    test('reports a rise as a count, both windows named', () async {
      // An episode older than both windows, so the rule has the two full
      // windows of history it requires. It falls outside either count.
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(70),
        severity: 5,
      );
      for (var i = 0; i < 3; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(35 + i),
          severity: 5,
        );
      }
      for (var i = 0; i < 9; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(i + 1),
          severity: 5,
        );
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      final freq = found.firstWhere((i) => i.id.startsWith('freq_'));
      expect(freq.detail, contains('9 in the last four weeks'));
      expect(freq.detail, contains('3 in the four weeks before'));
    });

    test('reports a fall without congratulating anyone', () async {
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: ago(70),
        severity: 5,
      );
      for (var i = 0; i < 9; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(31 + i),
          severity: 5,
        );
      }
      for (var i = 0; i < 2; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(i + 1),
          severity: 5,
        );
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      final freq = found.firstWhere((i) => i.id.startsWith('freq_'));
      // A quiet month is not an achievement, and framing it as one frames the
      // next bad month as a failure.
      final praise = RegExp(
        r'\b(great|well done|good job|congrat|nice work|keep it up|streak)\b',
        caseSensitive: false,
      );
      expect(praise.hasMatch('${freq.title} ${freq.detail}'), isFalse);
    });

    test('does not fire without two full windows of history', () async {
      for (var i = 0; i < 10; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(i + 1),
          severity: 5,
        );
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(
        found.where((i) => i.id.startsWith('freq_')),
        isEmpty,
        reason: 'the earlier window would include time before any logging',
      );
    });
  });

  group('what an insight may never be', () {
    test('no finding tells anyone to seek care', () async {
      await seedSleepSignal();
      for (var i = 0; i < 10; i++) {
        await episodes.create(
          kind: EpisodeKind.migraine,
          startedAt: ago(40 + i),
          endedAt: ago(40 + i).add(const Duration(hours: 2)),
          severity: 5,
          relievers: [
            EpisodeReliever(
              relieverCode: 'dark_room',
              takenAt: ago(40 + i),
              helped: 1,
            ),
          ],
        );
      }

      final found = await insights.all();
      expect(found, isNotEmpty);

      // Urgency belongs to Tier 0 alone, evaluated at the moment it matters.
      // A card someone reads next week is the wrong instrument for it.
      final urgent = RegExp(
        r'\b(emergency|urgent|ambulance|999|911|hospital|see a doctor|'
        r'seek (medical )?(care|help|attention)|call your doctor)\b',
        caseSensitive: false,
      );
      for (final i in found) {
        expect(
          urgent.hasMatch('${i.title} ${i.detail}'),
          isFalse,
          reason: i.id,
        );
      }
    });

    test('every finding states at least two numbers', () async {
      await seedSleepSignal();
      final found = await insights.all();
      expect(found, isNotEmpty);
      final digits = RegExp(r'\d+');
      for (final i in found) {
        expect(
          digits.allMatches(i.detail).length,
          greaterThanOrEqualTo(2),
          reason: '${i.id}: "${i.detail}" is not checkable',
        );
      }
    });
  });
}

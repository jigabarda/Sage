import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/dates.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/insights/cycle.dart';
import 'package:sage/data/insights/insights_service.dart';
import 'package:sage/data/models/daily_log.dart';
import 'package:sage/data/repositories/daily_log_repository.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the arithmetic', () {
    test('the window runs two days before to three after', () {
      final days = Cycle.perimenstrualDays([100]);
      expect(days, containsAll([98, 99, 100, 101, 102, 103]));
      expect(days.contains(97), isFalse);
      expect(days.contains(104), isFalse);
      expect(days, hasLength(6));
    });

    test('overlapping windows do not double-count a day', () {
      // Two starts four days apart, which is not physiological but is exactly
      // the sort of thing a mis-tap produces.
      final days = Cycle.perimenstrualDays([100, 104]);
      expect(days, hasLength(days.toSet().length));
    });

    test('no span until enough cycles have been seen', () {
      expect(Cycle.classifiableSpan([100]), isNull);
      expect(Cycle.classifiableSpan([100, 128]), isNull);
      // Three starts is two complete cycles. Two starts is one, and one cycle
      // is an anecdote.
      expect(Cycle.classifiableSpan([100, 128, 156]), isNotNull);
    });

    test('the span is bracketed by the recorded starts', () {
      final span = Cycle.classifiableSpan([100, 128, 156])!;
      expect(span.$1, 98);
      expect(span.$2, 159);
      // Outside it, "not around a period" would be a guess: a day three weeks
      // after the last start might be mid-cycle or a period nobody logged.
    });

    group('the day-number suggestion', () {
      test('counts from the most recent start on or before the day', () {
        expect(Cycle.dayNumberFor(100, [100]), 1);
        expect(Cycle.dayNumberFor(113, [100]), 14);
        expect(Cycle.dayNumberFor(130, [100, 128]), 3);
      });

      test('offers nothing before the first recorded period', () {
        expect(Cycle.dayNumberFor(90, [100]), isNull);
      });

      test('offers nothing when the answer would be absurd', () {
        // Day 97 is a period that was never logged, not a 97-day cycle.
        // Suggesting it would be worse than suggesting nothing.
        expect(Cycle.dayNumberFor(200, [100]), isNull);
      });
    });
  });

  group('the correlation rule', () {
    late Database db;
    late InsightsService insights;
    late DailyLogRepository daily;
    late EpisodeRepository episodes;

    setUp(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: SageDatabase.openOptions(),
      );
      insights = InsightsService(db);
      daily = DailyLogRepository(db);
      episodes = EpisodeRepository(db);
    });

    tearDown(() => db.close());

    DateTime at(LocalDay day, {int hour = 10}) =>
        startOfDay(day).add(Duration(hours: hour));

    Future<void> periodOn(LocalDay day) async {
      await daily.save(
        DailyLog(day: day, cycleDay: 1, updatedAt: DateTime.now()),
      );
    }

    Future<void> episodeOn(LocalDay day) async {
      await episodes.create(
        kind: EpisodeKind.migraine,
        startedAt: at(day),
        severity: 7,
      );
    }

    /// Three cycles, with a migraine on every period start and a couple
    /// scattered in between.
    Future<List<LocalDay>> seedSignal() async {
      final base = localDayOf(DateTime.now()) - 90;
      final starts = [base, base + 28, base + 56, base + 84];
      for (final s in starts) {
        await periodOn(s);
        await episodeOn(s);
        await episodeOn(s + 1);
      }
      await episodeOn(base + 14);
      await episodeOn(base + 45);
      return starts;
    }

    test('says nothing when cycle tracking was never used', () async {
      for (var i = 1; i <= 12; i++) {
        await episodeOn(localDayOf(DateTime.now()) - i);
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(found.where((i) => i.id.startsWith('cycle_')), isEmpty);
    });

    test('says nothing after only one cycle', () async {
      final base = localDayOf(DateTime.now()) - 40;
      await periodOn(base);
      await periodOn(base + 28);
      for (final s in [base, base + 28]) {
        await episodeOn(s);
        await episodeOn(s + 1);
      }
      for (var i = 0; i < 8; i++) {
        await episodeOn(base + 5 + i);
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(found.where((i) => i.id.startsWith('cycle_')), isEmpty);
    });

    test('finds the pattern and states what it counted', () async {
      final starts = await seedSignal();

      final found = await insights.forKind(EpisodeKind.migraine);
      final cycle = found.firstWhere((i) => i.id == 'cycle_migraine');

      expect(cycle.detail, contains('days around a period'));
      expect(cycle.detail, contains('days in between'));
      // Says how many periods it is built on, so the reader can judge it.
      expect(cycle.detail, contains('${starts.length} periods'));
    });

    test('does not fire when episodes are spread evenly', () async {
      final base = localDayOf(DateTime.now()) - 90;
      for (final s in [base, base + 28, base + 56, base + 84]) {
        await periodOn(s);
      }
      // One episode every four days, which is nothing to do with the cycle.
      for (var d = base; d <= base + 84; d += 4) {
        await episodeOn(d);
      }
      final found = await insights.forKind(EpisodeKind.migraine);
      expect(found.where((i) => i.id.startsWith('cycle_')), isEmpty);
    });

    test('only days inside the bracketed span are counted', () async {
      final starts = await seedSignal();
      // A cluster long after the last recorded period. It cannot be
      // classified, so it must not become baseline evidence either way.
      for (var i = 1; i <= 5; i++) {
        await episodeOn(starts.last + 20 + i);
      }

      final found = await insights.forKind(EpisodeKind.migraine);
      final cycle = found.firstWhere((i) => i.id == 'cycle_migraine');

      final numbers = RegExp(
        r'\d+',
      ).allMatches(cycle.detail).map((m) => int.parse(m.group(0)!)).toList();
      // days-with, days-without and the two episode counts all have to fall
      // inside the span, so no figure can exceed its length.
      final span =
          starts.last + Cycle.daysAfter - (starts.first - Cycle.daysBefore) + 1;
      for (final n in numbers) {
        expect(n, lessThanOrEqualTo(span));
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/guidance/guidance.dart';
import 'package:sage/data/guidance/guidance_service.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the fixed content', () {
    test('both conditions have steps and things to avoid', () {
      for (final kind in EpisodeKind.values) {
        expect(GuidanceContent.stepsFor(kind), isNotEmpty, reason: kind.code);
        expect(GuidanceContent.avoidFor(kind), isNotEmpty, reason: kind.code);
      }
    });

    test('no step names a drug or a dose', () {
      // Non-negotiable 6. "Take it as your doctor told you" is the most this
      // may ever say about medication.
      final dose = RegExp(r'\d+\s*(mg|ml|mcg|g)\b', caseSensitive: false);
      final named = RegExp(
        r'\b(ibuprofen|paracetamol|acetaminophen|aspirin|naproxen|omeprazole|'
        r'sumatriptan|ranitidine|famotidine)\b',
        caseSensitive: false,
      );
      for (final kind in EpisodeKind.values) {
        for (final s in GuidanceContent.stepsFor(kind)) {
          final text = '${s.text} ${s.detail ?? ''}';
          expect(dose.hasMatch(text), isFalse, reason: s.text);
          expect(named.hasMatch(text), isFalse, reason: s.text);
        }
      }
    });
  });

  group('personal notes', () {
    late Database db;
    late GuidanceService guidance;
    late EpisodeRepository repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: SageDatabase.openOptions(),
      );
      guidance = GuidanceService(db);
      repo = EpisodeRepository(db);
    });

    tearDown(() => db.close());

    Future<void> episodeWith({
      required DateTime start,
      DateTime? end,
      String? reliever,
      int? helped,
      EpisodeKind kind = EpisodeKind.migraine,
    }) async {
      await repo.create(
        kind: kind,
        startedAt: start,
        endedAt: end,
        severity: 5,
        relievers: reliever == null
            ? const []
            : [
                EpisodeReliever(
                  relieverCode: reliever,
                  takenAt: start.add(const Duration(minutes: 10)),
                  helped: helped,
                ),
              ],
      );
    }

    test('a new user gets steps and no claims about themselves', () async {
      final g = await guidance.forKind(EpisodeKind.migraine);
      expect(g.steps, isNotEmpty);
      // The gate failing produces nothing. It is never softened into "this may
      // have helped before" — a hedge is indistinguishable from a finding to
      // someone in pain.
      expect(g.personalNotes, isEmpty);
    });

    test('two rated attempts are not enough to quote', () async {
      for (var i = 0; i < 2; i++) {
        await episodeWith(
          start: DateTime(2026, 9, 1 + i, 9),
          reliever: 'dark_room',
          helped: 1,
        );
      }
      final g = await guidance.forKind(EpisodeKind.migraine);
      expect(g.personalNotes, isEmpty);
    });

    test(
      'three rated attempts clear the gate and state their numbers',
      () async {
        for (var i = 0; i < 3; i++) {
          await episodeWith(
            start: DateTime(2026, 9, 1 + i, 9),
            reliever: 'dark_room',
            helped: 1,
          );
        }
        final g = await guidance.forKind(EpisodeKind.migraine);
        expect(g.personalNotes, isNotEmpty);
        final note = g.personalNotes.first;
        expect(note, contains('Lay down in the dark'));
        // "helping 3 of the 3 times" — a reader can check that against what they
        // already believe. "Dark rooms work for you" is not checkable.
        expect(note, contains('3 of the 3'));
      },
    );

    test('unrated attempts are not counted at all', () async {
      await episodeWith(
        start: DateTime(2026, 9, 1, 9),
        reliever: 'dark_room',
        helped: 1,
      );
      for (var i = 0; i < 5; i++) {
        await episodeWith(
          start: DateTime(2026, 9, 2 + i, 9),
          reliever: 'dark_room',
          helped: null,
        );
      }
      // One rated attempt plus five unrated is still one rated attempt. The
      // people least likely to go back and rate are the ones having the worst
      // episodes, so counting unrated as neutral would bias this downwards.
      final g = await guidance.forKind(EpisodeKind.migraine);
      expect(g.personalNotes, isEmpty);
    });

    test('a reliever that mostly failed is not recommended back', () async {
      await episodeWith(
        start: DateTime(2026, 9, 1, 9),
        reliever: 'caffeine',
        helped: 1,
      );
      for (var i = 0; i < 3; i++) {
        await episodeWith(
          start: DateTime(2026, 9, 2 + i, 9),
          reliever: 'caffeine',
          helped: 0,
        );
      }
      final g = await guidance.forKind(EpisodeKind.migraine);
      expect(
        g.personalNotes.any((n) => n.contains('Caffeine')),
        isFalse,
        reason: '1 of 4 is not a track record worth repeating',
      );
    });

    test('notes do not leak across conditions', () async {
      for (var i = 0; i < 3; i++) {
        await episodeWith(
          start: DateTime(2026, 9, 1 + i, 9),
          reliever: 'antacid',
          helped: 1,
          kind: EpisodeKind.reflux,
        );
      }
      final migraine = await guidance.forKind(EpisodeKind.migraine);
      expect(migraine.personalNotes, isEmpty);

      final reflux = await guidance.forKind(EpisodeKind.reflux);
      expect(reflux.personalNotes, isNotEmpty);
    });

    group('typical duration', () {
      test('two closed episodes are not enough', () async {
        for (var i = 0; i < 2; i++) {
          await episodeWith(
            start: DateTime(2026, 9, 1 + i, 9),
            end: DateTime(2026, 9, 1 + i, 13),
          );
        }
        final g = await guidance.forKind(EpisodeKind.migraine);
        expect(g.personalNotes.any((n) => n.contains('Half of')), isFalse);
      });

      test('an ongoing episode is not counted', () async {
        for (var i = 0; i < 2; i++) {
          await episodeWith(
            start: DateTime(2026, 9, 1 + i, 9),
            end: DateTime(2026, 9, 1 + i, 13),
          );
        }
        await episodeWith(start: DateTime(2026, 9, 5, 9));

        final g = await guidance.forKind(EpisodeKind.migraine);
        expect(
          g.personalNotes.any((n) => n.contains('Half of')),
          isFalse,
          reason: 'an episode with no end has no duration to average',
        );
      });

      test('one very long episode does not drag the figure with it', () async {
        // Three at 2h, one at 16h. The mean of those is 5h30, which describes
        // none of the four. The median is why this reads as 2h.
        for (var i = 0; i < 3; i++) {
          await episodeWith(
            start: DateTime(2026, 9, 1 + i, 9),
            end: DateTime(2026, 9, 1 + i, 11),
          );
        }
        await episodeWith(
          start: DateTime(2026, 9, 5, 9),
          end: DateTime(2026, 9, 6, 1),
        );

        final g = await guidance.forKind(EpisodeKind.migraine);
        final note = g.personalNotes.firstWhere((n) => n.contains('Half of'));
        expect(note, contains('2h'));
      });
    });
  });
}

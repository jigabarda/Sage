import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/constants/symptoms.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/triage/red_flag.dart';
import 'package:sage/data/triage/triage_rules.dart';
import 'package:sage/data/triage/triage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tier 0 is the one part of Sage where being wrong cannot be undone by
/// editing a row later, so it is tested harder than anything else.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the rule set', () {
    test('every code is unique', () {
      final codes = TriageRules.all.map((f) => f.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('every flag can be shown to a user', () {
      for (final f in TriageRules.all) {
        expect(f.question.trim(), isNotEmpty, reason: f.code);
        expect(f.because.trim(), isNotEmpty, reason: f.code);
        expect(f.kinds, isNotEmpty, reason: f.code);
      }
    });

    test('both conditions have at least one emergency flag', () {
      for (final kind in EpisodeKind.values) {
        final emergencies = TriageRules.forKind(
          kind,
        ).where((f) => f.urgency == RedFlagUrgency.emergency);
        expect(emergencies, isNotEmpty, reason: kind.code);
      }
    });

    test('emergency flags are listed before urgent ones', () {
      for (final kind in EpisodeKind.values) {
        final list = TriageRules.forKind(kind);
        final firstUrgent = list.indexWhere(
          (f) => f.urgency == RedFlagUrgency.urgent,
        );
        if (firstUrgent == -1) continue;
        // Someone scanning this list while in pain reads the top of it, and
        // the entries where minutes matter have to be there.
        expect(
          list
              .skip(firstUrgent)
              .every((f) => f.urgency == RedFlagUrgency.urgent),
          isTrue,
          reason: 'an emergency flag sits below an urgent one for ${kind.code}',
        );
      }
    });

    test('reflux triage asks about the cardiac patterns first', () {
      // The specific thing this app must not get wrong: it is the app someone
      // opens when their chest burns, and a heart attack is what gets mistaken
      // for heartburn.
      final reflux = TriageRules.forKind(EpisodeKind.reflux);
      final codes = reflux.take(2).map((f) => f.code).toSet();
      expect(codes, containsAll(['cardiac_radiation', 'cardiac_associated']));
    });

    test('no red flag is also offered as an ordinary symptom', () {
      // A red flag is not a checkbox on a log. If a code appeared in both
      // places, ticking it in the editor would look like it had been reported
      // and acted on, when nothing would have happened.
      final flagCodes = TriageRules.all.map((f) => f.code).toSet();
      final symptomCodes = Symptoms.all.map((s) => s.code).toSet();
      expect(flagCodes.intersection(symptomCodes), isEmpty);
    });

    test('no flag mentions a drug or a dose', () {
      final dose = RegExp(r'\d+\s*(mg|ml|mcg|g)\b', caseSensitive: false);
      for (final f in TriageRules.all) {
        expect(dose.hasMatch(f.question), isFalse, reason: f.code);
        expect(dose.hasMatch(f.because), isFalse, reason: f.code);
      }
    });
  });

  group('evaluate', () {
    late Database db;
    late TriageService service;

    setUp(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: SageDatabase.openOptions(),
      );
      service = TriageService(db);
    });

    tearDown(() => db.close());

    test('nothing ticked is clear', () {
      final r = service.evaluate({});
      expect(r.isClear, isTrue);
      expect(r.urgency, isNull);
    });

    test('a single emergency flag escalates on its own', () {
      // No threshold, no scoring, no second opinion. One is enough.
      final r = service.evaluate({'thunderclap'});
      expect(r.isClear, isFalse);
      expect(r.matched.single.code, 'thunderclap');
      expect(r.urgency, RedFlagUrgency.emergency);
    });

    test('a single urgent flag escalates too, at the lower urgency', () {
      final r = service.evaluate({'weight_loss'});
      expect(r.isClear, isFalse);
      expect(r.urgency, RedFlagUrgency.urgent);
    });

    test('emergency wins when both are present', () {
      final r = service.evaluate({'weight_loss', 'vomiting_blood'});
      expect(r.urgency, RedFlagUrgency.emergency);
      expect(r.matched, hasLength(2));
      // Emergency first, so the screen leads with the thing that matters.
      expect(r.matched.first.urgency, RedFlagUrgency.emergency);
    });

    test('every single flag on its own is enough to escalate', () {
      // Exhaustive rather than sampled: a flag that quietly stopped firing
      // would be invisible in any other test.
      for (final f in TriageRules.all) {
        final r = service.evaluate({f.code});
        expect(r.isClear, isFalse, reason: '${f.code} did not escalate');
        expect(r.urgency, f.urgency, reason: f.code);
      }
    });

    test('an unknown code is ignored rather than treated as a match', () {
      // It can only come from a build that dropped a flag. Inventing an
      // escalation from a code nothing recognises is noise nobody can act on.
      expect(service.evaluate({'not_a_real_flag'}).isClear, isTrue);
      expect(
        service.evaluate({'not_a_real_flag', 'thunderclap'}).matched,
        hasLength(1),
      );
    });

    test('record writes a triage row that the export can find', () async {
      final r = service.evaluate({'thunderclap'});
      await service.record(r);

      final rows = await db.query('chat_messages');
      expect(rows, hasLength(1));
      expect(rows.single['tier'], 'triage');
      expect(rows.single['content'], contains('thunderclap'));
    });

    test('record writes nothing when the check was clear', () async {
      await service.record(service.evaluate({}));
      expect(await db.query('chat_messages'), isEmpty);
    });

    test('record links to an episode when there is one', () async {
      await db.insert('episodes', {
        'id': 'ep_1',
        'kind': 'migraine',
        'started_at': 0,
        'severity': 5,
        'notes': '',
        'started_day': 0,
        'created_at': 0,
        'updated_at': 0,
      });

      await service.record(
        service.evaluate({'thunderclap'}),
        episodeId: 'ep_1',
      );

      final rows = await db.query('chat_messages');
      expect(rows.single['episode_id'], 'ep_1');
    });
  });
}

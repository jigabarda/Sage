import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/core/brand_palette.dart';
import 'package:sage/core/sage_theme.dart';
import 'package:sage/data/db/sage_database.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/repositories/episode_repository.dart';
import 'package:sage/data/settings/cycle_tracking.dart';
import 'package:sage/features/backup/backup_screen.dart';
import 'package:sage/features/daily/daily_log_screen.dart';
import 'package:sage/features/export/export_screen.dart';
import 'package:sage/features/guidance/guidance_screen.dart';
import 'package:sage/features/history/history_screen.dart';
import 'package:sage/features/meds/meds_screen.dart';
import 'package:sage/features/patterns/patterns_screen.dart';
import 'package:sage/features/today/today_screen.dart';
import 'package:sage/features/triage/escalation_screen.dart';
import 'package:sage/features/triage/safety_check_screen.dart';
import 'package:sage/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders every screen on a small phone and at doubled text size, and fails
/// on any overflow.
///
/// ## Why doubled text is not an edge case here
///
/// Photophobia and visual aura are core migraine symptoms, and a large system
/// font is one of the first things people with them turn on. An app for
/// migraine that breaks at 2x text is broken for a meaningful share of the
/// people it is for — this is closer to a core requirement than an
/// accessibility nicety.
///
/// 320dp is the narrowest width Android still ships (small phones, and any
/// device in split-screen).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SharedPreferences prefs;

  setUp(() async {
    // Cycle tracking on, so the daily log renders its optional section too.
    // Off by default in the app, which would leave it untested here.
    SharedPreferences.setMockInitialValues({'track_cycle': true});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: SageDatabase.openOptions(),
    );

    // Enough content that lists, chips and cards actually render rather than
    // falling through to an empty state, which is the easy case.
    final repo = EpisodeRepository(db);
    for (var i = 1; i <= 4; i++) {
      final at = DateTime.now().subtract(Duration(days: i));
      await repo.create(
        kind: i.isEven ? EpisodeKind.migraine : EpisodeKind.reflux,
        startedAt: at,
        endedAt: at.add(const Duration(hours: 3)),
        severity: 7,
        notes: 'A note long enough to need wrapping on a narrow screen.',
        symptomCodes: const ['photophobia', 'nausea'],
        userTriggerCodes: const ['short_sleep'],
        relievers: [
          EpisodeReliever(relieverCode: 'dark_room', takenAt: at, helped: 1),
        ],
      );
    }
    await repo.startNow(EpisodeKind.migraine);
  });

  tearDown(() => db.close());

  Widget wrap(Widget child, {required double textScale}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        cycleTrackingProvider.overrideWith(
          (ref) => CycleTrackingController(prefs),
        ),
      ],
      child: MaterialApp(
        theme: buildSageTheme(Brightness.light, BrandPalette.olive),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    );
  }

  final screens = <String, Widget>{
    'Today': const TodayScreen(),
    'History': const HistoryScreen(),
    'Patterns': const PatternsScreen(),
    'Daily log': const DailyLogScreen(),
    'Safety check (migraine)': const SafetyCheckScreen(
      kind: EpisodeKind.migraine,
    ),
    'Safety check (reflux)': const SafetyCheckScreen(kind: EpisodeKind.reflux),
    'Escalation (emergency)': const EscalationScreen(flagCode: 'thunderclap'),
    'Escalation (urgent)': const EscalationScreen(flagCode: 'weight_loss'),
    'Guidance': const GuidanceScreen(kind: EpisodeKind.migraine),
    'Export': const ExportScreen(),
    'Backup': const BackupScreen(),
    'Medications': const MedsScreen(),
  };

  // 320x640 is the narrowest Android still ships. 2.0 is the top of the
  // usual system font range.
  for (final size in const [Size(320, 640), Size(360, 800)]) {
    for (final scale in const [1.0, 1.5, 2.0]) {
      for (final entry in screens.entries) {
        testWidgets(
          '${entry.key} fits at ${size.width.toInt()}dp, ${scale}x text',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(wrap(entry.value, textScale: scale));
            // Two pumps: the first frame is the loading state for every screen
            // that reads the database.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));

            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${entry.key} overflowed at ${size.width.toInt()}dp / '
                  '${scale}x',
            );
          },
        );
      }
    }
  }
}

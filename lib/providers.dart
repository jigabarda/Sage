import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'constants/episode_kind.dart';
import 'data/models/episode.dart';
import 'core/dates.dart';
import 'data/guidance/guidance.dart';
import 'data/guidance/guidance_service.dart';
import 'data/insights/insight.dart';
import 'data/insights/insights_service.dart';
import 'data/models/daily_log.dart';
import 'data/repositories/daily_log_repository.dart';
import 'data/repositories/episode_repository.dart';
import 'data/triage/triage_service.dart';

/// Both are opened once in `main.dart` and injected as overrides, so no screen
/// ever awaits a database handle mid-build. A provider that throws until
/// overridden fails loudly at startup rather than silently handing out a
/// second connection later.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  ),
);

final databaseProvider = Provider<Database>(
  (ref) =>
      throw StateError('databaseProvider must be overridden in ProviderScope'),
);

final episodeRepositoryProvider = Provider<EpisodeRepository>(
  (ref) => EpisodeRepository(ref.watch(databaseProvider)),
);

/// Newest first, for the history list.
final recentEpisodesProvider = FutureProvider<List<Episode>>(
  (ref) => ref.watch(episodeRepositoryProvider).recent(),
);

/// Anything still open. Usually empty or one; a migraine and reflux can
/// legitimately overlap, so this is a list.
final ongoingEpisodesProvider = FutureProvider<List<Episode>>(
  (ref) => ref.watch(episodeRepositoryProvider).ongoing(),
);

final episodeDetailProvider = FutureProvider.family<EpisodeDetail?, String>((
  ref,
  id,
) {
  return ref.watch(episodeRepositoryProvider).detailById(id);
});

/// The last reliever this person rated as helping, for one condition.
///
/// One remembered fact, not a pattern. See `lastThingThatHelped`.
final lastHelpedProvider = FutureProvider.family<String?, EpisodeKind>((
  ref,
  kind,
) {
  return ref.watch(episodeRepositoryProvider).lastThingThatHelped(kind);
});

/// Call after any write so the affected screens refresh.
///
/// Centralised because forgetting one of these is how a list ends up showing
/// an episode the user just deleted. Every write path in the app goes through
/// here rather than invalidating providers ad hoc.
void invalidateEpisodeData(WidgetRef ref) {
  ref.invalidate(recentEpisodesProvider);
  ref.invalidate(ongoingEpisodesProvider);
  ref.invalidate(lastHelpedProvider);
  ref.invalidate(episodeDetailProvider);
  // Guidance reads reliever ratings and closed-episode durations, so a
  // write can change what its gates allow it to say.
  ref.invalidate(guidanceProvider);
  // Every correlation rule counts episodes, so any episode write can
  // change which gates pass.
  ref.invalidate(insightsProvider);
  ref.invalidate(insightsProgressProvider);
}

/// Tier 0. Held as a plain provider because `evaluate` is pure and synchronous
/// — nothing about the triage decision may depend on I/O that could fail.
final triageServiceProvider = Provider<TriageService>(
  (ref) => TriageService(ref.watch(databaseProvider)),
);

final guidanceServiceProvider = Provider<GuidanceService>(
  (ref) => GuidanceService(ref.watch(databaseProvider)),
);

/// Tier 1 for one condition: fixed steps plus any personal note that clears
/// its evidence gate.
final guidanceProvider = FutureProvider.family<Guidance, EpisodeKind>((
  ref,
  kind,
) {
  return ref.watch(guidanceServiceProvider).forKind(kind);
});

final dailyLogRepositoryProvider = Provider<DailyLogRepository>(
  (ref) => DailyLogRepository(ref.watch(databaseProvider)),
);

final dailyLogForDayProvider = FutureProvider.family<DailyLog, LocalDay>((
  ref,
  day,
) {
  return ref.watch(dailyLogRepositoryProvider).forDay(day);
});

final insightsServiceProvider = Provider<InsightsService>(
  (ref) => InsightsService(ref.watch(databaseProvider)),
);

/// Tier 2. Findings that cleared their evidence gates, strongest first.
final insightsProvider = FutureProvider<List<Insight>>(
  (ref) => ref.watch(insightsServiceProvider).all(),
);

/// What is still missing, for the empty state. An empty patterns screen with
/// no explanation reads as broken.
final insightsProgressProvider = FutureProvider<String>(
  (ref) => ref.watch(insightsServiceProvider).progressNote(),
);

/// Call after writing a daily log.
///
/// Insights read both tables, so an episode write refreshes them too — see
/// [invalidateEpisodeData].
void invalidateDailyData(WidgetRef ref) {
  ref.invalidate(dailyLogForDayProvider);
  ref.invalidate(insightsProvider);
  ref.invalidate(insightsProgressProvider);
}

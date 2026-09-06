import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'constants/episode_kind.dart';
import 'data/models/episode.dart';
import 'data/repositories/episode_repository.dart';

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
}
